extends GutTest
## The network half of the module (brief 2.6): the 10 Hz snapshot, apply_snapshot's casts and the
## state it derives, events and their casts, int_fields, client_predict and the reconnect path.

const F := preload("res://tests/games/tank/tank_fakes.gd")


func _host(
	crew: int, builder: Callable = Callable(), content_id: String = "ashfall_road"
) -> TankGame:
	var g: TankGame = autofree(F.make_game(F.make_ctx(crew, 0, content_id)))
	g.state = builder.call(crew) if builder.is_valid() else TankFixtures.state(crew)
	g.state.content = g.content
	return g


func _client(crew: int, local: int = 1, content_id: String = "ashfall_road") -> TankGame:
	return autofree(F.make_game(F.make_ctx(crew, 0, content_id, Wl.CLIENT, local)))


## What the platform hands apply_snapshot: JSON text, parsed (every number a float), then the
## declared paths back to int.
func _wire(host: TankGame) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(host.snapshot()))
	return Protocol.apply_int_fields(parsed, host.int_fields()["snapshot"])


## The same, with the floats left alone (an apply_snapshot that must cast itself).
func _raw(host: TankGame) -> Dictionary:
	return JSON.parse_string(JSON.stringify(host.snapshot()))


func _leaves(node: Variant, out: Array) -> void:
	if node is Array:
		for x: Variant in node:
			_leaves(x, out)
	elif node is Dictionary:
		for k: Variant in node:
			_leaves(node[k], out)
	else:
		out.append(node)


# --- Encode ----------------------------------------------------------------------------------------


func test_the_snapshot_is_full_state_in_integers() -> void:
	for crew in [1, 2, 3]:
		for builder: Callable in [TankFixtures.state, TankFixtures.gun_line, TankFixtures.boss]:
			var snap := _host(crew, builder).snapshot()
			assert_eq(TankSnapshotSchema.check(snap), "", "crew %d" % crew)
			var leaves: Array = []
			_leaves(snap, leaves)
			for v: Variant in leaves:
				assert_eq(typeof(v), TYPE_INT, "crew %d: %s is an int" % [crew, str(v)])
	assert_eq(_host(1).snapshot().keys().size(), TankSnapshotSchema.KEYS.size())
	assert_eq(autofree(TankGame.new()).snapshot(), {}, "no state, no snapshot")


func test_the_snapshot_is_at_most_4_kb_at_the_caps() -> void:
	var host: TankGame = autofree(F.make_game(F.make_ctx(3)))
	host.state = TankFixtures.cap()
	host.state.content = host.content
	assert_eq(host.state.enemies.size(), TankConst.MAX_ENEMIES)
	assert_eq(host.state.shells.size(), TankConst.MAX_SHELLS)
	var size := TankSnapshotSchema.byte_size(host.snapshot())
	assert_lte(size, TankConst.SNAPSHOT_MAX_BYTES, "the cap state is %d bytes" % size)
	assert_gt(size, 1000, "and it really is the full state")
	for crew in [1, 2, 3]:
		var normal := TankSnapshotSchema.byte_size(_host(crew).snapshot())
		assert_lt(normal, size)


func test_encoding_twice_gives_the_same_bytes() -> void:
	var host := _host(3)
	assert_eq(JSON.stringify(host.snapshot()), JSON.stringify(host.snapshot()))


# --- Apply -----------------------------------------------------------------------------------------


func test_the_round_trip_through_json_restores_a_fresh_client() -> void:
	for crew in [1, 2, 3]:
		for builder: Callable in [TankFixtures.state, TankFixtures.gun_line, TankFixtures.boss]:
			var host := _host(crew, builder)
			var snap := host.snapshot()
			var client := _client(crew)
			client.apply_snapshot(_wire(host))
			assert_eq(JSON.stringify(client.snapshot()), JSON.stringify(snap), "crew %d" % crew)
	var cap: TankGame = autofree(F.make_game(F.make_ctx(3)))
	cap.state = TankFixtures.cap()
	cap.state.content = cap.content
	var c3 := _client(3)
	c3.apply_snapshot(_wire(cap))
	assert_eq(JSON.stringify(c3.snapshot()), JSON.stringify(cap.snapshot()), "the cap state")


func test_apply_casts_floats_to_int_itself() -> void:
	var host := _host(3, TankFixtures.gun_line)
	var client := _client(3)
	client.apply_snapshot(_raw(host))
	var s := client.state
	for v: Variant in [
		s.tick, s.seg.phase_index, s.seg.stage, s.hull.code, s.hull.facing, s.hull.loaded
	]:
		assert_eq(typeof(v), TYPE_INT)
	assert_eq(typeof(s.hull.target_id), TYPE_INT)
	assert_eq(s.hull.target_id, host.state.hull.target_id)
	for e in s.enemies:
		assert_eq(typeof(e.id), TYPE_INT)
		assert_eq(typeof(e.mode), TYPE_INT)
	assert_eq(s.enemies.map(func(e: TankEnemyState) -> int: return e.id), [21, 22, 23])
	assert_eq(s.hull.x_px, host.state.hull.x_px)
	assert_eq(JSON.stringify(client.snapshot()), JSON.stringify(host.snapshot()))


func test_apply_rebuilds_the_replicated_state() -> void:
	var host := _host(3)
	var client := _client(3)
	client.apply_snapshot(_wire(host))
	var h := host.state
	var c := client.state
	assert_eq(c.tick, h.tick)
	assert_almost_eq(c.t, h.t, 0.0001)
	assert_eq(
		[c.seg.seg, c.seg.stage, c.seg.phase_index], [h.seg.seg, h.seg.stage, h.seg.phase_index]
	)
	assert_eq(c.enemies.size(), 3)
	assert_eq(c.shells.size(), 3)
	assert_eq(c.obstacles.size(), 1)
	assert_almost_eq(c.hull.hp, 72.0, 0.001)
	assert_eq(c.hull.facing, h.hull.facing)
	for r in h.riders:
		var cr := c.rider(r.peer)
		assert_eq(cr.engine, r.engine)
		assert_eq(cr.raw_w, roundf(r.raw_w))
		assert_eq(cr.in_band, r.in_band)
	var dyn := c.station(TankIds.ENGINE_DYNAMO) as TankDynamoState
	assert_almost_eq(dyn.bank, 64.0, 0.05)
	var steam := c.station(TankIds.ENGINE_STEAM) as TankSteamState
	assert_almost_eq(steam.pressure_pct, 72.0, 0.05)
	assert_gt(c.enemy(13).telegraph_s, 2.0)


func test_apply_derives_what_the_snapshot_leaves_out() -> void:
	var host := _host(3)
	var client := _client(3)
	client.apply_snapshot(_wire(host))
	var c := client.state
	assert_eq(c.seg.kind, Wl.WORK)
	assert_eq(c.seg.segment_index, 4)
	assert_true(c.seg.open_ended)
	var seg_def := c.content.segment(4)
	assert_eq(
		[c.seg.min_s, c.seg.max_s, c.seg.length_m],
		[90.0, 300.0, float(seg_def["length_m"])],
		"the stage 2 Advance, its length from the content"
	)
	assert_almost_eq(c.hull.distance_m, host.state.hull.x_px / TankConst.PX_PER_M, 0.01)
	assert_eq(c.outcome, "")
	assert_false(c.all_afk)
	for st in c.stations:
		var holder := c.rider_at(st.slot)
		var want := holder.peer if holder != null else 0
		assert_eq(st.peer, want, "%s: who works the room (0: an empty seat)" % st.engine)
	var boss_def := c.content.boss_def()
	assert_eq(c.boss.bogie_max, float(boss_def["bogie_hp"]))
	assert_eq(c.boss.turret_max, float(boss_def["turret_hp"]))
	assert_eq(
		c.enemy(11).hp_max,
		float(c.content.enemy_def("medium")["hp"]),
		"a medium's full HP at scale 1.0"
	)
	var size: Array = c.content.enemy_def("medium")["size_px"]
	assert_eq([c.enemy(11).w, c.enemy(11).h], [int(size[0]), int(size[1])])
	var solo_host := _host(1)
	solo_host.state.enemy(11).hp = 30.0
	var solo := _client(1)
	solo.apply_snapshot(_wire(solo_host))
	var scale := c.content.enemy_scale(TankIds.TANK_LANDSHIP)
	assert_almost_eq(
		solo.state.boss.bogie_max, float(boss_def["bogie_hp"]) * scale, 0.001, "enemy scale"
	)
	assert_almost_eq(solo.state.boss.turret_max, float(boss_def["turret_hp"]) * scale, 0.001)
	# A client derives an enemy's maximum from the content, rounded up like every HP it shows.
	assert_almost_eq(
		solo.state.enemy(11).hp_max,
		ceilf(float(c.content.enemy_def("medium")["hp"]) * scale),
		0.001,
		"the scaled maximum, rounded up"
	)


func test_a_rotation_moves_the_rooms_to_the_riders_on_the_client() -> void:
	var host := _host(3)
	var h := host.state
	var client := _client(3)
	client.apply_snapshot(_wire(host))
	var engines: Array[String] = []
	for r in h.riders:
		engines.append(r.engine)
	engines.push_back(engines.pop_front())
	for i in h.riders.size():
		h.riders[i].engine = engines[i]
	for st in h.stations:
		st.slot = -1
	for r in h.riders:
		h.station(r.engine).slot = r.slot
	client.apply_snapshot(_wire(host))
	for r in client.state.riders:
		assert_eq(r.engine, engines[r.slot])
		assert_eq(client.state.station(r.engine).slot, r.slot)
		assert_eq(client.state.station(r.engine).peer, r.peer)


func test_all_afk_and_the_outcome_are_derived() -> void:
	var host := _host(2)
	for r in host.state.riders:
		r.afk = true
	var client := _client(2)
	client.apply_snapshot(_wire(host))
	assert_true(client.state.all_afk, "every rider on reserve")
	host.state.riders[0].afk = false
	client.apply_snapshot(_wire(host))
	assert_false(client.state.all_afk)
	host.state.seg.seg = TankIds.SEG_COOLDOWN
	host.state.seg.phase_index = 11
	client.apply_snapshot(_wire(host))
	assert_eq(client.state.seg.kind, Wl.COOLDOWN)
	assert_eq(client.state.seg.segment_index, -1)
	assert_eq(client.state.outcome, TankIds.OUTCOME_WITHDRAWN, "a boss mission without its death")
	host.state.score.behemoth_killed = true
	client.apply_snapshot(_wire(host))
	assert_eq(client.state.outcome, TankIds.OUTCOME_VICTORY)
	var drill := _host(1, Callable(), "drill")
	drill.state.seg.seg = TankIds.SEG_COOLDOWN
	drill.state.seg.phase_index = 3
	var drill_client := _client(1, 1, "drill")
	drill_client.apply_snapshot(_wire(drill))
	assert_eq(drill_client.state.outcome, TankIds.OUTCOME_COMPLETE, "the drill has no boss")


func test_a_malformed_snapshot_changes_nothing() -> void:
	var host := _host(1)
	var client := _client(1)
	client.apply_snapshot(_wire(host))
	var before := JSON.stringify(client.snapshot())
	var broken := _wire(host)
	broken.erase("tk")
	client.apply_snapshot(broken)
	var short := _wire(host)
	short["sg"] = [1, 2]
	client.apply_snapshot(short)
	client.apply_snapshot({})
	assert_eq(JSON.stringify(client.snapshot()), before)


func test_rows_over_the_caps_are_well_formed_and_still_applied() -> void:
	var host := _host(3)
	host.state = TankFixtures.cap()
	host.state.content = host.content
	host.state.enemies.append(TankFixtures._enemy(5000, TankIds.ENEMY_LIGHT, 10.0, 30.0, 1))
	var snap := _wire(host)
	assert_eq((snap["e"] as Array).size(), TankConst.MAX_ENEMIES + 1)
	var client := _client(3)
	client.apply_snapshot(snap)
	assert_eq(
		client.state.enemies.size(),
		TankConst.MAX_ENEMIES + 1,
		"a layout problem is skipped, a count is not"
	)
	assert_eq(client.state.tick, host.state.tick)


func test_apply_announces_each_snapshot_with_its_tick() -> void:
	var host := _host(1)
	var client := _client(1)
	watch_signals(client)
	client.apply_snapshot(_wire(host))
	assert_signal_emit_count(client, "snapshot_applied", 1)
	assert_eq(get_signal_parameters(client, "snapshot_applied", 0), [host.state.tick])


func test_a_reconnecting_client_needs_nothing_but_the_latest_snapshot() -> void:
	var host := _host(3)
	var first := _client(3, 2)
	first.apply_snapshot(_wire(host))
	host.state.tick += 400
	host.state.hull.hp = 33.0
	host.state.enemies.remove_at(0)
	host.state.riders[1].rescue = true
	var again := _wire(host)
	first.apply_snapshot(again)
	var restarted := _client(3, 2)
	restarted.apply_snapshot(again)
	assert_eq(JSON.stringify(restarted.snapshot()), JSON.stringify(first.snapshot()))
	assert_eq(JSON.stringify(restarted.snapshot()), JSON.stringify(host.snapshot()))


# --- int_fields and events -----------------------------------------------------------------------------


func test_int_fields_declare_the_snapshot_and_every_event_type() -> void:
	var f := _host(1).int_fields()
	assert_eq(f["snapshot"], TankSnapshotSchema.INT_PATHS)
	for t: String in TankEvents.TYPES:
		assert_true(f.has(t), t)
		assert_ne(t, "snapshot")
		assert_false(t.begins_with("wl."), "platform events own the wl. prefix")
	for spec: Array in [
		["segment", "i", "sg", "st"],
		["shot", "s", "sh", "id", "src", "e"],
		["hit", "on", "dmg", "b", "x"]
	]:
		for k in range(1, spec.size()):
			assert_has(f[spec[0]], spec[k])


func _sample_events() -> Array[Dictionary]:
	return [
		TankEvents.segment(4, TankIds.SEG_ADVANCE, 2),
		{"type": TankEvents.ROTATION, "r": [[0, 2], [1, 3], [2, 1]]},
		TankEvents.seat(1, TankIds.ENGINE_STEAM, TankIds.ENGINE_FEED),
		TankEvents.shot(1, TankIds.SHELL_HEAVY, 41, 0, 0),
		TankEvents.shot(-1, TankIds.SHELL_ENEMY, 42, 12, 2),
		TankEvents.hit(TankEvents.ON_TANK, 0, 11.6, TankIds.SHELL_ENEMY, 3.2, 3400.4),
		TankEvents.kill(12, 1, TankEvents.BY_SHELL, 1),
		TankEvents.kill(13, 2, TankEvents.BY_BOW, 3),
		{"type": TankEvents.RAM, "s": 2, "ok": 1, "id": 13},
		{"type": TankEvents.DODGE, "s": 2},
		TankEvents.breakdown(),
		TankEvents.repaired(40.0),
		TankEvents.overrun(TankIds.SEG_GUN_LINE, 2),
		TankEvents.boss_phase(TankIds.BOSS_PHASE_2),
		TankEvents.latch(2, TankIds.SHELL_OVER),
		{"type": TankEvents.LEVER, "s": 0, "lv": 1},
		TankEvents.seat(2, TankIds.ENGINE_ARC, TankIds.ENGINE_FEED),
		TankEvents.evade(-4, TankIds.BOSS_CODE, false),
		TankEvents.evade(13, 3, true, 2),
		TankEvents.turn(-1, TankIds.DIR_LEFT),
		TankEvents.time_up(),
	]


func test_every_numeric_field_of_every_event_is_declared() -> void:
	var f := _host(1).int_fields()
	var seen := {}
	for e in _sample_events():
		var type := str(e["type"])
		seen[type] = true
		for k: String in e:
			if k == "type":
				continue
			var v: Variant = e[k]
			assert_true(v is int or v is Array, "%s.%s is a whole number" % [type, k])
			var path := k + ("[][]" if v is Array else "")
			assert_has(f[type], path, "%s.%s is declared" % [type, k])
	assert_eq(seen.size(), TankEvents.TYPES.size(), "a sample of every type")


func test_events_survive_the_wire_as_ints() -> void:
	var f := _host(1).int_fields()
	for e in _sample_events():
		var type := str(e["type"])
		var parsed: Dictionary = JSON.parse_string(JSON.stringify(e))
		var decoded: Variant = Protocol.apply_int_fields(parsed, f[type])
		assert_eq(decoded, e, type)
		var cast := TankEventCast.cast(parsed)
		assert_eq(cast, e, "%s: the module's own cast agrees" % type)
		var leaves: Array = []
		_leaves(cast, leaves)
		for v: Variant in leaves:
			assert_true(v is int or v is String, "%s: %s" % [type, str(v)])


func test_the_cast_keeps_unknown_keys_and_leaves_the_event_untouched() -> void:
	var raw := {
		"type": "hit",
		"on": 0.0,
		"id": 3.0,
		"dmg": 11.0,
		"sh": 5.0,
		"b": 0.0,
		"x": 9.0,
		"extra": 1.5
	}
	var cast := TankEventCast.cast(raw)
	assert_eq(typeof(cast["dmg"]), TYPE_INT)
	assert_eq(cast["extra"], 1.5)
	assert_eq(typeof(raw["dmg"]), TYPE_FLOAT, "the input is not changed")
	assert_eq(TankEventCast.cast({"type": "banana", "a": 1.0}), {"type": "banana", "a": 1.0})
	assert_eq(TankEventCast.cast({"type": "rotation", "r": [[0.0, 2.0]]})["r"], [[0, 2]])
	assert_eq(TankEventCast.cast({}), {})


func test_apply_event_tells_the_view_in_order_with_ints() -> void:
	var client := _client(3)
	watch_signals(client)
	var parsed: Array = []
	for e in _sample_events():
		parsed.append(JSON.parse_string(JSON.stringify(e)))
		client.apply_event(parsed[-1])
	assert_signal_emit_count(client, "cue", parsed.size())
	for i in parsed.size():
		var params: Array = get_signal_parameters(client, "cue", i)
		assert_eq(params[0], parsed[i]["type"], "in the host's order")
		assert_eq(typeof((params[1] as Dictionary).get("i", 0)), TYPE_INT)
	autofree(TankGame.new()).apply_event({"type": "hit"})
	pass_test("an event with no state is ignored")


func test_the_host_emits_cue_for_each_event_it_sends() -> void:
	var ctx := F.make_ctx(1)
	var g: TankGame = autofree(F.make_game(ctx))
	var sent: Array = []
	g.game_event.connect(func(e: Dictionary) -> void: sent.append(str(e["type"])))
	var cued: Array = []
	g.cue.connect(func(kind: String, _d: Dictionary) -> void: cued.append(kind))
	var plans := F.plans_of(g)
	F.run(g, plans, 0, 10.0)
	assert_gt(sent.size(), 0, "the first segment starts")
	assert_eq(cued, sent, "the host's view hears every event it sends")
	assert_eq(sent[0], "segment")


# --- client_predict --------------------------------------------------------------------------------


func _telemetry(power: float, cadence: float, ftp_pct: float, mode: String = Wl.SIM) -> Telemetry:
	var t := Telemetry.new()
	t.power_w = power
	t.p_eff_w = power * 1.25
	t.cadence_rpm = cadence
	t.ftp_pct = ftp_pct
	t.mode = mode
	return t


func test_client_predict_moves_only_the_local_riders_room() -> void:
	var host := _host(3)
	var client := _client(3, 2)
	client.apply_snapshot(_wire(host))
	var before := {}
	for r in client.state.riders:
		before[r.peer] = [r.raw_w, r.cadence_rpm, r.ftp_pct, r.in_band]
	var rooms_before := {}
	for st in client.state.stations:
		rooms_before[st.engine] = [st.p_eff_w, st.in_band]
	var snap_before := JSON.stringify(client.snapshot())
	client.client_predict(0.05, _telemetry(333.0, 101.0, 140.0))
	var me := client.state.rider(2)
	assert_eq([me.raw_w, me.cadence_rpm, me.ftp_pct], [333.0, 101.0, 140.0])
	for r in client.state.riders:
		if r.peer != 2:
			assert_eq(
				[r.raw_w, r.cadence_rpm, r.ftp_pct, r.in_band], before[r.peer], "peer %d" % r.peer
			)
	for st in client.state.stations:
		if st.slot != me.slot:
			assert_eq([st.p_eff_w, st.in_band], rooms_before[st.engine], st.engine)
	assert_eq(client.state.station_of(me.slot).p_eff_w, 333.0 * 1.25)
	assert_eq(client.state.tick, host.state.tick, "the game clock is the host's")
	assert_ne(
		JSON.stringify(client.snapshot()), snap_before, "only the local rider's numbers moved"
	)


func test_the_local_glow_follows_local_telemetry_by_the_in_band_rule() -> void:
	var client := _client(1, 1)
	client.apply_snapshot(_wire(_host(1)))
	client.client_predict(0.05, _telemetry(180.0, 90.0, 90.0))
	assert_true(client.state.rider(1).in_band, "SIM, 90% FTP is inside 76-105")
	assert_true(client.state.station_of(0).in_band)
	client.client_predict(0.05, _telemetry(100.0, 90.0, 50.0))
	assert_false(client.state.rider(1).in_band, "50% FTP is below the band")
	assert_false(client.state.station_of(0).in_band)
	client.client_predict(0.05, _telemetry(240.0, 90.0, 120.0))
	assert_false(client.state.rider(1).in_band, "and 120% is above it")
	var rescued := _telemetry(180.0, 90.0, 90.0)
	rescued.rescue = true
	client.client_predict(0.05, rescued)
	assert_false(client.state.rider(1).in_band, "never in band in a rescue hold")
	client.client_predict(0.05, null)
	assert_false(client.state.rider(1).in_band, "no telemetry: nothing moves")


func test_a_reserve_room_stays_unpowered_by_the_riders_watts() -> void:
	var host := _host(1)
	host.state.stations[0].reserve = true
	host.state.stations[0].p_eff_w = 60.0
	var client := _client(1, 1)
	client.apply_snapshot(_wire(host))
	client.client_predict(0.05, _telemetry(300.0, 90.0, 120.0))
	assert_ne(client.state.stations[0].p_eff_w, 300.0 * 1.25, "not the rider's own watts")
	assert_false(client.state.stations[0].in_band, "never in band on reserve")
