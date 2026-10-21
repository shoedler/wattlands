# net-client decisions

## 2026-10-21: One relay core for the loopback hub and the LAN server

- Decision: `RelayRooms` implements the relay's room semantics (hello check, codes, ids, routing rules, tokens, held host rooms, limits) without sockets. `LoopbackHub` drives it in-process with JSON text frames; `LocalRelayServer` drives it over `TCPServer` + `WebSocketPeer`. `LoopbackTransport`, `RelayTransport` and `LanTransport` share the client side (`RelayClientTransport`: hello, create/join, error codes, signals).
- Alternatives: a loopback that only forwards dictionaries; a separate GDScript test server for the RelayTransport tests.
- Reason: tests and in-process simulations then see the relay's real behaviour (codes, `to: 0`, non-host routing, tokens, `peer_left` reasons) and the same JSON float/int effects as the network; one implementation to keep right. LoopbackTransport now extends RelayClientTransport (still a Transport); its public API is unchanged.

## 2026-10-21: Int conversion rules

- Decision: top-level `peer, host, from, to, seq, proto, max, v` and every `*_id` key become ints only when they hold a whole number; declared paths (schema and `int_fields()`) round any number; peer-keyed dictionaries convert only keys that spell an integer and never inside a snapshot's `state`, an event's `events` or `tm.intents`. `lobby_state.settings.bot_ftp/max_players/min_players` are converted too (requested as an additive NetMessages change).
- Alternatives: convert every number at those keys; convert peer keys everywhere.
- Reason: no data loss on unrelated fractional values; option ids under `player_options` stay strings; games keep their own payload keys as written; intents are cast by games (OWNERSHIP PR4).

## 2026-10-21: encode() writes insertion order at full precision

- Decision: `Protocol.encode()` is `JSON.stringify(msg, "", false, true)`.
- Alternatives: Godot's default (sorted keys, 14 significant digits).
- Reason: 14 digits loses information for ordinary floats; insertion order keeps dictionaries (rosters, lobbies) iterating the same on every peer. Godot's parser is still not correctly rounded for long decimals, so PROTOCOL.md promises exact round trips for ints and short decimals only.

## 2026-10-21: NetSession time comes from tick(dt), or one step per poll

- Decision: `tick(dt)` advances the session's platform time and polls; `set_time(t)` sets it; a session that is only polled counts each poll as `Wl.SIM_DT`. The autoload ticks from `_process`. Reconnect backoff, clock pings and coalescing use this time; only `RelayTransport`/`LocalRelayServer` timers (connect timeout, pings, silence, 250 ms linger) read the wall clock, with an injectable `time_func` for tests.
- Alternatives: wall clock everywhere; a SimClock reference in NetSession.
- Reason: in-process HOST simulations stay deterministic (OWNERSHIP C29) whatever the GameHost calls; real sockets are I/O and need real time.

## 2026-10-21: NetSession owns reconnect; transports report drops

- Decision: transports emit `disconnected("dropped")` and keep `room_code` and `reconnect_token`; `WlNetSession` re-joins at once, then after 1, 2, 4, 8 and every 15 s, and gives up after the token's 120 s with `refused("dropped")`. The token is saved to `Paths.reconnect_token_path()` on every `created`/`joined` (per-session `token_path` and `persist_token` for in-process peers, OWNERSHIP C28).
- Alternatives: automatic reconnect inside RelayTransport.
- Reason: one policy for every transport, testable over loopback; hosts reclaim peer 1 the same way.

## 2026-10-21: A refused ready-up is not a session refusal

- Decision: the host answers a `ready` from a client without the game, or with another version, with `refused {reason, scope: "ready", game_id, game_version}`; the client emits `ready_refused(reason, message)` and stays in the lobby. Clients also check locally (`ready_block_reason()`) and never send such a ready. Game versions compare as strings (whole floats as ints).
- Alternatives: a new message type (contract change); reusing `refused` without a scope (would end the session).
- Reason: BRIEF 5.5 wants a clear message without kicking the player; `refused` already exists in NetMessages.

## 2026-10-21: Schema version mismatches are refused both ways

- Decision: a game message with another `v` is dropped and reported (`protocol_mismatch`); the host refuses that client with `refused version_mismatch`, a client refuses itself on a host message with another `v`. `refused` is accepted on every version.
- Alternatives: silently drop mismatched messages.
- Reason: BRIEF 5.5 "show a clear error on mismatch"; the relay's `hello.proto` check does not cover the game-message schema.

## 2026-10-21: Lobby slots and drops

- Decision: slots follow join order, then bots. Before the start a dropped peer leaves the lobby but keeps its place in the join order if it comes back; an explicit leave forgets it. `mark_started()` freezes the slots; dropped riders stay with `connected: false`. Changing the game resets clients' ready flags (not the host's); changing content or options does not.
- Alternatives: re-slot on every rejoin; reset ready on every lobby change.
- Reason: stable looks for a flaky connection; scripted peers (e2e) re-ready only when the game changes.

## 2026-10-21: Coalesced directives are rate-limited per kind, flushed before other messages

- Decision: host `directive` messages of kind `course_grade`, `cadence_band`, `power_band` to one peer are sent at once unless one of the same kind went to that peer in the last 100 ms; then the latest waits and is sent when the window ends (or after two polls) or before any other message to that peer.
- Alternatives: batch everything per tick; no coalescing.
- Reason: OWNERSHIP C11 keeps the host under 60 frames a second without delaying the common 2 Hz case and without reordering `request` or `phase`.

## 2026-10-21: Game manifests from GameRegistry, overridable

- Decision: `set_game()` looks the manifest up in the `GameRegistry` autoload (duck-typed `manifest(id)`/`games()`) for `min_players`, `max_players`, `bots` and option defaults; `set_game_manifest()` registers one explicitly (tests, in-process runs). Player info without `games` gets the registry's `{id: version}`.
- Alternatives: change `set_game()`'s frozen signature; leave defaults to the app shell.
- Reason: the lobby needs the limits and defaults (OWNERSHIP REG4, PS14) and the frozen API has no place for them.

## 2026-10-21: Sockets linger 250 ms before closing

- Decision: after a leave (client) or a relay-initiated close (server) the WebSocket stays open 250 ms (wall clock) before `close()`, and both ends read every pending frame before handling a close.
- Alternatives: close at once.
- Reason: on Godot 4.7.2 a text frame sent right before `close()` never reaches the other side (measured with a probe); the relay would see a drop instead of a leave, and clients would miss the final `error`.
