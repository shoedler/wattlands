extends GutTest
## Rolling road's procedural course (BRIEF 3.7): grade -2% to +6%, seeded from the content,
## long enough for 30 minutes at any realistic speed.

const SPEC := {"seed": 7342, "length_m": 50000.0, "step_m": 250.0, "min_grade_pct": -2.0, "max_grade_pct": 6.0}


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
	assert_eq(s.phases[1].course_profile, WorkoutCourse.from_spec(SPEC).profile)
