# Turbo Reel: game brief

Turbo Reel (game id `fishing`) is a sport-fishing game for 1-4 riders plus bots on one shared ocean. Your stationary bike drives a pedal boat out from the harbour and, once a fish bites, turns the big-game reel. It is a GameModule (BRIEF 3.6) at `src/games/fishing/`; that folder's `README.md` lists its files. "BRIEF x.y" means a section of `docs/BRIEF.md`; on platform rules the BRIEF wins. The numbers live in `FishingConst` and the content JSON; this brief explains them.

## 1. Pillars

- **The trainer is the rod.** The fish's pull is the ERG target, a run is a surge, the gaff is a sprint. In ERG the power is held, so cadence is the skill: at a fixed power a lower cadence puts more torque on the line.
- **Fair.** Pulls are shares of each rider's FTP and fish tire by compliance, so the scaling mode (BRIEF 3.3) never decides who lands what. Boat thrust uses the effective power `P_eff`, so the lobby's scaling choice decides fairness there.
- **Low attention.** Drive, stop, pick a fish, keep cadence in the band.
- **Safety first.** BRIEF 4.6 outranks every idea here. The game changes trainer load only through `ctx.directives`.

## 2. Modes and contents

| Content | Mode | What |
| --- | --- | --- |
| `roam_30` (default), `roam_10`, `roam_20`, `roam_45`, `roam_60` | Free Roam | Competitive: N minutes of play from the start, the first 5 a fixed SIM drive-out with no bites. Most points wins. |
| `base_60` | Workout | 52 min of fishing, mackerel and mahi, nothing above 100 %, fights <= 25 % of fishing time |
| `threshold` | Workout | 4 scheduled tuna at 95 % with 360 s Trolls between (55 min) |
| `e2e_2min` | Workout | The e2e content: 15 s ride out, 20 s Troll, one scheduled mackerel per rider, Landing (<= 135 s) |

Free Roam is shown first and large in the content picker (`content_cards` in `game.json`). `roam_30` is the zero-input and first-run content (`first_run_priority` 10). Rider options (`player_options`): `reel_pct` (the workouts' Troll target, 50-70 %, default 60) and `relaxed_band` (a 22 rpm band instead of 16).

## 3. One ocean, the boat

Every rider has a boat on the same map. Each screen's camera follows the local boat across the full 640x360 art width; other boats show when in view. A minimap strip on top shows the floor profile, the zones, the dock and the edge (Free Roam) or a moving window (workouts), one icon per rider in their slot colour for the current action (driving, sprinting, casting or waiting, fighting, landed, paused, AFK), and a leaderboard with name, points and action.

`FishingBoat` (pure, 0.05 s steps): the effective power sets a steady speed of 15 m/s x (`P_eff` / 250 W)^0.6. 250 W (100 % FTP-equivalent in every scaling mode) holds 15 m/s and crosses the 18 km map in 20 minutes; 150 % holds 19 m/s (16 minutes). The boat closes on its new speed in under 3 s (time constant 0.9 s speeding up, 0.6 s slowing), so a surge visibly accelerates. Under 20 % FTP-equivalent the prop disengages and water drag stops the boat from cruise in about 3.3 s (15 m). Heading is +1 (out to sea) or -1 (back to the dock). Pause, AFK and stale telemetry free the prop, so a paused boat brakes to a stop.

Trim is signed, -6 to +14 degrees (+ bow up): a spring-damper (about 1.4 s period) toward 3 degrees per 15 m/s of the power's steady speed, plus 0.5 degrees per m/s^2 of acceleration or 0.8 per m/s^2 of deceleration. A surge kicks the bow above its steady trim and it settles in 1-2 s; a power cut or a hard drop digs the bow in, level again once slow. The view also gets a brake intensity (deceleration / 10 m/s^2) and the wake (speed and throttle).

While driving the trainer is in SIM with a gentle water drag: course grade 0.5 % + 2 (v / 15 m/s)^2, at most 3 % (inside the governor's warm-up range), the same feel at the same share of cruise speed; sent when it moved 0.1 % and at most twice a second, 0 % while stopped, casting or waiting.

## 4. Free Roam flow (per rider)

DRIVE, then DRIFT when `P_eff` falls under 20 %, then MENU once stopped. The menu is light, small chips near the boat:

- **Cast** at one of up to three fish hints drawn for this spot (species by rarity from the zone, depth from the species, `near_floor` fish 3-10 m above the floor; stopping 60 m from the last hints draws new ones). A hint's size sets the fish's weight.
- **Drive on**, or pedal at >= 80 % for 2 s.
- **Turn around** flips the heading. Driving into the dock wall or the edge opens the menu.

Input: left / right and confirm (keyboard, gamepad). With pedal navigation on (`PlayerSlot.pedal_nav`, BRIEF 3.5) the menu also scans every 1.6 s, a `surge` confirms and it auto-confirms after two scan cycles; off, nothing scans or auto-confirms. Autopilot riders and bots pick after 1 s and never drive on by pedaling.

**Cast** takes 1.5 s + depth / 60 m/s (at most 8 s), then **wait**: bites come at 1 / 25 s in the lure band (preferred cadence + the species offset +- 8 rpm), a quarter of that outside it, never in the first 5 s at depth, forced at 90 s, never in the drive-out, after time-up or during a stagger. Confirm reels the line in. The hook sets itself (no strike prompt).

**Fight, then Landing**, then back to the menu with fresh hints. There is no mandatory recovery between fights; BRIEF 4.6 limits still bind. At the bite the rules build the fight from the hooked hint and replan the rest of the plan: Fight (WORK, ERG, open-ended), Landing (WORK, SIM flat, 30 s), a new Roam (FREE, SIM), then end the Roam phase in the same tick. Each fight is therefore a real phase the PlanValidator checks and the FIT records as a lap.

**Time up:** no new bites and lines come in; a fight in progress may finish, at most 5 more minutes; then the session ends with `trip_over` and the cool-down.

## 5. Map and species

`content/fishing/map.json` (18 000 m, validated at load): dock 0-600 m, shallows 600-4000, reef 4000-8000, shelf 8000-12000, deep 12000-16400, abyss 16400-18000, with a floor profile from 3 m at the dock to 620 m, dropping away at 16 800 m. The ocean pours off a waterfall at the edge; boats stop at 17 900 m. At 100 % the reef is 4.5 minutes out, the shelf 9 and the deep 13. Decorative landmarks (`landmarks`, drawn by the view and on the minimap): the harbour lighthouse (240 m), a reef arch (6 km), whale bones on the shelf edge (11.6 km) and a sunken wreck in the deep (14.2 km).

| Species | Zone | kg | Pull % FTP | T_nom s | max_s | Runs / jumps (peak %) |
| --- | --- | --- | --- | --- | --- | --- |
| Mackerel | shallows | 0.5-2 | 60-66 | 50-80 | 120 | none |
| Sea bream | shallows | 1-4 | 64-72 | 60-100 | 140 | 1 run |
| Snapper | reef | 3-12 | 74-82 | 80-140 | 180 | 1-2 runs |
| Mahi-mahi | reef | 7-20 | 82-88 | 100-170 | 210 | 2-3 runs |
| Yellowfin tuna | shelf | 30-90 | 88-94 | 150-230 | 270 | 2-3 runs |
| Wahoo | shelf | 15-50 | 90-97 | 120-190 | 230 | 2-3 runs, peak 104 |
| Swordfish | deep | 80-250 | 93-99 | 180-280 | 330 | 1-2 jumps at 104 |
| Blue marlin | deep | 150-400 | 90-97 | 240-340 | 420 | 2-3 jumps at 104 |
| Giant grouper | deep, near the floor | 120-300 | 105-110 | 180-270 | 300 | none |
| Oarfish (legendary) | abyss | 200-500 | 100-104 | 220-280 | 300 | 2-3 runs, peak 108-110 |

`content/fishing/species.json` holds the rest (band offset, `d_max`, depth, rarity, run lengths). A hint's size w in [0, 1] sets weight = lerp(kg), base pull = lo + w (hi - lo) and T_nom = lo + 0.8 w (hi - lo). Many small fish near the dock and a few giants far out both pay (section 7).

## 6. The fight

Rules are pure `step(state, inputs, dt)` at 0.05 s with seeded streams (`FishingRandom` from `ctx.seed`), never wall-clock time. Each rider's phase comes from `frame.phase`. Cadence goes through an EMA (tau 1 s); stale cadence (> 3 s) freezes the meters. The band is published with `ctx.directives.cadence_band`.

- **State:** stamina S (1 fresh, 0 spent), distance d and depth z. d moves toward 10 + (d_max - 10) S (toward d_max on a run), at most 4 m/s out and 2 m/s in.
- **Tension band:** center = preferred cadence + species offset + run shift - 10 (1 - S) rpm; low edge = max(65, center - 8); width 16 rpm (22 relaxed); the center slides at most 3 rpm/s.
- **Meters:** strain fills at 1/6 per s below the band, slack above it; the other drains at 1/12 per s. Full strain snaps the line; full slack throws the hook.
- **Tiring:** in band dS/dt = -min(1.2, power / applied target) / T_nom; out of band +0.25 / T_nom. Run k of n fires at S = 1 - k / (n + 1).
- **A loss costs the fish, never the work.** After a snap or a thrown hook a same-species replacement hooks itself 5 s later in the same phase, 25 % lighter and never a trophy.
- **Staggers:** rescue, AFK and pause freeze S, the meters and the band and let the fish swim out; play resumes 10 s after the cause ends.
- **Landing:** the fight ends at S = 0 with d <= 10 m (`end_phase`), or at `max_s`. The 30 s Landing is SIM flat with virtual gears: a 15 s gaff sprint (the meter fills by the integral of max(0, P - CP) / (0.4 CP 15 s), counted only at P >= 1.2 FTP; full is a Trophy), then easy spin as the fish comes aboard. Autopilot never sprints. One last-run haptic (+3 % for 5 s, 3-6 s in) goes only to riders with haptics on and never in the plan's first 300 s.
- **Pull changes:** a new multiplier every 8-16 s inside the phase's `range_pct`, ramped over 3 s in six steps 0.5 s apart (at most 25 W/s); a run or jump holds its peak until its scheduled end.

## 7. Points, results, progression

- **Points** = round(15 + 12 kg^0.55) x grade (Trophy 1.5, Landed 1.0) x hookup. A 1 kg mackerel scores 27, a 13 kg mahi 64, a 60 kg tuna 128, a 200 kg grouper 237.
- **Free Roam:** most points wins; the rows show the rank. **Workouts** are co-op: Double Hookups (fights overlapping for 10 s or more) score x1.5, x2 and x2.5 for two, three and four; team points over expected points give the grade S >= 1.25, A >= 1.0, B >= 0.8, C >= 0.6, else D.
- **Rows:** kJ, average %FTP, time in band, fish landed, trophies, lost lines, biggest fish, longest fight, points, rank, farthest distance out. The results are identical on every peer.
- **Strava:** `ride_tag` is "Free Roam N min" or the workout's name; each rider's `ride_lines` give fish caught, biggest fish with kg, points, rank and the farthest distance out. No heart rate.
- **XP:** 1 per kJ, 10 per fish, 25 per trophy, 50 per new species record. Every 500 XP unlocks the next item of `content/fishing/cosmetics.json` (line colours, canopy patterns, hull trims, a trophy pennant). Progress (XP, unlocks, catch log, species records) is saved per rider through `ctx.progress`; only a `summary` intent goes to the host.

## 8. Workouts

They keep a plan: a ride out (ERG 50-65 %, 300 s), then Trolls (ERG at `reel_pct`) and Fights with Landings. Base rolls each rider's fights from the seed (fight budget 25 % of fishing time, nothing above 100 %); Threshold and e2e share one schedule. The boat still drives from the rider's real power. It trolls across an endless map generated from the seed (segments of 2.4-4.4 km; each reef, shelf or deep segment carries its landmark at a seeded spot), so nobody turns around. The plan's fish bite on their own and the hook sets itself: Base after R_min with a hazard, forced at R_min + 240 s, none if the fight would end more than 5 minutes after fishing ends; scheduled trips 4 s before the Troll ends. Bots may join as co-op riders.

## 9. Bots, Autopilot, zero input

Bots are platform riders at their slot FTP. Each draws one strategy per session from `ctx.rng` (`FishingAutopilot.STRATEGY_TABLE`: target zone, drive effort, pick rule, how often it moves on): **vibe** (low effort, the shallows), **small** (many small fish near the dock), **mixed** (shallows and reef, the biggest fish on offer), **big** (hard to the deep or the abyss, only deep fish). Autopilot humans play `mixed`. Autopilot never changes effort targets: a human's power is their own and a bot's follows the published band. Every session plays to the end with no input (BRIEF 2.5).

## 10. Safety (BRIEF 4.6)

- Each fight and the driving phases pass the PlanValidator; nothing exceeds 110 %, and ramps stay under the governor's slew.
- The warm-up is the fixed 300 s drive-out: SIM, no ERG, no haptics (4.6.8).
- Phases longer than 300 s stay <= 105 %. The over-105 % budget is one fight per session: the giant grouper (105-110 % for 3-4.5 min, `max_s` 300) or the oarfish's runs; a later giant caps at 105 %. A run or jump is at most 30 s above 105 %.
- A fight's `min_s` is at least 30 s and every Roam follows a 30 s Landing, so ERG and SIM switches stay 30 s apart.
- The band's low edge is at least 65 rpm, above the 45 rpm rescue trigger. The pause on not pedaling (BRIEF 3.5) pauses a rider's ride timer; the governor's own rules are unchanged.

## 11. Multiplayer

The host simulates every rider at 20 Hz and sends 10 Hz snapshots (schema v2, at most 2 KB for 4 riders): one row of 32 integer columns per rider (boat with signed trim and brake, menu, lure, fish, meters, flags, hints), a team row and the last five catches. Events (v2) go to every peer in order: `cast`, `bite`, `hookup`, `run`, `jump`, `snap`, `thrown`, `replacement`, `landing`, `landed`, `double_hookup`, `turn`, `time_up`, `trip_over`. Clients interpolate other boats 100 ms behind and the host owns the meters.

## 12. Look and sound

Hand-authored pixel art at 640x360 in the style of Slynyrd's "Nemk": one cool palette (`FishingPalette`, 12 colours plus one brass accent and four muted player colours), nothing darker than #1c4d65, flat top-lit planes, no outlines, dither, speckle or rotation, lines in uniform pixel steps. Sky #cedfd2; a 2 px foam surface line; water #b6d7cf, #91c2c2, #6fa3a6, #4b858f by depth; floors one step darker than the water above. The signed trim picks one of eight hand-built hull poses (five bow up to 8 px, two braking with the bow down, level), with spray under a raised forefoot and a foam mound when braking; the rider leans into sprints. The floor is built per zone from terraces, drops, short slopes, mounds and seeded prop clusters (harbour moorings, shallows seagrass and starfish, reef coral and the arch, shelf kelp, deep whale bones, caves and the wreck, abyss basalt); landmarks also show on the minimap. The fishing line is a verlet rope drawn as one curve from the rod tip to the hook; each rod is in its player's colour. Sprites are palette-indexed grids (`fishing_art_grids.gd`, written by `fishing_write_sprites.gd`); scenery is drawn in code; a palette-map shader keeps every pixel in the palette. The HUD uses a hand-made 5x7 pixel font (`fishing_font_grids.gd`) and `HudSpec.palette` puts the kit widgets on the same grid and palette. `tests/games/fishing/art/style_check.mjs` measures screenshots against the style rules.

The boat has a brass pedal drivetrain (rider on a saddle, chain, gears, flywheel, shaft and screw propeller driven by cadence) and a fixed rod on a winch. Driving and fishing are visible: the clutch lever flips, the prop spins down while the winch drum turns, the rod tips up to its fishing angle. The wobbler dives; the line is bright and taut above water, kinked at the surface and darker below. Audio is synthesized (drivetrain hum, winch clicks, drag, clutch clunk, bite bell, snap, landing fanfare, horn, surf).

## 13. Gates

Unit and property tests under `tests/games/fishing/`, the script check, gdlint and gdformat, `tests/sdk/test_conformance.gd` at 1 and 4 players, the simulation matrix (`bash tests/games/fishing/sim/run_sims.sh`, checked with `check_sims.mjs --fit`: Free Roam solo, four riders, bots, zero input, an unverified low FTP, a rider who stops pedaling, the three workouts, determinism and every FIT), `node tools/e2e/run.mjs --games=fishing`, and the full `tools/run_tests` at or above the previous green count. `src/games/fishing/HARDWARE_TEST.md` is the real-trainer checklist; known gaps are in `src/games/fishing/BACKLOG.md`.
