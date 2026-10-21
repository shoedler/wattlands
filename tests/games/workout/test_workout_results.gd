extends GutTest
## Results (BRIEF 3.7): per rider and interval time in band, kJ, average and normalized
## power, best 1/5/20-minute power, sprint peaks, a grade from the session's time in band
## (S >= 95%, A >= 90%, B >= 80%, C >= 65%, else D), XP, and progression.

const U := preload("res://tests/games/workout/workout_test_util.gd")

var _tmp: String = ""


func before_each() -> void:
	_tmp = Paths.make_temp_dir("workout_results")
	Paths.set_override(_tmp)


func after_each() -> void:
	Paths.set_override("")


## A game whose riders all sit at `fraction` time in band (set directly on the state).
func _graded(fraction: float) -> GameResults:
	var g := U.game("sweet_spot", U.players(2))
	for peer: int in g.state.order:
		var r := g.state.rider(peer)
		r.ride_s = 1000.0
		r.tib_s = 1000.0 * fraction
	var res := g.results()
	g.free()
	return res


func test_grade_band_edges() -> void:
	var cases := [[1.0, "S"], [0.95, "S"], [0.9499, "A"], [0.90, "A"], [0.8999, "B"], [0.80, "B"], [0.7999, "C"], [0.65, "C"], [0.6499, "D"], [0.0, "D"]]
	for c: Array in cases:
		assert_eq(_graded(float(c[0])).grade, str(c[1]), "%s in band" % c[0])


func test_group_grade_is_the_average_time_in_band() -> void:
	var g := U.game("sweet_spot", U.players(2))
	var a := g.state.rider(1)
	var b := g.state.rider(2)
	a.ride_s = 100.0
	a.tib_s = 100.0
	b.ride_s = 100.0
	b.tib_s = 80.0
	var res := g.results()
	assert_eq(res.grade, "A", "(100% + 80%) / 2 = 90%")
	assert_almost_eq(res.score, 90.0, 0.001)
	assert_eq(res.row(1)["stats"][WorkoutResults.STAT_GRADE], "S")
	assert_eq(res.row(2)["stats"][WorkoutResults.STAT_GRADE], "B")
	assert_eq(res.summary_key, "WORKOUT_RESULT_A")
	assert_eq(res.team[WorkoutResults.TEAM_RIDERS], 2)
	g.free()


func test_rows_from_a_synthetic_ride() -> void:
	var players := U.players(1, 1, 200.0)
	var g := U.game("easy_30", players)
	var sloppy := func(slot: PlayerSlot, p: PlanPhase, ps: PhaseState, tick: int) -> Dictionary:
		var v := U.compliant(slot, p, ps)
		# The bot rides 20% under target in the second endurance block.
		if slot.is_bot and ps.index == 3:
			v["power_w"] = float(v["power_w"]) * 0.8
		return v
	U.ride(g, sloppy)
	var res := g.results()
	assert_eq(res.rows.size(), 2)
	var me := res.row(1)
	var bot := res.row(-1)
	assert_almost_eq(float(me["time_in_band_pct"]), 100.0, 0.01)
	assert_almost_eq(float(bot["time_in_band_pct"]), (1500.0 - 330.0) / 1500.0 * 100.0, 0.1)
	assert_almost_eq(float(bot["time_in_band_s"]), 1170.0, 0.1)
	# Intervals: 8 game phases, the cool-down excluded.
	var intervals: Array = me["intervals"]
	assert_eq(intervals.size(), 8)
	assert_eq(intervals[3]["label"], "WORKOUT_LBL_ENDURANCE_2")
	assert_almost_eq(float(bot["intervals"][3]["tib_pct"]), 0.0, 0.01)
	assert_almost_eq(float(bot["intervals"][1]["tib_pct"]), 100.0, 0.01)
	# Ride statistics come from Workout's own tracker when ctx.stats has none.
	# 300 s ramp at 100-130 W, 1110 s at 130 W, 3 sprints (10 s at 280 W, 20 s at 160 W),
	# 180 s cool-down at the ERG 50% the compliant rider follows.
	var expected_kj := (300.0 * 115.0 + 1110.0 * 130.0 + 3.0 * (10.0 * 280.0 + 20.0 * 160.0) + 180.0 * 100.0) / 1000.0
	assert_almost_eq(float(me["kj"]), expected_kj, 0.5)
	assert_almost_eq(float(me["ride_s"]), 1680.0, 0.01, "28 minutes including the cool-down")
	assert_gt(float(me["np_w"]), float(me["avg_power_w"]) - 0.001)
	assert_gt(float(me["best_1m_w"]), 130.0, "the sprints lift the best minute")
	assert_true(float(me["best_1m_w"]) >= float(me["best_5m_w"]) and float(me["best_5m_w"]) >= float(me["best_20m_w"]))
	assert_gt(float(me["best_20m_w"]), 0.0)
	assert_almost_eq(float(me["avg_ftp_pct"]), float(me["avg_power_w"]) / 2.0, 0.001)
	# Sprints and display stats.
	assert_eq((me["sprints"] as Array).size(), 3)
	assert_eq(me["sprints"][0]["label"], "WORKOUT_LBL_SPRINT_1")
	assert_eq(me["stats"][WorkoutResults.STAT_SPRINT_PEAK], 280)
	# W3 WO-2: the results screen draws row stats, so best powers and each sprint's peak go there.
	assert_eq(me["stats"][WorkoutResults.STAT_SPRINT_PEAKS], "280 / 280 / 280", "every sprint's peak")
	for key: String in WorkoutResults.BEST_STATS:
		assert_eq(me["stats"][WorkoutResults.BEST_STATS[key]], roundi(float(me[key])), key)
	assert_eq(me["stats"][WorkoutResults.STAT_SPRINTS_HIT], "3/3")
	assert_eq(me["xp"], WorkoutResults.xp_for(float(me["kj"]), 1.0, 3))
	assert_eq(res.team[WorkoutResults.TEAM_SPRINTS], 6)
	assert_true(me.has("unlocks") and me.has("name") and me.has("is_bot"))
	assert_eq(res.grade, GameResults.grade_from_fraction((1.0 + 1170.0 / 1500.0) / 2.0))
	g.free()


func test_platform_stats_win_when_present() -> void:
	var players := U.players(1)
	var c := U.ctx("e2e", players)
	var fixed := U.FixedStats.new()
	fixed.rows[1] = {"kj": 99.0, "np_w": 123.0}
	c.stats = fixed
	var g := WorkoutGame.new()
	g.configure(c)
	U.ride(g)
	var row := g.results().row(1)
	assert_eq(float(row["kj"]), 99.0, "ctx.stats kJ is used")
	assert_eq(float(row["np_w"]), 123.0)
	assert_gt(float(row["avg_power_w"]), 0.0, "missing values come from Workout's tracker")
	g.free()


func test_results_round_trip_as_json() -> void:
	var g := U.game("e2e", U.players(2, 1))
	U.ride(g)
	var res := g.results()
	var back := GameResults.from_dict(JSON.parse_string(JSON.stringify(res.to_dict())))
	assert_eq(back.grade, res.grade)
	assert_eq(back.rows.size(), 3)
	assert_eq((back.row(-1)["intervals"] as Array).size(), 3)
	g.free()


func test_apply_progress_totals_and_unlocks() -> void:
	var g := U.game("e2e", U.players(1))
	U.ride(g)
	var res := g.results()
	var store := ProgressStore.open("workout", Paths.progress_path("workout"))
	var first := g.apply_progress(res, store)
	assert_eq(first, ["pennant_swallowtail", "pennant_star"], "first ride and a grade S")
	assert_eq(store.get_value("rides"), 1.0)
	assert_eq(store.get_value("pennant"), "pennant_star")
	assert_eq(store.get_value("best_grade"), "S")
	assert_eq(store.get_value("level"), 1)
	assert_gt(float(store.get_value("kj_total")), 0.0)
	assert_eq(float(store.get_value("xp_total")), float(res.row(1)["xp"]))
	assert_true(store.save())
	var again := ProgressStore.open("workout", Paths.progress_path("workout"))
	assert_eq(again.get_value("unlocks"), ["pennant_swallowtail", "pennant_star"], "saved under Paths")
	for i in 3:
		g.apply_progress(res, again)
	var fifth := g.apply_progress(res, again)
	assert_eq(fifth, ["pennant_chevron"], "five rides")
	assert_eq(g.apply_progress(res, again), [], "nothing new")
	assert_eq(again.get_value("rides"), 6.0)
	g.free()


func test_apply_progress_for_an_unknown_rider_does_nothing() -> void:
	var store := ProgressStore.open("workout", "")
	assert_eq(WorkoutProgress.apply(GameResults.new(), store, 1), [])
	assert_false(store.has("rides"))
	assert_eq(WorkoutProgress.level_for(2500.0), 3)
	assert_eq(WorkoutProgress.equipped(store), "")


## W3 WO-2: a ride shorter than 20 minutes shows no best 20-minute power (it has none), but its
## best minute is on the results screen.
func test_best_power_stats_skip_windows_longer_than_the_ride() -> void:
	var g := U.game("e2e", U.players(1))
	U.ride(g)
	var row := g.results().row(1)
	var st: Dictionary = row["stats"]
	assert_eq(float(row["best_20m_w"]), 0.0, "precondition: a 5-minute ride has no 20-minute power")
	assert_false(st.has(WorkoutResults.BEST_STATS["best_20m_w"]), "no 20-minute stat")
	assert_eq(st[WorkoutResults.BEST_STATS["best_1m_w"]], roundi(float(row["best_1m_w"])))
	assert_gt(int(st[WorkoutResults.BEST_STATS["best_1m_w"]]), 0)
	g.free()
