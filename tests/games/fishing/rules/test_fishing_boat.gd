extends GutTest
## FishingBoat: thrust from P_eff, drag, the drift brake, the dock wall and the edge, pitch, wake
## and the driving grade.


func _boat(x: float = 100.0, heading: int = 1) -> FishingRiderState:
	var r := FishingRiderState.new()
	r.x_m = x
	r.heading = heading
	return r


func _drive(r: FishingRiderState, p: float, seconds: float, on: bool = true) -> void:
	for i in roundi(seconds / Wl.SIM_DT):
		FishingBoat.step(r, p, on, 9000.0, Wl.SIM_DT)


func test_250_w_holds_5_m_s_so_the_map_takes_about_30_minutes() -> void:
	var v := FishingBoat.steady_speed(250.0)
	assert_almost_eq(v, 5.0, 0.05, "100 % FTP-equivalent holds 5 m/s")
	assert_between(9000.0 / v / 60.0, 28.0, 32.0, "crossing 9 km in about 30 min")
	var r := _boat()
	_drive(r, 250.0, 120.0)
	assert_almost_eq(r.v_mps, v, 0.05, "the simulated boat settles at the steady speed")


func test_speed_grows_with_power_but_slower_than_linear() -> void:
	var v125 := FishingBoat.steady_speed(125.0)
	var v500 := FishingBoat.steady_speed(500.0)
	assert_between(v125, 3.7, 4.1)
	assert_between(v500, 6.2, 6.6)
	assert_lt(v500 / v125, 2.0, "double power is far less than double speed")


func test_without_thrust_the_boat_brakes_to_a_stop_within_20_s() -> void:
	var r := _boat()
	_drive(r, 250.0, 120.0)
	_drive(r, 250.0, 20.0, false)
	assert_lt(absf(r.v_mps), FishingConst.STOP_SPEED, "stopped by the drift brake")
	assert_gt(r.x_m, 100.0)


func test_drag_never_reverses_the_boat() -> void:
	var r := _boat()
	r.v_mps = 0.05
	_drive(r, 0.0, 30.0, false)
	assert_eq(r.v_mps, 0.0)


func test_heading_minus_one_drives_toward_the_dock_and_stops_at_its_wall() -> void:
	var r := _boat(50.0, -1)
	_drive(r, 250.0, 30.0)
	assert_eq(r.x_m, 0.0, "the dock wall")
	assert_eq(r.v_mps, 0.0)


func test_the_boat_stops_dead_at_the_edge() -> void:
	var r := _boat(8990.0, 1)
	for i in 200:
		FishingBoat.step(r, 400.0, true, 9000.0, Wl.SIM_DT)
	assert_eq(r.x_m, 9000.0)
	assert_eq(r.v_mps, 0.0)
	assert_eq(r.furthest_x_m, 9000.0, "furthest out follows x")


func test_hammering_lifts_the_bow_and_it_settles_at_cruise() -> void:
	var r := _boat()
	_drive(r, 600.0, 1.5)
	var peak := r.pitch_deg
	assert_gt(peak, 8.0, "a hard start lifts the bow")
	assert_lte(peak, FishingConst.PITCH_MAX_DEG)
	_drive(r, 250.0, 120.0)
	assert_almost_eq(r.pitch_deg, FishingConst.PITCH_PER_THROTTLE, 0.2, "2.5 deg at 100 % cruise")
	_drive(r, 0.0, 10.0, false)
	assert_lt(r.pitch_deg, 0.5, "the bow drops when the prop is free")


func test_wake_scales_with_speed_and_throttle() -> void:
	var r := _boat()
	assert_eq(r.wake, 0.0)
	_drive(r, 250.0, 120.0)
	var cruise := r.wake
	assert_almost_eq(cruise, 0.6 * 5.0 / 7.0 + 0.4, 0.02)
	_drive(r, 500.0, 60.0)
	assert_gt(r.wake, cruise)
	assert_lte(r.wake, 1.0)


func test_grade_is_half_a_percent_plus_water_drag_capped_at_3() -> void:
	assert_almost_eq(FishingBoat.grade_for(0.0), 0.5, 1e-6)
	assert_almost_eq(FishingBoat.grade_for(5.0), 2.5, 1e-6)
	assert_eq(FishingBoat.grade_for(8.0), FishingConst.GRADE_MAX_PCT)
	assert_lte(FishingConst.GRADE_MAX_PCT, PlanValidator.WARMUP_GRADE_MAX, "inside the warm-up")


func test_the_same_inputs_give_the_same_boat() -> void:
	var a := _boat()
	var b := _boat()
	for i in 400:
		var p := 150.0 + 100.0 * sin(i * 0.1)
		FishingBoat.step(a, p, true, 9000.0, Wl.SIM_DT)
		FishingBoat.step(b, p, true, 9000.0, Wl.SIM_DT)
	assert_eq([a.x_m, a.v_mps, a.pitch_deg], [b.x_m, b.v_mps, b.pitch_deg])


func test_stopped_means_under_the_stop_speed() -> void:
	var r := _boat()
	r.v_mps = FishingConst.STOP_SPEED * 0.5
	assert_true(FishingBoat.stopped(r))
	r.v_mps = -FishingConst.STOP_SPEED * 2.0
	assert_false(FishingBoat.stopped(r))
