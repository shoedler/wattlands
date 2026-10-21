extends "res://tests/governor/gov_test_base.gd"
## BRIEF 3.6 directive channels inside the governor and OWNERSHIP DS3-DS7, PL5, PL6: a
## request changes only the channels it sets; a later request on a channel replaces it and
## cancels its pending expiry; duration_s applies to the request's own channels; on expiry
## only those revert to the plan; 0 means until the phase ends; every channel resets at a
## phase change; ramps follow game time; range_pct, SIM block, mode_grade and phase-mode
## refusals; target_w and target_wkg converted to % FTP; the cool-down ignores directives.


func _erg_rig(phase: PlanPhase, params: Dictionary = {}) -> Rig:
	var rig := make_rig(params, follower())
	rig.start([phase, erg(Wl.WORK, 60.0, 600.0), sim(Wl.GRADE_GAME, 600.0)])
	rig.run(10.0)
	return rig


func test_erg_target_expires_back_to_the_plan() -> void:
	var rig := _erg_rig(erg(Wl.WORK, 60.0, 600.0).with_range(50.0, 100.0))
	var t0 := rig.t
	var rec := rig.directive({"mode": "ERG", "target_pct": 80.0, "duration_s": 10.0, "reason": "bank"})
	assert_false(rec["refused"])
	assert_eq(int(rec["applied"]["target_w"]), 160)
	rig.run_until(func() -> bool: return rig.t >= t0 + 9.95 - 1e-6, 12.0)
	assert_eq(int(rig.s()["governed_target_w"]), 160, "held for 10 s")
	rig.step()
	assert_eq(int(rig.s()["governed_target_w"]), 120, "back to the planned 60%")
	assert_eq(rig.applied_w(), 120, "decreases at once")


func test_later_request_replaces_and_cancels_the_expiry() -> void:
	var rig := _erg_rig(erg(Wl.WORK, 60.0, 600.0).with_range(50.0, 100.0))
	rig.directive({"target_pct": 80.0, "duration_s": 10.0})
	rig.run(5.0)
	rig.directive({"target_pct": 90.0, "duration_s": 0.0})
	rig.run(20.0)
	assert_eq(int(rig.s()["governed_target_w"]), 180, "duration 0 holds until the phase ends")
	rig.gov.start_phase(1)
	assert_eq(int(rig.s()["governed_target_w"]), 120, "every channel resets at a phase change")


func test_fishing_run_steps_share_one_expiry() -> void:
	# F2.3: a run's ramp steps 0.5 s apart each carry duration_s = seconds left to the run's
	# end, so the target reverts to the base pull at once at that end.
	var rig := _erg_rig(erg(Wl.WORK, 70.0, 600.0).with_range(60.0, 110.0))
	var run_end := rig.t + 20.0
	for i in 6:
		var left := run_end - rig.t
		var rec := rig.directive({"mode": "ERG", "target_pct": 75.0 + 6.0 * i, "duration_s": left, "reason": "run", "source": "fishing"})
		assert_false(rec["refused"])
		rig.run(0.5)
	assert_eq(int(rig.s()["governed_target_w"]), 210)
	rig.run_until(func() -> bool: return rig.t >= run_end - DT - 1e-6, 20.0)
	assert_eq(int(rig.s()["governed_target_w"]), 210)
	rig.step()
	assert_eq(int(rig.s()["governed_target_w"]), 140, "the base pull at the run's end")
	assert_eq(rig.applied_w(), 140)


func test_erg_target_reverts_onto_the_ramp() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WARMUP, 50.0, 100.0).with_ramp(70.0).with_range(50.0, 90.0)])
	rig.run(10.0)
	rig.directive({"target_pct": 85.0, "duration_s": 20.0})
	rig.run(20.0)
	assert_eq(int(rig.s()["governed_target_w"]), GovernorClamps.whole_w(2.0 * (50.0 + 20.0 * 30.0 / 100.0)),
		"planned 56% at 30 s")


func test_ramp_follows_game_time() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WARMUP, 50.0, 100.0).with_ramp(70.0)])
	rig.run(25.0)
	assert_eq(int(rig.s()["governed_target_w"]), 110, "55% at 25 s")
	rig.gov.set_game_paused(true)
	rig.run(30.0)
	rig.gov.set_game_paused(false)
	rig.step()
	assert_almost_eq(float(rig.s()["planned_pct"]), 55.01, 0.011, "the ramp did not move while paused")


func test_range_pct_refusals() -> void:
	var rig := _erg_rig(erg(Wl.WORK, 60.0, 600.0).with_range(55.0, 100.0))
	assert_false(rig.directive({"target_pct": 55.0})["refused"], "lower bound inclusive")
	assert_false(rig.directive({"target_pct": 100.0})["refused"], "upper bound inclusive")
	var lo := rig.directive({"target_pct": 54.9})
	assert_true(lo["refused"])
	assert_eq(lo["reason"], Wl.REFUSE_RANGE)
	var hi := rig.directive({"target_pct": 100.1})
	assert_eq(hi["reason"], Wl.REFUSE_RANGE)


func test_default_range_is_the_target() -> void:
	var rig := _erg_rig(erg(Wl.WORK, 60.0, 600.0))
	assert_false(rig.directive({"target_pct": 60.0})["refused"])
	assert_eq(rig.directive({"target_pct": 61.0})["reason"], Wl.REFUSE_RANGE)


func test_target_w_and_wkg_converted_to_pct() -> void:
	var rig := _erg_rig(erg(Wl.WORK, 60.0, 600.0).with_range(50.0, 100.0), {"weight_kg": 80.0})
	var rec := rig.directive({"target_w": 160.0})
	assert_false(rec["refused"])
	assert_almost_eq(float(rec["applied"]["target_pct"]), 80.0, 1e-9)
	assert_eq(int(rec["applied"]["target_w"]), 160)
	assert_eq(rig.directive({"target_w": 201.0})["reason"], Wl.REFUSE_RANGE, "100.5% is outside")
	var wkg := rig.directive({"target_wkg": 2.0})
	assert_false(wkg["refused"])
	assert_almost_eq(float(wkg["applied"]["target_pct"]), 80.0, 1e-9, "2 W/kg x 80 kg = 160 W")
	assert_eq(rig.directive({"target_wkg": 3.0})["reason"], Wl.REFUSE_RANGE, "240 W = 120%")


func test_sim_block_length() -> void:
	var cases := [[9.95, true], [10.0, false], [30.0, false], [30.05, true], [0.0, true]]
	for c: Array in cases:
		var rig := _erg_rig(erg(Wl.WORK, 65.0, 600.0))
		rig.run(30.0)
		var rec := rig.directive({"mode": "SIM", "duration_s": float(c[0])})
		assert_eq(rec["refused"], bool(c[1]), "duration %s" % c[0])
		if bool(c[1]):
			assert_eq(rec["reason"], Wl.REFUSE_SIM_BLOCK_LENGTH)


func test_sim_block_spacing_and_the_bracketing_exemption() -> void:
	var rig := _erg_rig(erg(Wl.WORK, 65.0, 900.0))
	rig.run(30.0)
	var t_start := rig.t
	var rec := rig.directive({"mode": "SIM", "duration_s": 10.0})
	assert_false(rec["refused"], "the first block")
	var back := rig.run_until(func() -> bool: return not bool(rig.s()["sim_block_active"]), 12.0)
	assert_time(back - t_start, 10.0, "the block's own return to ERG is exempt from the 30 s spacing")
	rig.run_until(func() -> bool: return rig.t >= back + 29.95 - 1e-6, 31.0)
	var early := rig.directive({"mode": "SIM", "duration_s": 10.0})
	assert_true(early["refused"])
	assert_eq(early["reason"], Wl.REFUSE_SWITCH_SPACING, "29.95 s after the previous switch")
	rig.step()
	assert_false(rig.directive({"mode": "SIM", "duration_s": 10.0})["refused"], "30 s after it")


func test_plan_switches_count_for_spacing() -> void:
	var rig := make_rig({}, follower())
	rig.start([sim(Wl.GRADE_FLAT, 60.0), erg(Wl.WORK, 65.0, 600.0)])
	rig.run(10.0)
	rig.gov.start_phase(1)
	rig.run(20.0)
	assert_eq(rig.directive({"mode": "SIM", "duration_s": 15.0})["reason"], Wl.REFUSE_SWITCH_SPACING)
	rig.run(10.0)
	assert_false(rig.directive({"mode": "SIM", "duration_s": 15.0})["refused"])


func test_mode_erg_ends_a_running_block() -> void:
	var rig := _erg_rig(erg(Wl.WORK, 65.0, 600.0))
	rig.run(30.0)
	rig.directive({"mode": "SIM", "duration_s": 30.0})
	rig.run(5.0)
	var rec := rig.directive({"mode": "ERG"})
	assert_false(rec["refused"])
	assert_false(rig.s()["sim_block_active"])
	rig.run(2.0)
	assert_eq(rig.s()["mode"], Wl.ERG)


func test_mode_erg_with_a_target_in_an_erg_phase_is_no_switch() -> void:
	var rig := _erg_rig(erg(Wl.WORK, 70.0, 600.0).with_range(60.0, 110.0))
	var before := float(rig.s()["last_switch_t"])
	var rec := rig.directive({"mode": "ERG", "target_pct": 80.0, "duration_s": 0.0, "reason": "pull", "source": "fishing"})
	assert_false(rec["refused"])
	assert_eq(float(rig.s()["last_switch_t"]), before)


func test_mode_grade_only_in_sim() -> void:
	var rig := _erg_rig(erg(Wl.WORK, 65.0, 600.0))
	rig.run(30.0)
	var no := rig.directive({"mode_grade": 3.0})
	assert_true(no["refused"])
	assert_eq(no["reason"], Wl.REFUSE_MODE_GRADE)
	var with_block := rig.directive({"mode": "SIM", "mode_grade": 3.0, "duration_s": 15.0})
	assert_false(with_block["refused"], "allowed in the block the same request opens")
	assert_false(rig.directive({"mode_grade": 2.0})["refused"], "and inside a running block")
	rig.gov.start_phase(2)
	assert_false(rig.directive({"mode": "SIM", "mode_grade": 8.0, "duration_s": 0.0, "reason": "boiler"})["refused"],
		"and in a SIM phase")


func test_mode_grade_goes_with_its_block() -> void:
	var rig := _erg_rig(erg(Wl.WORK, 65.0, 600.0))
	rig.run(30.0)
	rig.directive({"mode": "SIM", "duration_s": 15.0})
	rig.directive({"mode_grade": 4.0, "duration_s": 0.0})
	rig.run(16.0)
	assert_false(rig.s()["sim_block_active"])
	assert_almost_eq(float(rig.s()["mode_grade_pct"]), 0.0, 1e-9)


func test_sim_phase_refuses_erg() -> void:
	var rig := _erg_rig(sim(Wl.GRADE_GAME, 600.0))
	var m := rig.directive({"mode": "ERG"})
	assert_eq(m["reason"], Wl.REFUSE_ERG_IN_SIM)
	var t := rig.directive({"target_pct": 60.0})
	assert_eq(t["reason"], Wl.REFUSE_ERG_IN_SIM)


func test_sim_in_a_sim_phase_is_a_no_op_confirmation() -> void:
	# OWNERSHIP C4: Tank's 1.5 s haptic and its boiler grade (duration 0) arrive with mode SIM.
	var rig := _erg_rig(sim(Wl.GRADE_GAME, 600.0), {"haptic_intensity": 1.0})
	var hap := rig.directive({"mode": "SIM", "haptic": 2.0, "duration_s": 1.5, "reason": "hit", "source": "tank"})
	assert_false(hap["refused"])
	assert_eq(hap["applied"]["mode"], "SIM")
	assert_false(hap["applied"].has("sim_block"), "no SIM block in a SIM phase")
	var boil := rig.directive({"mode": "SIM", "mode_grade": 8.0, "duration_s": 0.0, "reason": "boiler", "source": "tank"})
	assert_false(boil["refused"])
	var bare := rig.directive({"mode": "SIM", "duration_s": 2.0})
	assert_false(bare["refused"], "no length or spacing rule")
	assert_false(rig.s()["sim_block_active"])


func test_cooldown_ignores_every_directive() -> void:
	var rig := make_rig({}, follower())
	rig.gov.set_plan(plan_with_cooldown([erg(Wl.WORK, 65.0, 60.0)]))
	rig.gov.start_phase(1)
	for d: Dictionary in [{"target_pct": 50.0}, {"mode": "SIM", "duration_s": 20.0}, {"mode": "SIM", "haptic": 2.0, "duration_s": 1.0}, {"crr": 0.8}]:
		var rec := rig.directive(d)
		assert_true(rec["refused"])
		assert_eq(rec["reason"], Wl.REFUSE_COOLDOWN)


func test_no_phase() -> void:
	var rig := make_rig({}, follower())
	assert_eq(rig.directive({"target_pct": 50.0})["reason"], Wl.REFUSE_NO_PHASE)
	rig.gov.set_plan(EffortPlan.of([erg(Wl.WORK, 50.0, 60.0)]))
	assert_eq(rig.directive({"target_pct": 50.0})["reason"], Wl.REFUSE_NO_PHASE, "plan set, no phase started")


func test_bad_fields() -> void:
	var rig := _erg_rig(erg(Wl.WORK, 60.0, 600.0).with_range(50.0, 100.0))
	assert_eq(rig.directive({"target_pct": 60.0, "target_w": 120.0})["reason"], Wl.REFUSE_BAD_FIELDS)
	assert_eq(rig.directive({"mode": "TURBO", "target_pct": 60.0})["reason"], Wl.REFUSE_BAD_FIELDS)
	assert_eq(rig.directive({"duration_s": 5.0})["reason"], Wl.REFUSE_BAD_FIELDS, "nothing set")
	assert_eq(rig.directive({"target_pct": 60.0, "duration_s": -1.0})["reason"], Wl.REFUSE_BAD_FIELDS)
	assert_eq(rig.directive({"target_pct": INF})["reason"], Wl.REFUSE_BAD_FIELDS)
	assert_eq(rig.gov.apply_directive(null)["reason"], Wl.REFUSE_BAD_FIELDS)


func test_pause_stops_expiry() -> void:
	var rig := _erg_rig(erg(Wl.WORK, 60.0, 600.0).with_range(50.0, 100.0))
	rig.directive({"target_pct": 80.0, "duration_s": 10.0})
	rig.run(5.0)
	rig.gov.set_game_paused(true)
	rig.run(20.0)
	rig.gov.set_game_paused(false)
	rig.run(4.9)
	assert_eq(int(rig.s()["governed_target_w"]), 160, "still held: 9.9 s of game time")
	rig.run(0.2)
	assert_eq(int(rig.s()["governed_target_w"]), 120)


func test_channels_are_independent() -> void:
	var rig := _erg_rig(sim(Wl.GRADE_GAME, 600.0))
	rig.directive({"mode_grade": 4.0, "duration_s": 5.0})
	rig.directive({"cw": 0.8, "duration_s": 0.0})
	rig.run(6.0)
	assert_almost_eq(float(rig.s()["mode_grade_pct"]), 0.0, 1e-9, "mode grade expired")
	assert_almost_eq(float(rig.s()["cw"]), 0.51 * 0.8, 1e-9, "the factor channel kept its value")


func test_ids_echoed() -> void:
	var rig := _erg_rig(erg(Wl.WORK, 60.0, 600.0).with_range(50.0, 100.0))
	var d := EffortDirective.from_dict({"target_pct": 70.0})
	d.id = 42
	var rec := rig.gov.apply_directive(d)
	assert_eq(rec["id"], 42)
	assert_eq(rig.records[rig.records.size() - 1]["id"], 42)


func test_mode_erg_alone_in_an_erg_phase_confirms() -> void:
	var rig := _erg_rig(erg(Wl.WORK, 60.0, 600.0))
	var rec := rig.directive({"mode": "ERG"})
	assert_false(rec["refused"])
	assert_eq(rec["applied"], {"mode": "ERG"})
