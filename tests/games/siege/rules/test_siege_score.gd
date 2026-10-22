extends GutTest
## Score, grade and XP (brief 2.8): the three parts, the band edges and the XP formula.

var _c: SiegeContent


func before_each() -> void:
	_c = SiegeFakes.content("short")


func _state(
	fracs: Array, breaches: int = 0, earned: float = 0.0, planned: float = 0.0
) -> SiegeState:
	var s := SiegeState.create(
		_c, SiegeFakes.make_slots(1), Wl.FAIR_FTP, RandomNumberGenerator.new()
	)
	for f: float in fracs:
		s.wave_gate_frac.append(f)
	s.breaches = breaches
	s.team_earned = earned
	s.planned_kj = planned
	return s


func test_the_gate_part_is_40_times_the_mean_of_hp_over_max_at_each_wave_end() -> void:
	var sc := SiegeScore.compute(_state([1.0, 0.5, 0.75]))
	assert_almost_eq(float(sc["gate"]), 40.0 * 0.75, 1e-9)
	assert_almost_eq(float(SiegeScore.compute(_state([1.0]))["gate"]), 40.0, 1e-9)
	assert_almost_eq(float(SiegeScore.compute(_state([0.0, 0.0]))["gate"]), 0.0, 1e-9)


func test_with_no_wave_ended_yet_the_gate_now_counts() -> void:
	var s := _state([])
	s.gate_hp = 50.0
	assert_almost_eq(float(SiegeScore.compute(s)["gate"]), 20.0, 1e-9)


func test_the_breach_part_is_30_minus_15_per_breach_not_below_zero() -> void:
	var want := [30.0, 15.0, 0.0, 0.0, 0.0]
	for n in 5:
		assert_almost_eq(float(SiegeScore.compute(_state([1.0], n))["breaches"]), want[n], 1e-9)


func test_earnings_are_30_times_the_share_of_par_capped_at_one() -> void:
	# par = 0.75 x planned kJ
	var sc := SiegeScore.compute(_state([1.0], 0, 30.0, 80.0))
	assert_almost_eq(float(sc["par"]), 60.0, 1e-9)
	assert_almost_eq(float(sc["earnings"]), 15.0, 1e-9)
	assert_almost_eq(
		float(SiegeScore.compute(_state([1.0], 0, 60.0, 80.0))["earnings"]), 30.0, 1e-9
	)
	assert_almost_eq(
		float(SiegeScore.compute(_state([1.0], 0, 600.0, 80.0))["earnings"]), 30.0, 1e-9
	)
	assert_eq(float(SiegeScore.compute(_state([1.0], 0, 10.0, 0.0))["earnings"]), 0.0, "no par: 0")


func test_the_score_is_the_sum_and_a_perfect_run_is_100() -> void:
	var sc := SiegeScore.compute(_state([1.0, 1.0], 0, 100.0, 100.0))
	assert_almost_eq(float(sc["score"]), 100.0, 1e-9)
	assert_eq(sc["grade"], "S")
	var mid := SiegeScore.compute(_state([0.5, 0.5], 1, 30.0, 80.0))
	assert_almost_eq(float(mid["score"]), 20.0 + 15.0 + 15.0, 1e-9)
	assert_eq(mid["grade"], "C")


func test_grade_band_edges() -> void:
	var edges := {90.0: "S", 78.0: "A", 64.0: "B", 48.0: "C"}
	var below := {90.0: "A", 78.0: "B", 64.0: "C", 48.0: "D"}
	for e: float in edges:
		assert_eq(SiegeScore.grade(_c, e), edges[e], "%s is %s" % [e, edges[e]])
		assert_eq(SiegeScore.grade(_c, e + 5.0), edges[e] if e != 90.0 else "S")
		assert_eq(SiegeScore.grade(_c, e - 0.001), below[e], "just under %s" % e)
	assert_eq(SiegeScore.grade(_c, 100.0), "S")
	assert_eq(SiegeScore.grade(_c, 0.0), "D")
	assert_eq(SiegeScore.grade(_c, 47.999), "D")


func test_xp_is_kj_over_ten_plus_the_grade_bonus() -> void:
	var bonus := {"S": 60, "A": 40, "B": 25, "C": 10, "D": 0}
	for g: String in bonus:
		assert_eq(SiegeScore.xp(_c, 0.0, g), bonus[g])
		assert_eq(SiegeScore.xp(_c, 123.0, g), 12 + int(bonus[g]))
	assert_eq(SiegeScore.xp(_c, 124.9, "D"), 12)
	assert_eq(SiegeScore.xp(_c, 125.1, "D"), 13)
	assert_eq(SiegeScore.xp(_c, 500.0, "A"), 50 + 40)


func test_the_numbers_live_in_the_balance_file() -> void:
	assert_eq(_c.num("score.gate_pts"), 40.0)
	assert_eq(_c.num("score.breach_pts"), 30.0)
	assert_eq(_c.num("score.breach_cost"), 15.0)
	assert_eq(_c.num("score.earn_pts"), 30.0)
	assert_eq(_c.num("score.par_frac"), 0.75)
	assert_eq(_c.num("xp.kj_per_xp"), 10.0)
	assert_eq(
		[
			_c.num("score.grades.S"),
			_c.num("score.grades.A"),
			_c.num("score.grades.B"),
			_c.num("score.grades.C")
		],
		[90.0, 78.0, 64.0, 48.0]
	)
