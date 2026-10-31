# Diesel Domestiques (`tank`)

One to four riders crew a pedal-powered landship through a starry forest night, one seat each of five: Drive (the diesel), Gun (the dynamo), Loader (the steam engine), Lights (the arc generator) and Secondaries (the belt-fed bow guns). Riders move between the seats; a solo rider is seated automatically by the solo loop (v3, below). Presentation `2d` (the reference's night diorama at 960 x 540; the rules keep 640 x 360 units), version 0.3.1, 1 to 4 riders, no bots. Brief: `docs/games/tank.md`. Decisions: `docs/decisions/tank.md`. Contracts and the per-tick data flow: `contracts/README.md`. Real-trainer checklist: `HARDWARE_TEST.md`. Credits: `docs/credits.d/tank.md`.

Status: v3 (0.3.1). Every crew size, 1 to 4, plays Ashfall Road to the results with zero input and wins it on the simulation matrix with grade S. The tank is the reference landship rebuilt as pixel art (no generated sprites), the HUD is the game's own and the sound is rendered from recipes (see "Audio" below, `docs/credits.d/audio-tank.md`). Nothing has run on a real trainer (see "Known gaps and P2 notes").

## v3 rules and effort (2026-10-28)

v3 (brief "v3 (2026-10-28)") replaces the four tanks with one landship for every crew size and the engines with five seats; where this section and the v2 text below differ, this section wins (the v2 text still describes the drive, enemies, Surge to evade, the boss and free roam).

**Seats.** Drive (`diesel`, SIM terrain; moves the tank, digs the berm at a gun line), Gun (`dynamo`, ERG bank 55-100%; lays, chambers and fires the main gun), Loader (`steam`, SIM flat + boiler; fills the ready rack), Lights (`arc`, ERG 65-80%; the searchlights), Secondaries (`feed`, SIM flat; the two bow guns). A crew of n starts on Drive, Gun, Loader, Lights (the first n; stations.json `start_engines`). **An empty seat does nothing**: no drive (the tank stops), no laying, chambering or firing, no reloads, dark searchlights, silent bow guns. The repair after a breakdown is the crew's work: the mean P_eff of the manned seats.

**Moving seats** (0.3.1: no seat lock; `rules/tank_seats.gd`, `effort/tank_seat_plan.gd`, the director's pattern 9). The `seat` intent (a seat, or next / prev over the empty ones; the HUD's picker: < > on every seat, the Gun too, OK sits, back closes) moves the rider to any empty seat at once, in any segment, for every crew size: the stations, the `seat` event, the HUD and the power follow in the same tick (refused only for a manned seat, on reserve and in the cool-down). The trainer follows the seat (`TankSeatPlan.follow`): a move that keeps the mode (SIM -> SIM, ERG -> ERG) splits the rider's phase at once (the platform's `DirectiveSink.split`: the rest of the segment becomes a lap-false phase for the new seat, meta `offset_s`, and the current phase ends this tick); an ERG <-> SIM move switches at once when the rider's last switch is 30 s old (`TankConst.SWITCH_GAP_S`, BRIEF 4.5), else at the moment it is; when the segment's end (or its next planned switch) comes before the split's rest could hold 30 s, the switch waits for the segment's end (the later segments are replanned with `replan`). Moving back before the switch cancels it. While it waits the rider works on the new seat from its own power: an ERG seat on a SIM trainer is in band at 95% of the seat's planned target or more (x 0.85 while unverified) and cadence 60, a SIM seat on an ERG trainer by the SIM band; the director holds the old mode's grade neutral (no boiler or terrain grade) and the ERG patterns hold. `TankRiderState.mode_wait_s` and `mode_to` (snapshot v4) carry the switch to come; the HUD shows "ERG in 12 s" or "ERG at stage end". The rest phase's `min_s` keeps the PlanValidator's 30 s model (a phase that starts with a switch holds 30 s; one whose end switches holds what the next switch needs). Every split and replan passes the PlanValidator with no switch warning (`TankSeatPlan.check`, tested for every seat pair every 40 s of every phase in every content), and every ERG <-> SIM switch on the trace is 30 s or more from the next (the sims' S4 and S13).

**Automatic seating** (`TankAutopilot.seat_intent`) for bots, Autopilot riders and humans who never sent a deliberate intent (seat moves included; a human's own seat intent ends it): at most once a second, never inside the rider's minimum stay (`TankSeats.auto_stay_s`: 30 s solo, 60 s in a crew, from the rider's last move or segment start; no lock, but no thrashing), and in a fight only for a move its trainer follows at once (`TankSeats.follows_now`) and never an ERG <-> SIM move inside a warm-up segment (the depot, the drill's skirmish: the drill allows a rider one switch); once the objective is done, in a checkpoint or (solo) in its last minute before a checkpoint, for the next fight segment's seat. A crew's automatic riders hold their seats through a segment's opening (never in a checkpoint, not in a segment's first 60 s, in a fight not before the segment's own `min_s`). Solo, the solo loop: Drive while nothing is in the gun's reach; the Loader when a target comes and the rack is not full, until it is full; the Gun while it has shells (the rack or a chambered round) and a target; the Secondaries when only light targets (light tanks, dug-in turrets, barricades: what the bow guns hurt in full) are within 220 px; in its last minute before a checkpoint it takes the next segment's seat (it starts the Advance driving) unless the Gun has shells to fire at a target. Solo timing: in an Advance the solo rider leaves Drive for one stay at most (`TankAux.off_drive_seg`), then drives on to the halt line; from Drive it goes straight to the Gun with 2 shells or more (`SOLO_GUN_FIRST`), else to the Loader first; planning a gun line it reads what it will meet there (dug-ins in the bow guns' range: the Secondaries); and a segment's end waits ("Regroup", at most the stay and 2 s) while its stay runs and it wants another seat for the next fight segment. Crews: the Autopilot's riders hold the most needed seats (`seat_needs`: Drive to move on (5, 3.2 at a gun line), the Gun with shells or a Loader (4.5 with a target the auto-aim can lay on, 2 without), the Loader (4 with room in the rack in a fight, 3 on the road or with the rack full in a fight), the Lights in a fight the gun can fire in (3.4), the Secondaries with a target in their range (3.5, 4.6 when the main gun has nothing to lay on); ties Drive, Gun, Loader, Lights, Secondaries), moving when a seat is 0.5 more needed than their own.

**The Loader and the Gun.** The Loader in band (>= 90% FTP, or on reserve's 60 W) builds a shell on `steam.full_j` 1750 J of P_eff (about 7 s at 250 W; `load_t` its progress) into a ready rack of 3 (`rack`; it starts full); with the rack full it idles (no boiler grade, cadence band 50-120). Past the first 300 s of a SIM WORK phase a stowed shell opens the 5 s "Surge to overpressure" window: `over` takes it back to the boiler and the sprint builds it to 150% on `over_j` 1300 J (75% of a shell, v2's ratio) for a double-damage shell; an `over` up to 5 s before the stow (the surge came first) does the same at the stow. The depot drill's rounds are practice: the rack leaves the depot full. `latch` stows a light shell from 40%. With no round chambered and a shell in the rack the Gun goes to its loading elevation (0 degrees) and chambers the oldest shell in 1 s (`chamber`, `chamber_s`), then auto-aim lays again.

**The Lights.** In band (the arc's ERG rule) the searchlights are lit: the gun reaches the whole field with its normal dispersion. Dark (empty, out of band, stalled or on reserve) it reaches targets whose near edge is within the headlight's 260 rules px of the hull's front and its dispersion doubles. On the v3 field the screen clamps every enemy ahead within about 255 px of the hull's front, so the dark range bites only past that (the Behemoth's far parts); the dispersion is the Lights' everyday effect. The Lights' ERG pattern follows the searchlight load: the share of the last 10 s an enemy stood in range (65 + 15 x duty, 65-80%).

**The Secondaries.** Two bow guns fire exactly 2 rounds per pedal revolution of the Secondaries rider (2 x cadence a minute, alternating guns; `TankFeedState.rounds`, `rpm`, `fire_tick`) at the nearest enemy or Behemoth part 40-220 px ahead, else a barricade there (12 rounds that hit clear it). Power in band sets their slew (8 deg/s under band, 40 in band); a round hits when they point within 3 degrees: 1.5 damage (mediums 50%, heavies, destroyers and the Behemoth 25%). Rounds raise no events (the view reads `rounds`); kills are `BY_BOW`.

**The solo rider (v3 solo balance; crew 1 is under the sims' T1 like every crew).** Enemy counts are Simon's difficulty knob, and a solo rider meets less: entries with `min_crew` 2 (the barricades of Advances 1 and 2, the dug-ins of gun lines 2 and 3 and one of gun line 1's, gun line 3's destroyer) are not there for it, so it meets a medium and the rear light in every Advance, two dug-ins at gun line 1 and the heavy alone at gun lines 2 and 3; its Behemoth comes with every bogie wrecked (`boss.bogies_by_crew` [0, 3, 3, 3]: phase 2 at its stop line from the start, the turret's HP unchanged). Two per-crew tunings keep the locked rules: enemy and Behemoth shells do half damage to a solo hull (`enemies.json crew_damage_scale` [0.5, 1, 1, 1]; enemy HP stays the same for every crew), and a solo rider's rack is restocked to 3 at each checkpoint (`tanks.json steam.checkpoint_rack_by_crew` [3, 0, 0, 0]): it cannot load while it fires, and a stay is 60 s. For every crew, a phase entered through the platform's switch ramp (a move into the Gun or the Lights) keeps its entered target for its first 5 s cycle in ERG before the bank or arc pattern moves it.

**Enemies and telegraphs.** Counts x 0.5 / 0.7 / 0.85 / 1.0 for crews 1-4: a segment's total (rounded, at least 1), taken from its list in order (`TankEncounters.crew_counts`; each list puts first what a crew of 1 must meet); HP the same for every crew. Retuned on the rack: main-gun damage light 14, heavy 35, Overpressure 70 (v2's 20 / 50 / 100 x 0.7: shells come about 2.3x faster), HP light 35, medium 70, destroyer 80, heavy 150, the Behemoth's turret 150; the Gun's stabilizer drains 2.25 a second (v2 1.5 plus its bow bursts). The main gun never lays on a light tank behind the hull (v2's rule), so the rear light's flank shot always comes. The Behemoth creeps on until its front-most standing bogie stands where its front bogie stood, so the dark gun's headlight reaches every bogie in turn. Telegraphs: light flank shot 6 s, heavy 6 s, destroyer 7 s, Behemoth 8 s (hold 2 s, 3 s for the Behemoth).

**World.** Backdrops `forest`, `forest_firs`, `forest_birches`, `base` (TankIds.BACKDROPS): Ashfall Road through the forest with little bases at the depot, gun lines 1 and 2 and the Behemoth's gate; free-roam zones keep their ids with forest-variant and base labels (Pines, Fir hollow, Forest camp, Lumber yard, Birch glade); strongpoints stand at bases.

| Seat | Depot (WARMUP) | Advance | Gun line | Boss | Checkpoint | Roam |
| --- | --- | --- | --- | --- | --- | --- |
| Drive | SIM terrain 0..+2% | SIM terrain -3..+6% | **SIM flat (dig)** | SIM flat | ERG 50% | SIM valley grade |
| Gun | ERG 50 -> 65% | ERG 55%, bank [55, 100] | same | same | ERG 50% | bank [55, 85] |
| Loader | SIM flat, boiler 3% x p | SIM flat, boiler 8% x min(p, 1) | same | same | ERG 50% | same |
| Lights | ERG 50 -> 65% | ERG 65%, [65, 80] | same | same | ERG 50% | same |
| Secondaries | SIM flat | SIM flat | SIM flat | SIM flat | ERG 50% | SIM flat |

v2's ERG 90% gun-line block is gone. The power band (76-105%) shows for Drive and the Secondaries in WORK SIM phases. The free-roam phase is open from 30 s (`plan_min_s`, `TankConst.SWITCH_GAP_S`); the game's time up still reads the segment's own `min_s` (minutes x 60 - 300).

## How to play (v2; see v3 above for what changed)

- **Pedal.** Your watts (P_eff) run your engine. Each station is lit and its machinery turns on your cadence; the room glows and its wall lamp lights when you are "in band".
- **Crew size picks the tank.** 1 rider: Bulwark (220 x 71 rules px hull); 2: Rampart (251 x 71, diesel and dynamo); 3: Citadel (296 x 71, diesel, steam and dynamo); 4: Bastion (327 x 71, the Citadel plus an arc-generator room and a searchlight tower). Every tank has two bow guns in its nose. Slot 0 starts on the diesel, slot 1 on the dynamo, slot 2 on the steam engine, slot 3 on the arc generator. The `rotation` option (lobby toggle, default on) moves every rider to the next engine at each checkpoint (diesel, dynamo, steam, arc, among the tank's engines); with it off nobody moves.
- **Surge to evade.** Some enemy shots are telegraphed: a tank destroyer's 4 s glint, a heavy tank's 3 s muzzle glow, a light tank's 2.5 s flank shot (its first shot at its hold distance, 8 damage), the Behemoth's 6 s main gun. If any rider who can evade (in a SIM WORK phase past the first 300 s: the diesel, the steam engine, the Bulwark) holds the sprint rule (their last 3 s average at least 1.2 x FTP) for 2 s inside the telegraph (3 s for the Behemoth), the shot misses. There is no button: your legs are the input, so the Autopilot never evades.
- **Diesel** (the Bulwark's gearbox when solo): SIM. The tank's speed is your SIM speed; in band is 76-105 % of FTP. At a gun line the tracks lock and you "dig in" at ERG 90 %: in band you build a mud berm that absorbs hits (1 HP per 250 J, max 40).
- **Dynamo** (gunner): ERG. The target is its capacitor bank: it starts at 55 % FTP and climbs to 100 % as the bank drains. Power at 95 % of the target and cadence 60 charges the bank (1 unit per 150 J). The bank pays for stabilizing the gun while an enemy is on screen (the Bastion's heavier turret more), elevation, traverses, the Rampart's hoist and the bow guns of the Rampart and the Citadel (2 units a burst, none below 10).
- **Arc generator** (the Bastion): ERG 65 to 80 %: the target lifts with the arc load, the share of the last 10 s the bow guns fired (65 + 15 x duty). In band (power at 95 % of the target, cadence 60) the searchlights are lit (the main gun's dispersion halves) and the bow guns fire every 2 s; under band every 4 s; on reserve or stalled not at all. Auto-aim picks targets and fires; `left` / `right` cycle targets, `up` / `down` nudge the elevation (auto-aim pauses 5 s), `ability_2` traverses the turret to the other side, `confirm` fires.
- **Steam** (the Citadel's loader): SIM flat. Pressure builds with your watts (100 % = 4.5 kJ) and the boiler adds resistance as it builds (8 % x pressure). At 100 % a heavy shell latches after a 5 s window ("Surge to overpressure" inside it builds up to 150 % on a sprint, for a double-damage shell); `confirm` latches a light shell from 40 %. Each latch drops the boiler grade to 0 for the 6 s breech cycle. In band is 90 % FTP while building, cadence 50 while a shell is loaded or cycling.
- **Bulwark gearbox** (solo): the lever sits on Drive, Turret or Hoist (`left` / `right` / `swap` move it, 1 s with no power anywhere). The auto-lever (default on) picks Hoist when unloaded with a target in range, Turret when loaded and off target, otherwise Drive; a manual move suspends it for 15 s. Hoist adds a 4 % grade on top of the terrain in an Advance.
- **Zero input works.** The defaults play every station: the diesel drives on watts and digs in, auto-aim aims and fires, the boiler latches a heavy shell at 100 %, the auto-lever runs the Bulwark. The bow guns fire on their own. The Autopilot adds rear traverses and obstacle shots; it never latches early, moves the lever by hand, sprints (so never evades) or Overpressures, and never changes effort. A human counts as Autopilot until their first deliberate `lever`, `aim`, `target`, `traverse`, `fire`, `latch` or `turn` intent (an `over` never ends it).
- **Reserve and AFK.** A rider who stops pedaling gets the floor after 3 s, and after 10 s the platform's pause symbol, a stopped ride timer (BRIEF 3.5) and AFK (4.6.4); a dropped peer is AFK at once. That station runs on reserve (as if 60 W, never in band) under the Autopilot and keeps its plan until the rider returns. When every rider in the crew has stopped, the host pauses the game (`all_stopped`) until one pedals again. A solo rider who stops pedaling pauses after 10 s.
- **Rescue.** A cadence collapse in a dynamo or arc phase at 60 % of FTP or more, or in any 90 % gun line, arms the platform's rescue (target 50 %): the dynamo stalls (turret frozen, bank not charging, toast "Dynamo stalled"), the arc generator stalls (bow guns stop, searchlights dark, toast "Arc generator stalled"), the Bulwark's gun line gives nothing power, the berm stops growing. The plan continues.

## Rules summary (v2; see v3 above for what changed)

Numbers are the current content (`content/tank/*.json`) after the v2 rules pass (P4); where they differ from the brief, the ADRs "G1 rules: balance retune", "Balance iteration 1" and the P4 rules entries in `docs/decisions/tank.md` name the number and the evidence.

**The session**: depot, then three stages of (Advance, gun line, checkpoint), then the boss, then the platform's 180 s cool-down. Every phase is a FIT lap (12 laps). Advances, gun lines and the boss are open-ended: once the objective is done and `min_s` has passed ("Regroup" until then), the director ends the phase for every rider in one step; the platform cuts it at `max_s`, which is an overrun and costs score (an Advance tows the tank to the halt line, a gun line is finished by a support barrage, the Behemoth withdraws).

**Objectives**: an Advance is done when the tank has driven the segment's `length_m` to the halt line; a gun line when every gun is down (the dozer then shoves the tank traps aside); the boss when the Behemoth dies (`victory`). If the boss reaches `max_s` the Behemoth withdraws (`withdrawn`). The ride itself never fails.

**Drive**: the SIM speed model (BRIEF 3.11) with mass = rider mass + 8 kg and CdA 0.5 m2, on the terrain grade under the tank; the world scrolls at 0.4 x game speed, 20 art px per visual metre. While the driver is in band, enemy hit chances are x 0.45 (evasive). A barricade (wire, a wreck) stops the tank 180 px short of it, where the main gun and the bow guns reach; a heavy shell, three light shells or 4 s of bow-gun fire clears it.

**Gun**: the main turret faces right or left; a traverse flips it. Elevation -12 to +30 degrees, shells fly 360 px/s under 300 px/s2 gravity and inherit the hull's speed; the solver reaches a light tank at its hold distance from every tank (tested). Auto-aim priority: tank destroyer in telegraph, dug-in, heavy, medium, light, obstacle, nearer first (lower arc, with lead); it fires within 0.5 degrees once a shell is loaded. Damage: light 20, heavy 50, Overpressure 100; splash 16 px at 50 %. Mediums take 50 % from light shells and bow-gun bursts; heavies, destroyers and the Behemoth take 25 % from them.

**Bow guns** (every tank): a 5-damage burst every 2 s at the nearest enemy (or Behemoth part) ahead whose near edge is 40-220 px off the hull front, else a barricade there; hitscan. Power: the Bastion's arc generator (full rate in band, half under band, none on reserve or stalled), the Rampart's and the Citadel's dynamo bank (2 units a burst, none below 10), the Bulwark's gearbox (half rate, free). Rear light tanks are out of every gun's reach; they break off after 45 s.

**Lanes**: every enemy holds its position in one of four depth lanes, and no two held positions on one side and lane overlap (the view draws the lanes).

**Enemies** (HP and counts x 0.75 Bulwark, 0.8 Rampart, 1.0 Citadel, 1.2 Bastion, counts rounded, at least 1; held distances are clamped so the enemy stays on screen, which with the long v2 hulls is often nearer than the range below):

| Enemy | HP | Behaviour | Gun (damage / every / hit) |
| --- | --- | --- | --- |
| Light tank | 30 | rushes to 120-140 px, weaves, breaks off after 45 s; its first shot at its hold is a telegraphed flank shot (2.5 s) | 2.5 / 4 s / 50 %; flank shot 8 / 70 % |
| Medium tank | 50 | holds 260-340 px | 4 / 6 s / 60 % |
| Tank destroyer | 50 | stops at the screen edge, 4 s glint telegraph, shifts 40 px after each shot | 9 / 9 s / 75 % |
| Dug-in tank | 50 | gun line; only the turret above the concrete is hit | 5 / 9 s / 60 % |
| Heavy tank | 130 | gun-line duel at 300-380 px, 3 s telegraph, backs off 30 px per 50 damage | 7 / 7 s / 60 % |
| Behemoth (boss) | 3 bogies x 50, turret 205 | creeps to 120 px, each broken bogie pushes it back 24 px, phase 2 immobile; main gun every 35-45 s (25-35 s in phase 2) after a 6 s telegraph | main 13 / 75 %, secondary 2 every 5 s / 50 % |

Telegraphed shots (destroyer, heavy, the light's first shot at its hold, the Behemoth's main gun) can be evaded (How to play). Caps: 16 enemies, 24 shells. Enemy hits roll with `ctx.rng` at fire time; the shell lands on the tank or 20-40 px off. Encounters come only from the mission's fixed lists.

**Hull**: 150 HP, +30 at each checkpoint (the maximum rises by 30 and it heals 30). At 0 HP: breakdown (no movement or fire, damage ignored) until the driving station's P_eff has paid 5 kJ, then 40 HP.

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

## Free roam (brief 2.10)

`roam_10`, `roam_20`, `roam_30` (featured), `roam_45` and `roam_60`: one long night valley driven back and forth for N minutes, points for every kill. Each content file is `{id, kind: "roam", label, minutes}`; `TankContent.expand_roam` turns it into two segments, so every other part of the game sees an ordinary mission:

| Segment | Kind | Length | Plan (`stations.json` `roam_plans`) |
| --- | --- | --- | --- |
| Drive-out (`depot`) | WARMUP | 300 s (`valley.json` `drive_out_s`) | the depot's: diesel and Bulwark SIM `game` (0..+2 %), dynamo and arc ERG 50 % ramping to 65 %, steam SIM flat (boiler 3 %); no drills, no enemies |
| Roam (`roam`) | WORK, open-ended | `min_s` = minutes x 60 - 300, `max_s` = `min_s` + 300 | diesel SIM `game` on the valley's grade (-3..+5 %, 2 Hz); dynamo ERG 55 % with the bank pattern in `range_pct` [55, 85]; steam SIM flat + the boiler; arc ERG 65 % with the arc pattern in [65, 80]; Bulwark SIM `game` + the hoist (the Advance's) |
| Cool-down | appended | 180 s | Tank sends nothing |

Every roam phase is longer than 300 s, so BRIEF 4.6.1's 105 % cap applies; no bound Tank sets there is above 85 %. Each rider keeps its slot's start engine for the whole session (no rotation: diesel, dynamo, steam, arc; the Bulwark solo). There are no ERG <-> SIM switches before the cool-down. FIT laps: the drive-out, the roam and the cool-down.

**The valley** (`content/tank/roam/valley.json`, `contracts/tank_roam_map.gd`): about 6 km (5.8-6.2 km), built at the session start from a seed the host draws from `ctx.rng` (the snapshot carries it; every peer rebuilds the same map with `TankRoamMap`, a pure LCG of its own). Pine forest at both ends (each with a turning place), and between them the lake shore under the cliffs, the village, the quarry and the open meadow once each in a seeded order, some separated by more forest. Each zone has its own terrain range (forest -2..+3 %, lake -1..+1 %, village -1..+2 %, quarry -3..+5 %, meadow -2..+2 %; points 150-260 m apart, at most 2.5 points apart, flat over 200 m at both ends) and its own near plane. Travelling west the grade is the negation, clamped to -3..+5 %. Dug-in strongpoints stand at one seeded spot in each village, quarry and forest zone that fits (at least 900 m apart, 700 m clear of the ends).

**Driving and the turn** (`rules/tank_roam.gd`). The rules keep working in the travel frame: the tank always drives toward +x in rules px as in a mission; `TankRoamState.map_m` is the hull centre's place on the road and `TankHullState.dir` which way +x points (east +1, west -1). The road stops at the turning places (the hull's centre 60 m inside either end). The driver (the diesel, or the Bulwark solo) turns the tank with `ability_1` (or `confirm` on the diesel): the `turn` intent, refused for 30 s after a turn. A turn is an 8 s stop; at its midpoint `TankRoam.flip` mirrors the travel frame about the hull's centre (enemies change sides and move to a held place on their new side, a running telegraph is called off, shells and obstacles mirror, the turret keeps pointing the same way along the road), so every map point keeps its place. The Autopilot (a human on the fallback, a bot, a station on reserve) turns 3 s after the tank reached a turning place; the driver also gets the toast "Turn around".

**Patrols and strongpoints.** A patrol comes every 50-110 s of WORK time (drawn): 1-2 light tanks (45 %), a medium with a light half the time (30 %), a tank destroyer (15 %), a heavy tank (10 %, only after 600 s of WORK time and while no heavy is on the field). Counts scale with the tank (`enemy_scale`, as in missions), the patrol enters ahead (75 %) or behind (always behind with less than 150 m of road ahead) and is trimmed to 6 enemies on the field (a full field retries 10 s later). Patrols use the mission rules: depth lanes, holds, the light's 2.5 s flank shot, telegraphs and Surge to evade, the bow guns, breakdowns. A strongpoint joins the field when its spot nears the screen and leaves it, still standing, once well off screen; it returns 600 s after it falls. The tank halts ("Engage") while a strongpoint ahead is within 180 rules px of its front or a heavy tank within 400 px, else drives on. Nothing spawns in the drive-out.

**Time up.** At the roam phase's `min_s` the rules raise `time_up {p}` (`p`: the patrols so far; none come after): no new patrol or strongpoint. A fight in progress (an enemy within 400 px of the hull) may finish, the board shows OVERTIME; once none is left, or 1 s before `max_s` at the latest, the phase's objective is done and the director ends it for every rider in one step; the cool-down follows and the module finishes `time_up`.

**Points** (the crew's): light 10, medium 25, destroyer 30, dug-in 20, heavy 60 per kill by crew fire, +5 per evaded shot, -40 per breakdown, +2 per full kilometre driven in the roam phase. **Grade** by points per WORK minute: S >= 22.5, A >= 17.5, B >= 12.5, C >= 7.5, else D. These are the brief's starting cut-offs (9 / 7 / 5 / 3) x 2.5, tuned on the simulations: a compliant crew kills nearly every patrol, about 16-25 points a WORK minute, so the brief's cut-offs graded every compliant crew S. On `roam_30`, seeds 1-3: compliant crews 1-4 at 17.5-18.3 / 16.1-18.6 / 17.8-20.1 / 20.3-24.8 points a minute (A, B to A, A, A to S), crew 3 at 85 % compliance 16.7-19.8 (B or A), at 70 % 5.9-13.7 (D to B, with 3-7 breakdowns). Sprints that evade lift a crew toward S (+5 each). **Results**: the points, points a minute, kills by type (light/medium/destroyer/dug-in/heavy), distance, evades, breakdowns and patrols; XP = round(kJ / 10) + the grade bonus; unlocks as for missions (no Behemoth one); `summary_key` `TANK_RESULT_TIME_UP`; Strava `ride_tag` "Free Roam N min" and lines for points, kills, distance, evades and breakdowns.

**Net.** The snapshot's optional `rm` row (free roam only): the map seed, the hull's place on the road (0.1 m), the turn and its cooldown, the time at the end, flags (time up, overtime, engaging, the map end), the points, the strongpoints that are down, the odometers; a crew of 4 at the caps stays under 4 KB (tested). Events `turn {s, dir}` (s -1 for the Autopilot) and `time_up {p}`.

**View.** The camera follows the tank. The planes scroll with the hull's place on the road (`TankView.plane_x`), so the world scrolls with the direction; driving west, the world, tank, light and effect layers are drawn mirrored (the tank on the right, facing left; the planes and the HUD never mirror). A turn hides the flip in a dust cloud thickest at its midpoint; wrecks keep their place on the road through it. Each zone swaps the forest plane for its own near plane (lake shore, village, quarry, meadow; the pine forest keeps the forest plane), cross-faded over 60 m at a zone's edge; they are built by `assets/tank/v2/tools_src/zones.gd` from the kit's own planes (no fal) and listed in `kit.json` `zone_planes`. A turning place (a gravel loop, a hatched timber barrier, a hooded amber lamp) stands at each end of the road. The mission look is unchanged.

**HUD.** The map strip (`TankHudRoamStrip`) across the top in place of the mission plate: the zones in profile, the terrain, the turning places, the tank with its direction and the screen's bracket, patrols and strongpoints (crossed out while down), "ROAM / 30 MIN" (DRIVE-OUT, ENGAGE). The board (`TankHudBoard`) top right: the time left (the drive-out counts toward it; OVERTIME in red), points and kills; the hull plate under it without its kills; toasts under the strip; the turn marker (a striped post) at the turning place ahead; help for the map, the board and the turn. Toasts: "Turn around" (the driver), "Turning round", "Engage", "Time up: finish the fight".

| Knob | File and key | Now |
| --- | --- | --- |
| The valley | `roam/valley.json` `length_m`, `zones`, `terrain_*`, `end_flat_m`, `start_m`, `end_m` | 5.8-6.2 km; see above |
| Drive-out and overtime | `roam/valley.json` `drive_out_s`, `overtime_s` | 300, 300 |
| Patrols | `roam/valley.json` `patrols` | every 50-110 s, 75 % ahead, at most 6, heavy after 600 s, weights 45 / 30 / 15 / 10 |
| Strongpoints and the halt | `roam/valley.json` `strongpoints`, `engage_heavy_px`, `fight_px` | village, quarry, forest; 900 m apart; back after 600 s; 180 px; 400 px; 400 px |
| The turn | `roam/valley.json` `turn` | 8 s stop, 30 s cooldown, the Autopilot after 3 s |
| Points and grades | `roam/valley.json` `points`, `grades` | 10 / 25 / 30 / 20 / 60, +5, -40, +2 per km; S 22.5, A 17.5, B 12.5, C 7.5 |
| Roam plans | `stations.json` `roam_plans` | the table above |

## Content

| Content | Plan | Notes |
| --- | --- | --- |
| `ashfall_road` (default, zero-input) | depot 300 s, 3 x (Advance 90-300 s, gun line 60-180 s, checkpoint 60 s), boss 120-360 s, cool-down 180 s | 30 min nominal, 41 min at most; 12 FIT laps; Poplar Road (1100 m), Kettle Ford (1200 m), Quarry Ridge (950 m), Foundry Gate |
| `drill` (e2e) | depot 30 s, skirmish 70 s (WARMUP), checkpoint 30 s, cool-down 180 s | inside the warm-up limits, no haptics, at most one mode switch per rider; 4 FIT laps |
| `roam_10`, `roam_20`, `roam_30` (featured), `roam_45`, `roam_60` | drive-out 300 s (WARMUP), roam (WORK, `min_s` minutes x 60 - 300, `max_s` + 300), cool-down 180 s | free roam (above); 3 FIT laps; no rotation |

### Content files and schemas

Every file is JSON, validated at load by `TankContentSchema` (`contracts/tank_content_schema.gd`). The validator also holds each effort number to the brief's safety envelope (BRIEF 4.6), so a retune cannot move a number past it: a bad value is a load error and the game lists no plans. The `_doc` key of each file explains its keys.

| File | Holds |
| --- | --- |
| `tanks.json` | `tanks` (code, crew, hull size, engines, turrets, `enemy_scale`, the Bastion's `stabilizer_per_s`), `hull`, `drive`, `evade`, `berm`, `in_band`, `power_ratio`, `dynamo`, `steam`, `gearbox`, `gun`, `damage`, `bow`, `arc`, `caps`, `props`, `drill` |
| `stations.json` | engines and start engines, `rotation` rows, `plans` per engine and segment type, `drill_plans`, `roam_plans`, `terrain`, `bank`, `arc`, `boiler`, `hoist`, `cadence_band`, `haptics` |
| `enemies.json` | `types` (light, medium, destroyer, dugin, heavy: HP, size, preferred `lane`, hold distance, speed, gun, the light's telegraphed `flank` shot) and the `boss` (bogies, turret, main and secondary guns, telegraph), shell speed, miss distance, `lanes` |
| `missions/roam_<n>.json` | free roam: `id`, `kind` "roam", `label`, `minutes` (10..120); expanded at load (`TankContent.expand_roam`) |
| `roam/valley.json` | the free-roam valley: length, zones and their terrain, ends, drive-out and overtime, strongpoints, patrols, the halt, the turn, points and grades |
| `missions/<id>.json` | `id`, `label`, `rotation`, `plan_table`, `segments[]` (`id`, `type`, `stage`, `kind`, `duration_s`, `min_s`, `max_s`, `length_m`, `terrain` as `[distance_m, grade_pct]` points, `encounters[]` with `at_m` / `enemy` / `count` / `from`, `obstacles[]`, gun-line `enemies[]` with `at_px`, `props`, `drills`, `teach`) and the `cooldown` backdrops |
| `scoring.json` | score weights and scale, objective fractions, survival per breakdown, grade cut-offs, XP |
| `cosmetics.json` | hull finish unlock rules |
| `strings.csv` | every user-facing string, keys `TANK_*` (`strings.csv.import` and `strings.en.translation` are generated; commit them) |

### Tuning knobs

Everything below is a content number: change it in the file, re-run the matrix (`run_sims.sh`) and keep T1-T6 green. The brief gave the starting values; tuning is held to +-50 % unless an ADR records the sim evidence.

| Knob | File and key | Now |
| --- | --- | --- |
| Enemy HP and count per tank | `tanks.json` `tanks.<tank>.enemy_scale` | Bulwark 0.75, Rampart 0.8, Citadel 1.0, Bastion 1.2 |
| Hull toughness | `tanks.json` `hull.hp`, `hull.checkpoint_hp`, `hull.repair_j` | 150, 30, 5000 |
| What driving in band avoids | `tanks.json` `drive.evasive_hit_mult` | 0.45 |
| Enemy guns | `enemies.json` `types.<t>.gun`, `boss.main` | see the table above |
| Dynamo bank | `tanks.json` `dynamo.stabilizer_per_s`, `per_traverse`, `per_degree`, `hoist_s` | 1.5 (Rampart 1.3, Bastion 2.0: `tanks.<tank>.stabilizer_per_s`), 15, 0.5, [22, 11] (the Rampart's hoist) |
| Steam fill and latch | `tanks.json` `steam.full_j`, `window_s`, `breech_cycle_s` | 4000, 5, 7 |
| Bulwark gearbox | `tanks.json` `gearbox.hoist_j`, `auto_drive_clear_px`, `manual_suspend_s` | 5250, 340, 15 |
| Surge to evade | `tanks.json` `evade.sprint_window_s`, `hold_s`, `boss_hold_s`; telegraphs `enemies.json` `types.<t>.telegraph_s`, `types.light.flank`, `boss.main.telegraph_s` | 3, 2, 3; 4 / 3 / 2.5 / 6 s |
| Bow guns | `tanks.json` `bow` | 5 every 2 s, 40-220 px, 2 units a burst, under band 0.5, Bulwark 0.5, 4 s to clear |
| Arc generator | `tanks.json` `arc.lit_dispersion_mult`; `stations.json` `arc` | 0.5; 65 + 15 x duty |
| Bank, arc, boiler, hoist, terrain and haptic directive shape | `stations.json` `bank`, `arc`, `boiler`, `hoist`, `terrain`, `haptics` | schema-bounded |
| Spacing | `enemies.json` `lanes` | 4 lanes, 8 px gaps |
| Stage length and enemy lists | `missions/ashfall_road.json` `segments[].length_m`, `encounters`, `enemies`, `at_px` | Advances 1100 / 1200 / 950 m |
| Boss pacing | `enemies.json` `boss`; the mission's boss `start_left_px` and `end_hold_s` | `end_hold_s` 7.5 |
| Score and grades | `scoring.json` | as above |

## Tests, gates and commands

```bash
. tools/env.sh
# Tank GUT suite (strict): unit, static, view and HUD from fixtures, balance harness, S2 timing, S8 stress, rules-step perf
env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/run_tests --only=gut --gdir=res://tests/games/tank
env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/godot.sh --headless --path . -s tools/check_scripts.gd
# Node tests: the sim checker and the e2e report checker
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
# The same with a crew of four (the Bastion)
env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/screenshot --game=tank --content=ashfall_road --players=4 --at=60,400,560,1500
```

The simulation matrix (`tests/games/tank/sim/`, checked by `check_sims.mjs`):

| Run | What it asserts |
| --- | --- |
| S1 compliant `erg` riders, crews 1-4, seeds 1-3 | T1 phase times, no overrun, grade B or better; T2 (crews 2-4) the dynamo above 80 % for 30 s per stage and 60 s in the boss, back to 65 % or lower within 120 s; T3 (crews 3-4) each heavy shell built in 18-35 s and at least 6 s at boiler grade 0 for the rider who latched it; T4 (crew 1) the Bulwark on Drive for 60 % of each Advance; T6 a telegraphed shot and a medium in each Advance (and crew 1's "Surge to evade" prompt), a heavy duel of 90-180 s in gun lines 2 and 3; T7 (crew 4) the arc target above 72 % for 30 s per stage and back to 68 % within 60 s of a fight's end |
| S2 zero riders | crew 3 at 0 W: the host's shared pause holds the depot (no kill, grade D); crew 3 spinning at 10 W and 25 rpm overruns every stage (withdrawn, grade D); crew 1 pauses in the depot; each pause at most 10 s + 1 tick after the first sample that meets not_pedaling (the report bounds it from the trainer's first notification; `sim/test_tank_s2_pause.gd` measures it exactly) |
| S3 compliance 100 / 85 / 70 % | T5: the mean score falls strictly |
| S4 every content and crew (1-4) | every directive, plan and trace rule of BRIEF 4.5 and 4.6: patterns, applied values never above what was asked, warm-up limits, switch spacing, laps |
| S5 30 rpm collapse in a dynamo stage and in a 90 % gun line | rescue, stagger, the plan continues |
| S6 haptics off for one slot | no haptic applied to that rider |
| S7 same seed twice | identical events and snapshot hashes |
| S8 stress (`sim/test_tank_s8.gd`) | counts x 3: at most 16 enemies, snapshots under 4 KB |
| S9 a scripted sprinter (crew 1) | telegraphed shots evaded by the solo rider, no Ram event or haptic, a gun line entered after a sprint at or below its target |
| S10 crew 3 on the network path | every rider a scripted sprinter: a client's `over` arrives as a telemetry intent, is owned by the steam engine and latches an Overpressure shell (a client's `aim` is proven by `integration/test_tank_session.gd`: headless sims press no keys); slot 1 stops dead for 60 s in a dynamo gun line: rescue, AFK within 10 s, a station on reserve, back, nobody else affected |
| S11 free roam: `roam_10` crews 1 (SOLO) and 4, `roam_30` crew 3 | time up at `min_s` (`time_up` once), the roam phase ended by `end_phase` within `min_s` .. `max_s` and for every rider at once, no patrol after time up (the event's count equals the results'), 3 FIT laps, the plans' bounds, every directive, plan and trace rule of S4, the grade by points per WORK minute (crew 3 on `roam_30`: B or A), `ride_tag` "Free Roam N min" |
| S12 `roam_10` crew 3 at 0 W | as S2's zero crew: the shared pause holds the drive-out to `--max-sim-seconds`, no kill by crew fire, grade D |

Gates: the Tank GUT suite, `check_scripts`, gdformat and gdlint, `tests/sdk/test_conformance.gd` (Autopilot humans at 1 and 4 riders), the matrix with `fit_check`, `node tools/e2e/run.mjs --games=tank`, and the full `tools/run_tests` at or above the green-count floor.

## The look: the v2 kit, the view and the HUD

**The kit** (`assets/tank/v2/`, manifest `kit.json`, read by `TankKit`). Everything is built from Simon's reference image (`source/reference.webp`) by the scripts in `tools_src/` (`.gdignore`d; `regen.sh` rebuilds the kit): the four tank variants `tank_1rider` .. `tank_4rider` and the turret barrel, cut from the reference at its bulkheads (the Citadel is the reference tank, the Bastion adds the arc room and the searchlight tower); the backdrop planes in `planes2/` (far: sky, Milky Way, mountains, the pale cliff and the lake; forest; road; the dark foreground), each the reference's own 960 px cut plus its mirror, blurred once by `planes2.gd`; the enemies and the Behemoth in `enemies/`, procedural sprites in the reference's style; the 20 px crewmen in `crew20/`; the HUD's bitmap fonts in `hud/`; the content cards and the picker card. `kit.json` holds every rect, anchor, room, muzzle and light the view and the HUD read. No sprite is generated and the game makes no fal call.

**The view** (`view/`, `TankView`, a Node2D the PixelViewport shows at 960 x 540 art px, `pixel_flex` down to 852 x 480). Rules px x 1.5 = art px (`TankView.sx` / `sy`). Back to front: the planes at their parallax, the road with the halt line, obstacles, wrecks aging on sim time into debris heaps, the enemies in the depth lanes the rules hold them in (`TankEnemyState.lane`, in the snapshot) and the Behemoth at its rules position; the tank (`TankHullDraw`: the barrel at the gun's elevation and traverse, running gear at tank speed, the room machines `TankMech` and `TankRoomMachines` turning on their riders' cadence and showing under, in and over band, the crew `TankCrew`, plaques in slot colours, the bow guns); additive light (`TankLightDraw`: room lamps, the headlight and searchlight cones, the Bastion's searchlights following its arc generator, fires and flashes); smoke and the foreground plane; the tilt-shift shading; then the per-frame depth of field (`TankDof`, the rider's `miniature` option, off by itself after 5 s of slow frames). Effects come from pooled emitters with caps (`TankFx`, seeded from `ctx.seed`). Positions are drawn from a snapshot history (`TankSnapHistory`, `TankRenderClock`), so a client interpolates. The depot roll-out has its own yard (`TankDepotDraw`: a hangar with a lit doorway, a gantry, drums, a barrier arm); a lit gravel road runs under the tank with a contact shadow and the headlight's pool; back lanes stand smaller, higher and hazier on their own banks; wrecks are charred and burn, and the beams light what they cross. When the gun faces the rear the whole turret block (mantlet, crate, antenna, roof crew, searchlight) is drawn mirrored about its pivot, squeezed mid-traverse; every mirrored sprite keeps its rect. The view only reads the state; the evade cue lurches the tank (the diesel or the Bulwark evaded) or blows a smoke screen (the steam engine did), from the event's slot.

**The HUD** (`hud/`, `TankHud.spec()`: the game's own Controls, no kit widgets, `shows_power = true`), in the brief's riveted-iron palette and the game's own pixel fonts: the mission plate top left (stage, clock, stage strip, objective) with the toasts under it; the hull plate top right (HP bar and number, kills) with the Behemoth's bars under it; my numbers bottom left (watts and %FTP, cadence, their band gauges, one instruction line such as HOLD 152-210 W, SPIN 60+ RPM, SURGE 240+ W, LATCH or RESERVE, W' and the gear, the station); the crew row bottom middle (one live engine window per rider in room order, name in the slot colour, watts, an in-band strip, YOU on your own); world tags (the speed tag, the halt line's distance plate, SURGE TO EVADE with countdown pips over a telegraphing shooter, the gun's elevation arc, on the side of the drawn barrel, stepped outward until no pixel touches the turret or hull and hidden mid-traverse); banners in the middle; F1 help with five entries. Nothing covers the bottom-right 200 x 60 or, apart from the world tags, the tank's band (y 150-360). `TankHudGeom` reads the view's geometry for the tags.

## Files

| Path | What |
| --- | --- |
| `game.json` | The manifest: 1 to 4 riders, the contents, the `rotation` option, `first_run_priority` -1, no bots |
| `tank_game.gd` | `TankGame` (GameModule): intents, the host loop, bands and `end_phase` through the director, events, prompts, HUD feeds, snapshot, results, `apply_progress` |
| `contracts/` | Ids, constants, the state records, the intent / event / snapshot schemas, the content schemas, `TankGeometry`, `TankTerrain` (see `contracts/README.md`) |
| `effort/` | `TankPlanBuilder` (plans, rotation) and `TankDirector` (every directive, bands, haptics, `end_phase`; the only code that touches `ctx.directives`) |
| `rules/` | `TankRules.step` and its parts: segments, stations (the arc generator too), drive, hull, score, free roam (`TankRoam`), host-only bookkeeping (`TankAux`) |
| `combat/` | Ballistics, aim, targets, shells, damage, enemies and their lanes, encounters, the Behemoth, Surge to evade (`TankEvade`), the bow guns (`TankBow`) |
| `content/` | `TankContent`, the validated loader |
| `autopilot/`, `net/` | `TankAutopilot`; `TankSnapshot`, `TankCues`, `TankEventCast` |
| `view/` | `TankView` and the diorama from the v2 kit: planes (zone near planes in free roam), the tank variants (mirrored when driving west), room machines (`TankMech`), crew, enemies in their lanes, the Behemoth, lights, effects, the depth of field, interpolation |
| `hud/` | `TankHud` (the game's own Controls at art-px rects): mission plate, hull plate, the Behemoth's bars, my numbers, the crew row, world tags, help; the free-roam strip and board |
| `audio/` | `TankAudio`, the adapter on the platform's audio kit (see Audio below) |

## Known gaps and P2 notes

- Not tested on a real trainer: `HARDWARE_TEST.md` is the checklist, and its last section lists every item the automated runs could not judge (real sprint gestures, the mix, frame pacing on integrated graphics, network loss). Nothing has met a real Strava upload either.
- The mix has been measured offline and nobody has heard it; the look has been reviewed from screenshots and headless logs only.
- P1 is not built: the garage between missions (scrap buys +10 HP armour x3, +20 bank units, -10 % boiler energy, and the hull finish picker, so unlocked finishes cannot be equipped yet), Viaduct Crossing (a river viaduct with an armoured train as the gun line), and two tanks in one lobby (up to 6 riders, the second on a rear ground line 40 px higher, enemy scales summed).
- P2 ideas: tank duels across a ruined town square (a stand-off stage where heavies trade shells across rubble with dug-in guns behind cover); the cool-down gate roll-through (today the cool-down swaps the town backdrop in, or the field road if the Behemoth withdrew, and the tank keeps rolling; the broken Foundry Gate and a scripted camera move through it are not drawn); hull finishes drawn on the tank (today an unlock is a progress entry only); the garage.
- Balance was tuned on the simulation matrix with compliant synthetic riders. Real riders' compliance and sprint timing may want a retune once someone has ridden it: from a 90 % FTP ride the 3 s sprint rule holds after about 1.5 s at 1.5 x FTP, so the heavy's 3 s glow needs about 1.8 x FTP from its start and the light's 2.5 s flank shot is evadable only by a rider already sprinting.

## Audio

Everything is rendered from `assets/tank/audio/audio.json` by `tools/audio` (`docs/AUDIO_PIPELINE.md`): no samples, no downloads. `TankAudio` only maps state to parameters and events to cues. `node tools/audio/preview.mjs --game=tank` writes `build/audio_preview/tank.mp3`.

- **Each seat, 1:1 with its crank.** `TankView.audio_feed` hands the adapter each seat's `machine_phase`, the number the machine is drawn from, so sound and picture cannot drift. The fractions come from the art and `tests/games/tank/audio/test_tank_audio_bank.gd` pins them to `tank_mech.gd`. FTMS reports cadence about once a second and no crank angle: the strokes lock to the crank on screen exactly and to the rider's feet in rate only. A seat that stops, stops dead; a reserve room is silent because its crank stands still.
- **Diesel (Drive):** three unequal cylinders of 6, 5 and 4 takes against pitch tables of 7, so the takes only line up again after 60 revolutions. Exhaust and inlet valves, a body whose two loops cross over at 50-75 rpm, a rasp that breathes at the firing rate and opens with load, a turbo whistle by watts with a blow-off when you lift, and a crackle on lift-off or well over band.
- **Dynamo (Gun):** a whine with a 27 Hz ripple locked to the armature whose lines swell each on their own rate, brush crackle and ticks that come forward while the jars stay empty, the jars' dump at 0.8 of a turn once they fill, the hoist's ratchet. **Steam (Loader):** two chuffs a revolution by pressure, valve, simmer, the pawl while the rack fills, the safety valve when over. **Arc (Lights):** a beating hum, the ladder's buzz and its zaps at 0 and 0.5, doubled over band. **Feed (Secondaries):** bolts, the bow guns while they fire, links, casings, the belt's rattle. **Repair:** the rivet hammer on each strike with its ring and sparks while the hull needs it, a compressor that eases down and a dry tap that follow your legs when it does not, the press when a patch is done.
- **Track:** links and a squeak locked to the distance drawn (`travel`), three links and one squeak per 2.4 m, and a rumble by speed.
- **Other riders' machines** play 10 dB under yours, without their small details, and their strokes keep a 60 ms gap across the crew (`other_min_gap_s`). Yours are never thinned. Someone who stops pedalling stays the lead; only a spectator lifts the room 4 dB.
- **The gun and the far fight:** a low thump, crack and tail, the shell's flight and the ejected casing that vary round by round, its clang, a reload that varies too. Far landings and kills are heard after the flash, at twice real sound speed (`range / 680` m/s, 0.6 to 3.5 s), and quieter with range. An enemy's far shot is a distant thump after its range and a whistle that ends at impact: the telegraph for Surge. Near threats bring a burst from the bushes, their own engine by distance and a small gun; a round on one pings at once, however it was fired.
- **The night:** wind in the pines in two layers and a cricket chorus (lengths 5, 11 and 13 s, so 715 s before they meet), cricket trains, frogs, an owl, a creaking branch, and a far battle that stays out of the depot and the cool-down.

Settings > Audio holds the levels: Machines (seats, track), Ambience (the night), Effects (guns and hits).
