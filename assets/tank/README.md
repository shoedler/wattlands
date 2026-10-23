# Tank assets

Diesel Domestiques' `assets/tank/` (owner: artqa, except `audio/`, which is the view builder's).

- `art.json`: the 61 sprite requests for `tools/art/generate.mjs` (palette, style, sizes, `tile` + `mirror` strips wider than 3:1). This run sets no `WATTLANDS_ALLOW_ART`, so no fal call happens: every sprite id draws as a procedural placeholder (`src/games/tank/view/placeholder_art.gd`) at its `art.json` size, and the view works with placeholders for every id. See `docs/ART_PIPELINE.md`.
- `rigs.json`: cutaway rig anchors and gameplay geometry in art px, with every frame described in its `_doc`. The gameplay keys (muzzles, trunnions, barrel length, secondaries, the dug-in hit box, the Behemoth's part boxes and muzzles) are a frozen contract read through `TankGeometry` (`src/games/tank/contracts/tank_geometry.gd`): artqa may re-measure their values, never rename them or change their frames, and `muzzle == trunnion + [barrel_px, 0]` must hold (tested).
- `icons/engine_{diesel,dynamo,steam,bulwark}.png` (optional): 14 x 14 palette icons for the teammate strip, committed with their `.import` files. Until they exist the strip shows the engine name only, which is an accepted state.
- `audio/`: none; all sound is synthesized at runtime (`Sfx.synth`).

Credit every generated or third-party asset in `docs/credits.d/tank.md`.
