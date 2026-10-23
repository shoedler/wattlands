extends GutTest
## results() (brief 2.8): the platform's rows plus Tank's stats, grade, score, XP and the unlocks
## listed per rider; apply_progress into ctx.progress; and the first run never picks Tank.

const F := preload("res://tests/games/tank/tank_fakes.gd")
const BONUS := {"S": 60, "A": 40, "B": 25, "C": 10, "D": 0}
const STAT_KEYS: Array[String] = [
	"TANK_STAT_DIESEL_S",
	"TANK_STAT_DYNAMO_S",
	"TANK_STAT_STEAM_S",
	"TANK_STAT_BULWARK_S",
	"TANK_STAT_RAMS",
	"TANK_STAT_DODGES",
	"TANK_STAT_BERM",
	"TANK_STAT_SHOTS",
	"TANK_STAT_HITS",
	"TANK_STAT_ACCURACY",
	"TANK_STAT_SHELLS",
]
const TEAM_KEYS: Array[String] = [
	"TANK_TEAM_OUTCOME",
	"TANK_TEAM_HP",
	"TANK_TEAM_BREAKDOWNS",
	"TANK_TEAM_OVERRUNS",
	"TANK_TEAM_KILLS",
]


func _played(crew: int, kj: float = 300.0) -> TankGame:
	var ctx := F.make_ctx(crew)
	var rows := {}
	for p in ctx.players:
		rows[p.peer_id] = {"kj": kj + 10.0 * p.slot_index}
	(ctx.stats as F.Stats).rows = rows
	var g: TankGame = autofree(F.make_game(ctx))
	F.run_session(g, F.clock_of(g), 2.0)
	return g


func _perfect(crew: int) -> TankGame:
	var ctx := F.make_ctx(crew)
	var rows := {}
	for p in ctx.players:
		rows[p.peer_id] = {"kj": 500.0}
	(ctx.stats as F.Stats).rows = rows
	var g: TankGame = autofree(F.make_game(ctx))
	var s := g.state
	s.seg.seg = TankIds.SEG_COOLDOWN
	s.score.behemoth_killed = true
	s.score.stages_clean = 3
	s.score.shots = 20
	s.score.hits = 20
	s.score.breakdowns = 0
	s.outcome = TankIds.OUTCOME_VICTORY
	for r in s.riders:
		r.work_s = 1000.0
		r.band_s = 1000.0
	return g


func test_a_full_session_gives_every_rider_a_row_with_tank_stats_in_order() -> void:
	for crew in [1, 2, 3]:
		var g := _played(crew)
		var res := g.results()
		assert_eq(res.rows.size(), crew)
		assert_has(["S", "A", "B", "C", "D"], res.grade)
		assert_between(res.score, 0.0, 1000.0)
		for row in res.rows:
			assert_eq((row["stats"] as Dictionary).keys(), STAT_KEYS, "crew %d" % crew)
			for k: String in STAT_KEYS:
				var v: Variant = row["stats"][k]
				assert_true(v is int or v is String, "%s is a number or a string" % k)
			for k in ["kj", "avg_power_w", "np_w", "time_in_band_s", "time_in_band_pct", "xp"]:
				assert_true(row.has(k), k)
		assert_eq((res.team as Dictionary).keys(), TEAM_KEYS)
		assert_has(["TANK_RESULT_VICTORY", "TANK_RESULT_WITHDRAWN"], res.summary_key)


func test_results_survive_json_and_keep_their_order() -> void:
	var res := _played(3).results()
	var back: Variant = JSON.parse_string(JSON.stringify(res.to_dict(), "", false))
	assert_eq((back["rows"] as Array).size(), 3)
	assert_eq((back["rows"][0]["stats"] as Dictionary).keys(), STAT_KEYS)
	assert_eq((back["team"] as Dictionary).keys(), TEAM_KEYS)
	assert_eq(back["grade"], res.grade)


func test_xp_is_kj_over_ten_plus_the_grade_bonus_per_rider() -> void:
	var g := _played(3, 420.0)
	var res := g.results()
	for row in res.rows:
		var kj := float(row["kj"])
		assert_eq(row["xp"], roundi(kj / 10.0) + int(BONUS[res.grade]), "peer %d" % row["peer_id"])
	assert_ne(res.row(1)["xp"], res.row(3)["xp"], "each rider's own kJ")


func test_every_rider_lists_the_unlocks_of_the_session() -> void:
	var res := _played(2).results()
	for row in res.rows:
		var u: Array = row["unlocks"]
		assert_has(u, "soot", "a finished session")
		assert_eq(u.has("rust"), ["S", "A", "B"].has(res.grade))
		assert_eq(u.has("ash"), ["S", "A"].has(res.grade))
		assert_eq(u.has("mud_stripe"), res.grade == "S")
		assert_false(
			u.has("brass_machinery") and not _killed_the_behemoth(res), "brass needs the kill"
		)
	var perfect := _perfect(3).results()
	assert_eq(perfect.grade, "S")
	for row in perfect.rows:
		assert_eq(row["unlocks"], ["soot", "rust", "ash", "mud_stripe", "brass_machinery"])
	assert_eq(perfect.summary_key, "TANK_RESULT_VICTORY")
	assert_eq(perfect.row(1)["time_in_band_pct"], 100.0)


func _killed_the_behemoth(res: GameResults) -> bool:
	return res.summary_key == "TANK_RESULT_VICTORY"


func test_a_run_that_did_not_finish_unlocks_nothing() -> void:
	var ctx := F.make_ctx(1)
	var g: TankGame = autofree(F.make_game(ctx))
	F.run(g, F.plans_of(g), 0, 20.0)
	var res := g.results()
	assert_eq(res.rows[0]["unlocks"], [], "cut short")
	assert_eq(res.rows[0]["xp"], int(BONUS[res.grade]) + 0)


func test_a_broken_content_gives_a_d_with_the_platform_rows() -> void:
	var ctx := F.make_ctx(2)
	ctx.content_overrides = {"tanks.json": {"hull": {"hp": -5}}}
	var g: TankGame = autofree(F.make_game(ctx))
	assert_push_error("hull.hp")
	var res := g.results()
	assert_eq(res.grade, "D")
	assert_eq(res.rows.size(), 2)


func test_apply_progress_takes_only_the_local_riders_row() -> void:
	var res := GameResults.new()
	res.session_id = "tank/ashfall_road/1/a"
	res.rows = [
		{"peer_id": 1, "xp": 70, "unlocks": ["soot", "rust"]},
		{"peer_id": 2, "xp": 33, "unlocks": ["soot"]},
		{"peer_id": 3, "xp": 12, "unlocks": []},
	]
	for peer in [1, 2, 3]:
		var ctx := F.make_ctx(3, 0, "ashfall_road", Wl.CLIENT, peer)
		var g: TankGame = autofree(F.make_game(ctx))
		var fresh := g.apply_progress(res, ctx.progress)
		assert_eq(fresh, res.row(peer)["unlocks"] as Array, "peer %d" % peer)
		assert_eq(float(ctx.progress.get_value("xp", 0)), float(res.row(peer)["xp"]))
		assert_eq(ctx.progress.get_value("unlocks", []), res.row(peer)["unlocks"])
	var outsider := F.make_ctx(3, 0, "ashfall_road", Wl.CLIENT, 9)
	var g2: TankGame = autofree(F.make_game(outsider))
	assert_eq(g2.apply_progress(res, outsider.progress), [], "no row for this peer")
	assert_false(outsider.progress.has("xp"))


func test_a_session_counts_once_and_only_new_unlocks_are_returned() -> void:
	var ctx := F.make_ctx(1)
	var g: TankGame = autofree(F.make_game(ctx))
	var a := GameResults.new()
	a.session_id = "tank/ashfall_road/1/a"
	a.rows = [{"peer_id": 1, "xp": 50, "unlocks": ["soot", "rust"]}]
	assert_eq(g.apply_progress(a, ctx.progress), ["soot", "rust"])
	assert_eq(g.apply_progress(a, ctx.progress), [], "the results arrived twice")
	assert_eq(float(ctx.progress.get_value("xp", 0)), 50.0)
	var b := GameResults.new()
	b.session_id = "tank/ashfall_road/1/b"
	b.rows = [{"peer_id": 1, "xp": 20.0, "unlocks": ["rust", "ash", "ash"]}]
	assert_eq(g.apply_progress(b, ctx.progress), ["ash"])
	assert_eq(float(ctx.progress.get_value("xp", 0)), 70.0)
	assert_eq(ctx.progress.get_value("unlocks", []), ["soot", "rust", "ash"])
	var again := g.apply_progress(a, ctx.progress)
	assert_eq(again, [], "an old session id is remembered")
	assert_eq((ctx.progress.get_value("sessions", []) as Array).size(), 2)


func test_the_remembered_session_ids_are_capped() -> void:
	var ctx := F.make_ctx(1)
	var g: TankGame = autofree(F.make_game(ctx))
	for i in TankGame.PROGRESS_SESSIONS_KEPT + 10:
		var r := GameResults.new()
		r.session_id = "tank/x/1/%d" % i
		r.rows = [{"peer_id": 1, "xp": 1, "unlocks": []}]
		g.apply_progress(r, ctx.progress)
	assert_eq(
		(ctx.progress.get_value("sessions", []) as Array).size(), TankGame.PROGRESS_SESSIONS_KEPT
	)
	assert_eq(float(ctx.progress.get_value("xp", 0)), float(TankGame.PROGRESS_SESSIONS_KEPT + 10))


func test_results_from_the_real_session_feed_apply_progress() -> void:
	var g := _played(1, 420.0)
	var res := g.results()
	res.session_id = "tank/ashfall_road/1/real"
	var ctx := g.ctx
	var fresh := g.apply_progress(res, ctx.progress)
	assert_has(fresh, "soot")
	assert_eq(float(ctx.progress.get_value("xp", 0)), float(res.row(1)["xp"]))


func test_the_first_run_never_picks_tank() -> void:
	var m := F.manifest()
	assert_eq(int(m["first_run_priority"]), -1)
	var reg := WlGameRegistry.new()
	reg.scan_on_ready = false
	add_child_autofree(reg)
	reg.scan()
	assert_true(reg.has_game("tank"))
	assert_ne(reg.first_run_game(), "tank")
	var workout := {"id": "workout", "first_run_priority": 0}
	assert_eq(WlGameRegistry.pick_first_run([m, workout]), "workout")
	assert_eq(WlGameRegistry.pick_first_run([workout, m]), "workout", "whatever the order")
	var other := {"id": "aaa_game", "first_run_priority": 0}
	assert_eq(WlGameRegistry.pick_first_run([m, other]), "aaa_game", "a tie at 0 never goes to -1")
