extends GutTest
## LowPolyMesh (BRIEF 3.9; OWNERSHIP W3D1, W3D5, W3D6, W3D7): primitive vertex counts, flat
## normals that face outward, vertex colors and the shared material, merging per material,
## ground darkening, the vertex haze fallback, and the world3d demo scene.

const RED := Color(0.8, 0.2, 0.2)


## [normals, positions, colors] of every surface of the built mesh.
func _arrays(lp: LowPolyMesh) -> Array:
	var mesh := lp.build()
	var normals := PackedVector3Array()
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for i in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(i)
		normals.append_array(a[Mesh.ARRAY_NORMAL])
		verts.append_array(a[Mesh.ARRAY_VERTEX])
		cols.append_array(a[Mesh.ARRAY_COLOR])
	return [normals, verts, cols]


## Every triangle's three normals are equal (flat) and perpendicular to its edges.
func _assert_flat(lp: LowPolyMesh) -> void:
	var a := _arrays(lp)
	var n: PackedVector3Array = a[0]
	var v: PackedVector3Array = a[1]
	assert_eq(n.size(), v.size())
	var bad := 0
	for i in range(0, v.size(), 3):
		if not (n[i].is_equal_approx(n[i + 1]) and n[i].is_equal_approx(n[i + 2])):
			bad += 1
		elif absf(n[i].dot(v[i + 1] - v[i])) > 0.001 or absf(n[i].dot(v[i + 2] - v[i])) > 0.001:
			bad += 1
	assert_eq(bad, 0, "flat normals")


## Every normal of a convex primitive points away from `center`.
func _assert_outward(lp: LowPolyMesh, center: Vector3) -> void:
	var a := _arrays(lp)
	var n: PackedVector3Array = a[0]
	var v: PackedVector3Array = a[1]
	var bad := 0
	for i in range(0, v.size(), 3):
		var c := (v[i] + v[i + 1] + v[i + 2]) / 3.0
		if n[i].dot(c - center) <= 0.0:
			bad += 1
	assert_eq(bad, 0, "outward faces")


func test_box() -> void:
	var lp := LowPolyMesh.new().add_box(Vector3(2, 4, 6), RED)
	assert_eq(lp.triangle_count(), 12)
	assert_eq(lp.vertex_count(), 36)
	assert_eq(lp.aabb(), AABB(Vector3(-1, -2, -3), Vector3(2, 4, 6)))
	_assert_flat(lp)
	_assert_outward(lp, Vector3.ZERO)


func test_box_top_color() -> void:
	var lp := LowPolyMesh.new().add_box(Vector3.ONE, RED, Transform3D.IDENTITY, Color.WHITE)
	var a := _arrays(lp)
	var n: PackedVector3Array = a[0]
	var c: PackedColorArray = a[2]
	for i in n.size():
		if n[i].y > 0.9:
			assert_eq(c[i], Color.WHITE)
		else:
			assert_eq(c[i], RED)


func test_transformed_box_faces_outward() -> void:
	var xf := Transform3D(Basis(Vector3(1, 1, 0).normalized(), 0.7).scaled(Vector3(1, 2, 0.5)), Vector3(5, 1, -3))
	var lp := LowPolyMesh.new().add_box(Vector3(2, 2, 2), RED, xf)
	_assert_flat(lp)
	_assert_outward(lp, xf.origin)


func test_cylinder_prism_and_cone() -> void:
	var cyl := LowPolyMesh.new().add_cylinder(1.0, 1.0, 2.0, 8, RED)
	assert_eq(cyl.triangle_count(), 8 * 2 + 2 * (8 - 2))
	_assert_flat(cyl)
	_assert_outward(cyl, Vector3.ZERO)
	var prism := LowPolyMesh.new().add_cylinder(1.0, 0.5, 2.0, 3, RED, Transform3D.IDENTITY, false)
	assert_eq(prism.triangle_count(), 6, "no caps")
	var cone := LowPolyMesh.new().add_cone(1.0, 3.0, 6, RED)
	assert_eq(cone.triangle_count(), 6 + 4)
	_assert_flat(cone)
	_assert_outward(cone, Vector3(0, -0.5, 0))
	var aabb := cone.aabb()
	assert_almost_eq(aabb.position.y, -1.5, 0.0001)
	assert_almost_eq(aabb.end.y, 1.5, 0.0001)


func test_wedge() -> void:
	var lp := LowPolyMesh.new().add_wedge(Vector3(2, 1, 3), RED)
	assert_eq(lp.triangle_count(), 8)
	_assert_flat(lp)
	_assert_outward(lp, Vector3(0, -0.2, -0.5))


func test_low_sphere() -> void:
	var lp := LowPolyMesh.new().add_sphere(2.0, 3, 6, RED)
	assert_eq(lp.triangle_count(), 6 + 6 + 6 * 2)
	_assert_flat(lp)
	_assert_outward(lp, Vector3.ZERO)
	for v: Vector3 in lp.vertices():
		assert_almost_eq(v.length(), 2.0, 0.0001)


func test_ring() -> void:
	var lp := LowPolyMesh.new().add_ring(3.0, 0.5, 1.0, 12, RED)
	assert_eq(lp.triangle_count(), 12 * 8)
	_assert_flat(lp)
	var a := _arrays(lp)
	var n: PackedVector3Array = a[0]
	var v: PackedVector3Array = a[1]
	var bad := 0
	for i in range(0, v.size(), 3):
		var c := (v[i] + v[i + 1] + v[i + 2]) / 3.0
		var radial := Vector3(c.x, c.y, 0.0)
		var r := radial.length()
		var expected := Vector3.ZERO
		if absf(c.z) > 0.49:
			expected = Vector3(0, 0, signf(c.z))
		elif r > 2.75:
			expected = radial.normalized()
		else:
			expected = -radial.normalized()
		if n[i].dot(expected) <= 0.5:
			bad += 1
	assert_eq(bad, 0, "rim faces out, inner faces in, sides face along the axle")


func test_plane_and_grid() -> void:
	var plane := LowPolyMesh.new().add_plane(Vector2(4, 2), RED)
	assert_eq(plane.triangle_count(), 2)
	var a := _arrays(plane)
	for n: Vector3 in (a[0] as PackedVector3Array):
		assert_almost_eq(n.y, 1.0, 0.0001, "faces up")
	var hf := func(x: float, z: float) -> float: return x * 0.1 + z * 0.05
	var grid := LowPolyMesh.new().add_grid(Vector2(8, 6), Vector2i(4, 3), hf, RED)
	assert_eq(grid.triangle_count(), 4 * 3 * 2)
	for v: Vector3 in grid.vertices():
		assert_almost_eq(v.y, v.x * 0.1 + v.z * 0.05, 0.0001)
	var g := _arrays(grid)
	for n: Vector3 in (g[0] as PackedVector3Array):
		assert_gt(n.y, 0.0, "terrain faces up")


func test_grid_color_fn() -> void:
	var cf := func(center: Vector3, normal: Vector3) -> Color: return Color.GREEN if center.x < 0.0 else Color.BLUE
	var hf := func(_x: float, _z: float) -> float: return 0.0
	var grid := LowPolyMesh.new().add_grid(Vector2(4, 4), Vector2i(2, 2), hf, RED, cf)
	var verts := grid.vertices()
	var cols := grid.colors()
	for i in range(0, verts.size(), 3):
		var c := (verts[i] + verts[i + 1] + verts[i + 2]) / 3.0
		assert_eq(cols[i], Color.GREEN if c.x < 0.0 else Color.BLUE)


func test_vertex_colors_and_material() -> void:
	var lp := LowPolyMesh.new().add_box(Vector3.ONE, RED)
	var mesh := lp.build()
	assert_eq(mesh.get_surface_count(), 1)
	var cols: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	assert_eq(cols.size(), 36)
	for c: Color in cols:
		assert_almost_eq(c.r, RED.r, 0.01)
		assert_almost_eq(c.g, RED.g, 0.01)
	var mat := mesh.surface_get_material(0) as StandardMaterial3D
	assert_not_null(mat)
	assert_eq(mat, LowPolyMesh.vertex_color_material(), "one shared material")
	assert_true(mat.vertex_color_use_as_albedo)
	assert_null(mat.albedo_texture, "no textures")
	assert_null(mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV], "no UVs")


func test_append_merges_per_surface() -> void:
	var glow := StandardMaterial3D.new()
	var prop := LowPolyMesh.new()
	prop.add_box(Vector3.ONE, RED)
	prop.use_surface(&"glow", glow).add_box(Vector3(0.5, 0.5, 0.5), Color.YELLOW)
	var scene := LowPolyMesh.new()
	for i in 10:
		scene.append(prop, Transform3D(Basis(), Vector3(i * 2.0, 0, 0)))
	assert_eq(scene.surface_keys(), [LowPolyMesh.DEFAULT_SURFACE, &"glow"] as Array[StringName])
	assert_eq(scene.triangle_count(), 10 * 24)
	var mesh := scene.build()
	assert_eq(mesh.get_surface_count(), 2, "one surface (draw call) per material")
	assert_eq(mesh.surface_get_material(1), glow)
	assert_eq(scene.material_for(&"glow"), glow)
	assert_almost_eq(scene.aabb().end.x, 18.5, 0.0001)


func test_append_mirrored_keeps_faces_outward() -> void:
	var prop := LowPolyMesh.new().add_box(Vector3(1, 2, 3), RED)
	var scene := LowPolyMesh.new()
	var mirror := Transform3D(Basis().scaled(Vector3(-1, 1, 1)), Vector3(10, 0, 0))
	scene.append(prop, mirror)
	_assert_outward(scene, Vector3(10, 0, 0))
	var moved := LowPolyMesh.new().add_box(Vector3(1, 2, 3), RED)
	moved.transform(mirror)
	_assert_outward(moved, Vector3(10, 0, 0))


func test_darken_near_ground() -> void:
	var lp := LowPolyMesh.new().add_box(Vector3(1, 4, 1), Color.WHITE, Transform3D(Basis(), Vector3(0, 2, 0)))
	lp.darken_near_ground(0.0, 1.0, 0.4)
	var verts := lp.vertices()
	var cols := lp.colors()
	for i in verts.size():
		if verts[i].y < 0.001:
			assert_almost_eq(cols[i].r, 0.6, 0.0001, "base darkened by the strength")
		elif verts[i].y > 3.999:
			assert_almost_eq(cols[i].r, 1.0, 0.0001, "top untouched")
	assert_almost_eq(LowPolyMesh.darkening_factor(0.0, 0.0, 2.0, 0.5), 0.5, 0.0001)
	assert_almost_eq(LowPolyMesh.darkening_factor(1.0, 0.0, 2.0, 0.5), 0.75, 0.0001)
	assert_almost_eq(LowPolyMesh.darkening_factor(5.0, 0.0, 2.0, 0.5), 1.0, 0.0001)
	assert_almost_eq(LowPolyMesh.darkening_factor(-1.0, 0.0, 2.0, 0.5), 0.5, 0.0001, "below ground clamps")
	var prev := 0.0
	for k in 11:
		var f := LowPolyMesh.darkening_factor(k * 0.2, 0.0, 2.0, 0.5)
		assert_true(f >= prev, "monotonic")
		prev = f


func test_apply_haze_blends_with_distance() -> void:
	var lp := LowPolyMesh.new()
	lp.add_box(Vector3.ONE, RED, Transform3D(Basis(), Vector3(0, 0, -50)))
	lp.add_box(Vector3.ONE, RED, Transform3D(Basis(), Vector3(0, 0, -300)))
	var haze := Color("#9bb3c7")
	lp.apply_haze(Vector3.ZERO, 120.0, 240.0, haze, 1.0)
	var verts := lp.vertices()
	var cols := lp.colors()
	for i in verts.size():
		if verts[i].z > -100.0:
			assert_eq(cols[i], RED, "near: unchanged")
		else:
			assert_almost_eq(cols[i].b, haze.b, 0.0001, "far: hazed")
	assert_almost_eq(LowPolyMesh.haze_amount(Vector3(0, 50, -180), Vector3.ZERO, 120.0, 240.0), 0.5, 0.0001, "horizontal distance")
	assert_gt(LowPolyMesh.haze_amount(Vector3(0, 500, -180), Vector3.ZERO, 120.0, 240.0, false), 0.99)


func test_tint_clear_and_empty() -> void:
	var lp := LowPolyMesh.new().add_box(Vector3.ONE, Color.WHITE)
	lp.tint(Color(0.5, 0.5, 0.5))
	assert_almost_eq(lp.colors()[0].r, 0.5, 0.0001)
	lp.clear()
	assert_true(lp.is_empty())
	assert_eq(lp.build().get_surface_count(), 0)


func test_make_instance_casts_shadows() -> void:
	var mi: MeshInstance3D = autofree(LowPolyMesh.new().add_box(Vector3.ONE, RED).make_instance("Box"))
	assert_eq(mi.name, &"Box")
	assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	assert_eq(mi.mesh.get_surface_count(), 1)


# --- Demo scene (W3D6) --------------------------------------------------------------------

func test_demo_scene_runs_headless() -> void:
	var scene: PackedScene = load("res://addons/wattlands/world3d/demo.tscn")
	assert_not_null(scene)
	var demo: Node3D = scene.instantiate()
	add_child_autofree(demo)
	await wait_process_frames(5)
	assert_not_null(demo.get("sky"))
	var rig: MiniatureCameraRig = demo.get("rig")
	assert_not_null(rig)
	assert_true(rig.camera.current)
	var scenery := demo.get_node("Scenery") as MeshInstance3D
	assert_not_null(scenery)
	assert_eq(scenery.mesh.get_surface_count(), 1, "the static scene merges into one surface")
	var trees: Array = demo.get("trees")
	assert_eq(trees.size(), 3)
	var total := 0
	for t: MultiMeshScatter in trees:
		total += t.visible_count()
	assert_gt(total, 500, "hundreds of scattered props, three draw calls")
	var marchers: MultiMeshScatter = demo.get("marchers")
	assert_gt(marchers.visible_count(), 0)
	assert_eq((demo.get("wheels") as Array).size(), 4)
