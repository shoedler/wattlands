class_name AppSessionScreen
extends AppScreen
## A running session (BRIEF 3.6, 3.9, 4.6.5). Creates the GameHost with the lobby's players
## (NetSession.lobby_slots()), local riders (TrainerService.local_rider() plus a LocalRider per
## bot on the host, MockTrainer.from_spec(Bots.RIDER_SPEC, bot FTP)), the net session, the
## options and the scaling mode (AppSessionLauncher). The GameHost places the game's view in
## its PixelViewport (2D) or the 3D root inside `view_layer` and its HudLayer in `hud_layer`.
## On top: a pause overlay with its own pedal-scan menu, and an always-visible on-screen panic
## button (EventBus.panic_requested plus LocalRider.panic(): the governor goes safe at once).
## params: role (Wl.SOLO/HOST/CLIENT), game_id, content_id, quick (solo zero-touch start: set
## up the offline lobby here), session_start (CLIENT), rejoin + replay (a restarted client:
## messages that arrived before the GameHost existed are re-emitted to it).

var role: String = Wl.SOLO
var host: GameHost = null
var launcher: AppSessionLauncher = null
var config: Dictionary = {}
var view_layer: Control = null
var hud_layer: Control = null
var overlay: CenterContainer = null
var overlay_title: Label = null
var overlay_detail: Label = null
var panic_button: Button = null
var error_label: Label = null
var error: String = ""
var finished: bool = false
var panicked: bool = false
var paused: bool = false
var pause_reason: String = ""
var results: GameResults = null
var unlocks: Array = []
var ride_summary: Dictionary = {}
var fit_path: String = ""
var host_left: bool = false
var headless: bool = false
var _overlay_menu_open: bool = false


func _build() -> void:
	role = str(params.get("role", Wl.SOLO))
	headless = DisplayServer.get_name() == "headless"
	add_child(AppStyle.background(Color.BLACK))
	view_layer = Control.new()
	view_layer.name = "View"
	view_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view_layer)
	hud_layer = Control.new()
	hud_layer.name = "Hud"
	hud_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud_layer)
	_build_overlay()
	_build_panic_button()
	_connect_bus()
	if role == Wl.SOLO and bool(params.get("quick", false)):
		_prepare_offline_lobby()
	launcher = AppSessionLauncher.create(services)
	config = launcher.build_config(role, params, view_layer, hud_layer, headless)
	if config.is_empty():
		_fail(launcher.error)
		return
	if role == Wl.HOST and services.net != null:
		services.net.mark_started()
	host = services.make_game_host()
	host.name = "GameHost"
	host.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(host)
	var err := host.setup(config)
	if err != "":
		_fail(err)
		return
	host.state_changed.connect(_on_host_state)
	host.session_finished.connect(_on_session_finished)
	services.set_menu_ticking(false)
	host.start()
	for r: Variant in params.get("replay", []):
		if r is Dictionary and services.net != null:
			services.net.game_message.emit(int((r as Dictionary).get("from", Wl.HOST_PEER)), (r as Dictionary).get("data", {}))


func _on_leave() -> void:
	_disconnect_bus()
	services.set_menu_ticking(true)
	if host != null and is_instance_valid(host):
		if host.state_changed.is_connected(_on_host_state):
			host.state_changed.disconnect(_on_host_state)
		if host.session_finished.is_connected(_on_session_finished):
			host.session_finished.disconnect(_on_session_finished)
	if launcher != null:
		launcher.release.call_deferred()


## Solo quick start (zero-touch): the offline lobby the menus would have set up.
func _prepare_offline_lobby() -> void:
	var net := services.net
	if net == null:
		return
	var gid := str(params.get("game_id", ""))
	var m: Dictionary = services.registry.manifest(gid) if services.registry != null else {}
	var sc := str(services.settings.get_value("scaling_mode", Wl.FAIR_FTP)) if services.settings != null else Wl.FAIR_FTP
	if not Wl.SCALING_MODES.has(sc):
		sc = Wl.FAIR_FTP
	net.start_offline()
	net.set_game(gid, str(m.get("version", "")), str(params.get("content_id", "")))
	net.set_scaling(sc)
	net.set_setting("options", AppLobbyModel.resolve_game_options(services.registry, gid, {}))
	var popts := AppLobbyModel.resolve_player_options(services.registry, gid, {})
	var st := services.trainer.status() if services.trainer != null else ""
	net.set_local_player_info(AppLobbyModel.player_info(services.profile(), sc, popts, AppLobbyModel.installed_games(services.registry), st))
	net.set_ready(true)


func local_peer() -> int:
	return int(config.get("local_peer", Wl.HOST_PEER))


func local_rider() -> LocalRider:
	var riders: Dictionary = config.get("local_riders", {})
	return riders.get(local_peer(), null)


# --- overlay and panic -------------------------------------------------------------------------

func _build_overlay() -> void:
	overlay = CenterContainer.new()
	overlay.name = "PauseOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	add_child(overlay)
	var panel := AppStyle.panel(Color(0, 0, 0, 0.82))
	panel.custom_minimum_size = Vector2(1100, 560)
	overlay.add_child(panel)
	var box := AppStyle.vbox(16)
	panel.add_child(box)
	overlay_title = AppStyle.label("", AppStyle.FONT_TITLE, AppStyle.ACCENT)
	box.add_child(overlay_title)
	overlay_detail = AppStyle.paragraph("", AppStyle.FONT_BODY, AppStyle.TEXT)
	box.add_child(overlay_detail)
	var holder := AppStyle.vbox(8)
	holder.name = "OverlayMenu"
	box.add_child(holder)
	set_menu_holder(holder)
	error_label = AppStyle.paragraph("", AppStyle.FONT_HEADING, AppStyle.BAD)
	error_label.name = "Error"
	error_label.visible = false
	box.add_child(error_label)


func _build_panic_button() -> void:
	panic_button = Button.new()
	panic_button.name = "Panic"
	panic_button.text = t("APP_PANIC")
	panic_button.add_theme_font_size_override("font_size", AppStyle.FONT_HEADING)
	panic_button.focus_mode = Control.FOCUS_NONE
	panic_button.custom_minimum_size = Vector2(380, 100)
	add_child(panic_button)
	panic_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panic_button.offset_left = -420.0
	panic_button.offset_top = -130.0
	panic_button.offset_right = -40.0
	panic_button.offset_bottom = -30.0
	panic_button.pressed.connect(panic)


## On-screen panic (BRIEF 4.6.5): ERG off, SIM grade 0 and wind 0 at once, through the
## governor; stays safe until the rider resumes.
func panic() -> void:
	panicked = true
	if services.bus != null:
		services.bus.panic_requested.emit()
	var r := local_rider()
	if r != null:
		r.panic()
	_show_overlay()


## Leave the panic state (the governor resumes from the floor with slew).
func resume_trainer() -> void:
	panicked = false
	var r := local_rider()
	if r != null and r.governor != null:
		r.governor.resume()
	_show_overlay()


func open_menu() -> void:
	_show_overlay(true)


func _show_overlay(force_menu: bool = false) -> void:
	var show := force_menu or panicked or paused or error != "" or _overlay_menu_open
	overlay.visible = show
	if not show:
		if _overlay_menu_open:
			clear_menus()
			_overlay_menu_open = false
		return
	if error != "":
		overlay_title.text = t("APP_SESSION_ERROR_TITLE")
		overlay_detail.text = ""
	elif panicked:
		overlay_title.text = t("APP_SESSION_PANIC_TITLE")
		overlay_detail.text = t("APP_SESSION_PANIC_DETAIL")
	elif paused:
		overlay_title.text = t("APP_SESSION_PAUSED")
		overlay_detail.text = t("APP_SESSION_PAUSED_DETAIL").format([pause_reason])
	else:
		overlay_title.text = t("APP_SESSION_MENU")
		overlay_detail.text = ""
	var items := overlay_items()
	if not _overlay_menu_open:
		_overlay_menu_open = true
		push_menu(items, _on_overlay_pick, _on_overlay_back)
	else:
		refresh_menu(items, menus[0])


func overlay_items() -> Array:
	var items: Array = []
	if error != "":
		items.append({"id": "leave", "text": t("APP_BACK")})
		return items
	if panicked:
		items.append({"id": "resume_trainer", "text": t("APP_SESSION_RESUME_TRAINER")})
	else:
		items.append({"id": "resume", "text": t("APP_SESSION_RESUME")})
		items.append({"id": "panic", "text": t("APP_PANIC")})
	items.append({"id": "end", "text": t("APP_SESSION_END") if role != Wl.CLIENT else t("APP_SESSION_LEAVE")})
	return items


func _on_overlay_pick(_index: int, id: Variant, _auto: bool) -> void:
	match str(id):
		"resume":
			_overlay_menu_open = false
			clear_menus()
			if paused and host != null and role != Wl.CLIENT:
				host.resume()
			_show_overlay()
		"resume_trainer":
			resume_trainer()
		"panic":
			panic()
		"end":
			end_ride()
		"leave":
			goto("title")


func _on_overlay_back() -> void:
	if error != "":
		goto("title")
		return
	if not panicked and not paused:
		_overlay_menu_open = false
		clear_menus()
		_show_overlay()


## End the ride now: the host (or solo) ends the session and results follow; a client leaves.
func end_ride() -> void:
	if host != null and not finished:
		if role == Wl.CLIENT:
			host.end_session("left")
			if services.net != null:
				services.net.leave()
			if not finished:
				_finish(host.final_results())
		else:
			host.end_session("ended_by_rider")
			if host.is_finished() and not finished:
				_finish(host.final_results())


func _fail(reason: String) -> void:
	error = reason
	error_label.text = t(reason) if reason.begins_with("APP_") else t("APP_SESSION_SETUP_FAILED").format([reason])
	error_label.visible = true
	_show_overlay()


# --- input -------------------------------------------------------------------------------------

func _handle_action(action: StringName) -> bool:
	if action == &"panic":
		if not panicked:
			panic()
		return true
	if overlay.visible:
		return false
	if action == &"pause":
		# Idempotent: pause only; resuming is a menu pick, so this never fights a GameHost that
		# also reacts to the pause action.
		if host != null and role != Wl.CLIENT and not host.is_paused():
			host.pause("user")
		open_menu()
		return true
	if action == &"back":
		open_menu()
		return true
	return true


func _handle_gesture(gesture: StringName) -> bool:
	if gesture == Wl.G_PEDAL_START and paused and host != null and role != Wl.CLIENT and pause_reason != "user":
		host.resume()
		return true
	return not overlay.visible


# --- session events ----------------------------------------------------------------------------

func _connect_bus() -> void:
	var bus := services.bus
	if bus == null:
		return
	bus.results_ready.connect(_on_results_ready)
	bus.unlocks_ready.connect(_on_unlocks)
	bus.ride_saved.connect(_on_ride_saved)
	bus.paused_changed.connect(_on_paused_changed)
	bus.panic_requested.connect(_on_panic_requested)
	if services.net != null:
		services.net.refused.connect(_on_refused)


func _disconnect_bus() -> void:
	var bus := services.bus
	if bus != null:
		for pair: Array in [[bus.results_ready, _on_results_ready], [bus.unlocks_ready, _on_unlocks],
				[bus.ride_saved, _on_ride_saved], [bus.paused_changed, _on_paused_changed],
				[bus.panic_requested, _on_panic_requested]]:
			var sig: Signal = pair[0]
			if sig.is_connected(pair[1]):
				sig.disconnect(pair[1])
	if services.net != null and services.net.refused.is_connected(_on_refused):
		services.net.refused.disconnect(_on_refused)


func _on_host_state(state: String) -> void:
	match state:
		"paused":
			paused = true
			if pause_reason == "":
				pause_reason = "user"
			_show_overlay()
		"running", "cooldown":
			paused = false
			pause_reason = ""
			_show_overlay()
		"results", "ended":
			if not finished and host != null and host.final_results() != null:
				_finish(host.final_results())


func _on_paused_changed(p: bool, reason: String) -> void:
	paused = p
	pause_reason = reason if p else ""
	_show_overlay()


func _on_panic_requested() -> void:
	if not panicked:
		panicked = true
		_show_overlay()


func _on_results_ready(r: GameResults) -> void:
	results = r


func _on_unlocks(list: Array) -> void:
	unlocks = list.duplicate(true)


func _on_ride_saved(path: String, summary: Dictionary) -> void:
	fit_path = path
	ride_summary = summary.duplicate(true)


func _on_refused(reason: String) -> void:
	if reason == "host_left" and role == Wl.CLIENT and not finished:
		host_left = true
		if host != null:
			host.end_session("host_left")
		if not finished:
			_finish(host.final_results() if host != null else null)


func _on_session_finished(r: GameResults) -> void:
	_finish(r)


## The session is over: collect results, the FIT path and the ride summary, open results.
func _finish(r: GameResults) -> void:
	if finished:
		return
	finished = true
	if r != null:
		results = r
	if host != null and is_instance_valid(host):
		var paths := host.fit_paths()
		if paths.has(local_peer()) and str(paths[local_peer()]) != "":
			fit_path = str(paths[local_peer()])
	if ride_summary.is_empty():
		ride_summary = read_summary(local_rider(), fit_path)
	goto("results", {
		"results": results, "fit_path": fit_path, "summary": ride_summary, "unlocks": unlocks,
		"game_id": str(config.get("game_id", params.get("game_id", ""))),
		"content_id": str(config.get("content_id", params.get("content_id", ""))),
		"role": role, "local_peer": local_peer(), "host_left": host_left,
	})


## The ride's JSON summary: the recorder's, else the JSON written next to the FIT file.
static func read_summary(rider: LocalRider, path: String) -> Dictionary:
	if rider != null and rider.recorder != null:
		var s := rider.recorder.summary()
		if not s.is_empty():
			return s
	if path != "":
		var json_path := path.get_basename() + ".json"
		if FileAccess.file_exists(json_path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
			if parsed is Dictionary:
				return parsed
		return {"fit_path": path}
	return {}
