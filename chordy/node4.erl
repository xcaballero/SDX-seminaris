-module(node4).
-export([start/1, start/2]).

-define(Stabilize, 1000).
-define(Timeout, 5000).

start(MyKey) ->
    start(MyKey, nil).

start(MyKey, PeerPid) ->
    timer:start(),
    spawn(fun() -> init(MyKey, PeerPid) end).

init(MyKey, PeerPid) ->
    Predecessor = nil,
    {ok, Successor} = connect(MyKey, PeerPid),
    schedule_stabilize(),    
    node(MyKey, Predecessor, Successor, nil, storage:create(), storage:create()).

connect(MyKey, nil) ->
    {ok, {MyKey, nil, self()}};
connect(_, PeerPid) ->
    Qref = make_ref(),
    PeerPid ! {key, Qref, self()},
    receive
        {Qref, Skey} ->
            Sref = monit(PeerPid),
            {ok, {Skey, Sref, PeerPid}}
    after ?Timeout ->
        io:format("Timeout: no response from ~w~n", [PeerPid])
    end.

schedule_stabilize() ->
    timer:send_interval(?Stabilize, self(), stabilize).

node(MyKey, Predecessor, Successor, Next, Store, Replica) ->
    receive 
        {key, Qref, Peer} ->
            Peer ! {Qref, MyKey},
            node(MyKey, Predecessor, Successor, Next, Store, Replica);
        {notify, NewPeer} ->
            {NewPredecessor, NewStore} = notify(NewPeer, MyKey, Predecessor, Store),
             {_, _, Spid} = Successor,
            Spid ! {pushreplica, NewStore},
            node(MyKey, NewPredecessor, Successor, Next, NewStore, Replica);
        {request, Peer} ->
            request(Peer, Predecessor, Successor),
            node(MyKey, Predecessor, Successor, Next, Store, Replica);
        {status, Pred, Nx} ->
            {NewSuccessor, NewNext} = stabilize(Pred, Nx, MyKey, Successor),
            node(MyKey, Predecessor, NewSuccessor, NewNext, Store, Replica);
        stabilize ->
            stabilize(Successor),
            node(MyKey, Predecessor, Successor, Next, Store, Replica);
        stop ->
            ok;
        probe ->
            create_probe(MyKey, Successor, Store, Replica),
            node(MyKey, Predecessor, Successor, Next, Store, Replica);
        {probe, MyKey, Nodes, T} ->
            remove_probe(MyKey, Nodes, T),
            node(MyKey, Predecessor, Successor, Next, Store, Replica);
        {probe, RefKey, Nodes, T} ->
            forward_probe(MyKey, RefKey, [MyKey|Nodes], T, Successor, Store, Replica),
            node(MyKey, Predecessor, Successor, Next, Store, Replica);
        {add, Key, Value, Qref, Client} ->
            Added = add(Key, Value, Qref, Client,
                        MyKey, Predecessor, Successor, Store),
            node(MyKey, Predecessor, Successor, Next, Added, Replica);
        {lookup, Key, Qref, Client} ->
            lookup(Key, Qref, Client, MyKey, Predecessor, Successor, Store),
            node(MyKey, Predecessor, Successor, Next, Store, Replica);
        {handover, Elements} ->
            Merged = storage:merge(Store, Elements),
            {_, _, Spid} = Successor,
            Spid ! {pushreplica, Merged},
            node(MyKey, Predecessor, Successor, Next, Merged, Replica);
        {'DOWN', Ref, process, _, _} ->
            {NewPred, NewSucc, NewNext, NewStore, NewReplica} = down(Ref, Predecessor, Successor, Next, Store, Replica),
            node(MyKey, NewPred, NewSucc, NewNext, NewStore, NewReplica);
        {replicate, Key, Value, Client, Qref} ->
            Added = storage:add(Key, Value, Replica),
            Client ! {Qref, ok},
            node(MyKey, Predecessor, Successor, Next, Store, Added);
        {pushreplica, NewReplica} ->
            node(MyKey, Predecessor, Successor, Next, Store, NewReplica)
   end.

stabilize(Pred, Nx, MyKey, Successor) ->
  {Skey, Sref, Spid} = Successor,
  case Pred of
      nil ->
          Spid ! {notify, {MyKey, self()}},
          {Successor, Nx};
      {MyKey, _} ->
          {Successor, Nx};
      {Skey, _} ->
          Spid ! {notify, {MyKey, self()}},
          {Successor, Nx};
      {Xkey, Xpid} ->
            case key:between(Xkey, MyKey, Skey) of
                true ->
                    demonit(Sref),
                    Xref = monit(Xpid),
                    self() ! stabilize,
                    {{Xkey, Xref, Xpid}, {Skey, Spid}};
                false ->
                    Spid ! {notify, {MyKey, self()}},
                    {Successor, Nx}
            end
    end.

stabilize({_, _, Spid}) ->
    Spid ! {request, self()}.

request(Peer, Predecessor, {Skey, _, Spid}) ->
    case Predecessor of
        nil ->
            Peer ! {status, nil, {Skey, Spid}};
        {Pkey, _, Ppid} ->
            Peer ! {status, {Pkey, Ppid}, {Skey, Spid}}
    end.

notify({Nkey, Npid}, MyKey, Predecessor, Store) ->
    case Predecessor of
        nil ->
            Nref = monit(Npid),
            Keep = handover(Store, MyKey, Nkey, Npid),
            {{Nkey, Nref, Npid}, Keep};
        {Pkey, Pref, _} ->
            case key:between(Nkey, Pkey, MyKey) of
                true ->
                    demonit(Pref),
                    Nref = monit(Npid),
                    Keep = handover(Store, MyKey, Nkey, Npid),
                    {{Nkey, Nref, Npid}, Keep};
                false -> 
                    {Predecessor, Store}
            end
    end.

create_probe(MyKey, {_, _, Spid}, Store, Replica) ->
    Spid ! {probe, MyKey, [MyKey], erlang:monotonic_time()},
    io:format("Node ~w created probe, Store: ~w, Replica ~w~n", [MyKey, Store, Replica]).
    
remove_probe(MyKey, Nodes, T) ->
    T2 = erlang:monotonic_time(),
    Time = erlang:convert_time_unit(T2-T, native, microsecond),
    io:format("Node ~w received probe after ~w us -> Ring: ~w~n", [MyKey, Time, Nodes]).

forward_probe(MyKey, RefKey, Nodes, T, {_, _, Spid}, Store, Replica) ->
    Spid ! {probe, RefKey, Nodes, T},
    io:format("Node ~w forwarded probe started by node ~w, Store: ~w, Replica: ~w~n", [MyKey, RefKey, Store, Replica]).

add(Key, Value, Qref, Client, _, nil, {_, _,Spid}, Store) ->
    Spid ! {add, Key, Value, Qref, Client},
    Store;
add(Key, Value, Qref, Client, MyKey, {Pkey,_, _}, {_, _,Spid}, Store) ->
    case key:between(Key , Pkey , MyKey) of 
        true ->
            Added = storage:add(Key, Value, Store), 
            Spid ! {replicate, Key, Value,  Client, Qref},
            Added;
        false ->
            Spid ! {add, Key, Value, Qref, Client},
            Store
    end.
    
lookup(Key, Qref, Client, _, nil, {_, _, Spid}, _) ->
    Spid ! {lookup, Key, Qref, Client};
lookup(Key, Qref, Client, MyKey, {Pkey, _, _}, {_, _, Spid}, Store) ->
    case key:between(Key, Pkey , MyKey) of
        true ->
        Result = storage:lookup(Key, Store),
        Client ! {Qref, Result};
    false ->
        Spid ! {lookup, Key, Qref, Client}
    end.

handover(Store, MyKey, Nkey, Npid) ->
    {Keep, Leave} = storage:split(MyKey, Nkey, Store),
    Npid ! {handover, Leave},
    Keep.

monit(Pid) ->
    erlang:monitor(process, Pid).

demonit(nil) ->
    ok;
demonit(MonitorRef) ->
    erlang:demonitor(MonitorRef, [flush]).

down(Ref, {_, Ref, _}, Successor, Next, Store, Replica) ->
    NewStore = storage:merge(Store, Replica),
    {_, _, Spid} = Successor,
    Spid ! {pushreplica, NewStore},
    {nil, Successor, Next, NewStore, storage:create()};
down(Ref, Predecessor, {_, Ref, _}, {Nkey, Npid}, Store, Replica) ->
    Nref = monit(Npid),
    self() ! stabilize,
    {Predecessor, {Nkey, Nref, Npid}, nil, Store, Replica}.
    
