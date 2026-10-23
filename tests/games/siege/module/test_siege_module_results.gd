extends GutTest
## Results and progression (brief 2.8): per-player and team stats, each slot's session XP, XP added
## exactly once per session id on the host, on a client and on a client restarted in the
## cool-down, and each unlock once.

const K := preload("res://tests/games/siege/module/siege_module_kit.gd")
const F := preload("res://tests/games/siege/siege_fakes.gd")
const BONUS := {"S": 60, "A": 40, "B": 25, "C": 10, "D": 0}
const TEMP_PROGRESS := "user://siege_module_test/progress.json"


func after_each() -> void:
	if FileAccess.file_exists(TEMP_PROGRESS):
		DirAccess.remove_absolute(TEMP_PROGRESS)


func _results(g: SiegeGame, session: String, xp: int, peer: int = 1) -> GameResults:
	var res := GameResults.from_stats(g.ctx.stats, g.ctx.players)
	res.session_id = session
	res.row(peer)["xp"] = xp
	return res


func _store() -> ProgressStore:
	return ProgressStore.open("siege", "")


func test_results_hold_the_stats_the_brief_lists() -> void:
	var g := K.game(2, 1, "short")
	(g.ctx.stats as F.Stats).rows = {1: {"kj": 1004.0}, 2: {"kj": 500.0}, -1: {"kj": 10.0}}
	var st := g.state
	var r1 := st.rider(1)
	r1.gen_denarii = 120.7
	r1.bounty_denarii = 33.2
	r1.kills = 17
	r1.damage = 512.4
	r1.od_scored = 2
	r1.wave_gen_s = 410.0
	r1.wave_tower_s = 280.0
	r1.towers_built = 3
	st.wave_gate_hp = [100, 82, 64]
	st.leaks_by_road = [4, 0, 9]
	st.rams_total = 6
	st.rams_stopped = 5
	st.breaches = 0
	var res := g.results()
	var sc := SiegeScore.compute(st)
	assert_eq(res.grade, sc["grade"])
	assert_almost_eq(res.score, float(sc["score"]), 0.001)
	assert_eq(res.summary_key, "SIEGE_RESULTS")
	assert_eq(res.rows.size(), 3, "bots too")
	var row := res.row(1)
	assert_eq(
		row["stats"],
		{
			"SIEGE_STAT_GEN_DENARII": 120,
			"SIEGE_STAT_BOUNTY_DENARII": 33,
			"SIEGE_STAT_KILLS": 17,
			"SIEGE_STAT_DAMAGE": 512,
			"SIEGE_STAT_OVERDRIVES": 2,
			"SIEGE_STAT_GEN_TIME": 410,
			"SIEGE_STAT_TOWER_TIME": 280,
			"SIEGE_STAT_TOWERS_BUILT": 3,
		},
		"generator vs bounty denarii, kills, damage, scored Overdrives, wave time, towers built"
	)
	assert_eq(row["xp"], 100 + int(BONUS[res.grade]), "round(kJ / 10) + the grade bonus")
	assert_eq(res.row(2)["xp"], 50 + int(BONUS[res.grade]))
	assert_eq(res.row(-1)["xp"], 1 + int(BONUS[res.grade]))
	assert_eq(
		res.team.keys(),
		[
			"SIEGE_STAT_SCORE",
			"SIEGE_STAT_GATE_PER_WAVE",
			"SIEGE_STAT_BREACHES",
			"SIEGE_STAT_LEAKS_BY_ROAD",
			"SIEGE_STAT_RAMS_STOPPED"
		]
	)
	# The results screen prints team values with str(): readable text, not Array syntax.
	assert_eq(res.team["SIEGE_STAT_GATE_PER_WAVE"], "100 / 82 / 64")
	assert_eq(res.team["SIEGE_STAT_LEAKS_BY_ROAD"], "4 / 0 / 9")
	assert_eq(res.team["SIEGE_STAT_RAMS_STOPPED"], "5 / 6")
	assert_eq(res.team["SIEGE_STAT_BREACHES"], 0)
	assert_eq(JSON.parse_string(JSON.stringify(res.to_dict()))["team"].size(), 5, "JSON safe")
	assert_eq(res.ride_tag, "Short shift - won", "the Strava title tag: mission and outcome")
	assert_eq(res.ride_lines.size(), 4)
	assert_eq(res.ride_lines[1], "Gate breaches: 0")
	assert_eq(res.ride_lines[2], "Rams stopped: 5 of 6")
	assert_eq(res.ride_lines[3], "Enemies defeated: 17")
	st.breaches = 2
	assert_eq(g.results().summary_key, "SIEGE_RESULTS_FALLEN")
	assert_eq(g.results().ride_tag, "Short shift - lost")
	st.wave_gate_hp.clear()
	assert_eq(g.results().team["SIEGE_STAT_GATE_PER_WAVE"], "-")
	F.free_game(g)


func test_xp_counts_once_per_session_and_each_unlock_once() -> void:
	var g := K.game(1, 0, "short")
	var store := _store()
	assert_eq(g.apply_progress(_results(g, "siege/short/1/a", 99), store), [], "99 is not 100")
	assert_eq(g.apply_progress(_results(g, "siege/short/1/b", 1), store), ["swallowtail_pennant"])
	assert_eq(float(store.get_value("xp", 0)), 100.0)
	assert_eq(g.apply_progress(_results(g, "siege/short/1/b", 1), store), [], "same session")
	assert_eq(float(store.get_value("xp", 0)), 100.0)
	assert_eq(
		g.apply_progress(_results(g, "siege/short/1/c", 400), store),
		["walnut_wheel", "bronze_chain_trim"],
		"500 crosses 250 and 500, not the pennant again"
	)
	assert_eq(g.apply_progress(_results(g, "siege/short/1/d", 500), store), ["long_banner"])
	assert_eq(g.apply_progress(_results(g, "siege/short/1/e", 5000), store), [], "all held")
	assert_eq(float(store.get_value("xp", 0)), 6000.0)
	assert_eq(
		store.get_value("unlocks", []),
		["swallowtail_pennant", "walnut_wheel", "bronze_chain_trim", "long_banner"]
	)
	F.free_game(g)


func test_unlocks_cross_at_exactly_their_threshold() -> void:
	var g := K.game(1, 0, "short")
	var store := _store()
	var got: Array = []
	var total := 0
	for step in [100, 150, 250, 500]:
		got.append(g.apply_progress(_results(g, "s%d" % total, step), store))
		total += step
	assert_eq(
		got, [["swallowtail_pennant"], ["walnut_wheel"], ["bronze_chain_trim"], ["long_banner"]]
	)
	F.free_game(g)


func test_a_session_without_an_id_still_counts_once_per_module() -> void:
	var g := K.game(1, 0, "short")
	var store := _store()
	g.apply_progress(_results(g, "", 40), store)
	g.apply_progress(_results(g, "", 40), store)
	assert_eq(float(store.get_value("xp", 0)), 40.0)
	F.free_game(g)


func test_host_and_client_each_add_their_own_xp_and_nobody_else_s() -> void:
	var host := K.game(2, 0, "short", Wl.HOST, 1)
	var client := K.game(2, 0, "short", Wl.CLIENT, 2)
	var res := _results(host, "siege/short/7/n", 90)
	res.row(2)["xp"] = 260
	var host_store := _store()
	var client_store := _store()
	assert_eq(host.apply_progress(res, host_store), [])
	assert_eq(client.apply_progress(res, client_store), ["swallowtail_pennant", "walnut_wheel"])
	assert_eq(float(host_store.get_value("xp", 0)), 90.0)
	assert_eq(float(client_store.get_value("xp", 0)), 260.0)
	F.free_game(host)
	F.free_game(client)


func test_a_client_restarted_in_the_cool_down_does_not_count_the_session_twice() -> void:
	var first := K.game(2, 0, "short", Wl.CLIENT, 2)
	var res := _results(first, "siege/short/9/z", 130, 2)
	var store := ProgressStore.open("siege", TEMP_PROGRESS)
	assert_eq(first.apply_progress(res, store), ["swallowtail_pennant"])
	assert_true(store.save())
	F.free_game(first)
	# The app restarts and rejoins: a fresh module, the progress file read back, the results sent again.
	var second := K.game(2, 0, "short", Wl.CLIENT, 2)
	var reopened := ProgressStore.open("siege", TEMP_PROGRESS)
	assert_eq(second.apply_progress(res, reopened), [], "the file remembers the session")
	assert_eq(float(reopened.get_value("xp", 0)), 130.0)
	assert_eq(reopened.get_value("unlocks", []), ["swallowtail_pennant"])
	var next := _results(second, "siege/short/9/y", 130, 2)
	assert_eq(second.apply_progress(next, reopened), ["walnut_wheel"], "a new session counts")
	F.free_game(second)


func test_progress_remembers_a_bounded_number_of_sessions() -> void:
	var g := K.game(1, 0, "short")
	var store := _store()
	for i in 50:
		g.apply_progress(_results(g, "s%d" % i, 1), store)
	assert_eq(float(store.get_value("xp", 0)), 50.0)
	assert_lte((store.get_value("sessions", []) as Array).size(), SiegeGame.PROGRESS_SESSIONS_KEPT)
	F.free_game(g)


func test_a_rider_missing_from_the_results_gets_nothing() -> void:
	var g := K.game(1, 0, "short")
	var store := _store()
	var res := _results(g, "x", 500)
	res.rows.clear()
	assert_eq(g.apply_progress(res, store), [])
	assert_false(store.has("xp"))
	F.free_game(g)
