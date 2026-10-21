class_name MultiMeshScatter
extends MultiMeshInstance3D
## Many copies of one mesh in one draw call (BRIEF 3.9 "MultiMesh scatter"; Siege S3:
## ~600 cypress, 400 olive trees and 300 rocks from a fixed seed, one MultiMesh per enemy
## type with a vertex-shader walk bob, route chains). No per-instance nodes.
##
## 1. setup(mesh, capacity, use_colors, use_custom) creates the MultiMesh.
## 2. Static scenery: scatter(config) places instances with a seeded RNG (SeededRng) inside
##    an area or polygon, outside exclusion zones, with scale, yaw, tilt and color jitter.
##    The same config and seed always give the same instances (generate() is the pure part).
## 3. Moving crowds: set_instances(transforms, colors, customs) rewrites every instance in
##    one buffer upload each frame; visible_count hides the unused tail of the capacity.
##
## Per-instance colors multiply the mesh's vertex colors (LowPolyMesh's material uses them);
## per-instance custom data (INSTANCE_CUSTOM in shaders) carries e.g. a walk-bob phase for
## walk_bob_material(). The node keeps a CPU copy of what it uploaded (instance_transform(),
## instance_color(), instance_custom()), which also works headless.
## [codeblock]
## var trees := MultiMeshScatter.new()
## trees.setup(cypress_mesh, 600)
## trees.scatter({"seed": 7, "count": 600, "area": Rect2(-150, -150, 300, 300),
##     "exclude": [Rect2(-40, -30, 80, 60), Vector3(0, 90, 12)],   # fort; a circle x, z, r
##     "min_spacing": 2.0, "scale": Vector2(0.8, 1.3), "height": Callable(terrain, "height_at")})
## add_child(trees)
## [/codeblock]

## Config keys scatter() and generate() accept.
const CONFIG_KEYS: Array[String] = [
	"seed",
	"count",
	"area",
	"polygon",
	"exclude",
	"min_spacing",
	"scale",
	"height_jitter",
	"yaw",
	"tilt_deg",
	"colors",
	"color_jitter",
	"height",
	"y_offset",
	"max_attempts",
	"custom",
]

var _transforms: Array[Transform3D] = []
var _colors: PackedColorArray = PackedColorArray()
var _customs: PackedColorArray = PackedColorArray()


## Create the MultiMesh: `capacity` instances of `mesh` (3D transforms), optionally with
## per-instance colors and custom data. Every instance starts hidden (visible count 0).
## Custom data always comes with colors (white by default): on the Compatibility renderer
## (4.7.2) a MultiMesh with custom data but no colors draws wrong vertex colors.
func setup(mesh: Mesh, capacity: int, use_colors: bool = true, use_custom: bool = false) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = use_colors or use_custom
	mm.use_custom_data = use_custom
	mm.mesh = mesh
	mm.instance_count = maxi(capacity, 0)
	mm.visible_instance_count = 0
	multimesh = mm
	_transforms = []
	_colors = PackedColorArray()
	_customs = PackedColorArray()


## How many instances the MultiMesh holds.
func capacity() -> int:
	return multimesh.instance_count if multimesh != null else 0


## How many instances are shown (the first n).
func visible_count() -> int:
	return _transforms.size()


## Place instances from `config` (see generate()) and show them. Returns how many were
## placed (fewer than "count" when the area is too crowded; a warning says so).
func scatter(config: Dictionary) -> int:
	var cfg := config.duplicate()
	if not cfg.has("count"):
		cfg["count"] = capacity()
	if int(cfg["count"]) > capacity():
		push_warning(
			(
				"MultiMeshScatter: count %d exceeds capacity %d; clamped"
				% [int(cfg["count"]), capacity()]
			)
		)
		cfg["count"] = capacity()
	var result := generate(cfg)
	var xforms: Array[Transform3D] = result["transforms"]
	set_instances(xforms, result["colors"], result["customs"])
	if xforms.size() < int(cfg["count"]):
		push_warning(
			(
				"MultiMeshScatter: placed %d of %d (area too crowded)"
				% [xforms.size(), int(cfg["count"])]
			)
		)
	return xforms.size()


## Show `transforms` (at most capacity()), with optional per-instance colors and custom data
## (each either empty or one per transform). One buffer upload; call it every frame for
## moving instances.
func set_instances(
	transforms: Array[Transform3D],
	colors: PackedColorArray = PackedColorArray(),
	customs: PackedColorArray = PackedColorArray()
) -> void:
	if multimesh == null:
		push_error("MultiMeshScatter: set_instances() before setup()")
		return
	var n := mini(transforms.size(), capacity())
	if transforms.size() > capacity():
		push_warning(
			(
				"MultiMeshScatter: %d transforms for capacity %d; extra dropped"
				% [transforms.size(), capacity()]
			)
		)
	_transforms = transforms.slice(0, n)
	_colors = PackedColorArray()
	_customs = PackedColorArray()
	for i in n:
		_colors.append(colors[i] if i < colors.size() else Color.WHITE)
		_customs.append(customs[i] if i < customs.size() else Color(0, 0, 0, 0))
	multimesh.buffer = pack_buffer(
		_transforms, _colors, _customs, capacity(), multimesh.use_colors, multimesh.use_custom_data
	)
	multimesh.visible_instance_count = n


## The transform uploaded for instance i (CPU copy).
func instance_transform(i: int) -> Transform3D:
	return _transforms[i] if i >= 0 and i < _transforms.size() else Transform3D.IDENTITY


func instance_color(i: int) -> Color:
	return _colors[i] if i >= 0 and i < _colors.size() else Color.WHITE


func instance_custom(i: int) -> Color:
	return _customs[i] if i >= 0 and i < _customs.size() else Color(0, 0, 0, 0)


## Every uploaded transform (a copy).
func transforms() -> Array[Transform3D]:
	return _transforms.duplicate()


## Seeded placement, pure (no node needed). Config keys (all optional except an area):
## - "seed": int (0); "count": int (instances wanted)
## - "area": Rect2 in the XZ plane (position = (min x, min z)), or "polygon":
##   PackedVector2Array (x, z) to place inside; with both, a point must be in both
## - "exclude": Array of Rect2 (XZ), PackedVector2Array polygons, or Vector3(x, z, radius)
##   circles where nothing is placed
## - "min_spacing": float, minimum distance between instances (0 = none)
## - "scale": Vector2(min, max) uniform scale (default 1..1); "height_jitter": float, extra
##   random Y scale fraction (0.1 = up to +-10%)
## - "yaw": bool, random rotation about Y (default true); "tilt_deg": max random lean
## - "colors": PackedColorArray to pick from per instance (default white); "color_jitter":
##   float, random brightness variation (+-)
## - "height": Callable(x: float, z: float) -> float ground height; "y_offset": float
## - "custom": "random" fills custom data with 4 random 0..1 values (e.g. a walk-bob phase
##   in .r); anything else leaves it zero
## - "max_attempts": int (default count * 30)
## Returns {"transforms": Array[Transform3D], "colors": PackedColorArray,
## "customs": PackedColorArray, "positions": PackedVector2Array (x, z)}.
static func generate(config: Dictionary) -> Dictionary:
	for key: Variant in config:
		if not CONFIG_KEYS.has(str(key)):
			push_warning("MultiMeshScatter: unknown config key '%s'" % key)
	var rng := SeededRng.make(int(config.get("seed", 0)))
	var count := maxi(int(config.get("count", 0)), 0)
	var has_area := config.has("area")
	var area: Rect2 = config.get("area", Rect2())
	var polygon: PackedVector2Array = config.get("polygon", PackedVector2Array())
	if not has_area and polygon.size() >= 3:
		area = _polygon_bounds(polygon)
		has_area = true
	var no_transforms: Array[Transform3D] = []
	var out := {
		"transforms": no_transforms,
		"colors": PackedColorArray(),
		"customs": PackedColorArray(),
		"positions": PackedVector2Array(),
	}
	if not has_area or area.size.x <= 0.0 or area.size.y <= 0.0:
		if count > 0:
			push_error("MultiMeshScatter: generate() needs an 'area' Rect2 or a 'polygon'")
		return out
	var excludes: Array = config.get("exclude", [])
	var spacing := maxf(float(config.get("min_spacing", 0.0)), 0.0)
	var scale_range: Vector2 = config.get("scale", Vector2.ONE)
	var height_jitter := float(config.get("height_jitter", 0.0))
	var random_yaw := bool(config.get("yaw", true))
	var tilt := deg_to_rad(float(config.get("tilt_deg", 0.0)))
	var palette: PackedColorArray = config.get("colors", PackedColorArray())
	var color_jitter := float(config.get("color_jitter", 0.0))
	var height_fn: Callable = config.get("height", Callable())
	var y_offset := float(config.get("y_offset", 0.0))
	var random_custom := str(config.get("custom", "")) == "random"
	var max_attempts := int(config.get("max_attempts", count * 30))
	var xforms: Array[Transform3D] = []
	var cols := PackedColorArray()
	var customs := PackedColorArray()
	var positions := PackedVector2Array()
	var grid := {}
	var attempts := 0
	while xforms.size() < count and attempts < max_attempts:
		attempts += 1
		var p := Vector2(
			area.position.x + rng.randf() * area.size.x, area.position.y + rng.randf() * area.size.y
		)
		if polygon.size() >= 3 and not Geometry2D.is_point_in_polygon(p, polygon):
			continue
		if is_excluded(p, excludes):
			continue
		if spacing > 0.0 and _too_close(p, spacing, grid):
			continue
		var s := lerpf(scale_range.x, scale_range.y, rng.randf())
		var sy := s * (1.0 + (rng.randf() * 2.0 - 1.0) * height_jitter)
		var yaw := rng.randf() * TAU if random_yaw else 0.0
		var lean_dir := rng.randf() * TAU
		var lean := rng.randf() * tilt
		var basis := Basis(Vector3.UP, yaw)
		if lean > 0.0:
			basis = Basis(Vector3(cos(lean_dir), 0.0, sin(lean_dir)), lean) * basis
		basis = basis * Basis.from_scale(Vector3(s, sy, s))
		var y := y_offset + (float(height_fn.call(p.x, p.y)) if height_fn.is_valid() else 0.0)
		xforms.append(Transform3D(basis, Vector3(p.x, y, p.y)))
		var c := Color.WHITE
		if palette.size() > 0:
			c = palette[rng.randi_range(0, palette.size() - 1)]
		if color_jitter > 0.0:
			var f := 1.0 + (rng.randf() * 2.0 - 1.0) * color_jitter
			c = Color(c.r * f, c.g * f, c.b * f, c.a)
		cols.append(c)
		if random_custom:
			customs.append(Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
		else:
			customs.append(Color(0, 0, 0, 0))
		positions.append(p)
		if spacing > 0.0:
			_grid_add(p, spacing, grid)
	out["transforms"] = xforms
	out["colors"] = cols
	out["customs"] = customs
	out["positions"] = positions
	return out


## True when the XZ point lies in any exclusion (Rect2, polygon or Vector3(x, z, r) circle).
static func is_excluded(p: Vector2, excludes: Array) -> bool:
	for e: Variant in excludes:
		if e is Rect2:
			if (e as Rect2).has_point(p):
				return true
		elif e is Vector3:
			var c: Vector3 = e
			if p.distance_to(Vector2(c.x, c.y)) <= c.z:
				return true
		elif e is PackedVector2Array:
			if Geometry2D.is_point_in_polygon(p, e):
				return true
		else:
			push_warning("MultiMeshScatter: unsupported exclusion %s" % type_string(typeof(e)))
	return false


## Transforms along a polyline every `spacing` meters, starting `offset` meters in (wrapped,
## so increasing it scrolls the instances along the path: Siege's route chains). Each
## instance faces along the path (-Z forward). Open path; `closed` joins the ends.
static func along_path(
	points: PackedVector3Array,
	spacing: float,
	offset: float = 0.0,
	closed: bool = false,
	scale: float = 1.0
) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var pts := points.duplicate()
	if closed and pts.size() > 2:
		pts.append(pts[0])
	if pts.size() < 2 or spacing <= 0.0:
		return out
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
	var length := cum[cum.size() - 1]
	if length <= 0.0:
		return out
	var d := fposmod(offset, spacing)
	var seg := 0
	while d <= length:
		while seg < pts.size() - 2 and cum[seg + 1] < d:
			seg += 1
		var a := pts[seg]
		var b := pts[seg + 1]
		var seg_len := cum[seg + 1] - cum[seg]
		var t := (d - cum[seg]) / seg_len if seg_len > 0.0 else 0.0
		var pos := a.lerp(b, t)
		var fwd := (b - a).normalized()
		var basis := (
			Basis.looking_at(fwd, Vector3.UP) if absf(fwd.dot(Vector3.UP)) < 0.999 else Basis()
		)
		out.append(Transform3D(basis.scaled(Vector3.ONE * scale), pos))
		d += spacing
	return out


## The MultiMesh buffer for `transforms` (Godot's per-instance layout: 12 floats of the
## 3 x 4 transform row by row, then 4 color floats if use_colors, then 4 custom floats if
## use_custom), padded with zero instances up to `capacity`.
static func pack_buffer(
	transforms: Array[Transform3D],
	colors: PackedColorArray,
	customs: PackedColorArray,
	capacity: int,
	use_colors: bool,
	use_custom: bool
) -> PackedFloat32Array:
	var stride := 12 + (4 if use_colors else 0) + (4 if use_custom else 0)
	var buf := PackedFloat32Array()
	buf.resize(stride * maxi(capacity, 0))
	buf.fill(0.0)
	for i in mini(transforms.size(), capacity):
		var o := i * stride
		var t := transforms[i]
		buf[o + 0] = t.basis.x.x
		buf[o + 1] = t.basis.y.x
		buf[o + 2] = t.basis.z.x
		buf[o + 3] = t.origin.x
		buf[o + 4] = t.basis.x.y
		buf[o + 5] = t.basis.y.y
		buf[o + 6] = t.basis.z.y
		buf[o + 7] = t.origin.y
		buf[o + 8] = t.basis.x.z
		buf[o + 9] = t.basis.y.z
		buf[o + 10] = t.basis.z.z
		buf[o + 11] = t.origin.z
		var k := o + 12
		if use_colors:
			var c := colors[i] if i < colors.size() else Color.WHITE
			buf[k] = c.r
			buf[k + 1] = c.g
			buf[k + 2] = c.b
			buf[k + 3] = c.a
			k += 4
		if use_custom:
			var u := customs[i] if i < customs.size() else Color(0, 0, 0, 0)
			buf[k] = u.r
			buf[k + 1] = u.g
			buf[k + 2] = u.b
			buf[k + 3] = u.a
	return buf


## A material for walking crowds: vertex colors times instance colors, and a vertical bob
## of `bob_height_m` at `steps_hz` steps per second whose phase comes from INSTANCE_CUSTOM.r
## (0..1), so one MultiMesh of marching figures doesn't move in lockstep. Feet stay planted
## below `plant_below_m` (local y). Call set_walk_time() to drive it from sim time instead
## of TIME.
static func walk_bob_material(
	bob_height_m: float = 0.08, steps_hz: float = 2.0, plant_below_m: float = 0.0
) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://addons/wattlands/world3d/walk_bob.gdshader") as Shader
	mat.set_shader_parameter("bob_height", bob_height_m)
	mat.set_shader_parameter("steps_hz", steps_hz)
	mat.set_shader_parameter("plant_below", plant_below_m)
	return mat


## Drive a walk_bob_material from `t` seconds (deterministic frames).
static func set_walk_time(mat: ShaderMaterial, t: float) -> void:
	mat.set_shader_parameter("use_engine_time", false)
	mat.set_shader_parameter("time_s", t)


static func _polygon_bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p: Vector2 in poly:
		r = r.expand(p)
	return r


static func _cell(p: Vector2, spacing: float) -> Vector2i:
	return Vector2i(floori(p.x / spacing), floori(p.y / spacing))


static func _too_close(p: Vector2, spacing: float, grid: Dictionary) -> bool:
	var c := _cell(p, spacing)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := c + Vector2i(dx, dz)
			if not grid.has(key):
				continue
			for q: Vector2 in grid[key] as PackedVector2Array:
				if p.distance_squared_to(q) < spacing * spacing:
					return true
	return false


static func _grid_add(p: Vector2, spacing: float, grid: Dictionary) -> void:
	var c := _cell(p, spacing)
	var cell: PackedVector2Array = grid.get(c, PackedVector2Array())
	cell.append(p)
	grid[c] = cell
