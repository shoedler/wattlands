class_name QaScreenshotSession
extends RefCounted
## tools/screenshot --app-screen=session: the app's real session screen (AppSessionScreen) in a
## windowed run, so the HUD, the on-screen panic button and the session overlay show together
## as a rider sees them (BRIEF 3.9, 4.6.5, 7.8). Owned by qa; driven by
## tools/qa/screenshot_main.gd.
##   --app-role=client (default): the app joins a room that an in-process, headless host opens
##     over a LoopbackTransport hub (the app's NetSession uses the hub too). The app's lobby
##     screen joins with the code, readies on pedal_start, and opens the CLIENT session from the
##     host GameHost's session_start, so the HUD is built from session_start.
##   --app-role=host: the app's lobby hosts; an in-process headless client joins, readies, and
##     runs a CLIENT GameHost from the app's session_start.
##   --app-role=solo: the app's solo quick start.
## --app-game (default workout), --content (default the game's e2e_content, else its
## default_content), --at=<s>: shots once the app's session reached these platform seconds
## (default 30). --app-overlay=menu (default) | panic | none: after the last --at, one more
## shot with the session menu (or the panic overlay) open. The app reads --sim-speed itself
## (CmdLine); the in-process peer runs at the same speed. The app's profile is "Rider"
## (FTP 200), the other peer "Guest" (FTP 180), both on --mock-trainer.
## Prints one "screenshot: session ..." line per shot with the panic button's rect, the HUD's
## reserved bottom-right corner, that corner's stack and whether they overlap.

const DEFAULT_AT := 30.0
const PEER_FTP := 180.0
const PEER_NAME := "Guest"
const APP_NAME := "Rider"
const WAIT_NET_MS := 15000
const WAIT_START_MS := 60000

var tree: SceneTree = null
var main: Node = null
var app: WlApp = null
var opts: Dictionary = {}
var error: String = ""
var role: String = "client"
var game_id: String = "workout"
var content_id: String = ""
var sim_speed: float = 1.0

var _hub: RefCounted = null
var _holder: Node = null
var _peer_net: WlNetSession = null
var _peer_host: GameHost = null
var _peer_rider: LocalRider = null
var _peer_device: MockTrainer = null
var _peer_bus: WlEventBus = null
var _registry: WlGameRegistry = null


static func create(p_tree: SceneTree, p_main: Node, p_app: WlApp, p_opts: Dictionary) -> QaScreenshotSession:
	var s := QaScreenshotSession.new()
	s.tree = p_tree
	s.main = p_main
	s.app = p_app
	s.opts = p_opts
	s.role = str(p_opts.get("app_role", "client"))
	s.game_id = str(p_opts.get("app_game", "workout"))
	s.content_id = str(p_opts.get("content", ""))
	s.sim_speed = maxf(CmdLine.get_float("sim-speed", 1.0), 0.01)
	return s


## The app's session screen once its GameHost runs (null with `error` set).
func start() -> AppSessionScreen:
	_registry = tree.root.get_node_or_null(^"GameRegistry") as WlGameRegistry
	if _registry == null or not _registry.has_game(game_id):
		error = "unknown game %s" % game_id
		return null
	var m := _registry.manifest(game_id)
	if content_id == "":
		content_id = str(m.get("e2e_content", m.get("default_content", "")))
	var settings := tree.root.get_node_or_null(^"Settings") as WlSettings
	if settings != null and not settings.has_profile():
		settings.create_profile(APP_NAME)
	_holder = Node.new()
	_holder.name = "ScreenshotPeer"
	_holder.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(_holder)
	var ok := false
	match role:
		"solo":
			app.goto("session", {"role": Wl.SOLO, "game_id": game_id, "content_id": content_id, "quick": true})
			ok = true
		"client":
			ok = await _start_as_client()
		"host":
			ok = await _start_as_host()
		_:
			error = "--app-role must be client, host or solo"
	if not ok:
		return null
	if not await _wait(func() -> bool: return _session() != null and _session().host != null, WAIT_START_MS):
		error = "the app never opened its session screen (%s)" % role
		return null
	return _session()


## Platform seconds of the app's session (0 before its GameHost has a clock).
func session_seconds() -> float:
	var s := _session()
	if s == null or s.host == null or not is_instance_valid(s.host) or s.host.clock == null:
		return 0.0
	return s.host.clock.platform_time()


## Wait (rendering frames) until the app's session reached `at` platform seconds.
func advance_to(at: float) -> bool:
	var limit_ms := int((at / sim_speed + 60.0) * 1000.0)
	return await _wait(func() -> bool: return session_seconds() + 1e-6 >= at or _session() == null, limit_ms) and _session() != null


## One line for the run log: the panic button, the HUD's reserved corner and its stack.
func describe(screen: AppSessionScreen) -> String:
	var hud: HudLayer = screen.host.hud_layer() if screen.host != null else null
	if hud == null:
		return "screenshot: session %s: no HUD (headless?)" % role
	var pb := screen.panic_button.get_global_rect()
	var reserved := hud.reserved_corner(HudSpec.BOTTOM_RIGHT)
	var box := hud.anchor_box(HudSpec.BOTTOM_RIGHT)
	var box_rect := box.get_global_rect() if box != null and box.visible else Rect2()
	var overlap := box_rect.has_area() and box_rect.intersects(pb)
	return "screenshot: session %s at %.1f s: panic button %s, reserved bottom-right %s, bottom-right stack %s, overlap %s, top layer %d above HUD layer %d" % [
		role, session_seconds(), _rect_text(pb), reserved, _rect_text(box_rect), overlap, screen.top_layer.layer, hud.layer]


func cleanup() -> void:
	if _peer_host != null and is_instance_valid(_peer_host):
		_peer_host.set_process(false)
	if _holder != null and is_instance_valid(_holder):
		_holder.queue_free()


# --- the app as a client of an in-process host ------------------------------------------------

func _start_as_client() -> bool:
	var app_net := tree.root.get_node_or_null(^"NetSession") as WlNetSession
	if app_net == null:
		error = "the NetSession autoload is missing"
		return false
	_hub = LoopbackTransport.create_hub()
	app_net.use_transport(LoopbackTransport.hub_transport(_hub))
	_peer_net = _new_peer_net()
	var m := _registry.manifest(game_id)
	_peer_net.set_local_player_info(_peer_info())
	_peer_net.host_room(AppLobbyModel.max_players(m))
	if not await _wait(func() -> bool: return _peer_net.room_code != "" and _peer_net.local_peer != 0, WAIT_NET_MS):
		error = "the in-process host never opened a room"
		return false
	_peer_net.set_game(game_id, str(m.get("version", "")), content_id)
	_peer_net.set_scaling(Wl.FAIR_FTP)
	_peer_net.set_setting("options", AppLobbyModel.resolve_game_options(_registry, game_id, {}))
	_peer_net.set_ready(true)
	app.goto("lobby", {"mode": "join"})
	var lobby := _screen() as AppLobbyScreen
	if lobby == null:
		error = "the app did not open its lobby"
		return false
	lobby.join_code(_peer_net.room_code)
	if not await _wait(func() -> bool: return lobby.page == AppLobbyScreen.PAGE_LOBBY and lobby.current_game() == game_id, WAIT_NET_MS):
		error = "the app never joined room %s" % _peer_net.room_code
		return false
	# A rider readies with pedal_start (the mock pedals in the menus); feed it so the run
	# doesn't depend on the menu rider's timing.
	lobby.feed_gesture(Wl.G_PEDAL_START)
	if not await _wait(func() -> bool: return _peer_net.peers().size() == 2 and _peer_net.all_ready(), WAIT_NET_MS):
		error = "the app never readied in the host's lobby"
		return false
	_peer_net.mark_started()
	var players := _peer_net.lobby_slots()
	var mine := _slot_of(players, _peer_net.local_peer)
	if mine == null:
		error = "the host's own slot is missing"
		return false
	_make_peer_rider(mine)
	_peer_host = GameHost.new()
	_peer_host.name = "PeerHost"
	_peer_host.process_mode = Node.PROCESS_MODE_ALWAYS
	_holder.add_child(_peer_host)
	var err := _peer_host.setup({
		"game_id": game_id, "content_id": content_id, "seed": CmdLine.get_int("seed", 7), "role": Wl.HOST,
		"players": players, "local_riders": {_peer_net.local_peer: _peer_rider}, "local_peer": _peer_net.local_peer,
		"net": _peer_net, "bus": _peer_bus, "registry": _registry,
		"options": AppLobbyModel.resolve_game_options(_registry, game_id, {}), "scaling_mode": Wl.FAIR_FTP,
		"sim_speed": sim_speed, "headless": true, "realtime": true, "record_rides": false, "report": false,
		"input_router": null,
	})
	if err != "":
		error = "the in-process host failed to set up: %s" % err
		return false
	_peer_host.start()
	return true


# --- the app as the host of an in-process client ------------------------------------------------

func _start_as_host() -> bool:
	var app_net := tree.root.get_node_or_null(^"NetSession") as WlNetSession
	if app_net == null:
		error = "the NetSession autoload is missing"
		return false
	_hub = LoopbackTransport.create_hub()
	app_net.use_transport(LoopbackTransport.hub_transport(_hub))
	app.goto("lobby", {"mode": "host", "game_id": game_id})
	var lobby := _screen() as AppLobbyScreen
	if lobby == null:
		error = "the app did not open its lobby"
		return false
	if not await _wait(func() -> bool: return app_net.room_code != "", WAIT_NET_MS):
		error = "the app never opened a room"
		return false
	lobby.set_content(content_id)
	_peer_net = _new_peer_net()
	_peer_net.set_local_player_info(_peer_info())
	_peer_net.game_message.connect(_on_peer_message)
	_peer_net.join_room(app_net.room_code)
	if not await _wait(func() -> bool: return _peer_net.local_peer != 0 and str(_peer_net.lobby.get("game_id", "")) == game_id, WAIT_NET_MS):
		error = "the in-process client never joined room %s" % app_net.room_code
		return false
	_peer_net.set_local_player_info(_peer_info())
	_peer_net.set_ready(true)
	if not await _wait(func() -> bool: return app_net.peers().size() == 2, WAIT_NET_MS):
		error = "the app's lobby never listed the in-process client"
		return false
	lobby.pick_id("start")
	return true


func _on_peer_message(from: int, data: Dictionary) -> void:
	if str(data.get("type", "")) != "session_start" or _peer_host != null:
		return
	var players: Array[PlayerSlot] = []
	for p: Variant in data.get("players", []):
		if p is Dictionary:
			players.append(PlayerSlot.from_dict(p as Dictionary))
	var mine := _slot_of(players, _peer_net.local_peer)
	if mine == null:
		push_warning("screenshot: the session_start has no slot for the in-process client")
		return
	_make_peer_rider(mine)
	_peer_host = GameHost.new()
	_peer_host.name = "PeerClient"
	_peer_host.process_mode = Node.PROCESS_MODE_ALWAYS
	_holder.add_child(_peer_host)
	var err := _peer_host.setup({
		"role": Wl.CLIENT, "local_peer": _peer_net.local_peer, "local_riders": {_peer_net.local_peer: _peer_rider},
		"net": _peer_net, "bus": _peer_bus, "registry": _registry, "sim_speed": sim_speed,
		"headless": true, "realtime": true, "record_rides": false, "report": false, "input_router": null,
		"session_start": data.duplicate(true),
	})
	if err != "":
		push_warning("screenshot: the in-process client failed to set up: %s" % err)
		return
	_peer_host.start()
	# The GameHost listens from setup() on; hand it the message that made it.
	_peer_net.game_message.emit(from, data)


# --- helpers ----------------------------------------------------------------------------------

func _new_peer_net() -> WlNetSession:
	var n := WlNetSession.new()
	n.name = "PeerNet"
	_holder.add_child(n)
	n.auto_poll = true
	n.use_transport(LoopbackTransport.hub_transport(_hub))
	_peer_bus = WlEventBus.new()
	_peer_bus.name = "PeerBus"
	_holder.add_child(_peer_bus)
	return n


func _peer_profile() -> RiderProfile:
	var p := RiderProfile.new()
	p.display_name = PEER_NAME
	p.ftp_w = PEER_FTP
	p.cp_w = PEER_FTP
	p.ftp_verified = true
	p.created = true
	return p


func _peer_info() -> Dictionary:
	return AppLobbyModel.player_info(_peer_profile(), Wl.FAIR_FTP, AppLobbyModel.resolve_player_options(_registry, game_id, {}),
		AppLobbyModel.installed_games(_registry), TrainerDevice.STATUS_READY)


func _make_peer_rider(slot: PlayerSlot) -> void:
	_peer_device = MockTrainer.from_spec(str(opts.get("mock_trainer", QaScreenshotOptions.DEFAULT_MOCK)), slot.ftp, {"seed": 11})
	_peer_rider = LocalRider.new()
	_peer_rider.name = "PeerRider"
	_holder.add_child(_peer_rider)
	_peer_rider.add_child(_peer_device)
	_peer_rider.setup(slot.peer_id, _peer_profile(), slot, _peer_device, {
		"multiplayer": true, "scaling_mode": Wl.FAIR_FTP, "record": false, "game_id": game_id,
		"content_id": content_id, "seed": 11, "bus": _peer_bus,
	})


static func _slot_of(players: Array[PlayerSlot], peer: int) -> PlayerSlot:
	for s in players:
		if s.peer_id == peer:
			return s
	return null


func _screen() -> AppScreen:
	return main.get("screen") as AppScreen if main != null and is_instance_valid(main) else null


func _session() -> AppSessionScreen:
	return _screen() as AppSessionScreen


## Render frames until `done` is true or `limit_ms` of wall time passed.
func _wait(done: Callable, limit_ms: int) -> bool:
	var until := Time.get_ticks_msec() + limit_ms
	while not done.call():
		if Time.get_ticks_msec() > until:
			return false
		await tree.process_frame
	return true


static func _rect_text(r: Rect2) -> String:
	return "(%d, %d %dx%d)" % [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]
