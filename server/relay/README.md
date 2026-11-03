# Wattlands relay

The multiplayer relay from BRIEF 5.3. A host creates a room and gets a short code. Friends join with that code. The relay passes messages between them in a star around the host, and it never looks inside a message's payload. It needs no accounts and no database. One relay serves every game.

It is TypeScript, run directly by Node's built-in type stripping (Node 22.12 or newer; nothing is compiled). It prefers the [`ws`](https://github.com/websockets/ws) package. When `ws` can't be imported (no `npm ci`, an offline machine), it falls back to its own RFC 6455 server on `node:http` and `node:crypto`, so it also runs with zero npm dependencies.

## Run it locally

From the repository root, with nothing installed:

```sh
node server/relay/src/main.ts
```

It listens on port 8787 on every interface and prints `WATTLANDS_RELAY ws://127.0.0.1:8787/v1`. That line is the URL the app uses by default (`ws://localhost:8787/v1`, or `--relay=<url>`). Harnesses that start the relay on `PORT=0` read the chosen port from it.

On Node 22.12 to 22.17, add `--experimental-strip-types`: `node --experimental-strip-types server/relay/src/main.ts`. Newer Node versions strip types by default.

`npm ci` in `server/relay` installs `ws` 8.22.0, which the relay then uses. `npm start` does the same as the command above.

| Option | Environment | Default | Meaning |
| --- | --- | --- | --- |
| `--port=<n>` | `PORT` | `8787` | TCP port; `0` picks a free one. A blank `PORT` counts as unset |
| `--host=<addr>` | `HOST` | all interfaces | Interface to bind, for example `127.0.0.1` |
| `--impl=auto\|ws\|builtin` | `RELAY_WS_IMPL` | `auto` | WebSocket layer: `auto` uses `ws` when it imports, else the built-in server; `ws` fails if it is missing |
| | `RELAY_TRUST_PROXY` | off | Where the client address comes from behind a proxy: `1` the last `X-Forwarded-For` entry, `2` the second from the right, `fly` Fly's `Fly-Client-IP`. Leave it unset when clients connect directly. See [Behind a proxy](#behind-a-proxy) |
| `--max-connections=<n>` | `RELAY_MAX_CONNECTIONS` | `500` | Open sockets on the whole relay |
| `--max-connections-per-ip=<n>` | `RELAY_MAX_CONNECTIONS_PER_IP` | `64` | Open sockets from one IP address |
| `--max-rooms=<n>` | `RELAY_MAX_ROOMS` | `200` | Open rooms on the whole relay |
| `--max-rooms-per-ip=<n>` | `RELAY_MAX_ROOMS_PER_IP` | `8` | Open rooms whose host connected from one IP address |
| `--room-creates-per-min=<n>` | `RELAY_ROOM_CREATES_PER_MIN` | `10` | Rooms one IP address may create in a minute |
| `--hello-timeout=<s>` | `RELAY_HELLO_TIMEOUT_S` | `10` | Seconds a new socket has to send a valid `hello` |
| | `RELAY_LOG=quiet` | `info` | Turn off the operational log (room counts only; never codes, tokens or payloads) |

Flags take the form `--name=value` and win over the environment. The limits are whole numbers, and `0` turns that one off. An unknown option or a bad value (a typo in `RELAY_TRUST_PROXY` included) exits with code 1 and prints the usage text.

Endpoints:

- `GET /health` returns `{"status":"ok","proto":1,"impl":"ws","uptime_s":…,"rooms":…,"connections":…,"peers":…,"held":…}`: counts only, never a room code, token or address. It answers even when the relay is at its connection cap, and it costs a loop over at most a few hundred rooms. During shutdown it returns 503 with `"status":"closing"`.
- `/v1` is the WebSocket endpoint. A query string is allowed. A plain HTTP request gets 426.

## Protocol (version 1)

Every message is one JSON object in one WebSocket text message, with its type in `t`. Clients send `hello` first, then `create` or `join`. `ping` works at any time.

```text
-> {"t":"hello","proto":1,"game":"wattlands","build":"0.1.0"}
-> {"t":"create","max":8}                       optional "code":"K7QX2M" asks for a previous code (P1)
<- {"t":"created","code":"K7QX2M","peer":1,"token":"…","max":8}
-> {"t":"join","code":"k7q-x2m","token":null}   or the saved token to reclaim a peer id
<- {"t":"joined","peer":3,"host":1,"token":"…","rejoin":false,"peers":[1,2]}
<- {"t":"error","code":"room_not_found|room_full|version_mismatch|rate_limited|bad_request","detail":"…","re":"join"}
-> {"t":"msg","to":1,"d":{…}}                   to: a peer id, the host (1), or 0 for everyone except the sender
<- {"t":"msg","from":3,"d":{…}}
<- {"t":"peer_joined","peer":3}                 "rejoin":true when a token brought the peer back
<- {"t":"peer_left","peer":3,"reason":"dropped|left"}
<- {"t":"host_left","reason":"left|timeout|expired"}
-> {"t":"ping","ts":123}   <- {"t":"pong","ts":123}
-> {"t":"leave"}
```

Rules:

- `hello` with any `proto` other than 1 gets `version_mismatch` (with `"proto":1`), and the socket is closed with 4002. Missing or mistyped fields, unknown `t` values, invalid JSON and binary messages get `bad_request`. The connection stays open, and the message is dropped.
- Room codes are six characters from the Crockford Base32 alphabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ`, shown as `K7Q-X2M`. `join` input is case-insensitive and ignores dashes and spaces, and O reads as 0, I and L as 1. A code that can't be valid gets `room_not_found`.
- The host is always peer 1. Joiners get 2, 3 and so on, and a room never reuses a peer id. `joined.peers` lists the peers connected at that moment. `peer_joined` and `peer_left` go to every other connected peer.
- Only the host may send to a client or to everyone (`to: 0`). Clients may only send to the host; anything else is a `bad_request`. A message to a peer that isn't connected (dropped, gone or the sender itself) is dropped silently. `d` is forwarded byte for byte, so number spellings like `1.0` and integers above 2^53 arrive exactly as sent.
- `leave` by a client sends `peer_left` with reason `left` and frees its seat. Its token stops working. `leave` by the host sends `host_left` with reason `left` to everyone and closes the room. Peers stay connected outside any room and may create or join again on the same socket.

### Drops and reconnects

- A socket that closes or times out without `leave` is a drop. The others get `peer_left` with reason `dropped`, and the seat is held for 120 s. A held seat still counts toward `max`.
- A `join` with the seat's token within those 120 s takes the same peer id back. The reply has `"rejoin":true` and the same token: a seat keeps one token until it is freed, so a client saves it once, and a reconnect whose reply got lost can be retried with it. The 120 s restart at every drop. The others get `peer_joined` with `"rejoin":true`. Nothing sent while the peer was away is replayed.
- A token presented while its old socket is still open (the relay hasn't noticed the drop yet) replaces that socket. The old socket is closed with 4001, and the others see `peer_left` (`dropped`) and then `peer_joined` (`rejoin`). A client closed with 4001 should not reconnect on its own: another copy of it holds the seat now.
- After 120 s the seat is freed and the token stops working. A `join` with an unknown or expired token joins as a new peer. Expiry is checked when the `join` arrives, not only by the once-a-second sweep.
- When the host drops, everyone gets `peer_left` for peer 1 with reason `dropped`, and the room is held for 120 s. Messages to the host are dropped meanwhile. If the host doesn't come back with its token in time, everyone gets `host_left` with reason `timeout` and the room closes.
- A room closes 4 h after it was created: everyone, host included, gets `host_left` with reason `expired`.

## Limits

| Limit | Value | What happens |
| --- | --- | --- |
| Peers per room | 8 (`create.max` is capped at 8) | `room_full` |
| Message size | 16 KB (16 384 bytes of WebSocket payload, fragments included). A forwarded `msg` is a few bytes longer than the one sent (`"from":N` replaces `"to":N`), so clients keep their inbound buffer above 16 KB (Godot's default is 64 KB) | Close 1009 |
| Message rate | 60 a second per connection, burst 120 (token bucket over every message, `ping` included) | Message dropped; at most one `rate_limited` error a second |
| Idle timeout | 60 s without a message to the relay. Clients send `ping` every 15 s. WebSocket ping and pong frames are answered but don't count | Close 4000, a drop |
| Join attempts | 10 a minute per IP address (sliding window; refused attempts don't count) | `rate_limited` |
| First `hello` | 10 s after the socket opens. A `ping` doesn't count, only a valid `hello` | Close 4000 (reason `no hello`) |
| Open sockets | 500 in all, 64 per IP address | Refused before the handshake: HTTP 503 (full) or 429 (your address), with `Retry-After: 30`. A socket that gets past that anyway is closed with 1013 |
| Open rooms | 200 in all, 8 per IP address (counted by the address the host created it from; a room whose host dropped counts until it is freed) | `create` gets `rate_limited` |
| Room creates | 10 a minute per IP address (refused creates don't count) | `rate_limited` |
| Room lifetime | 4 h | `host_left` `expired` |
| Reconnect token | 120 s after the drop | Seat freed; for the host, `host_left` `timeout` |
| Unsent output | 1 MiB per connection, checked before each send and on each frame received (so a client that floods WebSocket pings and never reads is caught too) | Close 4003 (slow consumer), a drop |

Joining a room, rejoining with a token and a host taking its room back with its token use none of the room limits. Only `create` does, and a host that drops comes back with its token rather than with a new `create`. A host that restarts and asks for its old code does `create`, which counts once. Eight riders behind one router fit: that is one room, eight sockets, one create and seven joins.

Close codes the relay sends: 1001 shutdown, 1013 over a connection cap, 1002 protocol error, 1007 invalid UTF-8, 1009 message too big, 4000 idle timeout, 4001 replaced by a reconnect, 4002 version mismatch, 4003 slow consumer.

The built-in WebSocket server implements the version 13 handshake (426 for another version, 400 for a bad key, 404 for another path, 405 for a method other than GET). It handles text, binary, continuation, close, ping and pong frames. Client frames must be masked. It supports no extensions and no subprotocols, and it ignores permessage-deflate offers. The `ws` layer is configured the same way, and the same frame-level tests run against both.

## Running it for friends

Run `node server/relay/src/main.ts` on a PC that stays on, a small VPS or a Raspberry Pi, and make port 8787 reachable (a router port forward, or a proxy in front). Riders put the address in the app's Relay URL setting, or start the app with `--relay=<url>`. Everyone who uses the same relay can host and join, and the defaults suit a group of friends: nothing needs to be set. Rooms live in memory, so a restart ends them.

## Running it in public

Anyone who finds the address can open sockets and create rooms, so the relay caps what one address, and the relay as a whole, can hold: sockets, rooms, room creates and the time a socket may sit without saying hello (see Limits). The defaults suit a small public relay on a 256 MB machine. Raise them for a bigger machine, and lower them if you share it. To see how close you are, watch `/health` and the relay's log. The log gets one line a minute, with the counts of refused sockets and creates, when there were any (no addresses and no room codes).

Before you open it up:

- Put TLS in front of it (next section).
- Set `RELAY_TRUST_PROXY` correctly if there is a proxy (see [Behind a proxy](#behind-a-proxy)). A wrong count makes riders share one address and one set of caps.
- Run one instance, with a process manager that restarts it.
- Remember what a cap is for: it keeps one client from using all the memory. It is not a login. The relay has no accounts, and a room code is the only thing between a stranger and a room.

## TLS (`wss://`)

The relay itself speaks plain WebSocket (`ws://`). With `ws://`, anyone on the path between a rider and the relay can read every message (room codes, reconnect tokens, riders' names, power and cadence) and can forge them, for example by stealing a token and taking a rider's seat. That is fine on a home network and wrong on the internet. For anything public, serve the relay as `wss://` by putting a proxy that terminates TLS in front of it. Fly.io and Render do this for you, and Caddy or nginx work on your own machine. The app verifies the certificate for `wss://` addresses.

TLS protects the room, not the rider's body. Every rider's own PC applies its safety limits to each load request before it reaches their trainer, whoever sent that request. A forged message can spoil a game, but it can't push a trainer past what that rider's PC allows.

## Behind a proxy

The relay counts joins, sockets and rooms per client address. Behind a proxy the address on the socket is the proxy's, so `RELAY_TRUST_PROXY` says where the real one is. Left unset, the relay uses the socket address and ignores every forwarding header, which is right when clients connect directly.

- `RELAY_TRUST_PROXY=1` takes the **last** `X-Forwarded-For` entry. A proxy that appends writes the address it saw as the last entry. Everything to the left was sent by the client or by earlier hops, and a client can write anything there, so the relay never reads it.
- `RELAY_TRUST_PROXY=2` (or more) takes the second entry from the right, for two proxies in a row, such as a CDN in front of your own proxy. If the header has fewer entries than that, the socket address is used.
- `RELAY_TRUST_PROXY=fly` takes `Fly-Client-IP`, which Fly's proxy sets itself on every request. The other modes ignore that header: behind a proxy that doesn't overwrite it, a client could send its own.

**Fly.io:** `fly.toml` sets `RELAY_TRUST_PROXY = "fly"` under `[env]`.

**Render:** `render.yaml` sets `RELAY_TRUST_PROXY` to `1` under `envVars`. If your service has another layer in front of Render, such as Cloudflare, use `2`.

To check the setting after you deploy, start the relay with `RELAY_MAX_CONNECTIONS_PER_IP=1` for a minute. Open one connection (for example with `wscat -c wss://<your host>/v1`), and a second one from the same machine should be refused. Then connect from a phone on mobile data. If that is refused too, the relay sees the proxy's address and the count is too low.

## Tests

```sh
cd server/relay
node --test                     # zero dependencies: the ws suites are skipped
npm ci && node --test           # both WebSocket layers
RELAY_REQUIRE_WS=1 node --test  # fail instead of skip when ws is missing (CI)
```

The suites run in about a second. Time-based rules use an injected clock (`FakeClock`), so the 60 s, 120 s and 4 h cases don't wait. They cover create, join, leave, routing and `to: 0`, the client-to-host restriction, every limit and cap, the hello deadline, reconnects and token expiry, host drop and hold, `host_left`, malformed input, version mismatch, code normalization, RFC 6455 frame handling and the zero-dependency start.

The sources pass a strict TypeScript check (`tsconfig.json`, `erasableSyntaxOnly`). TypeScript isn't a dependency; any TypeScript 5.8 or newer with `@types/node` and `@types/ws` can run it.

## Deploying

The relay keeps every room in memory. Run exactly one instance, and don't scale it horizontally. A restart drops every room (clients see the socket close and can create a new room).

- Docker: `docker build -t wattlands-relay server/relay`, then `docker run -p 8787:8787 wattlands-relay`. The image is `node:24-alpine`. It runs as the `node` user, installs `ws` with `npm ci --omit=dev` when `package-lock.json` exists, and has a `HEALTHCHECK` on `/health`.
- Fly.io: `fly.toml` is an example (it sets `RELAY_TRUST_PROXY = "fly"`). Change `app`, then run `fly launch --copy-config --no-deploy` and `fly deploy` from `server/relay`. Keep one machine running (`fly scale count 1`). Clients connect to `wss://<app>.fly.dev/v1`.
- Render: `render.yaml` is an example Blueprint (a Docker web service with `rootDir: server/relay`; it sets `RELAY_TRUST_PROXY` to `1`). Render sets `PORT`, and the relay honours it. Clients connect to `wss://<service>.onrender.com/v1`.
- Behind a proxy, set `RELAY_TRUST_PROXY` so the limits see each rider's own address, not the proxy's (see below). Make sure the proxy's idle timeout is above the clients' 15 s ping interval.
- The relay never logs room codes, tokens or payloads. `/health` shows counts only.

## Files

- `src/main.ts`: the command-line entry. `src/options.ts` parses its flags and environment.
- `src/server.ts`: `startRelay()`, the HTTP routes and the choice of WebSocket layer.
- `src/relay.ts`: the protocol core.
- `src/ws_builtin.ts` and `src/handshake.ts`: the built-in RFC 6455 server.
- `src/ws_package.ts`: the `ws` adapter.
- `src/codes.ts`, `src/limits.ts`, `src/json_span.ts` and `src/clock.ts`: the helpers.
- `test/*.test.mjs`: the suites. `testkit/` holds their helpers: a WebSocket JSON client and a byte-level frame client.

For in-process use (an end-to-end harness, for example): `import { startRelay } from 'server/relay/src/server.ts'`, then `const r = await startRelay({ port: 0, host: '127.0.0.1' })`. `r.url` is the address, and `await r.close()` stops the relay.
