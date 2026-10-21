extends GutTest
## PlanValidator (BRIEF 3.6, 4.5, 4.6.1, 4.6.8; docs/OWNERSHIP.md PL2, PL4-PL6, PL9, PL12,
## PL14-PL19; 3.1 C15, C16, C35).


func _warmup() -> PlanPhase:
	return PlanPhase.erg(Wl.WARMUP, 50, 300, "Warm-up").with_ramp(65).with_lap()


func _plan(phases: Array) -> EffortPlan:
	return EffortPlan.of(phases)


func _ok(plan: EffortPlan, opts: Dictionary = {}) -> Dictionary:
	var res := PlanValidator.validate(plan, opts)
	assert_true(res["ok"], "expected ok, errors: %s" % [res["errors"]])
	return res


func _rejected(plan: EffortPlan, needle: String, opts: Dictionary = {}) -> Dictionary:
	var res := PlanValidator.validate(plan, opts)
	assert_false(res["ok"], "expected a rejection mentioning %s" % needle)
	var joined := "; ".join(res["errors"])
	assert_string_contains(joined, needle)
	return res


func test_simple_plan_is_ok_without_warnings() -> void:
	var res := _ok(_plan([_warmup(), PlanPhase.erg(Wl.WORK, 75, 180, "Push").with_lap()]))
	assert_eq(res["warnings"], [])
	assert_eq(res["errors"], [])


func test_finalize_appends_the_standard_cooldown() -> void:
	var plan := _plan([_warmup(), PlanPhase.erg(Wl.WORK, 75, 180, "Push")])
	var out := PlanValidator.finalize(plan)
	assert_not_null(out)
	assert_true(out.cooldown_appended)
	assert_eq(out.size(), 3)
	var cd := out.phase(2)
	assert_eq(cd.kind, Wl.COOLDOWN)
	assert_eq(cd.mode, Wl.ERG)
	assert_eq(cd.target_pct, 50.0)
	assert_eq(cd.duration_s, 180.0)
	assert_true(cd.lap)
	assert_eq(cd.label, "Cool-down")
	assert_eq(out.cooldown_index(), 2)
	assert_false(plan.cooldown_appended, "the input plan is not modified")
	assert_eq(plan.size(), 2)


func test_finalize_rejects_with_null_and_warning() -> void:
	var out := PlanValidator.finalize(_plan([PlanPhase.erg(Wl.WORK, 90, 60)]))
	assert_null(out)
	assert_push_warning("plan rejected")


func test_cooldown_phase_matches_the_contract() -> void:
	var cd := PlanValidator.cooldown_phase()
	assert_true(PlanValidator.is_standard_cooldown(cd))
	assert_eq(cd.kind, Wl.COOLDOWN)
	assert_eq(cd.target_pct, PlanValidator.COOLDOWN_PCT)
	assert_eq(cd.duration_s, PlanValidator.COOLDOWN_S)


func test_game_written_cooldown_is_rejected() -> void:
	_rejected(_plan([_warmup(), PlanPhase.erg(Wl.COOLDOWN, 50, 180)]), "COOLDOWN")


func test_null_and_empty_plans() -> void:
	var r1 := PlanValidator.validate(null)
	assert_false(r1["ok"])
	_rejected(EffortPlan.new(), "no phases")


func test_revalidating_a_finalized_plan_keeps_its_cooldown() -> void:
	var out := PlanValidator.finalize(_plan([_warmup(), PlanPhase.erg(Wl.WORK, 80, 120)]))
	_ok(out)
	var again := PlanValidator.finalize(out)
	assert_eq(again.size(), out.size(), "finalize never appends a second cool-down")
	# Over the wire (plan message) and back.
	var wire: Variant = JSON.parse_string(JSON.stringify(out.to_dict()))
	_ok(EffortPlan.from_dict(wire))


func test_finalized_plan_with_a_changed_cooldown_is_rejected() -> void:
	var out := PlanValidator.finalize(_plan([_warmup()]))
	out.phase(out.size() - 1).target_pct = 70
	_rejected(out, "standard cool-down")


func test_warmup_rejects_targets_above_65_in_the_first_300_s() -> void:
	_rejected(_plan([PlanPhase.erg(Wl.WARMUP, 70, 120)]), "target_pct 70% > 65%")
	_rejected(_plan([PlanPhase.erg(Wl.WARMUP, 50, 300).with_ramp(66)]), "ramp_to_pct 66%")
	_rejected(_plan([PlanPhase.erg(Wl.WARMUP, 50, 200).with_range(50, 70)]), "range_pct[1] 70%")
	# A phase that starts inside the first 300 s counts whole.
	_rejected(
		_plan([PlanPhase.erg(Wl.WARMUP, 50, 299), PlanPhase.erg(Wl.WORK, 80, 120)]), "phase 1"
	)


func test_warmup_allows_65_exactly_and_work_from_300_s() -> void:
	_ok(_plan([_warmup(), PlanPhase.erg(Wl.WORK, 95, 120)]))
	_ok(
		_plan(
			[PlanPhase.erg(Wl.WARMUP, 65, 300).with_range(50, 65), PlanPhase.erg(Wl.WORK, 100, 60)]
		)
	)


func test_warmup_allows_sim_phases_c35() -> void:
	# Tank's depot (SIM game from t = 0), Workout's e2e sprint and Fishing's e2e landing.
	_ok(
		_plan(
			[
				PlanPhase.sim(Wl.WARMUP, Wl.GRADE_GAME, 240, "Depot"),
				PlanPhase.erg(Wl.WORK, 55, 120).with_range(55, 65)
			]
		)
	)
	var e2e := _plan(
		[
			PlanPhase.erg(Wl.WARMUP, 50, 60).with_ramp(60),
			PlanPhase.erg(Wl.WORK, 65, 30),
			PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, 30, "Sprint"),
		]
	)
	var res := _ok(e2e)
	assert_eq(res["warnings"], [], "the e2e session's switches are exactly 30 s apart")


func test_open_ended_phases_at_min_s_decide_the_warmup_window() -> void:
	var opener := PlanPhase.erg(Wl.WARMUP, 50, 0, "Open").with_open(200, 400)
	_rejected(_plan([opener, PlanPhase.erg(Wl.WORK, 80, 120)]), "phase 1")
	var long_opener := PlanPhase.erg(Wl.WARMUP, 50, 0, "Open").with_open(300, 400)
	_ok(_plan([long_opener, PlanPhase.erg(Wl.WORK, 80, 120)]))


func test_absolute_ceiling_150() -> void:
	_rejected(_plan([_warmup(), PlanPhase.erg(Wl.WORK, 151, 20)]), "151% > 150%")
	_ok(_plan([_warmup(), PlanPhase.erg(Wl.WORK, 150, 20)]))
	_rejected(
		_plan([_warmup(), PlanPhase.erg(Wl.WORK, 100, 20).with_range(90, 155)]), "155% > 150%"
	)


func test_long_phase_cap_105() -> void:
	_rejected(_plan([_warmup(), PlanPhase.erg(Wl.WORK, 106, 301)]), "longer than 300 s")
	_ok(_plan([_warmup(), PlanPhase.erg(Wl.WORK, 105, 1200)]))
	_ok(_plan([_warmup(), PlanPhase.erg(Wl.WORK, 110, 300)]))
	# The range top counts (Tank's boss: max_s 360 at <= 100 % is fine; 106 % is not).
	_ok(_plan([_warmup(), PlanPhase.erg(Wl.WORK, 55, 180).with_range(55, 100).with_open(90, 360)]))
	_rejected(
		_plan([_warmup(), PlanPhase.erg(Wl.WORK, 55, 180).with_range(55, 106).with_open(90, 360)]),
		"longer than 300 s"
	)


func test_open_ended_long_phase_at_max_s_pl16() -> void:
	# Fishing's tuna: 104.76 % accepted at max_s 540; the marlin at 104 % for 1320 s.
	_ok(_plan([_warmup(), PlanPhase.erg(Wl.WORK, 104.76, 0, "Tuna").with_open(120, 540)]))
	_ok(_plan([_warmup(), PlanPhase.erg(Wl.WORK, 104, 0, "Marlin").with_open(300, 1320)]))
	_rejected(
		_plan([_warmup(), PlanPhase.erg(Wl.WORK, 105.5, 0, "Tuna").with_open(120, 540)]),
		"longer than 300 s"
	)


func test_105_accrual_and_reset_pl17() -> void:
	# 200 s + 200 s above 105 % with only 60 s of recovery: 400 s accrued.
	_rejected(
		_plan(
			[
				_warmup(),
				PlanPhase.erg(Wl.WORK, 110, 200),
				PlanPhase.erg(Wl.RECOVERY, 50, 60),
				PlanPhase.erg(Wl.WORK, 110, 200),
			]
		),
		"accrued above 105%"
	)
	# 120 s at exactly 90 % resets (inclusive).
	_ok(
		_plan(
			[
				_warmup(),
				PlanPhase.erg(Wl.WORK, 110, 200),
				PlanPhase.erg(Wl.RECOVERY, 90, 120),
				PlanPhase.erg(Wl.WORK, 110, 200),
			]
		)
	)
	# 119 s does not.
	_rejected(
		_plan(
			[
				_warmup(),
				PlanPhase.erg(Wl.WORK, 110, 200),
				PlanPhase.erg(Wl.RECOVERY, 90, 119),
				PlanPhase.erg(Wl.WORK, 110, 200),
			]
		),
		"accrued above 105%"
	)
	# Consecutive qualifying phases add up to the reset.
	_ok(
		_plan(
			[
				_warmup(),
				PlanPhase.erg(Wl.WORK, 110, 200),
				PlanPhase.erg(Wl.RECOVERY, 60, 60),
				PlanPhase.erg(Wl.RECOVERY, 85, 60),
				PlanPhase.erg(Wl.WORK, 110, 200),
			]
		)
	)
	# Exactly 300 s accrued is allowed.
	_ok(
		_plan(
			[
				_warmup(),
				PlanPhase.erg(Wl.WORK, 110, 150),
				PlanPhase.erg(Wl.WORK, 100, 30),
				PlanPhase.erg(Wl.WORK, 110, 150)
			]
		)
	)


func test_workout_vo2_blocks_are_valid() -> void:
	var phases: Array = [_warmup()]
	for i in 5:
		phases.append(PlanPhase.erg(Wl.WORK, 110, 180, "VO2 %d" % (i + 1)).with_lap())
		if i < 4:
			phases.append(PlanPhase.erg(Wl.RECOVERY, 50, 180).with_lap())
	_ok(_plan(phases))


func test_120_accrual() -> void:
	_rejected(
		_plan(
			[
				_warmup(),
				PlanPhase.erg(Wl.WORK, 125, 40),
				PlanPhase.erg(Wl.WORK, 100, 30),
				PlanPhase.erg(Wl.WORK, 125, 30),
			]
		),
		"accrued above 120%"
	)
	_ok(
		_plan(
			[
				_warmup(),
				PlanPhase.erg(Wl.WORK, 125, 30),
				PlanPhase.erg(Wl.WORK, 100, 30),
				PlanPhase.erg(Wl.WORK, 125, 30),
			]
		)
	)


func test_open_ended_accrual_at_max_s_and_reset_at_min_s() -> void:
	var fight := func() -> PlanPhase:
		return PlanPhase.erg(Wl.WORK, 110, 0, "Fight").with_open(60, 200)
	_rejected(
		_plan(
			[
				_warmup(),
				fight.call(),
				PlanPhase.erg(Wl.RECOVERY, 50, 0, "Reel").with_open(100, 400),
				fight.call()
			]
		),
		"accrued above 105%"
	)
	_ok(
		_plan(
			[
				_warmup(),
				fight.call(),
				PlanPhase.erg(Wl.RECOVERY, 50, 0, "Reel").with_open(120, 400),
				fight.call()
			]
		)
	)


func test_sim_phase_restarts_the_reset_count() -> void:
	_rejected(
		_plan(
			[
				_warmup(),
				PlanPhase.erg(Wl.WORK, 110, 200),
				PlanPhase.erg(Wl.RECOVERY, 50, 60),
				PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, 40),
				PlanPhase.erg(Wl.RECOVERY, 50, 60),
				PlanPhase.erg(Wl.WORK, 110, 200),
			]
		),
		"accrued above 105%"
	)


func test_ramp_test_skips_caps_but_not_warmup() -> void:
	var ramp := _plan([_warmup(), PlanPhase.erg(Wl.WORK, 60, 600).with_ramp(160)])
	_rejected(ramp, "longer than 300 s")
	_ok(ramp, {"ramp_test": true})
	_rejected(_plan([PlanPhase.erg(Wl.WORK, 80, 60)]), "warm-up", {"ramp_test": true})


func test_mode_switch_warning_pl18() -> void:
	var res := _ok(
		_plan(
			[
				_warmup(),
				PlanPhase.erg(Wl.WORK, 80, 60),
				PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, 20),
				PlanPhase.erg(Wl.WORK, 80, 60)
			]
		)
	)
	assert_eq((res["warnings"] as Array).size(), 1)
	assert_string_contains(str(res["warnings"][0]), "20 s apart")
	# Exactly 30 s: no warning (Fishing's Fight, Landing, Reel).
	res = _ok(
		_plan(
			[
				_warmup(),
				PlanPhase.erg(Wl.WORK, 80, 0, "Fight").with_range(70, 95).with_open(60, 240),
				PlanPhase.sim(Wl.WORK, Wl.GRADE_FLAT, 30, "Landing"),
				PlanPhase.erg(Wl.RECOVERY, 60, 0, "Reel").with_open(120, 300)
			]
		)
	)
	assert_eq(res["warnings"], [])
	# Open-ended phases count at min_s.
	res = _ok(
		_plan(
			[
				_warmup(),
				PlanPhase.sim(Wl.FREE, Wl.GRADE_GAME, 60).with_open(20, 120),
				PlanPhase.erg(Wl.WORK, 70, 60)
			]
		)
	)
	assert_eq((res["warnings"] as Array).size(), 1)
	# The switch into the appended cool-down counts.
	res = _ok(_plan([_warmup(), PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, 20)]))
	assert_eq((res["warnings"] as Array).size(), 1)


func test_structural_errors() -> void:
	var bad_kind := PlanPhase.erg("SPRINT", 50, 60)
	_rejected(_plan([bad_kind]), "unknown kind")
	var bad_mode := PlanPhase.erg(Wl.WORK, 50, 60)
	bad_mode.mode = "RESISTANCE"
	_rejected(_plan([bad_mode]), "unknown mode")
	_rejected(_plan([PlanPhase.erg(Wl.WARMUP, 50, 0)]), "duration_s must be > 0")
	_rejected(_plan([PlanPhase.erg(Wl.WARMUP, -5, 60)]), "target_pct")
	_rejected(_plan([PlanPhase.erg(Wl.WARMUP, 50, 60).with_range(60, 55)]), "range_pct")
	_rejected(_plan([PlanPhase.erg(Wl.WARMUP, 50, 60).with_open(0, 30)]), "open_ended")
	_rejected(_plan([PlanPhase.erg(Wl.WARMUP, 50, 60).with_open(90, 30)]), "open_ended")
	_rejected(
		_plan([PlanPhase.erg(Wl.WARMUP, 50, 0).with_ramp(60).with_open(60, 120)]),
		"a ramp needs duration_s > 0"
	)
	_rejected(_plan([PlanPhase.sim(Wl.WARMUP, Wl.GRADE_COURSE, 60)]), "course_profile")
	_rejected(
		_plan([PlanPhase.sim(Wl.WARMUP, Wl.GRADE_FLAT, 60).with_course([[0, 1], [0, 2]])]),
		"course_profile[1]"
	)
	_rejected(_plan([PlanPhase.sim(Wl.WARMUP, "hilly", 60)]), "grade_source")


func test_open_ended_with_zero_nominal_duration_is_valid_c15() -> void:
	_ok(_plan([_warmup(), PlanPhase.erg(Wl.WORK, 80, 0, "Reel").with_open(120, 240)]))
	_ok(
		_plan(
			[
				_warmup(),
				PlanPhase.sim(Wl.WORK, Wl.GRADE_COURSE, 120).with_course([[0, 0], [500, 3]])
			]
		)
	)


func test_error_names_the_phase_and_label() -> void:
	var res := PlanValidator.validate(_plan([PlanPhase.erg(Wl.WARMUP, 80, 60, "Wave 1")]))
	assert_string_contains(str(res["errors"][0]), "phase 0 (Wave 1)")


func test_spliced_keeps_the_head_and_drops_the_cooldown() -> void:
	var cur := PlanValidator.finalize(
		_plan([_warmup(), PlanPhase.erg(Wl.WORK, 70, 60, "A"), PlanPhase.erg(Wl.WORK, 70, 60, "B")])
	)
	var rest := _plan([PlanPhase.erg(Wl.WORK, 80, 90, "C")])
	var s := PlanValidator.spliced(cur, 1, rest)
	assert_eq(s.size(), 3)
	assert_eq(s.phase(1).label, "A")
	assert_eq(s.phase(2).label, "C")
	assert_false(s.cooldown_appended)


func test_validation_is_pure_and_fast_enough() -> void:
	var plan := _plan(
		[_warmup(), PlanPhase.erg(Wl.WORK, 104, 0).with_range(80, 104).with_open(120, 600)]
	)
	var before := JSON.stringify(plan.to_dict())
	for i in 2000:
		PlanValidator.validate(plan)
	assert_eq(JSON.stringify(plan.to_dict()), before)
