# Torque Company (`tank`)

One to four riders crew a pedal-powered landship through a starry forest night, one seat each of six. The enemy stands far off, so the screen splits: our tank and the near road on one side, a long-lens view of the enemy on the other, and a small screen in the far panel shows the shells in flight. Bots fill the empty seats.

Version 0.7.0, 1 to 4 riders, bots, presentation `2d` at 960 x 540 art px (`pixel_flex` down to 852 x 480). Brief: `docs/games/tank.md`. Decisions: `docs/decisions/tank.md`. Contracts and the per-tick data flow: `contracts/README.md`. Real-trainer checklist: `HARDWARE_TEST.md`. Credits: `docs/credits.d/tank.md`.

## Contents

| Content | Plan | Default difficulty | FIT laps |
| --- | --- | --- | --- |
| `ashfall_road` (default, zero-input) | hangar 180 s, roll-out 120 s, 3 x (Advance 90-300 s, holding action 60-180 s, checkpoint 60 s), Behemoth 120-360 s, cool-down 180 s. 30 min nominal, 41 min at most | Normal | 13 |
| `ambush_15` (featured) | hangar 180 s, roll-out 120 s, Advance 80-160 s, holding action 60-120 s, checkpoint 60 s, Behemoth 100-190 s, cool-down 180 s. 15 min nominal, 13-17 min | Hard | 7 |
| `roam_10`, `roam_20`, `roam_30` (featured), `roam_45`, `roam_60` | drive-out 300 s, one open roam phase (`min_s` minutes x 60 - 300, `max_s` + 300), cool-down 180 s | Normal | 3 |
| `drill` (e2e) | hangar 30 s, skirmish 70 s (both WARMUP), checkpoint 30 s, cool-down 180 s. No haptics, at most one mode switch per rider | Easy | 4 |

Every phase is a FIT lap, so a ride reads Hangar, Roll-out, Stage 1: Advance and so on. Advances, holding actions and the boss are open-ended: once the objective is done and `min_s` has passed ("Regroup" until then) the director ends the phase for every rider in one step; the platform cuts it at `max_s`, which is an overrun and costs score (an Advance tows the tank to the halt line, a holding force is barraged, the Behemoth withdraws). The ride itself never fails.

## Seats

| Seat | Machine (`engine`) | Trainer | What it does |
| --- | --- | --- | --- |
| Drive | diesel | SIM on the terrain | Moves the tank. At a holding action it digs the berm in SIM flat, which absorbs hits. Empty: the tank stops |
| Gun | dynamo | ERG, the capacitor bank | Lays, chambers and fires the main gun. The bank pays for stabilizing and elevation, and the ERG target climbs as it drains |
| Loader | steam | SIM flat + boiler grade | Builds shells into a ready rack of 3, at full speed in the band and at a fifth of your power below it. Surge in the 5 s window after a stow overpressures the shell for double damage |
| Lights | arc | ERG, the searchlight load | In band the searchlights are lit: the gun reaches its full range at normal dispersion. Dark: shorter reach, wider dispersion |
| Secondaries | feed | SIM flat | Two bow machine guns, exactly 6 rounds per pedal revolution (540 a minute at 90 rpm), 0.375 damage a round, at near threats and barricades, which are scaled to this rate: at 90 rpm a recon (22.5 HP) takes about 6.7 s, a tankette (13.5 HP) and a barricade (36 rounds) 4 s. In-band power speeds their slew |
| Repairs | repair | ERG, the repair load | Rebuilds the hull per joule in band, only below its maximum. A crank-driven rivet hammer strikes once per revolution and a press closes on each patch. Upper deck |

An empty seat does nothing. A crew of n starts on Drive, Gun, Loader, Lights (the first n); a solo rider is seated by the solo loop.

**Moving seats.** The `seat` intent (the HUD's picker: < > on every seat, OK sits, back closes) moves a rider to any empty seat at once, or to a bot's seat, which the bot gives up. Refused only for a seat a human holds, on reserve and in the cool-down. The stations, the `seat` event, the HUD and the power follow in the same tick. The trainer follows the seat (`TankSeatPlan.follow`, the director's pattern 9): a same-mode move splits the phase at once; an ERG <-> SIM move splits when the rider's last switch is 30 s old (`TankConst.SWITCH_GAP_S`, BRIEF 4.5), or at the segment's end when the split's rest could not hold 30 s. Moving back cancels a waiting switch. Meanwhile the rider works the new seat from its own power and the card says "ERG in 12 s" or "ERG at stage end". Every split and replan passes the PlanValidator with no switch warning.

**The hangar and the roll-out.** A ride opens in the hangar: the hull sits on a mechanic's stand under white ceiling bars, its tracks spinning in the air as the Drive seat pedals, and every seat works. The drive, aim and fire drills run here (drive 0-60 s, aim 60-120 s, fire 120-170 s). The last 10 s are a countdown: the bars go dark, two red beacons turn, a soft klaxon sounds, the hull comes down off the stand and the door opens. The roll-out is the 120 s out of the door and never stops. Both are warm-up, at 65 % of FTP or less.

**Controls.** Gun: up / down lay the gun, swap (R / LB) cycles targets, OK fires. Loader: OK stows a light shell from 40 %, ability 1 or a surge overpressures. Drive in free roam: ability 1 (or OK) turns the tank. A human who sends nothing plays on the Autopilot: aim, fire, latch and seats run by themselves. It never sprints, so it never evades or overpressures, and it never changes effort.

## The field

Two frames, with no conversion in the rules. A far enemy has no px and a near one has no metres.

| Thing | Frame | Unit |
| --- | --- | --- |
| Hull, barricades, drill wrecks, tank traps, recon cars, tankettes, bow guns | near | rules px (8 per game metre), `x_px` |
| Light, medium, destroyer, heavy, Behemoth | far | `range_m` from the hull's front |
| Far shells | far | `x` range in m, `y` height in m |
| Near threats' rounds, the main gun at a barricade or drill wreck | near | px |

Far enemies do not move with the road: they pace the tank, so Advance lengths and terrain stand alone. Nothing spawns or moves behind the tank, and there are no stationary guns.

| Enemy | Behaviour |
| --- | --- |
| Light tank | Far. Nearest of the far kinds; weaves around its hold, its first shot there is a telegraphed flank shot, retires after a while with no credit |
| Medium tank | Far. Holds and shifts on a timer |
| Tank destroyer | Far. Farthest, a casemate; telegraphs each shot and shifts after it |
| Heavy tank | Far. Telegraphs, shifts on a timer, backs off in steps as it takes damage |
| Behemoth (boss) | Far. Three bogies, then the turret; creeps in, each broken bogie pushes it back; main gun telegraphed |
| Recon car, tankette | Near. Burst from the roadside bushes, dash away with pauses, firing back over the turret while paused, then flee. Only the Secondaries hit them. Got away: no reward, no penalty |

Far enemies enter in 10 s from just past their hold, fading out of the haze. A holding action is a force of far kinds on the move at long range, retiring and shifting; the internal ids `gun_line`, `SEG_GUN_LINE` and `TankGunLineState` stay for the wire, the plans and the FIT, and the UI says "Holding action". Its objective is every enemy of the force down; near lists run alongside by elapsed time. An Advance's objective is the halt line.

**Main gun.** Far shells fly at 560 m/s under 70 m/s2 (real speed, gravity x 7, so the barrel visibly lays 5-16 degrees): 800 m takes 1.43 s, 2200 m 4.06 s. `TankBallistics.far_lead` solves lead from the target's range rate. Auto-aim picks by priority and fires on target (`TankAim.pick`, never a near threat). Dispersion widens on a low bank and by 1.5 times in the dark, and the shell lands where the error sends it: a direct hit inside the target's `hit_half_m`, else splash within `splash_m`, else a `splash` event. Near arcs stay for barricades and drill wrecks.

**Surge to evade.** Telegraphed far shots can be made to miss. A rider who can evade (a SIM WORK phase of their own plan, past its first 300 s) holds the sprint rule (the last 3 s average at least 1.2 x FTP) for 2 s, 3 s against the Behemoth, between the telegraph's start and the landing. There is no button. The shot is decided at landing, so a dead shooter's shell still resolves. Telegraph plus minimum flight is at least 6 s at Hard (`test_tank_ballistics`, schema check on hold ranges).

**The shell's path.** Ours leaves the near panel as a tracer, flies on the shell screen and drops into the far panel. Theirs leaves the far panel, flies on the shell screen and comes in on the near panel: that is the telegraph to read.

## Difficulty

Lobby option `difficulty`, set by the host: `auto` (the mission's `difficulty_default`), `easy`, `normal`, `hard`. It multiplies enemy HP, damage, accuracy, counts, telegraph length and the repair rate (`enemies.json difficulty`), and sets `tank_loss`. **It never touches an effort number, a plan or a governor input.** The schema refuses any other key in a difficulty row, a static test finds no difficulty read under `effort/`, and `TankPlanBuilder.build_all` is identical for all three in every content. The live patterns read the fight as always, so a longer fight on Hard keeps a target higher inside the same fixed `range_pct`.

| | Easy | Normal | Hard |
| --- | --- | --- | --- |
| Hull at 0 | breakdown | TANK LOST | TANK LOST |
| Target, compliant crew | wins, no losses | usually wins, 0-1 losses | 1-2 losses on most seeds |
| Target, crew at 85 % | wins or withdraws, no losses | more losses than compliant | more losses than compliant |
| Target grades | A or S | B or A; S with no losses | C to A; never S with a loss |

The targets are what the sim matrix checks (S14-S17 and `TankBalanceTargets`). Measured with the Autopilot (compliant, which never sprints, so it never evades), seeds 1-6, Easy seeds 1-3:

| Compliant crew | Easy | Normal | Hard |
| --- | --- | --- | --- |
| `ashfall_road`, crews 1-4 | 12 of 12 won, no losses, A or S | 24 of 24 won, no losses, A or S | 17 of 24 won, 1-3 losses (one run in 24 has 3), C to A |
| `ambush_15`, crews 1, 3, 4 | not in the matrix | 17 of 18 won, no losses, B to S | **1 of 18 won**, 1-3 losses, D to B |

`ambush_15` starts short of plates (`hull_hp` 90, `checkpoint_hp` 20, against the tank's 150 and 30), on every difficulty.

Open shortfalls against the targets, none of them touching effort, plans or safety:

- **T1 was widened for crew 2.** On `ashfall_road` a crew of two may hold a gun line up to 180 s, the brief's own 90% gun-line limit, against 160 s for every other crew. Its holds reach 175 s (seed 3, stage 2) and 168 s (seed 4, stage 3), neither at its 180 s `max_s`: one rider shuttles between Gun and Loader while the other repairs, and every tuning step that fixed one seed moved the miss to another seed or took crew 2's Hard losses under target. The ruling is in `docs/decisions/tank.md`.
- **Hard `ambush_15` is all but unwinnable for the Autopilot.** The target asks for 1-2 losses, which holds, but a compliant crew killed the Behemoth in 1 run of 18 (crew 4, seed 3) and 8 of them graded D, under the C the target table asks for. Bots did better: 1 human + 3 bots and 2 + 2 win 3 of 8 runs (seeds 1-4), so Hard is easier with bots filling the seats than with a full Autopilot crew. Whether a human who evades can win is not known until someone rides it.
- Normal cost no compliant crew a tank at all, the low end of its 0-1 target.

**TANK LOST.** The crew is towed back (`hull.tow_s`: no movement, no fire, nothing spawns, a flat grade for Drive), then the stage restarts from its start with its enemies back and part of the hull (`restart_hp_frac`). Rules only: same plan phase, same clock, no directive, no replan, no lap. Riders keep pedalling and the HUD says KEEP RIDING. `max_s` still cuts the phase, so a failed stage may be skipped when its time runs out. Each loss costs survival score and caps the grade at A. In free roam the field clears and the tank drives on, at the breakdown's points. A rider in rescue, AFK or dropped holds the hull at 1 HP on every difficulty (`TankHullRules.protected`, BRIEF 4.6.3), as do a won stage and every phase but WORK.

**Breakdown (Easy).** No movement or fire, damage ignored, until the mean P_eff of the manned seats has paid `hull.repair_j`; then it runs on `hull.repair_hp`.

## Bots and automatic seating

`TankBots` seats bots around the humans; a bot reads their seats and how they are doing. It never holds a seat against a human and never causes an effort change for one: it acts on its own seat, on cover and on being evicted, and its trainer follows through the same `TankSeatPlan.follow`. Enemy counts scale with the crew, bots included.

| Situation | A bot goes to |
| --- | --- |
| Rack at 1 or less, human on the Gun, no human loading | Loader |
| Hull below 60 %, more urgently below 35 % | Repairs |
| Human on the Gun in band, a far target, no human on the Lights | Lights |
| A near threat alive, no human on the Secondaries | Secondaries |
| Human in rescue, or out of band 15 s on the Gun | Loader if the rack has room, else Lights |
| Human out of band 15 s on the Loader | Repairs, more urgently |
| Human on reserve 10 s on Drive, Gun or Loader (WORK only) | Swaps seats to cover (`aux.cover`) and gives the seat back the tick the human returns. The human's plan is untouched |

A bot stays 30 s on a seat, moves only to an empty seat and, in a fight, only when its trainer follows at once.

**Automatic seating** (`TankAutopilot.seat_intent`) covers Autopilot riders and humans who never sent a deliberate intent. At most once a second, never inside the minimum stay (30 s solo, 60 s in a crew), in a fight only for a move its trainer follows at once, never an ERG <-> SIM move inside a warm-up. A crew's riders hold the most needed seats (`seat_needs`) and hold them through a segment's opening, unless a near threat is alive or an Advance has nobody on Drive. The solo loop: Drive while nothing is in reach; the Loader until the rack is full or straight to the Gun with 2 shells; the Gun while it has shells and a target; Repairs with the hull below 35 % and nothing laid; the Secondaries only with no round for the main gun. It leaves Drive for one stay per Advance. A solo rider meets what `min_crew` leaves (none of the missions' near threats or barricades), a Behemoth with its bogies wrecked, `crew_damage_scale` of the damage and a restocked rack at each checkpoint.

## Hull and score

Hull HP rises and heals at each checkpoint (`hull.checkpoint_hp`). The berm absorbs first. Score = 1000 x (0.3 band + 0.2 accuracy + 0.3 objectives + 0.2 survival), weights and cut-offs in `scoring.json`; survival falls with breakdowns and losses. Grades S >= 900, A >= 800, B >= 650, C >= 500, else D. XP = kJ / 10 plus a grade bonus. Hull finishes unlock into `ctx.progress`; the Behemoth's needs no breakdown and no loss. Free roam scores points per WORK minute instead.

## Effort

Every load change goes through `ctx.directives`, sent only by `TankDirector`; the governor clamps everything (BRIEF 4.6) and ramps every ERG / SIM switch (BRIEF 4.5). Grades are before the rider's difficulty setting. Targets are % FTP.

| Seat | Hangar and roll-out (WARMUP) | Advance | Holding action | Boss | Checkpoint | Roam |
| --- | --- | --- | --- | --- | --- | --- |
| Drive | SIM flat in the hangar, SIM terrain 0..+2 on the roll-out | SIM terrain -3..+6 | SIM flat (dig) | SIM flat | ERG 50 | SIM valley grade -3..+5 |
| Gun | ERG 50 -> 59 -> 65 (one ramp) | ERG 55, bank [55, 100] | same | same | ERG 50 | bank [55, 85] |
| Loader | SIM flat, boiler 3 x p | SIM flat, boiler 8 x min(p, 1) | same | same | ERG 50 | same |
| Lights | ERG 50 -> 59 -> 65 | ERG 65, [65, 80] | same | same | ERG 50 | same |
| Secondaries | SIM flat | SIM flat | SIM flat | SIM flat | ERG 50 | SIM flat |
| Repairs | ERG 50 -> 59 -> 65 | ERG 55, [55, 70] | same | same | ERG 50 | same |

The drill's skirmish keeps ERG seats in [55, 65]. The cool-down is the platform's ERG 50; Tank sends nothing. Every roam phase is over 300 s, so BRIEF 4.6.1's 105 % cap applies; no bound Tank sets there is above 85 %.

| # | Pattern | Rule |
| --- | --- | --- |
| 1 | Bank (Gun) | Target 55 + 45 x (1 - bank/100), clamped to `range_pct` |
| 2 | Arc (Lights) | 65 + 15 x duty, the share of the last 10 s an enemy stood in range |
| 10 | Repair (Repairs) | 55 + 15 x duty, the share of the last 10 s the hull was below its maximum |
| 1, 2, 10 | Their schedule | Every 5 s, at most 10 points, as three sub-steps 1 s apart (at most 3.3 % FTP/s); never in the hangar, the roll-out or checkpoints |
| 3 | Boiler (Loader) | SIM `mode_grade` 8 % x min(pressure, 1) (3 % in WARMUP), at most once a second, rises at most 0.5 % a step, drops at once at a stow; 0 with the rack full |
| 5 | Terrain | `course_grade` at 2 Hz in `grade_source: game` phases; 0 under a tow |
| 6 | Bands | `cadence_band(60, 120)`, (50, 120) while the Loader idles; `power_band` 76-105 % for Drive and the Secondaries in WORK SIM |
| 7 | Haptics | A hit (`haptics.hit.min_damage`, read before the difficulty) +2.0 % for 1.5 s, a Behemoth main-gun hit +3.0 % for 2 s, to riders in SIM; never in WARMUP, the first 300 s, the cool-down, ERG or opted out; 15 s apart |
| 8 | `end_phase` | Objective done, `min_s` passed, every rider past its own phase's `min_s` |
| 9 | The trainer follows the seat | See "Moving seats" |

Evade and Overpressure sprints send nothing: the rider sprints inside the phase's own SIM. In band: SIM seats 76-105 % FTP, the Loader 90 % while building, ERG seats 95 % of the target at cadence 60. Reserve: a rider who stops pedalling gets the floor after 3 s and is AFK at 10 s (a dropped peer at once); the seat runs as if 60 W, never in band, and keeps its plan. All riders stopped: the host pauses the game. A cadence collapse at an applied ERG target of 60 % or more arms the platform's rescue (target 50 %): the machine stalls, the plan continues.

## Free roam

`TankContent.expand_roam` turns `{id, kind: "roam", label, minutes}` into a WARMUP drive-out and one open WORK phase. The valley (`content/tank/roam/valley.json`, `TankRoamMap`, a seed from `ctx.rng` carried in the snapshot) is about 6 km: pine forest at both ends with a turning place, and the lake shore, the village, the quarry and the meadow once each in a seeded order, each with its own terrain.

The rules work in the travel frame: `TankRoamState.map_m` is the hull's place on the road and `TankHullState.dir` which way +x points. A turn (the driver's `turn` intent, 30 s cooldown, or the Autopilot 3 s after a road's end) is an 8 s stop; at its midpoint `TankRoam.flip` mirrors the obstacles and clears everything that moves with no credit, so nothing is ever behind the tank. Driving west the near stage draws mirrored and the far panel lands on the left.

Patrols come every 90-110 s of WORK time, drawn by weight: far kinds in the far panel, near kinds from the bushes, scaled by crew and `difficulty.count`, trimmed to `max_alive`. Strongpoints are holding forces of one heavy at seeded spots, on the field once within `spawn_m` ahead, back after `respawn_s`. The tank halts ("Engage") while one stands or a heavy holds within `engage_heavy_m`. Time up at `min_s`: no new patrol, a fight in progress may finish (OVERTIME), then the director ends the phase for every rider in one step and the module finishes `time_up`. Points per kill and kilometre, minus a breakdown or a loss; grade by points per WORK minute. HUD: the map strip and the board replace the mission plate.

## The look

**Art.** Everything is baked by scripts in this repository, and the game makes no fal call. The tank and its forest are `assets/tank/v3/` (`kit.json`, read by `TankRig`), rebuilt as pixel art from Simon's reference image (`docs/credits.d/tank.md`). The enemies, bushes and far ground are `assets/tank/v4/` (`enemies.json`, read by `TankEnemyKit`), baked by `assets/tank/v4/tools_src/enemy_bake.sh`.

**The Foundry Pact.** The enemy is the same hand as our tank on the opposite side: the same 1 px outline, plate-edge rule (top and left lit, far side dark) and rivet pixel, but ours is patched and open and theirs is sealed factory slab. `enemy_paint.gd` paints each layout straight onto the palette, so a plate keeps its ramp: field grey with 1-3 hard stepped bands of dark yellow (the destroyer the other way round), grime streaks, a mud line, chips on lit edges, the moon on open top edges. Flat decks, straight facets, welded seams (a dashed bead, 2 on, 1 off), rivets only on skirts, hatches, mantlets and access plates, stowage (bins, jerrycans, links, tools, tow cable), no windows and long guns. Hatches are shut doors: warmth lives in vents, the exhaust and the Behemoth's furnace, so nothing mimics our lit rooms. Slits are the cold foe signal: each sits in a recess in its plate under a 1 px dark lid. A turret and its gun ride level on a hull tilted by the ground, so its stencil keeps its rows. The mark is the Pact's own: a hollow bone diamond on a dark plate, its centre always the plate. Numbers use only 0, 1 and 8, because a turret's traverse and a flip mirror them, and none may read as 18, 81, 88 or 101 in either direction: the first three are far-right number codes, and 101 was a real SS heavy tank battalion's number. `tests/games/tank/art/test_tank_v4_pact.gd` holds the numbers.

**The hangar** (`TankHangar`; art in `assets/tank/hangar/`, baked by `tools_src/hangar_bake.sh`): the near panel shows a steel hangar side on, with the stand, the ceiling bars, the beacons and an end wall with its door; the far panel shows the gate wall face on with a rolling shutter. The roll-out slides both away. The stand lifts the hull by `TankHangar.STAND_LIFT` px and the floor is flat.

**Split screen** (`TankFarMap`, on every canvas): near panel, an 8 px riveted seam with the range plate (`TankSeam`), far panel (`TankFarPanel`, a SubViewport that never runs the depth of field, with its own parallax, light and haze), and the shell screen (`TankPip`) in the far panel's top. 960 x 540: 622 + 8 + 330. The tank's scale and place are unchanged and it stays whole.

**Live parts.** Tank: track links and road wheels on per-wheel suspension (`TankSuspension`, `TankGround`), the whole tank rotated as one sprite in a SubViewport (`TankBody`), gun recoil, bow guns, and each seat's lit room with its machine and rider turning on that rider's cadence (`TankInterior`), the turret's rack and breech windows. Enemies (`TankEnemyDraw`): shoes and road wheels on the same suspension, turret traverse, gun elevation and recoil, slit glows, burning wrecks, the Behemoth's bogies. Every view reads the state only; positions come from a snapshot history (`TankSnapHistory`, `SnapRenderClock`), so a client interpolates. Effects are pooled and seeded (`TankFx`). The depth of field (`TankDof`, the rider's `miniature` option) covers the near panel only and switches itself off after 5 s of slow frames.

**HUD** (`hud/`, `TankHud.spec()`: the game's own Controls and pixel fonts, `shows_power = true`). Mission plate top left with a difficulty tag and losses; hull plate top right, the Behemoth's bars under it; my numbers bottom left with one instruction line; six machine cards bottom middle (`TankHudSeats`, with ERG / SIM tags, BOT, rack pips, rounds a minute, Repairs' rate); TANK LOST above the banners; world tags (speed, the halt post, SURGE TO EVADE with pips, the elevation arc). F1 help: eight entries, nine in free roam. Nothing covers the bottom-right 200 x 60.

## Content files and knobs

Every file is JSON, validated at load by `TankContentSchema`, which also holds each effort number to BRIEF 4.6 (a bad value is a load error). Each file's `_doc` explains its keys. Change a number, re-run the matrix, keep the checks green. Enemy numbers are tuned against the targets under "Difficulty"; read the current values in the files.

| Knob | File and key |
| --- | --- |
| Difficulty table | `enemies.json` `difficulty` |
| Enemy HP, guns, holds, telegraphs | `enemies.json` `types.<kind>`, `boss` |
| Near threats' motion | `enemies.json` `types.{recon,tankette}` |
| Crew scaling | `enemies.json` `crew_count_scale`, `crew_damage_scale`, `boss.bogies_by_crew`; mission entries' `min_crew` |
| Hull, tow, restart | `tanks.json` `hull` |
| Main gun | `tanks.json` `gun`, `gun.far`, `damage` |
| Bank, rack, Lights | `tanks.json` `dynamo`, `steam`, `arc` |
| Secondaries | `tanks.json` `bow` (the rate: `TankFeedState.ROUNDS_PER_REV`) |
| Repairs | `tanks.json` `repair`; `stations.json` `repair` |
| Surge to evade | `tanks.json` `evade` |
| Plans and patterns | `stations.json` `plans`, `drill_plans`, `roam_plans`, `bank`, `arc`, `boiler`, `terrain`, `haptics` (schema-bounded) |
| Missions | `missions/<id>.json` `segments[]`: `encounters` (`at_m`), `enemies` (`hold_m`), `near` (`at_s`), `difficulty_default`, `score_stages`, `hull_hp`, `checkpoint_hp` |
| Valley | `content/tank/roam/valley.json` `patrols`, `strongpoints`, `turn`, `points`, `grades` |
| Score | `scoring.json` |
| Strings | `strings.csv`, keys `TANK_*` (commit the generated `strings.en.translation`) |

## Tests and commands

```bash
. tools/env.sh
# Tank GUT suite: unit, static, view and HUD from fixtures, balance harness, stress, rules-step perf
tools/run_tests --only=gut --gdir=res://tests/games/tank
tools/godot.sh --headless --path . -s tools/check_scripts.gd
# Node tests: the sim checker and the e2e report checker
(cd tests/games/tank && node --test)
# Lint and format check
tools/run_tests --only=static
# Simulation matrix, then check_sims.mjs with fit_check on every FIT
bash tests/games/tank/sim/run_sims.sh          # or: run_sims.sh s15 s16   (TANK_SEEDS="1" for one seed)
node tests/games/tank/sim/check_sims.mjs build/tank/sims --fit
# One run by hand
tools/run_game_sim --game=tank --content=ambush_15 --players=3 --bots=0 --rider=erg:compliance=1.0 --seed=1 --options='{"difficulty":"hard"}' --report=build/tank/r.json
# Fast balance table through the rules, no trainer stack
tools/godot.sh --lease=1 --timeout=900 --headless --path . -s tests/games/tank/sim/tank_balance_tool.gd -- --crews=1,2,3,4 --seeds=1,2,3 --compliance=1.0 --difficulties=easy,normal,hard --content=ambush_15
# The e2e (host plus two clients, drill) holds three Godot slots
node tools/e2e/run.mjs --games=tank
# Play it (the wrapper stops after 20 minutes without --timeout)
tools/godot.sh --timeout=7200 --path . -- --mock-trainer=erg
# Every v4 fixture at both canvases, windowed, to build/tank/v4_frames/
bash tests/games/tank/view/render_v4.sh
# Enemy art: rebake, then the critic's sheets in build/tank/v4_art/
bash assets/tank/v4/tools_src/enemy_bake.sh
```

| Run | What it asserts |
| --- | --- |
| S1 compliant, crews 1-4, seeds 1-3 | T1 phase times, grade, losses; T2 the bank's climb (crews 2-4); T3 shells per stage (crews 3-4); T4 the solo loop; T6 telegraphs and duels; T7 the Lights' load (crew 4); T8 near threats (crews 2-4); T9 no fire in checkpoints, every loss in WORK and followed by a restart |
| S2 zero riders | The shared pause; a 10 W crew overruns every stage |
| S3 compliance 100 / 85 / 70 % | T5: the mean score falls strictly |
| S4 every content and crew | **Every directive, plan and trace rule of BRIEF 4.5 and 4.6.** Reads S14-S18 too. Append-only |
| S5, S10 | Rescue and AFK: stagger, the plan continues, a client's intents, no tank lost inside a rescue or AFK span |
| S6, S7 | Haptics off; the same seed twice is identical |
| S8 (`tests/games/tank/sim/test_tank_s8.gd`) | Counts x 3: at most 16 enemies, snapshots under 4 KB |
| S9 | A scripted sprinter evades; a holding action entered after a sprint |
| S11, S12 | Free roam: time up, laps, nothing behind, the grade; the zero crew |
| S13 | Seat switching: every move's trainer follows within 30 s, nothing refused |
| S14 Easy, S15 Hard, S16 `ambush_15`, S17 crew 3 at 85 % and 70 % on Hard | The difficulty targets, phases, laps, S4; no loss in a rescue span |
| S18 bots, 1 + 3 and 2 + 2 | Complete, nothing refused, bots act only through their seats, never onto a human's |

Gates: the Tank GUT suite, `check_scripts`, gdformat and gdlint, `tests/sdk/test_conformance.gd` (with bots), the matrix with `fit_check`, `node tools/e2e/run.mjs --games=tank`, and the full `tools/run_tests` at or above the green-count floor.

## Files

| Path | What |
| --- | --- |
| `game.json` | The manifest: contents, cards, the `difficulty` option, `bots`, the `miniature` player option |
| `tank_game.gd` | `TankGame` (GameModule): intents, the host loop, events, prompts, HUD feeds, snapshot, results, `apply_progress` |
| `contracts/` | Ids, constants, state records, intent / event / snapshot schemas (snapshot v5), content schemas, `TankFarMap`, `TankDifficulty`, `TankGeometry`, `TankTerrain` |
| `effort/` | `TankPlanBuilder`, `TankSeatPlan`, `TankDirector` (the only code that touches `ctx.directives`). Reads no difficulty |
| `rules/` | `TankRules.step` and its parts: segments, stations, drive, hull, seats, score, free roam, `TankAux` |
| `combat/` | Ballistics, aim, targets, shells, damage, enemies with `TankFar` and `TankNear`, encounters and the tank loss's restart, the Behemoth, `TankEvade`, `TankBow` |
| `content/` | `TankContent`, the validated loader |
| `autopilot/` | `TankAutopilot`, `TankBots` |
| `net/` | `TankSnapshot`, `TankCues`, `TankEventCast` |
| `view/` | `TankView`, on a ladder of five layer classes, each extending the one before and calling only down: `TankViewBase` (constants, per-frame vars, the rules-to-art mapping), `TankViewMotion`, `TankViewSeats`, `TankViewWorld`, `TankViewHud`. Near stage and tank (`TankRig`, `TankBody`, `TankInterior`, `TankMech` over one class per machine, `TankMechDiesel` to `TankMechRepair`), far panel, seam, shell screen, enemies, lights, effects, interpolation (`TankSnapHistory`, a `SnapHistory`, drawn at a `SnapRenderClock`) |
| `hud/` | `TankHud` and its Controls |
| `audio/` | `TankAudio` |

## Known gaps

- Automated runs use a mock trainer: `HARDWARE_TEST.md` is the checklist for a real one, and its last section lists what the automated runs cannot judge.
- Frames and the mix are judged from screenshots and logs only. The split-screen frame cost is measured against the old baseline (2026-10-31, quiet machine, `TANK_FIXTURE="kind=v4:cap_v4;flex;stats;novsync;seconds=20"` against the same with `kind=cap`): v4 mean 14.98 ms, p99 16.67 ms, 355 draw calls, 3 of 1202 frames over 16.7 ms; baseline mean 14.84 ms, p99 16.31 ms, 385 draw calls, 4 of 1202 over. The gate is relative: v4 costs 0.14 ms more, with fewer draw calls. The spec's absolute "under 8 ms, p99 under 14" was an estimate the baseline never met either.
- Balance is tuned on the simulation matrix with compliant synthetic riders. Real riders' compliance and sprint timing may want a retune. The open shortfalls are listed under "Difficulty".
- A Behemoth (300 px) cannot fit the 286 px far panel at 852 x 480: it is centred and clipped 7 px each side.
- Far wrecks dim and burn, and close in with the hull and drop out of the far panel, but they do not collapse into debris heaps.
- Hull finishes unlock but cannot be equipped or seen: the garage is not built.
- P1, not built: the garage (scrap upgrades, the finish picker), Viaduct Crossing, two tanks in one lobby. P2 ideas: tank duels across a ruined town square; the cool-down's roll through the broken Foundry Gate.

## Audio

Every sound is rendered from the recipes in this repository, `assets/tank/audio/audio.json`, by `tools/audio` (`docs/AUDIO_PIPELINE.md`). `TankAudio` only maps state to parameters and events to cues. `node tools/audio/preview.mjs --game=tank` writes `build/audio_preview/tank.mp3`.

- **Each seat, 1:1 with its crank.** `TankView.audio_feed` hands the adapter each seat's `machine_phase`, the number the machine is drawn from, so sound and picture cannot drift. The fractions come from the art and `tests/games/tank/audio/test_tank_audio_bank.gd` pins them to the machine files (`src/games/tank/view/tank_mech_diesel.gd` and its siblings, one per machine). FTMS reports cadence about once a second and no crank angle: the strokes lock to the crank on screen exactly and to the rider's feet in rate only. A seat that stops, stops dead; a reserve room is silent because its crank stands still. The diesel's cutaway on the tank and its machine card are one three-cylinder engine on the view's crank, with firing tops on the fire strokes and overlap tops on the inlet strokes, read from the bank by `tests/games/tank/view/test_tank_cutaway_sync.gd`.
- **Diesel (Drive):** three unequal cylinders of 6, 5 and 4 takes against pitch tables of 7, so the takes only line up again after 60 revolutions. They differ in length and colour and share a pitch range about 1.2 semitones wide, so a revolution plays no tune. Each firing is a dull thump with a body and each valve a dull knock of 4 takes, held to a big engine's shape by `tests/games/tank/audio/diesel_stroke.test.mjs`. A body whose two loops cross over at 50-75 rpm, a rasp that breathes at the firing rate and opens with load, a turbo whistle by watts with a blow-off when you lift, and a crackle on lift-off or well over band.
- **Dynamo (Gun):** a whine with a 27 Hz ripple locked to the armature whose lines swell each on their own rate, brush crackle and ticks that come forward while the jars stay empty, the jars' dump at 0.8 of a turn once they fill, the hoist's ratchet. **Steam (Loader):** two chuffs a revolution by pressure, valve, simmer, the pawl while the rack fills, the safety valve when over. **Arc (Lights):** warm and low, because a rider may hear it for an hour: a generator thrum that follows the cadence, a body that opens with power, a soft relay tock at 0 and 0.5 as the ladder's arc starts up (one per stroke, louder with reach), a second tock between them when over band, and a rare dull spark at high reach. Nothing it plays has much above 2 kHz; `tests/games/tank/audio/lights_band.test.mjs` holds its 2-8 kHz level, and `ear_band.mjs` beside it prints every seat's. **Feed (Secondaries):** a machine gun's rattle, six strokes a revolution and 1:1 with the crank (`bow_shot` is 70 ms in 11 takes, silent before the next stroke even at 120 rpm, and only while they fire), a bolt on every stroke, links, casings, the belt's rattle. With no target the bolts cycle dry twice a revolution, as drawn, with no casings. A mate hears two rounds a revolution as strokes and a quiet loop of far rounds under them, so a burst doesn't crowd out the rest of the crew's machines. **Repair:** the rivet hammer on each strike with its ring and sparks while the hull needs it, a compressor that eases down and a dry tap that follow your legs when it does not, the press when a patch is done.
- **Hangar:** the klaxon is the segment's own soft horn (`horn_segment`, nothing over 1 kHz of its filter) pitched up a fifth and 7 dB under the segment horn, three times in the countdown at 10, 6.6 and 3.3 s before the door, from the state's own time so a client hears it too. A rider who joins late misses the beats that are gone. The bank's WAV budget (7 MB) has no room for a file of its own.
- **Track:** links and a squeak locked to the distance drawn (`travel`), three links and one squeak per 2.4 m, and a rumble by speed. Under a tow they follow the reversed tread, over the chain.
- **Other riders' machines** play 10 dB under yours, without their small details, and their strokes keep a 60 ms gap across the crew (`other_min_gap_s`). Yours are never thinned. Someone who stops pedalling stays the lead; only a spectator lifts the room 4 dB.
- **The gun and the far fight:** a low thump, crack and tail, the shell's flight and the ejected casing that vary round by round, its clang, a reload that varies too. Far landings and kills are heard after the flash, at twice real sound speed (`range / 680` m/s, 0.6 to 3.5 s), and quieter with range. An enemy's far shot is a low thump after its range; the shell in the air is faint, comes close only in its last second and ends at impact. A round on a near threat pings at once, however it was fired.
- **Near threats:** you hear them before you look. A burst from the bushes that ducks the room, then a small high engine over the machines while it is close (a recon and a tankette each have their own), revving as it dashes and idling down when it stops to fire. Its gun is a sharp crack and its round rings on the plate, never a shell's impact. One that flees drives on past the panel's edge and fades over about 3 s; a kill ends it at once.
- **The night:** wind in the pines in two layers and a cricket chorus (lengths 5, 11 and 13 s, so 715 s before they meet), cricket trains, frogs, an owl, a creaking branch, and a far battle that stays out of the hangar, the roll-out, the cool-down and any moment an enemy stands in the far panel, so a far thump in a fight is always a shot at you.

Settings > Audio holds the levels: Machines (seats, track), Ambience (the night), Effects (guns and hits).
