class_name AppLobbyScreen
extends AppScreen
## Lobby (BRIEF 3.5, 3.6, 5.5). params.mode:
##   "solo"  an offline lobby (NetSession.start_offline): content, options, bots, then ride;
##   "host"  a relay room: the code is shown as K7Q-X2M at >= 48 px for friends to type;
##   "join"  code entry first (on-screen keyboard for controller and pedal-scan, typing works
##           too, with no click first: the first code character typed puts the keyboard focus
##           in the field, W3 ZIH-7; dashes and spaces are ignored), plus Recent rooms and the
##           LAN list (P1).
## The host sets the content (<ID>_CONTENT_<CID> labels, bare id when missing; for a game with
## the "zwo" content scheme also the rider's own .zwo files from Paths.user_dir()/workouts/,
## as "zwo:<absolute path>", with the folder named on the page; the interactive app also takes
## --content=<id> for the game it opens; W3 WO-1), the scaling
## mode, the game's options (toggle, int, choice; sent in lobby_state.settings.options), bots
## (Add bot / Remove bot up to max_players, the bot FTP in lobby_state.settings.bot_ftp).
## Every rider edits their own player_options on their card (sent in player_info). Riders ready
## up with pedal_start or confirm. The host starts once everyone is ready; clients follow the
## host's session_start. Clear messages for a missing game, a version mismatch,
## session_in_progress and host_left.

const PAGE_JOIN := "join"
const PAGE_CONNECTING := "connecting"
const PAGE_LOBBY := "lobby"
const RECENT_MAX := 8
const BOT_FTP_MIN := 50.0
const BOT_FTP_MAX := 600.0

var mode: String = "solo"
var role: String = Wl.SOLO
var game_id: String = ""
var page: String = ""
var local_ready: bool = false
var start_requested: bool = false
var launched: bool = false
var joining_code: String = ""
## Host/solo copies of what was sent (NetSession echoes them in lobby_state).
var content_id: String = ""
var scaling: String = Wl.FAIR_FTP
var game_options: Dictionary = {}
var bot_ftp: float = 200.0
## This rider's player_options values.
var my_player_options: Dictionary = {}
## Client: the game whose player_options defaults were filled in (so a lobby_state echo never
## resets edited values or re-sends player_info for a game without player_options).
var _options_game: String = ""
## The last player_info sent (a client resends only when it changed, e.g. the host's scaling).
var _last_info: Dictionary = {}
## This rider's Autopilot for this session (BRIEF 3.5: toggled in the profile or the lobby);
## starts at the profile's default and is sent in player_info.
var my_autopilot: bool = false
var message: String = ""
var code_field: AppTextField = null
var keyboard: AppKeyboard = null
var code_label: Label = null
var message_label: Label = null
var info_label: Label = null
## Where the rider's own .zwo files go (host and solo of a game with the zwo scheme).
var zwo_hint_label: Label = null
## Rider cards, two per row (8 riders fit at 1080p).
var cards_box: GridContainer = null
var preview_box: VBoxContainer = null
var title_label: Label = null
var _left: VBoxContainer = null
var _preview_cache: Dictionary = {}


func _build() -> void:
	mode = str(params.get("mode", "solo"))
	game_id = str(params.get("game_id", ""))
	role = Wl.SOLO if mode == "solo" else (Wl.HOST if mode == "host" else Wl.CLIENT)
	my_autopilot = services.profile().autopilot_default
	var ui := make_page("")
	(ui["footer"] as Control).visible = false
	scroll_menu_column(ui["right"] as Control)
	title_label = ui["title"]

	_left = ui["left"]
	code_label = AppStyle.label("", AppStyle.FONT_CODE, AppStyle.ACCENT)
	code_label.name = "RoomCode"
	_left.add_child(code_label)
	message_label = AppStyle.paragraph("", AppStyle.FONT_BODY, AppStyle.WARN)
	message_label.name = "Message"
	message_label.visible = false
	_left.add_child(message_label)
	info_label = AppStyle.paragraph("", AppStyle.FONT_BODY, AppStyle.TEXT_DIM)
	info_label.name = "Info"
	_left.add_child(info_label)
	zwo_hint_label = AppStyle.paragraph("", AppStyle.FONT_SMALL, AppStyle.TEXT_DIM)
	zwo_hint_label.name = "ZwoHint"
	zwo_hint_label.visible = false
	_left.add_child(zwo_hint_label)
	cards_box = GridContainer.new()
	cards_box.columns = 2
	cards_box.add_theme_constant_override("h_separation", 12)
	cards_box.add_theme_constant_override("v_separation", 10)
	cards_box.name = "Cards"
	_left.add_child(cards_box)
	preview_box = AppStyle.vbox(6)
	preview_box.name = "Preview"
	_left.add_child(preview_box)
	_connect_net()
	match mode:
		"join":
			_show_join_page()
		"host":
			_host_room()
		_:
			if services.net != null:
				services.net.start_offline()
			_init_local_lobby()
			_show_lobby_page()


func _on_leave() -> void:
	_disconnect_net()


# --- net wiring ----------------------------------------------------------------------------


func _connect_net() -> void:
	var net := services.net
	if net == null:
		return
	net.state_changed.connect(_on_net_state)
	net.lobby_changed.connect(_on_lobby_changed)
	net.refused.connect(_on_refused)
	net.game_message.connect(_on_game_message)
	net.peer_joined.connect(_on_peer_changed)
	net.peer_left.connect(_on_peer_left)
	if net.has_signal("lan_rooms_changed"):
		net.connect("lan_rooms_changed", _on_lan_rooms_changed)
	if services.trainer != null:
		services.trainer.status_changed.connect(_on_trainer_status)


func _disconnect_net() -> void:
	var net := services.net
	if net != null:
		for pair: Array in [
			[net.state_changed, _on_net_state],
			[net.lobby_changed, _on_lobby_changed],
			[net.refused, _on_refused],
			[net.game_message, _on_game_message],
			[net.peer_joined, _on_peer_changed],
			[net.peer_left, _on_peer_left]
		]:
			var sig: Signal = pair[0]
			var cb: Callable = pair[1]
			if sig.is_connected(cb):
				sig.disconnect(cb)
		if (
			net.has_signal("lan_rooms_changed")
			and net.is_connected("lan_rooms_changed", _on_lan_rooms_changed)
		):
			net.disconnect("lan_rooms_changed", _on_lan_rooms_changed)
	if (
		services.trainer != null
		and services.trainer.status_changed.is_connected(_on_trainer_status)
	):
		services.trainer.status_changed.disconnect(_on_trainer_status)


func lobby() -> Dictionary:
	return services.net.lobby if services.net != null else {}


func local_peer() -> int:
	var p := services.net.local_peer if services.net != null else 0
	return p if p > 0 else Wl.HOST_PEER


func slots() -> Array[PlayerSlot]:
	if services.net == null:
		var empty: Array[PlayerSlot] = []
		return empty
	return services.net.lobby_slots()


## The game the lobby is about (the host's choice for clients).
func current_game() -> String:
	var g := str(lobby().get("game_id", ""))
	if role == Wl.CLIENT:
		return g
	return game_id if game_id != "" else g


func current_content() -> String:
	if role == Wl.CLIENT:
		return str(lobby().get("content_id", ""))
	return content_id


func manifest() -> Dictionary:
	var g := current_game()
	if g == "" or services.registry == null or not services.registry.has_game(g):
		return {}
	return services.registry.manifest(g)


# --- host and solo setup ---------------------------------------------------------------------


func _host_room() -> void:
	page = PAGE_CONNECTING
	_set_message(t("APP_LOBBY_CREATING"))
	var m := manifest()
	var max_peers := AppLobbyModel.max_players(m) if not m.is_empty() else Wl.MAX_SLOTS
	var net := services.net
	if net != null:
		var preferred := _recent_hosted_code()
		if preferred != "" and net.get_method_argument_count("host_room") >= 2:
			net.call("host_room", max_peers, preferred)
		else:
			net.host_room(max_peers)
	_init_local_lobby()
	_show_lobby_page()


## Send the host's (or solo rider's) game, content, scaling, options, bot FTP and player_info.
func _init_local_lobby() -> void:
	var m := manifest()
	if m.is_empty():
		_set_message(t("APP_ERR_NO_GAME"))
		return
	var wanted := str(params.get("content_id", ""))
	if (
		wanted == ""
		and CmdLine.has("content")
		and (not CmdLine.has("game") or CmdLine.get_str("game", "") == game_id)
	):
		# --content=<id> (for example zwo:<absolute path>) picks the content in the app too.
		wanted = CmdLine.get_str("content", "")
	var last_game := (
		str(services.settings.get_value("last_game", "")) if services.settings != null else ""
	)
	var last_content := (
		str(services.settings.get_value("last_content", "")) if services.settings != null else ""
	)
	if wanted == "" and last_game == game_id and AppLobbyModel.content_available(m, last_content):
		wanted = last_content
	content_id = (
		wanted if AppLobbyModel.content_available(m, wanted) else str(m.get("default_content", ""))
	)
	var sc := (
		str(services.settings.get_value("scaling_mode", Wl.FAIR_FTP))
		if services.settings != null
		else Wl.FAIR_FTP
	)
	scaling = sc if Wl.SCALING_MODES.has(sc) else Wl.FAIR_FTP
	game_options = AppLobbyModel.resolve_game_options(services.registry, game_id, {})
	my_player_options = AppLobbyModel.resolve_player_options(services.registry, game_id, {})
	bot_ftp = services.profile().ftp_w
	_push_lobby_settings()


func _push_lobby_settings() -> void:
	var net := services.net
	if net == null:
		return
	var m := manifest()
	net.set_game(game_id, str(m.get("version", "")), content_id)
	net.set_scaling(scaling)
	net.set_setting("options", game_options.duplicate(true))
	if bool(m.get("bots", false)):
		net.set_setting("bot_ftp", bot_ftp)
	_send_player_info()


func _send_player_info() -> void:
	if services.net == null:
		return
	var info := build_player_info()
	_last_info = info.duplicate(true)
	services.net.set_local_player_info(info)


## This rider's player_info now (a client's p_eff_per_w follows the host's scaling mode).
func build_player_info() -> Dictionary:
	var sc := scaling if role != Wl.CLIENT else str(lobby().get("scaling", Wl.FAIR_FTP))
	if not Wl.SCALING_MODES.has(sc):
		sc = Wl.FAIR_FTP
	var st := services.trainer.status() if services.trainer != null else ""
	return AppLobbyModel.player_info(
		services.profile(),
		sc,
		my_player_options,
		AppLobbyModel.installed_games(services.registry),
		st,
		my_autopilot
	)


## Toggle this rider's Autopilot for the session (sent in player_info; the profile keeps its
## own default). Switching it on turns pedal-scan on at once (scanning_enabled).
func set_autopilot(on: bool) -> void:
	my_autopilot = on
	_send_player_info()
	set_scanning(scanning_enabled())
	_refresh_root_menu()
	_refresh_all()


## Pedal navigation on (BRIEF 3.5): this rider's Autopilot for the session (the lobby toggle)
## counts as well as everything InputRouter.pedal_nav_active() checks (the pedal navigation
## setting, the profile's Autopilot default).
func pedal_nav_enabled() -> bool:
	return my_autopilot or super.pedal_nav_enabled()


## Send player_info only when it differs from the last one sent: the host's lobby_state echo of
## our own player_info must never trigger another send (that would loop host <-> client).
func _send_player_info_if_changed() -> bool:
	if services.net == null or build_player_info() == _last_info:
		return false
	_send_player_info()
	return true


# --- join page -------------------------------------------------------------------------------

## Keys that keep their routed actions while the code field has the keyboard focus (W4r2 R27).
const JOIN_NAV_KEYS: Array[Key] = [KEY_ESCAPE, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]


## A key typed on the join page while nothing has the keyboard focus goes into the code field,
## which takes the focus, so typing a code needs no click first (W3 ZIH-7). Only a character a
## code can hold starts it; Enter submits the code, and the controller and pedal-scan keep the
## on-screen keyboard. Esc and the arrow keys keep their actions even after typing (W4r2 R27):
## they take the focus off the field (WlInputRouter ignores keys while a LineEdit has the
## focus), so Esc backs out and the arrows move the on-screen keyboard and the room lists, and
## the next code character takes the focus back.
func _input(event: InputEvent) -> void:
	if take_typed_key(event):
		get_viewport().set_input_as_handled()
	else:
		release_code_focus_for(event)


## True when `event` is Esc or an arrow pressed while the code field has the focus: the field
## lets go of it, and the event goes on to the InputRouter (it is not marked handled).
func release_code_focus_for(event: InputEvent) -> bool:
	if page != PAGE_JOIN or code_field == null or code_field.line_edit == null:
		return false
	if not (event is InputEventKey):
		return false
	var k := event as InputEventKey
	if not k.pressed or k.echo or not code_field.line_edit.has_focus():
		return false
	if not (JOIN_NAV_KEYS.has(k.keycode) or JOIN_NAV_KEYS.has(k.physical_keycode)):
		return false
	code_field.line_edit.release_focus()
	return true


func take_typed_key(event: InputEvent) -> bool:
	if (
		page != PAGE_JOIN
		or code_field == null
		or not code_field.visible
		or code_field.line_edit == null
	):
		return false
	if not (event is InputEventKey):
		return false
	var k := event as InputEventKey
	if (
		not k.pressed
		or k.echo
		or k.ctrl_pressed
		or k.alt_pressed
		or k.meta_pressed
		or k.unicode <= 0
	):
		return false
	if not is_inside_tree() or get_viewport().gui_get_focus_owner() != null:
		return false
	var ch := String.chr(k.unicode)
	if AppCodeInput.map_char(ch) == "":
		return false
	code_field.append_char(ch)
	code_field.line_edit.grab_focus()
	code_field.line_edit.caret_column = code_field.line_edit.text.length()
	return true


func _show_join_page() -> void:
	page = PAGE_JOIN
	clear_menus()
	title_label.text = t("APP_JOIN_TITLE")
	code_label.visible = false
	if code_field == null:
		code_field = AppTextField.make_code(t("APP_JOIN_CODE"))
		code_field.name = "CodeEntry"
		_left.add_child(code_field)
		_left.move_child(code_field, 1)
		code_field.submitted.connect(_on_code_submitted)
		watch_text_focus(code_field)
	code_field.visible = true
	keyboard = AppKeyboard.create(self, code_field)
	keyboard.done_text_key = "APP_JOIN_GO"
	keyboard.extra_items = _join_extra_items()
	keyboard.on_extra = _on_join_extra
	keyboard.on_done = _on_code_submitted
	keyboard.on_cancel = _leave_to_title
	keyboard.open()
	_refresh_info()


## Recent rooms and LAN rooms (P1), pedal-scan selectable.
func _join_extra_items() -> Array:
	var items: Array = []
	for r: Dictionary in recent_rooms():
		var code := str(r.get("code", ""))
		if RoomCode.is_valid(code):
			items.append(
				{
					"id": "recent:" + code,
					"text":
					t("APP_JOIN_RECENT").format(
						[RoomCode.format(code), str(r.get("game_title", r.get("game_id", "")))]
					)
				}
			)
	for room: Dictionary in lan_rooms():
		var code := str(room.get("code", ""))
		items.append(
			{
				"id": "lan:" + code,
				"text":
				t("APP_JOIN_LAN").format([str(room.get("name", "?")), RoomCode.format(code)])
			}
		)
	return items


func _on_join_extra(id: Variant) -> void:
	var sid := str(id)
	if sid.begins_with("recent:"):
		join_code(sid.substr(7))
	elif sid.begins_with("lan:"):
		var code := sid.substr(4)
		for room: Dictionary in lan_rooms():
			if (
				str(room.get("code", "")) == code
				and services.net != null
				and services.net.has_method("join_lan")
			):
				_begin_join(code)
				services.net.call("join_lan", room)
				return
		join_code(code)


func _on_code_submitted(code: String) -> void:
	join_code(code)


## Join the room with `code` (normalised: dashes, spaces, case and O/I/L tolerated).
func join_code(code: String) -> void:
	var c := RoomCode.normalize(code)
	if c == "":
		_set_message(t("APP_JOIN_BAD_CODE"))
		return
	_begin_join(c)
	if services.net != null:
		_send_player_info()
		services.net.join_room(c)


func _begin_join(code: String) -> void:
	joining_code = RoomCode.normalize(code)
	page = PAGE_CONNECTING
	clear_menus()
	if code_field != null:
		code_field.visible = false
	code_label.visible = true
	code_label.text = RoomCode.format(joining_code)
	_set_message(t("APP_JOIN_JOINING").format([RoomCode.format(joining_code)]))
	push_menu([{"id": "leave", "text": t("APP_JOIN_CANCEL")}], _on_lobby_pick, _leave_to_title)


func lan_rooms() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if services.net != null and services.net.has_method("lan_rooms"):
		var v: Variant = services.net.call("lan_rooms")
		if v is Array:
			for r: Variant in v:
				if r is Dictionary:
					out.append(r as Dictionary)
	return out


func _on_lan_rooms_changed(_rooms: Variant = null) -> void:
	if page == PAGE_JOIN and keyboard != null:
		keyboard.extra_items = _join_extra_items()
		keyboard.refresh()


# --- recent rooms (P1) -----------------------------------------------------------------------


func recent_rooms() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if services.settings == null:
		return out
	var v: Variant = services.settings.get_value("recent_rooms", [])
	if v is Array:
		for r: Variant in v:
			if r is Dictionary:
				out.append(r as Dictionary)
	return out


func _remember_room(code: String, as_role: String) -> void:
	if services.settings == null or code == "":
		return
	var list: Array = []
	var m := manifest()
	list.append(
		{
			"code": code,
			"role": as_role,
			"game_id": current_game(),
			"game_title": str(m.get("title", current_game()))
		}
	)
	for r: Dictionary in recent_rooms():
		if str(r.get("code", "")) != code and list.size() < RECENT_MAX:
			list.append(r)
	services.settings.set_value("recent_rooms", list)
	services.settings.save_settings()


func _recent_hosted_code() -> String:
	for r: Dictionary in recent_rooms():
		if str(r.get("role", "")) == Wl.HOST:
			return str(r.get("code", ""))
	return ""


# --- lobby page ------------------------------------------------------------------------------


func _show_lobby_page() -> void:
	page = PAGE_LOBBY
	clear_menus()
	if code_field != null:
		code_field.visible = false
	push_menu(lobby_items(), _on_lobby_pick, _on_lobby_back)
	_refresh_all()


func lobby_items() -> Array:
	var items: Array = []
	var m := manifest()
	var problem := (
		AppLobbyModel.game_problem(services.registry, lobby()) if role == Wl.CLIENT else ""
	)
	if role == Wl.CLIENT:
		var ready_text := t("APP_LOBBY_UNREADY") if local_ready else t("APP_LOBBY_READY_UP")
		items.append(
			{"id": "ready", "text": ready_text, "disabled": problem != "" or current_game() == ""}
		)
	else:
		var start_text := t("APP_LOBBY_CANCEL_START") if start_requested else t("APP_LOBBY_START")
		items.append({"id": "start", "text": start_text, "disabled": m.is_empty()})
		var contents: Array = m.get("contents", [])
		if contents.size() > 1 or AppLobbyModel.accepts_zwo(m):
			items.append(
				{
					"id": "content",
					"text":
					t("APP_LOBBY_CONTENT").format(
						[AppLobbyModel.content_label(game_id, content_id)]
					)
				}
			)
		items.append(
			{"id": "scaling", "text": t("APP_LOBBY_SCALING").format([scaling_text(scaling)])}
		)
		for e: Variant in m.get("options", []):
			if e is Dictionary:
				var om := AppOptionModel.make(game_id, e as Dictionary)
				items.append(
					{
						"id": "opt:" + om.id(),
						"text":
						(
							"%s: %s"
							% [
								om.label_text(),
								om.value_text(game_options.get(om.id(), om.default_value()))
							]
						)
					}
				)
	if problem == "" and not m.is_empty():
		var gid := current_game()
		for e: Variant in m.get("player_options", []):
			if e is Dictionary:
				var pm := AppOptionModel.make(gid, e as Dictionary)
				var v: Variant = my_player_options.get(pm.id(), pm.default_value())
				items.append(
					{
						"id": "popt:" + pm.id(),
						"text": t("APP_LOBBY_MY_OPTION").format([pm.label_text(), pm.value_text(v)])
					}
				)
		items.append(
			{
				"id": "autopilot",
				"text":
				t("APP_LOBBY_AUTOPILOT").format([t("APP_ON") if my_autopilot else t("APP_OFF")])
			}
		)
	if role != Wl.CLIENT and bool(m.get("bots", false)):
		var all := slots()
		items.append(
			{
				"id": "add_bot",
				"text": t("APP_LOBBY_ADD_BOT"),
				"disabled": not AppLobbyModel.can_add_bot(m, all.size())
			}
		)
		items.append(
			{
				"id": "remove_bot",
				"text": t("APP_LOBBY_REMOVE_BOT"),
				"disabled": AppLobbyModel.bots(all).is_empty()
			}
		)
		items.append(
			{"id": "bot_ftp", "text": t("APP_LOBBY_BOT_FTP").format([int(round(bot_ftp))])}
		)
	items.append(
		{"id": "leave", "text": t("APP_LOBBY_LEAVE") if role != Wl.SOLO else t("APP_BACK")}
	)
	return items


static func scaling_text(mode_name: String) -> String:
	return AppScreen.t("APP_SCALING_" + mode_name)


func _on_lobby_pick(_index: int, id: Variant, _auto: bool) -> void:
	var sid := str(id)
	if sid.begins_with("opt:"):
		_open_option(sid.substr(4), false)
		return
	if sid.begins_with("popt:"):
		_open_option(sid.substr(5), true)
		return
	match sid:
		"start":
			if start_requested:
				start_requested = false
				_set_ready(false)
			else:
				start_requested = true
				_set_ready(true)
				try_launch()
			_refresh_root_menu()
		"ready":
			_set_ready(not local_ready)
		"autopilot":
			set_autopilot(not my_autopilot)
		"content":
			_open_content()
		"scaling":
			_open_scaling()
		"add_bot":
			if services.net != null and AppLobbyModel.can_add_bot(manifest(), slots().size()):
				services.net.add_bot()
			_refresh_root_menu()
			_refresh_all()
		"remove_bot":
			if services.net != null:
				services.net.remove_bot()
			_refresh_root_menu()
			_refresh_all()
		"bot_ftp":
			_open_bot_ftp()
		"leave":
			_leave_to_title()


## Back on the lobby menu highlights Leave instead of leaving at once (a coast is no exit).
func _on_lobby_back() -> void:
	var i := item_index("leave")
	if i >= 0 and active_menu() != null:
		active_menu().set_highlight(i)


func _leave_to_title() -> void:
	if services.net != null:
		services.net.leave()
	goto("title")


func _set_ready(on: bool) -> void:
	local_ready = on
	if services.net != null:
		services.net.set_ready(on)
	_refresh_root_menu()
	_refresh_all()


## Rebuild the lobby's root menu items (texts and enabled states) in place.
func _refresh_root_menu() -> void:
	if page == PAGE_LOBBY and not menus.is_empty():
		refresh_menu(lobby_items(), menus[0])


# --- sub-menus -------------------------------------------------------------------------------


## The content picker: the game's contents, then the rider's own .zwo files (pedal-scan
## selectable like the rest). The session preview below follows the highlighted pick once chosen.
func content_choices() -> Array[String]:
	var m := manifest()
	var out: Array[String] = []
	for c: Variant in m.get("contents", []):
		out.append(str(c))
	out.append_array(AppLobbyModel.user_zwo_contents(m))
	return out


func _open_content() -> void:
	var items: Array = []
	var hl := 0
	var choices := content_choices()
	for i in choices.size():
		var c := choices[i]
		if c == content_id:
			hl = i
		items.append({"id": c, "text": AppLobbyModel.content_label(game_id, c)})
	push_menu(items, _on_content_pick, Callable(), hl)
	_refresh_zwo_hint()


func _on_content_pick(_index: int, id: Variant, _auto: bool) -> void:
	set_content(str(id))
	pop_menu()
	refresh_menu(lobby_items())


func set_content(cid: String) -> void:
	content_id = cid
	if services.net != null:
		services.net.set_game(game_id, str(manifest().get("version", "")), content_id)
	_refresh_all()


func _open_scaling() -> void:
	var items: Array = []
	for mname: String in Wl.SCALING_MODES:
		items.append({"id": mname, "text": scaling_text(mname)})
	push_menu(items, _on_scaling_pick, Callable(), Wl.SCALING_MODES.find(scaling))


func _on_scaling_pick(_index: int, id: Variant, _auto: bool) -> void:
	scaling = str(id)
	if services.net != null:
		services.net.set_scaling(scaling)
	if services.settings != null:
		services.settings.set_value("scaling_mode", scaling)
	_send_player_info()
	pop_menu()
	refresh_menu(lobby_items())
	_refresh_all()


var _editing_option: AppOptionModel = null
var _editing_player: bool = false


func _option_entry(option_id: String, per_player: bool) -> Dictionary:
	var m := manifest()
	for e: Variant in m.get("player_options" if per_player else "options", []):
		if e is Dictionary and str((e as Dictionary).get("id", "")) == option_id:
			return e as Dictionary
	return {}


func _open_option(option_id: String, per_player: bool) -> void:
	var e := _option_entry(option_id, per_player)
	if e.is_empty():
		return
	_editing_option = AppOptionModel.make(current_game(), e)
	_editing_player = per_player
	var current: Variant = option_value(option_id, per_player)
	if _editing_option.uses_list():
		var items: Array = []
		var vals := _editing_option.values()
		for i in vals.size():
			items.append({"id": i, "text": _editing_option.value_text(vals[i])})
		push_menu(
			items, _on_option_value_pick, Callable(), maxi(_editing_option.index_of(current), 0)
		)
	else:
		push_menu(
			_stepper_items(
				_editing_option.label_text(),
				_editing_option.value_text(current),
				str(_editing_option.int_step())
			),
			_on_option_step_pick,
			Callable(),
			2
		)


func _stepper_items(label: String, value_text: String, step_text: String) -> Array:
	return [
		{"id": "value", "text": "%s: %s" % [label, value_text], "disabled": true},
		{"id": "dec", "text": "− " + step_text},
		{"id": "inc", "text": "+ " + step_text},
		{"id": "dec5", "text": "− 5 × " + step_text},
		{"id": "inc5", "text": "+ 5 × " + step_text},
		{"id": "done", "text": t("APP_KEY_DONE")},
	]


func _on_option_value_pick(index: int, _id: Variant, _auto: bool) -> void:
	var vals := _editing_option.values()
	if index >= 0 and index < vals.size():
		set_option(_editing_option.id(), vals[index], _editing_player)
	pop_menu()
	refresh_menu(lobby_items())


func _on_option_step_pick(_index: int, id: Variant, _auto: bool) -> void:
	var oid := _editing_option.id()
	var v: Variant = option_value(oid, _editing_player)
	match str(id):
		"dec":
			v = _editing_option.step_value(v, -1)
		"inc":
			v = _editing_option.step_value(v, 1)
		"dec5":
			v = _editing_option.step_value(v, -5)
		"inc5":
			v = _editing_option.step_value(v, 5)
		"done":
			pop_menu()
			refresh_menu(lobby_items())
			return
	set_option(oid, v, _editing_player)
	refresh_menu(
		_stepper_items(
			_editing_option.label_text(),
			_editing_option.value_text(v),
			str(_editing_option.int_step())
		)
	)


## Current value of a game option (host's or the lobby's) or of this rider's player option.
func option_value(option_id: String, per_player: bool) -> Variant:
	var e := _option_entry(option_id, per_player)
	var om := AppOptionModel.make(current_game(), e)
	if per_player:
		return om.normalize(my_player_options.get(option_id, om.default_value()))
	if role == Wl.CLIENT:
		return om.normalize(AppLobbyModel.game_options(lobby()).get(option_id, om.default_value()))
	return om.normalize(game_options.get(option_id, om.default_value()))


## Set a game option (host only: lobby_state.settings.options) or this rider's player option
## (player_info.player_options).
func set_option(option_id: String, value: Variant, per_player: bool) -> void:
	var e := _option_entry(option_id, per_player)
	if e.is_empty():
		return
	var om := AppOptionModel.make(current_game(), e)
	var v: Variant = om.normalize(value)
	if per_player:
		my_player_options[option_id] = v
		_send_player_info()
	elif role != Wl.CLIENT:
		game_options[option_id] = v
		if services.net != null:
			services.net.set_setting("options", game_options.duplicate(true))
	_refresh_all()


func _open_bot_ftp() -> void:
	push_menu(
		_stepper_items(t("APP_LOBBY_BOT_FTP_LABEL"), "%d W" % int(round(bot_ftp)), "10 W"),
		_on_bot_ftp_pick,
		Callable(),
		2
	)


func _on_bot_ftp_pick(_index: int, id: Variant, _auto: bool) -> void:
	match str(id):
		"dec":
			set_bot_ftp(bot_ftp - 10.0)
		"inc":
			set_bot_ftp(bot_ftp + 10.0)
		"dec5":
			set_bot_ftp(bot_ftp - 50.0)
		"inc5":
			set_bot_ftp(bot_ftp + 50.0)
		"done":
			pop_menu()
			refresh_menu(lobby_items())
			return
	refresh_menu(_stepper_items(t("APP_LOBBY_BOT_FTP_LABEL"), "%d W" % int(round(bot_ftp)), "10 W"))


func set_bot_ftp(w: float) -> void:
	bot_ftp = clampf(round(w), BOT_FTP_MIN, BOT_FTP_MAX)
	if services.net != null:
		services.net.set_setting("bot_ftp", bot_ftp)
	_refresh_all()


# --- start -----------------------------------------------------------------------------------


## Host/solo: start once the start was requested and every human is ready (solo: this rider).
## Returns true when the session screen was opened.
func try_launch() -> bool:
	if launched or role == Wl.CLIENT or not start_requested:
		return false
	var m := manifest()
	if m.is_empty():
		return false
	if role == Wl.HOST and (services.net == null or services.net.room_code == ""):
		# The relay has not created the room yet (or failed to): a HOST session needs one.
		_set_message(t("APP_LOBBY_CREATING"))
		return false
	var all := slots()
	if not all.is_empty() and all.size() < AppLobbyModel.min_players(m):
		_set_message(t("APP_LOBBY_NEED_PLAYERS").format([AppLobbyModel.min_players(m)]))
		return false
	if services.trainer == null or services.trainer.device() == null:
		_set_message(t("APP_ERR_NO_TRAINER"))
		return false
	var everyone_ready: bool = local_ready
	if role == Wl.HOST:
		everyone_ready = services.net != null and services.net.all_ready()
	if not everyone_ready:
		_set_message(t("APP_LOBBY_WAITING_READY"))
		return false
	launched = true
	goto("session", {"role": role, "game_id": game_id, "content_id": content_id})
	return true


func _tick(_dt: float) -> void:
	if start_requested and not launched:
		try_launch()


func _handle_gesture(gesture: StringName) -> bool:
	if gesture == Wl.G_PEDAL_START and page == PAGE_LOBBY:
		if role == Wl.CLIENT:
			if (
				not local_ready
				and AppLobbyModel.game_problem(services.registry, lobby()) == ""
				and current_game() != ""
			):
				_set_ready(true)
		elif role == Wl.SOLO and not start_requested:
			start_requested = true
			_set_ready(true)
			try_launch()
		elif not local_ready:
			_set_ready(true)
		return true
	return false


# --- net events ------------------------------------------------------------------------------


func _on_net_state(state: String, detail: String) -> void:
	match state:
		"hosting":
			if role == Wl.HOST:
				page = PAGE_LOBBY
				code_label.visible = true
				code_label.text = RoomCode.format(services.net.room_code)
				_remember_room(services.net.room_code, Wl.HOST)
				_set_message("")
				# The new room's lobby starts empty: send the game, settings, player_info and a
				# ready flag set before the room existed.
				_push_lobby_settings()
				if local_ready:
					services.net.set_ready(true)
				_refresh_all()
				try_launch()
		"joined":
			if role == Wl.CLIENT and page != PAGE_LOBBY:
				page = PAGE_LOBBY
				_remember_room(
					services.net.room_code if services.net.room_code != "" else joining_code,
					Wl.CLIENT
				)
				_set_message("")
				_send_player_info()
				_show_lobby_page()
		"error":
			_set_message(t("APP_NET_ERROR").format([detail]))
			if role == Wl.CLIENT and page == PAGE_CONNECTING:
				_show_join_page()
		"offline":
			if role == Wl.CLIENT and page == PAGE_LOBBY and not launched:
				_set_message(t("APP_NET_LOST"))


func _on_lobby_changed(_lobby: Dictionary) -> void:
	if role == Wl.CLIENT:
		var g := current_game()
		if (
			g != ""
			and g != _options_game
			and AppLobbyModel.game_problem(services.registry, lobby()) == ""
		):
			_options_game = g
			my_player_options = AppLobbyModel.resolve_player_options(services.registry, g, {})
		_send_player_info_if_changed()
		if page == PAGE_CONNECTING:
			page = PAGE_LOBBY
			_show_lobby_page()
			return
	if menus.size() == 1:
		_refresh_root_menu()
	_refresh_all()
	try_launch()


func _on_refused(reason: String) -> void:
	_set_message(refusal_text(reason))
	if role == Wl.CLIENT and page != PAGE_LOBBY:
		_show_join_page()
		_set_message(refusal_text(reason))
	elif page == PAGE_LOBBY and menus.size() >= 1:
		pop_to_root()
		refresh_menu([{"id": "leave", "text": t("APP_LOBBY_LEAVE")}])


## A clear message for each refusal (BRIEF 5.5).
static func refusal_text(reason: String) -> String:
	match reason:
		"session_in_progress":
			return AppScreen.t("APP_REFUSED_IN_PROGRESS")
		"version_mismatch":
			return AppScreen.t("APP_REFUSED_VERSION")
		"room_not_found":
			return AppScreen.t("APP_REFUSED_NOT_FOUND")
		"room_full":
			return AppScreen.t("APP_REFUSED_FULL")
		"rate_limited":
			return AppScreen.t("APP_REFUSED_RATE")
		"host_left":
			return AppScreen.t("APP_LOBBY_HOST_LEFT")
		AppLobbyModel.MISSING_GAME:
			return AppScreen.t("APP_LOBBY_MISSING_GAME")
	return AppScreen.t("APP_REFUSED_OTHER").format([reason])


## Client: the host started (session_start), or a rejoin brought the running session's plan,
## phase or snapshot: open the session screen with the message so the client GameHost gets it.
func _on_game_message(from: int, data: Dictionary) -> void:
	if role != Wl.CLIENT or launched:
		return
	var type := str(data.get("type", ""))
	if type == "session_start":
		launched = true
		goto("session", {"role": Wl.CLIENT, "session_start": data.duplicate(true)})
	elif type in ["plan", "phase", "snapshot"] and page == PAGE_LOBBY:
		launched = true
		goto(
			"session",
			{
				"role": Wl.CLIENT,
				"rejoin": true,
				"replay": [{"from": from, "data": data.duplicate(true)}]
			}
		)


func _on_peer_changed(_peer: int) -> void:
	_refresh_all()


func _on_peer_left(_peer: int, _reason: String) -> void:
	_refresh_all()


func _on_trainer_status(_status: String, _detail: String) -> void:
	if page == PAGE_LOBBY:
		_send_player_info()
	_refresh_all()


# --- view ------------------------------------------------------------------------------------


func _set_message(text: String) -> void:
	message = text
	if message_label != null:
		message_label.text = text
		message_label.visible = text != ""


func _refresh_all() -> void:
	_refresh_title()
	_refresh_cards()
	_refresh_info()
	_refresh_zwo_hint()
	_refresh_preview()
	if role == Wl.CLIENT and page == PAGE_LOBBY:
		var problem := AppLobbyModel.game_problem(services.registry, lobby())
		if problem == AppLobbyModel.MISSING_GAME:
			_set_message(t("APP_LOBBY_MISSING_GAME").format([str(lobby().get("game_id", ""))]))
		elif problem == AppLobbyModel.VERSION_MISMATCH:
			var have := str(services.registry.manifest(current_game()).get("version", ""))
			_set_message(
				t("APP_LOBBY_VERSION_MISMATCH").format([str(lobby().get("game_version", "")), have])
			)


func _refresh_title() -> void:
	if title_label == null or page == PAGE_JOIN:
		return
	var m := manifest()
	var gtitle := str(m.get("title", current_game()))
	var key := "APP_LOBBY_TITLE_SOLO"
	if role == Wl.HOST:
		key = "APP_LOBBY_TITLE_HOST"
	elif role == Wl.CLIENT:
		key = "APP_LOBBY_TITLE_CLIENT"
	title_label.text = t(key).format([gtitle])
	if role == Wl.SOLO:
		code_label.visible = false
	elif role == Wl.HOST:
		var code := services.net.room_code if services.net != null else ""
		code_label.visible = code != ""
		code_label.text = RoomCode.format(code)


func _refresh_cards() -> void:
	if cards_box == null:
		return
	for c in cards_box.get_children():
		cards_box.remove_child(c)
		c.free()
	if page != PAGE_LOBBY:
		return
	var lb := lobby()
	var me := local_peer()
	var gid := current_game()
	var m := manifest()
	for slot in slots():
		var is_me := slot.peer_id == me and not slot.is_bot
		var card := AppLobbyCard.make(slot, is_me)
		cards_box.add_child(card)
		var ready := AppLobbyModel.is_ready(lb, slot.peer_id) or (is_me and local_ready)
		var trainer := AppLobbyModel.trainer_status(lb, slot.peer_id)
		if is_me and services.trainer != null:
			trainer = services.trainer.status()
		var opts := my_player_options if is_me else slot.options
		if opts.is_empty():
			opts = AppLobbyModel.player_options_of(lb, slot.peer_id)
		var text := options_text(gid, m, opts)
		var autopilot := my_autopilot if is_me else slot.autopilot
		if autopilot and not slot.is_bot:
			text = (
				t("APP_LOBBY_AUTOPILOT_TAG")
				if text == ""
				else t("APP_LOBBY_AUTOPILOT_TAG") + " · " + text
			)
		card.update(ready, trainer, text, slot.is_bot)


## "Wave offset: 0 · Relaxed band: Off" for a rider's player_options.
static func options_text(gid: String, m: Dictionary, values: Dictionary) -> String:
	var parts: PackedStringArray = []
	for e: Variant in m.get("player_options", []):
		if e is Dictionary:
			var om := AppOptionModel.make(gid, e as Dictionary)
			parts.append(
				(
					"%s: %s"
					% [
						om.label_text(),
						om.value_text(om.normalize(values.get(om.id(), om.default_value())))
					]
				)
			)
	return " · ".join(parts)


func _refresh_info() -> void:
	if info_label == null:
		return
	if page == PAGE_JOIN:
		info_label.text = t("APP_JOIN_HINT")
		return
	var gid := current_game()
	if gid == "" or manifest().is_empty():
		info_label.text = ""
		return
	var m := manifest()
	var parts: PackedStringArray = []
	parts.append(
		t("APP_LOBBY_CONTENT").format([AppLobbyModel.content_label(gid, current_content())])
	)
	var sc := scaling if role != Wl.CLIENT else str(lobby().get("scaling", Wl.FAIR_FTP))
	parts.append(t("APP_LOBBY_SCALING").format([scaling_text(sc)]))
	for e: Variant in m.get("options", []):
		if e is Dictionary:
			var om := AppOptionModel.make(gid, e as Dictionary)
			parts.append("%s: %s" % [om.label_text(), om.value_text(option_value(om.id(), false))])
	if role != Wl.CLIENT and bool(m.get("bots", false)):
		parts.append(t("APP_LOBBY_BOT_FTP").format([int(round(bot_ftp))]))
	info_label.text = " · ".join(parts)


## Names the rider's .zwo folder on the lobby page of a game that takes .zwo files (host and solo).
func _refresh_zwo_hint() -> void:
	if zwo_hint_label == null:
		return
	var show := page == PAGE_LOBBY and role != Wl.CLIENT and AppLobbyModel.accepts_zwo(manifest())
	zwo_hint_label.visible = show
	if show:
		zwo_hint_label.text = t("APP_LOBBY_ZWO_HINT").format([AppLobbyModel.workouts_dir()])


## The game's session_preview() for the chosen content: title, total time and its lines (for
## example the .zwo importer's clamp list).
func preview() -> Dictionary:
	var gid := current_game()
	var cid := current_content()
	if gid == "" or cid == "" or services.registry == null or not services.registry.has_game(gid):
		return {}
	var key := gid + "/" + cid
	if _preview_cache.has(key):
		return _preview_cache[key]
	var module := services.registry.instantiate(gid)
	var p: Dictionary = {}
	if module != null:
		p = module.session_preview(cid)
		module.free()
	_preview_cache[key] = p
	return p


func _refresh_preview() -> void:
	if preview_box == null:
		return
	for c in preview_box.get_children():
		preview_box.remove_child(c)
		c.free()
	if page != PAGE_LOBBY:
		return
	var p := preview()
	if p.is_empty():
		return
	var head := str(p.get("title", ""))
	if p.has("total_s"):
		head = ("%s  %s" % [head, AppStyle.duration_text(float(p["total_s"]))]).strip_edges()
	if head != "":
		preview_box.add_child(AppStyle.label(head, AppStyle.FONT_HEADING))
	for line: Variant in p.get("lines", []):
		preview_box.add_child(AppStyle.paragraph(str(line), AppStyle.FONT_SMALL))
