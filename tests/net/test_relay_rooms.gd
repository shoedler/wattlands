extends GutTest
## RelayRooms (BRIEF 5.3 semantics without sockets): hello and version check, codes, peer
## ids from 1, to: 0 broadcast excluding the sender, non-hosts only to the host, leave,
## drops, reconnect tokens (120 s, same peer id), held host rooms, room_full, the 16 KB
## limit, 60 msgs/s (burst 120), the idle timeout and the P1 requested code.

const U := preload("res://tests/net/net_test_util.gd")

var r: RelayRooms


func before_each() -> void:
	r = RelayRooms.new()
	r.rng = SeededRng.make(5)
	r.enforce_idle_timeout = false


func _send(conn: int, env: Dictionary) -> void:
	r.receive(conn, JSON.stringify(env))


func _hello(conn: int) -> void:
	r.open(conn)
	_send(conn, {"t": "hello", "proto": Wl.PROTO, "game": Wl.RELAY_GAME, "build": Wl.BUILD})


## Output as {conn: [envelopes...]}.
func _out() -> Dictionary:
	var by: Dictionary = {}
	for pair: Array in r.take_output():
		var c := int(pair[0])
		if not by.has(c):
			by[c] = []
		(by[c] as Array).append(pair[1])
	return by


func _create(conn: int, max_n: int = 8) -> Dictionary:
	_hello(conn)
	_send(conn, {"t": "create", "max": max_n})
	return (_out()[conn] as Array)[0]


func _join(conn: int, code: String, token: Variant = null) -> Dictionary:
	_hello(conn)
	_send(conn, {"t": "join", "code": code, "token": token})
	var o := _out()
	return (o[conn] as Array)[0] if o.has(conn) else {}


func test_create_gives_code_peer_1_and_token() -> void:
	var created := _create(1)
	assert_eq(created["t"], "created")
	assert_eq(created["peer"], 1)
	assert_true(RoomCode.is_valid(str(created["code"])))
	assert_eq(str(created["code"]).length(), 6)
	assert_ne(str(created["token"]), "")
	assert_true(r.has_room(created["code"]))


func test_codes_are_deterministic_for_a_seed_and_unique() -> void:
	var codes := {}
	for i in 20:
		var c := _create(i + 1)
		codes[c["code"]] = true
	assert_eq(codes.size(), 20)
	var r2 := RelayRooms.new()
	r2.rng = SeededRng.make(5)
	r2.open(1)
	r2.receive(1, JSON.stringify({"t": "hello", "proto": 1, "game": "wattlands", "build": "x"}))
	r2.receive(1, JSON.stringify({"t": "create", "max": 8}))
	var first: Array = r2.take_output()[0]
	assert_true(codes.has((first[1] as Dictionary)["code"]))


func test_join_assigns_peer_ids_from_2_and_announces() -> void:
	var code: String = _create(1)["code"]
	var j := _join(2, code.to_lower().insert(3, "-"))
	assert_eq(j["t"], "joined", "codes are normalized")
	assert_eq(j["peer"], 2)
	assert_eq(j["host"], 1)
	_hello(3)
	_send(3, {"t": "join", "code": code, "token": null})
	var o := _out()
	assert_eq(((o[3] as Array)[0] as Dictionary)["peer"], 3)
	assert_true(U.same((o[1] as Array)[0], {"t": "peer_joined", "peer": 3}))
	assert_true(U.same((o[2] as Array)[0], {"t": "peer_joined", "peer": 3}))


func test_hello_is_required_and_checked() -> void:
	r.open(1)
	_send(1, {"t": "create", "max": 4})
	assert_eq(((_out()[1] as Array)[0] as Dictionary)["code"], "bad_request")
	r.open(2)
	_send(2, {"t": "hello", "proto": Wl.PROTO + 1, "game": Wl.RELAY_GAME, "build": "9"})
	assert_eq(((_out()[2] as Array)[0] as Dictionary)["code"], "version_mismatch")
	assert_eq(r.take_closes(), [2] as Array[int])


func test_unknown_room_and_malformed_input() -> void:
	_hello(1)
	_send(1, {"t": "join", "code": "ZZZZZZ", "token": null})
	assert_eq(((_out()[1] as Array)[0] as Dictionary)["code"], "room_not_found")
	r.receive(1, "{not json")
	assert_eq(((_out()[1] as Array)[0] as Dictionary)["code"], "bad_request")
	_send(1, {"t": "warp"})
	assert_eq(((_out()[1] as Array)[0] as Dictionary)["code"], "bad_request")
	_send(1, {"t": "msg", "to": 1, "d": {}})
	assert_eq(((_out()[1] as Array)[0] as Dictionary)["code"], "bad_request", "msg outside a room")


func test_routing_rules() -> void:
	var code: String = _create(1)["code"]
	_join(2, code)
	_join(3, code)
	_out()
	# Host broadcast: everyone but the sender.
	_send(1, {"t": "msg", "to": 0, "d": {"x": 1}})
	var o := _out()
	assert_false(o.has(1))
	assert_true(U.same((o[2] as Array)[0], {"t": "msg", "from": 1, "d": {"x": 1.0}}))
	assert_true(o.has(3))
	# Host to one peer.
	_send(1, {"t": "msg", "to": 3, "d": {"y": 2}})
	o = _out()
	assert_true(o.has(3) and not o.has(2))
	# Client to host.
	_send(2, {"t": "msg", "to": 1, "d": {"z": 3}})
	o = _out()
	assert_eq(((o[1] as Array)[0] as Dictionary)["from"], 2)
	# Non-hosts may only send to the host.
	_send(2, {"t": "msg", "to": 3, "d": {}})
	o = _out()
	assert_false(o.has(3))
	assert_eq(((o[2] as Array)[0] as Dictionary)["code"], "bad_request")
	_send(2, {"t": "msg", "to": 0, "d": {}})
	o = _out()
	assert_eq(((o[2] as Array)[0] as Dictionary)["code"], "bad_request")
	assert_false(o.has(1))
	# The fast path routes the same way.
	assert_eq(r.route(4242, 1, 10), [] as Array[int], "unknown connection")
	assert_eq(r.route(2, 1, 10).size(), 1)
	assert_eq(r.route(1, 0, 10).size(), 2)


func test_leave_and_host_leave() -> void:
	var code: String = _create(1)["code"]
	_join(2, code)
	_join(3, code)
	_out()
	_send(2, {"t": "leave"})
	var o := _out()
	assert_true(U.same((o[1] as Array)[0], {"t": "peer_left", "peer": 2, "reason": "left"}))
	assert_true(U.same((o[3] as Array)[0], {"t": "peer_left", "peer": 2, "reason": "left"}))
	_send(1, {"t": "leave"})
	o = _out()
	assert_true(U.same((o[3] as Array)[0], {"t": "host_left"}))
	assert_false(o.has(1))
	assert_false(r.has_room(code))


func test_drop_and_reconnect_keeps_peer_id() -> void:
	var code: String = _create(1)["code"]
	var j := _join(2, code)
	_out()
	r.closed(2)
	var o := _out()
	assert_true(U.same((o[1] as Array)[0], {"t": "peer_left", "peer": 2, "reason": "dropped"}))
	r.advance(60.0)
	var back := _join(5, code, j["token"])
	assert_eq(back["t"], "joined")
	assert_eq(back["peer"], 2, "the token keeps the peer id")
	assert_eq(back["token"], j["token"], "the peer keeps its token")
	# The answer may be lost (a second drop mid-handshake): the same token still works, and
	# a socket that comes back with it supersedes the one still open.
	var again := _join(6, code, j["token"])
	assert_eq(again["peer"], 2)
	assert_eq(r.take_closes(), [5] as Array[int], "the superseded socket is closed")
	var fresh := _join(7, code)
	assert_eq(fresh["peer"], 3, "a join without a token is a new peer")
	assert_ne(fresh["token"], j["token"])


func test_tokens_expire_after_120_s() -> void:
	var code: String = _create(1)["code"]
	var j := _join(2, code)
	r.closed(2)
	r.advance(121.0)
	_out()
	var late := _join(3, code, j["token"])
	assert_eq(late["peer"], 3, "an expired token joins as a new peer")
	assert_false(r.room_peers(code).has(2))


func test_host_drop_is_held_then_host_left() -> void:
	var created := _create(1)
	var code: String = created["code"]
	_join(2, code)
	_out()
	r.closed(1)
	var o := _out()
	assert_true(U.same((o[2] as Array)[0], {"t": "peer_left", "peer": 1, "reason": "dropped"}))
	r.advance(100.0)
	assert_true(r.has_room(code), "held for 120 s")
	_hello(7)
	_send(7, {"t": "join", "code": code, "token": created["token"]})
	o = _out()
	assert_eq(((o[7] as Array)[0] as Dictionary)["peer"], 1, "the host reclaims peer 1")
	assert_true(U.same((o[2] as Array)[0], {"t": "peer_joined", "peer": 1}))
	r.closed(7)
	_out()
	r.advance(121.0)
	o = _out()
	assert_true(U.same((o[2] as Array)[0], {"t": "host_left"}))
	assert_false(r.has_room(code))


func test_room_full() -> void:
	var code: String = _create(1, 2)["code"]
	assert_eq(_join(2, code)["peer"], 2)
	assert_eq(_join(3, code)["code"], "room_full")
	r.closed(2)
	_out()
	assert_eq(_join(4, code)["code"], "room_full", "a dropped peer's slot is held")


func test_message_size_limit() -> void:
	var code: String = _create(1)["code"]
	_join(2, code)
	_out()
	var big := "x".repeat(NetMessages.MAX_MESSAGE_BYTES)
	_send(1, {"t": "msg", "to": 2, "d": {"s": big}})
	var o := _out()
	assert_false(o.has(2))
	assert_eq(((o[1] as Array)[0] as Dictionary)["code"], "bad_request")
	assert_eq(r.route(1, 2, NetMessages.MAX_MESSAGE_BYTES + 1).size(), 0)


func test_rate_limit_60_per_second_burst_120() -> void:
	var code: String = _create(1)["code"]
	_join(2, code)
	_out()
	var delivered := 0
	for i in 130:
		delivered += r.route(2, 1, 50).size()
	assert_eq(delivered, 120 - 2, "burst 120 minus hello and join")
	var errs := 0
	for pair: Array in r.take_output():
		if (
			(pair[1] as Dictionary)["t"] == "error"
			and (pair[1] as Dictionary)["code"] == "rate_limited"
		):
			errs += 1
	assert_eq(errs, 12)
	r.advance(1.0)
	delivered = 0
	for i in 70:
		delivered += r.route(2, 1, 50).size()
	assert_eq(delivered, 60, "60 more after one second")
	r.take_output()
	r.enforce_rate_limits = false
	for i in 500:
		assert_eq(r.route(2, 1, 50).size(), 1)


func test_idle_timeout_drops_silent_connections() -> void:
	r.enforce_idle_timeout = true
	var code: String = _create(1)["code"]
	_join(2, code)
	_out()
	r.advance(30.0)
	_send(1, {"t": "ping", "ts": 1})
	assert_true(U.same((_out()[1] as Array)[0], {"t": "pong", "ts": 1.0}))
	r.advance(31.0)
	assert_eq(r.take_closes(), [2] as Array[int], "peer 2 was silent for 61 s")
	var o := _out()
	assert_true(U.same((o[1] as Array)[0], {"t": "peer_left", "peer": 2, "reason": "dropped"}))


func test_requested_code_when_free() -> void:
	_hello(1)
	_send(1, {"t": "create", "max": 8, "code": "k7q-x2m"})
	assert_eq(((_out()[1] as Array)[0] as Dictionary)["code"], "K7QX2M")
	_hello(2)
	_send(2, {"t": "create", "max": 8, "code": "K7QX2M"})
	var other: String = ((_out()[2] as Array)[0] as Dictionary)["code"]
	assert_ne(other, "K7QX2M", "a taken code gets a new one")


func test_secure_random_codes_and_tokens() -> void:
	r.secure_random = true
	var c := _create(1)
	assert_true(RoomCode.is_valid(str(c["code"])))
	assert_eq(str(c["token"]).length(), 32)
