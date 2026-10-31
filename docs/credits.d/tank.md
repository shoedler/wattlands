# Credits: tank

Art, audio and fonts the tank game ships, with their sources.

- Art, from the reference: the landship's base art (`assets/tank/v3/tools_src/src/tank_4rider.png`) and the far and foreground planes (`assets/tank/v3/tools_src/src/`) derive from Simon's reference image. `docs/games/tank.md` calls it his image and quotes the prompt that made it; it does not record the tool. The image left the tree in the v0.9.3 cleanup and stays in git history (`assets/tank/v2/source/reference.webp` at d82d901c). The scripts in `assets/tank/v3/tools_src/` rebuild the art as pixel art; the manifest is `assets/tank/v3/kit.json`.
- Art, procedural code: the enemies, their wrecks, the bushes and the far ground (`assets/tank/v4/tools_src/`; the manifest is `assets/tank/v4/enemies.json`), the machines in the rooms and on the cards and the riders (`TankInterior`, `TankMech`), the HUD (`src/games/tank/hud/`) and its bitmap fonts (`tank_stencil_5x7`, `tank_stencil_5x9` and `tank_digits_14x24`, written by `TankHudFont`), the shell screen and the seam, the lights, shells, tracers, smoke, sparks and every other effect (`src/games/tank/view/`). The content cards and the picker card are renders of the game's own view.
- The game and its tools make no fal or other image-model request. The reference above is the one input that came from a prompt.
- Audio: no third-party samples and no CC0 downloads. The game ships a bank rendered from its own recipes: see `docs/credits.d/audio-tank.md` and "Audio" in `src/games/tank/README.md`.
- Platform fonts and UI kit (pause, help and results screens): the platform's, credited in the platform's credits. Tank adds only the bitmap fonts above.
