extends "res://tests/governor/gov_test_base.gd"
## BRIEF 4.6.6 SIM stacking: base grade = (course grade + mode grade) x difficulty (default
## 50%) + virtual-gear offset, clamped to the user's range (default -5..+10); total clamped to
## -10..+16; crr and cw factors in [0.5, 1.0]. OWNERSHIP PL7/PL8 (grade sources and course
## profiles), DS7 (mode_grade), DS9 (course_grade at 2 Hz).


func _sim_rig(params: Dictionary = {}, source: String = Wl.GRADE_GAME, phase: PlanPhase = null) -> Rig:
	var rig := make_rig(params, follower())
	rig.start([phase if phase != null else sim(source, 600.0)])
	rig.run(1.0)
	return rig


func test_course_plus_mode_grade_times_difficulty() -> void:
	var rig := _sim_rig()
	rig.gov.set_course_grade(6.0)
	rig.directive({"mode": "SIM", "mode_grade": 4.0, "duration_s": 0.0, "reason": "boiler"})
	rig.run(1.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 5.0, 1e-9, "(6 + 4) x 50%")
	assert_almost_eq(float(rig.s()["course_grade_pct"]), 6.0, 1e-9)
	assert_almost_eq(float(rig.s()["mode_grade_pct"]), 4.0, 1e-9)
	var dev: ScriptedDevice = rig.device
	assert_almost_eq(dev.grade_pct, 5.0, 1e-9)


func test_difficulty_setting() -> void:
	var rig := _sim_rig({"difficulty_pct": 100.0})
	rig.gov.set_course_grade(6.0)
	rig.run(1.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 6.0, 1e-9)


func test_gear_offset_is_added_after_difficulty() -> void:
	var rig := _sim_rig()
	rig.gov.set_course_grade(4.0)
	rig.gov.shift(1)
	rig.run(1.0)
	var expect := 2.0 + VirtualGears.offset_for(13, 2.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), expect, 1e-9)
	assert_eq(int(rig.s()["gear"]), 13)


func test_user_range_clamp() -> void:
	var rig := _sim_rig()
	rig.gov.set_course_grade(30.0)
	rig.run(1.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 10.0, 1e-9, "15% capped at the default +10%")
	assert_has(rig.s()["clamped_by"], Wl.CLAMP_GRADE_RANGE)
	rig.gov.set_course_grade(-20.0)
	rig.run(1.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), -5.0, 1e-9, "-10% capped at the default -5%")
	var rig2 := _sim_rig({"grade_min_pct": -2.0, "grade_max_pct": 4.0})
	rig2.gov.set_course_grade(12.0)
	rig2.run(1.0)
	assert_almost_eq(float(rig2.s()["applied_grade_pct"]), 4.0, 1e-9, "the rider's own range")


func test_total_limits() -> void:
	var rig := _sim_rig({"grade_min_pct": -20.0, "grade_max_pct": 30.0, "difficulty_pct": 100.0})
	rig.gov.set_course_grade(25.0)
	rig.run(1.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 16.0, 1e-9, "the user range itself is bounded by +16%")
	rig.gov.set_course_grade(-25.0)
	rig.run(1.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), -10.0, 1e-9)


func test_tank_largest_stack_stays_below_16() -> void:
	# T2.3: Bulwark (6 + 4)% x difficulty <= +10%, plus the largest haptic +3% = 13%.
	var rig := _sim_rig({"difficulty_pct": 100.0, "haptic_intensity": 1.0})
	rig.gov.set_course_grade(6.0)
	rig.directive({"mode": "SIM", "mode_grade": 4.0, "duration_s": 0.0, "reason": "hoist"})
	rig.directive({"mode": "SIM", "haptic": 3.0, "duration_s": 2.0, "reason": "boss_hit"})
	rig.run(1.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 13.0, 1e-9)
	assert_does_not_have(rig.s()["clamped_by"], Wl.CLAMP_GRADE_LIMIT)


func test_crr_and_cw_factor_bounds() -> void:
	var rig := _sim_rig()
	var rec := rig.directive({"mode": "SIM", "crr": 0.3, "cw": 1.5, "duration_s": 0.0})
	assert_false(rec["refused"])
	assert_almost_eq(float(rec["applied"]["crr_factor"]), 0.5, 1e-9)
	assert_almost_eq(float(rec["applied"]["cw_factor"]), 1.0, 1e-9)
	assert_has(rec["clamped_by"], Wl.CLAMP_FACTOR)
	rig.run(1.0)
	assert_almost_eq(float(rig.s()["crr"]), 0.002, 1e-12, "0.004 x 0.5")
	assert_almost_eq(float(rig.s()["cw"]), 0.51, 1e-12, "factors only lower resistance")
	var dev: ScriptedDevice = rig.device
	assert_almost_eq(dev.crr, 0.002, 1e-9)
	var rec2 := rig.directive({"mode": "SIM", "cw": 0.7, "duration_s": 0.0, "reason": "draft"})
	assert_does_not_have(rec2["clamped_by"], Wl.CLAMP_FACTOR)
	rig.run(1.0)
	assert_almost_eq(float(rig.s()["cw"]), 0.357, 1e-9, "0.51 x 0.7")
	assert_almost_eq(float(rig.s()["crr"]), 0.004, 1e-12, "a request replaces the whole factors channel")


func test_flat_source_ignores_course_grade() -> void:
	var rig := _sim_rig({}, Wl.GRADE_FLAT)
	rig.gov.set_course_grade(6.0)
	rig.run(1.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 0.0, 1e-9)
	var last: Dictionary = rig.records[rig.records.size() - 1]
	assert_eq(last["kind"], "course_grade")
	assert_true(last["refused"])
	assert_eq(last["reason"], Wl.REFUSE_NOT_GAME_GRADE)


func test_course_grade_refused_in_erg_and_cooldown() -> void:
	var rig := make_rig({}, follower())
	rig.gov.set_plan(plan_with_cooldown([erg(Wl.WORK, 60.0, 60.0)]))
	rig.gov.start_phase(0)
	rig.gov.set_course_grade(3.0)
	assert_eq(rig.records[0]["reason"], Wl.REFUSE_NOT_GAME_GRADE)
	rig.gov.start_phase(1)
	rig.gov.set_course_grade(3.0)
	assert_eq(rig.records[1]["reason"], Wl.REFUSE_COOLDOWN)


func test_course_grade_coalesced_to_2_hz() -> void:
	var rig := _sim_rig({"difficulty_pct": 100.0})
	rig.keep_trace = true
	var t0 := rig.t
	for i in 100:
		rig.gov.set_course_grade(float(i) * 0.05)
		rig.step()
	rig.run(1.0)
	var changes: Array[float] = []
	var prev := float(rig.trace[0]["course_grade_pct"])
	for s: Dictionary in rig.trace:
		var g := float(s["course_grade_pct"])
		if absf(g - prev) > 1e-12:
			changes.append(float(s["rig_t"]))
			prev = g
	for i in range(1, changes.size()):
		assert_gte(changes[i] - changes[i - 1], 0.5 - 1e-6, "at most 2 changes per second")
	assert_almost_eq(float(rig.s()["course_grade_pct"]), 99.0 * 0.05, 1e-9, "the newest value wins")
	var dev: ScriptedDevice = rig.device
	assert_lte(dev.max_writes_in_window(1.0), 2)
	assert_eq(dev.writes_of("sim", t0).size() > 0, true)


func test_course_grade_holds_until_the_phase_ends() -> void:
	var rig := make_rig({}, follower())
	rig.start([sim(Wl.GRADE_GAME, 60.0), sim(Wl.GRADE_GAME, 60.0)])
	rig.gov.set_course_grade(6.0)
	rig.run(30.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 3.0, 1e-9)
	rig.gov.start_phase(1)
	rig.step()
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 0.0, 1e-9, "reset at the phase change")


func test_course_profile_followed_by_distance() -> void:
	var phase := PlanPhase.sim(Wl.WORK, Wl.GRADE_COURSE, 600.0).with_course([[0.0, 0.0], [100.0, 4.0], [200.0, -2.0]])
	var rig := make_rig({"difficulty_pct": 100.0}, follower())
	rig.gov.set_course_distance(1000.0)
	rig.start([phase])
	rig.run(1.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 0.0, 1e-9, "distance counts from the phase start")
	rig.gov.set_course_distance(1050.0)
	rig.run(1.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 2.0, 1e-9, "halfway to the 4% point")
	rig.gov.set_course_distance(1100.0)
	rig.run(1.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 4.0, 1e-9)
	rig.gov.set_course_distance(1175.0)
	rig.run(1.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), -0.5, 1e-9)
	rig.gov.set_course_distance(5000.0)
	rig.run(1.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), -2.0, 1e-9, "the last grade holds")


func test_profile_grade_helper() -> void:
	var p := [[0.0, 1.0], [10.0, 3.0]]
	assert_almost_eq(SafetyGovernor.profile_grade(p, -5.0), 1.0, 1e-12)
	assert_almost_eq(SafetyGovernor.profile_grade(p, 5.0), 2.0, 1e-12)
	assert_almost_eq(SafetyGovernor.profile_grade(p, 50.0), 3.0, 1e-12)
	assert_almost_eq(SafetyGovernor.profile_grade([], 5.0), 0.0, 1e-12)


func test_mode_grade_stack_in_a_sim_block() -> void:
	# In a SIM block inside an ERG phase there is no course grade: mode grade x difficulty + gear.
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 65.0, 600.0)])
	rig.run(40.0)
	var rec := rig.directive({"mode": "SIM", "mode_grade": 6.0, "duration_s": 20.0})
	assert_false(rec["refused"])
	rig.run(2.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 3.0, 1e-9)
