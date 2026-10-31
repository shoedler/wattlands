# Decisions: Workout audio

## 2026-10-31: `pedal_press` at .25 and .75, not 0 and .5

- Decision: the press sounds with a pedal furthest forward (rider sheet frames 6 and 18), where the foot pushes hardest. `chain_tick` stays at 0, the dead spot with the near pedal on top.
- Alternatives: SPEC_AUDIO 4.4's 0 and .5, which sound with a pedal on top, a quarter of a revolution before the leg shows any push.
- Reason: SPEC_AUDIO 2.3, fractions come from the art, and the art landed after the table was written. Tests in GUT and Node read `kit.rider.near_pedal` and `rig.mjs`.

## 2026-10-31: Other riders carry `peer_tick` and no loop

- Decision: machine `peer_bike` for everyone but the local rider, one mono stroke per revolution, `peer_tick` (3 variants, a 5-step pitch table, 2.2-5 kHz metal over a soft 1.8 kHz body), `mix.other_db` -4. No other rider plays a loop. Machines against the lead: one other -10.61 LU (scorecard A2 -11.24), seven real-bot cadences -12.68, seven at 88-112 rpm -11.04, five of seven at exactly equal rpm -13.63. Real players with 8 riders at speed and a crowd: loops peak 9 of 24 (was 16), Machines 5, Sfx 2, voiceless 0.
- Alternatives: `chain_hum` for others at -9.4, as the last round had it. Its share of cells 3 dB above the rest of the mix was about 5 % on the measure in `workout_bank.test.mjs`, the mix rose 0.2-0.5 dB in every octave with no change of shape (the critic's own measure: +0.5-0.8 dB), and it cost 7 players. On a client a resume also restarted every hum from sample 0 at one pitch, a swell of up to +8.7 dB (the critic's model), which a detune could only reduce. `chain_tick` for others: to reach A2 it needs the level of your own tick, which blurs the rhythm you ride to. A stereo `peer_tick` panned +-.5, the critic's other option: `AudioBank` and `bank.mjs` both refuse a stereo machine event, and `family.test.mjs` holds it, so that is a platform change for one game. Not worth it, and panned round-robin would throw one rider's crank from side to side.
- Reason: SPEC_AUDIO 4.4 and its risk 8 asked for one stroke and no loops, and this is what makes a group: the same budget in its own band. It clears the rest in 14.3 % of its cells, the mix changes shape (0.0 dB at 350 Hz, +0.56 dB at 2.8 kHz), your own rhythm holds (300-1500 Hz 10.5 dB alone, 10.4 among them; 1.5-4 kHz 10.2 and 9.5), and with no loop nothing can lock in phase: five riders with one crank and one rpm read 1.7-6.3 dB under the steady group, because the kit's 60 ms gap thins strokes that coincide. Two-speaker width stays unavailable to it.

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
- `WorkoutAudio.gust_at` repeats the formula in `WorkoutRideView._env_step`, because this branch edits the view only at the adapter's creation and update call. A test pins the two together, and WS-CLEANUP can merge them. What you hear follows `air_at`, half of that gust and half a slower swell: the picture has no reason to change.
- `freewheel_tick` no longer reads `shown_distance` directly: on a host that moves only on the 20 Hz sim step, which put a coast's ticks on a grid (stddev 11-14 ms). `WorkoutAudio._wheel_distance` integrates speed per frame, closes on the shown distance with a 0.4 s one-pole, never runs back and follows a jump over 4 m at once. Inter-tick stddev is under the kit's 4 ms at 3, 5, 7, 9 and 13 m/s, at 60 and 144 fps, against a 20 Hz stepped distance.
- D10, this game: `WorkoutAudio.update` with the kit's commit, 8 riders at 12 m/s with a crowd, 1503 frames at 60 fps, real players on the Dummy driver: mean 0.371 ms, p50 0.339, p99 1.07, max 12.3 (a contended machine; other agents were running). Silent: mean 0.273. Passes 0.5 ms mean. This was measured with a loop per other rider, and that loop is gone; not re-measured. The Dummy driver does not represent a real device.
- The fatigue rule (SPEC_AUDIO 5, -16 dB above 2 kHz against the main stroke) is read by energy. `chain_tick` is -34 to -36 dB by energy at any load, -8 to -10 by peak; the rule never said which. A tick is short and a peak does not tire: `workout_bank.test.mjs` tests energy at five loads.
- A16 passes on the preview seed 12. Over seeds 1 to 16 about half have one pair of details within 2 s in 60 s: the kit keeps no distance between spots, and the row is a proxy with the tractor always on. A collision in the game is two far sounds at once, which is acceptable.
- Unverified, and no number here can say: whether it sounds like a bike, whether the breath tires over a 3 x 8 threshold set, and the balance over a real fan and trainer. Those wait for the Listen step in `HARDWARE_TEST.md`.

## 2026-10-31: Tyres, wind and the wheel are on Sfx, not Machines

- Decision: `tyre_hum`, `tyre_grit`, `wind_rush` and machine `wheel` play on Sfx. Machines holds what stops with the legs, within 120 ms, and that is true in the game, not only in the preview: the preview's stop is now a real coast (rpm 0, speed held) with tyres, wind and ticks running over a silent Machines bus. D4 reads -300 dB, a GUT test holds the 120 ms at speed.
- Alternatives: Machines, where D4 passed only because the preview scripted an impossible stop. Ambience, where the road and the bed together pass A2's -29 LUFS ceiling.
- Reason: legs stop, wheel rolls, and a D row must describe the game. Settings' Machines slider now means your bike's drivetrain; Effects holds the road and the crowd.

## 2026-10-31: A steady block moves on its own clocks, and none of them repeat

- Decision: `wind_rush` and the grass follow `air_at(env_t)` (level -8..+2 dB, pitch .9..1.12), half the view's gust and half a swell on 23 and 61 s. `tyre_hum` follows `road_at(distance)`, on 59, 157 and 367 m (-3..+3 dB), and brings in `tyre_grit` on rough stretches, so level and timbre both move. Road stretches sound the same each time you ride them. The preview has a 36 s sweep of both at one power and speed.
- Alternatives: the gust alone, which correlates 1.00 with itself at 35 s (3.7 and 11 are close to 1:3), and the earlier `road_at` on 97 and 31 m, which at 8.5 m/s falls on the same 11.4 s and 3.65 s: about 51 identical swells in 30 minutes, at a mix correlation of .92. LRA and a 3 s range cannot see that. Leaving it to power changes, which a block of Easy 30 (90 % ERG) does not have: 180 s at 90 rpm, power .65 measured LRA 0.2 LU.
- Reason: in a 300 s render at 90 rpm, power .65, 8.5 m/s, 1 s levels correlate under .7 at every lag from 10 to 150 s, and `workout_bank.test.mjs` holds that. Mix .22 at 35 s, -.52 at 69 s, best lag 88 s at .52. Road .27, -.74, 88 s at .65, 3 s range 4.91 dB. The bike alone holds 0.33 dB: nothing else moves it, by design, since its level belongs to your power. The mix's LRA reads 1.22 LU here, lower than the 2.04 of the louder road before: this block moves in the road and the air, not by much in the whole. A human has to say if that is enough.

## 2026-10-31: The rest of the critic's rounds, with numbers

- Repetition: `chain_tick` 5 variants and a 7-step pitch table. `pedal_press` 5 variants, close in pitch and level (spread .9 dB), and a 4-step table. The cycle of both is 70 revolutions; the press alone repeats exactly at 10, and a lag 5 centroid cycle (2.5 revolutions) remains. The 3-beat accent is gone: centroid per stroke at lag 3 -.19, was 1.00; press waveform at 1.5 revolutions .82, was .97. Strokes-only correlation at 12 revolutions .82, was .999. `chain_hum` 3.72 s, chosen so its 75 and 150 Hz close on the tile.
- Your rhythm in the mix: the road is under the strokes. `tyre_hum` -7.5, `tyre_grit` -9.5, `wind_rush` -4.5, `chain_hum` -7, `chain_tick` 1.5, `pedal_press` 2, and at low power `chain_hum` falls further and `pedal_press` less. Peak over median of the envelope synchronous with the revolution, 90 rpm, power .65: 300-1500 Hz 10.3 dB (rough road 9.6), 1.5-4 kHz 10.1 (rough road 9.4), against 7.7 and 9.7 last round and 8.0 and 9.2 in the old preview. One revolution in the whole mix now spans at least 9 dB at 60, 90 and 110 rpm.
- Birds: `birds_dawn` at -25 sits under the birds it should carry: its 100 ms peak -46.1 dB in a dawn mix against -33.5 for lark, chirrup and wood call, and the mix's 4-8 kHz envelope at its 4 s correlates .33, was .575. The crossing to day dips at most 2 dB under its quieter end. Slow calls left the loops for spots (`chirrup` 5 variants, 2 of them far: comb, low-pass, 3 dB lower; `wood_call` 3 contours, gap up to 30 s; `lark` 2 contours). `birds_day` 3 s, width .55.
- `power_line_hum` is gone, past SPEC_AUDIO 4.4: its 100 Hz sine sat under the press and could not be heard. `church_bell_far` takes the slot, gap 90-200 s, so the bed has something on a scale of minutes. Its notes are A, D on the C pentatonic scale (440-2349 Hz), and it shares none with the chime (C6, E6) or the bell (G6), so a rider who has learned the cues never takes it for a phase change. The family test keeps 11025 Hz for loops, so `tractor_far` and the bell are 22050 Hz mono one-shots.
- The far stratum reads at endurance: `dog_far` [-13, -9], `church_bell_far` [-18, -14]. Best third-octave over the rest of the mix in a 93 ms window, the median play, 90 rpm, 8.5 m/s: dog -4.2 dB (the old levels -10.9), bell +6.4 (+3.6 at the old level). The dog is still masked in its median play and carries on its peaks: a far dog, not a near one.
- Load: the breath and the creak were not heard over the road. `breath` -5, its band down to 1400 Hz for the fatigue rule. `bb_creak` -2. Share of cells 3 dB above everything else in the real mix, on the test's measure: breath 8.4 % at 110 rpm, power 1.05, and 11.2 % at 100 rpm, power 1.2 (2.5 and 3.6 at the old levels); creak 4.3 and 5.7 % (1.3 and 1.9). The critic's stricter measure read 3.5 and 5.8, 1.2 and 2.2 for these levels. If a human finds the breath tiring, delete it rather than keep it inaudible.
- Brightness: above 4 kHz 3.3 % in the preview, within A8.
- Road tiles: `wind_rush` 7.36 s and aperiodic, 2-5 kHz envelope correlation at half a tile -.27, was -.93. `tyre_hum` 4.27 s. `wind_grass_hi` had a 13.2 dB dip repeating every 7 s in 1.5-8 kHz, from its own envelope and its grains' (`rotateToQuietStep` only moves where the file starts), which showed at low speed: 6.7 dB now. `wind_grass_lo` still repeats every 11 s in solo: air and speed move it in the mix, and a longer tile does not fit the cap.
- `crowd_loop` no longer pumps on 2.5 and 5 Hz against claps on your cadence: both tremolos became aperiodic envelopes at the same bytes, 1.6 dB 5-95 %, was 3.9. The tile itself still repeats at 2.8 s, under grains and claps.
- Total WAV 3.990 MB of 4: nothing more fits without taking something out.

## 2026-10-31: A phase change stacks chime, dyad, toast, then bell

- Decision: levels stay. Measured over the road and bike with the platform's `phase` and `toast` at `HudLayer`'s -4 dB: first 250 ms +9 dB in 1-4 kHz, bell +8.8 dB, chime 9 dB over `phase` and `toast` in its own band, no clipping. `workout_bank.test.mjs` renders this, since a bank's preview block cannot play a `_shared` sound.
- `warning` is not in the stack: `HudLayer.show_banner` played it on every non-cool-down interval, a safety prompt that cried wolf and ducked all of the above, 8 false alarms in Easy 30. The platform's `HudSpec.banner_sound` (default unchanged) lets Workout set it to `""`: the banner still shows, the chime and bell carry the change, and `warning` means a real safety prompt. `test_a_routine_banner_cries_no_wolf_through_the_real_hud` holds it. Tank's segment banner has the same sound.
