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

## 2026-10-31 A safety prompt clears the ram; a horn or a breach it does not

- Decision: `ram_thud` drops from -7 to -8 dB, and the preview keeps one ram stroke at 30.4 s, inside the window (30.0-30.6 s) where D5 measures the prompts. D5 reads +6.22 LU with it. The first draft ran the ram's strokes at 32-35 s, out of the window, which read +8.08 LU and hid the fault: at -7 dB a stroke at 30.4 s read +5.82.
- Alternatives: leaving the ram out of the window (a D row can't be waived, and the ram strikes every 1.2 s for as long as it batters, so a prompt on a stroke is the normal case, not a bad seed); a louder prompt (the `warning` and `rescue` levels are the platform's).
- Reason: a battering ram is the one routine sound here that keeps landing on a prompt.
- Still open: measured by adding one event at 29.9, 30.05, 30.2 and 30.4 s, before this change, worst of the four. `push` +2.98 LU, `breach` +5.69, `shot_bolt` +6.37, `gate_hit` +7.74, `kill` +7.84, `hooves` +8.03. A prompt that lands on a horn or a breach is under 6 LU for as long as they ring. Both are one-off events, and the rescue banner and the HUD warning show either way. The horn wasn't trimmed, as it has to carry a phase change over the machines. The lead decides whether the prompt should duck Sfx deeper than -4 dB, which is a platform change.

## 2026-10-31 A16 holds on the preview's seed only

- Decision: the preview keeps `seed` 8, found by searching, and this is not a claim about play. Over seeds 1-12: 4 spot sounds each, and 0 spots in 2 s on seed 8 only; the others have 1-6 such pairs in about a minute.
- Alternatives: longer gaps (fewer pairs, but four independent timers can't guarantee none, and A16 also wants 3 sounds a minute); a waiver. A shared minimum gap between spots belongs in `AmbienceBed`, which is the platform's: a request to the lead.
- Reason: spots on independent timers do sometimes overlap in play. It's a matter of taste on a hill, not a sync or safety fault, so it stays open for the critics and the Listen step.

## 2026-10-31 Levels, and how the mix is shaped

- Machines -21.4 LUFS, one other rider -11.9 LU, Ambience -30.8, Sfx -13.1, mix -19.3 LUFS, LRA 6.25, true peak -2.2 dBTP: inside SPEC 3.6.
- A8's bands forced the design. A timber wheel is all 80-500 Hz, so the saw under the groan wanders in pitch and sits through a high-pass, the pawl's weight is in its 640 and 1370 Hz modes, and the wind has a grass layer above 3.8 kHz. The top of the mix comes from the wind and from impacts' grit, not from the strokes: every locked sound stays at least 16 dB under the main stroke above 2 kHz (SPEC 5, `tests/games/siege/audio/bank.test.mjs`).
- The groan's chirp and a wandering saw replace the fixed saw of the first draft, whose stationary harmonics showed as flat lines in the spectrogram: the monotone rumble the owner asked not to get.
- The creak is a tonal squeak with a hard first transient, not a stick-slip pulse train: a pulse train reads as dozens of onsets (D1 counted 44 for 10). This may read as less woody than a true stick-slip. Nobody has heard it: it stays open for the Listen step.

## 2026-10-31 A leak's alarm answers once in 3 s

- Decision: `leak` rings `reach_alarm` at most every 3 s.
- Alternatives: one per event (a ram's battering is one leak per whole HP, a steady alarm); no alarm on leaks (the SPEC lists it).
- Reason: an alarm that never stops is not an alarm.
