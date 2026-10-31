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

- Decision: added `valve_tick` (.25 .75, lead only), `exhaust_crack` (just after each putt from `load` .6), `drive_whine` (the gear train's whistle, by `rpm` and `load`), `exhaust_burble` (`LiftOffDetector`, driving only), `cast_whip`, `fanfare_4` (a trophy's top note), `gull_far`, `hull_creak`, `fish_plop`, and the cues `jump_1`, `jump_3`, `landed_trophy`, `clutch`. Each leap's fall lands on the view's own timing (`FishingView.LEAP_S / n`).
- Alternatives: the bare list.
- Reason: the owner asked for an engine with valve sounds, a whistle and crackle rather than a monotone rumble, and these are the same idea at this boat's scale.

## 2026-10-31 Other boats fall away with distance

- Decision: a `near` param, 1 within 150 m and 0 from 700 m, takes up to -26 dB off another boat's strokes and loops on top of `mix.other_db`. Out of earshot the boat is not driven at all: its loops close, no stroke plans, and it comes back with no burst. Its routine cues (cast, bite, turn, hookup, landing, run, thrown, the jumps, a snap) fall the same -26 dB through the kit's `db_var`, here `far_db`. A catch and a double hookup (landed, trophy, double hookup) stay at `other_db` wherever the rider is, and the horns are everyone's. A bite is not news: it is the one sound a waiting rider listens for, and with 3 others waiting a flat bell rang about 7 times a minute, 10 dB under your own. `mix.other_doubling_db` is -6, not -3.
- Alternatives: -10 dB everywhere on the ocean, as SPEC reads; every cue at `other_db`, as the first pass did.
- Reason: boats share one ocean, and a rider 3 km away clanking at -10 dB tells you nothing and costs voices. Another rider's catch is news; a turn clunk from 3 km with no engine under it is not. With -3 the lead over 7 near boats fell to +5.0 LU; -6 gives +10.4 LU with everyone driving and does not touch the 1-other row (+10.5 LU). Worst case left: you waiting at 70 rpm with 7 boats driving within 150 m, -0.9 LU, because a waiting boat is meant to be quiet.

## 2026-10-31 The hull slap's edge comes from the heave, not `heave_rate`

- Decision: `_hull_slap` differentiates `heave_m`, smoothed over 250 ms, instead of SPEC's `heave_rate`.
- Alternatives: `heave_rate`.
- Reason: the snapshot carries only the heave in cm, so a client's `heave_rate` is always 0. One 1 cm snapshot step must not read as a fall, and a test says so.

## 2026-10-31 `plane_wash` is a `loops` entry on Ambience

- Decision: it runs from `plane` whatever the crank does.
- Alternatives: a machine loop, which would cut the wash dead at 0 rpm while the hull is still planing.
- Reason: a rider who stops pedalling on the plane still skids over the water.

## 2026-10-31 The mix against the safety prompts

- Decision: the putt falls with cadence (`rpm` on its level: +1.5 dB at 60, -2.6 at 110), and steady water carries more of the level than strokes do. The loud cues came down: bite and `time_up`, `double_hookup` and `landed` by 2 to 3 dB, `landed_trophy` by 4, `trip_over` by 6, `snap` by 1. D5 needs the deeper safety duck as well (Machines and Ambience -14, Sfx -20 over 2 s, and D5 scored at the mix's loudest moment too; see the next ADR for how it got here). No curve is tuned to a D5 sample point.
- Alternatives: much larger cue cuts on today's duck (-6, -6, -4); a review trial of bite -7, landed and trophy -5, snap -7 and more still left bite +5.6 and took the reward out of a catch. Louder peaks, as in the first pass.
- Reason: BRIEF 4.6 first. The old claim here, +5.4 to +12.9 LU, came from 11 samples; a sweep every 0.5 s across the preview, states and cues says otherwise.
- Numbers, sweep of D5's metric on this bank, `warning` (rescue reads about 0.25 LU more):

| Where | Today's duck, main | Deeper duck, 9db55bc |
|---|---|---|
| Scorecard D5 | +6.12, midpoint only | +7.81, midpoint and loudest |
| Preview, 212 points | 41 under +6, worst +1.90 (bite) | 0 under +6, worst +8.24 |
| Steady, alone, 60 to 140 rpm | worst +4.91 (140 rpm, load 1.4), +5.06 at 90 rpm | worst +8.67 |
| Steady, 7 boats near | worst +3.95 | worst +7.84 |
| Prompt within 0.5 s of any cue | worst +1.4 (bite) | worst +7.3 (landed) |
| Run with jumps at 44 rpm, with 7 boats | worst +3.90 | worst +10.38 |

- The old duck does not meet BRIEF 4.6's +6 LU in plain riding or on a cue, whatever the scorecard's midpoint says. `fishing_bank.test.mjs` holds +6 at every row, with no fallback to the old floors. A2 stays in range (Sfx -15.22); no waiver.

## 2026-10-31 This branch carries the platform's duck itself

- Decision: `audio/fishing` cherry-picks the six `platform:` commits of `audio/workout` (9db55bc, dd5f83e, 39939eb, 43effbf, 635de98, 0daaa2b), with `-x`, so the branch stands on its own and scores on the platform it will ship with. The `floorLu` fallback in `fishing_bank.test.mjs` is gone.
- Alternatives: wait for the commit on main (a builder never lands on main); merge all of `audio/workout` here (lands Workout's sound with Fishing's); a merge-order rule alone (nothing enforces it, and the floors would stay at +1.2 LU meanwhile).
- Reason: BRIEF 4.6 first, and the merge order then cannot put a thin prompt on main. The six are all that `audio/workout` holds in `addons`, `tools/audio`, `tests/audio` and `docs/AUDIO_PIPELINE.md`, so those paths are identical on both branches and either can land first. `git merge-tree` of this branch with `audio/workout` at 0daaa2b has no conflicts. A later platform commit there on the same lines would conflict: take that branch's side.
- Numbers on this tip, D5's metric every 0.5 s over the preview: `warning` 0 of 213 points under +6, worst +8.11; `rescue` worst +8.37. Scorecard D5 +7.94. Steady riding, 7 boats, and every cue at the six offsets before and after it: over +6, by the test.

## 2026-10-31 Preview seed 8

- Decision: `preview.seed` stays 8, and it no longer matters which: the bed has `spot_min_gap_s` 2.2, the round-robin runs per sound, and the moving `hull_slap` bands are gone. A13 and A16 pass on seeds 1, 2, 3 and 8; A12 reads 0.36, 0.44, 0.25 and 0.40.
- Alternatives: a chance seed, as before; a waiver.
- Reason: a seed that happens to pass says little about a real session; the gap holds on every seed. A12 rose from 0.16 with fewer spots on the bed and still passes, the room is 0.06 at worst among these.

## 2026-10-31 Lift-off burbles once, and never over a stopped crank

- Decision: the burble needs `cadence` above `CrankClock.STOP_RPM`, fires once per lift, and re-arms only when `load` has risen by `LiftOffDetector.DROP` from its low. A pause resets the detector.
- Alternatives: the detector alone.
- Reason: on a client cadence is live and load comes in the 10 Hz snapshot, so load falls after the crank has stopped, and a Machines-bus burble then breaks D4 in play. The preview never hit it because its lift comes before its stop. The client case is reasoned from the code and pinned with falling-power shapes in GUT, not run on a client.

## 2026-10-31 A pause stands the boat

- Decision: while `EventBus.paused_changed` says paused, `bed_params` reads speed 0, and no hull slap or lift-off edge is taken; the heave and the detector start fresh on resume.
- Alternatives: leave the frozen speed in, as the first pass did.
- Reason: 16 fast-band slaps in 30 s described a moving hull over a frozen boat. The slow band's slaps go on at the kit's pause drop: a boat at rest still knocks.

## 2026-10-31 The clutch lever has a clunk both ways

- Decision: `clutch`, the falling edge of `fishing_target`, local boat only: `reel_clunk` at 0.84 pitch and `turn`'s level.
- Alternatives: a file of its own (D9 has about 56 KB left, and it is the same lever).
- Reason: the fishing brief lists a clutch clunk and says the lever flips; only the cast had one.

## 2026-10-31 Less tape in the engine

- Decision: `outboard_chug`'s `pitch_table` has 7 entries against 3 takes, a 21 revolution cycle. `outboard_body` is 1.4 s of whole cycles (62.142857 and 92.857143 Hz, tremolo 6.428571 and 17.142857 Hz), `winch_gear` 1.7 s (110 Hz, tremolo 10 and 20). `line_creak`'s variants step 1, 1.06, 0.94, 1.03 with a small `pitch_table`, 1.5 dB lower: under 2 semitones where it spanned 4.5.
- Alternatives: more variants, which D9 cannot pay for.
- Reason: the strokes and the 1.0 s body formed a tape: machine waveform correlation at lag 3 revolutions was 0.98, 0.85, 0.71 at 60, 90, 110 rpm. It reads 0.46, 0.29, 0.19 on this bank, and the cycle is 14 s at 90 rpm. A5 looks only at lag 1, so a test pins the lengths. At lag 21 the machine does still repeat (0.98 at 60 rpm).

## 2026-10-31 Details that can be heard

- Decision: `fish_plop` -19..-13 dB, the resting `hull_slap` band -16..-10 with an airier noise layer, `hull_creak` -25..-18; `waves_lo` and `waves_wash` 1 dB down to make room, a second `waves_wash` layer at 0.87 pitch so the swell does not repeat every 11 s, `wind_sea`'s whistle at 0.022 from 0.05.
- Alternatives: lengthen the files (`waves_wash` is 970 KB, D9 cannot pay).
- Reason: at sea these spots were 11 to 13 dB under the bed. The whistle was the most recognisable repeat in the bed. The first pass kept SPEC 4.2's two moving `hull_slap` bands; they were masked under power, and the next ADR replaces them.

## 2026-10-31 The swell: what a long crossing has to listen to

- Decision: a `swell` param, `FishingAudio.swell(x_m)` = 0.6 sin(2 pi x / 110) + 0.4 sin(2 pi x / 71), a place on the ocean that repeats only after 7810 m, so about 6.9 and 4.4 s a wave at 16 m/s and the same on a host and a client. It moves `outboard_chug` and `outboard_body` (-2 to +1 dB), `prop_churn` (-4 to +2 dB, pitch 1.04 to 0.96), the chug's pitch (1.02 to 0.98), `drive_whine` (-3 to +2 dB) and `plane_wash` (-4 to +2 dB). Strokes stay exactly on the crank: only their level and pitch ride the wave. The curves read 0 dB and pitch 1 at swell 0, so the preview, which does not set it, is unmoved.
- The `hull_slap` cue also fires on it, armed over +0.1, fired under -0.2, from `SLAP_MIN_MPS`: 8.7 a minute at 16 m/s, and it rises with speed. The heave's own edge stays. The bed's two moving `hull_slap` bands are gone (35 voices a minute, mostly masked), which leaves SPEC 4.2's "gap by speed" to the swell: at speed each wave comes sooner. The preview's slaps sit where this rule puts them on its course, and a test holds that.
- Alternatives: leave the crossing steady; a timer on the slap, which would not rise with speed; louder spots under power (a trial with +10, +12 and +6 dB only reached -1, -1 and 0 dB against the background, and made far gulls as loud as near ones).
- Reason: the brief puts a 250 W crossing at about 19 minutes, and steady riding gave the heave no slap at all: 0 in 10 minutes at steady 250 W, 170 W, +-10 %, +-20 %, 200-300 W steps and 300/150 W intervals. The old claim here, that the heave's cue is the one heard at speed, was false. Crossing at 85 rpm, load 1, 16 m/s, measured on this bank: LRA 0.38 without the swell, 1.59 with it, integrated -0.13 LU. A fight reads about 1.7.

## 2026-10-31 The plane wash's tape

- Decision: `plane_wash` runs as two layers of the one file at -13.6 dB each, the second at 0.86 of the first's pitch.
- Alternatives: a longer file (101 KB, D9 has about 56 KB free).
- Reason: 2.3 s of frozen noise, about 2.0 s at speed, is 570 repeats in 19 minutes, and above 2 kHz it is as loud as the chug. The reviewer's trial read waveform correlation at lag 2 s of 0.52 falling to 0.27. -13.8 rounded A8's top band under its floor, so the layers are 0.2 dB over. It costs one more loop player: D6 reads 24 of 24 with seven others, and 7 others x 2 layers plus a driving lead is the worst row. Not re-measured here.

## 2026-10-31 The sea changes on the way out

- Decision: a bed param `offshore`, 0 to 600 m out, 1 from 12 km. `waves_lo` +4 dB, both `waves_wash` layers -3 dB; `buoy_bell` only up to `offshore` 0.4. `hull_creak` -21..-14 (from -25..-18), `buoy_bell` -28..-22 (from -33..-26).
- Alternatives: stages by the game's zones (more params for one change); pushing the details under power.
- Reason: 98.6 % of the map had one recipe. Arrival now has a sound, heard where the bed is heard: stopped to fish. Measured waiting: bed -31.13 LUFS inshore, -30.15 offshore, machines unmoved at -31.35. Under power it will hardly be heard, and that is fine.

## 2026-10-31 No event goes unheard

- Decision: `SILENT_EVENTS` is empty. `landing` gets its cue (`zip` at 1.5 pitch and `splash_small`, no new file; local full, others -10 dB with `far_db`). `replacement` maps to `hookup`. Both go through `FishingCues.from_event`, and `diff` has the same edges. `FishingCues.merged` folds a replacement into a landing of the same rider in the same frame, because `begin_landing` raises both when the fish was off the line.
- Alternatives: leave them silent, as the first pass did.
- Reason: its reasons were wrong. The landed cue comes 15 s after `landing`, so the start of the gaff sprint, the game's biggest scoring call and an ERG to SIM switch, had neither sound nor toast. A new fish hooks itself 5 s after a snap, and the line loops came back with only a toast.

## 2026-10-31 Fatigue at high load, and a quiet wait

- Decision: `drive_whine`'s sine 0.34 to 0.16 and its noise 0.32 to 0.62, q 1.1; `exhaust_crack`'s load curve tops out at -7 dB instead of +1. Waiting at rest: `crank_knock` and `gear_tick` get their extra level partly from `tension` (+4 and +5 fishing, +5 and +4 once the line is tight), `winch_gear` falls to -17 dB at no tension.
- Alternatives: the review's flat `crank_knock` cut, which took A5 to 0.54 in the fight; here it comes back with the pull, and A5 reads 0.63.
- Reason: the whine stood +20.8 dB as two dead-straight lines near the ear's peak, and rides at FTP last 19 minutes. With nothing on the line the sea should lead: machines -31.3 LUFS against the bed's -31.2, where it was -27.0 against -31.0.
- To hold A1 after these cuts: `outboard_body` -8.1, `prop_churn` -9.4 (0.5 dB of the room the deeper duck left), `winch_gear` -4.8, `plane_wash` as above. A1 -19.80 LUFS, A5 0.63, A7 +6.81, A8 top band 2.0 %, A10 8.93, D5 +7.94: all pass, A5, A8 and A10 with little room.

## 2026-10-31 Sounds that should stop

- Decision: `exhaust_crack` is gated on `prop`, with a load curve from -40 dB at 0.55, so there is no crack after a putt that is not there with the clutch on the winch. The preview's fishing segments hold load 0.6 waiting and 1.0 fighting, as riders do. `line_tension`'s 2161.8 Hz sine goes from gain 0.16 to 0.09, about 5 dB: the reviewer read +14.5 dB at the ear's most sensitive region, in fights of up to 4.5 minutes. The 1064.7 Hz line stays as the warning.
- Alternatives: leave the 2.2 kHz line for its bite, which a listener may still want.
- Reason: from the numbers; nobody has listened yet.

## 2026-10-31 Left open

- Waiting with 7 boats driving within 150 m: the lead stands -0.9 LU. A boat that waits is meant to be quiet, and the brief's 5 minute drive-out has no bites.
- D6's loops read 24 of 24 in the eight-boat scenario: at the cap, not over.
- Cadence jitter on the engine's delta stays as the lead ruled (DAG 8.9).
