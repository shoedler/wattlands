extends GutTest
## GovernorClamps (BRIEF 4.6.1, 4.6.12, 3.2): the ERG floor max(30% FTP, 50 W) rounded up,
## the ceiling min(150% FTP, 1000 W, trainer max) rounded down, whole-watt targets, the
## unverified factor and the ramp_test ceiling.


func test_constants() -> void:
	assert_eq(GovernorClamps.FLOOR_PCT, 30.0)
	assert_eq(GovernorClamps.FLOOR_MIN_W, 50.0)
	assert_eq(GovernorClamps.CEILING_PCT, 150.0)
	assert_eq(GovernorClamps.CEILING_ABS_W, 1000.0)
	assert_eq(GovernorClamps.UNVERIFIED_FACTOR, 0.85)
	assert_eq(GovernorClamps.KICKR_MAX_W, 1800)


func test_floor() -> void:
	assert_eq(GovernorClamps.floor_w(60.0), 50, "18 W < 50 W")
	assert_eq(GovernorClamps.floor_w(100.0), 50, "30 W < 50 W")
	assert_eq(GovernorClamps.floor_w(166.0), 50, "49.8 W < 50 W")
	assert_eq(GovernorClamps.floor_w(166.7), 51, "50.01 W rounds up")
	assert_eq(GovernorClamps.floor_w(200.0), 60)
	assert_eq(GovernorClamps.floor_w(201.0), 61, "60.3 W rounds up")
	assert_eq(GovernorClamps.floor_w(400.0), 120)
	assert_eq(GovernorClamps.floor_w(0.0), 50)


func test_ceiling() -> void:
	assert_eq(GovernorClamps.ceiling_w(60.0), 90)
	assert_eq(GovernorClamps.ceiling_w(100.0), 150)
	assert_eq(GovernorClamps.ceiling_w(166.7), 250, "250.05 W rounds down")
	assert_eq(GovernorClamps.ceiling_w(200.0), 300)
	assert_eq(GovernorClamps.ceiling_w(400.0), 600)
	assert_eq(GovernorClamps.ceiling_w(667.0), 1000, "1000.5 W capped at 1000 W")
	assert_eq(GovernorClamps.ceiling_w(800.0), 1000, "1000 W absolute cap")


func test_ceiling_with_trainer_max() -> void:
	assert_eq(GovernorClamps.ceiling_w(400.0, 800.0), 600, "150% FTP is lower")
	assert_eq(GovernorClamps.ceiling_w(600.0, 800.0), 800, "trainer max 800 W")
	assert_eq(GovernorClamps.ceiling_w(800.0, 800.0), 800)
	assert_eq(GovernorClamps.ceiling_w(800.0, 1800.0), 1000)
	assert_eq(GovernorClamps.ceiling_w(800.0, 0.0), 1000, "unknown trainer max")
	assert_eq(GovernorClamps.ceiling_w(800.0, -1.0), 1000, "unknown trainer max")
	assert_eq(GovernorClamps.ceiling_w(600.0, 799.5), 799, "rounded down")


func test_ramp_test_ceiling() -> void:
	assert_eq(GovernorClamps.ramp_test_ceiling_w(), 1000)
	assert_eq(GovernorClamps.ramp_test_ceiling_w(1800.0), 1000)
	assert_eq(GovernorClamps.ramp_test_ceiling_w(800.0), 800)
	assert_eq(GovernorClamps.ramp_test_ceiling_w(0.0), 1000, "unknown trainer max")
	assert_eq(GovernorClamps.ramp_test_ceiling_w(950.7), 950)


func test_unverified_factor() -> void:
	assert_eq(GovernorClamps.unverified_factor(false), 0.85)
	assert_eq(GovernorClamps.unverified_factor(true), 1.0)


func test_pct_conversions() -> void:
	assert_almost_eq(GovernorClamps.pct_to_w(75.0, 240.0), 180.0, 1e-9)
	assert_almost_eq(GovernorClamps.w_to_pct(180.0, 240.0), 75.0, 1e-9)
	assert_eq(GovernorClamps.w_to_pct(100.0, 0.0), 10000.0, "FTP floored at 1")


func test_whole_w_rounds_down() -> void:
	assert_eq(GovernorClamps.whole_w(150.99), 150)
	assert_eq(GovernorClamps.whole_w(150.0), 150)
	assert_eq(GovernorClamps.whole_w(149.9999999999), 150, "float noise just under a whole watt")
	assert_eq(GovernorClamps.whole_w(0.85 * 200.0), 170, "0.85 x 200 is 170 W")


func _clamp(target: float, ftp: float, trainer_max: float = 1800.0) -> Dictionary:
	return GovernorClamps.clamp_absolute(target, ftp, trainer_max)


func test_clamp_inside_the_limits() -> void:
	var r := _clamp(200.0, 200.0)
	assert_eq(r["w"], 200)
	assert_eq((r["clamped_by"] as Array).size(), 0)
	assert_true(r["w"] is int)


func test_target_exactly_at_the_ceiling_is_not_clamped() -> void:
	var r := _clamp(300.0, 200.0)
	assert_eq(r["w"], 300)
	assert_eq((r["clamped_by"] as Array).size(), 0)
	r = _clamp(300.9, 200.0)
	assert_eq(r["w"], 300, "whole watts round down to the ceiling")
	assert_eq((r["clamped_by"] as Array).size(), 0, "300.9 W is 300 W, which is at the cap")
	r = _clamp(1.5 * 166.7, 166.7)
	assert_eq(r["w"], 250)
	assert_eq((r["clamped_by"] as Array).size(), 0)


func test_target_above_the_ceiling_is_clamped() -> void:
	var r := _clamp(301.0, 200.0)
	assert_eq(r["w"], 300)
	assert_eq(r["clamped_by"], [Wl.CLAMP_CEILING])
	r = _clamp(1500.0, 900.0)
	assert_eq(r["w"], 1000, "absolute 1000 W")
	assert_eq(r["clamped_by"], [Wl.CLAMP_CEILING])
	r = _clamp(900.0, 600.0, 800.0)
	assert_eq(r["w"], 800, "trainer max")
	assert_eq(r["clamped_by"], [Wl.CLAMP_CEILING])


func test_target_exactly_at_the_floor_is_not_clamped() -> void:
	var r := _clamp(60.0, 200.0)
	assert_eq(r["w"], 60)
	assert_eq((r["clamped_by"] as Array).size(), 0)
	r = _clamp(51.0, 166.7)
	assert_eq(r["w"], 51)
	assert_eq((r["clamped_by"] as Array).size(), 0)


func test_target_below_the_floor_is_raised() -> void:
	var r := _clamp(59.9, 200.0)
	assert_eq(r["w"], 60, "59.9 W rounds down to 59 W, then the floor lifts it to 60 W")
	assert_eq(r["clamped_by"], [Wl.CLAMP_FLOOR])
	r = _clamp(0.0, 400.0)
	assert_eq(r["w"], 120)
	assert_eq(r["clamped_by"], [Wl.CLAMP_FLOOR])
	r = _clamp(30.0, 60.0)
	assert_eq(r["w"], 50, "50 W floor at FTP 60")
	assert_eq(r["clamped_by"], [Wl.CLAMP_FLOOR])
	r = _clamp(50.005, 166.7)
	assert_eq(r["w"], 51, "floor 50.01 W rounds up to 51")
	assert_eq(r["clamped_by"], [Wl.CLAMP_FLOOR])


func test_floor_wins_over_the_ceiling() -> void:
	# FTP 20: ceiling 30 W, floor 50 W.
	var r := _clamp(100.0, 20.0)
	assert_eq(r["w"], 50)
	assert_eq(r["clamped_by"], [Wl.CLAMP_CEILING, Wl.CLAMP_FLOOR])
	# A trainer that reports a 40 W maximum: the floor still wins.
	r = _clamp(200.0, 200.0, 40.0)
	assert_eq(r["w"], 60)
	assert_eq(r["clamped_by"], [Wl.CLAMP_CEILING, Wl.CLAMP_FLOOR])


func test_rescue_and_warmup_targets_meet_the_floor_at_low_ftp() -> void:
	# BRIEF 4.6.12: 50 W is above 65% FTP below FTP 77 W and above 50% FTP below 100 W.
	for ftp: float in [60.0, 70.0, 76.0, 80.0, 99.0]:
		var rescue := GovernorClamps.pct_to_w(50.0, ftp)
		var r := _clamp(rescue, ftp)
		assert_eq(r["w"], 50, "rescue at FTP %s" % ftp)
		assert_has(r["clamped_by"], Wl.CLAMP_FLOOR)
	for ftp: float in [60.0, 76.0]:
		var r := _clamp(GovernorClamps.pct_to_w(65.0, ftp), ftp)
		assert_eq(r["w"], 50, "warm-up cap at FTP %s" % ftp)
	var high := _clamp(GovernorClamps.pct_to_w(50.0, 100.0), 100.0)
	assert_eq(high["w"], 50)
	assert_eq((high["clamped_by"] as Array).size(), 0, "50% of 100 W is exactly the floor")


func test_unverified_factor_applied_before_the_clamp() -> void:
	var ftp := 200.0
	var target := GovernorClamps.pct_to_w(150.0, ftp) * GovernorClamps.unverified_factor(false)
	var r := _clamp(target, ftp)
	assert_eq(r["w"], 255, "150% x 0.85 = 255 W stays under the 300 W ceiling")
	assert_eq((r["clamped_by"] as Array).size(), 0)
