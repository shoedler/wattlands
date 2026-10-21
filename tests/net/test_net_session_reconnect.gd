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


## A relay that refuses every create carrying a code (`refuse_all`: every create), like a relay
## that does not know the P1 field.
class CodeRefusingRooms:
	extends RelayRooms
	var refused: int = 0
	var refuse_all: bool = false

	func _on_create(conn: int, c: Dictionary, msg: Dictionary) -> void:
		if refuse_all or msg.get("code") is String:
			refused += 1
			_error(conn, "bad_request")
			return
		super._on_create(conn, c, msg)


func _refusing_hub(refuse_all: bool = false) -> CodeRefusingRooms:
	var rooms := CodeRefusingRooms.new()
	rooms.rng = SeededRng.make(7)
	rooms.enforce_rate_limits = false
	rooms.enforce_idle_timeout = false
	rooms.refuse_all = refuse_all
	hub.rooms = rooms
	return rooms


## lead W2 round 2, BRIEF 5.2 P1: host_room(max_peers, preferred_code), the form the lobby
## calls (it checks get_method_argument_count("host_room") >= 2).
func test_host_room_asks_for_the_preferred_code() -> void:
	var h := make_session("host", rider("Hana"))
	assert_eq(h.get_method_argument_count("host_room"), 2)
	h.host_room(8, "k7q-x2m")
	pump()
	assert_eq(h.state, WlNetSession.STATE_HOSTING)
	assert_eq(h.room_code, "K7QX2M", "any RoomCode spelling; the relay grants a free code")
	assert_eq(events("host", "refused"), [])


func test_a_taken_or_invalid_preferred_code_gets_a_new_code() -> void:
	var r := room([])
	var taken := r[0].room_code
	var h2 := make_session("h2", rider("Bo"))
	h2.host_room(8, taken)
	pump()
	assert_eq(h2.state, WlNetSession.STATE_HOSTING)
	assert_ne(h2.room_code, taken, "the code is in use: a new one")
	assert_true(RoomCode.is_valid(h2.room_code))
	var h3 := make_session("h3", rider("Cy"))
	h3.host_room(8, "not a code!")
	pump()
	assert_eq(h3.state, WlNetSession.STATE_HOSTING)
	assert_true(RoomCode.is_valid(h3.room_code))
	assert_eq(events("h2", "refused") + events("h3", "refused"), [])


func test_a_relay_that_refuses_the_code_falls_back_to_a_new_code() -> void:
	var rooms := _refusing_hub()
	var h := make_session("host", rider("Hana"))
	h.host_room(6, "K7QX2M")
	pump()
	assert_eq(rooms.refused, 1, "the coded create was refused once")
	assert_push_warning("refused the requested room code")
	assert_eq(h.state, WlNetSession.STATE_HOSTING, "and the session hosts anyway")
	assert_true(RoomCode.is_valid(h.room_code))
	assert_ne(h.room_code, "K7QX2M")
	assert_eq(events("host", "refused"), [], "no refusal reaches the lobby")
	var c := make_session("c1", rider("Ike"))
	c.join_room(h.room_code)
	pump()
	assert_eq(c.state, WlNetSession.STATE_JOINED, "the fallback room works")


func test_the_fallback_is_tried_once_and_a_plain_create_is_never_retried() -> void:
	var rooms := _refusing_hub(true)
	var h := make_session("host", rider("Hana"))
	h.host_room(8, "K7QX2M")
	pump()
	assert_eq(rooms.refused, 2, "the coded create and one plain create")
	assert_push_warning("refused the requested room code")
	assert_eq(h.state, WlNetSession.STATE_ERROR)
	assert_true(U.same(events("host", "refused"), [["refused", "bad_request"]]))
	var h2 := make_session("h2", rider("Bo"))
	h2.host_room(8)
	pump()
	assert_eq(rooms.refused, 3, "no code asked: no retry")
	assert_true(U.same(events("h2", "refused"), [["refused", "bad_request"]]))


func test_leave_forgets_the_token() -> void:
	var r := room()
	assert_true(FileAccess.file_exists(r[1].token_path))
	r[1].leave()
	assert_false(FileAccess.file_exists(r[1].token_path))
	assert_eq(r[1].state, "offline")
	pump()
	assert_true(U.same(events("host", "peer_left").back(), ["peer_left", 2, "left"]))
	assert_eq(r[0].lobby_slots().size(), 2)


func test_private_sessions_do_not_persist_by_default() -> void:
	var s := WlNetSession.new()
	assert_false(s.persist_token, "only the NetSession autoload persists by default")
	assert_false(s.auto_poll)
	s.free()
	var autoload := get_node_or_null("/root/NetSession")
	if autoload != null:
		assert_true((autoload as WlNetSession).persist_token)
		assert_true((autoload as WlNetSession).auto_poll)


func test_tick_only_polls_when_auto_polling() -> void:
	var s := make_session("auto", rider("A"))
	s.set_time(10.0)
	s.tick(1.0)
	assert_eq(s.local_time(), 11.0)
	s.auto_poll = true
	s.tick(1.0)
	assert_eq(s.local_time(), 11.0, "the autoload's time follows _process only")


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
