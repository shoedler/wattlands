class_name AppSessionScreen
extends AppScreen
## A running session (BRIEF 3.6, 3.9, 4.6.5). Creates the GameHost with the lobby's players
## (NetSession.lobby_slots()), local riders (TrainerService.local_rider() plus a LocalRider per
## bot on the host, MockTrainer.from_spec(Bots.RIDER_SPEC, bot FTP)), the net session, the
## options and the scaling mode (AppSessionLauncher). The GameHost places the game's view in
## its PixelViewport (2D) or the 3D root inside `view_layer` and its HudLayer in `hud_layer`.
## On top: a pause overlay with its own pedal-scan menu over a dimming scrim, and an
## always-visible on-screen panic button in the warning colors (EventBus.panic_requested plus
## LocalRider.panic(): the governor goes safe at once).
## params: role (Wl.SOLO/HOST/CLIENT), game_id, content_id, quick (solo zero-touch start: set
## up the offline lobby here), session_start (CLIENT), rejoin + replay (a restarted client:
## messages that arrived before the GameHost existed are re-emitted to it).
## Network notice (BRIEF 5.5, W3 NET-6), a banner at the top of the screen: on a client,
## NET_HOST_DROPPED from the host's peer_left until it is back (peer_joined) or gone
## (host_left), and NET_STATE_RECONNECTING while this peer's own NetSession reconnects.

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
## Tests: build the game's view and HUD even under the headless display server.
var render_headless: bool = false
## True while this screen runs the Sfx cadence metronome.
var metronome_on: bool = false
var _overlay_menu_open: bool = false
var _left: bool = false
## What the GameHost reads from the InputRouter (AppSessionInput); null without a router.
var session_input: AppSessionInput = null
## Above the HudLayer: the pause overlay and the panic button.
var top_layer: CanvasLayer = null
var top_root: Control = null
## Dims the HUD and the game behind the overlay (shown with it), so the overlay's text never
## mixes with the HUD's banners and widgets.
var overlay_scrim: ColorRect = null
var _panic_reserved: bool = false
## The network notice banner (top centre, above the HUD) and what it says.
var net_notice: Label = null
var host_dropped: bool = false
var net_reconnecting: bool = false

const PANIC_SIZE := Vector2(380, 100)
const SCRIM_COLOR := Color(0.0, 0.0, 0.0, 0.6)
const OVERLAY_PANEL_COLOR := Color(0.06, 0.07, 0.09, 0.97)
const PANIC_BG := Color("#8a1f17")
const PANIC_BG_HI := Color("#b02a20")


func _build() -> void:
	role = str(params.get("role", Wl.SOLO))
	headless = DisplayServer.get_name() == "headless" and not render_headless
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
	# The pause overlay and the panic button draw above the GameHost's HudLayer (a CanvasLayer
	# at HudLayer.LAYER), so no HUD widget or toast ever covers them.
	top_layer = CanvasLayer.new()
	top_layer.name = "Top"
	top_layer.layer = HudLayer.LAYER + 10
	add_child(top_layer)
	top_root = Control.new()
	top_root.name = "TopRoot"
	top_root.theme = AppStyle.theme()
	top_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_layer.add_child(top_root)
	top_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_overlay()
	_build_panic_button()
	_build_net_notice()
	_connect_bus()
	if role != Wl.CLIENT and auto_process:
		# A SOLO or HOST start usually comes from inside the local rider's own tick (a surge that
		# picked Start, the zero-touch sample): setting that rider up for the session there would
		# let the rest of the tick record menu time into the new ride (stale time base). Start
		# right after the tick. A CLIENT starts at once: its GameHost must be listening before the
		# plan that follows session_start in the same NetSession poll.
		_start_session.call_deferred()
	else:
		_start_session()


## Create and start the GameHost (see the class doc).
func _start_session() -> void:
	if _left or host != null:
		return
	if role == Wl.SOLO and bool(params.get("quick", false)):
		_prepare_offline_lobby()
	launcher = AppSessionLauncher.create(services)
	var lp := params.duplicate()
	# The GameHost runs on wall time like the screen (tests drive both by hand).
	lp["realtime"] = auto_process
	config = launcher.build_config(role, lp, view_layer, hud_layer, headless)
	if config.is_empty():
		_fail(launcher.error)
		return
	if services.input != null:
		# The GameHost reads input through the screen, which owns pause and its overlay menu.
		session_input = AppSessionInput.create(services.input, _overlay_owns_input, _menu_rider)
		add_child(session_input)
		config["input_router"] = session_input
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
	if services.input != null:
		# stop_5s maps to pause only in a solo session (WlInputRouter.solo).
		services.input.solo = role == Wl.SOLO
	host.start()
	_reserve_panic_corner()
	_start_metronome()
	for r in AppSessionLauncher.replay_messages(params, services.net):
		services.net.game_message.emit(int(r["from"]), r["data"])


func _on_leave() -> void:
	_left = true
	_disconnect_bus()
	services.set_menu_ticking(true)
	if services.input != null:
		services.input.solo = true
	if metronome_on and services.sfx != null:
		services.sfx.set_metronome(0.0, false)
		metronome_on = false
	if host != null and is_instance_valid(host):
		if host.state_changed.is_connected(_on_host_state):
			host.state_changed.disconnect(_on_host_state)
		if host.session_finished.is_connected(_on_session_finished):
			host.session_finished.disconnect(_on_session_finished)
	if launcher != null:
		launcher.release.call_deferred()


## The optional cadence metronome (BRIEF 3.9 audio; profile setting, Settings -> Audio) clicks at
## the rider's preferred cadence while the session runs.
func _start_metronome() -> void:
	var p := services.profile()
	if p.metronome and services.sfx != null:
		services.sfx.set_metronome(p.preferred_cadence_rpm, true)
		metronome_on = true


## Solo quick start (zero-touch): the offline lobby the menus would have set up.
func _prepare_offline_lobby() -> void:
	var net := services.net
	if net == null:
		return
	var gid := str(params.get("game_id", ""))
	var m: Dictionary = services.registry.manifest(gid) if services.registry != null else {}
	var sc := (
		str(services.settings.get_value("scaling_mode", Wl.FAIR_FTP))
		if services.settings != null
		else Wl.FAIR_FTP
	)
	if not Wl.SCALING_MODES.has(sc):
		sc = Wl.FAIR_FTP
	net.start_offline()
	net.set_game(gid, str(m.get("version", "")), str(params.get("content_id", "")))
	net.set_scaling(sc)
	net.set_setting("options", AppLobbyModel.resolve_game_options(services.registry, gid, {}))
	var popts := AppLobbyModel.resolve_player_options(services.registry, gid, {})
	var st := services.trainer.status() if services.trainer != null else ""
	net.set_local_player_info(
		AppLobbyModel.player_info(
			services.profile(), sc, popts, AppLobbyModel.installed_games(services.registry), st
		)
	)
	net.set_ready(true)


func _overlay_owns_input() -> bool:
	return overlay != null and overlay.visible


func _menu_rider() -> LocalRider:
	return services.trainer.local_rider() if services.trainer != null else null


func local_peer() -> int:
	return int(config.get("local_peer", Wl.HOST_PEER))


func local_rider() -> LocalRider:
	var riders: Dictionary = config.get("local_riders", {})
	return riders.get(local_peer(), null)


## The session's own rider's trainer mode (the overlay menu's hint and coast follow it).
func local_trainer_mode() -> String:
	var r := local_rider()
	if r != null and is_instance_valid(r):
		var tm := r.telemetry()
		return tm.mode if tm != null else ""
	return super.local_trainer_mode()


# --- network notice (NET-6) ----------------------------------------------------------------------


func _build_net_notice() -> void:
	net_notice = AppStyle.paragraph("", AppStyle.FONT_HEADING, AppStyle.WARN)
	net_notice.name = "NetNotice"
	net_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	net_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	net_notice.visible = false
	top_root.add_child(net_notice)
	net_notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	net_notice.offset_top = WlTheme.MARGIN_PX + 120.0
	net_notice.offset_left = 240.0
	net_notice.offset_right = -240.0


## The notice text now ("" when there is nothing to say).
func net_notice_text() -> String:
	if net_reconnecting:
		return t("NET_STATE_RECONNECTING")
	if host_dropped:
		return t("NET_HOST_DROPPED")
	return ""


func _refresh_net_notice() -> void:
	if net_notice == null:
		return
	var text := net_notice_text()
	net_notice.text = text
	net_notice.visible = text != "" and not finished


func _host_peer() -> int:
	var net := services.net
	return net.host_peer if net != null and net.host_peer > 0 else Wl.HOST_PEER


func _on_net_peer_left(peer_id: int, _reason: String) -> void:
	if role == Wl.CLIENT and peer_id == _host_peer():
		host_dropped = true
		_refresh_net_notice()


func _on_net_peer_joined(peer_id: int) -> void:
	if role == Wl.CLIENT and peer_id == _host_peer() and host_dropped:
		host_dropped = false
		_refresh_net_notice()


func _on_net_state(state: String, _detail: String) -> void:
	net_reconnecting = role != Wl.SOLO and state == WlNetSession.STATE_RECONNECTING
	_refresh_net_notice()


# --- overlay and panic -------------------------------------------------------------------------


func _build_overlay() -> void:
	overlay_scrim = ColorRect.new()
	overlay_scrim.name = "OverlayScrim"
	overlay_scrim.color = SCRIM_COLOR
	overlay_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_scrim.visible = false
	top_root.add_child(overlay_scrim)
	overlay_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay = CenterContainer.new()
	overlay.name = "PauseOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	top_root.add_child(overlay)
	var panel := AppStyle.panel(OVERLAY_PANEL_COLOR)
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
	panic_button.text = t("APP_PANIC_BUTTON")
	panic_button.tooltip_text = t("APP_PANIC")
	panic_button.add_theme_font_size_override("font_size", AppStyle.FONT_HEADING)
	# A safety control looks like one: white text on red with a light-red border, unlike every
	# HUD panel (the word carries the meaning; the color is a second cue).
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		panic_button.add_theme_stylebox_override(
			state, _panic_style(PANIC_BG_HI if state in ["hover", "pressed"] else PANIC_BG)
		)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		panic_button.add_theme_color_override(c, Color.WHITE)
	panic_button.add_theme_color_override("font_outline_color", Color.BLACK)
	panic_button.add_theme_constant_override("outline_size", 6)
	panic_button.focus_mode = Control.FOCUS_NONE
	panic_button.custom_minimum_size = PANIC_SIZE
	top_root.add_child(panic_button)
	# In the bottom-right corner at the HUD's margin, growing left and up with its text; the
	# HudLayer keeps that corner clear (_reserve_panic_corner).
	panic_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panic_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panic_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panic_button.offset_right = -WlTheme.MARGIN_PX
	panic_button.offset_bottom = -WlTheme.MARGIN_PX
	panic_button.offset_left = panic_button.offset_right - PANIC_SIZE.x
	panic_button.offset_top = panic_button.offset_bottom - PANIC_SIZE.y
	panic_button.pressed.connect(panic)


static func _panic_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = AppStyle.BAD
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


## The panic button's size (its text may make it wider than PANIC_SIZE).
func panic_button_size() -> Vector2:
	if panic_button == null:
		return Vector2.ZERO
	var m := panic_button.get_combined_minimum_size()
	return Vector2(maxf(m.x, PANIC_SIZE.x), maxf(m.y, PANIC_SIZE.y))


## Ask the session's HudLayer to keep the panic button's corner clear (once it exists: a
## client's HUD is built when session_start arrives).
func _reserve_panic_corner() -> void:
	if _panic_reserved or host == null or not is_instance_valid(host):
		return
	var hud := host.hud_layer()
	if hud == null:
		return
	hud.reserve_corner(HudSpec.BOTTOM_RIGHT, panic_button_size())
	_panic_reserved = true


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
	overlay_scrim.visible = show
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
		overlay_detail.text = pause_text(pause_reason)
	else:
		overlay_title.text = t("APP_SESSION_MENU")
		overlay_detail.text = ""
	overlay_detail.visible = overlay_detail.text != ""
	var items := overlay_items()
	if not _overlay_menu_open:
		_overlay_menu_open = true
		push_menu(items, _on_overlay_pick, _on_overlay_back)
	else:
		refresh_menu(items, menus[0])
	_hold_resume_on_auto_pause()


## What the pause overlay says: a pause the rider asked for resumes from the menu; a platform
## pause (coasting 4.6.4, stop_5s) resumes as soon as the rider pedals again.
static func pause_text(reason: String) -> String:
	if reason == "" or reason == "user":
		return AppScreen.t("APP_SESSION_PAUSED_USER")
	return AppScreen.t("APP_SESSION_PAUSED_DETAIL")


## True while the session is paused by the platform (coasting 4.6.4, stop_5s), not by the rider.
func auto_paused() -> bool:
	return paused and pause_reason != "" and pause_reason != "user" and not panicked and error == ""


## A rider who coasted into a pause starts pedaling again to resume. From rest a surge (1.5 s)
## fires before pedal_start (3 s), so a scanning overlay could pick End ride or Panic by accident:
## while auto-paused the menu holds Resume and does not scan, so that surge resumes too.
func _hold_resume_on_auto_pause() -> void:
	if menus.is_empty():
		return
	var m := menus[0]
	if auto_paused():
		m.scanning = false
		var i := item_index("resume", m)
		if i >= 0:
			m.set_highlight(i)
	else:
		m.scanning = scanning_enabled()


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
	items.append(
		{"id": "end", "text": t("APP_SESSION_END") if role != Wl.CLIENT else t("APP_SESSION_LEAVE")}
	)
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
	error_label.text = (
		t(reason) if reason.begins_with("APP_") else t("APP_SESSION_SETUP_FAILED").format([reason])
	)
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
	if (
		gesture == Wl.G_PEDAL_START
		and paused
		and host != null
		and role != Wl.CLIENT
		and pause_reason != "user"
	):
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
		services.net.peer_left.connect(_on_net_peer_left)
		services.net.peer_joined.connect(_on_net_peer_joined)
		services.net.state_changed.connect(_on_net_state)


func _disconnect_bus() -> void:
	var bus := services.bus
	if bus != null:
		for pair: Array in [
			[bus.results_ready, _on_results_ready],
			[bus.unlocks_ready, _on_unlocks],
			[bus.ride_saved, _on_ride_saved],
			[bus.paused_changed, _on_paused_changed],
			[bus.panic_requested, _on_panic_requested]
		]:
			var sig: Signal = pair[0]
			if sig.is_connected(pair[1]):
				sig.disconnect(pair[1])
	var net := services.net
	if net != null:
		for pair: Array in [
			[net.refused, _on_refused],
			[net.peer_left, _on_net_peer_left],
			[net.peer_joined, _on_net_peer_joined],
			[net.state_changed, _on_net_state]
		]:
			var sig: Signal = pair[0]
			if sig.is_connected(pair[1]):
				sig.disconnect(pair[1])


func _on_host_state(state: String) -> void:
	_reserve_panic_corner()
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
	if reason == "host_left" and role == Wl.CLIENT:
		host_dropped = false
		_refresh_net_notice()
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
	goto(
		"results",
		{
			"results": results,
			"fit_path": fit_path,
			"summary": ride_summary,
			"unlocks": unlocks,
			"game_id": str(config.get("game_id", params.get("game_id", ""))),
			"content_id": str(config.get("content_id", params.get("content_id", ""))),
			"role": role,
			"local_peer": local_peer(),
			"host_left": host_left,
		}
	)


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
