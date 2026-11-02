extends GutTest
## The built-in relay (docs/PROTOCOL.md section 8): with no relay chosen WlNetSession hosts on its
## own PC through LanTransport and joins by code from the network's beacons, so a rider with only
## the release can play. Real sockets over loopback: the network lock keeps the relay and its
## beacons on 127.0.0.1, so a run sends no LAN traffic and raises no firewall prompt.

const WAIT_MS := 4000

var _clock: float = 0.0
var _sessions: Array[WlNetSession] = []


func before_each() -> void:
	_clock = 100.0
	_sessions = []
	CmdLine.set_args(
		PackedStringArray(["--lan-port=0", "--lan-discovery-port=%d" % _free_udp_port()]), true
	)


func after_each() -> void:
	CmdLine.set_args(PackedStringArray(), false)


func _free_udp_port() -> int:
	var probe := PacketPeerUDP.new()
	probe.bind(0, "127.0.0.1")
	var free_port := probe.get_local_port()
	probe.close()
	return free_port


func _session(label: String) -> WlNetSession:
	var s := WlNetSession.new()
	s.name = label
	s.persist_token = false
	s.bus = WlEventBus.new()
	s.add_child(s.bus)
	s.lan_time_func = func() -> float: return _clock
	add_child_autofree(s)
	s.set_local_player_info({"name": label, "ftp": 220, "games": {"workout": "1"}})
	_sessions.append(s)
	return s


func _until(cond: Callable) -> bool:
	var end_at := Time.get_ticks_msec() + WAIT_MS
	while Time.get_ticks_msec() < end_at:
		# Beacons go out once per second of this clock.
		_clock += 0.1
		for s in _sessions:
			s.poll()
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _hosting(label: String = "Hana") -> WlNetSession:
	var hs := _session(label)
	hs.host_room(4)
	assert_true(
		await _until(func() -> bool: return hs.state == WlNetSession.STATE_HOSTING), "hosting"
	)
	return hs


func test_no_relay_chosen_hosts_on_this_pc() -> void:
	var hs := await _hosting()
	assert_true(hs.transport is LanTransport)
	assert_true(hs.uses_builtin_relay())
	assert_true(RoomCode.is_valid(hs.room_code))
	assert_gt((hs.transport as LanTransport).serving_port(), 0)
	assert_eq(hs.relay_address(), "", "no relay address to name")


func test_a_client_finds_the_room_by_its_code_and_joins() -> void:
	var hs := await _hosting()
	var cs := _session("Bo")
	cs.join_room(hs.room_code)
	assert_eq(cs.state, WlNetSession.STATE_CONNECTING)
	assert_true(await _until(func() -> bool: return cs.state == WlNetSession.STATE_JOINED))
	assert_eq(cs.room_code, hs.room_code)
	assert_true(await _until(func() -> bool: return hs.peers().size() == 2))


func test_a_wrong_code_ends_as_room_not_found() -> void:
	await _hosting()
	var cs := _session("Bo")
	var reasons: Array[String] = []
	cs.refused.connect(func(r: String) -> void: reasons.append(r))
	cs.join_room("ZZZZZZ")
	_clock += LanTransport.DISCOVERY_TIMEOUT_S + 0.5
	assert_true(await _until(func() -> bool: return not reasons.is_empty()))
	assert_eq(reasons, ["room_not_found"] as Array[String])
	assert_eq(cs.state, WlNetSession.STATE_ERROR)


func test_the_host_leaving_reaches_clients_and_closes_the_relay() -> void:
	var hs := await _hosting()
	var cs := _session("Bo")
	var reasons: Array[String] = []
	cs.refused.connect(func(r: String) -> void: reasons.append(r))
	cs.join_room(hs.room_code)
	assert_true(await _until(func() -> bool: return cs.state == WlNetSession.STATE_JOINED))
	var lt := hs.transport as LanTransport
	hs.leave()
	assert_true(await _until(func() -> bool: return not reasons.is_empty()), "client told")
	assert_eq(reasons, ["host_left"] as Array[String])
	assert_true(lt.server.is_listening(), "the relay outlives the leave by its linger")
	_clock += LanTransport.SERVER_LINGER_S + 0.1
	assert_true(await _until(func() -> bool: return not lt.server.is_listening()), "then it closes")


func test_a_busy_port_falls_back_to_a_free_one() -> void:
	var holder := TCPServer.new()
	assert_eq(holder.listen(0, "127.0.0.1"), OK)
	var busy := holder.get_local_port()
	CmdLine.set_args(
		PackedStringArray(["--lan-port=%d" % busy, "--lan-discovery-port=%d" % _free_udp_port()]),
		true
	)
	var hs := await _hosting()
	var p := (hs.transport as LanTransport).serving_port()
	assert_gt(p, 0)
	assert_ne(p, busy)
	var cs := _session("Bo")
	cs.join_room(hs.room_code)
	assert_true(await _until(func() -> bool: return cs.state == WlNetSession.STATE_JOINED))
	holder.stop()


func test_the_host_gets_its_own_room_back_after_a_socket_drop() -> void:
	var hs := await _hosting()
	var code := hs.room_code
	var lt := hs.transport as LanTransport
	lt.server.drop_connection(1)
	assert_true(await _until(func() -> bool: return hs.state == WlNetSession.STATE_RECONNECTING))
	_clock += 1.0
	assert_true(await _until(func() -> bool: return hs.state == WlNetSession.STATE_HOSTING))
	assert_eq(hs.room_code, code)
	assert_eq(hs.local_peer, Wl.HOST_PEER)


func test_after_hosting_the_same_session_can_join_another_room() -> void:
	var other := await _hosting("Other")
	var hs := await _hosting("Hana")
	hs.leave()
	hs.join_room(other.room_code)
	assert_true(await _until(func() -> bool: return hs.state == WlNetSession.STATE_JOINED))
	assert_eq(hs.host_peer, other.local_peer)
	assert_true(await _until(func() -> bool: return other.peers().size() == 2))


func test_a_chosen_relay_is_read_at_each_room() -> void:
	var s := _session("Hana")
	s.relay_url = "ws://127.0.0.1:9/v1"
	assert_false(s.uses_builtin_relay())
	s.host_room(4)
	assert_true(s.transport is RelayTransport)
	assert_false(s.transport is LanTransport)
	assert_eq(s.relay_address(), "ws://127.0.0.1:9/v1")
	s.leave()
	s.relay_url = "ws://127.0.0.1:10/v1"
	s.host_room(4)
	assert_eq(s.relay_address(), "ws://127.0.0.1:10/v1", "a new choice applies to the next room")
	s.leave()
	s.relay_url = ""
	s.host_room(4)
	assert_true(s.transport is LanTransport, "no choice: the built-in relay")
	assert_true(await _until(func() -> bool: return s.state == WlNetSession.STATE_HOSTING))


func test_a_transport_from_outside_is_kept() -> void:
	var s := _session("Hana")
	var hub := LoopbackHub.new(3)
	var t := LoopbackTransport.hub_transport(hub)
	s.use_transport(t)
	s.host_room(4)
	assert_eq(s.transport, t)
	assert_false(s.uses_builtin_relay())


func test_only_this_machine_creates_rooms_on_the_relay() -> void:
	var rooms := RelayRooms.new()
	rooms.open(1)
	rooms.forbid_create(1)
	var hello := {"t": "hello", "proto": Wl.PROTO, "game": Wl.RELAY_GAME, "build": Wl.BUILD}
	rooms.receive(1, Protocol.encode(hello))
	rooms.receive(1, Protocol.encode({"t": "create", "max": 4}))
	var out := rooms.take_output()
	assert_eq(out.size(), 1, "one answer")
	assert_eq(str((out[0][1] as Dictionary)["t"]), "error")
	assert_eq(str((out[0][1] as Dictionary)["code"]), "bad_request")
	assert_true(LocalRelayServer.is_loopback("127.0.0.1"))
	assert_true(LocalRelayServer.is_loopback("::1"))
	assert_false(LocalRelayServer.is_loopback("192.168.1.20"))


func test_one_address_cannot_fill_the_relay() -> void:
	var server := LocalRelayServer.new()
	add_child_autofree(server)
	assert_eq(server.start(0, "127.0.0.1"), OK)
	var sockets: Array[WebSocketPeer] = []
	for i in LocalRelayServer.MAX_PER_ADDRESS + 3:
		var ws := WebSocketPeer.new()
		ws.connect_to_url(server.local_url())
		sockets.append(ws)
	var end_at := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < end_at:
		server.poll()
		for ws in sockets:
			ws.poll()
		await get_tree().process_frame
	assert_eq(server.connection_count(), LocalRelayServer.MAX_PER_ADDRESS)
	assert_eq(server.accepted, LocalRelayServer.MAX_PER_ADDRESS)
	for ws in sockets:
		ws.close()
	server.stop()


func test_shareable_addresses_are_private_then_tailscale() -> void:
	var got := LanDiscovery.shareable_addresses(
		PackedStringArray(
			[
				"127.0.0.1",
				"100.101.102.103",
				"192.168.1.20",
				"169.254.3.4",
				"8.8.8.8",
				"fe80::1",
				"10.0.0.5",
				"172.31.0.1",
				"172.32.0.1",
				"100.63.0.1"
			]
		)
	)
	assert_eq(got, PackedStringArray(["192.168.1.20", "10.0.0.5", "172.31.0.1", "100.101.102.103"]))
