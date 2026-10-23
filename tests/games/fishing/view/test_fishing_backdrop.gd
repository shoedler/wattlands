extends GutTest
## The lane backdrop and the presentation effects brief 3.5 names: no unpainted rows along the
## waterline or across the HUD zone, the zone cover over the surface strip, islands in front of
## the clouds and the palm islet at a distant islet's size, two light-ray sets that differ, the
## ride out's wake on visible water behind the stern, and the Double Hookup's gold flash.

const FX := preload("res://tests/games/fishing/view/fishing_view_fixtures.gd")


func _view(n: int, local_slot: int = 0) -> FishingView:
	var game: FishingGame = autofree(FX.make_game(n, local_slot))
	var v := FX.make_view(game, self)
	autofree(v)
	return v


func _run(v: FishingView, seconds: float, dt: float = 0.05) -> void:
	for _i in roundi(seconds / dt):
		v.advance(dt)


func _bottom(s: Sprite2D) -> float:
	return s.position.y + float(s.texture.get_height())


func test_every_row_of_every_lane_is_painted_from_sky_to_water() -> void:
	for n in range(1, 5):
		var v := _view(n)
		v.advance(0.05)
		for lv in v.lanes:
			assert_eq(lv.sky_a.position.y, 0.0)
			assert_gte(_bottom(lv.sky_a), lv.water.position.y, "n %d: sky meets the water" % n)
			assert_eq(_bottom(lv.water), float(lv.lane_h), "n %d: water to the lane bottom" % n)
			assert_lte(lv.water.position.y, float(lv.water_y), "the water backs the surface rows")
			var strip_bottom := lv.surface.position.y + float(lv.surface.texture.get_height())
			assert_eq(lv.water.position.y, lv.surface.position.y + 2.0, "crest rows on the sky")
			assert_lte(lv.water.position.y, strip_bottom, "the strip's opaque rows on the water")


func test_the_hud_zone_cover_hides_the_surface_strip_and_is_fully_painted() -> void:
	for n in range(1, 5):
		var v := _view(n)
		v.advance(0.05)
		var lv := v.lane_view(0)
		var cover := lv.zone_cover
		assert_gt(cover.get_index(), lv.surface.get_index(), "the cover is drawn over the strip")
		assert_gt(cover.get_index(), lv.palm.get_index())
		assert_gt(cover.get_index(), lv.islands_far.get_index())
		assert_eq(cover.position.x, float(FishingConst.HUD_X - FishingPalette.COVER_EDGE))
		assert_eq(cover.position.x + float(cover.texture.get_width()), float(FishingConst.PIXEL_W))
		var strip_bottom := lv.surface.position.y + float(lv.surface.texture.get_height())
		assert_gte(_bottom(cover), strip_bottom, "n %d: the cover reaches the strip's bottom" % n)
		assert_gte(_bottom(cover), lv.water.position.y, "n %d: and the water's top" % n)
		var img := cover.texture.get_image()
		for y in img.get_height():
			for x in range(FishingPalette.COVER_EDGE, img.get_width()):
				if img.get_pixel(x, y).a < 0.5:
					assert_true(false, "n %d: cover px (%d, %d) is see-through" % [n, x, y])
					return


func test_islands_draw_in_front_of_the_clouds_and_the_islet_is_distant_sized() -> void:
	for n in range(1, 5):
		var lv := _view(n).lane_view(0)
		assert_gt(lv.islands_far.get_index(), lv.clouds.get_index(), "far islands after clouds")
		assert_gt(lv.palm.get_index(), lv.clouds.get_index(), "palm islet after clouds")
		var full := FishingSprites.texture("island_palm")
		assert_eq(lv.palm.texture.get_width(), full.get_width() / 2, "half size")
		assert_lt(lv.palm.texture.get_height(), FishingRig.BOAT_H / 2, "smaller than the boat")
		lv.advance(0.05)
		assert_gte(lv.palm.position.y, 0.0, "n %d: the islet fits the sky" % n)
	var src := FishingSprites.texture("island_palm").get_image()
	var colours := {}
	for y in src.get_height():
		for x in src.get_width():
			colours[src.get_pixel(x, y).to_html(false)] = true
	var half := FishingPalette.half_size("island_palm", FishingSprites.texture("island_palm"))
	var img := half.get_image()
	var opaque := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				opaque += 1
				assert_true(colours.has(c.to_html(false)), "palette exact at (%d, %d)" % [x, y])
	assert_gt(opaque, 100, "the islet still reads")


func test_the_two_light_ray_sets_differ() -> void:
	var lv := _view(1).lane_view(0)
	assert_eq(lv.rays.size(), 2)
	var a := lv.rays[0]
	var b := lv.rays[1]
	assert_ne(a.flip_h, b.flip_h, "the second set is mirrored")
	assert_ne(a.region_rect, b.region_rect, "and shorter")
	var ma := a.material as ShaderMaterial
	var mb := b.material as ShaderMaterial
	assert_ne(ma.get_shader_parameter("frequency_hz"), mb.get_shader_parameter("frequency_hz"))
	lv.advance(0.05)
	assert_ne(ma.get_shader_parameter("time_s"), mb.get_shader_parameter("time_s"), "out of step")


func test_the_ride_out_wake_shows_on_open_water_behind_the_stern() -> void:
	var v := _view(1)
	var l := v.game.state.lane(0)
	l.state = FishingConst.ST_RIDE_OUT
	l.power_w = 200.0
	_run(v, 3.0)
	var lv := v.lane_view(0)
	assert_true(lv.boat.wake_on)
	var r: Rect2 = lv.model["wake_rect"]
	var tile := FishingSprites.texture("wake").get_width()
	assert_gte(r.size.x, float(tile), "at least a whole wake tile of open water behind the stern")
	var foam := lv.boat.wake_foam()
	assert_gt(foam.size(), 10, "foam trails the stern")
	var near := 0
	for p in foam:
		var x := lv.boat.position.x + p.x
		assert_lte(x, lv.boat.position.x, "foam behind the stern")
		if x >= 3.0:
			near += 1
	assert_gt(near, 10, "the foam lands inside the lane, past the border")
	# The first pick: the boat eases back to BOAT_X0.
	FX.set_pick(l)
	_run(v, 5.0)
	assert_eq(lv.model["boat_x"], float(FishingConst.BOAT_X0))
	assert_false(lv.boat.wake_on)


func test_a_game_clock_run_ahead_of_the_frames_places_the_boat_too() -> void:
	var v := _view(1)
	var l := v.game.state.lane(0)
	l.state = FishingConst.ST_RIDE_OUT
	l.power_w = 200.0
	v.game.state.t = 6.0
	v.advance(0.05)
	var lv := v.lane_view(0)
	assert_gt(lv.model["boat_x"], float(FishingConst.BOAT_X0) + 40.0, "shifted for the wake")
	assert_true(lv.boat.wake_on)
	FX.set_pick(l)
	v.game.state.t = 20.0
	v.advance(0.05)
	assert_eq(lv.model["boat_x"], float(FishingConst.BOAT_X0), "back by the pick")


func test_double_hookup_flashes_gold_between_the_rod_tips_and_fades() -> void:
	var v := _view(4)
	for i in 2:
		FX.set_fight(v.game.state.lane(i), 1, 50.0)
	_run(v, 0.1)
	v.game.state.hookup_level = 2
	v.advance(0.05)
	var px := v.link_pixels()
	assert_gt(px.size(), 10, "the flash shows")
	var lane_size := Vector2(FishingConst.PIXEL_W, v.lane_view(0).lane_h)
	var area := Rect2(v.lane_view(0).position, lane_size)
	area = area.merge(Rect2(v.lane_view(1).position, lane_size))
	for p in px:
		assert_true(area.has_point(p), "flash px %s inside the linked lanes" % p)
		var near_beam := absf(p.x - v.link_x()) <= float(FishingView.LINK_BEAM_W)
		var near_tip := false
		for lv in [v.lane_view(0), v.lane_view(1)]:
			var tip: Vector2 = (lv.position + lv.boat.position + lv.boat.rod_points()[-1]).floor()
			near_tip = near_tip or p.distance_to(tip) <= float(FishingView.LINK_BURST_R)
		assert_true(near_beam or near_tip, "flash px %s on the beam or at a tip" % p)
	var t0 := (
		v.lane_view(0).position
		+ v.lane_view(0).boat.position
		+ v.lane_view(0).boat.rod_points()[-1]
	)
	var t1 := (
		v.lane_view(1).position
		+ v.lane_view(1).boat.position
		+ v.lane_view(1).boat.rod_points()[-1]
	)
	var ys := []
	for p in px:
		ys.append(p.y)
	assert_lte(ys.min(), minf(t0.y, t1.y) + 0.5, "from the upper tip")
	assert_gte(ys.max(), maxf(t0.y, t1.y) - 0.5, "to the lower tip")
	_run(v, 0.8)
	assert_lt(v.link_pixels().size(), px.size(), "it fades by dither")
	_run(v, 1.0)
	assert_eq(v.link_pixels().size(), 0, "a short flash, not a box that stays")


func test_the_flash_ends_with_the_game_clock_when_frames_lag() -> void:
	var v := _view(2)
	for i in 2:
		FX.set_fight(v.game.state.lane(i), 1, 50.0)
	_run(v, 0.1)
	v.game.state.hookup_level = 2
	v.advance(0.05)
	assert_gt(v.link_pixels().size(), 0)
	v.game.state.t += 15.0
	v.advance(0.05)
	assert_eq(v.link_pixels().size(), 0, "15 s of game time later the flash is long over")
