extends GutTest
## The treadwheel formulas (brief 3 "Wheels"): rim speed 1.2 m/s x P_eff / 250 up to 3 m/s,
## one to three workers (1 below 150 W, 2 up to 300 W, 3 above) with 20 W of hysteresis, step
## rate cadence / 30 Hz, stride = rim speed / step rate, clamped.


func test_rim_speed_is_linear_in_p_eff() -> void:
	assert_almost_eq(SiegeWheelMath.rim_speed(0.0), 0.0, 1e-6)
	assert_almost_eq(SiegeWheelMath.rim_speed(250.0), 1.2, 1e-6)
	assert_almost_eq(SiegeWheelMath.rim_speed(125.0), 0.6, 1e-6)
	assert_almost_eq(SiegeWheelMath.rim_speed(500.0), 2.4, 1e-6)


func test_rim_speed_caps_at_3_mps() -> void:
	assert_almost_eq(SiegeWheelMath.rim_speed(625.0), 3.0, 1e-6)
	assert_almost_eq(SiegeWheelMath.rim_speed(2000.0), 3.0, 1e-6)
	assert_almost_eq(SiegeWheelMath.rim_speed(-50.0), 0.0, 1e-6)


func test_angular_speed_is_rim_speed_over_radius() -> void:
	assert_almost_eq(SiegeWheelMath.angular_speed(250.0), 1.2 / 2.5, 1e-6)
	assert_almost_eq(SiegeWheelMath.angular_speed(5000.0), 3.0 / 2.5, 1e-6)


func test_step_rate_is_cadence_over_30() -> void:
	assert_almost_eq(SiegeWheelMath.step_rate_hz(90.0), 3.0, 1e-6)
	assert_almost_eq(SiegeWheelMath.step_rate_hz(60.0), 2.0, 1e-6)
	assert_almost_eq(SiegeWheelMath.step_rate_hz(0.0), 0.0, 1e-6)


func test_stride_is_rim_speed_over_step_rate() -> void:
	# 1.2 m/s at 3 steps a second is 0.4 m.
	assert_almost_eq(SiegeWheelMath.stride_m(1.2, 3.0), 0.4, 1e-6)
	assert_almost_eq(SiegeWheelMath.stride_m(0.9, 3.0), 0.3, 1e-6)


func test_stride_is_clamped_and_zero_without_steps() -> void:
	assert_almost_eq(SiegeWheelMath.stride_m(3.0, 1.0), SiegeWheelMath.STRIDE_MAX_M, 1e-6)
	assert_almost_eq(SiegeWheelMath.stride_m(0.1, 3.0), SiegeWheelMath.STRIDE_MIN_M, 1e-6)
	assert_eq(SiegeWheelMath.stride_m(1.2, 0.0), 0.0)
	assert_eq(SiegeWheelMath.stride_m(0.0, 3.0), 0.0)


func test_worker_count_bands() -> void:
	assert_eq(SiegeWheelMath.worker_count(0.0, 1), 1)
	assert_eq(SiegeWheelMath.worker_count(149.0, 1), 1)
	assert_eq(SiegeWheelMath.worker_count(150.0, 1), 2)
	assert_eq(SiegeWheelMath.worker_count(300.0, 2), 2)
	assert_eq(SiegeWheelMath.worker_count(301.0, 2), 3)
	assert_eq(SiegeWheelMath.worker_count(900.0, 1), 3, "a big jump goes straight to three")


func test_worker_count_hysteresis_is_20_w() -> void:
	# Two workers hold down to 130 W, three hold down to 280 W.
	assert_eq(SiegeWheelMath.worker_count(145.0, 2), 2)
	assert_eq(SiegeWheelMath.worker_count(131.0, 2), 2)
	assert_eq(SiegeWheelMath.worker_count(129.0, 2), 1)
	assert_eq(SiegeWheelMath.worker_count(295.0, 3), 3)
	assert_eq(SiegeWheelMath.worker_count(281.0, 3), 3)
	assert_eq(SiegeWheelMath.worker_count(279.0, 3), 2)
	assert_eq(SiegeWheelMath.worker_count(100.0, 3), 1, "a big drop goes straight to one")


func test_worker_count_does_not_flicker_around_a_threshold() -> void:
	var n := 1
	var changes := 0
	for w in [148.0, 152.0, 149.0, 151.0, 147.0, 153.0, 140.0, 135.0]:
		var m := SiegeWheelMath.worker_count(w, n)
		if m != n:
			changes += 1
		n = m
	assert_eq(changes, 1, "one rise at 152 W and no fall above 130 W")


func test_worker_offsets_match_the_count() -> void:
	assert_eq(SiegeWheelMath.worker_offsets(1).size(), 1)
	assert_eq(SiegeWheelMath.worker_offsets(2).size(), 2)
	assert_eq(SiegeWheelMath.worker_offsets(3).size(), 3)
	assert_eq(SiegeWheelMath.worker_offsets(9).size(), 3)
