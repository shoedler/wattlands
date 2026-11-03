extends GutTest
## Multiplayer for every real game, in process (cleanup/mp-every-game): a host and two client
## GameHosts of fishing, siege, tank and workout over the real WlNetSession and a LoopbackHub,
## started the way the app shell starts them (each client's GameHost is made inside the
## game_message emission of session_start, so a rejoin or a restart makes a fresh one the same
## way). Every rider is a real LocalRider on a MockTrainer. The cases: a socket drop mid-phase,
## across a phase boundary and across the start of the cool-down; the host's own drop and
## return; a net that ends for good; a restarted client; latency; a late join; hostile input.

const GAMES: Array[String] = ["fishing", "siege", "tank", "workout"]
## Per game: [phase index, seconds into it] of a mid-phase moment with a game going on, the
## phase whose end a client's outage crosses, and the busiest moment [phase, seconds].
const MID := {"fishing": [2, 10.0], "siege": [1, 40.0], "tank": [1, 10.0], "workout": [1, 10.0]}
const BOUNDARY := {"fishing": 1, "siege": 0, "tank": 0, "workout": 0}
const BUSY := {"fishing": [2, 12.0], "siege": [1, 50.0], "tank": [1, 12.0], "workout": [1, 15.0]}
## Numeric slack between a restarted client's view state and a client that never left (the own
## rider's predicted fields differ a little per client).
const VIEW_TOL := {"fishing": 3.0, "siege": 0.0, "tank": 2.0, "workout": 12.0}
## Keys of a view state that depend on how often snapshot() was called, not on the game.
const VIEW_SKIP: Array[String] = ["tl", "tll"]

var _root: Node = null
var _reg: WlGameRegistry = null
var _hub: LoopbackHub = null
var _nets: Array[WlNetSession] = []
var _buses: Array[WlEventBus] = []
var _clients: Dictionary = {}
var _host: GameHost = null
var _tmp: String = ""
var _game: String = ""
var _content: String = ""
var _finished: Dictionary = {}
var _afk: Array = []
var _recs: Dictionary = {}
var _refusals: Dictionary = {}
var _watch: AppLogWatch = null


func before_each() -> void:
	_tmp = Paths.make_temp_dir("wattlands_mp_every")
	Paths.set_override(_tmp)
	_watch = AppLogWatch.new()
	OS.add_logger(_watch)


func after_each() -> void:
	_down()
	OS.remove_logger(_watch)
	Paths.set_override("")
	GameSimRunner._remove_tree(_tmp)


func _down() -> void:
	if _root != null:
		_root.free()
		_root = null
	_nets.clear()
	_buses.clear()
	_clients.clear()
	_finished.clear()
	_afk.clear()
	_recs.clear()
	_refusals.clear()
	_host = null
	_hub = null
	_reg = null


func _pump(done: Callable, max_iter: int = 400) -> bool:
	for k in max_iter:
		for n in _nets:
			n.poll()
		if done.call():
			return true
	return false


## A fresh host and two clients for `game` (its e2e content unless `content`), the host's
## GameHost started and both clients' GameHosts made. Call _down() before booting again.
func _boot(game: String, content: String = "") -> void:
	_down()
	_game = game
	_root = Node.new()
	add_child(_root)
	_reg = WlGameRegistry.new()
	_reg.scan_on_ready = false
	_root.add_child(_reg)
	_reg.scan()
	var manifest := _reg.manifest(game)
	_content = content if content != "" else str(manifest["e2e_content"])
	_hub = LoopbackTransport.create_hub() as LoopbackHub
	for i in 3:
		_nets.append(_make_net(i))
	var host_net := _nets[0]
	host_net.host_room(8)
	assert_true(_pump(func() -> bool: return host_net.room_code != "" and host_net.local_peer != 0))
	host_net.set_game(game, str(manifest["version"]), _content)
	for i in [1, 2]:
		_nets[i].join_room(host_net.room_code)
		var cn := _nets[i]
		assert_true(
			_pump(func() -> bool: return cn.local_peer != 0), "%s: client %d joined" % [game, i]
		)
	assert_true(_pump(func() -> bool: return host_net.peers().size() == 3))
	_start_host()
	_step(12)


func _make_net(i: int) -> WlNetSession:
	while _buses.size() <= i:
		var bus := WlEventBus.new()
		bus.name = "Bus%d" % _buses.size()
		_root.add_child(bus)
		_buses.append(bus)
	var t := LoopbackTransport.hub_transport(_hub)
	var s := WlNetSession.new()
	s.name = "Net%d" % i
	s.bus = _buses[i]
	s.registry = _reg
	s.persist_token = i > 0
	s.token_path = _tmp.path_join("token%d.json" % i)
	s.recent_rooms_file = _tmp.path_join("recent%d.json" % i)
	_root.add_child(s)
	s.use_transport(t)
	if t.get_parent() == null:
		s.add_child(t)
	if i > 0:
		s.game_message.connect(_on_client_message.bind(i))
		s.refused.connect(func(reason: String) -> void: _refusals[i] = reason)
	return s


func _rider(slot: PlayerSlot) -> LocalRider:
	var dev := MockTrainer.from_spec("erg", slot.ftp, {"seed": 11 + slot.slot_index})
	var r := LocalRider.new()
	r.name = "Rider%d" % slot.peer_id
	var opts := {"multiplayer": true, "scaling_mode": slot.scaling_mode, "record": false}
	var rec := RideRecorder.new()
	opts["recorder"] = rec
	_recs[slot.peer_id] = rec
	r.setup(slot.peer_id, null, slot, dev, opts)
	r.add_child(dev)
	_root.add_child(r)
	return r


func _start_host() -> void:
	var net := _nets[0]
	net.mark_started()
	var players := net.lobby_slots()
	var riders := {}
	for p in players:
		if p.peer_id == net.local_peer or p.is_bot:
			riders[p.peer_id] = _rider(p)
	_host = GameHost.new()
	_host.name = "Host"
	_root.add_child(_host)
	var err := (
		_host
		. setup(
			{
				"game_id": _game,
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
				"progress_path": _tmp.path_join("p1/games/%s/progress.json" % _game),
			}
		)
	)
	assert_eq(err, "", "%s: host setup" % _game)
	_buses[0].afk_changed.connect(func(peer: int, afk: bool) -> void: _afk.append([peer, afk]))
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
				"local_riders": {net.local_peer: _rider(slot)},
				"net": net,
				"bus": _buses[i],
				"registry": _reg,
				"headless": true,
				"realtime": false,
				"report": true,
				"record_rides": true,
				"progress_path":
				_tmp.path_join("p%d/games/%s/progress.json" % [net.local_peer, _game]),
				"session_start": data.duplicate(true),
			}
		)
	)
	assert_eq(err, "", "%s: client %d setup" % [_game, i])
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


## Step until `done` is true, at most `max_ticks` ticks.
func _step_until(done: Callable, max_ticks: int) -> bool:
	for k in max_ticks:
		if done.call():
			return true
		_step(1)
	return done.call()


func _lt(i: int) -> LoopbackTransport:
	return _nets[i].transport as LoopbackTransport


func _client(i: int) -> GameHost:
	return _clients[i] as GameHost


func _desyncs() -> int:
	return int(_watch.counts()["desync_warnings"])


func _script_errors() -> int:
	return int(_watch.counts()["script_errors"])


func _game_events(gh: GameHost) -> Array:
	var out: Array = []
	for e: Dictionary in gh.report.events:
		if str(e["type"]) == "game_event":
			out.append(e["event"])
	return out


func _report_events(gh: GameHost, type: String) -> Array:
	return gh.report.events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == type)


func _restart_client(i: int) -> void:
	var old := _client(i)
	var peer := old.local_peer()
	old.end_session("restart")
	_clients.erase(i)
	var rider := old.local_rider(peer)
	old.free()
	rider.free()
	var old_net := _nets[i]
	_nets[i] = null
	old_net.free()
	var s := _make_net(i)
	_nets[i] = s
	s.join_room(_nets[0].room_code)


func _diff(a: Variant, b: Variant, tol: float, path: String, out: Array) -> void:
	if a is Dictionary and b is Dictionary:
		for k: Variant in (a as Dictionary).keys():
			if not (b as Dictionary).has(k):
				out.append("%s.%s missing in b" % [path, k])
			else:
				_diff(a[k], b[k], tol, "%s.%s" % [path, k], out)
		for k: Variant in (b as Dictionary).keys():
			if not (a as Dictionary).has(k):
				out.append("%s.%s missing in a" % [path, k])
	elif a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			out.append("%s size %d vs %d" % [path, (a as Array).size(), (b as Array).size()])
			return
		for k in (a as Array).size():
			_diff(a[k], b[k], tol, "%s[%d]" % [path, k], out)
	elif (a is float or a is int) and (b is float or b is int):
		if absf(float(a) - float(b)) > tol:
			out.append("%s %s vs %s" % [path, a, b])
	elif a != b:
		out.append("%s %s vs %s" % [path, a, b])


func _host_idx(i: int) -> int:
	return _host.tracker.index_of(_client(i).local_peer())


func _plan_of(i: int) -> EffortPlan:
	return _host.plans[_client(i).local_peer()] as EffortPlan


## Step until the host has client 1's rider `elapsed_s` into phase `k` (or past it).
func _to_phase(k: int, elapsed_s: float) -> void:
	var peer := _client(1).local_peer()
	var ok := _step_until(
		func() -> bool:
			var idx := _host.tracker.index_of(peer)
			return idx > k or (idx == k and _host.tracker.state(peer).elapsed_s >= elapsed_s),
		6000
	)
	assert_true(ok, "%s: reached phase %d +%.0f s" % [_game, k, elapsed_s])


## Step until `lead_s` before the end of phase `k` (by its planned duration).
func _to_phase_end(k: int, lead_s: float) -> void:
	_to_phase(k, _plan_of(1).phase(k).duration_s - lead_s)


func _afk_edges(peer: int, from: int) -> Array:
	var out: Array = []
	for j in range(from, _afk.size()):
		if int((_afk[j] as Array)[0]) == peer:
			out.append(bool((_afk[j] as Array)[1]))
	return out


func _seq(gh: GameHost, field: String) -> int:
	return int(gh.get(field))


func _rejoin(i: int) -> void:
	var net := _nets[i]
	net.rejoin()
	assert_true(
		_step_until(func() -> bool: return net.state == WlNetSession.STATE_JOINED, 200),
		"%s: client %d rejoined" % [_game, i]
	)


## Drop client `i`'s socket for `ticks` platform ticks (the net stays down), then rejoin it.
## Returns the host's afk log size before the drop.
func _outage(i: int, ticks: int, during: Callable = Callable()) -> int:
	var before := _afk.size()
	_nets[i].auto_reconnect = false
	_lt(i).simulate_drop()
	_step(ticks)
	assert_eq(_nets[i].state, WlNetSession.STATE_RECONNECTING, "%s: client %d is away" % [_game, i])
	if during.is_valid():
		during.call()
	_rejoin(i)
	_nets[i].auto_reconnect = true
	return before


## What a rejoined client must have again: its seat, plan, phase and a fresh snapshot.
func _assert_resumed(i: int, peer: int, label: String) -> void:
	var c := _client(i)
	var g := "%s %s" % [_game, label]
	assert_eq(_nets[i].local_peer, peer, "%s: the same peer id" % g)
	assert_eq(c.local_peer(), peer, "%s: the same GameHost" % g)
	var seats := _nets[0].lobby_slots().filter(
		func(p: PlayerSlot) -> bool: return p.peer_id == peer
	)
	assert_eq(seats.size(), 1, "%s: still one seat" % g)
	assert_true(c.plans.has(peer), "%s: it has its plan" % g)
	if c.plans.has(peer):
		var pd: Array = []
		_diff(
			(c.plans[peer] as EffortPlan).to_dict()["phases"],
			(_host.plans[peer] as EffortPlan).to_dict()["phases"],
			0.001,
			"plan",
			pd
		)
		assert_eq(pd, [], "%s: the host's plan" % g)
	assert_eq(c.local_phase_state().index, _host.tracker.index_of(peer), "%s: the host's phase" % g)
	assert_lte(
		_seq(_host, "_snapshot_seq") - _seq(c, "_snap_seq_applied"), 2, "%s: a fresh snapshot" % g
	)
	assert_eq(c.desync_count, 0, "%s: no desync on this client" % g)


## Both clients saw the same game events from the first moment they were level on.
func _assert_same_events_after(
	a: int, b: int, max_ticks: int, label: String, require: bool = true
) -> void:
	var ca := _client(a)
	var cb := _client(b)
	var level := func() -> bool:
		return _seq(ca, "_event_seq_applied") == _seq(cb, "_event_seq_applied")
	var is_level := _step_until(level, max_ticks)
	if require:
		assert_true(is_level, "%s %s: the clients' event streams are level" % [_game, label])
	if not is_level:
		return
	var na := _game_events(ca).size()
	var nb := _game_events(cb).size()
	_step_until(func() -> bool: return _game_events(cb).size() > nb, max_ticks)
	_step_until(level, 40)
	var ea := _game_events(ca).slice(na)
	var eb := _game_events(cb).slice(nb)
	if require:
		assert_gt(ea.size(), 0, "%s %s: game events came in" % [_game, label])
	assert_eq(ea, eb, "%s %s: the same game events on both clients" % [_game, label])


func _assert_clean(label: String) -> void:
	assert_eq(_desyncs(), 0, "%s %s: no desync warning" % [_game, label])
	assert_eq(_script_errors(), 0, "%s %s: no script error" % [_game, label])


## Client 1 drops just before the end of phase `k` and rejoins after the host has left it.
func _outage_across(k: int, label: String) -> void:
	var peer := _client(1).local_peer()
	var pre := (
		"at the drop: host phase %d, %.2f s in; client phase %d"
		% [_host_idx(1), _host.tracker.state(peer).elapsed_s, _client(1).local_phase_state().index]
	)
	_nets[1].auto_reconnect = false
	_lt(1).simulate_drop()
	_step(60)
	var where := (
		"host phase %d (%.1f s in), client phase %d, phase %d lasts %.1f s"
		% [
			_host_idx(1),
			_host.tracker.state(peer).elapsed_s,
			_client(1).local_phase_state().index,
			k,
			_plan_of(1).phase(k).duration_s
		]
	)
	assert_gt(
		_host_idx(1), k, "%s %s: the host moved on while the client was away" % [_game, label]
	)
	assert_eq(
		_client(1).local_phase_state().index,
		k,
		"%s %s: and the client missed it (%s; %s)" % [_game, label, pre, where]
	)
	_rejoin(1)
	_nets[1].auto_reconnect = true
	_step(20)
	assert_eq(_client(1).local_peer(), peer)


## Case 1: a client's socket drops mid-phase and it rejoins.
func test_1_a_client_drops_mid_phase_and_rejoins() -> void:
	for g in GAMES:
		_boot(g)
		var mid: Array = MID[g]
		_to_phase(int(mid[0]), float(mid[1]))
		var c := _client(1)
		var peer := c.local_peer()
		var other := _client(2)
		var snap_before := _seq(c, "_snap_seq_applied")
		var before := _afk.size()
		var away := func() -> void:
			assert_eq(_afk_edges(peer, before), [true], "%s: the host's on_afk(true)" % g)
			var row: Dictionary = _host.ctx.roster.get(peer, {})
			assert_false(bool(row.get("connected", true)), "%s: the host's roster: away" % g)
			assert_false(
				bool((other.ctx.roster.get(peer, {}) as Dictionary).get("connected", true)),
				"%s: and the other client's" % g
			)
		_outage(1, 40, away)
		assert_true(
			_step_until(func() -> bool: return _afk_edges(peer, before).size() >= 2, 200),
			"%s: back from afk" % g
		)
		assert_eq(_afk_edges(peer, before), [true, false], "%s: on_afk true then false" % g)
		assert_gt(_seq(c, "_snap_seq_applied"), snap_before, "%s: new snapshots" % g)
		_assert_resumed(1, peer, "mid-phase rejoin")
		_step(20)
		assert_true(
			bool((other.ctx.roster.get(peer, {}) as Dictionary).get("connected", false)),
			"%s: the roster shows it back" % g
		)
		_assert_same_events_after(1, 2, 1500, "mid-phase rejoin")
		_assert_clean("mid-phase rejoin")


## Case 2: a client's outage spans a phase boundary, and the start of the cool-down.
func test_2_a_client_drops_across_a_phase_boundary_and_the_cooldown() -> void:
	for g in GAMES:
		_boot(g)
		var k := int(BOUNDARY[g])
		_to_phase_end(k, 1.0)
		var c := _client(1)
		var peer := c.local_peer()
		var other := _client(2)
		var other_peer := other.local_peer()
		_outage_across(k, "phase boundary")
		_assert_resumed(1, peer, "phase boundary")
		assert_eq(
			(_recs[peer] as RideRecorder).lap_count(),
			(_recs[other_peer] as RideRecorder).lap_count(),
			"%s: the same FIT laps as a rider that stayed" % g
		)
		_assert_same_events_after(1, 2, 100, "phase boundary", false)
		var cd := _plan_of(1).cooldown_index()
		_to_phase_end(cd - 1, 1.0)
		_outage_across(cd - 1, "start of the cool-down")
		_assert_resumed(1, peer, "cool-down start")
		assert_eq(_host_idx(1), cd, "%s: the host's cool-down" % g)
		assert_eq(int(c.local_rider(peer).governor.status()["phase_index"]), cd, "%s: governor" % g)
		assert_eq(
			(_recs[peer] as RideRecorder).lap_count(),
			(_recs[other_peer] as RideRecorder).lap_count(),
			"%s: the same FIT laps after the cool-down start" % g
		)
		_step(100)
		assert_eq(c.state, "cooldown", "%s: the client rides its cool-down" % g)
		_assert_clean("cool-down start")


## Case 3: the host's socket drops and it reclaims the room; clients keep riding.
func test_3_the_host_drops_and_reclaims_the_room() -> void:
	for g in GAMES:
		_boot(g)
		var mid: Array = MID[g]
		_to_phase(int(mid[0]), float(mid[1]))
		var host_net := _nets[0]
		var elapsed_before := _client(1).local_phase_state().elapsed_s
		host_net.auto_reconnect = false
		_lt(0).simulate_drop()
		_step(60)
		assert_eq(host_net.state, WlNetSession.STATE_RECONNECTING, "%s: the host is away" % g)
		for i in [1, 2]:
			assert_eq(_report_events(_client(i), "host_dropped").size(), 1, "%s: host_dropped" % g)
			assert_eq(_client(i).state, "running", "%s: client %d keeps riding" % [g, i])
		assert_gt(
			_client(1).local_phase_state().elapsed_s,
			elapsed_before + 2.5,
			"%s: its phase clock runs on" % g
		)
		host_net.rejoin()
		assert_true(
			_step_until(func() -> bool: return host_net.state == WlNetSession.STATE_HOSTING, 200),
			"%s: the host reclaimed the room" % g
		)
		_step(30)
		for i in [1, 2]:
			assert_eq(_report_events(_client(i), "host_back").size(), 1, "%s: host_back" % g)
			_assert_resumed(i, _client(i).local_peer(), "host back")
		_assert_same_events_after(1, 2, 1500, "host back")
		_assert_clean("host back")


## Case 4: a client's net ends for good: it rides its cool-down and ends with its ride.
func test_4_a_client_whose_net_ends_rides_its_cooldown_and_ends_with_its_ride() -> void:
	for g in GAMES:
		_boot(g)
		var mid: Array = MID[g]
		_to_phase(int(mid[0]), float(mid[1]))
		var c := _client(1)
		var peer := c.local_peer()
		_nets[1].auto_reconnect = false
		_nets[1].set_time(10.0)
		_lt(1).simulate_drop()
		_step(10)
		_nets[1].tick(125.0)  # past the 120 s rejoin window: the net session ends
		assert_eq(_refusals.get(1), "dropped", "%s: the net ended for good" % g)
		_step(20)
		var cd := _plan_of(1).cooldown_index()
		assert_eq(c.state, "cooldown", "%s: it rides its cool-down" % g)
		assert_eq(int(c.local_rider(peer).governor.status()["phase_index"]), cd, "%s: governor" % g)
		var snaps := _seq(_client(2), "_snap_seq_applied")
		_step(200)
		assert_gt(_seq(_client(2), "_snap_seq_applied"), snaps, "%s: client 2 gets snapshots" % g)
		assert_ne(_client(2).state, "ended", "%s: client 2 carries on" % g)
		assert_ne(_host.state, "ended", "%s: the host carries on" % g)
		assert_true(_afk_edges(peer, 0).has(true), "%s: the host marked the rider away" % g)
		var guard := 0
		while c.state != "ended" and guard < 4000:
			c.step()
			guard += 1
		assert_eq(c.state, "ended", "%s: the session ends after the cool-down" % g)
		assert_eq(c.end_reason, "dropped")
		assert_true(_finished.has(1) and _finished[1] == null, "%s: session_finished(null)" % g)
		var fits := c.fit_paths()
		assert_true(fits.has(peer), "%s: it ends with its ride data" % g)
		if fits.has(peer):
			assert_true(FileAccess.file_exists(str(fits[peer])), "%s: the FIT is on disk" % g)
		_step(40)
		assert_ne(_host.state, "ended", "%s: the host still carries on" % g)
		_assert_clean("net ended")


## Case 5: a client that restarts at the game's busiest moment has the same view state.
func test_5_a_restarted_client_matches_the_view_of_one_that_stayed() -> void:
	for g in GAMES:
		_boot(g)
		var busy: Array = BUSY[g]
		_to_phase(int(busy[0]), float(busy[1]))
		var peer := _client(1).local_peer()
		_restart_client(1)
		assert_true(
			_step_until(func() -> bool: return _clients.has(1), 200), "%s: a fresh client" % g
		)
		_step(40)
		assert_eq(_nets[1].local_peer, peer, "%s: the saved token gives the same peer id" % g)
		_assert_resumed(1, peer, "restart")
		var a := _view(_client(1))
		var b := _view(_client(2))
		var d: Array = []
		_diff(a, b, float(VIEW_TOL[g]), "view", d)
		assert_eq(d, [], "%s: the restarted client's view state matches" % g)
		assert_gt(a.size(), 0, "%s: a view state to compare" % g)
		_assert_same_events_after(1, 2, 1500, "restart")
		_assert_clean("restart")


## Case 6: a client several ticks behind keeps snapshots in order and events once each.
func test_6_latency_keeps_snapshots_in_order_and_events_once() -> void:
	for g in GAMES:
		_boot(g)
		_lt(1).latency_ticks = 6
		var seen: Array = []
		_nets[1].game_message.connect(
			func(_from: int, data: Dictionary) -> void:
				var t := str(data.get("type", ""))
				if t == "snapshot" or t == "event":
					seen.append([t, int(data.get("seq", 0))])
		)
		var busy: Array = BUSY[g]
		_to_phase(int(busy[0]), float(busy[1]))
		_step(300)
		var snap_seqs: Array = []
		var event_seqs: Array = []
		for m: Array in seen:
			(snap_seqs if m[0] == "snapshot" else event_seqs).append(m[1])
		assert_gt(snap_seqs.size(), 20, "%s: snapshots arrived" % g)
		for j in range(1, snap_seqs.size()):
			assert_gt(snap_seqs[j], snap_seqs[j - 1], "%s: snapshots in order" % g)
		for j in range(1, event_seqs.size()):
			assert_eq(event_seqs[j], event_seqs[j - 1] + 1, "%s: event batches once each" % g)
		assert_lte(
			_seq(_host, "_snapshot_seq") - _seq(_client(1), "_snap_seq_applied"),
			6,
			"%s: only a few snapshots behind" % g
		)
		_lt(1).latency_ticks = 0
		var level := func() -> bool:
			return _seq(_client(1), "_event_seq_applied") == _seq(_client(2), "_event_seq_applied")
		assert_true(_step_until(level, 100), "%s: the lagging client caught up" % g)
		assert_eq(
			_game_events(_client(1)),
			_game_events(_client(2)),
			"%s: the same game events, once each" % g
		)
		assert_gt(_game_events(_client(1)).size(), 0)
		_assert_clean("latency")


## Case 7: a late join without a token is refused and the session is unharmed.
func test_7_a_late_join_is_refused_and_the_session_is_unharmed() -> void:
	for g in GAMES:
		_boot(g)
		var mid: Array = MID[g]
		_to_phase(int(mid[0]), float(mid[1]))
		var late := _make_net(3)
		_nets.append(late)
		late.join_room(_nets[0].room_code)
		assert_true(
			_step_until(
				func() -> bool:
					late.poll()
					return _refusals.has(3),
				100
			),
			"%s: the late join was answered" % g
		)
		assert_eq(_refusals.get(3), "session_in_progress", "%s: refused" % g)
		assert_false(_clients.has(3), "%s: no GameHost for it" % g)
		var before := _afk.size()
		_step(100)
		assert_eq(_nets[0].peers().size(), 3, "%s: the lobby is the same" % g)
		assert_eq(_afk.size(), before, "%s: nobody went away" % g)
		assert_eq(_host.state, "running")
		for i in [1, 2]:
			assert_eq(_client(i).state, "running")
			assert_eq(_client(i).local_phase_state().index, _host_idx(i), "%s: in step" % g)
		_assert_clean("late join")


## A client's view state: what its module would send as a snapshot, without the keys that count
## calls to snapshot().
func _view(gh: GameHost) -> Dictionary:
	var v := gh.game.snapshot().duplicate(true)
	for k in VIEW_SKIP:
		v.erase(k)
	return v


# --- case 8: hostile input -------------------------------------------------------------------

## What a hostile or broken peer can put in a JSON value.
const HOSTILE: Array = [
	null, true, "x", "", -1, 0, 99999999, 1.5e300, -1.5e300, [], {}, [[]], [null, "a"], {"a": 1}
]
const MUTANTS_PER_GAME := 300


func _paths(v: Variant, prefix: Array, depth: int, out: Array) -> void:
	out.append(prefix)
	if depth == 0:
		return
	if v is Dictionary:
		for k: Variant in (v as Dictionary).keys():
			_paths(v[k], prefix + [k], depth - 1, out)
	elif v is Array and not (v as Array).is_empty():
		var n := (v as Array).size()
		var idx: Array = [0]
		if n > 1:
			idx.append(1)
		if n > 2:
			idx.append(n - 1)
		for i: int in idx:
			_paths(v[i], prefix + [i], depth - 1, out)


## A deep copy of `root` with the value at `path` replaced (`how` >= 0 picks a HOSTILE value),
## erased (-1), truncated to nothing (-2), to one element (-3), to half (-4) or grown to 3000
## elements (-5).
func _mutate(root: Variant, path: Array, how: int) -> Variant:
	var copy: Variant = root.duplicate(true)
	if path.is_empty():
		return copy
	var parent: Variant = copy
	for j in range(path.size() - 1):
		parent = parent[path[j]]
	var key: Variant = path[path.size() - 1]
	var cur: Variant = parent[key]
	match how:
		-1:
			if parent is Dictionary:
				(parent as Dictionary).erase(key)
			else:
				(parent as Array).remove_at(int(key))
		-2, -3, -4, -5:
			if cur is Array:
				var a: Array = cur
				if how == -2:
					a.clear()
				elif how == -3:
					a.resize(mini(a.size(), 1))
				elif how == -4:
					a.resize(int(a.size() * 0.5))
				else:
					for z in 3000:
						a.append(0)
		_:
			parent[key] = (
				(HOSTILE[how] as Variant).duplicate(true)
				if HOSTILE[how] is Array or HOSTILE[how] is Dictionary
				else HOSTILE[how]
			)
	return copy


## Up to `limit` mutants of `root`, a deterministic spread over every path and mutation.
func _mutants(root: Variant, limit: int, depth: int = 3) -> Array:
	var paths: Array = []
	_paths(root, [], depth, paths)
	var all: Array = []
	for p: Array in paths:
		if p.is_empty():
			continue
		for how in range(-5, HOSTILE.size()):
			all.append([p, how])
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var out: Array = []
	while out.size() < limit and not all.is_empty():
		var pick := all.pop_at(rng.randi() % all.size()) as Array
		out.append(_mutate(root, pick[0], int(pick[1])))
	return out


func _non_finite(v: Variant) -> bool:
	if v is float:
		return not is_finite(v)
	if v is Dictionary:
		for k: Variant in (v as Dictionary).keys():
			if _non_finite(v[k]):
				return true
	elif v is Array:
		for e: Variant in v:
			if _non_finite(e):
				return true
	return false


## One event of each type the game sent so far, as a client got it.
func _sample_events(gh: GameHost) -> Array:
	var seen := {}
	var out: Array = []
	for e: Dictionary in _game_events(gh):
		var t := str(e.get("type", ""))
		if not seen.has(t):
			seen[t] = true
			out.append(e.duplicate(true))
	return out


## Case 8a: a client's GameModule fed truncated, mistyped and oversized snapshots and events.
func test_8a_a_client_module_survives_hostile_snapshots_and_events() -> void:
	for g in GAMES:
		_boot(g)
		var busy: Array = BUSY[g]
		_to_phase(int(busy[0]), float(busy[1]))
		_step(200)
		var c := _client(1)
		var peer := c.local_peer()
		var rider := c.local_rider(peer)
		var snap: Dictionary = JSON.parse_string(JSON.stringify(_host.last_snapshot()))
		assert_gt(snap.size(), 0, "%s: a real snapshot to start from" % g)
		var events := _sample_events(_client(2))
		assert_gt(events.size(), 0, "%s: real events to start from" % g)
		var snap_seq := _seq(c, "_snap_seq_applied")
		var event_seq := _seq(c, "_event_seq_applied")
		var errors_before := _script_errors()
		var n := 0
		for m: Dictionary in _mutants(snap, MUTANTS_PER_GAME):
			c.call("_apply_snapshot_state", m)
			n += 1
			if n % 25 == 0:
				c.game.client_predict(0.05, rider.telemetry())
				c.step()
		assert_eq(
			_script_errors(), errors_before, "%s: a hostile snapshot raised a script error" % g
		)
		for st: Variant in [null, 5, "x", [], [1, 2], {}, {"k": []}]:
			c.call("_on_snapshot", {"seq": 1, "tick": -1, "state": st})
			c.set("_snap_seq_applied", 0)
		c.set("_snap_seq_applied", snap_seq)
		for ev: Dictionary in events:
			for m: Dictionary in _mutants(ev, int(float(MUTANTS_PER_GAME) / events.size()) + 10, 2):
				c.set("_event_seq_applied", 0)
				c.call("_on_event", {"seq": 1, "events": [m]})
				n += 1
				if n % 25 == 0:
					c.game.client_predict(0.05, rider.telemetry())
					c.step()
		var roster: Dictionary = JSON.parse_string(JSON.stringify(_host.ctx.roster))
		for m: Dictionary in _mutants(roster, 120, 3):
			c.call("_on_roster", {"riders": m})
			n += 1
			if n % 25 == 0:
				c.step()
		for bad: Variant in [null, 5, "x", [], {"1": 5}, {"x": {}}, {"1": {"raw_w": [1]}}]:
			c.call("_on_roster", {"riders": bad})
		c.step()
		var junk: Array = [
			null, 5, "x", [], {}, {"type": 5}, {"type": ""}, {"type": "no_such_event", "slot": 99}
		]
		var flood: Array = []
		for z in 3000:
			flood.append(events[z % events.size()])
		c.set("_event_seq_applied", 0)
		c.call("_on_event", {"seq": 1, "events": junk})
		c.set("_event_seq_applied", 0)
		c.call("_on_event", {"seq": 1, "events": flood})
		c.set("_event_seq_applied", 0)
		c.call("_on_event", {"seq": 1, "events": "x"})
		c.set("_event_seq_applied", event_seq)
		c.step()
		c.game.client_predict(0.05, rider.telemetry())
		assert_eq(_script_errors(), errors_before, "%s: a hostile event raised a script error" % g)
		# The next real snapshots and events set it right and the next ticks run.
		_step(60)
		assert_eq(_script_errors(), errors_before, "%s: the next ticks" % g)
		var d: Array = []
		_diff(_view(c), _view(_client(2)), float(VIEW_TOL[g]), "view", d)
		assert_eq(d, [], "%s: real snapshots after the hostile ones put the view state right" % g)
		assert_eq(c.state, "running", "%s: still running" % g)


## Hostile intents for `game`: the game's own kinds with every field mistyped, other kinds,
## nesting and size.
func _hostile_intents(kinds: Array) -> Array:
	var fields := [
		"k", "to", "item", "station", "pad", "auto", "via", "dir", "d", "xp", "rec", "cos", "slot"
	]
	var out: Array = []
	for kind: Variant in kinds + [null, 7, "", "no_such_kind"]:
		out.append({"k": kind})
		for f: String in fields:
			for v: Variant in (
				HOSTILE + ["mine", "next", "prev", "diesel", "surge", "auto", -2, 2, 1.5]
			):
				out.append({"k": kind, f: v})
		var many := {"k": kind}
		for z in 40:
			many["f%d" % z] = z
		out.append(many)
	var deep: Variant = {"k": "route"}
	var tail: Dictionary = deep
	for z in 120:
		tail["to"] = {"k": "x"}
		tail = tail["to"]
	out.append_array([null, 5, "x", [], [[]], deep, "y".repeat(100000), {"k": "x".repeat(100000)}])
	return out


const INTENT_KINDS := {
	"fishing": ["spot", "confirm", "summary"],
	"siege": ["route", "buy", "overdrive"],
	"tank": ["seat", "aim", "target", "fire", "latch", "over", "turn"],
	"workout": ["sprint", "surge"],
}


func _inject_telemetry(from: int, tm: Dictionary) -> void:
	_host.call("_authority_message", from, {"type": "telemetry", "tm": tm})


## Case 8b: the host's sim_step given hostile intents and telemetry from a client.
func test_8b_the_host_survives_hostile_intents_and_telemetry() -> void:
	for g in GAMES:
		_boot(g)
		var busy: Array = BUSY[g]
		_to_phase(int(busy[0]), float(busy[1]))
		var peer := _client(1).local_peer()
		var base: Dictionary = _client(1).local_rider(peer).telemetry().to_dict()
		var errors_before := _script_errors()
		var intents := _hostile_intents(INTENT_KINDS[g])
		var i := 0
		while i < intents.size():
			var tm := base.duplicate(true)
			tm["intents"] = intents.slice(i, i + 25)
			_inject_telemetry(peer, tm)
			_step(1)
			i += 25
		assert_eq(_script_errors(), errors_before, "%s: a hostile intent raised a script error" % g)
		# A flood in one message, an intent list that is no list, and unknown seats.
		var flood := base.duplicate(true)
		var one: Array = intents.slice(0, 200)
		var many: Array = []
		for z in 100:
			many.append_array(one)
		flood["intents"] = many
		_inject_telemetry(peer, flood)
		_step(2)
		for bad: Variant in [null, 5, "x", {}, [[]]]:
			var tm := base.duplicate(true)
			tm["intents"] = bad
			_inject_telemetry(peer, tm)
			_step(1)
		for seat in [0, -1, 99, 4096]:
			var tm := base.duplicate(true)
			tm["intents"] = intents.slice(0, 40)
			_inject_telemetry(seat, tm)
		_step(2)
		# The same through the real net (the net session trims and the host reads the rest).
		var tm := base.duplicate(true)
		tm["intents"] = intents.slice(0, 120)
		_nets[1].send_to_host(Protocol.game_msg("telemetry", {"tm": tm}))
		_step(10)
		assert_eq(_script_errors(), errors_before, "%s: hostile intents raised a script error" % g)
		# Mistyped and out-of-range telemetry fields, one at a time.
		for key: Variant in base.keys():
			for v: Variant in [null, "x", [], {}, -1, 1.0e30, 1.0e300, true]:
				var t2 := base.duplicate(true)
				t2[key] = v
				_inject_telemetry(peer, t2)
				_step(1)
		_step(20)
		assert_eq(
			_script_errors(), errors_before, "%s: hostile telemetry raised a script error" % g
		)
		assert_false(_non_finite(_host.last_snapshot()), "%s: the snapshot stays finite" % g)
		assert_eq(_host.state, "running", "%s: the host runs on" % g)
		var snaps := _seq(_client(2), "_snap_seq_applied")
		_step(40)
		assert_gt(_seq(_client(2), "_snap_seq_applied"), snaps, "%s: snapshots keep coming" % g)
		assert_eq(_script_errors(), errors_before)
