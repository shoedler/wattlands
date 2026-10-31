# Decisions: audio-siege

Short ADRs for Castellum Rotae's audio (`assets/siege/audio/audio.json`, `SiegeAudio`). "SPEC" is the run's SPEC_AUDIO.

## 2026-10-31 The walkers step with the crank; the wheel stays by watts

- Decision: `SiegeView.cranks[slot]` integrates the rider's cadence (0 with no rider). `walk_phase[slot]` reads its `revs`: one 4-frame walk cycle per revolution. `wheel_deg` keeps following watts.
- Alternatives: pawl from `wheel_deg` (SPEC_CLEANUP 1.5; a watt-driven wheel cannot be 1:1 with cadence); keep the walkers on watts and tick the audio from its own integrator (a second integrator, and the picture would contradict the strokes).
- Reason: the owner's "1:1 with cadence". The wheel is load, the walkers are legs. A rider coasting at high power is not a thing a trainer reports, so the two disagree only in the way a rider's legs and a wheel's inertia would.

## 2026-10-31 Three sounds beyond the SPEC's list

- Decision: `axle_knock` (lead only, at .75), `tower_dock` (the `dock` event), `far_anvil` (a bed spot), all recipes.
- Alternatives: the SPEC's list alone: pawl and step on 0 and .5, the creak on .25, and nothing on .75. That leaves a hole in each revolution, and `dock` with only the end of a creak.
- Reason: step, creak, step, knock gives each revolution a shape you can ride to, and a fourth accent that's heavier than the others. `far_anvil` carries a third spot in a wave, when the lark is silent, so a wave's hill isn't only crows and banners.

## 2026-10-31 A safety prompt clears the horns and the volley, and the mix pays for it

- Decision: bring every routine Sfx sound down until `warning` and `rescue` read at least +6 LU over the mix at the mix's loudest moments, not only in D5's own window. The horns and `overdrive_on` drop 8 to 11 dB, the whistles 11 dB. To stay heard, the horns are recut as far horns (a high-pass at 330 Hz, a 1050 Hz peak, the 98 Hz layer gone, tails that fall) and each ducks Machines -8 and Ambience -4 for as long as it blows. `horn_rush`'s stabs move from A3 to G3: its 2nd harmonic sat on `warning`'s 440 Hz square. The preview keeps a whistling volley at 30.0 s, on a stroke, and a ram at 30.4 s, inside D5's window.
- Alternatives: the old "one-off events" argument (false: at m = 1 the organ fires every 1.5 s, and a rush at 110 rpm read -0.06 LU); a louder prompt or a lower threshold (never); a deeper Sfx duck on prompts (the platform's: a request to the lead, below).
- Reason: BRIEF 4.6 outranks a horn. Measured with the prompt 50 ms after each of the 40 preview events: 37 clear +6, and the rest are `breach` +5.69, `shot_bolt` +5.76 and +5.81 (the first bolt at 60 rpm lands on a pawl). With the prompt 0.05, 0.2 and 0.4 s into each at 110 rpm: `rush` +7.31, `wave_start` +7.69, `push` +7.11, `overdrive_on` +6.69, volley +6.30, `reach` +6.01, `dock` +6.73, all held by `tests/games/siege/audio/bank.test.mjs`. D5 itself reads +6.16.
- Still open, plainly: (1) A long horn's tail, the prompt 0.8 s in at 110 rpm: `wave_start` +5.68, `rush` +5.89 (nothing landing reads +6.05 at that moment). (2) A busy wave (volleys, ram, gate hits, Scorpions, hooves and kills all at once, a worst case; the critic's probe with the organ's whistle rule added): 10 of 16 sampled moments under +6, minimum +4.83, where it was 15 of 16 and +1.61. These sit under +6 by the shots' transients, and the prompts duck Sfx only -4 dB. (3) A1 and D5 now press on each other from both sides: A1 -19.90 against a -20 floor, D5 +6.16 against +6. There is about 0.1 dB of level left in this mix.
- Trade: the horn is now about level with the mix in its best octave (1.28-2.56 kHz, +0.6 dB under its own duck, -7 dB one octave up), where before it stood well over. It may read as far off. It is unheard: Listen step, HARDWARE_TEST 14.
- Request to the lead: deepen the prompts' Sfx duck in `HudLayer` and in `SAFETY_DUCK` (`offline_mix.mjs`). Estimated with a duck of -8 dB in the same probe: the busy wave's 10 of 16 becomes 5 of 16, minimum +5.13; `wave_start`'s tail +5.86. It would also let the horns come back up.

## 2026-10-31 A2 is waived for Sfx, at -22.5 LUFS

- Decision: `preview.waive.A2`. Sfx peaks at -22.49 LUFS momentary against A2's -17..-11. Machines -20.82, one other rider -11.32 LU, Ambience -29.76, UI and the prompts are all in their windows.
- Alternatives: leave one rare sound (the Breach) at -17. A prompt on it would read about +1 LU, which is exactly what the blocker above forbids.
- Reason: with Sfx ducked -4 dB, D5 at +6 and A2's Sfx window cannot both hold: an Sfx moment at -17 is louder than -22.3 under the prompt. The deeper duck requested above would close this too.

## 2026-10-31 Keeping A1 with the events down: an even wheel

- Decision: the wheel's strokes and groan gain a `db_by` on rpm, so its level holds across cadence (strokes +2 dB at 60 rpm, the groan +3.8, both -1 at 140), and the preview rides 220 / 260 / 340 W. The bed comes up 1 dB. Pawl and creak level out at about -4.5, the footfall drops to -9, and the groan is -7 rather than the critic's -8.5.
- Alternatives: raise the wheel evenly (110 rpm reads the lowest D5 of the three, so it has nothing left); raise Sfx in the preview (Sfx ducks less than Machines, so it costs D5 more per dB of A1).
- Reason: a steady, even mix gives the most integrated level per LU of momentary peak. With nothing landing, a prompt read about +6.1 at 110 rpm and +6.4 at 90 rpm on two pawl strokes, while 60 rpm had 2 LU to spare, so that is where the level went. The critic's -8.5 groan reached only -20.4 LUFS here once the events were down, and A1 cannot be waived.
- Cost, measured with `strokes` and `loops` solo: the groan is 48-50 % of the lead's power at 90 and 110 rpm (was 54-57 %), but 69 % at 60 rpm, which is worse. At 60 rpm the 20 ms level is p50 -24.2, p95 -17.9, so strokes stand about 6 dB over the floor, not more. The groan still holds 80-96 % of 40-80 Hz, and groan plus strain 87-92 % above 2.5 kHz. The mix's 80-500 Hz share is now 38-40 % in every segment (the critic had 67.7 % at 110 rpm). The 3.7 s loop, the saw's gain of 0.14 and the separate contours are as asked; the tonal peaks and self-similarity were not measured again. The slow wheel may still read as a drone: Listen step.

## 2026-10-31 Effort has a timbre: timber_strain

- Decision: a lead-only loop that opens from about 180 W: band noise rising through 2.1-2.9 kHz, grains, a strained tri, a high hiss. The groan's flat hiss drops to a third of its gain, so the wheel gets brighter only with effort. `preview.checks.a6` holds it from 150 to 340 W: +27.85 % on the scorecard's magnitude-weighted centroid. Power-weighted it runs 409 to 467 Hz over the same range (+14 %) and 400 to 663 Hz from 100 to 500 W, where it was 417 to 454.
- Alternatives: the critic's recipe (bp 1250 Hz, 900-2400 Hz grains, a 420-560 Hz tri): measured, it could not move the magnitude-weighted centroid past +10 % at any level short of raising the mix.
- Reason: recovery and a hard wave must not be the same wheel a little louder.

## 2026-10-31 The arrow organ whistles once in three

- Decision: a volley within `WHISTLE_EVERY_S` (3.5 s) of the last whistling one plays `shot_arrow_rack`: release and patter. At m = 1 that is every third rack. Whistles sit at -27/-28/-29 dB (the critic asked -22/-23/-24; D5 asked for 5 more) with Ambience ducked -3 under them. The preview plays 10 s of racks at 1.5 s.
- Alternatives: a whistle on every rack (1800 in a short session, in the ear's most sensitive band); no whistle at all (the owner named arrows whistling).
- Reason: a whistle every 1.5 s for 5 minutes grates, and a human must still confirm 4.5 s doesn't.

## 2026-10-31 Gate hits answer what the gate lost, once a ram stroke

- Decision: a watermark that lowers only when a hit fires, at most once in `GATE_HIT_EVERY_S` (1.2 s), and rises with a repair. `dmg_db` is the drop, capped at 6 dB (was 12, since hits now add up over 1.2 s).
- Alternatives: the frame-to-frame drop: one ram's 0.195 HP a tick never sounded on a host, three fired 20 hits a second, and a client's whole-HP snapshot gave 3.9 a second.
- Reason: a host and a client must hear one gate.

## 2026-10-31 Stop means stop, pause means pause

- Decision: the adapter listens to `EventBus.paused_changed` and skips its enemy timers while paused, since `kit.cue` has no pause check and the view keeps updating. The junction also needs some rider's cadence over `CrankClock.STOP_RPM`: `team_w` is a 1 s mean that outlives the last stroke. The preview's junction now ends at the stop, so D4 sees the same.
- Reason: D4 and HARDWARE_TEST row 31. The mine and the pump still follow their drawn phase, which the Reserve flywheel holds after a stop: there the picture keeps moving, so the sound does too.

## 2026-10-31 Variation in what repeats, and an arc

- Decision: the creak's variants span 1.0 to 1.045 instead of 0.84 to 1.16 (machines stay untuned), peak at -6/-8.5/-7.5/-10.5/-8 (the critic's -9 and -12 took A5 under 0.6), and two have shapes of their own; the knock peaks at -6/-9. Coins: 4 variants, -22 dB. Every shot's single-file sounds take a small pitch from its spread seed; the ram cycles four pitches on gaps of 1.15 and 1.25 s. The adapter passes `in_wave` to the bed, which is 0 in a warm-up wave and a break: the lark and the far anvil (gap 9-22 s) keep to those. War drums (3 beats) sound while enemies are on the field. Crows caw one, two or three times. The wind's sine tremolos become irregular gain lists, searched for no envelope peak over 0.1 in the top band; the 1-3 kHz layer still peaks at 0.45 near 4 s, from its filter sweep. `crowd_far` moves up to 600-1500 Hz: 1.28-2.56 kHz now reads -6.9 dB under the machines at 90 rpm, against the -8 asked. The preview ends on 9 s of the calm hill, to be heard.
- Alternatives: the critic's drum `burst` of 3 to 5 at 0.62 s: `AmbienceBed` caps a burst at 1 s, so that is 2 beats. 0.48 s gives 3.
- Reason: the owner's "interesting to listen to". Budget: 4.488 MB of 4.5 (groan +79, strain +57, coins +28, drum +44, lark -35 KB). A long-run arc inside a wave is still only as much as the events give it: unmeasured since this pass.

## 2026-10-31 D6 and D10, the real figures

- D6's scenario passes no cues, so its Sfx figure is 0, and Siege cannot reach 8 riders (4 slots). A heavy-battle probe peaks at Machines 7, Sfx 10, loops 9, and the kit's pools enforce the caps. Request to the lead: add cues to that scenario.
- D10: `commit_8_machines_mean_ms` 0.113 against the 0.5 target (WASAPI, 90 rpm run of 6 s). It times the bench's machine: it excludes `SiegeAudio.update` and Siege's bank.

## 2026-10-31 A16 holds on the preview's seed only

- Decision: the preview keeps `seed` 184, found by searching, and this is not a claim about play. With the war drums in the bed, 45 of 3000 seeds have no two different spots within 2 s in a minute of wave; the median seed has 4 such pairs. Seed 184 also has a lark and an anvil in the preview's calm.
- Alternatives: longer gaps (fewer pairs, but four independent timers can't guarantee none, and A16 also wants 3 sounds a minute); a waiver. A shared minimum gap between spots belongs in `AmbienceBed`, which is the platform's: a request to the lead.
- Reason: spots on independent timers do sometimes overlap in play. It's a matter of taste on a hill, not a sync or safety fault, so it stays open for the critics and the Listen step.

## 2026-10-31 Levels, and how the mix is shaped

- Machines -20.82 LUFS, one other rider -11.32 LU, Ambience -29.76, Sfx -22.49 (waived, above), mix -19.90 LUFS, LRA 13.9, true peak -3.85 dBTP: otherwise inside SPEC 3.6. The LRA comes from the rider stopping and the calm at the end of the preview: with those left out it is about 2 LU.
- A8's bands forced the design. A timber wheel is all 80-500 Hz, so the saw under the groan wanders in pitch and sits through a high-pass, the pawl's weight is in its 640 and 1370 Hz modes, and the wind has a grass layer above 3.8 kHz. The top of the mix comes from the wind and from impacts' grit, not from the strokes: every locked sound stays at least 16 dB under the main stroke above 2 kHz (SPEC 5, `tests/games/siege/audio/bank.test.mjs`).
- The groan's chirp and a wandering saw replace the fixed saw of the first draft, whose stationary harmonics showed as flat lines in the spectrogram: the monotone rumble the owner asked not to get.
- The creak is a tonal squeak with a hard first transient, not a stick-slip pulse train: a pulse train reads as dozens of onsets (D1 counted 44 for 10). This may read as less woody than a true stick-slip. Nobody has heard it: it stays open for the Listen step.

## 2026-10-31 A leak's alarm answers once in 3 s

- Decision: `leak` rings `reach_alarm` at most every 3 s.
- Alternatives: one per event (a ram's battering is one leak per whole HP, a steady alarm); no alarm on leaks (the SPEC lists it).
- Reason: an alarm that never stops is not an alarm.
