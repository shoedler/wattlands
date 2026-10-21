extends "res://tests/net/net_session_test_base.gd"
## Hardening cases for WlNetSession, Protocol and the client transports (W1 review):
## leaving while a join is in flight, coalescing at real-time poll rates and with a frozen
## clock, the lobby's player limit when several peers join at once, the GameRegistry as the
## source of installed games, the default token file under Paths, rate limits while
## reconnecting, the telemetry sender id, readable texts for every refusal reason and
## decoding of hand-formatted JSON.


func _lt(s: WlNetSession) -> LoopbackTransport:
	return s.transport as LoopbackTransport


func _grade(id: int, g: float) -> Dictionary:
	return Protocol.game_msg(
		"directive", {"kind": NetMessages.DIRECTIVE_COURSE_GRADE, "id": id, "grade_pct": g}
	)


# --- leaving while connecting ---------------------------------------------------------------


func test_leave_while_joining_cancels_the_join() -> void:
	var h := make_session("host", rider("Hana"))
	h.host_room()
	pump()
	var c := make_session("c1", rider("Ann"))
	c.join_room(h.room_code)
	c.leave()
	pump()
	assert_eq(c.state, "offline")
	assert_eq(c.local_peer, 0)
	assert_false(c.transport.is_open(), "the in-flight join never lands")
	assert_false(
		events("c1", "state").any(func(e: Array) -> bool: return e[1] == "joined"), str(logs["c1"])
	)
	assert_eq(h.lobby_slots().size(), 1, "the host never lists it")
	var left := events("host", "peer_left")
	if not left.is_empty():
		assert_eq(left.back()[2], "left", "an explicit leave, not a held drop")


func test_leave_while_reconnecting_stops_the_rejoin() -> void:
	var r := room()
	var c1 := r[1]
	clear_logs()
	_lt(c1).simulate_drop()
	pump(1)
	assert_eq(c1.state, "reconnecting")
	c1.leave()
	pump(8)
	assert_eq(c1.state, "offline")
	assert_eq(c1.local_peer, 0)
	assert_false(
		events("c1", "state").any(func(e: Array) -> bool: return e[1] == "joined"), str(logs["c1"])
	)
	assert_eq(r[0].lobby_slots().size(), 2)


func test_refusal_while_hosting_is_pending_cancels_the_create() -> void:
	var h := make_session("host", rider("Hana"))
	h.host_room()
	h.start_offline()
	pump()
	assert_eq(h.state, "offline")
	assert_true(h.offline)
	assert_false(h.transport.is_open(), "the room created in flight is left")
	assert_eq(hub.rooms.room_codes().size(), 0, "and closed on the relay")


# --- coalescing ----------------------------------------------------------------------------


func test_coalescing_holds_100_ms_at_real_time_poll_rates() -> void:
	# The autoload polls every frame (here 100 fps) while the GameHost sends a course grade
	# every sim step (20 Hz): at most one per 100 ms reaches the client, the latest last.
	var r := room()
	var h := r[0]
	for s in r:
		s.set_time(0.0)
	clear_logs()
	var sent := 0
	for step in 200:
		if step % 5 == 0:
			sent += 1
			h.send_to(2, _grade(sent, float(sent)))
		for s in r:
			s.tick(0.01)
	for _i in 20:
		for s in r:
			s.tick(0.01)
	var got: Array = []
	for m: Array in messages("c1", "directive"):
		got.append(int((m[2] as Dictionary)["id"]))
	assert_eq(sent, 40)
	assert_between(got.size(), 19, 21, "about 10 a second over 2 s: %s" % str(got))
	assert_eq(got.back(), sent, "the latest grade always arrives")
	var sorted := got.duplicate()
	sorted.sort()
	assert_eq(got, sorted, "in order")


func test_coalesced_directive_flushes_with_a_frozen_clock() -> void:
	var r := room()
	var h := r[0]
	h.set_time(5.0)
	clear_logs()
	h.send_to(2, _grade(1, 1.0))
	h.send_to(2, _grade(2, 2.0))
	pump(4)
	var got: Array = []
	for m: Array in messages("c1", "directive"):
		got.append(int((m[2] as Dictionary)["id"]))
	assert_eq(got, [1, 2], "a pending grade is not stuck when time stands still")


func test_autoload_polling_several_times_a_frame_never_releases_early() -> void:
	# The autoload's time moves only in _process; the GameHost's tick() then just polls,
	# so several polls share one time. That is not a frozen clock.
	var r := room()
	var h := r[0]
	h.auto_poll = true
	h.set_time(0.0)
	clear_logs()
	h.send_to(2, _grade(1, 1.0))
	h.send_to(2, _grade(2, 2.0))
	for _i in 6:
		h.tick(Wl.SIM_DT)
	pump(3)
	var got: Array = []
	for m: Array in messages("c1", "directive"):
		got.append(int((m[2] as Dictionary)["id"]))
	assert_eq(got, [1], "the second grade waits for its 100 ms")
	h._process(0.1)
	pump(3)
	got.clear()
	for m: Array in messages("c1", "directive"):
		got.append(int((m[2] as Dictionary)["id"]))
	assert_eq(got, [1, 2])


# --- lobby limits --------------------------------------------------------------------------


func test_player_limit_holds_when_peers_join_together() -> void:
	var h := make_session("host", rider("Hana", "1", 250, {"games": {"duo": "1"}}))
	h.set_game_manifest(
		{"id": "duo", "version": "1", "min_players": 1, "max_players": 2, "bots": false}
	)
	h.set_game("duo", "1", "a")
	h.host_room(8)
	pump()
	var a := make_session("a", rider("A", "1", 200, {"games": {"duo": "1"}}))
	var b := make_session("b", rider("B", "1", 200, {"games": {"duo": "1"}}))
	a.join_room(h.room_code)
	b.join_room(h.room_code)
	pump(6)
	assert_eq(h.lobby_slots().size(), 2, "max_players 2")
	assert_eq(a.state, "joined")
	assert_true(U.same(events("b", "refused"), [["refused", "room_full"]]), str(logs["b"]))


# --- installed games from the GameRegistry ---------------------------------------------------


class FakeRegistry:
	extends Node

	func games() -> Array[Dictionary]:
		var out: Array[Dictionary] = [
			{"id": "workout", "version": "1"}, {"id": "siege", "version": 2.0}
		]
		return out

	func manifest(id: String) -> Dictionary:
		if id == "siege":
			return {
				"id": "siege",
				"version": "2",
				"min_players": 1,
				"max_players": 4,
				"bots": true,
				"options": [{"id": "rotation", "type": "toggle", "default": true}],
				"player_options":
				[{"id": "wave_offset", "type": "int", "default": 0, "min": -5, "max": 5}]
			}
		return {}


func test_local_profile_without_games_uses_the_registry() -> void:
	var reg := FakeRegistry.new()
	add_child_autofree(reg)
	var h := make_session("host")
	h.registry = reg
	var p := RiderProfile.new()
	p.display_name = "Hana"
	h.set_local_profile(p)
	h.set_game("siege", "2", "shift_1")
	h.host_room()
	pump()
	var c := make_session("c1")
	c.registry = reg
	var q := RiderProfile.new()
	q.display_name = "Bo"
	c.set_local_profile(q)
	c.join_room(h.room_code)
	pump()
	assert_eq(player(h, 2)["game_issue"], "", "the registry's games went into player_info")
	assert_eq(c.ready_block_reason(), "")
	assert_eq(h.max_players, 4, "limits from the registry manifest")
	assert_eq(h.lobby["settings"]["options"], {"rotation": true})
	assert_eq(float(h.lobby["player_options"][2]["wave_offset"]), 0.0)
	c.set_ready(true)
	pump()
	assert_true(bool(player(h, 2)["ready"]))


# --- persistence ---------------------------------------------------------------------------


func test_token_file_defaults_to_paths() -> void:
	var h := make_session("host", rider("Hana"))
	h.host_room()
	pump()
	var c := make_session("c1", rider("Ann"))
	c.token_path = ""
	c.recent_rooms_file = ""
	c.join_room(h.room_code)
	pump()
	var path := Paths.reconnect_token_path()
	assert_true(path.begins_with(tmp), path)
	assert_true(FileAccess.file_exists(path))
	assert_true(FileAccess.file_exists(Paths.recent_rooms_path()))
	h.mark_started()
	pump()
	var code := h.room_code
	sessions.erase(c)
	c.free()
	pump()
	var again := make_session("c1b", rider("Ann"))
	again.token_path = ""
	again.join_room(code)
	pump()
	assert_eq(again.local_peer, 2, "the restarted client found its token under Paths")
	assert_eq(events("c1b", "refused").size(), 0)
	again.leave()
	assert_false(FileAccess.file_exists(path), "leave removes it")


# --- reconnect -----------------------------------------------------------------------------


func test_drop_during_the_rejoin_handshake_retries_with_the_same_token() -> void:
	var r := room()
	var c1 := r[1]
	r[0].mark_started()
	pump()
	clear_logs()
	_lt(c1).simulate_drop()
	pump(1)
	assert_eq(c1.state, "reconnecting")
	assert_eq(_lt(c1).pending_frames(), 1, "the rejoin went out at once; its answer is in flight")
	_lt(c1).simulate_drop()
	pump(60)
	assert_eq(c1.state, "joined")
	assert_eq(c1.local_peer, 2, "the token survived the lost answer")
	assert_eq(events("c1", "refused").size(), 0)
	assert_eq(events("host", "rejoin_requested").back(), ["rejoin_requested", 2])


func test_rate_limited_rejoin_keeps_trying() -> void:
	var r := room()
	var c1 := r[1]
	c1.auto_reconnect = false
	_lt(c1).simulate_drop()
	pump()
	assert_eq(c1.state, "reconnecting")
	c1.transport.disconnected.emit("rate_limited")
	assert_eq(c1.state, "reconnecting", "a rate-limited rejoin is retried, not a refusal")
	assert_eq(events("c1", "refused").size(), 0)
	c1.rejoin()
	pump()
	assert_eq(c1.state, "joined")
	assert_eq(c1.local_peer, 2)


func _snap(seq: int) -> Dictionary:
	return Protocol.game_msg(
		"snapshot", {"game_id": "workout", "seq": seq, "t": seq * 0.1, "state": {"n": seq}}
	)


func test_rejoined_client_takes_the_hosts_latest_snapshot_whatever_its_seq() -> void:
	var r := room()
	var h := r[0]
	var c1 := r[1]
	h.mark_started()
	for i in range(1, 11):
		h.broadcast(_snap(i))
	pump()
	assert_eq(int(c1.latest_snapshot()["seq"]), 10)
	h.rejoin_requested.connect(func(peer: int) -> void: h.send_to(peer, _snap(3)))
	_lt(c1).simulate_drop()
	pump()
	assert_eq(c1.state, "joined")
	assert_eq(int(c1.latest_snapshot()["seq"]), 3, "the snapshot sent for the rejoin is applied")
	assert_eq(int(c1.stats["stale_snapshots"]), 0)


func test_snapshots_of_another_game_start_a_new_buffer() -> void:
	var r := room()
	var h := r[0]
	var c1 := r[1]
	for i in range(1, 4):
		h.broadcast(_snap(i))
	h.broadcast(
		Protocol.game_msg("snapshot", {"game_id": "siege", "seq": 1, "t": 0.5, "state": {}})
	)
	pump()
	assert_eq(c1.snapshot_buffer().size(), 1, "never interpolate across games")
	assert_eq(c1.latest_snapshot()["game_id"], "siege")
	var pair := c1.snapshot_pair_at(0.4)
	assert_eq((pair["from"] as Dictionary)["game_id"], "siege")


func test_session_start_and_end_in_lobby_state_reset_snapshot_seqs() -> void:
	var r := room()
	var h := r[0]
	var c1 := r[1]
	h.mark_started()
	for i in range(1, 6):
		h.broadcast(_snap(i))
	pump()
	assert_eq(c1.snapshot_buffer().size(), 5)
	h.mark_ended()
	pump()
	assert_false(c1.session_started)
	assert_true(c1.snapshot_buffer().is_empty(), "the session ended")
	h.mark_started()
	h.broadcast(_snap(1))
	pump()
	assert_true(c1.session_started)
	assert_eq(int(c1.latest_snapshot()["seq"]), 1, "a new session's first snapshot is not stale")


## One scripted HOST + client run on a fresh hub; returns what each side saw.
func _scripted_run(tag: String) -> Array:
	sessions.clear()
	hub = LoopbackHub.new(7)
	var h := make_session("host" + tag, rider("Hana", "1", 250))
	h.set_game("workout", "1", "easy30")
	h.host_room(8)
	pump()
	var c := make_session("c" + tag, rider("Bo", "1", 210))
	c.join_room(h.room_code)
	pump()
	h.add_bot()
	c.set_ready(true)
	h.set_ready(true)
	pump()
	h.mark_started()
	for i in 40:
		h.broadcast(_snap(i + 1))
		h.send_to(2, _grade(i, 0.5 * i))
		if i % 4 == 0:
			c.send_to_host(
				Protocol.game_msg("telemetry", {"tm": {"peer": 2, "power_w": 150.0 + i}})
			)
		if i == 20:
			_lt(c).simulate_drop()
		h.tick(Wl.SIM_DT)
		c.tick(Wl.SIM_DT)
	pump(30)
	return [
		h.room_code,
		(logs["host" + tag] as Array).duplicate(true),
		(logs["c" + tag] as Array).duplicate(true),
		h.stats.duplicate(),
		c.stats.duplicate()
	]


func test_loopback_runs_are_deterministic() -> void:
	# OWNERSHIP C29: same seed, same calls, same codes, messages, order and counters.
	var a := _scripted_run("_a")
	var b := _scripted_run("_b")
	assert_eq(a[0], b[0], "same room code")
	assert_true(U.same(a[1], b[1]), "host: " + U.diff(a[1], b[1]))
	assert_true(U.same(a[2], b[2]), "client: " + U.diff(a[2], b[2]))
	assert_true(U.same(a[3], b[3]), U.diff(a[3], b[3]))
	assert_true(U.same(a[4], b[4]), U.diff(a[4], b[4]))
	assert_gt((a[2] as Array).size(), 40)


# --- host-side checks ------------------------------------------------------------------------


func test_telemetry_peer_is_the_sender() -> void:
	var r := room()
	clear_logs()
	r[1].send_to_host(Protocol.game_msg("telemetry", {"tm": {"peer": 3, "power_w": 150.0}}))
	pump()
	var tm := messages("host", "telemetry")
	assert_eq(tm.size(), 1)
	assert_eq(tm[0][1], 2)
	assert_eq(
		((tm[0][2] as Dictionary)["tm"] as Dictionary)["peer"],
		2,
		"a client can't speak for another rider"
	)


# --- system nodes ----------------------------------------------------------------------------


func test_session_and_transports_run_while_paused() -> void:
	var nodes: Array[Node] = [
		WlNetSession.new(),
		LoopbackTransport.hub_transport(hub),
		RelayTransport.new(),
		LanTransport.new(),
		LocalRelayServer.new()
	]
	for n in nodes:
		assert_eq(n.process_mode, Node.PROCESS_MODE_ALWAYS, n.get_class())
		n.free()
	# A paused tree does not stop the session: poll() runs from tick() and _process.
	var r := room()
	get_tree().paused = true
	var processing: Array = []
	for s in r:
		processing.append(s.can_process() and s.transport.can_process())
	r[0].broadcast(_snap(1))
	pump()
	get_tree().paused = false
	assert_eq(
		processing, [true, true, true], "sessions and transports keep processing while paused"
	)
	assert_eq(messages("c1", "snapshot").size(), 1)


# --- strings -------------------------------------------------------------------------------


func test_every_end_reason_has_a_readable_text() -> void:
	var reasons: Array[String] = []
	reasons.append_array(WlNetSession.REFUSALS)
	reasons.append_array(["host_left", "dropped", "closed", "timeout", "error"])
	for reason in reasons:
		var key := WlNetSession.reason_key(reason)
		assert_true(key.begins_with("NET_REFUSED_"), key)
		assert_ne(WlNetSession.reason_text(reason), reason, "a text for %s" % reason)
	assert_eq(
		WlNetSession.reason_text("no_such_reason"), "no_such_reason", "unknown reasons pass through"
	)


func test_net_strings_are_platform_keys() -> void:
	var f := FileAccess.open("res://content/strings/net.csv", FileAccess.READ)
	assert_not_null(f)
	assert_eq(f.get_csv_line(), PackedStringArray(["keys", "en"]))
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 2 or row[0] == "":
			continue
		assert_true(row[0].begins_with("NET_"), row[0])
		for prefix in ["WORKOUT_", "SIEGE_", "TANK_", "FISHING_", "_TEMPLATE_"]:
			assert_false(row[0].begins_with(prefix), row[0])
		assert_ne(row[1], "", row[0])


# --- protocol --------------------------------------------------------------------------------


func test_hud_args_come_back_as_drawn_on_the_host() -> void:
	var msg := Protocol.game_msg(
		"hud", {"kind": "toast", "key": "SIEGE_TOAST_BUY", "args": ["ram", 2, 2.5, -3]}
	)
	var back := Protocol.decode_game(U.json_round_trip(msg))
	assert_true(U.same(back, msg), U.diff(back, msg))
	var named := Protocol.game_msg(
		"hud", {"kind": "banner", "key": "K", "args": {"name": "Bo", "n": 4}, "seconds": 3.0}
	)
	var back2 := Protocol.decode(Protocol.encode(named))
	assert_true(U.same(back2, named), U.diff(back2, named))
	assert_typeof(back2["seconds"], TYPE_FLOAT)


func test_platform_events_get_ints_without_game_fields() -> void:
	var ev := Protocol.decode(
		Protocol.encode(
			Protocol.game_msg(
				"event",
				{
					"seq": 1,
					"events":
					[
						{"type": "phase_started", "peer_id": 2, "index": 3, "tick": 120},
						{"type": "boom", "n": 2}
					]
				}
			)
		)
	)
	Protocol.apply_game_int_fields(ev, {})
	var e0: Dictionary = (ev["events"] as Array)[0]
	assert_typeof(e0["index"], TYPE_INT)
	assert_typeof(e0["tick"], TYPE_INT)
	assert_typeof(
		((ev["events"] as Array)[1] as Dictionary)["n"], TYPE_FLOAT, "game events need int_fields"
	)
	var r := room()
	clear_logs()
	r[0].broadcast(
		Protocol.game_msg(
			"event", {"seq": 1, "events": [{"type": "phase_started", "peer_id": 2, "index": 1}]}
		)
	)
	pump()
	var got: Dictionary = ((messages("c1", "event")[0][2] as Dictionary)["events"] as Array)[0]
	assert_typeof(
		got["index"], TYPE_INT, "a client without set_game_int_fields still gets an int index"
	)


func test_decode_tolerates_any_json_whitespace() -> void:
	var text := '{"type":"snapshot","v":1,"game_id":"g","seq":\n 4,"state":{"target_id" :\r\n\t3,"x": 1.5,"name_id": "n"}}'
	var d := Protocol.decode(text)
	assert_false(d.is_empty())
	assert_typeof(d["seq"], TYPE_INT)
	assert_typeof((d["state"] as Dictionary)["target_id"], TYPE_INT)
	assert_eq((d["state"] as Dictionary)["name_id"], "n")
	var pretty := Protocol.decode(
		JSON.stringify(
			Protocol.game_msg("event", {"seq": 1, "events": [{"type": "kill", "enemy_id": 7}]}),
			"\t"
		)
	)
	assert_typeof(((pretty["events"] as Array)[0] as Dictionary)["enemy_id"], TYPE_INT)
