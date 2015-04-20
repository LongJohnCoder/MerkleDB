-module(basic_db_storage).

-include("basic_db.hrl").
-include_lib("rkvs/include/rkvs.hrl").

-export([   open/1,
            open/2,
            close/1,
            destroy/1,
            get/2,
            put/3,
            delete/2,
            write_batch/2,
            fold/3,
            fold_keys/3,
            is_empty/1,
            drop/1
         ]).

-type storage() :: #engine{}.

-export_type([storage/0]).


%% @doc open a storage, and by default use levelDB as backend.
-spec open(list()) -> {ok, storage()} | {error, any()}.
open(Name) ->
    open(Name, [{backend, rkvs_leveldb}]).

%% @doc open a storage, and pass options to the backend.
-spec open(list(), list()) -> {ok, storage()} | {error, any()}.
open(Name, [{backend, ets}]) ->
    rkvs:open(Name, [{backend, rkvs_ets}]);
open(Name, [{backend, leveldb}]) ->
    try_open_level_db(Name, 5, undefined).

try_open_level_db(_Name, 0, LastError) ->
    {error, LastError};
try_open_level_db(Name, RetriesLeft, _) ->
    case rkvs:open(Name, [{backend, rkvs_leveldb}]) of
        {ok, Engine} ->
            {ok, Engine};
        %% Check specifically for lock error, this can be caused if
        %% a crashed vnode takes some time to flush leveldb information
        %% out to disk.  The process is gone, but the NIF resource cleanup
        %% may not have completed.
        {error, {db_open, OpenErr}=Reason} ->
            case lists:prefix("IO error: lock ", OpenErr) of
                true ->
                    SleepFor = 2000,
                    lager:warning("Leveldb Open backend retrying ~p in ~p ms after error ~s\n",
                                [Name, SleepFor, OpenErr]),
                    timer:sleep(SleepFor),
                    try_open_level_db(Name, RetriesLeft - 1, Reason);
                false ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc close a storage
-spec close(storage()) -> ok | {error, any()}.
close(Engine) ->
    case Engine#engine.ref of
        undefined ->
            ok;
        <<>> ->
            ok;
        _ ->
            rkvs:close(Engine)
    end.

%% @doc close a storage and remove all the data
-spec destroy(storage()) -> ok | {error, any()}.
destroy(Engine) ->
    rkvs:destroy(Engine).

%% @doc get the value associated to the key
-spec get(storage(), key()) -> any() | {error, term()}.
get(Engine, Key) ->
    BKey = basic_db_utils:encode_kv(Key),
    rkvs:get(Engine, BKey).

%% @doc store the value associated to the key.
-spec put(storage(), key(), value()) -> ok | {error, term()}.
put(Engine, Key, Value) ->
    BKey = basic_db_utils:encode_kv(Key),
    rkvs:put(Engine, BKey, Value).

%% @doc delete the value associated to the key
-spec delete(storage(), key()) -> ok | {error, term()}.
delete(Engine, Key) ->
    BKey = basic_db_utils:encode_kv(Key),
    rkvs:clear(Engine, BKey).

%% @doc do multiple operations on the backend.
-spec write_batch(storage(), multi_ops()) -> ok | {error, term()}.
write_batch(Engine, Ops) ->
    rkvs:write_batch(Engine, Ops).

%% @doc fold all keys with a function
-spec fold_keys(storage(), fun(), any()) -> any() | {error, term()}.
fold_keys(Engine, Fun, Acc0) ->
    rkvs:fold_keys(Engine, Fun, Acc0, []).

%% @doc fold all K/Vs with a function
-spec fold(storage(), function(), any()) -> any() | {error, term()}.
fold(Engine, Fun, Acc0) ->
    rkvs:fold(Engine, Fun, Acc0, []).

%% @doc Returns true if this backend has no values; otherwise returns false.
-spec is_empty(storage()) -> boolean() | {error, term()}.
is_empty(Engine) ->
    rkvs:is_empty(Engine).


%% @doc Delete all objects from this backend
%% and return a fresh reference.
-spec drop(storage()) -> {ok, storage()} | {error, term(), storage()}.
drop(Engine) ->
    drop(Engine, 2, undefined).

drop(Engine, 0, LastError) ->
    % os:cmd("rm -rf " ++ Engine#engine.name),
    {error, LastError, Engine};
drop(Engine, RetriesLeft, _) ->
    close(Engine),
    case rkvs:destroy(Engine) of
        ok ->
            % {ok, Engine#engine{ref = undefined}};
            {ok, Engine};
        %% Check specifically for lock error, this can be caused if
        %% a crashed vnode takes some time to flush leveldb information
        %% out to disk.  The process is gone, but the NIF resource cleanup
        %% may not have completed.
        {error, {error_db_destroy, DestroyErr}=Reason} ->
            case lists:prefix("IO error: lock ", DestroyErr) of
                true ->
                    SleepFor = 2000,
                    lager:warning("Leveldb destroy backend retrying ~p in ~p ms after error ~s\n",
                                [Engine#engine.name, SleepFor, DestroyErr]),
                    timer:sleep(SleepFor),
                    drop(Engine, RetriesLeft - 1, Reason);
                false ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason, Engine}
    end.
