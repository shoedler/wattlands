extends GutTest
## LanTransport and LanDiscovery (BRIEF 5.4 P1): the host serves the relay protocol on a
## local WebSocket server and announces its room by UDP; a client joins by code through the
## beacon. Every socket here binds 127.0.0.1 (no LAN traffic, no firewall prompt).

const U := preload("res://tests/net/net_test_util.gd")
const WAIT_MS := 4000

var pollers: Array = []
var disc_port: int = 0


## A UDP port the OS says is free. A PID-derived one can land in a Windows excluded port range.
func _free_udp_port() -> int:
	var probe := PacketPeerUDP.new()
	probe.bind(0, "127.0.0.1")
	var free_port := probe.get_local_port()
	probe.close()
	return free_port


func before_each() -> void:
	pollers = []
	disc_port = _free_udp_port()


func _lan(label: String) -> LanTransport:
	var t := LanTransport.new()
	t.name = label
	t.port = 0
	t.bind_address = "127.0.0.1"
	t.discovery_port = disc_port
	t.discovery_address = "127.0.0.1"
	t.discovery_bind = "127.0.0.1"
	t.host_name = label
	add_child_autofree(t)
	pollers.append(t)
	return t


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


func test_host_announces_and_client_joins_by_code() -> void:
	var h := _lan("Hana")
	h.host(4)
	assert_true(_until(func() -> bool: return h.is_open()), "host joined its own relay")
	assert_true(h.is_host())
	assert_true(h.server.is_listening())
	var c := _lan("Bo")
	var log: Array = []
	c.message.connect(func(from: int, d: Dictionary) -> void: log.append([from, d]))
	c.join(RoomCode.format(h.room_code))
	assert_true(c.searching())
	assert_true(_until(func() -> bool: return c.is_open()), "found by beacon and joined")
	assert_eq(c.local_peer, 2)
	assert_true(c.url.begins_with("ws://127.0.0.1:%d" % h.server.port), c.url)
	var room: Dictionary = c.discovery.rooms.get(h.room_code, {})
	assert_eq(room.get("name"), "Hana")
	h.send(
		Wl.ALL_PEERS,
		Protocol.game_msg("phase", {"index": 1, "start_tick": 0, "ended_by": "duration"})
	)
	assert_true(_until(func() -> bool: return log.size() == 1))
	assert_eq(log[0][0], 1)


func test_net_sessions_over_lan() -> void:
	var hs := WlNetSession.new()
	hs.persist_token = false
	hs.bus = WlEventBus.new()
	hs.add_child(hs.bus)
	add_child_autofree(hs)
	var ht := _lan("host")
	pollers.erase(ht)
	ht.get_parent().remove_child(ht)
	hs.use_transport(ht)
	hs.set_local_player_info({"name": "Hana", "ftp": 240, "games": {"workout": "1"}})
	hs.set_game("workout", "1", "e2e")
	pollers.append(hs)
	hs.host_room(4)
	assert_true(_until(func() -> bool: return hs.state == "hosting"))
	var cs := WlNetSession.new()
	cs.persist_token = false
	cs.bus = WlEventBus.new()
	cs.add_child(cs.bus)
	add_child_autofree(cs)
	var ct := _lan("client")
	pollers.erase(ct)
	ct.get_parent().remove_child(ct)
	cs.use_transport(ct)
	cs.set_local_player_info({"name": "Bo", "ftp": 200, "games": {"workout": "1"}})
	pollers.append(cs)
	cs.join_room(hs.room_code)
	assert_true(_until(func() -> bool: return cs.lobby_slots().size() == 2))
	assert_eq(cs.lobby_slots()[0].name, "Hana")
	assert_eq(cs.lobby["content_id"], "e2e")


func test_unknown_code_times_out_as_room_not_found() -> void:
	var clock := [0.0]
	var c := _lan("lost")
	c.time_func = func() -> float: return clock[0]
	var reasons: Array = []
	c.disconnected.connect(func(r: String) -> void: reasons.append(r))
	c.join("ZZZ-ZZZ")
	c.poll()
	assert_eq(reasons, [])
	clock[0] += LanTransport.DISCOVERY_TIMEOUT_S + 0.1
	c.poll()
	assert_eq(reasons, ["room_not_found"])
	assert_false(c.searching())


func test_direct_url_skips_discovery() -> void:
	var h := _lan("Hana")
	h.host(4)
	assert_true(_until(func() -> bool: return h.is_open()))
	var c := _lan("direct")
	c.url = "ws://127.0.0.1:%d/v1" % h.server.port
	c.join(h.room_code)
	assert_false(c.searching())
	assert_true(_until(func() -> bool: return c.is_open()))
	assert_eq(c.local_peer, 2)


func test_beacons() -> void:
	var text := LanDiscovery.beacon("k7q-x2m", 8790, "Hana")
	var b := LanDiscovery.parse_beacon(text)
	assert_eq(b["code"], "K7QX2M")
	assert_eq(b["port"], 8790)
	assert_eq(b["name"], "Hana")
	assert_true(LanDiscovery.parse_beacon("{nope").is_empty())
	assert_true(
		(
			LanDiscovery
			. parse_beacon(
				JSON.stringify({"wattlands": "lan", "proto": 99, "code": "K7QX2M", "port": 1})
			)
			. is_empty()
		)
	)
	assert_true(
		(
			LanDiscovery
			. parse_beacon(
				JSON.stringify({"wattlands": "lan", "proto": 1, "code": "UUUUUU", "port": 1})
			)
			. is_empty()
		)
	)
	assert_true(
		(
			LanDiscovery
			. parse_beacon(
				JSON.stringify({"wattlands": "lan", "proto": 1, "code": "K7QX2M", "port": 70000})
			)
			. is_empty()
		)
	)
	assert_true(LanDiscovery.parse_beacon(JSON.stringify({"other": "game"})).is_empty())


func test_discovery_hears_rooms_and_forgets_stale_ones() -> void:
	var d := LanDiscovery.new()
	d.port = disc_port
	d.bind_address = "127.0.0.1"
	assert_eq(d.start(), OK)
	var tx := PacketPeerUDP.new()
	tx.set_dest_address("127.0.0.1", disc_port)
	tx.put_packet("garbage".to_utf8_buffer())
	tx.put_packet(LanDiscovery.beacon("K7QX2M", 9000, "A").to_utf8_buffer())
	var heard: Array[String] = []
	var t0 := Time.get_ticks_msec()
	while heard.is_empty() and Time.get_ticks_msec() - t0 < WAIT_MS:
		heard = d.poll(10.0)
		OS.delay_msec(2)
	assert_eq(heard, ["K7QX2M"] as Array[String])
	assert_eq(d.find("k7q-x2m")["ip"], "127.0.0.1")
	assert_eq(d.find("K7QX2M")["port"], 9000)
	d.poll(10.0 + LanDiscovery.STALE_S + 1.0)
	assert_true(d.find("K7QX2M").is_empty(), "stale rooms are forgotten")
	d.stop()
	tx.close()
	assert_false(d.is_listening())
