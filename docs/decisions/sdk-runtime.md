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
