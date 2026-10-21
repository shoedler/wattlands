extends GutTest
## W2 (qa W1: in the real e2e run both clients stayed in the lobby after the host printed
## `running`): a host and two client GameHosts over the real WlNetSession and LoopbackTransport,
## started exactly as the app shell starts them (src/app/session_launcher.gd,
## src/app/scripted/scripted_peer.gd). The host marks its net started, then sets up and starts
## its GameHost from the lobby's slots. Each client creates its GameHost inside the
## game_message emission of `session_start`, with that message as config.session_start, so the
## GameHost never sees it on the net; `plan` and `phase` follow on the net (BRIEF 3.6, 5.5;
## docs/OWNERSHIP.md GM2, GM22, CTX1, CTX8, PS14, PL21).

const FIXTURES := "res://tests/fixtures/games"
const GAME := "fx_solo"

var _root: Node = null
var _reg: WlGameRegistry = null
var _nets: Array[WlNetSession] = []
var _buses: Array[WlEventBus] = []
## net index (1, 2) -> client GameHost, created when session_start arrives.
var _clients: Dictionary = {}
## net index -> the GameHost's state right after setup() (before its first step).
var _created_state: Dictionary = {}
var _host: GameHost = null
var _tmp: String = ""


func before_each() -> void:
	_root = Node.new()
	add_child_autofree(_root)
	_nets.clear()
	_buses.clear()
	_clients.clear()
	_created_state.clear()
	_host = null
	_tmp = Paths.make_temp_dir("wattlands_client_start")
	Paths.set_override(_tmp)
	_reg = WlGameRegistry.new()
	_reg.scan_on_ready = false
	_reg.content_root = FIXTURES.path_join("_content")
	_root.add_child(_reg)
	_reg.scan(FIXTURES.path_join("runtime"))


func after_each() -> void:
	Paths.set_override("")
	GameSimRunner._remove_tree(_tmp)


func _pump(done: Callable, max_iter: int = 400) -> bool:
	for k in max_iter:
		for n in _nets:
			n.poll()
		if done.call():
			return true
	return false


## Host, two joined clients and one bot in the host's lobby, game fx_solo/tiny, speed 4.
func _lobby() -> void:
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
	host_net.set_game(GAME, str(_reg.manifest(GAME)["version"]), "tiny")
	host_net.set_setting("options", {"speed": 4})
	assert_true(host_net.add_bot())
	for i in [1, 2]:
		_nets[i].join_room(host_net.room_code)
		var cn := _nets[i]
		assert_true(_pump(func() -> bool: return cn.local_peer != 0))
		cn.game_message.connect(_on_client_message.bind(i))
	assert_true(_pump(func() -> bool: return host_net.peers().size() == 3))
	assert_true(
		_pump(func() -> bool: return (_nets[2].lobby.get("players", []) as Array).size() == 4)
	)


static func _rider(parent: Node, slot: PlayerSlot, multiplayer: bool) -> LocalRider:
	var dev := MockTrainer.from_spec("erg", slot.ftp, {"seed": 11 + slot.slot_index})
	var r := LocalRider.new()
	r.name = "Rider%d" % slot.peer_id
	r.setup(
		slot.peer_id,
		null,
		slot,
		dev,
		{"multiplayer": multiplayer, "scaling_mode": slot.scaling_mode, "record": false}
	)
	r.add_child(dev)
	parent.add_child(r)
	return r


## The app shell's host side: mark_started, then a GameHost from the lobby's slots.
func _start_host() -> void:
	var net := _nets[0]
	net.mark_started()
	var players := net.lobby_slots()
	var riders := {}
	for p in players:
		if p.peer_id == net.local_peer or p.is_bot:
			riders[p.peer_id] = _rider(_root, p, true)
	_host = GameHost.new()
	_host.name = "Host"
	_root.add_child(_host)
	assert_eq(
		(
			_host
			. setup(
				{
					"game_id": GAME,
					"content_id": "tiny",
					"seed": 9,
					"role": Wl.HOST,
					"players": players,
					"local_riders": riders,
					"local_peer": net.local_peer,
					"net": net,
					"bus": _buses[0],
					"registry": _reg,
					"options": {"speed": 4},
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


## The app shell's client side: the GameHost is made inside session_start's emission.
func _on_client_message(_from: int, data: Dictionary, i: int) -> void:
	if str(data.get("type", "")) != "session_start" or _clients.has(i):
		return
	var net := _nets[i]
	var slot: PlayerSlot = null
	for pd: Variant in data.get("players", []):
		var p := PlayerSlot.from_dict(pd as Dictionary)
		if p.peer_id == net.local_peer:
			slot = p
	assert_not_null(slot, "session_start lists the client's own slot")
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
	gh.start()
	_created_state[i] = gh.state
	_clients[i] = gh


func _step(n: int) -> void:
	for k in n:
		_host.step()
		for i in [1, 2]:
			if _clients.has(i):
				(_clients[i] as GameHost).step()
			else:
				_nets[i].poll()


func test_clients_started_like_the_app_shell_run_the_session() -> void:
	_lobby()
	_start_host()
	_step(20)
	assert_eq(_clients.size(), 2, "both clients made their GameHost on session_start")
	for i in [1, 2]:
		var gh: GameHost = _clients[i]
		var peer := gh.local_peer()
		assert_eq(_created_state[i], "setup", "made before its first step")
		assert_eq(gh.state, "running", "client %d left the lobby" % peer)
		assert_true(gh.plans.has(peer), "client %d got its plan" % peer)
		assert_gt(gh.local_phase_state().index, -1, "client %d got its phase" % peer)
		var rider: LocalRider = gh.local_rider(peer)
		assert_eq(rider.telemetry().mode, Wl.ERG, "client %d's governor follows the plan" % peer)
		assert_eq(gh.ctx.players.size(), 4, "every slot, the bot included")
		assert_eq(gh.ctx.options["speed"], 4)
		assert_typeof(gh.ctx.options["speed"], TYPE_INT, "int options stay ints after JSON")
		for p in gh.ctx.players:
			assert_typeof(
				p.options["offset"],
				TYPE_INT,
				"player option of peer %d on client %d" % [p.peer_id, peer]
			)
			assert_eq(
				p.peer_id, _host.ctx.players[p.slot_index].peer_id, "same slot order as the host"
			)
	# Run the session out; the clients get the results.
	var guard := 0
	while guard < 6000 and not (_clients[1] as GameHost).is_finished():
		_step(1)
		guard += 1
	_step(20)
	assert_not_null(_host.final_results())
	var riders: Array[int] = []
	for p in _host.ctx.players:
		riders.append(p.peer_id)
	for i in [1, 2]:
		var gh: GameHost = _clients[i]
		assert_not_null(gh.final_results(), "client %d got the results" % gh.local_peer())
		assert_eq(gh.game.get("progress_calls"), 1)
		var seen := {}
		for e: Dictionary in gh.report_data()["events"]:
			if str(e["type"]) == "phase_started":
				seen[int(e["peer"])] = true
		for peer in riders:
			assert_true(
				seen.has(peer),
				"client %d recorded phase_started for rider %d" % [gh.local_peer(), peer]
			)


func test_a_session_start_that_also_arrives_on_the_net_configures_once() -> void:
	_lobby()
	_start_host()
	_step(5)
	var gh: GameHost = _clients[1]
	var game: GameModule = gh.game
	var configured: int = game.get("configure_count")
	# The app shell re-emits the opening message after start() (a rejoin replay does the same).
	var ss := Protocol.game_msg("session_start", {"game_id": GAME, "game": GAME})
	_nets[1].game_message.emit(_nets[1].host_peer, ss)
	_step(2)
	assert_eq(gh.game, game, "the same GameModule")
	assert_eq(game.get("configure_count"), configured, "configure() ran once")
	assert_eq(gh.state, "running")
