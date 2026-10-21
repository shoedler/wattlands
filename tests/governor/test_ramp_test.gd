extends "res://tests/governor/gov_test_base.gd"
## BRIEF 3.2 and 4.6.1: the FTP test's ramp_test profile suspends the duration limits, the
## 105% cap for long phases, the 150% cap and the unverified factor; the ceiling is
## min(1000 W, trainer max); slew, the floor, coasting, panic and rescue still apply, and a
## rescue ends the test (50% stands, never ramps back into a step).

const RT := {"profile": "ramp_test", "ftp_verified": false}


## The test's protocol at FTP 200: 65% + 6% per one-minute step.
func _steps(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(erg(Wl.WORK, 65.0 + 6.0 * i, 60.0, "Step %d" % (i + 1)))
	return out


func test_no_unverified_factor() -> void:
	var rig := make_rig(RT, follower())
	rig.start([erg(Wl.WORK, 100.0, 60.0)])
	rig.run(15.0)
	assert_eq(rig.applied_w(), 200, "100% of an unverified 200 W, no x0.85")
	assert_does_not_have(rig.s()["clamped_by"], Wl.CLAMP_UNVERIFIED)
	assert_eq(rig.s()["profile"], "ramp_test")


func test_no_150_pct_cap_but_1000_w_and_trainer_max() -> void:
	var rig := make_rig(RT, follower())
	rig.start([erg(Wl.WORK, 180.0, 60.0)])
	rig.run(20.0)
	assert_eq(rig.applied_w(), 360, "180% of 200 W passes the normal 300 W ceiling")
	var rig2 := make_rig(RT.merged({"ftp_w": 700.0}), follower())
	rig2.start([erg(Wl.WORK, 160.0, 60.0)])
	rig2.run(40.0)
	assert_eq(rig2.applied_w(), 1000, "1000 W absolute")
	assert_has(rig2.s()["clamped_by"], Wl.CLAMP_CEILING)
	var rig3 := make_rig(RT.merged({"trainer_max_w": 300.0}), follower())
	rig3.start([erg(Wl.WORK, 180.0, 60.0)])
	rig3.run(20.0)
	assert_eq(rig3.applied_w(), 300, "the trainer's Supported Power Range max")


func test_no_long_phase_cap() -> void:
	var rig := make_rig(RT, follower())
	rig.start([erg(Wl.WORK, 110.0, 400.0)])
	rig.run(20.0)
	assert_eq(rig.applied_w(), 220)
	assert_does_not_have(rig.s()["clamped_by"], Wl.CLAMP_LONG_PHASE)


func test_no_duration_limits() -> void:
	var rig := make_rig(RT, follower())
	rig.start([erg(Wl.WORK, 125.0, 400.0)])
	rig.run(400.0)
	assert_eq(rig.applied_w(), 250, "still 125% after 400 s")
	assert_false(rig.s()["latched_105"])
	assert_false(rig.s()["latched_120"])
	assert_almost_eq(float(rig.s()["s_left_105"]), 300.0, 1e-9)
	assert_almost_eq(float(rig.s()["s_left_120"]), 60.0, 1e-9)


func test_slew_and_floor_still_apply() -> void:
	var rig := make_rig(RT, follower())
	rig.keep_trace = true
	rig.start([erg(Wl.WORK, 10.0, 30.0), erg(Wl.WORK, 125.0, 60.0)])
	rig.run(10.0)
	assert_eq(rig.applied_w(), 60, "10% of 200 W lifted to the 60 W floor")
	assert_has(rig.s()["clamped_by"], Wl.CLAMP_FLOOR)
	rig.gov.start_phase(1)
	rig.run(1.0)
	assert_lte(rig.applied_w(), 60 + 30, "30 W/s")
	assert_has(rig.s()["clamped_by"], Wl.CLAMP_SLEW)


func test_rescue_ends_the_test_and_50_pct_stands() -> void:
	var rig := make_rig(RT, follower())
	rig.start(_steps(8))
	rig.run(10.0)
	rig.gov.start_phase(1)
	rig.run(10.0)
	assert_eq(rig.applied_w(), 142, "step 2: 71% of 200 W")
	var dev: ScriptedDevice = rig.device
	dev.cadence_rpm = 30.0
	rig.run(5.0)
	assert_true(rig.s()["rescue"])
	assert_true(rig.s()["test_ended"])
	assert_eq(rig.applied_w(), 100)
	var ended := rig.events_named("ramp_test_ended")
	assert_eq(ended.size(), 1)
	assert_eq(ended[0]["value"], "rescue")
	dev.cadence_rpm = 90.0
	rig.run(15.0)
	assert_false(rig.s()["rescue"], "the hold ends")
	assert_false(rig.s()["rescue_ramp"], "no ramp back")
	assert_eq(rig.applied_w(), 100, "50% stands")
	rig.gov.start_phase(4)
	rig.run(20.0)
	assert_eq(rig.applied_w(), 100, "never ramps back into a step")
	assert_eq(rig.events_named("ramp_test_ended").size(), 1)


func test_coasting_still_applies() -> void:
	var rig := make_rig(RT, follower())
	rig.start(_steps(3))
	rig.run(20.0)
	var dev: ScriptedDevice = rig.device
	dev.erg_follow = -1.0
	dev.power_w = 0.0
	dev.cadence_rpm = 0.0
	rig.run(5.0)
	assert_eq(rig.applied_w(), 60)
	assert_true(rig.s()["coasting"])


func test_panic_still_applies() -> void:
	var rig := make_rig(RT, follower())
	rig.start(_steps(3))
	rig.run(20.0)
	rig.gov.emergency_safe()
	var dev: ScriptedDevice = rig.device
	assert_eq(dev.mode, Wl.SIM)
	assert_almost_eq(dev.grade_pct, 0.0, 1e-9)


func test_new_plan_clears_the_ended_test() -> void:
	var rig := make_rig(RT, follower())
	rig.start(_steps(3))
	rig.run(20.0)
	var dev: ScriptedDevice = rig.device
	dev.cadence_rpm = 30.0
	rig.run(5.0)
	assert_true(rig.s()["test_ended"])
	dev.cadence_rpm = 90.0
	rig.start(_steps(3))
	assert_false(rig.s()["test_ended"])
