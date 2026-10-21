extends GutTest
## Keeping clients in step over the real WlNetSession and LoopbackTransport (W3 NET-1, NET-2,
## NET-5, SAF-5): a host and two client GameHosts started the way the app shell starts them
## (each client's GameHost is made inside the game_message emission of session_start). Clients
## ride real LocalRiders on MockTrainers so their governors' phase clocks and FIT laps show.
##   - The host's socket drops across a phase boundary and it reclaims peer 1: every client
##     follows the host's phase again, and a peer that left meanwhile is marked dropped.
##   - A client's socket drops mid-ramp and it rejoins: the governor keeps its phase clock and
##     the FIT gets no extra lap.
##   - A client whose net gives up for good rides its cool-down here and ends the session.

const FIXTURES := "res://tests/fixtures/games"
const GAME := "fx_solo"

var _root: Node = null
var _reg: WlGameRegistry = null
var _nets: Array[WlNetSession] = []
var _buses: Array[WlEventBus] = []
var _clients: Dictionary = {}
var _host: GameHost = null
var _tmp: String = ""
var _content: String = "tiny"
var _recorders: Dictionary = {}
var _finished: Dictionary = {}
var _watch: AppLogWatch = null


func before_each() -> void:
	_root = Node.new()
	add_child_autofree(_root)
	_nets.clear()
	_buses.clear()
	_clients.clear()
	_recorders.clear()
	_finished.clear()
	_host = null
	_tmp = Paths.make_temp_dir("wattlands_net_resync")
	Paths.set_override(_tmp)
	_reg = WlGameRegistry.new()
	_reg.scan_on_ready = false
	_reg.content_root = FIXTURES.path_join("_content")
	_root.add_child(_reg)
	_reg.scan(FIXTURES.path_join("runtime"))
	_watch = AppLogWatch.new()
	OS.add_logger(_watch)


func after_each() -> void:
	OS.remove_logger(_watch)
	Paths.set_override("")
	GameSimRunner._remove_tree(_tmp)


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
		var rec := RideRecorder.new()
		opts["recorder"] = rec
		_recorders[slot.peer_id] = rec
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
	var gh := GameHost.new()
	gh.name = "Client%d" % net.local_peer
	_root.add_child(gh)
	var err := gh.setup({
		"role": Wl.CLIENT, "local_peer": net.local_peer,
		"local_riders": {net.local_peer: _rider(_root, slot, true)}, "net": net, "bus": _buses[i],
		"registry": _reg, "headless": true, "realtime": false, "report": true, "record_rides": false,
		"progress_path": _tmp.path_join("p%d/games/%s/progress.json" % [net.local_peer, GAME]),
		"session_start": data.duplicate(true),
	})
	assert_eq(err, "")
	gh.session_finished.connect(func(r: GameResults) -> void: _finished[i] = r)
	gh.start()
	_clients[i] = gh


func _step(n: int) -> void:
	for k in n:
		_host.step()
		for i in [1, 2]:
			if _clients.has(i):
				(_clients[i] as GameHost).step()
			else:
				_nets[i].poll()


func _desyncs() -> int:
	return int(_watch.counts()["desync_warnings"])


## BRIEF 5.3 holds the room 120 s for a dropped host so it can come back, and 3.6/5.5 send
## every phase change to the rider's client. A phase change while the host's socket was down
## reaches the clients once the host reclaims peer 1 (WlNetSession.resync_requested).
func test_host_drop_and_reclaim_resyncs_client_phases() -> void:
	_lobby("tiny")
	_start_host()
	_step(20)
	assert_eq(_clients.size(), 2)
	var host_net := _nets[0]
	host_net.auto_reconnect = false
	(host_net.transport as LoopbackTransport).simulate_drop()
	_step(60)  # host game tick ~80: the 2 s WARMUP has ended on the host
	assert_eq(host_net.state, WlNetSession.STATE_RECONNECTING, "host is away")
	for i in [1, 2]:
		assert_eq((_clients[i] as GameHost).local_phase_state().index, 0, "precondition: client %d missed the change" % i)
	host_net.rejoin()
	assert_true(_pump(func() -> bool: return host_net.state == WlNetSession.STATE_HOSTING), "host reclaimed peer 1")
	_step(10)  # still inside the host's WORK phase (ends at tick 100)
	for i in [1, 2]:
		var gh: GameHost = _clients[i]
		var peer := gh.local_peer()
		var rider: LocalRider = gh.local_rider(peer)
		assert_eq(gh.local_phase_state().index, _host.tracker.index_of(peer), "peer %d follows the host's phase again" % peer)
		assert_eq(int(rider.governor.status()["phase_index"]), _host.tracker.index_of(peer), "and so does its governor")
		assert_almost_eq(gh.local_phase_state().elapsed_s, _host.tracker.state(peer).elapsed_s, 0.3, "with the host's phase clock")
	assert_eq(_desyncs(), 0, "the gap after the host's return is expected, not a desync")


## A client that leaves while the host is away is gone when the host reclaims peer 1 (the
## relay's joined.peers): on_afk(peer, true), connected false and no stale power (BRIEF 3.6).
func test_peer_that_left_while_host_was_away_is_marked_dropped() -> void:
	_lobby("short")
	_start_host()
	_step(100)
	var host_net := _nets[0]
	host_net.auto_reconnect = false
	(host_net.transport as LoopbackTransport).simulate_drop()
	_step(2)
	var gone: GameHost = _clients[2]
	var gone_peer := gone.local_peer()
	_nets[2].leave()  # explicit leave while the host is away
	_clients.erase(2)
	_step(20)
	host_net.rejoin()
	assert_true(_pump(func() -> bool: return host_net.state == WlNetSession.STATE_HOSTING))
	_step(200)
	var afk_log: Array = _host.game.get("afk_log")
	var marked := false
	for e: Array in afk_log:
		if int(e[0]) == gone_peer and bool(e[1]):
			marked = true
	var row: Dictionary = _host.ctx.roster.get(gone_peer, {})
	assert_true(marked, "on_afk(%d, true) after it left while the host was away" % gone_peer)
	assert_false(bool(row.get("connected", true)), "the roster shows the departed rider disconnected")
	assert_eq(float(row.get("raw_w", -1.0)), 0.0, "a departed rider's stale power is not live power")
	assert_false(host_net.peers().has(gone_peer), "the host's lobby no longer lists it as connected")
	var stayed: GameHost = _clients[1]
	assert_eq(stayed.local_phase_state().index, _host.tracker.index_of(stayed.local_peer()))


## BRIEF 3.6: a rejoin gets its plan and its phase, and the rider resumes the phase. A
## socket-only drop mid-ramp keeps the governor's phase clock, the ramp and the FIT laps.
func test_socket_rejoin_mid_ramp_keeps_the_ramp_and_laps() -> void:
	_lobby("short")  # WARMUP ERG 50 -> 65 % over 300 s (lap), FTP 200
	_start_host()
	_step(2400)  # 120 s into the ramp
	var c: GameHost = _clients[1]
	var peer := c.local_peer()
	var rider: LocalRider = c.local_rider(peer)
	var before_w := rider.telemetry().applied_target_w
	var rec: RideRecorder = _recorders[peer]
	var laps_before := rec.lap_count()
	(_nets[1].transport as LoopbackTransport).simulate_drop()  # socket drop, auto rejoin
	_step(40)
	assert_eq(_nets[1].state, WlNetSession.STATE_JOINED, "rejoined")
	var after_w := rider.telemetry().applied_target_w
	var gov_elapsed := float(rider.governor.status()["phase_elapsed_s"])
	assert_almost_eq(gov_elapsed, _host.tracker.state(peer).elapsed_s, 1.0, "the governor's phase clock follows the host after a rejoin")
	assert_gte(after_w, before_w, "the warm-up ramp does not start over after a rejoin")
	assert_eq(rec.lap_count(), laps_before, "a rejoin inside the same phase adds no FIT lap")
	assert_almost_eq(c.local_phase_state().elapsed_s, _host.tracker.state(peer).elapsed_s, 0.3)
	assert_eq(_desyncs(), 0, "the gap after this client's own rejoin is expected, not a desync")


## SAF-5: a client whose net session gives up for good (the 120 s rejoin window ran out, or
## the relay lost the room) leaves the interval: it rides its cool-down here, then the session
## ends with that reason and session_finished(null), so a zero-input rider is never stuck.
func _net_gives_up(reason: String) -> void:
	_lobby("short")
	_start_host()
	_step(6400)  # 320 s: the WORK phase at 75 %
	var c: GameHost = _clients[1]
	var peer := c.local_peer()
	var rider: LocalRider = c.local_rider(peer)
	assert_eq(int(rider.governor.status()["phase_index"]), 1, "precondition: the client rides WORK")
	# The net session ends for good with `reason`.
	_nets[1].refused.emit(reason)
	for k in 20:
		c.step()
	var cd := rider.plan().cooldown_index()
	assert_eq(int(rider.governor.status()["phase_index"]), cd, "%s: the rider rides its cool-down at once" % reason)
	assert_eq(c.state, "cooldown")
	assert_push_warning("riding the cool-down here")
	for k in roundi(180.0 / Wl.SIM_DT):
		c.step()
	assert_eq(c.state, "ended", "%s: the session ends after the cool-down" % reason)
	assert_eq(c.end_reason, reason)
	assert_true(_finished.has(1) and _finished[1] == null, "session_finished(null) tells the app")


func test_a_client_whose_net_drops_for_good_rides_its_cooldown_and_ends() -> void:
	_net_gives_up("dropped")


func test_a_client_whose_room_is_gone_rides_its_cooldown_and_ends() -> void:
	_net_gives_up("room_not_found")
