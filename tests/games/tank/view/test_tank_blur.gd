extends GutTest
## Fake depth of field (brief 3): every plane except the tank's is blurred once at load into a cached
## texture and tinted toward the haze colour; nothing runs per frame.

const PRESET_SHARP := {"down": 1, "box_r": 0, "passes": 1, "haze": 0.0, "darken": 0.0}


func _checker(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var on := (x / 2 + y / 2) % 2 == 0
			img.set_pixel(x, y, Color(1, 1, 1, 1) if on else Color(0, 0, 0, 1))
	return img


func _spread(img: Image) -> float:
	var lo := 1.0
	var hi := 0.0
	for y in img.get_height():
		for x in img.get_width():
			var v := img.get_pixel(x, y).r
			lo = minf(lo, v)
			hi = maxf(hi, v)
	return hi - lo


func test_presets_cover_every_plane_with_growing_blur_away_from_the_tank() -> void:
	for key in ["sky", "hills", "near", "ground", "debris"]:
		assert_true(TankBlur.PRESETS.has(key), key)
	var p: Dictionary = TankBlur.PRESETS
	assert_eq(int(p["ground"]["down"]), 1, "the tank's plane stays sharp")
	assert_eq(int(p["ground"]["box_r"]), 0)
	assert_lt(int(p["near"]["down"]), int(p["hills"]["down"]), "farther planes blur more")
	assert_lte(int(p["hills"]["down"]), int(p["sky"]["down"]))
	assert_gt(float(p["hills"]["haze"]), float(p["near"]["haze"]), "and fade into more haze")
	assert_gt(float(p["debris"]["darken"]), 0.4, "the foreground debris darkens")


func test_blur_keeps_the_size_and_softens_contrast() -> void:
	var src := _checker(64, 32)
	var out := TankBlur.blurred_image(src, TankBlur.PRESETS["hills"], TankPalette.HAZE)
	assert_eq(Vector2i(out.get_width(), out.get_height()), Vector2i(64, 32))
	assert_lt(_spread(out), _spread(src) * 0.6, "a checker board turns to grey")


func test_the_sharp_preset_does_not_blur() -> void:
	var src := _checker(32, 16)
	var out := TankBlur.blurred_image(src, PRESET_SHARP, TankPalette.HAZE)
	for y in 16:
		for x in 32:
			assert_eq(out.get_pixel(x, y).r8, src.get_pixel(x, y).r8)


func test_haze_pulls_colours_toward_the_haze_colour() -> void:
	var src := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	src.fill(Color(0, 0, 0, 1))
	var preset := {"down": 2, "box_r": 0, "passes": 1, "haze": 0.5, "darken": 0.0}
	var out := TankBlur.blurred_image(src, preset, Color(0.4, 0.4, 0.4))
	assert_almost_eq(out.get_pixel(8, 8).r, 0.2, 0.02)


func test_darken_moves_colours_toward_black() -> void:
	var lit := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	lit.fill(Color(0.8, 0.8, 0.8, 1))
	var preset := {"down": 1, "box_r": 0, "passes": 1, "haze": 0.0, "darken": 0.5}
	var out := TankBlur.blurred_image(lit, preset, Color.WHITE)
	assert_almost_eq(out.get_pixel(3, 3).r, 0.4, 0.02, "darken 0.5 halves the light")


func test_blur_keeps_transparent_pixels_transparent_and_the_silhouette_soft() -> void:
	var img := Image.create(40, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(10, 20):
		for x in 40:
			img.set_pixel(x, y, Color(0.3, 0.3, 0.3, 1))
	var out := TankBlur.blurred_image(img, TankBlur.PRESETS["hills"], TankPalette.HAZE)
	assert_lt(out.get_pixel(20, 0).a, 0.05, "far above the silhouette stays clear")
	assert_gt(out.get_pixel(20, 19).a, 0.95, "inside stays solid")
	var edge := out.get_pixel(20, 10).a
	assert_gt(edge, 0.05)
	assert_lt(edge, 0.95, "the silhouette's edge is soft")


func test_edges_repeat_instead_of_wrapping() -> void:
	var img := Image.create(48, 12, false, Image.FORMAT_RGBA8)
	for x in 48:
		img.fill_rect(Rect2i(x, 0, 1, 12), Color(float(x) / 47.0, 0.2, 0.2, 1))
	var out := TankBlur.blurred_image(img, TankBlur.PRESETS["sky"], TankPalette.HAZE)
	assert_lt(
		out.get_pixel(0, 6).r,
		out.get_pixel(47, 6).r,
		"the first and last columns do not bleed into each other"
	)


func test_plane_textures_are_cached_per_id_and_preset() -> void:
	TankBlur.clear_cache()
	var builds := TankBlur.builds
	var a := TankBlur.plane("bg_hills_far", "hills")
	assert_eq(TankBlur.builds, builds + 1)
	var b := TankBlur.plane("bg_hills_far", "hills")
	assert_same(a, b)
	assert_eq(TankBlur.builds, builds + 1, "built once")
	var c := TankBlur.plane("bg_hills_far", "near")
	assert_ne(a, c, "another preset is another texture")
	assert_eq(TankBlur.builds, builds + 2)
	assert_eq(a.get_size(), TankSprites.size("bg_hills_far"), "same size as the sprite")


func test_loading_every_plane_stays_cheap() -> void:
	TankBlur.clear_cache()
	var planes := {
		"bg_sky": "sky",
		"bg_hills_far": "hills",
		"bg_fields_near": "near",
		"bg_village_near": "near",
		"bg_quarry_near": "near",
		"bg_town_near": "near",
		"bg_depot_near": "near",
		"fg_debris": "debris",
	}
	var started := Time.get_ticks_msec()
	for id: String in planes:
		TankBlur.plane(id, planes[id])
	assert_lt(Time.get_ticks_msec() - started, 3000, "eight planes blur in well under 3 s")
