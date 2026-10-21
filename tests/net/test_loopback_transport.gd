extends GutTest
## LoopbackTransport + LoopbackHub (BRIEF 5.4 P0): relay semantics in-process (codes, peer
## ids from 1, to: 0 broadcast excluding the sender, non-hosts only to the host,
## peer_left/host_left, reconnect tokens, simulate_drop), messages through JSON, delivered
## in order in poll().

const U := preload("res://tests/net/net_test_util.gd")

var hub: LoopbackHub
var all: Array[LoopbackTransport] = []
var events: Dictionary = {}


func before_each() -> void:
	hub = LoopbackTransport.create_hub() as LoopbackHub
	all.clear()
	events.clear()


func _t(label: String) -> LoopbackTransport:
	var t := LoopbackTransport.hub_transport(hub)
	add_child_autofree(t)
	all.append(t)
	events[label] = []
	var log: Array = events[label]
	t.connected.connect(func() -> void: log.append(["connected"]))
	t.disconnected.connect(func(reason: String) -> void: log.append(["disconnected", reason]))
	t.peer_joined.connect(func(id: int) -> void: log.append(["peer_joined", id]))
	t.peer_left.connect(func(id: int) -> void: log.append(["peer_left", id, t.last_peer_left_reason]))
	t.message.connect(func(from: int, data: Dictionary) -> void: log.append(["message", from, data]))
	t.relay_error.connect(func(code: String) -> void: log.append(["relay_error", code]))
	t.protocol_mismatch.connect(func(from: int) -> void: log.append(["protocol_mismatch", from]))
	return t


func _pump(n: int = 3) -> void:
	for _i in n:
		for t in all:
			if is_instance_valid(t):
				t.poll()


func _names(label: String) -> Array:
	var out: Array = []
	for e: Array in events[label]:
		out.append(e[0])
	return out


func _messages(label: String) -> Array:
	var out: Array = []
	for e: Array in events[label]:
		if e[0] == "message":
			out.append(e)
	return out


func _room() -> Array[LoopbackTransport]:
	var h := _t("h")
	h.host(8)
	_pump()
	var a := _t("a")
	a.join(h.room_code)
	var b := _t("b")
	b.join(h.room_code)
	_pump()
	return [h, a, b]


func test_hub_factory() -> void:
	assert_true(LoopbackTransport.create_hub() is LoopbackHub)
	var t := LoopbackTransport.hub_transport(RefCounted.new())
	assert_push_error("not a LoopbackHub")
	t.free()


func test_host_creates_a_room_in_poll() -> void:
	var h := _t("h")
	h.host(4)
	assert_eq(_names("h"), [], "nothing is delivered before poll()")
	_pump(1)
	assert_eq(_names("h"), ["connected"])
	assert_true(RoomCode.is_valid(h.room_code))
	assert_eq(h.local_peer, 1)
	assert_eq(h.host_peer, 1)
	assert_true(h.is_host())
	assert_true(h.is_open())
	assert_ne(h.reconnect_token, "")


func test_join_assigns_ids_and_announces() -> void:
	var r := _room()
	assert_eq(r[1].local_peer, 2)
	assert_eq(r[2].local_peer, 3)
	assert_eq(r[1].host_peer, 1)
	assert_false(r[1].is_host())
	assert_eq(r[1].room_code, r[0].room_code)
	assert_true(U.same(events["h"], [["connected"], ["peer_joined", 2], ["peer_joined", 3]]), str(events["h"]))
	assert_true(U.same(events["a"], [["connected"], ["peer_joined", 3]]), str(events["a"]))


func test_broadcast_excludes_the_sender_and_converts_ints() -> void:
	var r := _room()
	r[0].send(Wl.ALL_PEERS, Protocol.game_msg("phase", {"index": 2, "start_tick": 40, "ended_by": "duration", "x": 3}))
	_pump()
	assert_eq(_messages("h").size(), 0)
	for label in ["a", "b"]:
		var m: Array = _messages(label)
		assert_eq(m.size(), 1)
		assert_eq(m[0][1], 1)
		var d: Dictionary = m[0][2]
		assert_typeof(d["index"], TYPE_INT, "decoded on arrival")
		assert_typeof(d["x"], TYPE_FLOAT, "undeclared numbers come back as floats, like the network")


func test_non_hosts_send_only_to_the_host() -> void:
	var r := _room()
	r[1].send(3, Protocol.game_msg("ready", {"ready": true}))
	assert_push_warning("non-hosts may only send to the host")
	r[1].send(Wl.ALL_PEERS, Protocol.game_msg("ready", {"ready": true}))
	assert_push_warning("non-hosts may only send to the host")
	r[1].send(1, Protocol.game_msg("ready", {"ready": true}))
	_pump()
	assert_eq(_messages("b").size(), 0)
	assert_eq(_messages("h").size(), 1)
	assert_eq(_messages("h")[0][1], 2)


func test_delivery_in_order() -> void:
	var r := _room()
	for i in 20:
		r[0].send(2, Protocol.game_msg("event", {"seq": i, "events": []}))
	_pump(1)
	var seqs: Array = []
	for m: Array in _messages("a"):
		seqs.append((m[2] as Dictionary)["seq"])
	assert_eq(seqs, range(20))


func test_latency_ticks_delay_delivery_keeping_order() -> void:
	var r := _room()
	r[1].latency_ticks = 2
	r[0].send(2, Protocol.game_msg("event", {"seq": 1, "events": []}))
	r[0].send(2, Protocol.game_msg("event", {"seq": 2, "events": []}))
	r[1].poll()
	r[1].poll()
	assert_eq(_messages("a").size(), 0)
	r[1].poll()
	assert_eq(_messages("a").size(), 2)


func test_drop_and_reconnect_with_token_keeps_peer_id() -> void:
	var r := _room()
	var a := r[1]
	var token := a.reconnect_token
	var code := a.room_code
	a.simulate_drop()
	assert_false(a.is_open())
	_pump()
	assert_true(U.same(events["h"].back(), ["peer_left", 2, "dropped"]), str(events["h"].back()))
	assert_true(U.same(events["a"].back(), ["disconnected", "dropped"]))
	assert_eq(a.room_code, code, "the room code survives a drop")
	assert_eq(a.reconnect_token, token, "so does the token")
	a.join(a.room_code, a.reconnect_token)
	_pump()
	assert_eq(a.local_peer, 2)
	assert_true(U.same(events["h"].back(), ["peer_joined", 2]))
	assert_eq(a.reconnect_token, token, "the peer keeps its token")


func test_drop_while_joining_fails_the_attempt_and_the_token_still_works() -> void:
	var r := _room()
	var a := r[1]
	var token := a.reconnect_token
	a.simulate_drop()
	_pump()
	a.join(a.room_code, token)
	assert_eq(a.pending_frames(), 1, "the joined answer is in flight")
	a.simulate_drop()
	assert_eq(a.pending_frames(), 1, "frames in flight are lost; one failure event")
	_pump()
	assert_true(U.same(events["a"].back(), ["disconnected", "error"]), str(events["a"]))
	assert_false(a.is_open())
	a.join(a.room_code, token)
	_pump()
	assert_eq(a.local_peer, 2, "the same token after a lost answer")


func test_hub_drop_peer_and_freed_transport_are_drops() -> void:
	var r := _room()
	assert_true(hub.drop_peer(r[0].room_code, 3))
	assert_false(hub.drop_peer(r[0].room_code, 9))
	_pump()
	assert_true(U.same(events["h"].back(), ["peer_left", 3, "dropped"]))
	assert_true(r[0].drop(2), "the stub's drop(peer)")
	assert_false(r[0].drop(9))
	_pump()
	assert_true(U.same(events["h"].back(), ["peer_left", 2, "dropped"]))
	assert_true(U.same(events["a"].back(), ["disconnected", "dropped"]))
	r[1].join(r[1].room_code, r[1].reconnect_token)
	_pump()
	assert_true(r[1].drop(r[1].local_peer), "its own peer: simulate_drop")
	_pump()
	assert_true(U.same(events["a"].back(), ["disconnected", "dropped"]))
	r[1].join(r[1].room_code, r[1].reconnect_token)
	_pump()
	all.erase(r[1])
	r[1].free()
	_pump()
	assert_true(U.same(events["h"].back(), ["peer_left", 2, "dropped"]))


func test_leave_and_host_leave() -> void:
	var r := _room()
	r[2].leave()
	assert_true(U.same(events["b"].back(), ["disconnected", "closed"]))
	_pump()
	assert_true(U.same(events["h"].back(), ["peer_left", 3, "left"]))
	r[0].leave()
	_pump()
	assert_true(U.same(events["a"].back(), ["disconnected", "host_left"]))
	assert_false(r[1].is_open())


func test_join_errors() -> void:
	var t := _t("x")
	t.join("ZZZZZZ")
	_pump()
	assert_true(U.same(events["x"], [["disconnected", "room_not_found"]]), str(events["x"]))
	var u := _t("y")
	u.join("not a code")
	assert_push_warning("is not a room code")
	assert_true(U.same(events["y"], [["disconnected", "room_not_found"]]))


func test_rate_limit_is_a_non_fatal_relay_error() -> void:
	hub.enforce_limits(true)
	var r := _room()
	for i in 130:
		r[1].send(1, Protocol.game_msg("event", {"seq": i, "events": []}))
	_pump()
	assert_gt(int(hub.error_counts.get("rate_limited", 0)), 0)
	assert_true(_names("a").has("relay_error"))
	assert_true(r[1].is_open(), "still in the room")
	assert_lt(_messages("h").size(), 130)


func test_other_schema_version_is_reported() -> void:
	var r := _room()
	r[1].send_encoded(1, JSON.stringify({"type": "ready", "v": 99, "ready": true}))
	_pump()
	assert_eq(_messages("h").size(), 0)
	assert_true(U.same(events["h"].back(), ["protocol_mismatch", 2]))
