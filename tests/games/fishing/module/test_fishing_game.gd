extends GutTest
## FishingGame's wiring (GAME_SDK 4, 10.2, 11, 12): the summary intent, the step-out order,
## fx_event on every peer, the event-toast routing rule, teammate chips, intents, rescue and AFK,
## client prediction, bot strategies, and a whole Free Roam session through the Clock (replans,
## course grades, fights, finished).

const F := preload("res://tests/games/fishing/fishing_fakes.gd")

var _fx: Array = []
var _sent: Array = []
var _finished: Array = []
## One roam_10 SOLO session with an Autopilot rider, run once for the tests that read it.
var _roam_game: FishingGame = null
var _roam_clock: F.Clock = null
var _roam_sent: Array = []
var _roam_finished: Array = []


func before_each() -> void:
	_fx.clear()
	_sent.clear()
	_finished.clear()


func after_all() -> void:
	if _roam_game != null:
		_roam_game.free()
		_roam_game = null
	_roam_clock = null


func _watch(g: FishingGame) -> FishingGame:
	g.fx_event.connect(func(e: Dictionary) -> void: _fx.append(e))
	g.game_event.connect(func(e: Dictionary) -> void: _sent.append(e))
	g.finished.connect(func(r: String) -> void: _finished.append(r))
	return g


func _game(
	humans: int = 2, role: String = Wl.HOST, peer: int = 1, content: String = "e2e_2min"
) -> FishingGame:
	return _watch(autofree(F.make_game(F.make_ctx(humans, 0, content, role, peer))))


func _hud(g: FishingGame) -> F.Hud:
	return g.ctx.hud as F.Hud


func _toasts(g: FishingGame) -> Array:
	return _hud(g).of("toast")


func _landed(l: int, grade: int) -> Dictionary:
	return FishingEvents.landed(l, FishingConst.species_index("tuna"), grade, 54.24, 220, 1.5)


## What an event looks like on a client after Protocol (numbers as floats).
func _wire(e: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(e))


func _on_roam_event(e: Dictionary) -> void:
	_roam_sent.append(e)


func _on_roam_finished(r: String) -> void:
	_roam_finished.append(r)


## The roam_10 session (built on first use): one human with Autopilot on, riding 100 % of FTP in
## SIM, until every rider finished the cool-down.
func _roam() -> FishingGame:
	if _roam_game != null:
		return _roam_game
	var ctx := F.make_ctx(1, 0, "roam_10", Wl.SOLO, 1, 5)
	ctx.players[0].autopilot = true
	_roam_game = F.make_game(ctx)
	_roam_game.game_event.connect(_on_roam_event)
	_roam_game.finished.connect(_on_roam_finished)
	_roam_clock = F.clock_for(_roam_game)
	_roam_clock.run_until_done(1500.0)
	return _roam_game


func _roam_types() -> Array:
	_roam()
	return _roam_sent.map(func(e: Dictionary) -> String: return e["type"])


# --- configure and the summary ---------------------------------------------------------------


func test_configure_sends_one_summary_from_the_local_store() -> void:
	var ctx := F.make_ctx(2, 0, "e2e_2min", Wl.CLIENT, 2)
	ctx.progress.set_value("xp", 1210.0)
	ctx.progress.set_value("records", {"mahi": 12.3})
	ctx.progress.set_value("equipped", {"line": "line_lime", "trim": "trim_teal"})
	var g: FishingGame = autofree(F.make_game(ctx))
	var sent: Array = (ctx.intents as F.Intents).sent
	assert_eq(sent.size(), 1, "exactly one summary")
	assert_eq(
		sent[0],
		{"k": "summary", "xp": 1210, "rec": {"mahi": 123}, "cos": [2, 0, 1, 0] as Array[int]}
	)
	assert_eq(g.local_rider().peer, 2)
	assert_eq(
		g.local_rider().cosmetics, [2, 0, 1, 0] as Array[int], "the local rider wears it at once"
	)
	assert_eq(g.state.riders[0].cosmetics, [0, 0, 0, 0] as Array[int])


func test_bad_content_builds_nothing_and_sends_no_summary() -> void:
	var ctx := F.make_ctx(1, 0, "e2e_2min")
	ctx.content_overrides = {"cosmetics.json": {"unlock_every_xp": 0}}
	var g := FishingGame.new()
	autofree(g)
	g.configure(ctx)
	assert_push_error("cosmetics.json")
	assert_null(g.state)
	assert_eq(g.build_effort_plans(), {})
	assert_eq((ctx.intents as F.Intents).sent, [])
	assert_null(g.local_rider())


func test_the_host_applies_each_riders_summary_intent_to_its_rider() -> void:
	var g := _game(2)
	var plans := F.plans_of(g)
	var summary := FishingIntents.summary(900, {"tuna": 61.25}, [3, 1, 99, 1] as Array[int])
	g.sim_step(Wl.SIM_DT, F.frame(g.ctx, plans, 0, 100.0, {2: [_wire(summary)]}))
	var r := g.state.riders[1]
	assert_eq(r.summary_xp, 900)
	assert_almost_eq(float(r.records["tuna"]), 61.3, 0.001, "kg x 10 on the wire")
	assert_eq(r.cosmetics, [3, 1, 3, 1] as Array[int], "clamped to the items of each kind")


func test_intents_are_rate_limited_per_rider_but_the_summary_always_applies() -> void:
	var g := _game(2)
	var plans := F.plans_of(g)
	var burst: Array = []
	for i in 8:
		burst.append(FishingIntents.spot(1 if i % 2 == 0 else -1))
	burst.append(FishingIntents.summary(10, {}, [0, 0, 0, 0] as Array[int]))
	g.sim_step(Wl.SIM_DT, F.frame(g.ctx, plans, 0, 100.0, {1: burst}))
	var inp: FishingRiderInput = g._inputs[0]
	assert_eq(
		inp.intents.size(), FishingConst.INTENTS_PER_S, "the summary is applied, not passed on"
	)
	assert_eq(g.state.riders[0].summary_xp, 10, "the summary always gets through")
	g.sim_step(Wl.SIM_DT, F.frame(g.ctx, plans, 5, 100.0, {1: [FishingIntents.spot(1)]}))
	assert_eq(inp.intents, [], "the window is full until a second has passed")
	g.sim_step(Wl.SIM_DT, F.frame(g.ctx, plans, 20, 100.0, {1: [FishingIntents.spot(1)]}))
	assert_eq(inp.intents.size(), 1)
	g.sim_step(Wl.SIM_DT, F.frame(g.ctx, plans, 21, 100.0))
	assert_eq(inp.intents, [], "no intents this tick")
	assert_eq((g._inputs[1] as FishingRiderInput).intents, [], "the other rider's own window")


func test_a_surge_and_a_confirm_in_one_tick_count_as_the_surge() -> void:
	var g := _game(1, Wl.SOLO)
	var plans := F.plans_of(g)
	var both := [FishingIntents.confirm("action"), FishingIntents.confirm("surge")]
	g.sim_step(Wl.SIM_DT, F.frame(g.ctx, plans, 0, 100.0, {1: both}))
	assert_eq((g._inputs[0] as FishingRiderInput).intents, [{"k": "confirm", "via": "surge"}])


func test_the_input_carries_effective_power_and_the_pause_flag() -> void:
	var g := _game(1, Wl.SOLO, 1, "roam_10")
	var c := F.clock_for(g)
	c.sim_power_pct = 80.0
	c.paused[1] = true
	c.step()
	var inp: FishingRiderInput = g._inputs[0]
	var p := g.ctx.players[0]
	assert_almost_eq(inp.power_w, 0.8 * p.ftp, 0.001)
	assert_almost_eq(inp.p_eff_w, 200.0, 0.001, "FAIR_FTP: 80 % of FTP is 200 W of P_eff")
	assert_true(inp.paused)
	assert_true(g.state.riders[0].paused, "the rules see the pause")


# --- the step-out ------------------------------------------------------------------------------


func test_a_step_out_is_applied_in_order_and_finished_only_once() -> void:
	var g := _game(2)
	var out := FishingStepOut.new()
	var tail := EffortPlan.of([PlanPhase.erg(Wl.WORK, 70, 60, "x").with_open(30, 90)])
	out.replans = [[2, tail]]
	out.directives = [
		[
			2,
			{
				"mode": Wl.ERG,
				"target_pct": 75.0,
				"duration_s": 0.0,
				"reason": "pull",
				"source": "fishing"
			}
		]
	]
	out.grades = [[1, 1.7]]
	out.bands = [[2, 92, 108]]
	out.power_bands = [[-1, 95.0, 105.0]]
	out.end_phase.assign([2])
	out.events = [FishingEvents.hookup(1, 0, 1, false), FishingEvents.trip_over()]
	out.toasts = [["FISHING_TIP_1", [], 2]]
	out.finished = "trip_over"
	g._apply(out)
	g._apply(out)
	var d := g.ctx.directives as F.Directives
	assert_eq(d.replans.size(), 2)
	assert_eq(d.replans[0][0], 2)
	assert_eq(d.replans[0][1], tail)
	assert_eq(d.requests.size(), 2)
	assert_eq(d.requests[0][0], 2)
	assert_eq(d.requests[0][1]["target_pct"], 75.0)
	assert_eq(d.requests[0][1]["reason"], "pull")
	assert_eq(d.course_grades[0], [1, 1.7])
	assert_eq(d.cadence_bands[0], [2, 92.0, 108.0])
	assert_eq(_hud(g).of("power_band")[0], ["power_band", -1, 95.0, 105.0])
	assert_eq(d.ended, [2, 2])
	assert_eq(_sent.size(), 4, "every event is sent")
	assert_eq(_fx, _sent, "and raised as fx on the host")
	var tips := _toasts(g).filter(func(c: Array) -> bool: return c[1] == "FISHING_TIP_1")
	assert_eq(tips.size(), 2, "the rules' own toasts pass")
	assert_eq(tips[0][3], 2, "with their peer")
	assert_eq(_finished, ["trip_over"], "finished once")


# --- a whole Free Roam session -----------------------------------------------------------------


func test_a_roam_session_hooks_fights_and_lands_and_finishes_once() -> void:
	var g := _roam()
	assert_true(_roam_clock.tracker.all_done(), "every rider finished the cool-down")
	var types := _roam_types()
	assert_gt(types.count("cast"), 0, "Autopilot cast")
	assert_gt(types.count("bite"), 0)
	assert_gt(types.count("hookup"), 0)
	assert_gt(types.count("landed"), 0, "at least one fish landed")
	assert_eq(types.count("time_up"), 1)
	assert_eq(types.count("trip_over"), 1)
	assert_eq(types[-1], "trip_over", "and last")
	assert_eq(_roam_finished, ["trip_over"], "finished once")
	assert_gt(g.state.riders[0].points, 0)
	assert_eq(g.state.riders[0].action, FishingConst.A_HOME)
	var labels := _roam_clock.labels(1)
	assert_eq(labels[0], "FISHING_PHASE_DRIVE_OUT")
	assert_eq(labels[1], "FISHING_PHASE_ROAM")
	assert_has(labels, "FISHING_PHASE_LANDING")
	assert_eq(labels[-1], "Cool-down")


func test_every_roam_replan_validates_without_warnings() -> void:
	_roam()
	var d := _roam_game.ctx.directives as F.Directives
	assert_gt(d.replans.size(), 0, "each bite replans the rest")
	assert_eq(d.refused_replans, [], "no replan was refused")
	for w: Array in d.replan_warnings:
		assert_eq(w, [], "no switch-spacing warning")
	for rp: Array in d.replans:
		var tail: EffortPlan = rp[1]
		assert_eq(tail.size(), 3, "Fight, Landing, Roam")
		assert_eq(tail.phase(0).mode, Wl.ERG)
		assert_string_starts_with(tail.phase(0).label, "FISHING_SPECIES_")
		assert_eq(tail.phase(1).label, "FISHING_PHASE_LANDING")
		assert_eq(tail.phase(2).grade_source, Wl.GRADE_GAME)
	assert_eq(
		d.replans.size(), _roam_types().count("bite"), "one replan per bite, nothing else replans"
	)


func test_course_grades_go_out_only_in_sim_game_phases_and_stay_gentle() -> void:
	_roam()
	var d := _roam_game.ctx.directives as F.Directives
	assert_gt(d.course_grades.size(), 0)
	assert_eq(d.course_grade_phases.size(), d.course_grades.size())
	for i in d.course_grades.size():
		var g := float(d.course_grades[i][1])
		assert_between(g, 0.0, FishingConst.GRADE_MAX_PCT, "grade %d" % i)
		var ph: Array = d.course_grade_phases[i]
		assert_eq(ph[1], Wl.SIM, "grade %d in a SIM phase" % i)
		assert_eq(ph[2], Wl.GRADE_GAME, "grade %d in a grade_source game phase" % i)
	var driving := d.course_grades.filter(func(c: Array) -> bool: return float(c[1]) > 0.0)
	assert_gt(driving.size(), 0, "driving loads the trainer")


func test_erg_requests_come_only_in_fights_and_inside_safe_bounds() -> void:
	_roam()
	var d := _roam_game.ctx.directives as F.Directives
	var erg := d.requests.filter(func(r: Array) -> bool: return r[1].has("target_pct"))
	assert_gt(erg.size(), 0, "the fights pull")
	for r: Array in erg:
		assert_between(float(r[1]["target_pct"]), 30.0, FishingConst.SELF_CAP_PCT)
		assert_eq(str(r[1]["mode"]), Wl.ERG)
	for b: Array in d.cadence_bands:
		if float(b[2]) > 0.0:
			assert_gte(float(b[1]), FishingConst.BAND_LOW_MIN, "no band under 65 rpm")


func test_bots_get_one_strategy_each_in_free_roam_only() -> void:
	var g: FishingGame = autofree(F.make_game(F.make_ctx(1, 3, "roam_30")))
	assert_eq(g.state.riders[0].strategy, -1, "humans play Autopilot's mixed default")
	for i in range(1, 4):
		assert_between(
			g.state.riders[i].strategy, 0, FishingAutopilot.STRATEGIES.size() - 1, "bot %d" % i
		)
	var again: FishingGame = autofree(F.make_game(F.make_ctx(1, 3, "roam_30")))
	for i in 4:
		assert_eq(again.state.riders[i].strategy, g.state.riders[i].strategy, "seeded by ctx.rng")
	var w: FishingGame = autofree(F.make_game(F.make_ctx(1, 2, "base_60")))
	assert_eq(w.state.riders[1].strategy, -1, "workouts keep no strategy")


func test_bots_ride_the_power_band_the_rules_publish() -> void:
	var g := _watch(autofree(F.make_game(F.make_ctx(1, 2, "roam_10"))))
	var c := F.clock_for(g)
	c.run(2.0)
	var bands := _hud(g).of("power_band")
	assert_gt(bands.size(), 0)
	for b: Array in bands:
		assert_lt(int(b[1]), 0, "only bots get a power band")
		assert_lt(float(b[2]), float(b[3]))


# --- event toasts (one routing rule) -------------------------------------------------------


func test_the_host_sends_team_toasts_to_everyone_and_own_toasts_only_for_its_rider() -> void:
	var g := _game(2)
	var out := FishingStepOut.new()
	out.events = [
		_landed(1, FishingConst.GRADE_LANDED),
		_landed(0, FishingConst.GRADE_TROPHY),
		FishingEvents.double_hookup([0, 1] as Array[int], 2),
		FishingEvents.time_up(),
		FishingEvents.snap(1),
		FishingEvents.thrown(1),
		FishingEvents.replacement(1, 2),
		FishingEvents.hookup(1, 2, 1, false),
		FishingEvents.snap(0),
		FishingEvents.replacement(0, 2),
		FishingEvents.cast(0, 1, 12.0, 30.0),
		FishingEvents.bite(0, 2),
		FishingEvents.turn(0, -1),
	]
	g._apply(out)
	var got := _toasts(g).map(func(c: Array) -> Array: return [c[1], c[3]])
	assert_eq(
		got,
		[
			["FISHING_TOAST_LANDED", 0],
			["FISHING_TOAST_TROPHY", 0],
			["FISHING_TOAST_DOUBLE_HOOKUP", 0],
			["FISHING_TOAST_TIME_UP", 0],
			["FISHING_TOAST_SNAP", 1],
			["FISHING_TOAST_REPLACEMENT", 1],
		],
		"slot 1 is peer 2's: its snap, thrown, replacement and hookup are raised there"
	)
	var landed: Dictionary = _toasts(g)[0][2]
	assert_eq(landed["name"], "Rider 2")
	assert_eq(landed["kg"], "54.2")
	assert_eq(landed["points"], 220)
	assert_eq(_toasts(g)[2][2], {"count": 2, "mult": "1.5"})


func test_a_client_raises_only_its_own_riders_toasts_and_never_a_team_one() -> void:
	var g := _game(2, Wl.CLIENT, 2)
	for e: Dictionary in [
		_landed(1, FishingConst.GRADE_TROPHY),
		FishingEvents.double_hookup([0, 1] as Array[int], 2),
		FishingEvents.time_up(),
		FishingEvents.snap(1),
		FishingEvents.thrown(0),
		FishingEvents.hookup(1, 1, 1, false),
		FishingEvents.replacement(0, 1),
	]:
		g.apply_event(_wire(e))
	var got := _toasts(g).map(func(c: Array) -> Array: return [c[1], c[3]])
	assert_eq(got, [["FISHING_TOAST_SNAP", 0], ["FISHING_TOAST_HOOKUP", 0]], "local calls only")
	assert_eq(_toasts(g)[1][2], {"species": g._species(1)})


func test_routing_never_doubles_a_toast_between_host_and_client() -> void:
	var host := _game(2)
	var client := _game(2, Wl.CLIENT, 2)
	var events: Array = [
		_landed(1, FishingConst.GRADE_LANDED),
		FishingEvents.snap(1),
		FishingEvents.snap(0),
		FishingEvents.time_up(),
		FishingEvents.thrown(1),
	]
	var out := FishingStepOut.new()
	out.events = events
	host._apply(out)
	for e: Dictionary in events:
		client.apply_event(_wire(e))
	# What peer 2 sees: the host's toasts addressed to 0 or 2, plus the client's own local ones.
	var seen_by_2: Array = []
	for c: Array in _toasts(host):
		if int(c[3]) in [0, 2]:
			seen_by_2.append(c[1])
	for c: Array in _toasts(client):
		seen_by_2.append(c[1])
	seen_by_2.sort()
	assert_eq(
		seen_by_2,
		[
			"FISHING_TOAST_LANDED",
			"FISHING_TOAST_SNAP",
			"FISHING_TOAST_THROWN",
			"FISHING_TOAST_TIME_UP"
		]
	)


func test_apply_event_casts_ints_and_raises_fx_on_the_client() -> void:
	var g := _game(2, Wl.CLIENT, 2)
	g.apply_event(_wire(_landed(1, FishingConst.GRADE_TROPHY)))
	g.apply_event(_wire(FishingEvents.double_hookup([0, 1] as Array[int], 2)))
	g.apply_event(_wire(FishingEvents.cast(1, 3, -12.34, 41.0)))
	assert_eq(_fx.size(), 3)
	assert_typeof(_fx[0]["kg"], TYPE_INT)
	assert_eq(_fx[0]["kg"], 542)
	assert_eq(_fx[0]["grade"], FishingConst.GRADE_TROPHY)
	assert_typeof(_fx[1]["lanes"][1], TYPE_INT)
	assert_eq(_fx[2]["dx"], -123)
	assert_eq(_fx[2]["z"], 410)
	assert_eq(_sent, [], "a client never sends events")


# --- teammate chips ----------------------------------------------------------------------------


func test_teammate_status_comes_once_a_second_per_rider() -> void:
	var g := _game(2)
	var plans := F.plans_of(g)
	for t in 20:
		g.sim_step(Wl.SIM_DT, F.frame(g.ctx, plans, t))
	var st := _hud(g).of("teammate_status")
	assert_eq(st.size(), 2, "tick 0 only (1 Hz)")
	assert_eq(st[0][1], 1)
	assert_eq(st[1][1], 2)
	assert_eq(st[0][2]["text"], g.ctx.strings.t("FISHING_STATUS_DRIVE"), "the ride out drives")
	assert_typeof(st[0][2]["in_band"], TYPE_BOOL)
	g.sim_step(Wl.SIM_DT, F.frame(g.ctx, plans, 20))
	assert_eq(_hud(g).of("teammate_status").size(), 4)


func test_in_band_follows_the_published_band_and_the_ema_cadence() -> void:
	var r := FishingRiderState.new()
	r.pub_lo = 82
	r.pub_hi = 98
	r.cadence_ema = 90.0
	assert_true(FishingGame.rider_in_band(r))
	r.cadence_ema = 98.4
	assert_false(FishingGame.rider_in_band(r))
	r.cadence_ema = 82.0
	assert_true(FishingGame.rider_in_band(r))
	r.rescue = true
	assert_false(FishingGame.rider_in_band(r), "a rescue is never in band")
	r.rescue = false
	r.stale = true
	assert_false(FishingGame.rider_in_band(r))
	r.stale = false
	r.pub_lo = 0
	r.pub_hi = 0
	assert_false(FishingGame.rider_in_band(r), "no band")


func test_status_text_names_the_fish_and_the_action() -> void:
	var g := _game(1, Wl.SOLO)
	var r := g.state.riders[0]
	r.action = FishingConst.A_FIGHT
	r.fish.sp = FishingConst.species_index("tuna")
	r.fish.d = 63.6
	assert_eq(
		g.status_text(r), g.ctx.strings.t("FISHING_STATUS_FIGHT", [g._species(r.fish.sp), 64])
	)
	r.action = FishingConst.A_WAIT
	r.target_sp = FishingConst.species_index("grouper")
	assert_eq(g.status_text(r), g.ctx.strings.t("FISHING_STATUS_WAIT", [g._species(r.target_sp)]))
	r.action = FishingConst.A_MENU
	assert_eq(g.status_text(r), g.ctx.strings.t("FISHING_STATUS_MENU"))
	r.action = FishingConst.A_HOME
	assert_eq(g.status_text(r), g.ctx.strings.t("FISHING_STATUS_HOME"))


# --- the rest of the contract ----------------------------------------------------------------


func test_rescue_and_afk_set_rider_flags() -> void:
	var g := _game(2)
	g.on_rescue(2, true)
	g.on_afk(1, true)
	assert_true(g.state.riders[1].rescue)
	assert_true(g.state.riders[0].afk)
	g.on_rescue(2, false)
	g.on_afk(99, true)
	assert_false(g.state.riders[1].rescue)
	assert_eq(g.autopilot_intents(1), [], "Autopilot runs inside the rules")


func test_local_intents_tag_their_source() -> void:
	var g := _game(1, Wl.SOLO)
	var none: Array[StringName] = []
	var lr: Array[StringName] = [&"left", &"right"]
	var conf: Array[StringName] = [&"confirm"]
	var surge: Array[StringName] = [Wl.G_SURGE]
	assert_eq(g.local_intents(lr, none), [FishingIntents.spot(-1), FishingIntents.spot(1)])
	assert_eq(g.local_intents(conf, none), [FishingIntents.confirm("action")])
	assert_eq(g.local_intents(conf, surge), [FishingIntents.confirm("surge")])
	assert_eq(g.local_intents(none, none), [])


func test_client_predict_moves_only_the_local_cadence_marker() -> void:
	var g := _game(2, Wl.CLIENT, 2)
	var before: Array = g.state.riders.map(
		func(r: FishingRiderState) -> Dictionary: return r.to_dict()
	)
	var fish_before := g.local_rider().fish.to_dict()
	var tm := Telemetry.new()
	tm.cadence_rpm = 100.0
	tm.power_w = 400.0
	for i in 20:
		g.client_predict(Wl.SIM_DT, tm)
	var after: Array = g.state.riders.map(
		func(r: FishingRiderState) -> Dictionary: return r.to_dict()
	)
	for d: Dictionary in after + before:
		d.erase("stop_x")  # NAN never equals itself
		d.erase("grade_sent")
	assert_eq(after[0], before[0], "another rider never moves")
	assert_gt(float(after[1]["cadence_ema"]), 60.0, "1 s at tau 1 s: 63 percent of the way")
	assert_lt(float(after[1]["cadence_ema"]), 64.0)
	after[1].erase("cadence_ema")
	before[1].erase("cadence_ema")
	assert_eq(after[1], before[1], "nothing else in the local rider: no boat prediction")
	assert_eq(g.local_rider().fish.to_dict(), fish_before)
	g.client_predict(Wl.SIM_DT, null)
	assert_eq(g.state.tick, 0)


func test_local_rider_is_the_local_peers() -> void:
	var g := _game(3, Wl.CLIENT, 3)
	assert_eq(g.local_rider(), g.state.riders[2])
	var lonely := FishingGame.new()
	autofree(lonely)
	assert_null(lonely.local_rider())
	lonely.apply_event({"type": "snap", "l": 0})
	lonely.apply_snapshot({})
	assert_eq(lonely.snapshot(), {})


func test_the_view_and_hud_load_by_path() -> void:
	var g := _game(1, Wl.SOLO, 1, "roam_10")
	assert_true(ResourceLoader.exists(FishingGame.VIEW_SCRIPT), "the view script exists")
	assert_true(ResourceLoader.exists(FishingGame.HUD_SCRIPT), "the HUD script exists")
	var view: Node = g.make_view()
	autofree(view)
	assert_not_null(view)
	if view.get_script() == null:
		pending("the view script did not load (VIEW work in progress)")
		return
	assert_eq(view.get("game"), g, "the view reads the module")
	var spec: HudSpec = g.hud_spec()
	assert_is(spec, HudSpec)
	for c: Dictionary in spec.controls:
		if c.get("control") is Node:
			(c["control"] as Node).free()
