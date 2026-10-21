# sdk-runtime decisions

Short ADRs for `addons/wattlands/sdk/` (WlGameRegistry, PlanValidator, GameHost, DirectiveRouter, HudRouter, IntentRouter, PhaseTracker, SessionStatsTracker, ReportCollector, SdkConformance, GameSimRunner) and `tests/sdk/`. "BRIEF x.y" is `docs/BRIEF.md`; C-numbers are `docs/OWNERSHIP.md` 3.1.

## 2026-10-21: A host-side refusal refuses the whole directive

- Decision: `DirectiveRouter.request` runs its checks in a fixed order (unknown peer, no phase, cool-down, bad fields, `erg_in_sim_phase`, `outside_range_pct`, SIM-block length, `sim_block_unsafe`, `switch_spacing`, `mode_grade_outside_sim`, `haptic_in_erg`, `haptics_off`) and refuses the whole request on the first failure, with `push_warning`, an `EventBus.directive_applied` record `{refused: true, reason, by: "host"}` and a report entry. Every request gets an id, refused ones too, so the report can join requested and applied records. An ERG target in a SIM phase is refused as `outside_range_pct` (a SIM phase has no ERG range).
- Alternatives: drop only the offending channel and apply the rest.
- Reason: a partial apply hides game bugs (C25's argument); BRIEF 3.6 says "the DirectiveSink refuses anything else". The governor still drops single channels where BRIEF 4.6.6 says so (haptics in warm-up, cooldown).

## 2026-10-21: The host tracks every rider's ERG<->SIM switches in game ticks

- Decision: `PhaseTracker` follows each rider's effective mode (the phase mode, or SIM during a directive block) and records the game tick of every change: plan phase changes between ERG and SIM, a block's entry, its expiry, and an early exit by a `mode: "ERG"` request. A new SIM block needs 30 s of game time since that tick. The block's own exit is never checked (the bracketing pair, BRIEF 4.5), but it counts for the next block. Block expiry rounds to whole ticks.
- Alternatives: platform time; ask the rider's governor.
- Reason: the host must decide synchronously (`DirectiveResult`), remote governors answer 0.2 s later, and directive expiry already counts game time (paused time can't create a switch).

## 2026-10-21: course_grade coalescing

- Decision: the first `course_grade` for a rider goes out at once; later ones go out at most every 10 ticks (0.5 s of game time), always the newest value; a value still pending when the rider's phase changes is dropped. Each delivered value gets an id and a report entry (calls coalesced away are not recorded).
- Alternatives: forward every call and let NetSession thin them; a fixed 2 Hz clock.
- Reason: BRIEF 3.6 "coalesced to 2 Hz"; holding a grade across a phase boundary would apply it to the wrong phase.

## 2026-10-21: Platform events ride in the game event batches

- Decision: the host's `event {seq, events}` batches carry game events and platform events whose `type` starts with `wl.` (`wl.phase_started {peer, index, ended_by}`, `wl.lap_marker {label}`, `wl.finished {reason}`). Clients handle `wl.` events themselves (EventBus.phase_started for other riders, LocalRider.lap, game_finished) and never pass them to `apply_event`. Game event types starting with `wl.` (and `snapshot`) are refused with a warning. Batches flush every second platform tick (10 Hz), before that tick's snapshot.
- Alternatives: separate messages per platform event.
- Reason: BRIEF 3.6 says phase changes go "in an event"; one ordered stream keeps every peer's event order identical and within 10 messages a second (C12).

## 2026-10-21: Session wire formats

- Decision: `session_start {game_id, game_version, content_id, seed, players: [PlayerSlot.to_dict()], options, scaling, start_tick, session_id, content_overrides}`; `plan {peer, plan}`; `phase {peer, index, start_tick, ended_by}`; `directive {kind: request, id, peer, directive: {...}}`, `{kind: course_grade, id, peer, grade_pct}`, `{kind: cadence_band, id, peer, lo_rpm, hi_rpm}`, `{kind: power_band, peer, lo_w, hi_w}`; `snapshot {game_id, seq, tick, state}`; `roster {riders: {peer: {raw_w, cadence_rpm, ftp_pct, rescue, afk, connected, status, name, slot_index}}}`; `hud {kind, key, args, seconds}`; `results {results}`; `session_end {reason}`; `telemetry {tm}`. The GameHost casts every number it reads and converts peer-keyed dictionary keys itself, so it works whether or not `Protocol.decode` already did.
- Alternatives: flatten the directive fields into the message.
- Reason: `EffortDirective.to_dict()` keeps exactly the game's keys; nesting avoids a clash between the message `id` and the directive's own fields.

## 2026-10-21: Plans are validated at their worst case per phase

- Decision: a phase whose ERG peak (`PlanPhase.peak_pct()`: target, ramp end, range top) is above 105% (120%) accrues its whole worst-case length (open-ended: `max_s`); a reset run counts best-case lengths (open-ended: `min_s`) of consecutive ERG phases whose peak is <= 90%; SIM phases restart the run. Warm-up checks every ERG value of each phase that starts inside the first 300 s (best-case starts). The mode-switch warning includes the switch into the cool-down. Thresholds are inclusive where BRIEF 4.6.1 says so.
- Alternatives: integrate the ramp exactly.
- Reason: directives may hold the target anywhere in the effective range for the whole phase, so only the worst case is safe (BRIEF 4.6 outranks gameplay).

## 2026-10-21: replan swaps at the next phase change

- Decision: `ctx.directives.replan(peer, plan)` validates phases 0..current of the current plan plus the new phases as one plan, finalizes it and keeps it pending; the swap happens at the rider's next phase change, where the rider gets `set_plan` (local) or a `plan` message followed by its `phase` message (remote).
- Alternatives: apply at once and restart the current phase.
- Reason: `SafetyGovernor.set_plan` resets channel state; swapping mid-phase would restart ramps and elapsed time. Games replan between phases (BRIEF 3.6).

## 2026-10-21: Local HUD drawing goes through the session's EventBus

- Decision: HudRouter "draws locally" by emitting this peer's WlEventBus HUD signals (`power_band_changed`, `roster_changed`, `toast_requested`, `banner_requested`, `readout_changed`), which HudLayer reads. The GameHost does not use `HudLayer.local_feed()`. The host's bus carries every rider's power and cadence band; a client's bus carries its own.
- Alternatives: wrap `HudLayer.local_feed()`.
- Reason: HudLayer's contract says it reads the bus; going through both would draw twice. Headless runs need no HudLayer at all.

## 2026-10-21: Gestures come from the LocalRider, actions from the InputRouter

- Decision: every tick the GameHost drains `LocalRider.take_gestures()` (for `local_intents`, `Telemetry.gestures` and the frame) and `InputRouter.take_actions()` (or `inject_action()`); the router's own gesture queue is drained and ignored. `pause` and `panic` are consumed (SOLO pause toggle, `LocalRider.panic()`); `shift_up`/`shift_down` also call `LocalRider.shift()` and still reach the game. When rendering, the GameHost attaches its rider to the InputRouter (`attach_rider`) for menus and detaches it at the end.
- Alternatives: gestures from the router.
- Reason: one source per input, so no gesture arrives twice (C14, GM8).

## 2026-10-21: GameSimRunner isolation and paths

- Decision: a run moves `Paths`' process-wide override to a fresh temp root for its duration (every human slot's progress under `slotN/games/<id>/`, the recorders' rides) and `cleanup()` restores the caller's override and deletes the root. FIT files go to `<report dir>/fit/<report stem>_slot<n>.fit` (the GameHost moves `LocalRider.finish_ride()`'s file and its JSON summary there right after saving, so slots never collide), or `<temp root>/fit/sim_slot<n>.fit` without a report. Relative `--report` and `--override` paths resolve against the project folder (the repo root, where the tools run).
- Alternatives: a `rides_dir` option on LocalRider (a frozen API owned by platform).
- Reason: C28 and SIM7 (the user's profile is never touched) without changing another module's API.

## 2026-10-21: Report schema 1 and the deterministic hash

- Decision: `build_report()` returns `schema, args, game_id, content_id, role, seed, slots, plans, plan_warnings, overrides, end_reason, finished_reason, sim_seconds, game_seconds, max_sim_seconds, events, phases, directives, directives_unmatched, trace, snapshots, max_snapshot_bytes, oversize_snapshots, results, unlocks, clients, fit_paths, meta, deterministic_hash`. `t` is platform seconds in trace rows and `game_t` game seconds; events carry `t` (game) and `pt` (platform); phase `start`/`end` are game seconds. `deterministic_hash` is the sha256 of `JSON.stringify(report, "", true)` without `fit_paths`, `meta`, the hash, and the args `report`, `override_path`, `screenshot_dir`, `at`, `headless`, `sim_speed`.
- Alternatives: hash only events and results.
- Reason: SIM4/SIM5; the games' `check_sims.mjs` read these keys, and the FIT stamp and paths vary between machines.

## 2026-10-21: Generic time in band uses the eligible time as denominator

- Decision: `SessionStatsTracker` counts ERG seconds with a positive applied target and SIM seconds with a published power band as eligible; `time_in_band_pct` is in-band seconds over eligible seconds. Best 1/5/20-minute power is 0 for a ride shorter than the window; NP below 30 s is the average power. Samples come once per game tick from the frame telemetry (paused time is not ridden time).
- Alternatives: divide by the whole ride.
- Reason: SIM without a band has no target to be in; games with their own definition override the rows (BRIEF 3.7).

## 2026-10-21: Clients type their options from the manifest

- Decision: a client resolves `session_start`'s `options` and every slot's `options` through the game's manifest (`WlGameRegistry.resolve_option_values`), so an `int` option is an int on every peer even though JSON delivered a float.
- Alternatives: declare option paths for Protocol's int conversion.
- Reason: CTX8/PS14 require identical ctx values on host and clients.

## 2026-10-21: Results identity and apply_progress once

- Decision: `GameResults.session_id` is `"<game>/<content>/<seed>"` (deterministic for reports); each GameHost applies progress once per session id, so a duplicated `results` message never adds XP twice; a restarted client is a new GameHost and applies it once (C33).
- Alternatives: a random session id.
- Reason: determinism of reports and of the conformance hashes.

## 2026-10-21: Conformance identifies games in log lines

- Decision: `tests/sdk/test_conformance.gd` runs `SdkConformance.check_game` for `_template` and every registered game inside fixed test functions and prints `conformance: <id> ok|FAILED` per game, with the id in every assertion message. Rider counts are min_players and max_players; with `bots` true that is one human slot plus bots (SOLO), otherwise Autopilot human slots (HOST). Plan validation runs for every content id; the 2-minute runs use `default_content` with seed 4242.
- Alternatives: GUT parameterized tests.
- Reason: GDScript test names can't be generated per game, and GUT's parameter names don't carry the id (TL8 asks for the id in the log).

## 2026-10-21: Registry additions for fixtures and tools

- Decision: additive WlGameRegistry API: `content_root`/`assets_root` (tests point them at fixtures), `scan_on_ready`, `clear()`, `add_game(m, folder, allow_template)`, `template_manifest()`, `warnings(id)`, `game_dir/content_dir/assets_dir(id)`, `check_option_values()` (tools exit naming the field), and statics `pick_first_run`, `resolve_option_values`, `validate_option_entries`, `coerce_option_value`, `instantiate_manifest`, `normalized`, `parse_json`, `json_equal`, `is_whole`. Fixture games live under `tests/fixtures/games/` (never under `src/games`), all using one fixture GameModule script.
- Alternatives: fixture games under `src/games`.
- Reason: the real registry must never list test games; first-run tests must not depend on which games are installed (B7.1).

## 2026-10-21: W1 test doubles; the real stack runs in W2

- Decision: W1 tests drive the GameHost with `tests/sdk/helpers/fake_rider.gd` (a LocalRider subclass with a real MockTrainer) and `fake_net.gd`/`fake_net_hub.gd` (a WlNetSession subclass that sends every message through JSON). GameSimRunner takes `rider_factory` and `net_factory` args for them. `tests/sdk/integration/` runs GameSimRunner and SdkConformance over the real LocalRider, governor, NetSession, LoopbackTransport and Protocol; the W1 test command leaves that folder out (no `-ginclude_subdirs`), the full suite includes it.
- Alternatives: wait for W2 to test the GameHost.
- Reason: LocalRider, WlNetSession, LoopbackTransport and Protocol are W0 stubs in this worktree.

## 2026-10-21: Rendering sessions take the local rider's gestures from the InputRouter (supersedes "Gestures come from the LocalRider")

- Decision: when the GameHost renders (not headless) and has an InputRouter, the local rider's gestures for `local_intents`, `Telemetry.gestures` and the frame come from `InputRouter.take_gestures()`, which merges the attached rider's pedal gestures (BRIEF 3.5, `WlInputRouter.attach_rider`); the GameHost then leaves the LocalRider's own gesture queue to the router. Headless sessions read `LocalRider.take_gestures()` and drain and ignore a router's queue. Bots' gestures always come from their LocalRiders. Actions always come from `InputRouter.take_actions()` plus `inject_action()`.
- Alternatives: the LocalRider's queue in every mode (the earlier ADR).
- Reason: the frozen InputRouter contract makes it the merged source for menus and sessions; if the router collects the rider's gestures by pulling `take_gestures()` itself, a GameHost that also pulled them would race it and lose them. One source per mode, so no gesture arrives twice (GM8, C14).

## 2026-10-21: The platform completes the results rows

- Decision: after `game.results()` the GameHost calls `complete_rows()`: every rider in `ctx.players` gets a row (the SessionStatsTracker's base row for a rider the game left out, appended after the game's rows), and every row gets the base keys the game did not set. Values the game set are never changed.
- Alternatives: trust the game to start from `GameResults.from_stats`.
- Reason: BRIEF 3.6 promises per-player rows with kJ, %FTP and time in band; the default `GameModule.results()` returns no rows, and the results screen and conformance need one per rider.

## 2026-10-21: Translations are reference-counted across registry instances

- Decision: `WlGameRegistry` counts how many instances registered each Translation (the resource cache hands every instance the same object) and removes it from the TranslationServer only when the last one clears.
- Alternatives: never remove translations.
- Reason: the conformance test and other tests scan with private registries; clearing one removed the strings the GameRegistry autoload still served (CTX13).

## 2026-10-21: Rejoin and stale telemetry

- Decision: a dropped peer's stored telemetry is zeroed (power, cadence, speed, P_eff), so after a rejoin the rider shows 0 W and AFK until fresh telemetry shows pedaling. The rejoin `phase` message carries the phase's real `start_tick` and how it began (`ended_by` of the previous phase, `start` for phase 0); a client sets its phase clock from `start_tick` and each snapshot's `tick`, so a rejoined client's PhaseState matches the host's.
- Alternatives: keep the last values until new telemetry arrives; restart the client's phase clock at 0.
- Reason: IF6, NET6 and the HUD timeline after a rejoin.

## 2026-10-21: A SIM block the governor refuses is taken back

- Decision: when a rider's governor refuses a SIM block the host pre-approved (a local rider's returned record, or a remote rider's ack in `Telemetry.acks`), the host's PhaseTracker drops the block and restores the rider's mode and latest switch, while the block is still the running one.
- Alternatives: keep the host's view until the block's nominal end.
- Reason: otherwise the host would accept `mode_grade` and haptics for a block that never ran and spend the 30 s switch spacing on it (BRIEF 4.5).

## 2026-10-21: session_start repeats its string ids without "_id"

- Decision: `session_start` also carries `game`, `content` and `session` (copies of `game_id`, `content_id`, `session_id`); clients read those first and fall back to the `_id` fields when they are strings.
- Alternatives: rely on Protocol.decode leaving string `*_id` values alone.
- Reason: `net_messages.gd` says decode converts every `*_id` key to int; a strict implementation would turn `"workout"` into a number and the client could not find its game. The contract clarification is requested; this keeps sessions working either way.

## 2026-10-21: A confirm that resumes a SOLO pause is the platform's

- Decision: when `confirm` resumes a paused SOLO session it is consumed; the game's `local_intents` never sees it. `pedal_start` that resumes still reaches the game as a gesture.
- Alternatives: pass it through.
- Reason: a rider pressing A to resume must not also buy, cast or pick in the game on the same tick.

## 2026-10-21 (W2): Loopback HOST runs wait for every client's player_info

- Decision: `GameSimRunner` starts a HOST run (`WlNetSession.mark_started()`) only once the host's lobby lists every human rider, i.e. after each loopback client's `player_info` has arrived.
- Alternatives: start as soon as each client has a peer id (W1); have NetSession admit any connected peer at the start.
- Reason: `mark_started()` fixes the session's players from the lobby, which lists a peer only after its `player_info`; the last client was still in flight, got `session_in_progress` and never rode, so the host's roster showed it at 0 W (qa W1) and HOST runs never reached `complete`.

## 2026-10-21 (W2): A client GameHost takes the session_start that opened it from its config

- Decision: `GameHost.setup()` in the CLIENT role queues `config.session_start` (the message the app shell received before the GameHost existed) and applies it on the first `step()`, before any later message; a copy that arrives again on the net is ignored because the client configures once. The GameHost keeps connecting to `config.net.game_message` in `setup()`, so `plan` and `phase`, sent right after `session_start`, still reach it.
- Alternatives: have the app shell re-emit `session_start` after `start()`; add a resync request to the protocol.
- Reason: the app shell creates the client's GameHost inside the `game_message` emission of `session_start`, so the GameHost never saw it and stayed in `setup` (qa's real e2e run: both clients stayed in the lobby). `tests/sdk/integration/test_client_session_start.gd` reproduces the app shell's start and failed before this change.

## 2026-10-21 (W2): The session screen owns pausing

- Decision: the GameHost drops the InputRouter's `pause` action, and its `confirm` while paused, instead of toggling pause on them; `inject_action(&"pause")` and an injected `confirm` still pause and resume (tools, tests, on-screen buttons). A user pause ends only through `resume()`, an injected `pause` or `confirm`; a coasting or `stop_5s` pause also ends on `pedal_start`, the same rule the session screen applies.
- Alternatives: keep toggling on the router's `pause` (the screen and the GameHost then fight: the screen pauses and opens its menu, the GameHost resumes on the same press).
- Reason: app-shell's W1 request; the session screen calls `pause()` and `resume()` and runs the pause menu, whose confirm must not also resume the session or reach the game.

## 2026-10-21 (W2): Clients record phase_started for every rider

- Decision: a client's report events get a `phase_started` entry for every rider: its own from its `phase` message, the others from the host's `wl.phase_started` events (the bus already emitted both).
- Alternatives: only the client's own rider (W1).
- Reason: qa's e2e compares event sequences across peers and expects `phase_started` per rider on every peer.

## 2026-10-21 (W2): content_schemes admit content ids outside `contents`

- Decision: `game.json` may list `content_schemes` (lower-case scheme names, default `[]`). A content id `<scheme>:<value>` with a listed scheme and a non-empty value starts a session although it is not in `contents`; `WlGameRegistry.content_allowed(manifest, id)` is the one check (GameHost setup, `GameSimRunner --content`), the id reaches `ctx.content_id` unchanged on every peer through `session_start`, and the game validates the value when it loads the content. Workout lists `zwo` for `zwo:<absolute path>` (BRIEF 3.7 Workout Director).
- Alternatives: accept any id containing `:` for every game; let Workout list every possible file.
- Reason: game-workout's W1 request; an opt-in per game keeps a typo like `--content=eas:30` an error for every other game.

## 2026-10-21 (W2): The warm-up window of the PlanValidator is [0, 300) s

- Decision: the warm-up rule covers phases that start in the half-open window [0, 300) s (open-ended phases at `min_s`); a phase that starts at exactly 300 s is outside it. This was already the code (`starts[i] >= 300 - 1e-6` ends the scan) and `test_warmup_allows_65_exactly_and_work_from_300_s` covers it; the doc comment now says so.
- Alternatives: a closed window [0, 300], which would cap every Workout session's first work phase at 65 %.
- Reason: game-workout's W1 request (every Workout session but `e2e` starts its work at exactly 300 s); BRIEF 4.6.8's "first 5 minutes" end at 300 s, and the governor enforces its own run-time warm-up independently.
