extends GutTest
## FishingView and FishingLaneView build and run headless from hand-made states (ride out, picks,
## fights, landing, cool-down) for 1-4 lanes, and draw what brief 3.5 asks: the fish left of
## x 420 inside the water, the line ending at its mouth or the lure, the boat flipped going home,
## the slot's colour on the boat, the local border and the day cycle.

const FX := preload("res://tests/games/fishing/view/fishing_view_fixtures.gd")


func _view(n: int, local_slot: int = 0) -> FishingView:
	var game: FishingGame = autofree(FX.make_game(n, local_slot))
	var v := FX.make_view(game, self)
	autofree(v)
	return v


func _run(v: FishingView, seconds: float, dt: float = 0.05) -> void:
	for _i in roundi(seconds / dt):
		v.advance(dt)


func test_builds_one_lane_per_slot_for_every_lane_count() -> void:
	for n in range(1, 5):
		var v := _view(n, n - 1)
		assert_eq(v.lanes.size(), n)
		assert_eq(v.local_slot(), n - 1)
		for i in n:
			var lv := v.lane_view(i)
			assert_eq(lv.position.y, float(FishingLayout.lane_y(i, n)))
			assert_eq(lv.lane_h, FishingLayout.lane_h(n))
			assert_eq(lv.local, i == n - 1)
		_run(v, 0.5)
		assert_not_null(v.audio)


func test_ride_out_scrolls_with_trainer_power_and_shows_the_wake() -> void:
	var v := _view(1)
	var l := v.game.state.lane(0)
	l.state = FishingConst.ST_RIDE_OUT
	l.power_w = 200.0
	l.cadence_ema = 90.0
	var lv := v.lane_view(0)
	var x0 := lv.world_x
	_run(v, 3.0)
	assert_gt(lv.world_x, x0 + 20.0, "the backdrop moves")
	assert_true(lv.model["moving"])
	assert_true(lv.boat.wake_on)
	assert_false(lv.model["flipped"])
	assert_ne(lv.boat.crank.angle(), 0.0, "the crank turns with cadence")


func test_cool_down_motors_home_with_the_boat_flipped() -> void:
	var v := _view(2)
	for l in v.game.state.lanes:
		FX.set_home(l)
	var lv := v.lane_view(1)
	var x0 := lv.world_x
	_run(v, 3.0)
	assert_true(lv.model["flipped"])
	assert_lt(lv.world_x, x0, "heading home scrolls the other way")
	assert_true(lv.boat.wake_on)
	assert_eq(lv.boat.position.x, float(FishingConst.BOAT_X1), "flipped about the boat's span")


func test_pick_draws_hints_with_the_selected_one_highlighted() -> void:
	var v := _view(4, 2)
	var l := v.game.state.lane(2)
	FX.set_pick(l, 2)
	_run(v, 0.3)
	var lv := v.lane_view(2)
	assert_eq(lv.model["state"], FishingConst.ST_PICK)
	assert_false(lv.model["fish_visible"])
	for i in 3:
		var r := lv._hint_rect(int(l.hints[3 * i]), FishingLayout.hint_x(l.hints[3 * i + 1]), 4)
		assert_lt(r.end.x, float(FishingConst.HUD_X), "hint %d left of the HUD zone" % i)
		assert_gte(r.position.y, 0.0)
		assert_lte(r.end.y, float(lv.lane_h))


func test_fight_places_the_fish_left_of_420_in_the_water_and_the_line_at_its_mouth() -> void:
	for n in range(1, 5):
		var v := _view(n)
		for sp in 4:
			for l in v.game.state.lanes:
				FX.set_fight(l, sp, 500.0, 1.0, 0.2, 0.1)
			_run(v, 0.1)
			for lv in v.lanes:
				var r: Rect2 = lv.model["fish_rect"]
				assert_true(lv.model["fish_visible"], "a fish shows (n %d sp %d)" % [n, sp])
				assert_lte(r.end.x, 420.0, "left of x 420 (n %d sp %d)" % [n, sp])
				assert_gte(r.position.y, float(lv.water_y) - 0.5)
				assert_lte(r.end.y, float(lv.water_y + lv.water_h) + 0.5)
				var end: Vector2 = lv.model["line_end"]
				assert_almost_eq(end.x, r.position.x, 0.01, "the line ends at the mouth")
				assert_almost_eq(lv.model["rod_tip"].x, float(FishingConst.ROD_TIP_X), 10.0)


func test_strain_bends_the_rod_and_straightens_the_line() -> void:
	var v := _view(1)
	var l := v.game.state.lane(0)
	FX.set_fight(l, 2, 60.0, 0.5, 0.0, 0.9)
	_run(v, 0.1)
	var lv := v.lane_view(0)
	var slack_tension: float = lv.model["tension"]
	l.strain = 1.0
	l.slack = 0.0
	_run(v, 0.1)
	assert_gt(lv.model["tension"], slack_tension)
	assert_eq(FishingRig.line_sag(100.0, 0.0, 1.0), 0.0, "straight under strain")
	assert_gt(
		FishingRig.line_sag(100.0, 1.0, 0.0),
		FishingRig.line_sag(100.0, 0.2, 0.0),
		"sags with slack"
	)


func test_reel_shows_the_lure_and_spins_the_reel_forward() -> void:
	var v := _view(1)
	FX.set_reel(v.game.state.lane(0), 70.0)
	_run(v, 1.0)
	var lv := v.lane_view(0)
	assert_eq(lv.model["line_end"].x, float(FishingLayout.hint_x(70.0)))
	assert_gt(lv.model["line_mps"], 0.0, "retrieving")


func test_a_run_reverses_the_reel() -> void:
	var v := _view(1)
	var l := v.game.state.lane(0)
	FX.set_fight(l, 1, 40.0)
	l.fish.run_active = true
	_run(v, 1.0)
	assert_lt(v.lane_view(0).model["line_mps"], 0.0, "line going out")
	assert_eq(v.lane_view(0).model["tension"], 1.0)


func test_landing_brings_the_fish_aboard_then_hides_it() -> void:
	var v := _view(2)
	var l := v.game.state.lane(0)
	FX.set_landing(l, 5.0, 0.6)
	_run(v, 0.1)
	var lv := v.lane_view(0)
	assert_true(lv.model["fish_visible"])
	l.state_t = 24.5
	_run(v, 0.1)
	assert_lt(lv.model["fish_rect"].position.x, 110.0, "near the boat")
	l.state_t = 28.0
	_run(v, 0.1)
	assert_false(lv.model["fish_visible"], "aboard")


func test_marlin_runs_are_jumps_with_leaps_and_splashes() -> void:
	var v := _view(1)
	var l := v.game.state.lane(0)
	FX.set_fight(l, 3, 120.0, 0.6)
	_run(v, 0.1)
	l.fish.run_active = true
	v.advance(0.05)
	v.advance(0.05)
	var lv := v.lane_view(0)
	assert_true(lv.model["jumping"], "state edge -> jump cue for a jumping species")
	var above := false
	for _i in 30:
		v.advance(0.05)
		var r: Rect2 = lv.model["fish_rect"]
		if r.position.y < float(lv.sky_h):
			above = true
	assert_true(above, "the fish leaves the water")
	assert_gt(lv.effects.active(), 0, "splashes")


func test_state_edges_raise_effects_and_landed_flash() -> void:
	var v := _view(2)
	var l := v.game.state.lane(1)
	FX.set_fight(l, 0, 10.0)
	_run(v, 0.1)
	l.state = FishingConst.ST_LANDING
	l.state_t = 29.0
	_run(v, 0.05)
	l.state = FishingConst.ST_REEL
	l.fish_landed = 1
	v.game.state.catches.assign([1, 0, FishingConst.GRADE_TROPHY])
	v.advance(0.05)
	var kinds: Array = v.cue_log.map(func(c: Dictionary) -> String: return str(c["k"]))
	assert_has(kinds, FishingCues.CUE_LANDED)
	var ids := v.lane_view(1).effects.active_ids()
	assert_has(ids, "catch_flash")
	assert_has(ids, "trophy_badge")
	_run(v, 3.0)
	assert_eq(v.lane_view(1).effects.active(), 0, "effects dissolve away")


func test_double_hookup_links_the_lanes() -> void:
	var v := _view(3)
	for i in 2:
		FX.set_fight(v.game.state.lane(i), 1, 50.0)
	_run(v, 0.1)
	v.game.state.hookup_level = 2
	v.advance(0.05)
	var link: Array = v.cue_log.filter(
		func(c: Dictionary) -> bool: return c["k"] == FishingCues.CUE_DOUBLE_HOOKUP
	)
	assert_eq(link.size(), 1)
	assert_eq(link[0]["lanes"], [0, 1])


func test_fx_event_is_used_when_the_module_has_it() -> void:
	var ctx := FishingFakes.make_ctx(2, 0, "e2e_2min")
	var game: FishingGame = autofree(FishingGame.new())
	game.configure(ctx)
	var v := game.make_view() as FishingView
	add_child_autofree(v)
	assert_true(v.events_connected)
	FX.set_fight(game.state.lane(0), 1, 60.0)
	v.advance(0.05)
	game.fx_event.emit(FishingEvents.run(0, 1, 2, 20.0))
	game.fx_event.emit(FishingEvents.landed(1, 2, 1, 55.0, 120, 1.5))
	game.state.lane(0).fish.run_active = true
	v.advance(0.05)
	var kinds: Array = v.cue_log.map(func(c: Dictionary) -> String: return str(c["k"]))
	assert_eq(
		kinds, [FishingCues.CUE_RUN, FishingCues.CUE_LANDED], "events only, no state-edge doubles"
	)
	assert_has(v.audio.played, "fishing_zip")


func test_boat_and_angler_are_recoloured_to_the_slot() -> void:
	var v := _view(4)
	for i in 4:
		var hull := v.lane_view(i).boat.hull
		var mat := hull.material as ShaderMaterial
		assert_not_null(mat, "lane %d hull has PaletteSwap" % i)
		assert_eq(PaletteSwap.keys_of(mat)[0], FishingPalette.KEY_LIGHT)
		assert_eq(PaletteSwap.swaps_of(mat)[0], PaletteSwap.slot_ramp(i, 2)[0])
		assert_not_null(v.lane_view(i).boat.angler.material)


func test_cosmetics_follow_the_lane_indexes() -> void:
	var v := _view(1)
	var l := v.game.state.lane(0)
	l.cosmetics.assign([2, 1, 3, 1])
	v.advance(0.05)
	var cv := v.lane_view(0).cosmetic_values
	assert_eq(cv["line"], "#9bd23c", "the second line colour")
	assert_eq(cv["canopy"], "stripes")
	assert_eq(cv["trim"], "#f2665a")
	assert_eq(cv["pennant"], "trophy")
	assert_true(v.lane_view(0).boat.trophy_pennant)
	l.cosmetics.assign([0, 0, 0, 0])
	v.advance(0.05)
	assert_eq(v.lane_view(0).cosmetic_values["line"], "")


func test_day_cycle_steps_through_three_skies_with_a_two_second_wipe() -> void:
	assert_eq(FishingPalette.day_variant(0.0, 900.0), 0)
	assert_eq(FishingPalette.day_variant(301.0, 900.0), 1)
	assert_eq(FishingPalette.day_variant(899.0, 900.0), 2)
	assert_eq(FishingPalette.day_variant(2000.0, 900.0), 2)
	assert_almost_eq(FishingPalette.wipe_progress(301.0, 900.0), 0.5, 0.001)
	assert_eq(FishingPalette.wipe_progress(303.0, 900.0), 1.0)
	var v := _view(1)
	v.game.state.t = v.game.state.trip_total_s / 3.0 + 1.0
	v.advance(0.05)
	var lv := v.lane_view(0)
	assert_eq(lv.model["variant"], 1)
	assert_true(lv.sky_b.visible, "mid-wipe")
	v.game.state.t += 2.0
	v.advance(0.05)
	assert_false(lv.sky_b.visible, "wipe done")


func test_sky_and_water_use_palette_colours_only() -> void:
	var palette := {}
	for c: Variant in (
		JSON.parse_string(FileAccess.get_file_as_string("res://assets/fishing/art.json"))["palette"]
	):
		palette[Color(str(c)).to_html(false)] = true
	for v in 3:
		var img := FishingPalette.gradient(32, 40, FishingPalette.SKY_VARIANTS[v])
		for y in 40:
			for x in 32:
				assert_true(
					palette.has(img.get_pixel(x, y).to_html(false)), "sky %d (%d,%d)" % [v, x, y]
				)
				if not palette.has(img.get_pixel(x, y).to_html(false)):
					return


func test_hud_zone_cover_is_dithered_on_its_left_edge() -> void:
	var img := FishingPalette.gradient(
		20, 8, FishingPalette.SKY_VARIANTS[1], FishingPalette.COVER_EDGE
	)
	var clear := 0
	for y in 8:
		for x in 20:
			if img.get_pixel(x, y).a < 0.5:
				assert_lt(x, FishingPalette.COVER_EDGE)
				clear += 1
	assert_gt(clear, 0)


func test_every_sprite_loads_at_its_art_json_size() -> void:
	FishingSprites.clear_cache()
	for id in FishingSprites.ids():
		var tex := FishingSprites.texture(id)
		assert_not_null(tex, id)
		assert_has(
			[FishingSprites.SRC_PNG, FishingSprites.SRC_FALLBACK, FishingSprites.SRC_PLACEHOLDER],
			FishingSprites.source(id)
		)
		assert_eq(FishingSprites.size_of(id), Vector2i(tex.get_size()), id)
	var tail := FishingSprites.part("fish_marlin", "tail")
	assert_eq(tail.get_width(), FishingSprites.part_rect("fish_marlin", "tail").size.x)
	assert_eq(FishingSprites.anchor("rig_crank"), Vector2i(5, 5), "align center")


func test_slot_colours_are_paired_with_distinct_shapes_and_patterns() -> void:
	var shapes := {}
	var patterns := {}
	for i in 4:
		var look := Wl.slot_look(i)
		shapes[look["shape"]] = true
		patterns[look["pattern"]] = true
		var pts := FishingView.shape_points(str(look["shape"]), Vector2.ZERO, 4.0)
		assert_gte(pts.size(), 3)
	assert_eq(shapes.size(), 4)
	assert_eq(patterns.size(), 4)
	assert_eq(FishingView.shape_points("triangle", Vector2.ZERO, 4.0).size(), 3)
	assert_ne(
		FishingView.shape_points("square", Vector2.ZERO, 4.0),
		FishingView.shape_points("diamond", Vector2.ZERO, 4.0)
	)


func test_only_the_local_lane_gets_the_patterned_border() -> void:
	var v := _view(4, 1)
	for i in 4:
		assert_eq(v.lane_view(i).local, i == 1)
		assert_eq(v.lane_view(i).look["pattern"], Wl.slot_look(i)["pattern"])


func test_legs_reach_the_pedals_with_the_knee_forward() -> void:
	for k in 16:
		var a := TAU * float(k) / 16.0
		var p := FishingRig.pedals(FishingRig.CRANK_HUB, FishingRig.CRANK_R, a)
		for foot in p:
			var leg := FishingRig.leg(FishingRig.HIP, foot)
			assert_almost_eq(leg[0].distance_to(leg[1]), FishingRig.THIGH, 0.01)
			assert_almost_eq(leg[1].distance_to(leg[2]), FishingRig.SHIN, 0.01)
			assert_almost_eq(leg[2].distance_to(foot), 0.0, 0.05, "the foot is on the pedal")
			assert_gte(leg[1].x, minf(leg[0].x, leg[2].x) - 0.01, "the knee bends forward")


func test_rod_bends_toward_the_line_with_tension() -> void:
	var rest := FishingRig.rod(FishingRig.ROD_BASE, FishingRig.ROD_TIP, 0.0, Vector2.DOWN)
	var bent := FishingRig.rod(FishingRig.ROD_BASE, FishingRig.ROD_TIP, 1.0, Vector2.DOWN)
	assert_eq(rest[-1], FishingRig.ROD_TIP)
	assert_almost_eq(bent[-1].y - rest[-1].y, FishingRig.ROD_BEND_PX, 0.001)


func test_cues_from_events_and_state_edges_match() -> void:
	var cues := FishingCues.new()
	assert_eq(
		cues.from_event(FishingEvents.cast(1, 0, 2, 55.0))[0], {"k": "cast", "l": 1, "d": 55.0}
	)
	assert_eq(cues.from_event(FishingEvents.jump(0, 1, 4, 25.0, 2))[0]["leaps"], 2)
	assert_eq(cues.from_event(FishingEvents.replacement(0, 1)), [] as Array[Dictionary])
	var game: FishingGame = autofree(FX.make_game(2))
	var st := game.state
	assert_eq(cues.diff(st), [] as Array[Dictionary], "the first call only learns")
	st.lane(0).state = FishingConst.ST_CAST
	cues.diff(st)
	st.lane(0).state = FishingConst.ST_REEL
	st.lane(0).lure_d = 64.0
	var c := cues.diff(st)
	assert_eq(c, [{"k": "cast", "l": 0, "d": 64.0}] as Array[Dictionary])
	st.lane(0).state = FishingConst.ST_STRIKE
	assert_eq(cues.diff(st)[0]["k"], FishingCues.CUE_BITE)
	FX.set_fight(st.lane(0), 1, 50.0, 0.5, 0.9, 0.0)
	assert_eq(cues.diff(st)[0]["k"], FishingCues.CUE_HOOKUP)
	st.lane(0).fish.off_line = true
	st.lane(0).strain = 0.0
	assert_eq(cues.diff(st)[0]["k"], FishingCues.CUE_SNAP, "the strain before the reset decides")
	st.trip_over = true
	assert_eq(cues.diff(st).back()["k"], FishingCues.CUE_TRIP_OVER)


func test_every_layer_draws_in_the_tree_without_errors() -> void:
	var v := _view(4, 0)
	FX.set_reel(v.game.state.lane(0), 55.0)
	FX.set_fight(v.game.state.lane(1), 3, 150.0, 0.8, 0.5, 0.3)
	FX.set_pick(v.game.state.lane(2), 0)
	FX.set_landing(v.game.state.lane(3), 3.0, 0.3)
	v.game.state.lane(1).cosmetics.assign([1, 2, 1, 1])
	await wait_process_frames(6)
	assert_true(v.lane_view(0).model.get("lure", false), "the line layer drew the lure")
	for l in v.game.state.lanes:
		FX.set_home(l)
	await wait_process_frames(3)
	assert_true(v.lane_view(0).model["flipped"])
