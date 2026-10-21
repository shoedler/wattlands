extends "res://tests/governor/gov_test_base.gd"
## BRIEF 4.6.8 warm-up: the first 5 minutes of riding, counted from the first pedal stroke
## after the trainer connects, reset after 20 minutes without pedaling. During it ERG <= 65%
## FTP, SIM grade within -2..+3%, no haptics; skip_warmup opts out. 4.6.12: the floor wins
## over the warm-up cap at FTP 60-76 W. OWNERSHIP GOV7.

const WARM := {"skip_warmup": false}


func _pedal(rig: Rig, on: bool) -> float:
	var dev: ScriptedDevice = rig.device
	if on:
		dev.power_w = 150.0
		dev.cadence_rpm = 90.0
		dev.erg_follow = 1.0
	else:
		dev.erg_follow = -1.0
		dev.power_w = 0.0
		dev.cadence_rpm = 0.0
	var before := dev.samples_sent
	while dev.samples_sent == before:
		rig.step()
	return dev.sample_times[dev.sample_times.size() - 1]


func test_starts_at_the_first_pedal_stroke_and_lasts_5_minutes() -> void:
	var dev := ScriptedDevice.new()
	dev.power_w = 0.0
	dev.cadence_rpm = 0.0
	var rig := make_rig(WARM, dev)
	rig.start([erg(Wl.WORK, 80.0, 900.0)])
	rig.run(30.0)
	assert_true(rig.gov.is_warmup_active(), "active (pending) before the first stroke")
	assert_almost_eq(float(rig.s()["warmup_remaining_s"]), 300.0, 1e-9, "not counting yet")
	var t1 := _pedal(rig, true)
	rig.run(100.0)
	assert_almost_eq(float(rig.s()["warmup_remaining_s"]), 300.0 - (rig.t - t1), 1e-6)
	var ended := rig.run_until(func() -> bool: return not rig.gov.is_warmup_active(), 250.0)
	assert_time(ended, t1 + 300.0, "ends 300 s after the first stroke")
	var ev := rig.events_named("warmup_changed")
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["value"], false)


func test_erg_capped_at_65_pct() -> void:
	var rig := make_rig(WARM, follower())
	rig.start([erg(Wl.WORK, 80.0, 900.0)])
	rig.run(30.0)
	assert_eq(rig.applied_w(), 130, "65% of 200 W")
	assert_has(rig.s()["clamped_by"], Wl.CLAMP_WARMUP)
	rig.run(280.0)
	assert_false(rig.gov.is_warmup_active())
	rig.run(3.0)
	assert_eq(rig.applied_w(), 160, "after warm-up the plan's 80%")


func test_directive_capped_too() -> void:
	var rig := make_rig(WARM, follower())
	rig.start([erg(Wl.WORK, 55.0, 600.0).with_range(55.0, 100.0)])
	rig.run(10.0)
	var rec := rig.directive({"target_pct": 90.0})
	assert_false(rec["refused"])
	assert_eq(int(rec["applied"]["target_w"]), 130)
	assert_has(rec["clamped_by"], Wl.CLAMP_WARMUP)


func test_sim_grade_within_minus_2_and_plus_3() -> void:
	var rig := make_rig(WARM.merged({"difficulty_pct": 100.0}), follower())
	rig.start([sim(Wl.GRADE_GAME, 600.0)])
	rig.run(2.0)
	rig.gov.set_course_grade(8.0)
	rig.run(2.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 3.0, 1e-9)
	assert_has(rig.s()["clamped_by"], Wl.CLAMP_WARMUP)
	rig.gov.set_course_grade(-6.0)
	rig.run(2.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), -2.0, 1e-9)
	var dev: ScriptedDevice = rig.device
	assert_almost_eq(dev.grade_pct, -2.0, 1e-9, "the trainer got -2%")


func test_haptics_off_in_warmup() -> void:
	var rig := make_rig(WARM, follower())
	rig.start([sim(Wl.GRADE_FLAT, 600.0)])
	rig.run(5.0)
	var rec := rig.directive({"mode": "SIM", "haptic": 2.0, "duration_s": 1.5, "reason": "hit"})
	assert_true(rec["refused"])
	assert_eq(rec["reason"], Wl.REFUSE_HAPTIC_WARMUP)


func test_zero_rider_never_starts_it() -> void:
	var mock := MockTrainer.from_spec("zero", 200.0)
	var rig := make_rig(WARM, mock)
	rig.start([erg(Wl.WORK, 60.0, 900.0)])
	rig.run(400.0)
	assert_true(rig.gov.is_warmup_active())
	assert_almost_eq(float(rig.s()["warmup_remaining_s"]), 300.0, 1e-9)


func test_simulated_rider_pedals_from_t0() -> void:
	var mock := MockTrainer.from_spec("erg", 200.0)
	var rig := make_rig(WARM, mock)
	rig.start([erg(Wl.WORK, 60.0, 900.0)])
	var first := mock.last_sample()
	var ended := rig.run_until(func() -> bool: return not rig.gov.is_warmup_active(), 320.0)
	assert_null(first)
	assert_gt(ended, 300.0)
	assert_lt(ended, 302.0, "the erg mock pedals from its first sample (~1 s)")


func test_reset_after_20_minutes_without_pedaling() -> void:
	var rig := make_rig(WARM, follower())
	rig.start([erg(Wl.WORK, 80.0, 3600.0)])
	rig.run(310.0)
	assert_false(rig.gov.is_warmup_active())
	_pedal(rig, false)
	# The last pedaling sample came 1 s before the first stopped one.
	var last_pedal := rig.t - 1.0
	rig.run_until(func() -> bool: return rig.t >= last_pedal + 1200.0 - DT - 1e-6, 1300.0)
	assert_false(rig.gov.is_warmup_active(), "not reset before 20 minutes")
	rig.step()
	assert_true(rig.gov.is_warmup_active(), "reset at 20 minutes")
	assert_almost_eq(float(rig.s()["warmup_remaining_s"]), 300.0, 1e-9)
	var ev := rig.events_named("warmup_changed")
	assert_eq(ev[ev.size() - 1]["value"], true)
	var t2 := _pedal(rig, true)
	rig.run(10.0)
	assert_almost_eq(float(rig.s()["warmup_remaining_s"]), 300.0 - (rig.t - t2), 1e-6, "counts again")
	assert_lte(rig.applied_w(), 130, "65% cap again")


func test_skip_warmup() -> void:
	var rig := make_rig({"skip_warmup": true}, follower())
	rig.start([erg(Wl.WORK, 80.0, 900.0)])
	assert_false(rig.gov.is_warmup_active())
	rig.run(20.0)
	assert_eq(rig.applied_w(), 160)
	assert_eq(rig.events_named("warmup_changed").size(), 0)


func test_floor_wins_over_the_warmup_cap_at_low_ftp() -> void:
	# 4.6.12: 50 W is above 65% FTP below an FTP of 77 W.
	for ftp: float in [60.0, 70.0, 76.0]:
		var rig := make_rig(WARM.merged({"ftp_w": ftp}), follower())
		rig.start([erg(Wl.WORK, 100.0, 600.0)])
		rig.run(10.0)
		assert_eq(rig.applied_w(), 50, "floor at FTP %s" % ftp)
		var cb: Array = rig.s()["clamped_by"]
		assert_has(cb, Wl.CLAMP_WARMUP)
		assert_has(cb, Wl.CLAMP_FLOOR)
		assert_true(cb.find(Wl.CLAMP_WARMUP) < cb.find(Wl.CLAMP_FLOOR), "the warm-up cap, then the floor")
	var rig77 := make_rig(WARM.merged({"ftp_w": 77.0}), follower())
	rig77.start([erg(Wl.WORK, 100.0, 600.0)])
	rig77.run(10.0)
	assert_eq(rig77.applied_w(), 50, "65% of 77 W is 50.05 W, 50 W whole")
	assert_does_not_have(rig77.s()["clamped_by"], Wl.CLAMP_FLOOR)


func test_haptics_allowed_once_warmup_ends() -> void:
	var rig := make_rig(WARM.merged({"haptic_intensity": 1.0}), follower())
	rig.start([sim(Wl.GRADE_FLAT, 3600.0)])
	rig.run(310.0)
	assert_false(rig.gov.is_warmup_active())
	var rec := rig.directive({"mode": "SIM", "haptic": 2.0, "duration_s": 5.0})
	assert_false(rec["refused"])
	assert_true(rig.s()["haptic_active"])
