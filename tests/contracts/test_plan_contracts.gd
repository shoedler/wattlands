extends GutTest
## PlanPhase and EffortPlan (BRIEF 3.6): JSON round trips and the helpers the
## PlanValidator and the governor rely on (planned_pct_at, effective_range, worst and best
## case length, peak_pct).


func _rt(d: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(d))
	assert_true(parsed is Dictionary)
	return parsed if parsed is Dictionary else {}


func _same_json(a: Dictionary, b: Dictionary, msg: String = "") -> void:
	assert_eq(JSON.stringify(a), JSON.stringify(b), msg)


# --- round trips ----------------------------------------------------------------------

func test_erg_phase_with_ramp_and_range_round_trip() -> void:
	var p := PlanPhase.erg(Wl.WARMUP, 50.0, 300.0, "Warm-up").with_ramp(65.0).with_range(45.0, 70.0).with_lap()
	var d := p.to_dict()
	assert_eq(d["mode"], Wl.ERG)
	assert_eq(d["target_pct"], 50.0)
	assert_eq(d["ramp_to_pct"], 65.0)
	assert_eq(d["range_pct"], [45.0, 70.0])
	assert_false(d.has("grade_source"), "ERG phases carry no SIM fields")
	assert_false(d.has("open_ended"))
	var q := PlanPhase.from_dict(_rt(d))
	_same_json(q.to_dict(), d)
	assert_eq(q.kind, Wl.WARMUP)
	assert_eq(q.label, "Warm-up")
	assert_true(q.lap)
	assert_true(q.has_ramp())
	assert_eq(q.range_pct, [45.0, 70.0])


func test_erg_phase_without_optionals() -> void:
	var d := PlanPhase.erg(Wl.WORK, 80.0, 60.0).to_dict()
	assert_false(d.has("ramp_to_pct"))
	assert_false(d.has("range_pct"))
	assert_false(d.has("meta"))
	var q := PlanPhase.from_dict(_rt(d))
	assert_false(q.has_ramp())
	assert_eq(q.ramp_to_pct, PlanPhase.NONE)
	assert_eq(q.range_pct.size(), 0)


func test_sim_course_phase_round_trip() -> void:
	var profile := [[0.0, 0.0], [500.0, 3.5], [1200.0, -2.0]]
	var p := PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, 600.0, "Course").with_course(profile)
	assert_eq(p.grade_source, Wl.GRADE_COURSE)
	var d := p.to_dict()
	assert_eq(d["mode"], Wl.SIM)
	assert_eq(d["grade_source"], Wl.GRADE_COURSE)
	assert_eq(d["course_profile"], profile)
	assert_false(d.has("target_pct"), "SIM phases carry no ERG fields")
	var q := PlanPhase.from_dict(_rt(d))
	_same_json(q.to_dict(), d)
	assert_eq(q.course_profile, profile)
	assert_eq(q.mode, Wl.SIM)


func test_sim_game_phase_round_trip() -> void:
	var d := PlanPhase.sim(Wl.WORK, Wl.GRADE_GAME, 120.0).to_dict()
	assert_false(d.has("course_profile"), "only course phases carry a profile")
	var q := PlanPhase.from_dict(_rt(d))
	assert_eq(q.grade_source, Wl.GRADE_GAME)
	assert_eq(q.duration_s, 120.0)


func test_open_ended_phase_round_trip() -> void:
	var p := PlanPhase.erg(Wl.WORK, 55.0, 180.0, "Advance").with_range(55.0, 100.0).with_open(90.0, 300.0)
	p.with_meta({"wave": 3.0, "name": "north gate"})
	var d := p.to_dict()
	assert_true(d["open_ended"])
	assert_eq(d["min_s"], 90.0)
	assert_eq(d["max_s"], 300.0)
	assert_eq(d["meta"], {"wave": 3.0, "name": "north gate"})
	var q := PlanPhase.from_dict(_rt(d))
	_same_json(q.to_dict(), d)
	assert_true(q.open_ended)
	assert_eq(q.min_s, 90.0)
	assert_eq(q.max_s, 300.0)
	assert_eq(q.meta["name"], "north gate")


func test_from_empty_dict_defaults() -> void:
	var q := PlanPhase.from_dict({})
	assert_eq(q.kind, Wl.WORK)
	assert_eq(q.mode, Wl.ERG)
	assert_eq(q.target_pct, 0.0)
	assert_false(q.has_ramp())
	assert_eq(q.grade_source, Wl.GRADE_FLAT)
	assert_false(q.open_ended)
	assert_false(q.lap)


func test_duplicate_phase_is_deep() -> void:
	var p := PlanPhase.erg(Wl.WORK, 70.0, 60.0).with_meta({"list": [1.0, 2.0]})
	var q := p.duplicate_phase()
	(q.meta["list"] as Array).append(3.0)
	assert_eq((p.meta["list"] as Array).size(), 2)
	q.target_pct = 99.0
	assert_eq(p.target_pct, 70.0)


func test_meta_is_copied_on_to_dict() -> void:
	var p := PlanPhase.erg(Wl.WORK, 70.0, 60.0).with_meta({"k": "v"})
	var d := p.to_dict()
	(d["meta"] as Dictionary)["k"] = "changed"
	assert_eq(p.meta["k"], "v")


# --- helpers --------------------------------------------------------------------------

func test_planned_pct_at_with_ramp() -> void:
	var p := PlanPhase.erg(Wl.WARMUP, 50.0, 300.0).with_ramp(65.0)
	assert_eq(p.planned_pct_at(0.0), 50.0)
	assert_almost_eq(p.planned_pct_at(150.0), 57.5, 1e-9)
	assert_almost_eq(p.planned_pct_at(300.0), 65.0, 1e-9)
	assert_almost_eq(p.planned_pct_at(400.0), 65.0, 1e-9, "holds the end after the ramp")
	assert_eq(p.planned_pct_at(-10.0), 50.0)
	var down := PlanPhase.erg(Wl.COOLDOWN, 70.0, 100.0).with_ramp(50.0)
	assert_almost_eq(down.planned_pct_at(25.0), 65.0, 1e-9)


func test_planned_pct_at_without_ramp() -> void:
	var p := PlanPhase.erg(Wl.WORK, 88.0, 120.0)
	for t: float in [0.0, 60.0, 120.0, 500.0]:
		assert_eq(p.planned_pct_at(t), 88.0)
	var zero_len := PlanPhase.erg(Wl.WORK, 60.0, 0.0).with_ramp(80.0)
	assert_eq(zero_len.planned_pct_at(10.0), 60.0, "no ramp over a zero-length phase")


func test_planned_pct_at_open_ended_ramps_over_duration_then_holds() -> void:
	var p := PlanPhase.erg(Wl.WORK, 50.0, 100.0).with_ramp(70.0).with_open(60.0, 200.0)
	assert_almost_eq(p.planned_pct_at(50.0), 60.0, 1e-9)
	assert_almost_eq(p.planned_pct_at(100.0), 70.0, 1e-9)
	assert_almost_eq(p.planned_pct_at(180.0), 70.0, 1e-9)


func test_effective_range() -> void:
	assert_eq(PlanPhase.erg(Wl.WORK, 80.0, 60.0).effective_range(), [80.0, 80.0])
	assert_eq(PlanPhase.erg(Wl.WARMUP, 50.0, 300.0).with_ramp(65.0).effective_range(), [50.0, 65.0])
	assert_eq(PlanPhase.erg(Wl.WORK, 70.0, 300.0).with_ramp(55.0).effective_range(), [55.0, 70.0], "a ramp down")
	assert_eq(PlanPhase.erg(Wl.WORK, 55.0, 180.0).with_range(55.0, 100.0).effective_range(), [55.0, 100.0])
	assert_eq(PlanPhase.erg(Wl.WORK, 80.0, 60.0).with_range(60.0, 70.0).effective_range(), [60.0, 80.0],
		"the target always stays inside its range")
	assert_eq(PlanPhase.erg(Wl.WORK, 50.0, 60.0).with_ramp(65.0).with_range(45.0, 70.0).effective_range(), [45.0, 70.0])
	assert_eq(PlanPhase.erg(Wl.WORK, 50.0, 60.0).with_ramp(75.0).with_range(45.0, 70.0).effective_range(), [45.0, 75.0],
		"ramp end above the range top")


func test_worst_and_best_case_length() -> void:
	var fixed := PlanPhase.erg(Wl.WORK, 80.0, 180.0)
	assert_eq(fixed.worst_case_length_s(), 180.0)
	assert_eq(fixed.best_case_length_s(), 180.0)
	var open := PlanPhase.erg(Wl.WORK, 80.0, 180.0).with_open(90.0, 330.0)
	assert_eq(open.worst_case_length_s(), 330.0, "max_s counts for BRIEF 4.6.1")
	assert_eq(open.best_case_length_s(), 90.0)
	assert_eq(open.duration_s, 180.0, "duration_s stays the nominal length")


func test_peak_pct() -> void:
	assert_eq(PlanPhase.erg(Wl.WORK, 80.0, 60.0).peak_pct(), 80.0)
	assert_eq(PlanPhase.erg(Wl.WORK, 80.0, 60.0).with_ramp(95.0).peak_pct(), 95.0)
	assert_eq(PlanPhase.erg(Wl.WORK, 55.0, 60.0).with_range(55.0, 104.0).peak_pct(), 104.0)
	assert_eq(PlanPhase.erg(Wl.WORK, 90.0, 60.0).with_ramp(70.0).with_range(60.0, 85.0).peak_pct(), 90.0)


# --- EffortPlan -----------------------------------------------------------------------

func _plan() -> EffortPlan:
	return EffortPlan.of([
		PlanPhase.erg(Wl.WARMUP, 50.0, 300.0, "Warm-up").with_ramp(65.0).with_lap(),
		PlanPhase.erg(Wl.WORK, 55.0, 180.0, "Advance").with_range(55.0, 100.0).with_open(90.0, 300.0),
		PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, 30.0, "Sprint"),
		"not a phase",
	])


func test_plan_basics() -> void:
	var plan := _plan()
	assert_eq(plan.size(), 3, "of() skips non-phases")
	assert_eq(plan.phase(0).label, "Warm-up")
	assert_null(plan.phase(3))
	assert_null(plan.phase(-1))
	assert_eq(plan.nominal_length_s(), 510.0)
	assert_eq(plan.max_length_s(), 630.0, "open-ended phases count max_s")
	assert_eq(plan.cooldown_index(), -1)
	assert_same(plan.add(PlanPhase.erg(Wl.COOLDOWN, 50.0, 180.0)), plan, "add is fluent")
	plan.cooldown_appended = true
	assert_eq(plan.cooldown_index(), 3)


func test_plan_round_trip() -> void:
	var plan := _plan()
	plan.add(PlanPhase.erg(Wl.COOLDOWN, 50.0, 180.0, "Cool-down"))
	plan.cooldown_appended = true
	var d := plan.to_dict()
	var back := EffortPlan.from_dict(_rt(d))
	_same_json(back.to_dict(), d)
	assert_eq(back.size(), 4)
	assert_true(back.cooldown_appended)
	assert_eq(back.cooldown_index(), 3)
	assert_true(back.phase(1).open_ended)
	assert_eq(back.phase(2).mode, Wl.SIM)


func test_duplicate_plan_is_independent() -> void:
	var plan := _plan()
	var copy := plan.duplicate_plan()
	copy.phase(0).target_pct = 99.0
	copy.add(PlanPhase.erg(Wl.WORK, 60.0, 60.0))
	assert_eq(plan.phase(0).target_pct, 50.0)
	assert_eq(plan.size(), 3)


func test_plan_from_bad_dict() -> void:
	var plan := EffortPlan.from_dict({"phases": [{"kind": Wl.WORK}, "junk", 3]})
	assert_eq(plan.size(), 1)
	assert_false(plan.cooldown_appended)
	assert_eq(EffortPlan.from_dict({}).size(), 0)
