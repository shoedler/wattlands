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
| `--port=<n>` | `PORT` | `8787` | TCP port; `0` picks a free one |
| `--host=<addr>` | `HOST` | all interfaces | Interface to bind, for example `127.0.0.1` |
| `--impl=auto\|ws\|builtin` | `RELAY_WS_IMPL` | `auto` | WebSocket layer: `auto` uses `ws` when it imports, else the built-in server; `ws` fails if it is missing |
| | `RELAY_TRUST_PROXY=1` | off | Take the client IP for the join limit from `Fly-Client-IP` or the first `X-Forwarded-For` entry. Set it only behind a proxy |
| | `RELAY_LOG=quiet` | `info` | Turn off the operational log (room counts only; never codes, tokens or payloads) |

Endpoints:

- `GET /health` returns `{"status":"ok","proto":1,"impl":"ws","uptime_s":…,"rooms":…,"connections":…,"peers":…,"held":…}`. During shutdown it returns 503 with `"status":"closing"`.
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
- A `join` with the seat's token within those 120 s takes the same peer id back. The reply has `"rejoin":true` and a new token: clients save the token from every `created` and `joined`. The others get `peer_joined` with `"rejoin":true`. Nothing sent while the peer was away is replayed.
- A token presented while its old socket is still open (the relay hasn't noticed the drop yet) replaces that socket. The old socket is closed with 4001, and the others see `peer_left` (`dropped`) and then `peer_joined` (`rejoin`).
- After 120 s the seat is freed and the token stops working. A `join` with an unknown or expired token joins as a new peer.
- When the host drops, everyone gets `peer_left` for peer 1 with reason `dropped`, and the room is held for 120 s. Messages to the host are dropped meanwhile. If the host doesn't come back with its token in time, everyone gets `host_left` with reason `timeout` and the room closes.
- A room closes 4 h after it was created: everyone, host included, gets `host_left` with reason `expired`.

## Limits

| Limit | Value | What happens |
| --- | --- | --- |
| Peers per room | 8 (`create.max` is capped at 8) | `room_full` |
| Message size | 16 KB (16 384 bytes of WebSocket payload, fragments included) | Close 1009 |
| Message rate | 60 a second per connection, burst 120 (token bucket over every message, `ping` included) | Message dropped; at most one `rate_limited` error a second |
| Idle timeout | 60 s without any frame (clients `ping` every 15 s; WebSocket pings count too) | Close 4000, a drop |
| Join attempts | 10 a minute per IP address (sliding window; refused attempts don't count) | `rate_limited` |
| Room lifetime | 4 h | `host_left` `expired` |
| Reconnect token | 120 s after the drop | Seat freed; for the host, `host_left` `timeout` |
| Unsent output | 1 MiB per connection | Close 4003 (slow consumer), a drop |

Close codes the relay sends: 1001 shutdown, 1002 protocol error, 1007 invalid UTF-8, 1009 message too big, 4000 idle timeout, 4001 replaced by a reconnect, 4002 version mismatch, 4003 slow consumer.

The built-in WebSocket server implements the version 13 handshake (426 for another version, 400 for a bad key, 404 for another path, 405 for a method other than GET). It handles text, binary, continuation, close, ping and pong frames. Client frames must be masked. It supports no extensions and no subprotocols, and it ignores permessage-deflate offers. The `ws` layer is configured the same way, and the same frame-level tests run against both.

## Tests

```sh
cd server/relay
node --test                     # zero dependencies: the ws suites are skipped
npm ci && node --test           # both WebSocket layers
RELAY_REQUIRE_WS=1 node --test  # fail instead of skip when ws is missing (CI)
```

The suites run in about a second. Time-based rules use an injected clock (`FakeClock`), so the 60 s, 120 s and 4 h cases don't wait. They cover create, join, leave, routing and `to: 0`, the client-to-host restriction, every limit, reconnects and token expiry, host drop and hold, `host_left`, malformed input, version mismatch, code normalization, RFC 6455 frame handling and the zero-dependency start.

The sources pass a strict TypeScript check (`tsconfig.json`, `erasableSyntaxOnly`). TypeScript isn't a dependency; any TypeScript 5.8 or newer with `@types/node` and `@types/ws` can run it.

## Deploying

The relay keeps every room in memory. Run exactly one instance, and don't scale it horizontally. A restart drops every room (clients see the socket close and can create a new room).

- Docker: `docker build -t wattlands-relay server/relay`, then `docker run -p 8787:8787 wattlands-relay`. The image is `node:24-alpine`. It runs as the `node` user, installs `ws` with `npm ci --omit=dev` when `package-lock.json` exists, and has a `HEALTHCHECK` on `/health`.
- Fly.io: `fly.toml` is an example. Change `app`, then run `fly launch --copy-config --no-deploy` and `fly deploy` from `server/relay`. Keep one machine running (`fly scale count 1`). Clients connect to `wss://<app>.fly.dev/v1`.
- Render: `render.yaml` is an example Blueprint (a Docker web service with `rootDir: server/relay`). Render sets `PORT`, and the relay honours it. Clients connect to `wss://<service>.onrender.com/v1`.
- Behind any TLS proxy, set `RELAY_TRUST_PROXY=1` so the join limit sees real client addresses. Make sure the proxy's idle timeout is above the clients' 15 s ping interval.
- The relay never logs room codes, tokens or payloads. `/health` shows counts only.

## Files

- `src/main.ts`: the command-line entry.
- `src/server.ts`: `startRelay()`, the HTTP routes and the choice of WebSocket layer.
- `src/relay.ts`: the protocol core.
- `src/ws_builtin.ts` and `src/handshake.ts`: the built-in RFC 6455 server.
- `src/ws_package.ts`: the `ws` adapter.
- `src/codes.ts`, `src/limits.ts`, `src/json_span.ts` and `src/clock.ts`: the helpers.
- `test/*.test.mjs`: the suites. `testkit/` holds their helpers: a WebSocket JSON client and a byte-level frame client.

For in-process use (an end-to-end harness, for example): `import { startRelay } from 'server/relay/src/server.ts'`, then `const r = await startRelay({ port: 0, host: '127.0.0.1' })`. `r.url` is the address, and `await r.close()` stops the relay.
