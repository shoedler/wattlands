extends GutTest
## FishingResults (brief 2.8, GAME_SDK 15): grade bands, rows and stats, XP, unlocks, the summary
## from the store and apply_progress, on hand-built FishingState data.

const F := preload("res://tests/games/fishing/fishing_fakes.gd")


func _game(humans: int = 2) -> FishingGame:
	return autofree(F.make_game(F.make_ctx(humans, 0, "e2e_2min")))


func _catch(sp: String, kg: float, grade: int, fight_s: float, points: int) -> Dictionary:
	return {
		"sp": FishingConst.species_index(sp),
		"kg": kg,
		"grade": grade,
		"fight_s": fight_s,
		"points": points
	}


## Lane 0: a trophy tuna and a mackerel, one lost line; lane 1: nothing.
func _fill(g: FishingGame) -> void:
	var st := g.state
	var a := st.lanes[0]
	a.catches = [
		_catch("tuna", 54.24, FishingConst.GRADE_TROPHY, 372.4, 220),
		_catch("mackerel", 1.5, FishingConst.GRADE_LANDED, 75.0, 24),
	]
	a.fish_landed = 2
	a.trophies = 1
	a.lost_lines = 1
	a.points = 244
	a.biggest_kg = 54.24
	a.biggest_sp = FishingConst.species_index("tuna")
	a.longest_fight_s = 372.4
	a.band_s = 300.0
	a.fight_total_s = 400.0
	a.records = {"tuna": 60.0}
	st.team_points = 244
	st.team_fish = 2
	st.fish_started = 3
	st.expected_points = 200.0


func _stats(rows: Dictionary) -> F.Stats:
	var s := F.Stats.new()
	s.rows = rows
	return s


func test_grade_bands_follow_points_over_expected() -> void:
	var st := FishingState.new()
	st.fish_started = 2
	st.expected_points = 100.0
	for case: Array in [
		[125, "S"], [124, "A"], [100, "A"], [99, "B"], [80, "B"], [79, "C"], [60, "C"], [59, "D"]
	]:
		st.team_points = int(case[0])
		assert_eq(FishingResults.grade_for(st), str(case[1]), "points %d" % case[0])


func test_no_started_fish_is_a_d() -> void:
	var st := FishingState.new()
	st.team_points = 500
	st.expected_points = 0.0
	st.fish_started = 0
	assert_eq(FishingResults.grade_for(st), "D")
	var g := _game(1)
	var res := FishingResults.build(g.state, _stats({}), g.ctx.players, g.content)
	assert_eq(res.grade, "D")


func test_rows_carry_band_stats_in_reading_order_and_team_values() -> void:
	var g := _game()
	_fill(g)
	var res := FishingResults.build(
		g.state,
		_stats({1: {"kj": 150.4}, 2: {"kj": 80.0}}),
		g.ctx.players,
		g.content,
		g.ctx.strings
	)
	assert_eq(res.grade, "A", "244 / 200 = 1.22")
	assert_eq(res.score, 244.0)
	assert_eq(res.summary_key, "FISHING_RESULTS")
	var row := res.row(1)
	assert_almost_eq(float(row["time_in_band_pct"]), 75.0, 0.001, "300 of 400 fight seconds")
	assert_almost_eq(float(row["time_in_band_s"]), 300.0, 0.001)
	assert_eq(
		(row["stats"] as Dictionary).keys(),
		[
			FishingResults.STAT_FISH,
			FishingResults.STAT_TROPHIES,
			FishingResults.STAT_LOST,
			FishingResults.STAT_BIGGEST,
			FishingResults.STAT_LONGEST,
			FishingResults.STAT_POINTS
		]
	)
	assert_eq(row["stats"][FishingResults.STAT_FISH], 2)
	assert_eq(row["stats"][FishingResults.STAT_TROPHIES], 1)
	assert_eq(row["stats"][FishingResults.STAT_LOST], 1)
	assert_string_ends_with(str(row["stats"][FishingResults.STAT_BIGGEST]), " 54.2 kg")
	assert_eq(row["stats"][FishingResults.STAT_LONGEST], "6:12")
	assert_eq(row["stats"][FishingResults.STAT_POINTS], 244)
	var other := res.row(2)
	assert_eq(other["time_in_band_pct"], 0.0, "no fight time: 0 %")
	assert_eq(other["stats"][FishingResults.STAT_BIGGEST], FishingResults.NONE_TEXT)
	assert_eq(other["stats"][FishingResults.STAT_LONGEST], FishingResults.NONE_TEXT)
	assert_eq(
		res.team,
		{
			FishingResults.TEAM_POINTS: 244,
			FishingResults.TEAM_FISH: 2,
			FishingResults.TEAM_TROPHIES: 1
		}
	)


func test_xp_counts_kj_fish_trophies_and_new_records() -> void:
	var g := _game()
	_fill(g)
	var res := FishingResults.build(
		g.state, _stats({1: {"kj": 150.4}, 2: {"kj": 80.0}}), g.ctx.players, g.content
	)
	# Tuna 54.2 kg stays under the 60 kg record; the mackerel is a first: one new record.
	assert_eq(res.row(1)["records"], {"mackerel": 1.5})
	assert_eq(res.row(1)["xp"], 150 + 2 * 10 + 25 + 50)
	assert_eq(res.row(2)["xp"], 80)
	assert_eq(FishingResults.xp_for(0.4, 0, 0, 0), 0)
	assert_eq(FishingResults.xp_for(10.0, 1, 1, 2), 10 + 10 + 25 + 100)


func test_catch_rows_are_json_safe() -> void:
	var g := _game()
	_fill(g)
	var res := FishingResults.build(g.state, _stats({}), g.ctx.players, g.content)
	var back := GameResults.from_dict(JSON.parse_string(JSON.stringify(res.to_dict())))
	assert_eq(
		back.row(1)["catches"],
		[
			{"sp": "tuna", "kg": 54.2, "grade": "trophy", "fight_s": 372.0},
			{"sp": "mackerel", "kg": 1.5, "grade": "landed", "fight_s": 75.0}
		]
	)


func test_unlocks_come_every_500_xp_of_the_running_total() -> void:
	var g := _game(1)
	var items := FishingResults.unlock_items(g.content)
	assert_eq(FishingResults.unlock_every(g.content), 500)
	assert_eq(FishingResults.unlocked_ids(items, 500, 499), [])
	assert_eq(FishingResults.unlocked_ids(items, 500, 1000), ["line_orange", "canopy_stripes"])
	assert_eq(
		FishingResults.unlocks_between(items, 500, 450, 1520),
		["line_orange", "canopy_stripes", "trim_teal"]
	)
	assert_eq(FishingResults.unlocked_ids(items, 500, 1000000).size(), items.size(), "capped")
	g.state.lanes[0].summary_xp = 480
	var res := FishingResults.build(g.state, _stats({1: {"kj": 30.0}}), g.ctx.players, g.content)
	assert_eq(res.row(1)["xp"], 30)
	assert_eq(res.row(1)["unlocks"], ["line_orange"], "480 + 30 crosses 500")


func test_cosmetic_indexes_are_one_based_per_kind() -> void:
	var g := _game(1)
	var eq := {"line": "line_lime", "canopy": "canopy_stripes", "pennant": "pennant_trophy"}
	assert_eq(FishingResults.cosmetic_indexes(g.content, eq), [2, 1, 0, 1] as Array[int])
	assert_eq(FishingResults.cosmetic_counts(g.content), [4, 3, 3, 1] as Array[int])


func test_summary_reads_xp_records_and_the_equipped_look() -> void:
	var g := _game(1)
	var p := ProgressStore.open("fishing", "")
	assert_eq(
		FishingResults.summary_from(p, g.content),
		{"xp": 0, "records": {}, "cosmetics": [0, 0, 0, 0] as Array[int]}
	)
	p.set_value("xp", 1234.0)
	p.set_value("records", {"tuna": 61.5, "bogus": 3.0})
	p.set_value("unlocks", ["line_orange", "canopy_stripes", "trim_teal", "line_lime"])
	var s := FishingResults.summary_from(p, g.content)
	assert_eq(s["xp"], 1234)
	assert_eq(s["records"], {"tuna": 61.5})
	assert_eq(s["cosmetics"], [2, 1, 1, 0] as Array[int], "newest per kind without 'equipped'")
	p.set_value("equipped", {"line": "line_orange"})
	assert_eq(FishingResults.summary_from(p, g.content)["cosmetics"], [1, 0, 0, 0] as Array[int])


func test_apply_progress_updates_the_local_rider_once_per_session() -> void:
	var g := _game()
	_fill(g)
	g.state.lanes[0].summary_xp = 400
	var res := FishingResults.build(
		g.state, _stats({1: {"kj": 150.4}, 2: {"kj": 80.0}}), g.ctx.players, g.content
	)
	res.session_id = "fishing/e2e_2min/7/1a168a1da00-1"
	var p := ProgressStore.open("fishing", "")
	p.set_value("xp", 400)
	p.set_value("records", {"tuna": 60.0})
	var fresh := FishingResults.apply_progress(res, p, 1, g.content, "e2e_2min")
	assert_eq(fresh, ["line_orange"], "400 + 245 crosses 500")
	assert_eq(int(p.get_value("xp")), 645)
	assert_eq(p.get_value("unlocks"), ["line_orange"])
	assert_eq(p.get_value("equipped"), {"line": "line_orange"})
	assert_eq(p.get_value("records"), {"tuna": 60.0, "mackerel": 1.5}, "the record only grows")
	assert_eq(p.get_value("trophies"), 1)
	var log: Array = p.get_value("catch_log")
	assert_eq(log.size(), 2)
	assert_eq(
		log[0],
		{
			"species": "tuna",
			"kg": 54.2,
			"grade": "trophy",
			"fight_s": 372,
			"trip": "e2e_2min",
			"date": "2026-10-23"
		}
	)
	assert_eq(FishingResults.apply_progress(res, p, 1, g.content, "e2e_2min"), [], "repeat skipped")
	assert_eq(int(p.get_value("xp")), 645)
	assert_eq((p.get_value("catch_log") as Array).size(), 2)


func test_apply_progress_survives_a_json_round_trip_and_equips_each_kinds_newest() -> void:
	var g := _game(1)
	var res := FishingResults.build(g.state, _stats({1: {"kj": 1600.0}}), g.ctx.players, g.content)
	res.session_id = "fishing/e2e_2min/7"
	res = GameResults.from_dict(JSON.parse_string(JSON.stringify(res.to_dict())))
	var p := ProgressStore.open("fishing", "")
	var fresh := FishingResults.apply_progress(res, p, 1, g.content, "e2e_2min")
	assert_eq(fresh, ["line_orange", "canopy_stripes", "trim_teal"])
	assert_eq(
		p.get_value("equipped"),
		{"line": "line_orange", "canopy": "canopy_stripes", "trim": "trim_teal"}
	)
	assert_eq(p.get_value("catch_log"), [], "no fish, no log rows")
	res.session_id = "fishing/e2e_2min/8"
	assert_eq(
		FishingResults.apply_progress(res, p, 1, g.content, "e2e_2min"),
		["line_lime", "canopy_dots", "trim_gold"]
	)
	assert_eq(p.get_value("equipped")["line"], "line_lime", "the newest line is worn")
	assert_eq(FishingResults.apply_progress(res, p, 99, g.content, "e2e_2min"), [], "no row")


func test_dates_come_from_the_session_nonce_never_a_clock() -> void:
	assert_eq(FishingResults.date_from_session_id("fishing/free_30/7/1a168a1da00-1"), "2026-10-23")
	assert_eq(FishingResults.date_from_session_id("fishing/free_30/7/dd9aa6e000-2"), "2000-02-29")
	assert_eq(FishingResults.date_from_session_id("fishing/free_30/7/1941f297818-a"), "2024-12-31")
	assert_eq(FishingResults.date_from_session_id("fishing/free_30/7/0-1"), "1970-01-01")
	assert_eq(FishingResults.date_from_session_id("fishing/free_30/7"), "", "run_game_sim: none")
	assert_eq(FishingResults.date_from_session_id("fishing/free_30/7/zz-1"), "")
	assert_eq(FishingResults.date_from_session_id(""), "")
	assert_eq(FishingResults.clock_text(372.4), "6:12")
	assert_eq(FishingResults.clock_text(59.6), "1:00")


func test_the_module_builds_results_from_its_state() -> void:
	var g := _game()
	_fill(g)
	(g.ctx.stats as F.Stats).rows = {1: {"kj": 10.0}}
	var res := g.results()
	assert_eq(res.grade, "A")
	assert_eq(res.row(1)["xp"], 10 + 20 + 25 + 50)
	assert_eq(g.apply_progress(res, g.ctx.progress), [])
	assert_eq(int(g.ctx.progress.get_value("xp")), 105)
