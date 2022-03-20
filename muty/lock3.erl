-module(lock3).
-export([start/1]).

start(MyId) ->
    spawn(fun() -> init(MyId) end).

init(MyId) ->
    receive
        {peers, Nodes} ->
            open(Nodes, MyId, 0);
        stop ->
            ok
    end.

open(Nodes, MyId, MyClock) ->
    receive
        {take, Master, Ref} ->
            IncMyClock = MyClock + 1,
            Refs = requests(Nodes, MyId, IncMyClock),
            wait(Nodes, Master, Refs, [], Ref, MyId, IncMyClock, IncMyClock);
        {request, From,  Ref, _, ReceivedTimestamp} ->
            NewClock = max(ReceivedTimestamp, MyClock),
            From ! {ok, Ref},
            open(Nodes, MyId, NewClock);
        stop ->
            ok
    end.

requests(Nodes, MyId, Timestamp) ->
    lists:map(
      fun(P) -> 
        R = make_ref(), 
        P ! {request, self(), R, MyId, Timestamp}, 
        R 
      end, 
      Nodes).

wait(Nodes, Master, [], Waiting, TakeRef, MyId, _, Timestamp) ->
    Master ! {taken, TakeRef},
    held(Nodes, Waiting, MyId, Timestamp);
wait(Nodes, Master, Refs, Waiting, TakeRef, MyId, MyClock, Timestamp) ->
    receive
        {request, From, Ref, Id, ReceivedTimestamp} ->
            NewTimestamp = max(ReceivedTimestamp, Timestamp),
            if
                ReceivedTimestamp < MyClock ->
                    From ! {ok, Ref},
                    wait(Nodes, Master, Refs, Waiting, TakeRef, MyId, MyClock, NewTimestamp);
                ReceivedTimestamp > MyClock ->
                    wait(Nodes, Master, Refs, [{From, Ref}|Waiting], TakeRef, MyId, MyClock, NewTimestamp);
                ReceivedTimestamp == MyClock ->
                    if
                        Id < MyId -> 
                            From ! {ok, Ref},
                            wait(Nodes, Master, Refs, Waiting, TakeRef, MyId, MyClock, NewTimestamp);
                        Id >= MyId -> 
                            wait(Nodes, Master, Refs, [{From, Ref}|Waiting], TakeRef, MyId, MyClock, NewTimestamp)
                    end
            end;
        {ok, Ref} ->
            NewRefs = lists:delete(Ref, Refs),
            wait(Nodes, Master, NewRefs, Waiting, TakeRef, MyId, MyClock, Timestamp);
        release ->
            ok(Waiting),            
            open(Nodes, MyId, Timestamp)
    end.

ok(Waiting) ->
    lists:foreach(
      fun({F,R}) -> 
        F ! {ok, R} 
      end, 
      Waiting).

held(Nodes, Waiting, MyId, Timestamp) ->
    receive
        {request, From, Ref, _, ReceivedTimestamp} ->
            NewTimestamp = max(ReceivedTimestamp, Timestamp),
            held(Nodes, [{From, Ref}|Waiting], MyId, NewTimestamp);
        release ->
            ok(Waiting),
            open(Nodes, MyId, Timestamp)
    end.
