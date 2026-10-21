extends GutTest
## Rolling road's procedural course (BRIEF 3.7): grade -2% to +6%, seeded from the content,
## long enough for 30 minutes at any realistic speed.

const SPEC := {
	"seed": 7342, "length_m": 50000.0, "step_m": 250.0, "min_grade_pct": -2.0, "max_grade_pct": 6.0
}


func test_same_seed_same_course() -> void:
	var a := WorkoutCourse.from_spec(SPEC)
	var b := WorkoutCourse.from_spec(SPEC)
	assert_eq(a.profile, b.profile)
	var other := SPEC.duplicate()
	other["seed"] = 99
	assert_ne(WorkoutCourse.from_spec(other).profile, a.profile, "the seed changes the road")


func test_grades_span_minus_2_to_plus_6() -> void:
	var c := WorkoutCourse.from_spec(SPEC)
	assert_almost_eq(c.min_grade(), -2.0, 0.001)
	assert_almost_eq(c.max_grade(), 6.0, 0.001)
	for pt: Array in c.profile:
		assert_true(float(pt[1]) >= -2.0 and float(pt[1]) <= 6.0)
		assert_almost_eq(float(pt[1]), snappedf(float(pt[1]), 0.1), 0.0001, "grades in 0.1% steps")


func test_profile_format_for_the_plan() -> void:
	var c := WorkoutCourse.from_spec(SPEC)
	assert_eq(float(c.profile[0][0]), 0.0, "starts at 0 m")
	for i in range(1, c.profile.size()):
		assert_almost_eq(float(c.profile[i][0]) - float(c.profile[i - 1][0]), 250.0, 0.001)
	assert_eq(float(c.profile.back()[0]), 50000.0)


func test_long_enough_for_30_minutes_at_any_realistic_speed() -> void:
	# Fastest realistic case: 1000 W of P_eff (RAW mode, a big rider) on the steepest descent.
	var v := SpeedModel.steady_state_speed(1000.0, -2.0, 120.0 + 8.0)
	var c := WorkoutCourse.from_spec(SPEC)
	assert_gt(c.length_m, v * 1800.0, "%.1f km/h for 30 min fits in %.0f m" % [v * 3.6, c.length_m])


func test_rolls_up_and_down() -> void:
	var c := WorkoutCourse.from_spec(SPEC)
	var climbs := 0
	var descents := 0
	for pt: Array in c.profile:
		if float(pt[1]) >= 4.0:
			climbs += 1
		elif float(pt[1]) <= 0.0:
			descents += 1
	assert_gt(climbs, 10, "real climbs")
	assert_gt(descents, 10, "real descents")


func test_grade_and_elevation_lookup() -> void:
	var c := WorkoutCourse.from_profile([[0.0, 2.0], [100.0, -1.0], [200.0, 4.0]])
	assert_eq(c.grade_at(0.0), 2.0)
	assert_eq(c.grade_at(99.9), 2.0)
	assert_eq(c.grade_at(100.0), -1.0)
	assert_eq(c.grade_at(5000.0), 4.0, "the last grade holds past the end")
	assert_eq(c.grade_at(-5.0), 2.0)
	assert_almost_eq(c.elevation_at(100.0), 2.0, 0.0001)
	assert_almost_eq(c.elevation_at(150.0), 1.5, 0.0001)
	assert_almost_eq(c.elevation_at(300.0), 5.0, 0.0001)


func test_spec_errors() -> void:
	assert_true(WorkoutCourse.spec_errors(SPEC).is_empty())
	assert_false(WorkoutCourse.spec_errors("x").is_empty())
	var bad := SPEC.duplicate()
	bad["max_grade_pct"] = 20.0
	assert_false(WorkoutCourse.spec_errors(bad).is_empty())
	var bad2 := SPEC.duplicate()
	bad2.erase("seed")
	assert_false(WorkoutCourse.spec_errors(bad2).is_empty())


func test_rolling_road_uses_the_content_course() -> void:
	var s := WorkoutSession.load_id("rolling_road")
	assert_not_null(s)
	assert_eq(s.course.seed, 7342)
	var spec := SPEC.duplicate()
	spec["window_m"] = 8000.0  # content/workout/sessions/rolling_road.json (W3 WO-3)
	assert_eq(s.phases[1].course_profile, WorkoutCourse.from_spec(spec).profile)


## W3 WO-3 (BRIEF 3.7 "grade -2% to +6%"): the road a rider actually rides in the 30-minute phase
## spans the full range. Rolling road's window_m (8 km) holds both extremes, and even a slow rider
## (120 W of P_eff, 50 % difficulty, the course grade halved) covers the window in 30 minutes.
func test_rolling_road_puts_both_extremes_within_every_riders_reach() -> void:
	var s := WorkoutSession.load_id("rolling_road")
	var c := s.course
	assert_eq(c.window_m, 8000.0)
	var lo := INF
	var hi := -INF
	for pt: Array in c.profile:
		if float(pt[0]) <= c.window_m:
			lo = minf(lo, float(pt[1]))
			hi = maxf(hi, float(pt[1]))
	assert_almost_eq(lo, -2.0, 0.001, "-2 %% within the first %.0f m" % c.window_m)
	assert_almost_eq(hi, 6.0, 0.001, "+6 %% within the first %.0f m" % c.window_m)
	var sm := SpeedModel.create(75.0)
	for i in roundi(1800.0 / Wl.SIM_DT):
		sm.step(Wl.SIM_DT, 120.0, 0.5 * c.grade_at(sm.distance_m))
	gutils_note("a 120 W rider covers %.0f m in 30 min" % sm.distance_m)
	assert_gt(sm.distance_m, c.window_m, "the slow rider rides past the whole window")
	# The rest of the 50 km repeats the window back and forth: same range, no jump at a seam.
	assert_almost_eq(c.min_grade(), -2.0, 0.001)
	assert_almost_eq(c.max_grade(), 6.0, 0.001)
	var w := roundi(c.window_m / c.step_m)
	var max_step := 0.0
	var window_step := 0.0
	for i in range(1, c.profile.size()):
		var step := absf(float(c.profile[i][1]) - float(c.profile[i - 1][1]))
		max_step = maxf(max_step, step)
		if i <= w:
			window_step = maxf(window_step, step)
	for seam in [w, 2 * w, 3 * w]:
		assert_eq(
			float(c.profile[seam + 1][1]),
			float(c.profile[seam - 1][1]),
			"mirrored at the seam %d" % seam
		)
	assert_almost_eq(
		max_step, window_step, 0.0001, "no seam adds a grade jump the window does not have"
	)
	assert_lte(
		window_step,
		2.0,
		"250 m steps change the grade by at most 2 %% (1 %% applied at 50 %% difficulty)"
	)


func test_window_m_spec_errors() -> void:
	var ok := SPEC.duplicate()
	ok["window_m"] = 8000.0
	assert_true(WorkoutCourse.spec_errors(ok).is_empty())
	for bad_w: float in [8100.0, 60000.0, 500.0]:
		var bad := SPEC.duplicate()
		bad["window_m"] = bad_w
		assert_false(WorkoutCourse.spec_errors(bad).is_empty(), "window_m %.0f" % bad_w)
	var no_window := WorkoutCourse.from_spec(SPEC)
	assert_eq(no_window.window_m, 50000.0, "without window_m the whole length is the window")


func gutils_note(s: String) -> void:
	gut.p(s)
