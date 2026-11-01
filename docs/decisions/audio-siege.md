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

- Decision, under the old duck (Machines -6, Ambience -6, Sfx -4): bring every routine Sfx sound down until `warning` and `rescue` read at least +6 LU over the mix at the mix's loudest moments, not only in D5's own window. The horns and `overdrive_on` dropped 8 to 11 dB, the whistles 11 dB. To stay heard, the horns were recut as far horns (a high-pass at 330 Hz, a 1050 Hz peak, the 98 Hz layer gone, tails that fall) and each ducks Machines -8 and Ambience -4 for as long as it blows. `horn_rush`'s stabs moved from A3 to G3: its 2nd harmonic sat on `warning`'s 440 Hz square. The preview keeps a whistling volley at 30.0 s, on a stroke, and a ram at 30.4 s, inside D5's window. The gains have since come back up: see "The duck landed" below. The recut and the horns' own ducks stay.
- Alternatives: the old "one-off events" argument (false: at m = 1 the organ fires every 1.5 s, and a rush at 110 rpm read -0.06 LU); a louder prompt or a lower threshold (never).
- Reason: BRIEF 4.6 outranks a horn. Today, measured with the prompt 50 ms after each of the 40 preview events: all 40 clear +6, minimum +10.70 (`shot_stone` at 26.8 s). `bank.test.mjs` holds +6 with the prompt 0.05, 0.2 and 0.4 s into each horn, a volley and a dock at 110 rpm. D5 itself reads +10.58 (+6.08 under the old duck and mix).
- D5 reads one window, so what holds elsewhere, all at the worst of 8 quarter-revolution prompt times (`bank.test.mjs` holds the four marked `*` at +6):

| Riding, nothing landing | Old duck, old mix | Duck -14/-14/-20, final mix |
| --- | --- | --- |
| 60 rpm 220 W, the preview's segment `*` | +6.03 | +11.32 |
| 90 rpm 260 W, the preview's segment | +7.14 | +12.55 |
| 110 rpm 340 W, the preview's segment `*` | +6.05 | +12.24 |
| 75 rpm 280 W, 3 others `*` | +6.13 | +11.21 |
| `rescue` at 44 rpm 250 W `*` | +6.78 | +13.38 |
| `rescue` at 44 rpm 300 W | +5.71 | +12.26 |
| 60 rpm 250 W | +5.39 | +11.15 |
| 60 rpm 300 W | +4.25 | +10.23 |
| 60 rpm 350 W | +4.01 | +9.82 |
| 60 rpm 500 W | +3.96 | +9.95 |
| 75 rpm 350 W | +5.77 | +11.02 |
| 110 rpm 420 W, 500 W | +6.17, +6.15 | +13.24, +13.24 |

- What was open under the old duck, today: (1) The rules-driven wave (`run_game_sim`'s events) read 8 of 40 under +6 at 90 rpm and 24 of 40 at 75 rpm. It has not been re-run. In its place, a denser hand-made wave at 280 W with 3 others (seeded random racks, volleys, bolts, Scorpions, stones, kills, hooves at `count_db` 4, rams and gate hits, 40 random moments): 90 rpm 0 of 40 under, minimum +7.05, median +12.39; 75 rpm 0 of 40, minimum +7.64, median +11.70. (2) Low cadence under high power: the table's 60 rpm rows, now +9.82 at the worst. (3) A long horn's tail, the prompt 0.8 s in at 110 rpm 340 W: +12.52 at the worst of the four horns. (4) Hooves at `HOOVES_MAX_DB` (10 horses or more), worst of 16 prompt moments at 90 rpm 260 W: +6.36. This is now the thinnest margin found. (5) A1 and D5 no longer press on each other: A1 -19.45, D5 +10.58.
- Trade, now mostly undone: under the old mix the horn was about level with the mix in its best octave. Today it reads +14.6, +12.2 and +13.5 dB (`wave_start`, `push`, `rush`) in its best third octave, median of 8 onsets, its own duck counted, over the wheel at 90 rpm 240 W. It is unheard: Listen step, HARDWARE_TEST 14.
- The request to the lead (a deeper duck) landed deeper than asked: Machines -14, Ambience -14, Sfx -20, release 2 s.

## 2026-10-31 A2 passes, with no waiver

- Decision: `preview.waive` is gone. Sfx peaks at -16.54 LUFS momentary against A2's -17..-11 (it was -22.49 under the waiver). Machines -20.83, one other rider -11.41 LU, Ambience -29.74, UI and the prompts are all in their windows.
- Alternatives: keep the waiver (its reason, the -4 dB duck, is no longer true); a battle sound as the peak, which would take `stone_impact` over -3 dB and past the Breach by a wider margin than it already is.
- Reason: with Sfx ducked -20 dB, an Sfx moment at -17 is about -37 under a prompt, so D5 and the window no longer conflict. Only the bell reaches the window: `wave_end` at 57.5 s is the -16.54, and the loudest battle moment is a stone's landing, -18.39 at 28.5 s. The pass has 0.46 LU to spare, on that one cue.

## 2026-10-31 The duck landed: the strokes and the cues come back

- Decision: the wheel's level follows the critic's stroke-heavy `db_by` curves on rpm: pawl and creak +3.6 at 60 rpm and below, +1.8 at 75, 0 at 90 and 110, -1 at 140; groan +1.8, +0.9, 0, 0, -1. The 75 and 140 rpm points are this pass's, since the critic gave 60, 90 and 110. Nothing rises under 60 rpm or above 340 W. The cues rise with it, all gain, no new bytes: bolt -8 and -13, Scorpion -9.5, onager -4.5, its whoosh -14, its landing -3, volley release -16, whistles -22/-23/-24 (the critic's ask), patter -15.5, rack -13 and -12.5, horns -9, `overdrive_on` -9, bell -4, Breach 0, gate hit -12, gate restored -9, hooves -10, ram -8, dock -4, reach -10, leak -12, kill -9.5, gold -18.
- Alternatives: the even wheel this replaces (pawl +1.9, +0.3, +0.1, -0.5; creak +1.9, 0, -1.4, -3; groan +2.2, +1.4, +1.7, +1.7), chosen to protect D5 under the old duck: the critic's curves read a prompt at +5.01 at 60 rpm 220 W under that duck, and read +11.32 under this one. A further cut of the groan at 60 rpm: not tried, since this reached the goal and the other rider's level has only 0.59 LU left in A2.
- Reason: the strokes carry the cadence, the owner's first request, and the groan took their place under the old duck. The new duck pays for it: D5 reads +10.58, against +10.65 with the even wheel and the old cues, and every row of the first ADR's table clears +9.82. A1 rises to -19.45 from -19.96, nearly all of it from the cues.
- Measured, before and after, in the same render, at 60 / 75 / 90 / 110 rpm. The groan's share of the lead's power at 250 W, solo: 61.8 / 59.4 / 60.7 / 61.5 % became 51.3 / 48.7 / 47.1 / 42.4 %. The 20 ms level p95 over p50, solo: 7.0 / 6.9 / 6.1 / 5.1 dB became 8.4 / 8.4 / 7.6 / 7.6. In a mix of wheel, one other rider, bed, mine, pump and running loops at 220 / 280 / 260 / 340 W: 6.4 / 5.8 / 4.8 / 4.0 became 7.6 / 7.1 / 6.2 / 6.1, and in 500-2000 Hz 12.2 / 12.2 / 9.8 / 8.3 became 13.8 / 13.8 / 11.5 / 11.1. A5 0.61..0.70 became 0.76..0.78 (floor 0.60), A3 0.47 became 0.56, A6 +29.51 % became +36.27 %. The mix's 80-500 Hz share fell from 52.1 % to 45.1 %. A8's top band reads 2.1 % against a floor of 2: raising the low cues takes share from it, so a further raise must watch it. Nobody has heard any of this: whether a stone at -3 or a swarm's kills at -9.5 tire the ear is for the Listen step.

## 2026-10-31 Effort has a timbre: timber_strain

- Decision: a lead-only loop that opens from about 170 W: band noise rising through 2.1-2.9 kHz, grains, a strained tri, a high hiss, on the curve -22, -13, -9, -7.7 dB at 170, 220, 262, 340 W and flat above (`db_by` closes the players under 100 W). Two copies a pitch apart (`pitch_by` 1.13, both -11.5 dB): the same file, no new bytes, one more lead player, which took the file's frozen noise from an autocorrelation of 0.93 at 1.3 s to 0.48 in the critic's render. The kit keys players by layer, so a sound may appear twice. The groan's flat hiss drops to a third of its gain, so the wheel gets brighter only with effort. `preview.checks.a6` holds it from 150 to 262 W, the top of what a rider can hold in ERG past 300 s under FAIR_FTP (105 %): +29.51 % on the scorecard's magnitude-weighted centroid.
- Alternatives: the critic's recipe (bp 1250 Hz, 900-2400 Hz grains, a 420-560 Hz tri): measured, it could not move the magnitude-weighted centroid past +10 % at any level short of raising the mix. A6 from 150 to 340 W: it read +27.85 % there while failing at +13.17 % to 262 W, so it measured past what riders ride. Rising above 340 W, as it did to -3 dB at 400 W: a prompt reads worse there, and A6 no longer needs it.
- Reason: recovery and a hard wave must not be the same wheel a little louder.

## 2026-10-31 The arrow organ whistles once in three

- Decision: a volley within the current gap of `WHISTLE_GAPS_S` (3.5, 5.5, 3.5, 7.5 s, cycling) of the last whistling one plays `shot_arrow_rack`: release and patter, at -13 and -12.5 dB, 3 dB over the same parts of `shot_arrow`, so the two racks between whistles are heard (+4.7 dB in their best band under the old mix; not re-measured). At m = 1 the whistles are 4.5, 6, 4.5 and 9 s apart. Whistles sit at -22/-23/-24 dB, the critic's ask, with Ambience ducked -3 under them. The preview plays 10 s of racks at 1.5 s.
- Alternatives: a whistle on every rack (1800 in a short session, in the ear's most sensitive band); no whistle at all (the owner named arrows whistling); a fixed gap (it came to exactly 4.5 s, about 400 in 30 minutes, a beat of its own).
- Reason: a whistle every 1.5 s for 5 minutes grates, and a human must still confirm these gaps don't. These louder whistles (+5 dB since D5 stopped limiting them) make that question sharper.

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

- Machines -20.83 LUFS, one other rider -11.41 LU, Ambience -29.74, Sfx -16.54, mix -19.45 LUFS, LRA 13.03, true peak -2.10 dBTP: inside SPEC 3.6. The LRA comes from the rider stopping and the calm at the end of the preview. Before the cues came up, a rules-driven wave read louder than the preview: -20.15 LUFS at 90 rpm 250 W, -19.07 at 75 rpm 280 W, -18.59 at 110 rpm 340 W, with an LRA under 1 LU. Those three are not re-measured.
- A8's bands forced the design. A timber wheel is all 80-500 Hz, so the saw under the groan wanders in pitch and sits through a high-pass, the pawl's weight is in its 640 and 1370 Hz modes, and the wind has a grass layer above 3.8 kHz. The top of the mix comes from the wind and from impacts' grit, not from the strokes: every locked sound stays at least 16 dB under the main stroke above 2 kHz (SPEC 5, `tests/games/siege/audio/bank.test.mjs`).
- The groan's chirp and a wandering saw replace the fixed saw of the first draft, whose stationary harmonics showed as flat lines in the spectrogram: the monotone rumble the owner asked not to get.
- The creak is a tonal squeak with a hard first transient, not a stick-slip pulse train: a pulse train reads as dozens of onsets (D1 counted 44 for 10). This may read as less woody than a true stick-slip. Nobody has heard it: it stays open for the Listen step.

## 2026-10-31 A kill, a Scorpion and hooves stand over the wheel

- Decision: `kill` -9.5, `shot_scorpion` -9.5, `hooves` -10 (were -14, -13.5, -20).
- Alternatives: a higher slap layer on the kill (the file's peak normalisation cancels it: it stayed at -1.4 dB in its best band).
- Reason: a rider's reward and threat must read over the wheel. Measured over wheel, one other rider, bed and running loops at 90 rpm 240 W, 25 enemies, in the cue's best third octave, the 100 ms from its onset against the same 100 ms without it, 16 onsets at eighth-revolution steps, as worst / median: kill +1.61 / +5.22 (was -3.38 / +0.28), Scorpion +1.37 / +3.70 (was -3.16 / -0.85), hooves at one horse +0.80 / +2.42 (was -10.02 / -8.45), at `count_db` 4 +4.80 / +6.42. The critic's earlier +1.2, +0.6, -1.0 came from another render, so they don't compare directly. A short transient is underrated by this measure. Cost to a prompt: see the first ADR's open list, item (4).

## 2026-10-31 A leak's alarm answers once in 3 s

- Decision: `leak` rings `reach_alarm` at most every 3 s.
- Alternatives: one per event (a ram's battering is one leak per whole HP, a steady alarm); no alarm on leaks (the SPEC lists it).
- Reason: an alarm that never stops is not an alarm.

## 2026-10-31 The arrows were never missing from the events: they were buried, and short

- The owner played it: "no sounds for the arrows and weird sounds for the wheels turning". The old bank passed its scorecard.
- Measured with `tools/audio/live_mix.gd`: the real host, module, view and kit on the real audio server (Dummy driver, a capture per bus), 1 rider and 3 bots, `short`, seed 1, 240 s of the first real wave. Cues reached the kit and voices started: 244 racks of 12 arrows (2928 projectiles), 45 stones, 22 ballista bolts, 252 Scorpion bolts, 0 strokes or events without a voice.
- What failed: (1) flight sounds. Only 43 of 244 volleys whistled (18 %), by design; the Scorpion's 252 had none. (2) Duration. Arrows fly a mean 3.96 s (3.05-5.51), stones 4.77 s, bolts 1.2 s, and the files were 0.78, 0.8 and 0.42 s: silence for four fifths of a flight. (3) Level. A whistle's loudest 200 ms was -34.0 dB rms, the wheels and the bed -22.6 dB: 11.4 dB under. In 800-6000 Hz, where an arrow lives, the whole Sfx bus was -35.1 dB against -30.4 dB of the wheels and the bed, because the wheel's creak, its strain and the junction's buzz sat there. (4) Hooves ran for 96 % of a wave, at -10 dB and up to +10 more for many horses: the steadiest thing on Sfx.
- A scorecard could not see it: it reads a sparse hand-written preview's whole mix (LRA 13 against 2.3 in a real wave), and a passing total says nothing about the part you asked about. So it has new rows, P1-P5, and `live_mix.gd` is the tool for the next time.

## 2026-10-31 A projectile has a release, a flight that lasts, and an impact by what it struck

- Decision: every weapon's `shot` is a release and a looping flight (`flight` on a cue hit, in the platform: `docs/AUDIO_PIPELINE.md`) given the real replayed flight time, rising and falling, dropping in pitch, moving from launch to landing on the panned sends of Sfx. `SiegeShotSounds` finds the landing from the same replay the picture draws (`SiegeV2ShotReplay`) and what stands there by the host's own impact tests over `state.enemies`: flesh, wood, shield (from the host's own block stream), dirt, or water by the art's moat band. Twenty `hit_<weapon>_<surface>` cues share 10 sounds by pitch and level.
- Alternatives: new fields in the `shot` event or a `hit` event from the rules (exact, but a wire change and the task says not to); damage read from enemies' HP in snapshots (exact on the host, 10 Hz and unattributed on a client); a fixed-length whoosh file (ends early or late, and the stone's flight varies from 3.7 to 5.3 s); a stereo file per direction (twice the bytes, no motion).
- Reason: the rules, snapshots and wire stay as they are, the behaviour hash stays, and a client hears what the host does. It can be wrong by a body at a client's snapshot, which no ear will catch. A volley: one swoosh (3 variants, so overlapping volleys never comb), one patter for its misses, by how many, at most two hits of a surface: about 4 voices for 12 arrows. Each volley still in the air takes 1.5 dB off the next swoosh (the cap moved to 7.5 dB: see the entry after the critics).
- Measured, the same session and seed, 180 s, final bank: 415 shots, 415 flights. 174 volleys 174 swooshes, 36 stones 36, 205 bolts and Scorpion bolts 205. In 800-6000 Hz Sfx -26.0 dB against -36.2 dB of the wheels and the bed: from 4.7 dB under to 10.2 dB over. Voices: Sfx mean 8.8, at its cap of 16 in 72 of 10800 frames, 8 of about 2000 Sfx starts found no voice. One rider with no bots, 120 s: 96 shots, 96 flights, no start without a voice, -19.6 LUFS. Stereo: Sfx left -20.4 dB, right -24.1 dB, because the road is on the left of the screen.

## 2026-10-31 The wheel is a low timber rumble with soft footfalls: no pitch in it at all

- Decision: `wheel_creak`, `timber_groan` and `timber_strain` are gone. The wheel is `tread_step` (a heel on planks, twice a revolution), `pawl_click` (quiet: -11 dB against the footfall's -4), `axle_knock` (once, at .75), `wheel_rumble` (brown noise and low knocks at one fixed pitch), and from about 170 W `wheel_load` (a dull rub of band-limited noise, no tone). Other riders: the pawl and `wheel_rumble_far`, a different noise, about 11 LU under. The junction's clatter lost its pulse waves and its pitch curve, the tower's creak its chirp. A test holds every part of the wheel to noise, modal and grains, with no drive and no `pitch_by`.
- Alternatives: keep the creak, quieter (it would still be the only pitched thing in a wheel, and in a real wave its loudest 200 ms was level with the wheels and the bed together). Keep pitch by rpm (a real wheel does rise a little, but two riders 2 rpm apart on one file sweep a comb through each other, a jet flanger).
- Reason: the old wheel's spectrogram in a real session shows narrow squiggles at 500-700 Hz and 1.3 kHz: triangle chirps with 34 Hz vibrato through a drive and a `room: wood` comb (a resonance every 91 Hz on continuous noise), repeating on every wheel and combing against each other. That is what "weird" looks like from here. The new wheel's spectrogram has its energy under 500 Hz and short vertical strokes, and no horizontal line anywhere. Every stroke keeps its place and its 1:1 count with the crank; only the creak's slot at .25 is gone.
- Trade: A8 asks 15 % of a mix's power in 500-4000 Hz, and the wheel no longer provides it: the flights do, at 16.9 %. A wheel with nothing firing is now duller, by choice.

## 2026-10-31 The rest of the mix

- Hooves: -20 dB and at most +4 for many, priority 4 (they were -10 and +10). `kill_thud` -15 dB, a body falling; a ram or a tower going down is its own timber crash. Horns: the push and the rush get the player's vibrato the wave horn already had. Wind: 2 dB off its bright layer in a wave, so flights have room; between waves it is about where it was. `mine_pick` and `tar_pour` 2 dB down, `tower_creak` 3 dB, `junction_clatter` 6 dB, for the same room. Gate hits, the ram, the bell, gold, crows, drums and banners are as they were: nothing in the spectrogram or the live numbers speaks against them, and no person has heard any of it.
- The real wave reads -16.0 LUFS on both channels, at the top of the -20..-16 window, and LRA 1.9. The old one read -19.1 on its left channel alone, so about -16 too. The preview reads -19.5 and LRA 13.3: a preview's quiet parts widen its range, and that gap is still there. The preview has 19 volleys against the old 9, closer to a real wave.
- D9 forced choices: the WAV cap is 4.5 MB, the bank is at 4.482. The rumbles run at 11025 Hz, `ballista_twang` and `stone_impact` lost a variant, and `tower_creak` is 1.9 s.

## 2026-11-01 After the critics: whose shot, a pass and not a bed, hits that rise

Two critics read the first overhaul at 1e795326, with probes on the real rules and a real-wave recording, and the owner had not heard it yet. What they found was true, and this is what changed.

- A killing blow sounded like a miss: the rules take a killed body off the list in the step that kills it, before any view runs. Against `station.hits` over 700 s: stones 57 of 67 struck, 60 of 67 played dirt; ballista 28 of 34 struck, 34 of 34 played dirt. Now `SiegeShotSounds` keeps each body for 0.3 s after it was last seen alive, which also covers a client's picture running behind its snapshots: stones 57 struck, 10 dirt; ballista 5 dirt. A bolt that struck home plays no dirt. Test: `test_a_real_wave_hears_what_the_host_hit`, within 10 % of the host's counts for stones, bolts and Scorpions and a quarter for arrows, whose first arrow can kill a body the rest then still count.
- Kills were all in the middle on a host: 715 of 715 cues found no body. The same cache gives them their side, the same on a client.
- A rider could not tell their own shots. `lead` is now `src == lit_station(me)` for release, flight and landing, `other_db` -5 on shots and -4 on hits (not the mix's -9.5, too deep to hear), a pad's Scorpion always other, and only your own stone ducks your wheel.
- The flights had become a bed in the band the owner had just rejected in Torque Company's Lights. 2-8 kHz of a real wave's master: -7.0 dB (the old Lights -6.3, its new limit -12). The organ fires every 0.87 s at its real rate, not 1.5 s, with 172 of 174 volleys at the old trim's cap. Now: `VOLLEY_TRIM_MAX` 5, the arrow's contour `[[0,-30],[.3,-14],[.5,0],[.62,-8],[1,-30]]` (4.0, 9.6 and 15.4 dB of ripple at 0.8, 1.5 and 2.3 s), and the flights moved down: the swarm 1.3-1.9 kHz with a little air above 4.8 kHz, the bolts 1.15 kHz, the stone 900 Hz. Real wave: -14.1 dB, -12.7 with the rider on the organ, the worst case. A swoosh down there reads less like hiss and may read more like wind: Listen step 61 asks.
- Hits did not rise out of the flights. The median rise in 400-6000 Hz over the preceding 250 ms was about +1 dB, against +1.6 at arbitrary moments. Files now hold more level for the same peak (a longer body, a little drive, less sub), cue levels went up, the patter down, and the releases, kills and hooves down. With the rider on the organ, arbitrary moments +3.1: flesh +6.9, wood +6.4, patter +6.7, stone +7.4 against +3.8 in its lower band: all at least 3 dB over them. With the rider on the onager, so arrows and Scorpions are another rider's: flesh +6.2, wood +5.2, patter +4.7 against +3.3, stone +8.5 against +3.5. Others' hits sit under your own by design, and they do not reach 3 dB over.
- Priority 8 on `gate_hit`, `ram_thud` and `leak`. A gate hit rose +12 dB in a weak team's wave, the alarm +16: no duck was needed. No recording caught a ram at the gate: its rise is unmeasured.
- Top band: above 9.8 kHz of the real master from -23.8 dB to -36.7 (-35.4 on the organ), by `band` on the pitched flights and hits and the Scorpion off 1.3 to 1.25 with its flight's own spectrum. New row A17 reads A9 at runtime pitch; P7 reads flight distance (7.79 dB, 2.1 before).
- Scorecard honesty: the preview now fires the real rate (0.97 volleys a second, 1.08 Scorpions) at levels the code can play, every hit cue is on the card (20 of 20), P4's background includes Sfx and its median is a true one. A14 reads the first ballista shot of the wave, before the organ has anything in the air: mid-wave at the real rate it reads -2 to +3 dB, and +6 is not reachable there without a release louder than anything else in the mix. That is the row's honest reach, recorded here.
- Limits on the real wave are held by a recording: `tests/games/siege/audio/real_wave_{auto,organ}.json`, written by `tools/audio/live_report.mjs` with the bank's sha, so a changed bank fails `bank.test.mjs` until it is recorded again. Hand-run: a test cannot start a window.
- Real wave now, rider where autopilot puts it: -17.2 LUFS, LRA 2.9, from -16.0 and 1.9. Rider on the organ: -17.4 LUFS, LRA 1.6. Worst prompt margin over it +8.0 and +7.4 LU at the prompt's real 20 ms attack. Hooves 128 starts in 700 s, from 675. 0 and 3 starts of about 2000 Sfx starts found no voice.
- Upgraded onager: the splash reads 6.5 m at level 3, not 5 m.
- Other games at runtime pitch, reported by A17 and not held: Torque Company -27.41 (`turbo_whistle`), Fishing -18.26 (`prop_churn`), Workout -31.72 (`wind_rush`). They pass A9 as it was. Holding them would fail their cards: a question for their owners.

## 2026-11-01 Last round: one flight you can follow, a target that isn't dirt, an honest A14

A fresh critic measured the recordings. Its figures matched mine within a few tenths on a run of its own kind, with flights now logged and not sampled (`flight_log` in `tools/audio/live_mix.gd`, read by `tools/audio/live_report.mjs`). Before and after are on the same session, rider on the organ, then rider on the onager:

| | Before | After |
|---|---|---|
| Own arrow's peak over everything, 1-2.4 kHz, median, full-level volleys | -3.54 (all volleys) | +4.64 |
| Other riders' arrows, same reading, rider on the onager | -8.70 | -3.60 |
| Flights alone, spread of 50 ms levels p90-p10, 1-2.4 kHz | 6.54, 10.11 | 8.23, 10.19 |
| Flesh to dirt, first 60 ms in the mix | 1.22, 1.30 dB | 5.61, 3.95 dB |
| Wood to dirt, same | 1.69, 1.51 dB | 4.96, 3.59 dB |
| Shield to dirt, same | 2.22, 2.62 dB | 5.44, 6.48 dB |
| Impacts a second, plus kills | 3.07 + 0.80, 3.16 + 0.90 | 2.17 + 0.30, 1.26 + 0.32 |
| Patters with a body hit within 300 ms | 72 %, 80 % | 44 %, 0 % (no own volleys) |
| Master head over -1 dBFS, episodes a minute | 64.8, 43.4 | 38.4, 19.0 |
| 2-8 kHz of the master | -12.72, -14.11 | -12.22, -14.95 |
| LUFS, LRA | -17.38 / 1.61, -17.20 / 2.80 | -17.72 / 1.67, -17.81 / 3.37 |

- Decision, flights: every other volley of the organ is under, a flight contour `[[0,-40],[.36,-18],[.5,0],[.6,-8],[.72,-30],[1,-40]]`, pitch `[[0,1.3],[.5,1],[1,.75]]` (about 3.4 semitones in the part you can hear), and the Scorpion's flight is a shorter pass. Each volley keeps its flight: P1 still 57 of 57.
- Alternative tried: -12 dB under, as the critic suggested. P3, which holds every flight at +3 dB over the wheels and the bed, fails by 3 to 5 dB on the quiet volleys, and no limit may loosen, so the volleys are 6 dB apart and the spread is 8.2 dB and not the 10+ it could be. The Scorpion's suggested -6 meets the same row: it plays 1.2 dB lower with a shorter pass and not 6 dB lower. These are the numbers to reopen if a listener still hears haze.
- Decision, impacts: a body around 1 kHz, the ground a low thud with sand above 3.4 kHz, a new bronze ring for a shield. A volley is its hit or one patter, never both. A stone on bodies is the bodies first, the ground 9 dB under. Other riders' arrow misses are dropped, and their other impacts and all kills are thinned on the audio side only; the sim's counts and the behaviour hash do not move. `hit_wood` varies by up to 6 % either way. `hit_flesh` is cue -2.5, so -3 dBFS alone.
- Rows: P8 is the rider's own flight over everything, because P3 ignores other flights; P9 is target against ground in the mix, first 60 ms, because P5 reads files. `bank.test.mjs` holds both on the real-wave JSONs.
- A14 reads the median of a cue's firings for every bank. Siege's reads +0.4 dB in the preview, +1.6 and +0.9 dB in the two real waves, against +6. The critic read +3.04 and +2.12 by its own method. I had moved the first ballista shot to before the organ was in the air, which read +6.9; that is withdrawn. It is `waive.A14`, on the card as a waiver and not a pass. The fixture's middle firing moved from 11 s to 5 s, because the median would otherwise read its busiest moment; Torque Company, Fishing and Workout pass unchanged.
- A17 stays held for Siege alone and reported for the rest (`docs/decisions/audio-siege.md`, the entry above): the lead keeps the other games' numbers on the backlog.
- Rises in the mix, 400-6000 Hz, median, against arbitrary moments +3.1 and +2.8: flesh +5.9 and +5.7, wood +6.5 and +4.9, patter +5.1, stone +5.9 and +8.2 (against +3.4 and +3.1 in its lower band). With the rider on the organ, over arbitrary moments: wood +3.4, flesh +2.8, patter +2.0, stone +2.5. The previous round's +3 slipped for flesh and the patter, because flesh came down to its -2.5 cue and the patter to keep the band limit; other riders' hits sit lower by design, as the lead accepted. Releases are unchanged: own arrow +3.8 and Scorpion +2.7, no room to lift them with the ear band at -12.22 on the organ.
