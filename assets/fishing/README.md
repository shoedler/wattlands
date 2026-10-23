# Turbo Reel assets

- `art.json`: the art pipeline's description of every sprite (palette of 32 colours, shared style, sizes, parts, tiling); brief 3.3, `docs/ART_PIPELINE.md`.
- `art_manifest.json`: every fal request and the art spend (`spend.total_usd`, budget $10): the generated art cost $3.56 (6 flare drafts kept, the rest sunburst, a few re-rolls).
- `sprites/`: one PNG per sprite (`<id>.png`), one per part (`<id>__<part>.png`: the fish's `body` and `tail`), `sprites.json` (size, anchor, align, tile, mirror, parts per sprite) and the `.import` files Godot writes.

## Generated art, with a placeholder fallback

The sprites in `sprites/` are real generated art (GPT Image 2.5 through fal, pixelated to the palette; credits in `docs/credits.d/fishing.md`). The placeholder drawer stays as brief 3.4's fallback: `src/games/fishing/tools/fishing_fallback_sprites.gd` (`FishingFallbackSprites.image(id)`) draws every sprite except `picker_card` from the palette, and the view calls it when a PNG is missing. Rewriting the placeholders overwrites the generated PNGs, so only do it on purpose (`git checkout` restores them):

```bash
tools/godot.sh --headless --path . -s src/games/fishing/tools/fishing_write_fallback_sprites.gd
tools/godot.sh --headless --path . --import
```

## Generating the real art

Needs `FAL_KEY` and `WATTLANDS_ALLOW_ART=1` (set only on the `generate.mjs` call); the budget is $10 minus `spend.total_usd`, so about $6.44 is left. Raw results live in the gitignored `.art_cache/`; a fresh clone fetches the selected ones again for free when `generate.mjs` runs with the sprite in `--only`, and `pixelate.gd` is byte-identical on re-runs.

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

Lessons from the v0.1 run: the shared style ("single subject centered") makes the model invent a mascot for strips and effects, so strip and effect prompts say "seamless wide horizontal strip made only of ..., no animals, no characters"; `reef_front` needs "no red" (the pink coral otherwise quantizes onto the key ramp, which `tests/games/fishing/art` forbids); `fish_tuna` needs "nose touches the left edge, tail tips touch the right edge" so the fitted fish reaches the right edge.
