# Turbo Reel assets

- `sprites/`: one PNG per sprite (`<id>.png`, its animation frames side by side), `sprites.json` (frame size, frame count, anchor per sprite) and the `.import` files Godot writes.
- `art.json`: the palette (`FishingPalette.ALL`) and the sprite list in the art pipeline's format, written by the same tool.
- `art_manifest.json`: the art pipeline's spend record ($3.56 of the $10 budget).

## Hand-authored pixel art

Every sprite is a palette-indexed text grid in `src/games/fishing/tools/fishing_art_grids.gd` (`FishingArtGrids`: one character per palette colour, `.` clear), plus a few frames derived in code (the fish's tail beat, the cards composed from other sprites). Edit the grids, then write the PNGs and re-import:

```bash
. tools/env.sh
tools/godot.sh --headless --path . -s src/games/fishing/tools/fishing_write_sprites.gd -- --sheet=/abs/path/sheet.png
tools/godot.sh --headless --path . --import
```

`--sheet` also writes a 4x preview of every sprite and the assembled boat (driving and fishing). PNGs no sprite owns are deleted. `tests/games/fishing/art/` fails when a PNG differs from the grids, uses a colour outside the palette, breaks the style rules (a cool hue family, nothing darker than the abyss, no fish outlines or lone pixels) or the shapes the view relies on (fish face left with the mouth at the anchor, boat parts inside the hull canvas, a slate hull under a straight foam rail).

## Style

Modelled on Slynyrd's "Nemk": one cool hue family in eight value steps from foam white to abyss teal (`FishingPalette.LADDER`, nothing darker than `#1c4d65`), seabed sage, two slates for wood and hulls, one warm accent (`#c98a5e`, the brass wheel and lever knob) and three desaturated player colours that appear only on the rider's cap and the bow pennant. Forms are 2-3 flat top-lit planes with no outlines, no anti-aliasing, no dither and no texture; edges are horizontal and vertical, diagonals only in even 1:1 and 2:1 runs; structure is 2 px, 1 px only for straight accents. Nothing is ever rotated: a boat's pitch lifts it by whole pixels. Fish shift along the ladder with depth (`FishingPaletteMap`): dark on the two light water bands, lit below. The sky, clouds, islands, water bands, stepped floor, dock, wakes and the world-edge waterfall are code-drawn from the same palette (`src/games/fishing/view/fishing_scenery.gd`, `fishing_view.gd`).

`tests/games/fishing/art/style_check.mjs` measures the rubric's numbers on 1920x1080 screenshots with the HUD masked: `node tests/games/fishing/art/style_check.mjs build/fishing/style/*.png`.

Sprites: `boat_hull` (96 x 40, the long-tail shaft included; boat-local points in `view/fishing_rig.gd`), `boat_crew` (clutch lever, tiller, rider, legs, pedal wheel and crank: four crank frames driving, four fishing), `boat_winch`, `boat_prop`, `lure`, ten `fish_<species>` with four swim frames, seven `icon_*` minimap and leaderboard icons (foam pixels take the player colour), `scenery_town`, `scenery_pier`, `gull`, `fx_splash`, `fx_sparkle`, and the cards `picker_card` (the game's picker image), `card_roam` and `card_workout` (160 x 90).
