# Big Game Fishing assets

- `art.json`: the art pipeline's description of every sprite (palette of 32 colours, shared style, sizes, parts, tiling); brief 3.3, `docs/ART_PIPELINE.md`.
- `art_manifest.json`: every fal request and the art spend (`spend.total_usd`, budget $10). v0.1 made no requests: $0.00.
- `sprites/`: one PNG per sprite (`<id>.png`), one per part (`<id>__<part>.png`: the fish's `body` and `tail`), `sprites.json` (size, anchor, align, tile, mirror, parts per sprite) and the `.import` files Godot writes.

## v0.1 ships placeholder art

`WATTLANDS_ALLOW_ART` was not set when the art builder ran, so brief 3.4's fallback applies: `src/games/fishing/tools/fishing_fallback_sprites.gd` (`FishingFallbackSprites.image(id)`) draws every sprite except `picker_card` from the palette with simple shapes, and `sprites.json` says `"art_mode": "placeholder"`. `picker_card.png` is the G0 placeholder. The view also calls `FishingFallbackSprites.image(id)` when a PNG is missing.

Rewrite the placeholders:

```bash
tools/godot.sh --headless --path . -s src/games/fishing/tools/fishing_write_fallback_sprites.gd
tools/godot.sh --headless --path . --import
```

## Generating the real art

Needs `FAL_KEY` and `WATTLANDS_ALLOW_ART=1`, set by a human (never by an agent); the budget is $10 minus `spend.total_usd`.

```bash
. tools/env.sh
node tools/art/generate.mjs --game=fishing --dry-run
# drafts on flare: set "endpoint" to openai/gpt-image-2.5/flare/text-to-image, then
node tools/art/generate.mjs --game=fishing --only=rig_bike,rig_angler,rig_crank,rig_reel,boat,fish_marlin --budget=<10 - spent>
tools/godot.sh --headless --path . -s tools/art/pixelate.gd -- --game=fishing
# review at 4x, fix prompts, set "endpoint" back to openai/gpt-image-2.5/sunburst/text-to-image, then
node tools/art/generate.mjs --game=fishing --only=<every other sprite and failed drafts> --budget=<10 - spent>
tools/godot.sh --headless --path . -s tools/art/pixelate.gd -- --game=fishing
tools/godot.sh --headless --path . --import
```

Review criteria (brief 3.4): fish face left with the tail at the right edge, the boat's bow points right, the red key ramp (`#e0413a`, `#9e2228`) only on the boat's trim and canopy and the angler's cap and shirt, clear silhouettes, no rocks in the HUD zone. At most two re-rolls per sprite, each with a sharpened prompt and `--only=<id>`. `tests/games/fishing/art/` checks every PNG (palette colours or full transparency, sizes, parts, the key ramp, fish facing).
