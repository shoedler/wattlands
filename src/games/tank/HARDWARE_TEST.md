# Diesel Domestiques: real-trainer checklist

The game's own checklist for a real KICKR CORE (BRIEF 4.7, `docs/games/tank.md` 2.3, 2.7 and 4). `docs/HARDWARE_TEST_PLAN.md` holds the firmware notes, the panic and stop advice, the log format and the platform checks (probe, connect, SIM flat, ERG, slew, rescue, coasting, panic and the mode-switch step), and links here. Nothing here ran during the build: every automated run used MockTrainer with the hardware lock set. Work through the platform plan first and stop at the first failed safety check. Sections 1 to 10 check what the simulations already assert (`tests/games/tank/sim/`) against a real trainer; section 11 lists what a simulation cannot judge at all (a real rider's sprints, the firmware's response, the network, the display and the speakers). Step numbers are stable (other notes refer to them): new steps are 43a and 43b in section 9, 49 onwards in section 11 and 68 onwards in section 12 (v2: the arc generator, Surge to evade, the bow guns and four riders). v2 removed the Ram: its steps (8, 31, the Ram parts of 11, 50, 54 and 57) are rewritten for "Surge to evade" and keep their numbers.

Tank reaches the trainer only through `ctx.directives`, so everything below is the governor acting on Tank's plans and directives. What Tank asks for, by engine:

| Engine | Depot (warm-up) | Advance | Gun line | Boss |
| --- | --- | --- | --- | --- |
| Diesel | SIM, terrain grade 0 to +2% | SIM, terrain -3 to +6% (2 Hz) | **ERG 90%** | SIM flat |
| Dynamo | ERG 50% ramping to 65% | **ERG, 55 to 100%** (the bank) | same | same |
| Steam | SIM flat, boiler 3% x pressure | SIM flat, boiler up to 8% x pressure | same | same |
| Bulwark (solo) | SIM, terrain 0 to +2%, Hoist 1% | SIM, terrain + Hoist 4% | **ERG 90%** | SIM flat + Hoist 4% or 0 |
| Arc generator (Bastion, crew 4) | ERG 50% ramping to 65% | **ERG, 65 to 80%** (the arc load: 65 + 15 x duty) | same | same |

Checkpoints are ERG 50% for everybody; the platform appends a 180 s cool-down at 50% (Tank sends nothing in it). Haptics (hit +2.0% for 1.5 s, boss hit +3.0% for 2 s) go only to riders in a SIM phase, never in the first 300 s, a warm-up or the cool-down. Sprints ("Surge to evade", "Surge to overpressure") send nothing: they are your own effort in the phase's SIM.

## 0. Setup

- [ ] Drop the locks only by hand, as the platform plan says. From source, PowerShell: `tools/godot.ps1 --allow-hw --timeout=14400 --path .`; Git Bash: `tools/godot.sh --allow-hw --timeout=14400 --path .` (without `--timeout` the wrappers stop a run after 20 minutes). `--allow-network` only for the Strava step. An exported build never sets the locks. Never pass these flags from an automated run.
- [ ] KICKR CORE, current firmware (before 1.5.5 it could spike on mode switches). Close Zwift and the Wahoo app. Know how to stop: hold Backspace for 1 s (panic), or stop pedaling.
- [ ] Set your FTP in the profile. Do the whole checklist **verified** (a test result), then repeat sections 1, 3 and 4 **unverified**: every ERG target is then x 0.85 and never higher.
- [ ] A full Ashfall Road is 30 to 41 minutes. To visit every engine with one trainer, host the **Citadel** on your PC (you are slot 0) and join two clients that ride `--mock-trainer=erg` (no trainer): with rotation on you ride diesel (depot, stage 1), dynamo (stage 2), steam (stage 3) and diesel again (boss). The clients can be Autopilot. For the Bulwark's lever and Hoist, start Ashfall Road **solo** (sections 6 and 8).
- [ ] Targets at an example FTP of 250 W (scale to yours; the unverified column is x 0.85):

| What | % FTP | Watts at 250 | Unverified watts |
| --- | --- | --- | --- |
| Checkpoint ERG | 50 | 125 | 106 |
| Dynamo depot ramp | 50 to 65 | 125 to 162 | 106 to 138 |
| Dynamo fight, bank full | 55 | 138 | 117 |
| Dynamo fight, bank empty | 100 | 250 | 212 |
| Arc generator fight, no bow-gun fire | 65 | 162 | 138 |
| Arc generator fight, bow guns always firing | 80 | 200 | 170 |
| Evade sprint (the sprint rule) | 120 or more | 300 | 300 (sprints are raw watts, never x 0.85) |
| Diesel or Bulwark gun line | 90 | 225 | 191 |
| Floor (never below) | max(30%, 50 W) | 75 | 75 |

- [ ] SIM grades are stacked by the governor: (terrain + boiler or hoist) x difficulty (default 50%) + gear offset, clamped to your grade range (default -5 to +10%), plus the haptic (x its intensity setting, at most +3% for at most 8 s, 15 s apart), total -10 to +16%. Note your difficulty and haptic intensity before you start.
- [ ] Use the log template of the platform plan per step, plus this running log for a full ride (one line per segment start, per switch and per event worth noting):

```text
t (mm:ss) | segment | engine | trainer mode | target W or grade % | power W | cadence | note
```

## 1. Depot: the first 300 s (BRIEF 4.6.8)

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 1 | Start Ashfall Road as the Citadel slot 0 (diesel) and pedal from 0:00 | SIM from the first second. Grade follows the depot's terrain 0 to +2% (before difficulty), never above +3% total in the first 300 s, never below -2%. No haptic | |
| 2 | In the depot sprint at 130% FTP while an enemy telegraphs (the drill's skirmish has light tanks) and do a surge gesture | Nothing happens on the trainer, no "Surge to evade" prompt and the shot is not evaded: evade and Overpressure are off in WARMUP phases and the first 300 s | |
| 3 | Repeat as the dynamo (host a second run with the dynamo in slot 0, or ride the Rampart in slot 1) | ERG 50% rising smoothly to 65% over 300 s (125 to 162 W at FTP 250), slewed, never above 65%. No haptic | |
| 4 | Repeat as the steam engine (Citadel slot 2) | SIM flat. The boiler grade rises with pressure to +3% (before difficulty) and never above it, even if you sprint; when the shell latches it drops to 0 at once | |
| 5 | Solo Bulwark in the depot | SIM with terrain 0 to +2%; the lever's Hoist step adds +1% (reached at 1% per second) and returns to 0 when you leave it | |

## 2. Advance, diesel and terrain

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 6 | Stage 1 Advance (5:00), diesel | SIM. The resistance follows the road under the tank (-2 to +3% in stage 1) x your difficulty, updated about twice a second, smooth, no surge at the phase start. The tank's speed is the SIM speed model (80% FTP on the flat is about 8 m/s) | |
| 7 | Stage 2 and 3 Advances (down to -3%, up to +5 and +6%) | Same, within your grade range (default -5 to +10%). With the steepest terrain and a boiler or Hoist grade running on the same trainer (solo Bulwark: terrain +6% plus Hoist 4%) the total stays at or under +10% before the haptic | |
| 8 | Evade sprint on "Surge to evade" (an enemy telegraphs: destroyer glint 4 s, heavy muzzle glow 3 s, a light tank's flank shot 2.5 s): hold 120% FTP or more (averaged over 3 s) for 2 s inside the telegraph | No directive: the SIM grade is unchanged, you simply sprint. The prompt and the SURGE line show only to riders in a SIM WORK phase past 5:00, never in an ERG gun line or the depot. An evaded shot misses: "Evaded!", the tank lurches, and no hit haptic | |
| 9 | Stage Advance ends (objective done or `max_s` 300 s) | The tank holds ("Regroup") until `min_s` 90 s; then ERG begins at the gun line (section 3). A phase that runs to `max_s` is an overrun: the tank is towed, score drops, the trainer does nothing unusual | |

## 3. Gun line: ERG 90%, and the switch into it

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 10 | Advance -> Gun line, diesel, from steady SIM at about 80 to 90% FTP | SIM -> ERG ramped by the platform: grade 0, then ERG at min(your 3 s power, 225 W at FTP 250), then up to 225 W at no more than 30 W/s. No spike | |
| 11 | **A gun line straight after an evade sprint**: sprint at 130% FTP (325 W) for the last seconds of the Advance, then the phase ends | ERG is entered at or below the planned 225 W (it must not jump to your 325 W) and slews up from there at <= 30 W/s. Log the first target the trainer shows | |
| 12 | 90% gun line, 90 to 180 s | Steady 225 W, "Dig in": the berm grows while you are in band. No duration-limit message (90% is under 105%). At 76.5% (unverified) the line is still held | |
| 13 | Gun line -> Checkpoint (ERG 50%) | The target falls at once to 125 W (decreases are immediate), no mode switch (ERG to ERG) | |
| 14 | Solo Bulwark gun line | ERG 90% as above; the lever shows Dig; Hoist sends nothing and the heavy shell lifts on your ERG work (4 kJ) with no mode grade | |

## 4. Dynamo: the bank is the ERG target

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 15 | Stage 2 Advance, dynamo (slot 0 after rotation), no enemy in range | ERG at 55% (138 W at 250) while the bank is full | |
| 16 | An enemy comes in range, the bank drains | The target climbs with the drain: 55 + 45 x (1 - bank/100) %, never outside 55 to 100%. Each bank update of at most 10 points arrives as three sub-steps 1 s apart, so the rise is <= 3.3% FTP per second (<= 8.3 W/s at 250), well under the 30 W/s slew. Decreases are immediate. Log the target every 5 s through one fight | |
| 17 | A traverse (15 units) or a heavy hoist drain | A step of at most 10 points, not a jump | |
| 18 | Boss (the dynamo's ERG phase is `max_s` 360 s, over 300 s) | Targets stay at or under 100%, below the 105% cap that long phases get. No duration counter runs | |
| 19 | After the fight (last gun falls or the Behemoth dies) | The target is back at or below 65% within 120 s (the next phase, a checkpoint, is 50%) | |
| 20 | The rider's own power | "In band" needs power >= 95% of the applied target and cadence >= 60: the wall lamp lights and the bank charges at one unit per 150 J | |

## 5. Steam: the boiler grade

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 21 | Stage 3 Advance, steam (slot 0 after rotation), ride 90% FTP | SIM flat, mode grade 8% x min(pressure, 1) (0 to +8% before difficulty). It rises at most 0.5% per step, at most once a second, so the resistance builds gently | |
| 22 | Pressure reaches 100%, the 5 s "Surge to overpressure" window | Without a surge, a heavy shell latches when the window ends: **the grade drops to 0 in one step** (resistance falls at once) and stays 0 while the shell is loaded and for the 6 s breech cycle (log the seconds at grade 0: at least 6) | |
| 23 | Surge inside the window (sprint, 120% FTP for 3 s) | Pressure builds 100 to 150% on 3 kJ counted only while the sprint holds; the grade stays at 8%; W' pays. Latch at 150% or after 30 s | |
| 24 | A confirm at >= 40% pressure | A light shell latches; the grade drops to 0 the same way | |
| 25 | Checkpoints | Pressure holds; the trainer is in ERG 50% with no boiler grade | |

## 6. Solo Bulwark: lever, Drive and Hoist

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 26 | Advance, auto-lever on | The lever stays on Drive unless a target is in range (>= 60% of an Advance on Drive when compliant). A lever move takes 1 s with no power anywhere in the game; the trainer does not change | |
| 27 | Move the lever to Hoist in an Advance | SIM mode grade rises to +4% (before difficulty) at +1% per second; leaving Hoist returns it to 0. Terrain stays on top: total at most +10% before the haptic | |
| 28 | Boss: Hoist on | +4% (SIM flat plus Hoist), or 0 when off | |

## 7. Haptics (BRIEF 4.6.6)

Each haptic is a `request` that changes only the haptic term: the boiler, Hoist and terrain grades stay, and its expiry ends only the haptic.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 29 | Take a hit of 8 damage or more in a SIM Advance after 5:00 (any engine in SIM) | About +2.0% x your intensity setting of grade for 1.5 s, on top of the stacked grade, then back. At intensity 100% and at 50% log the felt change | |
| 30 | A Behemoth main-gun hit (boss) | +3.0% x intensity for 2 s to every rider in SIM | |
| 31 | An evaded shot (you or a crewmate held the sprint inside the telegraph) | Nothing is felt: the shot missed (v2 has no Ram haptic) | |
| 32 | Two hits within 15 s | Only the first is felt: the second is dropped (the platform's 15 s cooldown, also checked in the game) | |
| 33 | Hits while you are in ERG (gun line, dynamo, checkpoint), in the depot, in the first 300 s, or in the cool-down | Nothing is felt, ever | |
| 34 | Turn haptics off in the lobby and take hits | Nothing is felt | |
| 35 | The worst stack: solo Bulwark on +6% terrain with Hoist 4%, difficulty 50%, then a boss hit | The trainer's total grade never exceeds +16% and your range clamp (+10% by default) holds before the haptic | |

## 8. Switches, checkpoints and rotation

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 36 | Log every ERG <-> SIM switch of a full run (the platform ramps each one) | Per rider they are at least 60 s apart. The closest pair brackets a checkpoint (60 s of ERG between SIM segments). Advance -> Gun line is at least 90 s after the Advance starts; Boss -> cool-down at least 120 s after the boss starts | |
| 37 | Every SIM -> ERG entry (each gun line for the diesel and Bulwark; the dynamo's or the arc's first phase after a SIM one) | ERG entered at or below the planned or directed target (or the floor) and slewed up, no spike. Include one entered straight after an evade sprint (step 11) | |
| 38 | Every ERG -> SIM entry (the steam and diesel Advances, the boss) | ERG target set to min(applied, your 3 s power), then SIM at grade 0, then the stacked grade: no jolt | |
| 39 | A checkpoint with rotation on | ERG 50% for everyone for 60 s while the crew moves to the next engine; the station card shows the new engine | |
| 40 | Drill content (`drill`, 130 s: depot, skirmish, checkpoint) | At most one mode switch per rider; all limits of the warm-up hold; no haptics | |

Planned ERG <-> SIM switches per rider, cool-down included (the platform's own ramps are part of each switch, not extra ones). Log every one of them in the running log for each crew size you ride, with the target or grade just before, at the switch and 10 s after:

| Crew | Rider (stages 1, 2, 3, boss) | Switches | Where they fall |
| --- | --- | --- | --- |
| 1 Bulwark | Bulwark throughout | 7 | SIM -> ERG at each gun line (3), ERG -> SIM at the stage 2 and 3 Advances and the boss (3), SIM -> ERG into the cool-down (1) |
| 2 Rampart | slot 0: diesel, dynamo, diesel, dynamo | 3 | gun line 1 (SIM -> ERG), Advance 3 (ERG -> SIM), gun line 3 (SIM -> ERG); the cool-down follows an ERG boss |
| 2 Rampart | slot 1: dynamo, diesel, dynamo, diesel | 4 | Advance 2 (ERG -> SIM), gun line 2 (SIM -> ERG), boss (ERG -> SIM), cool-down (SIM -> ERG) |
| 3 Citadel | slot 0: diesel, dynamo, steam, diesel | 5 | gun line 1 (SIM -> ERG), Advance 3 (ERG -> SIM), checkpoint 3 (SIM -> ERG), boss (ERG -> SIM), cool-down (SIM -> ERG) |
| 3 Citadel | slot 1: dynamo, steam, diesel, dynamo | 4 | Advance 2 (ERG -> SIM), checkpoint 2 (SIM -> ERG), Advance 3 (ERG -> SIM), gun line 3 (SIM -> ERG) |
| 3 Citadel | slot 2: steam, diesel, dynamo, steam | 5 | checkpoint 1 (SIM -> ERG), Advance 2 (ERG -> SIM), gun line 2 (SIM -> ERG), boss (ERG -> SIM), cool-down (SIM -> ERG) |

The closest pair is a checkpoint bracket (60 s of ERG between two SIM segments, as in the Citadel slot 0 at checkpoint 3 and the boss); every other pair is further apart. At each switch the expected result is step 37 (SIM -> ERG: at or below the planned target, slewed up) or step 38 (ERG -> SIM: grade 0 first, then the stacked grade).

## 9. Rescue, coasting and AFK

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 41 | Dynamo stage, applied target >= 60% FTP: drop cadence below 45 rpm for 3 s | Rescue: target 50% FTP, "Dynamo stalled", the turret freezes and the bank stops charging; the plan continues. Cadence >= 70 rpm for 3 s ramps back over 10 s | |
| 42 | The same in a 90% gun line (diesel or Bulwark) | Rescue at 50% FTP (armed at 76.5% applied when unverified); the berm stops growing; nothing gets power on the Bulwark | |
| 43 | Stop pedaling in a crew game (host with clients) | The floor after 3 s; the pause symbol at 5 s (your ride timer stops, the game runs on); at 10 s you go AFK and your station runs on reserve (as if 60 W, never in band); the others play on. All riders stopped: the host pauses the game for everyone (`all_stopped`) and it resumes when one rider pedals 1 s at 30 rpm or more | |
| 44 | Stop pedaling solo in the depot | The floor after 3 s, the session pauses at 5 s with the pause symbol; 1 s of pedaling at 30 rpm or more resumes it | |
| 43a | Step 43 follow-up: an AFK dynamo in a fight for 60 s, then pedal again (host with clients, dynamo in a stage with the bank draining) | While you coast the plan continues and your target sits at the floor or the rescue 50% (armed while coasting). Log the target when you start pedaling again and every 2 s for 20 s: in the mock run it came back at 72.5% (up from 55%) and then rose with the bank. Expected: no step faster than 30 W/s, the rescue clears after cadence >= 70 rpm for 3 s and the platform's 10 s ramp-back is smooth, the station leaves reserve at once, no mode switch | |
| 43b | **Dynamo client network drop and rejoin on a real KICKR, mid-fight**: pull the client's network for 30 s and reconnect, without restarting the app and with the trainer still connected (dynamo rider in a stage, enemies in range) | The rider is dropped (AFK at once, the station on reserve, an "on reserve" toast on the host), the plan continues, and on reconnect the client resumes from the latest full snapshot with no restart. Log the ERG target before the drop, right after the reconnect and every second for the next 10 s. The target can jump 20 to 40 points between the drop and the return (the bank moved on without you); the only limit on its rise is the platform's 30 W/s slew, so expect a smooth climb, never a step. A jolt, a mode switch or a target above 100% is a failed safety check | |
| 45 | Panic (Backspace 1 s) in an ERG gun line, a dynamo fight and a SIM Advance | ERG off or grade 0 and wind 0 at once; the trainer stays safe until you resume | |

## 10. Cool-down, FIT and Strava

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 46 | Cool-down (180 s) | ERG 50%; the view stays and the tank rolls into the town (or back up the road if the Behemoth withdrew); Tank sends no directive; no score | |
| 47 | Save the ride and run `node tools/fit_check/check.mjs <file> --expect-laps=12` (drill: 4) | Clean FIT: one lap per segment, laps adding up to the session, the cool-down as the last lap | |
| 48 | Upload to Strava (with `--allow-network`) | A Virtual Ride with power, cadence and a lap per segment (depot, each Advance and gun line, checkpoints, boss, cool-down) | |

## 11. What the simulations cannot judge

Each item is something a MockTrainer run cannot show: how the real firmware, a real rider's legs, the network, the display or the speakers behave. (Ids in brackets are the G3 review findings they came from.) Do them after sections 1 to 10 and note the exact segment and time for each.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 49 | ERG settling with the bank's 3.3%/s sub-steps (three sends 1 s apart, every 5 s) at FTP 200 and again at FTP 300, in a dynamo stage with the bank draining and refilling | The trainer follows each sub-step without overshoot or hunting between sub-steps; the log of target versus watts settles within a few seconds of each update; decreases are immediate. Log the overshoot in watts at both FTPs | |
| 50 | Write coalescing at 2 control writes a second: a Bulwark Advance (terrain at 2 Hz, Hoist steps at 1 Hz, a hit haptic on top) and a steam Advance (boiler at 1 Hz plus haptics) | The grade the trainer applies lags the newest value by no more than about 1 s and there is no audible or felt stepping; no write is lost (the grade after the Hoist or haptic ends is the held terrain plus Hoist grade again) | |
| 51 | A gun line straight after an evade sprint (steps 11 and 37), watching the rescue: sprint hard in the last seconds of an Advance, let the phase end, and watch the cadence the trainer reports at the SIM -> ERG boundary | The trainer's cadence estimate lags after sprints, but the ERG 90% entry must not trigger a false rescue (cadence below 45 rpm for 3 s). Log the cadence the trainer reports for the first 5 s of the gun line and whether rescue armed | |
| 52 | Haptic feel at the default intensity: a boss hit haptic (3.0 x 0.7 = +2.1% for 2 s) on top of Bulwark stage 3 terrain +6% plus Hoist 4% (both x the 50% default difficulty = 5%), a total of about 7.1% | No jolt; the haptic's expiry does not drop the held Hoist or terrain grade (the grade returns to about 5%, not 0) | |
| 53 | Mode switches per rider on current firmware: ride a full Bulwark (7 switches) and a Citadel slot (5 per ride) and watch for a power spike at every ERG <-> SIM boundary, including the 60 s checkpoint brackets | No power spike or lurch at any boundary; each switch is the ramped one of step 37 or 38. Note the firmware version | |
| 54 | Evade and Overpressure need the sprint rule (>= 1.2 x FTP averaged over the last 3 s) on real, noisy, delayed trainer watts, and the Overpressure's surge gesture in SIM (power above max(1.3 x your recent baseline, baseline + 40 W) for two samples) | Can you make a telegraphed shot miss ("Evaded!") from a 90% FTP ride? Count evades tried against evades made per telegraph type over a ride (the results show them), and the same for an Overpressure on the steam engine. The light tank's 2.5 s flank shot needs the rule to hold 2 s inside it: from 90% FTP that is about 2.7 x FTP, so expect it to be evadable only when you were already sprinting | |
| 55 | Boss evade feasibility (ED-2): reaction time plus how fast your SIM power can step from about 90% FTP to 160% or more, inside the Behemoth's 6 s telegraph | A sprint held 3 s inside the telegraph makes the shot miss ("Evaded!"). Record the best held seconds per telegraph over the whole boss and whether the sprint had to start within about 1.5 s of the telegraph | |
| 56 | What the real governor and host do with the rescue flag when a rider's Bluetooth link drops or a rider coasts to AFK: pull the trainer's link (or its power) while in a dynamo stage, then restore it | Whether the rescue flag clears on the drop (RN-1: a rescued rider who goes AFK keeps `rescue` set and the dynamo stays frozen) or stays set; the 10 s ramp-back after a rejoin while the dynamo is already on reserve is smooth. Note what the HUD and the station show | |
| 57 | Real relay latency and loss: a host and two clients over the real relay, with a bad connection (Wi-Fi at the edge of range, or a throttled link) through a gun line and the boss | Client intents (batched at 5 a second; the host accepts 5 a second per rider) still aim, fire and Overpressure; each client's own "Surge to evade" prompt follows the telegraph within a snapshot; the 100 ms snapshot interpolation looks smooth; a client restarted in the middle of a gun line or the boss resumes from the latest full snapshot (only the 3 s depot rejoin was run in the e2e). Log the dropped or late intents you noticed | |
| 58 | A real rider stopping in an ERG dynamo phase on a KICKR CORE: stop pedaling for 15 s in a dynamo stage at 60% FTP or more, then restart | The 3 s cadence-drop rescue, then AFK at 10 s, then back: the Citadel or Rampart gun is not left frozen once you pedal again (turret slews, bank charges, shells fly), after the rescue fix | |
| 59 | 60 fps at 1080p on integrated graphics (Intel or AMD): a 60 s windowed boss fight with the Citadel at the caps, vsync on | Mean and 1%-low frame times against 16.7 ms. The measured machine had an RTX 5060 Ti only; additive halos versus `PointLight2D` were never compared on integrated graphics. Note the GPU, driver and resolution | |
| 60 | Real-monitor legibility of the teammate strip: in its 140 x 22 art-px slot it scales to about 0.52 (130 x 66 px per card at 1080p, labels about 12 px) | Readable from riding distance on a real display: engine name, in-band mark, rescue and AFK marks, for 1 to 3 cards | |
| 61 | Audio: your own station loudest, the diesel, dynamo and steam voices, the cannon, the casing and the clunk, all synthesized at runtime | A person has to listen: your own station is loudest, no voice is shrill or drowns the others, nothing clips at a normal volume. Note anything that grates over 30 minutes | |
| 62 | Vsync frame pacing on a real display with nothing else running: the vsync run showed three isolated 28 ms frames about 16 s apart, and an uncapped run had no frame above 7 ms after start-up | On a quiet machine, do the isolated long frames appear (the desktop compositor and other Godot processes sharing the GPU are the suspects)? Log their spacing | |
| 63 | Boiler and Hoist feel at the default 50% difficulty: the steam grade peaks at 4.0% (8% x 0.5) in a ramp of about 20 s, then drops to 0 for 6.5 to 7 s at each latch; the Hoist peaks at 2.0% | The resistance steps are perceptible and the drop at a latch is felt; "building at 90% FTP or more" is holdable through the ramp. Note whether the difficulty should be higher by default | |
| 64 | Rampart dynamo ERG at 98 to 100% FTP for 199 to 255 s after about 17 minutes of work, and 565 s at 98% or more over the ride with rotation off (ED-4) | Do riders finish it? How the rescue or the stagger behaves at the end of a long block, and whether the bank empties as the sims predict. Note the heart-rate or RPE drift | |
| 65 | The dynamo's phase-boundary drop from about 95% to 55-58% ERG followed by a 22 s climb (ED-5), and the SIM -> ERG 90% gun-line entry right after an Advance sprint | The decrease is immediate and clean; the climb that follows is smooth; the gun-line entry is step 37 | |
| 66 | Hit haptics (2.0% for 1.5 s; boss 3.0% for 2.0 s) under the 15 s cooldown, once review finding ED-3 is resolved | Two hits within 15 s: only the first is felt (step 32), and the haptics feel proportionate to the stacked grade | |
| 67 | The unguided SIM warm-up in the depot (ED-6): the diesel, steam and Bulwark ride 5 minutes of SIM with no power band | What riders actually ride for 5 minutes with no band: log the power and grade from the platform log, and whether it is a sensible warm-up (cadence 60 to 120, no sprint prompts) | |

## 12. v2: the arc generator, Surge to evade, the bow guns and four riders

Host the **Bastion** (four riders: you in slot 3 start on the arc generator; three clients ride `--mock-trainer=erg`, Autopilot is fine). With rotation on, slot 3 rides arc (stage 1), diesel (stage 2), dynamo (stage 3) and steam (boss); slot 0 rides the arc at the boss.

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 68 | Depot as the arc generator | ERG 50% rising smoothly to 65% over 300 s, never above 65%, no arc pattern, no haptic | |
| 69 | Stage 1 Advance as the arc generator, nothing in the bow guns' range (40-220 px ahead) | ERG 65% (162 W at 250) | |
| 70 | Enemies come within the bow guns' range: the bow guns fire (a rattle, tracers from the nose) | The arc load (the share of the last 10 s the bow guns fired) lifts the target: 65 + 15 x duty %, never outside 65 to 80%. Each update every 5 s moves at most 10 points, as three sub-steps 1 s apart (<= 3.3% FTP per second); decreases are immediate. Log the target every 5 s through one fight | |
| 71 | The fight ends (the last enemy in range falls) | The duty decays over 10 s and the target is back at or below 68% within 60 s (T7); the next checkpoint is 50% at once | |
| 72 | In band (power >= 95% of the applied target, cadence >= 60) | The searchlights are lit (the main gun's dispersion halves) and the bow guns fire every 2 s; under band they fire every 4 s and the searchlights dim | |
| 73 | Rescue in an arc phase, applied target >= 60%: cadence below 45 rpm for 3 s | Rescue at 50% FTP: "Arc generator stalled" for the whole crew, the bow guns stop, the searchlights go dark; the plan continues and the ramp-back is the platform's 10 s | |
| 74 | Stop pedaling on the arc generator (AFK) | Your station runs on reserve: the bow guns stop (the Bastion's bow guns run only on a present arc rider); the others play on | |
| 75 | Bow-gun power on the Rampart or Citadel: watch the dynamo's bank while the bow guns fire | Each burst costs the bank 2 units (the dynamo's ERG target rises with the drain, step 16); below 10 units the bow guns stop. On the solo Bulwark they fire every 4 s and cost nothing | |
| 76 | A wire or wreck barricade in the bow guns' range with no enemy near | 4 s of bow-gun fire clears it (8 s on the Bulwark); a heavy shell or three light shells still do too | |
| 77 | Surge to evade per telegraph type, in SIM past 5:00 (diesel, steam or Bulwark): a destroyer's 4 s glint, a heavy's 3 s muzzle glow, a light tank's 2.5 s flank shot, the Behemoth's 6 s main gun (hold 3 s) | Each prompt shows only to riders who can evade (SIM WORK, past 5:00); an ERG rider (dynamo, arc, a 90% gun line) sees the world tag but no SURGE line, and their sprint never counts. A made evade: the shot misses, no haptic; the trainer never changes for the sprint | |
| 78 | Four riders end to end: a full Ashfall Road as the Bastion with three clients (or the drill for a short check) | Every client's HUD shows four crew cards and four engine windows, snapshots arrive smoothly, every peer reaches the results; with the drill every limit of the warm-up holds for all four riders and nobody's ERG exceeds 65% | |
| 79 | Rotation with four riders: each checkpoint | ERG 50% for everyone for 60 s while each rider moves one engine on (diesel -> dynamo -> steam -> arc -> diesel); over the four stages every rider works every engine once | |

Planned ERG <-> SIM switches with four riders (each at least 60 s apart; check each against steps 37 and 38):

| Crew | Rider (stages 1, 2, 3, boss) | Switches | Where they fall |
| --- | --- | --- | --- |
| 4 Bastion | slot 0: diesel, dynamo, steam, arc | 3 | gun line 1 (SIM -> ERG), Advance 3 (ERG -> SIM), checkpoint 3 (SIM -> ERG) |
| 4 Bastion | slot 1: dynamo, steam, arc, diesel | 4 | Advance 2 (ERG -> SIM), checkpoint 2 (SIM -> ERG), boss (ERG -> SIM), cool-down (SIM -> ERG) |
| 4 Bastion | slot 2: steam, arc, diesel, dynamo | 3 | checkpoint 1 (SIM -> ERG), Advance 3 (ERG -> SIM), gun line 3 (SIM -> ERG) |
| 4 Bastion | slot 3: arc, diesel, dynamo, steam | 4 | Advance 2 (ERG -> SIM), gun line 2 (SIM -> ERG), boss (ERG -> SIM), cool-down (SIM -> ERG) |

Log: date, trainer firmware, FTP, verified or not, difficulty and haptic settings, crew size, the content, and each step's result with the running log of a full ride attached. Anything that spikes, jolts, exceeds a stated bound or feels wrong is a failed safety check: stop, note the segment and time, and report it to the lead.
