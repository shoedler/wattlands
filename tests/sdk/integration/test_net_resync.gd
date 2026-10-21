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
##   - W4 NET-2: a restarted client, a phase change while a client's socket was down and one
##     while the host was away all resume the phase at the host's elapsed time through
##     LocalRider.resume_phase(index, elapsed_s) (a spy rider records the calls) and keep one
##     FIT lap per phase; with the real LocalRider the governor's phase clock follows the host.

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
## Clients ride ResumeSpyRider (W4 NET-2) instead of LocalRider.
var _spy: bool = false


## W4 NET-2: a LocalRider with resume_phase(index, elapsed_s), the signature trainer-core's
## LocalRider.resume_phase has. It records each call (with the rider's platform time) and enters
## the phase in the governor and MockTrainer; like the real one it laps only a real phase change
## (the rider rode another phase of this plan), never a restarted client's first phase. Its
## start_phase calls are recorded too.
class ResumeSpyRider:
	extends LocalRider
	var resumes: Array = []
	var starts: Array[int] = []

	func start_phase(index: int) -> void:
		starts.append(index)
		super.start_phase(index)

	func resume_phase(index: int, elapsed_s: float) -> void:
		resumes.append([index, elapsed_s, platform_time()])
		var previous := _phase_index
		_phase_index = index
		if governor != null:
			governor.start_phase(index)
		if device is MockTrainer:
			(device as MockTrainer).set_phase(index)
		var ph := plan().phase(index) if plan() != null else null
		if (
			ph != null
			and (ph.lap or ph.kind == Wl.COOLDOWN)
			and previous >= 0
			and previous != index
		):
			lap(ph.label)


func before_each() -> void:
	_root = Node.new()
	add_child_autofree(_root)
	_nets.clear()
	_buses.clear()
	_clients.clear()
	_recorders.clear()
	_finished.clear()
	_host = null
	_spy = false
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
	var r: LocalRider = ResumeSpyRider.new() if _spy and record else LocalRider.new()
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
	assert_eq(
		(
			_host
			. setup(
				{
					"game_id": GAME,
					"content_id": _content,
					"seed": 9,
					"role": Wl.HOST,
					"players": players,
					"local_riders": riders,
					"local_peer": net.local_peer,
					"net": net,
					"bus": _buses[0],
					"registry": _reg,
					"headless": true,
					"realtime": false,
					"report": true,
					"record_rides": false,
					"progress_path": _tmp.path_join("p1/games/%s/progress.json" % GAME),
				}
			)
		),
		""
	)
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
	var err := (
		gh
		. setup(
			{
				"role": Wl.CLIENT,
				"local_peer": net.local_peer,
				"local_riders": {net.local_peer: _rider(_root, slot, true)},
				"net": net,
				"bus": _buses[i],
				"registry": _reg,
				"headless": true,
				"realtime": false,
				"report": true,
				"record_rides": false,
				"progress_path":
				_tmp.path_join("p%d/games/%s/progress.json" % [net.local_peer, GAME]),
				"session_start": data.duplicate(true),
			}
		)
	)
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
		assert_eq(
			(_clients[i] as GameHost).local_phase_state().index,
			0,
			"precondition: client %d missed the change" % i
		)
	host_net.rejoin()
	assert_true(
		_pump(func() -> bool: return host_net.state == WlNetSession.STATE_HOSTING),
		"host reclaimed peer 1"
	)
	_step(10)  # still inside the host's WORK phase (ends at tick 100)
	for i in [1, 2]:
		var gh: GameHost = _clients[i]
		var peer := gh.local_peer()
		var rider: LocalRider = gh.local_rider(peer)
		assert_eq(
			gh.local_phase_state().index,
			_host.tracker.index_of(peer),
			"peer %d follows the host's phase again" % peer
		)
		assert_eq(
			int(rider.governor.status()["phase_index"]),
			_host.tracker.index_of(peer),
			"and so does its governor"
		)
		assert_almost_eq(
			gh.local_phase_state().elapsed_s,
			_host.tracker.state(peer).elapsed_s,
			0.3,
			"with the host's phase clock"
		)
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
	assert_false(
		bool(row.get("connected", true)), "the roster shows the departed rider disconnected"
	)
	assert_eq(
		float(row.get("raw_w", -1.0)), 0.0, "a departed rider's stale power is not live power"
	)
	assert_false(
		host_net.peers().has(gone_peer), "the host's lobby no longer lists it as connected"
	)
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
	assert_almost_eq(
		gov_elapsed,
		_host.tracker.state(peer).elapsed_s,
		1.0,
		"the governor's phase clock follows the host after a rejoin"
	)
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
	assert_eq(
		int(rider.governor.status()["phase_index"]),
		cd,
		"%s: the rider rides its cool-down at once" % reason
	)
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


## The host's elapsed time in the client's phase at the moment of `call` ([index, elapsed_s,
## the rider's platform time then]), from the host's elapsed time now.
func _host_elapsed_at(call: Array, rider: LocalRider, peer: int) -> float:
	return _host.tracker.state(peer).elapsed_s - (rider.platform_time() - float(call[2]))


## W4 NET-2 (BRIEF 3.6: the rider resumes its phase): a client that RESTARTS (a new GameHost and
## LocalRider, as the app does after a relaunch with the saved token) 120 s into the 300 s ERG
## ramp resumes the phase at the host's elapsed time instead of starting it over.
func test_a_restarted_client_resumes_its_phase_at_the_hosts_elapsed_time() -> void:
	_spy = true
	_lobby("short")  # WARMUP ERG 50 -> 65 % over 300 s (lap), WORK 75 % 120 s (lap)
	_start_host()
	_step(2400)
	var old: GameHost = _clients[1]
	var peer := old.local_peer()
	var old_rider := old.local_rider(peer)
	(_nets[1].transport as LoopbackTransport).simulate_drop()
	_clients.erase(1)
	old.end_session("restart")
	_step(40)  # the net rejoins on its own; session_start makes a fresh GameHost and rider
	assert_true(_clients.has(1), "a fresh client GameHost after the rejoin")
	if not _clients.has(1):
		return
	var c: GameHost = _clients[1]
	var rider := c.local_rider(peer) as ResumeSpyRider
	assert_not_null(rider)
	if rider == null:
		return
	assert_ne(rider, old_rider, "a fresh rider")
	assert_eq(rider.starts, [] as Array[int], "the phase is not started over")
	assert_eq(rider.resumes.size(), 1, "one resume_phase: %s" % str(rider.resumes))
	if rider.resumes.size() != 1:
		return
	var call: Array = rider.resumes[0]
	assert_eq(int(call[0]), _host.tracker.index_of(peer), "the host's phase index")
	assert_gt(float(call[1]), 119.0, "resumed mid-ramp, not at 0")
	assert_almost_eq(
		float(call[1]), _host_elapsed_at(call, rider, peer), 0.2, "at the host's elapsed time"
	)
	assert_eq(int(rider.governor.status()["phase_index"]), 0, "the governor rides the warm-up")
	var rec: RideRecorder = _recorders[peer]
	assert_eq(rec.lap_count(), 1, "the new FIT has one open lap")
	assert_almost_eq(c.local_phase_state().elapsed_s, _host.tracker.state(peer).elapsed_s, 0.3)


## W4 NET-2: the phase changes while a client's socket is down. After the rejoin the client
## resumes the NEW phase at the host's elapsed time (resume_phase, not start_phase); its FIT
## gets that phase's lap from resume_phase, once, and a resync of it changes nothing.
func test_a_phase_change_during_a_socket_outage_is_resumed_with_its_lap() -> void:
	_spy = true
	_lobby("short")
	_start_host()
	_step(5900)  # 295 s: 5 s before WORK
	var c: GameHost = _clients[1]
	var peer := c.local_peer()
	var rider := c.local_rider(peer) as ResumeSpyRider
	var rec: RideRecorder = _recorders[peer]
	var laps_before := rec.lap_count()
	assert_eq(rider.starts, [0] as Array[int], "precondition: the warm-up started normally")
	_nets[1].auto_reconnect = false
	(_nets[1].transport as LoopbackTransport).simulate_drop()
	_step(200)  # 305 s: the host moved this rider to WORK 5 s ago
	assert_eq(_host.tracker.index_of(peer), 1, "precondition: the host's WORK phase")
	assert_eq(c.local_phase_state().index, 0, "precondition: the client missed the change")
	_nets[1].rejoin()
	assert_true(
		_pump(func() -> bool: return _nets[1].state == WlNetSession.STATE_JOINED), "rejoined"
	)
	_step(10)
	assert_eq(rider.starts, [0] as Array[int], "WORK is not started at 0")
	assert_eq(rider.resumes.size(), 1, "one resume_phase: %s" % str(rider.resumes))
	if rider.resumes.size() != 1:
		return
	var call: Array = rider.resumes[0]
	assert_eq(int(call[0]), 1, "the new phase")
	assert_between(float(call[1]), 4.5, 6.0, "at the host's elapsed time in it")
	assert_almost_eq(float(call[1]), _host_elapsed_at(call, rider, peer), 0.2)
	assert_eq(int(rider.governor.status()["phase_index"]), 1, "the governor rides WORK")
	assert_eq(rec.lap_count(), laps_before + 1, "WORK's lap")
	assert_eq(c.local_phase_state().index, 1)
	assert_almost_eq(c.local_phase_state().elapsed_s, _host.tracker.state(peer).elapsed_s, 0.3)
	# A resync of the phase it now rides changes nothing.
	_host.call("_resync_peer", peer, "test")
	_step(10)
	assert_eq(rider.resumes.size(), 1, "the same phase is not resumed again")
	assert_eq(rec.lap_count(), laps_before + 1, "and gets no second lap")
	assert_eq(_desyncs(), 0)


## W4 NET-2: the phase changes while the HOST is away; when it reclaims peer 1 every client
## resumes the new phase at the host's elapsed time (not at 0).
func test_a_phase_change_while_the_host_was_away_is_resumed() -> void:
	_spy = true
	_lobby("tiny")  # WARMUP 2 s, WORK 3 s, ...
	_start_host()
	_step(20)
	var host_net := _nets[0]
	host_net.auto_reconnect = false
	(host_net.transport as LoopbackTransport).simulate_drop()
	_step(60)  # the 2 s warm-up ended on the host
	host_net.rejoin()
	assert_true(
		_pump(func() -> bool: return host_net.state == WlNetSession.STATE_HOSTING),
		"host reclaimed peer 1"
	)
	_step(10)
	for i in [1, 2]:
		var gh: GameHost = _clients[i]
		var peer := gh.local_peer()
		var rider := gh.local_rider(peer) as ResumeSpyRider
		assert_eq(rider.starts, [0] as Array[int], "peer %d: only the warm-up was started" % peer)
		assert_eq(
			rider.resumes.size(), 1, "peer %d: one resume_phase: %s" % [peer, str(rider.resumes)]
		)
		if rider.resumes.size() != 1:
			continue
		var call: Array = rider.resumes[0]
		assert_eq(int(call[0]), 1, "peer %d resumes WORK" % peer)
		assert_gt(float(call[1]), 0.0)
		assert_almost_eq(
			float(call[1]),
			_host_elapsed_at(call, rider, peer),
			0.2,
			"peer %d: at the host's elapsed time" % peer
		)
		assert_eq(int(rider.governor.status()["phase_index"]), _host.tracker.index_of(peer))
	assert_eq(_desyncs(), 0)


## The W4r2 NET-2 proof with the real LocalRider: a restarted client 120 s into the ERG ramp.
## With LocalRider.resume_phase (W4 R8, trainer-core) the governor resumes the ramp at the
## host's elapsed time and the applied target doesn't drop; a LocalRider without it falls back
## to start_phase (the governor rides the host's phase, from 0).
func test_a_restarted_client_with_the_real_rider_follows_the_hosts_phase() -> void:
	_lobby("short")
	_start_host()
	_step(2400)
	var old: GameHost = _clients[1]
	var peer := old.local_peer()
	var before_w := old.local_rider(peer).telemetry().applied_target_w
	(_nets[1].transport as LoopbackTransport).simulate_drop()
	_clients.erase(1)
	old.end_session("restart")
	_step(40)
	assert_true(_clients.has(1), "a fresh client GameHost after the rejoin")
	if not _clients.has(1):
		return
	var c: GameHost = _clients[1]
	var rider := c.local_rider(peer)
	var st: Dictionary = rider.governor.status()
	assert_eq(
		int(st["phase_index"]), _host.tracker.index_of(peer), "the governor rides the host's phase"
	)
	if rider.has_method("resume_phase"):
		assert_almost_eq(
			float(st["phase_elapsed_s"]),
			_host.tracker.state(peer).elapsed_s,
			1.0,
			"the restarted client's governor resumes the phase at the host's elapsed time"
		)
		assert_gte(
			rider.telemetry().applied_target_w, before_w - 2, "the warm-up ramp does not start over"
		)
	else:
		assert_lt(float(st["phase_elapsed_s"]), 5.0, "without resume_phase the phase starts over")
	assert_almost_eq(c.local_phase_state().elapsed_s, _host.tracker.state(peer).elapsed_s, 0.3)
