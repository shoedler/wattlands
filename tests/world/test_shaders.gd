extends GutTest
## PaletteSwap and SpriteWobble (BRIEF 3.9; OWNERSHIP W2D5, W2D6): the shaders load with
## their uniforms, the helpers set parameters, ramps come from slot colors, and the CPU
## references match the shaders' rules.

const KEYS: Array[Color] = [Color("#d0303c"), Color("#86202a")]


func _uniform_names(sh: Shader) -> Array[String]:
	var out: Array[String] = []
	for u: Dictionary in sh.get_shader_uniform_list():
		out.append(str(u["name"]))
	return out


# --- PaletteSwap ---------------------------------------------------------------------------

func test_palette_swap_shader_loads() -> void:
	var sh := PaletteSwap.shader()
	assert_not_null(sh)
	assert_eq(sh.get_mode(), Shader.MODE_CANVAS_ITEM)
	var names := _uniform_names(sh)
	for n: String in ["key_0", "key_7", "swap_0", "swap_7", "key_count", "tolerance"]:
		assert_has(names, n)


func test_make_material_sets_ramps() -> void:
	var keys := PackedColorArray(KEYS)
	var swaps := PackedColorArray([Color.BLUE, Color.NAVY_BLUE])
	var mat := PaletteSwap.make_material(keys, swaps, 0.05)
	assert_eq(mat.shader, PaletteSwap.shader())
	assert_eq(int(mat.get_shader_parameter("key_count")), 2)
	assert_almost_eq(float(mat.get_shader_parameter("tolerance")), 0.05, 0.0001)
	assert_eq(PaletteSwap.keys_of(mat), keys)
	assert_eq(PaletteSwap.swaps_of(mat), swaps)
	assert_eq(mat.get_shader_parameter("key_2"), Color(0, 0, 0, 0), "unused keys are cleared")


func test_apply_sets_item_material() -> void:
	var s: Sprite2D = autofree(Sprite2D.new())
	var mat := PaletteSwap.apply(s, PackedColorArray(KEYS), PackedColorArray([Color.RED, Color.DARK_RED]))
	assert_eq(s.material, mat)


func test_apply_slot_uses_session_colors() -> void:
	for slot in 8:
		var s: Sprite2D = autofree(Sprite2D.new())
		var mat := PaletteSwap.apply_slot(s, PackedColorArray(KEYS), slot)
		var swaps := PaletteSwap.swaps_of(mat)
		assert_eq(swaps.size(), 2)
		assert_eq(swaps[0], Wl.slot_look(slot)["color"], "slot %d light color" % slot)
		assert_lt(swaps[1].get_luminance(), swaps[0].get_luminance(), "darker second step")


func test_ramp_from() -> void:
	var r := PaletteSwap.ramp_from(Color(0.8, 0.4, 0.2), 3, 0.5)
	assert_eq(r.size(), 3)
	assert_eq(r[0], Color(0.8, 0.4, 0.2))
	assert_almost_eq(r[2].r, 0.4, 0.0001)
	assert_almost_eq(r[1].r, 0.6, 0.0001)
	assert_eq(PaletteSwap.ramp_from(Color.RED, 1).size(), 1)
	assert_eq(PaletteSwap.ramp_from(Color.RED, 99).size(), PaletteSwap.MAX_KEYS)


func test_set_swaps_replaces_only_swaps() -> void:
	var mat := PaletteSwap.make_material(PackedColorArray(KEYS), PaletteSwap.slot_ramp(0))
	PaletteSwap.set_swaps(mat, PaletteSwap.slot_ramp(1))
	assert_eq(PaletteSwap.swaps_of(mat), PaletteSwap.slot_ramp(1))
	assert_eq(PaletteSwap.keys_of(mat), PackedColorArray(KEYS))


func test_mismatched_ramps_are_an_error() -> void:
	var mat := PaletteSwap.make_material(PackedColorArray(KEYS), PackedColorArray([Color.BLUE]))
	assert_push_error("PaletteSwap")
	assert_eq(int(mat.get_shader_parameter("key_count")), 1)


func test_too_many_keys_are_an_error() -> void:
	var many := PackedColorArray()
	for i in 10:
		many.append(Color(i / 10.0, 0, 0))
	var mat := PaletteSwap.make_material(many, many)
	assert_push_error("MAX_KEYS")
	assert_eq(int(mat.get_shader_parameter("key_count")), PaletteSwap.MAX_KEYS)


func test_swap_color_reference() -> void:
	var keys := PackedColorArray(KEYS)
	var swaps := PaletteSwap.slot_ramp(1)
	assert_eq(PaletteSwap.swap_color(KEYS[0], keys, swaps), Color(swaps[0], 1.0))
	assert_eq(PaletteSwap.swap_color(KEYS[1], keys, swaps), Color(swaps[1], 1.0))
	var white := Color.WHITE
	assert_eq(PaletteSwap.swap_color(white, keys, swaps), white, "non-key colors stay")
	var half := Color(KEYS[0].r, KEYS[0].g, KEYS[0].b, 0.5)
	assert_eq(PaletteSwap.swap_color(half, keys, swaps).a, 0.5, "alpha is kept")
	var near := Color(KEYS[0].r + 0.01, KEYS[0].g, KEYS[0].b)
	assert_eq(PaletteSwap.swap_color(near, keys, swaps), Color(swaps[0], 1.0), "within tolerance")
	var far := Color(KEYS[0].r + 0.1, KEYS[0].g, KEYS[0].b)
	assert_eq(PaletteSwap.swap_color(far, keys, swaps), far)


func test_swap_image_recolors_only_keys() -> void:
	var img := Image.create_empty(3, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, KEYS[0])
	img.set_pixel(1, 0, KEYS[1])
	img.set_pixel(2, 0, Color.WHITE)
	var out := PaletteSwap.swap_image(img, PackedColorArray(KEYS), PaletteSwap.slot_ramp(3))
	var green: Color = Wl.slot_look(3)["color"]
	assert_almost_eq(out.get_pixel(0, 0).g, green.g, 0.01)
	assert_eq(out.get_pixel(2, 0), Color.WHITE)
	assert_eq(img.get_pixel(0, 0).r, KEYS[0].r, "the source is unchanged")


# --- SpriteWobble ---------------------------------------------------------------------------

func test_sprite_wobble_shader_loads() -> void:
	var sh := SpriteWobble.shader()
	assert_not_null(sh)
	assert_eq(sh.get_mode(), Shader.MODE_CANVAS_ITEM)
	var names := _uniform_names(sh)
	for n: String in ["amplitude_px", "wavelength_px", "frequency_hz", "phase", "vertical", "falloff_from", "falloff_to", "pixel_snap", "use_engine_time", "time_s", "margin_px"]:
		assert_has(names, n)


func test_make_material_sets_wave() -> void:
	var mat := SpriteWobble.make_material(2.0, 12.0, 1.5, false)
	assert_eq(mat.get_shader_parameter("amplitude_px"), 2.0)
	assert_eq(mat.get_shader_parameter("wavelength_px"), 12.0)
	assert_eq(mat.get_shader_parameter("frequency_hz"), 1.5)
	assert_eq(mat.get_shader_parameter("vertical"), false)
	assert_eq(mat.get_shader_parameter("margin_px"), 2.0, "the quad grows by the amplitude")


func test_presets() -> void:
	var fish: Sprite2D = autofree(Sprite2D.new())
	var m := SpriteWobble.fish_tail(fish, true)
	assert_eq(fish.material, m)
	assert_eq(m.get_shader_parameter("vertical"), true)
	assert_lt(float(m.get_shader_parameter("falloff_from")), float(m.get_shader_parameter("falloff_to")), "tail on the right")
	var right: Sprite2D = autofree(Sprite2D.new())
	var m2 := SpriteWobble.fish_tail(right, false)
	assert_gt(float(m2.get_shader_parameter("falloff_from")), float(m2.get_shader_parameter("falloff_to")), "tail on the left")
	var water: Sprite2D = autofree(Sprite2D.new())
	var m3 := SpriteWobble.water(water)
	assert_eq(m3.get_shader_parameter("vertical"), false)


func test_set_time_and_engine_time() -> void:
	var mat := SpriteWobble.make_material()
	SpriteWobble.set_time(mat, 3.25)
	assert_eq(mat.get_shader_parameter("use_engine_time"), false)
	assert_eq(mat.get_shader_parameter("time_s"), 3.25)
	SpriteWobble.use_engine_time(mat)
	assert_eq(mat.get_shader_parameter("use_engine_time"), true)


func test_bad_wavelength_is_an_error() -> void:
	var mat := SpriteWobble.make_material()
	SpriteWobble.set_wave(mat, 1.0, 0.0, 1.0)
	assert_push_error("wavelength_px")
	assert_eq(mat.get_shader_parameter("wavelength_px"), 1.0)


func test_displacement_reference() -> void:
	for x in 32:
		for k in 8:
			var t := k * 0.13
			var d := SpriteWobble.displacement(float(x), t, 2.0, 16.0, 1.0)
			assert_eq(d, roundf(d), "pixel snapped")
			assert_true(absf(d) <= 2.0, "bounded by the amplitude")
	assert_eq(SpriteWobble.displacement(5.0, 0.3, 2.0, 16.0, 1.0, 0.0, 0.0), 0.0, "no wobble at weight 0")
	var a := SpriteWobble.displacement(3.0, 0.2, 3.0, 10.0, 0.5, 0.0, 1.0, false)
	var b := SpriteWobble.displacement(13.0, 0.2, 3.0, 10.0, 0.5, 0.0, 1.0, false)
	var c := SpriteWobble.displacement(3.0, 2.2, 3.0, 10.0, 0.5, 0.0, 1.0, false)
	assert_almost_eq(a, b, 0.0001, "periodic in the wavelength")
	assert_almost_eq(a, c, 0.0001, "periodic in 1 / frequency")
