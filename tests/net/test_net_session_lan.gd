extends GutTest
## WlNetSession's LAN room list for the join page (BRIEF 5.4 P1, lead W2 round 2):
## lan_rooms() -> [{code, name, game_id, address, port, build}], lan_rooms_changed(rooms),
## join_lan(room) and stop_lan_discovery(), over a real LanTransport host. Every socket binds
## 127.0.0.1 (no LAN traffic, no firewall prompt).

const WAIT_MS := 4000

var pollers: Array = []
var disc_port: int = 0
var hub: LoopbackHub = null


func before_each() -> void:
	pollers = []
	# A per-process discovery port, away from the default and from test_lan_transport's.
	disc_port = 40000 + (OS.get_process_id() + 7919) % 20000
	hub = LoopbackHub.new(3)


func _session(label: String, info_name: String) -> WlNetSession:
	var s := WlNetSession.new()
	s.name = label
	s.persist_token = false
	s.bus = WlEventBus.new()
	s.add_child(s.bus)
	s.lan_discovery_port = disc_port
	s.lan_discovery_bind = "127.0.0.1"
	add_child_autofree(s)
	s.set_local_player_info({"name": info_name, "ftp": 220, "games": {"workout": "1"}})
	pollers.append(s)
	return s


## A session hosting a LAN room (its own LanTransport relay on 127.0.0.1, beacons to the test's
## discovery port).
func _lan_host(game_id: String = "workout") -> WlNetSession:
	var hs := _session("LanHost", "Hana")
	var t := LanTransport.new()
	t.port = 0
	t.bind_address = "127.0.0.1"
	t.discovery_port = disc_port
	t.discovery_address = "127.0.0.1"
	hs.use_transport(t)
	if game_id != "":
		hs.set_game(game_id, "1", "e2e")
	hs.host_room(4)
	assert_true(
		_until(func() -> bool: return hs.state == WlNetSession.STATE_HOSTING), "the LAN host is up"
	)
	return hs


## A client whose normal transport is a LoopbackTransport (standing in for the relay).
func _client() -> WlNetSession:
	var cs := _session("Client", "Bo")
	cs.use_transport(LoopbackTransport.hub_transport(hub))
	return cs


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


## Poll every session for `ms` milliseconds.
func _poll_for(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		for p: Variant in pollers:
			if is_instance_valid(p):
				p.call("poll")
		OS.delay_msec(2)


func test_beacons_carry_the_game_id() -> void:
	var b := LanDiscovery.parse_beacon(LanDiscovery.beacon("k7q-x2m", 8790, "Hana", "workout"))
	assert_eq(b["game_id"], "workout")
	assert_eq(
		LanDiscovery.parse_beacon(LanDiscovery.beacon("K7QX2M", 8790, "Hana"))["game_id"],
		"",
		"older beacons parse"
	)
	assert_false(
		LanDiscovery.beacon("K7QX2M", 8790).contains('"game"'), "no game key without a game"
	)
	var odd := LanDiscovery.parse_beacon(
		JSON.stringify(
			{"wattlands": "lan", "proto": Wl.PROTO, "code": "K7QX2M", "port": 1, "game": 5}
		)
	)
	assert_eq(odd["game_id"], "", "a non-string game is ignored")


func test_the_join_page_hears_a_lan_room_and_joins_it() -> void:
	var host := _lan_host()
	var cs := _client()
	var relay := cs.transport
	var changes: Array = []
	cs.lan_rooms_changed.connect(func(rooms: Array) -> void: changes.append(rooms))
	assert_eq(cs.lan_rooms(), [] as Array[Dictionary], "nothing heard yet")
	assert_true(cs.is_lan_discovering(), "the first call starts listening")
	assert_true(_until(func() -> bool: return not changes.is_empty()), "the host's beacon is heard")
	var rooms := cs.lan_rooms()
	assert_eq(rooms.size(), 1)
	var room: Dictionary = rooms[0]
	var server_port := (host.transport as LanTransport).server.port
	assert_eq(
		room,
		{
			"code": host.room_code,
			"name": "Hana",
			"game_id": "workout",
			"address": "127.0.0.1",
			"port": server_port,
			"build": Wl.BUILD
		}
	)
	assert_eq(changes[0], rooms, "the signal carries the list")
	var n := changes.size()
	_poll_for(2500)
	assert_eq(changes.size(), n, "repeated beacons of the same room change nothing")
	cs.join_lan(room)
	assert_false(cs.is_lan_discovering(), "joining stops discovery")
	assert_true(cs.transport is LanTransport)
	assert_true(_until(func() -> bool: return cs.lobby_slots().size() == 2), "joined the LAN room")
	assert_eq(cs.state, WlNetSession.STATE_JOINED)
	assert_eq(cs.room_code, host.room_code)
	assert_eq(cs.lobby_slots()[0].name, "Hana")
	assert_eq(host.peers(), [1, 2] as Array[int])
	# Back to the relay for the next room.
	cs.host_room(4)
	assert_eq(cs.transport, relay, "host_room() restores the transport join_lan() replaced")
	assert_true(
		_until(func() -> bool: return cs.state == WlNetSession.STATE_HOSTING), "and hosts on it"
	)


func test_rooms_go_stale_and_stop_clears_the_list() -> void:
	var host := _lan_host("")
	var cs := _client()
	var changes: Array = []
	cs.lan_rooms_changed.connect(func(rooms: Array) -> void: changes.append(rooms))
	cs.lan_rooms()
	assert_true(_until(func() -> bool: return not changes.is_empty()))
	assert_eq((changes[0] as Array)[0]["game_id"], "", "a host without a game announces none")
	host.leave()
	pollers.erase(host)
	_poll_for(300)
	var clock := [float(Time.get_ticks_msec()) / 1000.0 + LanDiscovery.STALE_S + 1.0]
	cs.lan_time_func = func() -> float: return clock[0]
	cs.poll()
	assert_eq(changes[changes.size() - 1], [], "a silent room is forgotten")
	assert_eq(cs.lan_rooms(), [] as Array[Dictionary])
	var h2 := _lan_host()
	assert_true(_until(func() -> bool: return cs.lan_rooms().size() == 1))
	cs.stop_lan_discovery()
	assert_false(cs.is_lan_discovering())
	assert_eq(changes[changes.size() - 1], [], "stopping clears the list")
	h2.leave()


func test_join_lan_refuses_a_room_it_cannot_reach() -> void:
	var cs := _client()
	var reasons: Array = []
	cs.refused.connect(func(r: String) -> void: reasons.append(r))
	cs.join_lan({"code": "K7Q-X2M", "name": "?"})
	assert_push_warning("join_lan needs a room")
	assert_eq(reasons, ["room_not_found"])
	assert_eq(cs.state, WlNetSession.STATE_ERROR)
	assert_false(cs.transport is LanTransport, "no LAN transport for a room without an address")
	cs.join_lan({"code": "", "address": "127.0.0.1", "port": 8790})
	assert_eq(reasons, ["room_not_found", "room_not_found"])
