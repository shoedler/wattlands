# Credits: siege

Third-party assets (art, audio, fonts) the siege game ships, with their licenses and sources.

- None. Every image is drawn by Siege's own CPU rasterizer and every sound is rendered from recipes by `tools/audio` (`docs/decisions/audio-siege.md`).
- Audio: all synthesized from `assets/siege/audio/audio.json` by `tools/audio`. No samples, no downloads, no fal, no third-party material; nothing to attribute.
- Art: no generated or downloaded art (no fal calls). `assets/siege/bake/` (the world, its depth and the sprite atlases) is rendered by our own rasterizer, `src/games/siege/art/*.mjs` (`node src/games/siege/art/bake.mjs`); the HUD shapes are code.
- Fonts: the HUD's type is drawn in code (`src/games/siege/hud/siege_hud_type.gd`). UI kit: the platform's (`addons/wattlands/ui`), credited in the platform's credits.
