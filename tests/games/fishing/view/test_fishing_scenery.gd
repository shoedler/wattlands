extends GutTest
## The code-drawn ocean and its floor, the boat's rig geometry and pixel runs, the rope line
## and the client's snapshot history.

var _world: FishingWorld = null


func before_all() -> void:
	var map: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/fishing/map.json")
	)
	_world = FishingWorld.from_map(map, 1)


func _scenery(depth: float = 100.0) -> FishingScenery:
	var s := FishingScenery.new()
	s.world = _world
	s.view_depth_m = depth
	return s


func test_depth_maps_down_from_the_surface_and_back() -> void:
	var s := _scenery(400.0)
	assert_eq(s.y_of_depth(0.0), float(FishingScenery.SURF_Y))
	var prev := -1.0
	for d: float in [1.0, 10.0, 50.0, 200.0, 400.0]:
		var y := s.y_of_depth(d)
		assert_gt(y, prev)
		assert_almost_eq(s.depth_of_y(y), d, 0.01)
		prev = y
	assert_almost_eq(
		s.y_of_depth(400.0), float(FishingScenery.SURF_Y + FishingScenery.FLOOR_ROWS), 0.01
	)
	assert_true(is_inf(s.y_of_depth(INF)))


func test_the_view_depth_follows_the_floor_in_sight() -> void:
	var s := _scenery()
	var dock := _world.floor_depth_m(300.0) * FishingScenery.VIEW_MARGIN
	assert_almost_eq(s.target_view_depth(-20.0), maxf(dock, 3.0), 2.5)
	assert_gt(s.target_view_depth(13600.0), 250.0)
	assert_eq(s.target_view_depth(17000.0), FishingScenery.ABYSS_M, "no floor: the abyss")


func test_the_far_water_band_lies_between_the_horizon_and_the_surface() -> void:
	assert_eq(FishingScenery.HORIZON_Y, FishingScenery.SURF_Y - FishingScenery.FAR_ROWS)
	assert_lt(FishingView.FAR_ROW_PX, FishingScenery.FAR_ROWS, "far boats sit on the band")


func test_the_deepest_floor_in_sight_stays_above_the_hud() -> void:
	assert_lt(FishingScenery.SURF_Y + FishingScenery.FLOOR_ROWS, FishingConst.PANIC_Y)


func test_water_darkens_with_depth_in_flat_steps() -> void:
	assert_eq(FishingScenery.water_at(0.0), FishingPalette.HAZE, "haze under the foam line")
	assert_lte(FishingPalette.SEA.size(), 5, "at most five flat water fields")
	var prev := -1
	for d: float in [0.0, 10.0, 30.0, 60.0, 120.0, 250.0, 400.0, 600.0]:
		var i := FishingPalette.SEA.find(FishingScenery.water_at(d))
		assert_gte(i, prev)
		prev = i
	assert_eq(FishingScenery.water_at(700.0), FishingPalette.MID)
	assert_eq(FishingScenery.water_at(30.0), FishingPalette.SURFACE, "the same metres everywhere")


func test_the_floor_is_sage_in_the_shallows_and_two_steps_under_the_water_in_the_deep() -> void:
	assert_eq(FishingScenery.floor_at(4.0), FishingPalette.SAGE)
	assert_eq(FishingScenery.floor_at(10.0), FishingPalette.SAGE)
	for d: float in [4.0, 15.0, 60.0, 150.0, 400.0, 600.0]:
		var water := FishingScenery.water_at(d)
		assert_ne(FishingScenery.floor_at(d), water, "floor at %s m reads" % d)
		var rim := FishingScenery.floor_at(d, true)
		assert_ne(rim, FishingScenery.floor_at(d), "the top line differs from the floor")
		assert_ne(rim, water, "and from the water")
	assert_eq(FishingScenery.floor_at(300.0), FishingPalette.DEEP, "two steps under the water")
	assert_eq(FishingScenery.floor_at(300.0, true), FishingPalette.SURFACE, "under a lit rim")
	assert_eq(FishingScenery.floor_at(600.0), FishingPalette.ABYSS)
	for band in FishingPalette.SEA.size():
		var ridge := FishingFloor.RIDGE_BANDS[band]
		assert_ne(ridge, FishingPalette.SEA[band], "the back ridge reads against the water")
		assert_ne(ridge, FishingFloor.FLOOR_BANDS[band], "and against the floor in front")


func test_the_floor_is_flat_terraces_with_drops_seeded_by_world_cell() -> void:
	var f := FishingFloor.new()
	f.set_world(_world)
	var g := FishingFloor.new()
	g.set_world(_world)
	for x_m: float in [400.0, 2400.0, 6000.0, 10000.0, 14000.0]:
		var px := x_m * FishingScenery.PX_PER_M
		var a := f.terraces_in(px, px + 640.0)
		assert_eq(a, g.terraces_in(px, px + 640.0), "deterministic at %s m" % x_m)
		var long := 0
		for i in a.size():
			var t: Dictionary = a[i]
			var w := int(t["x1"]) - int(t["x0"])
			assert_eq(w % FishingFloor.CELL_PX, 0, "whole cells")
			if i > 0:
				assert_eq(t["x0"], a[i - 1]["x1"], "terraces tile the floor at %s m" % x_m)
			if w >= 4 * FishingFloor.CELL_PX:
				long += 1
		assert_gt(long, 0, "long flat terraces at %s m, not a fine staircase" % x_m)
	for zone in FishingWorld.ZONES.size():
		for kind: String in FishingProps.BIG[zone] + FishingProps.SMALL[zone]:
			assert_has(FishingProps.KINDS, kind, "zone %d prop %s has a painter" % [zone, kind])
	assert_eq(FishingProps.BIG.size(), FishingWorld.ZONES.size(), "big props per zone")
	assert_eq(FishingProps.SMALL.size(), FishingWorld.ZONES.size(), "small props per zone")
	var dock := f.terraces_in(0.0, FishingFloor.DOCK_DROP_M * 2.0 * FishingScenery.PX_PER_M)
	var levels := {}
	for t in dock:
		if int(t["zone"]) == 0:
			levels[snappedf(float(t["d"]), 0.01)] = true
	assert_eq(levels.size(), 2, "the harbour: a quay shelf and one dredged drop")
	var piece_lens := {}
	for x_m: float in [6000.0, 10000.0]:
		for t in f.terraces_in(x_m * 2.0, x_m * 2.0 + 640.0):
			for p in FishingFloor.pieces(t):
				assert_lte(p.y - p.x, float(FishingFloor.PIECE_MIN + FishingFloor.PIECE_SPAN) * 1.5)
				piece_lens[int(p.y - p.x)] = true
	assert_gt(piece_lens.size(), 6, "pieces of many lengths, off any regular grid")
	var shallows := f.terraces_in(2400.0, 3040.0)
	assert_lte(shallows.size(), 640 / (6 * FishingFloor.CELL_PX), "gentle slopes merge")


func test_fish_stay_the_darkest_subject_in_every_band() -> void:
	assert_eq(FishingPaletteMap.shift_for(0), 0)
	assert_eq(FishingPaletteMap.shift_for(1), 0)
	assert_eq(FishingPaletteMap.shift_for(2), 1)
	assert_eq(FishingPaletteMap.shift_for(FishingPalette.SEA.size() - 1), 1)
	var ladder := FishingPalette.LADDER
	for band in FishingPalette.SEA.size():
		var shift := FishingPaletteMap.fish_shift(band)
		var belly := FishingPalette.darker(FishingPalette.UPPER, shift)
		var back := FishingPalette.darker(FishingPalette.DEEP, shift)
		var ridge := FishingFloor.RIDGE_BANDS[band]
		var water := FishingPalette.SEA[band]
		assert_gt(ladder.find(belly), ladder.find(water), "band %d: darker than the water" % band)
		assert_gt(ladder.find(back), ladder.find(ridge), "band %d: the back is darker" % band)
		if band < FishingPalette.SEA.size() - 1:
			assert_gt(ladder.find(belly), ladder.find(ridge), "band %d: the belly too" % band)
		assert_ne(belly, back, "band %d: two planes" % band)


func test_waves_are_crests_or_flat() -> void:
	var crests := 0
	for x in 640:
		var w := FishingScenery.wave(float(x), 1.0)
		assert_true(w == 0 or w == 1)
		crests += w
	assert_gt(crests, 10)
	assert_lt(crests, 320, "mostly calm water")


func test_the_edge_is_the_roam_maps_end_and_endless_has_none() -> void:
	assert_eq(_scenery().edge_m(), _world.length_m())
	var e := FishingScenery.new()
	e.world = FishingWorld.endless_for(3)
	assert_true(is_inf(e.edge_m()))


func test_screen_x_scales_world_metres() -> void:
	assert_eq(FishingScenery.screen_x(110.0, 100.0), 10.0 * FishingScenery.PX_PER_M)


func test_painting_every_region_draws_without_errors() -> void:
	var s := _scenery(600.0)
	var cams: Array[float] = [-60.0, 2900.0, 7700.0, 8800.0]
	var layer := FishingDrawLayer.make(
		"Paint",
		func(c: CanvasItem) -> void:
			for cam in cams:
				s.view_depth_m = s.target_view_depth(cam)
				s.paint_back(c, cam, 1.0)
	)
	add_child_autofree(layer)
	layer.queue_redraw()
	await wait_process_frames(2)
	assert_eq(s.view_depth_m, s.target_view_depth(8800.0))


func test_the_rod_frames_are_stowed_raised_and_bent_without_gaps_or_corners() -> void:
	var base := FishingRig.ROD_BASE
	var stowed := FishingRig.rod(0.0, 0.0)
	var raised := FishingRig.rod(1.0, 0.0)
	assert_lt(stowed[-1].x, base.x - 6, "stowed it lies back over the stern")
	assert_gt(stowed[-1].y, raised[-1].y, "low")
	assert_lt(raised[-1].y, base.y - 8, "raised it stands up")
	for t: float in [0.5, 1.0]:
		var bent := FishingRig.rod(1.0, t)
		assert_gt(bent[-1].y, raised[-1].y, "tension %s bends the tip down" % t)
		assert_lt(bent[-1].x, raised[-1].x, "and back")
	for frame in [stowed, raised, FishingRig.rod(1.0, 0.5), FishingRig.rod(1.0, 1.0)]:
		assert_eq(frame[0], base)
		for i in frame.size() - 1:
			var d: Vector2i = frame[i + 1] - frame[i]
			assert_true(absi(d.x) <= 1 and absi(d.y) <= 1, "the rod has no gaps")
	var diag := FishingRig.raster(Vector2i.ZERO, Vector2i(9, 9))
	assert_eq(diag.size(), 10, "a 1:1 run is one pixel per step, no corners")


func test_the_rope_sags_with_slack_straightens_under_strain_and_draws_clean() -> void:
	var a := Vector2(100, 100)
	var b := Vector2(220, 200)
	var loose := FishingRope.new()
	var taut := FishingRope.new()
	loose.reset(a, b)
	taut.reset(a, b)
	for _i in 180:
		loose.step(a, b, 1.0, 0.0, 1.0 / 60.0, 118.0)
		taut.step(a, b, 0.0, 1.0, 1.0 / 60.0, 118.0)
	var mid := a.lerp(b, 0.5)
	var half := FishingRope.SEGMENTS / 2
	assert_gt(loose.points[half].y - mid.y, 3.0, "slack lets the line bow")
	assert_lt(absf(taut.points[half].y - mid.y), 2.0, "strain pulls it straight")
	assert_eq(loose.points[0], a, "pinned at the rod")
	assert_eq(loose.points[FishingRope.SEGMENTS], b, "and at the fish")
	var px := loose.pixels()
	assert_eq(px[0], Vector2i(a), "drawn from the rod end")
	assert_eq(px[-1], Vector2i(b))
	for i in px.size() - 1:
		var d := px[i + 1] - px[i]
		assert_true(absi(d.x) <= 1 and absi(d.y) <= 1, "no gaps")
	for i in range(1, px.size() - 1):
		var p := px[i - 1]
		var q := px[i + 1]
		assert_false(absi(q.x - p.x) == 1 and absi(q.y - p.y) == 1, "no L-corner at %s" % px[i])
	assert_eq(FishingRope.length(100.0, 0.0, 1.0), 100.0, "a taut line is the straight distance")
	var spike: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 1), Vector2i(3, 0)]
	assert_eq(
		FishingRope.pixel_perfect(spike),
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)] as Array[Vector2i],
		"a one-pixel spike flattens"
	)


func test_the_rope_holds_its_pixels_against_sub_pixel_jitter() -> void:
	var r := FishingRope.new()
	r.reset(Vector2(10, 10), Vector2(90, 70))
	for _i in 120:
		r.step(Vector2(10, 10), Vector2(90, 70), 0.5, 0.2, 1.0 / 60.0, 118.0)
	var before := r.pixels()
	r.step(Vector2(10.3, 10.2), Vector2(90.3, 70.2), 0.5, 0.2, 1.0 / 60.0, 118.0)
	var after := r.pixels()
	var moved := 0
	for i in mini(before.size(), after.size()):
		if before[i] != after[i]:
			moved += 1
	assert_lte(moved, 2, "a third of a pixel barely moves the line")


func test_raster_runs_without_gaps_in_uniform_runs() -> void:
	var run := FishingRig.raster(Vector2i(3, 2), Vector2i(-40, 97))
	assert_eq(run[0], Vector2i(3, 2))
	assert_eq(run[-1], Vector2i(-40, 97))
	for i in run.size() - 1:
		var d := run[i + 1] - run[i]
		assert_true(absi(d.x) <= 1 and absi(d.y) <= 1, "no gaps")
	var flat := FishingRig.raster(Vector2i.ZERO, Vector2i(12, 4))
	var runs: Array[int] = []
	var n := 1
	for i in range(1, flat.size()):
		if flat[i].y == flat[i - 1].y:
			n += 1
		else:
			runs.append(n)
			n = 1
	runs.append(n)
	for i in runs.size() - 1:
		assert_eq(runs[i], 3, "uniform runs (3:1 slope), the last what is left: %s" % [runs])


func test_history_interpolates_between_snapshots_and_never_extrapolates() -> void:
	var h := FishingSnapHistory.new()
	var st := FishingState.new()
	var r := FishingRiderState.new()
	st.riders.append(r)
	r.x_m = 10.0
	h.push(1.0, st)
	r.x_m = 20.0
	h.push(1.1, st)
	assert_almost_eq(h.value_at(0, "x", 1.05, -1.0), 15.0, 0.001)
	assert_eq(h.value_at(0, "x", 0.5, -1.0), 10.0)
	assert_eq(h.value_at(0, "x", 9.0, -1.0), 20.0)
	assert_eq(h.value_at(3, "x", 1.0, -1.0), -1.0, "unknown rider")
	assert_almost_eq(h.mean_spacing(), 0.1, 0.0001)


func test_history_starts_over_after_a_gap_or_a_rewind_and_stays_small() -> void:
	var h := FishingSnapHistory.new()
	var st := FishingState.new()
	st.riders.append(FishingRiderState.new())
	for k in 20:
		h.push(float(k) * 0.1, st)
	assert_eq(h.entries.size(), FishingSnapHistory.CAPACITY)
	h.push(10.0, st)
	assert_eq(h.entries.size(), 1, "a long gap starts over")
	h.push(5.0, st)
	assert_eq(h.entries.size(), 1, "an earlier time starts over")
	h.push(5.0, st)
	assert_eq(h.entries.size(), 1, "the same time replaces")


func test_history_keeps_the_values_the_view_draws() -> void:
	var r := FishingRiderState.new()
	r.lure_dx = 3.0
	r.lure_depth = 7.0
	r.pitch_deg = 4.0
	var v := FishingSnapHistory.values_of(r)
	for k in FishingSnapHistory.KEYS:
		assert_true(v.has(k), k)
	assert_eq(float(v["ldx"]), 3.0)
	assert_eq(float(v["lz"]), 7.0)
	assert_eq(float(v["pitch"]), 4.0)


func test_no_narrow_slot_sinks_between_higher_floor_pieces() -> void:
	var s := FishingScenery.new()
	var map: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/fishing/map.json")
	)
	s.world = FishingWorld.from_map(map, 1)
	for cam_m in [2000.0, 5600.0, 8000.0, 11000.0, 14000.0]:
		s.view_depth_m = s.target_view_depth(cam_m)
		var shown := s.floor_art.profile(s, roundf(cam_m * 2.0), INF)
		for i in range(1, shown.size() - 1):
			var e := shown[i]
			if float(e["sx1"]) - float(e["sx0"]) >= FishingFloor.NARROW_PX:
				continue
			var low := maxf(float(shown[i - 1]["top"]), float(shown[i + 1]["top"]))
			assert_lte(float(e["top"]), low, "no slot at %s m, piece %d" % [cam_m, i])
		var body := FishingFloor.body_band(shown)
		for e in shown:
			assert_lte(int(e["band"]), body, "one body fill under every cap")
