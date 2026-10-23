# Credits: fishing

Third-party assets (art, audio, fonts) the fishing game ships, with their licenses and sources.

- Art: every sprite in `assets/fishing/sprites/` (and `picker_card.png`, the picker image) is generated with OpenAI's GPT Image 2.5 through fal (fal.ai) by the art pipeline (`tools/art/generate.mjs`, brief 3.4), from the original prompts in `assets/fishing/art.json`, and pixelated to the 32-colour palette by `tools/art/pixelate.gd`. `assets/fishing/art_manifest.json` records every request and the spend ($3.56 of the $10 budget). Flare drafts kept: `boat`, `rig_bike`, `rig_angler`, `rig_crank`, `rig_reel`, `fish_marlin` (`openai/gpt-image-2.5/flare/text-to-image`). Every other sprite (the fish, gulls, bait ball, sonar mark, effects, trophy badge, clouds, islands, sun, wake, surface, light rays, reefs, sand and `picker_card`) is a sunburst result (`openai/gpt-image-2.5/sunburst/text-to-image`). No third-party or downloaded art ships.
- Audio: no sound files and no third-party samples. Every sound (reel clicks, drag scream, gulls, splashes, strike bell, snap twang, landing fanfare, surf bed, metronome) is synthesized at runtime with `Sfx.synth` (ADR "Synthesized audio" in `docs/decisions/fishing.md`).
- Fonts, UI kit and 2D kit: the platform's (`addons/wattlands/ui`, `addons/wattlands/world2d`), credited in the platform's credits. Fishing adds none.
