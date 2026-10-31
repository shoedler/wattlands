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
