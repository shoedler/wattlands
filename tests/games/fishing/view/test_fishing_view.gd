extends GutTest
## The one-ocean view from hand-made riders: boats, camera, fish and wobblers under the water
## tint, the menu hints, lines, cues, effects and the client's interpolation.

const FX := preload("res://tests/games/fishing/view/fishing_view_fixtures.gd")


func _view(game: FishingGame) -> FishingView:
	add_child_autofree(game)
	var v := FishingView.new()
	v.game = game
	add_child_autofree(v)
	return v


func _run(v: FishingView, frames: int = 30, dt: float = 0.05) -> void:
	for i in frames:
		v.advance(dt)


func test_one_boat_per_rider_with_the_local_boat_drawn_last() -> void:
	var g := FX.make_game(3, 1)
	var v := _view(g)
	_run(v, 1)
	assert_eq(v.boats.size(), 3)
	assert_eq(v.local_slot(), 1)
	var layer := v.boat_view(1).get_parent()
	assert_eq(layer.get_child(layer.get_child_count() - 1), v.boat_view(1))


func test_the_view_registers_itself_for_the_hud() -> void:
	var g := FX.make_game(1)
	var v := _view(g)
	_run(v, 1)
	assert_eq(g.get_meta(FishingView.META), v)


func test_the_camera_keeps_a_driving_boat_left_of_centre_looking_ahead() -> void:
	var g := FX.make_game(1)
	FX.set_drive(g.state.rider(0), 3000.0, 5.0, 1)
	var v := _view(g)
	_run(v, 80)
	var p: Vector2 = v.model["boats"][0]
	var lead := FishingView.lead_px(5.0)
	assert_gt(lead, 0.0, "the camera leads ahead with speed")
	assert_almost_eq(p.x, roundf(FishingView.CAM_DRIVE_U * 640.0) - lead, 3.0)
	assert_eq(p.y, float(FishingScenery.SURF_Y))


func test_heading_home_mirrors_the_camera_and_flips_the_boat() -> void:
	var g := FX.make_game(1)
	FX.set_drive(g.state.rider(0), 3000.0, 5.0, -1)
	var v := _view(g)
	_run(v, 80)
	var p: Vector2 = v.model["boats"][0]
	var x := roundf(FishingView.CAM_DRIVE_U * 640.0) - FishingView.lead_px(5.0)
	assert_almost_eq(p.x, float(FishingScenery.W) - x, 3.0)
	assert_eq(v.boat_view(0).scale.x, -1.0)


func test_a_far_camera_goal_is_jumped_to() -> void:
	var g := FX.make_game(1)
	FX.set_drive(g.state.rider(0), 100.0)
	var v := _view(g)
	_run(v, 5)
	g.state.rider(0).x_m = 6000.0
	_run(v, 1)
	var p: Vector2 = v.model["boats"][0]
	var lead := FishingView.lead_px(g.state.rider(0).v_mps)
	assert_almost_eq(p.x, roundf(FishingView.CAM_DRIVE_U * 640.0) - lead, 3.0)


func test_signed_trim_picks_bow_up_and_braking_poses_by_whole_pixels_never_rotating() -> void:
	var g := FX.make_game(1)
	var r := g.state.rider(0)
	FX.set_drive(r, 3000.0, 7.0)
	r.pitch_deg = 14.0
	var v := _view(g)
	_run(v, 10)
	var b := v.boat_view(0)
	assert_eq(b.rotation, 0.0, "sprites are never rotated")
	assert_eq(b.pose(), FishingRig.POSE_MAX, "a hard surge lifts the bow 8 px")
	assert_eq(b.hull.texture, FishingSprites.frame("boat_hull", FishingRig.POSE_MAX))
	assert_gte(b.crew_frame(), 2 * FishingArtGrids.CREW_FRAMES, "the rider leans in")
	var flag_up := b.pixel_of(FishingRig.FLAG.position)
	var stern_up := b.pixel_of(Vector2i(FishingRig.STERN_X, FishingRig.WATERLINE))
	r.pitch_deg = 0.0
	_run(v, 2)
	assert_eq(b.pose(), 0)
	var flag := b.pixel_of(FishingRig.FLAG.position)
	var stern := b.pixel_of(Vector2i(FishingRig.STERN_X, FishingRig.WATERLINE))
	assert_eq(flag.y - flag_up.y, 8.0, "the bow came down 8 px")
	assert_eq(stern_up.y - stern.y, 2.0, "the stern had squatted 2 px")
	r.pitch_deg = -6.0
	_run(v, 2)
	assert_eq(b.pose(), FishingRig.POSE_MIN, "a power cut digs the bow in")
	assert_eq(b.pixel_of(FishingRig.FLAG.position).y - flag.y, 4.0, "bow down 4 px")
	var lifted := b.pixel_of(Vector2i(FishingRig.STERN_X, FishingRig.WATERLINE))
	assert_eq(stern.y - lifted.y, 2.0, "stern up 2 px")
	assert_eq(b.crew_frame() / FishingArtGrids.CREW_FRAMES, 3, "the rider sits back")


func test_poses_step_one_pixel_at_a_time_from_stern_to_bow() -> void:
	for pose in range(FishingRig.POSE_MIN, FishingRig.POSE_MAX + 1):
		var prev := FishingRig.tilt_dy(pose, 0)
		var run := 0
		for x in range(1, FishingRig.HULL_SIZE.x):
			var dy := FishingRig.tilt_dy(pose, x)
			assert_lte(absi(dy - prev), 1, "pose %d steps 1 px at x %d" % [pose, x])
			if dy != prev:
				assert_gte(run, 4, "pose %d steps are at least 5 px long" % pose)
				run = 0
			else:
				run += 1
			prev = dy
	assert_eq(FishingRig.tilt_dy(FishingRig.POSE_MAX, FishingRig.BOW_X), -8)
	assert_eq(FishingRig.tilt_dy(FishingRig.POSE_MIN, FishingRig.BOW_X), 4)
	assert_eq(FishingRig.hull_frame(0), 0, "the level hull is the first frame")
	var seen := {}
	for pose in range(FishingRig.POSE_MIN, FishingRig.POSE_MAX + 1):
		seen[FishingRig.hull_frame(pose)] = true
	assert_eq(seen.size(), FishingRig.POSE_MAX - FishingRig.POSE_MIN + 1, "one frame per pose")
	assert_eq(FishingSprites.count("boat_hull"), seen.size())
	assert_eq(FishingBoatView.pose_for(0.5), 0)
	assert_eq(FishingBoatView.pose_for(-6.0), FishingRig.POSE_MIN)


func test_other_boats_float_on_the_far_row_hazier_and_cut_at_their_waterline() -> void:
	var g := FX.make_game(2)
	FX.set_drive(g.state.rider(0), 1000.0)
	FX.set_drive(g.state.rider(1), 1000.0)
	var v := _view(g)
	_run(v, 10)
	var me := v.boat_view(0)
	var other := v.boat_view(1)
	assert_false(me.far)
	assert_true(other.far)
	assert_eq(me.position.y, float(FishingScenery.SURF_Y))
	assert_eq(other.position.y, float(FishingScenery.SURF_Y - FishingView.FAR_ROW_PX))
	assert_gt(other.position.y, float(FishingScenery.HORIZON_Y), "still on the water")
	var m := other.hull.material as ShaderMaterial
	assert_eq(m.shader, FishingPaletteMap.shader())
	assert_eq(float(m.get_shader_parameter("under_y")), other.position.y, "its own shadow slab")
	assert_eq(int(m.get_shader_parameter("count")), FishingBoatView.FAR_FROM.size(), "lighter")
	var mine := me.hull.material as ShaderMaterial
	assert_eq(int(mine.get_shader_parameter("count")), 0)
	assert_eq(float(mine.get_shader_parameter("under_y")), float(FishingScenery.SURF_Y))


func test_other_boats_far_away_are_not_drawn() -> void:
	var g := FX.make_game(2)
	FX.set_drive(g.state.rider(0), 1000.0)
	FX.set_drive(g.state.rider(1), 4000.0)
	var v := _view(g)
	_run(v, 10)
	assert_true(v.boat_view(0).visible)
	assert_false(v.boat_view(1).visible)


func test_driving_spins_the_prop_and_keeps_the_rod_stowed() -> void:
	var g := FX.make_game(1)
	FX.set_drive(g.state.rider(0), 2000.0, 6.0)
	var v := _view(g)
	_run(v, 40)
	var b := v.boat_view(0)
	assert_eq(b.fishing, 0.0)
	assert_gt(b.prop_drive, 1.0)
	assert_lt(b.crew_frame(), FishingArtGrids.CREW_FRAMES, "the driving pose: hand on the tiller")


func test_fishing_flips_the_clutch_raises_the_rod_and_moves_the_hands() -> void:
	var g := FX.make_game(1)
	FX.set_wait(g.state.rider(0), 2000.0)
	var v := _view(g)
	_run(v, 40)
	var b := v.boat_view(0)
	assert_eq(b.fishing, 1.0)
	assert_gte(b.crew_frame(), FishingArtGrids.CREW_FRAMES, "the fishing pose: clutch aft")
	assert_lt(b.rod_points()[-1].y, FishingRig.ROD_BASE.y - 8.0, "the rod tips up")


func test_a_wobbler_shows_at_its_depth_while_waiting() -> void:
	var g := FX.make_game(1)
	FX.set_wait(g.state.rider(0), 3000.0, 4, -12.0, 20.0)
	var v := _view(g)
	_run(v, 20)
	var p: Vector2 = v.model["lure"][0]
	assert_gt(p.y, float(FishingScenery.SURF_Y) + 10.0)
	var x := v.to_screen(3000.0 - 12.0, 20.0).x
	assert_almost_eq(p.x, x, 1.0, "at its x")


func test_a_hooked_fish_shows_with_its_mouth_toward_the_boat_and_tinted() -> void:
	var g := FX.make_game(1)
	FX.set_fight(g.state.rider(0), 7000.0, 8, 40.0, 300.0)
	var v := _view(g)
	_run(v, 40)
	var fish: Rect2 = v.model["fish"][0]
	assert_gt(fish.size.x, 30.0, "the grouper sprite")
	var boat: Vector2 = v.model["boats"][0]
	assert_lt(fish.position.x, boat.x, "behind the stern heading out")
	var spr := v.get_node("Underwater/Fish0") as Sprite2D
	assert_true(spr.flip_h, "mouth on the right, toward the boat")
	var m := spr.material as ShaderMaterial
	var band := FishingScenery.band_at(300.0)
	assert_eq(FishingPaletteMap.shift_of(m), FishingPaletteMap.shift_for(band), "by its band")
	assert_gt(FishingPaletteMap.shift_of(m), 0, "a dark subject on the deep water")


func test_no_fish_shows_outside_a_fight() -> void:
	var g := FX.make_game(1)
	FX.set_drive(g.state.rider(0), 3000.0)
	var v := _view(g)
	_run(v, 5)
	assert_false((v.model["fish"] as Dictionary).has(0))
	assert_false((v.get_node("Underwater/Fish0") as Sprite2D).visible)


func test_the_line_ends_at_the_fish_mouth() -> void:
	var g := FX.make_game(1)
	FX.set_fight(g.state.rider(0), 3000.0, 4, 30.0, 25.0)
	var v := _view(g)
	_run(v, 20)
	var end := v._line_end(g.state.rider(0))
	var fish: Rect2 = v.model["fish"][0]
	assert_true(fish.grow(1.0).has_point(end))


func test_menu_hints_show_as_silhouettes_and_the_picked_one_is_lit() -> void:
	var g := FX.make_game(1)
	FX.set_menu(g.state.rider(0), 3000.0, 1)
	var v := _view(g)
	_run(v, 10)
	var hints: Array = v.model["hints"]
	assert_eq(hints.size(), 3)
	var lit := 0
	for h: Dictionary in hints:
		lit += 1 if bool(h["selected"]) else 0
	assert_eq(lit, 1)
	assert_true(bool(hints[1]["selected"]))
	var m0 := v.get_node("Underwater/Hint0").material as ShaderMaterial
	var m1 := v.get_node("Underwater/Hint1").material as ShaderMaterial
	assert_true(FishingPaletteMap.is_flat(m0), "a flat silhouette")
	assert_false(FishingPaletteMap.is_flat(m1), "the picked fish shows itself")


func test_hints_stay_above_the_floor() -> void:
	var g := FX.make_game(1)
	var r := g.state.rider(0)
	FX.set_menu(r, 100.0)
	r.hints[2] = 300.0
	var v := _view(g)
	_run(v, 10)
	var floor_y := v.scenery.y_of_depth(g.state.world.floor_depth_m(100.0 + r.hints[1]))
	assert_lt((v.model["hints"][0]["pos"] as Vector2).y, floor_y)


func test_the_winch_turns_while_the_line_comes_in() -> void:
	var g := FX.make_game(1)
	var r := g.state.rider(0)
	FX.set_fight(r, 3000.0, 4, 40.0, 30.0)
	var v := _view(g)
	_run(v, 5)
	r.fish.d = 38.0
	v.advance(0.05)
	assert_gt(v.boat_view(0).winch_mps, 1.0)


func test_cues_come_from_every_event_type() -> void:
	var cases := {
		FishingEvents.cast(0, 1, 5.0, 10.0): FishingCues.CUE_CAST,
		FishingEvents.bite(0, 1): FishingCues.CUE_BITE,
		FishingEvents.hookup(0, 1, 1, false): FishingCues.CUE_HOOKUP,
		FishingEvents.run(0, 1, 2, 4.0): FishingCues.CUE_RUN,
		FishingEvents.snap(0): FishingCues.CUE_SNAP,
		FishingEvents.thrown(0): FishingCues.CUE_THROWN,
		FishingEvents.turn(0, -1): FishingCues.CUE_TURN,
		FishingEvents.time_up(): FishingCues.CUE_TIME_UP,
		FishingEvents.trip_over(): FishingCues.CUE_TRIP_OVER,
	}
	for e: Dictionary in cases:
		var out := FishingCues.from_event(e)
		assert_eq(out.size(), 1)
		assert_eq(str(out[0]["k"]), str(cases[e]))
	var j := FishingCues.from_event(FishingEvents.jump(2, 1, 2, 3.0, 3))
	assert_eq(int(j[0]["leaps"]), 3)
	assert_eq(int(j[0]["l"]), 2)
	var l := FishingCues.from_event(FishingEvents.landed(1, 3, 1, 12.0, 80, 1.0))
	assert_eq(int(l[0]["grade"]), FishingConst.GRADE_TROPHY)
	assert_eq(FishingCues.from_event(FishingEvents.landing(0, 1)).size(), 0)


func test_state_edges_raise_cues_without_events() -> void:
	var g := FX.make_game(1)
	var r := g.state.rider(0)
	FX.set_menu(r, 500.0)
	var cues := FishingCues.new()
	assert_eq(cues.diff(g.state).size(), 0, "the first call only learns")
	r.action = FishingConst.A_CAST
	assert_eq(str(cues.diff(g.state)[0]["k"]), FishingCues.CUE_CAST)
	r.action = FishingConst.A_FIGHT
	assert_eq(str(cues.diff(g.state)[0]["k"]), FishingCues.CUE_HOOKUP)
	r.fish_landed = 1
	r.heading = -1
	var ks: Array = cues.diff(g.state).map(func(c: Dictionary) -> String: return str(c["k"]))
	assert_has(ks, FishingCues.CUE_LANDED)
	assert_has(ks, FishingCues.CUE_TURN)
	g.state.time_up = true
	assert_eq(str(cues.diff(g.state)[0]["k"]), FishingCues.CUE_TIME_UP)


func test_a_cast_event_splashes_and_a_catch_sparkles() -> void:
	var g := FX.make_game(1)
	FX.set_wait(g.state.rider(0), 3000.0)
	var v := _view(g)
	_run(v, 2)
	v.on_fx_event(FishingEvents.cast(0, 4, -12.0, 30.0))
	v.on_fx_event(FishingEvents.landed(0, 4, 0, 30.0, 70, 1.0))
	v.advance(0.05)
	assert_has(v.effects.active_ids(), "fx_splash")
	assert_has(v.effects.active_ids(), "fx_sparkle")
	assert_eq(str(v.cue_log[-1]["k"]), FishingCues.CUE_LANDED)


func test_a_jump_lifts_the_fish_out_of_the_water() -> void:
	var g := FX.make_game(1)
	FX.set_fight(g.state.rider(0), 7000.0, 7, 40.0, 20.0)
	var v := _view(g)
	_run(v, 5)
	v.on_fx_event(FishingEvents.jump(0, 1, 2, 3.0, 2))
	_run(v, 10)
	var fish: Rect2 = v.model["fish"][0]
	assert_lt(fish.position.y, float(FishingScenery.SURF_Y), "airborne mid-leap")


func test_effects_play_once_and_end() -> void:
	var fx := FishingEffects.new()
	add_child_autofree(fx)
	fx.spawn("fx_splash", 10.0, 118.0)
	assert_eq(fx.active_ids(), ["fx_splash"])
	for i in 20:
		fx.tick(0.1, 0.0)
	assert_eq(fx.active_ids().size(), 0)


func test_the_view_draws_the_whole_width() -> void:
	var g := FX.make_game(1)
	var v := _view(g)
	_run(v, 1)
	assert_eq(FishingScenery.W, FishingConst.PIXEL_W)
	assert_eq(FishingScenery.H, FishingConst.PIXEL_H)


func test_a_client_draws_boats_between_snapshots() -> void:
	var g := FX.make_game(2, 1, Wl.CLIENT)
	var r := g.state.rider(0)
	FX.set_drive(r, 1000.0)
	var v := _view(g)
	for k in 6:
		g.state.tick = 2 * k
		g.state.t = 0.1 * float(k)
		r.x_m = 1000.0 + float(k)
		v.advance(0.1)
	var x := float(v.shown(0)["x"])
	assert_lt(x, 1005.0, "drawn behind the newest snapshot")
	assert_gt(x, 1002.0)
	var t0 := v.render_t
	v.advance(0.016)
	assert_gte(v.render_t, t0, "the render clock never runs backwards")


## The view inside a SubViewport of `size` (the flex PixelViewport's art size).
func _sized_view(game: FishingGame, size: Vector2i) -> FishingView:
	add_child_autofree(game)
	var vp := SubViewport.new()
	vp.size = size
	add_child_autofree(vp)
	var v := FishingView.new()
	v.game = game
	vp.add_child(v)
	return v


func test_the_view_lays_out_from_its_art_size() -> void:
	for size: Vector2i in [Vector2i(860, 360), Vector2i(640, 340), Vector2i(568, 320)]:
		var g := FX.make_game(1)
		FX.set_drive(g.state.rider(0), 3000.0, 5.0, 1)
		var v := _sized_view(g, size)
		_run(v, 80)
		assert_eq(v.art_size(), size)
		var p: Vector2 = v.model["boats"][0]
		var want := roundf(float(size.x) * FishingView.CAM_DRIVE_U) - FishingView.lead_px(5.0)
		assert_almost_eq(p.x, want, 3.0, "the drive spot scales with the width at %s" % size)
		var deepest := v.scenery.y_of_depth(v.scenery.view_depth_m)
		assert_almost_eq(
			deepest,
			float(size.y - FishingScenery.FLOOR_GAP),
			0.5,
			"the deepest floor keeps its gap to the bottom at %s" % size
		)


func test_solo_draws_the_fish_between_sim_steps() -> void:
	var g := FX.make_game(1)
	var r := g.state.rider(0)
	FX.set_fight(r, 7000.0, 4, 30.0, 40.0)
	var v := _view(g)
	_run(v, 3, 1.0 / 60.0)
	var xs: Array[float] = []
	for step in 4:
		g.state.tick += 1
		g.state.t += Wl.SIM_DT
		r.fish.d += 1.0
		for f in 3:
			v.advance(Wl.SIM_DT / 3.0)
			xs.append(-float(v.shown(0)["fdx"]))
	for i in range(1, xs.size()):
		assert_gt(xs[i] - xs[i - 1], -1e-6, "never backwards")
		assert_lt(xs[i] - xs[i - 1], 0.6, "no whole-step jumps: frame %d" % i)
	assert_gt(xs[-1] - xs[0], 2.0, "it follows the fish")


func test_the_fish_pulls_on_a_taut_steep_line_and_tires_when_spent() -> void:
	var g := FX.make_game(1)
	var r := g.state.rider(0)
	FX.set_fight(r, 7000.0, 4, 20.0, 60.0, 0.9, 0.0)
	var v := _view(g)
	_run(v, 10)
	var k := int(v.model["fish_frame"][0])
	assert_true(
		k == FishingSprites.FISH_PULL15 or k == FishingSprites.FISH_PULL30, "pulling: frame %d" % k
	)
	r.strain = 0.0
	r.slack = 0.6
	_run(v, 4)
	assert_has(FishingSprites.FISH_SWIM, int(v.model["fish_frame"][0]), "a slack line: swimming")
	r.fish.s = 0.05
	_run(v, 2)
	assert_eq(int(v.model["fish_frame"][0]), FishingSprites.FISH_TIRED)


func test_heave_moves_the_hull_by_whole_pixels_and_never_lifts_the_prop_out() -> void:
	assert_eq(FishingView.heave_px(0.0), 0)
	assert_eq(FishingView.heave_px(0.06), FishingView.HEAVE_UP_PX, "on the plane")
	assert_eq(FishingView.heave_px(-0.12), -FishingView.HEAVE_DOWN_PX, "squatting at the hump")
	var g := FX.make_game(1)
	var r := g.state.rider(0)
	FX.set_drive(r, 3000.0, 14.0)
	r.heave_m = 0.06
	var v := _view(g)
	_run(v, 4)
	var b := v.boat_view(0)
	assert_eq(b.heave_px, FishingView.HEAVE_UP_PX)
	var hub := b.pixel_of(Vector2i(FishingRig.PROP_HUB))
	assert_gt(hub.y, float(FishingScenery.SURF_Y), "the prop stays in the water")


func test_floor_slopes_and_the_view_depth_hold_still_as_the_camera_scrolls() -> void:
	var hi := {"top": 200.0, "x0": 4000.0, "sx0": 10.0, "sx1": 60.0}
	var lo := {"top": 208.0, "x0": 4100.0, "sx0": 60.0, "sx1": 160.0}
	var run := FishingFloor.ramp_run(hi, lo)
	for shift in [1.0, 2.0, 7.0]:
		var hi2 := hi.duplicate()
		var lo2 := lo.duplicate()
		for e: Dictionary in [hi2, lo2]:
			e["sx0"] = float(e["sx0"]) - shift
			e["sx1"] = float(e["sx1"]) - shift
		assert_eq(FishingFloor.ramp_run(hi2, lo2), run, "the slope pick ignores the camera")
	var g := FX.make_game(1)
	var r := g.state.rider(0)
	FX.set_drive(r, 5000.0, 6.0)
	var v := _view(g)
	_run(v, 60)
	var changes := 0
	var last := v.scenery.view_depth_m
	for i in 120:
		r.x_m += 0.3
		v.advance(0.05)
		if v.scenery.view_depth_m != last:
			changes += 1
		last = v.scenery.view_depth_m
	assert_lt(changes, 90, "the view depth rests between retargets")
