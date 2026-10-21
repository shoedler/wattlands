# Wattlands network protocol

Multiplayer is a star through a relay (BRIEF 5.1). The host's GameHost is authoritative and simulates at 20 Hz; clients send telemetry and intents; the host sends snapshots, events, plans, phases and directives. Every frame is one JSON text object. The relay (`server/relay`, Node) routes frames between the peers of a room and never looks inside a game message.

Two layers:

- The **relay envelope** (field `"t"`), between a client and the relay (BRIEF 5.3).
- **Game messages** (field `"type"` plus schema version `"v"`), carried in the envelope's `"d"` and read only by the peers (BRIEF 5.5).

The tables live in `addons/wattlands/contracts/net_messages.gd` (`NetMessages`). `Protocol` (`addons/wattlands/net/protocol.gd`) encodes, decodes and validates; `WlNetSession` (`net_session.gd`) runs the lobby and routing on top of a `Transport`.

## 1. Relay envelope

| Frame | Direction | Fields | Meaning |
| --- | --- | --- | --- |
| `hello` | client -> relay | `proto` (`Wl.PROTO`, 1), `game` (`"wattlands"`), `build` | First frame on every socket. Another `proto` gets `error version_mismatch` and the socket closes. |
| `create` | client -> relay | `max` (1-8), optional `code` (P1) | Create a room. With `code`, the relay uses it if it is free (host code reclaim). |
| `created` | relay -> client | `code`, `peer` (1), `token` | The room code (6 Crockford characters, no dash), the host's peer id and its reconnect token. |
| `join` | client -> relay | `code`, `token` (string or null) | Join by code. A valid token reclaims the same peer id. |
| `joined` | relay -> client | `peer`, `host`, `token` | The joiner's peer id (2, 3, ... never reused), the host's id (1) and a token. |
| `error` | relay -> client | `code`: `room_not_found`, `room_full`, `version_mismatch`, `rate_limited`, `bad_request` | See 1.2. |
| `msg` | client -> relay | `to`, `d` | `to` is a peer id, the host (1) or 0 for everyone except the sender. Non-hosts may only send to the host. |
| `msg` | relay -> client | `from`, `d` | `d` is the sender's game message, untouched. |
| `peer_joined` | relay -> others | `peer` | A peer joined or came back with its token (same id). |
| `peer_left` | relay -> others | `peer`, `reason` (`dropped`, `left`) | A socket dropped (the id is held 120 s) or the peer left. A host drop is `peer_left` for peer 1. |
| `host_left` | relay -> clients | | The host left explicitly, or its token expired 120 s after a drop. The room is gone. |
| `leave` | client -> relay | | Explicit leave; invalidates the peer's token. |
| `ping` / `pong` | client -> relay -> client | `ts` | Keep-alive; clients ping every 15 s. |

### 1.1 Rooms, ids and tokens

- Room codes use `0123456789ABCDEFGHJKMNPQRSTVWXYZ` and are shown as `K7Q-X2M`. Input is case-insensitive, ignores dashes and spaces, and maps O to 0 and I or L to 1 (`RoomCode`).
- The creator is peer 1; joiners get 2, 3, ... in join order. Ids are never reused within a room.
- Every `created` and `joined` carries a reconnect token. A token stays valid for 120 s after its peer's socket drops; joining with it restores the same peer id and tells the others `peer_joined`. The in-process relays (`RelayRooms`) issue a fresh token on every join; clients always save the latest token they got, so they work with a relay that keeps tokens too.
- A dropped host holds its room for 120 s and reclaims peer 1 with its token; after that the relay sends `host_left` to everyone.

### 1.2 Errors

While creating or joining, every error code ends the attempt: the transport closes the socket and emits `disconnected(code)`, and `WlNetSession` emits `refused(code)` and `EventBus.session_refused(code)`. Inside a room, `rate_limited` and `bad_request` only drop the offending frame (`push_warning`, `RelayClientTransport.relay_error`); `version_mismatch` always ends the connection.

### 1.3 Limits (BRIEF 5.3, `NetMessages`)

| Limit | Value |
| --- | --- |
| Peers per room | 8 |
| Frame size | 16 384 bytes (UTF-8 of the whole envelope) |
| Rate | 60 frames per second per peer, burst 120 |
| Idle timeout | 60 s without a frame (clients ping every 15 s) |
| Join attempts | 10 per minute per IP (Node relay) |
| Room lifetime | 4 h |
| Reconnect token | 120 s after a drop |

## 2. Game messages

Every game message has `"type"` and `"v"` (`NetMessages.VERSION`, 1). Build them with `Protocol.game_msg(type, payload)`. Required fields are checked on arrival (with their types for the fields in `Protocol.GAME_TYPES`); a message that fails is dropped with `push_warning`.

### 2.1 Client to host

| Type | Fields (required in bold) | Notes |
| --- | --- | --- |
| `player_info` | **`name`**, **`ftp`**, **`ftp_verified`**, **`p_eff_per_w`**, **`preferred_cadence_rpm`**, **`haptics_on`**, **`autopilot`**, **`player_options`** ({option id: value}), **`games`** ({game id: version}); `color` (profile colour, html), `weight_kg` (only if the rider shares it), `haptic_intensity` (0-1), `trainer` (status text), `p_eff_mode` (the scaling mode `p_eff_per_w` was computed for), `p_eff_by_mode` ({mode: value}; FAIR_FTP and RAW always, WKG only with a shared weight) | Sent on join, on every rejoin and whenever it changes. `WlNetSession.set_local_profile()` builds it from the `RiderProfile` and re-sends it when the lobby's scaling mode changes. |
| `ready` | **`ready`** (bool) | Refused by the host while the client lacks the game or has another version (2.4). |
| `telemetry` | **`tm`**: `Telemetry.to_dict()` | 5 Hz. Ints: `tm.peer`, `tm.applied_target_w`, `tm.gear`, `tm.phase_index`, `tm.acks[].id`. `tm.intents` is never converted (games cast); the host keeps at most 32 intents per message and drops any intent over 1 KB (`push_warning`). |
| `clock_ping` | **`t0`** (client platform time, s) | On join, then every 1 s for the first three samples and every 5 s after. |

### 2.2 Host to all clients

| Type | Fields | Notes |
| --- | --- | --- |
| `lobby_state` | **`players`**, **`game_id`**, **`game_version`**, **`content_id`**, **`scaling`**, **`settings`**; `seq` (lobby revision), `host`, `started`, `player_options` ({peer: {id: value}}), `ready_flags` ({peer: bool}), `trainers` ({peer: status}) | Sent on every lobby change, to each new peer and on every rejoin. `players` is in slot order: humans in join order, then bots. Each entry: `peer_id`, `name`, `slot_index`, `color`/`shape`/`pattern`/`hollow` (the slot look, `Wl.slot_look`), `profile_color`, `ftp` (int W), `ftp_verified`, `scaling_mode`, `p_eff_per_w`, `rider_mass_kg`, `preferred_cadence_rpm`, `haptics_on`, `haptic_intensity`, `autopilot`, `is_bot`, `ready`, `connected`, `game_ok`, `game_issue` (`""`, `missing_game`, `version_mismatch`), `trainer`. `settings`: `options` (the game's options with defaults filled), `bot_ftp` (int W; default the host's FTP), `max_players`, `min_players`, `bots_allowed`, plus any key set with `set_setting`. |
| `session_start` | **`game_id`**, **`game_version`**, **`content_id`**, **`seed`**, **`players`** (`PlayerSlot.to_dict()` in slot order), **`options`**, **`scaling`**, **`start_tick`** | Sent by the GameHost. Clients clear their snapshot buffer. |
| `snapshot` | **`game_id`**, **`seq`**, **`state`** (the game's `snapshot()`); `tick`, `t` (host time, s) | 10 Hz. Clients drop a `seq` at or below the newest one (`stats.stale_snapshots`). |
| `event` | **`seq`**, **`events`** (game events, each with `"type"`) | At most 10 per second, sent before the same tick's snapshot (OWNERSHIP C12). Phase changes travel here too. |
| `roster` | **`riders`**: {peer: `NetRoster.entry()`} | 2 Hz: `peer_id`, `name`, `slot_index`, `is_bot`, `raw_w`, `cadence_rpm`, `ftp_pct`, `rescue`, `afk`, `connected`, `status` (the latest `teammate_status`). Build with `NetRoster.build()`, send with `WlNetSession.send_roster()`. |
| `results` | **`results`**: `GameResults.to_dict()` | Ints: `results.rows[].xp`, `results.rows[].slot_index`. |
| `session_end` | **`reason`** | |
| `refused` | **`reason`**; `scope` (`"ready"` for a refused ready-up), `game_id`, `game_version` | `session_in_progress`, `room_full`, `version_mismatch` end the client's session; with `scope: "ready"` (`missing_game`, `version_mismatch`) only the ready-up is refused. Accepted on every schema version. |

### 2.3 Host to one client

| Type | Fields | Notes |
| --- | --- | --- |
| `plan` | **`plan`**: `EffortPlan.to_dict()` | At the start and after every `replan`; the client re-validates it before its governor uses it. |
| `phase` | **`index`**, **`start_tick`**, **`ended_by`** (`duration`, `max_s`, `end_phase`, `finished`, `start`) | On every phase change of that rider and on rejoin. |
| `directive` | **`kind`** (`request`, `course_grade`, `cadence_band`, `power_band`); `id` | `request`: the `EffortDirective.to_dict()` fields at the top level (`mode`, `target_pct`/`target_wkg`/`target_w`, `mode_grade`, `haptic`, `haptic_wind`, `crr`, `cw`, `duration_s`, `reason`, `source`). `course_grade`: `grade_pct`. `cadence_band`: `lo_rpm`, `hi_rpm` (0, 0 clears). `power_band`: `lo_w`, `hi_w` (0, 0 clears). |
| `hud` | **`kind`** (`toast`, `banner`), **`key`**; `args`, `seconds` | A toast or banner for that peer only. |
| `clock_pong` | **`t0`** (echoed), **`th`** (host platform time) | |

## 3. Int conversion

Godot's JSON parser returns every number as a float. `Protocol.decode()` (and `decode_game()`) turns them back:

1. `peer`, `host`, `from`, `to`, `seq`, `proto`, `max` and `v` at the top level of the envelope and of the game message.
2. Every key ending in `_id`, at any depth, when it holds a whole number (a string such as `game_id: "siege"` stays a string; `2.5` stays a float), except inside `tm.intents`.
3. The schema's int paths (`NetMessages.GAME[type].ints`, plus `settings.bot_ftp`, `settings.max_players` and `settings.min_players` of `lobby_state`). Paths are dotted; `[]` walks every array element, `{}` every dictionary value (`players[].slot_index`, `riders{}.slot_index`, `tm.acks[].id`).
4. The keys of dictionaries stored under `riders`, `player_options`, `ready_flags` and `trainers` become ints when they spell an integer, so `{"2": ...}` becomes `{2: ...}` (bots: `-1`). Keys that are not integers (option ids) stay strings. This does not apply inside a snapshot's `state` or an event's `events` (game payloads) or inside intents.

Games declare the ints of their own payloads with `GameModule.int_fields()`: `{"snapshot": [paths], "<event type>": [paths]}`. `Protocol.apply_int_fields(data, paths)` converts numeric leaves at matched paths (rounded) and leaves an Array or Dictionary found there unchanged, so Siege's `f: [[pad, [target_ids]]]` declares `f[][]` and `f[][][]` (OWNERSHIP 3.1 C10). `WlNetSession.set_game_int_fields(game.int_fields())` applies them to every received snapshot and event before `game_message`; applying them again is harmless. No event type may be named `snapshot`. Intents are never converted.

Round trips are exact: a message built with ints where these rules make ints, and floats elsewhere, comes back identical through `JSON.stringify` + `JSON.parse_string` + `decode_game`, and through `encode` + `decode` (tested for every message type in `tests/net/test_protocol.gd`). `encode()` keeps insertion order and writes floats at full precision. Godot's own parser is not correctly rounded for long decimals, so a float with many significant digits can differ in its last bit after a round trip; values such as `0.5`, `187.25` or `0.7` come back exactly.

## 4. Versioning

- The relay checks `hello.proto` (`Wl.PROTO`).
- Every game message carries `v` = `NetMessages.VERSION`. A message with another `v` is dropped (`Protocol.last_error == "version_mismatch"`) and the transport emits `protocol_mismatch(from)`. The host answers a client on another version with `refused {reason: "version_mismatch"}`; a client that gets a host message on another version refuses itself. Either way the player sees `NET_REFUSED_VERSION_MISMATCH`.
- `refused` is readable on every version.
- Each game's version is checked in the lobby: `player_info.games[game_id]` must equal `lobby_state.game_version`, or the client can't ready up (`ready_refused` with `NET_READY_MISSING_GAME` or `NET_READY_VERSION_MISMATCH`).
- A change to a message's required fields or meaning bumps `NetMessages.VERSION`; adding an optional field does not.

## 5. Session behaviour (`WlNetSession`)

- **Roles.** `host_room()` makes this peer the host (peer 1); `join_room(code)` a client; `start_offline()` the SOLO lobby with no transport (the local rider is peer 1). Lobby settings made before `host_room()` (game, scaling, options) carry over.
- **Lobby.** The host's lobby is the only truth; clients receive it as `lobby_state`. Slots follow join order (a dropped peer that comes back before the start keeps its place), then bots (`Bot n`, peer `-n`, the lobby's bot FTP, verified, Autopilot). `set_game_manifest()` (or the GameRegistry autoload) gives `min_players`, `max_players`, `bots` and the option defaults. Changing the game resets every client's ready flag. `all_ready()` needs every connected human ready with the game at the host's version and a player count within the game's limits.
- **Start.** `mark_started()` freezes the slots. A peer that joins afterwards without a valid token, or never sent `player_info`, gets `refused {reason: "session_in_progress"}` and leaves; the host never lists it.
- **Drops and rejoins.** A dropped client (or host) re-joins with its token: at once, then after 1, 2, 4, 8 and every 15 s, until 120 s have passed (`state` "reconnecting"; with `auto_reconnect` off it waits for `rejoin()`). The token is saved to `Paths.reconnect_token_path()` on every `created`/`joined`, so a restarted client with the same profile dir and `--join=<code>` comes back as the same peer. After the start, a returning peer gets `lobby_state` and the host emits `rejoin_requested(peer)`, on which the GameHost sends its `plan`, `phase` and the latest snapshot (`latest_snapshot()`). After 120 s the client ends with `refused("dropped")`.
- **Ending.** `host_left` ends every client gracefully: `refused("host_left")`, `EventBus.session_refused("host_left")`, state "offline", token forgotten. Host migration is P2.
- **Routing.** `send_to_host`, `send_to(peer)` and `broadcast` (host only). Clients may only send `player_info`, `ready`, `telemetry` and `clock_ping`, and only to the host; the host ignores other types from clients and clients ignore those four from the host. A message to the local peer is delivered locally on the next poll (through JSON). Invalid outgoing messages are refused with `push_error`.
- **Size.** Nothing over 16 384 bytes (the whole envelope) is sent: it is dropped with `push_warning` and counted in `stats.oversize_dropped` and, for snapshots, `stats.oversize_snapshots` (OWNERSHIP C9).
- **Coalescing.** `directive` messages of kind `course_grade`, `cadence_band` and `power_band` to one peer go out at most once per 100 ms per kind; the latest one wins and any pending one is flushed before another message to that peer, so `request` and `phase` are never dropped or reordered (OWNERSHIP C11).
- **Clock.** `clock_ping`/`clock_pong` give the client `clock_offset` (the sample with the smallest round trip of the last 8); `host_time()` is the estimated host platform time.
- **Snapshots.** Clients keep the last `snapshot_buffer_size` (8) snapshots: `latest_snapshot()`, `snapshot_at(t)` and `snapshot_pair_at(t)` (`{from, to, alpha}` for 100 ms interpolation at `host_time() - 0.1`).
- **Time.** `tick(dt)` advances the session's platform time and polls; the GameHost calls it once per platform step (or `set_time()` plus `poll()`). If a session is only ever polled, each poll counts as one 0.05 s step. The `NetSession` autoload ticks itself from `_process`.

## 6. Budget

A 4-rider session with 10 Hz snapshots, 10 Hz event batches, a 2 Hz roster and per-client directives (2 Hz requests, 2 Hz `course_grade`, 2 Hz `cadence_band`, 1 Hz `power_band`) sends about 43 frames a second from the host; clients send 5 Hz telemetry plus clock pings. `tests/net/test_net_session.gd` runs that load for 30 s against the relay's limits and asserts no `rate_limited`.

## 7. Transports

| Class | Use |
| --- | --- |
| `RelayTransport` | `WebSocketPeer` to the relay. URL: `--relay=<ws url>`, else `Settings.relay_url()`, else `ws://localhost:8787/v1`; `wss://` uses `TLSOptions.client()`. 10 s connect timeout, 15 s pings, a drop after 45 s without any frame. After `leave` the socket lingers 250 ms so the relay reads the leave first. |
| `LoopbackTransport` + `LoopbackHub` | In-process relay for tests and `run_game_sim` HOST runs: `RelayRooms` semantics, frames through JSON, delivery in each transport's `poll()` in order, deterministic codes and tokens. Fault injection: `simulate_drop()`, `LoopbackHub.drop_peer(code, peer)`, `latency_ticks`; `enforce_limits(true)` with `advance(dt)` turns on the rate limit and idle timeout. |
| `LocalRelayServer` | The relay protocol served by Godot itself (`TCPServer` + `WebSocketPeer` + `RelayRooms`), for LAN play and the RelayTransport tests. |
| `LanTransport` (P1) | LAN play without the internet relay: see section 8. |

All transports run with `PROCESS_MODE_ALWAYS` and do their I/O in `poll()`, which the owning `WlNetSession` calls.

## 8. LAN play (P1)

`LanTransport` (a `RelayTransport`) plays on a local network without the internet relay:

- **Host.** `host()` starts a `LocalRelayServer` on TCP port 8790 (`port`; every interface), joins it over `ws://127.0.0.1:8790/v1` as peer 1, and once the room exists broadcasts a beacon every second to UDP 255.255.255.255:8791 (`discovery_address`, `discovery_port`).
- **Beacon.** One datagram of JSON: `{"wattlands": "lan", "proto": 1, "code": "K7QX2M", "port": 8790, "name": "<host name>", "build": "0.1.0"}`. Receivers take the host's address from the datagram, never from the payload, and ignore beacons of another `proto` (`LanDiscovery.parse_beacon`).
- **Client.** `join(code)` listens on UDP 8791 (`LanDiscovery`) until it hears that code (at most 5 s, else `disconnected("room_not_found")`), then joins `ws://<sender>:<port>/v1` like any relay. With `url` set it connects straight to that host. A rejoin after a drop reuses the address it found.
- `lan_rooms()` lists the rooms heard so far (`{code: {code, ip, port, name, build, seen}}`; a room not heard for 5 s is forgotten), for a LAN room list in the UI.
- Everything else (codes, tokens, limits, lobby, reconnect) is the relay protocol above. Windows asks once to allow the game through the firewall when a LAN host first listens.

## 9. Files

| File | Content |
| --- | --- |
| `Paths.reconnect_token_path()` (`reconnect_token.json`) | `{code, token, peer, role}` of the current room; removed on leave, refusal and session end. |
| `Paths.recent_rooms_path()` (`recent_rooms.json`) | `[{code, role}]`, newest first, at most 10 (P1: `host_room_reclaim()` asks for the last hosted code). |
