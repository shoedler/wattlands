# world2d: the 2D pixel-art kit

Helpers for 2D games (BRIEF 3.9, 3.10). Every 2D game runs in a `PixelViewport`, and Workout scrolls its world on `ParallaxStrip`s. The shipped games draw most of their own art (Diesel Domestiques and Castellum Rotae bake theirs, Turbo Reel draws from grids), so the parts and shaders below are there for a new game to start from: no shipped game uses `SpinningPart`, `SlidingPart`, `ScrollingChain`, `PaletteSwap`, `SpriteWobble` or `DitherDissolve` today. Every class is documented in its script; this page is the overview. Run `addons/wattlands/world2d/demo.tscn` to see all of them at once.

## PixelViewport

The GameHost puts a 2D game's `make_view()` Node2D into a `PixelViewport` at the game's `pixel_base` (640 x 360 for Turbo Reel and the template, 960 x 540 for Diesel Domestiques, Castellum Rotae and Workout) with `set_game_view(view)`.

- The view renders into a SubViewport of exactly `pixel_base`, with nearest filtering, no texture repeat and 2D pixel snapping. Everything inside is drawn at art resolution, so rotated parts keep the chunky look.
- The frame is scaled by a whole number of device pixels (`integer_scale()`: 2 in a 1280 x 720 window, 3 at 1920 x 1080, 4 at 2560 x 1440) and centred. The rest of the control is `bar_color` (black).
- The HUD maps art-pixel rects with `art_rect_to_screen(Rect2i)`. The result is in the viewport's canvas coordinates, which a HudLayer Control uses directly. Re-lay out on `layout_changed`. `art_scale()` is canvas units per art pixel. It is 3.0 for every 16:9 window, because the canvas is always 1920 x 1080.
- `screen_to_art()` maps a mouse position back to art pixels. `capture()` returns the art-resolution frame, and `capture_scaled()` the frame at its on-screen size. In headless runs both return a blank frame in `background_color`.

## Parts: animate by parts, not frames

All parts take `speed` from -1 to 1, clamped. A negative speed runs the part backwards. `drive(value, full_scale)` sets `speed = value / full_scale`, so `drive(cadence, 120)` gives `speed = cadence / 120`. Each part advances in `tick(dt)`, which `_process` calls while `auto_process` is on. A view that drives everything from sim time turns `auto_process` off.

| Class | Use | Main properties |
| --- | --- | --- |
| `SpinningPart` | Gears, flywheels, cranks, reels, wheels. It rotates itself, so child sprites turn with it, or set `texture` to draw a centred sprite. A positive speed turns clockwise. | `max_rpm`, `ratio` (negative for a meshing gear), `phase_deg`, `inertia_s`, `snap_steps` |
| `SlidingPart` | `RECIPROCATE` moves pistons, rods and cradles between 0 and `travel_px` along `axis`. `SCROLL` moves track links by `max_px_s` and wraps at `wrap_px`. | `mode`, `axis`, `travel_px`, `max_cps`, `max_px_s`, `wrap_px`, `phase`, `rest_position` |
| `ScrollingChain` | Code-drawn chains, belts and track loops. `set_loop(a, ra, b, rb)` builds a belt round two sprockets and `set_belt(centers, radii)` one round any number of wheels (a tank track), clockwise, so a positive speed matches a `SpinningPart`. | `max_px_s`, `pitch_px`, `link_px`, `width_px`, `color_a`, `color_b`, `points`, `closed` |
| `ParallaxStrip` | Backdrop strips that repeat a texture across the view. Set `world_x` every frame; the strip scrolls by `world_x * factor`. `mirror_alternate` alternates flipped copies so the edges meet. | `texture`, `factor` (>= 0; 0 for sky, > 1 for foreground debris), `mirror_alternate`, `drift_px_s`, `align_bottom`, `cover_width` |

## Shaders

- **PaletteSwap** (`palette_swap.gdshader`): replaces up to 8 key colors with swap colors. `PaletteSwap.apply_slot(sprite, keys, slot_index)` swaps a light-to-dark key ramp for that slot's ramp, built from `Wl.slot_look()`. `ramp_from(color, steps)` builds any ramp. `swap_color()` and `swap_image()` do the same swap on the CPU.
- **SpriteWobble** (`sprite_wobble.gdshader`): a pixel-snapped sine displacement with a falloff.
  - `SpriteWobble.fish_tail(sprite)` keeps the body still and swings the tail.
  - `SpriteWobble.water(sprite)` sways each row.
  - `set_time(mat, t)` drives the wave from sim time instead of `TIME`.
  - `displacement()` is the CPU reference, for attaching things to a wobbling part.

- **DitherDissolve** (`dither_dissolve.gdshader`): fades an effect in or out through a 4 x 4 ordered-dither pattern, so the sprite keeps hard pixel edges instead of turning translucent. Use `DitherDissolve.apply(sprite)` to add it, then `set_amount(mat, 0..1)` to fade.

All three shaders keep `modulate`, so white sprites can still be tinted at runtime.

## Pixel import preset

New PNGs import lossless and without mipmaps through the project's texture importer defaults. Filtering is set per CanvasItem, and PixelViewport makes nearest the default inside game views.

- `PixelImportPreset.validate_import_file(png)` and `is_import_ok(png)` check a sprite's `.import` file.
- `write_import_file(png)` pins the preset in that file.
- `validate_texture(tex)` checks a loaded texture.
- `apply_to(item)` sets nearest filtering on a CanvasItem outside a PixelViewport, such as a menu or a picker card.

## PixelPainter

Procedural pixel images, used by the demo and handy for code-drawn parts and placeholder art:

- `from_rows()`: a sprite from text rows plus a palette.
- `gear()`, `disc()` and `silhouette()`.
- `vertical_gradient()`, with an ordered dither.
- `hill_heights()`, which tiles seamlessly.
- `bands()`.
- `line_pixels(a, b)`: the pixels of a Bresenham line, both ends included, as an `Array[Vector2i]`. The help overlay's arrows and Turbo Reel's fishing line use it.

## PixelFont

`PixelFont.hang(path, cap_rows, space_advance)` makes a pixel font from Godot's Image Font importer ready to set text on its art grid. The importer hangs a glyph by half its cell, which draws the caps under a Label's box and the descenders out of it. `hang` hangs every glyph `cap_rows` above the baseline and makes the space `space_advance` glyph px wide. It does this once per path, because the resource is shared, so the first call's numbers stand. A Font that is not a FontFile comes back as loaded, and a path that holds no Font gives null.

For a game's own HUD Controls on the art grid, see `HudArtControl` and `HudArtDraw` in `addons/wattlands/ui/hud/` (`docs/GAME_SDK.md` section 18).

## Performance

Each part is one CanvasItem with a few draw calls, and a ParallaxStrip batches its tiles. Everything in the view is drawn once into the SubViewport and shown with one textured quad.
