extends GutTest
## CadenceEstimator (BRIEF 4.5): FTMS cadence when present and fresh; estimated from
## flywheel speed when absent or stale, with the speed-to-cadence ratio learned while both are
## valid or set by a 10 s calibration at 90 rpm.


func _s(t: float, power: float, cadence: float, speed: float) -> TrainerSample:
	return TrainerSample.make(t, power, cadence, speed)


func test_present_cadence_passes_unchanged_and_teaches_the_ratio() -> void:
	var est := CadenceEstimator.new()
	assert_eq(est.ratio(), 0.0)
	var s := _s(1.0, 200.0, 90.0, 36.0)
	var out := est.process(s)
	assert_same(out, s, "unchanged")
	assert_almost_eq(est.ratio(), 0.4, 1e-12, "36 km/h / 90 rpm")
	assert_eq(out.flags & TrainerSample.CADENCE_ESTIMATED, 0)


func test_absent_cadence_without_a_ratio_is_unchanged() -> void:
	var est := CadenceEstimator.new()
	var s := _s(1.0, 200.0, -1.0, 36.0)
	var out := est.process(s)
	assert_same(out, s)
	assert_false(out.has_cadence())


func test_absent_cadence_is_estimated_from_speed() -> void:
	var est := CadenceEstimator.new()
	for i in 5:
		est.process(_s(float(i), 200.0, 90.0, 36.0))
	var out := est.process(_s(6.0, 200.0, -1.0, 32.0))
	assert_true(out.has_cadence())
	assert_almost_eq(out.cadence_rpm, 80.0, 1e-9, "32 km/h / 0.4")
	assert_ne(out.flags & TrainerSample.CADENCE_ESTIMATED, 0)
	assert_almost_eq(out.power_w, 200.0, 1e-12)
	assert_almost_eq(out.t, 6.0, 1e-12)


func test_learning_is_an_average_and_ignores_low_values() -> void:
	var est := CadenceEstimator.new()
	est.process(_s(1.0, 200.0, 90.0, 36.0))
	est.process(_s(2.0, 200.0, 100.0, 50.0))
	assert_almost_eq(est.ratio(), 0.4 + CadenceEstimator.LEARN_ALPHA * (0.5 - 0.4), 1e-12)
	var r := est.ratio()
	est.process(_s(3.0, 50.0, 30.0, 20.0))
	est.process(_s(4.0, 50.0, 90.0, 3.0))
	assert_almost_eq(est.ratio(), r, 1e-12, "below 40 rpm or 5 km/h teaches nothing")


func test_frozen_cadence_is_stale() -> void:
	var est := CadenceEstimator.new()
	for i in 4:
		est.process(_s(float(i), 200.0, 90.0 + float(i % 2), 36.0))
	# The trainer keeps reporting 60 rpm while the flywheel speeds up: after stale_s it is stale.
	est.process(_s(5.0, 400.0, 60.0, 36.0))
	var r := est.ratio()
	est.process(_s(6.0, 400.0, 60.0, 44.0))
	var fresh := est.process(_s(7.0, 400.0, 60.0, 48.0))
	assert_eq(fresh.flags & TrainerSample.CADENCE_ESTIMATED, 0, "2 s unchanged is not stale yet")
	assert_almost_eq(est.ratio(), r, 1e-12, "a repeated value while the speed moves teaches nothing")
	var stale := est.process(_s(8.5, 400.0, 60.0, 48.0))
	assert_ne(stale.flags & TrainerSample.CADENCE_ESTIMATED, 0, "3.5 s unchanged with speed +33%")
	assert_almost_eq(stale.cadence_rpm, 48.0 / r, 1e-9)


## W2r2: a coasting rider (power < 15 W, BRIEF 3.5) on a flywheel that spins down. The crank
## reads 0 rpm and keeps reading 0 while the speed falls: that's no frozen estimate, so no
## cadence is invented from the flywheel's momentum (it would hide coasting, pause, AFK and
## the warm-up's 20-minute reset).
func test_a_resting_crank_on_a_spinning_down_flywheel_is_not_stale() -> void:
	var est := CadenceEstimator.new()
	for i in 4:
		est.process(_s(float(i), 200.0, 90.0, 36.0))
	assert_almost_eq(est.ratio(), 0.4, 1e-9)
	for i in 20:
		var speed := 36.0 * pow(0.9, float(i + 1))
		var out := est.process(_s(4.0 + float(i), 0.0, 0.0, speed))
		assert_eq(out.flags & TrainerSample.CADENCE_ESTIMATED, 0, "coasting %d s: kept as reported" % (i + 1))
		assert_eq(out.cadence_rpm, 0.0)
	assert_almost_eq(est.ratio(), 0.4, 1e-9, "nothing learned from it")
	assert_almost_eq(est.cadence_age_s(23.0), 0.0, 1e-9, "a fresh reading")


func test_no_cadence_is_estimated_while_coasting() -> void:
	var est := CadenceEstimator.new()
	for i in 4:
		est.process(_s(float(i), 200.0, 90.0, 36.0))
	var coast := est.process(_s(5.0, 10.0, -1.0, 30.0))
	assert_false(coast.has_cadence(), "under 15 W an absent cadence stays absent")
	var pedal := est.process(_s(6.0, 150.0, -1.0, 30.0))
	assert_ne(pedal.flags & TrainerSample.CADENCE_ESTIMATED, 0, "pedaling again: estimated as before")
	assert_almost_eq(pedal.cadence_rpm, 75.0, 1e-9)


func test_a_frozen_zero_while_pedaling_is_still_stale() -> void:
	var est := CadenceEstimator.new()
	for i in 4:
		est.process(_s(float(i), 200.0, 90.0 + float(i % 2), 36.0))
	var r := est.ratio()
	est.process(_s(5.0, 200.0, 0.0, 36.0))
	est.process(_s(7.0, 200.0, 0.0, 40.0))
	var stale := est.process(_s(8.5, 200.0, 0.0, 44.0))
	assert_ne(stale.flags & TrainerSample.CADENCE_ESTIMATED, 0, "200 W at a 0 rpm reading: the reading is frozen")
	assert_almost_eq(stale.cadence_rpm, 44.0 / r, 1e-9)


func test_unchanged_cadence_at_steady_speed_is_not_stale() -> void:
	var est := CadenceEstimator.new()
	for i in 10:
		var out := est.process(_s(float(i), 200.0, 90.0, 36.0))
		assert_eq(out.flags & TrainerSample.CADENCE_ESTIMATED, 0)


func test_calibration_at_90_rpm() -> void:
	var est := CadenceEstimator.new()
	est.start_calibration(90.0)
	assert_true(est.is_calibrating())
	for i in 11:
		est.process(_s(float(i), 180.0, -1.0, 27.0 + (0.9 if i % 2 == 0 else -0.9)))
	assert_false(est.is_calibrating(), "done after 10 s")
	assert_almost_eq(est.ratio() * 90.0, 27.0 + 0.9 / 11.0, 1e-9, "mean speed / 90 rpm")


func test_calibration_ignores_reported_cadence() -> void:
	var est := CadenceEstimator.new()
	est.process(_s(0.0, 200.0, 90.0, 36.0))
	est.start_calibration(90.0)
	for i in 11:
		est.process(_s(1.0 + float(i), 200.0, 70.0, 27.0))
	assert_almost_eq(est.ratio(), 0.3, 1e-12, "27 km/h held at the 90 rpm target")


func test_calibration_rejects_a_bad_target() -> void:
	var est := CadenceEstimator.new()
	est.start_calibration(0.0)
	assert_push_error("calibration target")
	assert_false(est.is_calibrating())


func test_samples_already_estimated_pass_through() -> void:
	var est := CadenceEstimator.new()
	est.process(_s(0.0, 200.0, 90.0, 36.0))
	var s := _s(1.0, 200.0, 50.0, 36.0)
	s.flags |= TrainerSample.CADENCE_ESTIMATED
	assert_same(est.process(s), s)
	assert_almost_eq(est.ratio(), 0.4, 1e-12, "never learns from an estimate")


func test_cadence_age_and_reset() -> void:
	var est := CadenceEstimator.new()
	assert_eq(est.cadence_age_s(5.0), INF)
	est.process(_s(2.0, 200.0, 90.0, 36.0))
	assert_almost_eq(est.cadence_age_s(5.0), 3.0, 1e-12)
	est.reset()
	assert_eq(est.ratio(), 0.0)
	assert_eq(est.cadence_age_s(5.0), INF)
	assert_null(est.process(null))
