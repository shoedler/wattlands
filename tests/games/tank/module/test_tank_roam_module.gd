extends GutTest
## Free roam through the module (brief 2.5, 2.6, 2.8, 2.10): the driver's turn from the keys and its
## ownership, a whole roam played to finished("time_up") with every rider ended in one step, the roam
## results (points, kills by type, distance, the grade by points per WORK minute, XP, unlocks, ride_tag
## "Free Roam N min"), the snapshot's roam row round trip and its size at the caps with 4 riders, and
## the roam toasts.

const F := preload("res://tests/games/tank/tank_fakes.gd")


func _game(crew: int, content: String = "roam_30", role: String = Wl.SOLO) -> TankGame:
	var ctx := F.make_ctx(crew, 0, content, role)
	var rows := {}
	for p in ctx.players:
		rows[p.peer_id] = {"kj": 400.0}
	(ctx.stats as F.Stats).rows = rows
	var g: TankGame = autofree(F.make_game(ctx))
	assert_not_null(g.state, "configured")
	return g


# --- Keys and ownership ----------------------------------------------------------------------------


func test_the_driver_turns_with_ability_1_and_the_diesel_also_with_confirm() -> void:
	var g := _game(3)
	g.build_effort_plans()
	var diesel := g.state.station(TankIds.ENGINE_DIESEL)
	g.ctx.local_peer = diesel.peer
	g.state.rider(diesel.peer).engine = TankIds.ENGINE_DIESEL
	var none: Array[StringName] = []
	for act: StringName in [&"ability_1", &"confirm"]:
		var acts: Array[StringName] = [act]
		var out := g.local_intents(acts, none)
		assert_eq(out.size(), 1, str(act))
		assert_eq(str(out[0]["k"]), TankIds.INTENT_TURN, str(act))
	var dyn := g.state.station(TankIds.ENGINE_DYNAMO)
	g.ctx.local_peer = dyn.peer
	var both: Array[StringName] = [&"ability_1", &"confirm"]
	for n: Variant in g.local_intents(both, none):
		assert_ne(str((n as Dictionary)["k"]), TankIds.INTENT_TURN, "the dynamo never turns")
	var solo := _game(1)
	var turns := 0
	var a1: Array[StringName] = [&"ability_1"]
	for n2: Variant in solo.local_intents(a1, none):
		if str((n2 as Dictionary)["k"]) == TankIds.INTENT_TURN:
			turns += 1
	assert_eq(turns, 1, "the Bulwark turns with ability_1")
	var mission := _game(1, "ashfall_road")
	for n3: Variant in mission.local_intents(a1, none):
		assert_ne(str((n3 as Dictionary)["k"]), TankIds.INTENT_TURN, "no turn in a mission")


func test_a_turn_from_the_wrong_engine_is_dropped_and_the_drivers_ends_the_fallback() -> void:
	var g := _game(3)
	var plans := F.plans_of(g)
	var clock := F.PhaseClock.new(plans, g.ctx.directives as F.Directives)
	var tick := F.run(g, plans, 0, 1.0, 100.0, clock)
	var dyn := g.state.station(TankIds.ENGINE_DYNAMO).peer
	var diesel := g.state.station(TankIds.ENGINE_DIESEL).peer
	var f := F.frame(g.ctx, plans, tick, 100.0, {dyn: [{"k": "turn"}]}, clock)
	g.sim_step(Wl.SIM_DT, f)
	assert_eq(g.state.roam.turn_s, 0.0, "the dynamo does not own the turn")
	assert_true(g.state.rider(diesel).fallback)
	tick += 1
	f = F.frame(g.ctx, plans, tick, 100.0, {diesel: [{"k": "turn"}]}, clock)
	g.sim_step(Wl.SIM_DT, f)
	assert_gt(g.state.roam.turn_s, 0.0, "the diesel's turn starts one")
	assert_false(g.state.rider(diesel).fallback, "a deliberate turn ends the fallback")


# --- A whole roam ----------------------------------------------------------------------------------


func test_a_zero_input_roam_plays_to_finished_time_up() -> void:
	for crew in [1, 4]:
		var g := _game(crew, "roam_10")
		watch_signals(g)
		var clock := F.clock_of(g)
		F.run_session(g, clock, 2.0)
		assert_true(clock.all_in_cooldown(), "crew %d reached the cool-down" % crew)
		assert_signal_emitted_with_parameters(g, "finished", [TankIds.OUTCOME_TIME_UP])
		assert_eq(g.state.outcome, TankIds.OUTCOME_TIME_UP)
		var batch_ok := false
		for b: Dictionary in clock.batches:
			if int(b["index"]) == 1 and not bool(b["refused"]):
				batch_ok = (b["peers"] as Array).size() == crew
				assert_lte(float(b["elapsed_s"]), 600.0, "within the overtime bound")
				assert_gte(float(b["elapsed_s"]), 300.0 - 1e-6, "not before min_s")
		assert_true(batch_ok, "every rider ended in one step, crew %d" % crew)
		for c: Dictionary in clock.changes:
			assert_ne(str(c["ended_by"]), Wl.ENDED_MAX_S, "never cut at max_s")
		var res := g.results()
		assert_eq(res.ride_tag, "Free Roam 10 min")
		assert_eq(res.summary_key, "TANK_RESULT_TIME_UP")


func test_no_patrol_spawns_after_time_up() -> void:
	var g := _game(3, "roam_10")
	var clock := F.clock_of(g)
	var plans := clock.plans
	var tick := 0
	var seen := {}
	var late := 0
	while not clock.all_in_cooldown() and tick < 20000:
		F.run(g, plans, tick, Wl.SIM_DT, 100.0, clock)
		tick += 1
		for e in g.state.enemies:
			if not seen.has(e.id):
				seen[e.id] = true
				if g.state.roam.time_up and not g.state.roam.strong_id.has(e.id):
					late += 1
	assert_eq(late, 0, "no new patrol after time up")
	assert_gt(seen.size(), 0, "patrols came before it")


# --- Results ----------------------------------------------------------------------------------------


func test_roam_results_score_points_and_grade_by_points_per_work_minute() -> void:
	var cases := [[22.5, "S"], [17.5, "A"], [12.5, "B"], [7.5, "C"], [7.2, "D"]]
	for c: Array in cases:
		var g := _game(3)
		var s := g.state
		s.seg.seg = TankIds.SEG_COOLDOWN
		s.outcome = TankIds.OUTCOME_TIME_UP
		s.roam.work_s = 1500.0
		s.roam.points = roundi(float(c[0]) * 25.0)
		s.roam.odo_m = 12345.0
		s.score.kills = [0, 3, 2, 1, 1, 0, 0, 4, 5]
		s.score.evades_ok = 2
		s.score.evades_tried = 5
		var res := g.results()
		assert_eq(res.grade, str(c[1]), "%s points a minute" % c[0])
		assert_eq(res.score, float(s.roam.points))
		assert_eq(res.ride_tag, "Free Roam 30 min")
		assert_eq(
			(res.team as Dictionary).keys(),
			[
				"TANK_TEAM_OUTCOME",
				"TANK_TEAM_DIFFICULTY",
				"TANK_TEAM_LOSSES",
				"TANK_TEAM_POINTS",
				"TANK_TEAM_POINTS_PER_MIN",
				"TANK_TEAM_ROAM_KILLS",
				"TANK_TEAM_DISTANCE",
				"TANK_TEAM_EVADES",
				"TANK_TEAM_BREAKDOWNS",
				"TANK_TEAM_PATROLS"
			]
		)
		assert_eq(
			res.team["TANK_TEAM_ROAM_KILLS"],
			"3/2/1/1/0/4/5",
			"the near kinds count, the Behemoth's slot does not"
		)
		assert_eq(res.team["TANK_TEAM_DISTANCE"], "12.3")
		assert_eq(res.team["TANK_TEAM_EVADES"], "2/5")
		var bonus := {"S": 60, "A": 40, "B": 25, "C": 10, "D": 0}
		for row in res.rows:
			assert_eq(int(row["xp"]), roundi(400.0 / 10.0) + int(bonus[res.grade]), "XP")
			assert_false((row["unlocks"] as Array).has("brass_machinery"), "no Behemoth unlock")
			assert_true((row["ride_lines"] as Array).size() >= 5)
		assert_eq(res.ride_lines[0], "Points: %d (grade %s)" % [s.roam.points, res.grade])


func test_a_roam_cut_short_is_abandoned_with_no_unlock() -> void:
	var g := _game(2)
	g.state.seg.seg = TankIds.SEG_ROAM
	var res := g.results()
	assert_eq(res.summary_key, "TANK_RESULT_ABANDONED")
	for row in res.rows:
		assert_eq(row["unlocks"], [])


# --- Snapshot ------------------------------------------------------------------------------------------


func _roamy(s: TankState) -> void:
	s.roam.turn_s = 3.25
	s.roam.turn_cd_s = 21.5
	s.roam.end_s = 1.5
	s.roam.at_end = -1
	s.roam.engaging = true
	s.roam.time_up = true
	s.roam.overtime = true
	s.roam.points = 345
	s.roam.odo_m = 15234.0
	s.roam.work_m = 9876.0
	s.roam.map_m = 4321.7
	s.hull.dir = TankIds.DIR_LEFT
	if s.roam.strong_back_s.size() > 1:
		s.roam.strong_back_s[1] = 300.0


func test_the_roam_row_round_trips_and_clients_rebuild_the_map() -> void:
	var host := _game(4, "roam_45", Wl.HOST)
	_roamy(host.state)
	var snap := host.snapshot()
	assert_true(snap.has("rm"))
	assert_eq(TankSnapshotSchema.check(snap), "")
	var wire: Dictionary = JSON.parse_string(JSON.stringify(snap))
	var client := _game(4, "roam_45", Wl.CLIENT)
	assert_true(client.state.roam.active)
	assert_null(client.state.roam_map, "no map before the seed arrives")
	client.apply_snapshot(wire)
	var r := client.state.roam
	var h := host.state.roam
	assert_eq(r.map_seed, h.map_seed)
	assert_almost_eq(r.map_m, h.map_m, 0.05)
	assert_almost_eq(r.turn_s, h.turn_s, 0.001)
	assert_almost_eq(r.turn_cd_s, h.turn_cd_s, 0.001)
	assert_eq([r.at_end, r.engaging, r.time_up, r.overtime], [-1, true, true, true])
	assert_eq(r.points, 345)
	assert_eq(client.state.hull.dir, TankIds.DIR_LEFT)
	assert_not_null(client.state.roam_map)
	assert_eq(client.state.roam_map.zones, host.state.roam_map.zones, "the same valley")
	assert_true(r.strong_down(1))
	assert_false(r.strong_down(0))
	var mission := _game(3, "ashfall_road", Wl.HOST)
	assert_false(mission.snapshot().has("rm"), "missions send no roam row")


func test_a_roam_snapshot_at_the_caps_with_4_riders_stays_under_4_kb() -> void:
	var g := _game(4, "roam_60", Wl.HOST)
	var cap := TankFixtures.cap4()
	g.state.enemies = cap.enemies
	g.state.shells = cap.shells
	g.state.obstacles = cap.obstacles
	for i in g.state.riders.size():
		var r := g.state.riders[i]
		r.raw_w = 1999.0
		r.cadence_rpm = 199.0
		r.target_pct = 99.9
	g.state.hull.x_px = 230400.0
	_roamy(g.state)
	g.state.roam.points = -12345
	var snap := g.snapshot()
	assert_eq((snap["e"] as Array).size(), TankConst.MAX_ENEMIES)
	assert_eq((snap["s"] as Array).size(), TankConst.MAX_SHELLS)
	var bytes := TankSnapshotSchema.byte_size(snap)
	assert_lte(bytes, TankConst.SNAPSHOT_MAX_BYTES, "%d B" % bytes)


# --- Toasts --------------------------------------------------------------------------------------------


func test_the_driver_gets_turn_around_at_the_end_and_everyone_engage_and_time_up() -> void:
	var g := _game(3, "roam_30")
	var hud := g.ctx.hud as F.Hud
	var diesel := g.state.station(TankIds.ENGINE_DIESEL).peer
	g.ctx.local_peer = diesel
	var cues := TankCues.new(g.ctx)
	g.state.seg.seg = TankIds.SEG_ROAM
	g.state.seg.kind = Wl.WORK
	cues.on_state(g.state)
	g.state.roam.at_end = 1
	cues.on_state(g.state)
	cues.on_state(g.state)
	g.state.roam.engaging = true
	cues.on_state(g.state)
	cues.on_event(g.state, TankEvents.time_up())
	cues.on_event(g.state, TankEvents.turn(0, -1))
	var keys: Array = []
	for c: Variant in hud.of("toast"):
		keys.append(str((c as Array)[1]))
	assert_eq(keys.count("TANK_TOAST_TURN_AROUND"), 1, "once per arrival: %s" % [keys])
	assert_true(keys.has("TANK_TOAST_ENGAGE"))
	assert_true(keys.has("TANK_TOAST_TIME_UP"))
	assert_true(keys.has("TANK_TOAST_TURNING"))
	var steam := g.state.station(TankIds.ENGINE_STEAM).peer
	g.ctx.local_peer = steam
	var other := TankCues.new(g.ctx)
	other.on_state(g.state)
	g.state.roam.at_end = -1
	other.on_state(g.state)
	var n := 0
	for c2: Variant in hud.of("toast"):
		if str((c2 as Array)[1]) == "TANK_TOAST_TURN_AROUND":
			n += 1
	assert_eq(n, 1, "only the driver is told to turn around")
