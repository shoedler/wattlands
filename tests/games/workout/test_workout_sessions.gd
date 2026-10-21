extends GutTest
## Workout's built-in sessions against BRIEF 3.7's table: phase kinds, modes, targets,
## ramps, durations, laps and labels, totals with the platform's 3-minute cool-down, the
## warm-up opening, e2e inside the warm-up limits with its switches 30 s apart, and the
## 4.6.1 rules the table relies on.

const U := preload("res://tests/games/workout/workout_test_util.gd")
const BUILT_IN: Array[String] = ["easy_30", "sweet_spot", "threshold", "vo2", "rolling_road", "e2e"]
## content id -> total minutes including the cool-down (BRIEF 3.7).
const TOTAL_MIN := {
	"easy_30": 28.0,
	"sweet_spot": 36.0,
	"threshold": 40.0,
	"vo2": 35.0,
	"rolling_road": 38.0,
	"e2e": 5.0
}


func _load(id: String) -> WorkoutSession:
	var s := WorkoutSession.load_id(id)
	assert_not_null(s, "%s loads" % id)
	return s


## [kind, mode, target, ramp (-1 none), duration_s] per phase.
func _rows(s: WorkoutSession) -> Array:
	var out: Array = []
	for p in s.phases:
		out.append(
			[
				p.kind,
				p.mode,
				p.target_pct if p.mode == Wl.ERG else -1.0,
				p.ramp_to_pct if p.has_ramp() else -1.0,
				p.duration_s
			]
		)
	return out


func test_every_session_loads_with_laps_and_labels() -> void:
	for id in BUILT_IN:
		var s := _load(id)
		if s == null:
			continue
		assert_eq(s.id, id)
		assert_false(s.phases.is_empty(), "%s has phases" % id)
		for p in s.phases:
			assert_true(p.lap, "%s %s has lap = true" % [id, p.label])
			assert_true(
				p.label.begins_with("WORKOUT_LBL_"),
				"%s phase label is a strings key: %s" % [id, p.label]
			)
			assert_ne(p.kind, Wl.COOLDOWN, "%s never writes a cool-down" % id)
			assert_false(p.open_ended, "%s phases are fixed" % id)


func test_totals_include_the_platform_cooldown() -> void:
	for id in BUILT_IN:
		var s := _load(id)
		if s == null:
			continue
		assert_almost_eq(
			s.total_with_cooldown_s(), float(TOTAL_MIN[id]) * 60.0, 0.001, "%s total" % id
		)
		var tl := s.timeline()
		assert_eq(tl.back().kind, Wl.COOLDOWN, "%s timeline ends with the cool-down" % id)
		assert_eq(tl.back().duration_s, 180.0)
		assert_eq(tl.back().target_pct, 50.0)


func test_sessions_open_with_the_warmup_ramp_except_e2e() -> void:
	for id in BUILT_IN:
		var s := _load(id)
		if s == null or id == "e2e":
			continue
		var w := s.phases[0]
		assert_eq(
			[w.kind, w.mode, w.target_pct, w.ramp_to_pct, w.duration_s],
			[Wl.WARMUP, Wl.ERG, 50.0, 65.0, 300.0],
			"%s warm-up" % id
		)


func test_easy_30_table() -> void:
	var s := _load("easy_30")
	assert_eq(
		_rows(s),
		[
			[Wl.WARMUP, Wl.ERG, 50.0, 65.0, 300.0],
			[Wl.WORK, Wl.ERG, 65.0, -1.0, 360.0],
			[Wl.FREE, Wl.SIM, -1.0, -1.0, 30.0],
			[Wl.WORK, Wl.ERG, 65.0, -1.0, 330.0],
			[Wl.FREE, Wl.SIM, -1.0, -1.0, 30.0],
			[Wl.WORK, Wl.ERG, 65.0, -1.0, 330.0],
			[Wl.FREE, Wl.SIM, -1.0, -1.0, 30.0],
			[Wl.WORK, Wl.ERG, 65.0, -1.0, 90.0],
		]
	)
	# Sprints at minutes 6, 12 and 18 of the 20-minute main set.
	var main_start := 300.0
	var sprint_starts: Array[float] = []
	for i in s.phases.size():
		if s.phases[i].kind == Wl.FREE:
			sprint_starts.append((s.start_s(i) - main_start) / 60.0)
			assert_eq(s.phases[i].grade_source, Wl.GRADE_FLAT, "sprints ride SIM flat")
	assert_eq(sprint_starts, [6.0, 12.0, 18.0])
	assert_eq(s.total_s() - main_start, 1200.0, "20-minute main set")


func test_sweet_spot_table() -> void:
	assert_eq(
		_rows(_load("sweet_spot")),
		[
			[Wl.WARMUP, Wl.ERG, 50.0, 65.0, 300.0],
			[Wl.WORK, Wl.ERG, 90.0, -1.0, 720.0],
			[Wl.RECOVERY, Wl.ERG, 55.0, -1.0, 240.0],
			[Wl.WORK, Wl.ERG, 90.0, -1.0, 720.0],
		]
	)


func test_threshold_table() -> void:
	assert_eq(
		_rows(_load("threshold")),
		[
			[Wl.WARMUP, Wl.ERG, 50.0, 65.0, 300.0],
			[Wl.WORK, Wl.ERG, 98.0, -1.0, 480.0],
			[Wl.RECOVERY, Wl.ERG, 55.0, -1.0, 240.0],
			[Wl.WORK, Wl.ERG, 98.0, -1.0, 480.0],
			[Wl.RECOVERY, Wl.ERG, 55.0, -1.0, 240.0],
			[Wl.WORK, Wl.ERG, 98.0, -1.0, 480.0],
		]
	)


func test_vo2_table() -> void:
	var expected: Array = [[Wl.WARMUP, Wl.ERG, 50.0, 65.0, 300.0]]
	for i in 5:
		expected.append([Wl.WORK, Wl.ERG, 110.0, -1.0, 180.0])
		if i < 4:
			expected.append([Wl.RECOVERY, Wl.ERG, 50.0, -1.0, 180.0])
	assert_eq(_rows(_load("vo2")), expected)


func test_rolling_road_table() -> void:
	var s := _load("rolling_road")
	assert_eq(
		_rows(s),
		[
			[Wl.WARMUP, Wl.ERG, 50.0, 65.0, 300.0],
			[Wl.WORK, Wl.SIM, -1.0, -1.0, 1800.0],
		]
	)
	var road := s.phases[1]
	assert_eq(road.grade_source, Wl.GRADE_COURSE)
	assert_false(road.course_profile.is_empty(), "the course travels in the plan")
	assert_eq(s.band_pct, [76.0, 105.0])
	assert_not_null(s.course)
	assert_eq(road.course_profile, s.course.to_course_profile())


func test_e2e_table_and_warmup_limits() -> void:
	var s := _load("e2e")
	assert_eq(
		_rows(s),
		[
			[Wl.WARMUP, Wl.ERG, 50.0, 60.0, 60.0],
			[Wl.WORK, Wl.ERG, 65.0, -1.0, 30.0],
			[Wl.FREE, Wl.SIM, -1.0, -1.0, 30.0],
		]
	)
	assert_eq(s.phases[2].grade_source, Wl.GRADE_FLAT)
	assert_true(s.warmup_only)
	assert_eq(s.total_s(), 120.0, "2 minutes before the cool-down")
	for p in s.phases:
		if p.mode == Wl.ERG:
			assert_lte(p.peak_pct(), 65.0, "every e2e target <= 65% FTP")
	assert_lte(s.total_s(), 300.0, "all inside the first 300 s")
	var switches := _switch_times(s)
	assert_eq(switches, [90.0, 120.0], "ERG->SIM at 90 s, SIM->ERG (cool-down) at 120 s")
	assert_true(switches[1] - switches[0] >= 30.0, "the two switches are 30 s apart (no warning)")


## Plan times of every ERG<->SIM switch, the appended cool-down included.
func _switch_times(s: WorkoutSession) -> Array:
	var out: Array = []
	var tl := s.timeline()
	var t := 0.0
	for i in tl.size():
		if i > 0 and tl[i].mode != tl[i - 1].mode:
			out.append(t)
		t += tl[i].duration_s
	return out


func test_no_session_has_switches_closer_than_30_s() -> void:
	for id in BUILT_IN:
		var s := _load(id)
		if s == null:
			continue
		var sw := _switch_times(s)
		for i in range(1, sw.size()):
			assert_true(
				float(sw[i]) - float(sw[i - 1]) >= 30.0,
				"%s switches at %s and %s" % [id, sw[i - 1], sw[i]]
			)


func test_safety_rules_the_table_relies_on() -> void:
	for id in BUILT_IN:
		var s := _load(id)
		if s == null:
			continue
		var accrued_105 := 0.0
		var reset_run := 0.0
		for p in s.phases:
			if p.mode != Wl.ERG:
				reset_run = 0.0
				continue
			assert_lte(p.peak_pct(), 150.0, "%s %s <= 150%%" % [id, p.label])
			if p.duration_s > 300.0:
				assert_lte(
					p.peak_pct(), 105.0, "%s %s: phases > 300 s cap at 105%%" % [id, p.label]
				)
			if p.peak_pct() > 105.0:
				accrued_105 += p.duration_s
				reset_run = 0.0
				assert_lte(accrued_105, 300.0, "%s: <= 300 s above 105%% before a reset" % id)
				assert_lte(p.duration_s, 60.0 if p.peak_pct() > 120.0 else 300.0)
			elif p.peak_pct() <= 90.0:
				reset_run += p.duration_s
				if reset_run >= 120.0:
					accrued_105 = 0.0
		# Warm-up: the first 300 s stay <= 65% FTP.
		var t := 0.0
		for p in s.phases:
			if t < 300.0 and p.mode == Wl.ERG:
				assert_lte(p.peak_pct(), 65.0, "%s %s starts inside the warm-up" % [id, p.label])
			t += p.duration_s


func test_vo2_recoveries_reset_the_105_limit() -> void:
	var s := _load("vo2")
	for i in s.phases.size():
		var p := s.phases[i]
		if p.kind == Wl.RECOVERY:
			assert_lte(p.target_pct, 90.0)
			assert_true(p.duration_s >= 120.0, "each recovery resets the duration limits")


func test_build_plan_gives_fresh_phases() -> void:
	var s := _load("sweet_spot")
	var a := s.build_plan()
	var b := s.build_plan()
	assert_eq(a.size(), s.phases.size())
	assert_ne(a.phases[0], b.phases[0], "each rider gets its own PlanPhase objects")
	assert_eq(a.to_dict(), b.to_dict())
	assert_false(a.cooldown_appended, "the PlanValidator appends the cool-down")
	a.phases[1].target_pct = 10.0
	assert_eq(s.phases[1].target_pct, 90.0, "changing a plan never changes the session")


func test_rider_plans_are_percent_of_ftp() -> void:
	var g := U.game("threshold", U.players(2, 1))
	var plans := g.build_effort_plans()
	assert_eq(plans.size(), 3, "a plan for every rider, bots included")
	for peer: int in [1, 2, -1]:
		assert_true(plans.has(peer))
		assert_eq((plans[peer] as EffortPlan).phases[1].target_pct, 98.0)
	g.free()


func test_session_preview_lines_and_total() -> void:
	var s := _load("vo2")
	var pv := s.preview()
	assert_eq(float(pv["total_s"]), 35.0 * 60.0)
	assert_eq((pv["lines"] as Array).size(), s.phases.size())
	assert_string_contains(str(pv["lines"][0]), "5:00")
	var g := WorkoutGame.new()
	assert_eq(g.session_preview("vo2"), pv, "GameModule.session_preview works before configure")
	g.free()
