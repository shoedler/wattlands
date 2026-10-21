extends GutTest
## RelayTransport (WebSocketPeer, BRIEF 5.3/5.4) against an in-process GDScript WebSocket
## server that speaks the relay protocol (LocalRelayServer: TCPServer + WebSocketPeer +
## RelayRooms). The Node relay itself is tested by the relay builder and the e2e harness.
## hello, create/join, routing, error codes -> disconnected(reason) and NetSession refusals
## (EventBus.session_refused), peer_joined/peer_left/host_left, a dropped socket
## reconnecting with the saved token, the 15 s ping, the connect timeout and URLs.

const U := preload("res://tests/net/net_test_util.gd")
const WAIT_MS := 4000

var server: LocalRelayServer
var pollers: Array = []
var tmp: String = ""


func before_each() -> void:
	server = LocalRelayServer.new()
	add_child_autofree(server)
	assert_eq(server.start(0, "127.0.0.1"), OK)
	pollers = [server]
	tmp = Paths.make_temp_dir("wl_relay")
	Paths.set_override(tmp)


func after_each() -> void:
	server.stop()
	Paths.set_override("")
	for f in DirAccess.get_files_at(tmp):
		DirAccess.remove_absolute(tmp.path_join(f))
	DirAccess.remove_absolute(tmp)
	CmdLine.set_args(PackedStringArray(), false)


func _transport() -> RelayTransport:
	var t := RelayTransport.new()
	t.url = server.local_url()
	add_child_autofree(t)
	pollers.append(t)
	return t


func _session(label: String) -> WlNetSession:
	var s := WlNetSession.new()
	s.name = label
	var b := WlEventBus.new()
	s.add_child(b)
	s.bus = b
	s.token_path = tmp.path_join(label + "_token.json")
	s.recent_rooms_file = tmp.path_join(label + "_recent.json")
	add_child_autofree(s)
	var t := RelayTransport.new()
	t.url = server.local_url()
	s.use_transport(t)
	s.set_local_player_info({"name": label, "ftp": 200, "games": {"workout": "1"}})
	pollers.append(s)
	return s


## Poll everything until cond() is true or WAIT_MS passes.
func _until(cond: Callable) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < WAIT_MS:
		for p: Variant in pollers:
			if is_instance_valid(p):
				p.call("poll")
		if cond.call():
			return true
		OS.delay_msec(2)
	return false


## Poll everything for `ms` milliseconds.
func _pump_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		for p: Variant in pollers:
			if is_instance_valid(p):
				p.call("poll")
		OS.delay_msec(2)


func _log(t: Transport) -> Array:
	var log: Array = []
	t.connected.connect(func() -> void: log.append(["connected"]))
	t.disconnected.connect(func(reason: String) -> void: log.append(["disconnected", reason]))
	t.peer_joined.connect(func(id: int) -> void: log.append(["peer_joined", id]))
	t.peer_left.connect(
		func(id: int) -> void: log.append(["peer_left", id, t.last_peer_left_reason])
	)
	t.message.connect(
		func(from: int, data: Dictionary) -> void: log.append(["message", from, data])
	)
	return log


func _has(log: Array, entry: Array) -> bool:
	for e: Variant in log:
		if U.same(e, entry):
			return true
	return false


func test_create_join_and_route_over_websocket() -> void:
	var h := _transport()
	var hl := _log(h)
	h.host(4)
	assert_true(_until(func() -> bool: return h.is_open()), "host connected")
	assert_true(RoomCode.is_valid(h.room_code))
	assert_eq(h.local_peer, 1)
	assert_true(h.is_host())
	assert_ne(h.reconnect_token, "")
	var c := _transport()
	var cl := _log(c)
	c.join(RoomCode.format(h.room_code).to_lower())
	assert_true(_until(func() -> bool: return c.is_open() and _has(hl, ["peer_joined", 2])))
	assert_eq(c.local_peer, 2)
	assert_eq(c.host_peer, 1)
	c.send(1, Protocol.game_msg("phase", {"index": 3, "start_tick": 60, "ended_by": "duration"}))
	assert_true(
		_until(func() -> bool: return hl.any(func(e: Array) -> bool: return e[0] == "message"))
	)
	var got: Array = hl.filter(func(e: Array) -> bool: return e[0] == "message")[0]
	assert_eq(got[1], 2)
	assert_typeof((got[2] as Dictionary)["index"], TYPE_INT)
	h.send(Wl.ALL_PEERS, Protocol.game_msg("roster", {"riders": {2: {"raw_w": 180.5}}}))
	assert_true(
		_until(func() -> bool: return cl.any(func(e: Array) -> bool: return e[0] == "message"))
	)
	var rm: Array = cl.filter(func(e: Array) -> bool: return e[0] == "message")[0]
	assert_true(((rm[2] as Dictionary)["riders"] as Dictionary).has(2))
	c.send(3, Protocol.game_msg("ready", {"ready": true}))
	assert_push_warning("non-hosts may only send to the host")


func test_net_sessions_over_websocket() -> void:
	var h := _session("host")
	h.set_game("workout", "1", "e2e")
	h.host_room(4)
	assert_true(_until(func() -> bool: return h.state == "hosting"))
	var c := _session("c1")
	c.join_room(h.room_code)
	assert_true(_until(func() -> bool: return c.lobby_slots().size() == 2))
	assert_eq(c.state, "joined")
	assert_eq(c.lobby_slots()[1].name, "c1")
	assert_eq(c.lobby["content_id"], "e2e")
	c.set_ready(true)
	h.set_ready(true)
	assert_true(_until(func() -> bool: return h.all_ready() and c.all_ready()))


func test_relay_errors_become_refusals() -> void:
	var t := _transport()
	var log := _log(t)
	t.join("ZZZZZZ")
	assert_true(_until(func() -> bool: return _has(log, ["disconnected", "room_not_found"])))
	assert_false(t.is_open())
	var s := _session("lost")
	var refusals: Array = []
	s.bus.session_refused.connect(func(reason: String) -> void: refusals.append(reason))
	s.join_room("ZZZ-ZZZ")
	assert_true(_until(func() -> bool: return s.state == "error"))
	assert_eq(refusals, ["room_not_found"])
	assert_eq(s.refusal_reason, "room_not_found")


func test_dropped_socket_reconnects_with_the_same_peer_id() -> void:
	var h := _session("host")
	h.host_room(4)
	assert_true(_until(func() -> bool: return h.state == "hosting"))
	var c := _session("c1")
	c.join_room(h.room_code)
	assert_true(_until(func() -> bool: return h.lobby_slots().size() == 2))
	var left: Array = []
	var joined: Array = []
	h.peer_left.connect(func(id: int, reason: String) -> void: left.append([id, reason]))
	h.peer_joined.connect(func(id: int) -> void: joined.append(id))
	var states: Array = []
	c.state_changed.connect(func(st: String, _d: String) -> void: states.append(st))
	var conn := int(server.rooms.room_peers(h.room_code)[2])
	server.drop_connection(conn)
	assert_true(_until(func() -> bool: return joined.has(2) and c.state == "joined"))
	assert_true(U.same(left, [[2, "dropped"]]), str(left))
	assert_eq(c.local_peer, 2, "the token kept the peer id")
	assert_eq(states.front(), "reconnecting")
	assert_eq(h.lobby_slots().size(), 2)


func test_host_left_reaches_clients() -> void:
	var h := _transport()
	h.host(4)
	assert_true(_until(func() -> bool: return h.is_open()))
	var c := _transport()
	var cl := _log(c)
	c.join(h.room_code)
	assert_true(_until(func() -> bool: return c.is_open()))
	h.leave()
	assert_true(_until(func() -> bool: return _has(cl, ["disconnected", "host_left"])))
	assert_false(c.is_open())


func test_ping_every_15_seconds_with_an_injected_clock() -> void:
	var clock := [1000.0]
	var c := _transport()
	c.time_func = func() -> float: return clock[0]
	c.host(2)
	assert_true(_until(func() -> bool: return c.is_open()))
	assert_eq(c.last_rtt_s, -1.0)
	clock[0] += 14.0
	_pump_ms(100)
	assert_eq(c.last_rtt_s, -1.0, "no ping before 15 s")
	clock[0] += 1.5
	assert_true(_until(func() -> bool: return c.last_rtt_s >= 0.0), "ping at 15 s, pong back")
	assert_true(c.is_open())


func test_silence_counts_as_a_drop() -> void:
	var clock := [0.0]
	var c := _transport()
	var log := _log(c)
	c.time_func = func() -> float: return clock[0]
	c.host(2)
	assert_true(_until(func() -> bool: return c.is_open()))
	pollers.erase(server)
	clock[0] += RelayTransport.SILENCE_TIMEOUT_S + 1.0
	assert_true(_until(func() -> bool: return _has(log, ["disconnected", "dropped"])))
	assert_push_warning("no frame from the relay")


func test_connect_timeout() -> void:
	var clock := [0.0]
	var t := RelayTransport.new()
	t.url = "ws://127.0.0.1:1/v1"
	t.time_func = func() -> float: return clock[0]
	add_child_autofree(t)
	pollers.append(t)
	var log := _log(t)
	t.host(2)
	t.poll()
	clock[0] += RelayTransport.CONNECT_TIMEOUT_S + 0.5
	assert_true(_until(func() -> bool: return log.size() > 0))
	assert_true(
		_has(log, ["disconnected", "timeout"]) or _has(log, ["disconnected", "error"]), str(log)
	)


func test_urls() -> void:
	assert_true(RelayTransport.is_valid_url("ws://localhost:8787/v1"))
	assert_true(RelayTransport.is_valid_url("wss://relay.example.test/v1"))
	assert_false(RelayTransport.is_valid_url("http://localhost:8787/v1"))
	assert_eq(RelayTransport.default_url(), RelayTransport.DEFAULT_URL)
	assert_eq(RelayTransport.default_url(self), "ws://localhost:8787/v1", "Settings.relay_url()")
	CmdLine.set_args(PackedStringArray(["--relay=ws://127.0.0.1:9999/v1"]))
	assert_eq(RelayTransport.default_url(self), "ws://127.0.0.1:9999/v1", "--relay wins")
	var bad := RelayTransport.new()
	bad.url = "http://nope"
	add_child_autofree(bad)
	var log := _log(bad)
	bad.host(2)
	assert_push_warning("is not a ws:// or wss:// URL")
	assert_true(_has(log, ["disconnected", "error"]))


func test_server_counts_and_stops() -> void:
	var t := _transport()
	t.host(2)
	assert_true(_until(func() -> bool: return t.is_open()))
	assert_eq(server.connection_count(), 1)
	assert_true(server.is_listening())
	assert_true(server.local_url().begins_with("ws://127.0.0.1:"))
	server.stop()
	assert_false(server.is_listening())
	assert_eq(server.connection_count(), 0)


## A client from another protocol version (its hello carries proto + 1).
class FutureTransport:
	extends RelayTransport

	func _on_socket_open() -> void:
		_socket_state = SocketState.OPEN
		_send_envelope(
			{"t": "hello", "proto": Wl.PROTO + 1, "game": Wl.RELAY_GAME, "build": "9.9.9"}
		)
		_send_pending()


func test_version_mismatch_from_the_relay() -> void:
	var t := FutureTransport.new()
	t.url = server.local_url()
	add_child_autofree(t)
	pollers.append(t)
	var log := _log(t)
	var s := WlNetSession.new()
	var b := WlEventBus.new()
	s.add_child(b)
	s.bus = b
	s.persist_token = false
	add_child_autofree(s)
	s.use_transport(t)
	pollers.append(s)
	var refusals: Array = []
	b.session_refused.connect(func(reason: String) -> void: refusals.append(reason))
	s.host_room(2)
	assert_true(_until(func() -> bool: return refusals.size() > 0))
	assert_true(_has(log, ["disconnected", "version_mismatch"]), str(log))
	assert_eq(refusals, ["version_mismatch"])
	assert_eq(s.state, "error")
