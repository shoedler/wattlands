# world-kits decisions

## 2026-10-21: PixelViewport scales in device pixels

- Decision: `integer_scale()` is the whole number of device pixels per art pixel, chosen from the window's real size (the root viewport's stretch transform), so every art pixel is exactly k screen pixels. `art_scale()` (added) is the same scale in canvas units, `letterbox_offset()` is in the control's canvas units snapped to whole device pixels, and `art_rect_to_screen()` returns the viewport's canvas coordinates (what a HUD Control uses). Headless runs measure device scale 1, so there `integer_scale() == art_scale()` (3 at 1920 x 1080). `screen_scale_override` pins the device scale for tests and nested viewports.
- Alternatives: pick the integer scale in canvas units (the 1920 x 1080 `canvas_items` base).
- Reason: the window stretches a 1920 x 1080 canvas. Integer scale in canvas units is pixel-perfect only on 16:9 windows of 720p, 1080p and 1440p; at 1366 x 768, 1536 x 864 or 1600 x 900 it gives uneven 2.13x to 2.5x pixels. Device pixels keep "integer scaling to the window" (BRIEF 3.9) true everywhere, with bars instead. A windowed run at 1280 x 720 reports scale 2, art scale 3, no bars.

## 2026-10-21: PixelViewport keeps its SubViewport out of the container's own drawing

- Decision: the frozen stub extends `SubViewportContainer`, which draws direct SubViewport children unscaled at the origin. The SubViewport (nearest default filter, no repeat, 2D transform and vertex snapping, 3D disabled, GUI input off) is a child of an internal `TextureRect` that shows its texture at the integer-scaled, centred rect; `_draw()` fills the bars. A `CanvasLayer` at -128 inside the SubViewport clears it to `background_color`.
- Alternatives: `stretch = true` with `stretch_shrink` (forces the container's size to a multiple of the art size and can't letterbox); rendering the SubViewport at full resolution with `size_2d_override` (rotated sprites would lose their pixel look).
- Reason: keeps the frozen class and gives exact letterboxing with one extra node.

## 2026-10-21: Haze uses Environment depth fog on 4.7.2 Compatibility

- Decision: `SkyAmbient` turns on `Environment` depth fog (`FOG_MODE_DEPTH`, begin 120 m, end 380 m, density 0.55, no sky fog) by default. `SkyAmbient.haze_mesh(lp, camera_origin)` is the one haze helper games call on every `LowPolyMesh`: a no-op while fog is used, `LowPolyMesh.apply_haze()` (vertex colors blended toward the haze color by horizontal distance) when `haze_mode()` is `"vertex"` (forced with `haze_vertex_fallback`, or on an engine without depth fog).
- Alternatives: always blend vertex colors (Siege S3's fallback).
- Reason: a windowed Compatibility render on Godot 4.7.2 (NVIDIA, OpenGL 3.3) showed a red unshaded box 100 m away turn from (1.0, 0.0, 0.0) to (0.58, 0.0, 0.86) with blue depth fog, and to (0.40, 0.0, 0.94) with exponential fog, so fog works there. Fog follows the camera and needs no mesh rebuilds.

## 2026-10-21: SkyAmbient light energies calibrated for Compatibility

- Decision: defaults sun 0.3 (color `#ffeccc`, 48 degrees up, from the front left of a camera looking toward -Z, orthogonal shadows to 400 m) and flat ambient 0.35 (`#d4d9de`), linear tonemap, SSAO, SSIL, SDFGI and glow off.
- Alternatives: physically sensible energies (sun ~1, ambient ~0.5).
- Reason: on 4.7.2 Compatibility the shadowed directional light is added in a separate pass that blends in non-linear space, so sun 0.9 plus ambient 0.5 turned ochre `#c7a15a` ground into `#ffd65f`. With these values a windowed probe measured lit flat ground `#ca9c4c` (the palette color), the same ground in shadow at about half (`#65532d`) and lit marble `#ede1c6` for `#e8e2d4`. The values are plain properties; a Forward+ scene would raise them.

## 2026-10-21: Canvas shaders carry modulate through a varying

- Decision: `palette_swap.gdshader` and `sprite_wobble.gdshader` copy `COLOR` (vertex color times modulate) into a varying in `vertex()` and multiply their own texture sample by it.
- Alternatives: `COLOR = sample * COLOR` in `fragment()`.
- Reason: in Godot 4 `fragment()`'s input `COLOR` already includes the texture sample, so that applies the texture twice; a windowed probe showed a swapped blue at (0.0, 0.08, 0.16) instead of (0.0, 0.45, 0.70). With the varying the four slot colors render exactly.

## 2026-10-21: PaletteSwap uses eight separate key and swap uniforms

- Decision: `key_0`..`key_7`, `swap_0`..`swap_7`, `key_count`, `tolerance`; the helper fills them from ramps (light to dark) and builds slot ramps from `Wl.slot_look()`.
- Alternatives: `vec4` uniform arrays; a lookup texture.
- Reason: every value shows in the inspector and `get_shader_parameter()`; 8 keys cover any ramp the games need (Fishing uses 2).

## 2026-10-21: MultiMesh custom data always comes with colors

- Decision: `MultiMeshScatter.setup(..., use_custom = true)` also turns on per-instance colors (white unless given). The walk-bob shader writes `ALBEDO = COLOR.rgb` and, like `StandardMaterial3D` with `vertex_color_is_srgb`, decodes the sRGB vertex colors only when `OUTPUT_IS_SRGB` is false.
- Alternatives: custom data alone; always decoding the vertex colors in the shader.
- Reason: on 4.7.2 Compatibility a MultiMesh with custom data but no colors drew wrong vertex colors (brown figures came out green). Compatibility outputs sRGB (`OUTPUT_IS_SRGB`), so there `COLOR` already matches what `LowPolyMesh`'s `StandardMaterial3D` (vertex color as sRGB albedo) shows, and decoding it again darkened it. The guard keeps walking figures matching static props on a linear renderer too.

## 2026-10-21: PixelViewport also emits `resized` on layout changes at a fixed size

- Decision: when the layout changes while the control keeps its size (the window was resized at the fixed 1920 x 1080 canvas, so only the device scale moved, or `pixel_base` changed), `PixelViewport` emits `resized` after `layout_changed`. A real size change keeps Control's own single `resized`.
- Alternatives: only `layout_changed`, and ask ui-hud to listen to it.
- Reason: the frozen W0 API has no layout signal, so `HudLayer` re-lays out on the control's `resized`. A 1920 x 1080 window shrunk to 1600 x 900 keeps the canvas size but moves the image from scale 3 to scale 2 with a 192 x 108 letterbox; without the extra `resized` the HUD would stay where it was. A windowed 1600 x 900 run reports scale 2, art scale 2.4, offset (192, 108).

## 2026-10-21: LowPolyMesh is a builder of triangle lists per surface

- Decision: primitives append flat, outward-facing triangles (winding fixed by comparing SurfaceTool's normal `(a - c) x (a - b)` with the face's outward direction) to per-surface arrays; `append()` merges meshes per surface key (material), handling mirrored transforms; `build()` runs SurfaceTool with smooth group -1, vertex colors and the shared vertex-color material, one surface per material. Primitives are centred like Godot's primitive meshes; colors are always explicit arguments.
- Alternatives: committing each primitive to SurfaceTool directly; Godot's PrimitiveMesh classes.
- Reason: ground darkening, haze and merging need the vertices before commit; one surface per material is what keeps a Siege-sized scene within ~250 draw calls.

## 2026-10-21: Parts animate from _process by default, tick(dt) for sim-driven views

- Decision: `SpinningPart`, `SlidingPart`, `ScrollingChain`, `ParallaxStrip` drift and `MiniatureCameraRig` advance through `tick(dt)`; `auto_process` (default on) calls it from `_process(delta)`. `ParallaxStrip` scrolls only from the `world_x` the view sets. Shaders use `TIME` unless `set_time()` gives them sim time.
- Alternatives: everything driven from sim time only.
- Reason: views are presentation (they only read state), so render-rate animation is fine and needs no wiring; tests, screenshots and replays drive `tick()` for deterministic frames.

## 2026-10-21: Pixel import preset is validation plus project defaults

- Decision: `PixelImportPreset` documents and checks the preset: required `compress/mode` 0 (lossless) and `mipmaps/generate` false, recommended `detect_3d/compress_to` 0 and no size limit. The project's `[importer_defaults] texture` (lead) gives new PNGs the required half; `write_import_file()` patches or creates a `.import` for folders that need it pinned; filtering is set per CanvasItem (`PixelViewport` makes nearest the default; `apply_to()` elsewhere).
- Alternatives: pixelate writes hand-made `.import` files for every sprite.
- Reason: OWNERSHIP C36; Godot 4 has no per-texture filter setting, and hand-written `.import` files without uids churn on every import.
