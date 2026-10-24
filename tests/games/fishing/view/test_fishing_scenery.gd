extends GutTest
## The code-drawn ocean, the boat's rig geometry and the client's snapshot history.

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
	assert_almost_eq(s.target_view_depth(-20.0), maxf(_world.floor_depth_m(300.0), 3.0), 2.0)
	assert_gt(s.target_view_depth(6500.0), 250.0)
	assert_eq(s.target_view_depth(8500.0), FishingScenery.ABYSS_M, "no floor: the abyss")


func test_the_far_water_band_lies_between_the_horizon_and_the_surface() -> void:
	assert_eq(FishingScenery.HORIZON_Y, FishingScenery.SURF_Y - FishingScenery.FAR_ROWS)
	assert_lt(FishingView.FAR_ROW_PX, FishingScenery.FAR_ROWS, "far boats sit on the band")


func test_the_deepest_floor_in_sight_stays_above_the_hud() -> void:
	assert_lt(FishingScenery.SURF_Y + FishingScenery.FLOOR_ROWS, FishingConst.PANIC_Y)


func test_water_darkens_with_depth_in_flat_steps() -> void:
	assert_eq(FishingScenery.water_at(0.0), FishingPalette.SEA_1)
	var prev := -1
	for d: float in [0.0, 10.0, 30.0, 60.0, 120.0, 250.0, 400.0, 600.0]:
		var i := FishingPalette.SEA.find(FishingScenery.water_at(d))
		assert_gte(i, prev)
		prev = i
	assert_eq(FishingScenery.water_at(600.0), FishingPalette.VOID)


func test_the_floor_is_sand_in_the_shallows_and_dark_in_the_deep() -> void:
	assert_eq(FishingScenery.floor_at(4.0), FishingPalette.SAND_1)
	assert_eq(FishingScenery.floor_at(15.0), FishingPalette.SAND_2)
	for d: float in [30.0, 60.0, 150.0, 250.0, 400.0]:
		assert_ne(FishingScenery.floor_at(d), FishingScenery.water_at(d), "floor at %s m reads" % d)
		var ridge := FishingScenery.floor_at(d, true)
		assert_ne(ridge, FishingScenery.floor_at(d), "the ridge differs from the floor")
		assert_ne(ridge, FishingScenery.water_at(d), "and from the water")


func test_the_tint_grows_with_depth_but_never_hides_a_fish() -> void:
	assert_lt(FishingScenery.fog_at(1.0), FishingScenery.fog_at(100.0))
	assert_lte(FishingScenery.fog_at(1000.0), 0.45)


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
				s.paint_front(c, cam, 1.0)
	)
	add_child_autofree(layer)
	layer.queue_redraw()
	await wait_process_frames(2)
	assert_eq(s.view_depth_m, s.target_view_depth(8800.0))


func test_legs_reach_both_pedals_with_the_knee_forward() -> void:
	for a in 8:
		var p := FishingRig.pedals(float(a) * PI / 4.0)
		assert_almost_eq(p[0].distance_to(FishingRig.BB), FishingRig.CRANK_R, 0.01)
		assert_almost_eq((p[0] + p[1]) * 0.5, FishingRig.BB, Vector2(0.01, 0.01))
		var l := FishingRig.leg(FishingRig.HIP, p[0])
		assert_almost_eq(l[0].distance_to(l[1]), FishingRig.THIGH, 0.05)
		assert_almost_eq(l[2].distance_to(p[0]), 0.0, 0.05)
		assert_gte(l[1].x, minf(l[0].x, l[2].x) - 0.01, "the knee bends forward")


func test_the_clutch_flips_aft_to_fish() -> void:
	var drive := FishingRig.clutch_tip(0.0)
	var fish := FishingRig.clutch_tip(1.0)
	assert_gt(drive.x, FishingRig.CLUTCH_PIVOT.x, "toward the bow to drive")
	assert_lt(fish.x, FishingRig.CLUTCH_PIVOT.x, "aft to fish")


func test_the_rod_is_stowed_flat_and_raised_to_fish() -> void:
	var stowed := FishingRig.rod(0.0, 0.0, Vector2.DOWN)
	var raised := FishingRig.rod(1.0, 0.0, Vector2.DOWN)
	assert_almost_eq(stowed[-1], FishingRig.ROD_STOW_TIP, Vector2(0.01, 0.01))
	assert_almost_eq(raised[-1], FishingRig.ROD_FISH_TIP, Vector2(0.01, 0.01))
	var bent := FishingRig.rod(1.0, 1.0, Vector2.DOWN)
	assert_almost_eq(bent[-1].y - raised[-1].y, FishingRig.ROD_BEND_PX, 0.01)


func test_the_line_sags_with_slack_and_straightens_under_strain() -> void:
	assert_gt(FishingRig.line_sag(100.0, 1.0, 0.0), FishingRig.line_sag(100.0, 0.0, 0.0))
	assert_eq(FishingRig.line_sag(100.0, 0.0, 1.0), 0.0)
	var pts := FishingRig.line(Vector2.ZERO, Vector2(100, 0), 0.0, 1.0)
	for p in pts:
		assert_almost_eq(p.y, 0.0, 0.001)


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


func test_audio_hums_with_cadence_screams_on_a_run_and_plays_the_fanfare() -> void:
	var a := FishingAudio.new()
	add_child_autofree(a)
	var r := FishingRiderState.new()
	r.cadence_ema = 90.0
	a.update(0.05, r, 0.0)
	assert_true(a.hum_on)
	assert_almost_eq(a.hum_pitch, 1.0, 0.01)
	r.action = FishingConst.A_FIGHT
	r.fish.run_active = true
	a.update(0.05, r, 0.0)
	assert_true(a.drag_on)
	r.cadence_ema = 0.0
	a.update(0.05, r, 0.0)
	assert_false(a.hum_on)
	a.cue({"k": FishingCues.CUE_LANDED, "l": 0}, true)
	for i in 10:
		a.update(0.05, r, 0.0)
	assert_has(a.played, "fishing_note_3")


func test_audio_clicks_while_the_winch_brings_line_in() -> void:
	var a := FishingAudio.new()
	add_child_autofree(a)
	var r := FishingRiderState.new()
	r.x_m = 5000.0
	for i in 20:
		a.update(0.05, r, 3.0)
	assert_has(a.played, "fishing_click")
	assert_does_not_have(a.played, "fishing_gull", "no gulls out at sea")
	assert_eq(FishingAudio.sound_names().size(), FishingAudio.SOUNDS.size() + 3)
