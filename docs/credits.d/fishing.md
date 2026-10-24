# Credits: fishing

Third-party assets (art, audio, fonts) the fishing game ships, with their licenses and sources.

- Art: every sprite in `assets/fishing/sprites/` (and `picker_card.png`, the picker image) is original pixel art hand-authored as palette-indexed grids in `src/games/fishing/tools/fishing_art_grids.gd`; the sky, water, floor, clouds, coast and waterfall are drawn in code (`src/games/fishing/view/fishing_scenery.gd`). The style follows a reference image the user supplied (Slynyrd, "Pixelblog 7: developing style"); nothing from it ships. No generated, third-party or downloaded art ships.
- Audio: no sound files and no third-party samples. Every sound (the drivetrain hum, winch clicks, drag scream, gulls, splashes, the clutch clunk, bite bell, snap twang, landing fanfare, horn, surf bed) is synthesized at runtime with `Sfx.synth` (ADR "Synthesized audio" in `docs/decisions/fishing.md`).
- Fonts, UI kit and 2D kit: the platform's (`addons/wattlands/ui`, `addons/wattlands/world2d`), credited in the platform's credits. Fishing adds none.
