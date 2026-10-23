extends GutTest
## Score, grade, XP and unlocks (brief 2.8) and the per-rider counters results() reads.


func _state(crew: int = 1) -> TankState:
	return TankFixtures.state(crew)


func _score(s: TankState) -> Dictionary:
	return TankScore.summary(s)


func _reset(s: TankState) -> void:
	for r in s.riders:
		r.work_s = 0.0
		r.band_s = 0.0
	s.score.hits = 0
	s.score.shots = 0
	s.score.stages_clean = 0
	s.score.behemoth_killed = false
	s.score.breakdowns = 0


func test_the_score_is_1000_x_the_weighted_sum() -> void:
	var s := _state(1)
	_reset(s)
	s.riders[0].work_s = 200.0
	s.riders[0].band_s = 150.0
	s.score.shots = 10
	s.score.hits = 8
	s.score.stages_clean = 2
	s.score.behemoth_killed = true
	s.score.breakdowns = 1
	var r := _score(s)
	assert_almost_eq(r["band"], 0.75, 1e-9)
	assert_almost_eq(r["accuracy"], 0.8, 1e-9)
	assert_almost_eq(r["objectives"], 0.6 * 2.0 / 3.0 + 0.4, 1e-9)
	assert_almost_eq(r["survival"], 0.75, 1e-9)
	var want := 1000.0 * (0.3 * 0.75 + 0.2 * 0.8 + 0.3 * (0.4 + 0.4) + 0.2 * 0.75)
	assert_almost_eq(r["score"], want, 1e-6)
	assert_eq(r["grade"], "B")


func test_band_is_the_crew_mean_of_each_riders_work_time_in_band() -> void:
	var s := _state(3)
	_reset(s)
	s.riders[0].work_s = 100.0
	s.riders[0].band_s = 100.0
	s.riders[1].work_s = 400.0
	s.riders[1].band_s = 0.0
	s.riders[2].work_s = 200.0
	s.riders[2].band_s = 100.0
	assert_almost_eq(
		_score(s)["band"], (1.0 + 0.0 + 0.5) / 3.0, 1e-9, "a mean of ratios, not of seconds"
	)


func test_band_is_zero_with_no_work_time() -> void:
	var s := _state(2)
	_reset(s)
	assert_eq(_score(s)["band"], 0.0)


func test_accuracy_is_zero_without_a_shot() -> void:
	var s := _state(1)
	_reset(s)
	assert_eq(_score(s)["accuracy"], 0.0)
	s.score.shots = 4
	s.score.hits = 4
	assert_eq(_score(s)["accuracy"], 1.0)


func test_objectives_are_three_fifths_over_clean_stages_plus_two_fifths_for_the_behemoth() -> void:
	var s := _state(1)
	_reset(s)
	for clean in 4:
		s.score.stages_clean = clean
		var want := 0.6 * minf(float(clean), 3.0) / 3.0
		assert_almost_eq(_score(s)["objectives"], want, 1e-9, "%d clean stages" % clean)
	s.score.stages_clean = 3
	s.score.behemoth_killed = true
	assert_almost_eq(_score(s)["objectives"], 1.0, 1e-9)


func test_survival_loses_a_quarter_per_breakdown_and_floors_at_zero() -> void:
	var s := _state(1)
	_reset(s)
	for n in 6:
		s.score.breakdowns = n
		assert_almost_eq(_score(s)["survival"], maxf(0.0, 1.0 - 0.25 * n), 1e-9)


func test_the_grade_thresholds() -> void:
	var c := TankFixtures.content()
	for row: Array in [
		[1000.0, "S"],
		[900.0, "S"],
		[899.9, "A"],
		[800.0, "A"],
		[799.9, "B"],
		[650.0, "B"],
		[649.9, "C"],
		[500.0, "C"],
		[499.9, "D"],
		[0.0, "D"]
	]:
		assert_eq(TankScore.grade_of(c, float(row[0])), row[1], "score %s" % row[0])


func test_a_perfect_run_scores_1000_an_empty_one_200_for_survival_alone() -> void:
	var s := _state(1)
	_reset(s)
	s.riders[0].work_s = 100.0
	s.riders[0].band_s = 100.0
	s.score.shots = 5
	s.score.hits = 5
	s.score.stages_clean = 3
	s.score.behemoth_killed = true
	assert_almost_eq(_score(s)["score"], 1000.0, 1e-6)
	assert_eq(_score(s)["grade"], "S")
	_reset(s)
	assert_almost_eq(_score(s)["score"], 200.0, 1e-6)
	assert_eq(_score(s)["grade"], "D")


func test_xp_is_a_tenth_of_the_kilojoules_plus_the_grade_bonus() -> void:
	var c := TankFixtures.content()
	var bonus := {"S": 60, "A": 40, "B": 25, "C": 10, "D": 0}
	for g: String in bonus:
		assert_eq(TankScore.xp(c, 420.0, g), 42 + int(bonus[g]), g)
	assert_eq(TankScore.xp(c, 0.0, "D"), 0)
	assert_eq(TankScore.xp(c, 14.0, "D"), 1, "rounded")
	assert_eq(TankScore.xp(c, 14.9, "D"), 1)
	assert_eq(TankScore.xp(c, 15.1, "D"), 2)


func test_unlocks_by_finish_grade_and_a_clean_behemoth_kill() -> void:
	var s := _state(1)
	_reset(s)
	assert_eq(TankScore.unlocks(s, "D", true), ["soot"] as Array[String], "any finish")
	assert_eq(TankScore.unlocks(s, "C", true), ["soot"] as Array[String])
	assert_eq(TankScore.unlocks(s, "B", true), ["soot", "rust"] as Array[String])
	assert_eq(TankScore.unlocks(s, "A", true), ["soot", "rust", "ash"] as Array[String])
	assert_eq(
		TankScore.unlocks(s, "S", true), ["soot", "rust", "ash", "mud_stripe"] as Array[String]
	)
	assert_eq(
		TankScore.unlocks(s, "S", false), [] as Array[String], "a run cut short earns nothing"
	)
	s.score.behemoth_killed = true
	assert_has(TankScore.unlocks(s, "D", true), "brass_machinery")
	s.score.breakdowns = 1
	assert_does_not_have(
		TankScore.unlocks(s, "D", true), "brass_machinery", "a breakdown spoils the brass"
	)


# --- Counters from a played session -----------------------------------------------------------------


func test_work_time_and_band_time_count_only_in_work_phases() -> void:
	var rig := TankRig.new(1)
	rig.enter(0, 10.0)
	rig.run(20.0)
	assert_eq(rig.rider().work_s, 0.0, "the depot is a warm-up")
	rig.enter(1, 5.0)
	rig.no_fire = true
	rig.run(40.0)
	assert_almost_eq(rig.rider().work_s, 40.05, 0.1)
	assert_almost_eq(rig.rider().band_s, rig.rider().work_s, 0.1, "90% FTP is in the 76-105% band")
	rig.power_w[1] = 100.0
	rig.run(10.0)
	assert_almost_eq(rig.rider().work_s, 50.05, 0.1)
	assert_almost_eq(rig.rider().band_s, 40.05, 0.15, "50% FTP is out of band")
	rig.enter(3, 0.0)
	var w := rig.rider().work_s
	rig.run(10.0)
	assert_eq(rig.rider().work_s, w, "checkpoints are recovery")


func test_time_per_engine_follows_the_rotation() -> void:
	var rig := TankRig.new(2)
	rig.no_fire = true
	rig.enter(1, 0.0)
	rig.run(10.0)
	rig.enter(4, 0.0)
	rig.run(10.0)
	var r0 := rig.rider(1)
	assert_almost_eq(r0.engine_s[0], 10.05, 0.15, "diesel in stage 1")
	assert_almost_eq(r0.engine_s[1], 10.05, 0.15, "dynamo in stage 2")
	assert_eq(r0.engine_s[2], 0.0)
	var bul := TankRig.new(1)
	bul.no_fire = true
	bul.enter(1, 0.0)
	bul.run(10.0)
	assert_almost_eq(bul.rider().engine_s[3], 10.05, 0.15)


func test_the_per_rider_shell_counters_by_type() -> void:
	var rig := TankRig.new(2)
	rig.enter(3, 5.0)
	var g := rig.peer_of(TankIds.ENGINE_DYNAMO)
	rig.hull().aim_pause_s = 99.0
	for t in [TankIds.SHELL_LIGHT, TankIds.SHELL_HEAVY, TankIds.SHELL_HEAVY, TankIds.SHELL_OVER]:
		rig.load_shell(t)
		rig.send(g, {"k": "fire"})
		rig.run(0.05)
	var r := rig.rider(g)
	assert_eq(r.shots, 4)
	assert_eq(r.shells_by_type, [1, 2, 1, 0] as Array[int])
	assert_eq(rig.state.score.shots, 4)
