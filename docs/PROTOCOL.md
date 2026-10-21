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
| `joined` | relay -> client | `peer`, `host`, `token`; `rejoin` (bool: the token reclaimed this id), `peers` (the other peers connected now) | The joiner's peer id (2, 3, ... never reused), the host's id (1) and a token. A host that reclaims peer 1 reconciles its peer list with `peers` (section 5, "Host reclaim"). Both relays send both fields. |
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
- Every `created` and `joined` carries the peer's reconnect token. A token stays valid for 120 s after its peer's socket drops; joining with it restores the same peer id and tells the others `peer_joined`. The in-process relays (`RelayRooms`) keep one token per peer for as long as the peer is in the room and return it again on every rejoin, so a rejoin whose answer is lost (a second drop mid-handshake) can retry with the same token; a socket that joins with a token supersedes one still open for that peer. Clients always save the latest token they got, so they also work with a relay that rotates tokens.
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
| `player_info` | **`name`**, **`ftp`**, **`ftp_verified`**, **`p_eff_per_w`**, **`preferred_cadence_rpm`**, **`haptics_on`**, **`autopilot`**, **`player_options`** ({option id: value}), **`games`** ({game id: version}); `color` (profile colour, html), `weight_kg` (only if the rider shares it), `haptic_intensity` (0-1), `trainer` (status text), `p_eff_mode` (the scaling mode `p_eff_per_w` was computed for), `p_eff_by_mode` ({mode: value}; FAIR_FTP and RAW always, WKG only with a shared weight) | Sent on join, on every rejoin and whenever it changes. `WlNetSession.set_local_profile()` builds it from the `RiderProfile` (with the registry's installed games when none are given) and re-sends it when the lobby's scaling mode changes. Before the start, a `player_info` that would take the lobby past the game's `max_players` is answered with `refused {reason: "room_full"}`. |
| `ready` | **`ready`** (bool) | Refused by the host while the client lacks the game or has another version (`refused` with `scope: "ready"`, 2.2; section 4). |
| `telemetry` | **`tm`**: `Telemetry.to_dict()`; `resync` (a reason: the client asks for its state again) | 5 Hz. A client sets `resync` (`event_gap`, `phase`) after it logged a desync (section 5, "Staying in step"), at most every 2 s; the host answers it at most once a second per peer. Ints: `tm.peer`, `tm.applied_target_w`, `tm.gear`, `tm.phase_index`, `tm.acks[].id`. On arrival the host sets `tm.peer` to the sender's peer id (a client speaks only for its own rider). `tm.intents` is never converted (games cast); the host keeps at most 32 intents per message and drops any intent over 1 KB (`push_warning`). |
| `clock_ping` | **`t0`** (client platform time, s) | On join, then every 1 s for the first three samples and every 5 s after. |

### 2.2 Host to all clients

| Type | Fields | Notes |
| --- | --- | --- |
| `lobby_state` | **`players`**, **`game_id`**, **`game_version`**, **`content_id`**, **`scaling`**, **`settings`**; `seq` (lobby revision), `host`, `started`, `player_options` ({peer: {id: value}}), `ready_flags` ({peer: bool}), `trainers` ({peer: status}) | Sent on every lobby change, to each new peer and on every rejoin. In a WKG lobby every human's `p_eff_per_w` (75 / weight) goes out as 1.0, the 75 kg reference, so no client learns another rider's weight (BRIEF 3.2); the host keeps the real values, and a client's own `lobby_slots()` entry takes its own value from its `player_info`. `players` is in slot order: humans in join order, then bots. Each entry: `peer_id`, `name`, `slot_index`, `color`/`shape`/`pattern`/`hollow` (the slot look, `Wl.slot_look`), `profile_color`, `ftp` (int W), `ftp_verified`, `scaling_mode`, `p_eff_per_w`, `rider_mass_kg`, `preferred_cadence_rpm`, `haptics_on`, `haptic_intensity`, `autopilot`, `is_bot`, `ready`, `connected`, `game_ok`, `game_issue` (`""`, `missing_game`, `version_mismatch`), `trainer`. `settings`: `options` (the game's options with defaults filled), `bot_ftp` (int W; default the host's FTP), `max_players`, `min_players`, `bots_allowed`, plus any key set with `set_setting`. |
| `session_start` | **`game_id`**, **`game_version`**, **`content_id`**, **`seed`**, **`players`** (`PlayerSlot.to_dict()` in slot order), **`options`**, **`scaling`**, **`start_tick`**; `session_id` (`<game>/<content>/<seed>/<nonce>`, unique per session), `content_overrides`, `game`, `content`, `session` | Sent by the GameHost: one broadcast, or in WKG one per client in which only that client's own entry keeps its `p_eff_per_w` (the others carry 1.0). Clients clear their snapshot buffer. |
| `snapshot` | **`game_id`**, **`seq`**, **`state`** (the game's `snapshot()`); `tick`, `t` (host time, s) | 10 Hz. Clients drop a `seq` at or below the newest one (`stats.stale_snapshots`). |
| `event` | **`seq`**, **`events`** (game events, each with `"type"`) | At most 10 per second, sent before the same tick's snapshot (OWNERSHIP C12). Phase changes travel here too. |
| `roster` | **`riders`**: {peer: `NetRoster.entry()`} | 2 Hz: `peer_id`, `name`, `slot_index`, `is_bot`, `raw_w`, `cadence_rpm`, `ftp_pct`, `rescue`, `afk`, `connected`, `status` (the latest `teammate_status`); the GameHost's roster adds `phase` (the host's phase index for that rider, -1 before the start), which each client checks against its own. Build with `NetRoster.build()`, send with `WlNetSession.send_roster()`. |
| `results` | **`results`**: `GameResults.to_dict()` | Ints: `results.rows[].xp`, `results.rows[].slot_index`. |
| `session_end` | **`reason`** | |
| `refused` | **`reason`**; `scope` (`"ready"` for a refused ready-up), `game_id`, `game_version` | `session_in_progress`, `room_full`, `version_mismatch` end the client's session; with `scope: "ready"` (`missing_game`, `version_mismatch`) only the ready-up is refused. Accepted on every schema version. |

### 2.3 Host to one client

| Type | Fields | Notes |
| --- | --- | --- |
| `plan` | **`plan`**: `EffortPlan.to_dict()`; `peer`; for a split plan `part`, `parts`, `plan_id` | At the start, after every `replan` and on every rejoin or resync; the client re-validates it before its governor uses it, and ignores a plan identical to the one it rides. A plan whose message would be over 16 384 bytes (an imported `.zwo` with more than about 120 blocks) goes as `parts` messages, each a `plan` with a slice of whole phases (the other plan fields repeated), numbered `part` 0.. under one `plan_id`; the client joins them in order once all are in (at most 64 parts; a newer `plan_id` drops older parts) and validates the whole. |
| `phase` | **`index`**, **`start_tick`**, **`ended_by`** (`duration`, `max_s`, `end_phase`, `finished`, `start`); `peer`, `elapsed_s` | On every phase change of that rider, and on rejoin or resync with `elapsed_s` (the host's time into the phase). A client that already rides that `index` from that `start_tick` only catches its phase clock up (no restarted ramp, no extra FIT lap); otherwise it enters the phase, at `elapsed_s` when its LocalRider can resume a phase there. |
| `directive` | **`kind`** (`request`, `course_grade`, `cadence_band`, `power_band`); `id` | `request`: the `EffortDirective.to_dict()` fields at the top level (`mode`, `target_pct`/`target_wkg`/`target_w`, `mode_grade`, `haptic`, `haptic_wind`, `crr`, `cw`, `duration_s`, `reason`, `source`). `course_grade`: `grade_pct`. `cadence_band`: `lo_rpm`, `hi_rpm` (0, 0 clears). `power_band`: `lo_w`, `hi_w` (0, 0 clears). |
| `hud` | **`kind`** (`toast`, `banner`), **`key`**; `args`, `seconds` | A toast or banner for that peer only. |
| `clock_pong` | **`t0`** (echoed), **`th`** (host platform time) | |

## 3. Int conversion

Godot's JSON parser returns every number as a float. `Protocol.decode()` (and `decode_game()`) turns them back:

1. `peer`, `host`, `from`, `to`, `seq`, `proto`, `max` and `v` at the top level of the envelope and of the game message.
2. Every key ending in `_id`, at any depth, when it holds a whole number (a string such as `game_id: "siege"` stays a string; `2.5` stays a float), except inside `tm.intents`.
3. The schema's int paths (`NetMessages.GAME[type].ints`, plus `settings.bot_ftp`, `settings.max_players` and `settings.min_players` of `lobby_state`). Paths are dotted; `[]` walks every array element, `{}` every dictionary value (`players[].slot_index`, `riders{}.slot_index`, `tm.acks[].id`).
4. The keys of dictionaries stored under `riders`, `player_options`, `ready_flags` and `trainers` become ints when they spell an integer, so `{"2": ...}` becomes `{2: ...}` (bots: `-1`). Keys that are not integers (option ids) stay strings. This does not apply inside a snapshot's `state` or an event's `events` (game payloads) or inside intents.
5. A `hud` message's `args` (an Array, or a Dictionary for `{name}` placeholders) get whole numbers back as ints, so a client's toast reads "2" where the host's read 2.

Games declare the ints of their own payloads with `GameModule.int_fields()`: `{"snapshot": [paths], "<event type>": [paths]}`. `Protocol.apply_int_fields(data, paths)` converts numeric leaves at matched paths (rounded) and leaves an Array or Dictionary found there unchanged, so Siege's `f: [[pad, [target_ids]]]` declares `f[][]` and `f[][][]` (OWNERSHIP 3.1 C10). `WlNetSession.set_game_int_fields(game.int_fields())` applies them to every received snapshot and event before `game_message`; applying them again is harmless. `Protocol.apply_game_int_fields()` also converts the platform's own events (`Protocol.PLATFORM_EVENT_INTS`: `phase_started` gets `peer`, `index`, `tick` and `start_tick`; its `peer_id` is an `_id` key), with or without game fields. No event type may be named `snapshot`, and games should not reuse `phase_started`. Intents are never converted.

Game option values (`lobby_state.settings.options`, `player_options`, `session_start.options` and `players[].options`) are not converted: an `int` option arrives as a float. The GameHost should pass them through `GameRegistry.resolve_options()` on every peer, host included, so all peers see the same types.

Round trips are exact: a message built with ints where these rules make ints, and floats elsewhere, comes back identical through `JSON.stringify` + `JSON.parse_string` + `decode_game`, and through `encode` + `decode` (tested for every message type in `tests/net/test_protocol.gd`). `encode()` keeps insertion order and writes floats at full precision. Godot's own parser is not correctly rounded for long decimals, so a float with many significant digits can differ in its last bit after a round trip; values such as `0.5`, `187.25` or `0.7` come back exactly.

## 4. Versioning

- The relay checks `hello.proto` (`Wl.PROTO`).
- Every game message carries `v` = `NetMessages.VERSION`. A message with another `v` is dropped (`Protocol.last_error == "version_mismatch"`) and the transport emits `protocol_mismatch(from)`. The host answers a client on another version with `refused {reason: "version_mismatch"}`; a client that gets a host message on another version refuses itself. Either way the player sees `NET_REFUSED_VERSION_MISMATCH`.
- `refused` is readable on every version.
- Each game's version is checked in the lobby: `player_info.games[game_id]` must equal `lobby_state.game_version`, or the client can't ready up (`ready_refused` with `NET_READY_MISSING_GAME` or `NET_READY_VERSION_MISMATCH`).
- A change to a message's required fields or meaning bumps `NetMessages.VERSION`; adding an optional field does not.

## 5. Session behaviour (`WlNetSession`)

- **Roles.** `host_room(max_peers = 8, preferred_code = "")` makes this peer the host (peer 1); `join_room(code)` a client; `start_offline()` the SOLO lobby with no transport (the local rider is peer 1). Lobby settings made before `host_room()` (game, scaling, options) carry over. `leave()`, a refusal, the session's end and `start_offline()` also cancel a create, join or rejoin still in flight: its late answer never puts the session back in a room.
- **Code reclaim (P1, BRIEF 5.2).** `host_room(max_peers, preferred_code)` sends the code (any spelling `RoomCode.normalize()` accepts; an invalid one is ignored) in `create`. The relay grants it when no open room has it and hands out a new code otherwise; `room_code` is always the code granted. If a relay refuses the create itself (`bad_request`, `room_full`, `room_not_found` or `code_taken`: a relay that does not know the field), the session asks once more without the code (`push_warning`), so the code never stops a host from hosting; a refused plain create ends with `refused(code)` as before. `host_room_reclaim(max_peers)` is `host_room(max_peers, last_hosted_code())`.
- **Lobby.** The host's lobby is the only truth; clients receive it as `lobby_state`. Slots follow join order (a dropped peer that comes back before the start keeps its place), then bots (`Bot n`, peer `-n`, the lobby's bot FTP, verified, Autopilot). `set_game_manifest()` (or the game registry: `registry`, default the GameRegistry autoload) gives `min_players`, `max_players`, `bots` and the option defaults. Humans beyond `max_players` are refused with `room_full` (on `peer_joined` and on `player_info`); bots make room for humans. Changing the game resets every client's ready flag. `all_ready()` needs every connected human ready with the game at the host's version and a player count within the game's limits.
- **Start.** `mark_started()` freezes the slots. A peer that joins afterwards without a valid token, or never sent `player_info`, gets `refused {reason: "session_in_progress"}` and leaves; the host never lists it.
- **Host reclaim.** When the host gets peer 1 back after a drop it reconciles with `joined.peers`: a session peer it still counted as connected but the relay no longer lists gets `peer_left(peer, "dropped")` (the GameHost marks it AFK and stops counting its last power), a listed peer it did not know gets `peer_joined` (and, after the start, `rejoin_requested`), and every other connected session peer gets `resync_requested(peer)`, on which the GameHost resends that rider's plan, phase, snapshot and bands. Clients see `peer_left(1)` and then `peer_joined(1)`; on the latter a client re-sends its `player_info` (and its ready-up before the start), since what it sent while the host was away is lost.
- **Drops and rejoins.** A dropped client (or host) re-joins with its token: at once, then after 1, 2, 4, 8 and every 15 s, until 120 s have passed (`state` "reconnecting"; with `auto_reconnect` off it waits for `rejoin()`). A rejoin attempt that fails to connect or is `rate_limited` is retried at the next step; any other relay error ends the session with that refusal. The `NetSession` autoload saves the token to `Paths.reconnect_token_path()` on every `created`/`joined`, so a restarted client with the same profile dir and `--join=<code>` comes back as the same peer. Private instances (tests, in-process simulations) keep it in memory unless `persist_token` is on, with their own `token_path`. After the start, a returning peer gets `lobby_state` and the host emits `rejoin_requested(peer)`, on which the GameHost sends its `session_start`, `plan`, `phase` (with `elapsed_s`), the latest snapshot, its power and cadence bands and the results if they exist. After 120 s the client ends with `refused("dropped")`; its GameHost then rides the plan's cool-down locally and ends the session with that reason (section "Staying in step").
- **Ending.** `host_left` ends every client gracefully: `refused("host_left")`, `EventBus.session_refused("host_left")`, state "offline", token forgotten. Host migration is P2.
- **Routing.** `send_to_host`, `send_to(peer)` and `broadcast` (host only). Clients may only send `player_info`, `ready`, `telemetry` and `clock_ping`, and only to the host; the host ignores other types from clients and clients ignore those four from the host. A message to the local peer is delivered locally on the next poll (through JSON). Invalid outgoing messages are refused with `push_error`.
- **Size.** Nothing over 16 384 bytes (the whole envelope) is sent: it is dropped with `push_warning` and counted in `stats.oversize_dropped` and, for snapshots, `stats.oversize_snapshots` (OWNERSHIP C9). The GameHost splits a long `plan` itself (2.3), and Workout sends a long timeline in parts over consecutive snapshots.
- **Send budget.** Every frame a session sends spends a token from a bucket that refills at `send_budget_per_s` (50) up to `send_burst` (100), under the relay's 60 frames a second and burst 120, so the relay never rate-limits a peer. Frames wait in one queue in send order while the bucket is empty. A replaceable frame (a snapshot or roster per recipient, a `lobby_state`, a coalesced `course_grade`/`cadence_band`/`power_band` per peer and kind) that is still queued when a newer one of its kind arrives is dropped and the newer one goes to the back of the queue (`stats.superseded`), so a snapshot never overtakes the events sent before it. Under sustained overload a frame replaced every time before it reaches the front would never go out (W4: clients got no snapshot while the load lasted), so once the queued frame's chain of replacements is `SUPERSEDE_MAX_S` (0.5 s) old it stays where it is and the newer one queues behind it, where later ones keep replacing it: at most two frames of a kind wait, each kind still goes out about once per queue drain, and the newest always arrives. Every other frame (`request`, `phase`, `plan`, `event`, `telemetry`, ...) is sent, in order, never dropped. A peer that leaves loses its queued frames, and a dropped socket empties the queue (`stats.dropped_offline`). `queued_frames()` and `stats.queued_max` show the backlog; `send_budget_per_s = 0` turns the budget off.
- **Coalescing.** `directive` messages of kind `course_grade`, `cadence_band` and `power_band` to one peer go out at most once per 100 ms per kind, at any poll rate; the latest one wins and any pending one is flushed when its 100 ms are up or before another message to that peer, so `request` and `phase` are never dropped or reordered (OWNERSHIP C11). Only while a private session's clock stands still (polled without `tick()` after a `set_time()`) does a pending one go out three polls (`FROZEN_CLOCK_POLLS`) after it started waiting; the autoload never does this, since its clock moves in `_process` and several polls in one frame share one time.
- **Staying in step (GameHost).** A client warns `push_warning("GameHost: desync: ...")` (counted in `GameHost.desync_count`, the run report's `desync_warnings`, and the scripted peer's report through `AppLogWatch`, which the e2e check reads) when an event batch's `seq` skips one, or when two rosters in a row show another phase index for its rider than the one it rides; it then asks for a resync (`telemetry.resync`). The first gap after its own rejoin or after the host's return is expected and is no desync. Snapshot `seq` gaps are not checked: a snapshot carries the whole state and the send budget drops superseded ones. A client whose net session ends for good (any `refused`: `host_left`, `dropped` after the 120 s window, `room_not_found`, ...) rides its plan's cool-down locally, then ends the session with that reason and emits `session_finished(null)`.
- **Clock.** `clock_ping`/`clock_pong` give the client `clock_offset` (the sample with the smallest round trip of the last 8); `host_time()` is the estimated host platform time.
- **Snapshots.** Clients keep the last `snapshot_buffer_size` (8) snapshots: `latest_snapshot()`, `snapshot_at(t)` and `snapshot_pair_at(t)` (`{from, to, alpha}` for 100 ms interpolation at `host_time() - 0.1`). The buffer is cleared on `session_start`, whenever `lobby_state.started` changes and on every (re)join, so the host's latest snapshot after a rejoin is applied whatever its `seq`.
- **Time.** `tick(dt)` advances the session's platform time and polls; the GameHost calls it once per platform step (or `set_time()` plus `poll()`). If a session is only ever polled, each poll counts as one 0.05 s step. The `NetSession` autoload ticks itself from `_process` with the wall-clock delta (`auto_poll`); `tick()` from elsewhere then only polls.

## 6. Budget

A 4-rider session with 10 Hz snapshots, 10 Hz event batches, a 2 Hz roster and per-client directives (2 Hz requests, 2 Hz `course_grade`, 2 Hz `cadence_band`, 1 Hz `power_band`) sends about 43 frames a second from the host; clients send 5 Hz telemetry plus clock pings. `tests/net/test_net_session.gd` runs that load for 30 s against the relay's limits and asserts no `rate_limited`.

The same load with 8 riders is about 71 frames a second (22 broadcasts plus 7 per client), over the relay's 60. The send budget (section 5) keeps the host at 50: requests, phases and event batches all arrive in order, and snapshots, rosters and coalesced directives arrive less often (each about once a second, never ahead of the events sent before them). `tests/net/test_net_budget.gd` runs it for 30 s against the relay's limits: no `rate_limited`, every request and phase delivered in order, every event batch, the newest snapshot, and snapshots, rosters and `course_grade` reaching each client at least every 1.5 s while the load lasts, with a backlog that stops growing. A game for 8 riders should still keep its own per-rider directives at about 2 a second, or its snapshots thin out.

## 7. Transports

| Class | Use |
| --- | --- |
| `RelayTransport` | `WebSocketPeer` to the relay. URL: `--relay=<ws url>`, else `Settings.relay_url()`, else `ws://localhost:8787/v1`; `wss://` uses `TLSOptions.client()`. 10 s connect timeout, 15 s pings, a drop after 45 s without any frame. After `leave` the socket lingers 250 ms so the relay reads the leave first. |
| `LoopbackTransport` + `LoopbackHub` | In-process relay for tests and `run_game_sim` HOST runs: `RelayRooms` semantics, frames through JSON, delivery in each transport's `poll()` in order, deterministic codes and tokens. Fault injection: `simulate_drop()` (frames in flight are lost; `disconnected("dropped")` in a room, `disconnected("error")` while a create or join is in flight), `drop(peer)` (any peer of this transport's room), `LoopbackHub.drop_peer(code, peer)`, `latency_ticks`; `enforce_limits(true)` with `advance(dt)` turns on the rate limit and idle timeout. |
| `LocalRelayServer` | The relay protocol served by Godot itself (`TCPServer` + `WebSocketPeer` + `RelayRooms`), for LAN play and the RelayTransport tests. |
| `LanTransport` (P1) | LAN play without the internet relay: see section 8. |

All transports run with `PROCESS_MODE_ALWAYS` and do their I/O in `poll()`, which the owning `WlNetSession` calls.

## 8. LAN play (P1)

`LanTransport` (a `RelayTransport`) plays on a local network without the internet relay:

- **Host.** `host()` starts a `LocalRelayServer` on TCP port 8790 (`port`; every interface), joins it over `ws://127.0.0.1:8790/v1` as peer 1, and once the room exists broadcasts a beacon every second to UDP 255.255.255.255:8791 (`discovery_address`, `discovery_port`).
- **Beacon.** One datagram of JSON: `{"wattlands": "lan", "proto": 1, "code": "K7QX2M", "port": 8790, "name": "<host name>", "build": "0.1.0", "game": "workout"}`. `game` (the lobby's game id, from `LanTransport.game_id`, which `WlNetSession` keeps at its lobby's game) is optional; a beacon without it parses with `game_id` "". Receivers take the host's address from the datagram, never from the payload, and ignore beacons of another `proto` (`LanDiscovery.parse_beacon`).
- **Client.** `join(code)` listens on UDP 8791 (`LanDiscovery`) until it hears that code (at most 5 s, else `disconnected("room_not_found")`), then joins `ws://<sender>:<port>/v1` like any relay. With `url` set it connects straight to that host. A rejoin after a drop reuses the address it found.
- `LanTransport.lan_rooms()` lists the rooms heard so far (`{code: {code, ip, port, name, build, game_id, seen}}`; a room not heard for 5 s is forgotten).
- **The join page's list (`WlNetSession`).** `lan_rooms() -> Array[Dictionary]` returns `[{code, name, game_id, address, port, build}]` sorted by code. The first call listens for beacons on UDP `lan_discovery_port` (8791) at `lan_discovery_bind` ("*"); a bind failure gives `push_warning` and an empty list (no retry until `stop_lan_discovery()`). Each `poll()` hears more beacons, forgets rooms silent for 5 s of wall time (`lan_time_func` in tests) and emits `lan_rooms_changed(rooms)` when the list changes. `join_lan(room)` connects a `LanTransport` straight to `ws://<address>:<port>/v1` and joins by the room's code, like `join_room()`; a room without a code, address or port is refused as `room_not_found`. The transport used before (the relay) comes back with the next `host_room()`, `join_room()` or `start_offline()`; those, `join_lan()` and `stop_lan_discovery()` stop listening, so a later join by code can bind the discovery port itself.
- Everything else (codes, tokens, limits, lobby, reconnect) is the relay protocol above. Windows asks once to allow the game through the firewall when a LAN host first listens.

## 9. Files

| File | Content |
| --- | --- |
| `Paths.reconnect_token_path()` (`reconnect_token.json`) | `{code, token, peer, role}` of the current room; removed on leave, refusal and session end. |
| `Paths.recent_rooms_path()` (`recent_rooms.json`) | `[{code, role}]`, newest first, at most 10 (P1: `host_room_reclaim()` and the lobby's `host_room(max, code)` ask for the last hosted code). |
