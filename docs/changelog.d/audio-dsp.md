# Changelog: audio-dsp

- `tools/audio`: a zero-dependency, deterministic audio pipeline. Recipes in `audio.json` render to WAV with per-file import params; `preview` writes per-revolution solos, a bed and a full mix; `scorecard` turns the sync, loudness and family rules into permanent tests. See `docs/AUDIO_PIPELINE.md`.
- The platform's 15 UI sounds are redone in one family in `assets/_shared/audio/`, with their names unchanged.
