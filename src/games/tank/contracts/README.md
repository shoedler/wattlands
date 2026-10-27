# Tank contracts

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
- The sprint rule is `TankRiderState.sprint_rule(evade.sprint_window_s)` (`SprintRule`, host only): "held" means the trailing 3 s average >= 1.2 x FTP; the rider's and the diesel's `sprinting` mirror `holds()`.
- Entity ids (`TankState.take_id`) are > 0; boss part ids are negative (`TankBossState.part_id`); 0 is "none".
- Per-rider gates (SIM-only patterns, haptics, warm-up numbers, the first 300 s, the in-band kind) read the receiver's own `TankRiderInput` phase fields, never the group's `TankPhaseInfo`.

## Who implements what

| Class | File | Builder | State (G4) |
| --- | --- | --- | --- |
| `TankPlanBuilder` | `effort/tank_plan_builder.gd` | effort | complete (segment table, engines, rotation, drill, meta) |
| `TankDirector` | `effort/tank_director.gd` | effort | complete: every directive pattern (bank sub-steps, boiler, hoist, terrain, cadence and power bands, haptics, `end_phase` with the boss `end_hold_s`) and the pure helpers `power_band_pct`, `bank_target_pct`, `boiler_grade_pct`, `crew_haptic` |
| `TankContent` | `content/tank_content.gd` | rules | complete: loader and validation through `TankContentSchema` |
| `TankRules` | `rules/tank_rules.gd` | rules | complete: segments, rotation, overruns, stations (the arc generator too), the drive, Surge to evade (`TankEvade`), the bow guns (`TankBow`), lanes, hull and breakdown, reserve, all-AFK, in-band, WORK time (parts in `rules/` and `combat/`) |
| `TankScore` | `rules/tank_score.gd` | rules | complete: score, grade, XP, unlocks (brief 2.8) |
| `TankBallistics` | `combat/tank_ballistics.gd` | rules | complete: analytic arc, lower-arc solver, range, lead and dispersion |
| `TankGame` | `tank_game.gd` | module | complete: the flow above, the Autopilot merge, prompts, the teammate strip and hull HP feeds, snapshot, results, progress |
| `TankAutopilot` | `autopilot/tank_autopilot.gd` | module | complete: rear traverses and obstacle shots (never a sprint, so never an evade, never an Overpressure, early latch or manual lever) |
| `TankSnapshot` | `net/tank_snapshot.gd` | module | complete encode / apply |
| `TankView` | `view/tank_view.gd` | view | complete: the cutaway diorama (parallax planes with blur and haze, rigs and rooms, additive lights, pooled particles, snapshot interpolation); works with the placeholder art for every id |
| `TankHud` | `hud/tank_hud.gd` | view | complete: the ADR's `Rect2i`s with kit widgets, the station card, the objective line and the boss bars |
| `TankAudio` | `audio/tank_audio.gd` | view | complete: synthesized sounds (`Sfx.synth`) on `cue`, created by `TankView` |
| `TankPlaceholderArt` | `view/placeholder_art.gd` | artqa | complete: a procedural palette-colour drawing per sprite id at its art.json size (silhouettes, in memory only) |

Owned paths: effort `src/games/tank/effort/`, `content/tank/stations.json`, `tests/games/tank/effort/`; rules `src/games/tank/{rules,combat,content}/`, `content/tank/{tanks,scoring,cosmetics,enemies}.json`, `content/tank/missions/`, `tests/games/tank/{rules,combat}/`; module `src/games/tank/tank_game.gd`, `src/games/tank/{autopilot,net}/`, `tests/games/tank/{module,integration}/`, `tests/games/tank/e2e_check.mjs`; view `src/games/tank/view/` (not `placeholder_art.gd`), `src/games/tank/{hud,audio}/`, `assets/tank/audio/`, `tests/games/tank/{view,hud}/`; artqa `assets/tank/` (not `audio/`), `src/games/tank/view/placeholder_art.gd`, `tests/games/tank/{art,sim,static,perf}/`, `.github/workflows/game-tank.yml`, `src/games/tank/HARDWARE_TEST.md`, `docs/credits.d/tank.md`. The lead keeps `contracts/`, `game.json`, `content/tank/strings.csv` (request keys), `docs/decisions/tank.md`, `docs/changelog.d/tank.md`, `src/games/tank/README.md`, `tests/games/tank/{contracts,fixtures}/` (the plan and safety checks in `contracts/test_tank_plans.gd` included), `tank_fakes.gd`, `test_tank_game.gd` and `test_tank_package.gd`.

## Contract files

| File | Holds |
| --- | --- |
| `tank_ids.gd` | Every id and wire code: tanks, engines (+ label keys and icon paths), segments, enemies, obstacles, shells, lever, boss phases, outcomes, intent kinds, vias |
| `tank_const.gd` | Units, screen geometry, the first-300-s rule, the steam tolerance, caps, the snapshot budget |
| `tank_record.gd` | `to_dict` / `load_dict` base for state records |
| `tank_state.gd` | `TankState` (+ `create`, lookups) with `TankSegmentState`, `TankHullState`, `TankRiderState`, stations, enemies, shells, obstacles, `TankGunLineState`, `TankBossState`, `TankScoreState` |
| `tank_station_state.gd` + `tank_{diesel,dynamo,steam,gearbox,arc}_state.gd` | One room per engine; the Bulwark's `TankGearboxState` extends the diesel; `TankArcState` is the Bastion's arc generator (v2) |
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

## v2 contract additions (2026-10-27)

Additive, for the v2 brief (`docs/games/tank.md` 2.2, 2.4, 2.6, 2.10). Behaviour (evade, bow guns, the arc's plan and searchlights, free roam) comes from later builders; these are the names they build on.

- **Ids.** `ENGINE_ARC` "arc" (code 5, label `TANK_ENGINE_ARC`, icon `engine_arc.png`); `TANK_BASTION` "bastion" (code 4, the 4th of `TANKS`, so crew 4 picks it); `SHELL_BOW` 4 (was `SHELL_SECONDARY`, name "bow"); `INTENT_TURN` "turn" (deliberate; no engine owns it yet); `DIR_RIGHT` 1 / `DIR_LEFT` -1; `OUTCOME_TIME_UP` "time_up".
- **Events.** `evade {id, e, ok}`, `turn {s, dir}`, `time_up {}` appended to `TYPES` with `INT_FIELDS`; no emitter yet.
- **`TankArcState`** (`TankStationState.make("arc")`): [snap] `duty` 0..1, `lit`, `stalled`; host-only `note_fire(tick, fired)` keeps a 200-tick (10 s) fire ring and refreshes `duty`; `reset_fire()`.
- **`TankRiderState.target_pct`** [snap]: the rider's effort target in % FTP for the power ratio, set each tick by `TankRules.target_pct(state, rider_input, station)` (applied ERG target, else `TankRiderInput.planned_pct` from `PhaseState.planned_pct`, else the SIM band centre: diesel/Bulwark 90.5, steam building 90, loaded or cycling and WARMUP-kind SIM from `tanks.json` `power_ratio`). `client_predict` refreshes the local rider's.
- **`TankHullState.dir`** [snap]: +1 travelling right (missions), -1 left (free roam turns).
- **Snapshot v2.** `tk` gains `dir` (17 columns), `r` gains `target_x10` (7), the arc's `st` row carries `duty_pml` in `a` and the `STF_LIT` / `STF_ARC_STALLED` bits. The Bastion at the caps (4 riders, 4 rooms, 16 enemies, 24 shells) is about 1.6 KB.
- **Content.** `tanks.json`: the Bastion; the Citadel's rooms in the reference's order (diesel, steam, dynamo) with only its main turret; every `hull_px` from `assets/tank/v2/kit.json` / 1.5. `validate_cross` takes start engines as any order of the rooms. `stations.json`: the arc's plans (brief 2.3 table) and crew 4's rotation ((s + k) mod 4 of diesel, dynamo, steam, arc).
- **Geometry.** `TankGeometry.RIG_FALLBACK`: the Bastion uses the Citadel's rigs.json geometry until its own entry lands (`has_rig`, `rig_of`).

## v2 gameplay (P4, the rules builder, 2026-10-27)

Brief 2.2-2.4, 2.6-2.8 on top of the contract additions above.

- **The Ram is gone.** `TankIds.INTENT_RAM`, `TankEvents.ram()` / `dodge()`, `BY_RAM`, the diesel's `ram_s`, `ram_cd_s`, `dodge_s`, `sprint_s` and `prompt`, the hull's `stall_s` and `secondary_cd_s`, `TankBossState.dodged` (now `evaded`), `TankRiderState.rams` / `dodges`, `tanks.json` `ram` (now `evade`: `sprint_window_s`, `hold_s`, `boss_hold_s`) and `stations.json` `haptics.ram` are removed. The event types `ram` and `dodge` (and kill `by` 1) stay reserved on the wire, never emitted; the snapshot keeps their columns as zeros (`tk` stall_ms, the diesel's and Bulwark's a/b, the diesel's c) and the `STF_PROMPT` bit unused. A "ram" intent is junk to `normalize`.
- **Surge to evade** (`combat/tank_evade.gd`). Telegraphed shots: destroyer 4 s, heavy 3 s, a light tank's first shot at its hold (its `flank` shot, 2.5 s, 8 damage at 70 %), the Behemoth's main gun 6 s; a telegraph always runs in full. While one runs, every rider with `can_evade` (a SIM WORK phase of its own plan past the first 300 s, present, not in rescue) and `sprinting` adds the tick to its held seconds (`aux.evade`); the shot misses when one held `evade.hold_s` (2 s; `boss_hold_s` 3 s for the Behemoth). Every telegraphed shot that resolves raises `evade {id, e, ok, s}` before its `shot`; the score and each rider count evades tried and made. No intent; the Autopilot never sprints.
- **Rider flags** [snap]: `TankRiderState.can_evade` and `sprinting` (`r` flags `RF_CAN_EVADE` 16, `RF_SPRINTING` 32). Each peer raises its own "Surge to evade" from them and the replicated telegraph times (`TankCues`).
- **Bow guns** (`combat/tank_bow.gd`): every tank; a burst (one `SHELL_BOW` round) of `bow.damage` 5 every `bow.every_s` 2 at the nearest enemy or Behemoth part 40-220 px off the hull front (else a wire or wreck there: `bow.clear_s` 4 s of fire clears it, `TankObstacleState.bow_s`); hitscan (shot + hit events), kills `BY_BOW` (3) credited to the powering station's rider. Power: the Bastion's arc generator (1 in band, `bow.under_band_rate` 0.5 under, 0 on reserve or stalled), the dynamo bank (2 units a burst, none below 10 or stalled), the Bulwark (0.5, free). `TankArcState.note_fire` every tick with "engaged".
- **The arc generator** (`TankStations._arc`): `stalled` on rescue, `lit` while its rider is in band; lit searchlights halve the main gun's dispersion (`tanks.json` `arc.lit_dispersion_mult`). Its directive is pattern 2 in `TankDirector` (`stations.json` `arc`).
- **Lanes** (`TankEnemies.reserve_hold`, `enemies.json` `lanes`, each type's `lane`): every held position (spawn, a destroyer's shift, a heavy's back-off) is reserved in one of 4 depth lanes so no two held boxes (weave and `gap_px` included) overlap on one side and lane. `TankEnemyState.lane` [snap] is the snapshot's `e` column 7.
- **Geometry**: rigs.json tank guns re-measured from the v2 kit, `tanks.<id>.bow_guns[]` (`TankGeometry.bow_muzzles`), the hull standing on the ground (`screen.skirt_gap_px` 0); `tanks.citadel.secondaries` is no longer required.

## v2 free roam (P5, the roam builder, 2026-10-27)

Brief 2.10 on the contracts above; additive (no renamed or removed name).

- **Ids.** `SEG_ROAM` "roam" (code 8, in `SEGMENTS`); `KIND_MISSION` / `KIND_ROAM` (a mission file's `kind`); the zones `ZONE_FOREST`, `ZONE_LAKE`, `ZONE_VILLAGE`, `ZONE_QUARRY`, `ZONE_MEADOW` (`ZONES`). `INTENT_TURN` is now owned by the driver (`TankIntents.OWNERS`: the diesel and the Bulwark); the rules refuse it outside free roam.
- **`TankRoamState`** (`tank_roam_state.gd`, `TankState.roam`): `active`, `map_seed`, `map_m` (the hull centre's place on the road, m), the turn (`turn_s`, `turn_cd_s`, `flipped`), the map end (`at_end`, `end_s`), `engaging`, `time_up`, `overtime`, `points` (and their sources), the odometers, the WORK clock, the patrol timer and count, per strongpoint spot `strong_back_s` / `strong_id`. `TankState.roam_map` (`TankRoamMap`, not serialized) is rebuilt from the seed on every peer (`TankRoam.ensure_map`).
- **`TankRoamMap`** (`tank_roam_map.gd`): the seeded valley from `roam/valley.json` (pure, its own LCG): `length_m`, `zones`, `terrain` (for travel east), `strongpoints`, `lo_m` / `hi_m`, `zone_at`, `grade_at(m, dir)`, `profile(n)`.
- **`TankTerrain.for_roam`**: the one sampler for free roam (the drive and the director): the valley's grade under `map_m` in the travel direction, clamped to `valley.json` `terrain_pct` (warm-up range in WARMUP kinds).
- **Snapshot.** The optional `rm` row (`RM_*`, `RMF_*`; sent only while `TankRoamState.active`, `check()` validates it when present) and `INT_PATHS` `rm[]`.
- **Events.** `time_up` carries `p` (the patrols raised before it).
- **Content.** `missions/roam_<n>.json` (`kind` "roam", `minutes`) and `roam/valley.json` (`TankContent` file key `valley`, loaded with every content, validated for a roam: `validate_roam`, `validate_valley`, `VALLEY_SPEC`); `stations.json` `roam_plans` (`TABLE_SEGMENTS` "roam_plans": depot and roam); `SEGMENT_KINDS` and `OPEN_SEGMENTS` gain the roam. `TankContent.expand_roam`, `is_roam`, `roam_minutes`, `valley` are new methods (the frozen ones are unchanged).
