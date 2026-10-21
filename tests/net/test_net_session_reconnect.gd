extends "res://tests/net/net_session_test_base.gd"
## WlNetSession drops, rejoins and refusals over LoopbackTransport (BRIEF 3.6, 5.3, 5.5;
## OWNERSHIP NET6, NET7, GM7): drop and rejoin keeping the peer id, rejoin_requested after
## the start, a restarted client with its saved token, session_in_progress, host_left, a
## host drop, giving up after 120 s, saved tokens, recent rooms and version refusals.


func _lt(s: WlNetSession) -> LoopbackTransport:
	return s.transport as LoopbackTransport


func test_drop_and_rejoin_before_the_start_keeps_peer_id_and_slot() -> void:
	var r := room()
	var h := r[0]
	var c1 := r[1]
	c1.set_ready(true)
	pump()
	clear_logs()
	_lt(c1).simulate_drop()
	pump(1)
	assert_true(U.same(events("host", "peer_left"), [["peer_left", 2, "dropped"]]))
	assert_true(U.same(events("host", "bus_peer_left"), [["bus_peer_left", 2, "dropped"]]))
	pump()
	assert_true(U.same(events("c1", "state").front(), ["state", "reconnecting", "dropped"]), str(logs["c1"]))
	assert_eq(c1.state, "joined")
	assert_eq(c1.local_peer, 2, "the token keeps the peer id")
	assert_true(U.same(events("host", "peer_joined"), [["peer_joined", 2]]))
	assert_eq(events("host", "rejoin_requested").size(), 0, "only after the start")
	var slots := r[2].lobby_slots()
	assert_eq(slots.size(), 3)
	assert_eq(slots[1].peer_id, 2, "the same slot as before the drop")
	assert_true(bool(player(h, 2)["ready"]), "the client re-sent its ready flag")


func test_drop_after_the_start_keeps_the_slot_and_rejoin_requests_state() -> void:
	var r := room()
	var h := r[0]
	var c1 := r[1]
	h.mark_started()
	pump()
	assert_true(c1.session_started, "lobby_state says started")
	clear_logs()
	c1.auto_reconnect = false
	_lt(c1).simulate_drop()
	pump()
	assert_eq(c1.state, "reconnecting")
	assert_eq(h.lobby_slots().size(), 3, "the slot stays")
	assert_false(bool(player(h, 2)["connected"]))
	assert_eq(events("host", "peer_left").size(), 1)
	c1.rejoin()
	pump()
	assert_eq(c1.state, "joined")
	assert_eq(c1.local_peer, 2)
	assert_true(U.same(events("host", "rejoin_requested"), [["rejoin_requested", 2]]))
	assert_true(bool(player(h, 2)["connected"]))
	assert_gt(messages("c1", "lobby_state").size(), 0, "the host re-sent lobby_state")
	assert_true(c1.session_started)


func test_restarted_client_rejoins_with_its_saved_token() -> void:
	var r := room()
	var h := r[0]
	var c1 := r[1]
	var code := h.room_code
	h.mark_started()
	pump()
	var token_file := c1.token_path
	assert_true(FileAccess.file_exists(token_file))
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(token_file))
	assert_eq((saved as Dictionary)["code"], code)
	assert_eq(int((saved as Dictionary)["peer"]), 2)
	# The process dies: the session and its transport are freed without a leave.
	sessions.erase(c1)
	c1.free()
	pump()
	assert_true(U.same(events("host", "peer_left").back(), ["peer_left", 2, "dropped"]))
	var again := make_session("c1b", rider("Rider 1", "1", 210))
	again.token_path = token_file
	again.join_room(RoomCode.format(code))
	pump()
	assert_eq(again.local_peer, 2, "same peer id from the saved token")
	assert_true(U.same(events("host", "rejoin_requested"), [["rejoin_requested", 2]]))
	assert_eq(events("c1b", "refused").size(), 0)
	assert_true(again.session_started)


func test_joins_after_the_start_are_refused_with_session_in_progress() -> void:
	var r := room()
	var h := r[0]
	# A peer that joined but never sent player_info is refused at the start.
	var raw := LoopbackTransport.hub_transport(hub)
	add_child_autofree(raw)
	var raw_msgs: Array = []
	raw.message.connect(func(_f: int, d: Dictionary) -> void: raw_msgs.append(d))
	raw.join(h.room_code)
	raw.poll()
	pump()
	raw.poll()
	h.mark_started()
	pump()
	raw.poll()
	assert_true(raw_msgs.any(func(d: Dictionary) -> bool: return d["type"] == "refused" and d["reason"] == "session_in_progress"))
	clear_logs()
	var late := make_session("late", rider("Late"))
	late.join_room(h.room_code)
	pump()
	assert_true(U.same(events("late", "refused"), [["refused", "session_in_progress"]]))
	assert_true(U.same(events("late", "bus_refused"), [["bus_refused", "session_in_progress"]]))
	assert_eq(late.state, "error")
	assert_eq(late.refusal_reason, "session_in_progress")
	assert_false(late.transport.is_open(), "the refused client leaves the room")
	assert_ne(WlNetSession.reason_text("session_in_progress"), "session_in_progress", "a readable message")
	assert_eq(events("host", "peer_joined").size(), 0, "the host never lists it")
	assert_eq(events("host", "peer_left").size(), 0)
	assert_eq(h.lobby_slots().size(), 3)


func test_host_left_ends_the_session_gracefully() -> void:
	var r := room()
	var c1 := r[1]
	assert_true(FileAccess.file_exists(c1.token_path))
	r[0].leave()
	assert_eq(r[0].state, "offline")
	pump()
	for label in ["c1", "c2"]:
		assert_true(U.same(events(label, "refused"), [["refused", "host_left"]]), label)
		assert_true(U.same(events(label, "bus_refused"), [["bus_refused", "host_left"]]), label)
	assert_eq(c1.state, "offline")
	assert_eq(c1.room_code, "")
	assert_eq(c1.role, "")
	assert_false(FileAccess.file_exists(c1.token_path), "the token is forgotten")


func test_host_drop_and_reconnect() -> void:
	var r := room()
	var h := r[0]
	var code := h.room_code
	clear_logs()
	_lt(h).simulate_drop()
	pump(1)
	for label in ["c1", "c2"]:
		assert_true(U.same(events(label, "peer_left"), [["peer_left", 1, "dropped"]]), label)
	pump()
	assert_eq(h.state, "hosting")
	assert_eq(h.local_peer, 1)
	assert_eq(h.room_code, code)
	for label in ["c1", "c2"]:
		assert_true(U.same(events(label, "peer_joined"), [["peer_joined", 1]]), label)
		assert_gt(messages(label, "lobby_state").size(), 0, label)
	assert_eq(r[2].lobby_slots().size(), 3)


func test_reconnect_gives_up_after_the_token_life() -> void:
	var r := room()
	var c1 := r[1]
	c1.auto_reconnect = false
	c1.set_time(10.0)
	_lt(c1).simulate_drop()
	pump()
	assert_eq(c1.state, "reconnecting")
	c1.tick(60.0)
	assert_eq(c1.state, "reconnecting")
	c1.tick(61.0)
	assert_eq(c1.state, "error")
	assert_true(U.same(events("c1", "refused"), [["refused", "dropped"]]))


func test_rejoin_into_a_closed_room_is_refused() -> void:
	var r := room()
	var c1 := r[1]
	c1.auto_reconnect = false
	_lt(c1).simulate_drop()
	pump()
	r[0].leave()
	pump()
	c1.rejoin()
	pump()
	assert_true(U.same(events("c1", "refused"), [["refused", "room_not_found"]]))
	assert_eq(c1.state, "error")


func test_bad_codes_and_unknown_rooms() -> void:
	var s := make_session("x", rider("X"))
	s.join_room("??")
	assert_push_warning("is not a room code")
	assert_true(U.same(events("x", "refused"), [["refused", "room_not_found"]]))
	var t := make_session("y", rider("Y"))
	t.join_room("ZZZ-ZZZ")
	pump()
	assert_true(U.same(events("y", "refused"), [["refused", "room_not_found"]]))
	assert_true(U.same(events("y", "bus_refused"), [["bus_refused", "room_not_found"]]))


func test_room_full_at_the_lobby() -> void:
	var h := make_session("host", rider("Hana"))
	h.set_game_manifest({"id": "duo", "version": "1", "min_players": 1, "max_players": 2, "bots": false})
	h.set_game("duo", "1", "a")
	h.host_room(8)
	pump()
	var a := make_session("a", rider("A", "1", 200, {"games": {"duo": "1"}}))
	a.join_room(h.room_code)
	pump()
	var b := make_session("b", rider("B", "1", 200, {"games": {"duo": "1"}}))
	b.join_room(h.room_code)
	pump()
	assert_true(U.same(events("b", "refused"), [["refused", "room_full"]]))
	assert_eq(h.lobby_slots().size(), 2)


func test_other_schema_versions_are_refused_both_ways() -> void:
	var r := room()
	(r[1].transport as RelayClientTransport).send_encoded(1, JSON.stringify(
		{"type": "player_info", "v": NetMessages.VERSION + 1, "name": "Future"}))
	pump()
	assert_true(U.same(events("c1", "refused"), [["refused", "version_mismatch"]]))
	assert_eq(r[0].lobby_slots().size(), 2, "the host dropped the mismatched client from the lobby")
	(r[0].transport as RelayClientTransport).send_encoded(3, JSON.stringify(
		{"type": "phase", "v": NetMessages.VERSION + 1, "index": 1, "start_tick": 0, "ended_by": "x"}))
	pump()
	assert_true(U.same(events("c2", "refused"), [["refused", "version_mismatch"]]))


func test_recent_rooms_and_host_code_reclaim() -> void:
	var r := room()
	var h := r[0]
	var code := h.room_code
	assert_eq((h.recent_rooms()[0] as Dictionary)["code"], code)
	assert_eq((h.recent_rooms()[0] as Dictionary)["role"], Wl.HOST)
	assert_eq((r[1].recent_rooms()[0] as Dictionary)["role"], Wl.CLIENT)
	assert_eq(h.last_hosted_code(), code)
	h.leave()
	pump()
	h.host_room_reclaim(8)
	pump()
	assert_eq(h.room_code, code, "the previous code is free again")
	assert_eq(h.recent_rooms().size(), 1, "no duplicate entries")


func test_leave_forgets_the_token() -> void:
	var r := room()
	assert_true(FileAccess.file_exists(r[1].token_path))
	r[1].leave()
	assert_false(FileAccess.file_exists(r[1].token_path))
	assert_eq(r[1].state, "offline")
	pump()
	assert_true(U.same(events("host", "peer_left").back(), ["peer_left", 2, "left"]))
	assert_eq(r[0].lobby_slots().size(), 2)


func test_in_memory_tokens_when_not_persisted() -> void:
	var h := make_session("host", rider("Hana"))
	h.persist_token = false
	h.host_room()
	pump()
	var c := make_session("c1", rider("Ann"))
	c.persist_token = false
	c.join_room(h.room_code)
	pump()
	assert_false(FileAccess.file_exists(c.token_path))
	_lt(c).simulate_drop()
	pump()
	assert_eq(c.local_peer, 2, "reconnects with the token it keeps in memory")
	assert_eq(c.state, "joined")
