# Credits

The code, fonts, audio and art used by Wattlands, and where each came from. Merged from the fragments in `docs/credits.d/`, which hold the detail. Versions, sources and SHA-256 sums are in `docs/DEPENDENCIES.md` and `docs/deps.d/`.

## Code

- Godot Engine 4.7.2, MIT, https://godotengine.org/license (with the engine's own third-party notices).
- GDBLE v0.6.0, MIT, Copyright (c) 2025 Fantety, https://github.com/Fantety/GDBLE (Bluetooth LE GDExtension). Its DLL statically links btleplug 0.12 (MIT/Apache-2.0/BSD-3-Clause, https://github.com/deviceplug/btleplug) and godot-rust `godot` 0.5.2 (MPL-2.0, source at https://github.com/godot-rust/gdext).
- GUT 9.7.1 (Godot Unit Test), MIT, https://github.com/bitwes/Gut (tests only, not shipped). Its bundled fonts are under the SIL Open Font License 1.1.
- ws 8.22.0, MIT, https://github.com/websockets/ws (relay server; the relay also runs without it).
- @garmin/fitsdk 21.218.0, Garmin FIT Protocol License, https://www.npmjs.com/package/@garmin/fitsdk (test tool only: tools/fit_check; installed by npm ci, never shipped).

The Windows build ships `docs/THIRD_PARTY_NOTICES.txt` next to the executable.

## Fonts

- Menus and the HUD kit: Godot's default font, part of the engine.
- Each game's HUD type is its own, made in this repository: Torque Company `tank_stencil_5x7`, `tank_stencil_5x9` and `tank_digits_14x24` (`TankHudFont`); Workout `wo_text_5x7`, `wo_tall_5x9` and `wo_digits_14x24` (`src/games/workout/art/hud_font.mjs`); Turbo Reel `turbo_reel_5x7` (`src/games/fishing/tools/fishing_font_grids.gd`); Castellum Rotae's type is drawn in code (`src/games/siege/hud/siege_hud_type.gd`).

## Audio

All of it is rendered by `tools/audio` from recipes in this repository: the platform's sounds (`assets/_shared/audio/audio.json`) and each game's (`assets/<id>/audio/audio.json`). No samples, no downloads, no generated-media service and no third-party material, so nothing to attribute. The BS.1770 K-weighting constants in `tools/audio/lib/lufs.mjs` are the published ones; the implementation is ours.

## Art

- **Castellum Rotae:** drawn by the game's own CPU rasterizer (`src/games/siege/art/*.mjs`, baked to `assets/siege/bake/`); the HUD shapes are code. No generated or downloaded art.
- **Workout:** drawn by the game's own Node code (`src/games/workout/art/bake.mjs` and `src/games/workout/art/hud_bake.mjs`). No generated or downloaded art.
- **Turbo Reel:** every sprite is original pixel art hand-authored as palette-indexed grids (`src/games/fishing/tools/fishing_art_grids.gd`), and the sky, water, floor, clouds, coast and waterfall are drawn in code. The style follows a reference image supplied for the project (Slynyrd, "Pixelblog 7: developing style"); nothing from it ships. `assets/fishing/art_manifest.json` records 53 fal requests of 2026-10-23, a first attempt whose output the hand-authored grids replaced the next day; none of it ships.
- **Torque Company:** the landship's base art and the far and foreground planes derive from Simon's reference image, rebuilt as pixel art by the scripts in `assets/tank/v3/tools_src/`. `docs/games/tank.md` calls it Simon's image and quotes the prompt that made it; it does not record the tool. The enemies, machines, riders, HUD and effects are procedural code (`assets/tank/v4/tools_src/`, `src/games/tank/view/`, `src/games/tank/hud/`). The game and its tools make no fal or other image-model request.
