extends GutTest
## Events, toasts and the host's input handling (brief 2.6, 2.8): every toast follows an event and
## names only the local rider's peer, a refused purchase speaks only to its buyer, teaching toasts
## in the warm-up wave, unknown peers ignored, the 5 a second limit, phase_changed, dropped
## riders, rescue and AFK.

const K := preload("res://tests/games/siege/module/siege_module_kit.gd")
const F := preload("res://tests/games/siege/siege_fakes.gd")


func _host(humans: int = 2) -> SiegeGame:
	return K.game(humans, 0, "short", Wl.HOST, 1)


func _client(local_peer: int = 2) -> SiegeGame:
	return K.game(2, 0, "short", Wl.CLIENT, local_peer)


func _free(g: SiegeGame) -> void:
	F.free_game(g)


func _keys(toasts: Array) -> Array:
	var out: Array = []
	for t: Array in toasts:
		out.append(t[0])
	return out


# --- toasts -----------------------------------------------------------------------------------


func test_a_refused_purchase_toasts_only_the_buyers_peer() -> void:
	var host := _host()
	var refused_by_peer2 := SiegeEvents.buy(1, SiegeIds.ITEM_REPAIR, 0, false, "gate_full", 0)
	host._local_effects(refused_by_peer2)
	assert_eq(K.toasts(host), [], "the host's rider (slot 0) is not the buyer")
	var refused_by_host := SiegeEvents.buy(0, SiegeIds.ITEM_BUILD_BALLISTA, 3, false, "funds", 0)
	host._local_effects(refused_by_host)
	var toasts := K.toasts(host)
	assert_eq(toasts.size(), 1)
	assert_eq(toasts[0][0], "SIEGE_TOAST_BUY_REFUSED")
	assert_eq(toasts[0][2], 1, "named for the host's own peer: nothing is broadcast")
	_free(host)
	var client := _client(2)
	client.apply_event(refused_by_host)
	assert_eq(K.toasts(client), [], "someone else's refusal")
	client.apply_event(refused_by_peer2)
	toasts = K.toasts(client)
	assert_eq(toasts.size(), 1)
	assert_eq(toasts[0][0], "SIEGE_TOAST_BUY_REFUSED")
	assert_eq(toasts[0][2], Wl.ALL_PEERS, "a client's call is always local")
	_free(client)


func test_a_purchase_and_a_route_speak_to_their_own_rider_only() -> void:
	var client := _client(2)
	client.apply_event(SiegeEvents.buy(1, SiegeIds.ITEM_UPGRADE, 3, true, "", 2))
	client.apply_event(SiegeEvents.buy(0, SiegeIds.ITEM_UPGRADE, 3, true, "", 2))
	client.apply_event(SiegeEvents.route(0, 3))
	client.apply_event(SiegeEvents.route(1, 4))
	assert_eq(_keys(K.toasts(client)), ["SIEGE_TOAST_BUY_OK", "SIEGE_TOAST_ROUTE"])
	assert_eq(client.state.rider_at(1).target, 4, "the route shows at once")
	assert_eq(client.state.rider_at(1).reconnect_s, 2.0)
	assert_eq(client.state.rider_at(0).target, 3)
	_free(client)


func test_no_host_toast_ever_broadcasts() -> void:
	var host := _host()
	var events: Array[Dictionary] = [
		SiegeEvents.wave_start(2, SiegeIds.ROLE_WARMUP_WAVE, 0, 3, 100.0, [0, 1, 2]),
		SiegeEvents.wave_start(4, SiegeIds.ROLE_WAVE, 1, 3, 100.0, [0, 1, 2]),
		SiegeEvents.wave_end(4, 1, 80.0, 100.0, 3),
		SiegeEvents.wave_end(2, 0, 100.0, 100.0, 0),
		SiegeEvents.roads([1, 2] as Array[int], 5000),
		SiegeEvents.push([0, 1] as Array[int]),
		SiegeEvents.rush(true, 0),
		SiegeEvents.rush(false, 0),
		SiegeEvents.kill(1, SiegeIds.ENEMY_RAM, 3, 1, false),
		SiegeEvents.leak(2, SiegeIds.ENEMY_RAIDERS, 0, 2),
		SiegeEvents.breach(1),
		SiegeEvents.gate_restored(30.0),
		SiegeEvents.buy(0, SiegeIds.ITEM_GENERATOR, 0, true, "", 1),
		SiegeEvents.buy(0, SiegeIds.ITEM_BUILD_CALTROP, 5, false, "pad_taken", 0),
		SiegeEvents.route(0, 0),
		SiegeEvents.overdrive(0, SiegeIds.OD_EV_START),
		SiegeEvents.overdrive(0, SiegeIds.OD_EV_END, true),
		SiegeEvents.overdrive(0, SiegeIds.OD_EV_END, false, "phase"),
		SiegeEvents.overdrive(0, SiegeIds.OD_EV_REFUSED, false, "switch_spacing"),
	]
	for e in events:
		host._local_effects(e)
	var toasts := K.toasts(host)
	assert_eq(toasts.size(), events.size(), "every event here has a toast for the host's rider")
	for t: Array in toasts:
		assert_eq(t[2], 1, "%s names the host's peer" % t[0])
		assert_true(str(t[0]).begins_with("SIEGE_"))
	_free(host)


func test_a_client_raises_the_horns_and_toasts_from_events() -> void:
	var client := _client(2)
	var cues: Array = []
	client.cue.connect(func(kind: String, _d: Dictionary) -> void: cues.append(kind))
	client.apply_event(
		SiegeEvents.wave_start(4, SiegeIds.ROLE_WAVE, 2, 3, 120.0, [1] as Array[int])
	)
	assert_eq(client.state.wave.active_roads, [1])
	client.apply_event(SiegeEvents.roads([0, 2] as Array[int], 5000))
	assert_eq(client.state.wave.next_roads, [0, 2])
	assert_almost_eq(client.state.wave.horn_s, 5.0, 0.001)
	client.apply_event(SiegeEvents.push([1] as Array[int]))
	client.apply_event(SiegeEvents.rush(true, 1))
	assert_true(client.state.rush_on())
	client.apply_event(SiegeEvents.rush(false, 1))
	assert_false(client.state.rush_on())
	client.apply_event(SiegeEvents.breach(1))
	assert_eq(client.state.breaches, 1)
	client.apply_event(SiegeEvents.gate_restored(30.0))
	assert_eq(client.state.gate_hp, 30.0)
	assert_eq(
		_keys(K.toasts(client)),
		[
			"SIEGE_TOAST_WAVE_START",
			"SIEGE_TOAST_ROADS",
			"SIEGE_TOAST_PUSH",
			"SIEGE_TOAST_RUSH_START",
			"SIEGE_TOAST_RUSH_END",
			"SIEGE_TOAST_BREACH",
			"SIEGE_TOAST_GATE_RESTORED",
		]
	)
	assert_eq(K.toasts(client)[0][1], [2, 3])
	assert_eq(cues.size(), 7, "one cue per event for the view and the audio")
	# The horn counts down; then the roads switch.
	for _i in 101:
		client.client_predict(Wl.SIM_DT, null)
	assert_eq(client.state.wave.active_roads, [0, 2])
	assert_eq(client.state.wave.next_roads, [])
	_free(client)


func test_leak_toasts_are_rare() -> void:
	var client := _client(2)
	client.state.tick = 100
	client.apply_event(SiegeEvents.leak(1, SiegeIds.ENEMY_SHIELD_WALL, 0, 8))
	client.state.tick = 110
	client.apply_event(SiegeEvents.leak(2, SiegeIds.ENEMY_RAIDERS, 0, 2))
	client.state.tick = 190
	client.apply_event(SiegeEvents.leak(3, SiegeIds.ENEMY_RAIDERS, 0, 2))
	assert_eq(
		_keys(K.toasts(client)), ["SIEGE_TOAST_LEAK", "SIEGE_TOAST_LEAK"], "4 s apart at least"
	)
	_free(client)


func test_the_warm_up_wave_teaches_once_a_minute_on_the_host() -> void:
	var g := K.game(1, 0, "short")
	K.run_to(g, 0, 300.0)
	var teach: Array = []
	for t: Array in K.toasts(g):
		if str(t[0]).begins_with("SIEGE_TEACH_"):
			teach.append([t[0], t[2]])
	assert_eq(
		teach,
		[
			["SIEGE_TEACH_1", 1],
			["SIEGE_TEACH_2", 1],
			["SIEGE_TEACH_3", 1],
			["SIEGE_TEACH_4", 1],
			["SIEGE_TEACH_5", 1]
		],
		"five minutes, five lessons, each once, for the local rider"
	)
	_free(g)


func test_the_warm_up_wave_teaches_a_client_from_its_snapshots() -> void:
	var host := K.game(2, 0, "short", Wl.HOST, 1)
	var client := K.game(2, 0, "short", Wl.CLIENT, 2)
	var link := K.Link.new(host, client)
	link.run(0, 150.0)
	var teach: Array = []
	for t: Array in K.toasts(client):
		if str(t[0]).begins_with("SIEGE_TEACH_"):
			teach.append(t[0])
	assert_eq(teach, ["SIEGE_TEACH_1", "SIEGE_TEACH_2", "SIEGE_TEACH_3"])
	_free(host)
	_free(client)


# --- input handling ---------------------------------------------------------------------------


func test_telemetry_and_intents_from_a_peer_outside_the_slots_are_ignored() -> void:
	var g := K.game(1, 0, "short")
	var tick := K.run_to(g, 0, 430.0)
	var f := F.frame(g.ctx, g.plans, tick, 100.0, {})
	var stranger := Telemetry.new()
	stranger.peer_id = 99
	stranger.power_w = 900.0
	stranger.p_eff_w = 900.0
	stranger.intents = [SiegeIntents.overdrive("action"), SiegeIntents.route("next")]
	f.players[99] = stranger
	f.phase[99] = f.phase[1]
	g.sim_step(Wl.SIM_DT, f)
	assert_eq(K.directives(g).requests, [])
	assert_null(g.state.rider(99))
	assert_eq(g.state.riders.size(), 1)
	assert_false(g._collect_intents(f).has(99))
	_free(g)


func test_at_most_five_intents_a_second_per_peer() -> void:
	var g := K.game(2, 0, "short")
	var eight: Array = []
	for i in 8:
		eight.append(SiegeIntents.route("next"))
	var f := F.frame(g.ctx, g.plans, 100, 100.0, {1: eight, 2: eight})
	var got := g._collect_intents(f)
	assert_eq(got[1].size(), 5)
	assert_eq(got[2].size(), 5, "each peer has its own allowance")
	var again := g._collect_intents(F.frame(g.ctx, g.plans, 101, 100.0, {1: eight}))
	assert_eq(again[1].size(), 0, "the rest of that second is spent")
	again = g._collect_intents(F.frame(g.ctx, g.plans, 119, 100.0, {1: eight}))
	assert_eq(again[1].size(), 0)
	assert_eq(
		g._collect_intents(F.frame(g.ctx, g.plans, 120, 100.0, {1: eight}))[1].size(),
		5,
		"a second later the window is free again"
	)
	var junk: Array = [{"k": "dance"}, "route", {"k": "route", "to": 99}, {"k": "buy", "item": "x"}]
	var mixed := junk + [SiegeIntents.route("gen")]
	var clean := g._collect_intents(F.frame(g.ctx, g.plans, 400, 100.0, {1: mixed}))
	assert_eq(clean[1].size(), 1, "junk is dropped before it counts")
	_free(g)


func test_a_dropped_client_is_afk_until_it_reconnects() -> void:
	var g := K.game(2, 0, "short", Wl.HOST, 1)
	var tick := K.run_to(g, 0, 430.0)
	var off := {"connected": {2: false}, "power_w": {2: 0.0}}
	K.step(g, tick, {}, off)
	var rd := g.state.rider(2)
	assert_true(rd.afk, "AFK at once")
	assert_false(rd.connected)
	g.on_afk(2, true)
	var target := rd.target
	var denarii := rd.denarii
	K.step(g, tick + 1, {}, off)
	assert_eq(rd.target, target, "keeps its routing")
	assert_gte(rd.denarii, denarii, "and its denarii")
	K.step(g, tick + 2)
	assert_true(rd.connected)
	assert_true(rd.afk, "telemetry is back but the platform has not seen it pedal yet")
	g.on_afk(2, false)
	K.step(g, tick + 3)
	assert_false(rd.afk)
	_free(g)


func test_rescue_and_afk_toast_the_rider_themselves() -> void:
	var host := _host()
	host.on_rescue(2, true)
	host.on_afk(2, true)
	assert_eq(K.toasts(host), [], "the host does not speak for a remote rider")
	host.on_rescue(1, true)
	host.on_afk(1, true)
	assert_eq(_keys(K.toasts(host)), ["SIEGE_TOAST_STAGGER", "SIEGE_TOAST_AFK"])
	_free(host)
	var client := _client(2)
	var snap := SiegeSnapshot.encode(client.state)
	snap["r"][1][SiegeSnapshotSchema.R_RESCUE] = 1
	client.apply_snapshot(snap)
	client.apply_snapshot(snap)
	snap["r"][1][SiegeSnapshotSchema.R_AFK] = 1
	client.apply_snapshot(snap)
	assert_eq(_keys(K.toasts(client)), ["SIEGE_TOAST_STAGGER", "SIEGE_TOAST_AFK"], "on the edges")
	_free(client)


func test_the_gate_warning_shows_once_and_rearms() -> void:
	var client := _client(2)
	client.state.role = SiegeIds.ROLE_WAVE
	var snap := SiegeSnapshot.encode(client.state)
	snap["gate"] = [20, 100, 0]
	client.apply_snapshot(snap)
	client.apply_snapshot(snap)
	snap["gate"] = [60, 100, 0]
	client.apply_snapshot(snap)
	snap["gate"] = [25, 100, 0]
	client.apply_snapshot(snap)
	var warns := 0
	for k in _keys(K.toasts(client)):
		warns += int(k == "SIEGE_WARN_GATE_LOW")
	assert_eq(warns, 2)
	_free(client)


func test_controls_map_to_intents() -> void:
	var client := _client(2)
	client.state.role = SiegeIds.ROLE_WAVE
	var none: Array[StringName] = []
	var surge: Array[StringName] = [Wl.G_SURGE]
	var button: Array[StringName] = [&"ability_1"]
	var both: Array[StringName] = [&"ability_1", &"swap"]
	assert_eq(client.local_intents(none, surge), [SiegeIntents.overdrive("surge")])
	assert_eq(client.local_intents(button, none), [SiegeIntents.overdrive("action")])
	assert_eq(
		client.local_intents(both, surge),
		[SiegeIntents.overdrive("surge"), SiegeIntents.route("next")],
		"a surge wins over the button"
	)
	for pair: Array in [[&"left", "prev"], [&"up", "gen"], [&"down", "hot"], [&"right", "next"]]:
		var acts: Array[StringName] = [pair[0]]
		assert_eq(client.local_intents(acts, none), [SiegeIntents.route(pair[1])])
	_free(client)


func test_a_client_shows_its_route_change_at_once_and_the_host_has_the_last_word() -> void:
	var client := _client(2)
	client.state.role = SiegeIds.ROLE_WAVE
	var none: Array[StringName] = []
	var right: Array[StringName] = [&"right"]
	var me := client.state.rider(2)
	# right from the generator: the first built pad of the ring (pad 3), shown at once.
	client.local_intents(right, none)
	assert_eq(me.target, 3)
	assert_eq(me.reconnect_s, 2.0)
	# A snapshot that still says "generator" does not undo it; time does, if the host never agrees.
	var snap := SiegeSnapshot.encode(client.state)
	snap["r"][1][SiegeSnapshotSchema.R_TARGET] = 0
	client.apply_snapshot(snap)
	assert_eq(me.target, 0)
	client.client_predict(0.05, null)
	assert_eq(me.target, 3, "re-applied until the host answers")
	for _i in 60:
		client.client_predict(0.05, null)
	client.apply_snapshot(snap)
	client.client_predict(0.05, null)
	assert_eq(me.target, 0, "after 2.5 s the host's word stands")
	# The host's route event ends the guess at once.
	client.local_intents(right, none)
	client.apply_event(SiegeEvents.route(1, 4))
	client.client_predict(0.05, null)
	assert_eq(me.target, 4)
	_free(client)


func test_the_host_does_not_predict_and_breaks_take_the_controls() -> void:
	var host := _host()
	var none: Array[StringName] = []
	var right: Array[StringName] = [&"right"]
	host.state.role = SiegeIds.ROLE_WAVE
	assert_eq(host.local_intents(right, none), [SiegeIntents.route("next")])
	assert_eq(host.state.rider(1).target, SiegeIds.TARGET_GEN, "the rules decide on the host")
	host.state.role = SiegeIds.ROLE_BREAK
	assert_eq(host.local_intents(right, none), [])
	host.state.role = SiegeIds.ROLE_COOLDOWN
	assert_eq(host.local_intents(right, none), [])
	_free(host)


func test_bad_content_stops_the_host_cleanly() -> void:
	var ctx := F.make_ctx(1, 0, "nonesuch")
	var g := F.make_game(ctx)
	assert_push_error("siege: content nonesuch")
	assert_null(g.state)
	assert_eq(g.build_effort_plans(), {})
	g.sim_step(Wl.SIM_DT, InputFrame.new())
	assert_eq(g.snapshot(), {})
	F.free_game(g)
