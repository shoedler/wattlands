# Decisions: audio-fishing

Short ADRs for Turbo Reel's sound (`assets/fishing/audio/audio.json`, `FishingAudio`). "SPEC" is the run's SPEC_AUDIO.

## 2026-10-31 The stroke fractions, read off the drawn crank

- Decision: keep SPEC 4.2's fractions. `FishingRig.drivetrain` draws the pedal at `(cos a, sin a)`, clockwise with y down, so at 0 and .5 a foot is level and starts down (the putt, one per foot), at .25 and .75 the crank is at its bottom and top dead centre (the line takes up, the valve ticks). `crank_clock` is the only phase source.
- Alternatives: a power-stroke offset for the putt.
- Reason: the picture and the sound agree, and `test_the_stroke_fractions_come_from_the_art` holds it.

## 2026-10-31 `load` from effective power, not `prop`

- Decision: the engine's brightness and level follow `load` (`p_eff_w / P_EFF_REF_W`, on the snapshot, so a client has it). `prop` only gates the putt and scales the water.
- Alternatives: SPEC's `prop` alone.
- Reason: `prop_drive` is `|v| / 4`, capped at 1.5, so it saturates at 6 m/s while a boat cruises at 15. An engine driven by it would be flat for nearly the whole ride. The cap belongs to the prop animation and stays.

## 2026-10-31 Composite params for two-way gates

- Decision: a `when` reads one param (AUDIO_PIPELINE), so the adapter sends `prop` (zero once the clutch is halfway to the winch) and `reel` (the smoothed line speed, zero unless fishing and not on a run). `winch` keeps the plain line speed.
- Alternatives: a two-param `when` in the kit.
- Reason: no platform change, and the state logic stays in the adapter. The line speed is smoothed over 150 ms because on a client it arrives in 10 Hz steps and the ratchet would stutter.

## 2026-10-31 Sounds beyond SPEC 4.2

- Decision: added `valve_tick` (.25 .75, lead only), `exhaust_crack` (just after each putt from `load` .6), `drive_whine` (the gear train's whistle, by `rpm` and `load`), `exhaust_burble` (`LiftOffDetector`, driving only), `cast_whip`, `fanfare_4` (a trophy's top note), `gull_far`, `hull_creak`, `fish_plop`, and the cues `jump_1`, `jump_3`, `landed_trophy`. Each leap's fall lands on the view's own timing (`FishingView.LEAP_S / n`).
- Alternatives: the bare list.
- Reason: the owner asked for an engine with valve sounds, a whistle and crackle rather than a monotone rumble, and these are the same idea at this boat's scale.

## 2026-10-31 Other boats fall away with distance

- Decision: a `near` param, 1 within 150 m and 0 from 700 m, takes up to -26 dB off another boat's strokes and loops on top of `mix.other_db`. Out of earshot the boat is not driven at all: its loops close, no stroke plans, and it comes back with no burst.
- Alternatives: -10 dB everywhere on the ocean, as SPEC reads.
- Reason: boats share one ocean, and a rider 3 km away clanking at -10 dB tells you nothing and costs voices. Cues stay at `other_db` wherever the rider is: another rider's catch is news.

## 2026-10-31 The hull slap's edge comes from the heave, not `heave_rate`

- Decision: `_hull_slap` differentiates `heave_m`, smoothed over 250 ms, instead of SPEC's `heave_rate`.
- Alternatives: `heave_rate`.
- Reason: the snapshot carries only the heave in cm, so a client's `heave_rate` is always 0. One 1 cm snapshot step must not read as a fall, and a test says so.

## 2026-10-31 `plane_wash` is a `loops` entry on Ambience

- Decision: it runs from `plane` whatever the crank does.
- Alternatives: a machine loop, which would cut the wash dead at 0 rpm while the hull is still planing.
- Reason: a rider who stops pedalling on the plane still skids over the water.

## 2026-10-31 The mix against the safety prompts

- Decision: the putt falls with cadence (`rpm` on its level: +1.5 dB at 60, -2.6 at 110), so a rider's loudest moment is no louder per second, and steady water carries more of the level than strokes do. The drag scream sits at -9.5 dB.
- Alternatives: louder peaks, as in the first pass (D5 +4.76 LU at 110 rpm; +2.73 under a run with a jump).
- Reason: BRIEF 4.6 first: a prompt has to cut through, and rescue happens in fights. Numbers at this bank: mix -19.89 LUFS, LRA 5.7, D5 +6.11 LU at the scorecard's midpoint. Measured at 11 other moments of the preview, a prompt reads +5.4 to +12.9 LU; it dips under 6 when it meets a stroke pair at speed, a hull slap, or the catch's fanfare (+5.97). A1's floor (-20) and D5's floor leave a window about 0.2 dB wide on this bank, so any level change here should rerun the scorecard.

## 2026-10-31 Preview seed 8

- Decision: `preview.seed` is 8, one of the seeds where A13 (the speed bands of `hull_slap` have separate round-robins) and A16 (two details within 2 s) pass in the rendered minute.
- Alternatives: a waiver; a gap wide enough that the spots never meet, which would thin the sea.
- Reason: the rows are about a typical minute, and neither event is audible as a fault. In a real session a chance repeat or two near-coincident spots can still happen.
