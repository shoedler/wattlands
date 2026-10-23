# Siege assets

This folder is the game's `assets/<id>/`. Castellum Rotae ships no asset files:

- Every mesh is a GDScript `LowPolyMesh` or a `MultiMesh` built at load (`src/games/siege/view/`): flat shading, vertex colors, no textures, no generated or downloaded art.
- Every sound is synthesized at runtime with `Sfx.synth` (`src/games/siege/audio/siege_audio.gd`): the wheel creak, the generator hum, tower shots, hooves, the ram, the gate and horns. Coins and the Breach boom are the platform's built-in `coin` and `boom`.

So there is no `art.json`, no `art_manifest.json` and nothing to credit here. Any asset added later is credited in `docs/credits.d/siege.md`.
