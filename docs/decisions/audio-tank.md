# Decisions: audio-tank

Short ADRs for Diesel Domestiques' sound on the audio kit. "SPEC" is the run's SPEC_AUDIO.

## 2026-10-31 Part (b) merges the v4 leaf branches, because Tank has not landed

- Decision: `audio/tank` merges `game/tank4-rules`, `-effort`, `-art`, `-view`, `-hud`, `-sims` in T-INT's order, moves the adapter onto the `TankAudio` name, edits the `audio.update(` line (SPEC 2.2, site 3) and retires `tests/games/tank/view/test_tank_audio.gd`. It should land on main after T-FINAL; `git merge main` then keeps `tank_audio.gd` whole (SPEC 7).
- Alternatives: wait for T-FINAL (the review's blockers stay open, and no test can run the real rules), or merge only the rules and art (site 3 needs the view's `travel` and the rules need the view's six seats).
- Reason: part (a) held only offline. These merges resolve cleanly and touch nothing in those paths. The tank suite on this merge has six failures that exist without the adapter; they are T-INT's and T-TUNE's, not moved here.

## 2026-10-31 On a client the track follows the tread as drawn

- Decision: the track machine reads the view's `travel`, which advances by `render_dt` and so stalls and catches up on a client (SPEC 2.2 moved the cranks to frame time for that reason, not the tread). Accepted; links and squeak lurch when the tread does.
- Alternatives: a frame-time `travel` for the audio on clients, which is a second integrator.
- Reason: S1 is one number for picture and sound. A snapshot stall stalls the tread on screen too, the squeak is a texture rather than a rider's rhythm, and the kit's `plan()` accounts for every stroke as fired or dropped (a jump past 80 ms is dropped by design). The hardware test's step 121 asks a person to judge it.
- Measured through the real view as a client, 10 Hz state ticks in the probe (the critic's, on 8a7faf06): track links 7-8 per s steady, every seat exact over 30 revolutions, dropped 0. A 1 s snapshot stall gives 0 links in that second and no burst on resume, and the tread skips the same 6 m.

## 2026-10-31 A shot's flight comes from its event

- Decision: `incoming_whistle` and `enemy_thump` read `flight_s` and `rng_m` from the shot event. SPEC 4.1's held ids and `state.shells` lookup are gone; only its fallback stays, 2.5 s and 1400 m, for a far shot with no numbers.
- Alternatives: SPEC 4.1's lookup, written before ruling 8.5 put both numbers on the event.
- Reason: no frame of delay and no state to keep. A client gets the same numbers as the host.

## 2026-10-31 The bow guns are a locked stroke

- Decision: `bow_shot` also plays on the feed machine at 0 and 0.5 of a revolution while `TankFeedState.rpm` > 0, and stays a staggered cue for a SHOT with SHELL_BOW.
- Alternatives: the cue alone, as in SPEC 4.1.
- Reason: `TankBow` fires by pedal revolutions and emits no shot event, so a cue alone would leave the guns silent. Two rounds a revolution is the owner's 1:1 rule for this seat; the bolts come home on the same fractions.

## 2026-10-31 What was added to SPEC 4.1's list

- Decision: `diesel_rasp` (a load-driven exhaust sizzle, lead only), `boiler_simmer`, `belt_rattle`, `repair_compressor`; a second crackle entry at 0.16, 0.52, 0.85 on a deep lift-off; the exhaust spits a little well over band (`crackle_level`); fire pitch rises 6 % each way with rpm; TURN is a lever clunk, TIME_UP the horn; a far kill's explosion waits for the same delay as its boom.
- Alternatives: the list as written. Its crackle plays only on a lift-off, so a steady rider never hears the engine "crackling instead of a monotone rumble".
- Reason: A6 needs the top end to open with load, which a stroke's fixed filter cannot do. Scored with every machine as lead, the feed read 0.99 and the repair 1.00 on A5: one identical stroke a revolution is the machine gun that row warns of. A loop under each brings them to 0.9-0.97.

## 2026-10-31 Levels per seat, and thinning

- Decision: every machine leads inside SPEC 3.6's -22 +-2 and its room inside the mix's -18 +-2. `tests/games/tank/audio/seat_levels.test.mjs` holds it, since the scorecard scores only the diesel. Solo at power 1 and 90 rpm: diesel -20.9, dynamo -21.6, steam -21.5, arc -21.6, feed -21.4, repair -22.1 LUFS. `hoist_pawl` and `casing_tink` are `lead_only`, which SPEC 4.1 does not ask. `A13` is waived in the bank: 31 repeats among the 465 kept strokes of other riders in the preview, each from `other_min_gap_s` thinning the variant between. The lead has none.
- Alternatives: fewer riders in the preview, which hides how a full crew with bots sounds; more variants, which only makes the repeats rarer.
- Reason: a rider on any seat should hear their machine at one level. No listener can follow a variant through thinning at 14 dB under the lead.
- Numbers, lead then mix LUFS with a full room over the preview's segments (round 1's bank in brackets, the mix's): diesel -21.1, -19.2 (-19.4); dynamo -22.0, -19.8 (-19.9); steam -21.8, -19.7 (-20.2); arc -21.9, -19.8 (-20.4); feed -21.8, -19.7 (-21.0); repair -22.3, -19.9 (-21.5). True peak -0.9 to -1.2 dBTP: steam's -0.90 does not move with its own strokes (chuff_a 3 dB down leaves it), so it is the limiter's inter-sample overshoot on a stacked transient, and the seat test holds -0.85. Only the diesel's -1.17 is gated by A1.
- Reaching the level needed recipes as well as levels. On levels alone feed's 500-4k share rose to 51-53 %, so `bow_shot` got more chest (sine gain 0.7 to 1.1, noise 1300 to 1100 Hz) and `bolt_clack` too: 41 %, inside A8. Repair stayed at 1.3 % above 4 kHz, so `rivet_ring` got the sparks the art draws (grains 4.2-8.2 kHz) and `repair_compressor` a valve's hiss (4.6-7.4 kHz): 2.4 %. No bytes: no duration changed.

## 2026-10-31 What a full crew thins

- Decision: `diesel_fire_hard` and `bolt_clack` are `lead_only`, which SPEC 4.1 does not ask, so other riders ask for fewer strokes before `other_min_gap_s` starts choosing.
- Alternatives: leave the ask and let the gap thin it. An earlier version of this ADR said "the smallest details go first". That was wrong: thinning ignores priority and is first come in `at_s` order. Measured over 5 minutes of bots at 90 rpm: `chuff_a` 10-31 of 90 a minute, `diesel_fire_a` 21-90, and `bolt_clack` 0 while the bow guns fired; with identical cadence and phase some machines passed nothing in 100 revolutions.
- Reason: a level cut in the bank is the only fix in reach. Fairness between tied strokes and a per-seat start offset are in the kit and outside the three allowed edit sites, so they went to the lead as requests. Bots' cadence noise keeps the exact tie from lasting.
- Measured after the `lead_only` cut (the critic's, on 8a7faf06), 5 minutes at 90 rpm +-1.5, Gun leading, per minute: `diesel_fire_a` 68-71 of 90, `_b` 28-38, `_c` 56-61, `cap_dump` 90, `chuff_a` 43-49, `arc_zap` 91-105 of 180, `bow_shot` 95-106 of 180, `rivet_hit` 38-45 of 90. Much more even than the 10-90 before it. `diesel_fire_b` is the weakest: tie fairness stays the lead's call.
- CPU (D10), the same review: `TankAudio.update` with 6 seats and the track at 110 rpm averages 0.13 ms (p99 0.24, max 1.28) with real players on the dummy driver, under the 0.5 ms bench limit; setup takes 76 ms.

## 2026-10-31 Variation without bytes, and where the bytes went

- Decision: fire takes 6, 5 and 4 with per-variant `norm`, tables of 7; `pitch_table` of 7 on the single-stroke machines (their length co-prime with the variants, a test holds that), `norm` by variant on `cap_dump` and `rivet_hit`, 2 variants with a 3-entry table on the ticks. Cricket trains are baked into one file, because `AmbienceBed` walks variants and re-rolls pitch per burst entry, which hopped one cricket across the stereo field. A third bed layer `cricket_chorus`. `wind_pine_lo`'s tremolo goes to 0.2 and `wind_pine_hi`'s to 0.4. Each main-gun round takes the next of a counter's pitches and levels.
- Alternatives: the review's table lengths of 3 to 5 (a 12-revolution bar on the rivet and the dump); `wind_pine_hi` alone at 0.4, which raised A12 to 0.68 at 11 s, since the low wind then dominated the envelope and it is what repeats.
- Reason: at 90 rpm the 3-revolution diesel loop was a 2 s bar 900 times in 30 minutes. Then 5 takes on all three cylinders aligned into a 15-stroke bar: lag 5 0.89, lag 10 0.90, lag 15 0.88, lag 20 0.94, others about 0.6, 3.33 s at 90 rpm and 540 times in 30 minutes, with the per-take level swing repeating too. A5 cannot see it. With 6, 5 and 4 the full cycle is 60 revolutions: lag 4 0.81, lag 5 0.65, lag 8 0.81, lag 12 0.89, lag 20 0.86, so the first 0.89 moves from 3.3 s to 8 s (A5 0.85..0.91, a 4 ms envelope at lag 1). Bank 6.91 MB, under the 7.0 cap. A16 is a proxy on one seed: the spots' timers are independent, so at run time a frog can still land on a branch.

## 2026-10-31 Levels: working harder brightens every seat, within the fatigue rule

- Decision: the review's levels for the arc, dynamo and feed, except `link_clink`, which stays 16 dB under the feed's main stroke. The review's -11 breaks SPEC 5's fatigue rule, which `test_nothing_locked_above_two_kilohertz_outshouts_its_machine` holds, so it is -17. Repair: `rivet_ring` -7 by power, the compressor flatter.
- Numbers, power 0.5 to 1.2 at 90 rpm, power-weighted centroid: diesel +111 %, dynamo +34 %, steam +24 %, arc +34 %, feed +22 %, repair +24 %. Only the diesel's is a gate (A6). `cap_dump` comes down 1 dB, because the dynamo alone reached 0 dBFS at power 1.2.
- Reason: a seat you stay on should answer your legs.

## 2026-10-31 An overrun's barrage rolls

- Decision: a kill `by` `BY_BARRAGE` is heard at once in a staggered roll (1 s, then every 0.35 s) at the fallback range, not as a far kill.
- Alternatives: a far kill, as for a shell. D8 on the real rules found these: 4 kills in one tick after an overrun, no HIT or SPLASH to give a range, so the stale range of the last shot and four explosions stacked.
- Reason: there is no shell to be delayed from, and it is what a barrage sounds like.

## 2026-10-31 A reserve room is silent, and a spectator hears the track with the room

- Decision: the old 45 rpm reserve hum is gone: the sound follows the view, whose crank stands still there (SPEC 2.2). During a tow the crew pedals on and the machines keep sounding. A seat at rpm <= 1 is not driven, so it does not count toward `other_doubling_db`. The track drives as lead for a rider on any seat, not for a spectator.
- Alternatives: track as lead for everyone, as SPEC 4.1 says. That costs a spectator the kit's +4 dB for a room with no lead while the hull moves.
- Reason: picture and sound stop together. A spectator's track thins like any other machine: the squeak can drop out at speed, and only for a spectator.

## 2026-10-31 The dynamo's ripple is locked to its crank

- Decision: `dynamo_whine` is a 4 s file whose ripple runs at exactly 27 Hz, played at pitch rpm/90: 18 ripples per crank revolution at any cadence. Each of its three lines swells and wavers on its own whole-cycle rate (380 Hz at 0.25, 760 at 0.75 and 0.5, 1140 at 0.5 and 0.75), and the pink band breathes at 0.25, so it is not three flat lines and it stays locked to the revolution. `arc_hum` and `ladder_buzz` move the same way. `diesel_rasp` is 1.3333 s with its tremolo at 4.5 and 9 Hz, the firing rate at pitch 1.
- Alternatives: 26.67 Hz in a 1.5 s file, which reads as a beat against the strokes and pulled the dynamo's rhythm 1.4 % off the revolution when it led.
- Reason: a loop's own period should agree with the machine it belongs to.
- Numbers, 1 s band stdev at 60, 90, 110 rpm (round 1's target: at least 0.5 dB). Dynamo, 250-800 Hz: 0.91, 0.83, 1.11; 800-2 kHz: 1.16, 0.82, 0.54. Arc, 250-800: 1.02, 0.78, 0.33; 800-2 k: 0.92, 0.78, 0.59. Two misses stay open: the arc at 110 rpm in 250-800 (0.33), which tremolos on `arc_hum` barely move (its power sits at 100 and 200 Hz, under that band), and the whine's top line, 31.8 dB at 377 Hz against a target of 25. Thinning the line from gain 0.6 to 0.4 only took it from 32.4 to 31.8, since a line's height over its neighbours follows its narrowness, not its level, and a vibrato wide enough to reach 25 wobbles audibly. A dynamo's whine is a tone, so it stays one.

## 2026-10-31 A near hit is told by its target, not by a new field

- Decision: `TankAudio._hit` asks whether the target is near: the state's enemies for one still alive, and a note of near kills since the last `update()` for one the rules just erased (`kill_enemy` erases it and sends KILL before the HIT).
- Alternatives: an additive `far` field on HIT, which is a contract change outside this branch's paths, or noting ids from AMBUSH, which adds state for the whole of a threat's life and misses one seen only by snapshot.
- Reason: `TankShells._impact` sends world px in `x`, so a main-gun round on a recon read as metres: at world x above about 2400 px a far boom 3.5 s later at -16 dB, while KILL played `explode_small` at once. It takes a manual shot aimed low, so it is rare, and the fix needs no new data. `_last_far_m` no longer takes a near hit's px either.

## 2026-10-31 Sounds that outlive a lost tank are accepted

- Decision: on TANK_LOST a running `incoming_whistle` (up to 4 s at rate 0.63) and the pending `enemy_thump`, `far_boom` and `explode_big` play on into the tow, ducked -9 dB by the cue. From reading the code, not measured.
- Alternatives: `kit.stop_all()`, which also stops the bed and the machines the crew is still pedalling, or a selective flush in the kit, which is the kit's and goes to the lead as a request.
- Reason: the field is cleared at that moment, so these sounds telegraph a shell that no longer exists. That is a small wrong against a loud moment: the ducked tail sits under `tank_lost`, and the last shells landing as the tank dies reads as the fight's end. Not worth a kit change at this stage.

## 2026-10-31 A Repairs seat with nothing to mend still answers the legs

- Decision: `repair_compressor` runs on a full hull, 9 dB under the working level by `repairing`, and `repair_idle` is -1 dB by power (-6 at 0.3, 0 at 1.2). One layer with a level by `repairing`, not a second entry of the same file, so the compressor eases between the two states rather than restarting. The rivet stays gated.
- Alternatives: the critic's second layer entry, with a steeper rise (-8 to 0 by power, against -2 to 0) but two players and a seam at each change of state.
- Reason: SPEC 4.1 says quiet, not inaudible. It read -39.7 LUFS at every power against about -30.3 for the rest of the room, so a rider on that seat heard no answer to their legs. Solo now -33.9, -32.2, -30.9 LUFS at power 0.5, 0.9, 1.2, about 9 LU under the seat at work. Its tap over the room: median +7 dB, p10 +3 dB, from +2 and -3.

## 2026-10-31 Under the jars' gate the brush is the dynamo's stroke

- Decision: `brush_tick` rises 8 dB below power 0.46, back to its level by 0.5. The art draws the dump only above that gate (`max_fill > 0.4`, pinned by a bank test), so `cap_dump` stays where it is.
- Alternatives: lowering the gate, which would dump with no dump on screen; a ramp up to 0.6, which took the dynamo's brightening with load from +34 % to +18 %.
- Reason: below the gate the seat has no stroke to pick out. Against the room at power 0.4 the tick moves from median -8, p10 -13 dB to median 0, p10 -5 dB at 1600 Hz. That is a texture you can find, not a stroke that cuts through. Accepted: 0.4 is well under what the seat asks for, and the fatigue rule (`test_nothing_locked_above_two_kilohertz_outshouts_its_machine`) reads the table level, -12, which still applies once the dump plays.

## 2026-10-31 The night's details reach the rider, and the frogs get rarer for it

- Decision: `cricket_chorus` -26 to -19; `frog` [-23,-18] to [-18,-13] with its gap from [9,23] to [14,34] s; `far_battle` [-18,-12] to [-13,-8]; `branch_creak` [-20,-16] to [-16,-12]. The chorus stays, against dropping its 220 KB.
- Reason: the chorus sat -6.3 dB under the wind in its own band and -18 under the room. Best octave over the room at 90 rpm, power 0.9, 300 s, before and after: owl +0.3, +0.2; cricket -2.5, -2.7; branch -9.2, -4.4; far battle -11.3, -7.1; frog -11.9, -7.3. The chorus -11.5 dB at 3-5 kHz. They remain under the machines by design and come forward when the gun ducks the room. Bed solo -32.0 LUFS, LRA 2.6; Ambience in the mix -31.6, target -32 +-3. Nobody has listened: if the chorus still does nothing after a listen, drop it.

## 2026-10-31 The reload and the near impacts vary like the gun

- Decision: `shell_outgoing` and `shell_eject` take the round's `gun_pitch`; `shell_load` and `breech_close` a counter's `load_pitch` (1.0, 0.975, 1.02); `incoming_impact_near` and `near_miss_thud` a counter's `impact_pitch` (1.0, 0.96, 1.05, 0.98). No bytes.
- Reason: a shell takes about 7 s at 250 W, so up to about 250 identical sequences in 30 minutes. The session's near impacts were not counted over a long ride: at zero bytes that was not worth waiting for.

## 2026-10-31 What the critic measured with no change asked

- On 8a7faf06, for the record. Cricket trains hold pitch and pan. `night_forest` has no bed loop: under the adapter's real gust the highest envelope autocorrelation is 0.38 at 26 s, LRA 4.1. `turbo_whistle` is 7.7 dB over its neighbours in the mix at power 1. Limiter load is low: 7.6 % of the time at most at power 1.3, 110 rpm with the gun, gain reduction at most 2.3 dB. Family: mix -19.31 to -19.89 LUFS across the four games, A10 7.32-8.94 dB, above 4 kHz 2.1-3.3 %, Ambience -29.8 to -33.4.
- With every machine scored as lead on that head: D2 at most 0.32 ms, D3 at most 0.19 %, D4 digital silence at 400 ms, D5 6.34..8.14, D6 at most 8/0/13, D7 at most 11.4. Its one exception, repair at 110 rpm (`rivet_ring@0.03`: 9 onsets, 9 planned, 10 in the pattern), is the offline harness's first frame priming past that fraction, not the game: `test_tank_audio_patterns.gd` counts every seat exact past the first revolution, at its fraction.

## 2026-10-31 v4: a near threat is near, a far one stays far

- Decision: `recon_engine` (266 Hz) and `tankette_engine` (360 Hz) are rebuilt with their fundamental filtered down and formants at 1.15 and 2.4 kHz, 1.5 and 3.1 kHz, on Sfx at -4.5 and -4 dB against -20 before. The distance is from the hull's front, as the rules place them, with a `rev` param from `e.mode`: they rev as they dash and idle down, -1 dB and about a quarter lower, when they stop to fire. On `escaped` the adapter drives the loop on at 120 px/s to 620 px, about 3 s, because the rules erase the enemy at 220 px; a kill and a tow cut it. `ambush` ducks Machines -4 and Ambience -6 for 0.8 s. `small_mg` -15 to -2, its cracks moved from 1.7 to 2.6 kHz, where the chuffs and the zaps leave room. A near round on the hull (`dmg` 1 or less with the hull in action, a new cue `hit_small`) is `hull_hit` at 1.55 pitch and -11, not `incoming_impact_near`, which it shared with a far shell. `enemy_thump` has more sine and +3; the Behemoth's is +3 more and 0.8 lower. `incoming_whistle` keeps its 2.5 s and its end, and its first 1.9 s drop to under -9 dB of the end. It now also ends at impact on a 4.7 s flight (`whistle_delay`) and a 1.4 s one (rate up to 1.8).
- Alternatives: a near engine with no ghost, which the rules' 0.3 s from 185 to 220 px would turn into a cut; a duck under every near engine, which would pump for 7 s in the middle of a fight; dropping the whistle from the first part of the flight, as v4's stub did, which loses the warning that a shell is in the air; a low engine, which the diesel's bands would hide however loud.
- Reason: the critic's blocker. Over a hard ride, best third-octave band (`tests/games/tank/audio/read_over.mjs`, held by `cue_reads.test.mjs`). Before, the diesel leading: recon -19.2 and tankette -17.9 at 185 px from the hull's middle, which is its close range, and its gun -5.3. Now, worst seat: recon at close range +5.9 at 1260 Hz, tankette +4.7 at 1587 Hz; stopped to fire at 160 px +0.9 and +2.3; leaving at 185 px +1.9 and +0.7; fleeing, 320 px at most -3.5, 560 px at most -23.4. Its gun +3.4. The burst and engine in their first 200 ms +11.3. Far: the thump at 2200 m -3.3, now +4.0 and best at 63 Hz. The whistle's first second at most +6.7 and under the room on 4 of 6 seats, its last half second at least +17.7.
- Bytes: none. Same durations.

## 2026-10-31 RANGE_DB -5 to -12, from -6 to -16

- Decision: the far sounds lose 7 dB over the range, not 10.
- Alternatives: raising each cue by the 4 dB the far end needs, which pushes a light tank's boom at 800 m over the gun's tail.
- Reason: at 2200 m, the furthest a far tank holds, the cues' levels below on the old table would put a far hit's boom and a kill -2.4 under a diesel at a hard ride (computed from the -0.4 they measured at 1400 m at their old levels), so the rider's own reward was lost at range. It still reads as distance: the delay does most of that work.

## 2026-10-31 What the old shallow duck held back, and what the deep one allows

- Decision: with D5 now measuring the -14/-14/-20 duck and the loudest moment, Sfx came up: `far_boom` +3 on a hit and +2 on a splash, `far_hit_metal` +3, `explode_big` +3, `explode_small` +2, `near_miss_thud` +2, `far_hit_metal` on a near threat +4, `shell_eject` +4, `shell_load` and `breech_close` +1. `preview.hud` lists the real UI: the toasts at a latch, the Surge prompt, the ambush, the escape and the evade, and the phase chime at the segment.
- Numbers, before then now: D5 7.62 to 8.88, at 58 s, a toast on an evade. A2 Sfx -13.38 to -13.34 (-14 +-3). The bank's one waiver, A13, stays: its numbers are the same, 31 of 465, each from a thinned variant at 14 dB under the lead.
- A cue reads when its best third-octave band beats the room at the same moment (`cue_reads.test.mjs`, every seat at 100 rpm, 1.1 of target, a full crew): every threat and reward above 0 dB. Worst now, each with the diesel leading, the 2200 m ones at the furthest a far tank holds: `splash_far` +0.4, `explode_big` +1.2, `far_hit_metal` +1.2, `far_boom` +1.4, `hull_hit` on a small round +3.0, `near_miss_thud` +3.5.

## 2026-10-31 Which sounds the owner named, and what moved them

- Decision: `diesel_valve_ex` +6, `diesel_valve_in` +3, `turbo_whistle` +3 to +4, `track_squeak` +6, `track_link` +3, the crackle's lower end +2, and `diesel_body_lo`, `_hi` -0.6, so the lead stays in A2's window against the other riders (A2 other -11.95, floor -12: that is the row that stopped a higher `track_link`).
- Reason: measured against the room, not solo, several sat under it: squeak -2.6, valve -4.2, turbo -2.3, eject -0.7. Now all above 0 at a hard ride with the diesel leading: squeak +1.7 at 1260 Hz, shell eject +3.4, shell load +4.1, breech +1.7, exhaust valve +1.6, inlet valve +1.5, turbo +1.4 at 4 kHz, crackle over band +1.5, on a lift-off +9.1. Margins of 1 to 2 dB in one band: findable, not prominent, which is what an hour of them needs. Nobody has listened to say whether they are enough.

## 2026-10-31 The third site: what the far panel shows

- Decision: `audio.update(` takes one more argument, `not far.rects.is_empty() or far.boss_box.has_area()`, and `combat` goes to 0 while it is true, so `far_battle` stands down.
- Alternatives: reading `state.enemies` in the adapter, which is a second opinion on what is drawn; leaving the battle in.
- Reason: a far shot is now a low thump, and so is a far battle. A thump in a fight must always be a real shot.

## 2026-10-31 A tow runs the tread backwards, and the links follow it

- Decision: the adapter keeps its own odometer, the sum of how far the view's `travel` moved either way, and under `hull.tow_s` the track runs at the view's tow speed, 1.3 m/s.
- Alternatives: leaving the track silent, as the rules' hull speed is 0 then; reading the tow as negative revs, which the kit's plan treats as a reset.
- Reason: the picture's tread turns for 8 s and `tow_chain` lasts 2.4 s. S1 is one number for picture and sound, as for every crank. Measured through the real view: planned revolutions equal the tread's within 0.1, and a standing tank after it plays none.

## 2026-10-31 A banner is not a safety prompt

- Decision: `hs.banner_sound = ""`. Segment and boss banners have `segment` and `boss_phase`; `ctx.hud.banner` was also playing `warning` and ducking the mix -14/-14/-20 for 2 s at each.
- Reason: Tank's rider heard the safety sound at every segment. It must mean a real one (BRIEF 4.6). A trainer notice or safety banner ignores this field and always warns.

## 2026-10-31 What is measured here and what is not

- Measured offline: the numbers above, the scorecard, the wiring by GUT on the real rules and the real view. Not measured: how any of it sounds. Whether a recon reads as a small car, whether the near engine tires over a long fight, whether a fading engine past the panel's edge feels right, whether a far whistle reads as far. A third-octave win says a sound can be picked out by level in one band, not that a person will: real masking on real speakers over a real fan is the hardware test's section 16. Near threats are measured with one engine at a time and a static distance per case, with the rider's own bow guns not firing.

## 2026-10-31 The Lights machine is warm and low, and holds out of 2-8 kHz

- Decision: the owner rode it and called it too annoying, ear piercing. `ladder_buzz`, `arc_hum`, `arc_zap` and `arc_zap_over` are gone. Now `arc_thrum` (110 Hz and its octave, at rpm/90, so it follows the cadence), `arc_thrum_open` (the same series through a 590 Hz formant, opening with power), `arc_relay` at 0 and 0.5 (where the art's first arc starts up: a 250, 590, 1180 Hz contact and a falling low thump, band-limited to 1.8 kHz), `arc_relay_over` at 0.25 and 0.75 (the art's second arc, over 0.3), `arc_spark` at 0.44 and 0.94 (high on the horns, from reach 0.85, lead only), `belt_tick` duller and 3 dB down, and `arc_lamp` (next ADR). Fractions, gates and what the view draws are unchanged. `tests/games/tank/audio/lights_band.test.mjs` holds the limits and fails on the old bank; `ear_band.mjs` prints every number.
- Alternatives: lowering the old sounds, which keeps the shape that pierced (2-8 kHz at -4 dB of its total at any level); a machine with nothing at all in 2-8 kHz, which fails A8 (next ADR); a spark that plays one stroke in N by leaving it out of the pattern, which D1 would count as a missing stroke.
- Reason: 2-8 kHz against the machine's own total, at 60, 90, 110 rpm and power 1. Before: -4.8, -4.0, -3.7 dB, 40 % of its power and the highest of the six seats; loudest 186 ms +6.9, +6.2, +5.7 dB; 2-5 kHz -5.4, -4.6, -4.3 dB; -29.2 dBFS at 90 rpm. After: -18.3, -18.9, -19.1 dB; loudest -17.5, -18.1, -18.1 dB; 2-5 kHz -43.2, -39.8, -31.7 dB; -43.5 dBFS at 90 rpm. A full crew with it leading: -6.3 dB of the mix before, -14.0 after. Solo at power 1 and 90 rpm: -20.94 LUFS before, -22.44 after, the diesel's -20.72. What is left in the band is the lamp: every other Lights sound is at -67 dBFS or under there.
- Occasional, with no primitive for it: a stroke fires every time or D1 fails, so `arc_spark` has 7 takes, 2 of them about 14 dB over the other 5. The quiet ones are lost under the thrum and D1 still counts them. It repeats every 3.5 revolutions, at a level nobody should follow.

## 2026-10-31 A8's floor costs the Lights machine a faint hiss

- Decision: `arc_lamp`, the carbon lamp's hiss: filtered white noise at 6-9 kHz, -13.5 dB, rising with power, the rider's own (no `other`), and not pitched by rpm, since rpm/90 at 60 rpm would slide it to 4 kHz, into the most sensitive band. It is the one continuous sound up there, and it is there only because of A8, which `seat_levels.test.mjs` holds on every seat as lead: above 4 kHz at least 2 % of the mix.
- Alternatives: no lamp. The machine then reads 2-8 kHz at -46.5, -40.8, -31.8 dB of its own total at 60, 90, 110 rpm, but the mix with Lights leading has 1 % above 4 kHz: the room brings 2.1 % of its own power, 0.9 % of the mix, and nothing else is up there. The floor is not weakened. Strokes with an airy top spend the same energy in sharp bursts, which is what is being removed. Changing the other machines is out of scope.
- Reason: spread evenly over time and placed above 6 kHz is the least annoying way to spend 1 % of the mix. It is smooth, with no harmonics and no flutter, and well under the old sounds in that band (-43.5 dBFS at power 1, -40.5 at its loudest; `ladder_buzz` alone was -32.6 and `arc_zap` -27.6 at power 1.5). It is still the one thing here an ear could object to, so the Listen step asks. If it tires the owner: drop the `arc_lamp` layer, and whether a seat as lead keeps A8's floor is the lead's call.
- The same gates shaped the rest. A8's 80-500 Hz ceiling (60 %) stopped a darker first version at 69 %, so the body moved up into the 590 Hz formant. `cue_reads.test.mjs` moved the relay's modes twice (410 and 1160 Hz, then 285 and 770), since they covered `far_hit_metal` (410, 980) and `hit_small` (`hull_hit` at 1.55: 338, 786). Both now read over this seat, far metal +4.8 dB at 397 Hz. Bytes: bank 6.96 MB, up from about 6.9, under the 7.0 cap.
- Nobody has listened: whether it reads as a generator and a relay, whether it belongs to a searchlight, whether an hour of it is pleasant.
