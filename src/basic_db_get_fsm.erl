%% @doc The coordinator for stat get operations.  The key here is to
%% generate the preflist just like in wrtie_fsm and then query each
%% replica and wait until a quorum is met.
-module(basic_db_get_fsm).
-behavior(gen_fsm).
-include("basic_db.hrl").

%% API
-export([start_link/4]).

%% Callbacks
-export([init/1, code_change/4, handle_event/3, handle_info/3,
         handle_sync_event/4, terminate/3]).

%% States
-export([execute/2, waiting/2, waiting2/2, finalize/2]).

-record(state, {
    %% Unique request ID.
    req_id      :: pos_integer(),
    %% Pid from the caller process.
    from        :: pid(),
    %% The key to read.
    key         :: bkey(),
    %% The replica nodes for the key.
    replicas    :: riak_core_apl:preflist2(),
    %% Minimum number of acks from replica nodes.
    min_acks    :: non_neg_integer(),
    %% Maximum number of acks from replica nodes.
    max_acks    :: non_neg_integer(),
    %% Do read repair on outdated replica nodes.
    do_rr       :: boolean(),
    %% Return the final value or not
    return_val  :: boolean(),
    %% The current Object to return.
    replies     :: [{index_node(), basic_db_object:object()}],
    %% The timeout value for this request.
    timeout     :: non_neg_integer()
}).

%%%===================================================================
%%% API
%%%===================================================================

start_link(ReqID, From, BKey, Options) ->
    gen_fsm:start_link(?MODULE, [ReqID, From, BKey, Options], []).

%%%===================================================================
%%% States
%%%===================================================================

%% Initialize state data.
init([ReqId, From, BKey, Options]) ->
    case proplists:get_value(?OPT_REPAIR, Options) of
        %% This is a normal read request
        undefined ->
            Replicas    = basic_db_utils:replica_nodes(BKey),
            MinAcks     = proplists:get_value(?OPT_READ_MIN_ACKS, Options),
            MaxAcks     = ?REPLICATION_FACTOR,
            ReadRepair  = proplists:get_value(?OPT_DO_RR, Options),
            ReturnValue = true;
        %% This is a key repair request between two nodes
        {Node1, Node2} ->
            Replicas    = [Node1, Node2],
            MinAcks     = 2,
            MaxAcks     = 2,
            ReadRepair  = true,
            ReturnValue = false
    end,
    true = MaxAcks >= MinAcks, % sanity check
    State = #state{ req_id      = ReqId,
                    from        = From,
                    key         = BKey,
                    replicas    = Replicas,
                    min_acks    = MinAcks,
                    max_acks    = MaxAcks,
                    do_rr       = ReadRepair,
                    replies     = [],
                    return_val  = ReturnValue,
                    timeout     = proplists:get_value(?OPT_TIMEOUT, Options, ?DEFAULT_TIMEOUT)
    },
    {ok, execute, State, 0}.

%% @doc Execute the get reqs.
execute(timeout, State=#state{  req_id      = ReqId,
                                key         = BKey,
                                replicas    = ReplicaNodes}) ->
    % request this key from nodes that store it (ReplicaNodes)
    basic_db_vnode:read(ReplicaNodes, ReqId, BKey),
    {next_state, waiting, State}.

%% @doc Wait for W-1 write acks. Timeout is 5 seconds by default (see basic_db.hrl).
waiting(timeout, State=#state{  req_id      = ReqID,
                                from        = From}) ->
    lager:warning("GET_FSM timeout in waiting state."),
    From ! {ReqID, timeout},
    {stop, timeout, State};

waiting({ok, ReqID, IndexNode, Response}, State=#state{
                                                req_id      = ReqID,
                                                from        = From,
                                                replies     = Replies,
                                                return_val  = ReturnValue,
                                                min_acks    = Min,
                                                max_acks    = Max}) ->
    %% Add the new response to Replies. If it's a not_found or an error, add an
    %% empty Object.
    Replies2 =  case Response of
                    {ok, Object}   -> [{IndexNode, Object} | Replies];
                    _           -> [{IndexNode, basic_db_object:new()} | Replies]
                end,
    NewState = State#state{replies = Replies2},
    % test if we have enough responses to respond to the client
    case length(Replies2) >= Min of
        true -> % we already have enough responses to acknowledge back to the client
            create_client_reply(From, ReqID, Replies2, ReturnValue),
            case length(Replies2) >= Max of
                true -> % we got the maximum number of replies sent
                    {next_state, finalize, NewState, 0};
                false -> % wait for all replica nodes
                    {next_state, waiting2, NewState}
            end;
        false -> % we still miss some responses to respond to the client
            {next_state, waiting, NewState}
    end.

waiting2(timeout, State) ->
    {next_state, finalize, State, 0};
waiting2({ok, ReqID, IndexNode, Response}, State=#state{
                                                req_id      = ReqID,
                                                max_acks    = Max,
                                                replies     = Replies}) ->
    %% Add the new response to Replies. If it's a not_found or an error, add an
    %% empty Object.
    Replies2 =  case Response of
                    {ok, Object}   -> [{IndexNode, Object} | Replies];
                    _           -> [{IndexNode, basic_db_object:new()} | Replies]
                end,
    NewState = State#state{replies = Replies2},
    case length(Replies2) >= Max of
        true -> % we got the maximum number of replies sent
            {next_state, finalize, NewState, 0};
        false -> % wait for all replica nodes
            {next_state, waiting2, NewState}
    end.

finalize(timeout, State=#state{ do_rr       = false}) ->
    lager:debug("GET_FSM: read repair OFF"),
    {stop, normal, State};
finalize(timeout, State=#state{ do_rr       = true,
                                key         = BKey,
                                max_acks    = Max,
                                replies     = Replies}) ->
    read_repair(BKey, Replies, Max == ?REPLICATION_FACTOR),
    {stop, normal, State}.


handle_info(_Info, _StateName, StateData) ->
    {stop,badmsg,StateData}.

handle_event(_Event, _StateName, StateData) ->
    {stop,badmsg,StateData}.

handle_sync_event(_Event, _From, _StateName, StateData) ->
    {stop,badmsg,StateData}.

code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

terminate(_Reason, _SN, _State) ->
    ok.


%%%===================================================================
%%% Internal Functions
%%%===================================================================

-spec read_repair(bkey(), [{index_node(), basic_db_object:object()}], boolean()) -> ok.
read_repair(BKey, Replies, AAE_Repair) ->
    %% Compute the final Object.
    FinalObject = final_object_from_replies(Replies),
    %% Computed what replica nodes have an outdated version of this key.
    OutdatedNodes = [IN || {IN,Object} <- Replies, basic_db_object:less(Object, FinalObject)],
    %% Maybe update the false positive stats for AAE.
    case AAE_Repair of
        false ->
            % length(OutdatedNodes)=/=0 andalso
            %     lager:info("GET_FSM: AAE REPAIR for ~p nodes, ~p~n", [length(Replies),length(OutdatedNodes)]),
            % lager:info("FinalObject: ~p~n", [FinalObject]),
            % lager:info("Replies: ~p~n", [Replies]),
            PayloadSize = byte_size(term_to_binary(basic_db_object:get_values(FinalObject))),
            MetaSize = byte_size(term_to_binary(basic_db_object:get_context(FinalObject))),
            [rpc:cast(Node, basic_db_entropy_info, key_repair_complete,
                        [Index, length(OutdatedNodes), {PayloadSize,MetaSize}]) ||
                            {{Index, Node},_} <- Replies];
        true ->
            lager:info("GET_FSM: read repair ON"),
            ok
    end,
    %% Repair the outdated keys.
    basic_db_vnode:repair(OutdatedNodes, BKey, FinalObject),
    ok.

-spec final_object_from_replies([{index_node(), basic_db_object:object()}]) ->
    basic_db_object:object().
final_object_from_replies(Replies) ->
    Object = [Object || {_,Object} <- Replies],
    basic_db_object:sync(Object).

create_client_reply(From, ReqID, _Replies, _ReturnValue = false) ->
    From ! {ReqID, ok, get, ?OPT_REPAIR};
create_client_reply(From, ReqID, Replies, _ReturnValue = true) ->
    FinalObject = final_object_from_replies(Replies),
    case basic_db_object:get_values(FinalObject) == [] of
        true -> % no response found; return the context for possibly future writes
            From ! {ReqID, not_found, get, basic_db_object:get_context(FinalObject)};
        false -> % there is at least on value for this key
            From ! {ReqID, ok, get, {basic_db_object:get_values(FinalObject),
                                     basic_db_object:get_context(FinalObject)}}
    end.
