extends GutTest
## SiegeBallistics (brief 2.4 "Projectiles", 4): closed-form ballistics with k = 0, the drag
## flight, the solvers, spread from a seed replaying identically.

const G := 9.81


## The closed-form range of a launch from height h at speed v and elevation a (no drag).
func _range(v: float, a_deg: float, h: float) -> float:
	var a := deg_to_rad(a_deg)
	var vx := v * cos(a)
	var vz := v * sin(a)
	var t := (vz + sqrt(vz * vz + 2.0 * G * h)) / G
	return vx * t


func test_step_updates_v_then_p_by_the_mean_velocity() -> void:
	var nx := SiegeBallistics.step(Vector3.ZERO, Vector3(10, 0, 0), 0.0, 0.05)
	assert_almost_eq(nx[1].z, -G * 0.05, 1e-6, "v += g dt")
	assert_almost_eq(nx[0].z, -G * 0.05 * 0.05 * 0.5, 1e-6, "p += (v + v') / 2 dt: exact")
	assert_almost_eq(nx[0].x, 0.5, 1e-6)


func test_gravity_alone_is_integrated_exactly() -> void:
	var p := Vector3(0, 0, 100)
	var v := Vector3(5, 0, 12)
	for _i in 40:
		var nx := SiegeBallistics.step(p, v, 0.0)
		p = nx[0]
		v = nx[1]
	var t := 40 * 0.05
	assert_almost_eq(p.z, 100.0 + 12.0 * t - 0.5 * G * t * t, 1e-3)
	assert_almost_eq(p.x, 5.0 * t, 1e-4)


func test_drag_is_quadratic_against_the_velocity() -> void:
	var v := Vector3(30, 0, 40)
	var nx := SiegeBallistics.step(Vector3.ZERO, v, 0.01, 0.05)
	var want := v + (Vector3(0, 0, -G) - v * (0.01 * 50.0)) * 0.05
	assert_true((nx[1] as Vector3).is_equal_approx(want))


func test_without_drag_the_range_matches_closed_form_within_1_percent() -> void:
	# Station shots: launched from the towers' and the courtyard's height at their speeds.
	for spec: Array in [
		[34.0, 45.0, 17.2],
		[20.0, 45.0, 17.2],
		[45.0, 40.0, 17.5],
		[30.0, 40.0, 17.5],
		[70.0, -8.0, 21.0],
		[50.0, -5.0, 13.5],
		[20.0, 45.0, 0.0],
		[15.0, 60.0, 5.0]
	]:
		var v: float = spec[0]
		var a := deg_to_rad(float(spec[1]))
		var h: float = spec[2]
		var l := SiegeBallistics.land(
			Vector3(0, 0, h), Vector3(v * cos(a), 0, v * sin(a)), 0.0, 0.0
		)
		var want := _range(v, float(spec[1]), h)
		assert_almost_eq((l["p"] as Vector3).x, want, want * 0.01, "v %s at %s deg" % [v, spec[1]])


func test_without_drag_the_flight_time_matches_closed_form_within_a_tick() -> void:
	var v := 30.0
	var a := deg_to_rad(45.0)
	var l := SiegeBallistics.land(Vector3(0, 0, 17.2), Vector3(v * cos(a), 0, v * sin(a)), 0.0, 0.0)
	var vz := v * sin(a)
	var want := (vz + sqrt(vz * vz + 2.0 * G * 17.2)) / G
	assert_almost_eq(float(l["t"]), want, 0.05)
	assert_eq(int(l["steps"]), ceili(float(l["t"]) / 0.05))


func test_drag_shortens_the_range() -> void:
	var v0 := Vector3(30, 0, 30)
	var free := SiegeBallistics.land(Vector3.ZERO, v0, 0.0, 0.0)
	var dragged := SiegeBallistics.land(Vector3.ZERO, v0, 0.006, 0.0)
	assert_lt((dragged["p"] as Vector3).x, (free["p"] as Vector3).x * 0.8)


func test_arrows_reach_about_123_m_at_45_m_per_s() -> void:
	var best := 0.0
	for a in range(20, 60):
		var r := deg_to_rad(float(a))
		var l := SiegeBallistics.land(
			Vector3(0, 0, 17.5), Vector3(45 * cos(r), 0, 45 * sin(r)), 0.006, 0.0
		)
		best = maxf(best, (l["p"] as Vector3).x)
	assert_between(best, 115.0, 130.0, "the lead's physics check: k 0.006 reaches ~123 m")


func test_stones_at_45_degrees_need_15_to_32_m_per_s_for_30_to_100_m() -> void:
	var o := Vector3(0, 0, 17.2)
	var near := SiegeBallistics.solve_speed(o, Vector3(30, 0, 0), 45.0, 0.0016, 10.0, 34.0)
	var far := SiegeBallistics.solve_speed(o, Vector3(100, 0, 0), 45.0, 0.0016, 10.0, 34.0)
	assert_between(near.length(), 12.0, 18.0)
	assert_between(far.length(), 28.0, 34.0)
	var t := SiegeBallistics.flight_time(o, far, 0.0016, 0.0)
	assert_between(t, 3.4, 5.1, "3.4-5 s of flight")


func test_land_interpolates_the_crossing() -> void:
	var l := SiegeBallistics.land(Vector3(0, 0, 10), Vector3(5, 0, 0), 0.0, 0.0)
	assert_almost_eq((l["p"] as Vector3).z, 0.0, 1e-4)
	assert_lt(float(l["t"]), float(l["steps"]) * 0.05 + 1e-6)


func test_land_matches_stepping_tick_by_tick() -> void:
	var p := Vector3(0, 0, 21)
	var v := Vector3(50, 20, 8)
	var l := SiegeBallistics.land(p, v, 0.0016, 0.0)
	for _i in int(l["steps"]) - 1:
		var nx := SiegeBallistics.step(p, v, 0.0016)
		p = nx[0]
		v = nx[1]
	assert_gt(p.z, 0.0, "one step before the landing it is still up")
	var last := SiegeBallistics.step(p, v, 0.0016)
	assert_lte((last[0] as Vector3).z, 0.0, "the landing step crosses the ground")


func test_a_flight_never_runs_past_its_limit() -> void:
	var l := SiegeBallistics.land(Vector3.ZERO, Vector3(1, 0, 1000), 0.0, -1e9)
	assert_lte(float(l["t"]), SiegeBallistics.MAX_FLIGHT_S + 0.06)


func test_solve_angle_lands_on_the_target_with_drag() -> void:
	var o := Vector3(1, 59, 21)
	for d in [10.0, 40.0, 80.0, 110.0]:
		var target := Vector3(1 + d * 0.6, 59 + d * 0.8, 0.9)
		var v := SiegeBallistics.solve_angle(o, target, 70.0, 0.0004)
		assert_ne(v, Vector3.ZERO, "%s m" % d)
		var l := SiegeBallistics.land(o, v, 0.0004, target.z)
		assert_lt(Vector2(l["p"].x - target.x, l["p"].y - target.y).length(), 0.5)
		assert_almost_eq(v.length(), 70.0, 0.01, "at the bolt's speed")


func test_solve_angle_low_arc_is_flat_and_the_high_arc_is_steep() -> void:
	var low := SiegeBallistics.solve_angle(Vector3.ZERO, Vector3(60, 0, 0), 40.0, 0.0)
	var high := SiegeBallistics.solve_angle(Vector3.ZERO, Vector3(60, 0, 0), 40.0, 0.0, true)
	assert_lt(low.z / low.length(), 0.5)
	assert_gt(high.z / high.length(), 0.7)


func test_solve_angle_out_of_reach_is_zero() -> void:
	assert_eq(
		SiegeBallistics.solve_angle(Vector3.ZERO, Vector3(500, 0, 0), 30.0, 0.006), Vector3.ZERO
	)
	assert_eq(SiegeBallistics.solve_angle_full(Vector3.ZERO, Vector3(500, 0, 0), 30.0, 0.006), {})


func test_solve_speed_keeps_the_elevation() -> void:
	var v := SiegeBallistics.solve_speed(
		Vector3(0, 0, 17), Vector3(0, 70, 0), 40.0, 0.006, 10.0, 45.0
	)
	assert_almost_eq(rad_to_deg(atan2(v.z, Vector2(v.x, v.y).length())), 40.0, 0.01)
	var l := SiegeBallistics.land(Vector3(0, 0, 17), v, 0.006, 0.0)
	assert_lt(Vector2(l["p"].x, l["p"].y - 70.0).length(), 0.1)


func test_solve_speed_full_reports_the_flight() -> void:
	var o := Vector3(0, 0, 17)
	var sol := SiegeBallistics.solve_speed_full(o, Vector3(60, 0, 0), 45.0, 0.0016, 10.0, 34.0)
	var l := SiegeBallistics.land(o, sol["v"], 0.0016, 0.0)
	assert_almost_eq(float(sol["t"]), float(l["t"]), 1e-4)
	assert_eq(int(sol["steps"]), int(l["steps"]))


func test_solve_speed_out_of_the_bracket_is_zero() -> void:
	var o := Vector3(0, 0, 17)
	assert_eq(
		SiegeBallistics.solve_speed(o, Vector3(200, 0, 0), 45.0, 0.0016, 10.0, 34.0), Vector3.ZERO
	)
	assert_eq(
		SiegeBallistics.solve_speed(o, Vector3(1, 0, 0), 45.0, 0.0016, 10.0, 34.0), Vector3.ZERO
	)
	assert_eq(
		SiegeBallistics.solve_speed(o, Vector3(0, 0, 0), 45.0, 0.0016, 10.0, 34.0), Vector3.ZERO
	)


func test_spread_turns_lifts_and_scales() -> void:
	var v := Vector3(10, 0, 0)
	var s := SiegeBallistics.spread(v, 90.0, 0.0, 1.0)
	assert_true(s.is_equal_approx(Vector3(0, 10, 0)))
	var up := SiegeBallistics.spread(v, 0.0, 90.0, 2.0)
	assert_true(up.is_equal_approx(Vector3(0, 0, 20)))
	assert_true(SiegeBallistics.spread(v, 0.0, 0.0, 1.0).is_equal_approx(v))


func test_shot_velocities_replay_identically_from_the_seed() -> void:
	var v := Vector3(20, 25, 22)
	var a := SiegeBallistics.shot_velocities(v, 12, 123456, 2.5, 0.03)
	var b := SiegeBallistics.shot_velocities(v, 12, 123456, 2.5, 0.03)
	assert_eq(a, b, "two instances, one seed, the same arcs")
	assert_eq(a.size(), 12)
	var c := SiegeBallistics.shot_velocities(v, 12, 654321, 2.5, 0.03)
	assert_ne(a, c, "another seed spreads differently")


func test_shot_velocities_stay_within_the_speed_spread() -> void:
	var v := Vector3(30, 0, 30)
	for w in SiegeBallistics.shot_velocities(v, 50, 9, 2.5, 0.03):
		assert_between(w.length() / v.length(), 0.97 - 1e-6, 1.03 + 1e-6)


func test_the_spread_follows_the_draw_order_of_state_v2() -> void:
	var v := Vector3(10, 10, 10)
	var rng := SiegeHashRng.new(77)
	var dy := rng.gauss(0.6)
	var dp := rng.gauss(0.6)
	var sf := 1.0 + rng.range_f(-0.015, 0.015)
	var want := SiegeBallistics.spread(v, dy, dp, sf)
	assert_true(SiegeBallistics.shot_velocities(v, 1, 77, 0.6, 0.015)[0].is_equal_approx(want))


func test_zero_spread_keeps_the_aim() -> void:
	var v := Vector3(5, 6, 7)
	for w in SiegeBallistics.shot_velocities(v, 3, 1, 0.0, 0.0):
		assert_true(w.is_equal_approx(v))


func test_the_hash_rng_is_deterministic_and_in_range() -> void:
	var a := SiegeHashRng.new(5)
	var b := SiegeHashRng.new(5)
	for _i in 100:
		var x := a.randf01()
		assert_eq(x, b.randf01())
		assert_between(x, 0.0, 1.0)
	assert_ne(SiegeHashRng.new(0).next_u32(), 0, "a zero seed is replaced")


func test_the_hash_rng_gauss_has_the_right_spread() -> void:
	var r := SiegeHashRng.new(31)
	var sum := 0.0
	var sq := 0.0
	for _i in 2000:
		var g := r.gauss(2.0)
		sum += g
		sq += g * g
	assert_almost_eq(sum / 2000.0, 0.0, 0.2)
	assert_almost_eq(sqrt(sq / 2000.0), 2.0, 0.2)
