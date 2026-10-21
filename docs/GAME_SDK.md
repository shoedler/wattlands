# Game SDK

How to build a Wattlands game: the contract between a game and the platform, the tools a game session uses, and worked examples from the template game (`src/games/_template/`) and the reference game Workout (`src/games/workout/`). "BRIEF x.y" means a section of `docs/BRIEF.md`. The code is the final word: every type here is defined, with doc comments, in `addons/wattlands/contracts/` (frozen after W0; additive changes only), and the runtime that drives it lives in `addons/wattlands/sdk/`.

Read this with `CLAUDE.md` (rules, locks, conventions), `docs/ARCHITECTURE.md` (layers, time, sessions) and, for 2D pixel art, `docs/ART_PIPELINE.md`. Section 23 answers, one by one, the questions the game briefs' G0 steps ask of this document.

Contents: 1 Quick start · 2 Files and owned paths · 3 game.json · 4 GameModule · 5 GameContext · 6 PlayerSlot · 7 Effort plans · 8 Directives · 9 InputFrame, PhaseState, Telemetry · 10 HUD · 11 Input, intents and Autopilot · 12 Snapshots, events and int_fields · 13 Phases, cool-down, finishing and laps · 14 Rescue, AFK, pause, drops and rejoins · 15 Results and progression · 16 Determinism · 17 Strings · 18 Presentation and audio kits · 19 Tools · 20 MockTrainer rider profiles · 21 Safety rules for game designers · 22 Worked examples · 23 FAQ

## 1. Quick start

Every command runs from the repository root with the locks on (`. tools/env.sh` in Git Bash, `. tools\env.ps1` in PowerShell; the wrappers set them too). Each tool has a bash form and a PowerShell twin.

| Step | Git Bash | PowerShell |
| --- | --- | --- |
| Scaffold the game | `tools/new_game siege` | `tools\new_game.ps1 siege` |
| Refresh Godot's caches | `tools/godot.sh --headless --path . --import` | `tools\godot.ps1 --headless --path . --import` |
| The game's tests | `tools/godot.sh --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/games/siege -ginclude_subdirs -gexit -gjunit_xml_file=build/junit_siege.xml` | the same with `tools\godot.ps1` |
| Script check | `tools/godot.sh --headless --path . -s tools/check_scripts.gd` | `tools\godot.ps1 --headless --path . -s tools/check_scripts.gd` |
| Conformance | `tools/godot.sh --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/sdk/test_conformance.gd -gexit` | the same with `tools\godot.ps1` |
| A headless session | `tools/run_game_sim --game=siege --content=short --players=1 --bots=3 --rider=erg --sim-speed=200 --seed=1 --report=build/siege/sims/s.json` | `tools\run_game_sim.ps1 ...` (same flags) |
| Check its FIT files | `node tools/fit_check/check.mjs build/siege/sims/fit --expect-laps=12` | same |
| End to end | `node tools/e2e/run.mjs --games=siege` | same |
| Everything | `tools/run_tests` | `tools\run_tests.ps1` |

The loop: `tools/new_game <id>` copies the template into your paths, renamed. Edit `game.json`, replace the template's rules, view and HUD with your own, keep the tests green, then run the simulation matrix with `tools/run_game_sim` and check the reports.

## 2. Files and owned paths

A game session owns exactly these paths and edits nothing else (platform changes follow the platform-change policy in `CLAUDE.md`):

| Path | Holds |
| --- | --- |
| `src/games/<id>/` | `game.json`, the GameModule entry script, rules, view, HUD code, `README.md`, `HARDWARE_TEST.md` |
| `content/<id>/` | JSON content (validated at load) and `strings.csv` |
| `assets/<id>/` | Art, audio, `art.json` and `art_manifest.json` for generated art |
| `tests/games/<id>/` | GUT tests (`test_*.gd`), helpers, fixtures, `e2e_check.mjs`, simulation scripts |
| `.github/workflows/game-<id>.yml` | The game's CI |
| `docs/decisions/<id>.md`, `docs/credits.d/<id>.md`, `docs/changelog.d/<id>.md` | ADRs, credits and changelog fragments; the lead merges them |

Naming rules (BRIEF 6):

- Every `class_name` under `src/games/<id>/` and `tests/games/<id>/` starts with the game's prefix (`SiegeTower`, `TankShell`, `FishingLaneState`). Platform classes never use a game prefix.
- Every string key starts with the upper-case id and an underscore (`SIEGE_`, `TANK_`, `FISHING_`). The template's keys start with `_TEMPLATE_` (its id is `_template`).
- Extend platform classes by class name (`extends GameModule`), never by path.
- Load content only with `ctx.load_content_json(rel_path)`, so `run_game_sim --override` reaches it (section 5).
- Commit the `*.uid` and `*.import` files Godot writes for your files.

What `tools/new_game <id>` produces (section 19.2): `src/games/<id>/` with `game.json`, `<id>_game.gd` (`<Id>Game`), `<id>_rules.gd` (`<Id>Rules`), `<id>_view.gd` (`<Id>View`), `README.md` and `HARDWARE_TEST.md`; `content/<id>/` with `default.json`, `short.json` and `strings.csv`; `assets/<id>/README.md`; `tests/games/<id>/` with `<id>_fakes.gd` (`<Id>Fakes`), three unit test files and `integration/test_<id>_session.gd`; the CI workflow; and the three docs fragments where missing. All of it passes its tests and conformance before you change a line.

## 3. game.json

`src/games/<id>/game.json` declares the game. The `GameRegistry` autoload scans `res://src/games/*/game.json` at startup, validates each with `GameRegistry.validate_manifest()`, registers each valid game's translations and lists the valid games in the picker. An invalid game is hidden with a logged reason that names the field (`push_warning`), never a crash, and `tests/sdk/test_conformance.gd` fails on it, so a broken game can't pass by being hidden. `_template` is never listed.

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `id` | String | yes | The game id, `^[a-z][a-z0-9_]*$`, equal to the folder name |
| `title` | String | yes | Shown in the picker (plain text) |
| `summary` | String | yes | One line for the picker |
| `version` | String | yes | `"0.1.0"`; a client with another version can't ready up |
| `min_players`, `max_players` | int | yes | Human plus bot slots, 1..8 |
| `bots` | bool | yes | True if bots may fill slots (the lobby's Add bot / Remove bot) |
| `presentation` | `"2d"` or `"3d"` | yes | 2D views go into a `PixelViewport` |
| `pixel_base` | `[w, h]` | 2D only | Art resolution, for example `[640, 360]` |
| `entry` | res path | yes | The GameModule script, for example `res://src/games/siege/siege_game.gd` |
| `contents` | Array of String | yes | Content ids the lobby offers |
| `default_content` | String | yes | One of `contents` |
| `e2e_content` | String | yes | About 2 minutes, for `tools/e2e/run.mjs` |
| `zero_input_content` | String | yes | What a solo 5 s `pedal_start` on the title screen, or the first run, plays |
| `first_run_priority` | int | no, default 0 | The first run plays the registered game with the highest value; ties go to `workout`, then to the lowest id. Any integer is valid, negative included (Siege and Tank use −1; Fishing uses 10; Workout is 0) |
| `picker_image` | res path | no | A 16:9 picker card. A missing or unreadable file logs a warning and the picker draws a generated card; the game stays listed |
| `options` | Array of option entries | no | Session-wide options set by the host in the lobby; values in `ctx.options` |
| `player_options` | Array of option entries | no | Per-rider options set on each rider's lobby card; values in `PlayerSlot.options` |

**Option entries.** Each entry is `{"id", "type", "default", "label"?}` plus its type's fields. An unknown `type`, or a `default` outside its range or choices, makes the game invalid.

| `type` | Extra fields | Value | Example |
| --- | --- | --- | --- |
| `toggle` | none | bool | `{"id": "rotation", "type": "toggle", "default": true, "label": "TANK_OPT_ROTATION"}` |
| `int` | `min`, `max`, `step` (optional, default 1) | int, `min <= v <= max` | `{"id": "wave_offset", "type": "int", "min": -10, "max": 5, "step": 1, "default": 0, "label": "SIEGE_OPT_WAVE_OFFSET"}`; `{"id": "reel_pct", "type": "int", "min": 50, "max": 70, "step": 5, "default": 60}` |
| `choice` | `choices`: `[{"value", "label"}]` | one of the values (any JSON value) | `{"id": "track", "type": "choice", "default": 400, "choices": [{"value": 400, "label": "_TEMPLATE_TRACK_400"}, {"value": 800, "label": "_TEMPLATE_TRACK_800"}]}` |

- `label` is a key in the game's `strings.csv`; it defaults to `<ID>_OPT_<OPTION ID>` in upper case (`SIEGE_OPT_WAVE_OFFSET`). Each content id shows with the key `<ID>_CONTENT_<CONTENT ID>` (`SIEGE_CONTENT_SHORT`), or as the bare id when that key is missing.
- Keep an `int` default on the `min + n × step` grid; the lobby stepper moves in `step`s.
- The lobby fills every option's default, so `ctx.options` and each slot's `options` always hold every id. Bots get the `player_options` defaults. `GameRegistry.resolve_options(id, values, per_player)` fills defaults, validates values and drops unknown keys with a warning; `run_game_sim --options` and `--player-options` go through it (an out-of-range value exits non-zero naming the field).

Worked example: `src/games/_template/game.json` (one `toggle`, one `choice`, one per-rider `int` with `step` 5, `first_run_priority` −1 so a game scaffolded from it never takes the first run by accident).

## 4. The GameModule contract

A game is one `GameModule` subclass (`addons/wattlands/contracts/game_module.gd`, `extends Node`), named by `game.json` `entry`. Every method has a safe default, so override only what you use. The `GameHost` (`addons/wattlands/sdk/game_host.gd`) owns the session around it on each peer, in one of three roles (`ctx.role`): `SOLO` (one human, bots allowed, no network), `HOST` (simulates everything for several humans) and `CLIENT` (no game simulation; renders the host's state).

Life cycle on every peer: `configure(ctx)` → (host/SOLO: `build_effort_plans()`, validated) → `make_view()` and `hud_spec()` on rendering peers → the session runs → (host/SOLO: `results()`) → `apply_progress(results, ctx.progress)` on every peer → the results screen.

| Method | Called on | When | What to do |
| --- | --- | --- | --- |
| `configure(ctx: GameContext)` | every peer | once per session, before anything else, with every `ctx` field set | Call `super.configure(ctx)` (it stores `ctx`), load and validate content, build your state. Clients build the same state; snapshots overwrite it |
| `build_effort_plans() -> Dictionary` | host, SOLO | once, after `configure` | Return `{peer_id: EffortPlan}` for every slot in `ctx.players`, bots (negative ids) included. Each goes through `PlanValidator.finalize`; any rejection stops the start with the validator's errors (and `run_game_sim` exits 3 naming them). Each client receives its own plan as a `plan` message |
| `sim_step(dt: float, frame: InputFrame)` | host, SOLO | every 0.05 s of game time (`dt` is always `Wl.SIM_DT`); never while paused; through the cool-down too (`frame.phase` kind `COOLDOWN`) | Advance your rules; change trainer load only through `ctx.directives` |
| `autopilot_intents(peer_id) -> Array` | host, SOLO | every tick, for bots and riders with `autopilot` true only | Return the game choices Autopilot makes for that rider. Appended after the rider's own intents in `frame.players[peer].intents`. Never effort changes |
| `on_rescue(peer_id, active: bool)` | host, SOLO | once per transition, on the first tick the rider's `rescue` flag changes (remote riders up to 0.2 s later) | A stagger, never a wipe. `false` comes when the rescue hold ends (cadence ≥ 70 rpm for 3 s); the governor's 10 s ramp-back starts then |
| `on_afk(peer_id, afk: bool)` | host, SOLO | once per transition: `true` at the multiplayer coasting AFK (10 s not pedaling) and on a dropped peer in the same tick; `false` once fresh telemetry from that peer shows pedaling | Keep the slot; freeze or hand over its station. A SOLO coasting rider pauses instead (no `on_afk`) |
| `local_intents(actions: Array[StringName], gestures: Array[StringName]) -> Array` | every peer | every tick, for the local rider only | Turn this tick's input actions and pedal gestures into intents (section 11) |
| `snapshot() -> Dictionary` | host | every second tick (10 Hz) | Compact, JSON-safe full state (section 12) |
| `apply_snapshot(snapshot: Dictionary)` | clients | in `seq` order (older ones dropped); once right after a rejoin with the host's latest | Overwrite your state from it |
| `apply_event(event: Dictionary)` | clients only, never host or SOLO | each event once, in the host's emission order, before that tick's snapshot | Apply it; raise local effects (toasts, sounds) |
| `client_predict(dt: float, local: Telemetry)` | clients | every 0.05 s, after any snapshot applied that tick, with the client's own latest telemetry | Move your own rider ahead of the next snapshot |
| `int_fields() -> Dictionary` | every peer | when decoding messages | Declare the int fields of your snapshot and events (section 12) |
| `make_view() -> Node` | rendering peers (never headless runs) | after `configure` | 2D: a `Node2D` the GameHost puts in a `PixelViewport` at `pixel_base`; 3D: a `Node3D` with its own camera. The view only reads state |
| `hud_spec() -> HudSpec` | rendering peers | after `configure` (so it may use `ctx.players` and `ctx.local_peer`) | Which kit widgets show and where, plus your own Controls (section 10) |
| `results() -> GameResults` | host, SOLO | once: after the cool-down, or when a `run_game_sim` run ends by `timeout` or `paused` (`ctx.stats` is final then) | Grade, rows, XP, unlocks (section 15). The GameHost sends it to every client |
| `apply_progress(results: GameResults, progress: ProgressStore) -> Array` | every peer | once per session, after `results` arrives and before the results screen | Update the local rider's progress (`progress` is `ctx.progress`) and return the local rider's new unlock ids. The platform saves the store afterwards |
| `session_preview(content_id) -> Dictionary` | any peer, before `configure` | in the lobby | Optional `{"title", "total_s", "lines"}` for the session preview (for example a .zwo importer's clamp list); `{}` shows nothing extra |

| Signal | Emitted by | Effect |
| --- | --- | --- |
| `game_event(event: Dictionary)` (emit with `send_event(event)`) | the game, host/SOLO | Batched (at most 10 messages a second), delivered in order to every client's `apply_event`, recorded in the run_game_sim report's events. JSON-safe, with a `"type"` key |
| `lap_marker(label: String)` | the game, optional | A FIT lap at this point. Plan phases with `lap: true` and the cool-down make their own laps, so never emit it for those |
| `phase_changed(index: int)` | the game, optional and informational | The GameHost never emits it and never acts on it; it records it in the report as `{"type": "game_phase_changed", "index": n}`. Per-rider phases come from `frame.phase` and `EventBus.phase_started(peer_id, index)` |
| `finished(reason: String)` | the game, host/SOLO | The game is over: every rider not yet in the cool-down ends its phase (`ended_by: "finished"`) and starts the cool-down; unused phases never start. Idempotent. Emitted during the cool-down it only records the reason. The report keeps `finished_reason` |

What each role runs:

- **SOLO**: `configure`, `build_effort_plans`, `sim_step` (with `autopilot_intents` merged and `local_intents` for the one human), `on_rescue`, `on_afk` (never for the human: a coasting solo rider pauses), `make_view`, `hud_spec`, `results`, `apply_progress`. Never `snapshot`, `apply_snapshot`, `apply_event` or `client_predict`.
- **HOST**: everything SOLO runs, plus `snapshot` at 10 Hz and `send_event` delivery to clients.
- **CLIENT**: `configure`, `local_intents`, `apply_snapshot`, `apply_event`, `client_predict`, `make_view`, `hud_spec`, `apply_progress`. Never `build_effort_plans`, `sim_step`, `autopilot_intents`, `on_rescue`, `on_afk` or `results`. `ctx.directives` calls on a client are ignored with a warning.

Worked example: `src/games/_template/template_game.gd` overrides every method above and uses every signal; section 22 walks through it.

## 5. GameContext

`ctx` (`addons/wattlands/contracts/game_context.gd`), built by the GameHost once per peer and session:

| Field | Type | Meaning |
| --- | --- | --- |
| `game_id` | String | This game's id |
| `manifest` | Dictionary | The validated `game.json` |
| `players` | `Array[PlayerSlot]` | Every slot, sorted by `slot_index` 0..n−1, humans first then bots, identical on every peer. No peer outside it ever appears in `frame.players` |
| `content_id` | String | The lobby's content, one of `contents` |
| `seed` | int | The session seed, the same on every peer (`--seed` in tools) |
| `role` | String | `Wl.SOLO`, `Wl.HOST` or `Wl.CLIENT`; `is_authority()` is true for SOLO and HOST |
| `local_peer` | int | This machine's rider (the host's own in HOST and SOLO). Host peer id is `Wl.HOST_PEER` (1); clients 2..; bots negative |
| `rng` | RandomNumberGenerator | Seeded from `seed`, one per module instance; the only randomness your rules may use |
| `directives` | DirectiveSink | Section 8 |
| `options` | Dictionary | Every `options` id with defaults filled; the host's lobby values, the same on clients |
| `progress` | ProgressStore | The local rider's progression for this game (section 15) |
| `hud` | HudFeed | Section 10 |
| `intents` | IntentSink | `ctx.intents.send(intent)` for your own widgets (section 11) |
| `roster` | Dictionary | The latest roster, keyed by int peer id: `{raw_w, cadence_rpm, ftp_pct, rescue, afk, connected, status: {in_band, icon, text}, name, slot_index}`; 2 Hz on every peer, host included |
| `strings` | GameStrings | `ctx.strings.t(key, args)` (section 17) |
| `events` | WlEventBus | This peer's EventBus (a private instance per peer in in-process simulations); never use the `EventBus` autoload from session code |
| `stats` | SessionStats | Host/SOLO: per-rider ride statistics; final when `results()` runs; `kj(peer)` and `best_power(peer, window_s)` work live |
| `scaling_mode` | String | The lobby's effort scaling: `Wl.FAIR_FTP`, `Wl.WKG` or `Wl.RAW` (BRIEF 3.3) |
| `game_dir`, `content_dir`, `assets_dir` | String | `res://src/games/<id>`, `res://content/<id>`, `res://assets/<id>` |
| `content_overrides` | Dictionary | `run_game_sim --override` patches: rel path under `content_dir` → RFC 7386 merge patch |

Helpers: `is_authority()`, `player(peer) -> PlayerSlot` (null if unknown), `peers() -> Array[int]` (slot order), `local_player() -> PlayerSlot`, `load_content_json(rel_path) -> Variant` (reads `content/<id>/<rel_path>`, applies the matching override patch first, returns null with `push_error` on a missing or invalid file) and the static `GameContext.merge_patch(target, patch)`.

## 6. PlayerSlot

One rider (`addons/wattlands/contracts/player_slot.gd`). Every field exists on the host and on every client.

| Field | Meaning |
| --- | --- |
| `peer_id` | int; bots are negative (`Bots.peer_id(n)` = −n) |
| `name` | The rider's name; bots are `Bot n` |
| `slot_index` | 0..n−1, contiguous, the same on every peer |
| `color`, `shape`, `pattern`, `hollow` | The slot's session look from `Wl.slot_look(slot_index)`: slots 0–3 are (red, circle, solid), (blue, triangle, dashed), (yellow, square, dotted), (green, diamond, double); slots 4–7 repeat them with `hollow` true. Always pair a color with its shape or pattern |
| `ftp` | Watts. ERG targets always come from it, in every scaling mode |
| `ftp_verified` | False means the governor multiplies every ERG target by 0.85. Bots are verified |
| `scaling_mode` | The lobby's mode |
| `p_eff_per_w` | P_eff per raw watt, computed by the rider's own client: 250 / FTP (FAIR_FTP), 75 / weight (WKG), 1 (RAW). Every telemetry sample has `p_eff_w == power_w × p_eff_per_w`, so a game may use either |
| `rider_mass_kg` | The speed model's mass: 75 unless RAW with the weight shared |
| `preferred_cadence_rpm` | The profile's preferred cadence (default 90; bots 90); reaches the host in `player_info` |
| `haptics_on` | False when the rider opted out: skip them. The governor also drops any haptic that still arrives. Bots are true |
| `haptic_intensity` | 0..1; the rider's governor applies it. Games never scale haptics |
| `autopilot` | Autopilot on (profile or lobby flag; bots true; `run_game_sim --autopilot`) |
| `is_bot` | True for bots |
| `options` | Every `player_options` id with defaults filled (lobby card, `player_info`, or `run_game_sim --player-options`) |

## 7. Effort plans

A plan is the rider's whole session: `EffortPlan.phases`, an ordered `Array[PlanPhase]`. Plans may differ per rider (Fishing) or share every boundary (Siege, Tank). A game never writes a cool-down: the `PlanValidator` appends it.

### 7.1 PlanPhase

| Field | Meaning |
| --- | --- |
| `kind` | `Wl.WARMUP`, `Wl.WORK`, `Wl.RECOVERY`, `Wl.FREE`; `Wl.COOLDOWN` only from the validator (a game-written one is rejected) |
| `mode` | `Wl.ERG` or `Wl.SIM` |
| `target_pct` | ERG: the planned target in % of the rider's own FTP at the phase start |
| `ramp_to_pct` | ERG, optional: a linear ramp from `target_pct` across `duration_s` (`PlanPhase.NONE` = no ramp) |
| `range_pct` | ERG, optional `[lo, hi]`: how far directives may move the target in this phase. Default `[target, target]` (with a ramp, the ramp's span). A directive outside it is refused `outside_range_pct` |
| `grade_source` | SIM: `"flat"` (0 % plus virtual gears), `"course"` (follows `course_profile` by the speed model's distance) or `"game"` (the game pushes the grade with `ctx.directives.course_grade`) |
| `course_profile` | SIM `course`: `[[distance_m, grade_pct], ...]`, distance ascending from 0. Tank stores terrain in this format and pushes it as `game` |
| `duration_s` | Fixed phases: the length. Open-ended phases: a nominal length for previews and ramps only; it may be 0 (the timeline then shows `min_s`–`max_s`; a ramp on an open-ended phase needs `duration_s` > 0) |
| `open_ended`, `min_s`, `max_s` | The game ends the phase with `ctx.directives.end_phase(peer)` once `min_s` has passed; the platform ends it at `max_s` (`ended_by: "max_s"`). Needs 0 < `min_s` ≤ `max_s` |
| `lap` | True: the ride recorder starts a FIT lap at this phase's start. A lap-false phase continues the current lap |
| `label` | A strings key or plain text: the HUD shows `ctx.strings.t(label)` (plain text passes through); also the FIT lap name |
| `meta` | Game data the platform carries and never reads (Siege's wave role) |

Builders: `PlanPhase.erg(kind, target_pct, duration_s, label)` and `PlanPhase.sim(kind, grade_source, duration_s, label)`, then the chainable `.with_ramp(to_pct)`, `.with_range(lo, hi)`, `.with_open(min_s, max_s)`, `.with_lap()`, `.with_course(profile)` and `.with_meta(dict)`. Plans: `EffortPlan.of([...])` or `EffortPlan.new().add(phase)`. Helpers: `planned_pct_at(elapsed_s)`, `effective_range()`, `peak_pct()`, `worst_case_length_s()` (`max_s` for open-ended phases), `best_case_length_s()` (`min_s`), `EffortPlan.nominal_length_s()`, `max_length_s()`, `cooldown_index()`, `to_dict()`/`from_dict()`.

```gdscript
var plan := EffortPlan.of([
	PlanPhase.erg(Wl.WARMUP, 50, 300, "SIEGE_WARMUP_WAVE").with_ramp(65).with_lap(),
	PlanPhase.erg(Wl.WORK, 55, 180, "TANK_ADVANCE").with_range(55, 100).with_open(90, 300).with_lap(),
	PlanPhase.sim(Wl.WORK, Wl.GRADE_FLAT, 30, "FISHING_LANDING"),
])
```

### 7.2 The PlanValidator

`PlanValidator.validate(plan, opts = {}) -> {"ok": bool, "errors": Array[String], "warnings": Array[String]}` is static, pure, %-only (the same answer at every FTP) and needs no GameHost, so plan tests can run thousands of plans. `PlanValidator.finalize(plan) -> EffortPlan` returns a copy with the cool-down appended (`cooldown_appended` true), or null with a `push_warning` of the errors. `PlanValidator.cooldown_phase()` is that phase: `COOLDOWN`, ERG 50 %, 180 s, `lap` true, label `Cool-down`.

It rejects a plan when:

- **Structure**: the plan is empty; a kind or mode is unknown; a fixed phase has `duration_s` ≤ 0; an open-ended phase lacks 0 < `min_s` ≤ `max_s`; a `course` phase has no profile; the game wrote a `COOLDOWN` (a finalized plan with `cooldown_appended` true is re-validated by setting aside exactly one trailing standard cool-down, which is how clients re-validate their `plan` message).
- **Warm-up (BRIEF 4.6.8)**: in the first 300 s, every ERG `target_pct`, `ramp_to_pct` and `range_pct` bound is ≤ 65 %. Open-ended phases count at `min_s` to decide which phases fall inside the first 300 s. SIM phases are allowed there: the governor clamps their grade to −2…+3 % and drops haptics during the rider's warm-up.
- **Caps (BRIEF 4.6.1)**: any ERG value above 150 % or below 0; a phase longer than 300 s (open-ended: its `max_s`) above 105 % (inclusive: 105 is allowed), checked on `target_pct`, `ramp_to_pct` and `range_pct`.
- **Duration limits (BRIEF 4.6.1)**: more than 300 s accrued above 105 %, or more than 60 s above 120 %, without a reset in between. Open-ended phases accrue at `max_s` and at their range top. A reset is ≥ 120 consecutive ERG seconds at ≤ 90 % (inclusive; open-ended phases count at `min_s`). A SIM phase restarts the reset count and accrues nothing.

It warns (never rejects) when two ERG ↔ SIM switches are less than 30 s apart (strictly; exactly 30 s gives none; open-ended phases at `min_s`). Games assert `warnings` is empty. `opts` takes `{"ramp_test": true}` for the FTP test's profile only.

`ctx.directives.replan(peer, plan)` replaces a rider's remaining plan between phases with the same validation; a rejection keeps the old plan.

## 8. Directives: the only way to change trainer load

`ctx.directives` (`DirectiveSink`). On the host and in SOLO the sink checks each call against the rider's plan and current phase, assigns an id and routes it: a local rider's governor directly (`LocalRider.apply_directive`), a remote rider's through a `directive` message, where the client's own governor re-validates and clamps it and reports what it applied in `Telemetry.acks`. Every refusal is logged with `push_warning`, returned, and recorded; every applied record reaches `ctx.events.directive_applied(peer, record)` on the host, and the run_game_sim report keeps each directive as requested and as applied. The network never carries device commands (BRIEF 4.6.7).

| Call | Use |
| --- | --- |
| `request(peer, directive: EffortDirective) -> DirectiveResult` | An ERG target, a SIM block, a mode grade, a haptic or the `crr`/`cw` factors, inside the current phase |
| `course_grade(peer, grade_pct)` | The live course grade in a `grade_source: "game"` phase. Coalesced to 2 Hz, stacked by BRIEF 4.6.6, holds until the next call or the phase end. Outside a `game` phase it is recorded with reason `grade_source_not_game` |
| `end_phase(peer) -> bool` | Ends an open-ended phase after `min_s`. False (with `push_warning`, recorded `before_min_s` or `not_open_ended`) otherwise. It takes effect at the end of the current tick, so every call in one `sim_step` changes phase on the same tick, and the next `frame.phase` shows the new index at elapsed 0. Remote riders follow through their `phase` message |
| `cadence_band(peer, lo_rpm, hi_rpm)` | Publishes the cadence band you want. The rider's HUD cadence widget draws it (`cadence_band_changed`), bots and MockTrainer's `band` profile follow it; it never changes trainer load. Holds across phases until replaced; `cadence_band(peer, 0, 0)` clears it; the cool-down clears every band |
| `replan(peer, plan) -> bool` | Section 7.2 |

`request` returns a `DirectiveResult` `{accepted, id, reason}` for the host-side checks; the governor still clamps what it accepts.

### 8.1 EffortDirective

Build it with `EffortDirective.from_dict({...})` (or `make`). Unset fields stay unset (NAN or `""`), and `to_dict()` emits only the fields you set plus `duration_s`, so the report's `requested` shows exactly your keys.

| Field | Channel | Meaning |
| --- | --- | --- |
| `target_pct`, `target_wkg`, `target_w` | ERG target | A new ERG target; `target_w` and `target_wkg` are converted to % FTP before every check |
| `mode` | SIM block | `"SIM"` in an ERG phase opens a SIM block; see below |
| `mode_grade` | mode grade | A game's own load in % grade (Tank's boiler), only inside a SIM phase or a SIM block |
| `haptic` (grade %), `haptic_wind` (m/s) | haptic | A short effect before the rider's intensity, at most +3 % (or the same force as wind) for at most 8 s |
| `crr`, `cw` | factors | Relative factors in [0.5, 1.0]: they can only lower resistance |
| `duration_s` | — | Applies to the channels this request sets; 0 (default) means until the phase ends |
| `reason`, `source` | — | Free strings for the report (`"overdrive"`, `"siege"`); the platform never restricts them |
| `id` | — | Assigned by the sink |

**Channels and expiry.** A request touches only the channels whose fields it sets. A later request on a channel replaces it and cancels that channel's pending expiry. When a request's `duration_s` runs out, only its channels revert: the ERG target to the phase's planned target (ramp included), a SIM block back to ERG through the ramped switch, `mode_grade`, the factors and the haptic to none. Every channel resets when the phase changes. Expiry counts game time rounded to whole ticks, so it stops while paused. Channel values and expiries keep counting under rescue and coasting, which only override the applied target; after a rescue hold, the 10 s ramp-back heads for the channel's current value (a run that expired during rescue lands on the base pull).

**`mode` depends on the phase.** In an ERG phase, `mode: "SIM"` opens a SIM block: 10 s ≤ `duration_s` ≤ 30 s (inclusive), starting ≥ 30 s after the rider's previous ERG ↔ SIM switch; its two bracketing switches are exempt from the 30 s spacing. It is refused during rescue, coasting, AFK or pause (`sim_block_unsafe`). In a SIM phase, `mode: "SIM"` is a no-op confirmation (no channel, no length or spacing rule, no expiry effect), so Tank's 1.5 s hit haptic and Fishing's 5 s last run are fine there; `mode: "ERG"` in a SIM phase is refused (`erg_in_sim_phase`). `EffortDirective.channels_for_phase(phase_mode)` gives the channels a request touches in a phase of that mode.

**Haptics** are a channel of their own: a haptic over a held `mode_grade` changes only the haptic term, and its expiry ends only the haptic (the grade stays). The governor multiplies `haptic` by the rider's `haptic_intensity` and caps +3 % and 8 s. A haptic is dropped, logged and recorded (never turned into a mode switch) for a rider in ERG (`haptic_in_erg`), in that rider's warm-up (`haptic_in_warmup`), opted out (`haptics_off`), or within 15 s of the end of that rider's last applied haptic (`haptic_cooldown`).

### 8.2 Refusals and clamps

Refusal reasons (`DirectiveResult.reason`, `Wl.REFUSE_*`):

| Reason | When |
| --- | --- |
| `no_phase` | The rider has no active phase |
| `cooldown` | Every `request`, `course_grade`, `end_phase` and `cadence_band` during the cool-down is refused and recorded, so a game's check can see a violation |
| `outside_range_pct` | An ERG target outside the phase's `range_pct` (kept as a refusal, not a clamp: it exposes a game bug) |
| `sim_block_length` | A SIM block with `duration_s` outside [10, 30] |
| `switch_spacing` | A SIM block less than 30 s after the rider's previous switch |
| `sim_block_unsafe` | A SIM block during rescue, coasting, AFK or pause |
| `mode_grade_outside_sim` | `mode_grade` outside a SIM phase or block |
| `erg_in_sim_phase` | `mode: "ERG"` in a SIM phase |
| `haptic_in_erg`, `haptics_off`, `haptic_in_warmup`, `haptic_cooldown` | See haptics |
| `grade_source_not_game` | `course_grade` outside a `game` phase |
| `not_open_ended`, `before_min_s` | `end_phase` refusals |
| `bad_fields`, `unknown_peer`, `plan_invalid`, `not_authority` | Malformed request, a peer not in `ctx.players`, a rejected `replan`, a call on a client |

`clamped_by` names every rule that changed an applied value, in the order applied (`Wl.CLAMP_*`): `unverified` (×0.85), `ceiling` (min(150 % FTP, 1000 W, trainer max)), `long_phase` (105 % in phases > 300 s), `limit_105` and `limit_120` (duration limits), `warmup` (65 %, grade −2…+3, no haptics), `floor` (max(30 % FTP, 50 W)), `rescue` (50 % FTP), `coasting` (floor), `slew` (+30 W/s), `switch_ramp` (ramped ERG ↔ SIM entry), `panic`, `grade_range` (user range, default −5…+10), `grade_limit` (−10…+16), `haptic_intensity` (scaled by the rider's setting), `haptic_limit` (only when the +3 % or 8 s bound bites), `factor_bounds` and `paused`. A target exactly at a cap is neither clamped nor counted.

### 8.3 Examples

```gdscript
# Template: a +5% hill for 30 s inside range_pct [75, 80]; it expires back to the plan.
ctx.directives.request(peer, EffortDirective.from_dict({"target_pct": ph.planned_pct + 5.0,
	"duration_s": 30.0, "reason": "hill", "source": "_template"}))
# Siege Overdrive: a 30 s SIM block in a WORK ERG phase (no target, grade, haptic or factor keys).
ctx.directives.request(peer, EffortDirective.from_dict({"mode": "SIM", "duration_s": 30, "reason": "overdrive", "source": "siege"}))
# Tank boiler in a SIM phase: a held mode grade; then a hit haptic on top of it.
ctx.directives.request(peer, EffortDirective.from_dict({"mode": "SIM", "mode_grade": 6.0, "reason": "boiler", "source": "tank"}))
ctx.directives.request(peer, EffortDirective.from_dict({"mode": "SIM", "haptic": 2.0, "duration_s": 1.5, "reason": "hit", "source": "tank"}))
# Fishing pull change: six ERG steps 0.5 s apart, each held until the next.
ctx.directives.request(peer, EffortDirective.from_dict({"mode": "ERG", "target_pct": 93.5, "duration_s": 0, "reason": "pull", "source": "fishing"}))
# Terrain at 2 Hz in a grade_source "game" phase, a cadence band, and ending an open-ended phase.
ctx.directives.course_grade(peer, 3.5)
ctx.directives.cadence_band(peer, 60, 120)
if ph.open_ended and ph.elapsed_s >= ph.min_s:
	ctx.directives.end_phase(peer)
```

## 9. InputFrame, PhaseState and Telemetry

`sim_step(dt, frame)` gets an `InputFrame`:

| Field | Meaning |
| --- | --- |
| `tick`, `t` | Game tick and game time (`tick × Wl.SIM_DT`); both stop while paused |
| `players` | peer → Telemetry for every slot, bots and dropped peers included; `frame.telemetry(peer)` |
| `phase` | peer → PhaseState, keyed by peer even when every rider shares one sequence (Siege and Tank read any slot's); `frame.phase_of(peer)` |

`PhaseState` (`frame.phase[peer]`): `index`, `kind`, `mode`, `elapsed_s`, `duration_s` (nominal for open-ended phases), `open_ended`, `min_s`, `max_s`, `label`, `planned_pct` (the planned ERG target now, ramp included; 0 in SIM), `remaining_s` (until the platform ends the phase on its own: `duration_s − elapsed` for fixed phases, `max_s − elapsed` for open-ended ones; never negative), `count` (phases in the plan, cool-down included), `plan_elapsed_s` (game seconds since this rider's plan started: "the first 300 s" is `plan_elapsed_s < 300`), `prev_ended_by` (how the previous phase ended: `duration`, `max_s`, `end_phase`, `finished`; `""` for the first), and `is_cooldown()`.

`Telemetry` (`frame.players[peer]`, and what a client sends at 5 Hz):

| Field | Meaning |
| --- | --- |
| `power_w`, `cadence_rpm`, `speed_kmh` | The rider's latest values (raw watts) |
| `effort` | Effort in the scaling mode: P/FTP, P/kg or W |
| `p_eff_w` | Effective power (BRIEF 3.3): `power_w × p_eff_per_w` |
| `wbal_j` | W′ balance in joules (Skiba, BRIEF 3.4) |
| `ftp_pct` | Raw power / FTP × 100 |
| `mode` | The trainer mode the governor applied: `ERG`, `SIM` or `OFF` |
| `applied_target_w` | The applied ERG target in whole watts after every governor rule; 0 outside ERG; 50 % FTP during rescue |
| `applied_grade_pct`, `gear`, `haptic_pct` | Applied total SIM grade, virtual gear 1..24, applied haptic now |
| `clamped_by` | Rules that changed the latest applied value |
| `rescue`, `coasting`, `afk`, `paused` | Safety states |
| `s_left_105`, `s_left_120` | Seconds left above 105 % / 120 % FTP before a duration limit latches |
| `gestures` | Gestures since the previous telemetry |
| `intents` | Game intents: the rider's own, then (bots and Autopilot riders) `autopilot_intents()` |
| `distance_m`, `phase_index`, `acks`, `t` | Trainer distance, the phase the rider's governor follows, directive acknowledgements, the sender's platform time |
| `connected`, `age_s`, `cadence_age_s` | `age_s`: seconds since this rider's latest telemetry arrived, set every tick for every remote rider (0 for local riders and bots). `cadence_age_s`: seconds since the last fresh cadence value. A dropped peer has `connected` false, power and cadence 0, `afk` true and a growing `age_s` |

## 10. HUD

### 10.1 HudSpec

`hud_spec()` returns a `HudSpec`: kit widgets and your own Controls, each at a named anchor or, in a 2D game, at a `Rect2i` in art pixels.

```gdscript
func hud_spec() -> HudSpec:
	return HudSpec.new() \
		.add(HudSpec.TIMELINE, HudSpec.TOP_LEFT) \
		.add(HudSpec.READOUT, HudSpec.TOP_RIGHT, {"source": "custom", "id": "laps", "label": "_TEMPLATE_LAPS"}) \
		.add(HudSpec.POWER_GAUGE, HudSpec.BOTTOM_LEFT).add(HudSpec.CADENCE, HudSpec.BOTTOM_LEFT) \
		.add(HudSpec.TEAMMATES, HudSpec.BOTTOM) \
		.add_control(my_card, Rect2i(427, 24, 212, 80)) \
		.toasts_at(HudSpec.TOP).banners_at(Rect2i(0, 24, 284, 84))
```

- Anchors: `top_left`, `top`, `top_right`, `bottom_left`, `bottom`, `bottom_right` (`HudSpec.TOP_LEFT`, ...). Entries at one anchor stack in the order added: top anchors downward, bottom anchors upward. "Bottom center" is `bottom`.
- `add(widget, at, options = {})`, `add_control(control, at)`, `toasts_at(at)`, `banners_at(at)`, `show_safety_banners` (default true: the kit's rescue and warm-up banners), `has_widget(widget)`, `HudSpec.is_valid_position(at)`.
- **Rect2i placement (2D)**: a `Rect2i` is in art pixels of `pixel_base`. The HUD maps it through `PixelViewport.art_rect_to_screen(rect)`, which applies the viewport's integer scale and letterbox offset, and re-lays it out on resize. At 1080p a 640 × 360 view has scale 3, so Fishing's 4-lane HUD zone, art x 427–639 and 84 px high, is 639 × 252 screen pixels. Kit widgets shrink to fit their rect; key numbers keep ≥ 48 px at 1080p where the rect allows. (W2: ui-hud adds each widget's minimum rect here.)
- The HUD draws at native resolution above the game view (base size 1920 × 1080, `canvas_items` stretch, so HUD sizes are 1080p pixels). (W2: ui-hud adds the HudLayer's CanvasLayer `layer` value, so a view's own CanvasLayer below it, such as Siege's vignette, draws under the HUD, and the shared Theme's res path and font sizes, so your Controls match the kit.)

Kit widgets (BRIEF 3.9):

| Widget | Shows | Options |
| --- | --- | --- |
| `power_gauge` | ERG: the applied target band; SIM: the band set with `ctx.hud.power_band`; glows in band | `{"peer": int}` (default the local rider) |
| `cadence` | Cadence with the band published by `ctx.directives.cadence_band` | |
| `wbal` | W′ balance bar | |
| `timeline` | The local rider's plan, the current phase and a preview of the next; open-ended phases by nominal length or `min_s`–`max_s` | |
| `teammates` | One chip per slot from `ctx.roster`: color, shape, pattern and `hollow`, name, raw W, %FTP, rescue, AFK, disconnected, and the latest `teammate_status` (`in_band`, `icon` as a `res://` texture path, `text`) | |
| `readout` | A big number (≥ 48 px) | `{"source": "power_w" \| "cadence_rpm" \| "ftp_pct" \| "wkg" \| "custom", "id": String, "label": key}`; custom readouts are fed by `ctx.hud.readout(id, text)` |
| `gear` | The virtual gear, shown whenever the local trainer is in SIM (SIM phases and SIM blocks), hidden in ERG | |

The teammate strip is roster-driven (2 Hz, host values). What it can't show (Siege's target icon, Tank's engine icon beyond `icon`), draw in your own Control beside it.

### 10.2 ctx.hud routing

| Call | On the host or in SOLO | On a client |
| --- | --- | --- |
| `power_band(peer, lo_w, hi_w)` | For a remote rider: a `directive` of kind `power_band` to that peer's gauge and MockTrainer. For the caller's own rider: applied to its own gauge and MockTrainer, nothing sent. `(0, 0)` clears; it holds until replaced; the cool-down clears it | Applies to the client's own gauge and MockTrainer; nothing sent |
| `teammate_status(peer, {in_band, icon, text})` | Into the roster for every peer | Local only |
| `toast(key, args = [], peer = 0)` | `peer` 0 (`Wl.ALL_PEERS`, the default) reaches every peer, the host included; `peer == ctx.local_peer` draws on the host only and sends nothing; another peer gets a `hud` message | Draws locally whatever `peer` says |
| `banner(key, args = [], seconds = 3.0, peer = 0)` | Same as `toast` | Local |
| `readout(id, text)` | Local only, never routed | Local only |

`args` (Array or Dictionary) fill `{0}` or `{name}` placeholders. **Careful:** a host that raises its own rider's prompt with the default `peer` broadcasts it to every client. Pass `ctx.local_peer` for prompts meant for the host's rider, and raise each client's own prompts on that client (in `apply_event`, `apply_snapshot` or `client_predict`):

```gdscript
# Host side (Tank-style "Surge to ram" prompt for the host's own driver only):
if driver == ctx.local_peer:
	ctx.hud.toast("TANK_PROMPT_RAM", [], ctx.local_peer)
# Client side, from the snapshot it just applied:
func apply_snapshot(s: Dictionary) -> void:
	...
	if _my_station_can_ram(s):
		ctx.hud.toast("TANK_PROMPT_RAM")  # a client call is always local
```

The template does the same with its lap toast (host: `peer = ctx.local_peer`; clients: in `apply_event`).

### 10.3 PedalScanList

`PedalScanList` (`addons/wattlands/ui/pedal_scan_list.gd`, a VBoxContainer) is the pedal-scan component for shops and pickers (BRIEF 3.5):

- `set_items([{id, text, disabled?, icon?, detail?}])`, `highlighted()`, `set_highlight(i)`, `tick(dt)` (headless tests; `_process` drives it in real time), `feed_gesture(name)`, `feed_action(name)`.
- `scan_interval_s` (1.6), `scanning`, `erg_auto_confirm`, `follow_local_mode` (in sessions `erg_auto_confirm` follows the local rider's mode: on in ERG), `listen_to_input` (follow InputRouter automatically; off in headless tests).
- `surge` or `confirm` picks; `coast` or `back` backs out (`coast` never in ERG); up/down move focus and pause scanning for 10 s.
- ERG auto-confirm: with `erg_auto_confirm` on, the highlighted item is picked after two full cycles (2 × item count × `scan_interval_s`) without input, whether or not scanning is on, so a rider with Autopilot off who only pedals still gets picks.
- Signals: `item_chosen(index, id, auto: bool)` (auto is true for an auto-confirm), `item_picked(index, id, via: String)` emitted with it (`via` is `"action"`, `"surge"` or `"auto"`), `backed_out`, `highlight_changed(index)`.

The platform never edits intents: tag your own, for example Siege's buy `{"k": "buy", "item": id, "pad": n, "auto": 1}` when `via == "auto"`.

## 11. Input, intents and Autopilot

**Actions** (BRIEF 3.5): `confirm`, `back`, `up`, `down`, `left`, `right`, `ability_1`, `ability_2`, `item`, `swap`, `shift_up`, `shift_down`, `pause`, `panic` (`Wl.ACTIONS`). Keyboard: arrows or WASD, Enter or Space, Esc, 1 and 2, F, R, Q and E, P, Backspace held 1 s. Xbox: stick or D-pad, A, B, X and Y, RB, LB, LT and RT, Start, View + Menu. `pause` and `panic` are consumed by the platform and never reach a game; `shift_up` and `shift_down` drive the virtual gears.

**Gestures** (`Wl.G_*`): `pedal_start` (cadence ≥ 40 rpm or ≥ 30 % FTP for 3 s), `surge` (confirm; in ERG by flywheel speed ≥ 1.12 × its 10 s average for 1.5 s, else by power), `coast` (back; not pedaling 3 s, never in ERG), `stop_5s` (pause; solo, outside ERG). `not_pedaling` (power < 15 W and cadence < 20 rpm) is the shared detector behind them and the coasting rule. A stricter scored sprint is `SprintRule` (≥ 1.2 × FTP, optionally over a trailing window): `SprintRule.create(ftp_w, window_s)`, `update(t, power_w)`, `holds()`, `held_s()`, `best_s()`, `threshold_w()`, `reset()`.

**`local_intents(actions, gestures)`** runs on every peer every tick for the local rider. `actions` holds device actions (keys, buttons, sticks) since the last tick and is never synthesized from a gesture; `gestures` holds the gestures since the last tick. A surge never also arrives as `confirm`. If you ever see both in one tick, treat it as the surge. Tag gesture-made intents so your rules can tell them apart:

```gdscript
func local_intents(actions: Array[StringName], gestures: Array[StringName]) -> Array:
	if gestures.has(Wl.G_SURGE):
		return [{"k": "boost", "via": "surge"}]
	return [{"k": "boost", "via": "action"}] if actions.has(&"confirm") else []
```

**`ctx.intents.send(intent)`** is for your own widgets (a shop button, a PedalScanList pick). Both paths deliver the same way:

- HOST and SOLO: into the local rider's `frame.players[peer].intents` on the next tick. Intents sent before the first tick (for example Fishing's `summary` from `configure`) arrive in the first frame.
- CLIENT: batched into `Telemetry.intents` at 5 Hz; they appear in `frame.players[peer].intents` on the first host tick after that telemetry arrives.
- Each intent arrives exactly once, in order, at most 32 per telemetry message (beyond that `push_warning` and drop), each ≤ 1 KB. The platform has no intent rate limit of its own; enforce yours (Siege and Tank: 5 a second per peer) on the host.
- Intents are small JSON-safe Dictionaries of your choosing and are never int-converted: cast values yourself (`int(intent["pad"])`).

**Autopilot** (BRIEF 3.5): `autopilot_intents(peer)` runs on the host every tick only for bots and riders with `autopilot` true, and its result is appended after the rider's own intents. It is never called for an Autopilot-off human. Autopilot never changes effort. The platform does not tag merged intents, so a game that must tell them apart (Siege: "Overdrive never from Autopilot") tags its own `autopilot_intents()` output (the template uses `"auto": 1`).

**Zero input**: every game must play to the results with no input at all. The pattern all three briefs use: a human counts as Autopilot for a choice until their first deliberate intent of that kind; surge-made intents and PedalScanList auto-confirms never end the fallback (tag them, and check the tag on the host).

## 12. Snapshots, events and int_fields

- **`snapshot()`** runs on the host at 10 Hz and is sent as `snapshot {game_id, seq, state}`. Send full state, so a rejoining client needs no special path. Its size is the UTF-8 byte length of `JSON.stringify(state)` (state only, no envelope, no indent); the run_game_sim report records each snapshot's size and SHA-256 over the same bytes. No message may exceed 16 384 bytes (the relay limit): NetSession drops an oversize one with `push_warning` and the report counts `oversize_snapshots`. Keep your own cap well below (Siege 8 KB, Tank 4 KB, Fishing 2 KB) and test it.
- **Events**: `send_event({"type": ..., ...})` on the host. The GameHost sends one `event {seq, events}` batch per ≤ 100 ms, before the snapshot of the same tick, so clients apply that tick's events, then its snapshot, in the same order on every client. `apply_event` never runs on the host or in SOLO: raise the host's own effects directly where you emit the event.
- **`int_fields()`**: Godot's JSON parser returns every number as a float. `Protocol.decode()` converts the paths you declare back to int. Keys are `"snapshot"` and each event `"type"` (so no event type may be called `snapshot`); values are dotted paths where `[]` means every array element and `{}` every dictionary value. Only numeric leaves at a matched path are converted; an Array or Dictionary found there is left unchanged, so Siege's `f: [[pad, [target_ids]]]` declares both `f[][]` and `f[][][]`. Casting with `int()` in `apply_snapshot` and `apply_event` stays good practice.

```gdscript
func int_fields() -> Dictionary:
	return {"snapshot": ["v", "tick", "r[][]"], "boost": ["slot"], "lap": ["slot", "laps"]}
```

- **`client_predict(dt, local)`** runs on clients every tick after any snapshot applied that tick. Move only what the local rider controls (your own wheel, cadence marker or machinery); interpolate everything else between snapshots.
- **Protocol** also converts `peer`, `host`, `from`, `to`, `seq`, `proto`, `max` and every `*_id` key, gives peer-keyed dictionaries int keys, and rejects messages that fail their schema or version (`docs/PROTOCOL.md`).
- **Bandwidth**: the host sends about 35 messages a second (snapshots 10, roster 2, events ≤ 10, directives); NetSession keeps only the latest `course_grade`, `cadence_band` and `power_band` per peer per 100 ms and never drops or reorders a `request` or a `phase`.

## 13. Phases, cool-down, finishing and laps

- The GameHost tracks every rider's plan itself. A phase ends by its duration, at `max_s`, by `end_phase`, or by `finished`. On every change (the cool-down start included) it emits `ctx.events.phase_started(peer, index)`, sends that rider's client a `phase` message `{index, start_tick, ended_by}` (the client's governor starts the phase from it), records a `phase_started` event in the report, and updates `frame.phase`.
- **`phase_changed`**: the GameHost never emits it, never changes phases or laps on it, and records the game's emits as `game_phase_changed` report events. Games whose riders share one sequence may emit it (Siege, Tank, the template); games with per-rider plans don't need it (Fishing).
- **The cool-down**: the validator appends `COOLDOWN`, ERG 50 %, 180 s, `lap` true, label `Cool-down`. During it the GameHost keeps your view on screen and keeps calling `sim_step` with `frame.phase` kind `COOLDOWN` (show the ride home), refuses every directive (`cooldown`) and clears every band. It always starts its own FIT lap.
- **`finished(reason)`**: every rider not yet in the cool-down ends its phase (`ended_by: "finished"`) and starts the cool-down; unused phases never start (no lap). Emitted during the cool-down it only records the reason. Emit it once.
- **FIT laps**: one lap at each lap-true phase that started, one per `lap_marker` emit, and one for the cool-down. Expected laps = lap-true phases that started + `lap_marker` emits + 1. A run that ends by `timeout` or `paused` before the cool-down has no cool-down lap. The template's `default` content gives 2 + 1 + 1 = 4.

## 14. Rescue, AFK, pause, drops and rejoins

- **Rescue** (BRIEF 4.6.3): in ERG with a governed target ≥ 60 % FTP, cadence < 45 rpm for 3 s or power < 75 % of the target for 5 s drops the rider to 50 % FTP; the hold ends at cadence ≥ 70 rpm for 3 s, then the target ramps back over 10 s. `on_rescue(peer, true/false)` brackets the hold; `Telemetry.rescue` shows it. Treat it as a stagger. Don't send `request`s to a rider in rescue unless you mean them (they keep counting underneath); a SIM block is refused then.
- **Coasting** (BRIEF 4.6.4): `not_pedaling` for 3 s drops ERG to the floor; at 10 s a SOLO rider is paused (game time stops: no `sim_step`) and a multiplayer rider goes AFK (`on_afk(peer, true)`, `Telemetry.afk`). `on_afk(peer, false)` follows when they pedal again.
- **Pause**: game time stops (no `sim_step`, phase clocks and directive expiries stop); the trainer goes to the ERG floor or SIM flat; trainer I/O, telemetry and panic keep working.
- **A dropped client**: `on_afk(peer, true)` at once; its `frame.players[peer]` has `connected` false, power and cadence 0 and a growing `age_s`; its last telemetry never counts as pedaling. The slot stays until the session ends, with its plan.
- **Rejoin**: a client that reconnects with the relay's reconnect token gets `lobby_state`, its `plan`, its `phase` and the latest snapshot (`apply_snapshot` once), then `on_afk(peer, false)` once fresh telemetry shows pedaling. A restarted client starts a new FIT file from the rejoin. After the token expires the slot stays AFK. Joins without a token after the start are refused with `session_in_progress`, which the client shows.
- **Staleness**: `age_s` is set every tick for remote riders; `cadence_age_s` tells a fresh cadence from a held one (Fishing freezes its meters when it passes 3 s).

## 15. Results and progression

`results()` runs once on the host (or in solo play) when the cool-down ends, or when a `run_game_sim` run ends by `timeout` or `paused`. Start from the platform's rows:

```gdscript
var res := GameResults.from_stats(ctx.stats, ctx.players)
```

Each row holds `peer_id`, `slot_index`, `name`, `is_bot`, `kj`, `avg_power_w`, `avg_ftp_pct`, `np_w`, `best_1m_w`, `best_5m_w`, `best_20m_w`, `ride_s`, `time_in_band_s`, `time_in_band_pct` (generic: in ERG power within ±5 % of the applied target; in SIM power inside the published power band), plus `xp` (0), `unlocks` (`[]`) and `stats` (`{}`). Override time in band with your own definition, add custom per-rider values under `row["stats"]`, team values in `res.team`, and set `res.grade` (`"S"`..`"D"`; `GameResults.grade_from_fraction(f)` gives BRIEF 3.7's bands), `res.score` and `res.summary_key`. `res.row(peer)` finds a row. The platform sends the results to every client.

`apply_progress(results, progress)` then runs once on every peer, host included, before the results screen. `progress` is `ctx.progress`, a `ProgressStore` at `Paths.user_dir()/games/<id>/progress.json`, local to the peer and the profile (in-process simulations give every human slot its own temp path), never sent anywhere unless your game sends a summary. API: `has(key)`, `get_value(key, default)`, `set_value(key, value)`, `add(key, amount) -> float`, `save()` (the platform saves after `apply_progress`). Return the local rider's new unlock ids; the results screen shows them. `results.session_id` is unique per session: store the last one you applied and skip a repeat, so a peer that receives results twice counts the session once (the template does this).

## 16. Determinism

- Rules are pure classes with `step(state, inputs, dt)` at `dt = 0.05`. They use only `ctx.rng` and never the wall clock: no `Time.*`, no `OS.get_ticks*`, no global `randi`/`randf`/`randomize`, no `RandomNumberGenerator.new()` in rules (a view may seed its own cosmetic RNG from `ctx.seed`). The template's `test_template_package.gd` scans for these.
- Iterate in slot order (`ctx.players`), not dictionary order, wherever the order changes the outcome.
- The same seed and inputs give the same snapshots: `run_game_sim` runs with the same arguments and seed give the same `deterministic_hash`, in SOLO and HOST runs.
- Directive expiries, phase clocks and your rules all run on game time; the governor, MockTrainer and telemetry run on platform time (`docs/ARCHITECTURE.md`, Time).

## 17. Strings

- `content/<id>/strings.csv`, header `keys,en`; every key starts with `<ID>_`. The GameRegistry registers each valid game's translations with the TranslationServer at startup; the conformance test fails a key without the prefix.
- `ctx.strings.t(key, args = [])` returns the text with `{0}` or `{name}` filled from an Array or Dictionary; a missing key returns the key itself (so plain text passes through). `ctx.strings.has(key)`.
- Phase labels, option labels (`<ID>_OPT_<OPTION ID>`), content labels (`<ID>_CONTENT_<CONTENT ID>`), toasts, banners and readout labels are all keys. Test that every key you use exists (the template's package test does).

## 18. Presentation and audio kits

- **2D** (`addons/wattlands/world2d/`, BRIEF 3.9): `PixelViewport` (`pixel_base`, `set_game_view(view)`, `game_view()`, `integer_scale()`, `letterbox_offset()`, `art_rect_to_screen(rect)`, `capture()`); `ParallaxStrip` (any factor ≥ 0, including > 1 for foreground debris; tiles a narrow texture across the width; `mirror_alternate` alternates flipped copies); `SpinningPart` and `SlidingPart` (signed speed −1..1, negative runs backwards; `SlidingPart` reciprocates or scrolls); the `PaletteSwap` shader (key colors to slot colors, with a two-tone ramp helper); the `SpriteWobble` shader; the pixel import preset (filter off, mipmaps off: `project.godot` sets the texture importer defaults, so sprites need no hand-written `.import`). Demo: `addons/wattlands/world2d/demo.tscn`.
- **3D** (`addons/wattlands/world3d/`): `LowPolyMesh` (primitives, flat shading, vertex colors, merging, ground darkening, haze blend), MultiMesh scatter (seeded, exclusion zones, per-instance custom data), the miniature camera rig (high three-quarter view, limited orbit, push-in, shake), sky and ambient for the Compatibility renderer (no SSAO, no depth of field). Demo: `addons/wattlands/world3d/demo.tscn`.
- **Art**: generated 2D pixel art comes from `tools/art` (`docs/ART_PIPELINE.md`).
- **Audio**: the `Sfx` autoload: `play(name, volume_db, pitch)`, `register(name, stream)`, `has_sound(name)`, `synth(kind, freq_hz, duration_s, attack_s, release_s, loop)` (`"sine"`, `"square"`, `"saw"`, `"noise"`; `loop` for continuous sounds you pitch live), `set_metronome(rpm, on)`. Silent and error-free headless. Credit your sounds in `docs/credits.d/<id>.md`.
- (W2: world-kits and ui-hud check these names against their code and link their API docs.)

## 19. Tools

Every tool exists as a bash script with a shebang and a PowerShell twin (`.ps1`, Windows PowerShell 5.1; other tools start them with `powershell -NoProfile -ExecutionPolicy Bypass -File`). Godot runs only through `tools/godot.sh` / `tools/godot.ps1` (stdin closed, a timeout, a machine-wide slot lock, never `-d`).

### 19.1 tools/run_game_sim

Runs one game session headless with MockTrainer riders and writes a JSON report and FIT files.

```bash
tools/run_game_sim --game=siege --content=vo2 --players=4 --bots=0 --rider=erg+surge:every_s=60,for_s=2,lift=0.2,sim_pct=130 \
  --sim-speed=200 --seed=1 --report=build/siege/sims/s10_vo2.json \
  --player-options='[{"wave_offset":5},{"wave_offset":-10},{"wave_offset":0},{"wave_offset":5}]'
```

```powershell
tools\run_game_sim.ps1 --game=siege --content=vo2 --players=4 --bots=0 --rider=erg+surge:every_s=60,for_s=2,lift=0.2,sim_pct=130 `
  --sim-speed=200 --seed=1 --report=build/siege/sims/s10_vo2.json `
  '--player-options=[{"wave_offset":5},{"wave_offset":-10},{"wave_offset":0},{"wave_offset":5}]'
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `--game=<id>` | required | The game |
| `--report=<path>` | required | Where the JSON report goes (relative paths are taken from your current directory) |
| `--content=<id>` | `default_content` | One of `contents` |
| `--players=<n>` | 1 | Human slots, 1..8 |
| `--bots=<n>` | 0 | Bot slots added after the humans (only if `bots` is true) |
| `--rider=<profile>` | `erg` | A MockTrainer profile (section 20). Give it once for every human slot, or repeat it once per human slot in slot order. Profiles contain commas, so it is never comma-joined. Bots always ride `erg:compliance=1.0` |
| `--sim-speed=<x>` | 1 | Fixed 0.05 s steps per 0.05 s of wall time: 1 is real time, 200 runs a 55-minute session in about 66 s. It never touches `Engine.time_scale` |
| `--seed=<n>` | 1 | The session seed (`ctx.seed`; MockTrainer jitter, noise and dropouts are seeded per slot from it) |
| `--autopilot=all\|none\|<slot,...>` | `all` | Which human slots have `autopilot` true. Bots always do |
| `--ftp=<w>[,<w>...]` | 200 | One value for every slot, or one per slot in slot order (humans, then bots); bots without a value use the first slot's FTP |
| `--unverified` | off | Every human slot's FTP is unverified (×0.85 on ERG targets); bots stay verified |
| `--haptics-off=<slot,...>` | none | These human slots have `haptics_on` false |
| `--options=<json object>` | defaults | Session options, validated against `game.json` |
| `--player-options=<json array>` | defaults | One object per human slot, in slot order; missing keys and bots get defaults |
| `--override=<json file>` | none | `{"<file under content/<id>/>": <JSON merge patch>}` applied by `ctx.load_content_json` before validation, for stress runs; recorded in the report |
| `--max-sim-seconds=<n>` | the validated plan with every open-ended phase at `max_s`, plus 600 | Hard stop: `end_reason: "timeout"` |

The defaults are `GameSimRunner.parse_args`'s (W2: the lead checks this table against it). Wrapper-only flags: `--godot-timeout=<s>` (kill Godot after s seconds, default 1800) and `--godot-lock-timeout=<s>` (stop waiting for a Godot slot). The wrappers always run with the hardware and network locks, add `--mock-trainer` (the entry script refuses to run without it or without the locks), refuse `--allow-hw` and `--allow-network`, and run `tools/godot.sh --headless --path <repo> -s tools/sdk/run_game_sim_main.gd -- <flags>`. `--echo-args` prints the flags Godot received and exits; `--help` prints the usage.

Exit codes: 0 the run completed, whatever `end_reason` says; 2 bad flags (an unknown flag, a missing value, a bad value naming the field) or missing locks; 3 setup failed (an unknown game or content, an invalid option value, a rejected plan, with the validator's errors); 4 the report could not be written; 75 the Godot slot wait timed out; 124 Godot was killed by the timeout.

**Slots and roles.** `--players` counts human slots and `--bots` adds bot slots after them (slot indexes 0..n−1, humans first). One human slot, with or without bots, runs as `SOLO`, so a coasting rider pauses (BRIEF 4.6.4). Two or more run as `HOST` plus one `LoopbackTransport` `CLIENT` per other human, each with its own GameModule, `WlNetSession`, `WlEventBus`, `LocalRider`, governor and MockTrainer, so a coasting rider goes AFK. Every human slot gets a temp profile dir; your real profile, progress and rides are never touched. Human peer ids are 1 (the host's own rider, slot 0), 2, 3, ...; bots are −1, −2, ...

**Endings.** `complete` when the cool-down finishes; `timeout` at `--max-sim-seconds`; `paused` once a SOLO run stayed paused for 120 s of platform time. Every ending calls `results()` and writes the report and the FIT files.

**FIT files**: one per human slot, none for bots, at `<report dir>/fit/<report stem>_slot<n>.fit` (`build/siege/sims/fit/s10_vo2_slot0.fit`).

**The report** (`GameSimRunner.build_report()`, schema 1). JSON object keys are strings, so peer-keyed maps use the peer id as a string (`"1"`, `"-1"`). (W2: the lead checks every key below against `tests/sdk/test_sim_report.gd`'s schema fixture and corrects whichever side is wrong.)

| Key | Type | Content |
| --- | --- | --- |
| `schema` | int | 1 |
| `args` | object | The parsed arguments (`game`, `content`, `players`, `bots`, `riders`, `sim_speed`, `seed`, `autopilot`, `ftp`, `unverified`, `haptics_off`, `options`, `player_options`, `max_sim_seconds`) |
| `slots` | array | Per slot: `{slot, peer, name, is_bot, role, ftp, ftp_verified, rider, autopilot, haptics_on, options}` |
| `plans` | object | peer → the validated plan (`EffortPlan.to_dict()`, cool-down included) |
| `plan_warnings` | object | peer → the validator's warnings |
| `overrides` | object | The `--override` patches applied |
| `end_reason` | string | `complete`, `timeout` or `paused` |
| `finished_reason` | string | The game's `finished(reason)`, or `""` |
| `events` | array | In order: `{t, tick, type, peer?, ...}`: `session_state`, `phase_started` (`peer`, `index`, `ended_by`), every game event as emitted (`type` is yours), `game_phase_changed` (`index`), `lap_marker` (`label`), `rescue` and `afk` (`peer`, `active`), `paused`, `finished` (`reason`), `results` |
| `phases` | object | peer → `[{index, kind, mode, label, start_s, end_s, ended_by}]`; `ended_by` is `duration`, `max_s`, `end_phase` or `finished` (game seconds) |
| `directives` | array | Every directive: `{t, peer, id, kind, requested, accepted, refused, applied, clamped_by}`; `kind` is `request`, `course_grade`, `end_phase`, `cadence_band` or `power_band`; `requested` is exactly what the game set (`EffortDirective.to_dict()`); `refused` is the refusal reason or `""`; `applied` is what the rider's governor applied |
| `traces` | object | peer → 1 Hz samples `{t, phase_index, kind, mode, applied_target_w, applied_pct, applied_grade_pct, clamped_by, rescue, afk, paused, haptic_pct, power_w, cadence_rpm}` for every rider, bots included |
| `snapshots` | array | `{tick, bytes, sha256}` for every snapshot the host builds at 10 Hz (W2: sdk-runtime states whether SOLO runs record them too) |
| `max_snapshot_bytes`, `oversize_snapshots` | int | The largest snapshot, and how many exceeded 16 384 bytes |
| `results` | object | `GameResults.to_dict()` |
| `fit_paths` | array | Absolute FIT paths, one per human slot in slot order |
| `meta` | object | Wall-clock values (start time, duration, Godot version); excluded from the hash |
| `deterministic_hash` | string | SHA-256 of the canonical report without `fit_paths`, `meta` and any path |

Read reports with Node (`JSON.parse`) in your `check_sims.mjs`; a scenario asserts over `events`, `directives`, `traces`, `phases`, `results` and `deterministic_hash`.

### 19.2 tools/new_game

```bash
tools/new_game <id> [--dry-run]
```
```powershell
tools\new_game.ps1 <id> [--dry-run]
```

Copies `src/games/_template/`, `content/_template/`, `assets/_template/` and `tests/games/_template/` to `<id>`, rewriting every copied text file and file name at word starts: `_TEMPLATE_` and `TEMPLATE_` → `<ID>_` (string keys), `_template` → `<id>` (paths, the game id, `source`), `Template` → `<Id>` (class names; `big_fish` → `BigFish`), `template_` → `<id>_` (file names: `template_game.gd` → `siege_game.gd`). It sets `game.json` `title` to the id in words, strips `uid="uid://..."` attributes from copied `.tscn` and `.tres` files, and copies no `.uid`, `.import` or `.translation` file (the next import makes fresh ones, so nothing collides with the template). It also writes `.github/workflows/game-<id>.yml` and creates `docs/decisions/<id>.md`, `docs/credits.d/<id>.md` and `docs/changelog.d/<id>.md` only where missing (a session may write its decisions before scaffolding). Ids match `^[a-z][a-z0-9_]*$`.

It refuses, exiting 1 and writing nothing, when `src/games/<id>/`, `content/<id>/`, `assets/<id>/`, `tests/games/<id>/` or `.github/workflows/game-<id>.yml` exists, so a resumed session never overwrites a game. Exit 2 is a usage error (no id or a bad id). `--dry-run` lists what it would write. Afterwards run `tools/godot.sh --headless --path . --import`. `tools/run_tests` checks the scaffold on every run (BRIEF 7.3): it scaffolds `demo` in a copy of the tree and runs the conformance test there.

### 19.3 tools/screenshot

```bash
tools/screenshot --game=<id> --content=<id> --at=<s>[,<s>...] [--players=<n>] [--bots=<n>] [--rider=<profile>] [--autopilot=all|none] [--seed=<n>]
```
```powershell
tools\screenshot.ps1 --game=<id> --content=<id> --at=<s>[,<s>...] ...
```

Runs the game windowed through `GameSimRunner` with `run_game_sim`'s slot, role and profile rules, steps the sim as fast as it can to just before each `--at` (sim seconds: the fast-forward), renders at normal speed and saves the full frame, HUD included, from the host's view (slot 0; Fishing's highlighted lane is slot 0's). It also accepts `--ftp`, `--unverified`, `--options`, `--player-options`, `--override` and `--screenshot-dir=<dir>` (default `build/screenshots/<game>/`). Files: `<game>_<content>_<players>p_<at>s.png`. (W2: qa confirms against `tools/screenshot`.)

### 19.4 End to end: tools/e2e/run.mjs and e2e_check.mjs

```bash
node tools/e2e/run.mjs --games=<id>[,<id>...]
```

Per game: starts the relay, the mock Strava server, a host and two clients (headless, mock trainers, Autopilot, separate profile dirs, `--sim-speed=1`) under one Godot lease, plays the game's `e2e_content`, kills and restarts one client to test the reconnect, checks one auto-upload, and writes `build/e2e/<id>/report.json` (per peer: events in order, game events included, applied directives, the 1 Hz trace, FIT paths, uploads, desync warnings, script errors). If `tests/games/<id>/e2e_check.mjs` exists it runs `node tests/games/<id>/e2e_check.mjs build/e2e/<id>/report.json` and fails the game on a non-zero exit. One pass or fail line per game; a non-zero exit if any failed; ≤ 6 minutes per game, not counting the cool-down. It holds three Godot slots at once, so run it while no other Godot work runs. (W2: qa links the report schema in `tools/e2e/README.md`.)

### 19.5 tools/fit_check

```bash
node tools/fit_check/check.mjs <file|dir>... [--expect-laps=<n>] [--json]
```

Decodes every FIT file given (directories recursively) and prints, per file, its errors, record count, laps (start, duration) and session totals; exits non-zero on any error or on a lap count other than `--expect-laps`. `--json` prints the same as JSON (W2: rides documents the JSON fields in `tools/fit_check/README.md`). Expected laps: section 13.

### 19.6 Tests, the script check and the wrappers

- The game's GUT tests: `tools/godot.sh --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/games/<id>/<dir> -ginclude_subdirs -gexit -gjunit_xml_file=build/junit_<id>_<agent>.xml`. GUT collects only `test_*.gd` files; helpers elsewhere in the folder still load in the script check.
- Strict rules (BRIEF 7): exit 0, "Run Summary" in the log, a test count above 0, and none of "SCRIPT ERROR", "Parse Error", "Debugger Break", "Ignoring script" or "Nothing was run" (pass `-gdisable_colors` when you grep a log). `tools/run_tests --only=gut --gdir=res://tests/games/<id>` applies them for you. A test fails on any unhandled `push_error`: code that rejects bad input uses `push_error` and its test `assert_push_error()`; expected non-fatal conditions use `push_warning`.
- `tools/godot.sh --headless --path . -s tools/check_scripts.gd` loads every script under `addons/wattlands/`, `src/`, `tests/` and `tools/`.
- `tools/run_tests` (`tools/run_tests.ps1`) runs every gate, with `FAL_KEY` and `WATTLANDS_ALLOW_ART` removed from its processes.
- `tools/godot.sh` / `tools/godot.ps1` pass everything after `--` to Godot untouched; `--lease=<n>`, `--lock-timeout=<s>` and `--timeout=<s>` are wrapper flags. `tools/env.sh` / `tools/env.ps1` set the two locks and leave `FAL_KEY` and `WATTLANDS_ALLOW_ART` alone.

## 20. MockTrainer rider profiles

`--rider=<profile>` (and the app's `--mock-trainer=<profile>`) names a MockTrainer profile (`addons/wattlands/trainer/mock_trainer.gd`, BRIEF 4.2). Grammar: `name:key=value,key=value` components joined with `+`; names and keys are case-insensitive; values are numbers. A component may appear more than once and each instance is independent (two `cadence_drop`s in one rider). An invalid spec logs an error and falls back to `erg`. Jitter, noise and dropouts are seeded from the run seed and the slot, so runs repeat. Simulated riders pedal from t = 0, so their warm-up starts at once (a `zero` rider never starts it).

| Profile | Parameters | Behaviour |
| --- | --- | --- |
| `erg` | `compliance` 0–1, default 1.0 | In ERG, follows the applied target × compliance with τ ≈ 2 s settling and a slight overshoot; fatigue from W′ eventually fails high targets. In SIM, rides compliance × the centre of the power band published with `ctx.hud.power_band`, else 90 % FTP (Tank's steam rider relies on the 90 %) |
| `zero` | none | 0 W and 0 rpm from t = 0 (coasting: the floor at 3 s, pause or AFK at 10 s) |
| `const` | `w` (required), `rpm` | Constant power (and cadence; default the preferred cadence) |
| `ramp` | `from_w`, `to_w`, `over_s` (required), `rpm` | A linear power ramp |
| `band` | `offset_rpm`, default 0 | Cadence follows the published cadence band's centre + `offset_rpm`, with 2 s lag and noise bounded to ±2 rpm; with no band, the preferred cadence. `offset_rpm` is measured from the centre, so ±(half the band width + n) holds the rider n rpm outside it: with a 16 rpm band, `offset_rpm=-18` holds 10 rpm below the low edge and `18` 10 rpm above the high edge |
| `cadence_drop` | `rpm`; a start: `at_s`, or `at_phase` (the rider's plan phase index) with optional `after_s`, or `at_target_pct` (with optional `at_phase` and `after_s`); `for_s` (default the rest of the run) | Cadence drops to `rpm`. With `at_target_pct=<n>` it first waits (inside `at_phase` if given) until the applied ERG target, after the unverified factor, is ≥ n % FTP, then counts `after_s` |
| `surge` | `every_s` 60, `for_s` 2, `lift` 0.2, `sim_pct` | Every `every_s` it multiplies cadence and reported speed by 1 + `lift` for `for_s`, aligned so each surge spans at least two notifications, so the ERG `surge` gesture fires every time. With `sim_pct=<n>` the rider rides n % FTP whenever its trainer is in SIM, overriding `erg`'s band rule |
| `intervals`, `noise` | (W2: trainer-core lists their keys) | Scripted intervals; power and cadence noise |

Precedence: cadence: an active `cadence_drop` > `surge`'s lift (it multiplies) > `band` > the preferred cadence. Power: `zero` or `const` (or `ramp`) > `surge`'s `sim_pct` in SIM > `erg`. Bots ride `erg:compliance=1.0` (`Bots.RIDER_SPEC`).

Examples: `erg:compliance=0.85+band`; `erg+band:offset_rpm=-18`; `erg+cadence_drop:rpm=40,at_s=1200`; `erg+cadence_drop:rpm=40,at_s=600,for_s=20`; `erg+cadence_drop:rpm=30,at_phase=4,after_s=20,for_s=30`; `erg+cadence_drop:rpm=30,at_phase=1,at_target_pct=60,for_s=30`; `erg+surge:every_s=60,for_s=2,lift=0.2,sim_pct=130`; `erg+cadence_drop:rpm=30,at_phase=2,at_target_pct=60,for_s=20+cadence_drop:rpm=30,at_phase=3,after_s=30,for_s=20` (two drops in one rider).

## 21. Safety rules for game designers

BRIEF 4.6 outranks every gameplay idea: change your design to fit it, never the governor. A game reaches the trainer only through `ctx.directives`; nothing under `src/games/` may name `TrainerController`, `SafetyGovernor`, `FtmsClient`, `write_control`, `set_target_power`, `set_simulation` or `set_resistance` (`tests/arch/test_no_bypass.gd` scans for them). What the governor does to your plans and directives, so you can design inside it:

- **Floor and ceiling**: ERG targets never go below max(30 % FTP, 50 W) (rounded up; it wins over every cap and over rescue) or above min(150 % FTP, 1000 W, the trainer's max). Applied targets are whole watts, rounded down.
- **Long phases**: a phase longer than 300 s (open-ended: `max_s`) caps every target in it, directives included, at 105 %. Fishing's marlin jumps stop at 104 % for this reason.
- **Duration limits**: at most 300 s above 105 % and 60 s above 120 %, accrued until ≥ 120 consecutive ERG seconds at ≤ 90 % reset both; time in SIM accrues nothing and restarts the reset count.
- **Unverified FTP**: every ERG target × 0.85.
- **Slew**: increases at most 30 W/s; decreases at once. Ramp big steps yourself if your rules read the applied target.
- **Rescue**: section 14. **Coasting**: the floor at 3 s, pause or AFK at 10 s.
- **Warm-up**: the first 5 minutes of riding: ERG ≤ 65 %, SIM grade −2…+3 %, no haptics. Every game opens with warm-up content.
- **Mode switches** are ramped: ERG → SIM sets the ERG target to min(applied, 3 s power), then SIM at grade 0, then the stacked grade; SIM → ERG sets grade 0, then ERG at min(3 s power, the planned or directed target), never below the floor, slewing up and never above the target. Keep ERG ↔ SIM switches ≥ 30 s apart (a directive SIM block of 10–30 s is the one exception).
- **SIM stacking**: (course grade + mode grade) × difficulty (default 50 %) + gear offset, clamped to the user's range (default −5…+10 %); plus haptic × intensity ≤ +3 % for ≤ 8 s with a 15 s cooldown per rider; total −10…+16 %. `crr` and `cw` only lower resistance.
- **Haptics**: never to ERG riders, in warm-up, or to riders who opted out (`haptics_on`).
- **Panic** (`SafetyGovernor.emergency_safe()`): ERG off, SIM grade 0 and wind 0 at once.
- **Cool-down**: 180 s at 50 % FTP; your directives are refused.
- **The network never sends device commands**: each rider's own governor validates and clamps everything locally.

## 22. Worked examples

### 22.1 The template (`src/games/_template/`)

The template is the smallest complete game: `game.json`, `TemplateGame` (the GameModule), `TemplateRules` (pure rules) and `TemplateView` (the 2D view), with content in `content/_template/` and tests in `tests/games/_template/`. Each rider pushes a marker along their lane at a speed proportional to P_eff.

| SDK feature | Where in the template |
| --- | --- |
| Content loading and validation | `configure`: `ctx.load_content_json("<content>.json")`, `TemplateRules.content_error()`, `push_error` on bad content |
| `ctx.rng` | `configure`: the seeded start spread |
| Plans with builders, a ramp, per-rider `int` option, `range_pct` | `build_effort_plans`: `PlanPhase.erg(...).with_lap()`, `.with_ramp(65)`, `work_offset` on WORK only, `.with_range(t, t + 5)` |
| Pure rules | `TemplateRules.step(state, inputs, dt)` returns the events it raised |
| A directive inside `range_pct` that expires back to the plan | `_phase_rules`: the "hill" `request`, once per rider at WORK elapsed 60 s |
| `cadence_band`, `power_band` | `_phase_rules`, at the WORK start of each rider |
| `teammate_status`, `readout`, toasts with a `peer` | `_phase_rules` (1 Hz), `sim_step` and `apply_snapshot` (laps readout), `sim_step` (host lap toast with `ctx.local_peer`), `on_rescue` (toast to the rescued rider only), `apply_event` (client lap toast) |
| `phase_changed`, `lap_marker`, `finished` | `_phase_rules`: on slot 0's index change; once at WORK elapsed 90 s; once at the first COOLDOWN frame |
| Autopilot | `autopilot_intents`: a boost every 30 s, tagged `"auto": 1`, never effort |
| Rescue and AFK as staggers | `on_rescue`, `on_afk`: the marker waits |
| Input | `local_intents`: surge and confirm tagged by `via`; the HUD button sends `{"k": "boost", "via": "button"}` with `ctx.intents.send` |
| Snapshots, events, `int_fields`, prediction | `snapshot` (integer arrays), `apply_snapshot`, `send_event` in `sim_step`, `apply_event`, `int_fields`, `client_predict` |
| View and HUD | `make_view` (a `TemplateView` Node2D at 640 × 360), `hud_spec` (seven kit widgets and a Button at an art-pixel `Rect2i`) |
| Results and progress | `results` (`GameResults.from_stats`, XP per kJ and per lap, an unlock, grade from time in band), `apply_progress` (XP once per `session_id`, only new unlocks returned) |

Its tests show how to test a game without the platform runtime: `template_fakes.gd` builds a `GameContext` whose `directives`, `hud`, `intents` and `stats` record every call, appends the cool-down like the validator, computes `PhaseState`s like the GameHost and builds synthetic `InputFrame`s. `test_template_game.gd` then asserts exact directive dictionaries, signal counts, HUD calls, snapshot round trips through JSON, results and progress. `test_template_package.gd` checks `game.json`, the content files, the string keys and the determinism and no-bypass scans. `integration/test_template_session.gd` runs the real registry, validator and `GameSimRunner` (SOLO and HOST).

### 22.2 Workout (`src/games/workout/`)

(W2: the lead fills this section from `src/games/workout/` once game-workout merges: how Workout builds its sessions from `content/workout/sessions/<id>.json` with a 5-minute ramp-in, ERG phases and the FREE SIM-flat sprints with virtual gears; Rolling road's `course` phase and its 76–105 % `power_band`; time in band per interval and the S–D grade; SprintRule sprint scoring; the pedal-scan session picker; its `e2e` content inside the warm-up limits; and its simulation tests through `GameSimRunner`.)

## 23. FAQ

Answers to the questions the game briefs' G0 steps ask (and to `docs/OWNERSHIP.md` 2.23).

**Q1. Which mock rider profiles exist, with which parameters?** Section 20: `erg` (`compliance`), `zero`, `const` (`w`, `rpm`), `ramp`, `band` (`offset_rpm`), `cadence_drop` (`rpm`, `at_s` | `at_phase` [+ `after_s`] | `at_target_pct` [+ `at_phase`, `after_s`], `for_s`), `surge` (`every_s`, `for_s`, `lift`, `sim_pct`), joined with `+`, components repeatable.

**Q2. How does run_game_sim count `--players` and `--bots`? What FTP, verified status, profile and Autopilot does each rider get?** `--players` counts human slots (slots 0..n−1), `--bots` adds bot slots after them. Each human gets the FTP from `--ftp` (default 200), is verified unless `--unverified`, rides its `--rider` profile (one for all, or one per slot), and has Autopilot per `--autopilot` (default `all`). Bots are verified, ride `erg:compliance=1.0` and always run Autopilot. One human runs SOLO, two or more run HOST with loopback clients (section 19.1).

**Q3. What does the report hold, and where do the FIT files go?** Section 19.1: arguments, slots, plans and warnings, overrides, `end_reason`, `finished_reason`, events, per-rider phases with `ended_by`, every directive as requested and as applied with `clamped_by` or its refusal, the 1 Hz trace per rider (applied target, mode, grade, `clamped_by`, rescue, AFK, haptic, power, cadence), each snapshot's size and SHA-256 with `max_snapshot_bytes`, the results, `fit_paths` and `deterministic_hash`. FIT files: `<report dir>/fit/<report stem>_slot<n>.fit`, one per human slot.

**Q4. How do I invoke fit_check?** `node tools/fit_check/check.mjs <file|dir>... [--expect-laps=<n>] [--json]` (section 19.5), for example `node tools/fit_check/check.mjs build/siege/sims/fit`.

**Q5. Does the appended cool-down get its own FIT lap?** Yes, always. Expected laps = lap-true phases that started + `lap_marker` emits + 1 for the cool-down (none if the run ended by `timeout` or `paused` before it).

**Q6. How do a client's actions and shop picks become `Telemetry.intents`?** Actions and gestures go through your `local_intents()` on the client; your widgets (a PedalScanList shop) call `ctx.intents.send()`. The client batches both into `Telemetry.intents` at 5 Hz; the host puts them into that rider's `frame.players[peer].intents` on its first tick after the telemetry arrives, once each, in order. Tag auto-confirmed picks yourself from `PedalScanList.item_picked(..., via)` (section 11).

**Q7. How does a GameModule learn its local peer id?** `ctx.local_peer` (and `ctx.local_player()`); the host's own rider in HOST and SOLO.

**Q8. What does the GameHost do when a client drops or rejoins? Does a dropped peer get `on_afk`?** Yes: `on_afk(peer, true)` at once; the slot stays with `connected` false, power and cadence 0 and a growing `age_s` (never counted as pedaling). A rejoin with the reconnect token gets `lobby_state`, its `plan`, its `phase` and the latest snapshot, then `on_afk(peer, false)` once it pedals; a restarted client starts a new FIT. After the token expires the slot stays AFK (section 14).

**Q9. How does `hud_spec()` place kit widgets? How is the power gauge's SIM band set, the strip filled, toasts and banners posted?** Section 10: widgets at anchors or art-pixel `Rect2i`s; `ctx.hud.power_band(peer, lo_w, hi_w)` sets the gauge's band (shown in SIM; ERG shows the applied target); the teammate strip draws `ctx.roster` plus each rider's `teammate_status`; `ctx.hud.toast(key, args, peer)` and `banner(key, args, seconds, peer)` with the routing table in 10.2.

**Q10. How do `course_grade`, `cadence_band` and `end_phase` reach a remote rider's governor?** The host sink checks them and sends `directive` messages (`course_grade`, `cadence_band`) to that rider's client, whose governor validates, clamps and acknowledges in `Telemetry.acks`; `end_phase` travels as that rider's `phase` message (the client's governor starts the next phase). The host records each applied record (`directive_applied`) and the report keeps them.

**Q11. How does a haptic stack with a mode grade?** As a separate channel: the haptic adds on top of the stacked grade (× intensity, ≤ +3 %, ≤ 8 s) and its expiry ends only the haptic; the boiler or hoist grade stays. No re-send is needed (section 8.1).

**Q12. How is `apply_progress` called on host and clients?** Once per session on every peer, host included, after the results arrive and before the results screen, with `ctx.progress` (the local rider's own store); update only the local rider and return its new unlocks. Skip a repeated `results.session_id` (a client restarted in the cool-down gets exactly one call).

**Q13. How do I clear a cadence band?** `ctx.directives.cadence_band(peer, 0, 0)`. The cool-down clears every band.

**Q14. `phase_changed` with per-rider plans: does the GameHost emit it?** No, never. It emits `phase_started(peer, index)` on `ctx.events` for each rider and updates `frame.phase`. Emit `phase_changed` yourself only if your riders share one sequence (Siege, Tank); Fishing doesn't need it.

**Q15. Can `tools/screenshot` set the player count, seed and time, and fast-forward?** Yes: `--players`, `--bots`, `--rider`, `--autopilot`, `--seed`, and `--at=<s>[,<s>...]` in sim seconds, stepping as fast as it can to just before each time (section 19.3). HOST runs show the host's view (slot 0).

**Q16. How do HudSpec positions map to PixelViewport art pixels?** A `Rect2i` in art pixels goes through `PixelViewport.art_rect_to_screen()`: × the integer scale, + the letterbox offset, re-laid out on resize (section 10.1). Anchors ignore the viewport.

**Q17. Are these spelled exactly so?** Yes: PlanPhase `kind`, `mode`, `target_pct`, `ramp_to_pct`, `range_pct`, `grade_source`, `course_profile`, `duration_s`, `lap`, `label`, `open_ended`, `min_s`, `max_s`, `meta`; option entries `id`, `type` (`toggle`, `int`, `choice`), `default`, `label`, `min`, `max`, `step`, `choices` (`value`, `label`); `ctx.directives.course_grade(peer, grade_pct)`, `end_phase(peer)`, `cadence_band(peer, lo_rpm, hi_rpm)`; `frame.phase`; `ctx.options`; `ctx.progress`; `ctx.hud.power_band(peer, lo_w, hi_w)`; `local_intents(actions, gestures)`; `apply_progress(results, progress)`; `picker_image`.

**Q18. Does PlayerSlot carry the haptics setting, the verified flag and the preferred cadence?** Yes: `haptics_on` (plus `haptic_intensity`), `ftp_verified`, `preferred_cadence_rpm`.

**Q19. Does PedalScanList report auto-confirms?** Yes: `item_chosen(index, id, auto)` and `item_picked(index, id, via)` with `via` `"auto"`; write `"auto": 1` into your own intent.

**Q20. Do options have an `int` type with `step`?** Yes (section 3). Siege's `wave_offset` and Fishing's `reel_pct` work as written in their briefs.

**Q21. Does `ParallaxStrip` mirror, and does `SpinningPart` reverse?** Yes: `mirror_alternate`, and a signed speed −1..1 (section 18).

**Q22. How does pixelate pick among several results of one sprite?** It uses only the result marked `selected` in `assets/<id>/art_manifest.json` (the newest by default; `--select=<sprite id>:<request id>` overrides). See `docs/ART_PIPELINE.md`.

**Q23. Does sourcing `tools/env.*` keep `FAL_KEY` and `WATTLANDS_ALLOW_ART`?** Yes: the env scripts and Godot wrappers never set, unset or print them; only `tools/run_tests` removes them from its own processes.

**Q24. How do games declare int fields for `Protocol.decode()`?** `int_fields()` (section 12).

**Q25. Where must the game load content so `--override` works?** Through `ctx.load_content_json(rel_path)` only.

**Siege-specific.** The slot patterns are defined (`Wl.slot_look`: solid, dashed, dotted, double), so use the platform pairing. A dropped client's telemetry never counts as pedaling. The GameHost never emits `phase_changed`, so Siege emits it. `PlayerSlot.ftp_verified` exists (no platform change), and `p_eff_w == power_w × p_eff_per_w` holds for every sample, so the WKG factor r can come from either. The report holds snapshot sizes and hashes, each rider's applied target, mode, `clamped_by` and rescue at 1 Hz, and the FIT paths. Make the teammate strip's per-rider raw W and %FTP from your snapshot in your own Control if the roster-fed strip isn't enough. Auto-confirmed buys: tag them from `item_picked`'s `via`.

**Tank-specific.** `ctx.hud.toast` and `banner` do take a `peer` (default every rider): raise each rider's own prompts on their own peer as in 10.2, or pass `ctx.local_peer` on the host. Haptics have their own channel. `cadence_drop` triggers by segment and applied target with `at_phase` and `at_target_pct`; haptics off for one slot is `--haptics-off=<slot>`. Detect an overrun with `PhaseState.prev_ended_by == "max_s"` on the next phase. Enemy counts × 3 for S8: `--override` or an in-memory content dictionary in a GUT test. A screenshot of the Citadel at 3 riders: `tools/screenshot --players=3`.

**Fishing-specific.** The preferred cadence is `PlayerSlot.preferred_cadence_rpm`. Gestures arrive apart from actions in `local_intents`, and a surge never also arrives as `confirm`. Int fields are declared with `int_fields()`. The haptics setting is `PlayerSlot.haptics_on`. Clear the band at Landing with `cadence_band(peer, 0, 0)`. Fishing never emits `phase_changed`. "The first 300 s of the plan" is `PhaseState.plan_elapsed_s < 300`. Autopilot off in a simulation: `--autopilot=none`. Staleness: `Telemetry.age_s` (every tick for remote riders) and `cadence_age_s`.
