extends GutTest
## CrankClock (SPEC_AUDIO 1.2, EXECUTION_DAG E1): one rider's crank phase, the one number audio and view both read.


func test_advance_integrates_cadence() -> void:
	var c := CrankClock.new()
	c.advance(90.0, 1.0)
	assert_almost_eq(c.revs, 1.5, 1e-12)
	c.advance(60.0, 0.5)
	assert_almost_eq(c.revs, 2.0, 1e-12)


func test_advance_returns_the_revolutions_crossed() -> void:
	var c := CrankClock.new()
	assert_eq(c.advance(60.0, 0.5), 0)
	assert_eq(c.advance(60.0, 0.5), 1)
	assert_eq(c.advance(60.0, 2.5), 2)
	assert_eq(c.advance(60.0, 0.25), 0, "3.5 to 3.75 is no crossing")


func test_crossings_counts_whole_revolutions() -> void:
	var c := CrankClock.new()
	c.advance(120.0, 3.25)
	assert_eq(c.crossings(), 6)
	assert_almost_eq(c.frac(), 0.5, 1e-12)
	assert_almost_eq(c.angle(), 0.5 * TAU, 1e-12)


func test_stands_still_at_or_below_stop_rpm() -> void:
	var c := CrankClock.new()
	c.advance(90.0, 1.0)
	for rpm: float in [0.0, 0.5, CrankClock.STOP_RPM, -30.0]:
		assert_eq(c.advance(rpm, 1.0), 0, "rpm %.1f" % rpm)
		assert_almost_eq(c.revs, 1.5, 1e-12, "rpm %.1f" % rpm)


func test_zero_or_negative_dt_stands_still() -> void:
	var c := CrankClock.new()
	assert_eq(c.advance(90.0, 0.0), 0)
	assert_eq(c.advance(90.0, -1.0), 0)
	assert_eq(c.revs, 0.0)


func test_frac_is_in_range_below_zero_too() -> void:
	var c := CrankClock.new()
	c.revs = -0.25
	assert_almost_eq(c.frac(), 0.75, 1e-12)


func test_reset() -> void:
	var c := CrankClock.new()
	c.advance(90.0, 10.0)
	c.reset()
	assert_eq(c.revs, 0.0)
	assert_eq(c.crossings(), 0)
