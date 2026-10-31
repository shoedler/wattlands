# Decisions: audio-dsp

Short ADRs for the audio pipeline (`tools/audio`, `assets/_shared/audio`). "SPEC" is the run's SPEC_AUDIO.

## 2026-10-31 A loop file carries a guard frame; `edit/loop_end` stays -1

- Decision: a loop of N frames is written as N + 1, the last a copy of frame 0, with `edit/loop_end=-1`.
- Alternatives: N frames with -1, as the SPEC's skeleton implied (measured on 4.7.2: Godot stores `frames - 1`, a period one frame short that drops the last frame); N frames with `loop_end=N` (Godot keeps it, but its resampler then reads one frame past the loop end into the zero padding, a small tick each wrap).
- Reason: the period is exactly N and the read past the end lands on frame 0, in PCM and in QOA. `test_audio_assets.gd` holds it through the real importer. Manifest entries carry both `frames` and `loop_frames`.

## 2026-10-31 A loop's seam goes at the quietest step of its cycle

- Decision: after the crossfade the file is rotated to start where the sample step is smallest.
- Alternatives: leave the seam where the crossfade ends. On noise that pair is 2 sigma past the median step about one time in 25, per channel, and A11 can't be waived, so a few games' beds would fail by chance.
- Reason: a seam no louder than any other pair of samples. A cyclic signal loses nothing by rotating.

## 2026-10-31 The crossfade adapts to the head and tail's correlation

- Decision: fade gains `u / sqrt(u² + v² + 2ruv)`, with r measured over the crossfade. No per-sound setting.
- Alternatives: equal power (measured: +2.5 dB across the seam of a tone in phase); linear (a dip on noise); a recipe flag that each builder has to get right.
- Reason: constant power for any r, with nothing to choose.

## 2026-10-31 `warning` and `rescue` play at -16 LUFS momentary, past the UI row's -17

- Decision: as played, both prompts read -16. `HudLayer._play`, the only path they have to `WlSfx`, plays at -4 dB and `hud_layer.gd` is frozen, so the files carry it: file peaks -8 and -10.6 dBFS, file momentary -12. `simulate()` plays a prompt at -4 dB too (`PROMPT_VOICE_DB`, pinned to `hud_layer.gd` by a test), D5 reads that, and A2 holds the prompts as played to -23..-15 and every other UI sound's file to -23..-17.
- Alternatives: -17 and under, the SPEC's row. Measured as played on the fixture, -16 reads D5 +7.83 LU over a -19.31 LUFS mix, +6.53 over -18.13 and +6.03 over -17.67, so -17 would read about +5.5 at the SPEC's own -18 target. Raising the prompts further to cover A1's whole window (-16 LUFS needs about -14 as played) was also rejected: a louder alarm for a mix no bank should aim at.
- Reason: D5 is the safety row and cannot be waived; BRIEF 4.6 outranks a loudness target. A sound here is over the row only by 1 dB, and only for the two prompts. The cost: D5 caps a game's mix at about -17.6 LUFS, inside A1's window, and the scorecard says so to the builder.

## 2026-10-31 Ticks under 100 ms and the metronome are outside the UI loudness row

- Decision: `ui_move` (50 ms, about -27 momentary) and `click` (12 ms) are not metered. `coin`, `hit`, `boom` and `whoosh` play on Sfx (SPEC 1.4), so the UI row does not apply to them either.
- Alternatives: raise `ui_move` by 4 dB so a 400 ms meter reads -23.
- Reason: a 400 ms block reads a 50 ms tick as silence plus the tick. SPEC 4.5 asks for a soft tick, and raising it makes it louder than a confirm to the ear. `shared.test.mjs` names the excluded sounds, so a new one must be placed.

## 2026-10-31 The preview's limiter runs 0.25 dB under the kit's ceiling

- Decision: `offline_mix` limits sample peaks to -1.25 dB. The kit's `AudioEffectHardLimiter` stays at -1 dB (SPEC 1.4).
- Alternatives: -1 dB, which read -0.85 dBTP on the fixture, a failure of the unwaivable A1 from intersample peaks alone.
- Reason: A1's -1 dBTP is a true-peak target and the limiter is a sample-peak one. Godot's true peak behind its own limiter is not measured here.

## 2026-10-31 A3 is measured with a longer window and a floor

- Decision: spectral flux with a 2048 window, hop 512, from the second revolution on, as stdev over mean plus 2 % of the frame magnitude.
- Alternatives: stdev over mean on a 512 window, which passed a steady 55 Hz saw: the window was shorter than its period, and the loops' opening dominated the stdev.
- Reason: A3 exists to catch a monotone rumble. A drone now reads about 0.2 and fails; the fixture's engine reads 1.3.

## 2026-10-31 Additions to the schema, all of them read only by the generator or the preview

- Decision: `per_variant`, `pitch`, `width`, `xfade_s`, layer `dur`, `glide_s`, swept filter `f`; `preview.others[].lead` and `.rpm_by` (a Tank track, driven by speed), `preview.loops`, `preview.seed`, `preview.checks`, `preview.waive`. `audio_manifest.json` is keyed by file stem and adds `sound`, `variant`, `loop_frames`, `preroll`, `bytes`, `loop`, `locked`, `compress`.
- Alternatives: requests to the lead from each game builder later. The SPEC's list has no way to give variants different pans, which it asks for (gulls left and right), nor to run a machine on hull speed in the preview.
- Reason: game builders do not edit `tools/audio/lib/`. `AudioBank` ignores keys it does not read.

## 2026-10-31 A third import proof fixture

- Decision: `import_proof_locked` joins the SPEC's two, plus the bank and its manifest under the same prefix.
- Alternatives: read the pre-roll guarantee off `edit/trim=false` alone.
- Reason: SPEC's point is that a locked file's pre-roll survives import, so the test reads the 80 ms of silence out of the imported data.
