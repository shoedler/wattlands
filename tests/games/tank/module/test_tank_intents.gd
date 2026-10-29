extends GutTest
## The module's intent flow (brief 2.5, 2.6): keys to intents, ownership by engine, the 5 a second
## per peer limit, the Autopilot fallback of a human and the reserve station.

const F := preload("res://tests/games/tank/tank_fakes.gd")
## Game time 700 s: Stage 2's Advance (phase 4) in every plan.
const TICK := 14000

var _actions: Array[StringName] = []
var _gestures: Array[StringName] = []


## A module on the fixture state (stage 2 Advance) for `crew`; `human` makes every slot a human
## without the Autopilot flag. The plans are built (the engine of each phase is read from them).
func _game(crew: int, human: bool = false) -> TankGame:
	var ctx := F.make_ctx(crew)
	for p in ctx.players:
		p.autopilot = not human
	var g: TankGame = autofree(F.make_game(ctx))
	g.state = TankFixtures.state(crew)
	g.state.content = g.content
	g.build_effort_plans()
	for r in g.state.riders:
		r.autopilot = not human
	g.state.enemies.clear()
	g.state.obstacles.clear()
	g.state.hull.facing = TankIds.FACE_RIGHT
	g.state.hull.traverse_s = 0.0
	return g


func _frame(g: TankGame, tick: int, intents: Dictionary) -> InputFrame:
	return F.frame(g.ctx, g.plans, tick, 100.0, intents)


func _kinds(list: Array) -> Array:
	return list.map(func(i: Dictionary) -> String: return str(i["k"]))


func _rear_enemy(g: TankGame) -> void:
	g.state.enemies.append(
		TankFixtures._enemy(90, TankIds.ENEMY_MEDIUM, g.state.camera_x() + 10.0, 30.0, -1)
	)


func _wreck(g: TankGame) -> TankObstacleState:
	var ob := TankObstacleState.new()
	ob.id = 80
	ob.code = TankIds.obstacle_code(TankIds.OBST_WRECK)
	ob.x_px = g.state.hull.x_px + g.state.hull.hull_w + 150.0
	ob.w = 72
	g.state.obstacles.append(ob)
	return ob


func _local(
	g: TankGame, peer: int, actions: Array[StringName], gestures: Array[StringName]
) -> Array:
	g.ctx.local_peer = peer
	return g.local_intents(actions, gestures)


# --- Keys and gestures ------------------------------------------------------------------------


func test_a_surge_is_only_ever_over() -> void:
	var g := _game(3)
	var surge: Array[StringName] = [Wl.G_SURGE]
	var confirm: Array[StringName] = [&"confirm"]
	var every: Array[StringName] = [&"confirm", &"up", &"down", &"left", &"right", &"item", &"swap"]
	var engines := {}
	for r in g.state.riders:
		engines[r.engine] = r.peer
	for engine: String in engines:
		var peer: int = engines[engine]
		var got := _local(g, peer, confirm, surge)
		for i: Dictionary in got:
			assert_eq(i["k"], "over", "%s: a surge never fires or latches" % engine)
			assert_eq(i["via"], "surge")
		var with_keys := _local(g, peer, every, surge)
		for i: Dictionary in with_keys:
			if i["via"] == "surge":
				assert_eq(i["k"], "over")
	assert_eq(
		_local(g, engines["diesel"], _actions, surge), [], "Surge to evade needs no intent (v2)"
	)
	assert_eq(_local(g, engines["steam"], _actions, surge), [{"k": "over", "via": "surge"}])
	assert_eq(_local(g, engines["dynamo"], _actions, surge), [], "the dynamo has no sprint")


func test_the_crew_keys() -> void:
	var g := _game(3)
	var by_engine := {}
	for r in g.state.riders:
		by_engine[r.engine] = r.peer
	var act := func(peer: int, a: StringName) -> Array:
		var acts: Array[StringName] = [a]
		return _local(g, peer, acts, _gestures)
	var dyn: int = by_engine["dynamo"]
	assert_eq(act.call(dyn, &"up"), [{"k": "aim", "d": 1, "via": "action"}])
	assert_eq(act.call(dyn, &"left"), [{"k": "target", "d": -1, "via": "action"}])
	assert_eq(act.call(dyn, &"right"), [{"k": "target", "d": 1, "via": "action"}])
	assert_eq(act.call(dyn, &"ability_2"), [{"k": "traverse", "via": "action"}])
	assert_eq(act.call(dyn, &"confirm"), [{"k": "fire", "via": "action"}])
	assert_eq(act.call(dyn, &"ability_1"), [], "the dynamo has no sprint intent")
	assert_eq(act.call(by_engine["diesel"], &"ability_1"), [], "v2: no Ram")
	assert_eq(act.call(by_engine["diesel"], &"confirm"), [], "the diesel has no gun")
	assert_eq(act.call(by_engine["steam"], &"ability_1"), [{"k": "over", "via": "action"}])
	assert_eq(act.call(by_engine["steam"], &"confirm"), [{"k": "latch", "via": "action"}])
	assert_eq(act.call(by_engine["steam"], &"up"), [], "the loader does not aim")


func test_a_surge_that_also_arrives_as_confirm_counts_as_the_surge() -> void:
	var g := _game(3)
	var steam := 0
	for r in g.state.riders:
		if r.engine == TankIds.ENGINE_STEAM:
			steam = r.peer
	var both: Array[StringName] = [&"confirm", &"ability_1"]
	var surge: Array[StringName] = [Wl.G_SURGE]
	assert_eq(_local(g, steam, both, surge), [{"k": "over", "via": "surge"}], "one over, no latch")
	assert_eq(_local(_game(1), 1, both, surge), [], "the solo driver neither fires nor latches")


func test_every_local_intent_normalizes() -> void:
	var g := _game(3)
	var all_keys: Array[StringName] = [
		&"up", &"down", &"left", &"right", &"item", &"swap", &"ability_1", &"ability_2", &"confirm"
	]
	var n := 0
	for r in g.state.riders:
		for raw: Dictionary in _local(g, r.peer, all_keys, _gestures):
			assert_false(TankIntents.normalize(raw).is_empty(), JSON.stringify(raw))
			n += 1
	assert_gt(n, 0, "the Gun and the Loader have keys")


# --- Ownership, the limit and the next tick --------------------------------------------------------


func test_each_engine_may_send_only_its_own_intents() -> void:
	var g := _game(3)
	var everything: Array = []
	for k: String in TankIds.INTENT_KINDS:
		var to := "next" if k == TankIds.INTENT_SEAT else "turret"
		everything.append({"k": k, "to": to, "d": 1})
	var intents := {}
	for p in g.ctx.players:
		intents[p.peer_id] = everything
	var got := g._collect_intents(_frame(g, TICK, intents))
	for r in g.state.riders:
		var kinds: Array = _kinds(got.get(r.peer, []))
		var want: Array = (TankIntents.OWNERS[r.engine] as Array).duplicate()
		want = want.filter(func(k: String) -> bool: return TankIds.INTENT_KINDS.has(k))
		kinds.sort()
		want.sort()
		assert_eq(kinds, want, "%s sends exactly what it owns" % r.engine)


func test_junk_intents_are_dropped_before_they_count() -> void:
	var g := _game(2)
	var junk: Array = [
		"fire", 5, {"k": "banana"}, {"k": "lever", "to": "sideways"}, {"k": "aim", "d": 2}, {}
	]
	for i in 8:
		junk.append({"k": "teleport"})
	junk.append({"k": "traverse"})
	var got := g._collect_intents(_frame(g, TICK, {2: junk}))
	assert_eq(_kinds(got[2]), ["traverse"], "the junk did not eat the budget")


func test_five_a_second_per_peer_and_the_window_rolls() -> void:
	var g := _game(3)
	var by_engine := {}
	for r in g.state.riders:
		by_engine[r.engine] = r.peer
	var dyn: int = by_engine["dynamo"]
	var steam: int = by_engine["steam"]
	var accepted := 0
	for tick in range(TICK, TICK + 20):
		var got := g._collect_intents(_frame(g, tick, {dyn: [{"k": "fire"}, {"k": "fire"}]}))
		accepted += (got.get(dyn, []) as Array).size()
	assert_eq(accepted, TankConst.INTENTS_PER_S, "5 in the first second, however they arrive")
	var got := g._collect_intents(
		_frame(g, TICK + 20, {dyn: [{"k": "fire"}], steam: [{"k": "latch"}]})
	)
	assert_eq((got[dyn] as Array).size(), 1, "the next second starts afresh")
	assert_eq((got[steam] as Array).size(), 1, "another peer has its own budget")
	var burst: Array = []
	for i in 9:
		burst.append({"k": "latch"})
	got = g._collect_intents(_frame(g, TICK + 40, {steam: burst}))
	assert_eq((got[steam] as Array).size(), 5)


func test_only_peers_of_the_session_are_read() -> void:
	var g := _game(1)
	var f := _frame(g, TICK, {1: [{"k": "traverse"}]})
	var stranger := Telemetry.new()
	stranger.peer_id = 77
	stranger.intents = [{"k": "fire"}]
	f.players[77] = stranger
	var got := g._collect_intents(f)
	assert_eq(got.keys(), [1])


func test_what_passes_reaches_the_rules_input_in_order() -> void:
	var g := _game(2)
	var f := _frame(
		g, TICK, {2: [{"k": "aim", "d": 1}, {"k": "fire"}, {"k": "traverse", "via": "button"}]}
	)
	var inp := TankInputs.from_frame(f, g.ctx.players, g.plans, g._collect_intents(f), {}, {})
	var got: Array = inp.rider(2).intents.map(func(n: Dictionary) -> String: return str(n["k"]))
	assert_eq(got, ["aim", "fire", "traverse"])
	assert_eq(inp.rider(2).intents[2]["via"], "button")
	assert_eq(inp.rider(2).intents[0]["d"], 1, "normalized ints")


# --- The Autopilot fallback ------------------------------------------------------------------------


func test_a_human_with_only_junk_or_unowned_intents_keeps_the_rear_traverses() -> void:
	var g := _game(2, true)
	_rear_enemy(g)
	var ram_by_surge := {"k": "ram", "via": "surge"}
	var got := g._collect_intents(_frame(g, TICK, {2: [ram_by_surge]}))
	assert_eq(_kinds(got[2]), ["traverse"], "v2's junk ram is dropped; the Autopilot traverses")
	assert_true(got[2][0]["auto"], "tagged auto")
	assert_true(g.state.rider(2).fallback, "a dropped intent does not end the fallback")
	var over_and_ram := [{"k": "over", "via": "surge"}, {"k": "ram", "via": "action"}]
	g._collect_intents(_frame(g, TICK + 1, {2: over_and_ram}))
	assert_true(
		g.state.rider(2).fallback, "over and ram never end it (the gunner's over is dropped)"
	)


func test_a_human_with_only_a_junk_intent_keeps_the_obstacle_shots() -> void:
	var g := _game(2, true)
	var ob := _wreck(g)
	g.state.hull.target_id = ob.id
	g.state.hull.loaded = TankIds.SHELL_LIGHT
	g.state.hull.elev_deg = 4.0
	g.state.hull.elev_target_deg = 4.0
	var got := g._collect_intents(_frame(g, TICK, {2: [{"k": "ram", "via": "surge"}]}))
	assert_eq(_kinds(got[2]), ["fire"])
	assert_true(g.state.rider(2).fallback)


func test_a_deliberate_intent_ends_the_fallback_for_good() -> void:
	for kind in ["seat", "aim", "target", "traverse", "fire", "latch"]:
		var g := _game(3, true)
		_rear_enemy(g)
		var peer := 0
		for r in g.state.riders:
			if peer == 0 and TankIntents.owned(kind, r.engine):
				peer = r.peer
		var raw := {"k": kind, "to": "next" if kind == "seat" else "turret", "d": 1}
		var got := g._collect_intents(_frame(g, TICK, {peer: [raw]}))
		assert_false(g.state.rider(peer).fallback, "%s ends it" % kind)
		assert_true(_kinds(got[peer]).has(kind), "%s itself is still applied" % kind)
		got = g._collect_intents(_frame(g, TICK + 20, {}))
		assert_false(got.has(peer), "%s: and the Autopilot stops" % kind)
		assert_eq(g.autopilot_intents(peer), [], "%s: also from the platform's call" % kind)


func test_an_intent_the_rider_may_not_send_is_no_action() -> void:
	var g := _game(3, true)
	var diesel := 0
	for r in g.state.riders:
		if r.engine == TankIds.ENGINE_DIESEL:
			diesel = r.peer
	g._collect_intents(_frame(g, TICK, {diesel: [{"k": "fire"}, {"k": "lever", "to": "drive"}]}))
	assert_true(
		g.state.rider(diesel).fallback, "the diesel cannot fire or lever, so nothing was done"
	)


func test_a_human_off_the_fallback_plays_alone_until_the_station_goes_to_reserve() -> void:
	var g := _game(2, true)
	_rear_enemy(g)
	g.state.rider(2).fallback = false
	assert_false(g._collect_intents(_frame(g, TICK, {})).has(2))
	g.on_afk(2, true)
	var got := g._collect_intents(_frame(g, TICK + 1, {}))
	assert_eq(_kinds(got[2]), ["traverse"], "a reserve station runs on the Autopilot")
	g.on_afk(2, false)
	assert_false(g._collect_intents(_frame(g, TICK + 2, {})).has(2))


func test_autopilot_riders_and_bots_get_the_autopilot_from_the_platform_call() -> void:
	var g := _game(2)
	_rear_enemy(g)
	assert_eq(_kinds(g.autopilot_intents(2)), ["traverse"], "an Autopilot human on the fallback")
	var plain := g._collect_intents(_frame(g, TICK, {}))
	assert_false(plain.has(2), "the module does not add it a second time")
	g.state.rider(2).is_bot = true
	g.state.rider(2).fallback = false
	assert_eq(_kinds(g.autopilot_intents(2)), ["traverse"], "a bot always plays it")
	assert_eq(g.autopilot_intents(42), [], "an unknown peer")


func test_the_platform_merged_autopilot_never_counts_as_a_deliberate_intent() -> void:
	var g := _game(2)
	var merged := [
		{"k": "traverse", "auto": 1}, {"k": "fire", "auto": 1}, {"k": "target", "d": 1, "auto": 1}
	]
	g._collect_intents(_frame(g, TICK, {2: merged}))
	assert_true(g.state.rider(2).fallback)


func test_a_dropped_session_without_state_is_safe() -> void:
	var g: TankGame = autofree(TankGame.new())
	assert_eq(g.autopilot_intents(1), [])
	assert_eq(g.local_intents(_actions, _gestures), [])
