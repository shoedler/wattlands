extends "res://tests/net/net_session_test_base.gd"
## WlNetSession messaging over LoopbackTransport (BRIEF 5.4, 5.5; OWNERSHIP NET1, NET3,
## NET4, C11, GM10, CTX12): routing rules, local delivery, invalid sends, telemetry intent
## caps, directive coalescing, the snapshot buffer with game int_fields, events, the
## roster and the clock offset.


func _directive(kind: String, fields: Dictionary) -> Dictionary:
	var d := fields.duplicate()
	d["kind"] = kind
	return Protocol.game_msg("directive", d)


func _snapshot(seq: int, t: float, state: Dictionary) -> Dictionary:
	return Protocol.game_msg("snapshot", {"game_id": "workout", "seq": seq, "t": t, "tick": seq * 2,
		"state": state})


func test_routing_rules() -> void:
	var r := room()
	var h := r[0]
	h.send_to(2, Protocol.game_msg("phase", {"index": 1, "start_tick": 20, "ended_by": "duration"}))
	pump()
	assert_eq(messages("c1", "phase").size(), 1)
	assert_eq(messages("c2", "phase").size(), 0, "point to point")
	assert_eq(messages("c1", "phase")[0][1], 1)
	h.broadcast(Protocol.game_msg("roster", {"riders": {1: {"raw_w": 200.0}}}))
	pump()
	assert_eq(messages("c1", "roster").size(), 1)
	assert_eq(messages("c2", "roster").size(), 1)
	assert_eq(messages("host", "roster").size(), 0, "a broadcast excludes the sender")
	assert_true(r[1].latest_roster.has(1), "roster keys are ints")
	r[1].send_to_host(Protocol.game_msg("telemetry", {"tm": {"peer": 2, "power_w": 150.0}}))
	pump()
	var tm := messages("host", "telemetry")
	assert_eq(tm.size(), 1)
	assert_eq(tm[0][1], 2)
	assert_eq(((tm[0][2] as Dictionary)["tm"] as Dictionary)["peer"], 2)
	r[1].send_to(3, Protocol.game_msg("ready", {"ready": true}))
	assert_push_warning("clients send only to the host")
	r[1].broadcast(Protocol.game_msg("ready", {"ready": true}))
	assert_push_warning("only the host broadcasts")
	h.send_to(-1, Protocol.game_msg("phase", {"index": 1, "start_tick": 0, "ended_by": "duration"}))
	assert_push_warning("no such peer")
	pump()
	assert_eq(messages("c2", "ready").size(), 0)


func test_direction_rules_on_arrival() -> void:
	var r := room()
	clear_logs()
	# A client cannot push host -> client types to the host...
	r[1].send_to_host(_snapshot(1, 0.0, {}))
	pump()
	assert_eq(messages("host", "snapshot").size(), 0)
	assert_push_warning("host ignored \"snapshot\"")
	# ...and clients ignore client -> host types.
	r[0].send_to(2, Protocol.game_msg("telemetry", {"tm": {}}))
	pump()
	assert_eq(messages("c1", "telemetry").size(), 0)
	assert_push_warning("client ignored \"telemetry\"")
	assert_gt(int(r[0].stats["ignored"]), 0)


func test_messages_to_self_are_delivered_on_the_next_poll() -> void:
	var r := room()
	clear_logs()
	r[0].send_to_host(Protocol.game_msg("telemetry", {"tm": {"peer": 1}}))
	r[0].send_to(1, Protocol.game_msg("phase", {"index": 2, "start_tick": 0, "ended_by": "duration"}))
	assert_eq(messages("host").size(), 0)
	r[0].poll()
	assert_eq(messages("host", "telemetry").size(), 1)
	assert_eq(messages("host", "phase").size(), 1)
	assert_typeof((messages("host", "phase")[0][2] as Dictionary)["index"], TYPE_INT, "through JSON")


func test_invalid_messages_are_not_sent() -> void:
	var r := room()
	r[0].broadcast({"type": "snapshot", "seq": 1})
	assert_push_error("refusing to send an invalid \"snapshot\" message")
	r[0].send_to(2, {"type": "warp"})
	assert_push_error("refusing to send an invalid \"warp\" message")
	r[1].send_to_host({"type": "ready", "ready": true})
	pump()
	assert_eq(messages("host", "ready").size(), 1, "a missing v is filled in")
	assert_eq(int(r[0].stats["invalid_sends"]), 2)



func test_telemetry_intents_are_capped() -> void:
	var r := room()
	clear_logs()
	var many: Array = []
	for i in 40:
		many.append({"k": "tap", "i": i})
	r[1].send_to_host(Protocol.game_msg("telemetry", {"tm": {"peer": 2, "intents": many}}))
	r[1].send_to_host(Protocol.game_msg("telemetry", {"tm": {"peer": 2, "intents": [
		{"k": "big", "s": "y".repeat(2000)}, {"k": "ok"}]}}))
	pump()
	var tm := messages("host", "telemetry")
	assert_eq(tm.size(), 2)
	var first: Array = ((tm[0][2] as Dictionary)["tm"] as Dictionary)["intents"]
	assert_eq(first.size(), 32, "at most 32 intents per telemetry")
	assert_eq(float((first[31] as Dictionary)["i"]), 31.0, "the first 32, in order")
	var second: Array = ((tm[1][2] as Dictionary)["tm"] as Dictionary)["intents"]
	assert_eq(second.size(), 1, "an intent over 1 KB is dropped")
	assert_eq((second[0] as Dictionary)["k"], "ok")
	assert_eq(int(r[0].stats["intents_dropped"]), 9)
	assert_push_warning("dropped 8 intents")
	assert_push_warning("dropped 1 intents")


func test_band_and_grade_directives_are_coalesced_never_requests_or_phases() -> void:
	var r := room()
	var h := r[0]
	clear_logs()
	h.send_to(2, _directive("course_grade", {"id": 1, "grade_pct": 1.0}))
	h.send_to(2, _directive("course_grade", {"id": 2, "grade_pct": 2.0}))
	h.send_to(2, _directive("course_grade", {"id": 3, "grade_pct": 3.0}))
	h.send_to(2, _directive("power_band", {"lo_w": 150.0, "hi_w": 200.0}))
	h.send_to(2, Protocol.game_msg("phase", {"index": 1, "start_tick": 40, "ended_by": "end_phase"}))
	for i in 5:
		h.send_to(2, _directive("request", {"id": 10 + i, "target_pct": 80.0 + i, "duration_s": 0.0}))
	h.send_to(3, _directive("cadence_band", {"lo_rpm": 80.0, "hi_rpm": 90.0}))
	h.send_to(3, _directive("cadence_band", {"lo_rpm": 82.0, "hi_rpm": 92.0}))
	h.send_to(3, _directive("cadence_band", {"lo_rpm": 85.0, "hi_rpm": 95.0}))
	pump(6)
	var seen: Array = []
	for m: Array in messages("c1"):
		var d: Dictionary = m[2]
		if d["type"] == "directive":
			seen.append("%s:%s" % [d["kind"], str(d.get("id", d.get("lo_w", "")))])
		elif d["type"] == "phase":
			seen.append("phase")
	assert_eq(seen, ["course_grade:1", "power_band:150.0", "course_grade:3", "phase", "request:10",
		"request:11", "request:12", "request:13", "request:14"],
		"the latest grade wins, flushed before the phase; requests all arrive in order")
	var bands: Array = []
	for m: Array in messages("c2", "directive"):
		bands.append(float((m[2] as Dictionary)["lo_rpm"]))
	assert_eq(bands, [80.0, 85.0], "at most one per 100 ms, the latest wins")
	assert_eq(int(h.stats["coalesced"]), 2)


func test_snapshot_buffer_int_fields_and_interpolation() -> void:
	var r := room()
	var h := r[0]
	var c1 := r[1]
	c1.set_game_int_fields({"snapshot": ["r[][]"], "kill": ["slot"]})
	clear_logs()
	h.broadcast(_snapshot(1, 1.0, {"r": [[1, 2]], "x": 0.5}))
	h.broadcast(_snapshot(2, 1.1, {"r": [[3, 4]], "x": 1.5}))
	pump()
	assert_eq(int(h.latest_snapshot()["seq"]), 2, "the host keeps its latest sent snapshot")
	h.broadcast(_snapshot(2, 1.1, {"r": [[3, 4]]}))
	h.broadcast(_snapshot(1, 1.0, {"r": [[1, 2]]}))
	pump()
	var snaps := messages("c1", "snapshot")
	assert_eq(snaps.size(), 2, "older and repeated seqs are dropped")
	assert_eq(int(c1.stats["stale_snapshots"]), 2)
	var latest := c1.latest_snapshot()
	assert_eq(latest["seq"], 2)
	assert_typeof(latest["tick"], TYPE_INT)
	assert_true(U.same((latest["state"] as Dictionary)["r"], [[3, 4]]), "game int_fields applied")
	assert_typeof((latest["state"] as Dictionary)["x"], TYPE_FLOAT)
	assert_eq(c1.snapshot_buffer().size(), 2)
	var pair := c1.snapshot_pair_at(1.05)
	assert_eq((pair["from"] as Dictionary)["seq"], 1)
	assert_eq((pair["to"] as Dictionary)["seq"], 2)
	assert_almost_eq(float(pair["alpha"]), 0.5, 1e-6)
	assert_eq(c1.snapshot_at(1.05)["seq"], 1)
	assert_eq(c1.snapshot_at(0.2)["seq"], 1, "older than the buffer: the oldest")
	assert_eq(c1.snapshot_at(9.0)["seq"], 2)
	var late := c1.snapshot_pair_at(5.0)
	assert_eq((late["from"] as Dictionary)["seq"], 2)
	assert_eq(float(late["alpha"]), 1.0)
	c1.snapshot_buffer_size = 3
	for i in range(3, 10):
		h.broadcast(_snapshot(i, 1.0 + i * 0.1, {"r": []}))
	pump()
	assert_eq(c1.snapshot_buffer().size(), 3)
	assert_eq((c1.snapshot_buffer()[0] as Dictionary)["seq"], 7)
	# A new session clears the buffer (seq restarts).
	h.broadcast(Protocol.game_msg("session_start", {"game_id": "workout", "game_version": "1", "content_id": "a", "seed": 1,
		"players": [], "options": {}, "scaling": Wl.FAIR_FTP, "start_tick": 0}))
	h.broadcast(_snapshot(1, 0.1, {"r": []}))
	pump()
	assert_true(c1.session_started)
	assert_eq(c1.latest_snapshot()["seq"], 1)
	h.broadcast(Protocol.game_msg("event", {"seq": 1, "events": [{"type": "kill", "slot": 2, "x": 0.5},
		{"type": "phase_started", "peer_id": 2, "index": 1}]}))
	pump()
	var ev: Array = (messages("c1", "event")[0][2] as Dictionary)["events"]
	assert_typeof((ev[0] as Dictionary)["slot"], TYPE_INT)
	assert_typeof((ev[0] as Dictionary)["x"], TYPE_FLOAT)
	assert_typeof((ev[1] as Dictionary)["peer_id"], TYPE_INT)


func test_clock_offset_from_clock_ping() -> void:
	var h := make_session("host", rider("Hana"))
	h.set_time(100.0)
	h.host_room()
	pump()
	var c := make_session("c1", rider("Ann"))
	c.set_time(5.0)
	c.join_room(h.room_code)
	pump()
	assert_almost_eq(c.clock_offset, 95.0, 1e-9)
	assert_almost_eq(c.host_time(), 100.0, 1e-9)
	assert_eq(c.clock_rtt, 0.0)
	assert_eq(h.host_time(), 100.0, "the host's own time")
	c.tick(1.5)
	assert_almost_eq(c.host_time(), 101.5, 1e-9)
	assert_eq(c.local_time(), 6.5)


func test_roster_reaches_every_peer_with_int_keys() -> void:
	var r := room()
	var h := r[0]
	var host_seen: Array = []
	h.bus.roster_changed.connect(func(ro: Dictionary) -> void: host_seen.append(ro))
	var c_seen: Array = []
	r[2].bus.roster_changed.connect(func(ro: Dictionary) -> void: c_seen.append(ro))
	var slots := h.lobby_slots()
	var tm := Telemetry.new()
	tm.peer_id = 2
	tm.power_w = 180.0
	tm.cadence_rpm = 88.0
	tm.ftp_pct = 85.5
	tm.rescue = true
	var riders := NetRoster.build(slots, {2: tm}, {2: {"in_band": true, "text": "Diesel"}})
	assert_eq(riders.keys(), [1, 2, 3], "slot order")
	assert_eq(riders[1]["raw_w"], 0.0, "no telemetry yet")
	assert_true(riders[1]["connected"])
	var sent := h.send_roster(riders)
	pump()
	assert_eq(host_seen.size(), 1, "the host's own bus")
	assert_eq(c_seen.size(), 1)
	for s in [h, r[1], r[2]]:
		var ro: Dictionary = s.latest_roster
		assert_true(U.same(ro, sent), s.name + ": " + U.diff(ro, sent))
		var e: Dictionary = ro[2]
		assert_eq(e["raw_w"], 180.0)
		assert_eq(e["cadence_rpm"], 88.0)
		assert_eq(e["ftp_pct"], 85.5)
		assert_true(e["rescue"])
		assert_eq((e["status"] as Dictionary)["text"], "Diesel")
		assert_typeof(e["slot_index"], TYPE_INT)
		for f in NetRoster.FIELDS:
			assert_true(e.has(f), f)
	assert_eq(messages("c1", "roster").size(), 1)
	r[1].send_roster({})
	assert_push_warning("only the host sends the roster")
	var t2 := Telemetry.new()
	t2.power_w = 125.0
	var bot := Bots.make_slot(1, 3, 250.0)
	assert_eq(NetRoster.entry(bot, t2)["ftp_pct"], 50.0, "%FTP from power when telemetry has none")
