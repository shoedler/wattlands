class_name LowPolyMesh
extends RefCounted
## Builds flat-shaded, vertex-colored low-poly meshes from primitives (BRIEF 3.9; Siege S3
## "Every mesh is a GDScript LowPolyMesh: primitives, flat shading, vertex colors and no
## textures. Merge static meshes per material").
##
## A LowPolyMesh collects triangles (positions and colors) per surface, then build() turns
## each surface into one ArrayMesh surface through SurfaceTool with smooth group -1 (flat
## normals). Every surface uses the shared vertex-color material unless use_surface() names
## another, so a whole static scene merges into one draw call per material.
##
## Primitives are centred on the origin like Godot's own primitive meshes (box, cylinder or
## prism with n sides, cone, wedge, low sphere, ring, quad, plane, terrain grid) and placed
## with an optional Transform3D. append() merges another LowPolyMesh (per surface), so
## props are built once in local space and stamped into the scene mesh.
##
## Grounding and haze work on vertex colors, because Compatibility has no SSAO or depth of
## field: darken_near_ground() darkens colors near an object's base, apply_haze() blends
## colors toward a haze color with distance (the fallback when Environment fog is not used;
## see SkyAmbient.haze_mesh()).
## [codeblock]
## var tower := LowPolyMesh.new()
## tower.add_box(Vector3(6, 12, 6), MARBLE, Transform3D(Basis(), Vector3(0, 6, 0)))
## tower.add_cone(4.6, 4.0, 4, TERRACOTTA, Transform3D(Basis(), Vector3(0, 14, 0)))
## tower.darken_near_ground(0.0, 2.5, 0.35)
## var fort := LowPolyMesh.new()
## for p in tower_positions:
##     fort.append(tower, Transform3D(Basis(), p))
## add_child(fort.make_instance("Fort"))   # one draw call
## [/codeblock]

const DEFAULT_SURFACE := &"default"

static var _vertex_color_material: StandardMaterial3D = null


## One surface's triangles (3 vertices and 3 colors per triangle) and its material.
class Surface:
	extends RefCounted

	var verts: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	## null = the shared vertex-color material.
	var material: Material = null

	func add(v: Vector3, c: Color) -> void:
		verts.append(v)
		colors.append(c)

	func add_arrays(v: PackedVector3Array, c: PackedColorArray) -> void:
		verts.append_array(v)
		colors.append_array(c)

	func clear() -> void:
		verts = PackedVector3Array()
		colors = PackedColorArray()


## Surface key -> Surface, in insertion order.
var _surfaces: Dictionary = {}
var _current: StringName = DEFAULT_SURFACE
var _cur: Surface = null


func _init() -> void:
	_ensure_surface(DEFAULT_SURFACE)


# --- Surfaces ----------------------------------------------------------------------------

## Send the following primitives to surface `key`, created with `material` (null: the shared
## vertex-color material; a material given for an existing key replaces its material).
func use_surface(key: StringName, material: Material = null) -> LowPolyMesh:
	_ensure_surface(key)
	if material != null:
		_surface(key).material = material
	_current = key
	_cur = _surface(key)
	return self


## The surface the next primitives go to.
func current_surface() -> StringName:
	return _current


## Surface keys in insertion order (only surfaces that have triangles).
func surface_keys() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: StringName in _surfaces:
		if _surface(key).verts.size() > 0:
			out.append(key)
	return out


## The material a surface is built with.
func material_for(key: StringName) -> Material:
	var surf := _surface(key)
	if surf != null and surf.material != null:
		return surf.material
	return vertex_color_material()


## A copy of a surface's vertex positions (3 per triangle).
func vertices(key: StringName = DEFAULT_SURFACE) -> PackedVector3Array:
	var surf := _surface(key)
	return surf.verts.duplicate() if surf != null else PackedVector3Array()


## A copy of a surface's vertex colors.
func colors(key: StringName = DEFAULT_SURFACE) -> PackedColorArray:
	var surf := _surface(key)
	return surf.colors.duplicate() if surf != null else PackedColorArray()


func vertex_count() -> int:
	var n := 0
	for key: StringName in _surfaces:
		n += _surface(key).verts.size()
	return n


func triangle_count() -> int:
	return floori(vertex_count() / 3.0)


func is_empty() -> bool:
	return vertex_count() == 0


## Remove every triangle (surfaces and materials stay).
func clear() -> void:
	for key: StringName in _surfaces:
		_surface(key).clear()


## Bounds of all vertices (empty AABB when empty).
func aabb() -> AABB:
	var box := AABB()
	var first := true
	for key: StringName in _surfaces:
		for v: Vector3 in _surface(key).verts:
			if first:
				box = AABB(v, Vector3.ZERO)
				first = false
			else:
				box = box.expand(v)
	return box


# --- Primitives (centred on the origin, then transformed by `xform`) ----------------------

## One triangle, given in any order: it faces `outward` (a direction in the same space as
## the points; zero = keep the given order, clockwise seen from the front).
func add_triangle(a: Vector3, b: Vector3, c: Vector3, col: Color, outward: Vector3 = Vector3.ZERO) -> LowPolyMesh:
	_tri(a, b, c, col, outward)
	return self


## A quad a-b-c-d (a convex outline in order) facing `outward`.
func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, outward: Vector3 = Vector3.ZERO) -> LowPolyMesh:
	_quad(a, b, c, d, col, outward)
	return self


## A box of `size`, centred. `top_col` (alpha > 0) colors the top face differently.
func add_box(size: Vector3, col: Color, xform: Transform3D = Transform3D.IDENTITY, top_col: Color = Color(0, 0, 0, 0)) -> LowPolyMesh:
	var h := size * 0.5
	var p: Array[Vector3] = []
	for i in 8:
		var v := Vector3(
			h.x if (i & 1) != 0 else -h.x, h.y if (i & 2) != 0 else -h.y, h.z if (i & 4) != 0 else -h.z
		)
		p.append(xform * v)
	var center := xform.origin
	var top := top_col if top_col.a > 0.0 else col
	_quad_c(p[0], p[1], p[3], p[2], col, center)  # -z
	_quad_c(p[4], p[5], p[7], p[6], col, center)  # +z
	_quad_c(p[0], p[2], p[6], p[4], col, center)  # -x
	_quad_c(p[1], p[3], p[7], p[5], col, center)  # +x
	_quad_c(p[0], p[1], p[5], p[4], col, center)  # -y
	_quad_c(p[2], p[3], p[7], p[6], top, center)  # +y
	return self


## A prism with `sides` sides (a cylinder at 8+), radius_bottom at -height/2 and radius_top
## at +height/2, centred. radius_top 0 makes a cone. Caps unless `caps` is false.
func add_cylinder(radius_bottom: float, radius_top: float, height: float, sides: int, col: Color, xform: Transform3D = Transform3D.IDENTITY, caps: bool = true) -> LowPolyMesh:
	var n := maxi(sides, 3)
	var hy := height * 0.5
	var bottom: Array[Vector3] = []
	var top: Array[Vector3] = []
	for i in n:
		var a := TAU * float(i) / float(n)
		var dir := Vector3(cos(a), 0.0, sin(a))
		bottom.append(xform * (dir * radius_bottom + Vector3(0, -hy, 0)))
		top.append(xform * (dir * radius_top + Vector3(0, hy, 0)))
	var center := xform.origin
	for i in n:
		var j := (i + 1) % n
		if radius_top <= 0.0:
			_tri_c(bottom[i], bottom[j], top[i], col, center)
		elif radius_bottom <= 0.0:
			_tri_c(bottom[i], top[j], top[i], col, center)
		else:
			_quad_c(bottom[i], bottom[j], top[j], top[i], col, center)
	if caps:
		var up := xform.basis * Vector3.UP
		if radius_bottom > 0.0:
			for i in range(1, n - 1):
				_tri(bottom[0], bottom[i], bottom[i + 1], col, -up)
		if radius_top > 0.0:
			for i in range(1, n - 1):
				_tri(top[0], top[i], top[i + 1], col, up)
	return self


## A cone (a pyramid at 3 or 4 sides) of `radius` and `height`, centred.
func add_cone(radius: float, height: float, sides: int, col: Color, xform: Transform3D = Transform3D.IDENTITY) -> LowPolyMesh:
	return add_cylinder(radius, 0.0, height, sides, col, xform)


## A wedge (ramp): a box whose top slopes from full height at -z down to 0 at +z.
func add_wedge(size: Vector3, col: Color, xform: Transform3D = Transform3D.IDENTITY) -> LowPolyMesh:
	var h := size * 0.5
	var b0 := xform * Vector3(-h.x, -h.y, -h.z)
	var b1 := xform * Vector3(h.x, -h.y, -h.z)
	var b2 := xform * Vector3(h.x, -h.y, h.z)
	var b3 := xform * Vector3(-h.x, -h.y, h.z)
	var t0 := xform * Vector3(-h.x, h.y, -h.z)
	var t1 := xform * Vector3(h.x, h.y, -h.z)
	var center := xform * Vector3(0, -h.y * 0.33, -h.z * 0.33)
	_quad_c(b0, b1, b2, b3, col, center)  # bottom
	_quad_c(b0, b1, t1, t0, col, center)  # back (vertical)
	_quad_c(t0, t1, b2, b3, col, center)  # slope
	_tri_c(b0, t0, b3, col, center)       # -x side
	_tri_c(b1, t1, b2, col, center)       # +x side
	return self


## A low-poly UV sphere: `rings` latitude bands (>= 2) and `segments` around (>= 3),
## centred. rings 3, segments 6 gives 24 faceted triangles (bushes, olive crowns, rocks).
func add_sphere(radius: float, rings: int, segments: int, col: Color, xform: Transform3D = Transform3D.IDENTITY) -> LowPolyMesh:
	var nr := maxi(rings, 2)
	var ns := maxi(segments, 3)
	var center := xform.origin
	var grid: Array[Array] = []
	for r in nr + 1:
		var phi := PI * float(r) / float(nr)
		var row: Array[Vector3] = []
		for s in ns:
			var th := TAU * float(s) / float(ns) + (PI / float(ns) if r % 2 == 1 else 0.0)
			row.append(xform * (Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th)) * radius))
		grid.append(row)
	for r in nr:
		var a: Array = grid[r]
		var b: Array = grid[r + 1]
		for s in ns:
			var s1 := (s + 1) % ns
			if r == 0:
				_tri_c(a[0], b[s], b[s1], col, center)
			elif r == nr - 1:
				_tri_c(a[s], a[s1], b[0], col, center)
			else:
				_tri_c(a[s], a[s1], b[s], col, center)
				_tri_c(a[s1], b[s1], b[s], col, center)
	return self


## A flat ring around the local Z axis (a wheel rim): `segments` blocks between radius - width
## and radius, `depth` thick along Z, centred.
func add_ring(radius: float, width: float, depth: float, segments: int, col: Color, xform: Transform3D = Transform3D.IDENTITY) -> LowPolyMesh:
	var n := maxi(segments, 3)
	var r_in := maxf(radius - width, 0.0)
	var hz := depth * 0.5
	var axis := xform.basis * Vector3.BACK
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var d0 := Vector3(cos(a0), sin(a0), 0.0)
		var d1 := Vector3(cos(a1), sin(a1), 0.0)
		var o0f := xform * (d0 * radius + Vector3(0, 0, hz))
		var o1f := xform * (d1 * radius + Vector3(0, 0, hz))
		var o0b := xform * (d0 * radius - Vector3(0, 0, hz))
		var o1b := xform * (d1 * radius - Vector3(0, 0, hz))
		var i0f := xform * (d0 * r_in + Vector3(0, 0, hz))
		var i1f := xform * (d1 * r_in + Vector3(0, 0, hz))
		var i0b := xform * (d0 * r_in - Vector3(0, 0, hz))
		var i1b := xform * (d1 * r_in - Vector3(0, 0, hz))
		var mid := xform.basis * ((d0 + d1).normalized())
		_quad(o0f, o1f, o1b, o0b, col, mid)          # outer
		if r_in > 0.0:
			_quad(i0f, i1f, i1b, i0b, col, -mid)     # inner
		_quad(i0f, i1f, o1f, o0f, col, axis)         # front (+z)
		_quad(i0b, i1b, o1b, o0b, col, -axis)        # back (-z)
	return self


## A horizontal quad of `size` (x, z), facing up, centred.
func add_plane(size: Vector2, col: Color, xform: Transform3D = Transform3D.IDENTITY) -> LowPolyMesh:
	var h := size * 0.5
	var a := xform * Vector3(-h.x, 0, -h.y)
	var b := xform * Vector3(h.x, 0, -h.y)
	var c := xform * Vector3(h.x, 0, h.y)
	var d := xform * Vector3(-h.x, 0, h.y)
	_quad(a, b, c, d, col, xform.basis * Vector3.UP)
	return self


## A terrain grid of `size` (x, z) in `cells`, centred, heights from `height_fn.call(x, z)`
## (local x, z; returns y) and colors from `color_fn.call(center: Vector3, normal: Vector3)`
## per triangle (an invalid Callable uses `col`). Cells split along alternating diagonals.
func add_grid(size: Vector2, cells: Vector2i, height_fn: Callable, col: Color, color_fn: Callable = Callable(), xform: Transform3D = Transform3D.IDENTITY) -> LowPolyMesh:
	var nx := maxi(cells.x, 1)
	var nz := maxi(cells.y, 1)
	var pts: Array[Vector3] = []
	for iz in nz + 1:
		for ix in nx + 1:
			var x := -size.x * 0.5 + size.x * float(ix) / float(nx)
			var z := -size.y * 0.5 + size.y * float(iz) / float(nz)
			var y := float(height_fn.call(x, z)) if height_fn.is_valid() else 0.0
			pts.append(Vector3(x, y, z))
	var up := xform.basis * Vector3.UP
	for iz in nz:
		for ix in nx:
			var p00 := pts[iz * (nx + 1) + ix]
			var p10 := pts[iz * (nx + 1) + ix + 1]
			var p01 := pts[(iz + 1) * (nx + 1) + ix]
			var p11 := pts[(iz + 1) * (nx + 1) + ix + 1]
			var tris: Array[Array] = []
			if (ix + iz) % 2 == 0:
				tris = [[p00, p10, p11], [p00, p11, p01]]
			else:
				tris = [[p00, p10, p01], [p10, p11, p01]]
			for t: Array in tris:
				var a: Vector3 = t[0]
				var b: Vector3 = t[1]
				var c: Vector3 = t[2]
				var tc := col
				if color_fn.is_valid():
					var n := (c - a).cross(b - a).normalized()
					if n.y < 0.0:
						n = -n
					tc = color_fn.call((a + b + c) / 3.0, n)
				_tri(xform * a, xform * b, xform * c, tc, up)
	return self


## Merge another LowPolyMesh, transformed, surface by surface (surfaces and their materials
## are created here as needed).
func append(other: LowPolyMesh, xform: Transform3D = Transform3D.IDENTITY) -> LowPolyMesh:
	if other == null:
		return self
	var flips := xform.basis.determinant() < 0.0
	for key: StringName in other._surfaces:
		var src: Surface = other._surface(key)
		if src.verts.is_empty():
			continue
		_ensure_surface(key)
		var dst := _surface(key)
		if dst.material == null and src.material != null:
			dst.material = src.material
		var n := src.verts.size()
		var tv := PackedVector3Array()
		var tc := PackedColorArray()
		tv.resize(n)
		tc.resize(n)
		for i in range(0, n, 3):
			# A mirroring transform reverses winding; swap two vertices to keep faces out.
			var j1 := i + 2 if flips else i + 1
			var j2 := i + 1 if flips else i + 2
			tv[i] = xform * src.verts[i]
			tv[i + 1] = xform * src.verts[j1]
			tv[i + 2] = xform * src.verts[j2]
			tc[i] = src.colors[i]
			tc[i + 1] = src.colors[j1]
			tc[i + 2] = src.colors[j2]
		dst.add_arrays(tv, tc)
	return self


## Transform every vertex already added.
func transform(xform: Transform3D) -> LowPolyMesh:
	var flips := xform.basis.determinant() < 0.0
	for key: StringName in _surfaces:
		var surf := _surface(key)
		var verts := surf.verts
		var cols := surf.colors
		for i in verts.size():
			verts[i] = xform * verts[i]
		if flips:
			for i in range(0, verts.size(), 3):
				var v := verts[i + 1]
				verts[i + 1] = verts[i + 2]
				verts[i + 2] = v
				var c := cols[i + 1]
				cols[i + 1] = cols[i + 2]
				cols[i + 2] = c
		surf.verts = verts
		surf.colors = cols
	return self


# --- Vertex-color effects ---------------------------------------------------------------

## Darken vertex colors near the ground to ground an object without SSAO (BRIEF 3.9): a
## vertex at `ground_y` gets its color times (1 - strength), one at ground_y + height or
## above keeps it, smoothly in between. Applies to everything added so far, so call it on a
## prop in local space before append().
func darken_near_ground(ground_y: float = 0.0, height: float = 1.0, strength: float = 0.4) -> LowPolyMesh:
	for key: StringName in _surfaces:
		var surf := _surface(key)
		var verts := surf.verts
		var cols := surf.colors
		for i in verts.size():
			var f := darkening_factor(verts[i].y, ground_y, height, strength)
			var c := cols[i]
			cols[i] = Color(c.r * f, c.g * f, c.b * f, c.a)
		surf.colors = cols
	return self


## Blend vertex colors toward `haze_color` with distance from `origin`: 0 at `start_m`,
## `max_blend` at `end_m` and beyond (horizontal distance unless `horizontal` is false).
## The vertex-color haze fallback (Siege S3: hazy blue beyond 120 m); SkyAmbient.haze_mesh()
## calls it only when Environment fog is not used.
func apply_haze(origin: Vector3, start_m: float, end_m: float, haze_color: Color, max_blend: float = 1.0, horizontal: bool = true) -> LowPolyMesh:
	for key: StringName in _surfaces:
		var surf := _surface(key)
		var verts := surf.verts
		var cols := surf.colors
		for i in verts.size():
			var t := haze_amount(verts[i], origin, start_m, end_m, horizontal) * clampf(max_blend, 0.0, 1.0)
			if t > 0.0:
				var c := cols[i]
				var h := c.lerp(haze_color, t)
				cols[i] = Color(h.r, h.g, h.b, c.a)
		surf.colors = cols
	return self


## Multiply every vertex color by `tint` (team tint, damage flash on a merged prop).
func tint(t: Color) -> LowPolyMesh:
	for key: StringName in _surfaces:
		var surf := _surface(key)
		var cols := surf.colors
		for i in cols.size():
			cols[i] = cols[i] * t
		surf.colors = cols
	return self


## The darkening multiplier darken_near_ground() applies at height y.
static func darkening_factor(y: float, ground_y: float, height: float, strength: float) -> float:
	if height <= 0.0:
		return 1.0
	var t := clampf((y - ground_y) / height, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	return lerpf(1.0 - clampf(strength, 0.0, 1.0), 1.0, t)


## The haze blend (0..1) apply_haze() uses at point p.
static func haze_amount(p: Vector3, origin: Vector3, start_m: float, end_m: float, horizontal: bool = true) -> float:
	var d := p - origin
	if horizontal:
		d.y = 0.0
	var dist := d.length()
	if end_m <= start_m:
		return 1.0 if dist >= start_m else 0.0
	return clampf((dist - start_m) / (end_m - start_m), 0.0, 1.0)


# --- Output -------------------------------------------------------------------------------

## Build an ArrayMesh: one surface per non-empty surface key, through SurfaceTool with
## smooth group -1 (flat normals) and vertex colors. Pass `into` to append surfaces to an
## existing ArrayMesh.
func build(into: ArrayMesh = null) -> ArrayMesh:
	var mesh := into if into != null else ArrayMesh.new()
	for key: StringName in surface_keys():
		var verts := _surface(key).verts
		var cols := _surface(key).colors
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)
		for i in verts.size():
			st.set_color(cols[i])
			st.add_vertex(verts[i])
		st.generate_normals()
		st.set_material(material_for(key))
		st.commit(mesh)
		var idx := mesh.get_surface_count() - 1
		mesh.surface_set_name(idx, String(key))
	return mesh


## A MeshInstance3D showing build() (casts shadows).
func make_instance(node_name: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if not node_name.is_empty():
		mi.name = node_name
	mi.mesh = build()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


## The shared material for vertex-colored meshes: vertex color as albedo (sRGB, so palette
## hex colors show as given), fully rough, no specular highlight, back faces culled.
static func vertex_color_material() -> StandardMaterial3D:
	if _vertex_color_material == null:
		var m := StandardMaterial3D.new()
		m.resource_name = "LowPolyVertexColor"
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.albedo_color = Color.WHITE
		m.roughness = 1.0
		m.metallic = 0.0
		m.metallic_specular = 0.0
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.cull_mode = BaseMaterial3D.CULL_BACK
		_vertex_color_material = m
	return _vertex_color_material


## A new unshaded vertex-color material (glows, readouts, the haze-free sky props).
static func unshaded_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


# --- Internals -----------------------------------------------------------------------------

func _ensure_surface(key: StringName) -> void:
	if not _surfaces.has(key):
		_surfaces[key] = Surface.new()
	if key == _current:
		_cur = _surfaces[key]


func _surface(key: StringName) -> Surface:
	return _surfaces.get(key, null) as Surface


## Godot's front faces are clockwise; SurfaceTool's flat normal for (a, b, c) is
## (a - c) x (a - b). Swap b and c when that normal points away from `outward`.
func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color, outward: Vector3) -> void:
	var n := (a - c).cross(a - b)
	_cur.add(a, col)
	if outward != Vector3.ZERO and n.dot(outward) < 0.0:
		_cur.add(c, col)
		_cur.add(b, col)
	else:
		_cur.add(b, col)
		_cur.add(c, col)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, outward: Vector3) -> void:
	_tri(a, b, c, col, outward)
	_tri(a, c, d, col, outward)


## Triangle facing away from a convex primitive's `center`.
func _tri_c(a: Vector3, b: Vector3, c: Vector3, col: Color, center: Vector3) -> void:
	_tri(a, b, c, col, (a + b + c) / 3.0 - center)


func _quad_c(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, center: Vector3) -> void:
	var out := (a + b + c + d) * 0.25 - center
	_tri(a, b, c, col, out)
	_tri(a, c, d, col, out)
