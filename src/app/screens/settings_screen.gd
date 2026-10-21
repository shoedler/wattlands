class_name AppSettingsScreen
extends AppFormScreen
## Settings (BRIEF 3.2, 3.5, 3.8, 3.9), every page on pedal-scan:
##   Trainer   status, scan and connect (FtmsConnectionManager), use the mock trainer, disconnect.
##             Before the link drops (Disconnect, another trainer, the mock) the rider's governor
##             goes SIM flat, then Stop, and the control point gets SAFE_DRAIN_S to send them
##             (BRIEF 4.6.9).
##   Strava    the player's own API app client ID and secret, connect (loopback OAuth), disconnect,
##             auto-upload (off by default), and the opt-in FTP and weight import (P1, BRIEF 3.8:
##             connect with profile:read_all, pick FTP and/or weight, import). The secret is only
##             passed to Rides and never shown, logged or kept here.
##   Haptics   accept haptic effects on/off, intensity 0-100 %
##   Controls  rebind every action (saved to input.cfg by InputRouter): each row shows the action
##             with its first keyboard and controller binding, the content column all of them.
##             Esc or the controller's B button cancels a capture, and so does leaving the page.
##   Audio     master volume, cadence metronome
##   Network   relay URL
##   Pedal UI  pedal-scan menus on/off, scan interval
##   FTP test (P1) and Rides history (P1) open their own pages.

const MOCK_SPEC := "erg"
## Real seconds the control point gets to send SIM flat and Stop before the link drops (the same
## grace App.quit gives a real trainer).
const SAFE_DRAIN_S := 0.5

var status_label: Label = null
var strava_client_id: String = ""
var strava_client_secret: String = ""
var strava_state: String = ""
var found_devices: Array[Dictionary] = []
var capturing: StringName = &""
var _capture_cooldown: bool = false
var _trainer_menu: PedalScanList = null
var _connection: FtmsConnectionManager = null
## What runs once the trainer was made safe and SAFE_DRAIN_S passed (dropping the link).
var _unlink_pending: Callable = Callable()
var _unlink_left: float = 0.0
## The FTP and weight import (P1): what to import, and the last result line.
var import_ftp: bool = true
var import_weight: bool = false
var import_result: String = ""
var importing: bool = false


func _build() -> void:
	make_form_page(t("APP_SETTINGS_TITLE"))
	status_label = AppStyle.paragraph("", AppStyle.FONT_BODY, AppStyle.TEXT)
	status_label.name = "Status"
	content_box.add_child(status_label)
	if services.bus != null:
		services.bus.strava_state_changed.connect(_on_strava_state)
	if services.trainer != null:
		services.trainer.status_changed.connect(_on_trainer_status)
		_connection = services.trainer.connection()
		if _connection != null:
			_connection.device_found.connect(_on_device_found)
	open_fields(root_fields(), _back)
	var start_page := str(params.get("section", ""))
	if start_page != "":
		open_section(start_page)


func _on_leave() -> void:
	# A link drop still waiting for the safe commands happens now (the rider is already safe).
	_run_unlink()
	_end_capture()
	if services.bus != null and services.bus.strava_state_changed.is_connected(_on_strava_state):
		services.bus.strava_state_changed.disconnect(_on_strava_state)
	if services.trainer != null and services.trainer.status_changed.is_connected(_on_trainer_status):
		services.trainer.status_changed.disconnect(_on_trainer_status)
	if _connection != null and is_instance_valid(_connection) and _connection.device_found.is_connected(_on_device_found):
		_connection.device_found.disconnect(_on_device_found)
	strava_client_secret = ""


func _back() -> void:
	goto("title")


func p() -> RiderProfile:
	return services.profile()


func save_profile() -> void:
	if services.settings != null:
		services.settings.save_profile()
	if services.bus != null:
		services.bus.profile_changed.emit()


func set_setting(key: String, value: Variant) -> void:
	if services.settings != null:
		services.settings.set_value(key, value)
		services.settings.save_settings()
	if services.bus != null:
		services.bus.settings_changed.emit(key)


func root_fields() -> Array:
	return [
		{"id": "trainer", "label": t("APP_SET_TRAINER"), "type": "action", "run": open_section.bind("trainer")},
		{"id": "strava", "label": t("APP_SET_STRAVA"), "type": "action", "run": open_section.bind("strava")},
		{"id": "haptics", "label": t("APP_SET_HAPTICS"), "type": "action", "run": open_section.bind("haptics")},
		{"id": "controls", "label": t("APP_SET_CONTROLS"), "type": "action", "run": open_section.bind("controls")},
		{"id": "audio", "label": t("APP_SET_AUDIO"), "type": "action", "run": open_section.bind("audio")},
		{"id": "network", "label": t("APP_SET_NETWORK"), "type": "action", "run": open_section.bind("network")},
		{"id": "pedal_ui", "label": t("APP_SET_PEDAL_UI"), "type": "action", "run": open_section.bind("pedal_ui")},
		{"id": "ftp_test", "label": t("APP_SET_FTP_TEST"), "type": "action", "run": func() -> void: goto("settings", {"page": "ftp_test"})},
		{"id": "rides", "label": t("APP_SET_RIDES"), "type": "action", "run": func() -> void: goto("settings", {"page": "rides"})},
		{"id": "back", "label": t("APP_BACK"), "type": "action", "run": _back},
	]


## Open a settings page by id ("trainer", "strava", "haptics", "controls", "audio", "network",
## "pedal_ui").
func open_section(section: String) -> void:
	var fields: Array = []
	match section:
		"trainer":
			fields = trainer_fields()
		"strava":
			fields = strava_fields()
		"haptics":
			fields = haptics_fields()
		"controls":
			fields = controls_fields()
		"audio":
			fields = audio_fields()
		"network":
			fields = network_fields()
		"pedal_ui":
			fields = pedal_fields()
	if fields.is_empty():
		return
	fields.append({"id": "back", "label": t("APP_BACK"), "type": "action", "run": _pop_section})
	# A coast or back on a page goes through _pop_section too, so it ends a key capture (W3 ZIH-4).
	var list := open_fields(fields, _pop_section)
	if section == "trainer":
		_trainer_menu = list
	_refresh_status(section)


func _pop_section() -> void:
	_end_capture()
	if menus.size() > 1:
		pop_menu()
	_trainer_menu = null
	_refresh_status("")


# --- trainer ---------------------------------------------------------------------------------

func trainer_fields() -> Array:
	var fields: Array = [
		{"id": "status", "label": t("APP_SET_TRAINER_STATUS"), "type": "info",
			"get": func() -> Variant: return AppLobbyCard.trainer_text(services.trainer.status() if services.trainer != null else "")},
		{"id": "scan", "label": t("APP_SET_TRAINER_SCAN"), "type": "action", "run": scan_trainers,
			"enabled": func() -> bool: return _connection != null},
	]
	for d: Dictionary in found_devices:
		var addr := str(d.get("address", ""))
		fields.append({"id": "dev:" + addr, "label": t("APP_SET_TRAINER_CONNECT").format([str(d.get("name", addr)), int(d.get("rssi", 0))]),
			"type": "action", "run": connect_trainer.bind(addr)})
	fields.append({"id": "mock", "label": t("APP_SET_TRAINER_MOCK"), "type": "action", "run": use_mock})
	fields.append({"id": "disconnect", "label": t("APP_SET_TRAINER_DISCONNECT"), "type": "action", "run": disconnect_trainer,
		"enabled": func() -> bool: return _connection != null})
	return fields


func scan_trainers() -> void:
	found_devices.clear()
	if _connection != null:
		_connection.scan(10.0)
	_refresh_status("trainer")


func connect_trainer(address: String) -> void:
	if _connection == null:
		_refresh_status("trainer")
		return
	# Switching trainers drops the current link first (FtmsConnectionManager.connect_to).
	make_trainer_safe_then(_connect_now.bind(address))
	_refresh_status("trainer")


func _connect_now(address: String) -> void:
	if _connection != null and is_instance_valid(_connection):
		_connection.connect_to(address)
	_refresh_status("trainer")


func use_mock() -> void:
	make_trainer_safe_then(_use_mock_now)
	_refresh_status("trainer")


func _use_mock_now() -> void:
	if services.trainer != null:
		services.trainer.use_mock(MOCK_SPEC)
	_rebuild_trainer_page()


func disconnect_trainer() -> void:
	if _connection == null:
		_rebuild_trainer_page()
		return
	make_trainer_safe_then(_disconnect_now)
	_refresh_status("trainer")


func _disconnect_now() -> void:
	if _connection != null and is_instance_valid(_connection):
		_connection.disconnect_trainer()
	_rearm_menu_rider()
	_rebuild_trainer_page()


## BRIEF 4.6.9 ("on disconnect: try SIM flat, then Stop"): before this page drops the trainer
## link, the menu rider's governor shuts down (SIM flat, then Stop) and the control point gets
## SAFE_DRAIN_S of real time to send both; then `then` runs (from tick()). With a MockTrainer, no
## rider, or a link that is not ready, `then` runs at once. Returns true when it waits (W3 SAF-8).
## Until the trainer area's TrainerService method for this lands, the page uses the rider's own
## shutdown (the API App.quit uses) and waits as App.quit does for a real trainer.
func make_trainer_safe_then(then: Callable) -> bool:
	_run_unlink()
	var ts := services.trainer
	var dev: TrainerDevice = ts.device() if ts != null else null
	var rider: LocalRider = ts.local_rider() if ts != null and dev != null else null
	if rider == null or dev is MockTrainer or not dev.is_ready() or rider.is_shut_down() or ts.is_external_tick():
		then.call()
		return false
	rider.shutdown()
	_unlink_pending = then
	_unlink_left = SAFE_DRAIN_S
	return true


## True while a link drop waits for the safe commands to go out.
func is_making_trainer_safe() -> bool:
	return _unlink_pending.is_valid()


func _run_unlink() -> void:
	if not _unlink_pending.is_valid():
		return
	var f := _unlink_pending
	_unlink_pending = Callable()
	_unlink_left = 0.0
	f.call()


## After Disconnect the same trainer object comes back on the next connect (the manager keeps it
## per address), and TrainerService then keeps its rider as it is: set the shut-down menu rider
## up again, as TrainerService's menu reset does, so the next connect has a live governor and
## App.quit shuts it down again (BRIEF 4.6.9 on exit).
func _rearm_menu_rider() -> void:
	var ts := services.trainer
	if ts == null or ts.is_external_tick():
		return
	var dev := ts.device()
	var rider := ts.local_rider()
	if dev == null or rider == null or not rider.is_shut_down():
		return
	var prof := p()
	var mode := str(services.settings.get_value("scaling_mode", Wl.FAIR_FTP)) if services.settings != null else Wl.FAIR_FTP
	if not Wl.SCALING_MODES.has(mode):
		mode = Wl.FAIR_FTP
	rider.setup(1, prof, prof.to_slot(1, mode), dev, {
		"multiplayer": false, "scaling_mode": mode, "record": false, "seed": CmdLine.get_int("seed", 0),
	})


func _on_device_found(info: Dictionary) -> void:
	var addr := str(info.get("address", ""))
	for d: Dictionary in found_devices:
		if str(d.get("address", "")) == addr:
			return
	found_devices.append(info.duplicate(true))
	_rebuild_trainer_page()


func _rebuild_trainer_page() -> void:
	if _trainer_menu == null or not is_instance_valid(_trainer_menu) or not menus.has(_trainer_menu):
		return
	var fields := trainer_fields()
	fields.append({"id": "back", "label": t("APP_BACK"), "type": "action", "run": _pop_section})
	_fields_by_menu[_trainer_menu.get_instance_id()] = fields
	refresh_menu(items_for(fields), _trainer_menu)
	_refresh_status("trainer")


func _on_trainer_status(_status: String, _detail: String) -> void:
	refresh_fields()


# --- strava ----------------------------------------------------------------------------------

func strava_connected() -> bool:
	return services.rides != null and services.rides.strava_connected()


func strava_fields() -> Array:
	var fields: Array = [
		{"id": "strava_status", "label": t("APP_SET_STRAVA_STATUS"), "type": "info", "get": strava_status_text},
		{"id": "client_id", "label": t("APP_SET_STRAVA_ID"), "type": "text", "rows": AppTextField.ROWS_DIGITS, "max_length": 12,
			"get": func() -> Variant: return strava_client_id, "set": func(v: Variant) -> void: strava_client_id = str(v).strip_edges()},
		{"id": "client_secret", "label": t("APP_SET_STRAVA_SECRET"), "type": "text", "rows": AppTextField.ROWS_HEX, "max_length": 64, "secret": true,
			"get": func() -> Variant: return strava_client_secret, "set": func(v: Variant) -> void: strava_client_secret = str(v).strip_edges()},
		{"id": "connect", "label": t("APP_SET_STRAVA_CONNECT"), "type": "action", "run": strava_connect,
			"enabled": func() -> bool: return strava_client_id != "" and strava_client_secret != "" and not strava_connected()},
		{"id": "disconnect", "label": t("APP_SET_STRAVA_DISCONNECT"), "type": "action", "run": strava_disconnect,
			"enabled": strava_connected},
		{"id": "auto_upload", "label": t("APP_SET_STRAVA_AUTO"), "type": "toggle",
			"get": func() -> Variant: return p().strava_auto_upload,
			"set": func(v: Variant) -> void: _set_profile("strava_auto_upload", bool(v))},
	]
	fields.append_array(strava_import_fields())
	return fields


## The opt-in FTP and weight import (BRIEF 3.2, 3.8 P1): connect with profile:read_all, choose
## FTP and/or weight, import (an imported FTP is verified and CP follows it).
func strava_import_fields() -> Array:
	return [
		{"id": "connect_profile", "label": t("APP_SET_STRAVA_CONNECT_PROFILE"), "type": "action", "run": strava_connect_profile,
			"enabled": func() -> bool: return strava_client_id != "" and strava_client_secret != "" and not strava_has_profile_scope()},
		{"id": "import_ftp", "label": t("APP_SET_STRAVA_IMPORT_FTP"), "type": "toggle",
			"get": func() -> Variant: return import_ftp, "set": func(v: Variant) -> void: import_ftp = bool(v)},
		{"id": "import_weight", "label": t("APP_SET_STRAVA_IMPORT_WEIGHT"), "type": "toggle",
			"get": func() -> Variant: return import_weight, "set": func(v: Variant) -> void: import_weight = bool(v)},
		{"id": "import", "label": t("APP_SET_STRAVA_IMPORT"), "type": "action", "run": strava_import,
			"enabled": func() -> bool: return strava_connected() and not importing and (import_ftp or import_weight)},
	]


## True when the Strava connection includes profile:read_all (GET /athlete's FTP and weight).
func strava_has_profile_scope() -> bool:
	if services.rides == null or not strava_connected():
		return false
	var scope := str(services.rides.strava_info().get("scope", ""))
	return scope.split(",").has("profile:read_all")


## Connect (or reconnect) with profile:read_all for the import.
func strava_connect_profile() -> void:
	if services.rides == null or strava_client_id == "" or strava_client_secret == "":
		return
	strava_state = "connecting"
	var secret := strava_client_secret
	strava_client_secret = ""
	refresh_fields()
	_refresh_status("strava")
	await services.rides.strava_connect_with_profile(strava_client_id, secret)
	if is_inside_tree():
		refresh_fields()


## Import the chosen values into the profile and save it. Returns Rides' result ({} when Strava
## gave nothing, for example without profile:read_all).
func strava_import() -> Dictionary:
	if services.rides == null or not strava_connected() or importing or not (import_ftp or import_weight):
		return {}
	importing = true
	refresh_fields()
	var res: Dictionary = await services.rides.strava_import_athlete(p(), import_ftp, import_weight)
	importing = false
	var applied: Array = res.get("applied", [])
	if applied.is_empty():
		import_result = t("APP_STRAVA_IMPORT_NONE")
	else:
		save_profile()
		var parts: PackedStringArray = []
		if applied.has("ftp"):
			parts.append(t("APP_STRAVA_IMPORT_FTP_DONE").format([int(round(p().ftp_w))]))
		if applied.has("weight"):
			parts.append(t("APP_STRAVA_IMPORT_WEIGHT_DONE").format([AppStyle.weight_text(p().weight_kg, p().units)]))
		import_result = ", ".join(parts)
	if is_inside_tree():
		refresh_fields()
		_refresh_status("strava")
	return res


func strava_status_text() -> String:
	if strava_state == "connecting":
		return t("APP_STRAVA_CONNECTING")
	if strava_state == "error":
		return t("APP_STRAVA_ERROR")
	return t("APP_STRAVA_CONNECTED") if strava_connected() else t("APP_STRAVA_DISCONNECTED")


## Connect with the player's own API app (Rides runs the loopback OAuth flow).
func strava_connect() -> void:
	if services.rides == null or strava_client_id == "" or strava_client_secret == "":
		return
	strava_state = "connecting"
	services.rides.strava_connect(strava_client_id, strava_client_secret)
	strava_client_secret = ""
	refresh_fields()
	_refresh_status("strava")


func strava_disconnect() -> void:
	if services.rides != null:
		services.rides.strava_disconnect()
	strava_state = ""
	refresh_fields()


func _on_strava_state(state: String, _detail: String) -> void:
	strava_state = state
	if state == "connected" and services.rides != null:
		services.rides.process_queue()
	refresh_fields()
	_refresh_status("strava")


# --- haptics, audio, network, pedal UI -------------------------------------------------------------

func _set_profile(prop: String, v: Variant) -> void:
	p().set(prop, v)
	save_profile()


func haptics_fields() -> Array:
	return [
		{"id": "haptics_on", "label": t("APP_SET_HAPTICS_ON"), "type": "toggle",
			"get": func() -> Variant: return p().haptics_on, "set": func(v: Variant) -> void: _set_profile("haptics_on", bool(v))},
		{"id": "haptic_intensity", "label": t("APP_SET_HAPTICS_INTENSITY"), "type": "stepper", "min": 0.0, "max": 100.0, "step": 10.0, "unit": "%",
			"get": func() -> Variant: return p().haptic_intensity_pct,
			"set": func(v: Variant) -> void: _set_profile("haptic_intensity_pct", float(v)),
			"enabled": func() -> bool: return p().haptics_on},
	]


func audio_fields() -> Array:
	return [
		{"id": "volume", "label": t("APP_SET_VOLUME"), "type": "stepper", "min": -30.0, "max": 0.0, "step": 3.0, "unit": "dB",
			"get": func() -> Variant: return float(services.settings.get_value("master_volume_db", 0.0)) if services.settings != null else 0.0,
			"set": set_volume},
		{"id": "metronome", "label": t("APP_SET_METRONOME"), "type": "toggle",
			"get": func() -> Variant: return p().metronome, "set": func(v: Variant) -> void: _set_profile("metronome", bool(v))},
	]


func set_volume(v: Variant) -> void:
	var db := float(v)
	set_setting("master_volume_db", db)
	apply_volume(db)


## Set the master bus volume (the Settings key master_volume_db; also applied at boot).
static func apply_volume(db: float) -> void:
	if AudioServer.bus_count > 0:
		AudioServer.set_bus_volume_db(0, clampf(db, -80.0, 6.0))


func network_fields() -> Array:
	return [
		{"id": "relay", "label": t("APP_SET_RELAY"), "type": "text", "rows": AppTextField.ROWS_URL, "max_length": 120,
			"get": func() -> Variant: return services.settings.relay_url() if services.settings != null else "",
			"set": func(v: Variant) -> void: set_setting("relay_url", str(v).strip_edges())},
	]


func pedal_fields() -> Array:
	return [
		{"id": "pedal_ui", "label": t("APP_SET_PEDAL_UI_ON"), "type": "toggle",
			"get": func() -> Variant: return p().pedal_ui, "set": set_pedal_ui},
		{"id": "scan_interval", "label": t("APP_SET_SCAN_INTERVAL"), "type": "stepper", "min": 0.8, "max": 4.0, "step": 0.2, "unit": "s", "decimals": 1,
			"get": func() -> Variant: return p().scan_interval_s, "set": set_scan_interval},
	]


func set_pedal_ui(v: Variant) -> void:
	_set_profile("pedal_ui", bool(v))
	set_scanning(scanning_enabled())


func set_scan_interval(v: Variant) -> void:
	_set_profile("scan_interval_s", float(v))
	for m in menus:
		m.scan_interval_s = p().scan_interval_s


# --- controls ----------------------------------------------------------------------------------

func controls_fields() -> Array:
	var fields: Array = []
	for a: StringName in Wl.ACTIONS:
		var label := "%s: %s" % [t("APP_ACTION_" + String(a).to_upper()), compact_binding_text(a)]
		fields.append({"id": "bind:" + String(a), "label": label, "type": "action", "run": start_capture.bind(a)})
	return fields


## Short labels (InputBindings.describe: "Enter", "A", "D-pad up") for every binding of `action`.
func binding_labels(action: StringName) -> Array[String]:
	var out: Array[String] = []
	if services.input != null:
		out = services.input.binding_labels(action)
	elif InputMap.has_action(action):
		for e: InputEvent in InputMap.action_get_events(action):
			var s := InputBindings.describe(e)
			if s != "":
				out.append(s)
	return out


## A menu row's bindings: the first keyboard and the first controller binding, short, so the row
## fits the 640 px menu column (W3 ZIH-3). The content column lists all of them.
func compact_binding_text(action: StringName) -> String:
	var key := ""
	var pad := ""
	if InputMap.has_action(action):
		for e: InputEvent in InputMap.action_get_events(action):
			var s := InputBindings.describe(e)
			if s == "":
				continue
			if (e is InputEventKey or e is InputEventMouseButton) and key == "":
				key = s
			elif (e is InputEventJoypadButton or e is InputEventJoypadMotion) and pad == "":
				pad = s
	var parts: PackedStringArray = []
	for s: String in [key, pad]:
		if s != "":
			parts.append(s)
	if parts.is_empty():
		var all := binding_labels(action)
		return all[0] if not all.is_empty() else "—"
	return ", ".join(parts)


## Every action with all its bindings, one line each (the Controls page's content column).
func all_bindings_text() -> String:
	var lines: PackedStringArray = []
	for a: StringName in Wl.ACTIONS:
		var labels := binding_labels(a)
		lines.append("%s: %s" % [t("APP_ACTION_" + String(a).to_upper()), ", ".join(labels) if not labels.is_empty() else "—"])
	return "\n".join(lines)


## The current bindings of `action` as text ("Enter, Space, Joypad Button 0").
static func binding_text(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "—"
	var parts: PackedStringArray = []
	for e: InputEvent in InputMap.action_get_events(action):
		parts.append(e.as_text())
	return ", ".join(parts) if not parts.is_empty() else "—"


## Wait for the next key, button or stick move and bind it to `action` (Esc cancels).
func start_capture(action: StringName) -> void:
	capturing = action
	if value_label != null:
		value_label.text = t("APP_SET_CAPTURE").format([t("APP_ACTION_" + String(action).to_upper())])


func capture_event(event: InputEvent) -> bool:
	if capturing == &"":
		return false
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return false
		if k.physical_keycode == KEY_ESCAPE or k.keycode == KEY_ESCAPE:
			_end_capture()
			return true
	elif event is InputEventJoypadButton:
		if not (event as InputEventJoypadButton).pressed:
			return false
		if (event as InputEventJoypadButton).button_index == JOY_BUTTON_B:
			# The controller's B (back) button cancels, as Esc does, so a controller-only rider
			# can always get out of a capture (W3 ZIH-4).
			_end_capture()
			return true
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) < 0.6:
			return false
	else:
		return false
	if services.input != null:
		services.input.rebind(capturing, event)
		services.input.save_bindings()
	_end_capture()
	return true


func _end_capture() -> void:
	if capturing == &"":
		return
	capturing = &""
	_capture_cooldown = true
	if value_label != null:
		value_label.text = ""
	for m in menus:
		var fields := fields_of(m)
		if not fields.is_empty() and str((fields[0] as Dictionary).get("id", "")).begins_with("bind:"):
			var fresh := controls_fields()
			fresh.append({"id": "back", "label": t("APP_BACK"), "type": "action", "run": _pop_section})
			_fields_by_menu[m.get_instance_id()] = fresh
			refresh_menu(items_for(fresh), m)


func _input(event: InputEvent) -> void:
	if capture_event(event):
		get_viewport().set_input_as_handled()


func _handle_action(_action: StringName) -> bool:
	return capturing != &"" or _capture_cooldown


func _tick(dt: float) -> void:
	_capture_cooldown = false
	if _unlink_pending.is_valid():
		_unlink_left -= dt
		if _unlink_left <= 1e-6:
			_run_unlink()


func _refresh_status(section: String) -> void:
	if status_label == null:
		return
	match section:
		"strava":
			status_label.text = t("APP_SET_STRAVA_HELP")
			if import_result != "":
				status_label.text += "\n" + import_result
		"trainer":
			var d := services.trainer.device() if services.trainer != null else null
			status_label.text = t("APP_SET_TRAINER_HELP").format([d.device_name() if d != null else "—"])
			if is_making_trainer_safe():
				status_label.text += "\n" + t("APP_SET_TRAINER_SAFE")
		"controls":
			status_label.text = all_bindings_text()
		_:
			status_label.text = ""
