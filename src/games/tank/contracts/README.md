# Tank contracts (G0)

The shared types every Diesel Domestiques builder codes against. The lead owns this folder after G0: builders adapt inside their own paths and request changes (additive where possible) in their report under `contract_change_requests`. Brief: `docs/games/tank.md`; decisions: `docs/decisions/tank.md`; platform: `docs/GAME_SDK.md`.

## Data flow per tick (host / SOLO, every 0.05 s of game time)

```
InputFrame (frame.players[peer] Telemetry, frame.phase[peer] PhaseState)
  -> TankGame._collect_intents: TankIntents.normalize -> owned by the rider's engine -> TankIntentLimiter (5/s/peer);
     the module also adds TankAutopilot output for an unflagged human on the fallback or on reserve (see below)
  -> TankInputs.from_frame: the rider input digest (TankRiderInput per slot) + the group's phase (TankPhaseInfo:
     the lowest phase index any rider is in, with its PlanPhase.meta {seg, stage, segment, engine, mission})
  -> TankRules.step(state, inputs, dt) -> Array[Dictionary] events (TankEvents)        [pure; state.rng only]
  -> TankDirector.step(state, inputs, events) -> ctx.directives (request, course_grade, cadence_band, end_phase)
                                                 and ctx.hud.power_band                  [reads state, never writes it]
  -> send_event(e) for each event (clients get them in order in apply_event)
  -> phase_changed(group index) on change; finished(state.outcome) once every rider is in the cool-down
snapshot() at 10 Hz -> TankSnapshot.encode(state) (TankSnapshotSchema, ints, <= 4 KB at 16 enemies / 24 shells)
```

Clients: `apply_snapshot` -> `TankSnapshot.apply(state, snap)` -> `snapshot_applied(state.tick)`; `apply_event` raises local effects (toasts, sound) through `cue`; `client_predict` moves only the local rider's own room. The view (`TankView`) and HUD only read `TankGame.state`.

## Module and view

- The module (`TankGame`) owns the tick flow above, intents from `local_intents`, the Autopilot, prompts per peer, results and progress. It emits `cue(kind, data)` for every event and, on clients, `snapshot_applied(tick)` after each snapshot.
- The view (`TankView`) owns snapshot interpolation: a `WorkoutSnapHistory`-style buffer keyed by `state.tick`, fed from `snapshot_applied`, the render clock behind the newest snapshot by the mean spacing (notes). It creates `TankAudio` as its child and connects `game.cue` to `TankAudio.on_cue`. Tank Controls (station card, trajectory dots, boss bars, objective line) send their intents themselves with `game.ctx.intents.send(TankIntents.*)`.

## TankContent surface (frozen)

`TankState.create` and effort's `TankPlanBuilder` depend on these `TankContent` methods, so their names, arguments and meanings are contract: `ok`, `num(file, path, default)`, `value(file, path, default)`, `mission`, `segments`, `segment(i)`, `mission_rotates`, `plan_table`, `plan_entry(engine, seg_type)` (checkpoints: the table's `checkpoint` entry), `tank_def`, `engines_of`, `start_engines`, `rotation_row(tank, slot)` (the start engine x4 for a slot without a row), `enemy_def`, `boss_def`, `enemy_scale`, `scaled_count`, `unlocks`. The rules builder owns the file and may add methods and change internals, never these.

## Geometry (frozen keys of `assets/tank/rigs.json`)

`TankGeometry` (`tank_geometry.gd`) is the only way code reads gameplay geometry: the tank's `turret.ring`, `turret.trunnion`, `turret.barrel_px` and `muzzle`, the Citadel's `secondaries[]` (`muzzle`, `facing`), every enemy's `muzzle`, the dug-in's `hitbox`, the Behemoth's `bogies`, `turret.rect`, `turret.muzzle` and `secondary_muzzle`. Frames: tank points in the hull frame (the hull sprite's top-left, y down, facing right; facing left mirrors x about the ring); enemy points in their sprite's frame facing left; boss points in `boss_hull`'s frame. At elevation a the muzzle is `trunnion + barrel_px x (cos a, -sin a)`; `validate()` checks the keys and that the file's muzzle equals `trunnion + [barrel_px, 0]`. artqa re-measures values, never names or frames; rules tests read the file through `TankGeometry`, never hard-coded numbers.

## Drive, sprint and ids

- The drive is `TankHullState.speed_model(cda, offset)` (`SpeedModel`, host only), with `rider_mass_kg` set each tick from the `TankRiderInput` of the rider on the diesel or bulwark station; `speed_mps` is its v.
- The sprint rule is `TankRiderState.sprint_rule(ram.sprint_window_s)` (`SprintRule`, host only): "held" means the trailing 3 s average >= 1.2 x FTP; `sprinting` mirrors `holds()`, `sprint_s` and `dodge_s` count `held_s()`.
- Entity ids (`TankState.take_id`) are > 0; boss part ids are negative (`TankBossState.part_id`); 0 is "none".
- Per-rider gates (SIM-only patterns, haptics, warm-up numbers, the first 300 s, the in-band kind) read the receiver's own `TankRiderInput` phase fields, never the group's `TankPhaseInfo`.

## Who implements what

| Class | File | Builder | G0 state |
| --- | --- | --- | --- |
| `TankPlanBuilder` | `effort/tank_plan_builder.gd` | effort | complete first version (segment table, engines, rotation, drill, meta) |
| `TankDirector` | `effort/tank_director.gd` | effort | end_phase rule, cadence band (60, 120) at segment start, driver power band in WORK SIM phases only, the pure helpers `power_band_pct`, `bank_target_pct`, `boiler_grade_pct`, `crew_haptic`; adds patterns 1-4, the loader band and haptics |
| `TankContent` | `content/tank_content.gd` | rules | working loader + validation through `TankContentSchema` |
| `TankRules` | `rules/tank_rules.gd` | rules | segment tracking, rotation and overrun events, stations, reserve, all-AFK, in-band, WORK time; placeholder drive and objective (replace) |
| `TankScore` | `rules/tank_score.gd` | rules | score, grade, XP, unlocks (brief 2.8) |
| `TankBallistics` | `combat/tank_ballistics.gd` | rules | analytic arc, lower-arc solver, range; adds lead and dispersion |
| `TankGame` | `tank_game.gd` | module | working skeleton (see the flow above) |
| `TankAutopilot` | `autopilot/tank_autopilot.gd` | module | stub (returns no intents) |
| `TankSnapshot` | `net/tank_snapshot.gd` | module | complete encode / apply |
| `TankView` | `view/tank_view.gd` | view | flat placeholder drawing |
| `TankHud` | `hud/tank_hud.gd` | view | the ADR's `Rect2i`s with kit widgets and empty Tank Controls |
| `TankAudio` | `audio/tank_audio.gd` | view | silent stub (`on_cue`), created by `TankView` |
| `TankPlaceholderArt` | `view/placeholder_art.gd` | artqa | a flat palette block per sprite id at its art.json size |

Owned paths: effort `src/games/tank/effort/`, `content/tank/stations.json`, `tests/games/tank/effort/`; rules `src/games/tank/{rules,combat,content}/`, `content/tank/{tanks,scoring,cosmetics,enemies}.json`, `content/tank/missions/`, `tests/games/tank/{rules,combat}/`; module `src/games/tank/tank_game.gd`, `src/games/tank/{autopilot,net}/`, `tests/games/tank/{module,integration}/`, `tests/games/tank/e2e_check.mjs`; view `src/games/tank/view/` (not `placeholder_art.gd`), `src/games/tank/{hud,audio}/`, `assets/tank/audio/`, `tests/games/tank/{view,hud}/`; artqa `assets/tank/` (not `audio/`), `src/games/tank/view/placeholder_art.gd`, `tests/games/tank/{art,sim,static,perf}/`, `.github/workflows/game-tank.yml`, `src/games/tank/HARDWARE_TEST.md`, `docs/credits.d/tank.md`. The lead keeps `contracts/`, `game.json`, `content/tank/strings.csv` (request keys), `docs/decisions/tank.md`, `docs/changelog.d/tank.md`, `src/games/tank/README.md`, `tests/games/tank/{contracts,fixtures}/` (the plan and safety checks in `contracts/test_tank_plans.gd` included), `tank_fakes.gd`, `test_tank_game.gd` and `test_tank_package.gd`.

## Contract files

| File | Holds |
| --- | --- |
| `tank_ids.gd` | Every id and wire code: tanks, engines (+ label keys and icon paths), segments, enemies, obstacles, shells, lever, boss phases, outcomes, intent kinds, vias |
| `tank_const.gd` | Units, screen geometry, the first-300-s rule, the steam tolerance, caps, the snapshot budget |
| `tank_record.gd` | `to_dict` / `load_dict` base for state records |
| `tank_state.gd` | `TankState` (+ `create`, lookups) with `TankSegmentState`, `TankHullState`, `TankRiderState`, stations, enemies, shells, obstacles, `TankGunLineState`, `TankBossState`, `TankScoreState` |
| `tank_station_state.gd` + `tank_{diesel,dynamo,steam,gearbox}_state.gd` | One room per engine; the Bulwark's `TankGearboxState` extends the diesel |
| `tank_phase_info.gd`, `tank_rider_input.gd`, `tank_inputs.gd` | The rider input digest and the group's phase |
| `tank_intents.gd`, `tank_intent_limiter.gd` | Intent wire and normalized forms, ownership by engine, the 5/s limit |
| `tank_events.gd` | Event types, fields, builders, `INT_FIELDS` |
| `tank_snapshot_schema.gd` | Snapshot keys, columns, flag bits, `INT_PATHS`, `check()`, `byte_size()` |
| `tank_content_schema.gd` | Validators for tanks, stations, enemies, missions, scoring and cosmetics, the brief's safety envelope (bounds a G2 retune cannot pass) and `validate_cross` |
| `tank_geometry.gd` | The frozen gameplay geometry of `assets/tank/rigs.json` |
| `tank_terrain.gd` | The one terrain sampler (`grade_at`, `for_segment`): the rules roll the hull on it and the director pushes `course_grade` from it |

## Units and constants

Art px of the 640 x 360 view (world x in art px along the segment, 8 px per game metre: 0.4 x 20 px per visual metre); game metres for driving; game seconds (0.05 s ticks); joules of P_eff; % FTP. Ground line y 296; the hull's rear at screen x 16, its bottom 10 px above the ground; HUD only in y 0-60 and 300-360; PANIC at x >= 503 and y >= 316. Snapshot wire units: 0.1 px, ms, cm/s, x10 grades and angles, HP rounded up. Content numbers live in `content/tank/*.json`, never in code.

## Rules every builder keeps

- Every BRIEF 4.6 and 4.5 rule outranks gameplay; only `TankDirector` calls `ctx.directives` (no-bypass gate, SDK 21).
- `rules/`, `effort/`, `combat/` and the module use no `Time.*`, `OS.get_ticks*`, global `randi`/`randf` or `RandomNumberGenerator.new()`; randomness is `state.rng` (ctx.rng).
- Iterate in slot order; ids never reused; lists keep a fixed order.
- New string keys are requested from the lead (`TANK_` prefix); new contract fields are requested, never edited here.

## G2 additions (integration)

- **One terrain sampler.** `TankTerrain.for_segment(content, segment, distance_m, warmup)` (`tank_terrain.gd`, here in `contracts/`) is the only place a mission segment's `terrain` points become a grade: linear between points, held past either end, clamped to `stations.json` `terrain.warmup_grade_pct` (0..+2%) in WARMUP kinds and to -3..+6% otherwise. `TankDrive` writes `TankHullState.grade_pct` with it for the speed model (warm-up when the segment kind is WARMUP) and `TankDirector.terrain_grade_pct` is a thin wrapper that the director pushes with `course_grade` (warm-up from the receiver's own phase kind), so the tank speeds up and slows down on exactly the hill the rider feels. Never sample `terrain` anywhere else.
- **`TankIds.EM_LEAVE` (6).** A raider (light tank with `linger_s`) that breaks off: it rolls away, fires no more and is removed off screen with no kill credit. `EM_MOVE` stays a destroyer's shift after a shot. The snapshot carries `mode`, so clients and the view tell them apart.
- **`stations.json` `hoist.step_s`** (positive, default 1): the hoist grade rises `rise_pct_s x step_s` per whole `step_s` counted from reaching Hoist, so it is never above `rise_pct_s x time`. It is in `STATIONS_SPEC`.
- **Boss bogie order.** Bogie index 0 is the one nearest the tank (the lowest x in the `boss_hull` frame, rigs.json order; the Behemoth faces left); index 2 is the farthest. Auto-aim takes the lowest standing index. Part ids -1..-3 follow the index.
- **`TankAux`** (`rules/tank_aux.gd`): host-only bookkeeping on the state as object metadata (`TankAux.of(state)`), so the frozen `TankState` is unchanged. It holds the loaded geometry, this tick's target list (`aux.targets`, valid after `TankRules.step` for the Autopilot and the view's trajectory dots), the auto-aim choice, enemy velocities, distances, ages and shots, shell arrival times and the Ram contact flag. Never serialized; clients never need it.
- **Engagement rules** (rules builder; numbers in `tanks.json`, `enemies.json` and the mission): the main gun depresses to -5 degrees, so it cannot reach anything nearer than about 230 px from the muzzle (lights nearer than about 115 px, rear lights, anything inside 230 px are Ram or secondary prey); gun-line `at_px` values (214 / 234 / 254 dug-in, 222 / 248 in stages 2 and 3, 300 heavy) keep every gun inside that reach for all three tanks (tested); a barricade stops the tank `props.standoff_px` (260) short of it, where the gun can reach; the Behemoth stops at `stop_px` 150 (brief 120: the front bogie would sit inside the gun's minimum range) and starts 470 px from the left edge. Raiders with `linger_s` (light: 45 s) break off, so a compliant crew that never rams is not worn down by rear lights.
- **Autopilot for unflagged humans.** The platform merges `autopilot_intents()` only for flagged riders and bots. `TankGame._collect_intents` adds `TankAutopilot` output, through the same engine ownership and 5/s filter, for a human who has not yet sent a deliberate intent (the fallback) whether or not the lobby Autopilot flag is set, and always for a station on reserve (AFK or dropped). `_end_fallback` ends the fallback of any human on a deliberate intent. The Autopilot is a stateless function of `TankState`.
- **Cadence band.** (60, 120) at every segment start for every rider; (50, 120) only while the steam rider's shell is loaded or cycling in a WORK phase (brief 2.3 pattern 5), then back to (60, 120).
- **Sprite id `flyball`** (was `governor`; the no-bypass scan forbids that literal in game code). `TankSprites.flyball_id()` returns it.
