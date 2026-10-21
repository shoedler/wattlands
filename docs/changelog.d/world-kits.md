### world-kits

- `PixelViewport`: renders a 2D game view at its `pixel_base` with nearest filtering, integer device-pixel scaling and black letterbox bars; `art_rect_to_screen()`, `art_to_screen()`, `screen_to_art()`, `art_scale()` and `layout_changed` for the HUD; headless-safe `capture()` and `capture_scaled()`.
- 2D parts driven by a signed speed signal (-1..1): `SpinningPart` (gears, flywheels, cranks, reels; ratio, phase, inertia, angle snapping), `SlidingPart` (reciprocating pistons and scrolling links), `ScrollingChain` (code-drawn chains and belts round sprockets).
- `ParallaxStrip`: repeating backdrop strips at any factor >= 0 with `mirror_alternate` tiling, drift and vertical placement, scrolled by a world x.
- Shaders with helpers: `PaletteSwap` (key color ramp to a player's slot ramp) and `SpriteWobble` (pixel-snapped sine wobble with falloff; fish-tail and water presets).
- `PixelImportPreset`: checks and writes the lossless, mipmap-free import preset for pixel sprites; `PixelPainter`: procedural pixel sprites (text rows, gears, discs, dithered gradients, tileable hills).
- world3d: `LowPolyMesh` (flat-shaded vertex-colored primitives, merging per material, ground darkening, vertex haze), `MultiMeshScatter` (seeded scatter with exclusions, per-frame instance updates, path placement, walk-bob shader), `MiniatureCameraRig` (high three-quarter view, limited orbit, push-in, decaying shake) and `SkyAmbient` (Compatibility sky, ambient, shadowed sun and depth-fog haze).
- Demo scenes `addons/wattlands/world2d/demo.tscn` and `addons/wattlands/world3d/demo.tscn`, built entirely from procedural art.
