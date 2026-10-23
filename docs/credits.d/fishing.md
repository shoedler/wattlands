# Credits: fishing

Third-party assets (art, audio, fonts) the fishing game ships, with their licenses and sources.

- Art (v0.1, placeholder): every sprite in `assets/fishing/sprites/` is drawn in code by `FishingFallbackSprites` (`src/games/fishing/tools/fishing_fallback_sprites.gd`) from the 32-colour palette in `assets/fishing/art.json`, and written by `src/games/fishing/tools/fishing_write_fallback_sprites.gd`; `picker_card.png` is the hand-made G0 placeholder in the same palette. No generated or downloaded art ships in this build: the art pipeline did not run (`WATTLANDS_ALLOW_ART` was not set), so no fal requests were made and the art spend is $0.00 (`assets/fishing/art_manifest.json`).
- Art (when regenerated): sprites made by the art pipeline (`tools/art/generate.mjs`, brief 3.4) are generated with OpenAI's GPT Image 2.5 through fal (fal.ai), from the original prompts in `assets/fishing/art.json`, and pixelated to the palette by `tools/art/pixelate.gd`. `assets/fishing/art_manifest.json` records every request and its cost.
- Audio: no sound files and no third-party samples. Every sound (reel clicks, drag scream, gulls, splashes, strike bell, snap twang, landing fanfare, surf bed, metronome) is synthesized at runtime with `Sfx.synth` (ADR "Synthesized audio" in `docs/decisions/fishing.md`).
- Fonts, UI kit and 2D kit: the platform's (`addons/wattlands/ui`, `addons/wattlands/world2d`), credited in the platform's credits. Fishing adds none.
