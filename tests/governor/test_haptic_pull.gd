extends "res://tests/governor/gov_test_base.gd"
## BRIEF 4.6.6 haptic pull (v0.3.0): `haptic_pull` % FTP x the rider's haptic intensity, at
## most +50% FTP, on top of the governed ERG target for at most 3 s, then back at once. The
## target with the pull never exceeds min(150% FTP, 1000 W, trainer max) nor a latched
## duration-limit band, and its time above 105% / 120% counts toward the budgets. Exempt from
## slew and from the long-phase 105% cap only. ERG only; off in warm-up, rescue, coasting,
## panic and for opted-out riders; 15 s cooldown per rider from the end of the previous one.

const PULL := SafetyGovernor.CLAMP_PULL


## A rider at 100% FTP (200 W, steady) in a 290 s ERG phase.
func _erg_rig(params: Dictionary = {}, pct: float = 100.0, dur: float = 290.0) -> Rig:
	var p := {"haptic_intensity": 1.0}
	p.merge(params, true)
	var rig := make_rig(p, follower())
	rig.start([erg(Wl.WORK, pct, dur)])
	rig.run(15.0)
	return rig


func _pull(rig: Rig, pct: float, dur: float = 2.0) -> Dictionary:
	return rig.directive({"haptic_pull": pct, "duration_s": dur, "reason": "tug"})


func test_pull_adds_pct_ftp_at_once() -> void:
	var rig := _erg_rig()
	assert_eq(rig.applied_w(), 200)
	var rec := _pull(rig, 20.0)
	assert_false(rec["refused"])
	assert_eq(int(rec["applied"]["haptic_pull_w"]), 40)
	assert_almost_eq(float(rec["applied"]["haptic_pull_pct"]), 20.0, 1e-9)
	assert_eq(int(rec["applied"]["target_with_pull_w"]), 240)
	assert_eq(rec["clamped_by"], [] as Array[String], "nothing bites at full intensity")
	rig.step()
	assert_eq(rig.applied_w(), 240, "+40 W in one tick: exempt from the 30 W/s slew")
	assert_true(rig.s()["haptic_pull_active"])
	assert_eq(int(rig.s()["haptic_pull_w"]), 40)
	assert_has(rig.s()["clamped_by"], PULL, "the trace and telemetry see the pull")
	assert_does_not_have(rig.s()["clamped_by"], Wl.CLAMP_SLEW)
	assert_eq(int(rig.s()["governed_target_w"]), 200, "the governed target stays the plan's")


func test_intensity_scales_the_pull() -> void:
	var rig := _erg_rig({"haptic_intensity": 0.5})
	var rec := _pull(rig, 20.0)
	assert_eq(int(rec["applied"]["haptic_pull_w"]), 20)
	assert_has(rec["clamped_by"], Wl.CLAMP_HAPTIC_INTENSITY)
	rig.step()
	assert_eq(rig.applied_w(), 220)


func test_at_most_plus_50_pct_ftp() -> void:
	var rig := _erg_rig({}, 80.0)
	var rec := _pull(rig, 90.0)
	assert_eq(int(rec["applied"]["haptic_pull_w"]), 100, "50% of 200 W")
	assert_has(rec["clamped_by"], Wl.CLAMP_HAPTIC)
	rig.step()
	assert_eq(rig.applied_w(), 260)
	var rig2 := _erg_rig({"haptic_intensity": 0.7}, 80.0)
	var rec2 := _pull(rig2, 80.0)
	assert_eq(int(rec2["applied"]["haptic_pull_w"]), 100, "56% after intensity, bounded to 50%")


func test_unverified_factor_applies_to_the_pull() -> void:
	var rig := _erg_rig({"ftp_verified": false})
	assert_eq(rig.applied_w(), 170)
	var rec := _pull(rig, 20.0)
	assert_eq(int(rec["applied"]["haptic_pull_w"]), 34, "40 W x 0.85")
	assert_has(rec["clamped_by"], Wl.CLAMP_UNVERIFIED)
	rig.step()
	assert_eq(rig.applied_w(), 204)


func test_absolute_ceiling() -> void:
	var rig := _erg_rig({}, 120.0)
	assert_eq(rig.applied_w(), 240)
	var rec := _pull(rig, 50.0)
	assert_eq(int(rec["applied"]["target_with_pull_w"]), 300, "150% FTP")
	assert_eq(int(rec["applied"]["haptic_pull_w"]), 60)
	assert_has(rec["clamped_by"], Wl.CLAMP_CEILING)
	rig.step()
	assert_eq(rig.applied_w(), 300)
	var rig2 := _erg_rig({"trainer_max_w": 260.0}, 120.0)
	var rec2 := _pull(rig2, 50.0)
	assert_eq(int(rec2["applied"]["target_with_pull_w"]), 260, "the trainer's max")
	rig2.step()
	assert_eq(rig2.applied_w(), 260)
	var rig3 := make_rig({"ftp_w": 900.0, "haptic_intensity": 1.0}, follower())
	rig3.start([erg(Wl.WORK, 100.0, 290.0)])
	rig3.run(40.0)
	var rec3 := _pull(rig3, 50.0)
	assert_eq(int(rec3["applied"]["target_with_pull_w"]), 1000, "1000 W")
	rig3.step()
	assert_eq(rig3.applied_w(), 1000)


func test_latched_105_band_holds_the_pull() -> void:
	var rig := make_rig({"haptic_intensity": 1.0}, follower())
	rig.start([erg(Wl.WORK, 110.0, 290.0), erg(Wl.WORK, 110.0, 290.0)])
	rig.run(290.0)
	rig.gov.start_phase(1)
	rig.run(30.0)
	assert_true(rig.s()["latched_105"])
	assert_eq(rig.applied_w(), 210)
	var rec := _pull(rig, 20.0)
	assert_eq(int(rec["applied"]["target_with_pull_w"]), 210, "clamped to the latched 105% band")
	assert_eq(int(rec["applied"]["haptic_pull_w"]), 0)
	assert_has(rec["clamped_by"], Wl.CLAMP_LIMIT_105)
	rig.step()
	assert_eq(rig.applied_w(), 210)


func test_latched_120_band_holds_the_pull() -> void:
	var rig := _erg_rig({}, 125.0)
	rig.run(70.0)
	assert_true(rig.s()["latched_120"])
	assert_eq(rig.applied_w(), 240)
	var rec := _pull(rig, 30.0)
	assert_eq(int(rec["applied"]["haptic_pull_w"]), 0, "no room above the latched 120% band")
	assert_has(rec["clamped_by"], Wl.CLAMP_LIMIT_120)
	rig.step()
	assert_eq(rig.applied_w(), 240)


func test_at_most_3_s_then_back_at_once() -> void:
	var rig := _erg_rig()
	var t0 := rig.t
	var rec := _pull(rig, 20.0, 10.0)
	assert_almost_eq(float(rec["applied"]["haptic_pull_s"]), 3.0, 1e-9)
	assert_has(rec["clamped_by"], Wl.CLAMP_HAPTIC)
	var ended := rig.run_until(func() -> bool: return rig.applied_w() == 200, 6.0)
	assert_time(ended, t0 + 3.0, "back to the target at 3 s, in one tick")
	assert_false(rig.s()["haptic_pull_active"])
	var rig2 := _erg_rig()
	var rec2 := _pull(rig2, 20.0, 0.0)
	assert_almost_eq(float(rec2["applied"]["haptic_pull_s"]), 3.0, 1e-9, "0 means at most 3 s")
	var rig3 := _erg_rig()
	var t3 := rig3.t
	_pull(rig3, 20.0, 1.0)
	var ended3 := rig3.run_until(func() -> bool: return rig3.applied_w() == 200, 6.0)
	assert_time(ended3, t3 + 1.0, "a shorter duration_s ends sooner")


## Ticks the trainer holds a target above 200 W (only a pull can put it there) while `rig`
## runs `seconds`.
func _trainer_pull_s(rig: Rig, seconds: float) -> float:
	var dev: ScriptedDevice = rig.device
	var held := 0
	for i in roundi(seconds / DT):
		rig.step()
		if dev.mode == Wl.ERG and dev.target_w > 200:
			held += 1
	return held * DT


func test_trainer_holds_the_pull_at_most_3_s() -> void:
	for start_delay: float in [0.0, 0.1, 0.25, 0.45]:
		var rig := _erg_rig()
		rig.run(start_delay)
		_pull(rig, 20.0, 3.0)
		var held := _trainer_pull_s(rig, 6.0)
		assert_gt(held, 2.4, "steady target: the pull reached the trainer")
		assert_lte(held, 3.0 + 1e-6, "steady target: the trainer holds it at most 3 s")
		assert_lte((rig.device as ScriptedDevice).max_writes_in_window(1.0), 2)
	for start_delay: float in [0.0, 0.1, 0.25, 0.45]:
		# A target still slewing up writes every 0.5 s; the drop-back still comes by 3 s.
		var rig := make_rig({"haptic_intensity": 1.0}, follower())
		rig.start([erg(Wl.WORK, 50.0, 60.0), erg(Wl.WORK, 100.0, 60.0)])
		rig.run(20.0)
		rig.gov.start_phase(1)
		rig.run(0.2 + start_delay)
		_pull(rig, 50.0, 3.0)
		var held := _trainer_pull_s(rig, 6.0)
		assert_gt(held, 2.4, "slewing target: the pull reached the trainer")
		assert_lte(held, 3.0 + 1e-6, "slewing target: the trainer holds it at most 3 s")
		assert_lte((rig.device as ScriptedDevice).max_writes_in_window(1.0), 2)


func test_cooldown_15_s_from_the_end() -> void:
	var rig := _erg_rig()
	assert_false(_pull(rig, 20.0, 2.0)["refused"])
	var during := _pull(rig, 20.0, 2.0)
	assert_true(during["refused"])
	assert_eq(during["reason"], Wl.REFUSE_HAPTIC_COOLDOWN)
	rig.run_until(func() -> bool: return not bool(rig.s()["haptic_pull_active"]), 5.0)
	rig.run(14.9)
	var early := _pull(rig, 20.0)
	assert_true(early["refused"], "14.9 s after the end")
	assert_eq(early["reason"], Wl.REFUSE_HAPTIC_COOLDOWN)
	rig.run(0.1)
	assert_false(_pull(rig, 20.0)["refused"], "15 s after the end")


func test_cooldown_is_per_rider() -> void:
	var a := _erg_rig()
	var b := _erg_rig()
	assert_false(_pull(a, 20.0)["refused"])
	assert_false(_pull(b, 20.0)["refused"], "another receiver has its own cooldown")


func test_erg_only() -> void:
	var rig := make_rig({"haptic_intensity": 1.0}, follower())
	rig.start([sim(Wl.GRADE_GAME, 600.0)])
	rig.run(5.0)
	var rec := _pull(rig, 20.0)
	assert_true(rec["refused"])
	assert_eq(rec["reason"], SafetyGovernor.REFUSE_PULL_SIM)
	var mixed := rig.directive({"mode_grade": 2.0, "haptic_pull": 20.0, "duration_s": 2.0})
	assert_false(mixed["refused"], "the other channels still apply")
	assert_eq(
		mixed["dropped"], [{"channel": "haptic_pull", "reason": SafetyGovernor.REFUSE_PULL_SIM}]
	)
	assert_eq(rig.s()["mode"], Wl.SIM, "never a mode switch")


func test_switch_to_sim_ends_the_pull() -> void:
	var rig := make_rig({"haptic_intensity": 1.0}, follower())
	rig.start([erg(Wl.WORK, 100.0, 60.0), sim(Wl.GRADE_FLAT, 60.0)])
	rig.run(40.0)
	_pull(rig, 20.0, 3.0)
	rig.step()
	assert_eq(rig.applied_w(), 240)
	rig.gov.start_phase(1)
	rig.step()
	assert_false(rig.s()["haptic_pull_active"])


func test_off_in_warmup() -> void:
	var rig := _erg_rig({"skip_warmup": false}, 60.0)
	assert_true(rig.s()["warmup_active"])
	var rec := _pull(rig, 20.0)
	assert_true(rec["refused"])
	assert_eq(rec["reason"], Wl.REFUSE_HAPTIC_WARMUP)


func test_off_for_opted_out_riders() -> void:
	var rig := _erg_rig({"haptics_on": false})
	var rec := _pull(rig, 20.0)
	assert_true(rec["refused"])
	assert_eq(rec["reason"], Wl.REFUSE_HAPTIC_OFF)
	var rig2 := _erg_rig()
	_pull(rig2, 20.0, 3.0)
	rig2.step()
	assert_eq(rig2.applied_w(), 240)
	rig2.gov.configure({"haptics_on": false})
	rig2.step()
	assert_eq(rig2.applied_w(), 200, "opting out ends a running pull at once")


func test_off_in_rescue() -> void:
	var rig := _erg_rig()
	var dev: ScriptedDevice = rig.device
	dev.cadence_rpm = 40.0
	rig.run(1.5)
	var rec := _pull(rig, 20.0, 3.0)
	assert_false(rec["refused"])
	var t0 := rig.t
	var rescued := rig.run_until(func() -> bool: return bool(rig.s()["rescue"]), 4.0)
	assert_gt(rescued, 0.0)
	assert_lt(rescued, t0 + 3.0, "rescue starts while the pull runs")
	assert_false(rig.s()["haptic_pull_active"], "rescue ends the pull")
	assert_eq(rig.applied_w(), 100, "rescue's 50% FTP, no pull")
	var during := _pull(rig, 20.0)
	assert_true(during["refused"])
	assert_eq(during["reason"], SafetyGovernor.REFUSE_PULL_UNSAFE)
	dev.cadence_rpm = 90.0
	rig.run(4.5)
	assert_true(rig.s()["rescue_ramp"])
	var ramp := _pull(rig, 20.0)
	assert_true(ramp["refused"], "the ramp-back is still rescue")
	assert_eq(ramp["reason"], SafetyGovernor.REFUSE_PULL_UNSAFE)
	rig.run(12.0)
	assert_false(rig.s()["rescue_ramp"])
	assert_false(_pull(rig, 20.0)["refused"], "after the ramp-back")


func test_off_while_coasting() -> void:
	var rig := _erg_rig()
	var dev: ScriptedDevice = rig.device
	dev.erg_follow = -1.0
	dev.power_w = 0.0
	dev.cadence_rpm = 0.0
	rig.run(5.0)
	assert_true(rig.s()["coasting"])
	var rec := _pull(rig, 20.0)
	assert_true(rec["refused"])
	assert_eq(rec["reason"], SafetyGovernor.REFUSE_PULL_UNSAFE)


func test_off_in_panic_and_pause() -> void:
	var rig := _erg_rig()
	_pull(rig, 20.0, 3.0)
	rig.step()
	assert_eq(rig.applied_w(), 240)
	rig.gov.emergency_safe()
	assert_false(rig.s()["haptic_pull_active"])
	var rec := _pull(rig, 20.0)
	assert_true(rec["refused"])
	assert_eq(rec["reason"], SafetyGovernor.REFUSE_PULL_UNSAFE)
	var rig2 := _erg_rig()
	_pull(rig2, 20.0, 3.0)
	rig2.step()
	rig2.gov.set_game_paused(true)
	rig2.step()
	assert_false(rig2.s()["haptic_pull_active"], "pause ends the pull")
	assert_eq(_pull(rig2, 20.0)["reason"], SafetyGovernor.REFUSE_PULL_UNSAFE)


func test_slew_exemption_rides_on_the_slewed_target() -> void:
	var rig := make_rig({"haptic_intensity": 1.0}, follower())
	rig.start([erg(Wl.WORK, 50.0, 60.0), erg(Wl.WORK, 100.0, 60.0)])
	rig.run(20.0)
	rig.gov.start_phase(1)
	rig.run(1.0)
	var base := rig.applied_w()
	assert_lt(base, 200, "still slewing up")
	_pull(rig, 20.0, 2.0)
	rig.step()
	var gain := rig.applied_w() - base - 40
	assert_between(gain, 1, 2, "the base keeps slewing (1.5 W per tick), the pull is instant")
	assert_has(rig.s()["clamped_by"], Wl.CLAMP_SLEW, "the base is still slew-limited")
	assert_has(rig.s()["clamped_by"], PULL)


func test_long_phase_cap_exemption() -> void:
	var rig := _erg_rig({}, 105.0, 600.0)
	assert_eq(rig.applied_w(), 210)
	var rec := _pull(rig, 20.0)
	assert_eq(int(rec["applied"]["target_with_pull_w"]), 250, "above 105% in a 600 s phase")
	assert_does_not_have(rec["clamped_by"], Wl.CLAMP_LONG_PHASE)
	rig.step()
	assert_eq(rig.applied_w(), 250)
	assert_does_not_have(rig.s()["clamped_by"], Wl.CLAMP_LONG_PHASE)


func test_time_above_counts_toward_the_budgets() -> void:
	var rig := _erg_rig()
	assert_almost_eq(float(rig.s()["s_left_105"]), 300.0, 1e-9)
	assert_almost_eq(float(rig.s()["s_left_120"]), 60.0, 1e-9)
	_pull(rig, 25.0, 3.0)
	rig.run(5.0)
	assert_almost_eq(float(rig.s()["s_left_105"]), 297.0, 0.06, "about 3 s above 105%")
	assert_almost_eq(float(rig.s()["s_left_120"]), 57.0, 0.06, "about 3 s above 120%")


func test_bad_pull_is_refused() -> void:
	var rig := _erg_rig()
	var rec := _pull(rig, -10.0)
	assert_true(rec["refused"])
	assert_eq(rec["reason"], Wl.REFUSE_BAD_FIELDS)
	assert_true(_pull(rig, 0.0)["refused"])
