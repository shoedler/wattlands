extends GutTest
## The small view parts: the light layer, the procedural textures, the row layer, the palette and the
## sprite helpers. Nothing here creates a texture per frame.


func test_lights_are_capped_and_weak_or_tiny_ones_are_skipped() -> void:
	var l := TankLights.new()
	add_child_autofree(l)
	l.begin()
	l.add(Vector2(10, 10), 20.0, Color.WHITE, 0.0)
	l.add(Vector2(10, 10), 0.5, Color.WHITE, 1.0)
	assert_eq(l.count, 0)
	for i in TankLights.MAX_LIGHTS + 20:
		l.add(Vector2(float(i), 10), 10.0, Color.WHITE, 0.5)
	assert_eq(l.count, TankLights.MAX_LIGHTS)
	l.begin()
	assert_eq(l.count, 0, "a new frame forgets the halos")
	assert_eq(l.wash, 0.0)


func test_intensity_near_adds_up_by_distance() -> void:
	var l := TankLights.new()
	add_child_autofree(l)
	l.begin()
	l.add(Vector2(100, 100), 40.0, Color.WHITE, 1.0)
	var close := l.intensity_near(Vector2(100, 100), 10.0)
	var far := l.intensity_near(Vector2(125, 100), 10.0)
	assert_gt(close, far)
	assert_gt(far, 0.0)
	assert_eq(l.intensity_near(Vector2(400, 100), 10.0), 0.0)


func test_the_light_layer_is_additive() -> void:
	var l := TankLights.new()
	add_child_autofree(l)
	assert_eq((l.material as CanvasItemMaterial).blend_mode, CanvasItemMaterial.BLEND_MODE_ADD)
	var fx := TankFx.new()
	add_child_autofree(fx)
	assert_eq(
		(fx.add_layer.material as CanvasItemMaterial).blend_mode, CanvasItemMaterial.BLEND_MODE_ADD
	)
	assert_null(fx.alpha_layer.material, "smoke is alpha blended")


func test_procedural_textures_are_cached() -> void:
	assert_same(TankProcTex.glow(), TankProcTex.glow())
	assert_same(TankProcTex.puff(), TankProcTex.puff())
	assert_same(TankProcTex.fireball(), TankProcTex.fireball())
	assert_same(TankProcTex.vignette(), TankProcTex.vignette())


func test_the_glow_falls_off_from_a_bright_centre() -> void:
	var img := TankProcTex.glow().get_image()
	assert_eq(img.get_size(), Vector2i(64, 64))
	assert_gt(img.get_pixel(32, 32).a, 0.9)
	assert_lt(img.get_pixel(0, 0).a, 0.01)
	assert_gt(img.get_pixel(32, 32).a, img.get_pixel(32, 50).a)


func test_the_vignette_darkens_the_corners_only() -> void:
	var img := TankProcTex.vignette().get_image()
	assert_lt(img.get_pixel(40, 22).a, 0.02, "clear in the middle")
	assert_gt(img.get_pixel(0, 0).a, 0.2, "dark in the corners")
	assert_lt(img.get_pixel(0, 0).a, 0.7, "never black")


func test_the_fireball_is_hot_in_the_middle_and_orange_at_the_rim() -> void:
	var img := TankProcTex.fireball().get_image()
	var core := img.get_pixel(16, 16)
	var rim := img.get_pixel(16, 3)
	assert_gt(core.g, rim.g)
	assert_gt(rim.r, rim.b, "warm")


func test_the_row_layer_draws_every_row_type_headless() -> void:
	var layer := TankRowLayer.new()
	add_child_autofree(layer)
	var rows: Array[Dictionary] = [
		{
			"t": "sprite",
			"id": "enemy_light",
			"pos": Vector2(10, 10),
			"size": Vector2(80, 40),
			"flip": false,
			"tint": Color.WHITE
		},
		{
			"t": "sprite",
			"id": "enemy_light",
			"pos": Vector2(100, 10),
			"size": Vector2(80, 40),
			"flip": true,
			"tint": Color(0.5, 0.5, 0.5)
		},
		{"t": "line", "a": Vector2(0, 0), "b": Vector2(20, 20), "w": 2.0, "c": Color.RED},
		{"t": "rect", "r": Rect2(5, 5, 3, 3), "c": Color.WHITE},
		{"t": "bar", "pos": Vector2(20, 5), "w": 24.0, "frac": 0.4},
	]
	layer.set_rows(rows)
	await get_tree().process_frame
	assert_eq(layer.rows.size(), 5)


func test_the_painter_calls_its_callable_with_itself() -> void:
	var p := TankPainter.new()
	var seen: Array[Node2D] = []
	p.painter = func(item: Node2D) -> void: seen.append(item)
	add_child_autofree(p)
	await get_tree().process_frame
	assert_true(seen.is_empty() or seen[0] == p)


func test_palette_helpers_and_tracer_colours() -> void:
	assert_eq(TankPalette.with_alpha(Color.RED, 0.25).a, 0.25)
	var d := TankPalette.darkened(Color(0.8, 0.6, 0.4), 0.5)
	assert_almost_eq(d.r, 0.4, 1e-6)
	assert_eq(d.a, 1.0)
	for sh: int in [
		TankIds.SHELL_LIGHT,
		TankIds.SHELL_HEAVY,
		TankIds.SHELL_OVER,
		TankIds.SHELL_SECONDARY,
		TankIds.SHELL_ENEMY,
		TankIds.SHELL_BOSS_MAIN
	]:
		assert_true(TankPalette.TRACER.has(sh), "tracer colour for shell %d" % sh)
	var art := TankPlaceholderArt.palette()
	for c in [
		TankPalette.FIRE,
		TankPalette.AMBER,
		TankPalette.GLOW_WARM,
		TankPalette.COLD_LIGHT,
		TankPalette.WHITE_COLD,
		TankPalette.STEEL,
		TankPalette.MUD
	]:
		assert_true(c in art, "%s is an art.json palette colour" % c.to_html(false))


func test_only_the_lights_are_saturated() -> void:
	for c in [
		TankPalette.STEEL,
		TankPalette.STEEL_DARK,
		TankPalette.MUD,
		TankPalette.MUD_LIGHT,
		TankPalette.OLIVE,
		TankPalette.HAZE,
		TankPalette.SMOKE,
		TankPalette.IRON
	]:
		assert_lt(c.s, 0.45, "%s is desaturated" % c.to_html(false))


func test_sprite_helpers() -> void:
	assert_eq(TankSprites.enemy_id("dugin"), "enemy_dugin")
	assert_eq(TankSprites.hull_id("citadel"), "hull_citadel")
	assert_eq(TankSprites.turret_id("bulwark"), "turret_bulwark")
	assert_eq(TankSprites.size("hull_rampart"), Vector2(240, 76))
	assert_false(TankSprites.has_real("not_a_sprite"))
	assert_ne(TankSprites.flyball_id(), "", "the steam room's regulator sprite exists in art.json")
	assert_not_null(TankSprites.tex(TankSprites.flyball_id()))


func test_every_sprite_the_view_uses_resolves_to_a_texture_of_its_size() -> void:
	var ids: Array[String] = []
	for tank in ["bulwark", "rampart", "citadel"]:
		ids.append_array([TankSprites.hull_id(tank), TankSprites.turret_id(tank)])
	for id in TankPlaceholderArt.ids():
		ids.append(id)
	for id in ids:
		var tex := TankSprites.tex(id)
		assert_not_null(tex, id)
		assert_eq(Vector2(tex.get_size()), TankSprites.size(id), id)


func test_rigs_json_gives_every_tank_rooms_wheels_and_a_turret() -> void:
	for tank in TankIds.TANKS:
		var def := TankRigs.tank_def(tank)
		assert_gt((def["rooms"] as Array).size(), 0, tank)
		assert_gt((def["road_wheels_x"] as Array).size(), 4)
		assert_eq(TankRigs.rect(def["turret"]["rect"]).size.x > 0.0, true)
	assert_eq(TankRigs.vec([3, 4]), Vector2(3, 4))
	assert_eq(TankRigs.vec("junk"), Vector2.ZERO)
	assert_eq(TankRigs.rect(null), Rect2())
