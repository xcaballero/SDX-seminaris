# Run the system
## Run server
```
erl -name server@127.0.0.1
c(server).
server:start().
```
## Run clients
```
erl -name client1@127.0.0.1
c(client).
client:start({myserver, 'server@127.0.0.1'}, "User1").
```
```
erl -name client2@127.0.0.1
c(client).
client:start({myserver, 'server@127.0.0.1'}, "User2").
```
