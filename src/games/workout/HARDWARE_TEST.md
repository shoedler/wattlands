# Workout: real-trainer checklist

A checklist for Simon with the real KICKR CORE (BRIEF 4.7). `docs/HARDWARE_TEST_PLAN.md` links here from its Workout section. Nothing here ran during the build: every automated run used MockTrainer with the hardware lock set. Do the platform plan's "Before you start", probe, connect, SIM flat and panic steps first, and stop at the first failed safety check.

Commands that drive the trainer pass `--allow-hw` to the wrapper (`tools/godot.ps1` on Windows, `tools/godot.sh` in Git Bash). Use the log template from `docs/HARDWARE_TEST_PLAN.md` for every step.

## 1. Easy 30, solo, with zero input

- [ ] Hold a steady cadence on the title screen for 5 s with a saved profile (or 20 s on a first run). Expected: Workout's Easy 30 starts solo without a key press.
- [ ] Warm-up (0:00–5:00). Expected: ERG ramps from 50% to 65% FTP (×0.85 with an unverified FTP); the warm-up banner shows; targets never exceed 65%; the timeline plate counts down and the interval blocks on the ground scroll; your rider, with the caret over its helmet, stands over the "now" mark; its legs turn exactly at your cadence and stop dead when you coast.
- [ ] Endurance 1 (5:00–11:00) at 65% FTP. Expected: the in-band lamp on your plate lights and the watts turn to the in-band colour while you stay within ±5% of the target; the time in band on the score plate climbs toward 100%.
- [ ] Ten seconds before minute 11, a "Sprint in 10 s" toast. At 11:00 the trainer switches to SIM flat with no surge. Expected: the gear on your plate lights (it shows `-` in ERG); shift up and down (E/Q, RT/LT) and feel each step change resistance by roughly 6–8%; the gauge shows a 120–160% FTP band; the instruction line reads `SPRINT` with the watts to beat; a crowd lines the road with a gantry over it. Over 120% FTP your rider stands out of the saddle.
- [ ] Sprint above 1.2 × FTP for at least 3 s. Expected: at 11:30 a "Sprint! Peak … W" toast; ERG resumes at or below 65% FTP and slews up (no spike).
- [ ] Repeat for the sprints at 17:00 and 23:00, then the cool-down at 25:00 (50% FTP, 3 minutes). Expected: results with a grade, time in band per interval, sprint peaks, kJ and XP; a FIT file with 9 laps (8 phases plus the cool-down); the first ride unlocks the swallowtail pennant on your rider's whip.

## 2. Rescue in a work interval

- [ ] In Endurance 2 (65% FTP, above the 60% rescue threshold), drop below 45 rpm for 3 s. Expected: the target drops to 50% FTP, the rescue banner shows, your rider sits up with the rescue bubble over its head and its whip pennant hanging, your crew card reads `RESCUE`, and the time in band stops rising. Hold 70 rpm for 3 s: the target ramps back over 10 s, the rider goes back to the seated pose and the pennant lifts.

## 3. VO2, 5 minutes from the first interval

- [ ] Start VO2 (skip the warm-up in Settings only if you already warmed up). Expected: 3-minute blocks at 110% FTP with 3-minute recoveries at 50%; no duration-limit clamp (each block stays under the 300 s limit above 105%).

## 4. Rolling road for 5 minutes

- [ ] Start Rolling road and ride into the SIM phase at 5:00. Expected: the switch to SIM is smooth; the road on screen rises and falls with the course; resistance follows the grade (scaled by the difficulty setting) and the gears work; the gauge shows a 76–105% FTP band and the in-band lamp lights inside it; on a climb of 4% or more at 95% FTP your rider stands.

## 5. Group ride on two PCs

- [ ] PC A hosts Sweet spot with one bot; PC B joins with the code. Expected: both riders and the bot ride the same timeline at their own % FTP; the crew plate shows each rider's watts, in-band lamp and time in band; interval-done toasts reach only their own rider; both PCs show the same riders, each rider's legs at its own cadence and its wheels at its own speed.
- [ ] Kill the app on PC B mid-interval and restart it with the same profile. Expected: while it is gone PC A shows its rider sitting up or stopped with the link bubble and `LINK` on its crew card; it rejoins, the view and timeline come back within a second, and PC B's rider is out of band only while it was gone.

## 6. A .zwo of your own

- [ ] Start the app with `--content=zwo:<absolute path to a .zwo>` (or pick Sample .zwo in the lobby). Expected: the session preview lists every clamped block with its reason and every skipped tag; the ride follows the clamped targets.

## 7. The look on your own screen

- [ ] Press F1 in a ride. Expected: the help overlay names watts, cadence, the timeline, the blocks on the ground, the crew and the gears; on a rider's first session it opens once by itself.
- [ ] Over a whole Easy 30, watch the sky. Expected: blue hour at the start, rose and gold through the main set, clear day by the cool-down; windows lit at dawn and dark by day.
- [ ] Vary your cadence from 60 to 110 rpm. Expected: the crank icon on your plate and your rider's legs follow at once, one turn per pedal stroke, and stay in step with your feet for a full minute.
