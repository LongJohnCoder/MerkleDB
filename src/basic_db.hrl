
-define(PRINT(Var), io:format("DEBUG: ~p:~p - ~p~n~n ~p~n~n", [?MODULE, ?LINE, ??Var, Var])).

-define(DEFAULT_TIMEOUT, 20000).
-define(REPLICATION_FACTOR, 3).
% -define(R, 2).
% -define(W, 2).
-define(DEFAULT_BUCKET, <<"default_bucket">>).
-define(DELETE_OP, delete_op).
-define(WRITE_OP, write_op).

%% Options for AAE.
-define(DEFAULT_HASHTREE_TOKENS, 90).
-define(TICK, 2000).
-define(MTREE_CHILDREN, 6). % (MTREE_CHILDREN ^ 2) leafs

%% Options for read requests.
-define(OPT_DO_RR, do_read_repair).
-define(OPT_READ_MIN_ACKS, read_acks).
-define(OPT_REPAIR, repair_key).

%% Options for put/delete requests.
-define(OPT_PUT_REPLICAS, put_replicas).
-define(OPT_PUT_MIN_ACKS, put_acks).
-define(ALL_REPLICAS_WRITE_RATIO, 0.9). % 85% of put/deletes go to all replica nodes

-define(OPT_TIMEOUT, opt_timeout).

-type bucket()     :: term().
-type key()        :: term().
-type bkey()       :: {bucket(), key()}.

% index in the consistent hashing ring
-type index()      :: non_neg_integer().
% element of the consistent hashing ring
-type index_node() :: {index(), node()}.

-type keylog()     :: {counter(), [key()]}.

-type multi_ops()  :: [{put, key(), value()}
                       |{delete, key(), value()}].

-type id()         :: term().
-type counter()    :: non_neg_integer().
-type value()      :: any().
