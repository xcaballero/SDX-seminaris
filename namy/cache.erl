-module(cache).
-export([lookup/2, add/4, remove/2, purge/1]).

lookup(Req, Cache) ->
    case lists:keyfind(Req, 1, Cache) of
        false ->
            unknown;
        {Req, Entry, Expire} ->
            Now = erlang:convert_time_unit(erlang:monotonic_time() , native, second),
            case Expire < Now of
                true ->
                    invalid;
                false ->
                    Entry
            end
    end.
            

add(Name, Expire, Entry, Cache) ->
    lists:keystore(Name, 1, Cache, {Name, Entry, Expire}).


remove(Name, Cache) ->
    lists:keydelete(Name, 1, Cache).


purge([]) ->
    [];
purge([{Name, Entry, Expire} | Rest]) ->
    Now = erlang:convert_time_unit(erlang:monotonic_time() , native, second),
    case Expire < Now of
        true ->
            purge(Rest);
        false ->
            RestCache = purge(Rest),
            [{Name, Entry, Expire} | RestCache]
    end.