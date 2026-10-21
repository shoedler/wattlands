extends "res://tests/governor/gov_test_base.gd"
## BRIEF 4.6.12 precedence: panic > [target x unverified, ceilings, duration limits, warm-up
## cap] > rescue 50% > coasting floor (wins over rescue) > the floor (wins over every cap and
## over rescue's 50% at low FTP) > slew (last, increases only). BRIEF 7.1 overlaps.


func _cadence_drop(rig: Rig, rpm: float, wait_s: float) -> void:
	var dev: ScriptedDevice = rig.device
	dev.cadence_rpm = rpm
	rig.run(wait_s)


func test_floor_beats_warmup_and_rescue_at_ftp_60_to_100() -> void:
	# During warm-up with rescue active, at FTP 60..100 W the result is never below 50 W.
	for ftp: float in [60.0, 65.0, 76.0, 77.0, 90.0, 99.0, 100.0]:
		var rig := make_rig({"ftp_w": ftp, "skip_warmup": false}, follower())
		rig.start([erg(Wl.WORK, 100.0, 600.0)])
		rig.run(10.0)
		_cadence_drop(rig, 30.0, 5.0)
		var expect := maxi(GovernorClamps.floor_w(ftp), GovernorClamps.whole_w(0.5 * ftp))
		assert_true(rig.s()["rescue"], "rescue at FTP %s" % ftp)
		assert_eq(rig.applied_w(), expect, "FTP %s" % ftp)
		assert_eq(rig.applied_w(), 50, "the 50 W floor at FTP %s" % ftp)


func test_floor_beats_the_ceiling_and_long_phase_cap() -> void:
	var rig := make_rig({"ftp_w": 30.0}, follower())
	rig.start([erg(Wl.WORK, 150.0, 600.0)])
	rig.run(10.0)
	assert_eq(rig.applied_w(), 50, "150% of 30 W is 45 W; the floor is 50 W")
	var cb: Array = rig.s()["clamped_by"]
	assert_eq(cb[cb.size() - 1], Wl.CLAMP_FLOOR, "the floor applies after every cap")


func test_coasting_beats_rescue_and_the_floor_is_the_result() -> void:
	var rig := make_rig({"ftp_w": 300.0}, follower())
	rig.start([erg(Wl.WORK, 90.0, 600.0)])
	rig.run(15.0)
	_cadence_drop(rig, 30.0, 5.0)
	assert_eq(rig.applied_w(), 150, "rescue 50% of 300 W")
	var dev: ScriptedDevice = rig.device
	dev.erg_follow = -1.0
	dev.power_w = 0.0
	dev.cadence_rpm = 0.0
	rig.run(5.0)
	assert_eq(rig.applied_w(), 90, "coasting floor (30% of 300 W) beats rescue's 150 W")


func test_slew_is_last_and_only_limits_increases() -> void:
	# FTP 800: the 10 s rescue ramp-back from 400 W to 800 W asks for 40 W/s; slew caps it at
	# 30 W/s. The drop into rescue is immediate.
	var rig := make_rig({"ftp_w": 800.0}, follower())
	rig.keep_trace = true
	rig.start([erg(Wl.WORK, 100.0, 600.0)])
	rig.run(30.0)
	assert_eq(rig.applied_w(), 800)
	var dev: ScriptedDevice = rig.device
	dev.cadence_rpm = 30.0
	var t_r := rig.run_until(func() -> bool: return bool(rig.s()["rescue"]), 6.0)
	assert_eq(rig.applied_w(), 400, "the drop is immediate")
	dev.cadence_rpm = 90.0
	var t_ramp := rig.run_until(func() -> bool: return bool(rig.s()["rescue_ramp"]), 6.0)
	assert_gt(t_ramp, t_r)
	rig.run(10.0)
	assert_lt(rig.applied_w(), 800, "the 10 s ramp asked for 800 W, slew lags behind")
	assert_has(rig.s()["clamped_by"], Wl.CLAMP_SLEW)
	rig.run(5.0)
	assert_eq(rig.applied_w(), 800)
	var worst := 0
	for i in range(20, rig.trace.size()):
		worst = maxi(
			worst,
			int(rig.trace[i]["applied_target_w"]) - int(rig.trace[i - 20]["applied_target_w"])
		)
	assert_lte(worst, 30)


func test_panic_beats_everything() -> void:
	var rig := make_rig({"ftp_w": 70.0, "skip_warmup": false, "ftp_verified": false}, follower())
	rig.start([erg(Wl.WORK, 100.0, 600.0)])
	rig.run(10.0)
	_cadence_drop(rig, 30.0, 5.0)
	rig.gov.emergency_safe()
	rig.run(1.0)
	assert_eq(rig.s()["clamped_by"], [Wl.CLAMP_PANIC])
	assert_eq(rig.s()["mode"], Wl.SIM)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 0.0, 1e-9)
