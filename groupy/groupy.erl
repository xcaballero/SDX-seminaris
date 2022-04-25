-module(groupy).
-export([start/2, stop/0, start_distributed/2, stop_distributed/0]).

% We use the name of the module (i.e. gms3) as the parameter Module to the start procedure. Sleep stands for up to how many milliseconds the workers should wait until the next message is sent.

start(Module, Sleep) ->
    register(a, worker:start("P1", Module, Sleep)),
    register(b, worker:start("P2", Module, a, Sleep)),
    register(c, worker:start("P3", Module, b, Sleep)),
    register(d, worker:start("P4", Module, c, Sleep)),
    register(e, worker:start("P5", Module, d, Sleep)).

stop() ->
    stop(a),
    stop(b),
    stop(c),
    stop(d),
    stop(e).
    

start_distributed(Module, Sleep) ->
    spawn('a@127.0.0.1', fun() -> register(a, worker:start("P1", Module, Sleep)) end),
    spawn('b@127.0.0.1', fun() -> register(b, worker:start("P2", Module, {a, 'a@127.0.0.1'}, Sleep)) end),
    spawn('c@127.0.0.1', fun() -> register(c, worker:start("P3", Module, {b, 'b@127.0.0.1'}, Sleep)) end),
    spawn('d@127.0.0.1', fun() -> register(d, worker:start("P4", Module, {c, 'c@127.0.0.1'}, Sleep)) end),
    spawn('e@127.0.0.1', fun() -> register(e, worker:start("P5", Module, {d, 'd@127.0.0.1'}, Sleep)) end).

stop_distributed() ->
    {a, 'a@127.0.0.1'} ! stop,
    {b, 'b@127.0.0.1'} ! stop,
    {c, 'c@127.0.0.1'} ! stop,
    {d, 'd@127.0.0.1'} ! stop,
    {e, 'e@127.0.0.1'} ! stop.  

stop(Name) ->
    case whereis(Name) of
        undefined ->
            ok;
        Pid ->
            Pid ! stop
    end.

