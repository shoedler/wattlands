# Audio pipeline

All game audio is rendered from recipes in this repo by `tools/audio`, a zero-dependency Node DSP. No samples, no downloads, no art service. One recipe file per game, `assets/<id>/audio/audio.json`, holds both the recipes and the runtime data (patterns, loops, beds, cues), so the preview and the game read the same numbers. The platform's UI set is `assets/_shared/audio/`.

```
node tools/audio/generate.mjs --game=<id>|all [--only=<ids>] [--check]
node tools/audio/preview.mjs  --game=<id>|all [--rpm=60,90,110] [--no-mp3]
node tools/audio/scorecard.mjs --game=<id>|all [--json]
```

`_shared` counts as a game id; `all` means `_shared` plus every `assets/<id>/audio/audio.json`. `--bank=<path>` takes a bank file instead (the import proof; the fixture). After generating new files run `tools/godot.sh --headless --path . --import` and commit `.wav`, `.wav.import` and `audio_manifest.json`.

Commit `.wav` at most twice per branch (end of the first critic round, and final). Recipes commit freely; output is deterministic, so an unchanged sound makes no diff.

## The family

Enforced by `tools/audio/test/family.test.mjs` and bank validation, not by taste:

- 22050 Hz; 11025 Hz only for low bed layers.
- Band 40-9000 Hz (11025 Hz: 40-5000 Hz), 24 dB/oct each side. A sound may narrow it, never widen it. Energy above 9.8 kHz stays at -32 dB or under.
- 16-bit container, 12 significant bits, low nibble zero, no dither. `crush` may lower the bits, never raise them.
- Machines and events are mono. Only beds and spots are stereo.
- Tonal UI and fanfares sit on C major pentatonic.
- Three shared rooms: `iron` (18 and 31 ms combs), `wood` (11 ms damped), `open` (an HF tilt).

## A recipe

```jsonc
"diesel_fire_a": {
  "dur": 0.22,            // seconds, pre-roll not counted
  "rate": 22050, "ch": 1, // required: AudioBank validates them at load
  "seed": 101,            // default: a hash of the id, so reordering a bank changes nothing
  "variants": 3,          // files diesel_fire_a_1..3.wav; a reference round-robins them
  "per_variant": [{"pitch": 1.0}, {"pitch": 0.96}, {"pitch": 1.05}], // any field, one object per variant
  "locked": true,         // 80 ms of silence prepended; required for machine events
  "loop": false,          // seamless wrap over xfade_s (default min(dur/4, 0.5))
  "compress": "pcm",      // pcm | qoa. Default: pcm for locked, _shared and loops <= 2 s, else qoa
  "norm": {"peak": -6.0}, // or {"lufs": -20}. Default: locked -6 peak, loops -20 LUFS, else -3 peak
  "band": [40, 9000], "crush": 12, "room": "iron",
  "pitch": 1.0,           // scales every frequency of the sound
  "pan": 0.0, "width": 1, // ch 2: constant-power pan; width 1 renders two independent sides, 0 one
  "layers": [
    {"src": "noise", "color": "brown", "gain": 0.9, "at": 0.0, "dur": 0.2,
     "env": {"a": 0.001, "d": 0.09, "curve": "exp"},
     "fx": [{"lp": {"f": 420, "q": 0.9}}, {"drive": 2.5}]}
  ]
}
```

A layer runs: source, `env`, `fx` in order, `gain`, placed at `at`. With no `dur` it runs to the end of the sound.

| `src` | Fields | For |
|---|---|---|
| `sine` `tri` `saw` `square` `pulse` | `f`, `glide` lin or exp, `glide_s`, `duty`, `phase` | polyBLEP on the steps |
| `noise` | `color` white, pink or brown | seeded `seed + variant*1009 + layer*31 + channel*7919` |
| `modal` | `f[]` `t60[]` `g[]` | metal, wood |
| `pluck` | `f` `decay` (t60) `bright` 0..1 | Karplus-Strong: ballista, line snap |
| `chirp` | `points` `[[t, hz], ...]`, `vibrato {hz, cents}`, `wave`, `duty` | gull, whistle, owl |
| `grains` | `rate_hz`, `f [lo, hi]`, `dur_s [a, b]`, `g [a, b]`, `kind` sine or noise, `sweep` | crackle, bubbling, patter |
| `fm` | `f` `ratio` `index` `index_decay` (time constant, s) | bell, horn |

`f` on an oscillator or a filter is a number, `[start, end]`, or `[[t, hz], ...]`.

`env`: `{a, h, d, s, r, curve}` or `{points: [[t, g], ...]}`. Attack linear, decay `exp` (exactly at `s` when `d` ends) or `lin`, release linear to the end of the layer. With `d` and no `s` it ends at 0; with neither it holds 1.

`fx`: `lp` `hp` `bp` `notch` `peak` (RBJ; `f`, `q`, `db`), `drive` (tanh), `crush {bits, hold}`, `comb {ms, fb, damp}`, `trem {hz, depth}`, `gain_env` (an `env`).

Final chain of every sound, in order: sum, room, band, loop wrap or a 2 ms tail fade, norm, family crush, pre-roll, 16-bit.

The rest of the bank (`mix`, `machines`, `loops`, `beds`, `cues`) is the runtime contract: `docs/GAME_SDK.md`, and `tools/audio/test/fixtures/engine_bank.json` is a complete worked example. A new primitive or a change in `tools/audio/lib/` is a request to the lead, not a game's edit.

## Files

`generate` writes beside the bank: `<sound>.wav` or `<sound>_<n>.wav`, each with a `.wav.import`, and `audio_manifest.json`, keyed by file stem:

```json
"diesel_fire_a_2": {"sound": "diesel_fire_a", "variant": 1, "rate": 22050, "ch": 1, "frames": 6615, "loop_frames": 0, "preroll": 1764,
                    "bytes": 13274, "sha256": "...", "peak_db": -6, "lufs": -21.3, "loop": false, "locked": true, "compress": "pcm"}
```

A sidecar is created if absent; on an existing one only the `[params]` lines change, so Godot's `uid`, `path` and `dest_files` stay. `--check` renders in memory and compares with disk, writing nothing. It allows one 12-bit step per sample (a `Math.*` difference between Node versions can flip a rounding), and fails on anything else, a stray or missing file, a changed import param, or a manifest that is not the file on disk.

**Loops carry a guard frame.** A loop of N frames is written with N + 1, the last a copy of frame 0, and `edit/loop_end=-1`. Godot reads -1 as `frames - 1`, so the period is exactly N, and its resampler's read one frame past the loop end lands on frame 0, not on the zero padding after the data. The file also starts at the quietest sample step of its cycle, so the seam is no louder than any other pair of samples. `test_audio_assets.gd` proves this through Godot's importer.

**WAV in git, imported by Godot, never OGG.** Vorbis seeks poorly on the audio thread and smears loop seams. Machine strokes stay PCM: their sync depends on an exact seek into the pre-roll. Long files go QOA (3.2 bits per sample) in the export.

Repo WAV caps, `tools/audio/test/budget.test.mjs`: tank 7.0, fishing 4.5, siege 4.5, workout 4.0, shared 0.3 MB; total 20.5 MB. A new game needs its own cap in `lib/score.mjs`.

## Preview and scorecard

`preview` runs the kit's logic (`lib/pattern.mjs`, a JS port held to the GDScript by the parity table in `tests/audio/test_audio_parity.gd` and `test/pattern.test.mjs`) at 60 frames a second, and mixes at 44100 Hz. The bank's `preview` block drives it:

```jsonc
"preview": {
  "lead": "diesel",
  "others": [{"machine": "dynamo", "rpm_scale": 0.97, "params": {"power": 0.9}},
             {"machine": "track", "lead": true, "rpm_by": {"param": "speed", "ratio": 0.04}}],
  "bed": "night_forest", "bed_params": {"gust": 0.4}, "seed": 3,
  "segments": [{"rpm": 60, "s": 20, "params": {"power": 0.8}}, {"rpm": 0, "s": 3, "params": {"power": 0}}],
  "events": [{"t": 4.0, "cue": "shot_main", "vars": {}}],
  "loops": [{"id": "drag_scream", "t0": 30, "t1": 34, "params": {"tension": 0.9}}],
  "checks": {"a6": {"param": "power", "from": 0.5, "to": 1.2}, "a7": {"param": "power", "from": 0.5, "to": 1.3}, "a14": {"cue": "shot_main"}},
  "waive": {"A10": "the stated musical reason, with the number"}
}
```

It writes to `build/audio_preview/`: `<game>.wav` and `.mp3`, `<game>_<machine>_<rpm>.wav` (the lead alone, 10 revolutions), `<game>_bed.wav` (30 s), `<game>_events.json`, and with ffmpeg `<game>.png`, a spectrogram per solo and `<game>.ebur128.txt`. ffmpeg is optional and used nowhere else; the JS loudness numbers agree with its `ebur128` to 0.1 LU on the fixture. `build/.gdignore` is created first, or the next `--import` would take every preview WAV in.

`scorecard` computes the game developer (D) and audio creator (A) rows and exits non-zero on any failure with no waiver. `tools/audio/test/scorecard_gate.test.mjs` holds every bank on disk with a `preview` block to it, so these are permanent gates. D rows never take a waiver, and neither do A1, A9, A11 or A15. D8 (event coverage) is each game's GUT test; D10 is a bench.

Levels add up tightly: Machines at -22 and Ambience at -32 sum to about -21.5 LUFS, under A1's -20 floor unless events are frequent. The fixture reaches -19.3 with Machines at -20.4, the top of their window, so start a bank there.

How a row reads the audio, where the name alone doesn't say:

- D1, D2: each event entry of the lead machine, rendered alone over 10 revolutions, against the pattern: a sharp rise of the fast envelope, 20 ms apart at least. A stroke with no attack of its own, ringing into the next, fails.
- D5: `warning` and `rescue` momentary against every other bus in the same 600 ms, the prompt's own ducks counted (`SAFETY_DUCK`, `WlSfx`'s -14 dB on Machines and Ambience and -20 dB on Sfx, back over 2 s), and the prompt at the -4 dB `HudLayer` plays it (`PROMPT_VOICE_DB`). It plays the prompts at the mix's midpoint and on and just before the mix's loudest moment (0, 0.2 and 0.4 s ahead of the loudest 400 ms): a prompt can fire in a sprint, and one fired just before a stinger meets it with its duck already releasing. The worst of these is the row's value, with the prompt and time in its note. A preview's loudest moment should be the game's real one.
- A3: spectral flux, stdev over mean plus 2 % of the frame magnitude, from the second revolution on, with a 2048 window. A steady drone reads near 0.2, and an engine with strokes above 1.
- A5: the correlation of a 4 ms envelope between successive revolutions.
- A12: the bed's 50 ms envelope, autocorrelated at each layer's own length. A second layer of a co-prime length and the spots are what bring it down.
- A16: at least 3 different spot sounds in 60 s, and no 2 different spots within 2 s. A spot whose own gap can be under 2 s (cricket trains) is a texture and counts only toward the 3.

## What no number here can say

Whether a diesel reads as a diesel or a gull as a gull, whether an hour of it is pleasant, the balance on real speakers over a real trainer and fan, driver latency on a real device, and how it feels against your own feet. The critics check coherence, not beauty. Those stay open until someone listens to `build/audio_preview/*.mp3` and rides.

FTMS reports cadence, not crank angle, about once a second. The audio locks to the on-screen crank exactly and to the feet in rate only.
