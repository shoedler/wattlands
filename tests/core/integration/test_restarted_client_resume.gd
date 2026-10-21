extends GutTest
## W4r2 (W3 NET-2, second half): a client that RESTARTS (a new GameHost and a new LocalRider, as
## the app does after a crash or a quit and relaunch with the saved token) rejoins 120 s into a
## 300 s ERG ramp. BRIEF 3.6: the rider resumes its phase (plan, phase, latest snapshot), it does
## not restart it. A host and two client GameHosts over the real WlNetSession and
## LoopbackTransport, started the way the app shell starts them (from the W4r2 network proof
## build/w4r2/network/test_net2_restart.gd). Before W4r2 the restarted client's governor went
## from 119.9 s to 1.9 s into the ramp and its target fell from 95 W to 85 W.

const FIXTURES := "res://tests/fixtures/games"
const GAME := "fx_solo"
const DT := Wl.SIM_DT

var _root: Node = null
var _reg: WlGameRegistry = null
var _nets: Array[WlNetSession] = []
var _buses: Array[WlEventBus] = []
var _clients: Dictionary = {}
## Client index -> the LocalRider its GameHost was given (the test's own handle on it).
var _client_riders: Dictionary = {}
var _host: GameHost = null
var _tmp: String = ""
var _content: String = "tiny"


func before_each() -> void:
	_root = Node.new()
	add_child_autofree(_root)
	_nets.clear()
	_buses.clear()
	_clients.clear()
	_client_riders.clear()
	_host = null
	_tmp = Paths.make_temp_dir("wattlands_w4r2_resume")
	Paths.set_override(_tmp)
	_reg = WlGameRegistry.new()
	_reg.scan_on_ready = false
	_reg.content_root = FIXTURES.path_join("_content")
	_root.add_child(_reg)
	_reg.scan(FIXTURES.path_join("runtime"))


func after_each() -> void:
	Paths.set_override("")
	GameSimRunner._remove_tree(_tmp)
	await wait_process_frames(1)


func _pump(done: Callable, max_iter: int = 400) -> bool:
	for k in max_iter:
		for n in _nets:
			n.poll()
		if done.call():
			return true
	return false


func _lobby(content: String) -> void:
	_content = content
	var hub: RefCounted = LoopbackTransport.create_hub()
	for i in 3:
		var bus := WlEventBus.new()
		bus.name = "Bus%d" % i
		_root.add_child(bus)
		_buses.append(bus)
		var t := LoopbackTransport.hub_transport(hub)
		var s := WlNetSession.new()
		s.name = "Net%d" % i
		s.bus = bus
		s.registry = _reg
		_root.add_child(s)
		s.use_transport(t)
		if t.get_parent() == null:
			s.add_child(t)
		_nets.append(s)
	var host_net := _nets[0]
	host_net.host_room(8)
	assert_true(_pump(func() -> bool: return host_net.room_code != "" and host_net.local_peer != 0))
	host_net.set_game(GAME, str(_reg.manifest(GAME)["version"]), content)
	for i in [1, 2]:
		_nets[i].join_room(host_net.room_code)
		var cn := _nets[i]
		assert_true(_pump(func() -> bool: return cn.local_peer != 0))
		cn.game_message.connect(_on_client_message.bind(i))
	assert_true(_pump(func() -> bool: return host_net.peers().size() == 3))


func _rider(parent: Node, slot: PlayerSlot, record: bool) -> LocalRider:
	var dev := MockTrainer.from_spec("erg", slot.ftp, {"seed": 11 + slot.slot_index})
	var r := LocalRider.new()
	r.name = "Rider%d" % slot.peer_id
	var opts := {"multiplayer": true, "scaling_mode": slot.scaling_mode, "record": false}
	if record:
		opts["recorder"] = RideRecorder.new()
	r.setup(slot.peer_id, null, slot, dev, opts)
	r.add_child(dev)
	parent.add_child(r)
	return r


func _start_host() -> void:
	var net := _nets[0]
	net.mark_started()
	var players := net.lobby_slots()
	var riders := {}
	for p in players:
		if p.peer_id == net.local_peer or p.is_bot:
			riders[p.peer_id] = _rider(_root, p, false)
	_host = GameHost.new()
	_host.name = "Host"
	_root.add_child(_host)
	assert_eq(_host.setup({
		"game_id": GAME, "content_id": _content, "seed": 9, "role": Wl.HOST, "players": players,
		"local_riders": riders, "local_peer": net.local_peer, "net": net, "bus": _buses[0],
		"registry": _reg, "headless": true, "realtime": false,
		"report": true, "record_rides": false,
		"progress_path": _tmp.path_join("p1/games/%s/progress.json" % GAME),
	}), "")
	_host.start()


func _on_client_message(_from: int, data: Dictionary, i: int) -> void:
	if str(data.get("type", "")) != "session_start" or _clients.has(i):
		return
	var net := _nets[i]
	var slot: PlayerSlot = null
	for pd: Variant in data.get("players", []):
		var p := PlayerSlot.from_dict(pd as Dictionary)
		if p.peer_id == net.local_peer:
			slot = p
	var rider := _rider(_root, slot, true)
	var gh := GameHost.new()
	gh.name = "Client%d" % net.local_peer
	_root.add_child(gh)
	var err := gh.setup({
		"role": Wl.CLIENT, "local_peer": net.local_peer,
		"local_riders": {net.local_peer: rider}, "net": net, "bus": _buses[i],
		"registry": _reg, "headless": true, "realtime": false, "report": true, "record_rides": false,
		"progress_path": _tmp.path_join("p%d/games/%s/progress.json" % [net.local_peer, GAME]),
		"session_start": data.duplicate(true),
	})
	assert_eq(err, "")
	gh.start()
	_clients[i] = gh
	_client_riders[i] = rider


func _step(n: int) -> void:
	for k in n:
		_host.step()
		for i in [1, 2]:
			if _clients.has(i):
				(_clients[i] as GameHost).step()
			else:
				_nets[i].poll()


func test_restarted_client_resumes_the_ramp() -> void:
	_lobby("short")  # WARMUP ERG 50 -> 65 % over 300 s (lap), FTP 200
	_start_host()
	_step(2400)
	var old: GameHost = _clients[1]
	var peer := old.local_peer()
	var old_rider: LocalRider = _client_riders[1]
	var before_w := old_rider.telemetry().applied_target_w
	var gov_before := float(old_rider.governor.status()["phase_elapsed_s"])
	(_nets[1].transport as LoopbackTransport).simulate_drop()
	_clients.erase(1)
	old.end_session("restart")
	_step(40)  # the net rejoins on its own; session_start creates a fresh GameHost and rider
	assert_true(_clients.has(1), "a fresh client GameHost after the rejoin")
	var c: GameHost = _clients[1]
	var rider: LocalRider = _client_riders[1]
	assert_ne(rider, old_rider, "a fresh LocalRider")
	var after_w := rider.telemetry().applied_target_w
	var gov_after := float(rider.governor.status()["phase_elapsed_s"])
	var host_el := _host.tracker.state(peer).elapsed_s
	gut.p("restarted peer %d: applied %d W -> %d W; governor phase elapsed %.1f s -> %.1f s; GameHost local phase elapsed %.1f s; host phase elapsed %.1f s; phase %d vs host %d"
		% [peer, before_w, after_w, gov_before, gov_after, c.local_phase_state().elapsed_s, host_el, c.local_phase_state().index, _host.tracker.index_of(peer)])
	assert_eq(c.local_phase_state().index, _host.tracker.index_of(peer), "the same phase as the host")
	assert_almost_eq(gov_after, host_el, 1.0, "the restarted client's governor resumes the phase at the host's elapsed time")
	assert_almost_eq(gov_after, c.local_phase_state().elapsed_s, 1.0, "the trainer's ramp and the HUD clock agree")
	assert_gte(after_w, before_w - 2, "the warm-up ramp does not start over after a restart")
	assert_lte((rider.recorder as RideRecorder).lap_count(), 1, "the new FIT starts at the rejoin with no extra lap")
