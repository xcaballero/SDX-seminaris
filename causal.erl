-module(basic).
-export([start/3]).

start(Id, Master, Jitter) ->
    spawn(fun() -> init(Id, Master, Jitter) end).

init(Id, Master, Jitter) ->
    receive
        {peers, Nodes} ->
            server(Id, Master, lists:delete(self(), Nodes), Jitter)
    end.

server(Id, Master, Nodes, Jitter, MsgVC, Queue) ->
    receive
        {send, Msg} ->
            NewMsgVC = increment(Id, MsgVC)
            multicast(NewMsgVC, Nodes, Jitter),
            Master ! {deliver, NewMsgVC},
            server(Id, Master, Nodes, Jitter, NewMsgVC);
        {multicast, Msg, FromId, MsgVC} ->
            case checkMsg(FromId, MsgVC, VC, size(VC)) of
                ready ->
                    Master ! {deliver, Msg},
                    NewMsgVC = setelement(FromId, VC, element(FromId, MsgVC)),
                    {NewerVC, NewQueue} = deliverReadyMsgs(Master, NewVC, Queue, Queue),
                    server(Id, Master, Nodes, Jitter, NewerVC, NewQueue);
                wait -> 
                    server(Id, Master, Nodes, Jitter, VC, [{FromId, MsgVC, Msg}|Queue])
            
        stop ->
            ok
    end.

multicast(Msg, Nodes, 0, Id, MsgVC) ->
    lists:foreach(fun(Node) -> 
                      Node ! {multicast, Msg} 
                  end, 
                  Nodes);
multicast(Msg, Nodes, Jitter, Id, MsgVC) ->
    lists:foreach(fun(Node) -> 
                      T = rand:uniform(Jitter),
                      timer:send_after(T, Node, {multicast, Msg})
                  end, 
                  Nodes).
                  
deliverReadyMsgs(_, VC, [], Queue) -> {VC, Queue};
deliverReadyMsgs(Master, VC, [{FromId, MsgVC, Msg}|Rest], Queue) -> 
    case checkMsg(FromId, MsgVC, VC, size(VC)) of
        ready ->
            Master ! {deliver, Msg},
            NewVC = setelement(FromId, VC, element(FromId, MsgVC)),
            NewQueue = lists:delete({FromId, MsgVC, Msg}, Queue),
            deliverReadyMsgs(Master, NewVC, NewQueue, NewQueue);
        wait ->
            deliverReadyMsgs(Master, VC, Rest, Queue)
    end.


increment(N, VC) ->
    setelement(N, VC, element(N, VC) + 1)

%% Check if a message can be delivered to the master
checkMsg(_, _, _, 0) -> ready;
checkMsg(FromId, MsgVC, VC, FromId) ->
    if (element(FromId, MsgVC) == element(FromId, VC)) ->
        checkMsg(FromId, MsgVC, VC, FromId-1);
    true -> wait
    end;
checkMsg(FromId, MsgVC, VC, N) ->
    if (element(N, MsgVC) =< element(N, VC)) ->
        checkMsg(FromId, MsgVC, VC, N-1);
    true -> wait
    end.
    
                  
newVC(0, List) ->
    list_to_tuple(List);
newVC(N, List) ->
    newVC(N-1, [0|List]).
