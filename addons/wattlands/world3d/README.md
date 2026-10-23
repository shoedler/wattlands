# world3d: the low-poly miniature kit

Helpers for 3D games on the Compatibility renderer (BRIEF 3.9). Castellum Rotae builds its tabletop fort with them. Every class is documented in its script; this page is the overview. Run `addons/wattlands/world3d/demo.tscn` to see them together.

## LowPolyMesh

LowPolyMesh builds flat-shaded, vertex-colored meshes from primitives, with no textures.

- **Primitives.** `add_box`, `add_cylinder` (an n-sided prism; top radius 0 makes a cone), `add_cone`, `add_wedge`, `add_sphere` (low rings and segments), `add_ring` (wheel rims), `add_plane`, `add_quad`, `add_triangle`, and `add_grid` (terrain from a height function and an optional per-triangle color function). Each one is centred and takes a color and a `Transform3D`. Faces always point outward.
- **Merging.** Build a prop once in local space, then `append(prop, xform)` it into a scene mesh. `build()` makes one ArrayMesh surface per material: SurfaceTool with smooth group -1, plus the shared vertex-color material (`LowPolyMesh.vertex_color_material()`). `use_surface(key, material)` routes glows or other materials to their own surface. A static scene costs one draw call per material.
- **Grounding without SSAO.** Call `darken_near_ground(ground_y, height, strength)` on a prop before `append()`. It darkens vertex colors near the prop's base.
- **Haze fallback.** `apply_haze(origin, start_m, end_m, color, max_blend)` blends vertex colors toward a haze color with horizontal distance. Call it through `SkyAmbient.haze_mesh()`, which does nothing while depth fog is on.
- **Output.** `make_instance(name)` returns a shadow-casting MeshInstance3D. `vertex_count()`, `triangle_count()` and `aabb()` help keep budgets.

## MultiMeshScatter

MultiMeshScatter is a `MultiMeshInstance3D` that draws many copies of one mesh in one draw call, with no per-instance nodes.

- `setup(mesh, capacity, use_colors, use_custom)`. Custom data always comes with colors, because Compatibility needs it.
- `scatter(config)` places instances from a seed. The same seed always gives the same instances. Config keys:
  - `seed`, `count`;
  - `area` (a Rect2 in XZ) and/or `polygon`;
  - `exclude` (Rect2s, polygons, or `Vector3(x, z, radius)` circles);
  - `min_spacing`, `scale` (min, max), `height_jitter`, `yaw`, `tilt_deg`;
  - `colors`, `color_jitter`;
  - `height` (a ground Callable), `y_offset`;
  - `custom: "random"`, for walk-bob phases.
- `set_instances(transforms, colors, customs)` rewrites every instance in one buffer upload. Use it every frame for enemies. `instance_transform()` and the other getters read the node's CPU copy.
- `MultiMeshScatter.along_path(points, spacing, offset)` places instances along a polyline, facing along it. Raising `offset` scrolls them, as Siege's route chains do.
- `MultiMeshScatter.walk_bob_material(bob_height_m, steps_hz, plant_below_m)` returns a spatial shader that bobs each instance by its `INSTANCE_CUSTOM.r` phase.

## MiniatureCameraRig

MiniatureCameraRig gives a high three-quarter view of `target` from `distance`, at `pitch_deg` (42 by default) and `fov_deg` (32 by default).

- **Limits.** Every value is clamped. Yaw stays within `base_yaw_deg +- orbit_limit_deg`, pitch within 25-65 degrees, and FOV within 15-60 degrees.
- **Framing.** `fit_width(width_m)` frames a span. `orbit()` turns the view within the limits.
- **Push-in.** `push_in(from_factor, duration_s)` eases in from farther out and emits `push_in_finished` when done.
- **Shake.** `shake(amplitude_m, duration_s)` is a deterministic, decaying shake in the screen plane. Its amplitude is capped at `max_shake_m` (0.15 m).
- **No depth of field.** The miniature look comes from the narrow FOV seen from far away.

## SkyAmbient

SkyAmbient adds a WorldEnvironment and one DirectionalLight3D:

- a ProceduralSkyMaterial sky;
- flat ambient light;
- a linear tonemap;
- SSAO, SSIL, SDFGI and glow off;
- one warm sun with orthogonal shadows, 48 degrees up, from the front left of a camera that looks toward -Z.

The light energies are calibrated for Compatibility, so lit flat ground shows the palette color: sun 0.3, ambient 0.35 (see `docs/decisions/world-kits.md`). Haze is Environment depth fog from 120 m, which Godot 4.7.2's Compatibility renderer draws. `haze_mode()` reports `"fog"`, `"vertex"` or `"off"`. Call `haze_mesh(lp, camera_origin)` on every LowPolyMesh, and it does the right thing in each mode. Change properties, then call `apply()`.

## ScreenVignette

`ScreenVignette` is a CanvasLayer at -1, so it sits above the 3D view and below the HUD. It darkens the screen corners by `strength`, 0.12 by default, which is Siege's 12% cap.

## Performance (target: 60 fps at 1080p on integrated graphics)

- **Merge static geometry.** Use LowPolyMesh with one surface per material. The demo's terrain, roads, fort and machine frames are about 7,800 triangles in one draw call.
- **Draw crowds and scenery with MultiMesh.** Use one MultiMeshScatter per mesh type. The demo's 660 trees and rocks take three draw calls, and 40 walking figures take one.
- **Light and effects.** Use one shadowed light with orthogonal shadows, and no SSAO, glow or volumetrics.
- **Budget check.** The demo prints a `world3d demo:` line after 30 frames. Windowed at 1080p it reported 22 draw calls and about 62,000 primitives (shadow pass included). That is well under Siege's budget of 250 draw calls and 400,000 triangles.
- **Instance updates.** Moving instances update through one `set_instances()` call per type per frame. Never use one node per enemy.
