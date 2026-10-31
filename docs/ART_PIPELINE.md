# Art pipeline

A 2D game can make its pixel art with `tools/art` (BRIEF 3.10): `generate.mjs` asks fal.ai's GPT Image 2.5 for one picture per sprite, and `pixelate.gd` turns each picture into a small sprite in the game's palette. The art is animated by parts in the `world2d` kit, not by drawn frames. No shipped game uses this today: Castellum Rotae, Torque Company and Workout bake their art with their own scripts, and Turbo Reel draws it from grids in code. Turbo Reel tried the pipeline first; `assets/fishing/art_manifest.json` is the record of that, and none of its output ships.

```
assets/<id>/art.json ──► node tools/art/generate.mjs ──► .art_cache/<id>/<request id>.png   (raw, gitignored)
                                     │                     assets/<id>/art_manifest.json     (committed)
                                     ▼
                     tools/godot.sh ... -s tools/art/pixelate.gd ──► assets/<id>/sprites/*.png  (committed)
                                                                    assets/<id>/sprites/sprites.json
```

## Setup and the art lock

Real generation needs two environment variables, both set by a human (Simon), never by an agent:

- `FAL_KEY`: the fal API key (`<id>:<secret>`). Never print, log or commit it. `generate.mjs` sends it only to `queue.fal.run` and `api.fal.ai`, never to an image host, and redacts it from every message and from every file it writes (`art_manifest.json` and the `.art_cache` result JSON, whatever fal sends back). It uses the key with surrounding whitespace trimmed, as it goes on the wire.
- `WATTLANDS_ALLOW_ART=1`: the permission for paid calls.

Without both, `generate.mjs` refuses (exit 4) before it opens any connection, unless `--mock=<url>` points it at `tools/art/mock_fal`. The art lock replaces the network lock for this one tool: `generate.mjs` never reads `WATTLANDS_NO_NETWORK_INTEGRATIONS`, so keep that lock on (`. tools/env.sh`) for everything, art runs included. `tools/env.*` and the Godot wrappers never touch `FAL_KEY` or `WATTLANDS_ALLOW_ART`; `tools/run_tests` removes both from every process it starts, so no test can reach the real fal. Run your own test commands the same way: `env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/run_tests`.

In the Claude desktop app, add both variables to the app's Local environment before starting the game session. `generate.mjs` contacts only fal's hosts (`*.fal.run`, `*.fal.ai`, `*.fal.media`, https only) or, with `--mock`, only the mock's loopback origin.

### Budgets and fal credits

- Every run stops before its own estimated spend would pass `--budget=<usd>` (default `$10`). The stop sums, per request, the larger of the estimate and the billed amount fal reports (exit 3, with the sprites it didn't pay for). Cached and recovered results cost nothing.
- A game session's total art spend is `spend.total_usd` in `assets/<id>/art_manifest.json` (the larger of estimate and billed amount per paid request, summed). Pass `--budget=<session cap − spent>` on every run.
- Estimates come from `tools/art/prices.json`: sunburst at high quality is $0.07 an image up to 1536 × 864 (more above, by pixel count); flare uses fal's listed per-size price plus a prompt allowance (about $0.04–0.06 at the sizes the tool requests). fal bills on completion, even when the download fails afterwards (see Recovery).
- fal credits: top up in fal's dashboard (Billing). When the balance runs out fal refuses new requests (an HTTP 403 "exhausted balance" error); the run records them as `submit_failed`, which costs nothing, and exits 1. A submit that never left this machine (offline, no DNS answer, connection refused, a failed TLS handshake) costs nothing either: it is `submit_failed`, and the run stops submitting, names the sprites it did not submit and exits 1. A submit whose answer never arrives after the connection was made (a dropped connection or a timeout) is different: fal may have queued it, so it stays counted against `--budget` and in `spend.total_usd` (`submit_unconfirmed`), and the next run adopts it from fal's request history.

## Writing art.json

`assets/<id>/art.json` describes every sprite. Keep sprites consistent by sharing as much as possible: one `style` prefix for all of them, one fixed palette, transparent backgrounds for everything but backdrops, and sizes in art pixels (the pixels of the game's `pixel_base`, e.g. 640 × 360).

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `palette` | array of `"#rrggbb"`, 1–32, no duplicates | required | Every output pixel is one of these colors or fully transparent |
| `style` | string | required | Prompt prefix shared by every sprite; the prompt sent is `style + " " + prompt` |
| `endpoint` | string | `openai/gpt-image-2.5/sunburst/text-to-image` | `openai/gpt-image-2.5/flare/text-to-image` for cheap drafts; any endpoint must be listed in `tools/art/endpoints.json` |
| `quality` | `auto`, `low`, `medium`, `high`, `xhigh`, `max` | `high` | Sent explicitly wherever the endpoint takes it |
| `dither` | `none`, `ordered` | `none` | Default dithering for every sprite (4×4 Bayer, applied before quantizing) |
| `sprites` | array | required | One entry per sprite, below |
| `notes`, `_anything` | | | Ignored; any other unknown key is an error, so typos are caught |

Each sprite:

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `id` | `[a-z0-9]` words joined by single `_` | required | Unique; the output file is `sprites/<id>.png` |
| `prompt` | string | required | What this sprite shows; the style comes first |
| `size` | `[w, h]` integers, 1–4096 | required | The sprite's size in art pixels |
| `background` | `transparent`, `opaque` | `transparent` | `opaque` only for backdrops and cards |
| `parts` | `{name: [x, y, w, h]}` | `{}` | Named sub-sprites cut from the finished sprite. Rectangles are in art pixels, origin top-left, inside `size`; names follow the id rule. Each is written as `sprites/<id>__<name>.png` (two underscores) |
| `anchor` | `[x, y]` (numbers, art pixels, origin top-left, inside the sprite) or a named point | the sprite's `align` | The pivot a game places the sprite by; written to `sprites.json` as `[x, y]` |
| `align` | `top_left`, `top_center`, `top_right`, `center_left`, `center`, `center_right`, `bottom_left`, `bottom_center`, `bottom_right` | `bottom_center` | Where a fitted transparent sprite sits inside `size`; named anchors use the same names (`bottom_center` of 80 × 32 is `[40, 32]`) |
| `tile` | bool | `false` | One segment is generated, scaled to the sprite's height and repeated across its width |
| `mirror` | bool | `false` | With `tile`: every second copy is flipped, so edges match. Needs `tile: true` |
| `dither` | `none`, `ordered` | the top-level `dither` | Per-sprite override |

Prompts describe original designs only: no brand names, logos, real insignia, flags or existing characters (BRIEF 3.10). Say what you want to keep simple: "flat colors, hard edges, no anti-aliasing, single subject filling the frame, no text".

### Request sizes and aspect limits

fal's GPT Image 2.5 endpoints take custom sizes whose sides are multiples of 16, with 655,360 to 8,294,400 pixels, at most 3840 px per side and at most 3:1 (`tools/art/endpoints.json`). `generate.mjs` requests each sprite once, at the valid size whose aspect is nearest the sprite's (about 1 megapixel, never more than 1536 × 864 worth of pixels so the base price holds). Sprites between 1:3 and 3:1 keep their aspect within 1 %. A sprite beyond 3:1 is requested at 3:1 and listed by `--dry-run` as outside the limits: make it a `tile: true` strip (one segment within 3:1, repeated) or give it a narrower `size` and repeat it in code with `ParallaxStrip`.

## Generating

```
node tools/art/generate.mjs --game=<id> [--only=<ids>] [--dry-run] [--budget=<usd>] [--reroll=<ids>]
     [--select=<sprite id>:<request id>] [--mock=<url>] [--root=<dir>] [--concurrency=<n>] [--json]
```

- `--only=a,b` processes just those sprites (the rest of the manifest is untouched).
- `--dry-run` prints the plan and contacts nothing (no key needed): each sprite's request size, aspect error in % (`request aspect / sprite aspect − 1`), estimate, status (`new`, `cached`, `recoverable`, `reroll`), the total, whether the budget would stop the run, and the sprites outside the endpoint limits. `--json` prints the same plan as JSON.
- An unchanged input (same endpoint and full input: prompt with style, size, background, quality, format) returns the cached result for free. Change the prompt to get a different picture.
- `--reroll=a,b` skips the cache and the 24-hour reuse and pays for new results of those sprites.
- `--select=<sprite>:<request id>` (repeatable or comma list) only edits the manifest: it marks that result as the sprite's selected one.
- `--concurrency=<n>` (default 4) requests in flight; `--poll-ms`, `--timeout-s` tune polling.
- Exit codes: 0 done, 1 some sprites failed (details on stderr and in the manifest), 2 usage or art.json error (every problem listed), 3 budget stop, 4 refused by the art lock.

Per sprite, a run tries the free paths first: the local cache; a stored image URL or an unfinished request from an earlier run (resumed, not paid again); then fal's request history (Recovery). Only then does it pay: submit to `https://queue.fal.run/<endpoint>`, poll the returned `status_url`, fetch `response_url`, download `images[0].url` into `.art_cache/<id>/<request id>.png`.

### Drafts on flare

Flare is cheaper and fine for checking style, palette and silhouettes. Set `"endpoint": "openai/gpt-image-2.5/flare/text-to-image"`, run with `--only=<a few ids>`, pixelate, look at the PNGs at 3–4×, fix prompts and palette, then set the endpoint back to sunburst and run the full pass. Because the endpoint is part of the input, a sprite drafted on flare gets a new sunburst request in the full pass, and that newer result becomes selected. To keep a draft that passed review, leave its id out of `--only` on the sunburst run (or `--select` it afterwards).

### Selection: which result pixelate uses

Every request is a row in `assets/<id>/art_manifest.json`; exactly one usable (`"status": "ok"`) row per sprite has `"selected": true`, and `pixelate.gd` uses only that one.

- A run selects, for each sprite it processes, the result for the sprite's current input: a new paid result, a recovered one, or the cached one. So the newest result wins by default, and returning to an earlier prompt or endpoint selects its cached result again.
- "Newest" means the newest request. A paid result that is newer than the cached one (say a `--reroll` whose download failed) is recovered by the next run and selected, without paying again. An unfinished newer request gets one status check; until fal has finished it, the cached result is used and the request stays recoverable.
- `--select=<sprite>:<request id>` picks any usable result (`"selected_by": "user"`). A later run that only finds the cache keeps that choice; a new or recovered result for the sprite replaces it (fetching an image that was already fine again, after a cache wipe, does not). If the chosen result's raw image is missing from `.art_cache` (a fresh clone), the next run that includes the sprite fetches it again from its stored image URL for free. If that fetch fails, the choice is no longer usable for now: the run warns and selects the usable result it has instead, so `pixelate.gd` never skips the sprite for it, and marks the choice `"reselect": true`. Each later run that includes the sprite fetches it again for free and selects it as soon as that works. `--select` also accepts a paid result whose image is not fetched yet (`download_failed` with an image URL): it is marked the same way and selected by the next run that fetches it. A new or recovered result for the sprite replaces a waiting choice.
- `pixelate.gd` warns when the selected result no longer matches `art.json` (another endpoint, prompt or background), for example a flare draft that is still selected after you switched to sunburst, and uses it anyway.

### The manifest

`assets/<id>/art_manifest.json` (commit it):

```json
{
  "version": 1,
  "game": "tank",
  "updated_at": "2026-10-21T12:00:00.000Z",
  "spend": { "total_usd": 4.13, "estimated_usd": 4.13, "billed_usd": 0, "paid_requests": 59 },
  "requests": [
    {
      "sprite": "hull_citadel",
      "endpoint": "openai/gpt-image-2.5/sunburst/text-to-image",
      "input": { "prompt": "<style> <prompt>", "image_size": { "width": 1728, "height": 480 }, "background": "transparent",
                 "quality": "high", "num_images": 1, "output_format": "png" },
      "request_id": "…", "status": "ok", "source": "generated", "paid": true,
      "estimated_usd": 0.07, "billed_usd": null,
      "created_at": "…", "submitted_at": "…", "completed_at": "…", "downloaded_at": "…",
      "status_url": "…", "response_url": "…", "image_url": "https://v3.fal.media/…",
      "cache": ".art_cache/tank/<request id>.png", "width": 1728, "height": 480, "bytes": 812345, "sha256": "…",
      "selected": true, "selected_by": "run", "error": null
    }
  ]
}
```

`status` is `ok`, `submitted` (in flight or interrupted), `timeout`, `result_failed`, `download_failed` (all four recoverable without paying again), `failed` (fal reported an error; counted as paid to stay conservative), `submit_unconfirmed` (the submit's answer was lost, so there is no request id yet; counted as paid, and the next run adopts the request from fal's history when it is there) or `submit_failed` (fal answered with an error, or the request never left this machine; nothing taken, not counted). `"reselect": true` marks a `--select` choice that waits for its image to be fetched. `source` is `generated` or `recovered`. fal documents no per-request cost today; when a response carries one (`cost_total` at the top level or under `billing` or `metrics`, as `mock_fal` sends it), it lands in `billed_usd`.

### Recovering a paid result after a failed download

fal bills when a request completes, even if the image download fails afterwards. Nothing is lost:

1. The failed run records the request (`"status": "download_failed"`, its `request_id` and `image_url`) and exits 1.
2. Run the same command again. Before paying for any sprite, `generate.mjs` re-fetches stored image URLs, resumes unfinished requests from their `status_url`, and, if the manifest lost the record (a crash, a deleted file), asks fal's request history: `GET https://api.fal.ai/v1/models/requests/by-endpoint?endpoint_id=<endpoint>&expand=payloads&status=success&start=<24 hours ago>`. A successful request from the last 24 hours whose `json_input` matches the sprite's input is downloaded from its `json_output.images[0].url` and recorded with `"source": "recovered"`.
3. If the history can't be read (the key lacks `models:requests:read`, or fal is down), the run warns and pays. `--reroll` skips this reuse on purpose.

A stored `image_url` or `status_url` keeps working for as long as fal keeps the request; the history lookup covers the last 24 hours only, so rerun soon after a failure. Older results are still visible in fal's dashboard.

If fal ever hands back an image URL outside its own domains (`*.fal.run`, `*.fal.ai`, `*.fal.media`), `generate.mjs` refuses to fetch it, stops paying for further sprites (each would be paid and unfetchable), names the sprites it did not pay for and exits 1. The paid request stays in the manifest as `download_failed` with its URL; tell a human, because allowing another host is a change to the art lock's host list in `tools/art/lib/fal.mjs`.

## Pixelating

```
tools/godot.sh --headless --path . -s tools/art/pixelate.gd -- --game=<id> [--only=<ids>] [--root=<dir>]
```

(`tools/godot.ps1` takes the same arguments.) Run `tools/godot.sh --headless --path . --import` once after cloning so the class cache knows `ArtPixelate`. For each sprite of `art.json` with a selected result, `pixelate.gd`:

1. trims transparent margins (alpha ≥ 16/255 counts as content);
2. never stretches: a transparent sprite is fitted inside `size` keeping its aspect and padded with transparency toward `align`; an opaque sprite is scaled to cover `size` and centre-cropped; a `tile: true` sprite is scaled to the sprite's height and repeated across its width, alternating flipped copies with `mirror: true`;
3. downsamples with area averaging (exact pixel coverage, premultiplied alpha, so edges don't go dark);
4. thresholds alpha (≥ 0.5 opaque, else transparent) and quantizes every opaque pixel to the nearest palette color in Oklab, with no dithering unless `dither: "ordered"`;
5. cuts `parts` from the finished sprite;
6. writes `assets/<id>/sprites/<sprite id>.png`, `<sprite id>__<part>.png` and `sprites.json`, only when the bytes change, and removes the `<sprite id>__*.png` files (with their `.import`) of parts that `art.json` no longer lists, so a renamed part leaves no stale, off-palette PNG behind. Re-runs are byte-identical.

Every pixel of the output is a palette color at alpha 255 or `(0, 0, 0, 0)`, which is what a game's palette test (F4.1) checks. Sprites without a selected result are skipped with a warning (exit 0), so you can pixelate drafts before the full pass; a selected result whose raw PNG is missing from `.art_cache` is an error (run `generate.mjs` again: it re-downloads for free).

`sprites.json` lists every sprite that has a PNG: `file`, `size`, `anchor` (`[x, y]` in art pixels), `align`, `background`, `tile`, `mirror`, `parts` (`{name: {file, rect}}`) and `source` (`request_id`, `endpoint`).

The pixel import preset (filter off, mipmaps off, lossless) has one mechanism (OWNERSHIP C36): `project.godot`'s `[importer_defaults] texture` imports every new PNG lossless (`compress/mode` 0) without mipmaps, so pixelate writes plain PNGs and no `.import` files. `pixelate.gd` checks those defaults first (`PixelImportPreset.check_project_defaults()`) and stops with an error if they are missing. Filtering is per CanvasItem in Godot 4: `PixelViewport` draws with nearest filtering, and `PixelImportPreset.apply_to(item)` sets nearest on a CanvasItem outside it. After pixelating, run `tools/godot.sh --headless --path . --import` and commit the PNGs with the `.import` files Godot writes. (`ArtPixelate.import_preset_mode = ArtPixelate.IMPORT_WRITE_FILE` is an opt-in for a sprite folder that must pin the preset in its own `.import` files; nothing uses it by default.)

## Animating by parts

Draw a sprite per moving part instead of frames (BRIEF 3.10), and let the `world2d` kit move them (see `docs/GAME_SDK.md` for each helper's exact properties):

- `SpinningPart` rotates gears, flywheels, crank arms and reels from a signed speed −1…1 (negative runs backwards). Generate the part face-on, centred, with `"anchor": "center"`, and place it at the hub measured on the parent sprite.
- `SlidingPart` moves pistons (reciprocating) and scrolls chains and track links (continuous).
- `ParallaxStrip` scrolls backdrop strips at a factor per layer; `mirror_alternate` tiles normal and flipped copies so edges match (the same idea as `tile` + `mirror` at generation time).
- `PaletteSwap` recolors a sprite's key ramp to a player's color: keep the key colors (for example a 2-color red ramp) in the palette and use them only where the player color belongs.
- `SpriteWobble` waves fish tails, bait balls and water by shader.
- Draw extra frames only where parts can't do the job; code-draw anything under 16 px or made of lines (barrels, rods, chains, needles) in palette colors.

Measure pivots and mounting points (muzzles, hubs, wheel lines, room rects) on the pixelated sprites and keep them in your game's own rig file; `sprites.json` gives each sprite's size and anchor.

## Worked example

A fishing game wants a marlin whose tail wobbles, a tiled reef and a backdrop sky:

```json
{
  "palette": ["#14203a", "#2a5aa8", "#6fb4ff", "#d8f0ff", "#f4e3b1", "#e8743b", "#c0392b", "#7b1f1f", "#2e8b57", "#ffd34d"],
  "style": "Clean 16-bit pixel art game sprite, side view, bright cheerful tropical colors, flat colors, dark navy outline, chunky readable shapes, single subject centered and filling the frame, no text, letters, numbers, logos, emblems or flags.",
  "endpoint": "openai/gpt-image-2.5/flare/text-to-image",
  "sprites": [
    { "id": "fish_marlin", "prompt": "a blue marlin in exact profile facing left, tail at the right edge, bill and sail", "size": [64, 22], "anchor": "center",
      "parts": { "body": [0, 0, 48, 22], "tail": [48, 0, 16, 22] } },
    { "id": "reef_front", "prompt": "colorful corals and rocks on sand, flat at both ends", "size": [416, 18], "tile": true, "mirror": true },
    { "id": "sky", "prompt": "a bright tropical sky with soft clouds", "size": [320, 120], "background": "opaque" }
  ]
}
```

1. `node tools/art/generate.mjs --game=fishing --dry-run`: the marlin is requested at 1536 × 528 and the sky at 1664 × 624 (aspect error +0.00 % each); `reef_front` (23.11:1) is listed as outside the limits and requested at 1776 × 592 (3:1) as a tile segment. Total $0.1641 on flare ($0.0547 each).
2. Draft: `node tools/art/generate.mjs --game=fishing --only=fish_marlin --budget=0.5`, then `tools/godot.sh --headless --path . -s tools/art/pixelate.gd -- --game=fishing --only=fish_marlin` and look at `assets/fishing/sprites/fish_marlin.png` at 4×.
3. Final: set `endpoint` to sunburst and run `node tools/art/generate.mjs --game=fishing --budget=<10 − spent>`. The sunburst marlin is newer, so it is selected. Pixelate everything, then import.
4. A sprite fails review (say the marlin faces right): sharpen its prompt ("…facing LEFT, head on the left…") and run with `--only=fish_marlin`; the old result stays in the manifest, unselected. To go back to it: `--select=fish_marlin:<its request id>`.
5. In the view: `fish_marlin__body.png` as a Sprite2D, `fish_marlin__tail.png` with `SpriteWobble`; `reef_front.png` (416 × 18, already tiled with flips) in a `ParallaxStrip`; `sky.png` as the back layer.
6. Credit the art as generated with OpenAI's GPT Image 2.5 through fal in `docs/credits.d/<id>.md`.

## Tests and the mock

- `tools/art/mock_fal/server.mjs` (tests only) mirrors the queue API (submit, status, result, cancel), image downloads (deterministic PNGs honouring size and background), the by-endpoint history with payloads, billed amounts, and failure injection (model errors, 500s per route, download failures after billing, dropped connections). Its admin API (`/_admin/state`, `/_admin/config`, `/_admin/requests`, `/_admin/reset`) drives tests. `node tools/art/mock_fal/server.mjs --port=0` prints `MOCK_FAL_PORT=<port>`.
- `node --test` in `tools/art`: sizing, prices, art.json validation, PNG codec, the mock, generation end to end, the manifest, recovery, the budget stop, `--dry-run`, the art lock (refusal before any socket opens), key secrecy, and identical behaviour with `WATTLANDS_NO_NETWORK_INTEGRATIONS` set or unset. Every test starts `generate.mjs` without `WATTLANDS_ALLOW_ART` and without a real `FAL_KEY`, and passes `--mock` except the refusal cases.
- GUT: `tools/godot.sh --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/art -ginclude_subdirs -gexit -gjunit_xml_file=build/junit_art.xml` (ArtPixelate: fit, cover, tile, mirror, align, area averaging, Oklab quantization to the palette only, parts, determinism, run_game, the import preset).
- End to end: `node tools/art/pixelate_e2e.mjs` (after the import and GUT, never from inside Godot) generates a fixture game against the mock and pixelates it twice through the wrapper.
