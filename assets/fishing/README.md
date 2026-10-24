# Turbo Reel assets

- `sprites/`: one PNG per sprite (`<id>.png`, its animation frames side by side), `sprites.json` (frame size, frame count, anchor per sprite) and the `.import` files Godot writes.
- `art.json`: the palette (32 colours, `FishingPalette.ALL`) and the sprite list in the art pipeline's format, written by the same tool.
- `art_manifest.json`: the art pipeline's spend record ($3.56 of the $10 budget).

## Hand-authored pixel art

Every sprite is a palette-indexed text grid in `src/games/fishing/tools/fishing_art_grids.gd` (`FishingArtGrids`: one character per palette colour, `.` clear), plus a few frames derived in code (fish swim waves, flywheel spokes, the cards composed from other sprites). Edit the grids, then write the PNGs and re-import:

```bash
. tools/env.sh
tools/godot.sh --headless --path . -s src/games/fishing/tools/fishing_write_sprites.gd -- --sheet=/abs/path/sheet.png
tools/godot.sh --headless --path . --import
```

`--sheet` also writes a 4x preview of every sprite and the assembled boat (driving and fishing). PNGs no sprite owns are deleted. `tests/games/fishing/art/` fails when a PNG differs from the grids, uses a colour outside the palette, or breaks the shapes the view relies on (fish face left with the mouth at the anchor, boat parts inside the hull canvas, key reds on the hull and rider for the slot colour).

Style: the muted, limited palette in a few ramps, no outlines, flat haze layers, calm negative space, tiny crisp sprites with a few precise details. The sky, water, floor, clouds, coast, waves and the world-edge waterfall are code-drawn from the same palette (`src/games/fishing/view/fishing_scenery.gd`).

Sprites: `boat_hull` (96 x 40, the stern long-tail shaft included; boat-local points in `view/fishing_rig.gd`), `boat_flywheel`, `boat_gears`, `boat_winch`, `boat_prop`, `rider`, `lure`, ten `fish_<species>` with four swim frames, seven `icon_*` minimap and leaderboard icons (white pixels take the slot colour), `scenery_town`, `scenery_pier`, `gull`, `fx_splash`, `fx_sparkle`, and the cards `picker_card` (the game's picker image), `card_roam` and `card_workout` (160 x 90).
