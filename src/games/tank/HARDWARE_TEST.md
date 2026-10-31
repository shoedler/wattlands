# Torque Company: real-trainer checklist

The game's own checklist for a real KICKR CORE (BRIEF 4.7). `docs/HARDWARE_TEST_PLAN.md` holds the firmware notes, the panic and stop advice, the log format and the platform checks (probe, connect, SIM flat, ERG, slew, rescue, coasting, panic and the mode-switch step), and links here. Nothing here ran during the build: every automated run used MockTrainer with the hardware lock set. Work through the platform plan first and stop at the first failed safety check.

Sections 1 to 14 check what the simulations already assert (`tests/games/tank/sim/`) against a real trainer. Section 15 lists what a simulation cannot judge at all.

Tank reaches the trainer only through `ctx.directives`, so everything below is the governor acting on Tank's plans and directives. What Tank asks for, by seat (% FTP; grades before your difficulty setting):

| Seat | Depot (warm-up) | Advance | Holding action | Boss | Roam |
| --- | --- | --- | --- | --- | --- |
| Drive | SIM terrain 0 to +2% | SIM terrain -3 to +6% (2 Hz) | SIM flat (dig) | SIM flat | SIM valley grade -3 to +5% |
| Gun | ERG 50 ramping to 65 | ERG 55 to 100 (the bank) | same | same | ERG 55 to 85 |
| Loader | SIM flat, boiler 3% x pressure | SIM flat, boiler up to 8% x pressure | same | same | same |
| Lights | ERG 50 ramping to 65 | ERG 65 to 80 (the searchlight load) | same | same | same |
| Secondaries | SIM flat | SIM flat | SIM flat | SIM flat | SIM flat |
| Repairs | ERG 50 ramping to 65 | ERG 55 to 70 (the repair load) | same | same | same |

Checkpoints are ERG 50% for everybody; the platform appends a 180 s cool-down at 50% (Tank sends nothing in it). Haptics (hit +2.0% for 1.5 s, boss hit +3.0% for 2 s) go only to riders in a SIM phase, never in the first 300 s, a warm-up or the cool-down. Sprints ("Surge to evade", "Surge to overpressure") send nothing: they are your own effort in the phase's SIM. **The difficulty option changes none of this** (section 10).

## 0. Setup

- [ ] Drop the locks only by hand, as the platform plan says. From source, PowerShell: `tools/godot.ps1 --allow-hw --timeout=14400 --path .`; Git Bash: `tools/godot.sh --allow-hw --timeout=14400 --path .` (without `--timeout` the wrappers stop a run after 20 minutes). `--allow-network` only for the Strava step. An exported build never sets the locks. Never pass these flags from an automated run.
- [ ] KICKR CORE, current firmware (before 1.5.5 it could spike on mode switches). Close Zwift and the Wahoo app. Know how to stop: hold Backspace for 1 s (panic), or stop pedaling.
- [ ] Set your FTP in the profile. Do the whole checklist **verified** (a test result), then repeat sections 1, 3 and 7 **unverified**: every ERG target is then x 0.85 and never higher.
- [ ] Sessions: `ashfall_road` 30 to 41 minutes, `ambush_15` 13 to 17 minutes, `drill` under 6 minutes with its cool-down. To ride every seat with one trainer, fill the crew with bots in the lobby or join clients on `--mock-trainer=erg`, then move seats yourself with < > and OK.
- [ ] Targets at an example FTP of 250 W (scale to yours; the unverified column is x 0.85):

| What | % FTP | Watts at 250 | Unverified watts |
| --- | --- | --- | --- |
| Checkpoint ERG | 50 | 125 | 106 |
| Gun, Lights, Repairs depot ramp | 50 to 65 | 125 to 162 | 106 to 138 |
| Gun fight, bank full | 55 | 138 | 117 |
| Gun fight, bank empty | 100 | 250 | 212 |
| Gun roam, bank empty (the roam's cap) | 85 | 212 | 181 |
| Lights fight, nothing in range | 65 | 162 | 138 |
| Lights fight, always a target in range | 80 | 200 | 170 |
| Repairs, hull full | 55 | 138 | 117 |
| Repairs, hull always below its maximum | 70 | 175 | 149 |
| Evade sprint (the sprint rule) | 120 or more | 300 | 300 (sprints are raw watts, never x 0.85) |
| Floor (never below) | max(30%, 50 W) | 75 | 75 |

- [ ] SIM grades are stacked by the governor: (terrain or boiler) x difficulty setting (default 50%) + gear offset, clamped to your grade range (default -5 to +10%), plus the haptic (x its intensity setting, at most +3% for at most 8 s, 15 s apart), total -10 to +16%. Note your settings before you start.
- [ ] Use the log template of the platform plan per step, plus this running log for a full ride (one line per segment start, per seat move, per switch and per event worth noting):

```text
t (mm:ss) | segment | seat | trainer mode | target W or grade % | power W | cadence | note
```

## 1. Depot: the first 300 s (BRIEF 4.6.8)

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 1 | Start Ashfall Road on Drive and pedal from 0:00 | SIM from the first second. Grade follows the depot's terrain 0 to +2% (before your setting), never above +3% total in the first 300 s, never below -2%. No haptic | |
| 2 | Sprint at 130% FTP in the depot | Nothing happens on the trainer, no "Surge to evade" prompt: evade and Overpressure are off in WARMUP phases and the first 300 s | |
| 3 | Repeat on the Gun, the Lights and Repairs | ERG 50% rising smoothly to 65% over 300 s (125 to 162 W at FTP 250), slewed, never above 65%. No pattern, no haptic | |
| 4 | Repeat on the Loader | SIM flat. The boiler grade rises with pressure to +3% (before your setting) and never above it, even if you sprint; it drops to 0 at once at a stow and stays 0 with the rack full | |
| 5 | Repeat on the Secondaries | SIM flat, no pattern | |
| 6 | Move seat in the depot, ERG to SIM and back, 30 s or more apart | Ramped switches, each within the warm-up's limits: grade never above +3%, ERG never above 65% | |

## 2. Drive and the terrain

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 7 | Stage 1 Advance (5:00) on Drive | SIM. The resistance follows the road under the tank x your setting, updated about twice a second, smooth, no surge at the phase start. Speed is the SIM speed model | |
| 8 | Stage 2 and 3 Advances (down to -3%, up to +6%) | Same, within your grade range | |
| 9 | The Advance's objective (the halt line) or `max_s` 300 s | The tank holds ("Regroup") until `min_s` 90 s. A phase that runs to `max_s` is an overrun: the tank is towed to the line, score drops, the trainer does nothing unusual | |
| 10 | Holding action on Drive | SIM flat, no ERG block. In band (76-105% FTP) the berm grows; your power band shows | |
| 11 | Holding action -> Checkpoint | ERG 50% through the platform's ramp, no spike | |

## 3. Gun: the bank is the ERG target

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 12 | Advance on the Gun, no enemy in range | ERG at 55% (138 W at 250) while the bank is full | |
| 13 | An enemy comes in range, the bank drains | The target climbs with the drain: 55 + 45 x (1 - bank/100) %, never outside 55 to 100%. Each update of at most 10 points arrives as three sub-steps 1 s apart, so the rise is at most 3.3% FTP per second (8.3 W/s at 250), well under the 30 W/s slew. Decreases are immediate. Log the target every 5 s through one fight | |
| 14 | Lay on a far target at 2000 m or more: elevation costs the bank | A step of at most 10 points, not a jump | |
| 15 | Boss (phase `max_s` 360 s, over 300 s) | Targets stay at or under 100%, below the 105% cap that long phases get. No duration counter runs | |
| 16 | After the fight | The target is back at or below 65% within 120 s (the next phase, a checkpoint, is 50%) | |
| 17 | Your own power | In band needs power at 95% of the applied target and cadence 60: the room lamp lights and the bank charges | |

## 4. Loader: the boiler grade

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 18 | Advance on the Loader, ride 90% FTP with the rack not full | SIM flat, mode grade 8% x min(pressure, 1) before your setting. It rises at most 0.5% a step, at most once a second. One shell about every 7 s at 250 W | |
| 19 | A shell stows | The grade resets at the stow; with the rack full the grade is 0 and the cadence band 50-120 | |
| 20 | Surge in the 5 s "Surge to overpressure" window after a stow (past 5:00, SIM WORK) | Sprinting builds the shell 100 to 150%; the grade holds; a double-damage shell stows at 150% | |
| 21 | Checkpoints | The trainer is in ERG 50% with no boiler grade | |

## 5. Lights

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 22 | Advance on the Lights, nothing in range | ERG 65% (162 W at 250) | |
| 23 | Enemies in the gun's range | The load lifts the target: 65 + 15 x duty %, never outside 65 to 80%, on the bank's schedule (at most 3.3% FTP per second). Log it every 5 s through one fight | |
| 24 | The fight ends | Back at or below 68% within 60 s; the next checkpoint is 50% at once | |
| 25 | In band against out of band | Lit: the searchlights burn and fade over 0.4 s with a 2 s hold; dark: the rooms fall to backup lighting. The trainer does not react to either | |

## 6. Secondaries and near threats

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 26 | A recon car or a tankette bursts from the bushes (crews of 2 or more) | "Ambush: Secondaries". Nothing changes on any trainer | |
| 27 | Move to the Secondaries | SIM flat. The bow guns fire 2 rounds per pedal revolution (the dial reads 2 x your cadence); in band (76-105% FTP) they slew faster and hit more | |
| 28 | Leave the threat alone | It flees; "It got away"; no score penalty, no effort change | |
| 29 | Its rounds hit the hull | Chip damage. The trainer changes only if a hit reaches the haptic's `min_damage` (step 39) | |

## 7. Repairs

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 30 | Advance on Repairs, hull full | ERG 55% (138 W at 250). Nothing is rebuilt; the hammer turns on your cadence | |
| 31 | Hull below its maximum, stay in band | The target rises to 55 + 15 x duty %, never outside 55 to 70%, at most 3.3% FTP per second. The hull rises, the card shows the rate. The hammer strikes once per revolution | |
| 32 | The hull reaches its maximum | The rate stops; within about 10 s the duty falls and the target eases back to 55%, decreases immediate | |
| 33 | Cadence below 45 rpm for 3 s with the applied target at 60% or more | Rescue at 50% FTP; the repair stops; the plan continues; 10 s ramp-back. Under a 60% target rescue does not arm | |
| 34 | Move from Drive to Repairs 5 s after a sprint | ERG entered at or below the planned target or the floor, never at your sprint power, slewed up at no more than 30 W/s | |

## 8. Seat moves and switches

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 35 | Pick a seat by hand (< > on every seat, OK sits, back closes) in a fight and right after a stage change | The seat is yours at once. Same mode: the new target or grade within a second. ERG <-> SIM: at once if your last switch is 30 s old, else "ERG in N s" counts down and it switches then, or "ERG at stage end". Never a spike | |
| 36 | Move Gun -> Loader -> Gun within 10 s | "SIM in N s" shows, then disappears: no switch at all, the bank pattern carries on | |
| 37 | Every SIM -> ERG entry | Grade 0, then ERG at min(your 3 s power, the planned target), then up at no more than 30 W/s | |
| 38 | Every ERG -> SIM entry | ERG target set to min(applied, your 3 s power), then SIM at grade 0, then the stacked grade: no jolt. Log every switch of a full ride: each 30 s or more from the next | |

## 9. Haptics (BRIEF 4.6.6)

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 39 | Take a hit in a SIM phase past 5:00 | About +2.0% x your intensity setting for 1.5 s on top of the stacked grade, then back | |
| 40 | A Behemoth main-gun hit | +3.0% x intensity for 2 s to every rider in SIM | |
| 41 | An evaded shot | Nothing is felt: the shot missed | |
| 42 | Two hits within 15 s | Only the first is felt | |
| 43 | Hits while in ERG, in the depot, in the first 300 s, in the cool-down, or under a tow | Nothing is felt, ever | |
| 44 | Turn haptics off in the lobby and take hits | Nothing is felt | |
| 45 | The worst stack: Drive on +6% terrain, then a hit | The total never exceeds +16% and your range clamp holds before the haptic | |

## 10. Difficulty changes no effort number

Ride the same seat and content on Easy and on Hard, and log both. Enemy HP, damage, accuracy, counts, telegraph length and the repair rate change; nothing else may.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 46 | Each ride's running log, phase by phase | The same phases, modes, planned targets and ranges. The HUD's difficulty tag differs | |
| 47 | The Gun in a long fight on Hard | The target may sit higher because the fight lasts longer, always inside [55, 100], at the same slew and sub-steps | |
| 48 | The same hit on each difficulty | The same haptic: the haptic reads the shell's damage before the difficulty | |

## 11. Tank lost

On Normal or Hard take the hull to 0: ride the Gun out of band, or leave the crew short. Easy breaks down instead, and you cannot lose.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 49 | The hull reaches 0 in a WORK phase with nobody in rescue or AFK | TANK LOST, the countdown, KEEP RIDING. **The trainer does nothing unusual**: same phase, same clock, no switch, no new FIT lap. Log the target or grade 5 s before and 5 s after | |
| 50 | On Drive during the tow | The grade goes flat, no jolt | |
| 51 | On the Gun, the Lights or Repairs during the tow | The ERG target stays inside the phase's range. No spike | |
| 52 | The stage restarts | The tank is back at the stage's start, the enemies return, the terrain's first point is 0 to 1%. The ride timer never stopped | |
| 53 | Stay in the restarted stage until `max_s` | The platform cuts it there as for any overrun; the next phase starts on plan | |
| 54 | Drop cadence into rescue while the hull is low | The hull stops at 1 HP: no TANK LOST while any rider is in rescue, AFK or dropped (BRIEF 4.6.3). The same at the end of a won stage and in a checkpoint | |
| 55 | Easy: hull at 0 | Breakdown: no movement or fire, damage ignored, the crew's power pays for the repair, then it runs on. No effort change | |

## 12. Ambush, 15 minutes

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 56 | Start `ambush_15` with the difficulty on "Mission default" | Hard's tag, the hull at 90. The full 300 s warm-up runs under section 1's limits before any fight | |
| 57 | Ride it through | Advance, holding action, checkpoint, Behemoth, cool-down; ERG <-> SIM switches 30 s or more apart; 15 minutes nominal, under 17 at worst | |
| 58 | `node tools/fit_check/check.mjs <file> --expect-laps=6` | Clean FIT with 6 laps | |
| 59 | How it feels on Hard | A good workout even after losing the tank once or twice. Note the RPE and how many stages were skipped | |

## 13. Bots

Ride alone with three bots.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 60 | Ride one seat for 10 minutes and watch your log | Your target or grade changes only by your plan and your own moves. A bot's move never changes your effort | |
| 61 | Move to a seat a bot holds | The move lands at once and the bot leaves for another seat; your trainer follows as in step 35 | |
| 62 | On the Gun with the rack low; then with the hull low | A bot goes to the Loader; a bot goes to Repairs | |
| 63 | Stop pedaling on the Gun for 20 s in a WORK phase, then pedal | A bot swaps onto the Gun 10 s after you go on reserve; you land back on the Gun when you return. No split, no replan, your plan untouched | |

## 14. Rescue, AFK, cool-down, FIT, free roam

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 64 | Gun phase, applied target at 60% FTP or more: cadence below 45 rpm for 3 s | Rescue: target 50% FTP, "Dynamo stalled", the gun freezes and the bank stops charging; the plan continues. Cadence 70 rpm or more for 3 s ramps back over 10 s | |
| 65 | The same on the Lights | "Arc generator stalled", the searchlights go dark | |
| 66 | Stop pedaling in a crew game | The floor after 3 s; at 10 s the pause symbol (your ride timer stops, the game runs on), AFK, and the seat runs on reserve (as if 60 W, never in band). All riders stopped: the host pauses for everyone, and it resumes when one rider pedals 1 s at 30 rpm or more | |
| 67 | Stop pedaling solo in the depot | The floor after 3 s, the session pauses at 10 s; 1 s at 30 rpm or more resumes it | |
| 68 | A Gun rider AFK in a fight for 60 s, then back | Log the target when you start again and every 2 s for 20 s: no step faster than 30 W/s, the rescue clears after 70 rpm for 3 s, the seat leaves reserve at once, no mode switch | |
| 69 | **A client's network drops mid-fight for 30 s and rejoins, trainer still connected, on the Gun** | AFK at once, seat on reserve, plan continues; on reconnect the client resumes from the latest snapshot. Log the target before the drop, after the reconnect and every second for 10 s. It can have moved 20 to 40 points; expect a smooth climb at no more than 30 W/s. A jolt, a mode switch or a target above 100% is a failed safety check | |
| 70 | Panic (Backspace 1 s) in an ERG fight and a SIM Advance | ERG off or grade 0 and wind 0 at once; the trainer stays safe until you resume | |
| 71 | Cool-down (180 s) | ERG 50%; the view stays and the tank rolls on; Tank sends no directive; no score | |
| 72 | `node tools/fit_check/check.mjs <file> --expect-laps=12` (`drill` 4, free roam 3) | Clean FIT: one lap per segment, laps adding up to the session, the cool-down last | |
| 73 | Upload to Strava (with `--allow-network`) | A Virtual Ride with power, cadence and a lap per segment | |
| 74 | Free roam, drive-out (0:00-5:00) | The depot's targets and limits; the tank drives along the valley; no enemy appears | |
| 75 | 5:00, the roam phase | One FIT lap boundary, no ERG <-> SIM switch here | |
| 76 | A long roam phase on the Gun | The target rises as the bank drains and never above **85%**, for the whole phase; log it every 30 s. Never above 105% in the trace | |
| 77 | Drive in the roam | -3 to +5% before your setting at 2 Hz, the sign flipping after a turn | |
| 78 | A road's end, or turn by hand (ability 1, or OK on Drive) | The tank stops; a turn is an 8 s stop behind dust; a second within 30 s is refused; the field clears; nothing ever comes from behind | |
| 79 | Time up with an enemy in reach | "Time up: finish the fight"; OVERTIME; once it ends (5 min at most) every rider leaves the roam phase in the same second, then the cool-down; "Free Roam 30 min" on Strava | |

## 15. What the simulations cannot judge

Each item is something a MockTrainer run cannot show. Do them after the rest and note the exact segment and time for each.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 80 | ERG settling with 3.3%/s sub-steps (three sends 1 s apart, every 5 s) at FTP 200 and 300, on the Gun with the bank draining and refilling | The trainer follows without overshoot or hunting; the log settles within a few seconds; decreases immediate. Log the overshoot in watts | |
| 81 | Write coalescing at 2 control writes a second: Drive on terrain at 2 Hz with a hit haptic; the Loader with the boiler at 1 Hz plus haptics | The applied grade lags the newest by no more than about 1 s, no felt stepping; the grade after a haptic is the held grade again | |
| 82 | A holding action on the Gun straight after a sprint: watch the cadence the trainer reports at the SIM -> ERG boundary | The cadence estimate lags after sprints, but the entry must not trigger a false rescue. Log the first 5 s | |
| 83 | Mode switches on current firmware: a full ride with many moves | No power spike or lurch at any boundary. Note the firmware | |
| 84 | **Can you make a shell miss?** The sprint rule on real, noisy, delayed watts, from a 90% FTP ride, per shooter: the telegraph and the flight together are at least 6 s | Count evades tried against made (the results show them), for the light's flank shot, the destroyer, the heavy, and the Behemoth (hold 3 s). Note the reaction time | |
| 85 | Reading the shell screen and the far panel from the saddle at riding distance | Does the red dot on the arc read as "sprint now"? Can you tell the kinds apart at a glance? Is the range plate legible? | |
| 86 | The six cards at 852 x 480 and 1080p from riding distance | Seat name, ERG / SIM tag, in-band strip, BOT and EMPTY readable | |
| 87 | The rescue flag when a rider's Bluetooth drops, or a rider coasts to AFK | Whether it clears on the drop; the ramp-back after a rejoin is smooth. Note what the HUD and the seat show | |
| 88 | Real relay latency and loss, a host and two clients with a bad link, through a holding action and the boss | Intents still aim, fire and overpressure; each client's own prompt follows the telegraph within a snapshot; interpolation is smooth, in the far panel too; a client restarted mid-fight resumes | |
| 89 | A real rider stopping on the Gun for 15 s at 60% FTP or more, then restarting | Rescue, AFK at 10 s, back: the gun is not left frozen | |
| 90 | 60 fps at 1080p on integrated graphics: a 60 s boss fight with far and near enemies at the caps, vsync on | Mean and 1%-low frame times against 16.7 ms. Note the GPU, driver and resolution, and whether the miniature pass turned itself off | |
| 91 | Frame pacing on a real display with nothing else running | Do isolated long frames appear? Log their spacing | |
| 92 | Audio | Section 16, the Listen step: your own station loudest, nothing shrill, nothing clips at a normal volume. Note anything that grates over 30 minutes | |
| 93 | Boiler feel at the default 50% setting: 4.0% peak, then 0 at a stow | The steps are perceptible; "building at 90% FTP or more" is holdable | |
| 94 | The Gun at 98 to 100% FTP for several minutes in a long boss on Hard | Do riders finish it? How rescue or the stagger behaves at the end. Note heart-rate or RPE drift | |
| 95 | The Gun's phase-boundary drop from about 95% to 55% ERG, then the climb | The decrease is immediate and clean; the climb smooth | |
| 96 | Repairs as a calmer seat: ERG 55 to 70% for a whole fight | Does it feel like a recovery of sorts inside a fight, and is the hull's return worth the seat? | |
| 97 | The unguided SIM warm-up in the depot: Drive, Loader and Secondaries ride 5 minutes of SIM with no power band | What riders actually ride; whether it is a sensible warm-up | |
| 98 | A tank loss on a real ride | Does the loss feel fair, with the effort unchanged? Is KEEP RIDING clear? Is the stage's restart motivating or deflating? | |

Log: date, trainer firmware, FTP, verified or not, your settings, crew size, the content, the difficulty, and each step's result with the running log of a full ride attached. Anything that spikes, jolts, exceeds a stated bound or feels wrong is a failed safety check: stop, note the segment and time, and report it.

## 16. Listen

Nobody has heard this audio: every number behind it was measured offline. A machine can check timing and levels, not whether a diesel reads as a diesel or whether an hour of it tires you. Listen with the sound on, over the fan and the trainer, and write down what you hear.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 99 | Before riding, play `build/audio_preview/tank.mp3` (`node tools/audio/preview.mjs --game=tank`) | A diesel with valves, a turbo whistle and crackle, not a monotone rumble; the night forest behind it; the gun, a far boom some time after it, an incoming whistle | |
| 100 | Drive for 10 minutes at 60, then 90, then 110 rpm, with the fan on | The firing stays with the machine on screen at every cadence and stops when you stop; it follows your feet in rate, not in phase (FTMS reports cadence about once a second and no crank angle). No two-second bar you can sing along to. The turbo climbs when you push and is not shrill | |
| 101 | Lift off hard from over band | One blow-off, then the exhaust crackles and fades | |
| 102 | Ten minutes on each of Gun, Loader, Lights, Secondaries and Repairs | Each machine is about as loud as the diesel was, and brighter the harder you push; none reaches the point of grating. Its stroke matches the drawn one: the jars' dump, the chuff, the ladder's zap, the bolts, the hammer's strike | |
| 103 | Stop pedalling on any seat with others riding | Your machine stops dead, and the others' machines do **not** get louder | |
| 104 | Fire and watch a far hit | The flash first, the boom later (0.6 to 3.5 s by range; twice real sound speed on purpose). Say whether the delay feels right or detached | |
| 105 | A far kill | The wreck goes up with its own boom, not before it | |
| 106 | An incoming shell, then Surge | The shot is a low thump after its range. The shell in the air is faint and comes close only in its last second, ending at the impact; say whether it reads as far until then, and whether its end still cuts through the machines. The Surge prompt, not this, is the time to start a sprint | |
| 107 | A near threat | Before you look: a burst from the bushes, a small high engine over your machine that revs as it dashes and idles down to fire, a sharp small gun whose rounds ring on the plate; no whistle. It fades over about 3 s as it flees, and stops dead if you kill it. Say whether a recon and a tankette sound different, and whether they get tiring in a long fight | |
| 108 | The track at speed | Links and a squeak that follow the tread on screen and stop with the hull. On a client, say whether they lurch when the network does (they follow the drawn tread, ADR 2026-10-31) | |
| 109 | The depot, a fight, the cool-down | Wind, crickets and now and then a frog, an owl or a branch; a far battle on the road, gone once an enemy stands in the far panel. Crickets stay crickets for 30 minutes, not a pattern | |
| 110 | Lose the tank on Hard, then the restart. Also a segment and a boss banner: a horn and a groan of iron, never the safety warning | A heavy hit, the klaxon, everything else ducked, the chain of the tow and the tread's links as it runs backwards, the engine catching at the restart | |
| 111 | Pause and resume, with the crank still turning | Machines close, the night drops, a pending boom waits; nothing bursts on resume | |
| 112 | A crew of 4 with bots at 90 rpm, as the driver | Your diesel in front; the others a texture behind it, no machine-gun | |
| 113 | Half an hour on your speakers or headphones | Note what tires you, and set the levels in Settings > Audio (Machines holds the seats and track, Ambience the night, Effects the guns and hits) | |
