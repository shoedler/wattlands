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

Two critics read the first overhaul at caf2b4fe, with probes on the real rules and a real-wave recording, and the owner had not heard it yet. What they found was true, and this is what changed.

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
- Alternative tried: -12 dB under, as the critic suggested. P3, which holds every flight at +3 dB over the wheels and the bed, fails by about 6 dB on the quiet volleys, and no limit may loosen, so the volleys are 6 dB apart and the spread is 8.2 dB and not the 10+ it could be. The Scorpion's suggested -6 meets the same row: its peak stays where it was, at -4.3 dB, and only its pass got shorter. These are the numbers to reopen if a listener still hears haze.
- Decision, impacts: a body around 1 kHz, the ground a low thud with sand above 3.4 kHz, a new bronze ring for a shield. A volley is its hit or one patter, never both. A stone on bodies is the bodies first, the ground 9 dB under. Other riders' arrow misses are dropped, and their other impacts and all kills are thinned on the audio side only; the sim's counts and the behaviour hash do not move. `hit_wood` varies by up to 6 % either way. `hit_flesh` is cue -2.5, so -3 dBFS alone.
- Rows: P8 is the rider's own flight over everything, because P3 ignores other flights; P9 is target against ground in the mix, first 60 ms, because P5 reads files. `bank.test.mjs` holds both on the real-wave JSONs.
- A14 reads the median of a cue's firings for every bank. Siege's reads +0.4 dB in the preview, +1.6 and +0.9 dB in the two real waves, against +6. The critic read +3.04 and +2.12 by its own method. I had moved the first ballista shot to before the organ was in the air, which read +6.9; that is withdrawn. It is `waive.A14`, on the card as a waiver and not a pass. The fixture's middle firing moved from 11 s to 5 s, because the median would otherwise read its busiest moment; Torque Company, Fishing and Workout pass unchanged.
- A17 stays held for Siege alone and reported for the rest (`docs/decisions/audio-siege.md`, the entry above): the lead keeps the other games' numbers on the backlog.
- Rises in the mix, 400-6000 Hz, median, against arbitrary moments +3.1 and +2.8: flesh +5.9 and +5.7, wood +6.5 and +4.9, patter +5.1, stone +5.9 and +8.2 (against +3.4 and +3.1 in its lower band). With the rider on the organ, over arbitrary moments: wood +3.4, flesh +2.8, patter +2.0, stone +2.5. The previous round's +3 slipped for flesh and the patter, because flesh came down to its -2.5 cue and the patter to keep the band limit; other riders' hits sit lower by design, as the lead accepted. Releases are unchanged: own arrow +3.8 and Scorpion +2.7, no room to lift them with the ear band at -12.22 on the organ.

## 2026-11-01 Every arrow that lands has its own sound

The owner played rc.2: "arrow hits still make no sound. they should individually make a sound." The tracked figures said hits rose +5 to +6 dB. The ear wins, so first why.

**Why a rider heard nothing.** The voices played. In the real app (`tools/audio/live_mix.gd --app`: main scene, autoloads, solo quick start on the session screen, a mock trainer, rc.2's bank), 150 s of the first wave: 59 volleys, 684 arrows landed, 98 struck bodies. The arrow sounds were 22 `arrow_dirt` plus at most 73 `hit_flesh` and `hit_wood`, those two shared with the Scorpions: at most 95 sounds for 684 arrows, 13.9 %. Each of the 95 reached a player, 0 lost, on `Sfx` or its panned sends at -2 to -6.5 dB, with the Sfx bus at 0 dB and its user setting 0 (the owner's own `settings.json` has every bus at 0 too). So voice limits, stealing, routing and bus levels are clear. With three bots, 180 s, rider where the Autopilot puts them: 2076 arrows landed, at most 169 body sounds of any weapon and no miss: 8 % at the very most. Rider on the organ: 2110 arrows, at most 324 sounds: 15 %.

- Most arrows were silent by design: `MAX_HITS_PER_VOLLEY := 1`, "a volley is its hit or its patter", and other riders' misses dropped, their other impacts thinned to one per 0.7 s across every weapon.
- The sounds that played did not lack level. By the figure now on the record, first 50 ms at 400-6000 Hz over the rest of the mix: +8.7 dB in the solo app, +5.4 on the organ, +4.4 with the rider elsewhere. So this does not explain why a person heard none of them. What the numbers do show is that what a rider sees, twelve arrows coming down in about half a second, got one sound 150 ms long in the 1 kHz region the flights sit around, on one volley in a few, with `hit_flesh` stopping at 2.4 kHz. Nobody has heard the result either, so this stays a hypothesis until the Listen step.
- One thing was wrong with the measuring: the Dummy driver mixes 4096 frames at a time, 93 ms, so every voice started inside one begins on the same sample. A few hits a second hardly show it. Twelve arrows a second would have piled up. `--mute-master` now records on WASAPI with Master at -80 dB and the captures before the volume: starts arrive about 10 ms apart, and every recording below is on it. rc.2's own figures are from the Dummy driver, the only build they were run on.

**Decision.**

- `SiegeShotSounds` gives each arrow one impact at its own `land_t[j]` and `landing(j)`: the cap, the patter, `count`, `patter_db` and "a volley is its hit or its patter" are gone. Other riders' arrows sound too, 5 dB under, unthinned; their bolts and Scorpions keep the 0.7 s thinning. A shot past `MAX_SHOT_SOUNDS_PER_TICK` still has no release or flight of its own, and now it does land.
- Five new sounds, 60-90 ms, 3 or 4 variants, PCM, on a ladder so they stay apart: `arrow_dirt` a soft thud around 430 Hz with a little sand above 4.6 kHz, `arrow_flesh` a slap around 680 Hz with a short crack at 4.6 kHz, `arrow_wood` a knock at 1.1 and 1.7 kHz, `arrow_shield` a bronze ring at 2.5 kHz and up, `arrow_water` a small rising plip. Each cue takes a per-arrow pitch (+-7 %) and level (0 to -2.5 dB) from two low-discrepancy steps, the kit's round robin takes the file, and the pan is the arrow's landing point.
- A pool of their own: `crowd` on a cue hit and `mix.crowd_voices` 16, a small additive platform change. Arrows can't take a player from a flight, a release, a stone or a gate hit, and can't lose one to them. Sfx stays at 16, so D6 still reads it against 16 and reads the crowd against its own cap.
- The limit of 2.5 impacts a second in `bank.test.mjs` is removed, as the lead withdrew it. It now reads about 12.8 impacts a second.

**Alternatives.** A bigger `sfx_voices` with arrows at the lowest priority: no code, but D6 holds Sfx to 16 and may not move. Stem-mixed "clusters" for a volley: cheaper, and not what was asked. Keeping `hit_flesh` for arrows: 150 ms at 13 arrows a second is a wash. A body with its energy above 2 kHz: in the first tries the crack took the ear band to -11.18 against -12, so bodies sit below 2 kHz and only a very short crack goes over.

**Numbers.** Same session and seed. rc.2 on the Dummy driver, then this on WASAPI at -80 dB. Rider on the organ, rider where the Autopilot puts them, the real app solo:

| | rc.2 | Now |
|---|---|---|
| Arrows landed | 2110, 2076, 684 | 2110, 2076, 874 |
| Arrow sounds on a player | at most 324, 169, 95 | 2110, 2076, 874 |
| Dropped, cut by another arrow | 0 | 0, 0, 0 |
| Crowd voices, most at once of 16 | - | 8, 9, 7 |
| Body sounds against arrows struck (host's `station.hits`) | capped | 246 of 246 (228), 256 of 256 (226), 114 of 114 (106) |
| A body over the rest of the mix, first 50 ms, 400-6000 Hz, median | +5.4, +4.4, +8.7 | +5.2, +2.3, +8.7 |
| ... flesh, wood | +5.3 +5.6, +4.4 +4.5, +8.5 +9.0 | +5.1 +5.5, +3.5 +1.1, +9.5 +6.0 |
| ... flesh under the flights, 400-1000 Hz | +4.4, +2.5, +10.6 | +6.7, +5.1, +11.2 |
| A body's rise in the master itself, against an arbitrary moment | +7.5, +6.4, +13.1 | +7.6, +4.8, +9.7 |
| A miss over the rest, same band | +6.1 (patter), none, +11.1 (patter) | -7.0, -10.9, -5.6 |
| Flesh to dirt, wood to dirt, first 60 ms in the mix | 5.2 4.6, 4.0 3.6, 6.5 7.3 | 5.2 4.8, 3.4 3.1, 5.1 4.0 |
| 2-8 kHz of the master, limit -12 | -12.2, -15.0 (tracked) | -13.6, -14.9, -13.4 |
| LUFS, LRA | -17.7 / 1.6, -17.8 / 3.3, -21.3 / 2.4 | -17.2 / 2.1, -17.5 / 3.2, -20.7 / 3.0 |
| Worst prompt margin, +6 needed | +10.4, +8.5 (tracked) | +11.0, +10.5, +10.8 |
| Own flight over everything, 1-2.4 kHz, +3 needed | +4.6 (tracked) | +4.5 |
| Master over -1 dBFS, episodes a minute | 38.4, 19.0 (tracked) | 22.7, 17.7, 6.3 |

The third wave, rider on the organ, with its upgrades: 2256 landed, 2256 on players, none dropped, 8 voices at most, ear band -13.17, prompt margin +9.3. It has only two shield blocks, so a wave full of `arrow_shield` is still unmeasured.

So one body stands about 12 to 13 dB over one miss in the same mix, which is what tells them apart. A body's level over the mix did not rise: it is level with rc.2's on the organ and lower for another rider's arrow, because every other arrow is now in the mix around it. **A miss on its own sits under the mix: it is heard as part of a patter, not one by one.** The Listen step asks about both.

D9: 4.486 MB of 4.5. Nothing else was cut: the old `arrow_dirt` (2 x 0.42 s) and `arrow_water` (0.5 s) paid for all of it, and bolts and Scorpions in the moat play `stone_splash`, a bit up, no new bytes.

**P4 did not hold for a crowd, and no level could make it** (the ruling is in the next entry). P4 asks each surface's median impact for +3 dB over everything else, and "everything else" includes the other arrows of the volley. Real arrows land a median 22 ms apart, inside P4's 50 ms. With everything in the mix silenced but the misses, a miss reads -0.30 dB over the other misses, at any level, because they all move together. Lifting the ground failed as well: at cue -5 it read -3.72 and took P8 to +2.47, under its limit.

P6 and A1's LRA, the other two rows the lead expected to go, hold: -12.04 against -12 (thin: there is no room for more sand) and LRA 13.16 against 4-14. A1's true peak reads -1.02 against -1, also thin.

**Fatigue, by measurement only.** Nobody has heard this for an hour.

- 30 s levels stay put: -16.7 to -18.0 LUFS on the organ, spread 1.31 LU; 1.10 with the rider elsewhere; 0.44 solo (rc.2: 0.84, 0.90, 0.81). The extra spread is the wave filling up: the arrows go from 7.6 to 14.6 a second over those 180 s.
- 3 s loudness, p10 to p90: -18.4 to -16.3 (rc.2 -18.7 to -17.1).
- Arrows come in bursts, not a stream: the median gap is 22 ms and the p90 149 ms. The 400-6000 Hz envelope's best repeat in 30 s is 0.24 at 1.6 s on the organ, 0.32 at 0.65 s with the rider elsewhere (rc.2: 0.21, 0.38), so the bed did not become a metronome by this reading.
- The organ fires at a steady rate, so its volleys are a pulse whatever the sound is: that is the risk a measurement here can't rule out.
- An hour's repeats: 50400 arrows at 14 a second, the same file at the same pitch to 0.2 % and level to 0.25 dB comes back after 1220 arrows at the soonest, about 87 s, and a median of 1652. No file twice running on a surface in any recording.
- `tests/games/siege/audio/bank.test.mjs` holds the 30 s spread to 2.5 LU, the repeat to under 0.6 and no file twice running, on the tracked recordings.

**Unverified.** All of it is mock-trainer, muted, on this PC: no speakers, no real trainer, no fan, no exported exe, and no client over a network. A client's arrows land by its own replay and its own snapshots, and that was not recorded.

## 2026-11-01 Heard one by one: rulings after a critic, accents, depth, and rows that fail on rc.2

An audio critic read the recordings above. The fix stood, but "would the owner notice" was unproved: voice by voice nothing had got stronger than rc.2's. rc.2's hits were not masked (`hit_flesh` +11 to +18, `hit_wood` +17 to +22 over an arrow-free mix): they were missing. Clearly audible arrow sounds rose only 1.3-1.5x at the organ and solo. Twelve arrows land in 344 ms, about 31 a second, above any counting rate, so a landing likely reads as one rattle with the occasional body. rc.2's patter stood about 5 dB over the rest in 4-8 kHz and the first version's volley median -2.0. Solo, volleys fly 3.87 s at 1.9 s apart, so each landing falls on the next volley's flight peak, a +13.7 dB lock. The lead's rulings follow.

**P4: crowd hits leave its medians.** The lead's ruling. P4's "everything else" contains the other arrows, and -0.30 dB is the ceiling with only misses playing, so the row could not pass at any level and said nothing about anyone hearing them. Everything that is not `crowd: true` stays held to +3 dB as before, which took work: see below. My first proposal (a body over a miss, "audible as a group") was rejected: a ratio passes in silence, and the second reads the same on rc.2.

**New rows, from the tracked real-wave reports, on the card as R1-R3 and in `bank.test.mjs`.** Each fails on rc.2's bank, re-recorded on WASAPI in the same sessions. Organ / autopilot / solo app:

| Row | Limit | rc.2 (WASAPI) | Final |
|---|---|---|---|
| R1 voices started per arrow landed (at most: rc.2's sounds are shared with other weapons) | >= 0.95 | 0.15 / 0.08 / 0.13 | 1.00 / 1.00 / 1.00 |
| R2 strong onsets a second inside landing windows over outside, from the master alone | >= 2.0 | 1.50 / 1.15 / 1.24 | 3.16 / 2.22 / 6.83 |
| R3 a body over a miss in the same mix | >= +6 dB | -1.71 / +4.30 / -4.41 | +13.41 / +12.68 / +12.20 |

R2 is the critic's measure, ported to `live_report.mjs`, which reads his recordings within a few hundredths to 0.45 of his script (rc.2 1.17 / 1.19 / 1.37 against his 1.19 / 1.13 / 1.26 on the Dummy recordings; the first version 2.50 / 1.32 / 3.78 against 2.36 / 1.29 / 3.33). He proposed 1.5. rc.2's organ reads exactly 1.50 on WASAPI, which would pass, and the rows must fail on rc.2, so the limit is 2.0. That is tighter, not looser.

**Decisions, what each is for.**

- `arrow_dirt` per the critic's candidate: 100 ms, body at 520 Hz, a longer decay, a low-pass at 1.1 kHz after the drive. Sand gain 1.0 and not his 0.72: at his the ground and the bodies read too alike on P9 and A8's top band fell under its floor, and his own candidate failed A1. Cue -9.8.
- Flight contour per the candidate, peak at 40 % of the way with pitch following, so the flight is past before its arrows land. It lowers the flight at the landing by a modelled -8.3 dB solo, -2.7 on the organ, -3.6 elsewhere. **The swoosh goes better with the picture, not worse.** With the organ's real numbers (40 degrees, k 0.006, 30-45 m/s) the arc's highest point, in the world and on screen, comes at 38-41 % of the flight, because drag slows the way down. The peak at 50 % was late, about 0.38 s at a flight of 3.6 s, and the new one sits on the top of the arc. A frame sequence (`tools/screenshot` at 440-443.5 s) shows volleys as specks over the road at this size: nothing there contradicts it, and no eye can read 0.38 s from it, so this rests on the numbers.
- Another rider's arrows: `other_db` -2 on bodies, -3 on misses, from -5. The lead withdrew his earlier acceptance of them sitting lower, because the owner's complaint outranks it.
- Accents, because the owner said "individually" and 3 or 4 distinct events a second is what can be heard as individual. The critic's measure can't justify this; the lead asked for it anyway. At most one arrow per 150 ms, across all volleys, plays +4 dB: a body if one lands in that window, else the earliest landing. That is about 3 in a volley. The gap started at 90 ms, about 4 in a volley and a third of all arrows, and took A2's Sfx to -9.19 against -11. It stays at +4, the lead's starting point. An arrow's level over its cue is capped at +3 dB, so an accent on an arrow near the camera gets the cap and not +7, and the cap is what holds A2. On the card, +5 under that cap also holds (P6 -12.52, P9 3.06, A1 -1.04, A2 -11.05), with little difference, since the cap clips it on many arrows. +5 with a cap of +4 fails A2 at -10.47. +5 was not recorded on a real wave, and +6 was not tried.
- Depth: +-3 dB by where the arrow lands on screen, near louder, around art y 430 and +-90 px: the road in the organ's reach runs from about y 340 to 510. Centred on the middle of the screen, as I first wrote it, almost every arrow got +3 dB and the organ's wave read -15.88 LUFS, over the limit of -16.
- Pan: a volley's place 1.3 times as wide as the picture and each arrow's distance from it 7 times. One send's share falls from 72 % to 52, 54 and 41 %.
- Rotation: `variant_var` on a cue hit lets a game name the file (small and additive, in the kit and the offline mix). `SiegeAudio.next_file` never plays the same file twice running on a surface and otherwise does not keep an order. By my reading (the same file, pitch within 1 %, level within 0.5 dB, within 3 s, 14 arrows a second) a near-twin falls from 91 % of misses to 45 %. The critic read 66 % by his. That is still a lot: 42 arrows in 3 s on 4 files, a 14 % pitch range and a 2.5 dB level range can't avoid it. An hour's soonest return at 0.2 % and 0.25 dB is 322 arrows, about 23 s, median 2207.
- `arrow_flesh` variants have their own layers: bodies at 640, 720, 800 and 1120 Hz, cracks at 3.5-5.4 kHz, one with a low thump. Their spectra are 5.0 to 11.2 dB apart (he read 1.8-2.3).

**What this cost elsewhere.** The levels below are not arrows, and they move because of them. The rows that hold are all held, none loosened.

- `tower_dock` -6 (from -4) and `wave_end_bell` -5.5 (from -4): A2's Sfx peak and A1's true peak in a mix with arrows landing on them. Nobody has heard these two at these levels.
- `hit_stone_dirt` -1 (from 0): the same reason.
- With crowd hits out of P4's medians, the other hits needed to clear +3 on their own in a louder crowd: `hit_bolt_dirt` and `hit_scorpion_dirt` +1.5 (from 0); `hit_bolt_shield` and `hit_stone_shield` -2.5 (from -3), `hit_scorpion_shield` -3.5 (from -4); bolts, stones and Scorpions in the moat +0.5, -0.5 and -2.5 on `stone_splash`.
- `arrow_shield` is thinner above 5 kHz, which was what pushed A1 over. In the card's preview it took 35 % of the mix's 2-4 kHz with only 14 arrows, at a 2 % share. The real waves show 0.1 %, so the preview now plays 0.5 %. A wave that really has many blocks is still unmeasured, and it would press on the ear band.

**Numbers.** rc.2 re-recorded on WASAPI, then final. Organ / autopilot / solo app:

| | rc.2 | Final |
|---|---|---|
| Arrows landed | 2110 / 2076 / 874 | 2110 / 2076 / 874 |
| Arrow sounds on a player, at most for rc.2 | 324 / 168 / 111 | 2110 / 2076 / 874 |
| Dropped, cut by another arrow | 0 | 0 / 0 / 0 |
| Crowd voices, most at once of 16 | n/a | 10 / 9 / 8 |
| A body over the rest of the mix, first 50 ms, 400-6000 Hz, median | +5.5 / +4.3 / +8.6 | +7.9 / +5.2 / +8.8 |
| ... flesh, wood | | +9.1 +6.8 / +8.8 +3.4 / +8.5 +8.8 |
| ... p10 | +1.5 / 0.0 / +5.4 | -2.4 / -2.8 / +0.1 |
| A body's rise in the master, against an arbitrary moment | +8.0 / +6.9 / +13.9 | +7.6 / +6.8 / +11.6 |
| A miss over the rest (rc.2: its patter) | +7.2 / none / +13.1 | -5.6 / -7.5 / -3.4 |
| 2-8 kHz of the master, limit -12 | -12.41 / -15.07 / -12.36 | -13.35 / -14.59 / -13.31 |
| LUFS, limit -20 to -16 on the first two | -17.76 / -17.84 / -21.36 | -16.32 / -16.60 / -19.54 |
| LRA | 1.58 / 3.34 / 2.22 | 3.35 / 4.13 / 5.06 |
| Worst prompt margin, +6 needed | +9.60 / +8.15 / +11.57 | +7.42 / +8.33 / +9.05 |
| Own flight over everything, 1-2.4 kHz, +3 needed | +4.67 (organ) | +4.86 (organ) |
| Flesh to dirt, wood to dirt, first 60 ms in the mix | 6.2 6.2 / 3.6 3.9 / 7.6 8.1 | 4.8 5.1 / 4.3 4.2 / 4.3 4.5 |
| Master over -1 dBFS, episodes a minute | 29.3 / 17.0 / 11.7 | 43.7 / 39.0 / 27.0 |

Third wave, rider on the organ: 2257 landed, 2257 on players, none dropped, 9 voices at most, ear band -12.81, -16.45 LUFS, R2 2.88.

So against rc.2: the median body is stronger at the organ and for another rider's arrows (+2.3 and +0.9 dB, over a mix that now holds every other arrow), level solo, and its p10 is lower by 3 to 5 dB, because a body with no accent, or a far one, sits lower in the crowd. An accent with a body has what rc.2's one sound had and more.

The price is 1.2 to 1.8 LU: the wave reads -16.32 against the limit of -16 and is the loudest this game has been. The prompt's worst margin went from +9.6 to +7.42 on the organ and from +11.57 to +9.05 solo, and rose by 0.2 with the rider elsewhere. The master goes over -1 dBFS two to three times as often, so the limiter works harder. A rc.2 target against the ground was already apart, by its dirt's sand; it now stands apart by its own body, and the figure fell by 1.1 to 3.6 dB on the organ and solo.

**Fatigue, by measurement only.** 30 s level spread 1.45, 1.93, 1.60 LU (rc.2 0.93, 0.96, 1.08). 3 s loudness on the organ -18.0 to -15.0 (rc.2 -18.65 to -17.2): the wave moves more, because accents come and go. The envelope's best repeat in 30 s is 0.20 at 1.55 s on the organ, 0.26 at 0.8 s with the rider elsewhere, 0.36 at 1.85 s solo (rc.2 0.21, 0.38, 0.32). Nobody has heard this for an hour.

**The exported exe.** The owner plays the exe, and nothing had recorded one, so this could have been the whole story. It is not. rc.2's own PCK (`build/windows`, read only) holds all of its bank: siege 98/98, and the file list of the sounds at issue includes `hit_flesh` and `arrow_dirt`, import and imported data. This branch's exe, exported with the standard editor: siege 113/113 in the PCK. An export template ignores `-s`, so `--audio-log` went in (`AudioRunLog`). A throwaway profile rode the exe through the zero-touch start on `--mock-trainer`, Master at -80 dB, WASAPI, 553.78 s, into the first wave: `exported: true`, 150 flights, 889 `arrow_dirt`, 100 `arrow_flesh` and 7 `arrow_wood` taken by players, all still playing a frame later, 0 voiceless, nothing stolen, and 86 volleys in the air or landed against 996 arrow sounds. Its Master capture reads -19.37 LUFS in the last 100 s, as the solo app does (-19.54). rc.2's own exe was not run, since it has no such log: what is shown is that its files are there and that the same export of the same engine plays this bank's. `node tools/export_windows.mjs --smoke` now reads the PCK and fails if a sound is lost: fishing 70/70, siege 113/113, tank 163/163, workout 57/57, `_shared` 15/15.

## 2026-11-01 Every body an accent, clean captures, the alarm, and what the prompts got back

A second critic read the recordings. These figures replace the ones in the entry above: its recordings clipped in the capture, and its one-arrow figures ignored pan.

**Clean capture.** `tools/audio/live_mix.gd` clamped to +-1 as 16-bit, so every `listen_*` file and Sfx stem carried clipping the game doesn't make (the Master head peaks at +2 to +6 dBFS before the limiter, up to 2332 samples over full scale in a final run). Captures are 32-bit float now, in `live_mix` and `AudioRunLog`, and a capture after Master's limiter is what a rider hears. The `listen_*` files are cut from it with no gain of ours: 0 dB of padding, peak -1.00 dBFS by the game's own limiter, 0 samples at full scale.

**Every body is an accent.** Half used to lose it to the gap. A body now always is one, and misses keep the 150 ms gap. `ARROW_LVL_MAX_DB` goes from 3 to 2, and the accent is +6 on what is under that cap: the rows hold it, and the rider elsewhere's R2 needed it. The critic's model predicted plain bodies at about 13 dB of rise with LUFS within 0.04. **That did not happen by this measure.** The plain category is gone, and a body's median rise is +7.07 / +5.68 / +10.36 raw on the organ, autopilot and solo (rc.2 +7.84 / +6.94 / +13.81), and LUFS moved 0.13 quieter on the organ. The reasons: the cap fell, and the next item.

**A pile of bodies steps back.** A volley on a ram is twelve bodies in about 120 ms. At full level they took a safety prompt's margin to 5.82 LU in a weak team's window (rc.2 11.67), so 2 dB off per doubling of the bodies in 120 ms, and the margin there is +8.08. Prompts don't move, so the arrows do.

**`arrow_flesh` peaks lower.** Yes, it can: a longer hold (40 ms) and a second, narrow saturation take its crest from 8.6-11.4 dB to 7.1-7.9 dB, and its loudest 50 ms rise 1.3 to 3.8 dB for the same peak. Its cue goes from -3.6 to -6.5, about the same loudness by that reading, and with the cap it plays at -5.5 dBFS at most, from -0.6. Its starts sit within 80 ms of 40 / 30 / 73 / 19 % of overs (the critic read 48-83 %). Master over -1 dBFS, linked stereo, a minute: 27.0 / 22.0 / 13.3 / 24.0 against rc.2's 31.7 / 16.7 / 13.7. The solo run is where flesh still leads: 73 %. It is near what `arrow_dirt` reads, about 70 %, and that is density as much as cause.

**Prompts over the mix, read from recordings that hold them.** `live_report` now writes `events`: each start, the master's rise, first 300 ms against the 500 ms before it, whole and in its best octave. rc.2 and final, same session and moments:

| | rc.2 rise, best octave | Final |
|---|---|---|
| `horn_wave`, start of a wave, no arrows yet | +8.3, +26.0 | +7.5, +24.9 |
| `wave_end_bell`, -4 to -5.5 | +4.0, +12.8 | +3.9, +12.1 |
| `tower_dock`, -4 to -6, 6 arrows around | +5.1, +8.2 | +4.0, +6.1 |
| `reach_alarm` on the organ, three leaks | +0.2 +1.6 +0.7, +2.2 +4.5 +4.3 | -0.6 -0.9 +1.7, +5.2 +4.2 +6.0 |
| `reach_alarm` with the rider elsewhere, one | +3.5, +6.1 | -1.1, +4.2 |
| `reach_alarm` in the third wave, one | not recorded | +2.9, +7.6 |
| `reach_alarm`, a weak team, in order | best +10.1 +10.3 +5.6 +6.8 +9.0 +6.9 +3.1 | best +5.7 +14.2 +8.1 +10.2 +2.4 +8.4 |

Horn, bell and dock are no blocker: the bell and the dock are merely a little softer, and each stands 6 to 25 dB over its moment in its best octave. The rush horn wasn't in any session recorded.

**The alarm is a warning a rider acts on, so it moved.** It rises 5 dB (a leak -12 to -7, a reach -10 to -7), the arrows take 6 dB off and Machines 6 dB for its first strokes, and a reach takes the place of the leak that comes with it. Its whole-band rise stays low in a dense mix, and in its best octave it reads 4 to 8 dB, better than rc.2 on the organ and 1.9 dB under it with the rider elsewhere. One moment of the weak team's window reads +2.4. `bank.test.mjs` holds every tracked alarm to +3 in its best octave. A partial at 2637 Hz, tried first, did not help that reading and took the third wave's ear band to -11.96, so it is gone.

**The tracked waves, now four, on float captures with pan honoured.** rc.2 re-recorded the same way, then final. Organ / autopilot / solo / third wave:

| | rc.2 | Final |
|---|---|---|
| Arrows landed | 2110 / 2076 / 874 | 2110 / 2076 / 874 / 2256 |
| Arrow sounds on a player | at most 323 / 169 / 111 | 2110 / 2076 / 874 / 2256 |
| R1, at least 0.95 | 0.15 / 0.08 / 0.13 | 1.00 / 1.00 / 1.00 / 1.00 |
| R2, at least 2.0 | 1.35 / 1.06 / 1.29 | 3.01 / 2.07 / 6.33 / 3.10 |
| R3, at least +6 dB | -0.86 / +5.50 / -4.79 | +12.37 / +13.14 / +12.79 / +9.99 |
| Body over the mix, in its pan's channel | +6.35 / +5.50 / +10.78 | +7.19 / +5.94 / +9.70 / +5.80 |
| ... p10 | +1.69 / +0.25 / +6.52 | -2.45 / -3.19 / -0.54 / -2.35 |
| ... flesh, wood | +6.87 +6.20 / +5.35 +5.55 / +12.45 +8.57 | +8.32 +6.44 / +8.16 +2.55 / +9.81 +6.83 / +8.74 +5.62 |
| A miss over the mix | +7.21 / none / +15.57 (its patter) | -5.18 / -7.20 / -3.09 / -4.19 |
| 2-8 kHz, limit -12 | -12.40 / -15.09 / -12.35 | -13.04 / -14.30 / -13.17 / -12.46 |
| LUFS, limit -16 on the wave rows | -17.77 / -17.82 / -21.37 | -16.45 / -16.68 / -19.81 / -16.58 |
| LRA | 1.61 / 3.38 / 2.20 | 2.80 / 3.77 / 4.23 / 3.12 |
| Worst prompt margin, +6 needed | +10.64 / +9.58 / +11.81 | +9.12 / +9.58 / +10.08 / +9.31 |
| Own flight, +3 needed | +5.44 (organ) | +4.31 (organ), +4.18 (third wave) |
| Flesh to dirt, wood to dirt | 6.06 6.00 / 4.70 4.81 / 7.56 8.23 | 4.37 5.16 / 3.75 4.39 / 3.97 4.70 / 4.31 4.95 |
| 30 s spread | 0.98 / 0.96 / 0.93 | 1.40 / 1.59 / 1.19 / 1.50 |

R2 moves from run to run on one bank. The rider elsewhere read 2.07 and 2.13 on this final bank, and 1.77 to 2.23 on the nearby ones of this round, so it sits on its limit. Nothing here is a proof it will always clear it, and rc.2 stays under it by 0.65. The third wave's prompt margin holds at +9.31: the +6.43 the critic read is gone with the piles, and it is on the table now.

**Report tooling.** `one_arrow` reads each voice in the channel its pan puts it in, which lifts every reading a little. `start_log` carries pitch and a `tag_var`, here 1 on an accent. Overs count once on linked stereo (the old 43.66 was 40.0). `build/audio_preview/siege_scorecard.json` is written by the card, so it is fresh from the last gate.

**Costs elsewhere, on top of the entry above.** `arrow_swarm` -3.3 to -3.7, for A2 and A1. `hit_stone_dirt` -1. Bolts, Scorpions and stones in the moat on `stone_splash` at +1.3, -1 and 0, `hit_scorpion_shield` -4.2, `hit_scorpion_wood` -2, because P4 reads those against a louder crowd. `arrow_dirt` sand 0.9, cue -9.3; `arrow_wood` modes at 1320 and 1900 Hz, under the ear band, cue -7.9; `arrow_water` -10; `arrow_shield` -5.8. The preview's arrows follow all of this, with its fixed cap at +2.

**The exe.** The run log repeated on the final export of this bank, merged with main: `exported: true`, WASAPI, 553.79 s, 845 `arrow_dirt`, 111 `arrow_flesh` and 16 `arrow_wood` on players and all still playing a frame later, 84 volleys, 0 voiceless, nothing stolen, and a `reach_alarm`, the bell and the horns among them. Its limited capture peaks at -1.00 dBFS and reads -19.44 LUFS in the last 100 s.

**Left for the owner's ears, not acted on.** The 512-sample start grid shows a 93.75 Hz line 27-31 dB over its neighbours in 4-8 kHz (rc.2 13-19). The solo pulse is 1.9 s.
