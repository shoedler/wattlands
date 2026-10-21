extends "res://tests/governor/gov_test_base.gd"
## BRIEF 4.6.1 duration limits: time with the applied target above 105% FTP (300 s) and
## above 120% FTP (60 s); when a limit is reached the ceiling drops to that band and stays
## until the applied target has been <= 90% FTP for 120 consecutive seconds of ERG
## (inclusive), which resets both counters. A switch to SIM restarts that count; SIM time
## adds nothing. Whole watts: a target exactly at 105% is not counted.


func _count(rig: Rig, pred: Callable) -> int:
	var n := 0
	for s: Dictionary in rig.trace:
		if pred.call(s):
			n += 1
	return n


func _latched_rig() -> Rig:
	var rig := make_rig({}, follower())
	rig.keep_trace = true
	rig.start(
		[
			erg(Wl.WORK, 110.0, 290.0),
			erg(Wl.WORK, 110.0, 290.0),
			erg(Wl.RECOVERY, 90.0, 200.0),
			sim(Wl.GRADE_FLAT, 30.0, Wl.FREE),
			erg(Wl.RECOVERY, 90.0, 200.0)
		]
	)
	rig.run(290.0)
	rig.gov.start_phase(1)
	rig.run(30.0)
	return rig


func test_105_limit_latches_after_300_s_above() -> void:
	var rig := _latched_rig()
	var above := _count(rig, func(s: Dictionary) -> bool: return int(s["applied_target_w"]) > 210)
	assert_eq(above, 6000, "exactly 300 s with the applied target above 105% (210 W)")
	assert_true(rig.s()["latched_105"])
	assert_eq(rig.applied_w(), 210, "ceiling dropped to 105%")
	assert_has(rig.s()["clamped_by"], Wl.CLAMP_LIMIT_105)
	assert_almost_eq(float(rig.s()["s_left_105"]), 0.0, 1e-9)
	assert_false(rig.s()["latched_120"])


func test_s_left_counts_down() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 110.0, 290.0)])
	rig.run(10.0)
	var left_a := float(rig.s()["s_left_105"])
	rig.run(100.0)
	assert_almost_eq(float(rig.s()["s_left_105"]), left_a - 100.0, 1e-6)
	assert_almost_eq(float(rig.s()["s_left_120"]), 60.0, 1e-9, "220 W is not above 120%")


func test_target_exactly_at_105_is_not_counted() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 105.0, 290.0), erg(Wl.WORK, 105.0, 290.0)])
	rig.run(290.0)
	rig.gov.start_phase(1)
	rig.run(290.0)
	assert_eq(rig.applied_w(), 210)
	assert_almost_eq(float(rig.s()["s_left_105"]), 300.0, 1e-9)
	assert_false(rig.s()["latched_105"])
	var cb: Array = rig.s()["clamped_by"]
	assert_eq(cb.size(), 0, "nothing clamped at exactly 105%")


func test_whole_watts_decide_at_odd_ftp() -> void:
	# FTP 201: 105% is 211.05 W. 105% gives 211 W (not above); 105.5% gives 212 W (above).
	var rig := make_rig({"ftp_w": 201.0}, follower())
	rig.start([erg(Wl.WORK, 105.0, 200.0), erg(Wl.WORK, 105.5, 200.0)])
	rig.run(100.0)
	assert_eq(rig.applied_w(), 211)
	assert_almost_eq(float(rig.s()["s_left_105"]), 300.0, 1e-9)
	rig.gov.start_phase(1)
	rig.run(20.0)
	assert_eq(rig.applied_w(), 212)
	assert_almost_eq(float(rig.s()["s_left_105"]), 280.0, DT * 1.01)


func test_120_limit_latches_after_60_s_and_105_after_300_s() -> void:
	var rig := make_rig({}, follower())
	rig.keep_trace = true
	rig.start([erg(Wl.WORK, 125.0, 290.0), erg(Wl.WORK, 125.0, 290.0)])
	rig.run(80.0)
	assert_true(rig.s()["latched_120"])
	assert_eq(rig.applied_w(), 240, "ceiling 120%")
	assert_has(rig.s()["clamped_by"], Wl.CLAMP_LIMIT_120)
	assert_eq(
		_count(rig, func(s: Dictionary) -> bool: return int(s["applied_target_w"]) > 240),
		1200,
		"exactly 60 s above 120% (240 W)"
	)
	rig.run(210.0)
	rig.gov.start_phase(1)
	rig.run(60.0)
	assert_true(rig.s()["latched_105"])
	assert_eq(rig.applied_w(), 210)
	assert_eq(
		_count(rig, func(s: Dictionary) -> bool: return int(s["applied_target_w"]) > 210), 6000
	)


func test_reset_after_120_s_at_or_below_90_pct_inclusive() -> void:
	var rig := _latched_rig()
	rig.gov.start_phase(2)
	var t0 := rig.t
	rig.run(125.0)
	assert_false(rig.s()["latched_105"])
	assert_almost_eq(float(rig.s()["s_left_105"]), 300.0, 1e-9)
	# Find the tick that reset it and the run of ticks <= 180 W ending there.
	var reset_i := -1
	for i in rig.trace.size():
		var s: Dictionary = rig.trace[i]
		if float(s["rig_t"]) > t0 and not bool(s["latched_105"]):
			reset_i = i
			break
	assert_gt(reset_i, 0)
	var run := 0
	var j := reset_i
	while j >= 0 and int(rig.trace[j]["applied_target_w"]) <= 180:
		run += 1
		j -= 1
	assert_eq(run, 2400, "120.0 s at <= 90% FTP, inclusive")
	assert_true(bool(rig.trace[reset_i - 1]["latched_105"]), "still latched at 119.95 s")


func test_reset_clears_both_limits() -> void:
	# 125% latches the 120% limit at 60 s and the 105% limit at 300 s; 120 s at 90% resets both
	# counters and both latches, so the next 125% interval runs unclamped.
	var rig := make_rig({}, follower())
	rig.start(
		[
			erg(Wl.WORK, 125.0, 290.0),
			erg(Wl.WORK, 125.0, 290.0),
			erg(Wl.RECOVERY, 90.0, 200.0),
			erg(Wl.WORK, 125.0, 100.0)
		]
	)
	rig.run(290.0)
	rig.gov.start_phase(1)
	rig.run(20.0)
	assert_true(rig.s()["latched_120"])
	assert_true(rig.s()["latched_105"])
	assert_eq(rig.applied_w(), 210)
	rig.gov.start_phase(2)
	rig.run(119.0)
	assert_true(rig.s()["latched_120"], "not reset before 120 s")
	assert_true(rig.s()["latched_105"])
	rig.run(1.5)
	assert_false(rig.s()["latched_120"])
	assert_false(rig.s()["latched_105"])
	assert_almost_eq(float(rig.s()["s_left_105"]), 300.0, 1e-9)
	assert_almost_eq(float(rig.s()["s_left_120"]), 60.0, 1e-9)
	rig.gov.start_phase(3)
	rig.run(10.0)
	assert_eq(rig.applied_w(), 250, "125% again after the reset")
	for name: String in [Wl.CLAMP_LIMIT_105, Wl.CLAMP_LIMIT_120]:
		assert_does_not_have(rig.s()["clamped_by"], name)


func test_paused_floor_counts_toward_the_reset() -> void:
	# A pause holds the ERG floor (<= 90%) in ERG, so it is part of the 120 s recovery.
	var rig := _latched_rig()
	rig.gov.start_phase(2)
	rig.run(60.0)
	rig.gov.set_game_paused(true)
	rig.run(61.0)
	assert_false(rig.s()["latched_105"], "60 s at 90% plus 60 s at the paused floor")


func test_91_pct_never_resets() -> void:
	var rig := make_rig({}, follower())
	rig.start(
		[erg(Wl.WORK, 110.0, 290.0), erg(Wl.WORK, 110.0, 290.0), erg(Wl.RECOVERY, 90.5, 290.0)]
	)
	rig.run(290.0)
	rig.gov.start_phase(1)
	rig.run(30.0)
	assert_true(rig.s()["latched_105"])
	rig.gov.start_phase(2)
	rig.run(200.0)
	assert_eq(rig.applied_w(), 181)
	assert_true(rig.s()["latched_105"], "181 W is above 90% of 200 W")


func test_switch_to_sim_restarts_the_reset_count() -> void:
	var rig := _latched_rig()
	rig.gov.start_phase(2)
	rig.run(100.0)
	assert_true(rig.s()["latched_105"])
	rig.gov.start_phase(3)
	rig.run(30.0)
	assert_true(rig.s()["latched_105"], "SIM time does not count toward the reset")
	rig.gov.start_phase(4)
	var t0 := rig.t
	var reset_t := rig.run_until(func() -> bool: return not bool(rig.s()["latched_105"]), 130.0)
	assert_gt(reset_t, 0.0)
	assert_almost_eq(reset_t - t0, 120.0, 0.11, "a fresh 120 s after the SIM phase")


func test_sim_time_adds_nothing() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 125.0, 100.0), sim(Wl.GRADE_FLAT, 120.0, Wl.FREE)])
	rig.run(40.0)
	var left_105 := float(rig.s()["s_left_105"])
	var left_120 := float(rig.s()["s_left_120"])
	assert_lt(left_120, 60.0)
	rig.gov.start_phase(1)
	rig.run(100.0)
	assert_almost_eq(float(rig.s()["s_left_105"]), left_105, 0.06, "SIM adds nothing")
	assert_almost_eq(float(rig.s()["s_left_120"]), left_120, 0.06)


func test_unverified_targets_count_after_the_factor() -> void:
	var rig := make_rig({"ftp_verified": false}, follower())
	rig.start([erg(Wl.WORK, 110.0, 290.0)])
	rig.run(200.0)
	assert_eq(rig.applied_w(), 187, "110% x 0.85")
	assert_almost_eq(float(rig.s()["s_left_105"]), 300.0, 1e-9, "93.5% counts nothing")


func test_latched_ceiling_covers_directives() -> void:
	var rig := _latched_rig()
	rig.gov.set_plan(EffortPlan.of([erg(Wl.WORK, 100.0, 290.0).with_range(100.0, 125.0)]))
	rig.gov.start_phase(0)
	var rec := rig.directive({"target_pct": 125.0})
	assert_false(rec["refused"])
	assert_eq(int(rec["applied"]["target_w"]), 210)
	assert_has(rec["clamped_by"], Wl.CLAMP_LIMIT_105)
