extends GutTest
## ParallaxStrip (BRIEF 3.9; OWNERSHIP W2D2): factors including 0 and > 1, wrap, mirrored
## tiling, covering a width wider than the texture, drift and determinism.


func _tex(w: int, h: int) -> ImageTexture:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _strip(w: int = 32, factor: float = 1.0, mirror: bool = false) -> ParallaxStrip:
	var s: ParallaxStrip = autofree(ParallaxStrip.new())
	s.texture = _tex(w, 8)
	s.factor = factor
	s.mirror_alternate = mirror
	s.cover_width = 640.0
	return s


func _xs(tiles: Array[Dictionary]) -> Array:
	var out: Array = []
	for t: Dictionary in tiles:
		out.append([t["x"], t["flipped"]])
	return out


func test_scroll_is_world_x_times_factor() -> void:
	var s := _strip(32, 0.5)
	s.world_x = 100.0
	assert_eq(s.scroll(), 50.0)
	s.factor = 1.3
	assert_eq(s.scroll(), 130.0)
	s.factor = 0.0
	assert_eq(s.scroll(), 0.0, "factor 0 stays still")


func test_tiles_cover_the_width_with_a_narrow_texture() -> void:
	# Tank's 240 x 80 bg_ground across a 640 px view.
	var s := _strip(240, 1.0)
	for wx: float in [0.0, 17.0, 239.0, 240.0, 1000.0, -17.0, -1000.0]:
		s.world_x = wx
		var tiles := s.visible_tiles()
		assert_true(float(tiles[0]["x"]) <= 0.0, "starts at or left of 0 (world_x %s)" % wx)
		var last: Dictionary = tiles[tiles.size() - 1]
		assert_true(float(last["x"]) + 240.0 >= 640.0, "reaches the right edge")
		for i in range(1, tiles.size()):
			assert_eq(float(tiles[i]["x"]) - float(tiles[i - 1]["x"]), 240.0, "tiles abut")


func test_wrap_after_one_period() -> void:
	var s := _strip(32, 1.0)
	s.world_x = 10.0
	var a := _xs(s.visible_tiles())
	s.world_x = 10.0 + s.period()
	assert_eq(_xs(s.visible_tiles()), a)


func test_mirror_alternates_flipped_copies() -> void:
	var s := _strip(32, 1.0, true)
	assert_eq(s.period(), 64.0)
	s.world_x = 0.0
	var tiles := s.visible_tiles()
	for t: Dictionary in tiles:
		assert_eq(t["flipped"], posmod(int(t["index"]), 2) == 1)
	var flipped := 0
	for t: Dictionary in tiles:
		if t["flipped"]:
			flipped += 1
	assert_gt(flipped, 0)
	assert_lt(flipped, tiles.size())


func test_mirror_needs_two_tiles_to_repeat() -> void:
	var s := _strip(32, 1.0, true)
	s.world_x = 5.0
	var a := _xs(s.visible_tiles())
	s.world_x = 5.0 + 32.0
	assert_ne(_xs(s.visible_tiles()), a, "one tile later the flips are swapped")
	s.world_x = 5.0 + 64.0
	assert_eq(_xs(s.visible_tiles()), a, "two tiles later it is the same")


func test_without_mirror_nothing_is_flipped() -> void:
	var s := _strip(32, 1.0, false)
	s.world_x = 77.0
	for t: Dictionary in s.visible_tiles():
		assert_false(t["flipped"])


func test_factor_greater_than_one_moves_faster() -> void:
	var ground := _strip(32, 1.0)
	var debris := _strip(32, 1.3)
	ground.world_x = 100.0
	debris.world_x = 100.0
	assert_gt(debris.scroll(), ground.scroll())


func test_negative_factor_is_clamped_with_warning() -> void:
	var s := _strip(32, 1.0)
	s.factor = -0.5
	assert_push_warning("factor")
	assert_eq(s.factor, 0.0)


func test_pixel_snap_rounds_scroll() -> void:
	var s := _strip(32, 0.2)
	s.world_x = 10.0
	assert_eq(s.scroll(), 2.0)
	s.world_x = 13.0
	assert_eq(s.scroll(), 3.0, "2.6 rounds to 3")
	s.pixel_snap = false
	assert_almost_eq(s.scroll(), 2.6, 0.0001)


func test_drift_advances_with_tick_and_wraps() -> void:
	var s := _strip(32, 0.0)
	s.drift_px_s = 4.0
	s.tick(1.0)
	assert_eq(s.scroll(), 4.0)
	s.tick(8.0)
	assert_eq(s.scroll(), 4.0, "36 px wraps at the 32 px period")
	s.tick(0.0)
	s.tick(-1.0)
	assert_eq(s.scroll(), 4.0, "non-positive dt does nothing")


func test_offset_x_shifts_the_strip() -> void:
	var s := _strip(32, 1.0)
	s.offset_x = 7.0
	s.world_x = 0.0
	assert_eq(s.scroll(), 7.0)


func test_deterministic_for_the_same_world_x() -> void:
	var a := _strip(48, 0.5, true)
	var b := _strip(48, 0.5, true)
	a.world_x = 1234.5
	b.world_x = 1234.5
	assert_eq(_xs(a.visible_tiles()), _xs(b.visible_tiles()))


func test_no_texture_draws_nothing() -> void:
	var s: ParallaxStrip = autofree(ParallaxStrip.new())
	assert_eq(s.visible_tiles().size(), 0)
	assert_eq(s.period(), 0.0)


func test_draws_in_tree_with_default_cover_width() -> void:
	var s := ParallaxStrip.new()
	s.texture = _tex(16, 4)
	s.mirror_alternate = true
	s.align_bottom = true
	add_child_autofree(s)
	assert_gt(s.covered_width(), 0.0)
	s.world_x = 9.0
	await wait_process_frames(2)
	assert_gt(s.visible_tiles().size(), 0)
