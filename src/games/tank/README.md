# Diesel Domestiques (`tank`)

One to four riders crew a pedal-powered landship through a starry forest night, one engine each: the diesel drives, the dynamo aims, the steam engine loads, the arc generator lights the searchlights and feeds the bow guns. A solo rider gets the Bulwark, whose diesel does everything through a three-way gearbox. Presentation `2d` (the reference's night diorama at 960 x 540; the rules keep 640 x 360 units), version 0.2.0, 1 to 4 riders, no bots. Brief: `docs/games/tank.md`. Decisions: `docs/decisions/tank.md`. Contracts and the per-tick data flow: `contracts/README.md`. Real-trainer checklist: `HARDWARE_TEST.md`. Credits: `docs/credits.d/tank.md`.

Status: P0 complete. Every crew size plays Ashfall Road (30 to 41 minutes) to the results with zero input. The art is procedural placeholders (no fal run was made) and the sound is synthesized. Nothing has run on a real trainer (see "Known gaps and P2 notes").

## How to play

- **Pedal.** Your watts (P_eff) run your engine. Each station is lit and its machinery turns on your cadence; the room glows and its wall lamp lights when you are "in band".
- **Crew size picks the tank.** 1 rider: Bulwark (220 x 71 rules px hull); 2: Rampart (251 x 71, diesel and dynamo); 3: Citadel (296 x 71, diesel, steam and dynamo); 4: Bastion (327 x 71, the Citadel plus an arc-generator room and a searchlight tower). Every tank has two bow guns in its nose. Slot 0 starts on the diesel, slot 1 on the dynamo, slot 2 on the steam engine, slot 3 on the arc generator. The `rotation` option (lobby toggle, default on) moves every rider to the next engine at each checkpoint (diesel, dynamo, steam, arc, among the tank's engines); with it off nobody moves.
- **Surge to evade.** Some enemy shots are telegraphed: a tank destroyer's 4 s glint, a heavy tank's 3 s muzzle glow, a light tank's 2.5 s flank shot (its first shot at its hold distance, 8 damage), the Behemoth's 6 s main gun. If any rider who can evade (in a SIM WORK phase past the first 300 s: the diesel, the steam engine, the Bulwark) holds the sprint rule (their last 3 s average at least 1.2 x FTP) for 2 s inside the telegraph (3 s for the Behemoth), the shot misses. There is no button: your legs are the input, so the Autopilot never evades.
- **Diesel** (the Bulwark's gearbox when solo): SIM. The tank's speed is your SIM speed; in band is 76-105 % of FTP. At a gun line the tracks lock and you "dig in" at ERG 90 %: in band you build a mud berm that absorbs hits (1 HP per 250 J, max 40).
- **Dynamo** (gunner): ERG. The target is its capacitor bank: it starts at 55 % FTP and climbs to 100 % as the bank drains. Power at 95 % of the target and cadence 60 charges the bank (1 unit per 150 J). The bank pays for stabilizing the gun while an enemy is on screen (the Bastion's heavier turret more), elevation, traverses, the Rampart's hoist and the bow guns of the Rampart and the Citadel (2 units a burst, none below 10).
- **Arc generator** (the Bastion): ERG 65 to 80 %: the target lifts with the arc load, the share of the last 10 s the bow guns fired (65 + 15 x duty). In band (power at 95 % of the target, cadence 60) the searchlights are lit (the main gun's dispersion halves) and the bow guns fire every 2 s; under band every 4 s; on reserve or stalled not at all. Auto-aim picks targets and fires; `left` / `right` cycle targets, `up` / `down` nudge the elevation (auto-aim pauses 5 s), `ability_2` traverses the turret to the other side, `confirm` fires.
- **Steam** (the Citadel's loader): SIM flat. Pressure builds with your watts (100 % = 4.5 kJ) and the boiler adds resistance as it builds (8 % x pressure). At 100 % a heavy shell latches after a 5 s window ("Surge to overpressure" inside it builds up to 150 % on a sprint, for a double-damage shell); `confirm` latches a light shell from 40 %. Each latch drops the boiler grade to 0 for the 6 s breech cycle. In band is 90 % FTP while building, cadence 50 while a shell is loaded or cycling.
- **Bulwark gearbox** (solo): the lever sits on Drive, Turret or Hoist (`left` / `right` / `swap` move it, 1 s with no power anywhere). The auto-lever (default on) picks Hoist when unloaded with a target in range, Turret when loaded and off target, otherwise Drive; a manual move suspends it for 15 s. Hoist adds a 4 % grade on top of the terrain in an Advance.
- **Zero input works.** The defaults play every station: the diesel drives on watts and digs in, auto-aim aims and fires, the boiler latches a heavy shell at 100 %, the auto-lever runs the Bulwark. The bow guns fire on their own. The Autopilot adds rear traverses and obstacle shots; it never latches early, moves the lever by hand, sprints (so never evades) or Overpressures, and never changes effort. A human counts as Autopilot until their first deliberate `lever`, `aim`, `target`, `traverse`, `fire`, `latch` or `turn` intent (an `over` never ends it).
- **Reserve and AFK.** A rider who stops pedaling gets the floor after 3 s, the platform's pause symbol and a stopped ride timer after 5 s (BRIEF 3.5), and goes AFK after 10 s; a dropped peer is AFK at once. That station runs on reserve (as if 60 W, never in band) under the Autopilot and keeps its plan until the rider returns. When every rider in the crew has stopped, the host pauses the game (`all_stopped`) until one pedals again. A solo rider who stops pedaling pauses after 5 s.
- **Rescue.** A cadence collapse in a dynamo or arc phase at 60 % of FTP or more, or in any 90 % gun line, arms the platform's rescue (target 50 %): the dynamo stalls (turret frozen, bank not charging, toast "Dynamo stalled"), the arc generator stalls (bow guns stop, searchlights dark, toast "Arc generator stalled"), the Bulwark's gun line gives nothing power, the berm stops growing. The plan continues.

## Rules summary

Numbers are the current content (`content/tank/*.json`) after the v2 rules pass (P4); where they differ from the brief, the ADRs "G1 rules: balance retune", "Balance iteration 1" and the P4 rules entries in `docs/decisions/tank.md` name the number and the evidence.

**The session**: depot, then three stages of (Advance, gun line, checkpoint), then the boss, then the platform's 180 s cool-down. Every phase is a FIT lap (12 laps). Advances, gun lines and the boss are open-ended: once the objective is done and `min_s` has passed ("Regroup" until then), the director ends the phase for every rider in one step; the platform cuts it at `max_s`, which is an overrun and costs score (an Advance tows the tank to the halt line, a gun line is finished by a support barrage, the Behemoth withdraws).

**Objectives**: an Advance is done when the tank has driven the segment's `length_m` to the halt line; a gun line when every gun is down (the dozer then shoves the tank traps aside); the boss when the Behemoth dies (`victory`). If the boss reaches `max_s` the Behemoth withdraws (`withdrawn`). The ride itself never fails.

**Drive**: the SIM speed model (BRIEF 3.11) with mass = rider mass + 8 kg and CdA 0.5 m2, on the terrain grade under the tank; the world scrolls at 0.4 x game speed, 20 art px per visual metre. While the driver is in band, enemy hit chances are x 0.5 (evasive). A barricade (wire, a wreck) stops the tank 180 px short of it, where the main gun and the bow guns reach; a heavy shell, three light shells or 4 s of bow-gun fire clears it.

**Gun**: the main turret faces right or left; a traverse flips it. Elevation -12 to +30 degrees, shells fly 360 px/s under 300 px/s2 gravity and inherit the hull's speed; the solver reaches a light tank at its hold distance from every tank (tested). Auto-aim priority: tank destroyer in telegraph, dug-in, heavy, medium, light, obstacle, nearer first (lower arc, with lead); it fires within 0.5 degrees once a shell is loaded. Damage: light 20, heavy 50, Overpressure 100; splash 16 px at 50 %. Mediums take 50 % from light shells and bow-gun bursts; heavies, destroyers and the Behemoth take 25 % from them.

**Bow guns** (every tank): a 5-damage burst every 2 s at the nearest enemy (or Behemoth part) ahead whose near edge is 40-220 px off the hull front, else a barricade there; hitscan. Power: the Bastion's arc generator (full rate in band, half under band, none on reserve or stalled), the Rampart's and the Citadel's dynamo bank (2 units a burst, none below 10), the Bulwark's gearbox (half rate, free). Rear light tanks are out of every gun's reach; they break off after 45 s.

**Lanes**: every enemy holds its position in one of four depth lanes, and no two held positions on one side and lane overlap (the view draws the lanes).

**Enemies** (HP and counts x 0.75 Bulwark, 0.8 Rampart, 1.0 Citadel, counts rounded, at least 1):

| Enemy | HP | Behaviour | Gun (damage / every / hit) |
| --- | --- | --- | --- |
| Light tank | 30 | rushes to 120-140 px, weaves, rammable, breaks off after 45 s | 2.5 / 4 s / 50 % |
| Medium tank | 64 | holds 260-340 px | 4 / 6 s / 60 % |
| Tank destroyer | 50 | stops at the screen edge, 4 s glint telegraph, shifts 40 px after each shot | 9 / 9 s / 75 % |
| Dug-in tank | 50 | gun line; only the turret above the concrete is hit | 5 / 7 s / 60 % |
| Heavy tank | 100 | gun-line duel at 300-380 px, 3 s telegraph, backs off 30 px per 50 damage | 7 / 7 s / 60 % |
| Behemoth (boss) | 3 bogies x 50, turret 270 | creeps to 150 px, each broken bogie pushes it back 24 px, phase 2 immobile; main gun every 35-45 s (25-35 s in phase 2) after a 6 s telegraph | main 13 / 75 %, secondary 2 every 5 s / 50 % |

Telegraphed shots (destroyer, heavy, the light's first shot at its hold, the Behemoth's main gun) can be evaded (How to play). Caps: 16 enemies, 24 shells. Enemy hits roll with `ctx.rng` at fire time; the shell lands on the tank or 20-40 px off. Encounters come only from the mission's fixed lists.

**Hull**: 140 HP, +30 at each checkpoint (the maximum rises by 30 and it heals 30). At 0 HP: breakdown (no movement or fire, damage ignored) until the driving station's P_eff has paid 5 kJ, then 40 HP.

**Score** = 1000 x (0.3 band + 0.2 accuracy + 0.3 objectives + 0.2 survival). Band = the crew mean of WORK time in band; accuracy = main-gun hits / shots (0 with no shot); objectives = 0.6 x stages completed without an overrun / 3, plus 0.4 if the Behemoth died; survival = max(0, 1 - 0.25 x breakdowns). Grades: S >= 900, A >= 800, B >= 650, C >= 500, else D. XP = round(kJ / 10) + S 60, A 40, B 25, C 10, D 0. Hull finishes (`content/tank/cosmetics.json`, saved to `ctx.progress`): Soot on the first finish, Rust at B, Ash at A, Mud stripe at S, Brass machinery for a Behemoth kill with no breakdown. Equipping a finish needs the garage (P1, below). The `drill` has no boss, so its WORK time is 0 and its grade is D.

### Effort tables

Every rider has a plan of the same shape. Targets are % FTP; the platform's governor clamps everything (BRIEF 4.6) and ramps every ERG / SIM switch (BRIEF 4.5). Grades are before the rider's difficulty setting.

| Segment (kind, length) | Diesel | Dynamo | Steam | Bulwark |
| --- | --- | --- | --- | --- |
| Depot (WARMUP, 300 s) | SIM, terrain 0 to +2 % | ERG 50 % ramping to 65 % | SIM flat, boiler 3 % x pressure | SIM, terrain 0 to +2 %, Hoist 1 % |
| Advance (WORK, nominal 180 s, `min_s` 90, `max_s` 300) | SIM, terrain -3 to +6 %; evade sprints | ERG 55 %, `range_pct` [55, 100] (the bank) | SIM flat, boiler 8 % x min(pressure, 1); Overpressure and evade sprints | SIM, terrain + Hoist 4 %; evade sprints |
| Gun line (WORK, 120 s, 60-180) | **ERG 90 %** | the bank, as the Advance | the boiler, as the Advance | **ERG 90 %**; Hoist sends nothing |
| Checkpoint (RECOVERY, 60 s) | ERG 50 % | ERG 50 % | ERG 50 % | ERG 50 % |
| Boss (WORK, 240 s, 120-360) | SIM flat; evade sprints | the bank | the boiler; evade sprints | SIM flat + Hoist 4 % or 0; evade sprints |
| Cool-down (appended, 180 s) | ERG 50 %; Tank sends nothing | | | |

The arc generator (Bastion): depot ERG 50 % ramping to 65 %, Advance, gun line and boss ERG 65 % with `range_pct` [65, 80] (the arc load), checkpoints 50 %.

Nominal 300 + 3 x (180 + 120 + 60) + 240 + 180 = 1800 s; at most 2460 s. A checkpoint already carries the next segment's engine. Rotation rows (stage 1, 2, 3, boss): Rampart slot 0 diesel, dynamo, diesel, dynamo and slot 1 the reverse; Citadel slot 0 diesel, dynamo, steam, diesel, slot 1 dynamo, steam, diesel, dynamo, slot 2 steam, diesel, dynamo, steam; Bastion slot s works engine (s + k) mod 4 of diesel, dynamo, steam, arc in stage k + 1 (the boss is k = 3). The `drill` plan (130 s) uses `stations.json` `drill_plans` and ignores rotation.

**Directives** (all through `ctx.directives`, `source: "tank"`, sent only by `TankDirector`):

1. Bank: `{mode: ERG, target_pct: 55 + 45 x (1 - bank/100), reason: "bank"}` clamped to the phase's `range_pct`; an update every 5 s moves at most 10 points and is sent as three sub-steps 1 s apart (at most 3.3 % FTP per second); none in the depot or checkpoints.
2. Arc: `{mode: ERG, target_pct: 65 + 15 x duty, reason: "arc"}` clamped to the phase's `range_pct`, on the bank's schedule (every 5 s, at most 10 points, three sub-steps 1 s apart); none in the depot or checkpoints.
3. Boiler: `{mode: SIM, mode_grade: 8 % x min(pressure, 1), reason: "boiler"}` (3 % in WARMUP), at most once per second, rises at most 0.5 % per step, drops to 0 in one step at a latch and stays 0 while a shell is loaded or cycling; only in SIM phases.
4. Hoist (Bulwark): `{mode: SIM, mode_grade: 4 % (1 % in WARMUP), reason: "hoist"}` rising 1 % per second from reaching Hoist, 0 at once on leaving; none in a gun line.
5. Terrain: `course_grade` at 2 Hz in `grade_source: game` phases, the grade under the tank (one sampler, `TankTerrain`).
6. `cadence_band(60, 120)` at every segment start, (50, 120) while the loader's shell is loaded or cycling in a WORK phase; `power_band` 76-105 % FTP for diesel and Bulwark riders in WORK SIM phases.
7. Haptics: a hit (the content's `haptics.hit.min_damage`) +2.0 % for 1.5 s to every rider in SIM; a Behemoth main-gun hit +3.0 % for 2.0 s to every rider in SIM; an evaded shot is a miss, so no haptic. Never in WARMUP, the first 300 s or the cool-down, never to an ERG rider or one who opted out; 15 s apart. The governor scales them by the rider's intensity setting.
8. `end_phase` once the objective is done and `min_s` has passed; nothing in the cool-down.

Evade and Overpressure sprints send nothing: the rider sprints inside the phase's own SIM. They are off in WARMUP phases, ERG phases and the first 300 s.

## Content

| Content | Plan | Notes |
| --- | --- | --- |
| `ashfall_road` (default, zero-input) | depot 300 s, 3 x (Advance 90-300 s, gun line 60-180 s, checkpoint 60 s), boss 120-360 s, cool-down 180 s | 30 min nominal, 41 min at most; 12 FIT laps; Poplar Road (1100 m), Kettle Ford (1200 m), Quarry Ridge (950 m), Foundry Gate |
| `drill` (e2e) | depot 30 s, skirmish 70 s (WARMUP), checkpoint 30 s, cool-down 180 s | inside the warm-up limits, no haptics, at most one mode switch per rider; 4 FIT laps |

### Content files and schemas

Every file is JSON, validated at load by `TankContentSchema` (`contracts/tank_content_schema.gd`). The validator also holds each effort number to the brief's safety envelope (BRIEF 4.6), so a retune cannot move a number past it: a bad value is a load error and the game lists no plans. The `_doc` key of each file explains its keys.

| File | Holds |
| --- | --- |
| `tanks.json` | `tanks` (code, crew, hull size, engines, turrets, `enemy_scale`, the Bastion's `stabilizer_per_s`), `hull`, `drive`, `evade`, `berm`, `in_band`, `power_ratio`, `dynamo`, `steam`, `gearbox`, `gun`, `damage`, `bow`, `arc`, `caps`, `props`, `drill` |
| `stations.json` | engines and start engines, `rotation` rows, `plans` per engine and segment type, `drill_plans`, `terrain`, `bank`, `arc`, `boiler`, `hoist`, `cadence_band`, `haptics` |
| `enemies.json` | `types` (light, medium, destroyer, dugin, heavy: HP, size, preferred `lane`, hold distance, speed, gun, the light's telegraphed `flank` shot) and the `boss` (bogies, turret, main and secondary guns, telegraph), shell speed, miss distance, `lanes` |
| `missions/<id>.json` | `id`, `label`, `rotation`, `plan_table`, `segments[]` (`id`, `type`, `stage`, `kind`, `duration_s`, `min_s`, `max_s`, `length_m`, `terrain` as `[distance_m, grade_pct]` points, `encounters[]` with `at_m` / `enemy` / `count` / `from`, `obstacles[]`, gun-line `enemies[]` with `at_px`, `props`, `drills`, `teach`) and the `cooldown` backdrops |
| `scoring.json` | score weights and scale, objective fractions, survival per breakdown, grade cut-offs, XP |
| `cosmetics.json` | hull finish unlock rules |
| `strings.csv` | every user-facing string, keys `TANK_*` (`strings.csv.import` and `strings.en.translation` are generated; commit them) |

### Tuning knobs

Everything below is a content number: change it in the file, re-run the matrix (`run_sims.sh`) and keep T1-T6 green. The brief gave the starting values; tuning is held to +-50 % unless an ADR records the sim evidence.

| Knob | File and key | Now |
| --- | --- | --- |
| Enemy HP and count per tank | `tanks.json` `tanks.<tank>.enemy_scale` | Bulwark 0.75, Rampart 0.8, Citadel 1.0, Bastion 1.2 |
| Hull toughness | `tanks.json` `hull.hp`, `hull.checkpoint_hp`, `hull.repair_j` | 140, 30, 5000 |
| What driving in band avoids | `tanks.json` `drive.evasive_hit_mult` | 0.5 |
| Enemy guns | `enemies.json` `types.<t>.gun`, `boss.main` | see the table above |
| Dynamo bank | `tanks.json` `dynamo.stabilizer_per_s`, `per_traverse`, `per_degree`, `hoist_s` | 1.5, 15, 0.5, [22, 11] |
| Steam fill and latch | `tanks.json` `steam.full_j`, `window_s`, `breech_cycle_s` | 4500, 5, 6 |
| Bulwark gearbox | `tanks.json` `gearbox.hoist_j`, `auto_drive_clear_px`, `manual_suspend_s` | 4000, 340, 15 |
| Surge to evade | `tanks.json` `evade.sprint_window_s`, `hold_s`, `boss_hold_s`; telegraphs `enemies.json` `types.<t>.telegraph_s`, `types.light.flank`, `boss.main.telegraph_s` | 3, 2, 3; 4 / 3 / 2.5 / 6 s |
| Bow guns | `tanks.json` `bow` | 5 every 2 s, 40-220 px, 2 units a burst, under band 0.5, Bulwark 0.5, 4 s to clear |
| Arc generator | `tanks.json` `arc.lit_dispersion_mult`; `stations.json` `arc` | 0.5; 65 + 15 x duty |
| Bank, arc, boiler, hoist, terrain and haptic directive shape | `stations.json` `bank`, `arc`, `boiler`, `hoist`, `terrain`, `haptics` | schema-bounded |
| Spacing | `enemies.json` `lanes` | 4 lanes, 8 px gaps |
| Stage length and enemy lists | `missions/ashfall_road.json` `segments[].length_m`, `encounters`, `enemies`, `at_px` | Advances 1100 / 1200 / 950 m |
| Boss pacing | `enemies.json` `boss`; the mission's boss `start_left_px` and `end_hold_s` | `end_hold_s` 6.5 |
| Score and grades | `scoring.json` | as above |

## Tests, gates and commands

```bash
. tools/env.sh
# Tank GUT suite (strict): unit, static, art, balance harness, S8 stress, rules-step perf
env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/run_tests --only=gut --gdir=res://tests/games/tank
env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/godot.sh --headless --path . -s tools/check_scripts.gd
# Node tests: the sim checker, the art.json dry run, the e2e report checker
(cd tests/games/tank && node --test)
# Lint
uvx --from gdtoolkit==4.5.0 gdformat --check src/games/tank tests/games/tank
uvx --from gdtoolkit==4.5.0 gdlint src/games/tank tests/games/tank
# Simulation matrix S1-S7, S9 and S10, then check_sims.mjs with fit_check on every FIT
bash tests/games/tank/sim/run_sims.sh          # or: run_sims.sh s2 s5 s9 s10   (TANK_SEEDS="1" for one seed)
node tests/games/tank/sim/check_sims.mjs build/tank/sims --fit
# One run by hand
env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/run_game_sim --game=tank --content=drill --players=1 --rider=erg --seed=1 --report=build/tank/sims/drill.json
node tools/fit_check/check.mjs build/tank/sims/fit --expect-laps=4
# The e2e (host plus two clients, drill) holds three Godot slots: run it when nothing else does
env -u FAL_KEY -u WATTLANDS_ALLOW_ART node tools/e2e/run.mjs --games=tank
# Play it: start the app with a mock trainer and pick Diesel Domestiques (the wrapper stops after 20 minutes without --timeout)
tools/godot.sh --timeout=7200 --path . -- --mock-trainer=erg
# Screenshots: the depot, the skirmish, a gun line and the boss, solo
env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/screenshot --game=tank --content=ashfall_road --at=60,400,560,1500
```

The simulation matrix (`tests/games/tank/sim/`, checked by `check_sims.mjs`):

| Run | What it asserts |
| --- | --- |
| S1 compliant `erg` riders, crews 1-3, seeds 1-3 | T1 phase times, no overrun, grade B or better; T2 (crews 2-3) the dynamo above 80 % for 30 s per stage and 60 s in the boss, back to 65 % or lower within 120 s; T3 (crew 3) each heavy shell built in 18-35 s and at least 6 s at boiler grade 0 for the rider who latched it; T4 (crew 1) the Bulwark on Drive for 60 % of each Advance; T6 a light and a medium in each Advance (and crew 1's "Surge to ram" prompt), a heavy duel of 90-180 s in gun lines 2 and 3 |
| S2 zero riders | crew 3 at 0 W: the host's shared pause holds the depot (no kill, grade D); crew 3 spinning at 10 W and 25 rpm overruns every stage (withdrawn, grade D); crew 1 pauses in the depot |
| S3 compliance 100 / 85 / 70 % | T5: the mean score falls strictly |
| S4 every content and crew | every directive, plan and trace rule of BRIEF 4.5 and 4.6: patterns, applied values never above what was asked, warm-up limits, switch spacing, laps |
| S5 30 rpm collapse in a dynamo stage and in a 90 % gun line | rescue, stagger, the plan continues |
| S6 haptics off for one slot | no haptic applied to that rider |
| S7 same seed twice | identical events and snapshot hashes |
| S8 stress (`sim/test_tank_s8.gd`) | counts x 3: at most 16 enemies, snapshots under 4 KB |
| S9 a scripted sprinter (crew 1) | a Ram in every Advance, the ram haptic accepted, a gun line entered after a sprint at or below its target |
| S10 crew 3 on the network path | every rider a scripted sprinter: the clients' Rams arrive as telemetry intents and only count on the diesel; slot 1 stops dead for 60 s in a dynamo gun line: rescue, AFK within 10 s, a station on reserve, back, nobody else affected |

Gates: the Tank GUT suite, `check_scripts`, gdformat and gdlint, `tests/sdk/test_conformance.gd` (Autopilot humans at 1 and 3 riders), the matrix with `fit_check`, `node tools/e2e/run.mjs --games=tank`, and the full `tools/run_tests` at or above the green-count floor.

## Art

No generated art ships: every one of the 61 sprite ids is a procedural placeholder drawn at runtime by `view/placeholder_art.gd` in the 32 palette colours (no PNG is written; `assets/tank/sprites/` does not exist), and the view works with placeholders for every id. `assets/tank/art.json` is ready for a real pass (a dry run estimates about $4.27 for the 61 sunburst requests; the budget is $15). To regenerate with fal, a human sets `FAL_KEY` and `WATTLANDS_ALLOW_ART=1` in the shell for these commands only (never print or commit the key, and never export them for the test commands):

```bash
. tools/env.sh                      # keeps both locks on; generate.mjs does not read the network lock
node tools/art/generate.mjs --game=tank --dry-run
# 1. Style check on flare: set "endpoint" in assets/tank/art.json to openai/gpt-image-2.5/flare/text-to-image
node tools/art/generate.mjs --game=tank --only=hull_citadel,room_diesel,diesel_block,enemy_medium,bg_village_near,explosion_large --budget=1
tools/godot.sh --headless --path . -s tools/art/pixelate.gd -- --game=tank --only=hull_citadel,room_diesel,diesel_block,enemy_medium,bg_village_near,explosion_large
# Look at assets/tank/sprites/*.png at 3x, fix prompts and palette, set "endpoint" back to the sunburst endpoint.
# 2. The full pass, then pixelate everything and import
node tools/art/generate.mjs --game=tank --budget=<15 - spent>
tools/godot.sh --headless --path . -s tools/art/pixelate.gd -- --game=tank
tools/godot.sh --headless --path . --import
```

Then look at every sprite (reroll failures with a changed prompt, at most twice), re-measure the anchors in `assets/tank/rigs.json` (the gameplay keys keep their names and frames; `muzzle == trunnion + [barrel_px, 0]` is tested), add `"picker_image": "res://assets/tank/sprites/picker_card.png"` to `game.json` once that PNG exists, optionally add the 14 x 14 engine icons `assets/tank/icons/engine_{diesel,dynamo,steam,bulwark}.png` (the teammate strip shows the engine name until they exist), and credit OpenAI's GPT Image 2.5 through fal with the spend from `assets/tank/art_manifest.json` in `docs/credits.d/tank.md`. A generated `explosion_large`, `explosion_small` or `muzzle_flash` replaces its procedural stand-in automatically (`TankSprites.has_real`); re-tune the haze and light values after the art pass (`docs/decisions/tank.md`, "G1 view").

## Files

| Path | What |
| --- | --- |
| `game.json` | The manifest: two contents, the `rotation` option, `first_run_priority` -1, no bots |
| `tank_game.gd` | `TankGame` (GameModule): intents, the host loop, bands and `end_phase` through the director, events, prompts, HUD feeds, snapshot, results, `apply_progress` |
| `contracts/` | Ids, constants, the state records, the intent / event / snapshot schemas, the content schemas, `TankGeometry`, `TankTerrain` (see `contracts/README.md`) |
| `effort/` | `TankPlanBuilder` (plans, rotation) and `TankDirector` (every directive, bands, haptics, `end_phase`; the only code that touches `ctx.directives`) |
| `rules/` | `TankRules.step` and its parts: segments, stations, drive and Ram, hull, score, host-only bookkeeping (`TankAux`) |
| `combat/` | Ballistics, aim, targets, shells, damage, enemies, encounters, the Behemoth |
| `content/` | `TankContent`, the validated loader |
| `autopilot/`, `net/` | `TankAutopilot`; `TankSnapshot`, `TankCues`, `TankEventCast` |
| `view/` | `TankView` and the diorama: backdrop planes with blur and haze, rigs, cutaway rooms, lights, particles, interpolation, placeholder art |
| `hud/` | `TankHud` (the `HudSpec` rects), the station card, the objective line, the boss bars |
| `audio/` | `TankAudio`, synthesized with `Sfx.synth` |

## Known gaps and P2 notes

- Not tested on a real trainer: `HARDWARE_TEST.md` is the checklist, and its last section lists every item the automated runs could not judge (real sprint gestures, the mix, frame pacing on integrated graphics, network loss). Nothing has met a real Strava upload either.
- The art is placeholders and the sound is synthesized; the look and the mix have been reviewed from screenshots and headless logs only.
- P1 is not built: the garage between missions (scrap buys +10 HP armour x3, +20 bank units, -10 % boiler energy, and the hull finish picker, so unlocked finishes cannot be equipped yet), Viaduct Crossing (a river viaduct with an armoured train as the gun line), and two tanks in one lobby (up to 6 riders, the second on a rear ground line 40 px higher, enemy scales summed).
- P2 ideas: tank duels across a ruined town square (a stand-off stage where heavies trade shells across rubble with dug-in guns behind cover); the cool-down gate roll-through (today the cool-down swaps the town backdrop in, or the field road if the Behemoth withdrew, and the tank keeps rolling; the broken Foundry Gate and a scripted camera move through it are not drawn); hull finishes drawn on the tank (today an unlock is a progress entry only); the garage.
- Balance was tuned on the simulation matrix with compliant synthetic riders. Real riders' compliance, sprint timing and the Ram and dodge windows (a dodge sprint must start within about 1.25 s of the 6 s telegraph) may want a retune once someone has ridden it.
