extends "res://tests/governor/gov_test_base.gd"
## BRIEF 4.6.6 haptics and OWNERSHIP DS8/GOV11: haptic grade x intensity adds at most +3%
## for at most 8 s, with a 15 s cooldown per receiver from the end of its previous applied
## haptic; haptic wind is bounded to the force of +3% grade at the current speed; haptics are
## dropped (and logged) for ERG riders (never a mode switch), opted-out riders and during
## warm-up. A haptic is its own channel: a 1.5 s haptic over a held mode_grade leaves the
## grade in place (BRIEF 7.1).


func _sim_rig(params: Dictionary = {}) -> Rig:
	var rig := make_rig(params, follower())
	rig.start([sim(Wl.GRADE_GAME, 600.0)])
	rig.run(2.0)
	return rig


func test_intensity_scales_the_haptic() -> void:
	var rig := _sim_rig({"haptic_intensity": 0.7})
	var rec := rig.directive({"mode": "SIM", "haptic": 2.0, "duration_s": 1.5, "reason": "hit", "source": "tank"})
	assert_false(rec["refused"])
	assert_almost_eq(float(rec["applied"]["haptic_pct"]), 1.4, 1e-9)
	assert_has(rec["clamped_by"], Wl.CLAMP_HAPTIC_INTENSITY)
	assert_does_not_have(rec["clamped_by"], Wl.CLAMP_HAPTIC, "intensity is not the +3% bound")
	rig.step()
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 1.4, 1e-9)
	assert_true(rig.s()["haptic_active"])


func test_plus_3_pct_bound() -> void:
	var rig := _sim_rig({"haptic_intensity": 1.0})
	var rec := rig.directive({"mode": "SIM", "haptic": 5.0, "duration_s": 2.0})
	assert_almost_eq(float(rec["applied"]["haptic_pct"]), 3.0, 1e-9)
	assert_has(rec["clamped_by"], Wl.CLAMP_HAPTIC)
	assert_does_not_have(rec["clamped_by"], Wl.CLAMP_HAPTIC_INTENSITY, "full intensity changes nothing")
	var rig2 := _sim_rig({"haptic_intensity": 0.7})
	var rec2 := rig2.directive({"mode": "SIM", "haptic": 5.0, "duration_s": 2.0})
	assert_almost_eq(float(rec2["applied"]["haptic_pct"]), 3.0, 1e-9, "3.5% after intensity, bounded")
	assert_eq(rec2["clamped_by"], [Wl.CLAMP_HAPTIC_INTENSITY, Wl.CLAMP_HAPTIC])


func test_8_s_bound() -> void:
	var rig := _sim_rig({"haptic_intensity": 1.0})
	var t0 := rig.t
	var rec := rig.directive({"mode": "SIM", "haptic": 2.0, "duration_s": 20.0})
	assert_almost_eq(float(rec["applied"]["haptic_s"]), 8.0, 1e-9)
	assert_has(rec["clamped_by"], Wl.CLAMP_HAPTIC)
	var ended := rig.run_until(func() -> bool: return not bool(rig.s()["haptic_active"]), 12.0)
	assert_time(ended, t0 + 8.0, "ends at 8 s")
	var rig2 := _sim_rig({"haptic_intensity": 1.0})
	var rec2 := rig2.directive({"mode": "SIM", "haptic": 2.0, "duration_s": 0.0})
	assert_almost_eq(float(rec2["applied"]["haptic_s"]), 8.0, 1e-9, "duration 0 still lasts at most 8 s")


func test_8_s_bound_holds_in_platform_time_while_paused() -> void:
	var rig := _sim_rig({"haptic_intensity": 1.0})
	rig.directive({"mode": "SIM", "haptic": 2.0, "duration_s": 6.0})
	rig.run(2.0)
	rig.gov.set_game_paused(true)
	rig.run(10.0)
	rig.gov.set_game_paused(false)
	rig.step()
	assert_false(rig.s()["haptic_active"], "never more than 8 s of real time")


func test_cooldown_from_the_end_of_the_previous_haptic() -> void:
	var rig := _sim_rig({"haptic_intensity": 1.0})
	assert_false(rig.directive({"mode": "SIM", "haptic": 2.0, "duration_s": 2.0})["refused"])
	var during := rig.directive({"mode": "SIM", "haptic": 2.0, "duration_s": 2.0})
	assert_true(during["refused"])
	assert_eq(during["reason"], Wl.REFUSE_HAPTIC_COOLDOWN, "no haptic while one is active")
	rig.run(2.0)
	assert_false(rig.s()["haptic_active"])
	var end_t := rig.t
	rig.run_until(func() -> bool: return rig.t >= end_t + 14.95 - 1e-6, 20.0)
	var early := rig.directive({"mode": "SIM", "haptic": 2.0, "duration_s": 2.0})
	assert_true(early["refused"])
	assert_eq(early["reason"], Wl.REFUSE_HAPTIC_COOLDOWN, "14.95 s after the end")
	rig.step()
	var ok := rig.directive({"mode": "SIM", "haptic": 2.0, "duration_s": 2.0})
	assert_false(ok["refused"], "15 s after the end")


func test_dropped_for_an_erg_rider_never_a_mode_switch() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 80.0, 600.0)])
	rig.run(40.0)
	var dev: ScriptedDevice = rig.device
	var n := dev.writes.size()
	var rec := rig.directive({"mode": "SIM", "haptic": 2.0, "duration_s": 1.5, "reason": "hit", "source": "tank"})
	assert_true(rec["refused"])
	assert_eq(rec["reason"], Wl.REFUSE_HAPTIC_ERG)
	rig.run(5.0)
	assert_eq(rig.s()["mode"], Wl.ERG)
	assert_false(rig.s()["sim_block_active"])
	assert_eq(dev.writes_of("sim").size(), 0, "never a mode switch")
	assert_eq(dev.writes.size(), n)
	var rec2 := rig.directive({"mode": "SIM", "duration_s": 20.0, "haptic": 2.0})
	assert_true(rec2["refused"], "not even with a valid block length")
	assert_eq(rec2["reason"], Wl.REFUSE_HAPTIC_ERG)


func test_opting_out_ends_a_running_haptic() -> void:
	var rig := _sim_rig({"haptic_intensity": 1.0})
	assert_false(rig.directive({"mode": "SIM", "haptic": 3.0, "duration_s": 5.0})["refused"])
	rig.run(1.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 3.0, 1e-9)
	rig.gov.configure({"haptics_on": false})
	rig.step()
	assert_false(rig.s()["haptic_active"])
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 0.0, 1e-9, "the haptic is gone at once")


func test_haptic_for_an_erg_rider_with_other_channels_is_refused_whole() -> void:
	# Never a mode switch: even a valid ERG target in the same request is refused, so a
	# game's haptic can never open a SIM block or move an ERG rider's target by accident.
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 70.0, 600.0).with_range(60.0, 90.0)])
	rig.run(10.0)
	var rec := rig.directive({"target_pct": 80.0, "haptic": 2.0, "duration_s": 3.0})
	assert_true(rec["refused"])
	assert_eq(rec["reason"], Wl.REFUSE_HAPTIC_ERG)
	rig.run(2.0)
	assert_eq(int(rig.s()["governed_target_w"]), 140, "the plan's 70% stands")


func test_dropped_for_an_opted_out_rider() -> void:
	var rig := _sim_rig({"haptics_on": false})
	var rec := rig.directive({"mode": "SIM", "haptic": 3.0, "duration_s": 5.0, "reason": "last_run", "source": "fishing"})
	assert_true(rec["refused"])
	assert_eq(rec["reason"], Wl.REFUSE_HAPTIC_OFF)
	rig.step()
	assert_false(rig.s()["haptic_active"])


func test_dropped_haptic_keeps_the_rest_of_the_request() -> void:
	var rig := _sim_rig({"haptics_on": false})
	var rec := rig.directive({"mode": "SIM", "mode_grade": 4.0, "haptic": 2.0, "duration_s": 0.0})
	assert_false(rec["refused"])
	assert_eq(rec["dropped"], [{"channel": "haptic", "reason": Wl.REFUSE_HAPTIC_OFF}])
	rig.step()
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 2.0, 1e-9, "the mode grade applies")


func test_haptic_over_a_held_mode_grade_leaves_the_grade() -> void:
	var rig := _sim_rig({"haptic_intensity": 0.7})
	assert_false(rig.directive({"mode": "SIM", "mode_grade": 4.0, "duration_s": 0.0, "reason": "boiler"})["refused"])
	rig.run(1.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 2.0, 1e-9)
	var t0 := rig.t
	assert_false(rig.directive({"mode": "SIM", "haptic": 2.0, "duration_s": 1.5, "reason": "hit"})["refused"])
	rig.step()
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 3.4, 1e-9, "2% + 1.4% haptic")
	rig.run_until(func() -> bool: return rig.t >= t0 + 1.5 - 1e-6, 3.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 2.0, 1e-9, "only the haptic expired")
	assert_almost_eq(float(rig.s()["mode_grade_pct"]), 4.0, 1e-9)


func test_wind_bounded_to_plus_3_pct_force() -> void:
	var rig := _sim_rig({"haptic_intensity": 1.0})
	var rec := rig.directive({"mode": "SIM", "haptic_wind": 10.0, "duration_s": 3.0})
	assert_false(rec["refused"])
	var v := 30.0 / 3.6
	var cw := 0.51
	var f_budget := 83.0 * 9.80665 * sin(atan(0.03))
	var w_max := -v + sqrt(v * v + f_budget / cw)
	assert_almost_eq(float(rec["applied"]["haptic_wind_mps"]), w_max, 1e-6)
	assert_has(rec["clamped_by"], Wl.CLAMP_HAPTIC)
	var added := cw * ((v + w_max) * (v + w_max) - v * v)
	assert_almost_eq(added, f_budget, 1e-6, "added force equals +3% grade's")


func test_grade_and_wind_share_one_budget() -> void:
	var rig := _sim_rig({"haptic_intensity": 1.0})
	var rec := rig.directive({"mode": "SIM", "haptic": 3.0, "haptic_wind": 5.0, "duration_s": 3.0})
	assert_almost_eq(float(rec["applied"]["haptic_pct"]), 3.0, 1e-9)
	assert_almost_eq(float(rec["applied"]["haptic_wind_mps"]), 0.0, 1e-9, "+3% grade used the whole budget")


func test_small_wind_passes_unbounded() -> void:
	var rig := _sim_rig({"haptic_intensity": 1.0})
	var rec := rig.directive({"mode": "SIM", "haptic_wind": 0.5, "duration_s": 3.0})
	assert_almost_eq(float(rec["applied"]["haptic_wind_mps"]), 0.5, 1e-9)
	assert_does_not_have(rec["clamped_by"], Wl.CLAMP_HAPTIC)
	rig.run(1.0)
	var dev: ScriptedDevice = rig.device
	assert_almost_eq(dev.wind_mps, 0.5, 1e-9, "sent as SIM wind")


func test_haptic_during_a_sim_block() -> void:
	var rig := make_rig({"haptic_intensity": 1.0}, follower())
	rig.start([erg(Wl.WORK, 65.0, 600.0)])
	rig.run(40.0)
	assert_false(rig.directive({"mode": "SIM", "duration_s": 30.0})["refused"])
	var rec := rig.directive({"mode": "SIM", "haptic": 2.0, "duration_s": 2.0})
	assert_false(rec["refused"], "a rider in a SIM block rides SIM")
	assert_eq(rec["applied"]["mode"], "SIM", "mode SIM confirms the running block")


func test_stacks_with_the_base_grade_within_16() -> void:
	var rig := _sim_rig({"haptic_intensity": 1.0, "grade_max_pct": 16.0, "difficulty_pct": 100.0})
	rig.directive({"mode": "SIM", "mode_grade": 15.0, "duration_s": 0.0})
	var rec := rig.directive({"mode": "SIM", "haptic": 3.0, "duration_s": 2.0})
	assert_almost_eq(float(rec["applied"]["grade_pct"]), 16.0, 1e-9)
	assert_has(rec["clamped_by"], Wl.CLAMP_GRADE_LIMIT)
