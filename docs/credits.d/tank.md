# Credits: tank

Art, audio and fonts the tank game ships (v2, `docs/games/tank.md` 3), with their sources.

- Art, from the reference: the tank (all four variants, the turret and the barrel), the backdrop planes (the sky with the Milky Way, the mountains, the cliff and the lake, the forest, the road and the dark foreground) and the enemies (light, medium, heavy, tank destroyer, dug-in and the Behemoth) are cut from Simon's reference image (`assets/tank/v2/source/reference.webp`, made for this project) and derived from it procedurally by the kit scripts in `assets/tank/v2/tools_src/` (`regen.sh`; the manifest is `assets/tank/v2/kit.json`). The content cards and the picker card are rendered from the same kit (`cards.gd`).
- Art, procedural code: the machines in the engine rooms (`TankMech`), the crew (`assets/tank/v2/crew20/`, drawn by `crew20.gd` and posed by `TankCrew`), the HUD (`src/games/tank/hud/`) and its bitmap fonts (`tank_stencil_5x7`, `tank_stencil_5x9` and `tank_digits_14x24` in `assets/tank/v2/hud/`, drawn by `font.gd`), and the lights, wrecks, halt line, shells, tracers, smoke, sparks and every other effect (`src/games/tank/view/`).
- No generated sprites: v2 makes no fal or other image-model request and ships none of v1's generated sprites (`assets/tank/sprites/`, `assets/tank/art.json` and its manifest are gone).
- Audio: no third-party samples and no CC0 downloads. The game ships a bank rendered from its own recipes: see `docs/credits.d/audio-tank.md` and "Audio" in `src/games/tank/README.md`.
- Platform fonts and UI kit (pause, help and results screens): the platform's, credited in the platform's credits. Tank adds only the bitmap fonts above.
