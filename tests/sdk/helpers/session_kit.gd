extends RefCounted
## Builders for sdk-runtime tests: a fixture registry, slots, fake riders and GameHost
## sessions (SOLO, or HOST with FakeNet clients). Every node is added under `parent`, which
## the test frees (add_child_autofree), so nothing leaks between tests.

const FakeRider := preload("res://tests/sdk/helpers/fake_rider.gd")
const FakeNetHub := preload("res://tests/sdk/helpers/fake_net_hub.gd")
const RecordingMock := preload("res://tests/sdk/helpers/recording_mock.gd")
const FIXTURES := "res://tests/fixtures/games"


static func registry(parent: Node = null) -> WlGameRegistry:
	var r := WlGameRegistry.new()
	r.scan_on_ready = false
	r.content_root = FIXTURES.path_join("_content")
	if parent != null:
		parent.add_child(r)
	r.scan(FIXTURES.path_join("runtime"))
	return r


static func human(peer: int, idx: int, ftp: float = 200.0) -> PlayerSlot:
	var s := PlayerSlot.new()
	s.peer_id = peer
	s.name = "Rider %d" % (idx + 1)
	s.apply_look(idx)
	s.ftp = ftp
	s.ftp_verified = true
	s.p_eff_per_w = EffortScaling.p_eff_per_w(Wl.FAIR_FTP, ftp, 75.0)
	return s


## A fake LocalRider with a real MockTrainer that records its bands (recording_mock.gd).
static func rider(parent: Node, slot: PlayerSlot) -> LocalRider:
	var r: LocalRider = FakeRider.new()
	var dev: MockTrainer = RecordingMock.new()
	r.setup(slot.peer_id, null, slot, dev, {})
	r.add_child(dev)
	r.name = "Rider%d" % slot.slot_index
	parent.add_child(r)
	return r


static func new_bus(parent: Node, bus_name: String) -> WlEventBus:
	var b := WlEventBus.new()
	b.name = bus_name
	parent.add_child(b)
	return b


## A SOLO session of fx_solo: one human (peer 1) and `bots` bots. Returns {host, err, game,
## riders, bus, registry, tmp}. `extra` keys override the GameHost config.
static func solo(
	parent: Node,
	content: String = "tiny",
	extra: Dictionary = {},
	bots: int = 0,
	game_id: String = "fx_solo"
) -> Dictionary:
	var reg := registry(parent)
	var tmp := Paths.make_temp_dir("wattlands_sdk_test")
	var players: Array[PlayerSlot] = [human(1, 0)]
	for n in range(1, bots + 1):
		players.append(Bots.make_slot(n, n, 200.0))
	var riders := {}
	for p in players:
		riders[p.peer_id] = rider(parent, p)
	(riders[1] as LocalRider).set("ride_dir", tmp.path_join("rides1"))
	var bus := new_bus(parent, "SoloBus")
	var host := GameHost.new()
	host.name = "SoloHost"
	parent.add_child(host)
	var cfg := {
		"game_id": game_id,
		"content_id": content,
		"seed": 7,
		"role": Wl.SOLO,
		"players": players,
		"local_riders": riders,
		"local_peer": 1,
		"bus": bus,
		"registry": reg,
		"headless": true,
		"realtime": false,
		"report": true,
		"progress_path": tmp.path_join("p1/games/%s/progress.json" % game_id),
	}
	for k: Variant in extra.keys():
		cfg[k] = extra[k]
	var err := host.setup(cfg)
	return {
		"host": host,
		"err": err,
		"game": host.game,
		"riders": riders,
		"bus": bus,
		"registry": reg,
		"tmp": tmp
	}


## A HOST session of fx_solo with `humans` human peers (1 = the host, 2.. clients over
## FakeNet) and `bots` bots. Returns {host, clients, hub, nets, riders, buses, game,
## registry, tmp, err}. Client GameHosts are set up (they wait for session_start).
static func multi(
	parent: Node,
	humans: int,
	content: String = "tiny",
	extra: Dictionary = {},
	bots: int = 0,
	game_id: String = "fx_solo"
) -> Dictionary:
	var reg := registry(parent)
	var tmp := Paths.make_temp_dir("wattlands_sdk_test")
	var hub: RefCounted = FakeNetHub.new()
	var nets: Array[WlNetSession] = []
	for i in humans:
		var s: WlNetSession = hub.call("add", i + 1)
		s.name = "Net%d" % (i + 1)
		parent.add_child(s)
		nets.append(s)
	var players: Array[PlayerSlot] = []
	for i in humans:
		players.append(human(i + 1, i, 180.0 + 20.0 * i))
	for n in range(1, bots + 1):
		players.append(Bots.make_slot(n, humans + n - 1, 200.0))
	var riders := {}
	for p in players:
		riders[p.peer_id] = rider(parent, p)
		if not p.is_bot:
			(riders[p.peer_id] as LocalRider).set("ride_dir", tmp.path_join("rides%d" % p.peer_id))
	var buses: Array[WlEventBus] = [new_bus(parent, "HostBus")]
	var host := GameHost.new()
	host.name = "Host"
	parent.add_child(host)
	var host_riders := {1: riders[1]}
	for p in players:
		if p.is_bot:
			host_riders[p.peer_id] = riders[p.peer_id]
	var cfg := {
		"game_id": game_id,
		"content_id": content,
		"seed": 7,
		"role": Wl.HOST,
		"players": players,
		"local_riders": host_riders,
		"local_peer": 1,
		"net": nets[0],
		"bus": buses[0],
		"registry": reg,
		"headless": true,
		"realtime": false,
		"report": true,
		"progress_path": tmp.path_join("p1/games/%s/progress.json" % game_id),
	}
	for k: Variant in extra.keys():
		cfg[k] = extra[k]
	var err := host.setup(cfg)
	var clients: Array[GameHost] = []
	for i in range(1, humans):
		var peer := i + 1
		var b := new_bus(parent, "ClientBus%d" % peer)
		buses.append(b)
		var c := GameHost.new()
		c.name = "Client%d" % peer
		parent.add_child(c)
		var cerr := (
			c
			. setup(
				{
					"role": Wl.CLIENT,
					"local_peer": peer,
					"local_riders": {peer: riders[peer]},
					"net": nets[i],
					"bus": b,
					"registry": reg,
					"headless": true,
					"realtime": false,
					"report": true,
					"progress_path": tmp.path_join("p%d/games/%s/progress.json" % [peer, game_id]),
				}
			)
		)
		if cerr != "" and err == "":
			err = "client %d: %s" % [peer, cerr]
		clients.append(c)
	return {
		"host": host,
		"clients": clients,
		"hub": hub,
		"nets": nets,
		"riders": riders,
		"buses": buses,
		"game": host.game,
		"registry": reg,
		"tmp": tmp,
		"err": err,
	}


## Step every GameHost of a session bundle `n` times (host first, then clients).
static func step(bundle: Dictionary, n: int = 1) -> void:
	var host: GameHost = bundle["host"]
	var clients: Array = bundle.get("clients", [])
	for k in n:
		host.step()
		for c: Variant in clients:
			(c as GameHost).step()


static func start(bundle: Dictionary) -> void:
	(bundle["host"] as GameHost).start()
	for c: Variant in bundle.get("clients", []):
		(c as GameHost).start()


## Step until `cond` (a Callable returning bool) holds or `max_steps` pass. Returns the
## number of steps taken (max_steps + 1 when it never held).
static func step_until(bundle: Dictionary, cond: Callable, max_steps: int) -> int:
	for k in max_steps:
		if cond.call():
			return k
		step(bundle)
	return max_steps + 1 if not cond.call() else max_steps


static func remove_tree(dir: String) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.include_hidden = true
	for f in da.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in da.get_directories():
		remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)
