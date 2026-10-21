extends GutTest
## SkyAmbient (BRIEF 3.9; OWNERSHIP W3D4, W3D5): a Compatibility-safe environment (sky,
## flat ambient, SSAO/SSIL/SDFGI/glow off, no depth of field), one shadowed sun from the front
## left, and the haze helper (depth fog on 4.7, vertex blend as the fallback).


func _sky() -> SkyAmbient:
	return autofree(SkyAmbient.new())


func test_builds_environment_and_sun() -> void:
	var s := _sky()
	assert_not_null(s.world_environment)
	assert_eq(s.world_environment.environment, s.environment)
	assert_not_null(s.sun)
	assert_eq(s.environment.background_mode, Environment.BG_SKY)
	assert_true(s.environment.sky.sky_material is ProceduralSkyMaterial)
	assert_eq(s.environment.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR)


func test_no_ssao_or_other_unsupported_effects() -> void:
	var env := _sky().environment
	assert_false(env.ssao_enabled)
	assert_false(env.ssil_enabled)
	assert_false(env.sdfgi_enabled)
	assert_false(env.glow_enabled)
	assert_false(env.volumetric_fog_enabled)


func test_one_shadowed_sun_from_the_front_left() -> void:
	var s := _sky()
	assert_true(s.sun.shadow_enabled)
	assert_eq(s.sun.directional_shadow_mode, DirectionalLight3D.SHADOW_ORTHOGONAL)
	var d := s.sun_direction()
	assert_lt(d.y, 0.0, "shines down")
	assert_gt(d.x, 0.0, "from the left (toward +X)")
	assert_lt(d.z, 0.0, "from the camera side (toward -Z)")
	assert_almost_eq(asin(-d.y), deg_to_rad(s.sun_elevation_deg), 0.0001)


func test_haze_uses_depth_fog_on_this_engine() -> void:
	assert_true(SkyAmbient.environment_fog_supported())
	var s := _sky()
	assert_eq(s.haze_mode(), SkyAmbient.HAZE_FOG)
	assert_true(s.environment.fog_enabled)
	assert_eq(s.environment.fog_mode, Environment.FOG_MODE_DEPTH)
	assert_eq(s.environment.fog_depth_begin, s.haze_begin_m)
	assert_eq(s.environment.fog_depth_end, s.haze_end_m)
	assert_eq(s.haze_begin_m, 120.0, "Siege: haze beyond 120 m")


func test_haze_mesh_is_a_no_op_with_fog() -> void:
	var s := _sky()
	var lp := LowPolyMesh.new().add_box(Vector3.ONE, Color.RED, Transform3D(Basis(), Vector3(0, 0, -500)))
	assert_false(s.haze_mesh(lp, Vector3.ZERO))
	assert_eq(lp.colors()[0], Color.RED)


func test_vertex_fallback() -> void:
	var s := _sky()
	s.haze_vertex_fallback = true
	s.apply()
	assert_eq(s.haze_mode(), SkyAmbient.HAZE_VERTEX)
	assert_false(s.environment.fog_enabled)
	var lp := LowPolyMesh.new()
	lp.add_box(Vector3.ONE, Color.RED, Transform3D(Basis(), Vector3(0, 0, -10)))
	lp.add_box(Vector3.ONE, Color.RED, Transform3D(Basis(), Vector3(0, 0, -1000)))
	assert_true(s.haze_mesh(lp, Vector3.ZERO))
	var verts := lp.vertices()
	var cols := lp.colors()
	for i in verts.size():
		if verts[i].z > -100.0:
			assert_eq(cols[i], Color.RED)
		else:
			assert_ne(cols[i], Color.RED, "far vertices are hazed")
			assert_almost_eq(cols[i].b, lerpf(0.0, s.haze_color.b, s.haze_max), 0.0001)


func test_haze_off() -> void:
	var s := _sky()
	s.haze_enabled = false
	s.apply()
	assert_eq(s.haze_mode(), SkyAmbient.HAZE_OFF)
	assert_false(s.environment.fog_enabled)
	assert_false(s.haze_mesh(LowPolyMesh.new(), Vector3.ZERO))


func test_apply_pushes_properties() -> void:
	var s := _sky()
	s.sky_top_color = Color.DARK_BLUE
	s.ambient_energy = 0.9
	s.sun_energy = 0.7
	s.shadows = false
	s.apply()
	assert_eq(s.sky_material.sky_top_color, Color.DARK_BLUE)
	assert_almost_eq(s.environment.ambient_light_energy, 0.9, 0.0001)
	assert_almost_eq(s.sun.light_energy, 0.7, 0.0001)
	assert_false(s.sun.shadow_enabled)


func test_runs_in_tree() -> void:
	var s := SkyAmbient.new()
	add_child_autofree(s)
	await wait_process_frames(2)
	assert_true(s.world_environment.is_inside_tree())
	assert_true(s.sun.is_inside_tree())


# --- ScreenVignette ------------------------------------------------------------------------------

func test_vignette_darkens_corners_at_most_strength() -> void:
	assert_eq(ScreenVignette.darkening_at(Vector2(0.5, 0.5), 0.12, 0.55), 0.0, "centre untouched")
	assert_almost_eq(ScreenVignette.darkening_at(Vector2(0, 0), 0.12, 0.55), 0.12, 0.0001)
	assert_almost_eq(ScreenVignette.darkening_at(Vector2(1, 1), 0.12, 0.55), 0.12, 0.0001)
	var prev := 0.0
	for k in 11:
		var d := ScreenVignette.darkening_at(Vector2(0.5, 0.5).lerp(Vector2.ZERO, k / 10.0), 0.12, 0.55)
		assert_true(d >= prev and d <= 0.12 + 0.0001)
		prev = d


func test_vignette_layer_sits_under_the_hud() -> void:
	var v: ScreenVignette = autofree(ScreenVignette.new())
	assert_eq(v.layer, -1)
	assert_eq(v.strength, 0.12, "Siege: at most 12%")
	assert_eq(v.rect.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(v.vignette_material.get_shader_parameter("strength"), 0.12)
	v.strength = 2.0
	assert_eq(v.strength, 1.0)
	assert_eq(v.vignette_material.get_shader_parameter("strength"), 1.0)
	var sh := v.vignette_material.shader
	assert_not_null(sh)
	assert_eq(sh.get_mode(), Shader.MODE_CANVAS_ITEM)
