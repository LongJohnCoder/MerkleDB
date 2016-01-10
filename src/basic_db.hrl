
-define(PRINT(Var), io:format("DEBUG: ~p:~p - ~p~n~n ~p~n~n", [?MODULE, ?LINE, ??Var, Var])).

-define(DEFAULT_TIMEOUT, 10000).
-define(REPLICATION_FACTOR, 3).
% -define(R, 2).
% -define(W, 2).
-define(DEFAULT_BUCKET, <<"b">>).
-define(DELETE_OP, delete_op).
-define(WRITE_OP, write_op).
-define(DEFAULT_NO_REPLY, true). % true if we don't care about Acks in FSMs

%% Options for AAE.
-define(DEFAULT_SYNC_INTERVAL, 2000).
-define(DEFAULT_HASHTREE_TOKENS, 90).
-define(MTREE_CHILDREN, 10). % (MTREE_CHILDREN ^ 2) leafs
-define(DEFAULT_NODE_KILL_RATE, 0). % kill a vnode every x milliseconds; 0 = disabled

%% Options for read requests.
-define(OPT_DO_RR, do_read_repair).
-define(OPT_READ_MIN_ACKS, read_acks).
-define(OPT_REPAIR, repair_key).

%% Options for put/delete requests.
-define(OPT_PUT_REPLICAS, put_replicas).
-define(OPT_PUT_MIN_ACKS, put_acks).
-define(REPLICATION_FAIL_RATIO, repl_fail_ratio).
-define(DEFAULT_REPLICATION_FAIL_RATIO, 0). % ratio of "lost" replicated put/deletes

%% Options for vnodes
-define(REPORT_TICK_INTERVAL, 2500). % (ms) interval between report stats
-define(MAX_KEYS_SENT_RECOVERING, 1000). % max sent at a time to a restarting node.

-define(STATS_FLUSH_INTERVAL, 10). % (sec) interval between flushing data to disk
-define(DEFAULT_DO_STATS, true). % bool that says if a vnode should collect and report stats

-define(ETS_CACHE_REPLICA_NODES, ets_cache_replica_nodes).
-define(OPT_TIMEOUT, opt_timeout).

-type bucket()     :: term().
-type key()        :: term().
-type bkey()       :: {bucket(), key()}.

% index in the consistent hashing ring
-type index()      :: non_neg_integer().
% element of the consistent hashing ring
-type index_node() :: {index(), node()}.
-type vnode_id()   :: {index(), pos_integer()}.

-type keylog()     :: {counter(), [key()]}.

-type multi_ops()  :: [{put, key(), value()}
                       |{delete, key()}].

-type id()         :: term().
-type counter()    :: non_neg_integer().
-type value()      :: any().
