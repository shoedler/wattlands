# Decisions: fishing

Short ADRs for Turbo Reel (game id `fishing`): date, decision, alternatives, reason. "Brief" is docs/games/fishing.md; "SDK n" is a section of docs/GAME_SDK.md. Where the brief and the code or the SDK disagree, the code and the SDK win.

## 2026-10-24 Free Roam fights are built at the bite: replan, then end_phase

- Decision: a Free Roam plan starts as a fixed 300 s drive-out (WARMUP SIM, grade_source game) and one open-ended Roam phase (FREE SIM game, min_s 5, max_s = play left + 5 min + 60 s). At each bite the rules build the fight from the hooked hint (FishingPreroll.roam_slot), call `ctx.directives.replan` with Fight (WORK ERG, open-ended), Landing (WORK SIM flat 30 s) and a new Roam, and `end_phase` in the same tick; the pending plan swaps in at that phase change.
- Alternatives: a pre-rolled plan as in v0.1 (the species and size the rider picks are unknown in advance); ERG blocks inside one long SIM phase (directive SIM blocks are 10-30 s, and the PlanValidator could not see the fights).
- Reason: every fight is a real ERG phase the PlanValidator checks (SDK 7.2) and the FIT records as a lap.

## 2026-10-24 No fish bite in the first 5 minutes of Free Roam

- Decision: the drive-out is a fixed phase, so no Fight can start before 300 s; a rider may stop and cast, and the bite comes once the Roam phase opens. roam_N counts N minutes from the start, the drive-out included.
- Alternatives: fights capped at 65 % during the warm-up. The validator places open-ended phases at min_s, so later fights would also land in its warm-up window and be capped long after real time passed 300 s.
- Reason: BRIEF 4.6.8 holds by construction and the 105 % accounting stays simple.

## 2026-10-24 The 105 % budget is the PlanValidator's, mirrored in the rules

- Decision: each rider keeps acc105_s, the seconds above 105 % its plan has accrued (open-ended phases at max_s, the validator's rule). A fight whose max_s would push it past 300 s caps every target at 105 %. Only the giant grouper (pull 105-110 %, max_s 300) and the oarfish's runs (108-110 %) go above 105 %, so a rider gets one such fight per session. Species with max_s over 300 s cap at 105 % (FishingPreroll._top). A slot whose base pull stays above 105 % has hold_above_105: its pull changes may stay above 105 % within its range; every other slot keeps pull changes <= 105 % and passes 105 % only in runs (<= 30 s each, <= 90 s per fight).
- Alternatives: insert a 120 s recovery after a hard fight (the user decided against mandatory recovery); refuse the second giant.
- Reason: no replan is ever refused, and the governor's own 4.6.1 limits never need to clamp a fish.

## 2026-10-24 Boat physics and the driving load

- Decision: thrust = P_eff / max(|v|, 1 m/s), drag 1.6 v|v| + 2 v, mass 400 kg: 250 W of P_eff holds 5 m/s and crosses the 9 km map in 30 min. With the prop free a linear drag of 80 N per m/s stops the boat within 15 s. The trainer load while driving is the course grade 0.5 % + 0.08 v^2, at most 3 % (inside the governor's warm-up range), sent when it moves 0.1 % and at most twice a second; 0 % while stopped, casting or waiting. Pitch: 2.5 deg per 100 % throttle plus 20 deg per m/s^2, at most 14 deg. Wake: 0.6 |v| / 7 + 0.4 x throttle.
- Alternatives: the platform SpeedModel (cycling physics, wrong feel for a boat); the trainer's own speed.
- Reason: P_eff makes the lobby's scaling mode the fairness choice; small grades keep the resistance gentle.

## 2026-10-24 Roam flow: drift, the light menu, auto-hooking bites

- Decision: under 20 % FTP-equivalent the prop disengages (DRIFT); stopped, the menu offers up to three fish from the zone (species by rarity, depth from the species, near_floor fish 3-10 m above the floor), Drive on and Turn around. Pedaling >= 80 % for 2 s from the menu drives on. Casting takes 1.5 s + depth / 60 m/s (<= 8 s); bites come at 1 / 25 s in the lure band (a quarter outside), never in the first 5 s, forced at 90 s. The hook sets itself (no strike prompt). Driving into the edge or the dock wall opens the menu.
- Alternatives: the v0.1 strike prompt (a missed strike stalls a zero-input rider).
- Reason: the spec's DRIVE -> DRIFT -> STOPPED -> CAST -> WAIT -> FIGHT loop with the fewest states.

## 2026-10-24 pedal_nav decides scan, surge and auto-confirm

- Decision: PlayerSlot.pedal_nav true: the menu scans every 1.6 s, a surge confirms and the menu auto-confirms after two scan cycles. False: left/right and confirm only; a surge is ignored. Autopilot riders and bots pick after 1 s. The v0.1 zero-input fallback (play as Autopilot until a deliberate key) is gone.
- Reason: the spec; zero input is pedal_nav or Autopilot.

## 2026-10-24 Autopilot and bots run inside the host rules

- Decision: `autopilot_intents()` returns `[]`. FishingAutopilot plays the menu for Autopilot riders and bots: one strategy per bot from ctx.rng in configure (vibe, small, mixed, big; Autopilot humans play mixed), a stop x inside the strategy's zone (falling back to a nearer zone when it is out of reach in the time left), cast by its pick rule, move on or turn around. An Autopilot rider's prop disengages only at its stop, whatever its power. Bots ride the power band the rules publish (`ctx.hud.power_band`): the strategy's effort while driving, 45 % otherwise, 130 % in the Landing's gaff window (vibe never sprints).
- Alternatives: autopilot intents from the module (the platform never calls it for Autopilot-off humans, and menu timing lives in the rules).
- Reason: deterministic sims and one place for every choice.

## 2026-10-24 Points by weight

- Decision: points = round(15 + 12 x kg^0.55) x trophy (1.5) x hookup (workouts only). A 1 kg mackerel scores 27, a 13 kg mahi 64, a 60 kg tuna 128, a 200 kg grouper 237.
- Alternatives: 20 sqrt(kg) (giants dominate); linear in kg.
- Reason: the base term pays many small fish near the dock, the exponent pays the giants far out; the bots' sims (check_sims R3) keep both strategies within a factor of 2.5.

## 2026-10-24 Workouts on the endless map, trolling

- Decision: workouts keep their pre-rolled plans (Ride out, Troll, Fight, Landing). The Troll phase drives the boat with the lure out behind it (no menu); the plan's fish bites (Base: after R_min with the hazard, forced at R_min + 240 s, refused by last call; Threshold and e2e: 4 s before the fixed Troll ends) and hooks itself. The map is FishingWorld.endless_for(seed): the zones cycle with seeded lengths, no edge. Double Hookups stay (co-op); Free Roam has none (competitive). Frenzies are gone.
- Reason: the spec (fish from the plan, nobody turns around) with the v0.1 bite rules kept.

## 2026-10-24 One snapshot row per rider (v2)

- Decision: snapshot v2 drops lanes: 31 integer columns per rider (boat, menu, lure, fish, meters, flags), the team row and the last five catches; the worst case at 4 riders stays under 1 KB. Clients restore the fish's jump from F_JUMP (FishingFishState.jumping). The view keeps its own interpolation from the `snapshot_applied` signal.
- Reason: the shared ocean; ints only, under 2 KB.

## 2026-10-24 The view and HUD load by path

- Decision: FishingGame.make_view and hud_spec load `view/fishing_view.gd` and `hud/fishing_hud.gd` with load() instead of naming their classes.
- Reason: the module, the rules and their tests parse while the view is rebuilt; the module has no compile-time dependency on presentation code.

## 2026-10-24 Strava lines per rider

- Decision: results() sets ride_tag ("Free Roam N min" or the workout's name) and each row's "ride_lines" (fish caught, biggest fish with kg, points, rank in Free Roam with 2+ riders, furthest out in km); res.ride_lines holds the host rider's. Results are never changed per peer.
- Alternatives: apply_progress replacing res.ride_lines with the local rider's (the e2e harness requires identical results on every peer).
- Reason: GameResults carries one ride_lines list but every peer uploads its own ride; the platform can read the local row's "ride_lines".

## 2026-10-23 Fight model kept from v0.1

- Decision: the tension band (preferred + species offset + run shift - 10 (1 - S), sliding <= 3 rpm/s; low edge max(65, centre - 8), high = low + 16, or 22 relaxed), strain and slack (fill 1/6 s, drain 1/12 s), tiring (in band -min(1.2, P / applied target) / T_nom, out of band +0.25 / T_nom), runs at S = 1 - k / (n + 1), replacements after a snap or thrown hook (x0.75 kg, never a trophy), the 15 s gaff sprint (max(0, P - FTP) / (0.4 FTP x 15 s) while P >= 1.2 FTP) and one 3 % last-run haptic 3-6 s into the Landing (never in the first 300 s, to an opted-out, rescued, AFK, paused or stale rider). Fight min_s = max(floor(0.8 T_nom), 30). The cadence EMA (tau 1 s) starts at the first sample.
- Reason: the fight mechanics were judged good and stay (spec).

## 2026-10-23 Every published band keeps 65 rpm and its width

- Decision: every band (lure, tension) has its low edge at max(65, centre - half) and its high edge low + width; the width is rounded on its own so a published band keeps it.
- Reason: BRIEF 4.6.3: never coach a rider toward the 45 rpm rescue trigger, whatever the preferred cadence (30-160 rpm).

## 2026-10-23 Pull scheduler models the governor channel

- Decision: FishingPullState tracks the ERG channel as the governor holds it (target, expiry back to the base pull). Pull changes every 8-16 s ramp in >= 6 steps 0.5 s apart, no step adding more than 12.5 W (25 W/s); every directive is >= 0.5 s after the previous one. One run at a time (jumps also 90 s apart); a run above 105 % reserves its whole length. While staggered nothing is sent and queued ramps drop; the pull clock stops from a run's start to its end and from a stagger's start to 10 s after its end. The rules forward every stagger edge whatever the action.
- Reason: BRIEF 4.5 (2 writes/s) and SDK 8 expiry semantics; a stagger outliving its fight must not mute the next one.

## 2026-10-23 Staggers

- Decision: a stagger is on while rescue (on_rescue or telemetry), AFK (on_afk, telemetry, or stale telemetry: age > 3 s or disconnected) or the platform's pause is on. Meters, S and the band freeze, the fish swims out at 1 m/s, no bites, runs that come due are skipped, play resumes 10 s after the cause ends. A paused or AFK boat drifts.
- Reason: SDK 14 (a stagger, never a wipe); the spec (a paused boat drifts).

## 2026-10-23 e2e mackerel band offset +3

- Decision: e2e_2min's scheduled mackerel uses band_offset 3.
- Reason: the e2e harness and conformance ride a constant ~90 rpm; with +3 the band runs from [85, 101] at S = 1 to [75, 91] at S = 0, so that rider stays in band and lands the fish in T_nom.

## 2026-10-23 Event toasts: one routing rule

- Decision: team-wide event toasts (landed or trophy, double hookup, time up) go out from the host with peer 0; a rider's own (hookup, snap, thrown, replacement) are raised only on that rider's peer (the host with ctx.local_peer, a client in apply_event).
- Reason: SDK 10.2 routing with no duplicates.

## 2026-10-23 Summary intent, progress and catch-log dates

- Decision: configure sends the local rider's summary (XP, species records, equipped look as 1-based per-kind cosmetics indexes, 0 = default) on every peer; the host applies it, exempt from the 5-per-second intent limit. Results rows carry catches and records so every peer writes its own progress (xp, unlocks, equipped, records, trophies, catch_log, sessions). The catch-log date is the UTC day of the session id's nonce, never a clock.
- Reason: SDK 15; determinism.

## 2026-10-23 Allowed clamps in the sims

- Decision: applied records and trace rows may show only slew, floor, unverified, rescue, coasting, haptic_intensity and warmup; switch_ramp, paused, the SIM grade bounds and haptic_pull (a surge's pull, exempt from the 105 % long-phase cap) are noted. ceiling, long_phase, limit_105 and limit_120 fail by name.
- Reason: the plans must never need the governor's caps; rule names from wl.gd.

## 2026-10-27 The boat is a rigid body on the water

- Decision: FishingBoat simulates surge, heave and pitch with forces (turbo thrust 150 x P_eff / (u + 6 m/s), hull drag tuned to keep 15 m/s x (P_eff / 250 W)^0.6 in displacement, a displacement hump, line tension) and force-driven spring-dampers, plus a planing latch (on at 11.9 m/s, about 70 % FTP-equivalent; off under 11.3 m/s) that cuts drag for a 7 % faster cruise. The prop depth is part of the state and never above 0.2 m.
- Alternatives: keep the scripted trim spring with kicks; a pose table by speed.
- Reason: the owner asked for a boat that reacts to pedalling exactly; poses, wake and tow follow from one model the view reads through the snapshot.

## 2026-10-27 Big-fish surges as an ERG haptic pull

- Decision: a run or jump by a fish of 30 kg or more requests haptic_pull +50 % FTP for 2 s (haptics on, not in the first 300 s or a stagger, one per 15 s) and shows F_SURGE for 2 s either way. The governor applies it: the sims and the e2e check want every surge pull applied (at most 3 s and +50 % FTP) or dropped only for haptics off, warm-up, the haptic cooldown or an unsafe rider, and at least one applied across the matrix.
- Alternatives: a SIM haptic grade (not available in an ERG phase); a target change (would be a ride target, not a feel).
- Reason: owner-approved BRIEF 4.6.6 amendment; the governor bounds and spaces it.
