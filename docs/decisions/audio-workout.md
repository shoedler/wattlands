# Decisions: Workout audio

## 2026-10-31: `pedal_press` at .25 and .75, not 0 and .5

- Decision: the press sounds with a pedal furthest forward (rider sheet frames 6 and 18), where the foot pushes hardest. `chain_tick` stays at 0, the dead spot with the near pedal on top.
- Alternatives: SPEC_AUDIO 4.4's 0 and .5, which sound with a pedal on top, a quarter of a revolution before the leg shows any push.
- Reason: SPEC_AUDIO 2.3, fractions come from the art, and the art landed after the table was written. Tests in GUT and Node read `kit.rider.near_pedal` and `rig.mjs`.

## 2026-10-31: Other riders carry a quiet `chain_hum` as well as the tick

- Decision: `chain_hum` has `other: true`, `mix.other_db` is -7.5. One other rider measures -11.5 LU against the lead (A2's window is -8 to -12). Eight riders peak at 12 loop players of 24.
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

- `gear_click_up` and `gear_click_down` are two sounds, not two variants: `kit.cue` round-robins variants, and the two directions must differ. `chain_shift` waits a quarter of a revolution, and stays silent under 10 rpm: a chain that is not moving cannot cross.
- `tyre_hum` and `wind_rush` sit on Machines, with the bike the rider is on, so Settings' Ambience slider holds the world. Scorecard D4 measures the preview's stop, where they stop too; in the game they run on while the wheel does, since a coast is real. They close when the sim goes quiet: the state keeps its last speed under a pause or at the end.
- `interval_bell` starts 0.42 s after a phase change, so `interval_chime` and it read as "done, then next", not as one chord. Scorecard A14 therefore checks `interval_end`.
- `tractor_far` plays only while `WorkoutSpots` has a tractor crossing. The adapter builds the same seeded list as the view, since that list is the view's private.
- `WorkoutAudio.gust_at` repeats the formula in `WorkoutRideView._env_step`, because this branch edits the view only at the adapter's creation and update call. A test pins the two together. WS-CLEANUP can merge them.
- Unverified, and no number here can say: whether it sounds like a bike, whether the breath tires over a 3 x 8 threshold set, and the balance over a real fan and trainer. Those wait for the Listen step in `HARDWARE_TEST.md`.
