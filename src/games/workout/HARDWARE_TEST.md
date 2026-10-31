# Workout: real-trainer checklist

A checklist for Simon with the real KICKR CORE (BRIEF 4.7). `docs/HARDWARE_TEST_PLAN.md` links here from its Workout section. Nothing here ran during the build: every automated run used MockTrainer with the hardware lock set. Do the platform plan's "Before you start", probe, connect, SIM flat and panic steps first, and stop at the first failed safety check.

Commands that drive the trainer pass `--allow-hw` to the wrapper (`tools/godot.ps1` on Windows, `tools/godot.sh` in Git Bash). Use the log template from `docs/HARDWARE_TEST_PLAN.md` for every step.

## 1. Easy 30, solo, with zero input

- [ ] Hold a steady cadence on the title screen for 5 s with a saved profile (or 20 s on a first run). Expected: Workout's Easy 30 starts solo without a key press.
- [ ] Warm-up (0:00–5:00). Expected: ERG ramps from 50% to 65% FTP (×0.85 with an unverified FTP); the warm-up banner shows; targets never exceed 65%; the timeline and the interval blocks on the ground scroll; your pennant sits under the "now" mark.
- [ ] Endurance 1 (5:00–11:00) at 65% FTP. Expected: the power gauge glows while you stay within ±5% of the target; the "In band" readout climbs toward 100%.
- [ ] Ten seconds before minute 11, a "Sprint in 10 s" toast. At 11:00 the trainer switches to SIM flat with no surge. Expected: the gear indicator appears; shift up and down (E/Q, RT/LT) and feel each step change resistance by roughly 6–8%; the gauge shows a 120–160% FTP band.
- [ ] Sprint above 1.2 × FTP for at least 3 s. Expected: at 11:30 a "Sprint! Peak … W" toast; ERG resumes at or below 65% FTP and slews up (no spike).
- [ ] Repeat for the sprints at 17:00 and 23:00, then the cool-down at 25:00 (50% FTP, 3 minutes). Expected: results with a grade, time in band per interval, sprint peaks, kJ and XP; a FIT file with 9 laps (8 phases plus the cool-down); the first ride unlocks the swallowtail pennant.

## 2. Rescue in a work interval

- [ ] In Endurance 2 (65% FTP, above the 60% rescue threshold), drop below 45 rpm for 3 s. Expected: the target drops to 50% FTP, the rescue banner shows, your pennant droops on the road, and the time-in-band readout stops rising. Hold 70 rpm for 3 s: the target ramps back over 10 s and the pennant lifts.

## 3. VO2, 5 minutes from the first interval

- [ ] Start VO2 (skip the warm-up in Settings only if you already warmed up). Expected: 3-minute blocks at 110% FTP with 3-minute recoveries at 50%; no duration-limit clamp (each block stays under the 300 s limit above 105%).

## 4. Rolling road for 5 minutes

- [ ] Start Rolling road and ride into the SIM phase at 5:00. Expected: the switch to SIM is smooth; the road on screen rises and falls with the course; resistance follows the grade (scaled by the difficulty setting) and the gears work; the gauge shows a 76–105% FTP band and glows inside it.

## 5. Group ride on two PCs

- [ ] PC A hosts Sweet spot with one bot; PC B joins with the code. Expected: both riders and the bot ride the same timeline at their own % FTP; the teammate strip shows each rider's in-band state and time in band; interval-done toasts reach only their own rider; both PCs show the same pennants moving at their riders' speeds.
- [ ] Kill the app on PC B mid-interval and restart it with the same profile. Expected: it rejoins, the view and timeline come back within a second, and PC B's rider is out of band only while it was gone.

## 6. A .zwo of your own

- [ ] Start the app with `--content=zwo:<absolute path to a .zwo>` (or pick Sample .zwo in the lobby). Expected: the session preview lists every clamped block with its reason and every skipped tag; the ride follows the clamped targets.

## 7. Listen

Nobody has heard this audio: every number behind it was measured offline. Listen with the sound on, over the fan and the trainer.

- [ ] Before riding, play `build/audio_preview/workout.mp3` (`node tools/audio/preview.mjs --game=workout`). Expected: a bike, not an engine: a chain, a soft push on each pedal, tyres and wind that grow with speed, birds in the grass.
- [ ] Ride Easy 30 at 60, then 90, then 110 rpm. Expected: tick and press stay with the legs on screen at every cadence and stop as your legs stop; the sound follows your feet in rate, not in phase (FTMS reports cadence about once a second).
- [ ] Stop pedalling at speed. Expected: the chain stops dead, the freewheel ticks on, evenly, slowing with the wheel; tyres and wind fade as you slow.
- [ ] Ride ten minutes of a steady block with 7 bots. Expected: it does not freeze: gusts in the wind, patches of rougher road in the tyres, a far bell or dog now and then. The group is a whirr behind you, your own strokes stay the clearest rhythm, and it does not swell when everyone starts or resumes together.
- [ ] Go through a phase change. Expected: the chime, a beat later the bell, the banner silent. The warning sound plays only for a real safety prompt.
- [ ] Shift in a sprint. Expected: a click, then the chain crossing a moment later, up and down audibly different.
- [ ] Ride a scored sprint (the first in Easy 30). Expected: the crowd grows as it comes on screen, claps and rings its bell on your cadence, cheers at the finish, and fades as it leaves the screen. There is no crowd in the warm-up.
- [ ] Note what tires you over half an hour, and set the levels in Settings > Audio (Machines holds your legs and chain: it goes silent when you stop pedalling; Effects the tyres, wind, freewheel, bell and crowd; Ambience the birds, grass and what is far off).
