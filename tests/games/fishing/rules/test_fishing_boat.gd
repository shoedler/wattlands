extends GutTest
## FishingBoat: the steady speed from P_eff, the quick approach to it, the drift brake, the dock
## wall and the edge, the signed trim (surge kick, braking), brake, wake and the driving grade.

const EDGE := 17900.0


func _boat(x: float = 100.0, heading: int = 1) -> FishingRiderState:
	var r := FishingRiderState.new()
	r.x_m = x
	r.heading = heading
	return r


func _drive(r: FishingRiderState, p: float, seconds: float, on: bool = true) -> void:
	for i in roundi(seconds / Wl.SIM_DT):
		FishingBoat.step(r, p, on, EDGE, Wl.SIM_DT)


## Seconds of steps at `p` until the boat passes x (at most `limit`).
func _until_past(r: FishingRiderState, p: float, x: float, limit: float) -> float:
	var t := 0.0
	while r.x_m < x and t < limit:
		FishingBoat.step(r, p, true, EDGE, Wl.SIM_DT)
		t += Wl.SIM_DT
	return t


## Seconds of drifting until the boat counts as stopped (at most `limit`).
func _until_stopped(r: FishingRiderState, limit: float) -> float:
	var t := 0.0
	while not FishingBoat.stopped(r) and t < limit:
		FishingBoat.step(r, 0.0, false, EDGE, Wl.SIM_DT)
		t += Wl.SIM_DT
	return t


func test_250_w_holds_15_m_s_so_the_map_takes_about_20_minutes() -> void:
	var v := FishingBoat.steady_speed(250.0)
	assert_almost_eq(v, 15.0, 1e-4, "100 % FTP-equivalent holds 15 m/s")
	var t := _until_past(_boat(10.0), 250.0, EDGE - 1.0, 3600.0)
	gut.p("crossing at 100 %%: %.1f min" % (t / 60.0))
	assert_between(t / 60.0, 19.0, 21.0, "crossing 18 km in about 20 min")
	var t150 := _until_past(_boat(10.0), 375.0, EDGE - 1.0, 3600.0)
	gut.p("crossing at 150 %%: %.1f min" % (t150 / 60.0))
	assert_between(t150 / 60.0, 15.0, 16.5)


func test_steady_speed_grows_with_power_to_the_0_6() -> void:
	assert_almost_eq(FishingBoat.steady_speed(125.0), 15.0 * pow(0.5, 0.6), 1e-4)
	assert_almost_eq(FishingBoat.steady_speed(500.0), 15.0 * pow(2.0, 0.6), 1e-4)
	assert_gt(FishingBoat.steady_speed(500.0) / FishingBoat.steady_speed(250.0), 1.5)
	assert_eq(FishingBoat.steady_speed(0.0), 0.0)
	assert_eq(FishingBoat.steady_speed(5000.0), FishingBoat.steady_speed(750.0), "capped at 300 %")


func test_the_boat_reaches_its_new_speed_within_3_s() -> void:
	var r := _boat()
	_drive(r, 250.0, 3.0)
	assert_gt(r.v_mps, 0.95 * 15.0, "from rest to 95 % of cruise in 3 s")
	_drive(r, 250.0, 10.0)
	_drive(r, 500.0, 3.0)
	assert_gt(r.v_mps, 15.0 + 0.95 * (FishingBoat.steady_speed(500.0) - 15.0), "a surge")
	_drive(r, 125.0, 2.0)
	assert_lt(r.v_mps, FishingBoat.steady_speed(125.0) + 0.5, "slowing is quicker")


func test_without_thrust_the_boat_stops_from_cruise_within_4_s() -> void:
	var r := _boat()
	_drive(r, 250.0, 20.0)
	var x0 := r.x_m
	var t := _until_stopped(r, 60.0)
	gut.p("stop from cruise: %.2f s over %.0f m" % [t, r.x_m - x0])
	assert_between(t, 2.0, 4.0, "a few seconds, not tens")
	_drive(r, 0.0, 1.0, false)
	assert_eq(r.v_mps, 0.0, "and stays stopped")


func test_drag_never_reverses_the_boat() -> void:
	var r := _boat(100.0, -1)
	r.v_mps = -0.05
	_drive(r, 0.0, 30.0, false)
	assert_eq(r.v_mps, 0.0)


func test_heading_minus_one_drives_toward_the_dock_and_stops_at_its_wall() -> void:
	var r := _boat(50.0, -1)
	_drive(r, 250.0, 10.0)
	assert_eq(r.x_m, 0.0, "the dock wall")
	assert_eq(r.v_mps, 0.0)


func test_the_boat_stops_dead_at_the_edge() -> void:
	var r := _boat(EDGE - 10.0, 1)
	_drive(r, 400.0, 10.0)
	assert_eq(r.x_m, EDGE)
	assert_eq(r.v_mps, 0.0)
	assert_eq(r.furthest_x_m, EDGE, "furthest out follows x")


func test_a_surge_kicks_the_bow_up_then_it_settles_at_the_steady_trim() -> void:
	var r := _boat()
	_drive(r, 250.0, 20.0)
	assert_almost_eq(r.pitch_deg, FishingConst.TRIM_PER_SPEED, 0.05, "3 deg at 100 % cruise")
	var peak := r.pitch_deg
	for i in 40:
		FishingBoat.step(r, 500.0, true, EDGE, Wl.SIM_DT)
		peak = maxf(peak, r.pitch_deg)
	_drive(r, 500.0, 8.0)
	var steady := FishingConst.TRIM_PER_SPEED * pow(2.0, 0.6)
	assert_almost_eq(r.pitch_deg, steady, 0.05, "settled at the steady trim for 200 %")
	assert_gt(peak, steady + 2.0, "the kick overshoots the steady trim")
	assert_lte(peak, FishingConst.TRIM_MAX_DEG)
	var start := _boat()
	var top := 0.0
	for i in 60:
		FishingBoat.step(start, 600.0, true, EDGE, Wl.SIM_DT)
		top = maxf(top, start.pitch_deg)
	assert_between(top, 8.0, FishingConst.TRIM_MAX_DEG, "a hard start lifts the bow high")


func test_cutting_the_power_digs_the_bow_in_then_it_levels_once_stopped() -> void:
	var r := _boat()
	_drive(r, 250.0, 20.0)
	assert_almost_eq(r.brake, 0.0, 1e-4, "no braking at cruise")
	var low := 0.0
	var brake := 0.0
	while not FishingBoat.stopped(r):
		FishingBoat.step(r, 0.0, false, EDGE, Wl.SIM_DT)
		low = minf(low, r.pitch_deg)
		brake = maxf(brake, r.brake)
	assert_lt(low, -4.0, "bow down while braking")
	assert_gte(low, FishingConst.TRIM_MIN_DEG)
	assert_gt(brake, 0.9, "full braking from cruise")
	_drive(r, 0.0, 3.0, false)
	assert_almost_eq(r.pitch_deg, 0.0, 0.1, "level when stopped")
	assert_lt(r.brake, 0.01)


func test_a_hard_drop_in_power_dips_the_bow_while_driving() -> void:
	var r := _boat()
	_drive(r, 250.0, 20.0)
	var low := r.pitch_deg
	for i in 40:
		FishingBoat.step(r, 125.0, true, EDGE, Wl.SIM_DT)
		low = minf(low, r.pitch_deg)
	assert_lt(low, -1.0, "halving the power dips the bow below level")
	_drive(r, 125.0, 8.0)
	assert_almost_eq(r.pitch_deg, FishingConst.TRIM_PER_SPEED * pow(0.5, 0.6), 0.05)


func test_heading_home_mirrors_the_trim() -> void:
	var a := _boat(5000.0, 1)
	var b := _boat(5000.0, -1)
	for i in 100:
		var p := 250.0 if i < 60 else 0.0
		FishingBoat.step(a, p, i < 60, EDGE, Wl.SIM_DT)
		FishingBoat.step(b, p, i < 60, EDGE, Wl.SIM_DT)
	assert_almost_eq(a.pitch_deg, b.pitch_deg, 1e-6)
	assert_almost_eq(a.brake, b.brake, 1e-6)
	assert_almost_eq(a.v_mps, -b.v_mps, 1e-6)


func test_wake_scales_with_speed_and_throttle() -> void:
	var r := _boat()
	assert_eq(r.wake, 0.0)
	_drive(r, 250.0, 20.0)
	var cruise := r.wake
	assert_almost_eq(cruise, 0.6 * 15.0 / 21.0 + 0.4, 0.02)
	_drive(r, 500.0, 10.0)
	assert_gt(r.wake, cruise)
	assert_lte(r.wake, 1.0)


func test_grade_follows_the_share_of_cruise_speed_capped_at_3() -> void:
	assert_almost_eq(FishingBoat.grade_for(0.0), 0.5, 1e-6)
	assert_almost_eq(FishingBoat.grade_for(15.0), 2.5, 1e-6, "2.5 % at cruise, as before")
	assert_almost_eq(FishingBoat.grade_for(7.5), 1.0, 1e-6)
	assert_eq(FishingBoat.grade_for(24.0), FishingConst.GRADE_MAX_PCT)
	assert_lte(FishingConst.GRADE_MAX_PCT, PlanValidator.WARMUP_GRADE_MAX, "inside the warm-up")


func test_the_same_inputs_give_the_same_boat() -> void:
	var a := _boat()
	var b := _boat()
	for i in 400:
		var p := 150.0 + 100.0 * sin(i * 0.1)
		FishingBoat.step(a, p, true, EDGE, Wl.SIM_DT)
		FishingBoat.step(b, p, true, EDGE, Wl.SIM_DT)
	assert_eq([a.x_m, a.v_mps, a.pitch_deg, a.brake], [b.x_m, b.v_mps, b.pitch_deg, b.brake])


func test_stopped_means_under_the_stop_speed() -> void:
	var r := _boat()
	r.v_mps = FishingConst.STOP_SPEED * 0.5
	assert_true(FishingBoat.stopped(r))
	r.v_mps = -FishingConst.STOP_SPEED * 2.0
	assert_false(FishingBoat.stopped(r))
