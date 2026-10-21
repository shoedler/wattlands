extends "res://tests/governor/gov_test_base.gd"
## BRIEF 4.6.3 rescue: in ERG with a governed target >= 60% FTP, cadence < 45 rpm for 3 s or
## power < 75% of the applied target for 5 s drops to 50% FTP, holds until cadence >= 70 for
## 3 s, then ramps back over 10 s. 4.6.12 overlaps: the floor wins over rescue's 50% at FTP
## 60-100 W; the coasting floor wins over rescue. OWNERSHIP DS14 and IF9.


## Set the rider's cadence and return the time of the first sample that carries it.
func _cadence(rig: Rig, rpm: float) -> float:
	var dev: ScriptedDevice = rig.device
	dev.cadence_rpm = rpm
	var before := dev.samples_sent
	while dev.samples_sent == before:
		rig.step()
	return dev.sample_times[dev.sample_times.size() - 1]


func test_cadence_below_45_for_3_s_triggers() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 80.0, 120.0)])
	rig.run(20.0)
	assert_eq(rig.applied_w(), 160)
	var t_s := _cadence(rig, 40.0)
	rig.run_until(func() -> bool: return rig.t >= t_s + 2.95 - 1e-6, 5.0)
	assert_false(rig.s()["rescue"], "not before 3 s")
	rig.step()
	assert_true(rig.s()["rescue"], "at 3 s")
	assert_true(rig.gov.is_rescue())
	assert_eq(rig.applied_w(), 100, "50% FTP")
	assert_has(rig.s()["clamped_by"], Wl.CLAMP_RESCUE)
	var ev := rig.events_named("rescue_changed")
	assert_eq(ev.size(), 1)
	assert_time(float(ev[0]["t"]), t_s + 3.0)


func test_power_below_75_pct_for_5_s_triggers() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 80.0, 120.0)])
	rig.run(20.0)
	var dev: ScriptedDevice = rig.device
	dev.erg_follow = 0.7
	var before := dev.samples_sent
	while dev.samples_sent == before:
		rig.step()
	var t_s := dev.sample_times[dev.sample_times.size() - 1]
	var at := rig.run_until(func() -> bool: return bool(rig.s()["rescue"]), 8.0)
	assert_time(at, t_s + 5.0, "112 W < 75% of 160 W for 5 s")
	assert_eq(rig.applied_w(), 100)


func test_power_at_75_pct_does_not_trigger() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 80.0, 120.0)])
	rig.run(20.0)
	var dev: ScriptedDevice = rig.device
	dev.erg_follow = 0.75
	rig.run(20.0)
	assert_false(rig.s()["rescue"], "120 W is not < 75% of 160 W")


func test_not_armed_below_60_pct() -> void:
	var rig := make_rig({}, follower(40.0))
	rig.start([erg(Wl.RECOVERY, 59.5, 120.0)])
	rig.run(30.0)
	assert_false(rig.s()["rescue"], "119 W < 60% of 200 W")
	assert_eq(rig.events_named("rescue_changed").size(), 0)


func test_armed_exactly_at_60_pct() -> void:
	var rig := make_rig({}, follower(40.0))
	rig.start([erg(Wl.WORK, 60.0, 120.0)])
	var at := rig.run_until(func() -> bool: return bool(rig.s()["rescue"]), 10.0)
	assert_time(at, 1.0 + 3.0, "first low sample at 1 s, rescue 3 s later")


func test_armed_in_whole_watts_at_an_odd_ftp() -> void:
	# FTP 201: 60% FTP is 120.6 W. A 60% target governs to 120 W, which is 60% in whole watts
	# (4.6.1 compares whole-watt values), so rescue arms; a 59.5% target (119 W) does not.
	var rig := make_rig({"ftp_w": 201.0}, follower(40.0))
	rig.start([erg(Wl.WORK, 60.0, 120.0)])
	var at := rig.run_until(func() -> bool: return bool(rig.s()["rescue"]), 10.0)
	assert_time(at, 1.0 + 3.0, "a target exactly at 60% arms rescue")
	var rig2 := make_rig({"ftp_w": 201.0}, follower(40.0))
	rig2.start([erg(Wl.WORK, 59.5, 120.0)])
	rig2.run(20.0)
	assert_eq(int(rig2.s()["governed_target_w"]), 119)
	assert_false(rig2.s()["rescue"], "119 W is below 60% of 201 W in whole watts")


func test_hold_until_cadence_70_for_3_s_then_ramp_back_over_10_s() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 80.0, 120.0)])
	rig.run(20.0)
	_cadence(rig, 40.0)
	rig.run(5.0)
	assert_true(rig.s()["rescue"])
	_cadence(rig, 65.0)
	rig.run(10.0)
	assert_true(rig.s()["rescue"], "65 rpm does not end the hold")
	assert_eq(rig.applied_w(), 100)
	var t_h := _cadence(rig, 75.0)
	rig.run_until(func() -> bool: return rig.t >= t_h + 2.95 - 1e-6, 5.0)
	assert_true(rig.s()["rescue"], "not before 3 s at >= 70 rpm")
	rig.step()
	assert_false(rig.s()["rescue"], "hold ends at 3 s")
	assert_true(rig.s()["rescue_ramp"])
	var ev := rig.events_named("rescue_changed")
	assert_eq(ev.size(), 2)
	assert_eq(ev[1]["value"], false)
	var ramp_t := rig.t
	rig.run(5.0)
	assert_almost_eq(rig.applied_w(), 130, 1, "halfway up the 10 s ramp")
	assert_has(rig.s()["clamped_by"], Wl.CLAMP_RESCUE)
	rig.run_until(func() -> bool: return rig.t >= ramp_t + 10.0 - 1e-6, 6.0)
	rig.step()
	assert_eq(rig.applied_w(), 160, "back at the plan after 10 s")
	assert_false(rig.s()["rescue_ramp"])
	assert_does_not_have(rig.s()["clamped_by"], Wl.CLAMP_RESCUE)


func test_floor_wins_over_rescue_at_low_ftp() -> void:
	# FTP 60, 80 and 99: 50% FTP is below 50 W, so the floor holds 50 W (4.6.12).
	for ftp: float in [60.0, 80.0, 99.0]:
		var rig := make_rig({"ftp_w": ftp}, follower())
		rig.start([erg(Wl.WORK, 80.0, 120.0)])
		rig.run(20.0)
		_cadence(rig, 30.0)
		rig.run(4.0)
		assert_true(rig.s()["rescue"], "rescue at FTP %s" % ftp)
		assert_eq(rig.applied_w(), 50, "floor 50 W at FTP %s" % ftp)
		var cb: Array = rig.s()["clamped_by"]
		assert_has(cb, Wl.CLAMP_FLOOR, "floor named at FTP %s" % ftp)
		assert_true(cb.find(Wl.CLAMP_RESCUE) < cb.find(Wl.CLAMP_FLOOR), "rescue, then the floor")
	var rig100 := make_rig({"ftp_w": 100.0}, follower())
	rig100.start([erg(Wl.WORK, 80.0, 120.0)])
	rig100.run(20.0)
	_cadence(rig100, 30.0)
	rig100.run(4.0)
	assert_eq(rig100.applied_w(), 50, "50% of 100 W is exactly the floor")
	assert_does_not_have(rig100.s()["clamped_by"], Wl.CLAMP_FLOOR)


func test_coasting_floor_wins_over_rescue() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 80.0, 120.0)])
	rig.run(20.0)
	_cadence(rig, 40.0)
	rig.run(4.0)
	assert_true(rig.s()["rescue"])
	assert_eq(rig.applied_w(), 100)
	var dev: ScriptedDevice = rig.device
	dev.erg_follow = -1.0
	dev.power_w = 0.0
	dev.cadence_rpm = 0.0
	rig.run(5.0)
	assert_true(rig.s()["coasting"])
	assert_true(rig.s()["rescue"], "still in rescue")
	assert_eq(rig.applied_w(), 60, "the coasting floor wins over rescue's 100 W")
	var cb: Array = rig.s()["clamped_by"]
	assert_has(cb, Wl.CLAMP_COASTING)
	assert_true(cb.find(Wl.CLAMP_RESCUE) < cb.find(Wl.CLAMP_COASTING))


func test_expired_directive_lands_on_the_plan_after_the_ramp() -> void:
	# DS14: channels keep counting game time under rescue; the ramp-back heads for the
	# channel's current value, so a run that expired during rescue lands on the base pull.
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 80.0, 120.0).with_range(80.0, 120.0)])
	rig.run(20.0)
	var rec := rig.directive(
		{"mode": "ERG", "target_pct": 110.0, "duration_s": 10.0, "reason": "run"}
	)
	assert_false(rec["refused"])
	rig.run(3.0)
	_cadence(rig, 40.0)
	rig.run(4.0)
	assert_true(rig.s()["rescue"])
	rig.run(5.0)
	assert_eq(int(rig.s()["governed_target_w"]), 100, "still rescue after the run expired")
	var t_h := _cadence(rig, 90.0)
	rig.run_until(func() -> bool: return rig.t >= t_h + 3.0 + 10.0 + DT, 20.0)
	assert_eq(rig.applied_w(), 160, "the base pull, not the expired run's 220 W")


func test_sim_phase_ends_the_rescue() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 80.0, 60.0), sim(Wl.GRADE_FLAT, 60.0)])
	rig.run(20.0)
	_cadence(rig, 40.0)
	rig.run(4.0)
	assert_true(rig.s()["rescue"])
	rig.gov.start_phase(1)
	assert_false(rig.gov.is_rescue())
	var ev := rig.events_named("rescue_changed")
	assert_eq(ev[ev.size() - 1]["value"], false)


func test_no_rescue_in_sim() -> void:
	var rig := make_rig({}, follower(30.0))
	rig.start([sim(Wl.GRADE_FLAT, 60.0)])
	rig.run(30.0)
	assert_false(rig.s()["rescue"])


func test_warmup_ramp_triggers_once_it_passes_60_pct() -> void:
	# BRIEF 7.4: rescue triggers on cadence collapse in the warm-up ramp once it passes 60%,
	# never below 60%.
	var rig := make_rig({"skip_warmup": false}, follower(40.0))
	rig.start([erg(Wl.WARMUP, 50.0, 300.0).with_ramp(65.0)])
	var at := rig.run_until(func() -> bool: return bool(rig.s()["rescue"]), 260.0)
	assert_gt(at, 0.0)
	assert_gte(at, 203.0 - 1e-6, "the ramp reaches 60% at 200 s; 3 s of low cadence after that")
	assert_lte(at, 203.1, "and no later")


func test_rescue_not_armed_while_paused() -> void:
	var rig := make_rig({}, follower(40.0))
	rig.start([erg(Wl.WORK, 80.0, 120.0)])
	rig.gov.set_game_paused(true)
	rig.run(10.0)
	assert_false(rig.s()["rescue"])
	rig.gov.set_game_paused(false)
	var t0 := rig.t
	var at := rig.run_until(func() -> bool: return bool(rig.s()["rescue"]), 5.0)
	assert_time(at, t0 + 3.0 + DT, "3 s of low cadence while armed, counted from the unpause")


func test_low_power_from_an_unarmed_phase_does_not_fire_at_once() -> void:
	var dev := ScriptedDevice.new()
	dev.erg_follow = 0.7
	var rig := make_rig({}, dev)
	rig.start([erg(Wl.RECOVERY, 50.0, 60.0), erg(Wl.WORK, 100.0, 60.0)])
	rig.run(30.0)
	assert_false(rig.s()["rescue"], "50% is not armed")
	rig.gov.start_phase(1)
	var t0 := rig.t
	var at := rig.run_until(func() -> bool: return bool(rig.s()["rescue"]), 10.0)
	assert_gt(at, 0.0, "a rider at 70% of the target is rescued")
	assert_gte(at - t0, 5.0 - 1e-6, "but only after 5 s of the armed phase")
	assert_lte(at - t0, 6.1)
