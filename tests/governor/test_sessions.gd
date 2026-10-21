extends "res://tests/governor/gov_test_base.gd"
## Whole sessions with the W0 MockTrainer (BRIEF 4.2 erg follower, ~1 Hz jittered samples),
## stepping phases the way the GameHost does: Workout's VO2 never reaches the 105% duration
## limit (BRIEF 3.7, 7.4), a compliant rider is never rescued, warm-up limits hold, the
## cool-down runs at 50% FTP and every write respects coalescing.


## Run `plan` phase by phase (fixed durations); returns the per-tick statuses.
func _ride(rig: Rig, plan: EffortPlan) -> void:
	rig.gov.set_plan(plan)
	for i in plan.size():
		rig.gov.start_phase(i)
		rig.run(plan.phase(i).duration_s)


func _vo2() -> EffortPlan:
	var phases: Array = [PlanPhase.erg(Wl.WARMUP, 50.0, 300.0, "Warm-up").with_ramp(65.0)]
	for i in 5:
		phases.append(PlanPhase.erg(Wl.WORK, 110.0, 180.0, "VO2 %d" % (i + 1)))
		if i < 4:
			phases.append(PlanPhase.erg(Wl.RECOVERY, 50.0, 180.0, "Easy"))
	return plan_with_cooldown(phases)


func test_vo2_never_reaches_the_105_limit() -> void:
	var mock := MockTrainer.from_spec("erg:compliance=1.0", 250.0, {"seed": 3})
	var rig := make_rig({"ftp_w": 250.0, "skip_warmup": false}, mock)
	rig.keep_trace = true
	_ride(rig, _vo2())
	var min_left := 300.0
	var max_target := 0
	var rescues := 0
	for s: Dictionary in rig.trace:
		min_left = minf(min_left, float(s["s_left_105"]))
		max_target = maxi(max_target, int(s["applied_target_w"]))
		assert_false(bool(s["latched_105"]), "never latched")
		if bool(s["rescue"]):
			rescues += 1
	assert_between(min_left, 120.0, 130.0, "each 180 s block spends < 180 s of the 300 s, then the 50% recovery resets it")
	assert_eq(max_target, 275, "110% of 250 W")
	assert_eq(rescues, 0, "a compliant rider is never rescued")
	assert_eq(rig.events_named("rescue_changed").size(), 0)
	assert_eq(int(rig.s()["applied_target_w"]), 125, "the cool-down at 50%")
	assert_lte(mock.command_count, int(rig.t * 2.0) + 2)


func test_warmup_limits_hold_for_the_whole_first_5_minutes() -> void:
	var mock := MockTrainer.from_spec("erg", 200.0, {"seed": 5})
	var rig := make_rig({"skip_warmup": false}, mock)
	rig.keep_trace = true
	var plan := EffortPlan.of([PlanPhase.erg(Wl.WARMUP, 60.0, 120.0).with_range(60.0, 100.0),
		PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, 60.0), PlanPhase.erg(Wl.WORK, 90.0, 300.0)])
	rig.gov.set_plan(plan)
	rig.gov.start_phase(0)
	rig.directive({"target_pct": 100.0})
	rig.run(120.0)
	rig.gov.start_phase(1)
	for i in 12:
		rig.gov.shift(1)
	rig.run(60.0)
	rig.gov.start_phase(2)
	rig.run(300.0)
	for s: Dictionary in rig.trace:
		if bool(s["warmup_active"]):
			assert_lte(int(s["applied_target_w"]), 130, "ERG <= 65% in warm-up")
			assert_between(float(s["applied_grade_pct"]), -2.0, 3.0, "grade within -2..+3 in warm-up")
	assert_false(rig.gov.is_warmup_active())
	assert_eq(rig.applied_w(), 180)


func test_sim_phase_with_a_mock_rider_returns_to_erg_at_or_below_the_target() -> void:
	# The erg mock rides 90% FTP in SIM without a power band, so the return to a 65% ERG
	# phase enters at the planned 130 W, never above it.
	var mock := MockTrainer.from_spec("erg", 200.0, {"seed": 9})
	var rig := make_rig({}, mock)
	rig.keep_trace = true
	_ride(rig, EffortPlan.of([PlanPhase.erg(Wl.WORK, 65.0, 60.0), PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, 30.0),
		PlanPhase.erg(Wl.WORK, 65.0, 60.0)]))
	for s: Dictionary in rig.trace:
		assert_lte(int(s["applied_target_w"]), 130)
	assert_eq(mock.commanded_mode, Wl.ERG)
	assert_eq(mock.commanded_target_w, 130)


## One busy, seeded ride: warm-up ramp, ERG directives, a SIM block, a game-grade SIM phase
## with haptics and gears. Returns everything the governor reported, as JSON.
func _busy_ride() -> String:
	var mock := MockTrainer.from_spec("erg:compliance=1.0", 250.0, {"seed": 11})
	var rig := make_rig({"ftp_w": 250.0, "ftp_verified": false, "skip_warmup": false, "haptic_intensity": 0.7}, mock)
	rig.keep_trace = true
	rig.gov.set_plan(plan_with_cooldown([
		PlanPhase.erg(Wl.WARMUP, 50.0, 300.0).with_ramp(65.0),
		PlanPhase.erg(Wl.WORK, 80.0, 120.0).with_range(70.0, 110.0),
		PlanPhase.sim(Wl.WORK, Wl.GRADE_GAME, 90.0),
	]))
	rig.gov.start_phase(0)
	rig.run(300.0)
	rig.gov.start_phase(1)
	for i in 2400:
		if i % 10 == 0:
			rig.directive({"mode": "ERG", "target_pct": 70.0 + float(i % 400) / 10.0, "duration_s": 3.0})
		if i == 1200:
			rig.directive({"mode": "SIM", "duration_s": 20.0, "reason": "overdrive"})
		rig.step()
	rig.gov.start_phase(2)
	for i in 1800:
		rig.gov.set_course_grade(sin(float(i) * 0.02) * 5.0)
		if i % 300 == 0:
			rig.directive({"mode": "SIM", "haptic": 2.0, "duration_s": 1.5})
		if i % 100 == 0:
			rig.gov.shift(1 if (i / 100) % 2 == 0 else -1)
		rig.step()
	rig.gov.start_phase(3)
	rig.run(30.0)
	return JSON.stringify({"trace": rig.trace, "records": rig.records, "events": rig.events,
		"commands": mock.command_count})


func test_same_inputs_give_the_same_ride() -> void:
	# OWNERSHIP C29: every governor rule runs on the sim clock, so two runs with the same
	# inputs and seed report exactly the same thing.
	var a := _busy_ride()
	var b := _busy_ride()
	assert_gt(a.length(), 100000, "a long report")
	assert_eq(a.sha256_text(), b.sha256_text(), "identical reports")
