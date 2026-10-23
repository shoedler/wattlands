extends GutTest
## FishingGame's wiring (GAME_SDK 4, 10.2, 11, 12): the summary intent, the step-out order,
## fx_event on every peer, the event-toast routing rule, teammate chips, intents, rescue and AFK,
## and client prediction. The rules are the G0 stub in this branch, so events come from
## hand-built FishingStepOuts.

const F := preload("res://tests/games/fishing/fishing_fakes.gd")

var _fx: Array = []
var _sent: Array = []
var _finished: Array = []


func before_each() -> void:
	_fx.clear()
	_sent.clear()
	_finished.clear()


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
	assert_eq(g.local_lane().peer, 2)
	assert_eq(
		g.local_lane().cosmetics, [2, 0, 1, 0] as Array[int], "the local lane wears it at once"
	)
	assert_eq(g.state.lanes[0].cosmetics, [0, 0, 0, 0] as Array[int])


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
	assert_null(g.local_lane())


func test_the_host_applies_each_riders_summary_intent_to_its_lane() -> void:
	var g := _game(2)
	var plans := F.plans_of(g)
	var summary := FishingIntents.summary(900, {"tuna": 61.25}, [3, 1, 99, 1] as Array[int])
	g.sim_step(Wl.SIM_DT, F.frame(g.ctx, plans, 0, 100.0, {2: [_wire(summary)]}))
	var l := g.state.lanes[1]
	assert_eq(l.summary_xp, 900)
	assert_almost_eq(float(l.records["tuna"]), 61.3, 0.001, "kg x 10 on the wire")
	assert_eq(l.cosmetics, [3, 1, 3, 1] as Array[int], "clamped to the items of each kind")


func test_intents_are_rate_limited_per_rider_but_the_summary_always_passes() -> void:
	var g := _game(2)
	var plans := F.plans_of(g)
	var burst: Array = []
	for i in 8:
		burst.append(FishingIntents.spot(1 if i % 2 == 0 else -1))
	burst.append(FishingIntents.summary(10, {}, [0, 0, 0, 0] as Array[int]))
	g.sim_step(Wl.SIM_DT, F.frame(g.ctx, plans, 0, 100.0, {1: burst}))
	var inp: FishingLaneInput = g._inputs[0]
	assert_eq(inp.intents.size(), FishingConst.INTENTS_PER_S + 1)
	assert_eq(inp.intents[-1]["k"], "summary")
	g.sim_step(Wl.SIM_DT, F.frame(g.ctx, plans, 5, 100.0, {1: [FishingIntents.spot(1)]}))
	assert_eq(inp.intents, [], "the window is full until a second has passed")
	g.sim_step(Wl.SIM_DT, F.frame(g.ctx, plans, 20, 100.0, {1: [FishingIntents.spot(1)]}))
	assert_eq(inp.intents.size(), 1)
	g.sim_step(Wl.SIM_DT, F.frame(g.ctx, plans, 21, 100.0))
	assert_eq(inp.intents, [], "no intents this tick")
	assert_eq((g._inputs[1] as FishingLaneInput).intents, [], "the other rider's own window")


func test_a_surge_and_a_confirm_in_one_tick_count_as_the_surge() -> void:
	var g := _game(1, Wl.SOLO)
	var plans := F.plans_of(g)
	var both := [FishingIntents.confirm("action"), FishingIntents.confirm("surge")]
	g.sim_step(Wl.SIM_DT, F.frame(g.ctx, plans, 0, 100.0, {1: both}))
	assert_eq((g._inputs[0] as FishingLaneInput).intents, [{"k": "confirm", "via": "surge"}])


# --- the step-out ------------------------------------------------------------------------------


func test_a_step_out_is_applied_in_order_and_finished_only_once() -> void:
	var g := _game(2)
	var out := FishingStepOut.new()
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
	out.bands = [[2, 92, 108]]
	out.end_phase.assign([2])
	out.events = [FishingEvents.hookup(1, 0, 1, false), FishingEvents.trip_over()]
	out.toasts = [["FISHING_TOAST_LANDED", [], 0], ["FISHING_STATUS_PICK", ["x"], 2]]
	out.finished = "trip_over"
	g._apply(out)
	g._apply(out)
	var d := g.ctx.directives as F.Directives
	assert_eq(d.requests.size(), 2)
	assert_eq(d.requests[0][0], 2)
	assert_eq(d.requests[0][1]["target_pct"], 75.0)
	assert_eq(d.requests[0][1]["reason"], "pull")
	assert_eq(d.cadence_bands[0], [2, 92.0, 108.0])
	assert_eq(g.state.lanes[1].pub_lo, 92, "the published band is kept on the lane")
	assert_eq(g.state.lanes[1].pub_hi, 108)
	assert_eq(d.ended, [2, 2])
	assert_eq(_sent.size(), 4, "every event is sent")
	assert_eq(_fx, _sent, "and raised as fx on the host")
	var keys := _toasts(g).map(func(c: Array) -> String: return c[1])
	assert_false(keys.has("FISHING_TOAST_LANDED"), "a rules toast under an event key is dropped")
	assert_eq(keys.count("FISHING_STATUS_PICK"), 2, "the rules' own toasts pass")
	assert_eq(_toasts(g)[0][3], 2, "with their peer")
	assert_eq(_finished, ["trip_over"], "finished once")


func test_sim_step_steps_the_rules_and_ends_a_free_trip_once() -> void:
	var g := _game(1, Wl.SOLO, 1, "free_20")
	var c := F.clock_for(g)
	assert_true(c.run_until_done(1500.0), "ride out, the open-ended Reel, finished, cool-down")
	assert_eq(_finished, ["trip_over"])
	assert_eq(_sent.map(func(e: Dictionary) -> String: return e["type"]), ["trip_over"])
	assert_eq(_fx.size(), 1)
	assert_eq(c.changes[-1]["ended_by"], Wl.ENDED_FINISHED, "the Reel ended by finished")
	assert_almost_eq(float(c.changes[-1]["t"]), g.state.fishing_end_t, 0.051)


# --- event toasts (one routing rule) -------------------------------------------------------


func test_the_host_sends_team_toasts_to_everyone_and_own_toasts_only_for_its_rider() -> void:
	var g := _game(2)
	var out := FishingStepOut.new()
	out.events = [
		_landed(1, FishingConst.GRADE_LANDED),
		_landed(0, FishingConst.GRADE_TROPHY),
		FishingEvents.double_hookup([0, 1] as Array[int], 2),
		FishingEvents.frenzy(1),
		FishingEvents.snap(1),
		FishingEvents.thrown(1),
		FishingEvents.replacement(1, 2),
		FishingEvents.hookup(1, 2, 1, false),
		FishingEvents.strike_miss(1, 2),
		FishingEvents.snap(0),
		FishingEvents.replacement(0, 2),
		FishingEvents.cast(0, 1, 2, 55.0),
		FishingEvents.bite(0, 2),
	]
	g._apply(out)
	var got := _toasts(g).map(func(c: Array) -> Array: return [c[1], c[3]])
	assert_eq(
		got,
		[
			["FISHING_TOAST_LANDED", 0],
			["FISHING_TOAST_TROPHY", 0],
			["FISHING_TOAST_DOUBLE_HOOKUP", 0],
			["FISHING_TOAST_FRENZY", 0],
			["FISHING_TOAST_SNAP", 1],
			["FISHING_TOAST_REPLACEMENT", 1],
		],
		"lane 1 is peer 2's: its snap, thrown, replacement, hookup and miss are raised there"
	)
	var landed: Array = _toasts(g)[0][2]
	assert_eq(landed[0], "Rider 2")
	assert_eq(landed[2], "54.2")
	assert_eq(landed[3], 220)
	assert_eq(_toasts(g)[2][2], [2, "1.5"])


func test_a_client_raises_only_its_own_riders_toasts_and_never_a_team_one() -> void:
	var g := _game(2, Wl.CLIENT, 2)
	for e: Dictionary in [
		_landed(1, FishingConst.GRADE_TROPHY),
		FishingEvents.double_hookup([0, 1] as Array[int], 2),
		FishingEvents.frenzy(1),
		FishingEvents.snap(1),
		FishingEvents.thrown(0),
		FishingEvents.hookup(1, 1, 1, false),
		FishingEvents.replacement(0, 1),
	]:
		g.apply_event(_wire(e))
	var got := _toasts(g).map(func(c: Array) -> Array: return [c[1], c[3]])
	assert_eq(got, [["FISHING_TOAST_SNAP", 0], ["FISHING_TOAST_HOOKUP", 0]], "local calls only")
	assert_eq(_toasts(g)[1][2], [g._species(1)])


func test_routing_never_doubles_a_toast_between_host_and_client() -> void:
	var host := _game(2)
	var client := _game(2, Wl.CLIENT, 2)
	var events: Array = [
		_landed(1, FishingConst.GRADE_LANDED),
		FishingEvents.snap(1),
		FishingEvents.snap(0),
		FishingEvents.frenzy(0),
		FishingEvents.strike_miss(1, 0),
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
			"FISHING_TOAST_FRENZY",
			"FISHING_TOAST_LANDED",
			"FISHING_TOAST_SNAP",
			"FISHING_TOAST_STRIKE_MISS"
		]
	)


func test_apply_event_casts_ints_and_raises_fx_on_the_client() -> void:
	var g := _game(2, Wl.CLIENT, 2)
	g.apply_event(_wire(_landed(1, FishingConst.GRADE_TROPHY)))
	g.apply_event(_wire(FishingEvents.double_hookup([0, 1] as Array[int], 2)))
	assert_eq(_fx.size(), 2)
	assert_typeof(_fx[0]["kg"], TYPE_INT)
	assert_eq(_fx[0]["kg"], 542)
	assert_eq(_fx[0]["grade"], FishingConst.GRADE_TROPHY)
	assert_typeof(_fx[1]["lanes"][1], TYPE_INT)
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
	assert_eq(st[0][2]["text"], g.ctx.strings.t("FISHING_STATUS_RIDE_OUT"))
	assert_false(st[0][2]["in_band"], "no published band yet")
	g.sim_step(Wl.SIM_DT, F.frame(g.ctx, plans, 20))
	assert_eq(_hud(g).of("teammate_status").size(), 4)


func test_in_band_follows_the_published_band_and_the_ema_cadence() -> void:
	var l := FishingLaneState.new()
	l.pub_lo = 82
	l.pub_hi = 98
	l.cadence_ema = 90.0
	assert_true(FishingGame.lane_in_band(l))
	l.cadence_ema = 98.4
	assert_false(FishingGame.lane_in_band(l))
	l.cadence_ema = 82.0
	assert_true(FishingGame.lane_in_band(l))
	l.rescue = true
	assert_false(FishingGame.lane_in_band(l), "a rescue is never in band")
	l.rescue = false
	l.stale = true
	assert_false(FishingGame.lane_in_band(l))
	l.stale = false
	l.pub_lo = 0
	l.pub_hi = 0
	assert_false(FishingGame.lane_in_band(l), "no band")


func test_status_text_names_the_fish_and_its_distance() -> void:
	var g := _game(1, Wl.SOLO)
	var l := g.state.lanes[0]
	l.state = FishingConst.ST_FIGHT
	l.fish.sp = FishingConst.species_index("tuna")
	l.fish.d = 63.6
	assert_eq(
		g.status_text(l), g.ctx.strings.t("FISHING_STATUS_FIGHT", [g._species(l.fish.sp), 64])
	)
	l.state = FishingConst.ST_REEL
	l.lure_d = 41.2
	assert_eq(g.status_text(l), g.ctx.strings.t("FISHING_STATUS_REEL", [41]))
	l.state = FishingConst.ST_HOME
	assert_eq(g.status_text(l), g.ctx.strings.t("FISHING_STATUS_HOME"))


# --- the rest of the contract ----------------------------------------------------------------


func test_rescue_and_afk_set_lane_flags() -> void:
	var g := _game(2)
	g.on_rescue(2, true)
	g.on_afk(1, true)
	assert_true(g.state.lanes[1].rescue)
	assert_true(g.state.lanes[0].afk)
	g.on_rescue(2, false)
	g.on_afk(99, true)
	assert_false(g.state.lanes[1].rescue)
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
	var before: Array = g.state.lanes.map(
		func(l: FishingLaneState) -> Dictionary: return l.to_dict()
	)
	var fish_before := g.local_lane().fish.to_dict()
	var tm := Telemetry.new()
	tm.cadence_rpm = 100.0
	tm.power_w = 400.0
	for i in 20:
		g.client_predict(Wl.SIM_DT, tm)
	var after: Array = g.state.lanes.map(
		func(l: FishingLaneState) -> Dictionary: return l.to_dict()
	)
	assert_eq(after[0], before[0], "another lane never moves")
	assert_gt(float(after[1]["cadence_ema"]), 60.0, "1 s at tau 1 s: 63 percent of the way")
	assert_lt(float(after[1]["cadence_ema"]), 64.0)
	after[1].erase("cadence_ema")
	before[1].erase("cadence_ema")
	assert_eq(after[1], before[1], "nothing else in the local lane")
	assert_eq(g.local_lane().fish.to_dict(), fish_before)
	g.client_predict(Wl.SIM_DT, null)
	assert_eq(g.state.tick, 0)


func test_local_lane_is_the_local_peers() -> void:
	var g := _game(3, Wl.CLIENT, 3)
	assert_eq(g.local_lane(), g.state.lanes[2])
	var lonely := FishingGame.new()
	autofree(lonely)
	assert_null(lonely.local_lane())
	lonely.apply_event({"type": "snap", "l": 0})
	lonely.apply_snapshot({})
	assert_eq(lonely.snapshot(), {})
