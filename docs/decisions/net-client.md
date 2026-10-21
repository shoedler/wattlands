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

- Decision: transports emit `disconnected("dropped")` and keep `room_code` and `reconnect_token`; `WlNetSession` re-joins at once, then after 1, 2, 4, 8 and every 15 s, and gives up after the token's 120 s with `refused("dropped")`. The autoload saves the token to `Paths.reconnect_token_path()` on every `created`/`joined`; private instances keep it in memory unless `persist_token` is on (with their own `token_path`), so in-process peers sharing one profile never pick up each other's token (OWNERSHIP C28).
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

- Decision: host `directive` messages of kind `course_grade`, `cadence_band`, `power_band` to one peer are sent at once unless one of the same kind went to that peer in the last 100 ms; then the latest waits and is sent when the window ends or before any other message to that peer. The window is measured on the session's clock, whatever the poll rate; only a private session whose clock stands still (polled without `tick()` after `set_time()`) releases a waiting directive three polls after it started waiting; the autoload, whose clock moves in `_process`, never does.
- Alternatives: batch everything per tick; no coalescing; a fixed two-poll window (the first W1 version: at 60-144 fps it let 20 or more a second through per kind, against C11).
- Reason: OWNERSHIP C11 keeps the host under 60 frames a second without delaying the common 2 Hz case and without reordering `request` or `phase`.

## 2026-10-21: Game manifests from GameRegistry, overridable

- Decision: `set_game()` looks the manifest up in the game registry (`WlNetSession.registry`, default the `GameRegistry` autoload; duck-typed `manifest(id)`/`games()`) for `min_players`, `max_players`, `bots` and option defaults; `set_game_manifest()` registers one explicitly (tests, in-process runs). Player info without `games`, and `set_local_profile()` with empty `games`, get the registry's `{id: version}`.
- Alternatives: change `set_game()`'s frozen signature; leave defaults to the app shell.
- Reason: the lobby needs the limits and defaults (OWNERSHIP REG4, PS14) and the frozen API has no place for them.

## 2026-10-21: Sockets linger 250 ms before closing

- Decision: after a leave (client) or a relay-initiated close (server) the WebSocket stays open 250 ms (wall clock) before `close()`, and both ends read every pending frame before handling a close.
- Alternatives: close at once.
- Reason: on Godot 4.7.2 a text frame sent right before `close()` never reaches the other side (measured with a probe); the relay would see a drop instead of a leave, and clients would miss the final `error`.

## 2026-10-21: One reconnect token per peer in RelayRooms

- Decision: the in-process relay (`RelayRooms`, behind `LoopbackHub` and `LocalRelayServer`) keeps one token per peer while the peer is in the room and returns the same token on every rejoin; a join with that token supersedes a socket still open for the peer. Clients still save whatever token each `created`/`joined` returns.
- Alternatives: a fresh token on every join (the first W1 version).
- Reason: with rotation, a second drop during the rejoin handshake loses the new token with the answer, and the client comes back as a new peer (after the start: `session_in_progress`). BRIEF 5.3 says a token "stays valid for 120 s and keeps the same peer id"; clients that save the latest token work with either relay.

## 2026-10-21: Leaving cancels what is in flight

- Decision: `WlNetSession.leave()`, refusals, the session's end and `start_offline()` call the transport's `leave()` even before the room exists; `RelayClientTransport.leave()` then sends `leave` (harmless outside a room) and closes the socket, and late `created`/`joined` frames are ignored. A rejoin attempt that fails to connect or is `rate_limited` is retried at the next backoff step instead of ending the session.
- Alternatives: ignore stale `connected` events in NetSession only.
- Reason: a join answered after `leave()` used to put the session back in the room ("joined" after "offline"), and the host listed a rider who had left.

## 2026-10-21 (W2 round 2): host_room(max_peers, preferred_code) and the LAN room list

- Decision: `WlNetSession.host_room(max_peers := 8, preferred_code := "")` sends the preferred code in the relay's `create`; the relay grants it when free and a new code otherwise. A relay that refuses the coded create (`bad_request`, `room_full`, `room_not_found`, `code_taken`) gets one more create without the code (`push_warning`), so a code never stops a host. `host_room_reclaim()` is now `host_room(max, last_hosted_code())`. P1 LAN list for the join page: `lan_rooms() -> Array[Dictionary]` (`{code, name, game_id, address, port, build}`, sorted by code), `signal lan_rooms_changed(rooms)`, `join_lan(room)`, `stop_lan_discovery()`, `is_lan_discovering()`; beacons carry the optional `game` id. Staleness uses the wall clock (`lan_time_func` for tests): beacons are a 1 Hz real-time affair and a private session's poll-count clock runs at any speed.
- Alternatives: keep `host_room(max)` and have the lobby call `host_room_reclaim()` (the lead chose the two-argument form the lobby already calls); retry any failed create without the code (a socket error would then cost a second connect attempt); let `join_lan()` join by code through LanTransport's own discovery (a second listener on the same UDP port, and a 5 s wait for a room already heard).
- Reason: lead W2 round 2 and docs/DESIGN.md known difference 8 (P1 gaps). Both additions change what subclasses may declare: `tests/app/fakes/fake_net.gd` overrides `host_room(max_peers)` and `tests/app/fakes/fake_lan_net.gd` declares `lan_rooms_changed`, so both need a one-line change (requested from app-shell / the lead).

## 2026-10-21 (W4): A send budget under the relay's rate limit, replaceable frames give way

- Decision: every frame a `WlNetSession` sends spends a token of a bucket refilled at `send_budget_per_s` (50) up to `send_burst` (100). Frames wait in one FIFO queue while the bucket is empty. A snapshot or roster (per recipient), a `lobby_state` and a coalesced `course_grade`/`cadence_band`/`power_band` (per peer and kind) are replaceable: a newer one removes the queued older copy and joins the back of the queue (`stats.superseded`). Every other frame is sent in order and never dropped. A peer that leaves loses its queued frames; a dropped socket empties the queue.
- Alternatives: mirror the relay exactly (60/120: the relay's own pings and clock drift between the two clocks would still trip it); drop low-priority frames instead of queueing; a priority queue that sends requests ahead of older events (reorders the stream games see).
- Reason: W3 NET-4: at 8 riders the documented directive load is about 71 frames a second and the relay silently dropped `request` and `phase` frames. Superseding instead of reordering keeps "a snapshot never overtakes the events sent before it" and "request and phase are never dropped or reordered" (OWNERSHIP C11).

## 2026-10-21 (W4): A reclaiming host reconciles with joined.peers and resyncs who stayed

- Decision: `RelayRooms` (the in-process relay) now sends `joined.peers` and `joined.rejoin` like `server/relay`, and `RelayClientTransport` keeps them (`joined_peers`, `joined_peers_known`, `rejoined`). When the host reclaims peer 1 after a drop, a connected peer missing from `joined.peers` gets `peer_left(peer, "dropped")`, a listed peer it did not know gets `peer_joined` (and `rejoin_requested` after the start), and every other connected session peer gets the new signal `resync_requested(peer)`. A client re-sends `player_info` (and a wanted ready-up before the start) on `peer_joined` of the host.
- Alternatives: emit `rejoin_requested` for every peer (the GameHost would mark them as awaiting pedaling and resend `session_start`); queue messages while the host is away and flush them on reclaim (stale phases and events would arrive late and out of step).
- Reason: W3 NET-1: after a host drop nothing resent the phases it changed meanwhile, departed peers stayed "connected" with stale power, and a client that joined meanwhile never reached the lobby.

## 2026-10-21 (W4): WKG lobby_state hides every rider's p_eff_per_w from the other clients

- Decision: in a WKG lobby the `lobby_state` clients receive carries `p_eff_per_w` 1.0 (the 75 kg reference) for every human, the host's own included; the host keeps the real values in its own `lobby`. A client's `lobby_slots()` takes its own entry's value from its own `player_info`. FAIR_FTP (250 / FTP, and FTP is public in the lobby) and RAW (1) are sent as before.
- Alternatives: one personalised `lobby_state` per client (n frames for every lobby change, against the send budget); redact only riders who did not share their weight (needs a new lobby field; a shared weight is still nobody else's business in the lobby).
- Reason: W3 PROF-2 and BRIEF 3.2 ("weight never leaves the machine unless the player opts in; the host receives only what the selected scaling needs"): 75 / p gave every other client the exact weight. Clients never simulate other riders, so nothing on a client needs the value.

## 2026-10-21 (W4 round 2): A replaceable frame stops being replaced after 0.5 s, so it is never starved

- Decision: a queued replaceable frame is replaced (removed, the newer one joins the back) only while its chain of replacements is younger than `SUPERSEDE_MAX_S` (0.5 s) or an older kept frame of the same key already waits. Otherwise it stays where it is and the newer one queues behind it, so at most two frames of one key wait: the kept one, which goes out when it reaches the front, and the newest, which later ones keep replacing. A clock that went backwards counts as an old chain.
- Alternatives: replace the queued frame in place (fresher content, but the newer snapshot would overtake the events, and a newer coalesced directive the `phase`, queued after the old one's slot); keep the old one and drop the newer (the newest `lobby_state`, band or final snapshot would never arrive); a time limit alone, appending a new frame each time (with 23 replaceable keys under the 8-rider load the demand stayed over the budget and the queue grew without bound).
- Reason: W4r2 R11: under sustained overload every snapshot was replaced before it reached the front, so clients got none for as long as the load lasted (15 of 300 in the first 1.5 s, then a 28.5 s gap). With the rule each key goes out about once per queue drain (snapshots at most 1.35 s apart in `tests/net/test_net_budget.gd`), the backlog stays bounded (about two frames per key plus the never-dropped frames, which stay under the budget), nothing overtakes a frame queued before it, and the newest of each key still arrives.
