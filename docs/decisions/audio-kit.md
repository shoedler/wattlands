# Decisions: audio kit

## 2026-10-31: CrankClock lives in addons/wattlands/audio/, verbatim from the run's errata

- **Decision:** `CrankClock` is `addons/wattlands/audio/crank_clock.gd`. No `drive`, `fraction` or `MAX_DT_S`.
- **Alternatives:** `addons/wattlands/sim/` from a separate contract commit, which was dropped.
- **Reason:** one class, one place. A second `class_name CrankClock` fails parse.

## 2026-10-31: a bank never plays on Master, and no duck touches Master or UI

- **Decision:** `AudioBank.validate` rejects a bank's bus or duck on Master and a duck on UI; `AudioBuses.duck` refuses both with a warning. A game that registers its own `warning` or `rescue` in `WlSfx` still plays on Master.
- **Alternatives:** trusting the bank's author, as the schema's plain "unknown bus" rule would.
- **Reason:** BRIEF 4.6: no sub-slider or duck can hide a safety prompt. The rule is enforced where the data enters.

## 2026-10-31: validate accepts a bus that exists on the server

- **Decision:** a bank's bus is known if it is one of `AudioBuses.ALL` or exists on `AudioServer`.
- **Alternatives:** the bench puts a capture effect on the real Machines bus.
- **Reason:** the jitter bench machine sits on its own temporary, muted bus, so the bench never sounds on the rider's speakers and never touches a real bus.

## 2026-10-31: `variant` from CadenceVoice and AmbienceBed is a running count

- **Decision:** the pure classes count firings per sound; `AudioBank.stream` wraps the count by the sound's `variants`.
- **Alternatives:** handing the variant counts to the pure classes, whose `_init` signature is fixed by the spec.
- **Reason:** the pure classes stay free of the bank, and round-robin needs no RNG.

## 2026-10-31: additions to the kit's spec, all additive

- `CadenceVoice`: `gated` (S2 counts fired + dropped + gated) and `planned_to()`.
- `LayeredLoop`: `close(dt)`, `layer(i)`, `all_off()`. A machine's loops close at `rpm <= STOP_RPM` whatever its layers say (S4), also without `min_rpm`.
- `AmbienceBed.trim_db`: the kit's crossfade (old bed down at 40 dB/s, new one up from -30 dB) and pause drop.
- `GameAudioKit`: `preroll_on` (the bench's baseline), `voiceless`, test accessors. A stroke that may not steal anything is dropped and counted.
- `AudioBank`: `duplicate_keys(text)` reads the raw JSON, because `JSON.parse` keeps only the last of a repeated key. A locked sound must be PCM (its seek must be exact).
- A cue's `duck` runs only for `lead` true: someone else's shot does not duck my machine.

## 2026-10-31: the jitter bench misses with Godot's delta smoothing, and passes without it

Superseded: `docs/decisions/audio-sync.md` replaces the call below to report the miss and keep the strokes on `revs`.

Measured on WASAPI, 48 kHz, 59.94 Hz display, with other Godot runs on the machine; residual p99 / stddev in ms, limits 12 / 4, thresholds unchanged. All slopes hold (at most 0.056 %, limit 0.1 %), all onsets found, no stroke late or dropped.

| rpm | engine delta, smoothing on (the exit code) | real clock | engine delta, smoothing off | no pre-roll seek |
|---|---|---|---|---|
| 60 | 9.05 / 3.83 | 5.85 / 3.15 | 5.69 / 2.99 | 17.15 / 6.93 |
| 90 | 12.11 / 5.30 | 5.61 / 3.08 | 5.15 / 3.05 | 19.78 / 7.89 |
| 110 | 14.18 / 6.88 | 5.70 / 3.40 | 5.52 / 3.16 | 18.48 / 7.86 |
| 140 | 12.07 / 5.34 | 5.73 / 3.08 | 6.06 / 3.20 | 19.61 / 7.77 |

- **Cause:** at 59.94 Hz Godot's delta smoothing hands out 16.667 ms and carries the rest, then pays it back as a whole vsync. `revs` integrates that delta, so it has a sawtooth of up to one vsync against real time, and a run looks good or bad according to where the jumps fall in it (a 60 rpm run measured 6.27 / 3.18 once and 18.75 / 6.71 once). What remains without it, stddev about 3.1, is a uniform spread over one 512-frame mix step (10.67 ms, stddev 3.08): the spec's own bound.
- **Decision:** the kit keeps the spec's strategy, horizon and formula. The miss is reported with these numbers; the thresholds stay. S1 and S3 hold against `revs`: the stroke and the picture share the sawtooth.
- **Alternatives:** `application/run/delta_smoothing=false` in `project.godot` passes every rpm, but it is the lead's file and changes every game's frame delta, so it is the lead's call. Feeding the bench only the real clock would have passed and hidden what a game actually does, so the "engine" run decides the exit code and the "real" run is a diagnosis.

## 2026-10-31: contract critic's fixes

- **A safety prompt is never stolen.** `WlSfx`'s round-robin skips a player on Master (only `warning` and `rescue` play there). If all eight hold a prompt, a new prompt gets a player past the cap and an effect gets none: a prompt always sounds, and the pool grows only in that case. Alternatives: a reserved player (one prompt only, and it would shrink the pool for everyone).
- **A pause closes `loops` entries** even while the adapter still calls `set_loop`. Spec 2.5 lists only machine loops, but views keep running under a pause, so its literal text would leave a drag scream at full level. Alternative: gating in each adapter, which would need `_paused` public or its own bus connection.
- **A cue duck without times takes spec 5's 10 ms and 350 ms** (`DUCK_ATTACK_S`, `DUCK_RELEASE_S`), the preview's defaults. Alternative: both validators requiring the keys, which touches the dsp's file for no gain.
- **`gap_s` stays fixed and `when` stays one param; no `gap_by`.** `hull_slap`'s gap by speed is one spot per speed band, each with its own `gap_s` and a `when` on speed; `reel_ratchet` and `freewheel_tick` take one composite param from the adapter. Alternatives: an optional `gap_by` or a list of gates, which adds schema and a second implementation in `tools/audio/lib/pattern.mjs` that the preview must match, for sounds that bands already express. The test is `test_bed_gap_by_speed_is_one_spot_per_band`; the words are in `docs/GAME_SDK.md` section 18, since `docs/AUDIO_PIPELINE.md` is the dsp builder's.
- **`AudioBank.validate` checks shapes before it uses them:** blocks, lists, curves, `when`, and the numbers and flags the kit reads with a cast. A wrong shape is an error naming its key path, not a run-time type error. The loop budget runs only on a doc with no errors, since it reads the same blocks.
