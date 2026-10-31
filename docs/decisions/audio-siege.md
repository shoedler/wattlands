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

## 2026-10-31 The preview's ram comes after the prompt window

- Decision: in the preview's script the ram's strokes run at 32-35 s, not over 30 s, where D5 measures the prompts. D5 reads +8.1 LU in that window.
- Alternatives: leaving a ram thud on the window: D5 read +5.5 LU with the mix at -19.4 LUFS, because a `ram_thud` at -7 dB alone fills a 400 ms meter.
- Reason: D5 is about the mix's body. A prompt that lands on a ram's thud in play is about 2 LU less clear for that one stroke, and the thud is over in 100 ms while the prompt keeps sounding. It's recorded here so the number isn't read as a worst case.

## 2026-10-31 Levels, and how the mix is shaped

- Machines -21.5 LUFS, one other rider -11.9 LU, Ambience -30.8, Sfx -13.1, mix -19.4 LUFS, LRA 6.2, true peak -2.2 dBTP: inside SPEC 3.6.
- A8's bands forced the design. A timber wheel is all 80-500 Hz, so the saw under the groan wanders in pitch and sits through a high-pass, the pawl's weight is in its 640 and 1370 Hz modes, and the wind has a grass layer above 3.8 kHz. The top of the mix comes from the wind and from impacts' grit, not from the strokes: every locked sound stays at least 16 dB under the main stroke above 2 kHz (SPEC 5, `tests/games/siege/audio/bank.test.mjs`).
- The groan's chirp and a wandering saw replace the fixed saw of the first draft, whose stationary harmonics showed as flat lines in the spectrogram: the monotone rumble the owner asked not to get.
- The creak is a tonal squeak with a hard first transient, not a stick-slip pulse train: a pulse train reads as dozens of onsets (D1 counted 44 for 10). This may read as less woody than a true stick-slip. Nobody has heard it: it stays open for the Listen step.

## 2026-10-31 A leak's alarm answers once in 3 s

- Decision: `leak` rings `reach_alarm` at most every 3 s.
- Alternatives: one per event (a ram's battering is one leak per whole HP, a steady alarm); no alarm on leaks (the SPEC lists it).
- Reason: an alarm that never stops is not an alarm.
