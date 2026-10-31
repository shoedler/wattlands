# Credits: fishing

Third-party assets (art, audio, fonts) the fishing game ships, with their licenses and sources.

- Art: every sprite in `assets/fishing/sprites/` is original pixel art hand-authored as palette-indexed grids in `src/games/fishing/tools/fishing_art_grids.gd`; the sky, water, floor, clouds, coast and waterfall are drawn in code (`src/games/fishing/view/fishing_scenery.gd`). The style follows a reference image the user supplied (Slynyrd, "Pixelblog 7: developing style"); nothing from it ships. The picker image `assets/fishing/cards/picker_card.png` is a render of the game's own view with no HUD (`tools/picker_cards/`). No generated, third-party or downloaded art ships. `assets/fishing/art_manifest.json` still records 53 fal requests of 2026-10-23 ($3.56): a first attempt, kept as the spend record. The hand-authored grids replaced its output on 2026-10-24, and no shipped PNG comes from those requests.
- Audio: all synthesized from recipes in this repo (`assets/fishing/audio/audio.json`, rendered by `tools/audio`): no samples, no downloads, no generated-media service, no third-party material. Nothing to attribute.
- Fonts: the HUD's 5 x 7 pixel font (`assets/fishing/font/turbo_reel_5x7.png`) is hand-authored as grids in `src/games/fishing/tools/fishing_font_grids.gd`.
- UI kit and 2D kit: the platform's (`addons/wattlands/ui`, `addons/wattlands/world2d`), credited in the platform's credits.
