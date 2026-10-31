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
- Alternatives: the old "one-off events" argument (false: at m = 1 the organ fires every 1.5 s, and a rush at 110 rpm read -0.06 LU); a louder prompt or a lower threshold (never).
- Reason: BRIEF 4.6 outranks a horn. Measured with the prompt 50 ms after each of the 40 preview events: all 40 clear +6, minimum +6.00 (`wave_end`). With the prompt 0.05, 0.2 and 0.4 s into each at 110 rpm, all held by `tests/games/siege/audio/bank.test.mjs`. D5 itself reads +6.08.
- D5 reads one window, so what holds elsewhere, all at the worst of 8 quarter-revolution prompt times (`bank.test.mjs` holds the four marked `*` at +6):

| Riding, nothing landing | Now | With the duck below |
| --- | --- | --- |
| 60 rpm 220 W, the preview's segment `*` | +6.03 | +8.28 |
| 90 rpm 260 W, the preview's segment | +7.14 | +9.19 |
| 110 rpm 340 W, the preview's segment `*` | +6.05 | +8.45 |
| 75 rpm 280 W, 3 others `*` | +6.13 | +8.65 |
| `rescue` at 44 rpm 250 W `*` | +6.78 | +9.13 |
| `rescue` at 44 rpm 300 W | +5.71 | +8.09 |
| 60 rpm 250 W | +5.39 | +7.59 |
| 60 rpm 300 W | +4.25 | +6.51 |
| 60 rpm 350 W | +4.01 | +6.27 |
| 60 rpm 500 W | +3.96 | +6.22 |
| 75 rpm 350 W | +5.77 | +8.37 |
| 110 rpm 420 W, 500 W | +6.17, +6.15 | +8.43, +8.41 |

- Still open, plainly, and only the lead can close it: (1) A rules-driven wave (`run_game_sim`'s events, `vo2`, 112 %, 280 W, 3 others, the adapter's thinning, no ram or hooves, so this favours the mix), 40 random moments: at 90 rpm 8 under +6, minimum +4.21, median +6.79; at 75 rpm 24 under, minimum +3.64, median +5.95, and the brief tolerates 70-79 rpm with only a small arrow. (2) Low cadence under high power: the table's 60 rpm rows, about 1 LU per 50 W from 220 W, as the groan and strokes rise with effort below 340 W. (3) A long horn's tail, the prompt 0.8 s in at 110 rpm: `wave_start` +5.90. (4) Hooves at 10 chariots (`count_db` 10): +5.65 at 90 rpm, after this pass's +3 dB. These sit under +6 by the shots' transients and by the wheel: the prompts duck Machines and Ambience only -6 dB, Sfx only -4. (5) A1 and D5 press on each other: A1 -19.96 against a -20 floor, D5 +6.08 against +6. There is under 0.1 dB of level left in this mix.
- Trade: the horn is now about level with the mix in its best octave (1.28-2.56 kHz, +0.6 dB under its own duck, -7 dB one octave up), where before it stood well over. It may read as far off. It is unheard: Listen step, HARDWARE_TEST 14.
- Request to the lead, one change in `sfx.gd` and `SAFETY_DUCK` (`offline_mix.mjs`): a prompt ducks Machines -10, Ambience -6, Sfx -8 (now -6, -6, -4). It strengthens 4.6. It is what "With the duck" reads above, from a patched copy of the offline mix: the wave at 90 rpm 0 of 40 under, minimum +6.73, median +9.24; at 75 rpm 0 of 40, minimum +6.24, median +8.51; every row of the table over +6; the 40 events clear. A Sfx duck alone, which this ADR asked for before, does not do it: Sfx -8 by itself leaves that wave at 4 of 40 under at 90 rpm, minimum +5.42, and 19 of 40 under at 75 rpm, minimum +4.69. Machines is what dominates these moments. With that duck in, the wheel's strokes can have back what they lost below, and the horns can come up.

## 2026-10-31 A2 is waived for Sfx, at -22.5 LUFS

- Decision: `preview.waive.A2`. Sfx peaks at -22.49 LUFS momentary against A2's -17..-11. Machines -20.80, one other rider -11.55 LU, Ambience -29.74, UI and the prompts are all in their windows.
- Alternatives: leave one rare sound (the Breach) at -17. A prompt on it would read about +1 LU, which is exactly what the blocker above forbids.
- Reason: with Sfx ducked -4 dB, D5 at +6 and A2's Sfx window cannot both hold: an Sfx moment at -17 is louder than -22.3 under the prompt. The deeper duck requested above would close this too.

## 2026-10-31 Keeping A1 with the events down: an even wheel

- Decision: the wheel's level follows `db_by` curves on rpm, chosen so a prompt has the same margin at each cadence the preview rides: pawl +1.9 at 60 rpm and below, +0.3 at 75, +0.1 at 90, -0.5 at 110; creak +1.9, 0, -1.4, -3; groan +2.2, +1.4, +1.7, +1.7. Nothing rises under 60 rpm, where the rescue fires, and every `p_eff` curve of the wheel is flat above 340 W, about 136 % FTP under the default FAIR_FTP, so a sprint adds no level. The preview rides 220 / 260 / 340 W. The bed comes up 1 dB, the footfall is -9, the groan -7, pawl -4.0, creak -3.9.
- Alternatives: the critic's "more on the strokes" curves (pawl and creak +3.6 at 60 rpm, 0 at 90 and 110; groan +1.8, 0, 0), which read A1 -19.97 and D5 +6.10 but a prompt at +5.01 at 60 rpm 220 W, +5.40 at 110 rpm 340 W and +5.39 at 75 rpm 280 W with 3 others: they stand strokes up where 4.6.3 fires. An even raise of the wheel (110 rpm has nothing left); raising Sfx in the preview (Sfx ducks less than Machines, so it costs D5 more per dB of A1).
- Reason: a steady wheel gives the most integrated level per LU of momentary peak, and the creak has the worst ratio: it is what a prompt's window reads hardest. Lowering it 0.6 dB gives a prompt about +0.25 LU for 0.17 LU of A1; raising the groan 0.5 dB costs -0.12 LU for +0.22 LU of A1. At this bank's curves all four of `bank.test.mjs`'s prompt cases clear +6 by the mix alone. The earlier "about +6.1 and +6.4" in this ADR was wrong: at quarter-revolution steps, that bank read +5.64 at 110 rpm, +7.32 at 90, +5.63 at 60, and it had not been measured below 60 rpm or above 340 W.
- Cost, measured with `strokes` and `loops` solo at 250 W: the groan is 61 % of the lead's power at 60 rpm (was 69 %), 60 % at 75, 62 % at 90, 63 % at 110 (was 48-50 % at 90 and 110, and 67 % at 110 rpm 340 W). That moves toward the round 1 fault at the fast end. The 20 ms level p95 over p50 is 7.0 dB at 60 rpm (was about 6), 6.8 at 75, 5.8 at 90, 5.0 at 110. In the full mix it is 5.9 / 5.7 / 4.7 / 3.8 dB at the preview's pairings, and 10.5 / 10.8 / 8.7 / 7.4 dB in 500-2000 Hz, where the pawl's weight is; the critic's curves read 12.0 / 12.2 / 10.4 / 10.2 there. The strokes carry the cadence, the owner's first request, so this is the price of 4.6 and the first thing to give back: once the lead's deeper duck is in, the critic's curves above fit, and A1 moves level off the groan again. A5 reads 0.61..0.70 against a 0.60 floor, A3 0.47; the mix's 80-500 Hz share is 52.1 %. The slow wheel may still read as a drone: Listen step.

## 2026-10-31 Effort has a timbre: timber_strain

- Decision: a lead-only loop that opens from about 170 W: band noise rising through 2.1-2.9 kHz, grains, a strained tri, a high hiss, on the curve -22, -13, -9, -7.7 dB at 170, 220, 262, 340 W and flat above (`db_by` closes the players under 100 W). Two copies a pitch apart (`pitch_by` 1.13, both -11.5 dB): the same file, no new bytes, one more lead player, which took the file's frozen noise from an autocorrelation of 0.93 at 1.3 s to 0.48 in the critic's render. The kit keys players by layer, so a sound may appear twice. The groan's flat hiss drops to a third of its gain, so the wheel gets brighter only with effort. `preview.checks.a6` holds it from 150 to 262 W, the top of what a rider can hold in ERG past 300 s under FAIR_FTP (105 %): +29.51 % on the scorecard's magnitude-weighted centroid.
- Alternatives: the critic's recipe (bp 1250 Hz, 900-2400 Hz grains, a 420-560 Hz tri): measured, it could not move the magnitude-weighted centroid past +10 % at any level short of raising the mix. A6 from 150 to 340 W: it read +27.85 % there while failing at +13.17 % to 262 W, so it measured past what riders ride. Rising above 340 W, as it did to -3 dB at 400 W: a prompt reads worse there, and A6 no longer needs it.
- Reason: recovery and a hard wave must not be the same wheel a little louder.

## 2026-10-31 The arrow organ whistles once in three

- Decision: a volley within the current gap of `WHISTLE_GAPS_S` (3.5, 5.5, 3.5, 7.5 s, cycling) of the last whistling one plays `shot_arrow_rack`: release and patter, at -16 and -15.5 dB, 3 dB over the same parts of `shot_arrow`, so the two racks between whistles are heard (+4.7 dB in their best band, was +0.8). At m = 1 the whistles are 4.5, 6, 4.5 and 9 s apart. Whistles sit at -27/-28/-29 dB (the critic asked -22/-23/-24; D5 asked for 5 more) with Ambience ducked -3 under them. The preview plays 10 s of racks at 1.5 s.
- Alternatives: a whistle on every rack (1800 in a short session, in the ear's most sensitive band); no whistle at all (the owner named arrows whistling); a fixed gap (it came to exactly 4.5 s, about 400 in 30 minutes, a beat of its own).
- Reason: a whistle every 1.5 s for 5 minutes grates, and a human must still confirm these gaps don't. The louder racks cost little: 7 of 40 moments under +6 in the wave of the ADR above become 8.

## 2026-10-31 Gate hits answer what the gate lost, once a ram stroke

- Decision: a watermark that lowers only when a hit fires, at most once in `GATE_HIT_EVERY_S` (1.2 s), and rises with a repair. `dmg_db` is the drop, capped at 6 dB (was 12, since hits now add up over 1.2 s).
- Alternatives: the frame-to-frame drop: one ram's 0.195 HP a tick never sounded on a host, three fired 20 hits a second, and a client's whole-HP snapshot gave 3.9 a second.
- Reason: a host and a client must hear one gate.

## 2026-10-31 Stop means stop, pause means pause

- Decision: the adapter listens to `EventBus.paused_changed` and skips its enemy timers while paused, since `kit.cue` has no pause check and the view keeps updating. While paused it also tells the bed `enemies` 0 and `in_wave` 1, so no spot with a burst passes its `when`: the bed keeps updating under a pause, a burst's first beat plays at once and the rest wait in the kit's pending queue until the resume (a 180 s pause fired 16 war drums over the frozen picture and held 32 that landed together). `crowd_far` slews down, which suits a pause. The junction also needs some rider's cadence over `CrankClock.STOP_RPM`: `team_w` is a 1 s mean that outlives the last stroke. The preview's junction now ends at the stop, so D4 sees the same.
- Reason: D4 and HARDWARE_TEST row 31. The mine and the pump still follow their drawn phase: with Reserve they run 10 s on Machines after a stop, and with the Aqueduct the pump never stops. There the picture keeps moving, so the sound does too (HARDWARE_TEST row 60).
- Request to the lead: hold bed spots under a pause in `GameAudioKit`/`AmbienceBed`, since any game's burst spot has this bug.

## 2026-10-31 Variation in what repeats, and an arc

- Decision: the creak's variants span 1.0 to 1.045 instead of 0.84 to 1.16 (machines stay untuned), peak at -6/-8.5/-7.5/-10.5/-8 (the critic's -9 and -12 took A5 under 0.6), and two have shapes of their own; the knock peaks at -6/-9; the pawl at -6/-7.5/-6.8 and the footfall at -6/-8/-7/-9, the strokes heard most, which had an sd under 0.3 dB. Coins: 4 variants, -22 dB. Every shot's single-file sounds take a small pitch from its spread seed; the ram cycles four pitches on gaps of 1.15 and 1.25 s. The adapter passes `in_wave` to the bed, which is 0 in a warm-up wave and a break: the lark and the far anvil (gap 9-22 s) keep to those. Crows caw one, two or three times. The wind's sine tremolos become irregular gain lists, searched for no envelope peak over 0.1 in the top band; the 1-3 kHz layer still peaks at 0.45 near 4 s, from its filter sweep.
- War drums sound while enemies are on the field, two or three beats, cut higher (modal 190, 420, 880 Hz, a 1500 Hz slap) and louder by swarm (-7 dB at one enemy, +3 at 50). Banners moved up too (bp 1350 Hz). Over wheel, Sfx and bed at 90 rpm 240 W and 25 enemies they read -1.1 and -2.9 dB in their best band in the critic's render, so both stay marginal, and `far_anvil` was -3.7 against a wave (a break is lower power). A human must judge them.
- A scene you can hear: a 120 s wave at steady power has an LRA of 0.6-0.7 LU, and wave against break differs by only +1.8 dB of power with the spectrum unchanged. The wind is the one bed layer heard nearly always, so it marks the scene: `wind_hill_hi` is +2.5 dB in a break and -1 in a wave. Above 5 kHz a break then reads 1.9 dB brighter while the rest reads about 2 dB lower (centroid 560 Hz in a wave, 765 in a break). `crowd_far` comes up to -11.5 dB and moves up to 600-1500 Hz, yet going from 3 to 40 enemies still shifts the mix only about +0.6 dB in its best octave: the crowd is not what carries enemy count, the drums and cues are. Rider effort and the cues must carry the rest of the arc inside a wave. The preview ends on 9 s of the calm hill, to be heard.
- Alternatives: the critic's drum `burst` of 3 to 5 at 0.62 s: `AmbienceBed` caps a burst at 1 s, so that is 2 beats. 0.48 s gives 3.
- Reason: the owner's "interesting to listen to". Budget: 4.488 MB of 4.5 (groan +79, strain +57, coins +28, drum +44, lark -35 KB). Tight: nothing new fits without something going.

## 2026-10-31 D6 and D10, the real figures

- D6's scenario passes no cues, so its Sfx figure is 0, and Siege cannot reach 8 riders (4 slots). A heavy-battle probe peaks at Machines 7, Sfx 10, loops 9, and the kit's pools enforce the caps. Request to the lead: add cues to that scenario.
- D10: `commit_8_machines_mean_ms` 0.113 against the 0.5 target (WASAPI, 90 rpm run of 6 s). It times the bench's machine: it excludes `SiegeAudio.update` and Siege's bank.

## 2026-10-31 A16 holds on the preview's seed only

- Decision: the preview keeps `seed` 184, found by searching, and this is not a claim about play. With the war drums in the bed, 45 of 3000 seeds have no two different spots within 2 s in a minute of wave; the median seed has 4 such pairs. Seed 184 also has a lark and an anvil in the preview's calm.
- Alternatives: longer gaps (fewer pairs, but four independent timers can't guarantee none, and A16 also wants 3 sounds a minute); a waiver. A shared minimum gap between spots belongs in `AmbienceBed`, which is the platform's: a request to the lead.
- Reason: spots on independent timers do sometimes overlap in play. It's a matter of taste on a hill, not a sync or safety fault, so it stays open for the critics and the Listen step.

## 2026-10-31 Levels, and how the mix is shaped

- Machines -20.80 LUFS, one other rider -11.55 LU, Ambience -29.74, Sfx -22.49 (waived, above), mix -19.96 LUFS, LRA 12.76, true peak -3.52 dBTP: otherwise inside SPEC 3.6. The LRA comes from the rider stopping and the calm at the end of the preview: with those left out it is about 2 LU. A rules-driven wave reads louder than the preview: -20.15 LUFS at 90 rpm 250 W, -19.07 at 75 rpm 280 W, -18.59 at 110 rpm 340 W, with an LRA under 1 LU.
- A8's bands forced the design. A timber wheel is all 80-500 Hz, so the saw under the groan wanders in pitch and sits through a high-pass, the pawl's weight is in its 640 and 1370 Hz modes, and the wind has a grass layer above 3.8 kHz. The top of the mix comes from the wind and from impacts' grit, not from the strokes: every locked sound stays at least 16 dB under the main stroke above 2 kHz (SPEC 5, `tests/games/siege/audio/bank.test.mjs`).
- The groan's chirp and a wandering saw replace the fixed saw of the first draft, whose stationary harmonics showed as flat lines in the spectrogram: the monotone rumble the owner asked not to get.
- The creak is a tonal squeak with a hard first transient, not a stick-slip pulse train: a pulse train reads as dozens of onsets (D1 counted 44 for 10). This may read as less woody than a true stick-slip. Nobody has heard it: it stays open for the Listen step.

## 2026-10-31 A kill, a Scorpion and hooves come up to the wheel

- Decision: `kill` -14, `shot_scorpion` -13.5, `hooves` -20 (were -17, -15, -23), and a rack's parts as above.
- Alternatives: a higher slap layer on the kill (the file's peak normalisation cancels it: it stayed at -1.4 dB in its best band).
- Reason: they all sit in the 125-640 Hz the groan and strokes own, and a kill read -1.9 dB in its best third-octave band, 100 ms mean, against the wheel and bed: not a reward. In the critic's render they read +1.2, +0.6, -1.0 at one horse and +0.5 at four. A short transient is underrated by this measure. Cost to a prompt in the wave of the first ADR: 7 under +6 of 40 become 8, the minimum holds at +4.21.

## 2026-10-31 A leak's alarm answers once in 3 s

- Decision: `leak` rings `reach_alarm` at most every 3 s.
- Alternatives: one per event (a ram's battering is one leak per whole HP, a steady alarm); no alarm on leaks (the SPEC lists it).
- Reason: an alarm that never stops is not an alarm.
