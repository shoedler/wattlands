# Decisions: Workout audio

## 2026-10-31: `pedal_press` at .25 and .75, not 0 and .5

- Decision: the press sounds with a pedal furthest forward (rider sheet frames 6 and 18), where the foot pushes hardest. `chain_tick` stays at 0, the dead spot with the near pedal on top.
- Alternatives: SPEC_AUDIO 4.4's 0 and .5, which sound with a pedal on top, a quarter of a revolution before the leg shows any push.
- Reason: SPEC_AUDIO 2.3, fractions come from the art, and the art landed after the table was written. Tests in GUT and Node read `kit.rider.near_pedal` and `rig.mjs`.

## 2026-10-31: Other riders carry a quiet `chain_hum` as well as the tick

- Decision: `chain_hum` has `other: true`, `mix.other_db` is -9.4. Machines against the lead at the same power: one other rider -11.35 LU (scorecard A2 -11.81, its window -8 to -12), seven real-bot cadences (90 rpm, sd 0.6) -8.59, seven at 88-112 rpm -8.34: the group stays at -8 or under, and `workout_bank.test.mjs` holds that. Exactly equal pitch would read -0.51, but a real group starting together measures 1.6 dB under its steady level in its first 300 ms, so there is no start swell at real cadences. In real players with 8 riders at speed and a crowd (the GUT test and the bench): loops peak 15-16 of 24, Machines 6 of 16, Sfx 2 of 16, voiceless 0.
- Alternatives: SPEC_AUDIO 4.4's tick alone: -17.5 LU at `other_db` -6, and only 0 dB `other_db` reaches the window, which puts others' ticks at the level of your own and blurs the rhythm you ride to. A waiver on A2, which would also hide its other columns.
- Reason: the group is heard as a whirr around you and your own strokes stay the clearest rhythm.

## 2026-10-31: The crowd follows the view's crowd, not `is_sprint`

- Decision: `crowd_loop`, the claps and the cheer exist only when `WorkoutCrowd` draws a crowd (`cheers_for`). Level follows distance to the crowd on screen, 0 at either screen edge.
- Alternatives: SPEC_AUDIO 4.4's "while a sprint phase runs", which would cheer a warm-up sprint.
- Reason: BRIEF 4.6.8 outranks the sound list: a cheering crowd in the warm-up asks for the effort the warm-up forbids. The view already rules it out, and the sound now cannot disagree with the picture.

## 2026-10-31: The crowd and the breath are cadence machines

- Decision: machines `crowd` (`crowd_clap` at 0, `cowbell` at .5, the moments the view's hands drop and rise) and `breath` (driven with `revs / 2`, the view's breath-cloud rule, above FTP only). `bb_creak` under load in `bike`. All lead only.
- Alternatives: spots or cues on timers, which would drift off the rider.
- Reason: the owner's first demand is 1:1 with cadence; whatever the picture moves on cadence sounds on cadence. These go beyond SPEC_AUDIO's list and stay within the WAV cap.

## 2026-10-31: Small ones

- `gear_click_up` and `gear_click_down` are two sounds, not two variants: `kit.cue` round-robins variants, and the two directions must differ. `chain_shift` fires when `game.cranks` passes a quarter of a revolution on, never on a timer, and is dropped if the rider falls under 10 rpm or the ride pauses first: a chain that is not moving cannot cross.
- `tyre_hum` and `wind_rush` close when the sim goes quiet: the state keeps its last speed under a pause or at the end.
- `interval_bell` starts 0.42 s after a phase change, so `interval_chime` and it read as "done, then next", not as one chord. Scorecard A14 therefore checks `interval_end`.
- `tractor_far` plays only while `WorkoutSpots` has a tractor crossing. The adapter builds the same seeded list as the view, since that list is the view's private.
- `WorkoutAudio.gust_at` repeats the formula in `WorkoutRideView._env_step`, because this branch edits the view only at the adapter's creation and update call. A test pins the two together. WS-CLEANUP can merge them.
- `freewheel_tick` no longer reads `shown_distance` directly: on a host that moves only on the 20 Hz sim step, which put a coast's ticks on a grid (stddev 11-14 ms). `WorkoutAudio._wheel_distance` integrates speed per frame, closes on the shown distance with a 0.4 s one-pole, never runs back and follows a jump over 4 m at once. Inter-tick stddev is under the kit's 4 ms at 3, 5, 7, 9 and 13 m/s, at 60 and 144 fps, against a 20 Hz stepped distance.
- D10, this game: `WorkoutAudio.update` with the kit's commit, 8 riders at 12 m/s with a crowd, 1503 frames at 60 fps, real players on the Dummy driver: mean 0.371 ms, p50 0.339, p99 1.07, max 12.3 (a contended machine; other agents were running). Silent: mean 0.273. Passes 0.5 ms mean. Most of the cost is logic, so the margin is not large. The Dummy driver does not represent a real device.
- The fatigue rule (SPEC_AUDIO 5, -16 dB above 2 kHz against the main stroke) is read by energy. `chain_tick` is -34 to -36 dB by energy at any load, -8 to -10 by peak; the rule never said which. A tick is short and a peak does not tire: `workout_bank.test.mjs` tests energy at five loads.
- A16 passes on the preview seed 12. Over seeds 1 to 16 about half have one pair of details within 2 s in 60 s: the kit keeps no distance between spots, and the row is a proxy with the tractor always on. A collision in the game is two far sounds at once, which is acceptable.
- Unverified, and no number here can say: whether it sounds like a bike, whether the breath tires over a 3 x 8 threshold set, and the balance over a real fan and trainer. Those wait for the Listen step in `HARDWARE_TEST.md`.

## 2026-10-31: Tyres, wind and the wheel are on Sfx, not Machines

- Decision: `tyre_hum`, `tyre_grit`, `wind_rush` and machine `wheel` play on Sfx. Machines holds what stops with the legs, within 120 ms, and that is true in the game, not only in the preview: the preview's stop is now a real coast (rpm 0, speed held) with tyres, wind and ticks running over a silent Machines bus. D4 reads -300 dB, a GUT test holds the 120 ms at speed.
- Alternatives: Machines, where D4 passed only because the preview scripted an impossible stop. Ambience, where the road and the bed together pass A2's -29 LUFS ceiling.
- Reason: legs stop, wheel rolls, and a D row must describe the game. Settings' Machines slider now means your bike's drivetrain; Effects holds the road and the crowd.

## 2026-10-31: A steady block moves on its own clocks

- Decision: `wind_rush` follows the view's gust (level -8..+2 dB, pitch .9..1.12). `tyre_hum` follows `road_at(distance)` (-3..+3 dB) and brings in `tyre_grit` on rough stretches, so level and timbre both move. Road stretches sound the same each time you ride them. The preview has a 36 s sweep of both at one power and speed.
- Alternatives: leaving it to power changes, which a block of Easy 30 (90 % ERG) does not have: 180 s at 90 rpm, power .65 measured LRA 0.2 LU.
- Reason: now LRA 2.04 LU, 3 s range 2.29 dB on machines and road, 10 s centroid stdev 2.04 %. The critic's scratch reached a higher centroid figure on a brighter mix; the brightness item below takes that away, so `tyre_grit` is added beyond its list.

## 2026-10-31: The rest of the critic's round, with numbers

- Repetition: `chain_tick` 5 variants and a 7-step pitch table, `pedal_press` a 5-step table, with narrow level spreads. The cycle is 105 revolutions (70 s at 90 rpm), was 12. Strokes-only correlation at 12 revolutions .92, was .999; at 3, .91, was .98. `chain_hum` 3.72 s, chosen so its 75 and 150 Hz close on the tile.
- Birds: the crossing has no hole (solo -47.1 at day .2, -50.9 at .42, -49.8 at .7; was -68 at .42). Slow calls left the loops for spots (`chirrup` 5 variants, 2 of them far: comb, low-pass, 3 dB lower; `wood_call`). `birds_dawn` 4 s, `birds_day` 3 s, width .55, LR correlation .65.
- `power_line_hum` is gone, past SPEC_AUDIO 4.4: its 100 Hz sine sat under the press and could not be heard. `church_bell_far` takes the slot, on the C pentatonic scale, gap 90-200 s, so the bed has something on a scale of minutes. The family test keeps 11025 Hz for loops, so `tractor_far` and the bell are 22050 Hz mono one-shots instead of the critic's 11025.
- Spots over the machines at endurance (share of a spot's cells 3 dB above them): lark 81 %, chirrup 73 %, wood call 73 %, rooster 23 %, dog 15 %, tractor 12 %, bell 8 %.
- Load: whole-machine power-weighted centroid .65 to 1.05 FTP, 697 to 830 Hz, +19 % (was flat above .8). Over the rest of the machines: rattle 11/23/34 % at .65/.95/1.2, creak 6 % at 1.2, breath 4/7 % at 1/1.2. These layers now do something.
- Press: no longer a kick (sine .5 at 112-82 Hz, d .08), its grind stands up (pink 1250 gain 2.6, low-passed under 2 kHz for the fatigue rule).
- Brightness: at endurance the mix centroid is 735 Hz, was 976; above 4 kHz 2.4 %, was 4.9 %. Each steady loop has more of its own band: tyres 250-500 Hz down, chain 500-2000, wind flat and quiet.
- Road tiles: `wind_rush` 7.36 s and aperiodic, 2-5 kHz envelope correlation at half a tile -.27, was -.93. `tyre_hum` 4.27 s. `wind_grass_hi` has no dip at its seam. `wind_grass_lo` still repeats every 11 s in solo: gust and speed move it in the mix, and a longer tile does not fit the cap.
- Total WAV 3.914 MB of 4.

## 2026-10-31: A phase change stacks chime, dyad, toast, then bell

- Decision: levels stay. Measured over the road and bike with the platform's `phase` and `toast` at `HudLayer`'s -4 dB: first 250 ms +9 dB in 1-4 kHz, bell +8.8 dB, chime 9 dB over `phase` and `toast` in its own band, no clipping. `workout_bank.test.mjs` renders this, since a bank's preview block cannot play a `_shared` sound.
- Open: the same step also plays `warning`, from `HudLayer.show_banner`, on every non-cool-down interval: a safety prompt that cries wolf and ducks all of the above. The fix is a platform field (`HudSpec.banner_sound`, default unchanged), requested from the lead with a tested patch. Until it lands the rider still hears it. Tank's segment banner has the same sound.

