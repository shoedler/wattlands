# Decisions: audio-tank

Short ADRs for Diesel Domestiques' sound on the audio kit. "SPEC" is the run's SPEC_AUDIO.

## 2026-10-31 Part (b) merges the v4 leaf branches, because Tank has not landed

- Decision: `audio/tank` merges `game/tank4-rules`, `-effort`, `-art`, `-view`, `-hud`, `-sims` in T-INT's order, moves the adapter onto the `TankAudio` name, edits the `audio.update(` line (SPEC 2.2, site 3) and retires `tests/games/tank/view/test_tank_audio.gd`. It should land on main after T-FINAL; `git merge main` then keeps `tank_audio.gd` whole (SPEC 7).
- Alternatives: wait for T-FINAL (the review's blockers stay open, and no test can run the real rules), or merge only the rules and art (site 3 needs the view's `travel` and the rules need the view's six seats).
- Reason: part (a) held only offline. These merges resolve cleanly and touch nothing in those paths. The tank suite on this merge has six failures that exist without the adapter; they are T-INT's and T-TUNE's, not moved here.

## 2026-10-31 On a client the track follows the tread as drawn

- Decision: the track machine reads the view's `travel`, which advances by `render_dt` and so stalls and catches up on a client (SPEC 2.2 moved the cranks to frame time for that reason, not the tread). Accepted; links and squeak lurch when the tread does.
- Alternatives: a frame-time `travel` for the audio on clients, which is a second integrator.
- Reason: S1 is one number for picture and sound. A snapshot stall stalls the tread on screen too, the squeak is a texture rather than a rider's rhythm, and the kit's `plan()` still fires every stroke exactly once. The hardware test's step 121 asks a person to judge it. Not measured.

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

- Decision: every machine leads at about -21 to -24 LUFS at 90 rpm (diesel -20.6, dynamo -21.2, steam -22.4, arc -22.5, feed -22.9, repair -24.4). `hoist_pawl` and `casing_tink` are `lead_only`, which SPEC 4.1 does not ask. `A13` is waived in the bank: 31 repeats among the 465 kept strokes of other riders in the preview, each from `other_min_gap_s` thinning the variant between. The lead has none.
- Alternatives: fewer riders in the preview, which hides how a full crew with bots sounds; more variants, which only makes the repeats rarer.
- Reason: a rider on any seat should hear their machine at one level. No listener can follow a variant through thinning at 14 dB under the lead.

## 2026-10-31 What a full crew thins

- Decision: `diesel_fire_hard` and `bolt_clack` are `lead_only`, which SPEC 4.1 does not ask, so other riders ask for fewer strokes before `other_min_gap_s` starts choosing.
- Alternatives: leave the ask and let the gap thin it. An earlier version of this ADR said "the smallest details go first". That was wrong: thinning ignores priority and is first come in `at_s` order. Measured over 5 minutes of bots at 90 rpm: `chuff_a` 10-31 of 90 a minute, `diesel_fire_a` 21-90, and `bolt_clack` 0 while the bow guns fired; with identical cadence and phase some machines passed nothing in 100 revolutions.
- Reason: a level cut in the bank is the only fix in reach. Fairness between tied strokes and a per-seat start offset are in the kit and outside the three allowed edit sites, so they went to the lead as requests. Bots' cadence noise keeps the exact tie from lasting.

## 2026-10-31 Variation without bytes, and where the bytes went

- Decision: fire takes 5 with per-variant `norm`, tables of 4 and 7; `pitch_table` of 7 on the single-stroke machines (their length co-prime with the variants, a test holds that), `norm` by variant on `cap_dump` and `rivet_hit`, 2 variants with a 3-entry table on the ticks. Cricket trains are baked into one file, because `AmbienceBed` walks variants and re-rolls pitch per burst entry, which hopped one cricket across the stereo field. A third bed layer `cricket_chorus`. `wind_pine_lo`'s tremolo goes to 0.2 and `wind_pine_hi`'s to 0.4. Each main-gun round takes the next of a counter's pitches and levels.
- Alternatives: the review's table lengths of 3 to 5 (a 12-revolution bar on the rivet and the dump); `wind_pine_hi` alone at 0.4, which raised A12 to 0.68 at 11 s, since the low wind then dominated the envelope and it is what repeats.
- Reason: at 90 rpm the 3-revolution diesel loop was a 2 s bar 900 times in 30 minutes. Lag 3 is now 0.60, lag 5 0.89 (A5 still reads 0.87..0.91, a 4 ms envelope at lag 1). Bank 6.91 MB, under the 7.0 cap: the rest of the review's list is all levels and tables, no files. A16 is a proxy on one seed: the spots' timers are independent, so at run time a frog can still land on a branch.

## 2026-10-31 Levels: working harder brightens every seat, within the fatigue rule

- Decision: the review's levels for the arc, dynamo and feed, except `link_clink`, which stays 16 dB under the feed's main stroke. The review's -11 breaks SPEC 5's fatigue rule, which `test_nothing_locked_above_two_kilohertz_outshouts_its_machine` holds, so it is -17. Repair: `rivet_ring` -7 by power, the compressor flatter.
- Numbers, power 0.5 to 1.2 at 90 rpm, power-weighted centroid: diesel +101 %, dynamo +34 %, steam +36 %, arc +48 %, feed +13 %, repair +30 %. `cap_dump` comes down 1 dB, because the dynamo alone reached 0 dBFS at power 1.2.
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

- Decision: `dynamo_whine` is a 4 s file whose ripple runs at exactly 27 Hz, played at pitch rpm/90: 18 ripples per crank revolution at any cadence, and a 0.75 Hz swell and vibrato, one per 2 revolutions, so it is not three flat lines. `diesel_rasp` is 1.3333 s with its tremolo at 4.5 and 9 Hz, the firing rate at pitch 1.
- Alternatives: 26.67 Hz in a 1.5 s file, which reads as a beat against the strokes and pulled the dynamo's rhythm 1.4 % off the revolution when it led.
- Reason: a loop's own period should agree with the machine it belongs to. Its period does still show: lag 6 revolutions at the dynamo is 0.89 at 90 rpm, the loop's own 4 s.
