# Decisions: audio-tank

Short ADRs for Diesel Domestiques' sound on the audio kit. "SPEC" is the run's SPEC_AUDIO.

## 2026-10-31 The adapter stands beside the old TankAudio until the view moves

- Decision: part (a) adds `TankKitAudio` in `audio/tank_kit_audio.gd` and leaves `TankAudio` as it is. Part (b), after Tank v4 lands, edits the `audio.update(` line (SPEC 2.2, site 3), moves the new file onto `TankAudio` and retires `tests/games/tank/view/test_tank_audio.gd`.
- Alternatives: rewrite `tank_audio.gd` now, which breaks `test_tank_audio.gd` and the script check until part (b), and conflicts with builder V's edits of the same file.
- Reason: the branch stays green at every step, and part (b) is a rename plus one line.

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

- Decision: every machine leads at about -21 to -24 LUFS at 90 rpm (diesel -20.6, dynamo -21.2, steam -22.4, arc -22.5, feed -22.9, repair -24.4). `hoist_pawl` and `casing_tink` are `lead_only`, which SPEC 4.1 does not ask. `A13` is waived in the bank: 37 repeats among the 465 kept strokes of other riders in the preview, each from `other_min_gap_s` thinning the variant between. The lead has none.
- Alternatives: fewer riders in the preview, which hides how a full crew with bots sounds; more variants, which only makes the repeats rarer.
- Reason: a rider on any seat should hear their machine at one level. With five others at 110 rpm the strokes ask more than the 16.7 a second D7 allows, so the smallest details go first. No listener can follow a variant through thinning at 14 dB under the lead.

## 2026-10-31 A reserve room is silent, and a spectator hears the track with the room

- Decision: the old 45 rpm reserve hum is gone: the sound follows the view, whose crank stands still there (SPEC 2.2). During a tow the crew pedals on and the machines keep sounding. A seat at rpm <= 1 is not driven, so it does not count toward `other_doubling_db`. The track drives as lead for a rider on any seat, not for a spectator.
- Alternatives: track as lead for everyone, as SPEC 4.1 says. That costs a spectator the kit's +4 dB for a room with no lead while the hull moves.
- Reason: picture and sound stop together. A spectator's track thins like any other machine: the squeak can drop out at speed, and only for a spectator.

## 2026-10-31 The dynamo's ripple is locked to its crank

- Decision: `dynamo_whine` is a 2 s file whose ripple runs at exactly 27 Hz, played at pitch rpm/90: 18 ripples per crank revolution at any cadence.
- Alternatives: 26.67 Hz in a 1.5 s file, which reads as a beat against the strokes and pulled the dynamo's rhythm 1.4 % off the revolution when it led.
- Reason: a loop's own period should agree with the machine it belongs to.
