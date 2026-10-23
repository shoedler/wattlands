# Diesel Domestiques: real-trainer checklist

The game's own checklist for a real KICKR CORE (BRIEF 4.7, `docs/games/tank.md` 2.3, 2.7 and 4). `docs/HARDWARE_TEST_PLAN.md` holds the firmware notes, the panic and stop advice, the log format and the platform checks (probe, connect, SIM flat, ERG, slew, rescue, coasting, panic and the mode-switch step), and links here. Nothing here ran during the build: every automated run used MockTrainer with the hardware lock set. Work through the platform plan first and stop at the first failed safety check.

Tank reaches the trainer only through `ctx.directives`, so everything below is the governor acting on Tank's plans and directives. What Tank asks for, by engine:

| Engine | Depot (warm-up) | Advance | Gun line | Boss |
| --- | --- | --- | --- | --- |
| Diesel | SIM, terrain grade 0 to +2% | SIM, terrain -3 to +6% (2 Hz) | **ERG 90%** | SIM flat |
| Dynamo | ERG 50% ramping to 65% | **ERG, 55 to 100%** (the bank) | same | same |
| Steam | SIM flat, boiler 3% x pressure | SIM flat, boiler up to 8% x pressure | same | same |
| Bulwark (solo) | SIM, terrain 0 to +2%, Hoist 1% | SIM, terrain + Hoist 4% | **ERG 90%** | SIM flat + Hoist 4% or 0 |

Checkpoints are ERG 50% for everybody; the platform appends a 180 s cool-down at 50% (Tank sends nothing in it). Haptics (hit +2.0% for 1.5 s, boss hit +3.0% for 2 s, Ram +3.0% for 1 s) go only to riders in a SIM phase, never in the first 300 s, a warm-up or the cool-down.

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
| 1 | Start Ashfall Road as the Citadel slot 0 (diesel) and pedal from 0:00 | SIM from the first second. Grade follows the depot's terrain 0 to +2% (before difficulty), never above +3% total in the first 300 s, never below -2%. No haptic. One teaching toast per station | |
| 2 | In the depot press `ability_1` and do a surge gesture | Nothing happens on the trainer, no "Surge to ram" prompt: Ram, dodge and Overpressure are off in the first 300 s | |
| 3 | Repeat as the dynamo (host a second run with the dynamo in slot 0, or ride the Rampart in slot 1) | ERG 50% rising smoothly to 65% over 300 s (125 to 162 W at FTP 250), slewed, never above 65%. No haptic | |
| 4 | Repeat as the steam engine (Citadel slot 2) | SIM flat. The boiler grade rises with pressure to +3% (before difficulty) and never above it, even if you sprint; when the shell latches it drops to 0 at once | |
| 5 | Solo Bulwark in the depot | SIM with terrain 0 to +2%; the lever's Hoist step adds +1% (reached at 1% per second) and returns to 0 when you leave it | |

## 2. Advance, diesel and terrain

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 6 | Stage 1 Advance (5:00), diesel | SIM. The resistance follows the road under the tank (-2 to +3% in stage 1) x your difficulty, updated about twice a second, smooth, no surge at the phase start. The tank's speed is the SIM speed model (80% FTP on the flat is about 8 m/s) | |
| 7 | Stage 2 and 3 Advances (down to -3%, up to +5 and +6%) | Same, within your grade range (default -5 to +10%). With the steepest terrain and a boiler or Hoist grade running on the same trainer (solo Bulwark: terrain +6% plus Hoist 4%) the total stays at or under +10% before the haptic | |
| 8 | Ram sprint on "Surge to ram" (a 10 s window, 30 s cooldown): 120% FTP or more for 3 s | No directive: the SIM grade is unchanged, you simply sprint. The prompt appears only in the Advance, never in a gun line or the depot. A Ram impact gives a +3.0% haptic for 1 s (section 7) | |
| 9 | Stage Advance ends (objective done or `max_s` 300 s) | The tank holds ("Regroup") until `min_s` 90 s; then ERG begins at the gun line (section 3). A phase that runs to `max_s` is an overrun: the tank is towed, score drops, the trainer does nothing unusual | |

## 3. Gun line: ERG 90%, and the switch into it

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 10 | Advance -> Gun line, diesel, from steady SIM at about 80 to 90% FTP | SIM -> ERG ramped by the platform: grade 0, then ERG at min(your 3 s power, 225 W at FTP 250), then up to 225 W at no more than 30 W/s. No spike | |
| 11 | **A gun line straight after a Ram sprint**: sprint at 130% FTP (325 W) for the last seconds of the Advance, then the phase ends | ERG is entered at or below the planned 225 W (it must not jump to your 325 W) and slews up from there at <= 30 W/s. Log the first target the trainer shows | |
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
| 31 | A Ram impact (diesel or Bulwark) | +3.0% x intensity for 1 s to the driver only | |
| 32 | Two hits within 15 s | Only the first is felt: the second is dropped (the platform's 15 s cooldown, also checked in the game) | |
| 33 | Hits while you are in ERG (gun line, dynamo, checkpoint), in the depot, in the first 300 s, or in the cool-down | Nothing is felt, ever | |
| 34 | Turn haptics off in the lobby and take hits | Nothing is felt | |
| 35 | The worst stack: solo Bulwark on +6% terrain with Hoist 4%, difficulty 50%, then a boss hit | The trainer's total grade never exceeds +16% and your range clamp (+10% by default) holds before the haptic | |

## 8. Switches, checkpoints and rotation

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 36 | Log every ERG <-> SIM switch of a full run (the platform ramps each one) | Per rider they are at least 60 s apart. The closest pair brackets a checkpoint (60 s of ERG between SIM segments). Advance -> Gun line is at least 90 s after the Advance starts; Boss -> cool-down at least 120 s after the boss starts | |
| 37 | Every SIM -> ERG entry (each gun line for the diesel and Bulwark; the dynamo's first phase after a SIM one) | ERG entered at or below the planned or directed target (or the floor) and slewed up, no spike. Include one entered straight after a Ram sprint (step 11) | |
| 38 | Every ERG -> SIM entry (the steam and diesel Advances, the boss) | ERG target set to min(applied, your 3 s power), then SIM at grade 0, then the stacked grade: no jolt | |
| 39 | A checkpoint with rotation on | ERG 50% for everyone for 60 s while the crew moves to the next engine; the station card shows the new engine | |
| 40 | Drill content (`drill`, 130 s: depot, skirmish, checkpoint) | At most one mode switch per rider; all limits of the warm-up hold; no haptics | |

## 9. Rescue, coasting and AFK

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 41 | Dynamo stage, applied target >= 60% FTP: drop cadence below 45 rpm for 3 s | Rescue: target 50% FTP, "Dynamo stalled", the turret freezes and the bank stops charging; the plan continues. Cadence >= 70 rpm for 3 s ramps back over 10 s | |
| 42 | The same in a 90% gun line (diesel or Bulwark) | Rescue at 50% FTP (armed at 76.5% applied when unverified); the berm stops growing; nothing gets power on the Bulwark | |
| 43 | Stop pedaling in a crew game (host with clients) | The floor after 3 s; at 10 s you go AFK and your station runs on reserve (as if 60 W, never in band); the others play on. All riders AFK: nothing has power, no gun fires | |
| 44 | Stop pedaling solo in the depot | The floor after 3 s, pause at 10 s | |
| 45 | Panic (Backspace 1 s) in an ERG gun line, a dynamo fight and a SIM Advance | ERG off or grade 0 and wind 0 at once; the trainer stays safe until you resume | |

## 10. Cool-down, FIT and Strava

| # | Step | Expected | Result |
| --- | --- | --- | --- |
| 46 | Cool-down (180 s) | ERG 50%; the view stays and the tank rolls into the town (or back up the road if the Behemoth withdrew); Tank sends no directive; no score | |
| 47 | Save the ride and run `node tools/fit_check/check.mjs <file> --expect-laps=12` (drill: 4) | Clean FIT: one lap per segment, laps adding up to the session, the cool-down as the last lap | |
| 48 | Upload to Strava (with `--allow-network`) | A Virtual Ride with power, cadence and a lap per segment (depot, each Advance and gun line, checkpoints, boss, cool-down) | |

Log: date, trainer firmware, FTP, verified or not, difficulty and haptic settings, crew size, the content, and each step's result with the running log of a full ride attached. Anything that spikes, jolts, exceeds a stated bound or feels wrong is a failed safety check: stop, note the segment and time, and report it to the lead.
