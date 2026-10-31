extends GutTest
## The world around the riders: every canvas, the road's blend into a course, props and spots that
## peers agree on, and the crowd, which never asks for an effort in the warm-up (BRIEF 4.6.8).

const U := preload("res://tests/games/workout/workout_test_util.gd")
const V := preload("res://src/games/workout/view/workout_ride_view.gd")
const CANVASES: Array[Vector2] = [
	Vector2(853, 480),
	Vector2(960, 540),
	Vector2(1146, 480),
	Vector2(1280, 720),
	Vector2(1700, 950),
]
const FRAME := 1.0 / 60.0


func _view(content: String, humans: int = 1, bots: int = 0) -> WorkoutRideView:
	var g := U.game(content, U.players(humans, bots))
	autofree(g)
	var view := g.make_view() as WorkoutRideView
	add_child_autofree(view)
	view.set_process(false)
	return view


func _course_index(state: WorkoutState) -> int:
	for i in state.phases.size():
		if state.is_course_phase(i):
			return i
	return -1


func _sprint_index(state: WorkoutState) -> int:
	for i in state.phases.size():
		if WorkoutSession.is_sprint(state.phase(i)):
			return i
	return -1


# --- canvases ------------------------------------------------------------------------


func test_every_canvas_is_covered_and_anchored_to_the_bottom() -> void:
	for canvas in CANVASES:
		var view := _view("easy_30", 8)
		view.canvas_override = canvas
		view.refresh()
		var road: PackedFloat64Array = view.model["road"]
		var cols := int(ceil(canvas.x / float(WorkoutTrackLayer.COLUMN_W)))
		assert_eq(road.size(), cols, "the road covers %s" % canvas)
		assert_eq(view.stage.position.y, canvas.y - 540.0, "bottom-anchored at %s" % canvas)
		assert_eq(view.near_trees.cover_width, canvas.x, "strips cover %s" % canvas)
		var runs: PackedInt32Array = view.model["runs"]
		assert_true(
			float(runs[runs.size() - 2]) >= canvas.x, "the road's runs reach the right edge"
		)
		assert_eq((view.model["markers"] as Array).size(), 8, "8 riders build at %s" % canvas)


func test_above_the_sky_tile_a_flat_fill_covers_the_tall_canvas() -> void:
	var view := _view("easy_30")
	view.canvas_override = Vector2(1700, 950)
	view.refresh()
	assert_eq(view.sky_fill.position.y, -view.stage.position.y, "from the canvas' top")
	assert_eq(view.sky_fill.size, Vector2(1700, 950 - 720), "down to the sky tile")
	view.canvas_override = Vector2(960, 540)
	view.refresh()
	assert_eq(view.sky_fill.size.y, 0.0, "nothing to fill on the base")


func test_the_edge_clamp_follows_the_canvas() -> void:
	for canvas in CANVASES:
		var view := _view("easy_30", 2)
		view.canvas_override = canvas
		view.game.state.rider(2).speed.distance_m = 5000.0
		view.refresh()
		var far := view.marker(2)
		assert_eq(int(far["edge"]), 1)
		assert_almost_eq(float(far["x"]), canvas.x - V.EDGE_MARGIN_RIGHT, 0.001, "at %s" % canvas)


func test_the_canvas_can_change_while_riding() -> void:
	var view := _view("easy_30")
	view.refresh()
	assert_eq((view.model["road"] as PackedFloat64Array).size(), 480)
	view.canvas_override = Vector2(1280, 720)
	view.refresh()
	assert_eq((view.model["road"] as PackedFloat64Array).size(), 640)
	assert_eq(view.stage.position.y, 180.0)


func test_the_rider_stays_put_on_a_wider_canvas_and_blocks_cull_by_it() -> void:
	var view := _view("easy_30")
	view.canvas_override = Vector2(1700, 950)
	view.refresh()
	assert_eq(int(view.marker(1)["draw_x"]), int(V.RIDER_X))
	var wide: int = (view.model["blocks"] as Array).size()
	view.canvas_override = Vector2(853, 480)
	view.refresh()
	assert_true((view.model["blocks"] as Array).size() <= wide, "fewer on the narrow canvas")


# --- road ----------------------------------------------------------------------------


func test_the_road_blends_in_over_8_seconds_and_back_out() -> void:
	var view := _view("rolling_road")
	var state := view.game.state
	var i := _course_index(state)
	var start := state.phase_start_s(i)
	state.plan_t = start
	assert_eq(V.road_blend(state, i), 0.0, "at the phase's start")
	state.plan_t = start + 4.0
	assert_almost_eq(V.road_blend(state, i), 0.5, 1e-9)
	state.plan_t = start + 8.0
	assert_eq(V.road_blend(state, i), 1.0, "after 8 s")
	state.plan_t = start + 500.0
	assert_eq(V.road_blend(state, i), 1.0)
	var after := state.phase_start_s(i + 1)
	state.plan_t = after
	assert_eq(V.road_blend(state, i + 1), 1.0, "the next phase starts where it was")
	state.plan_t = after + 8.0
	assert_eq(V.road_blend(state, i + 1), 0.0, "and settles")
	assert_eq(V.road_blend(state, i - 1), 0.0, "a phase before it is flat")


func test_flat_gives_road_y_everywhere_and_one_run() -> void:
	var view := _view("sweet_spot")
	for y in view.model["road"] as PackedFloat64Array:
		assert_eq(y, V.ROAD_Y)
	assert_eq((view.model["runs"] as PackedInt32Array).size(), 3, "one run on the flat")


func test_the_local_rider_stands_at_road_y_on_a_climb() -> void:
	var view := _view("rolling_road")
	var state := view.game.state
	var i := _course_index(state)
	state.phase_index = i
	var r := state.rider(1)
	r.phase_index = i
	r.course_d = 2000.0
	state.plan_t = state.phase_start_s(i) + 100.0
	view.refresh()
	var road: PackedFloat64Array = view.model["road"]
	var col := int(V.RIDER_X) / WorkoutTrackLayer.COLUMN_W
	assert_almost_eq(road[col], V.ROAD_Y, 1.5, "the world moves around the rider")


func test_runs_merge_equal_heights() -> void:
	var road := PackedFloat64Array([384.0, 384.2, 383.6, 383.0, 390.0])
	var runs := WorkoutRoadLayer.runs_of(road, 2)
	assert_eq(runs, PackedInt32Array([0, 6, 384, 6, 8, 383, 8, 10, 390]))


func test_the_foreground_stays_under_the_lowest_wheel() -> void:
	var view := _view("rolling_road", 8)
	var base_y := float(view.kit.plane("foreground")["y"])
	view.refresh()
	assert_eq(view.foreground.position.y, base_y, "on the flat, its own place")
	var road := PackedFloat64Array()
	road.resize(480)
	road.fill(V.ROAD_MAX_Y)
	var markers: Array = []
	for peer: int in view.game.state.order:
		var m := {"x": V.RIDER_X, "edge": 0}
		view._place(m, view.game.state, view.game.state.rider(peer), 0.0, road)
		markers.append(m)
	view._set_foreground_y(markers)
	assert_eq(view.foreground.position.y, V.ROAD_MAX_Y + 9.0 + float(V.FOREGROUND_CLEAR_PX))


# --- props and spots -----------------------------------------------------------------


func test_the_bank_tile_is_the_same_every_time_and_painted() -> void:
	var px := WorkoutBankTile.indices()
	assert_eq(px, WorkoutBankTile.indices(), "deterministic")
	assert_eq(px.size(), WorkoutBankTile.W * WorkoutBankTile.H)
	var tones := {}
	for y in WorkoutBankTile.GROUND_H:
		for x in range(0, WorkoutBankTile.W, 3):
			tones[px[y * WorkoutBankTile.W + x] / WorkoutBankTile.INDEX_SCALE] = true
	assert_false(tones.has(WorkoutBankTile.NOTHING), "the ground has no holes")
	for tone: int in [
		WorkoutBankTile.SHADE,
		WorkoutBankTile.BASE,
		WorkoutBankTile.LIGHT,
		WorkoutBankTile.EARTH,
		WorkoutBankTile.EARTH_DARK,
		WorkoutBankTile.STONE,
	]:
		assert_true(tones.has(tone), "tone %d is on the ground" % tone)


func test_the_bank_tile_covers_the_highest_road_and_its_stamps_fit() -> void:
	var top := roundi(WorkoutRideView.ROAD_MIN_Y) + WorkoutBankLayer.TOP_BELOW_CONTACT
	assert_true(WorkoutBankLayer.BOTTOM - top <= WorkoutBankTile.GROUND_H)
	var cell := WorkoutBankTile.STAMP_CELL
	assert_true(WorkoutBankTile.stamp_count() * cell.x <= WorkoutBankTile.W)
	for rows: Array in WorkoutBankTile.STAMPS:
		assert_true(rows.size() <= cell.y)
		for row: String in rows:
			assert_true(row.length() <= cell.x, row)


func test_the_bank_ramp_follows_the_morning() -> void:
	var view := _view("easy_30")
	var kit := view.kit
	var dawn := WorkoutBankTile.ramp(
		kit.tod_color(0, "bank"), kit.tod_color(0, "bank_hi"), kit.tod_color(0, "rider_tint")
	)
	var day := WorkoutBankTile.ramp(
		kit.tod_color(31, "bank"), kit.tod_color(31, "bank_hi"), kit.tod_color(31, "rider_tint")
	)
	assert_eq(dawn.size(), WorkoutBankTile.NOTHING, "one entry per index")
	var bank := kit.tod_color(31, "bank")
	assert_almost_eq(day[WorkoutBankTile.BASE].y, bank.g, 0.001, "base is the row's bank")
	assert_true(day[WorkoutBankTile.DEEP].y < day[WorkoutBankTile.BASE].y)
	assert_true(day[WorkoutBankTile.PALE].y > day[WorkoutBankTile.BASE].y)
	assert_true(dawn[WorkoutBankTile.EARTH].x < day[WorkoutBankTile.EARTH].x, "earth dims at dawn")


func test_interval_blocks_are_muted_toward_the_ground_and_keep_their_zone_colour() -> void:
	var view := _view("threshold")
	view.refresh()
	var block: Dictionary = (view.model["blocks"] as Array)[0]
	assert_true(WorkoutArt.ZONE_THRESHOLD != Color.BLACK)
	var zone: Color = block["color"]
	var fill := WorkoutTrackLayer.muted(zone, view.track.ground)
	assert_true(fill.a < 1.0, "the ground shows through")
	assert_true(fill.s < zone.s or fill.v < zone.v, "quieter than the zone's colour")


func test_a_bucket_hash_has_no_visible_repeat() -> void:
	var picks: Array = []
	for k in 256:
		picks.append(WorkoutPropLayer.bucket_hash(k, 7) % 8)
	var repeats := 0
	for k in range(8, 256):
		if picks[k] == picks[k - 8]:
			repeats += 1
	assert_lt(repeats, 80, "low bits do not cycle every 8 buckets (%d of 248)" % repeats)
	assert_eq(WorkoutPropLayer.bucket_hash(5, 7), WorkoutPropLayer.bucket_hash(5, 7), "pure")
	assert_gte(WorkoutPropLayer.bucket_hash(-5, 7), 0, "negative buckets are fine")


func test_props_are_fixed_by_the_world_not_the_frame() -> void:
	var view := _view("easy_30")
	var a := view.mid_props.entries(1000.0, 2000.0)
	var b := view.mid_props.entries(1000.0, 2000.0)
	assert_eq(a, b)
	var near := view.near_props.entries(0.0, 5200.0)
	for e in near:
		assert_eq(str(e["kind"]), "windpump")
	assert_gt(near.size(), 0, "a pump in 5200 px")


func test_spots_are_the_same_for_the_same_seed_and_leave_the_game_rng_alone() -> void:
	var g := U.game("easy_30", U.players(1))
	autofree(g)
	var before := g.ctx.rng.state
	var a := WorkoutSpots.build(7, 1800.0)
	var b := WorkoutSpots.build(7, 1800.0)
	assert_eq(a, b, "every peer sees the same flock")
	assert_ne(a, WorkoutSpots.build(8, 1800.0), "another seed, another morning")
	assert_eq(g.ctx.rng.state, before, "ctx.rng untouched")
	assert_gt(a.size(), 10)
	var prev := 0.0
	for s in a:
		var gap := float(s["t0"]) - prev
		assert_between(gap, WorkoutSpots.GAP_MIN_S, WorkoutSpots.GAP_MAX_S, "a gap")
		prev = float(s["t0"])


func test_spots_are_well_formed_and_chosen_by_plan_time() -> void:
	var spots := WorkoutSpots.build(7, 3000.0)
	var last_tractor_gone := 0.0
	for s in spots:
		match str(s["kind"]):
			"flock":
				assert_between(int(s["n"]), 5, 11, "birds")
				assert_between(float(s["y"]), 90.0, 200.0, "flock y")
				assert_between(float(s["vx"]), 18.0, 30.0, "flock vx")
			"tractor":
				assert_eq(float(s["vx"]), 6.0)
				assert_gte(float(s["t0"]), last_tractor_gone, "one field, one tractor")
				last_tractor_gone = float(s["t0"]) + float(s["dur"])
			"balloon":
				assert_gte(float(s["t0"]) / 3000.0, WorkoutSpots.BALLOON_MIN_P, "day only")
			_:
				fail_test("unknown spot %s" % s["kind"])
	var first: Dictionary = spots[0]
	assert_eq(WorkoutSpots.active(spots, float(first["t0"]) - 1.0), [] as Array[Dictionary])
	assert_true(WorkoutSpots.active(spots, float(first["t0"]) + 1.0).has(first))


func test_spots_are_rebuilt_when_a_client_gets_a_longer_timeline() -> void:
	var view := _view("easy_30")
	var state := view.game.state
	var short := state.total_s()
	assert_eq(view._spots_for_s, short)
	state.phases[0].duration_s += 600.0
	view.refresh()
	assert_eq(view._spots_for_s, short + 600.0)


# --- the crowd -----------------------------------------------------------------------


func test_cheers_never_in_the_warm_up_and_for_a_scored_sprint() -> void:
	var e2e := U.game("e2e", U.players(1))
	autofree(e2e)
	var i := _sprint_index(e2e.state)
	assert_almost_eq(e2e.state.phase_start_s(i), 90.0, 1.0, "e2e's free sprint at 90 s")
	assert_false(WorkoutCrowd.cheers_for(e2e.state, i), "a warm-up sprint: no crowd, no gantry")
	assert_eq(WorkoutCrowd.cheering_phase(e2e.state, 90.0), -1)
	var easy := U.game("easy_30", U.players(1))
	autofree(easy)
	var j := _sprint_index(easy.state)
	var start := easy.state.phase_start_s(j)
	assert_almost_eq(start, 660.0, 1.0, "easy_30's first sprint")
	assert_true(WorkoutCrowd.cheers_for(easy.state, j))
	assert_false(WorkoutCrowd.cheers_for(easy.state, j - 1), "not a sprint")


func test_the_crowd_opens_6_seconds_ahead_and_closes_with_the_sprint() -> void:
	var view := _view("easy_30")
	var state := view.game.state
	var j := _sprint_index(state)
	var start := state.phase_start_s(j)
	state.phase_index = j - 1
	assert_eq(WorkoutCrowd.cheering_phase(state, start - 6.1), -1)
	assert_eq(WorkoutCrowd.cheering_phase(state, start - 5.9), j, "from 6 s before it")
	state.phase_index = j
	assert_eq(WorkoutCrowd.cheering_phase(state, start + 1.0), j)
	assert_eq(WorkoutCrowd.cheering_phase(state, start + state.phase(j).duration_s), -1)


func test_nobody_pops_in_on_screen() -> void:
	var view := _view("easy_30")
	var state := view.game.state
	var j := _sprint_index(state)
	state.phase_index = j
	state.plan_t = state.phase_start_s(j)
	state.rider(1).speed.distance_m = 500.0
	view.refresh()
	assert_true(view.crowd_layer.active(), "a rejoin mid-sprint captures on the first frame")
	var w: Dictionary = view.crowd_layer.windows[0]
	var world_x := 500.0 * V.VISUAL_PX_PER_M
	assert_eq(float(w["w0"]), world_x + 960.0, "it starts past the screen's right edge")
	var seen := WorkoutCrowd.spectators(
		float(w["w0"]), float(w["w0"]) + 400.0, 7, world_x, world_x + 960.0
	)
	assert_eq(seen, [], "none on screen at activation")


func test_spectators_stand_14_to_22_px_apart_inside_their_window() -> void:
	var people := WorkoutCrowd.spectators(1000.0, 3000.0, 7, 0.0, 10000.0)
	assert_gt(people.size(), 90)
	var prev := -1.0
	for p: Dictionary in people:
		var x := float(p["x"])
		assert_between(x, 1000.0, 3000.0, "inside the window")
		if prev >= 0.0:
			assert_between(x - prev, 10.0, 26.0, "bucket 18, 4 px either way")
		prev = x
		assert_between(int(p["kind"]), 0, 7, "one of 8 spectators")
	assert_eq(people, WorkoutCrowd.spectators(1000.0, 3000.0, 7, 0.0, 10000.0), "peers agree")


func test_the_crowd_goes_when_it_has_scrolled_off() -> void:
	var view := _view("easy_30")
	var state := view.game.state
	var j := _sprint_index(state)
	state.phase_index = j
	state.plan_t = state.phase_start_s(j)
	view.refresh()
	assert_true(view.crowd_layer.active())
	state.plan_t = state.phase_start_s(j + 1) + 1.0
	state.phase_index = j + 1
	view.refresh()
	assert_true(view.crowd_layer.active(), "the last ones are still on the road")
	state.rider(1).speed.distance_m += 500.0
	view.refresh()
	assert_false(view.crowd_layer.active(), "and gone past")


func test_the_crowd_claps_on_the_viewers_cadence_only() -> void:
	var view := _view("easy_30", 2)
	var state := view.game.state
	state.rider(1).cadence_rpm = 0.0
	state.rider(2).cadence_rpm = 120.0
	var seen := {}
	for i in 60:
		view.game.sim_alive()
		view.advance(FRAME)
		seen[view.hands_up(state.rider(1))] = true
	assert_eq(seen.size(), 1, "the viewer stopped, so did the crowd")
