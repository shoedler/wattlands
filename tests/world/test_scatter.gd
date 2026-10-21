extends GutTest
## MultiMeshScatter (BRIEF 3.9; OWNERSHIP W3D2): same seed same transforms, exclusion zones,
## spacing, scale ranges, heights, custom data, the buffer layout and path placement.


func _config(seed: int = 7) -> Dictionary:
	return {
		"seed": seed,
		"count": 200,
		"area": Rect2(-100, -100, 200, 200),
		"exclude": [Rect2(-20, -20, 40, 40), Vector3(60, 60, 15.0)],
		"min_spacing": 2.0,
		"scale": Vector2(0.5, 1.5),
		"tilt_deg": 5.0,
		"colors": PackedColorArray([Color.RED, Color.GREEN]),
		"color_jitter": 0.1,
	}


func _xforms(result: Dictionary) -> Array[Transform3D]:
	return result["transforms"]


func test_same_seed_same_transforms() -> void:
	var a := MultiMeshScatter.generate(_config(7))
	var b := MultiMeshScatter.generate(_config(7))
	assert_eq(_xforms(a), _xforms(b))
	assert_eq(a["colors"], b["colors"])
	assert_eq(_xforms(a).size(), 200)


func test_different_seed_different_transforms() -> void:
	var a := MultiMeshScatter.generate(_config(7))
	var b := MultiMeshScatter.generate(_config(8))
	assert_ne(_xforms(a), _xforms(b))


func test_inside_area_and_outside_exclusions() -> void:
	var r := MultiMeshScatter.generate(_config())
	for p: Vector2 in (r["positions"] as PackedVector2Array):
		assert_true(Rect2(-100, -100, 200, 200).has_point(p))
		assert_false(Rect2(-20, -20, 40, 40).has_point(p), "outside the rect exclusion")
		assert_gt(p.distance_to(Vector2(60, 60)), 15.0, "outside the circle exclusion")


func test_polygon_area_and_polygon_exclusion() -> void:
	var tri := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(0, 100)])
	var hole := PackedVector2Array([Vector2(5, 5), Vector2(30, 5), Vector2(5, 30)])
	var r := MultiMeshScatter.generate({"seed": 3, "count": 80, "polygon": tri, "exclude": [hole]})
	assert_eq(_xforms(r).size(), 80)
	for p: Vector2 in (r["positions"] as PackedVector2Array):
		assert_true(Geometry2D.is_point_in_polygon(p, tri))
		assert_false(Geometry2D.is_point_in_polygon(p, hole))


func test_min_spacing() -> void:
	var r := MultiMeshScatter.generate(_config())
	var pts: PackedVector2Array = r["positions"]
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			assert_true(pts[i].distance_to(pts[j]) >= 2.0)


func test_scale_rotation_and_colors() -> void:
	var r := MultiMeshScatter.generate(_config())
	var yaws := {}
	for t: Transform3D in _xforms(r):
		var s := t.basis.get_scale()
		assert_true(s.x >= 0.5 - 0.0001 and s.x <= 1.5 + 0.0001, "scale in range")
		assert_almost_eq(s.x, s.y, 0.0001, "uniform without height jitter")
		yaws[snappedf(t.basis.get_euler().y, 0.5)] = true
	assert_gt(yaws.size(), 5, "random yaw")
	for c: Color in (r["colors"] as PackedColorArray):
		assert_true(c.r > 0.85 or c.g > 0.85, "picked from the palette, jittered")


func test_height_function_and_offset() -> void:
	var hf := func(x: float, z: float) -> float: return x * 0.1 - z * 0.2
	var r := MultiMeshScatter.generate({"seed": 1, "count": 20, "area": Rect2(0, 0, 50, 50), "height": hf, "y_offset": -0.5, "yaw": false})
	for t: Transform3D in _xforms(r):
		assert_almost_eq(t.origin.y, t.origin.x * 0.1 - t.origin.z * 0.2 - 0.5, 0.0001)
		assert_eq(t.basis, Basis(), "no yaw, tilt or scale")


func test_custom_random() -> void:
	var r := MultiMeshScatter.generate({"seed": 5, "count": 30, "area": Rect2(0, 0, 10, 10), "custom": "random"})
	var distinct := {}
	for c: Color in (r["customs"] as PackedColorArray):
		assert_true(c.r >= 0.0 and c.r < 1.0)
		distinct[snappedf(c.r, 0.01)] = true
	assert_gt(distinct.size(), 5, "phases differ")


func test_crowded_area_places_fewer() -> void:
	var r := MultiMeshScatter.generate({"seed": 2, "count": 100, "area": Rect2(0, 0, 10, 10), "min_spacing": 4.0, "max_attempts": 500})
	assert_lt(_xforms(r).size(), 100)


func test_missing_area_is_an_error() -> void:
	var r := MultiMeshScatter.generate({"seed": 1, "count": 5})
	assert_push_error("area")
	assert_eq(_xforms(r).size(), 0)


func test_unknown_key_warns() -> void:
	MultiMeshScatter.generate({"seed": 1, "count": 1, "area": Rect2(0, 0, 1, 1), "bogus": 1})
	assert_push_warning("bogus")


func test_node_scatter_and_cpu_copy() -> void:
	var lp := LowPolyMesh.new().add_cone(1.0, 4.0, 5, Color.DARK_GREEN)
	var mm: MultiMeshScatter = autofree(MultiMeshScatter.new())
	mm.setup(lp.build(), 300)
	assert_eq(mm.capacity(), 300)
	assert_eq(mm.visible_count(), 0)
	var cfg := _config()
	var placed := mm.scatter(cfg)
	assert_eq(placed, 200)
	assert_eq(mm.visible_count(), 200)
	assert_eq(mm.multimesh.visible_instance_count, 200)
	var ref := MultiMeshScatter.generate(cfg)
	assert_eq(mm.instance_transform(17), _xforms(ref)[17])
	assert_eq(mm.instance_color(17), (ref["colors"] as PackedColorArray)[17])
	assert_eq(mm.transforms().size(), 200)


func test_scatter_clamps_to_capacity() -> void:
	var mm: MultiMeshScatter = autofree(MultiMeshScatter.new())
	mm.setup(BoxMesh.new(), 10)
	var placed := mm.scatter({"seed": 1, "count": 50, "area": Rect2(0, 0, 100, 100)})
	assert_push_warning("capacity")
	assert_eq(placed, 10)


func test_set_instances_each_frame() -> void:
	var mm: MultiMeshScatter = autofree(MultiMeshScatter.new())
	mm.setup(BoxMesh.new(), 8, false, true)
	assert_true(mm.multimesh.use_colors, "custom data brings colors (Compatibility)")
	var xs: Array[Transform3D] = []
	for i in 5:
		xs.append(Transform3D(Basis(), Vector3(i, 0, 0)))
	mm.set_instances(xs, PackedColorArray(), PackedColorArray([Color(0.25, 0, 0, 0)]))
	assert_eq(mm.visible_count(), 5)
	assert_eq(mm.instance_transform(3).origin, Vector3(3, 0, 0))
	assert_eq(mm.instance_color(3), Color.WHITE, "missing colors default to white")
	assert_eq(mm.instance_custom(0).r, 0.25)
	assert_eq(mm.instance_custom(1), Color(0, 0, 0, 0))
	xs.resize(2)
	mm.set_instances(xs)
	assert_eq(mm.visible_count(), 2)
	for i in 12:
		xs.append(Transform3D())
	mm.set_instances(xs)
	assert_push_warning("capacity")
	assert_eq(mm.visible_count(), 8)


func test_set_instances_before_setup_is_an_error() -> void:
	var mm: MultiMeshScatter = autofree(MultiMeshScatter.new())
	var xs: Array[Transform3D] = [Transform3D()]
	mm.set_instances(xs)
	assert_push_error("setup")


func test_pack_buffer_layout() -> void:
	var xf := Transform3D(Basis.from_euler(Vector3(0.1, 0.2, 0.3)).scaled(Vector3(1, 2, 3)), Vector3(4, 5, 6))
	var xs: Array[Transform3D] = [Transform3D(), xf]
	var buf := MultiMeshScatter.pack_buffer(xs, PackedColorArray([Color.RED, Color(0.1, 0.2, 0.3, 0.4)]), PackedColorArray([Color.BLACK, Color(0.5, 0.6, 0.7, 0.8)]), 3, true, true)
	assert_eq(buf.size(), 3 * 20)
	var o := 20
	var expect := [xf.basis.x.x, xf.basis.y.x, xf.basis.z.x, xf.origin.x,
		xf.basis.x.y, xf.basis.y.y, xf.basis.z.y, xf.origin.y,
		xf.basis.x.z, xf.basis.y.z, xf.basis.z.z, xf.origin.z,
		0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]
	for k in 20:
		assert_almost_eq(buf[o + k], float(expect[k]), 0.0001, "float %d" % k)
	for k in 20:
		assert_eq(buf[40 + k], 0.0, "unused capacity is zero")
	var plain := MultiMeshScatter.pack_buffer(xs, PackedColorArray(), PackedColorArray(), 2, false, false)
	assert_eq(plain.size(), 24)
	assert_almost_eq(plain[12 + 3], 4.0, 0.0001)


func test_along_path_spacing_and_scroll() -> void:
	var path := PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10)])
	var a := MultiMeshScatter.along_path(path, 2.0)
	assert_eq(a.size(), 11, "0, 2, ... 20 m")
	assert_eq(a[0].origin, Vector3.ZERO)
	assert_almost_eq(a[6].origin.z, 2.0, 0.0001, "round the corner")
	assert_almost_eq(a[1].basis.z.dot(Vector3(-1, 0, 0)), 1.0, 0.0001, "faces along the path (-Z forward)")
	var b := MultiMeshScatter.along_path(path, 2.0, 0.5)
	assert_almost_eq(b[0].origin.x, 0.5, 0.0001, "offset scrolls forward")
	var c := MultiMeshScatter.along_path(path, 2.0, 2.5)
	assert_almost_eq(c[0].origin.x, 0.5, 0.0001, "and wraps every spacing")
	assert_eq(MultiMeshScatter.along_path(PackedVector3Array([Vector3.ZERO]), 1.0).size(), 0)
	var loop := MultiMeshScatter.along_path(PackedVector3Array([Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 4)]), 1.0, 0.0, true)
	assert_eq(loop.size(), 14, "closed: 4 + 4 + 5.66 m")


func test_walk_bob_material() -> void:
	var mat := MultiMeshScatter.walk_bob_material(0.1, 2.5, 0.2)
	assert_not_null(mat.shader)
	assert_eq(mat.shader.get_mode(), Shader.MODE_SPATIAL)
	assert_eq(mat.get_shader_parameter("bob_height"), 0.1)
	assert_eq(mat.get_shader_parameter("steps_hz"), 2.5)
	MultiMeshScatter.set_walk_time(mat, 4.0)
	assert_eq(mat.get_shader_parameter("use_engine_time"), false)
	assert_eq(mat.get_shader_parameter("time_s"), 4.0)


func test_is_excluded_kinds() -> void:
	var ex: Array = [Rect2(0, 0, 1, 1), Vector3(5, 5, 1), PackedVector2Array([Vector2(10, 10), Vector2(12, 10), Vector2(10, 12)])]
	assert_true(MultiMeshScatter.is_excluded(Vector2(0.5, 0.5), ex))
	assert_true(MultiMeshScatter.is_excluded(Vector2(5.5, 5.5), ex))
	assert_true(MultiMeshScatter.is_excluded(Vector2(10.5, 10.5), ex))
	assert_false(MultiMeshScatter.is_excluded(Vector2(20, 20), ex))
