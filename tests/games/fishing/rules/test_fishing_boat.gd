extends GutTest
## FishingBoat: the rigid body on the water. Speeds from P_eff (displacement law, planing gain),
## planing and its hysteresis, the approach and the drift brake, the dock wall and the edge,
## pitch and heave (surge kick, hump squat, flat on the plane, braking), the prop always in the
## water, the fish's tow, brake, wake and the driving grade.

const EDGE := 17900.0


func _boat(x: float = 100.0, heading: int = 1) -> FishingRiderState:
	var r := FishingRiderState.new()
	r.x_m = x
	r.heading = heading
	return r


## A fish 30 m behind the stern, 40 m down: the line pulls back and down.
func _hook(r: FishingRiderState) -> void:
	r.fish.d = 30.0
	r.fish.hook_depth_m = 40.0
	r.fish.z = 1.0


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


## Seconds at `p` from rest until the boat planes (at most `limit`).
func _until_planing(r: FishingRiderState, p: float, limit: float) -> float:
	var t := 0.0
	while not r.planing and t < limit:
		FishingBoat.step(r, p, true, EDGE, Wl.SIM_DT)
		t += Wl.SIM_DT
	return t


func test_250_w_planes_at_16_m_s_so_the_map_takes_about_19_minutes() -> void:
	assert_almost_eq(FishingBoat.steady_speed(250.0), 15.0, 1e-4, "15 m/s in displacement")
	var r := _boat(10.0)
	var t := _until_past(r, 250.0, EDGE - 1.0, 3600.0)
	gut.p("crossing at 100 %%: %.1f min" % (t / 60.0))
	assert_between(t / 60.0, 18.0, 20.0, "crossing 18 km in about 19 min")
	assert_almost_eq(r.v_mps, 15.0 * 1.07, 0.05, "on the plane: 7 % faster")
	var t150 := _until_past(_boat(10.0), 375.0, EDGE - 1.0, 3600.0)
	gut.p("crossing at 150 %%: %.1f min" % (t150 / 60.0))
	assert_between(t150 / 60.0, 14.0, 16.0)


func test_steady_speed_grows_with_power_to_the_0_6() -> void:
	assert_almost_eq(FishingBoat.steady_speed(125.0), 15.0 * pow(0.5, 0.6), 1e-4)
	assert_almost_eq(FishingBoat.steady_speed(500.0), 15.0 * pow(2.0, 0.6), 1e-4)
	assert_gt(FishingBoat.steady_speed(500.0) / FishingBoat.steady_speed(250.0), 1.5)
	assert_eq(FishingBoat.steady_speed(0.0), 0.0)
	assert_eq(FishingBoat.steady_speed(5000.0), FishingBoat.steady_speed(750.0), "capped at 300 %")
	assert_almost_eq(FishingBoat.cruise_speed(250.0), 15.0 * 1.07, 1e-4, "planes from 70 %")
	assert_eq(FishingBoat.cruise_speed(150.0), FishingBoat.steady_speed(150.0))


func test_the_simulated_cruise_matches_the_speed_laws() -> void:
	for p: float in [50.0, 250.0, 500.0]:
		var r := _boat()
		_drive(r, p, 60.0)
		assert_almost_eq(r.v_mps, FishingBoat.cruise_speed(p), 0.02 * r.v_mps, "at %d W" % p)
	var hump := _boat()
	_drive(hump, 125.0, 60.0)
	var share := hump.v_mps / FishingBoat.steady_speed(125.0)
	gut.p("125 W on the hump: %.2f m/s (%.3f of the law)" % [hump.v_mps, share])
	assert_between(share, 0.9, 0.97, "the displacement hump costs a few percent near 9.5 m/s")


func test_70_percent_climbs_onto_the_plane_66_percent_does_not() -> void:
	var r := _boat()
	var t := _until_planing(r, 175.0, 60.0)
	gut.p("time to plane at 175 W: %.2f s" % t)
	assert_true(r.planing, "175 W planes")
	assert_lt(t, 15.0)
	_drive(r, 175.0, 30.0)
	assert_almost_eq(r.plane, 1.0, 1e-6)
	var gain := r.v_mps / FishingBoat.steady_speed(175.0)
	assert_between(gain, 1.05, 1.10, "5-10 % faster than in displacement")
	var low := _boat()
	_drive(low, 165.0, 120.0)
	assert_false(low.planing, "165 W stays in displacement")
	assert_eq(low.plane, 0.0)
	var t250 := _until_planing(_boat(), 250.0, 60.0)
	var t500 := _until_planing(_boat(), 500.0, 60.0)
	gut.p("time to plane at 250 W: %.2f s, at 500 W: %.2f s" % [t250, t500])
	assert_lt(t250, 3.0)
	assert_lt(t500, t250)


func test_planing_has_hysteresis_and_does_not_flicker() -> void:
	var r := _boat()
	_drive(r, 200.0, 30.0)
	assert_true(r.planing)
	_drive(r, 150.0, 30.0)
	assert_true(r.planing, "150 W holds the plane once on it")
	_drive(r, 120.0, 30.0)
	assert_false(r.planing, "120 W drops off the plane")
	var b := _boat()
	_drive(b, 180.0, 30.0)
	var flips := 0
	var was := b.planing
	for i in 2400:
		FishingBoat.step(b, 165.0 + 20.0 * sin(i * 0.3), true, EDGE, Wl.SIM_DT)
		if b.planing != was:
			flips += 1
			was = b.planing
	assert_eq(flips, 0, "pedal strokes around the threshold never flicker the plane")


func test_the_boat_follows_the_pedals() -> void:
	var r := _boat()
	_drive(r, 250.0, 5.0)
	assert_gt(r.v_mps, 0.9 * FishingBoat.cruise_speed(250.0), "from rest to 90 % in 5 s")
	_drive(r, 250.0, 20.0)
	var v0 := r.v_mps
	_drive(r, 500.0, 3.0)
	assert_gt(r.v_mps, v0 + 5.0, "a surge")
	var v1 := r.v_mps
	FishingBoat.step(r, 125.0, true, EDGE, Wl.SIM_DT)
	assert_lt(r.v_mps, v1, "less power slows it the very next step")
	_drive(r, 125.0, 3.0)
	assert_lt(r.v_mps, v1 - 8.0, "drag brakes it")


func test_without_thrust_the_boat_stops_from_cruise_within_5_s() -> void:
	var r := _boat()
	_drive(r, 250.0, 20.0)
	var x0 := r.x_m
	var t := _until_stopped(r, 60.0)
	gut.p("stop from cruise: %.2f s over %.0f m" % [t, r.x_m - x0])
	assert_between(t, 2.0, 5.0, "a few seconds, not tens")
	_drive(r, 0.0, 3.0, false)
	assert_eq(r.v_mps, 0.0, "and comes to rest")


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


func test_a_surge_kicks_the_bow_up_then_it_settles() -> void:
	var r := _boat()
	_drive(r, 250.0, 20.0)
	var cruise := r.pitch_deg
	assert_between(cruise, 1.0, 4.0, "a few degrees bow up at cruise on the plane")
	var peak := cruise
	for i in 40:
		FishingBoat.step(r, 500.0, true, EDGE, Wl.SIM_DT)
		peak = maxf(peak, r.pitch_deg)
	_drive(r, 500.0, 10.0)
	assert_gt(peak, r.pitch_deg + 1.5, "the kick overshoots the new trim")
	assert_lte(peak, FishingConst.TRIM_MAX_DEG)
	var start := _boat()
	var top := 0.0
	for i in 60:
		FishingBoat.step(start, 600.0, true, EDGE, Wl.SIM_DT)
		top = maxf(top, start.pitch_deg)
	assert_between(top, 8.0, FishingConst.TRIM_MAX_DEG, "a hard start lifts the bow high")


func test_on_the_plane_the_hull_rises_and_flattens_with_the_transom_at_the_waterline() -> void:
	var r := _boat()
	var hump_pitch := 0.0
	var hump_prop := 0.0
	for i in 400:
		FishingBoat.step(r, 200.0, true, EDGE, Wl.SIM_DT)
		if r.plane <= 0.0:
			hump_pitch = maxf(hump_pitch, r.pitch_deg)
			hump_prop = maxf(hump_prop, r.prop_depth_m)
	assert_gt(hump_pitch, 5.0, "climbing the hump: bow up")
	assert_gt(hump_prop, FishingConst.PROP_REST_M + 0.05, "the stern squats: the prop goes deeper")
	assert_almost_eq(r.plane, 1.0, 1e-6)
	assert_gt(r.heave_m, 0.04, "on the plane the hull rides higher")
	assert_lt(r.pitch_deg, hump_pitch - 2.0, "and flatter")
	var stern := r.heave_m - FishingConst.STERN_ARM_M * sin(deg_to_rad(r.pitch_deg))
	assert_almost_eq(stern, 0.0, 0.03, "the transom stays at the waterline")
	assert_gte(r.prop_depth_m, FishingConst.PROP_REST_M - 0.03, "the prop stays in the water")


func test_the_prop_never_leaves_the_water() -> void:
	var r := _boat(5000.0)
	_hook(r)
	var rng := FishingRandom.derive(7, 1, 2)
	var low := INF
	for k in 200:
		var p := rng.range_f(0.0, 750.0)
		var on := rng.unit() > 0.25
		r.tow_n = rng.range_f(0.0, FishingConst.TOW_MAX_N) if rng.unit() < 0.3 else 0.0
		for i in roundi(rng.range_f(2.0, 80.0)):
			FishingBoat.step(r, p, on, EDGE, Wl.SIM_DT)
			var sink := FishingConst.STERN_ARM_M * sin(deg_to_rad(r.pitch_deg))
			low = minf(low, FishingConst.PROP_REST_M - r.heave_m + sink)
	gut.p("shallowest prop: %.3f m" % low)
	assert_gt(low, FishingConst.PROP_MIN_M, "the physics alone keeps the prop under")


func test_cutting_the_power_digs_the_bow_in_then_it_levels_once_stopped() -> void:
	var r := _boat()
	_drive(r, 250.0, 20.0)
	assert_almost_eq(r.brake, 0.0, 1e-3, "no braking at cruise")
	var low := 0.0
	var brake := 0.0
	while not FishingBoat.stopped(r):
		FishingBoat.step(r, 0.0, false, EDGE, Wl.SIM_DT)
		low = minf(low, r.pitch_deg)
		brake = maxf(brake, r.brake)
	assert_lt(low, -2.0, "bow down while braking")
	assert_gte(low, FishingConst.TRIM_MIN_DEG)
	assert_gt(brake, 0.9, "full braking from cruise")
	_drive(r, 0.0, 4.0, false)
	assert_almost_eq(r.pitch_deg, 0.0, 0.1, "level when stopped")
	assert_almost_eq(r.heave_m, 0.0, 0.01)
	assert_lt(r.brake, 0.01)


func test_a_hooked_fish_tows_the_boat_toward_it_and_pulls_the_stern_down() -> void:
	var r := _boat(5000.0)
	_hook(r)
	_drive(r, 0.0, 2.0, false)
	assert_eq(r.v_mps, 0.0, "no tension, no tow")
	r.tow_n = FishingConst.TOW_MAX_N
	var top := 0.0
	for i in 600:
		FishingBoat.step(r, 0.0, false, EDGE, Wl.SIM_DT)
		top = maxf(top, absf(r.v_mps))
	gut.p("full tow: %.2f m/s, %.1f m in 30 s" % [top, 5000.0 - r.x_m])
	assert_lt(r.x_m, 5000.0, "toward the fish behind the stern")
	assert_lt(top, 1.5, "bounded: a slow sleigh ride")
	assert_gt(r.pitch_deg, 0.5, "the stern goes down, the bow up")
	assert_gt(r.prop_depth_m, FishingConst.PROP_REST_M, "the prop deeper")
	var home := _boat(5000.0, -1)
	_hook(home)
	home.tow_n = FishingConst.TOW_MAX_N
	_drive(home, 0.0, 30.0, false)
	assert_almost_eq(home.x_m - 5000.0, 5000.0 - r.x_m, 1e-6, "heading home: toward its stern")
	r.tow_n = 0.0
	_drive(r, 0.0, 10.0, false)
	assert_eq(r.v_mps, 0.0, "the tow stops when the line goes slack")


func test_heading_home_mirrors_the_hull() -> void:
	var a := _boat(5000.0, 1)
	var b := _boat(5000.0, -1)
	for i in 100:
		var p := 250.0 if i < 60 else 0.0
		FishingBoat.step(a, p, i < 60, EDGE, Wl.SIM_DT)
		FishingBoat.step(b, p, i < 60, EDGE, Wl.SIM_DT)
	assert_almost_eq(a.pitch_deg, b.pitch_deg, 1e-6)
	assert_almost_eq(a.heave_m, b.heave_m, 1e-6)
	assert_almost_eq(a.plane, b.plane, 1e-6)
	assert_almost_eq(a.brake, b.brake, 1e-6)
	assert_almost_eq(a.v_mps, -b.v_mps, 1e-6)


func test_wake_scales_with_speed_and_throttle() -> void:
	var r := _boat()
	assert_eq(r.wake, 0.0)
	_drive(r, 250.0, 20.0)
	var cruise := r.wake
	assert_almost_eq(cruise, 0.6 * r.v_mps / 21.0 + 0.4, 0.02)
	_drive(r, 500.0, 10.0)
	assert_gt(r.wake, cruise)
	assert_lte(r.wake, 1.0)


func test_grade_follows_the_share_of_cruise_speed_capped_at_3() -> void:
	assert_almost_eq(FishingBoat.grade_for(0.0), 0.5, 1e-6)
	assert_almost_eq(FishingBoat.grade_for(15.0), 2.5, 1e-6, "2.5 % at cruise, as before")
	assert_almost_eq(FishingBoat.grade_for(7.5), 1.0, 1e-6)
	assert_almost_eq(FishingBoat.grade_for(15.0 * 1.07, 1.0), 2.5, 1e-6, "planing is no heavier")
	assert_eq(FishingBoat.grade_for(24.0), FishingConst.GRADE_MAX_PCT)
	assert_lte(FishingConst.GRADE_MAX_PCT, PlanValidator.WARMUP_GRADE_MAX, "inside the warm-up")


func test_the_same_inputs_give_the_same_boat() -> void:
	var a := _boat()
	var b := _boat()
	for i in 400:
		var p := 150.0 + 100.0 * sin(i * 0.1)
		FishingBoat.step(a, p, true, EDGE, Wl.SIM_DT)
		FishingBoat.step(b, p, true, EDGE, Wl.SIM_DT)
	assert_eq(
		[a.x_m, a.v_mps, a.pitch_deg, a.heave_m, a.plane, a.brake],
		[b.x_m, b.v_mps, b.pitch_deg, b.heave_m, b.plane, b.brake]
	)


func test_stopped_means_under_the_stop_speed() -> void:
	var r := _boat()
	r.v_mps = FishingConst.STOP_SPEED * 0.5
	assert_true(FishingBoat.stopped(r))
	r.v_mps = -FishingConst.STOP_SPEED * 2.0
	assert_false(FishingBoat.stopped(r))
