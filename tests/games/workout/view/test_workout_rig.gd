extends GutTest
## What each rider shows (WorkoutRig and the view's markers): poses with their hysteresis, no-slip
## wheels, the group's formation and paint order, and the three clocks never mixing.

const U := preload("res://tests/games/workout/workout_test_util.gd")
const FRAME := 1.0 / 60.0


func _facts(overrides: Dictionary = {}) -> Dictionary:
	var f := {
		"rescue": false,
		"afk": false,
		"disconnected": false,
		"v_mps": 9.0,
		"cadence_rpm": 90.0,
		"power_w": 150.0,
		"ftp": 200.0,
		"sprint_phase": false,
		"grade_pct": 0.0,
	}
	f.merge(overrides, true)
	return f


func _pose(prev: int, overrides: Dictionary) -> int:
	return WorkoutRig.pose_of(prev, _facts(overrides))


func _view(humans: int, bots: int = 0, local: int = 1, content := "easy_30") -> WorkoutRideView:
	var g := U.game(content, U.players(humans, bots), Wl.SOLO, local)
	autofree(g)
	var view := g.make_view() as WorkoutRideView
	add_child_autofree(view)
	view.set_process(false)
	return view


# --- poses ---------------------------------------------------------------------------


func test_a_rider_who_has_gone_stops_or_sits_up() -> void:
	const P := WorkoutRig.POSE_SEAT
	assert_eq(_pose(P, {"afk": true, "v_mps": 0.4}), WorkoutRig.POSE_STOP)
	assert_eq(_pose(P, {"disconnected": true, "v_mps": 0.0}), WorkoutRig.POSE_STOP)
	assert_eq(_pose(P, {"afk": true, "v_mps": 5.0}), WorkoutRig.POSE_SITUP)
	assert_eq(_pose(P, {"disconnected": true, "v_mps": 0.5}), WorkoutRig.POSE_SITUP)
	assert_eq(_pose(P, {"rescue": true, "v_mps": 0.0}), WorkoutRig.POSE_SITUP, "rescue never stops")
	assert_eq(_pose(P, {"rescue": true, "v_mps": 9.0}), WorkoutRig.POSE_SITUP)


func test_a_sprint_stands_at_120_percent_and_holds_to_95() -> void:
	const P := WorkoutRig.POSE_SEAT
	const S := WorkoutRig.POSE_STAND
	assert_eq(_pose(P, {"sprint_phase": true, "power_w": 239.0}), P, "just under")
	assert_eq(_pose(P, {"sprint_phase": true, "power_w": 240.0}), S)
	assert_eq(_pose(S, {"sprint_phase": true, "power_w": 190.0}), S, "95% holds a stander")
	assert_eq(_pose(S, {"sprint_phase": true, "power_w": 189.0}), P, "under it, he sits")
	assert_eq(_pose(P, {"sprint_phase": true, "power_w": 190.0}), P, "and 95% does not stand him")
	assert_eq(_pose(S, {"power_w": 190.0}), P, "the sprint is over")


func test_a_climb_stands_at_95_percent_and_holds_to_85() -> void:
	const P := WorkoutRig.POSE_SEAT
	const S := WorkoutRig.POSE_STAND
	assert_eq(_pose(P, {"grade_pct": 4.0, "power_w": 189.0}), P)
	assert_eq(_pose(P, {"grade_pct": 4.0, "power_w": 190.0}), S)
	assert_eq(_pose(P, {"grade_pct": 3.9, "power_w": 400.0}), P, "too flat")
	assert_eq(_pose(S, {"grade_pct": 4.0, "power_w": 170.0}), S, "85% holds a stander")
	assert_eq(_pose(S, {"grade_pct": 4.0, "power_w": 169.0}), P)
	assert_eq(_pose(P, {"grade_pct": 6.0, "power_w": 300.0, "cadence_rpm": 0.0}), P, "no pedalling")
	assert_eq(_pose(S, {"grade_pct": 6.0, "power_w": 300.0, "cadence_rpm": 0.0}), P)


func test_gone_outranks_standing() -> void:
	var climbing := {"grade_pct": 6.0, "power_w": 300.0, "rescue": true}
	assert_eq(_pose(WorkoutRig.POSE_STAND, climbing), WorkoutRig.POSE_SITUP)


func test_the_sheet_addressing_rule() -> void:
	var rows := {"seat": 0, "stand": 4, "situp": 8, "stop": 12}
	assert_eq(WorkoutRig.cell_of(WorkoutRig.POSE_SEAT, 0, rows), Vector2i(0, 0))
	assert_eq(WorkoutRig.cell_of(WorkoutRig.POSE_SEAT, 23, rows), Vector2i(5, 3))
	assert_eq(WorkoutRig.cell_of(WorkoutRig.POSE_STAND, 7, rows), Vector2i(1, 5))
	assert_eq(WorkoutRig.cell_of(WorkoutRig.POSE_SITUP, 12, rows), Vector2i(0, 10))
	assert_eq(
		WorkoutRig.cell_of(WorkoutRig.POSE_STOP, 17, rows), Vector2i(0, 12), "stop ignores it"
	)


# --- wheels and shear ----------------------------------------------------------------


func test_wheels_do_not_slip_against_the_road() -> void:
	var turn_m: float = TAU * WorkoutRig.WHEEL_RADIUS_PX / WorkoutRideView.VISUAL_PX_PER_M
	assert_almost_eq(WorkoutRig.wheel_revs(turn_m), 1.0, 1e-9, "one turn a circumference")
	assert_eq(WorkoutRig.wheel_frame(0.0), 0)
	assert_eq(WorkoutRig.wheel_frame(turn_m * 0.5 + 1e-6), WorkoutRig.WHEEL_FRAMES / 2)
	assert_eq(WorkoutRig.wheel_frame(turn_m * 3.0 + 1e-6), 0, "whole turns come back")
	assert_almost_eq(
		WorkoutRig.wheel_revs(9.0), 1.54, 0.01, "9 m/s is 1.54 rev/s, as the spec says"
	)


func test_the_shear_stays_on_the_grid_and_meets_both_wheels() -> void:
	for pitch in range(-6, 7):
		var slices := WorkoutRig.shear_slices(pitch, 88, 20, 60)
		assert_eq(slices.size(), absi(pitch) + 1, "one slice per pixel of pitch %d" % pitch)
		var at := 0
		for s in slices:
			assert_eq(s.x, at, "columns are contiguous")
			at = s.y
			if s.x <= 20 and 20 < s.y:
				assert_eq(s.z, 0, "the rear hub's column stays")
			if s.x <= 60 and 60 < s.y:
				assert_eq(s.z, pitch, "the front hub's column has the pitch")
		assert_eq(at, 88, "every column drawn")


# --- formation -----------------------------------------------------------------------


func test_no_two_riders_in_a_lane_overlap_and_all_stay_on_screen() -> void:
	for local in 8:
		for a in 8:
			var xa := WorkoutRideView.RIDER_X + float(WorkoutRig.formation_dx(a, local))
			assert_true(xa >= 0.0 and xa <= float(WorkoutArt.W), "rider %d, local %d" % [a, local])
			for b in 8:
				if a != b and WorkoutRig.lane_dy(a) == WorkoutRig.lane_dy(b):
					var gap := absi(
						WorkoutRig.formation_dx(a, local) - WorkoutRig.formation_dx(b, local)
					)
					assert_true(gap >= 88, "riders %d and %d stand %d px apart" % [a, b, gap])


func test_the_local_rider_is_on_its_spot_and_last_for_every_ordinal() -> void:
	for local in 8:
		var peer := local + 1
		var view := _view(8, 0, peer)
		var markers: Array = view.model["markers"]
		assert_eq(int(markers.back()["peer"]), peer, "markers.back() is the local rider")
		assert_eq(int(view.marker(peer)["draw_x"]), int(WorkoutRideView.RIDER_X))
		var order: Array = view.model["draw_order"]
		assert_eq(order.size(), 8)
		for i in 8:
			assert_true(order.has(i), "draw_order holds marker %d" % i)


func test_paint_order_is_far_lane_first_and_the_local_rider_last_in_its_lane() -> void:
	var view := _view(8, 0, 4)
	var markers: Array = view.model["markers"]
	var order: Array = view.model["draw_order"]
	var prev_lane := -100
	var local_lane := int(view.marker(4)["lane"])
	var seen_local := false
	for i: int in order:
		var m: Dictionary = markers[i]
		assert_true(int(m["lane"]) >= prev_lane, "lanes back to front")
		prev_lane = int(m["lane"])
		if seen_local:
			assert_ne(int(m["lane"]), local_lane, "nobody in the local lane paints after it")
		if int(m["peer"]) == 4:
			seen_local = true


func test_a_marker_keeps_the_map_position_and_adds_the_formation() -> void:
	var view := _view(4)
	var other := view.marker(3)
	assert_almost_eq(float(other["x"]), WorkoutRideView.RIDER_X, 0.001, "x is the map position")
	assert_eq(int(other["edge"]), 0)
	var spot := int(WorkoutRideView.RIDER_X) + WorkoutRig.formation_dx(2, 0)
	assert_true(absi(int(other["draw_x"]) - spot) <= 3, "its place in the group, wandering 3 px")
	for key: String in [
		"rear_y", "front_y", "pitch", "pose", "crank_frame", "wheel_frame", "slot", "lane", "grey"
	]:
		assert_true(other.has(key), key)
	assert_eq(int(other["rear_y"]), roundi(WorkoutRideView.ROAD_Y) + WorkoutRig.lane_dy(2))


func test_the_pitch_is_clamped_and_wheels_stand_on_their_own_contact() -> void:
	var view := _view(1, 0, 1, "rolling_road")
	var road := PackedFloat64Array()
	road.resize(480)
	for i in 480:
		road[i] = 400.0 - float(i)
	var m := {"x": 300.0, "edge": 0}
	view._place(m, view.game.state, view.game.state.rider(1), 0.0, road)
	assert_eq(int(m["pitch"]), -6, "nose up, clamped")
	assert_lt(int(m["front_y"]), int(m["rear_y"]))
	assert_eq(int(m["rear_y"]) - int(m["front_y"]), 20, "the wheels keep their real contact")


func test_states_show_by_pose_bubble_and_grey() -> void:
	var view := _view(4)
	var state := view.game.state
	state.rider(2).rescue = true
	state.rider(3).afk = true
	state.rider(4).connected = false
	view.refresh()
	assert_eq(str(view.marker(1)["bubble"]), "")
	assert_eq(float(view.marker(1)["grey"]), 0.0)
	assert_eq(str(view.marker(2)["bubble"]), "rescue")
	assert_eq(float(view.marker(2)["grey"]), WorkoutRideView.GREY_RESCUE)
	assert_eq(int(view.marker(2)["pose"]), WorkoutRig.POSE_SITUP)
	assert_eq(str(view.marker(3)["bubble"]), "afk")
	assert_eq(float(view.marker(3)["grey"]), WorkoutRideView.GREY_AFK)
	assert_eq(str(view.marker(4)["bubble"]), "link")
	assert_eq(float(view.marker(4)["grey"]), WorkoutRideView.GREY_LINK)


# --- the three clocks ----------------------------------------------------------------


## Drives the view `frames` frames at `rpm` and `v` on rider 1 and reports what moved.
func _clocks(rpm: float, v: float, frames: int) -> Dictionary:
	var view := _view(1)
	var r := view.game.state.rider(1)
	r.cadence_rpm = rpm
	r.speed.v_mps = v
	var seen := {"crank": {}, "hands": {}, "wheel": {}, "scroll": {}, "flutter": {}}
	var env0 := view.env_t
	var rotor0: float = view._rotor_revs
	var grass0: float = view._grass_frames
	var clouds0 := view.clouds.scroll()
	for i in frames:
		view.game.sim_alive()
		r.speed.distance_m += v * FRAME
		view.advance(FRAME)
		var m := view.marker(1)
		seen["crank"][int(m["crank_frame"])] = true
		seen["hands"][view.hands_up(r)] = true
		seen["wheel"][int(m["wheel_frame"])] = true
		seen["scroll"][view.near_trees.world_x] = true
		seen["flutter"][int(m["flutter"])] = true
	seen["env"] = view.env_t - env0
	seen["rotor"] = view._rotor_revs - rotor0
	seen["grass"] = view._grass_frames - grass0
	seen["clouds"] = view.clouds.scroll() - clouds0
	return seen


func _environment_moved(seen: Dictionary) -> void:
	assert_gt(float(seen["env"]), 0.0, "the environment clock runs")
	assert_gt(float(seen["rotor"]), 0.0, "the wind pump turns")
	assert_gt(float(seen["grass"]), 0.0, "the grass moves")
	assert_ne(float(seen["clouds"]), 0.0, "the clouds drift")


func test_no_cadence_no_speed_only_the_environment_moves() -> void:
	var seen := _clocks(0.0, 0.0, 240)
	assert_eq((seen["crank"] as Dictionary).size(), 1, "cranks hold")
	assert_eq((seen["hands"] as Dictionary).size(), 1, "hands hold")
	assert_eq((seen["wheel"] as Dictionary).size(), 1, "wheels hold")
	assert_eq((seen["scroll"] as Dictionary).size(), 1, "the road holds")
	_environment_moved(seen)


func test_cadence_alone_moves_the_legs_not_the_wheels() -> void:
	var seen := _clocks(90.0, 0.0, 120)
	assert_eq((seen["crank"] as Dictionary).size(), WorkoutRig.CRANK_FRAMES, "every frame in 2 s")
	assert_eq((seen["hands"] as Dictionary).size(), 2, "hands go up and down")
	assert_eq((seen["wheel"] as Dictionary).size(), 1, "wheels hold")
	assert_eq((seen["scroll"] as Dictionary).size(), 1, "the road holds")
	assert_eq((seen["flutter"] as Dictionary).size(), 1, "the pennant flutters on speed")
	_environment_moved(seen)


func test_coasting_moves_the_wheels_and_holds_the_cranks() -> void:
	var seen := _clocks(0.0, 9.0, 120)
	assert_eq((seen["crank"] as Dictionary).size(), 1, "cranks hold")
	assert_eq((seen["hands"] as Dictionary).size(), 1, "hands hold")
	assert_gt((seen["wheel"] as Dictionary).size(), 8, "wheels turn")
	assert_gt((seen["scroll"] as Dictionary).size(), 8, "the road scrolls")
	assert_eq((seen["flutter"] as Dictionary).size(), 2, "the pennant flutters")


func test_a_quiet_sim_holds_the_cranks_at_90_rpm() -> void:
	var view := _view(1)
	view.game.state.rider(1).cadence_rpm = 90.0
	view.game.sim_alive()
	var quiet_frames := ceili(WorkoutGame.SIM_ALIVE_S / FRAME) + 1
	for i in quiet_frames:
		view.advance(FRAME)
	var held := view.game.cranks.revs(1)
	for i in 60:
		view.advance(FRAME)
	assert_eq(view.game.cranks.revs(1), held, "paused or over: the legs stop")


func test_a_disconnected_rider_holds_its_cranks() -> void:
	var view := _view(2)
	view.game.state.rider(2).cadence_rpm = 90.0
	view.game.state.rider(2).connected = false
	for i in 60:
		view.game.sim_alive()
		view.advance(FRAME)
	assert_eq(view.game.cranks.revs(2), 0.0)


func test_breath_comes_every_second_turn_and_stops_with_the_legs() -> void:
	var view := _view(1)
	view.game.state.plan_t = 0.0
	view.game.state.rider(1).cadence_rpm = 120.0
	var clouds := 0
	var was := 0
	for i in 240:
		view.game.sim_alive()
		view.advance(FRAME)
		var now: int = (view.model["puffs"] as Array).size()
		if now > was:
			clouds += now - was
		was = now
		assert_lte(now, WorkoutRideView.BREATH_MAX)
	assert_between(clouds, 3, 5, "120 rpm for 4 s is 8 turns, 4 clouds")
	view.game.state.rider(1).cadence_rpm = 0.0
	for i in 60:
		view.game.sim_alive()
		view.advance(FRAME)
	assert_eq((view.model["puffs"] as Array).size(), 0, "no pedalling, no breath")


func test_no_breath_in_warm_air() -> void:
	var view := _view(1)
	view.game.state.plan_t = view.game.state.total_s()
	view.game.state.rider(1).cadence_rpm = 120.0
	for i in 120:
		view.game.sim_alive()
		view.advance(FRAME)
		assert_eq((view.model["puffs"] as Array).size(), 0)


func test_dust_only_when_fast_and_it_stays_on_the_road() -> void:
	var view := _view(1)
	var r := view.game.state.rider(1)
	r.speed.v_mps = 9.0
	view.refresh()
	assert_eq((view.marker(1)["dust"] as Array).size(), 0, "no dust at 9 m/s")
	r.speed.v_mps = 12.0
	r.speed.distance_m = 100.5
	view.refresh()
	var a: Array = view.marker(1)["dust"]
	assert_eq(a.size(), WorkoutRideView.DUST_PUFFS)
	r.speed.distance_m = 101.0
	view.refresh()
	var b: Array = view.marker(1)["dust"]
	var moved: int = (a[0]["at"] as Vector2i).x - (b[0]["at"] as Vector2i).x
	assert_eq(moved, roundi(0.5 * WorkoutRideView.VISUAL_PX_PER_M), "the puff stays on its spot")


func test_the_view_keeps_ctx_rng_untouched() -> void:
	var view := _view(4)
	var rng := view.game.ctx.rng
	var before := rng.state
	for i in 30:
		view.game.sim_alive()
		view.advance(FRAME)
	assert_eq(rng.state, before)
