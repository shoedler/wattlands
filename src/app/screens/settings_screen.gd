class_name AppSettingsScreen
extends AppFormScreen
## Settings (BRIEF 3.2, 3.5, 3.8, 3.9), every page on pedal-scan:
##   Trainer   status, scan and connect (FtmsConnectionManager), use the mock trainer, disconnect
##   Strava    the player's own API app client ID and secret, connect (loopback OAuth), disconnect,
##             auto-upload (off by default). The secret is only passed to Rides.strava_connect and
##             never shown, logged or kept here.
##   Haptics   accept haptic effects on/off, intensity 0-100 %
##   Controls  rebind every action (saved to input.cfg by InputRouter)
##   Audio     master volume, cadence metronome
##   Network   relay URL
##   Pedal UI  pedal-scan menus on/off, scan interval
##   FTP test (P1) and Rides history (P1) open their own pages.

const MOCK_SPEC := "erg"

var status_label: Label = null
var strava_client_id: String = ""
var strava_client_secret: String = ""
var strava_state: String = ""
var found_devices: Array[Dictionary] = []
var capturing: StringName = &""
var _capture_cooldown: bool = false
var _trainer_menu: PedalScanList = null
var _connection: FtmsConnectionManager = null


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
	var list := open_fields(fields)
	if section == "trainer":
		_trainer_menu = list
	_refresh_status(section)


func _pop_section() -> void:
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
	if _connection != null:
		_connection.connect_to(address)
	_refresh_status("trainer")


func use_mock() -> void:
	if services.trainer != null:
		services.trainer.use_mock(MOCK_SPEC)
	_rebuild_trainer_page()


func disconnect_trainer() -> void:
	if _connection != null:
		_connection.disconnect_trainer()
	_rebuild_trainer_page()


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
	return [
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
	if AudioServer.bus_count > 0:
		AudioServer.set_bus_volume_db(0, db)


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
		var label := "%s: %s" % [t("APP_ACTION_" + String(a).to_upper()), binding_text(a)]
		fields.append({"id": "bind:" + String(a), "label": label, "type": "action", "run": start_capture.bind(a)})
	return fields


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


func _tick(_dt: float) -> void:
	_capture_cooldown = false


func _refresh_status(section: String) -> void:
	if status_label == null:
		return
	match section:
		"strava":
			status_label.text = t("APP_SET_STRAVA_HELP")
		"trainer":
			var d := services.trainer.device() if services.trainer != null else null
			status_label.text = t("APP_SET_TRAINER_HELP").format([d.device_name() if d != null else "—"])
		_:
			status_label.text = ""
