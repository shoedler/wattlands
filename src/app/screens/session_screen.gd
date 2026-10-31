class_name AppSessionScreen
extends AppScreen
## A running session (BRIEF 3.6, 3.9, 4.6.5). Creates the GameHost with the lobby's players
## (NetSession.lobby_slots()), local riders (TrainerService.local_rider() plus a LocalRider per
## bot on the host, MockTrainer.from_spec(Bots.RIDER_SPEC, bot FTP)), the net session, the
## options and the scaling mode (AppSessionLauncher). The GameHost places the game's view in
## its PixelViewport (2D) or the 3D root inside `view_layer` and its HudLayer in `hud_layer`.
## On top: a pause overlay with its own pedal-scan menu over a dimming scrim. Panic (BRIEF
## 4.6.5; EventBus.panic_requested plus LocalRider.panic(): the governor goes safe at once)
## is Backspace held 1 s, gamepad View + Menu, or the overlay's Panic item; the overlay's hint
## line says so (APP_SESSION_PANIC_HINT). There is no on-screen panic button.
## params: role (Wl.SOLO/HOST/CLIENT), game_id, content_id, quick (solo zero-touch start: set
## up the offline lobby here), session_start (CLIENT), rejoin + replay (a restarted client:
## messages that arrived before the GameHost existed are re-emitted to it).
## Network notice (BRIEF 5.5, W3 NET-6), a banner at the top of the screen: on a client,
## NET_HOST_DROPPED from the host's peer_left until it is back (peer_joined) or gone
## (host_left), and NET_STATE_RECONNECTING while this peer's own NetSession reconnects.
## Discard the ride, under End/Leave on every overlay menu but the error one, opens a confirm with
## Keep riding first (discard_ride(): end_ride() with this machine's ride thrown away, then the
## title). Pedals can never pick Yes: the confirm does not scan or auto-pick and a surge does
## nothing there, since a surge can fire from riding alone (a rescue's recovery, a hard effort) and
## the ride can't be had back. Yes takes a keyboard or controller pick. A coast still backs out
## (never in ERG, BRIEF 3.5), so a pedal-only rider can leave it.

var role: String = Wl.SOLO
var host: GameHost = null
var launcher: AppSessionLauncher = null
var config: Dictionary = {}
var view_layer: Control = null
var hud_layer: Control = null
var overlay: CenterContainer = null
var overlay_title: Label = null
var overlay_detail: Label = null
## The overlay's line naming the emergency stop keys (hidden once panicked or on an error).
var panic_hint: Label = null
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
## Above the HudLayer: the pause overlay.
var top_layer: CanvasLayer = null
var top_root: Control = null
## Dims the HUD and the game behind the overlay (shown with it), so the overlay's text never
## mixes with the HUD's banners and widgets.
var overlay_scrim: ColorRect = null
## The network notice banner (top centre, above the HUD) and what it says.
var net_notice: Label = null
var host_dropped: bool = false
var net_reconnecting: bool = false
## The rider confirmed Discard the ride: the session goes to the title, not to results.
var discarded: bool = false

const SCRIM_COLOR := Color(0.0, 0.0, 0.0, 0.6)
const OVERLAY_PANEL_COLOR := Color(0.06, 0.07, 0.09, 0.97)


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
	# The pause overlay draws above the GameHost's HudLayer (a CanvasLayer at HudLayer.LAYER),
	# so no HUD widget or toast ever covers it.
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


## True when this machine's rider rides this session on Autopilot: its own slot's flag (the
## lobby toggle, or the profile's default for a quick start). False before the GameHost config.
func session_autopilot() -> bool:
	for slot: PlayerSlot in config.get("players", []):
		if slot.peer_id == local_peer() and not slot.is_bot:
			return slot.autopilot
	return false


## Pedal navigation on (BRIEF 3.5): this session's Autopilot counts as well as
## InputRouter.pedal_nav_active(). An auto-pause still holds Resume without scanning.
func pedal_nav_enabled() -> bool:
	return session_autopilot() or super.pedal_nav_enabled()


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
	panic_hint = AppStyle.paragraph(t("APP_SESSION_PANIC_HINT"), AppStyle.FONT_SMALL, AppStyle.WARN)
	panic_hint.name = "PanicHint"
	box.add_child(panic_hint)


## Panic (BRIEF 4.6.5): ERG off, SIM grade 0 and wind 0 at once, through the governor; stays
## safe until the rider resumes.
func panic() -> void:
	panicked = true
	if services.bus != null:
		services.bus.panic_requested.emit()
	var r := local_rider()
	if r != null:
		r.panic()
	_close_discard_confirm()
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
	elif discard_confirm_showing():
		overlay_title.text = t("APP_SESSION_DISCARD_TITLE")
		overlay_detail.text = "%s\n%s" % [discard_detail(), t("APP_SESSION_DISCARD_HOW")]
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
	panic_hint.visible = not panicked and error == ""
	var items := overlay_items()
	if not _overlay_menu_open:
		_overlay_menu_open = true
		push_menu(items, _on_overlay_pick, _on_overlay_back)
	else:
		refresh_menu(items, menus[0])
	_hold_resume_on_auto_pause()


## What the pause overlay says: a pause the rider asked for resumes from the menu; a pause on
## not pedaling (BRIEF 3.5) resumes as soon as the rider pedals again.
static func pause_text(reason: String) -> String:
	if reason == "" or reason == "user":
		return AppScreen.t("APP_SESSION_PAUSED_USER")
	return AppScreen.t("APP_SESSION_PAUSED_DETAIL")


## True while the session is paused for not pedaling (BRIEF 3.5), not by the rider.
func auto_paused() -> bool:
	return paused and pause_reason != "" and pause_reason != "user" and not panicked and error == ""


## A rider who stopped into a pause starts pedaling again to resume (the GameHost resumes after
## 1 s at >= 30 rpm). A surge from rest could still pick End ride or Panic on a scanning overlay
## by accident: while auto-paused the menu holds Resume and does not scan, so a surge resumes.
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
	items.append({"id": "discard", "text": t("APP_SESSION_DISCARD")})
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
		"discard":
			open_discard_confirm()
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


# --- discard the ride -----------------------------------------------------------------------


## The confirm is the menu on top of the ride menu (the overlay's only sub-menu).
func discard_confirm_showing() -> bool:
	return menus.size() > 1


func discard_detail() -> String:
	match role:
		Wl.HOST:
			return t("APP_SESSION_DISCARD_DETAIL_HOST")
		Wl.CLIENT:
			return t("APP_SESSION_DISCARD_DETAIL_CLIENT")
	return t("APP_SESSION_DISCARD_DETAIL")


## Keep riding first and highlighted, and it stays there: the list runs without pedal navigation,
## so it never scans or auto-picks and its hint names the keys.
func open_discard_confirm() -> void:
	var items: Array = [
		{"id": "keep", "text": t("APP_SESSION_DISCARD_KEEP")},
		{"id": "yes", "text": t("APP_SESSION_DISCARD_YES")}
	]
	var m := push_menu(items, _on_discard_pick, _on_discard_back, 0)
	m.pedal_nav = false
	m.scanning = false
	m.erg_auto_confirm = false
	m.follow_local_mode = false
	_show_overlay()


func _close_discard_confirm() -> void:
	if discard_confirm_showing():
		pop_menu()


func _on_discard_pick(_index: int, id: Variant, auto: bool) -> void:
	if auto:
		return
	match str(id):
		"keep":
			_keep_riding()
		"yes":
			discard_ride()


func _on_discard_back() -> void:
	_close_discard_confirm()
	_show_overlay()


## Like the ride menu's Resume. In a panic only Resume the trainer leaves it, so back to that menu.
func _keep_riding() -> void:
	_close_discard_confirm()
	if panicked:
		_show_overlay()
	else:
		_on_overlay_pick(0, "resume", false)


## Throw this machine's ride away and end the session on End/Leave's path, then go to the title.
## A host leaves the room only once the results and session_end are out, so the other riders get
## them; a client has already left in end_ride().
func discard_ride() -> void:
	if host == null or finished or not host.discard_own_ride():
		return
	discarded = true
	end_ride()
	finished = true
	if role != Wl.CLIENT and services.net != null:
		services.net.leave_when_flushed()
	# The rider may still be spinning: that stretch must not start a new ride from the title.
	goto("title", {"fresh_start": true})


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
		if _help_open():
			# The GameHost takes this `back` from its queue and closes the help overlay.
			return true
		open_menu()
		return true
	return true


## The session HUD's help overlay is open (HudLayer.help_visible()).
func _help_open() -> bool:
	if host == null or not is_instance_valid(host) or host.hud_layer() == null:
		return false
	return host.hud_layer().help_visible()


## A pause on not pedaling ends in the GameHost (1 s of pedaling at >= 30 rpm, BRIEF 3.5).
func _handle_gesture(gesture: StringName) -> bool:
	if discard_confirm_showing():
		if gesture == Wl.G_COAST and local_trainer_mode() != Wl.ERG:
			active_menu().feed_action(&"back")
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
	match state:
		"paused":
			paused = true
			if pause_reason == "":
				pause_reason = "user"
			_show_overlay()
		"running", "cooldown":
			_pause_ended()
		"results", "ended":
			if not finished and host != null and host.final_results() != null:
				_finish(host.final_results())


func _on_paused_changed(p: bool, reason: String) -> void:
	if not p:
		_pause_ended()
		return
	paused = true
	pause_reason = reason
	_show_overlay()


## The session runs again (the menu's Resume, or the GameHost ending a pause on not pedaling):
## the pause menu closes with it.
func _pause_ended() -> void:
	var was_paused := paused
	paused = false
	pause_reason = ""
	if was_paused and _overlay_menu_open and not panicked and error == "":
		_overlay_menu_open = false
		clear_menus()
	_show_overlay()


func _on_panic_requested() -> void:
	if not panicked:
		panicked = true
		_close_discard_confirm()
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
			# The host's results can arrive in the same poll as its leave.
			host.apply_pending_results()
		if host != null and not finished:
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
	if discarded:
		return
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
			"autopilot": session_autopilot(),
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
