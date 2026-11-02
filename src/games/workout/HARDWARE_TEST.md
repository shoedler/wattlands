# Workout: real-trainer checklist

A checklist for riding this game on a real KICKR CORE (BRIEF 4.7). `docs/HARDWARE_TEST_PLAN.md` links here from its Workout section. Nothing here ran during the build: every automated run used MockTrainer with the hardware lock set. Do the platform plan's "Before you start", probe, connect, SIM flat and panic steps first, and stop at the first failed safety check.

Commands that drive the trainer pass `--allow-hw` to the wrapper (`tools/godot.ps1` on Windows, `tools/godot.sh` in Git Bash). Use the log template from `docs/HARDWARE_TEST_PLAN.md` for every step.

## 1. Easy 30, solo, with zero input

- [ ] Hold a steady cadence on the title screen for 5 s with a saved profile (or 20 s on a first run). Expected: Workout's Easy 30 starts solo without a key press.
- [ ] Warm-up (0:00–5:00). Expected: ERG ramps from 50% to 65% FTP (×0.85 with an unverified FTP); the warm-up banner shows; targets never exceed 65%; the timeline plate counts down and the interval blocks on the ground scroll; your rider, with the caret over its helmet, stands over the "now" mark; its legs turn exactly at your cadence and stop dead when you coast.
- [ ] Endurance 1 (5:00–11:00) at 65% FTP. Expected: the in-band lamp on your plate lights and the watts turn to the in-band colour while you stay within ±5% of the target; the time in band on the score plate climbs toward 100%.
- [ ] Ten seconds before minute 11, a "Sprint in 10 s" toast. At 11:00 the trainer switches to SIM flat with no surge. Expected: the gear on your plate lights (it shows `-` in ERG); shift up and down (E/Q, RT/LT) and feel each step change resistance by roughly 6–8%; the gauge shows a 120–160% FTP band; the instruction line reads `SPRINT` with the watts to beat; a crowd lines the road with a gantry over it. Over 120% FTP your rider stands out of the saddle.
- [ ] Sprint above 1.2 × FTP for at least 3 s. Expected: at 11:30 a "Sprint! Peak … W" toast; ERG resumes at or below 65% FTP and slews up (no spike).
- [ ] Repeat for the sprints at 17:00 and 23:00, then the cool-down at 25:00 (50% FTP, 3 minutes). Expected: results with a grade, time in band per interval, sprint peaks, kJ and XP; a FIT file with 9 laps (8 phases plus the cool-down); the first ride unlocks the swallowtail pennant on your rider's whip.

## 2. Rescue in a work interval

- [ ] In Endurance 2 (65% FTP, above the 60% rescue threshold), drop below 45 rpm for 3 s. Expected: the target drops to 50% FTP, the rescue banner shows, your rider sits up with the rescue bubble over its head and its whip pennant hanging, your crew card reads `RESCUE`, the instruction line reads `SPIN`, and the time in band stops rising. Hold 70 rpm for 3 s: the target ramps back over 10 s, the rider goes back to the seated pose and the pennant lifts.

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

## 8. Listen

Nobody has heard this audio: every number behind it was measured offline. Listen with the sound on, over the fan and the trainer.

- [ ] Before riding, play `build/audio_preview/workout.mp3` (`node tools/audio/preview.mjs --game=workout`). Expected: a bike, not an engine: a chain, a soft push on each pedal, tyres and wind that grow with speed, birds in the grass.
- [ ] Ride Easy 30 at 60, then 90, then 110 rpm. Expected: tick and press stay with the legs on screen at every cadence and stop as your legs stop; the sound follows your feet in rate, not in phase (FTMS reports cadence about once a second).
- [ ] Stop pedalling at speed. Expected: the chain stops dead, the freewheel ticks on, evenly, slowing with the wheel; tyres and wind fade as you slow.
- [ ] Ride ten minutes of a steady block with 7 bots. Expected: it does not freeze: gusts in the wind, patches of rougher road in the tyres and the chain, a creak on the roughest of them, a far bell or dog now and then. If the creak sounds like a broken bike rather than a rough road, or the press's strong and weak leg like a limp, say so: both are one level in `audio.json`. Whether the press reads as a wooden thunk or as boxy is open too (a fixed hump near 317 Hz). The group is a light scattered ticking around you, in a band of its own, that you notice when it stops. Your own strokes stay the clearest rhythm, and it does not swell when everyone starts or resumes together.
- [ ] Go through a phase change. Expected: the chime, a beat later the bell, the banner silent. The warning sound plays only for a real safety prompt.
- [ ] Stop pedalling for two minutes in the middle of a block so the ride pauses, then ride on. Expected: the birds and the far sounds carry on quietly under the pause, and nothing bursts when you start again.
- [ ] In a sprint, pull the trainer's power or link so a real safety prompt fires. Expected: the warning stands clear of everything, the bike, the road and the interface sounds drop away at once and come back over two seconds; a start countdown keeps its level. If it is hard to hear over your fan, say so: this is the one sound that must never be missed.
- [ ] Ride all of Easy 30 listening to the birds. Expected: a busy dawn chorus at the start that thins out as the sky brightens, with single calls by the cool-down, and never a stretch that sounds empty.
- [ ] Shift in a sprint. Expected: a click, then the chain crossing a moment later, up and down audibly different.
- [ ] Ride a scored sprint (the first in Easy 30). Expected: the crowd grows as it comes on screen, claps and rings its bell on your cadence, cheers at the finish, and fades as it leaves the screen. There is no crowd in the warm-up.
- [ ] Ride above FTP for three minutes. Expected: your breath and the bottom bracket come up with the effort. If the breath tires you, say so: it gets deleted, not hidden.
- [ ] Note what tires you over half an hour, and set the levels in Settings > Audio (Machines holds your legs and chain: it goes silent when you stop pedalling; Effects the tyres, wind, freewheel, bell and crowd; Ambience the birds, grass and what is far off).
