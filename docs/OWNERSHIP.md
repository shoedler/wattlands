# Ownership and game-brief inventory

Section 1 says who owns each path today; `tools/gate check` enforces it from `tools/lib/gate_manifest.json`, which wins if the two differ.

**Sections 2-4 are the W0 inventory, kept for their IDs.** Written in W0 on 2026-10-21 from `docs/BRIEF.md`, the three game briefs and the W0 contracts and stubs; comments and docs across the repo cite those IDs (GM4, C36, SH2). Section 2 lists every SDK call, kit helper, tool flag and platform behaviour the game briefs cite, with what the game expected and the test that had to prove it. Section 3 lists where a game brief assumed something BRIEF or the frozen contracts didn't say, with a resolution. Section 4 is the flat name checklist of the W3 SDK-completeness review. The W1 agents named in their Owner columns have ended; read those names as history, and section 1 for who owns a path now. `docs/GAME_SDK.md` is the live contract.

How to read sections 2-4:

- "B x.y" is a BRIEF section; "S x.y", "T x.y" and "F x.y" are sections of the Siege, Tank and Fishing briefs ("S4 S10" is Siege section 4, scenario S10; "G0.2" is step 2 of a brief's G0).
- Where a row names several owners, the first wrote the test.
- Names in `code` existed in the W0 contracts or stubs unless marked **(add)**, an additive change to a frozen file that only the lead may make (collected in 3.2), or **(doc)**, behaviour `docs/GAME_SDK.md` must state in words (collected in 2.23).
- A row can be out of date with the games as they shipped: the inventory describes the briefs of W0.

## 1. Ownership

### 1.1 Paths

| Owner | Paths | CI |
| --- | --- | --- |
| Each game `<id>` (`fishing`, `siege`, `tank`, `workout`) | `src/games/<id>/`, `content/<id>/`, `assets/<id>/`, `tests/games/<id>/`, `.github/workflows/game-<id>.yml`, `docs/decisions/<id>.md`, `docs/credits.d/<id>.md`, `docs/changelog.d/<id>.md` | `game-<id>.yml` |
| Relay | `server/relay/` | `relay.yml` |
| Trainer bridge | `tools/trainer_bridge/`, `addons/wattlands/trainer/ble/` | `trainer-bridge.yml` |
| Lead (the platform) | Everything else: `addons/wattlands/`, `src/app/`, `src/games/_template/` and its counterparts, `content/strings/`, `server/mock_strava/`, `tools/`, `tests/` outside `tests/games/<id>/`, `docs/` | `lead.yml` (every gate) |
| Lead only, for every session | `README.md`, `CHANGELOG.md`, `CREDITS.md`, `CLAUDE.md`, `LICENSE`, `.gitignore`, `project.godot`, `gdlintrc`, `addons/gut/`, `addons/wattlands/contracts/` (frozen after W0, additive changes only), `tests/green_count_floor.txt`, `tests/pending_allowlist.txt`, `tools/lib/gut_gate.mjs`, `tools/lib/run_tests.mjs`, `tools/lib/gate*`, `tools/lib/safety_pins.json` | |
| Nobody | `docs/BRIEF.md`, `docs/games/`, `docs/concept/`, `docs/research.md`, `.gitattributes`, `.claude/settings.json` | |

A game session changes the platform only under the platform-change policy in `CLAUDE.md`: small, additive, tested, and committed alone with the prefix `platform:`. A run's other workstreams (audio, cleanup, docs, gate) are the `workstreams` of the manifest; no workstream may touch a path its `deny` lists, and `safety_pin_globs` lists the files the gate pins.

### 1.2 Shared folders

| Folder | Rule |
| --- | --- |
| `content/strings/<module>.csv` | Platform strings, one file per module, each registered in `project.godot`. Platform keys never start with `WORKOUT_`, `SIEGE_`, `TANK_`, `FISHING_` or `_TEMPLATE_`. |
| `docs/decisions/`, `docs/deps.d/`, `docs/credits.d/`, `docs/changelog.d/` | One `<agent or game id>.md` per owner. The lead merges them: changelog fragments are emptied at each release; decision fragments stay as the source. |
| `.github/workflows/` | Seven workflows: `lead.yml` runs every gate, `game-<id>.yml` per game (`tools/new_game` writes it), `relay.yml` builds the relay's Docker image, `trainer-bridge.yml` runs the Python bridge's tests. |

### 1.3 Frozen seams

Fixed in W0 and additive since. These are the APIs between platform modules that a change must keep: time (`SimClock`, `Wl.SIM_DT`); the rider stack (`LocalRider`, with the GameHost's riders private and forbidden under `src/games/`); the governor (`SafetyGovernor.configure/set_plan/start_phase/resume_phase/set_game_paused/apply_directive/set_course_grade/shift/tick/status`, `Wl.CLAMP_*`, `Wl.REFUSE_*`); the mock rider (`MockTrainer.from_spec/parse_spec/set_cadence_band/set_power_band/set_phase`); pixel layout (`PixelViewport`); the HUD feed (`HudFeed`, `HudSpec`, `HudLayer`, the `WlEventBus` HUD signals); the session runner (`GameSimRunner`); the recorder (`RideRecorderApi`, `SessionStats`); messages (`NetMessages`, `Protocol`); per-peer services (`WlEventBus` and `WlNetSession` instantiable per in-process peer); slot looks (`Wl.slot_look`); the pixel import preset (3.1 C36).

## 2. Game brief requirements

### 2.1 GameModule methods and signals

| # | Item | Cited by | What the games expect | Owner | Test that must cover it |
| --- | --- | --- | --- | --- | --- |
| GM1 | `class_name GameModule extends Node` (`addons/wattlands/contracts/game_module.gd`); games `extends GameModule` | S0.1, T0.1, F0.1 | Every method has a safe default, so a game overrides only what it uses; `game.json` `entry` names the subclass; `GameRegistry.instantiate(id)` returns it | lead, sdk-runtime | `tests/sdk/test_game_registry.gd`: instantiate `_template` and a fixture game |
| GM2 | `configure(ctx: GameContext)` | all | Once per peer per session, before any other call, on SOLO, HOST and CLIENT, with every field of 2.2 set | sdk-runtime | `tests/sdk/test_game_host_net.gd`: ctx fields on the host and two loopback clients |
| GM3 | `build_effort_plans() -> Dictionary` | S2.3, T2.3, F2.3 | Host/SOLO, after configure; `{peer_id: EffortPlan}` for every slot, bots (negative ids) included; each through `PlanValidator.finalize`; any rejection stops the start with the validator's errors (and `run_game_sim` exits non-zero naming them); each client gets its own as `plan` | sdk-runtime | `tests/sdk/test_game_host.gd`: bot plans present; a rejected plan blocks the start with its reason |
| GM4 | `sim_step(dt: float, frame: InputFrame)` | all | Host/SOLO only; `dt` is always `Wl.SIM_DT` of game time; not called while paused; keeps being called through the COOLDOWN phase (S2.8, T2.4, F2.4) | sdk-runtime | `test_game_host.gd`: dt constant; no calls while paused; calls continue in COOLDOWN |
| GM5 | `autopilot_intents(peer_id) -> Array` | S2.5, T2.5, F2.5 | Host/SOLO, every tick, only for bots and riders with `autopilot` true; appended after the rider's own intents in `frame.players[peer].intents`. Never called for an Autopilot-off human: each game runs its own zero-input fallback for them | sdk-runtime | `test_game_host.gd`: merge order; not called for Autopilot-off slots |
| GM6 | `on_rescue(peer_id, active: bool)` | S2.4, T2.4, F2.4 | Host/SOLO; once per transition, on the first tick the rider's `rescue` flag changes (remote riders up to 0.2 s later); `false` when the rescue hold ends (cadence ≥ 70 rpm for 3 s), which is when the governor's 10 s ramp-back starts (F2.4 resumes play 10 s after it) **(doc)** | sdk-runtime, trainer-control | `test_game_host.gd` with an `erg+cadence_drop` mock: one `true`, one `false` |
| GM7 | `on_afk(peer_id, afk: bool)` | S2.2, S2.4, T2.2, F2.4 | Host/SOLO; `true` at the multiplayer coasting AFK (B 4.6.4) and on `peer_left` in the same tick; `false` once fresh telemetry from that peer shows pedaling; once per transition. A SOLO coasting rider pauses instead | sdk-runtime, net-client | `test_game_host_net.gd`: drop → `on_afk(true)` that tick; rejoin plus pedaling → `false` |
| GM8 | `local_intents(actions: Array[StringName], gestures: Array[StringName]) -> Array` | T2.5, F2.5 | Every peer, every tick, local rider only. `actions` holds device actions (keys, buttons, sticks) since the last tick and is never synthesized from a gesture; `gestures` holds `pedal_start`, `surge`, `coast`, `stop_5s` since the last tick. A surge never also arrives as `confirm` (F2.5). `pause` and `panic` are consumed by the platform and never passed **(doc)**. Returned intents go the way of `ctx.intents.send` | sdk-runtime, ui-hud (`InputRouter.take_actions/take_gestures`) | `test_game_host.gd`: surge only in `gestures`; host intents in the next frame; client intents in `Telemetry.intents` |
| GM9 | `snapshot() -> Dictionary` | S2.6, T2.6, F2.6 | Host, every second tick (10 Hz), sent as `snapshot {game_id, seq, state}`; size and hash measured per 3.1 C9 | sdk-runtime, net-client | `tests/sdk/test_conformance.gd` round trip; `tests/sdk/test_sim_report.gd` |
| GM10 | `apply_snapshot(snapshot: Dictionary)` | S2.6, T2.6, F2.6 | Clients only; gets `state` after `Protocol.apply_int_fields(state, int_fields()["snapshot"])`; in `seq` order (older dropped); once right after a rejoin with the host's latest (S2.6 and F2.6 rely on full-state snapshots for reconnects) | net-client, sdk-runtime | `tests/net/test_protocol.gd`; rejoin case in `test_game_host_net.gd` |
| GM11 | `apply_event(event: Dictionary)` | S2.6, T2.6, F2.6 | Clients only, never on host or SOLO (S2.6 raises the host's own effects directly); each event once, in the host's emission order, identical on every client; a tick's events are applied before that tick's snapshot **(doc)** | sdk-runtime, net-client | `test_game_host_net.gd`: same order on two clients; never called on the host |
| GM12 | `client_predict(dt: float, local: Telemetry)` | S2.6, T2.6, F2.6 | Clients only, every 0.05 s, with the client's own latest local Telemetry, after any snapshot applied that tick | sdk-runtime | `test_game_host_net.gd` |
| GM13 | `int_fields() -> Dictionary` | S2.6, F2.6 | Keys `"snapshot"` and each event `"type"`; values are dotted paths with `[]` and `{}`; rule for mixed arrays in 3.1 C10 | net-client | `test_protocol.gd`: a Siege-shaped fixture (`r[][]`, `f[][]`, `f[][][]`) comes back as ints |
| GM14 | `make_view() -> Node` | S3, T3, F3.5 | 2D: a Node2D the GameHost places with `PixelViewport.set_game_view` at `pixel_base`; 3D: a Node3D with its own camera; built on every rendering peer, never in headless runs | sdk-runtime, world-kits | `test_game_host.gd`: `_template`'s view lands in a PixelViewport |
| GM15 | `hud_spec() -> HudSpec` | S3, T3, F3.5 | Called on every rendering peer after configure, so it may depend on `ctx.players` and `ctx.local_peer` (Fishing's lane rects depend on both) | sdk-runtime, ui-hud | `tests/ui/test_hud_layer.gd` |
| GM16 | `results() -> GameResults` | S2.8, T2.8, F2.8 | Host/SOLO, once: after the cool-down, or at a `run_game_sim` `timeout` or `paused` end (T4 S2 expects results with grade D after a pause); `ctx.stats` is final then; sent to every client as `results` | sdk-runtime | `test_game_host.gd`; paused end in `test_sim_report.gd` |
| GM17 | `apply_progress(results: GameResults, progress: ProgressStore) -> Array` | S2.8, T2.8, F2.8 | Every peer, once per session, after `results` arrives and before the results screen; returns the local rider's new unlock ids, which the screen shows; the platform saves the store afterwards. A client restarted during the cool-down gets exactly one call (S4) | sdk-runtime, app-shell | `tests/sdk/test_progress.gd`: once on host and on each client, including a restarted client |
| GM18 | signal `lap_marker(label: String)` | S2.8, T2.8, F2.4 (none of them emits it) | Optional; each emit adds a FIT lap; nothing may depend on games emitting it | rides, sdk-runtime | `tests/rides/test_laps.gd` |
| GM19 | signal `phase_changed(index: int)` | S2.8, T2.8, F2.4 | Emitted by games only (Siege and Tank emit it; Fishing doesn't); the GameHost never emits it and never changes phases or laps on it, and records it in the report events as `{"type": "game_phase_changed", "index": n}` **(doc)** (3.1 C2) | sdk-runtime | `test_game_host.gd` |
| GM20 | signal `finished(reason: String)` | S2.8 `complete`, T2.3 `victory`/`withdrawn`, F2.4 `trip_over` | Host/SOLO: every rider not yet in COOLDOWN ends its phase (`ended_by` `finished`) and starts the cool-down; unused phases never start (no lap); idempotent; emitted during the cool-down it only records the reason (Siege emits it as its last wave ends, when the cool-down is already starting); the report keeps `finished_reason` **(add to report)** | sdk-runtime | `test_game_host.gd`: early finish; finish during COOLDOWN |
| GM21 | signal `game_event(event: Dictionary)` / `send_event(event)` | S2.6, T2.6, F2.6 (their event lists) | Host/SOLO; JSON-safe with a `"type"` key; batched and ordered as NET3; recorded in the report events in order | sdk-runtime, net-client | `test_game_host_net.gd` |
| GM22 | `EventBus.phase_started(peer_id, index)` and the `phase` message | B3.6; S2.4, T2.3, F2.4 read phases from `frame.phase` | For every rider on every phase change, the cool-down start included; the client's governor `start_phase(index)` follows its `phase` message | sdk-runtime | `test_game_host.gd`: per-rider plans that differ (F2.3) |

### 2.2 GameContext

| # | Item | Cited by | What the games expect | Owner | Test |
| --- | --- | --- | --- | --- | --- |
| CTX1 | `ctx.players: Array[PlayerSlot]` | S2.2, T2.2, F2.2 | Sorted by `slot_index` 0..n−1, identical on every peer; humans first, then bots; no peer outside it ever appears in `frame.players` (S2.2 ignores others anyway) | sdk-runtime, app-shell | `test_game_host_net.gd`: same order on host and clients |
| CTX2 | `ctx.content_id` | all | The lobby's choice, one of `contents` | sdk-runtime | `test_game_host.gd` |
| CTX3 | `ctx.seed` | F2.3 (pre-roll from seed and slot), F3.5 (view RNG) | The same int on every peer (`session_start`); `--seed` in tools | sdk-runtime | `test_game_host_net.gd` |
| CTX4 | `ctx.role` `"SOLO"`, `"HOST"`, `"CLIENT"`; `ctx.is_authority()` | S4, T4, F4.2 (SOLO vs HOST behaviour) | One human slot is SOLO even with bots; two or more are HOST and CLIENT | sdk-runtime | `test_sim_report.gd` |
| CTX5 | `ctx.local_peer`, `ctx.local_player()` | S2.4 (`power_band(ctx.local_peer, …)`), S5 G0.2, T5 G0.2 | This machine's rider; the host's own in HOST and SOLO | sdk-runtime | `test_game_host_net.gd` |
| CTX6 | `ctx.rng` | all | A `RandomNumberGenerator` seeded from `seed`, one per module instance; the only randomness rules use | sdk-runtime | `test_conformance.gd` determinism |
| CTX7 | `ctx.directives: DirectiveSink` | all | 2.5; on clients every call is ignored with `push_warning` | sdk-runtime | `tests/sdk/test_directive_sink.gd` |
| CTX8 | `ctx.options` | T2.2 (`rotation`) | Every `options` id with defaults filled, the host's lobby values, the same on clients | sdk-runtime, app-shell | `tests/sdk/test_options.gd`: host and clients |
| CTX9 | `ctx.progress: ProgressStore` (`get_value`, `set_value`, `add`, `has`, `save`) | S2.8, T2.8, F2.8 | `<user dir>/games/<id>/progress.json`, local to each peer, isolated per game and per profile; in-process sims give each human slot its own temp path; never sent anywhere | sdk-runtime | `test_progress.gd` |
| CTX10 | `ctx.hud: HudFeed` | S2.4, T3, F3.5 | 2.7 | ui-hud, sdk-runtime | 2.7 |
| CTX11 | `ctx.intents.send(intent: Dictionary)` | S2.6, T2.6, F2.6, F2.8 (`summary`) | HOST/SOLO: the local rider's `frame.players[peer].intents` on the next tick; CLIENT: `Telemetry.intents` at 5 Hz; each intent exactly once, in order; intents sent before the first tick (Fishing's `summary` from configure) arrive in the first frame **(doc)** | sdk-runtime, net-client | `test_game_host_net.gd` |
| CTX12 | `ctx.roster` | B3.6, B5.5 | Keyed by int peer id: `raw_w`, `cadence_rpm`, `ftp_pct`, `rescue`, `afk`, `connected`, `status`, `name`, `slot_index`; 2 Hz on every peer, host included | net-client, sdk-runtime | `test_game_host_net.gd` (B7.1 "the roster reaching every client") |
| CTX13 | `ctx.strings.t(key, args)` | S3, T3, F3.5 (strings) | Game keys from `content/<id>/strings.csv`; a missing key returns the key | sdk-runtime | `test_game_registry.gd` |
| CTX14 | `ctx.events: WlEventBus` | B3.6 | This peer's own bus (a private instance per in-process peer) | lead, sdk-runtime | `test_game_host_net.gd`: no cross-talk between peers |
| CTX15 | `ctx.stats: SessionStats`; `GameResults.from_stats(ctx.stats, ctx.players)` | S2.8 (XP from kJ, "the platform's per-player rows"), T2.8, F2.8 | Host/SOLO: kJ, average power and %FTP, NP, best 1/5/20-minute power, generic time in band per rider; final when `results()` runs; `kj(peer)` live | sdk-runtime, rides | `test_game_host.gd` |
| CTX16 | `ctx.load_content_json(rel_path)` | T4 S8 (`--override`), B3.6 | Reads `content/<id>/<rel_path>`; under `run_game_sim --override` it applies that file's merge patch first (3.1 C19) | sdk-runtime, lead | `test_sim_report.gd`: an override changes a value and is recorded |
| CTX17 | `ctx.scaling_mode`, `manifest`, `game_id`, `content_dir`, `assets_dir`, `player(peer)`, `peers()` | S2.4 (r by scaling mode) | Helpers | sdk-runtime | `test_game_host.gd` |

### 2.3 PlayerSlot

All rows are covered by `tests/sdk/test_player_slot.gd` (B7.1 "every PlayerSlot field" on the host and on clients) unless another test is named.

| # | Field | Cited by | What the games expect | Owner |
| --- | --- | --- | --- | --- |
| PS1 | `peer_id` | all | int; bots negative (`Bots.peer_id(n)` = −n) | sdk-runtime |
| PS2 | `name` | S2.2 | Bots are `Bot n` | sim |
| PS3 | `slot_index` | S2.2 (NW, NE, SW, SE wheels), T2.2 (starting engine), F2.2 and F2.3 (lane order, pre-roll) | 0..n−1, contiguous | sdk-runtime, app-shell |
| PS4 | `color`, `shape`, `pattern`, `hollow` (`Wl.slot_look`) | S2.2, T3 (shape badge), F2.2 | Slots 0–3: (red, circle, solid), (blue, triangle, dashed), (yellow, square, dotted), (green, diamond, double); 4–7 repeat with `hollow` (B3.9; matches S2.2 and F2.2). Test: `tests/contracts/test_wl.gd` | lead, app-shell, ui-hud |
| PS5 | `ftp` (watts) | S2.2, S2.4 | Bots use the lobby's bot FTP; `run_game_sim --ftp` | sdk-runtime |
| PS6 | `ftp_verified` | S2.4 (u = 0.85), T2.3, F4.2 | Bots true; `run_game_sim` slots verified unless `--unverified` | sdk-runtime |
| PS7 | `scaling_mode` | S2.4 | The lobby mode | sdk-runtime |
| PS8 | `p_eff_per_w` | S2.4 (WKG r) | 250 / FTP, 75 / weight or 1, from the rider's own client; every telemetry sample has `p_eff_w == power_w × p_eff_per_w` (3.1 C7). Test: `tests/core/test_scaling.gd` | platform |
| PS9 | `rider_mass_kg` | T2.4 (m = mass + 8 kg) | 75 unless RAW with the weight shared | platform |
| PS10 | `preferred_cadence_rpm` | F1, F2.4 | The profile value (default 90); bots 90; reaches the host in `player_info` | net-client |
| PS11 | `haptics_on`, `haptic_intensity` | T2.7, F2.7 | `haptics_on` false when the rider opted out; games skip such riders and the governor drops anything that still arrives | sdk-runtime |
| PS12 | `autopilot` | S2.5, T2.5, F2.5 | Profile or lobby flag; bots true; `run_game_sim --autopilot` | sdk-runtime |
| PS13 | `is_bot` | S2.2 (toothed pennant) | | sim |
| PS14 | `options` | S2.3 (`wave_offset`), F2.5 (`reel_pct`, `relaxed_band`) | Every `player_options` id with defaults filled; bots get the defaults (S2.3 "bots 0"); set from the lobby card via `player_info` or `run_game_sim --player-options`. Test: `test_options.gd` on host and clients | sdk-runtime, app-shell |

### 2.4 EffortPlan, PlanPhase and the PlanValidator

| # | Item | Cited by | What the games expect | Owner | Test |
| --- | --- | --- | --- | --- | --- |
| PL1 | `EffortPlan.phases: Array[PlanPhase]`, `EffortPlan.of([...])`, `add` | S2.3, T2.3, F2.3 | One plan per rider; may differ per rider (F2.3) or share boundaries (S2.3, T2.3) | lead | `tests/contracts/test_plan_types.gd` |
| PL2 | `kind` (`Wl.WARMUP`, `WORK`, `RECOVERY`, `FREE`, `COOLDOWN`) | all | A game-written COOLDOWN is rejected | sdk-runtime | `tests/sdk/test_plan_validator.gd` |
| PL3 | `mode` (`"ERG"`, `"SIM"`); `PlanPhase.erg(...)`, `PlanPhase.sim(...)` | all | | lead | `test_plan_types.gd` |
| PL4 | `target_pct` | S2.3, T2.3, F2.3 | % of the rider's own FTP | sdk-runtime | `test_plan_validator.gd` |
| PL5 | `ramp_to_pct` (`with_ramp`), `planned_pct_at(elapsed_s)` | S2.3 (50 → 65), T2.3 (dynamo depot 50 → 65), F2.3 (ride out 50 → 65) | Linear across `duration_s` | trainer-control, sdk-runtime | `tests/governor/test_channels.gd`: ramp applied |
| PL6 | `range_pct` (`with_range`), `effective_range()` | T2.3 ([55, 100]; `drill` [55, 65]), F2.3 (fight ranges; ≤ 100 in Base) | Default [target, target]; the validator checks the top bound; a directive outside it is refused `outside_range_pct`. Siege sets none | sdk-runtime | `test_plan_validator.gd`, `test_directive_sink.gd` |
| PL7 | `grade_source` `"flat"`, `"course"`, `"game"` | T2.3 (`game`, `flat`), F2.3 (Landing `flat`) | `game`: grade from `course_grade`; `flat`: 0 % plus gears; `course`: follows `course_profile` by speed-model distance | trainer-control | `tests/governor/test_stacking.gd` |
| PL8 | `course_profile` `[[distance_m, grade_pct], ...]` (`with_course`) | T2.4 (terrain stored in this format, pushed as `game`) | | trainer-control | `test_stacking.gd` |
| PL9 | `duration_s` | all | Fixed length. On open-ended phases a nominal length for previews and ramps only (T2.3 gives 180/120/240). F2.3's Reels give none: an open-ended phase with `duration_s` 0 is valid and the timeline shows `min_s`–`max_s` (3.1 C15) | sdk-runtime, ui-hud | `test_plan_validator.gd` |
| PL10 | `lap` (`with_lap`) | S2.3 (all), T2.3 (all), F2.3 (all but Landing) | A lap starts at each lap-true phase; a lap-false phase continues the current lap | rides | `test_laps.gd` |
| PL11 | `label` | S2.3 (`"Wave n"`), T2.3 (a strings key), F2.3 (`"Reel n"`, `"<Species> n"`) | Plain text or a strings key; the HUD shows `ctx.strings.t(label)`, which passes plain text through **(doc)**; also the FIT lap name | ui-hud, rides | `test_hud_layer.gd` |
| PL12 | `open_ended`, `min_s`, `max_s` (`with_open`), `worst_case_length_s()`, `best_case_length_s()` | T2.3, F2.3 | The platform ends the phase at `max_s` (`ended_by` `max_s`); `end_phase` works only after `min_s` | sdk-runtime | `test_game_host.gd` |
| PL13 | `meta` | S2.4 ("takes each phase's role from shifts.json") | Game data the platform carries and never reads | lead | `test_plan_types.gd` |
| PL14 | `PlanValidator.validate(plan, opts) -> {ok, errors, warnings}`, `PlanValidator.finalize(plan) -> EffortPlan` | S4 (every content at FTP 80, 200, 400, verified or not, offsets −10, 0, +5), T4, F4.1 (200 seeds × 4 riders × each `reel_pct`) | Static, pure, %-only (FTP-independent), callable without a GameHost; fast enough for F4.1's thousands of plans; games assert `warnings` is empty | sdk-runtime | `test_plan_validator.gd` |
| PL15 | Warm-up rule (4.6.8) | S2.3, T2.3 and T2.9, F2.3 | In the first 300 s (open-ended phases at `min_s` decide which phases fall inside), every ERG target, ramp end and range bound ≤ 65 %; SIM phases are allowed there (the governor clamps the grade to −2…+3 % and drops haptics). Accepts Tank's depot (SIM `game`), Tank and Siege `drill`, Fishing `e2e_2min` with its 30 s SIM Landing | sdk-runtime | `test_plan_validator.gd` with these fixtures |
| PL16 | Caps (4.6.1) | S2.3 (≤ 117 % only in waves ≤ 240 s), T2.3 (boss `max_s` 360 at ≤ 100 %), F2.3 (marlin 1320 s at 104 %, tuna 104.8 %) | ≤ 150 % everywhere; a phase longer than 300 s (open-ended: `max_s`) ≤ 105 % inclusive | sdk-runtime | `test_plan_validator.gd`: 104.76 % accepted at `max_s` 540 |
| PL17 | Duration accrual and reset (4.6.1) | S2.3 (`vo2`), F2.3 (mahi 270 s at 110 %; Reels `min_s` 120) | > 105 % ≤ 300 s and > 120 % ≤ 60 s, accrued with open-ended phases at `max_s` and their range top; reset by ≥ 120 consecutive ERG seconds ≤ 90 % (inclusive; open-ended at `min_s`); a SIM phase restarts the reset count and accrues nothing | sdk-runtime | `test_plan_validator.gd` |
| PL18 | Mode-switch warning | S2.3, T2.3 (≥ 60 s), F2.3 (30 s Landing) | Warning only when two ERG↔SIM switches are less than 30 s apart (strict; exactly 30 s gives none); open-ended at `min_s` | sdk-runtime | `test_plan_validator.gd`: Fishing's Fight, Landing, Reel gives no warning |
| PL19 | Appended cool-down (`PlanValidator.cooldown_phase()`) | S2.3, T2.3, F2.3 | COOLDOWN, ERG 50 %, 180 s, `lap` true, label `Cool-down`; `cooldown_appended` true; games never write one | sdk-runtime | `test_plan_validator.gd` |
| PL20 | `ctx.directives.replan(peer, plan) -> bool` | T2.2, F2.3 (neither uses it) | Same validation; a rejection keeps the old plan | sdk-runtime | `test_directive_sink.gd` |
| PL21 | Client re-validation of `plan` | B5.5 | Each client validates the plan it receives before its governor uses it (3.1 C16) | net-client, sdk-runtime | `test_game_host_net.gd` |

### 2.5 DirectiveSink and EffortDirective

| # | Item | Cited by | What the games expect | Owner | Test |
| --- | --- | --- | --- | --- | --- |
| DS1 | `ctx.directives.request(peer, directive: EffortDirective) -> DirectiveResult`; `EffortDirective.from_dict({...})` / `make` | S2.3, T2.3, T2.7, F2.3, F2.7 | `to_dict()` emits only the fields the game set (plus `duration_s`), so the report's `requested` shows the game's keys plus `duration_s` and the sink-assigned `id` (checkers ignore those two; S4 and S4 S10: "no `mode_grade`, `haptic`, `target_*`, `crr` or `cw` key") | lead, sdk-runtime | `test_sim_report.gd`: requested keys round-trip |
| DS2 | Fields `mode`, `target_pct`, `target_wkg`, `target_w`, `mode_grade`, `haptic`, `haptic_wind`, `crr`, `cw`, `duration_s` (default 0), `reason`, `source`; `id` from the sink | all | Exact keys | lead | `test_plan_types.gd` |
| DS3 | Channels and expiry | S2.3, T2.3, T2.7, F2.3 | A request touches only the channels it sets; a later request on a channel replaces it and cancels that channel's pending expiry; `duration_s` applies to that request's channels; on expiry the ERG target returns to the phase's planned target (with ramp), a SIM block returns to ERG through the ramped switch, `mode_grade`, factors and haptic return to none; `duration_s` 0 holds until the phase ends; every channel resets at a phase change (`start_phase`); expiry counts game time rounded to whole ticks **(doc)** | trainer-control, sdk-runtime | `test_channels.gd`, including B7.1's "a 1.5 s haptic over a held `mode_grade` leaves the grade in place" and F's run ramp expiring straight to the base pull |
| DS4 | `mode` depends on the phase | S2.3 (`mode: SIM` in an ERG phase), T2.3 (boiler and hoist `{mode: SIM, mode_grade}` with `duration_s` 0 in SIM phases), T2.7 and F2.7 (`{mode: SIM, haptic, duration_s 1–5}` in SIM phases), F2.3 (`mode: ERG` with a target in ERG phases) | In an ERG phase `mode: "SIM"` opens a SIM block. In a SIM phase `mode: "SIM"` is a no-op confirmation: no SIM-block rule, no spacing check, no expiry effect; `mode: "ERG"` there is refused (3.1 C4) | trainer-control, sdk-runtime, lead | `test_channels.gd`: Tank's 1.5 s hit haptic and the boiler grade in a SIM phase are accepted |
| DS5 | Siege Overdrive `{mode: SIM, duration_s: 30, reason: "overdrive", source: "siege"}` | S2.3, S4 S10 | In a WORK ERG phase after 420 s, with ≥ 30 s left and ≥ 90 s since the previous block ended: accepted with no dropped channel; SIM grade = gear offset clamped to the user range; after 30 s back to ERG through the ramped entry (min(3 s power, planned target), never below the floor, slew 30 W/s). 10 ≤ `duration_s` ≤ 30 inclusive; the block's two switches are exempt from the 30 s spacing | trainer-control, sdk-runtime | `tests/governor/test_sim_block.gd` |
| DS6 | ERG target requests | T2.3 (bank: 1 s sub-steps, `duration_s` 0), F2.3 (pull ramps: 6 requests 0.5 s apart; runs with `duration_s` = seconds left, so every step keeps one expiry) | Inside `range_pct` or refused; `target_w` and `target_wkg` converted to %FTP first; then ×0.85 if unverified, caps, floor, slew; 2 requests per second per rider are accepted (the controller coalesces writes to 2/s) | trainer-control | `test_channels.gd` |
| DS7 | `mode_grade` | T2.3 (boiler up to 8 %, hoist 4 %, 1 % in the depot) | Only in a SIM phase or a SIM block, else refused `mode_grade_outside_sim`; stacked as (course + mode) × difficulty + gear, clamped to the user range | trainer-control | `test_stacking.gd` |
| DS8 | `haptic` | T2.7 (2.0 for 1.5 s `hit`, 3.0 for 2.0 s `boss_hit`, 3.0 for 1.0 s `ram`), F2.7 (3.0 for 5 s `last_run`) | Grade % before intensity; the governor multiplies by `haptic_intensity`, caps +3 % and 8 s; dropped, logged with `push_warning` and recorded for an ERG rider (`haptic_in_erg`), in warm-up (`haptic_in_warmup`), opted out (`haptics_off`), or within 15 s of the end of that rider's last applied haptic (`haptic_cooldown`); never a mode switch; only the haptic term changes and expires | trainer-control | `tests/governor/test_haptics.gd` |
| DS9 | `course_grade(peer, grade_pct)` | T2.3 pattern 4 (2 Hz) | Only in `grade_source: game` phases (otherwise recorded with reason `grade_source_not_game` **(add)**); coalesced to 2 Hz; stacked by 4.6.6; holds until the next call or the phase end; reaches remote riders as `directive` kind `course_grade` | sdk-runtime, trainer-control | `test_directive_sink.gd` |
| DS10 | `end_phase(peer) -> bool` | T2.3 (every rider in one step, after `min_s`), F2.4 (hook-set, landing) | `true` only for an open-ended phase past `min_s`; otherwise `false`, `push_warning`, recorded `before_min_s` or `not_open_ended`; takes effect at the end of the current tick, so every call in one `sim_step` changes phase on the same tick; the next `frame.phase` shows the new index at elapsed 0 | sdk-runtime | `test_directive_sink.gd` |
| DS11 | `cadence_band(peer, lo_rpm, hi_rpm)` | T2.3 pattern 5 ((60, 120), (50, 120)), F2.4 (published when its rounded edges change; cleared at Landing) | Holds across phases; (0, 0) clears; the cool-down clears every band; reaches that peer's HUD cadence widget (`cadence_band_changed`), its MockTrainer (`set_cadence_band`) and bots; never changes trainer load | sdk-runtime, ui-hud, trainer-core | `test_directive_sink.gd` (B7.1 "`cadence_band` reaching the HUD and MockTrainer and clearing") |
| DS12 | Cool-down | S4 ("COOLDOWN … sends no directive"), T2.3 ("Nothing in the cool-down"), F2.4 | Every `request`, `course_grade`, `end_phase` and `cadence_band` during COOLDOWN is refused `cooldown` and recorded, so a game's check can see a violation | sdk-runtime | `test_directive_sink.gd` |
| DS13 | Routing and acks | B3.6, B4.6.7; T5 G0.2 ("how course_grade, cadence_band and end_phase reach a remote rider's governor") | The host sink pre-checks and assigns an id; local riders through `LocalRider.apply_directive`; remote riders through `directive` (`request`, `course_grade`, `cadence_band`, `power_band`); `end_phase` travels as the `phase` message; the client governor re-validates, clamps and acks in `Telemetry.acks`; the host emits `EventBus.directive_applied(peer, record)`; the report keeps both | sdk-runtime, net-client | `test_game_host_net.gd` (B7.1 "each client's governor follows its remote `plan`, `phase` changes caused by `end_phase`, `course_grade` and `cadence_band`") |
| DS14 | Rescue, coasting and pause underneath directives | F2.3 (pauses), F4.1 (rescue or AFK at every ramp step) | Channel values and expiries keep counting game time under rescue and coasting, which only override the applied target; after the rescue hold the 10 s ramp-back heads for the channel's current value, so a run that expired during rescue lands on the base pull; pause stops game time and therefore expiries | trainer-control | `tests/governor/test_rescue.gd` |
| DS15 | `clamped_by` and refusal names (`Wl.CLAMP_*`, `Wl.REFUSE_*`) | F4.2 #1 and F6 (`clamped_by` never names the ceiling, the long-phase cap or a duration limit), S4 S10 (no refusal, no dropped channel) | Every rule that changed the value, in order applied; distinct names per rule (3.1 C5) | trainer-control, lead | `tests/governor/test_clamped_by.gd` |

### 2.6 InputFrame, PhaseState and Telemetry

| # | Item | Cited by | What the games expect | Owner | Test |
| --- | --- | --- | --- | --- | --- |
| IF1 | `frame.players` (peer → Telemetry), `frame.telemetry(peer)` | all | Every slot, bots and dropped peers included | sdk-runtime | `test_game_host.gd` |
| IF2 | `frame.phase` (peer → PhaseState), `frame.phase_of(peer)` | S2.4 (one shared phase clock), T2.3, F2.4 (per rider) | Keyed by peer even when every rider shares one sequence (Siege and Tank read any slot's) **(doc)**. `PhaseState`: `index`, `kind`, `mode`, `elapsed_s`, `duration_s`, `open_ended`, `min_s`, `max_s`, `label`, `planned_pct`, `remaining_s`, `count`. S2.3's "≥ 30 s left" is `remaining_s` | sdk-runtime | `test_game_host.gd` |
| IF3 | `frame.tick`, `frame.t` | S2.6 (`tick` in its snapshot) | Game time | sdk-runtime | `test_game_host.gd` |
| IF4 | Telemetry `power_w`, `cadence_rpm`, `speed_kmh`, `effort`, `p_eff_w`, `wbal_j`, `applied_target_w`, `clamped_by`, `rescue`, `afk`, `gestures`, `intents`, `connected`, `age_s` | S2.4 (P_eff, raw W vs CP, WKG r), T2.4, F2.3 ("the rules use the applied target from telemetry"), F2.4 (staleness) | As named in B3.6 | platform, sdk-runtime | `tests/core/test_local_rider.gd` |
| IF5 | Telemetry `t`, `ftp_pct`, `mode`, `applied_grade_pct`, `gear`, `coasting`, `paused`, `s_left_105`, `s_left_120`, `distance_m`, `phase_index`, `acks` | report traces (S4 S10, T4 S4) | Frozen extras | platform | `test_local_rider.gd` |
| IF6 | Dropped peer | S2.2, T2.2, F2.4 | `connected` false, power and cadence 0, `age_s` growing, `afk` true; the slot stays | sdk-runtime | `test_game_host_net.gd` |
| IF7 | Staleness | F2.4 (telemetry stale > 3 s: lane AFK; cadence stale > 3 s: meters freeze) | `age_s` set every tick for every remote rider, not only after a drop; cadence staleness needs `cadence_age_s` **(add)** (3.1 C20) | sdk-runtime, platform | `test_game_host_net.gd` |
| IF8 | Gestures and intents arrive exactly once | S2.5, S2.6, T2.6 ("applied next tick"), F2.5 | Each appears in exactly one frame: the host's own on the next tick; a client's on the first host tick after its telemetry arrives | sdk-runtime | `test_game_host_net.gd` |
| IF9 | `applied_target_w` | F2.4 (tiring uses power / applied target) | Whole watts after every governor rule; 0 outside ERG; 50 % FTP during rescue | trainer-control | `test_rescue.gd` |

### 2.7 HUD kit, ctx.hud and HudSpec

| # | Item | Cited by | What the games expect | Owner | Test |
| --- | --- | --- | --- | --- | --- |
| HUD1 | `HudSpec.add(widget, at, options)`, `add_control(control, at)`, `toasts_at`, `banners_at`, anchors `top_left`, `top`, `top_right`, `bottom_left`, `bottom`, `bottom_right` | S3 (HUD table: "bottom center" is `bottom`), T3 | Entries at one anchor stack in the order added | ui-hud | `tests/ui/test_hud_layer.gd` |
| HUD2 | Rect2i art-pixel placement | T3 (HUD only in y 0–60 and 300–360), F3.2 and F3.5 (the local lane's HUD zone x 427–639; toasts below the deck bar; banners over the local lane's left two-thirds), F5 G0.2 | Mapped through `PixelViewport.art_rect_to_screen` and re-laid out on resize; kit widgets shrink to fit: Fishing's 4-lane zone is 213 × 84 art px (639 × 252 px at 1080p) for timeline, power gauge, cadence, W′ and gear; key numbers keep ≥ 48 px where the rect allows; each widget's minimum rect is documented **(doc)** | ui-hud, world-kits | `test_hud_layer.gd`: Rect2i at scale 2 and 3 with a letterbox |
| HUD3 | Kit widgets `power_gauge`, `cadence`, `wbal`, `timeline`, `teammates`, `readout`, `gear` | S3, T3, F3.5 | Power gauge: the applied target in ERG, the published power band in SIM, glowing in band; cadence with the published band; W′ bar; timeline with next-phase preview, the local rider's plan, open-ended phases shown by nominal or `min_s`–`max_s`; readouts ≥ 48 px at 1080p | ui-hud | `test_hud_layer.gd` |
| HUD4 | `gear` visibility | S3 ("only in Overdrive"), T3 ("gear in SIM"), F3.5 ("during Landing") | Shown whenever the local trainer is in SIM, SIM blocks included; hidden in ERG (3.1 C23) | ui-hud | `test_hud_layer.gd` |
| HUD5 | `teammates` strip | S3 (color and pattern chip, raw W, %FTP), T3 (color and shape chip, engine icon, %FTP, in band, rescue, AFK, reconnect) | Per slot from `ctx.roster`: a chip with color, shape, pattern and `hollow`; name, raw W, %FTP, rescue, AFK, disconnected; `teammate_status` `in_band`, `icon` (a `res://` texture path **(doc)**), `text`. What the kit can't show, games draw in their own Control beside it (S3, T3) | ui-hud | `test_hud_layer.gd` |
| HUD6 | `readout` with `source` `power_w`, `cadence_rpm`, `ftp_pct`, `wkg` or `custom` (plus `id`); `ctx.hud.readout(id, text)` | S3 (gate HP, denarii), T3 (big watts, hull HP, the station's key number), F3.5 (W and rpm) | Custom text is local only | ui-hud | `test_hud_layer.gd` |
| HUD7 | `ctx.hud.power_band(peer, lo_w, hi_w)` | S2.4 (Overdrive: `power_band(ctx.local_peer, 1.2 × FTP, 1.4 × FTP)` on the rider's own peer), T3 (each peer sets its diesel or Bulwark rider's 76–105 % band; none for steam) | A host call for a remote peer travels as `directive` kind `power_band` to that peer's gauge and MockTrainer; a call for the caller's own rider (host or client) applies to its own gauge and MockTrainer and sends nothing; it holds until replaced or (0, 0); the cool-down clears it (3.1 C27) | sdk-runtime, ui-hud, trainer-core | `tests/sdk/test_hud_routing.gd` (B7.1 "a host-side `power_band` reaching a client's power gauge and MockTrainer", plus the client-side case) |
| HUD8 | `ctx.hud.teammate_status(peer, {in_band, icon, text})` | T3 | Host: into the roster for every peer; client: local only | sdk-runtime, ui-hud | `test_hud_routing.gd` |
| HUD9 | `ctx.hud.toast(key, args = [], peer = 0)`, `ctx.hud.banner(key, args = [], seconds = 3.0, peer = 0)` | S2.4 (a refused buy toasts only on the buyer's peer), S2.6 (horns and toasts raised per peer), T2.6 and T3 (prompts per peer), F3.5 | HOST/SOLO: `peer` 0 (`Wl.ALL_PEERS`) reaches every peer including the host; `peer == ctx.local_peer` draws on the host only and sends nothing; another peer gets a `hud` message. A client draws locally whatever `peer` says. `args` fill `{0}` or `{name}` (3.1 C1) | sdk-runtime, ui-hud, net-client | `test_hud_routing.gd` (B7.1 "a toast with a `peer` reaching only that peer") |
| HUD10 | Rescue banner (always shown) and warm-up and pause banners (`show_safety_banners`) | S3, T3, F3.5 | Drawn in `banner_area` | ui-hud | `test_hud_layer.gd` |
| HUD11 | Game Controls and the shared Theme | S3 (routing card, Overdrive button, shop), T3 (station card, objective line, boss bars), F3.5 (meters, fish row, `FishingLaneHud`) | Laid out at anchors or rects above the view; the Theme's `res://` path and font sizes documented so games match the kit **(doc)** | ui-hud | `test_hud_layer.gd` |
| HUD12 | Drawing under the HUD | S3 (a vignette under the HUD) | `HudLayer`'s CanvasLayer `layer` value documented, so a game view's own CanvasLayer below it draws under the HUD **(doc)** | ui-hud | none (doc) |

### 2.8 PedalScanList and pedal-scan

| # | Item | Cited by | What the games expect | Owner | Test |
| --- | --- | --- | --- | --- | --- |
| PSL1 | `PedalScanList` (`addons/wattlands/ui/pedal_scan_list.gd`): `set_items`, `scan_interval_s` (1.6), `scanning`, `erg_auto_confirm`, `listen_to_input`, `highlighted`, `set_highlight`, `tick(dt)`, `feed_gesture`, `feed_action`; signals `item_chosen(index, id, auto)`, `backed_out`, `highlight_changed` | S2.4 and S3 (the shop "uses the platform's pedal-scan component"), F2.4 (spot picks), T2.5 (results) | `surge` or `confirm` picks; `coast` or `back` backs out (`coast` never in ERG); up and down move focus and pause scanning for 10 s | ui-hud | `tests/ui/test_pedal_scan_list.gd` |
| PSL2 | ERG auto-confirm | S2.4 ("picks auto-confirm after two scan cycles because breaks are ERG phases"), S2.5, F2.4, F2.5 | With `erg_auto_confirm` on, the highlighted item is picked after two full cycles (2 × item count × `scan_interval_s`) without input, whether or not scanning is on, so a rider with Autopilot off who only pedals still gets picks (S4, F4.1). Sessions bind it to the local rider's mode: `follow_local_mode` **(add)** or the game sets it from `Telemetry.mode` **(doc)** | ui-hud | `test_pedal_scan_list.gd` |
| PSL3 | Pick source | S2.6 (a buy picked by auto-confirm carries `"auto": 1`), F2.5 (surge picks and auto picks don't end the fallback; key and button picks do) | `auto` covers auto-confirms; surge versus button needs signal `item_picked(index, id, via)` with `via` `"action"`, `"surge"` or `"auto"` **(add)**. The game writes `"auto": 1` (or a gesture tag) into its own intent; the platform never edits intents (3.1 C14) | ui-hud, lead | `test_pedal_scan_list.gd` |
| PSL4 | Pedal-scan everywhere | B3.5; T2.5 (results), F2.5 | Game picker, lobby (content, options, player options, Add bot and Remove bot), results and Upload to Strava | app-shell | `tests/app/test_pedal_scan_flow.gd` |

### 2.9 world2d

| # | Item | Cited by | What the games expect | Owner | Test |
| --- | --- | --- | --- | --- | --- |
| W2D1 | `PixelViewport` (`pixel_base`, `set_game_view`, `game_view`, `integer_scale`, `letterbox_offset`, `art_rect_to_screen`, `capture`) | T0.2, T3, F0.3, F3.2, F5 G0.2 | Nearest filtering, integer scale ≥ 1, letterbox; `capture()` for screenshots | world-kits | `tests/world/test_pixel_viewport.gd` |
| W2D2 | `ParallaxStrip` with `mirror_alternate` | T3 (factors 0.05, 0.2, 0.5, 1.0, 1.3), F3.3 (clouds and islands) | Any factor ≥ 0, including > 1 for foreground debris; tiles a texture narrower than the screen (T3's 240 × 80 `bg_ground`) across the width, alternating flipped copies when `mirror_alternate`; scrolled by a world x the view sets, so it is deterministic | world-kits | `tests/world/test_parallax_strip.gd` |
| W2D3 | `SpinningPart` | T3 (speed = cadence / 120, 0–1), F3.3 (crank by cadence; reel by line speed, reversed on runs) | Signed `speed` clamped to −1…1, negative runs backwards; a maximum rate at \|speed\| = 1 | world-kits | `tests/world/test_parts.gd` |
| W2D4 | `SlidingPart` | T3 (pistons, track chain) | Signed speed; a reciprocating mode (pistons) and a continuous scroll mode (chains, track links) | world-kits | `test_parts.gd` |
| W2D5 | `PaletteSwap` shader | F3.1 and F3.3 (one 2-colour red key ramp replaced by the player's ramp), T3 (white sprites tinted at runtime, which `modulate` already does) | Key colours → slot colours, with a helper that builds a 2-tone ramp from a slot colour | world-kits | `tests/world/test_shaders.gd` |
| W2D6 | `SpriteWobble` shader | F3.3 (fish tails, bait ball, light rays) | Amplitude, frequency, wavelength, axis; pixel-snapped | world-kits | `test_shaders.gd` |
| W2D7 | Pixel import preset | T3, F3.4 (pixelate output), B3.9 | Filter off, mipmaps off, lossless; applies to every `assets/<id>/sprites/*.png` without hand-written `.import` files (3.1 C36) | world-kits, art-pipeline, lead | `tests/art/test_pixelate.gd`: an imported sprite has mipmaps off |
| W2D8 | `addons/wattlands/world2d/demo.tscn` | B3.9 | Capturable by `tools/screenshot` | world-kits | `test_pixel_viewport.gd` loads it |

### 2.10 world3d

| # | Item | Cited by | What the games expect | Owner | Test |
| --- | --- | --- | --- | --- | --- |
| W3D1 | `LowPolyMesh` | S3 Look ("Every mesh is a GDScript `LowPolyMesh`: primitives, flat shading, vertex colors and no textures. Merge static meshes per material") | SurfaceTool with smooth group −1 and vertex colours; primitives (box, cylinder or prism with n sides, cone, wedge, quad, low sphere), transforms, appending meshes into one, one shared vertex-colour material; darkening vertex colours near the ground (B3.9); blending vertex colours toward a haze colour beyond a distance (S3's fallback beyond 120 m) | world-kits | `tests/world/test_low_poly_mesh.gd` |
| W3D2 | MultiMesh scatter | S3 Scene (about 600 cypress, 400 olive, 300 rocks from a fixed seed; one MultiMesh per enemy type with a vertex-shader walk bob; route chains) | Seeded scatter in an area with exclusion zones, scale and rotation jitter; per-instance custom data on (walk-bob phase); a helper to set instance transforms each frame | world-kits | `tests/world/test_scatter.gd`: same seed, same transforms |
| W3D3 | Miniature camera rig | S3 Scene (fixed high three-quarter view, pitch about 42°, FOV 30–35°; 4 s push-in; shake up to 0.15 m) | High three-quarter with limited orbit; push-in and shake helpers | world-kits | `tests/world/test_camera_rig.gd` |
| W3D4 | Sky and ambient for Compatibility | S3 Light (one warm shadowed sun from the front left, the `world3d` sky and ambient, SSAO off) | WorldEnvironment plus DirectionalLight3D setup, SSAO off, no depth of field | world-kits | `demo.tscn` builds headless |
| W3D5 | Fog or haze | S3 Look ("Environment fog if Compatibility supports it in 4.7, otherwise vertex colors blended toward hazy blue beyond 120 m") | world-kits decides on 4.7.2 (windowed demo screenshot, ADR) and exposes one haze helper that uses Environment depth fog where it works and the vertex blend otherwise | world-kits | ADR plus `test_low_poly_mesh.gd` for the blend |
| W3D6 | `addons/wattlands/world3d/demo.tscn` | B3.9 | Capturable by `tools/screenshot` | world-kits | `test_low_poly_mesh.gd` loads it |
| W3D7 | Budget | S3 (≤ 250 draw calls, ≤ 400k triangles, 60 fps at 1080p on integrated graphics) | Helpers merge static geometry so a scene like Siege's can meet it; the demo logs its draw calls | world-kits | demo log line |

### 2.11 Audio

| # | Item | Cited by | What the games expect | Owner | Test |
| --- | --- | --- | --- | --- | --- |
| AU1 | `Sfx.play(name, volume_db, pitch)`, `register(name, stream)`, `has_sound(name)`, `synth(kind, freq_hz, duration_s, attack_s, release_s)` | S3 Audio, T3 Audio, F3.5 Audio | Silent and error-free headless; games register their own synthesized clips. Continuous sounds pitched live (S3 hum and creak, T3 rumble and whine, F3.5 reel clicks): `synth` returns an `AudioStreamWAV` whose loop mode a game may set **(doc)**, or `synth(..., loop)` **(add)** | ui-hud | `tests/audio/test_sfx.gd` |
| AU2 | Metronome `Sfx.set_metronome(rpm, on)` | F3.5 ("the optional metronome") | On per the profile setting; the GameHost feeds it the local rider's published cadence band centre, else the preferred cadence **(doc)** | ui-hud, sdk-runtime | `test_sfx.gd` |
| AU3 | CC0 packs credited, synthesis as the fallback | S1, T1, F3.5 | Games credit their own sounds in `docs/credits.d/<id>.md` | ui-hud | none |

### 2.12 GameRegistry and game.json

| # | Item | Cited by | What the games expect | Owner | Test |
| --- | --- | --- | --- | --- | --- |
| REG1 | Fields `id`, `title`, `summary`, `version`, `min_players`, `max_players`, `bots`, `presentation`, `pixel_base`, `entry`, `contents`, `default_content`, `e2e_content`, `zero_input_content`, `first_run_priority`, `picker_image`, `options`, `player_options` | S2.2, T2.2, F5 G0.3 | Validated by `validate_manifest`; an invalid game is hidden with a reason naming the field | sdk-runtime | `test_game_registry.gd` |
| REG2 | `first_run_priority`, `first_run_game()` | S2.2 (−1), T2.2 (−1), F0.5 (10) | Any integer, negative included; the highest wins, ties go to `workout`, then the lowest id. With Fishing installed the first run plays `fishing` `free_30`; no test hard-codes `workout` (B7.1) | sdk-runtime, app-shell | `test_game_registry.gd` with a fixture registry (−1, 0, 10); `tests/app/test_first_run.gd` |
| REG3 | `picker_image` | T2.2 (added in G2), F5 G0.3 | A missing or unreadable file logs a warning and the picker draws a generated card; the game stays listed | sdk-runtime, app-shell | `test_game_registry.gd` |
| REG4 | Option entries `{id, type, default, label}`: `toggle`; `int` with `min`, `max`, `step` (default 1); `choice` with `choices: [{value, label}]` | S2.2 (`wave_offset`: int −10…5, step 1, default 0), T2.2 (`rotation`: toggle, true), F5 G0.3 (`reel_pct`: int 50…70, step 5, default 60; `relaxed_band`: toggle, false) | An unknown type or a default outside its range or choices makes the game invalid (B3.6); recommended: a default off the `min` + n × `step` grid too; the lobby stepper honours `step`; labels default to `<ID>_OPT_<OPTION ID>`, content labels to `<ID>_CONTENT_<CONTENT ID>` | sdk-runtime, app-shell | `test_game_registry.gd` (every option type); `tests/app/test_lobby.gd` |
| REG5 | `resolve_options(id, values, per_player)` | S4 (`--player-options` offsets), F4.2 | Defaults filled, values validated, unknown keys dropped with a warning | sdk-runtime | `test_options.gd` |
| REG6 | Game translations | S3, T3, F3.5 | `content/<id>/strings.csv` registered with the TranslationServer at startup; conformance fails a key without the game's prefix | sdk-runtime | `test_conformance.gd` |
| REG7 | `_template` never listed; every other `game.json` must validate | T0.1, T4 gate 3, F4.3 | Conformance asserts it, naming the failing field | sdk-runtime | `test_conformance.gd` |
| REG8 | `zero_input_content` and the 5 s `pedal_start` | T2.5 (Bulwark, solo, `ashfall_road`), F2.5 (`free_30`) | Starts the last-played game solo | app-shell | `tests/app/test_zero_input.gd` |

### 2.13 Protocol and int_fields

| # | Item | Cited by | What the games expect | Owner | Test |
| --- | --- | --- | --- | --- | --- |
| PR1 | `Protocol.apply_int_fields(data, paths)` | S2.6, F2.6 | `[]` every array element, `{}` every dictionary value; converts only numeric leaves at a matched path and leaves an Array or Dictionary there unchanged, so Siege's `f: [[pad, [target_ids]]]` declares `f[][]` and `f[][][]` (3.1 C10) | net-client | `test_protocol.gd` |
| PR2 | `Protocol.decode()` and `decode_game()` | S2.6, T2.6 | `peer`, `host`, `from`, `to`, `seq`, `proto`, `max` and every `*_id` key to int; peer-keyed dictionaries get int keys; bad schema or version rejected | net-client | `test_protocol.gd` |
| PR3 | Exact round trips through `JSON.stringify` and `JSON.parse_string` | S4, T4, F4.1 | For every message type | net-client | `test_protocol.gd` |
| PR4 | Intents are not converted | S2.6 (`pad`, `to`), T2.6 | Games cast intent values themselves **(doc)** | sdk-runtime | none (doc) |

### 2.14 Networking

| # | Item | Cited by | What the games expect | Owner | Test |
| --- | --- | --- | --- | --- | --- |
| NET1 | Client telemetry at 5 Hz with gestures, intents and acks | S2.6, T2.6, F2.6 | | sdk-runtime, net-client | `test_game_host_net.gd` |
| NET2 | Snapshots at 10 Hz | S2.6 (≤ 8 KB), T2.6 (≤ 4 KB), F2.6 (≤ 2 KB) | Never a message over 16 384 bytes (3.1 C9) | net-client, sdk-runtime | `tests/net/test_net_session.gd` |
| NET3 | `event {seq, events}` batches | S2.6, T2.6, F2.6 (same order everywhere, ≤ 10 messages a second) | One batch per ≤ 100 ms, sent before the snapshot of the same tick (3.1 C12) | sdk-runtime, net-client | `test_game_host_net.gd` |
| NET4 | `roster` at 2 Hz | B5.5 | Every peer | net-client | `test_game_host_net.gd` |
| NET5 | Host send budget | T2.3 (`course_grade` 2 Hz, bank 1 Hz, boiler 1 Hz), F2.3 (2 Hz ramps, band updates) | Stays under the relay's 60 messages a second per peer (3.1 C11) | net-client | `test_net_session.gd`: 4 riders of Fishing-like load never hit `rate_limited` |
| NET6 | Drop and rejoin | S2.2, T2.2, F2.4, F2.6 | A drop calls `on_afk(peer, true)` at once and the slot stays; a rejoin with the reconnect token gets `lobby_state`, its `plan`, its `phase` and the latest snapshot, then `on_afk(peer, false)` after fresh pedaling; a restarted client starts a new FIT from the rejoin; after the token expires the slot stays AFK | sdk-runtime, net-client | `test_game_host_net.gd` |
| NET7 | No joins after the start: `session_in_progress` | S2.2, T2.2 | Shown by the client | net-client, app-shell | `test_net_session.gd` |
| NET8 | `player_info` | F1, F2.4 | Carries `preferred_cadence_rpm`, `haptics_on`, `ftp_verified`, `p_eff_per_w`, `autopilot`, `player_options` (frozen schema) | net-client | `test_protocol.gd` |

### 2.15 Rides and FIT laps

| # | Item | Cited by | What the games expect | Owner | Test |
| --- | --- | --- | --- | --- | --- |
| FIT1 | Laps | S0.6 and S4 S5, T0.6 and T4 S4, F2.3 and F4.2 #9 | A lap at each lap-true phase start, at each `lap_marker` and at the cool-down start (always its own lap, B3.8). Expected laps = lap-true phases that started + `lap_marker`s + 1 for the cool-down; a run that ends by `timeout` or `paused` before the cool-down has no cool-down lap **(doc)** | rides, sdk-runtime | `test_laps.gd`; `fit_check --expect-laps` in `test_sim_report.gd` |
| FIT2 | One FIT per human slot in `run_game_sim`: `<report dir>/fit/<report stem>_slot<n>.fit`; none for bots | S5 G0.2, T4 gate 5, F4.2 #9 | Listed in `fit_paths` | sdk-runtime, rides | `test_sim_report.gd` |
| FIT3 | FIT written on every ending, `paused` and `timeout` included | T4 S2 | | sdk-runtime | `test_sim_report.gd` |
| FIT4 | A restarted client starts a new FIT from the rejoin | B3.6 | | rides, sdk-runtime | `test_game_host_net.gd` |

### 2.16 Results and progression

| # | Item | Cited by | What the games expect | Owner | Test |
| --- | --- | --- | --- | --- | --- |
| RES1 | `GameResults` `grade` (S–D), `score`, `summary_key`, `rows`, `team`; `from_stats`, `row(peer)`, `grade_from_fraction` | S2.8, T2.8, F2.8 | Rows hold `peer_id`, `slot_index`, `name`, `is_bot`, `kj`, `avg_power_w`, `avg_ftp_pct`, `np_w`, `best_1m_w`, `best_5m_w`, `best_20m_w`, `ride_s`, `time_in_band_s`, `time_in_band_pct`, `xp`, `unlocks`, `stats`; games override time in band (T2.8, F2.8) and add `stats` and `team`; the results screen draws rows, custom stats and team stats, on pedal-scan | sdk-runtime, app-shell | `test_game_host.gd`; `tests/app/test_results.gd` |
| RES2 | `xp` and `unlocks` per row | S2.8, T2.8, F2.8 | Shown on the results screen | app-shell | `test_results.gd` |
| RES3 | Upload to Strava offered on the results screen | B3.8 | Pedal-scan selectable; auto-upload honoured | rides, app-shell | `test_results.gd` |

### 2.17 tools/run_game_sim

| # | Item | Cited by | What the games expect | Owner | Test |
| --- | --- | --- | --- | --- | --- |
| SIM1 | `tools/run_game_sim` and `.ps1` with `--game`, `--content`, `--players`, `--bots`, `--rider` (once, or once per human slot), `--sim-speed`, `--seed`, `--report`, `--autopilot=all\|none\|<slot,…>` (default `all`), `--ftp=<w>[,<w>…]` (default 200), `--unverified`, `--haptics-off=<slot,…>`, `--options=<json>`, `--player-options=<json array>`, `--override=<json file>`, `--max-sim-seconds=<n>` | S4, T4, F4.2 | Profiles contain commas, so `--rider` repeats and is never comma-joined; `--player-options` holds one object per human slot in slot order (bots get defaults; missing keys get defaults); an unknown or out-of-range value exits non-zero naming the field; `--unverified` makes every human slot unverified (bots stay verified) | sdk-runtime | `tools/tests/run_game_sim.test.mjs`; `test_sim_report.gd` |
| SIM2 | Roles | S4 (S3 relies on AFK), T4 S2, F4.2 | One human slot, with or without bots, runs SOLO; two or more run HOST with LoopbackTransport clients, each with its own CLIENT GameModule, `WlNetSession`, `WlEventBus`, `LocalRider` and MockTrainer; every human slot has its own governor | sdk-runtime | `test_sim_report.gd`: a 0 W rider pauses in SOLO, goes AFK in HOST |
| SIM3 | `end_reason` `complete`, `timeout`, `paused` | S4, T4 S2 | `timeout` at `--max-sim-seconds` (default: the validated plan with every open-ended phase at `max_s`, plus 600); `paused` once a SOLO run stayed paused 120 s of platform time; every ending calls `results()` and writes the report and FIT files | sdk-runtime | `test_sim_report.gd` |
| SIM4 | Report contents | S4 S5, S7, S10; S5 G0.2; T4 S1, S4, S7; F4.2 #1, #8 | B3.6's list: arguments, `end_reason`, events, each rider's phases (`index`, `kind`, start, end, `ended_by`), every directive as requested and as applied (`clamped_by` or refusal reason), the 1 Hz trace per rider (t, phase index, kind, mode, `applied_target_w`, applied %FTP, applied grade, `clamped_by`, `rescue`, `afk`, `paused`, haptic, `power_w`, `cadence_rpm`), each snapshot's sha256 and JSON byte size, `max_snapshot_bytes`, results, `fit_paths`, `deterministic_hash`. Also needed **(add)**: `slots` (slot, peer, name, is_bot, ftp, ftp_verified, rider spec, autopilot, haptics_on, options), the validated `plans` and their `plan_warnings`, `finished_reason`, `overrides`, a `schema` version. Exact JSON keys documented in GAME_SDK.md, because the games' `check_sims.mjs` read them | sdk-runtime | `test_sim_report.gd` against a schema fixture |
| SIM5 | `deterministic_hash` | S4 S7, T4 S7, F4.2 #8 | Same arguments and seed, same hash, in SOLO and HOST runs; computed over the canonical report without `fit_paths` and without any wall-clock value (wall time lives under a `meta` key that is excluded) (3.1 C29) | sdk-runtime | `test_sim_report.gd`: two HOST runs match |
| SIM6 | Speed | S4 (a 55-minute shift in ≤ 66 s at `--sim-speed=200`), B6 | Headless runs step as fast as `--sim-speed` allows; loopback HOST runs at any speed | sdk-runtime | `test_sim_report.gd` timing log |
| SIM7 | Isolation | S4, T4, F4.2 | Each human slot gets a temp profile dir; the user's real profile, progress and rides are never touched | sdk-runtime | `test_sim_report.gd` |

### 2.18 Other tools

| # | Item | Cited by | What the games expect | Owner | Test |
| --- | --- | --- | --- | --- | --- |
| TL1 | `tools/new_game <id>` and `.ps1` | S5 G0.1, T5 G0.1, F5 G0.1 | Copies `src/games/_template/`, `content/_template/`, `assets/_template/` and `tests/games/_template/`; rewrites `_template` → `<id>`, `_TEMPLATE_` → `<ID>_` and the `Template` class prefix → `<Id>` (`siege` → `Siege`), renames files; copies no `.uid` or `.import` file and strips `uid="uid://…"` attributes from copied `.tscn` and `.tres`; recommended: also writes `.github/workflows/game-<id>.yml` from a template; refuses (exit 1, writing nothing) if any of its targets exists; creates `docs/{decisions,credits.d,changelog.d}/<id>.md` only if missing, never refusing over them (3.1 C17); ids match `^[a-z][a-z0-9_]*$` | sdk-runtime | `tools/tests/new_game.test.mjs`; the B7.3 scaffold check (`demo` passes conformance) |
| TL2 | `tools/screenshot` and `.ps1`: `--game`, `--content`, `--at=<s>[,<s>…]`, `--players`, `--bots`, `--rider`, `--autopilot=all\|none`, `--seed` | S4 P1 (a Breach with 4 riders at 0 W), T4 P1 (the Citadel at 3 riders; fast-forward), F4.3 P1 (1, 2 and 4 lanes; seed; time) | `GameSimRunner` windowed with `run_game_sim`'s slot, role and profile rules; steps as fast as possible to just before each `--at`, renders at normal speed and saves the full frame with HUD from the host's view; `--screenshot-dir` (default `build/screenshots/<game>/`), files `<game>_<content>_<players>p_<at>s.png` **(doc)**; also accepts the other `run_game_sim` flags (3.1 C13) | qa, sdk-runtime | `tools/tests/screenshot.test.mjs` (argument parsing); one windowed capture of each demo scene |
| TL3 | `node tools/e2e/run.mjs --games=<ids>` | S4 gates 6–7, T4 gates 6–7, F4.3 | A comma list; per game: relay, mock Strava, a host and two clients under one wrapper lease, `e2e_content`, `--sim-speed=1`; writes `build/e2e/<id>/report.json` (events per peer, game events included in order; applied directives; FIT paths); runs `tests/games/<id>/e2e_check.mjs <report>` if present; a pass or fail line per game; non-zero exit if any fails; ≤ 6 min per game excluding the cool-down; reconnect and one auto-upload | qa | `tools/e2e/test/run.test.mjs`; the Workout e2e gate |
| TL4 | `node tools/fit_check/check.mjs <file\|dir>... [--expect-laps=<n>] [--json]` | S4 gate 5, S5 G0.2, T4 gate 5, F4.2 #9 | Directories recursively; per file errors, record count, laps (start, duration) and session totals; non-zero exit on any error; the `--json` output schema documented | rides | `tools/fit_check/test/` |
| TL5 | `tools/run_tests` and `.ps1` | S4 gate 7, T4 gate 7, F4.3 | B7's strict rules; runs with `FAL_KEY` and `WATTLANDS_ALLOW_ART` removed (`env -u …`) | lead | `tools/tests/run_tests.test.mjs` |
| TL6 | `tools/godot.sh` and `.ps1` | S5, T5, F5 (their GUT command `-s addons/gut/gut_cmdln.gd -gdir=res://tests/games/<id>/<dir> -ginclude_subdirs -gexit -gjunit_xml_file=build/junit_<id>_<agent>.xml`; `-s tools/check_scripts.gd`; `-s tools/art/pixelate.gd -- --game=<id>`; `--import`); S4 P1 (a windowed 60 s run of `tests/games/siege/perf/stress_scene.tscn`) | User arguments after `--` pass through untouched; windowed scene runs work under the timeout | lead | `tools/tests/godot_wrapper.test.mjs` |
| TL7 | `tools/env.sh` and `env.ps1` leave `FAL_KEY` and `WATTLANDS_ALLOW_ART` alone | T5 G0.4, F1, F5 G0.2 | Already true in W0 | lead | `tools/tests/env.test.mjs` (B1: both set to dummies, both unchanged) |
| TL8 | `tests/sdk/test_conformance.gd` | S0.1 (with bots at 1 and 4), T4 gate 3 (Autopilot humans at 1 and 3), F4.3 (Autopilot at 1 and 4) | Finds games through the GameRegistry; Autopilot human slots when `bots` is false; runs every game at `min_players` and `max_players`; each game's id appears in its GUT test names and in a log line (`conformance: tank ...`), so a hidden game shows as missing | sdk-runtime | itself |
| TL9 | `tools/check_scripts.gd` | S4 gate 2, T4 gate 2, F4.3 | Loads every `.gd` under `src/` and `tests/`, game test helpers included | lead | itself |
| TL10 | GUT collects only `test_*.gd` | S4 ("GUT collects only `test_*.gd` files") | The default prefix; helpers elsewhere still load in `check_scripts` | lead | `tools/run_tests` |

### 2.19 Art pipeline

| # | Item | Cited by | What the games expect | Owner | Test |
| --- | --- | --- | --- | --- | --- |
| ART1 | `node tools/art/generate.mjs --game=<id> [--only=<ids>] [--dry-run] [--budget=<usd>] [--reroll=<ids>] [--select=<sprite id>:<request id>] [--mock=<url>]` | T1, T3, F1, F3.4 | Zero dependencies | art-pipeline | `tools/art/test/generate.test.mjs` |
| ART2 | `--dry-run` | T3 (aspect within 2 %), F3.4 (sprites more than 5 % off) | No network and no key; prints each sprite's requested size, aspect error in %, estimated cost and the total, and lists sprites outside the endpoint's limits | art-pipeline | `generate.test.mjs` |
| ART3 | `assets/<id>/art.json`: `palette` (≤ 32), `style`, `endpoint`, `quality`, `sprites: [{id, prompt, size, background, parts, anchor, align, tile, mirror}]` | T3, F3.3 | The `parts` rectangle format, part output names and the `anchor` format documented **(doc)** | art-pipeline | `generate.test.mjs` |
| ART4 | Switching `endpoint` between flare and sunburst runs; `selected` | T3 steps 2–3, F3.4 step 2 | One `selected` result per sprite, the newest by default (`--select` overrides); pixelate uses only it; an unchanged input returns the cached or reused paid result | art-pipeline | `generate.test.mjs` |
| ART5 | `assets/<id>/art_manifest.json` | T1 ($15), F1 ($10) | Per request: endpoint, full input, request id, estimated cost and billed cost; plus a top-level spend total (the larger of the two per request) **(add)** | art-pipeline | `generate.test.mjs` |
| ART6 | `tools/godot.sh --headless --path . -s tools/art/pixelate.gd -- --game=<id>` | T3, F3.4 | Fit, crop, tile and mirror per B3.10; area downsampling; Oklab palette quantization; alpha only fully opaque or fully transparent (F4.1 tests that sprites use only palette colours); parts cut; deterministic; writes `assets/<id>/sprites/<sprite id>.png` | art-pipeline | `tests/art/test_pixelate.gd` |
| ART7 | Locks | T1, F1 | Real calls only with `FAL_KEY` and `WATTLANDS_ALLOW_ART=1`; never reads `WATTLANDS_NO_NETWORK_INTEGRATIONS`; never prints the key; tests pass `--mock` | art-pipeline | `generate.test.mjs` (B7.1 cases) |
| ART8 | `tools/art/endpoints.json` limits | T3 (`bg_ground` 240 × 80 at 3:1), F3.4 (8:1 to 23:1 strips narrowed) | Both sides multiples of 16, ≥ 655 360 px, maximum edge and aspect (3840 px and 3:1 where fal states none) | art-pipeline | `generate.test.mjs` |
| ART9 | Recovering a paid result | B3.10 | `GET https://api.fal.ai/v1/models/requests/by-endpoint?expand=payloads` before paying | art-pipeline | `generate.test.mjs` against `mock_fal` |
| ART10 | `docs/ART_PIPELINE.md` | T5 G0.2, F3.4 | Setup, budgets, how pixelate picks a result, recovery, part animation | art-pipeline | W3 review |

### 2.20 Mock rider profiles

All rows are covered by `tests/trainer/test_mock_profiles.gd` unless another test is named.

| # | Profile or rule | Cited by | What the games expect | Owner |
| --- | --- | --- | --- | --- |
| MR1 | Grammar `name:key=value,…` joined with `+`; `MockTrainer.from_spec(spec, ftp_w, options)`, `parse_spec` | S4, T4, F4.2 | A component may appear more than once (T4 S5: one drop in a dynamo stage and one in a gun line); cadence precedence: an active `cadence_drop` > `surge`'s lift (multiplies) > `band` > preferred cadence; power: `zero` or `const` > `surge` `sim_pct` in SIM > `erg` (3.1 C31) | trainer-core |
| MR2 | `erg` (`compliance`, 0–1, default 1.0) | S4 (1.0, 0.9, 0.8), T4 (1.0, 0.85, 0.70), F4.2 | In ERG it follows the applied target × compliance with τ ≈ 2 s; in SIM it rides compliance × the centre of the published power band, else 90 % FTP (T3's steam rider relies on the 90 %) | trainer-core |
| MR3 | `zero` | S4 S3, T4 S2 | 0 W and 0 rpm from t = 0 | trainer-core |
| MR4 | `const` (`w`, `rpm`) | B4.2 | | trainer-core |
| MR5 | `band` (`offset_rpm`, default 0) | F4.2 (`erg+band`; `erg+band:offset_rpm=-18` and `=18`), T4 | Cadence follows the published band's centre + `offset_rpm` with 2 s lag and noise bounded to ±2 rpm **(doc)**, so ±10 rpm outside the band holds; with no band, the preferred cadence | trainer-core |
| MR6 | `cadence_drop` (`rpm`; `at_s`, or `at_phase` with optional `after_s`; `at_target_pct` with optional `at_phase` and `after_s`; `for_s`, default the rest of the run) | S4 (`erg+cadence_drop:rpm=40,at_s=1200`), T4 S5 (by segment and applied target), F4.2 #7 (`rpm=40,at_s=600,for_s=20`) | `at_phase` is the rider's plan phase index; `at_target_pct` compares the applied ERG target (after the unverified factor) with n % FTP | trainer-core |
| MR7 | `surge` (`every_s` 60, `for_s` 2, `lift` 0.2, `sim_pct`) | S4 (`erg+surge:every_s=60,for_s=2,lift=0.2,sim_pct=130`; S10 needs ≥ 3 Overdrives a run) | Multiplies cadence and reported speed by 1 + `lift`, and every surge contains at least two notifications so the ERG `surge` gesture fires each time (3.1 C30); `sim_pct` rides n % FTP while the trainer is in SIM | trainer-core, sim |
| MR8 | Seeded randomness | S4 S7, T4 S7, F4.2 #8 | Jitter, noise and dropouts come from (run seed, slot) | trainer-core |
| MR9 | Bots | S2.2 | `Bots.RIDER_SPEC` `"erg:compliance=1.0+band"` | sim |
| MR10 | `--mock-trainer=<profile>` in the app | S6, T6, F6 (commands to play solo with a mock) | | platform, trainer-core |

### 2.21 Sim helpers

| # | Item | Cited by | What the games expect | Owner | Test |
| --- | --- | --- | --- | --- | --- |
| SH1 | `SprintRule.create(ftp_w, window_s)`, `update(t, power_w)`, `holds()`, `held_s()`, `best_s()`, `threshold_w()`, `reset()` | S2.4 (held ≥ 10 s), T2.4 (≥ 1.2 × FTP over the last 3 s; held ≥ 3 s inside a 6 s telegraph), F2.4 (gaff counts only while P ≥ 1.2 × FTP) | `window_s` 0 is instantaneous | sim | `tests/sim/test_sprint_rule.gd` |
| SH2 | `SpeedModel.create(rider_mass_kg, cda, mass_offset_kg)`, `step(dt, p_eff_w, grade_pct, wind_mps)`, `steady_state_speed(...)`, `visual_multiplier` | T2.4 (CdA 0.5 m², m + 8 kg; tested against the B3.11 oracle) | | sim | `tests/sim/test_speed_model.gd` |
| SH3 | `WBalance` and `Telemetry.wbal_j` | S2.4 (W′ drains in Overdrive), T2.4 (W′ pays for Overpressure) | Skiba's model, B3.4 | sim | `tests/sim/test_wbal.gd` |
| SH4 | `GestureRecognizer` | S2.4, S2.5, T2.4, T2.5, F2.4, F2.5 | ERG `surge` by flywheel speed; `coast` never in ERG; `stop_5s` solo outside ERG only | sim | `tests/sim/test_gestures.gd` |
| SH5 | `ZwoImport.parse_zwo(text)`, `parse_zwo_file(path)` (named WorkoutImport until W4) | S2.9 P1, F2.9 P1 | Returns `phases`, `blocks`, `clamps`, `warnings` | sim | `tests/sim/test_workout_import.gd` |
| SH6 | Virtual gears (`shift_up`, `shift_down`, `SafetyGovernor.shift`) | S2.4, T2.3, F2.4 | Work in every SIM phase and SIM block; shown by the gear widget | trainer-control | `tests/governor/test_gears.gd` |

### 2.22 Governor behaviours the games rely on

All rows are trainer-control's, tested under `tests/governor/`.

| # | Rule | Cited by | What the games expect |
| --- | --- | --- | --- |
| GOV1 | Floor max(30 % FTP, 50 W), rounded up | S2.3 (FTP below 100 W), T2.3 | Wins over every cap and over rescue |
| GOV2 | Unverified factor 0.85 | S2.3, S2.4, T2.3, F4.2 #1 | On every ERG target |
| GOV3 | Ceiling min(150 % FTP, 1000 W, trainer max); 105 % cap in phases > 300 s; duration limits at 105 % (300 s) and 120 % (60 s) with latch and reset | S2.3, T2.3, F2.3 | Whole watts, target rounded down; a target exactly at a cap is neither clamped nor counted |
| GOV4 | Slew: up 30 W/s, down at once | S2.3 (50 → 117 % in ≤ 9 s at 400 W), T2.3 (bank sub-steps), F2.3 (runs revert at once) | |
| GOV5 | Rescue | S2.4, T2.3, T2.4, F2.4, S4 S6, T4 S5, F4.2 #7 | In ERG with a governed target ≥ 60 % FTP: cadence < 45 rpm for 3 s or power < 75 % of target for 5 s → 50 % FTP; hold until cadence ≥ 70 rpm for 3 s; ramp back over 10 s; `rescue` in telemetry |
| GOV6 | Coasting | S4 S3, T4 S2, B7.4 | `not_pedaling` timed from its first sample: the ERG floor at 3 s; at 10 s pause (SOLO) or AFK (multiplayer) |
| GOV7 | Warm-up | S2.3, T2.3, F2.3 | The first 5 minutes of pedaling after connecting: ERG ≤ 65 %, grade −2…+3 %, no haptics; simulated riders pedal from t = 0 (a `zero` rider never starts it) |
| GOV8 | SIM stacking | T2.3 (≤ +13 % with the largest haptic), F2.3 | (course + mode grade) × difficulty + gear offset, clamped to the user range; haptic × intensity ≤ +3 %; total −10…+16 % |
| GOV9 | Ramped mode switches | S2.3, T5 G4 (a gun line straight after a Ram), F2.3, T4 S4 | ERG → SIM: ERG target min(applied, 3 s power), then SIM grade 0, then the stacked grade; SIM → ERG: grade 0, then ERG at min(3 s power, planned or directed target), never below the floor, slewing up; never above the planned target |
| GOV10 | Switch spacing for directive switches; the SIM-block exemption | S2.3, S4 S10 | ≥ 30 s apart except the two switches bracketing one 10–30 s block |
| GOV11 | Haptic cooldown | T2.7, F2.3 | 15 s per receiver, from the end of their last applied haptic |
| GOV12 | Pause | S4, T4 S2 | ERG floor or SIM flat; game time stops; trainer I/O continues |
| GOV13 | Panic `SafetyGovernor.emergency_safe()` | S5 G4 (panic during an Overdrive) | ERG off, SIM grade 0 and wind 0 at once |
| GOV14 | Cool-down | all | ERG 50 % FTP; directives refused; bands cleared |

### 2.23 What docs/GAME_SDK.md must answer

Each game brief's G0 records what `docs/GAME_SDK.md` says on these points. sdk-runtime writes every answer; the W3 reviewer checks each against the code.

| # | Question | Asked by | Answer the platform gives |
| --- | --- | --- | --- |
| Q1 | The mock rider profiles and their parameters | S5 G0.2, T5 G0.2, F5 G0.2 | 2.20 |
| Q2 | How `run_game_sim` counts `--players` and `--bots`; each rider's FTP, verified status, profile and Autopilot | S5 G0.2, T5 G0.2, F5 G0.2 | SIM1, SIM2 |
| Q3 | What the report holds; where FIT files go | S5 G0.2, T4, F5 G0.2 | SIM4, FIT2 |
| Q4 | The `fit_check` command line | S5 G0.2, F5 G0.2 | TL4 |
| Q5 | Whether the appended cool-down gets its own FIT lap | S5 G0.2, S4 S5, T4 S4, F4.2 #9 | Yes, always (FIT1) |
| Q6 | How a client's actions and shop picks become `Telemetry.intents` | S5 G0.2, T5 G0.2 | GM8, CTX11, PSL3 |
| Q7 | How a GameModule learns its local peer id | S5 G0.2, T5 G0.2 | `ctx.local_peer` |
| Q8 | What the GameHost does when a client drops or rejoins; whether a dropped peer gets `on_afk` | S5 G0.2, T5 G0.2 | GM7, NET6 |
| Q9 | How `hud_spec()` places kit widgets; how the power gauge's SIM band is set; how the strip is filled; how toasts and banners are posted | T5 G0.2 | HUD1–HUD9 |
| Q10 | How `course_grade`, `cadence_band` and `end_phase` reach a remote rider's governor | T5 G0.2 | DS13 |
| Q11 | How a haptic stacks with a mode grade | T2.7, T5 G0.2 | DS3, DS8: a separate channel |
| Q12 | How `apply_progress` is called on host and clients | T5 G0.2 | GM17 |
| Q13 | How to clear a cadence band | F2.4, F5 G0.2 | `cadence_band(peer, 0, 0)` |
| Q14 | `phase_changed` with per-rider plans; whether the GameHost emits it | S2.8, T2.8, F2.4, F5 G0.2 | GM19: only games emit it |
| Q15 | `tools/screenshot`: player count, seed, time, fast-forward | S4, T4, F5 G0.2 | TL2 |
| Q16 | How HudSpec positions map to PixelViewport art pixels | F5 G0.2 | HUD2 |
| Q17 | The spellings of PlanPhase fields, option entry fields, `course_grade`, `end_phase`, `cadence_band`, `frame.phase`, `ctx.options`, `ctx.progress`, `ctx.hud.power_band`, `local_intents`, `apply_progress`, `picker_image` | T5 G0.2, S2.2, F5 G0.3 | All exist with exactly these spellings (section 4) |
| Q18 | Whether PlayerSlot carries the haptics setting, the verified flag and the preferred cadence | T2.7, F2.7, S2.4, F2.4 | `haptics_on`, `ftp_verified`, `preferred_cadence_rpm` |
| Q19 | Whether PedalScanList reports auto-confirms | S2.6 | `item_chosen(..., auto)`, plus `item_picked(..., via)` (PSL3) |
| Q20 | Whether options have an `int` type with `step` | S2.2, F5 G0.3 | Yes (REG4) |
| Q21 | Whether `ParallaxStrip` mirrors and `SpinningPart` reverses | T3, F3.3 | Yes (W2D2, W2D3) |
| Q22 | How pixelate picks among results of one sprite | T3 | `selected` (ART4) |
| Q23 | Whether sourcing `tools/env.*` keeps `FAL_KEY` and `WATTLANDS_ALLOW_ART` | T5 G0.4, F5 G0.2 | Yes (TL7) |
| Q24 | How games declare int fields for `Protocol.decode()` | S2.6, F2.6 | `int_fields()` (GM13, PR1) |
| Q25 | Where the game loads content so `--override` works | T4 S8 | `ctx.load_content_json` (CTX16) |

## 3. Conflicts and ambiguities

### 3.1 Resolutions

Each resolution keeps BRIEF 4.6 and 7 intact and works for all three game briefs.

| # | Topic | What the game brief assumes | What BRIEF or the W0 contract says | Resolution | Owners |
| --- | --- | --- | --- | --- | --- |
| C1 | Toast and banner peer | T2.6: "`ctx.hud.toast` and `banner` take no peer", so each peer raises its own prompts. S2.6: never a host-only toast | B3.6 and `HudFeed`: optional last argument `peer`, default `Wl.ALL_PEERS` (0) = every rider | Keep BRIEF. Danger: a host that raises its own rider's prompt with the default broadcasts it to every client. GAME_SDK.md says, with a Tank-style example: on the host pass `ctx.local_peer` to draw on the host only (nothing is sent); a call on a client is always local. Both games' designs then work unchanged | ui-hud, sdk-runtime, net-client |
| C2 | Who emits `phase_changed` | S2.8, T2.8: emit it unless the GameHost does. F2.4: never, unless defined for per-rider plans | B3.6 and `GameModule`: optional, informational, games only; the GameHost emits `EventBus.phase_started` | The GameHost never emits `phase_changed`, never acts on it, and records it as a report event. Siege and Tank may emit it; Fishing doesn't need it | sdk-runtime |
| C3 | Cool-down FIT lap | S4 S5, T4 S4, F4.2 #9: "if the platform laps it" | B3.8 and `RideRecorderApi`: always its own lap | Always. GAME_SDK.md gives the expected-lap formula of FIT1 | rides, sdk-runtime |
| C4 | `mode: "SIM"` inside a SIM phase | T2.3 (boiler, hoist with `duration_s` 0) and T2.7, F2.7 (haptics of 1–5 s) send `mode: SIM` in SIM phases | The `EffortDirective` and `DirectiveSink` comments scope SIM blocks to ERG phases, but `sets_sim_block()` and `channels()` report `sim_block` for any `mode: "SIM"` whatever the phase, and nothing says what `mode: "ERG"` means in a SIM phase. Code that trusts the helpers would refuse Tank's 1.5 s haptic as a too-short block and give `mode` an expiry | A SIM block exists only in an ERG phase. In a SIM phase `mode: "SIM"` is a no-op confirmation (no channel, no length or spacing rule, no expiry); `mode: "ERG"` there is refused with `erg_in_sim_phase` **(add)**. The lead adds a phase-aware helper (`channels_for_phase(phase_mode)`) or the rule to both helpers' comments; the sink and governor never call the phase-blind helpers | trainer-control, sdk-runtime, lead |
| C5 | Haptic channel and its reporting | T2.7: if haptics have no channel of their own, re-send the mode grade after each haptic | B3.6: a separate haptic channel; `Wl.CLAMP_HAPTIC` (`haptic_limit`) is the only haptic clamp name | Separate channel as DS3 and DS8 (no Tank workaround needed). Add `Wl.CLAMP_HAPTIC_INTENSITY := "haptic_intensity"` **(add)** for the intensity scaling, and report `haptic_limit` only when the +3 % or 8 s bound bites, so F4.2 #1 and F6 can tell scaling from capping | trainer-control, lead |
| C6 | PlayerSlot haptics flag | T2.7, F2.7: skip opted-out riders "if PlayerSlot carries the setting" | B3.6 and `PlayerSlot`: `haptics_on` (plus `haptic_intensity`) | No change; GAME_SDK.md names both. Bots have `haptics_on` true; they have no trainer to feel it, and Siege and Fishing send bots none | sdk-runtime |
| C7 | Other PlayerSlot hedges | S2.4: "if `PlayerSlot` has no verified flag, add it"; F1, F2.4: preferred cadence may be missing; S2.4: WKG `r` from `p_eff_w / power_w` in telemetry, 1 before power ≥ 50 W | `ftp_verified`, `preferred_cadence_rpm` (also in `player_info`) and `p_eff_per_w` all exist; the FTP field is `ftp` | No platform change. The platform guarantees `p_eff_w == power_w × p_eff_per_w` for every sample, so Siege may use either source; GAME_SDK.md says so | platform, sdk-runtime |
| C8 | Slot patterns | S2.2: "BRIEF 3.9 pairs colors with patterns but names none" | B3.9 and `Wl.slot_look` name them: solid, dashed, dotted, double for slots 0–3 (Siege's own choice matches) | Use `Wl.slot_look`; kit chips draw color, shape, pattern and `hollow` | ui-hud, app-shell |
| C9 | Snapshot size | S2.6 ≤ 8 KB, T2.6 ≤ 4 KB, F2.6 ≤ 2 KB; relay 16 KB per message | B3.6 asks for "the JSON byte size of every snapshot" without defining it | A snapshot's bytes = UTF-8 length of `JSON.stringify(state)` (state only, no envelope, no indent); sha256 over the same bytes; `max_snapshot_bytes` is their maximum. NetSession never sends a message over 16 384 bytes: it drops it with `push_warning` and the report counts `oversize_snapshots` **(add to report)**. Conformance asserts every snapshot message fits; the games' own caps stay in their tests | sdk-runtime, net-client |
| C10 | `int_fields` on mixed arrays | S2.6: `f: [[pad, [target_ids]]]` mixes an int and an array at one depth | `apply_int_fields` knows `[]` and `{}` only | Convert numeric leaves at a matched path and leave an Array or Dictionary found there unchanged (no error). Siege declares `f[][]` and `f[][][]`. Event keys in `int_fields()` are event `"type"` values next to `"snapshot"`, so no event type may be named `snapshot`. Intents are never converted; games cast them | net-client, sdk-runtime |
| C11 | Rate limits | S2.6, T2.6: the host drops anything beyond 5 intents a second per peer | B5.3: 60 messages a second per peer (burst 120) at the relay; intents batch at 5 Hz | The platform has no intent rate limit of its own: every intent arrives once, in order, at most 32 per telemetry message (beyond that `push_warning` and drop), each ≤ 1 KB; games enforce their 5 a second. Host sends: snapshot 10 + roster 2 + events ≤ 10 + per-client directives (Fishing's 2 Hz ramps and band updates to 3 clients, Tank's 2 Hz `course_grade`) come to about 35 a second; NetSession keeps only the latest `course_grade`, `cadence_band` and `power_band` per peer per 100 ms and never drops or reorders `request` or `phase`. The e2e harness asserts no `rate_limited` | net-client, sdk-runtime, qa |
| C12 | Event order | S2.6, T2.6, F2.6: same order on every peer, ≤ 10 messages a second | `event {seq, events}` batches, GameHost batching (lead ADR) | One batch per ≤ 100 ms, flushed before the snapshot of the same tick; clients apply the events, then the snapshot; `apply_event` never runs on the host | sdk-runtime, net-client |
| C13 | `tools/screenshot` options | S4 P1 ("if `tools/screenshot` can't set the rider count and profile"), T4 P1 (player count, fast-forward), F4.3 (player count, seed, time) | B3.6 gives `--players`, `--bots`, `--rider`, `--autopilot`, `--seed`, `--at` and the fast-forward | Implement all of them through the shared `GameSimRunner` parser, plus `--ftp`, `--unverified`, `--options`, `--player-options`, `--override` and `--screenshot-dir`; HOST runs show the host's view, so Fishing's highlighted lane is slot 0 | qa, sdk-runtime |
| C14 | PedalScanList pick source and `"auto": 1` | S2.6: auto-confirmed buys carry `"auto": 1` ("if the PedalScanList doesn't report auto-confirms, add that"); F2.5: surge picks don't end the fallback either | `item_chosen(index, id, auto)` reports auto-confirms but not surge versus button; the `IntentSink` comment implies the platform adds `"auto": 1` | Add `signal item_picked(index, id, via: String)` with `via` `"action"`, `"surge"` or `"auto"`, emitted with `item_chosen` **(add)**. The game writes `"auto": 1` (or its gesture tag) into its own intent; the lead fixes the `IntentSink` comment to say the platform never edits intents. Auto-confirm fires after two full cycles in ERG even with scanning off; add `follow_local_mode` (on in sessions) so `erg_auto_confirm` follows the local rider's mode **(add)** | ui-hud, lead |
| C15 | Open-ended phases without `duration_s` | F2.3: Reels have `min_s` and `max_s` only. T2.3 gives a nominal `duration_s` | The PlanValidator stub rejects "non-positive duration" | That rule applies to fixed phases only. An open-ended phase may have `duration_s` 0 (PhaseState then shows 0; the timeline shows `min_s`–`max_s`); a ramp on an open-ended phase needs `duration_s` > 0 | sdk-runtime, ui-hud |
| C16 | Re-validating a finalized plan | B5.5: clients re-validate the `plan` they receive, which already ends with the appended cool-down | The validator rejects a game-written COOLDOWN | With `cooldown_appended` true, `validate()` checks and sets aside exactly one trailing standard cool-down (ERG 50 %, 180 s) before the rules and keeps it | sdk-runtime, net-client |
| C17 | `tools/new_game` and fragments written first | S5 G0.1, T5 G0.1 may write `docs/decisions/<id>.md` before running `tools/new_game` | B3.6: it refuses if any target path exists | Only `src/games/<id>/`, `content/<id>/`, `assets/<id>/`, `tests/games/<id>/` and, if `new_game` writes it, `.github/workflows/game-<id>.yml` trigger the refusal; the docs fragments are created only when missing and never overwritten | sdk-runtime |
| C18 | Negative `first_run_priority` | S2.2, T2.2: −1 | B3.6: "optional integer, default 0" | Any integer is valid, negative included; the registry test uses −1, 0 and 10 | sdk-runtime, app-shell |
| C19 | `--override` and content loading | T4 S8 offers `--override` | `GameContext.load_content_json` reads files directly | Add `GameContext.content_overrides: Dictionary` (rel path → merge patch), set by `GameSimRunner`; `load_content_json` applies the RFC 7386 merge first **(add)**. GAME_SDK.md tells games to load content only through it; the report records `overrides` | lead, sdk-runtime |
| C20 | Telemetry staleness | F2.4: a rider's telemetry stale > 3 s marks the lane AFK; cadence stale > 3 s freezes the meters | `Telemetry.age_s` is documented for dropped peers; no cadence age | `age_s` is set every tick for every remote rider (0 for local riders and bots). Add `Telemetry.cadence_age_s`, the seconds since the last fresh cadence value, measured or estimated **(add)** | lead, sdk-runtime, platform |
| C21 | "The first 300 s" in games | T2.3, T2.7, F2.7 gate sprints and haptics on the plan's first 300 s | `PhaseState` has no plan time | Games sum their own phase lengths; optionally add `PhaseState.plan_elapsed_s` **(add)**. The governor's own warm-up blocks haptics independently | lead, sdk-runtime |
| C22 | Detecting an overrun | T2.4 plays the overrun "if the platform ends a phase at `max_s`" | The phase changes with `ended_by` `max_s`, which reaches clients but not `PhaseState` | The game sees `remaining_s` reach 0 and the index advance without its own `end_phase`; optionally add `PhaseState.prev_ended_by` **(add)** | sdk-runtime, lead |
| C23 | Gear indicator | S3: "only in Overdrive" (a SIM block in an ERG phase) | `HudSpec.GEAR`: "shown in SIM phases" | Shown whenever the local trainer is in SIM, so it appears in Overdrive, Tank's SIM phases and Fishing's Landings with no game code; the lead fixes the comment | ui-hud, lead |
| C24 | Teammate strip source | S4: "a client's teammate strip shows each rider's raw W and %FTP from the snapshot" | The kit strip draws `ctx.roster` (2 Hz, host values) | No platform change. GAME_SDK.md says the strip is roster-driven; Siege tests the roster-fed strip or draws W and %FTP in its own Control from its snapshot | ui-hud, sdk-runtime |
| C25 | A directive outside `range_pct` | T2.3, F2.3 stay inside | B3.6 doesn't say clamp or refuse; the stub refuses (`outside_range_pct`) | Keep the refusal: it exposes a game bug instead of hiding it. Also add `grade_source_not_game` **(add)** for `course_grade` outside a `game` phase | trainer-control, sdk-runtime, lead |
| C26 | A SIM block during rescue, coasting, AFK or pause | S2.3 never sends one during rescue | BRIEF is silent | Refuse with `sim_block_unsafe` **(add)**; leaving rescue's 50 % for SIM would undo the protection | trainer-control, lead |
| C27 | `power_band` called on the rider's own peer | S2.4, T3 call it client-side for their own rider | B3.6 routes host calls; a client call "draws only on that client's HUD" | A call for the caller's own rider also feeds that peer's MockTrainer (so `erg` rides the band in SIM in HOST simulations), and sends nothing. Bands hold until replaced or (0, 0); the cool-down clears them; Tank clears it when its rider leaves the diesel | sdk-runtime, ui-hud, trainer-core |
| C28 | Process-wide statics with in-process peers | S4, T4, F4.2 run HOST simulations with several peers in one process | `Paths.set_override` and `CmdLine` are process-wide statics | Inside a session the GameHost and `GameSimRunner` pass explicit per-slot paths (progress, rides) and never call `Paths.user_dir()`; session code uses `ctx.events` and the GameHost's `net`, never the `EventBus` or `NetSession` autoloads | sdk-runtime, platform, net-client |
| C29 | Determinism, HOST runs included | S4 S7, T4 S7, F4.2 #8 | B3.6: same arguments and seed, same `deterministic_hash` | Every timer on the sim path runs on `SimClock`: governor rules, gestures, mock notifications (jitter, noise and dropouts seeded per slot), 5 Hz telemetry, roster, snapshots, event batches and loopback delivery in a fixed tick order; dictionaries iterate in sorted peer order; the hashed report holds no wall-clock value | sim, trainer-core, trainer-control, platform, net-client, sdk-runtime |
| C30 | The `surge` profile and the ERG `surge` gesture | S4 S10: at least 3 Overdrives a run from `surge:for_s=2` | B3.5: flywheel speed ≥ 1.12 × its 10 s average for 1.5 s, "two consecutive samples at about 1 Hz"; notifications jitter | A 2 s lift could hold one sample and miss the gesture. MockTrainer aligns each surge so it spans at least two notifications; the test fires 10 surges and expects 10 gestures | trainer-core, sim |
| C31 | Composing `cadence_drop` | T4 S5 needs two drops in one rider; F4.2 #7 uses `erg+band+cadence_drop` | B4.2 says profiles combine with `+` | Components may repeat and each instance is independent; precedence as MR1 | trainer-core |
| C32 | kJ inside `results()` | S2.8, T2.8, F2.8 compute XP from kJ | — | `ctx.stats` is final when `results()` runs; `GameResults.from_stats` pre-fills every row. No change | sdk-runtime |
| C33 | `apply_progress` exactly once | S4: XP once per session, including a client restarted during the cool-down | — | Called only after `results` arrives (after the cool-down), once per peer process; optionally add `GameResults.session_id` **(add)** so a peer that gets results twice can skip | sdk-runtime, lead |
| C34 | Telling Autopilot intents apart | S2.3: Overdrive "never from Autopilot's own intents or from bots" | The platform merges `autopilot_intents` into the rider's intents | The platform doesn't tag merged intents; a game that needs to tell them apart tags its own `autopilot_intents()` output **(doc)** | sdk-runtime |
| C35 | SIM inside the first 300 s | S2.3 forbids it for itself; T2.3 (depot) and F2.3 (`e2e_2min` Landing) use it | 4.6.8 allows SIM with grade −2…+3 % | The validator accepts SIM there; the governor clamps. Siege's stricter rule is its own | sdk-runtime |
| C36 | Pixel import preset | T3, F3.4 expect pixelated sprites with filter off and mipmaps off | B3.9 puts the preset in world2d; B3.10 has pixelate write PNGs "with the pixel import preset" | In Godot 4 filtering is per CanvasItem: `PixelViewport` sets nearest. The lead adds texture importer defaults to `project.godot` (mipmaps off, lossless; no 3D game uses textures), so pixelate writes plain PNGs and no hand-made `.import` files. world-kits documents the preset | lead, world-kits, art-pipeline |
| C37 | Per-peer events in e2e reports | F4.3: "checked from the harness's per-peer event logs if it writes them" | B3.6: the report holds "events per peer" | Include every peer's game events in order (host: sent; clients: applied), so a game's `e2e_check.mjs` can assert them | qa |
| C38 | Art spend total | T1, F1: spend "summed from `art_manifest.json`" | The manifest records estimate and billed cost per request | Also write a top-level spend total (the larger of the two per paid request) **(add)** | art-pipeline |

### 3.2 Additive contract changes for the lead

Frozen files only the lead may change; each item is additive and comes from 3.1.

1. `Wl`: `CLAMP_HAPTIC_INTENSITY := "haptic_intensity"` (C5); `REFUSE_ERG_IN_SIM := "erg_in_sim_phase"` (C4); `REFUSE_NOT_GAME_GRADE := "grade_source_not_game"` (C25); `REFUSE_SIM_BLOCK_UNSAFE := "sim_block_unsafe"` (C26).
2. `EffortDirective`: document that a SIM block exists only in an ERG phase, or add `channels_for_phase(phase_mode: String)` (C4).
3. `GameContext`: `content_overrides: Dictionary`, applied by `load_content_json` (C19).
4. `Telemetry`: `cadence_age_s`; document that `age_s` is set every tick for remote riders (C20). Optional: `haptic_pct` (the applied haptic, for report traces).
5. `PedalScanList` (frozen W0 stub): `signal item_picked(index: int, id: Variant, via: String)` and `var follow_local_mode: bool` (C14).
6. `IntentSink`: comment fix, the platform never edits intents (C14).
7. `HudSpec.GEAR`: comment fix, shown whenever the trainer is in SIM (C23).
8. Optional: `PhaseState.plan_elapsed_s` and `prev_ended_by` (C21, C22); `GameResults.session_id` (C33); `WlSfx.synth(..., loop := false)` (AU1).
9. `project.godot`: texture importer defaults (C36).
10. `GameSimRunner` report keys: `slots`, `plans`, `plan_warnings`, `finished_reason`, `overrides`, `oversize_snapshots`, `schema`, `meta` (SIM4, C9); sdk-runtime owns the file, so this is a stub doc update rather than a contract change.

## 4. Names the platform must use exactly

The W3 SDK-completeness reviewer ticks each name against the code and `docs/GAME_SDK.md`. Every name here is cited by at least one game brief, or by BRIEF 3.6/3.7 where a game brief relies on it.

**Classes and autoloads**

- [ ] `GameModule`, `GameContext`, `PlayerSlot`, `EffortPlan`, `PlanPhase`, `PhaseState`, `EffortDirective`, `DirectiveSink`, `InputFrame`, `Telemetry`, `HudSpec`, `GameResults`, `ProgressStore`
- [ ] `GameRegistry` (autoload), `GameHost`, `PlanValidator`, `EventBus` (autoload), `NetSession` (autoload), `Protocol`, `LoopbackTransport`
- [ ] `PedalScanList`, `PixelViewport`, `ParallaxStrip`, `SpinningPart`, `SlidingPart`, `PaletteSwap`, `SpriteWobble`, `LowPolyMesh`
- [ ] `MockTrainer`, `SafetyGovernor`, `TrainerController`, `FtmsClient`, `SprintRule`, `Paths`
- [ ] `addons/wattlands/sim/workout_import` (`ZwoImport`)
- [ ] Names Siege's and Tank's static tests scan for, which must stay the platform's only call sites: `TrainerController`, `SafetyGovernor`, `FtmsClient`, `write_control`, `set_target_power`, `set_simulation`, `set_resistance`

**GameModule**

- [ ] `configure(ctx)`, `build_effort_plans()`, `sim_step(dt, frame)`, `autopilot_intents(peer_id)`, `on_rescue(peer_id, active)`, `on_afk(peer_id, afk)`, `local_intents(actions, gestures)`, `snapshot()`, `apply_snapshot(snapshot)`, `apply_event(event)`, `client_predict(dt, local)`, `int_fields()`, `make_view()`, `hud_spec()`, `results()`, `apply_progress(results, progress)`
- [ ] Signals `lap_marker(label)`, `phase_changed(index)`, `finished(reason)`; EventBus `phase_started(peer_id, index)`

**GameContext**

- [ ] `ctx.players`, `ctx.content_id`, `ctx.seed`, `ctx.role` (`SOLO`, `HOST`, `CLIENT`), `ctx.local_peer`, `ctx.rng`, `ctx.directives`, `ctx.options`, `ctx.progress`, `ctx.hud`, `ctx.intents` (`ctx.intents.send(intent)`), `ctx.roster`, `ctx.strings`, `ctx.events`

**PlayerSlot**

- [ ] `ftp_verified`, `p_eff_per_w`, `rider_mass_kg`, `preferred_cadence_rpm`, `haptics_on`, `is_bot`, `options`; peer id, name, slot index, color, shape, pattern, FTP, scaling mode and Autopilot flag as `peer_id`, `name`, `slot_index`, `color`, `shape`, `pattern`, `ftp`, `scaling_mode`, `autopilot`
- [ ] Shapes `circle`, `triangle`, `square`, `diamond`; patterns `solid`, `dashed`, `dotted`, `double`

**Plans**

- [ ] PlanPhase `kind` (`WARMUP`, `WORK`, `RECOVERY`, `FREE`, `COOLDOWN`), `mode` (`ERG`, `SIM`), `target_pct`, `ramp_to_pct`, `range_pct`, `grade_source` (`flat`, `course`, `game`), `course_profile`, `duration_s`, `lap`, `label`, `open_ended`, `min_s`, `max_s`

**Directives**

- [ ] `ctx.directives.request(peer, EffortDirective)`, `course_grade(peer, grade_pct)`, `end_phase(peer)`, `cadence_band(peer, lo_rpm, hi_rpm)`, `replan(peer, plan)`
- [ ] EffortDirective `mode`, `target_pct`, `target_wkg`, `target_w`, `mode_grade`, `haptic`, `crr`, `cw`, `duration_s`, `reason`, `source`
- [ ] Reasons and sources the games send: `overdrive`, `bank`, `boiler`, `hoist`, `hit`, `boss_hit`, `ram`, `pull`, `run`, `jump`, `last_run`; `siege`, `tank`, `fishing` (free strings; the platform must not restrict them)

**Frame and telemetry**

- [ ] `frame.players[peer]`, `frame.phase`
- [ ] Telemetry `power_w`, `cadence_rpm`, `speed_kmh`, `effort`, `p_eff_w`, `wbal_j`, `applied_target_w`, `clamped_by`, `rescue`, `afk`, `gestures`, `intents`, `connected`, `age_s`
- [ ] `Telemetry.intents` batched at 5 Hz

**HUD**

- [ ] `ctx.hud.power_band(peer, lo_w, hi_w)`, `ctx.hud.teammate_status(peer, {in_band, icon, text})`, `ctx.hud.toast(key, args, peer)`, `ctx.hud.banner(key, args, seconds, peer)`
- [ ] Anchors `top_left`, `top`, `top_right`, `bottom_left`, `bottom`, `bottom_right`; Rect2i art-pixel positions
- [ ] Kit widgets: power gauge with target band, cadence with band, W′ bar, phase timeline with next-phase preview, teammate strip, toasts, rescue and warm-up banners, big numeric readout, gear indicator (W0 ids `power_gauge`, `cadence`, `wbal`, `timeline`, `teammates`, `readout`, `gear`)

**Inputs and gestures**

- [ ] Actions `confirm`, `back`, `up`, `down`, `left`, `right`, `ability_1`, `ability_2`, `item`, `swap`, `shift_up`, `shift_down`, `pause`, `panic`
- [ ] Gestures `pedal_start`, `surge`, `not_pedaling`, `coast`, `stop_5s`

**game.json and strings**

- [ ] `id`, `title`, `summary`, `version`, `min_players`, `max_players`, `bots`, `presentation` (`2d`, `3d`), `pixel_base`, `entry`, `contents`, `default_content`, `e2e_content`, `zero_input_content`, `first_run_priority`, `picker_image`, `options`, `player_options`
- [ ] Option entry `id`, `type` (`toggle`, `int`, `choice`), `default`, `label`, `min`, `max`, `step`, `choices` (`value`, `label`)
- [ ] Keys `<ID>_OPT_<OPTION ID>` (`SIEGE_OPT_WAVE_OFFSET`, `TANK_OPT_ROTATION`, `FISHING_OPT_REEL_PCT`, `FISHING_OPT_RELAXED_BAND`) and `<ID>_CONTENT_<CONTENT ID>`; game strings in `content/<id>/strings.csv` with prefixes `SIEGE_`, `TANK_`, `FISHING_`

**Network**

- [ ] `Protocol.decode()`, `int_fields()` paths with `[]`; messages `player_info`, `lobby_state`, `telemetry`, `snapshot`, `event`, `plan`, `phase`, `directive` (kinds `request`, `course_grade`, `cadence_band`, `power_band`), `roster`; `peer_left`; `session_in_progress`; reconnect token

**Tools and flags**

- [ ] `tools/run_game_sim` (+ `.ps1`): `--game`, `--content`, `--players`, `--bots`, `--rider`, `--sim-speed`, `--seed`, `--report`, `--autopilot=all|none|<slot,…>`, `--ftp`, `--unverified`, `--haptics-off`, `--options`, `--player-options`, `--override`, `--max-sim-seconds`
- [ ] Report: `end_reason` (`complete`, `timeout`, `paused`), `ended_by` (`duration`, `max_s`, `end_phase`, `finished`), `clamped_by`, `max_snapshot_bytes`, `fit_paths`, `deterministic_hash`; FIT path `<report dir>/fit/<report stem>_slot<n>.fit`
- [ ] `tools/new_game <id>` (+ `.ps1`)
- [ ] `tools/screenshot` (+ `.ps1`): `--game`, `--content`, `--at`, `--players`, `--bots`, `--rider`, `--autopilot`, `--seed`
- [ ] `tools/run_tests` (+ `.ps1`), `tools/godot.sh`, `tools/godot.ps1`, `tools/env.sh`, `tools/env.ps1`, `tools/check_scripts.gd`
- [ ] `node tools/e2e/run.mjs --games=<ids>`, `build/e2e/<id>/report.json`, `tests/games/<id>/e2e_check.mjs`
- [ ] `node tools/fit_check/check.mjs <file|dir>... [--expect-laps=<n>] [--json]`
- [ ] `node tools/art/generate.mjs --game --only --dry-run --budget --reroll --select --mock`; `tools/art/pixelate.gd -- --game=<id>`; `assets/<id>/art.json` (`palette`, `style`, `endpoint`, `quality`, `sprites`, `id`, `prompt`, `size`, `background`, `parts`, `anchor`, `align`, `tile`, `mirror`); `assets/<id>/art_manifest.json`; `assets/<id>/sprites/<sprite id>.png`; endpoints `openai/gpt-image-2.5/sunburst/text-to-image` and `openai/gpt-image-2.5/flare/text-to-image`
- [ ] `tests/sdk/test_conformance.gd`; GUT `addons/gut/gut_cmdln.gd` with `-gdir`, `-ginclude_subdirs`, `-gexit`, `-gjunit_xml_file`

**Mock rider profiles**

- [ ] `erg` (`compliance`), `zero`, `const` (`w`, `rpm`), `band` (`offset_rpm`), `cadence_drop` (`rpm`, `at_s`, `at_phase`, `after_s`, `at_target_pct`, `for_s`), `surge` (`every_s`, `for_s`, `lift`, `sim_pct`), joined with `+`; `--mock-trainer=<profile>`

**Paths, docs and environment**

- [ ] `Paths.user_dir()`, `Paths.user_dir()/games/<id>/`, `src/games/<id>/HARDWARE_TEST.md`, `docs/GAME_SDK.md`, `docs/ART_PIPELINE.md`, `docs/ARCHITECTURE.md`, `docs/HARDWARE_TEST_PLAN.md`, `CLAUDE.md`
- [ ] `WATTLANDS_NO_HW_CONTROL`, `WATTLANDS_NO_NETWORK_INTEGRATIONS`, `FAL_KEY`, `WATTLANDS_ALLOW_ART`
