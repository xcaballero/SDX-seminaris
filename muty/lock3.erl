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

open(Nodes, MyId, Timestamp) ->
    receive
        {take, Master, Ref} ->
            NewTimestamp = Timestamp + 1,
            Refs = requests(Nodes, MyId, NewTimestamp),
            wait(Nodes, Master, Refs, [], Ref, MyId, NewTimestamp);
        {request, From,  Ref, _, ReceivedTimestamp} ->
            NewTimestamp = max(ReceivedTimestamp, Timestamp),
            From ! {ok, Ref},
            open(Nodes, MyId, NewTimestamp);
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

wait(Nodes, Master, [], Waiting, TakeRef, MyId, Timestamp) ->
    Master ! {taken, TakeRef},
    held(Nodes, Waiting, MyId, Timestamp);
wait(Nodes, Master, Refs, Waiting, TakeRef, MyId, Timestamp) ->
    receive
        {request, From, Ref, Id, ReceivedTimestamp} ->
            if
                ReceivedTimestamp < Timestamp ->
                    From ! {ok, Ref},
                    wait(Nodes, Master, Refs, Waiting, TakeRef, MyId, Timestamp);
                ReceivedTimestamp > Timestamp ->
                    wait(Nodes, Master, Refs, [{From, Ref}|Waiting], TakeRef, MyId, ReceivedTimestamp);
                ReceivedTimestamp == Timestamp ->
                    if
                        Id < MyId -> 
                            From ! {ok, Ref},
                            NewRef = make_ref(),
                            NewTimestamp = Timestamp + 1,
                            From ! {request, self(), NewRef, MyId, NewTimestamp},
                            wait(Nodes, Master, [NewRef|Refs], Waiting, TakeRef, MyId, NewTimestamp);
                        Id >= MyId -> 
                            wait(Nodes, Master, Refs, [{From, Ref}|Waiting], TakeRef, MyId, Timestamp)
                    end
            end;
        {ok, Ref} ->
            NewRefs = lists:delete(Ref, Refs),
            wait(Nodes, Master, NewRefs, Waiting, TakeRef, MyId, Timestamp);
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
