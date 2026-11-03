class_name AppSettingsScreen
extends AppFormScreen
## Settings (BRIEF 3.2, 3.5, 3.8, 3.9), every page on pedal-scan:
##   Trainer   status, scan (FtmsConnectionManager), connect, use the mock trainer, disconnect;
##             with the mock active also "Keyboard controls the mock trainer" (Settings mock_keyboard).
##             Connect, Disconnect and the mock go through TrainerService.connect_trainer(),
##             disconnect_trainer() and use_mock(): before a link drops (Disconnect, another
##             trainer, the mock) the rider's governor goes SIM flat, then Stop, and the link
##             waits until the control point sent both (BRIEF 4.6.9; W4 SAF-8, W4r2 R6). Picking
##             the trainer that is already linked changes nothing (W4r2 R7). Leaving the page never
##             cuts that wait short.
##   Sensors   opened from the Trainer page (the root menu fills a 1080p screen): the heart rate
##             sensor (TrainerService.hr_manager(), HrSensorManager): status, live bpm, scan
##             (0x180D or a heart-rate-like name), pair, forget. The paired sensor is remembered
##             and reconnects by itself.
##   Strava    the player's own API app client ID and secret, connect (loopback OAuth), disconnect,
##             auto-upload (off by default), and the opt-in FTP and weight import (P1, BRIEF 3.8:
##             connect with profile:read_all, pick FTP and/or weight, import). The secret is only
##             passed to Rides and never shown, logged or kept here.
##   Haptics   accept haptic effects on/off, intensity 0-100 %
##   Controls  rebind every action (saved to input.cfg by InputRouter): each row shows the action
##             with its first keyboard and controller binding, the content column all of them.
##             Esc or the controller's B button cancels a capture, and so does leaving the page;
##             the page says so. Reset to defaults, the first row, puts every project.godot default
##             back after a Keep / Reset confirm that highlights Keep, Esc and B on `back`
##             included, and saves input.cfg (InputRouter.reset_bindings, save_bindings). The page
##             is taller than a 1080p screen, so the menu column scrolls and keeps the highlighted
##             row in view (AppScreen.scroll_menu_column).
##   Audio     master volume, cadence metronome
##   Network   relay URL
##   Pedal navigation  on/off (default off: keyboard and controller only), scan interval
##   FTP test (P1) and Rides history (P1) open their own pages.

const MOCK_SPEC := "erg"

var status_label: Label = null
## The Controls page's one-line help above the bindings list (Esc or B cancels a capture, Reset
## to defaults gets them back); hidden on the other pages.
var controls_help_label: Label = null
var strava_client_id: String = ""
var strava_client_secret: String = ""
var strava_state: String = ""
var found_devices: Array[Dictionary] = []
var capturing: StringName = &""
var _capture_cooldown: bool = false
var _trainer_menu: PedalScanList = null
## The Reset to defaults confirm menu while it is open.
var _reset_menu: PedalScanList = null
var _connection: FtmsConnectionManager = null
## Settings > Sensors: the heart rate sensors the last scan found, the page's menu, and the
## TrainerService's HrSensorManager (null with a mock trainer).
var found_sensors: Array[Dictionary] = []
var _sensors_menu: PedalScanList = null
var _hr: HrSensorManager = null
var _shown_bpm: int = -1
## True while this page waits for TrainerService's safe unlink (its status line says so).
var _unlink_shown: bool = false
## The FTP and weight import (P1): what to import, and the last result line.
var import_ftp: bool = true
var import_weight: bool = false
var import_result: String = ""
var importing: bool = false


func _build() -> void:
	make_form_page(t("APP_SETTINGS_TITLE"))
	controls_help_label = AppStyle.paragraph(
		t("APP_SET_CONTROLS_HELP"), AppStyle.FONT_SMALL, AppStyle.TEXT_DIM
	)
	controls_help_label.name = "ControlsHelp"
	controls_help_label.visible = false
	content_box.add_child(controls_help_label)
	status_label = AppStyle.paragraph("", AppStyle.FONT_BODY, AppStyle.TEXT)
	status_label.name = "Status"
	content_box.add_child(status_label)
	if services.bus != null:
		services.bus.strava_state_changed.connect(_on_strava_state)
	if services.trainer != null:
		services.trainer.status_changed.connect(_on_trainer_status)
		_sync_connection()
		_sync_hr()
	open_fields(root_fields(), _back)
	var start_page := str(params.get("section", ""))
	if start_page != "":
		open_section(start_page)


func _on_leave() -> void:
	# A link drop still waiting for the safe commands keeps waiting in TrainerService.
	_end_capture()
	if services.bus != null and services.bus.strava_state_changed.is_connected(_on_strava_state):
		services.bus.strava_state_changed.disconnect(_on_strava_state)
	if (
		services.trainer != null
		and services.trainer.status_changed.is_connected(_on_trainer_status)
	):
		services.trainer.status_changed.disconnect(_on_trainer_status)
	if (
		_connection != null
		and is_instance_valid(_connection)
		and _connection.device_found.is_connected(_on_device_found)
	):
		_connection.device_found.disconnect(_on_device_found)
	_link_hr(false)
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
		{
			"id": "trainer",
			"label": t("APP_SET_TRAINER"),
			"type": "action",
			"run": open_section.bind("trainer")
		},
		{
			"id": "strava",
			"label": t("APP_SET_STRAVA"),
			"type": "action",
			"run": open_section.bind("strava")
		},
		{
			"id": "haptics",
			"label": t("APP_SET_HAPTICS"),
			"type": "action",
			"run": open_section.bind("haptics")
		},
		{
			"id": "controls",
			"label": t("APP_SET_CONTROLS"),
			"type": "action",
			"run": open_section.bind("controls")
		},
		{
			"id": "audio",
			"label": t("APP_SET_AUDIO"),
			"type": "action",
			"run": open_section.bind("audio")
		},
		{
			"id": "network",
			"label": t("APP_SET_NETWORK"),
			"type": "action",
			"run": open_section.bind("network")
		},
		{
			"id": "pedal_nav",
			"label": t("APP_SET_PEDAL_NAV"),
			"type": "action",
			"run": open_section.bind("pedal_nav")
		},
		{
			"id": "ftp_test",
			"label": t("APP_SET_FTP_TEST"),
			"type": "action",
			"run": func() -> void: goto("settings", {"page": "ftp_test"})
		},
		{
			"id": "rides",
			"label": t("APP_SET_RIDES"),
			"type": "action",
			"run": func() -> void: goto("settings", {"page": "rides"})
		},
		{"id": "back", "label": t("APP_BACK"), "type": "action", "run": _back},
	]


## Open a settings page by id ("trainer", "strava", "haptics", "controls", "audio", "network",
## "pedal_nav").
func open_section(section: String) -> void:
	var fields: Array = []
	match section:
		"trainer":
			fields = trainer_fields()
		"sensors":
			fields = sensors_fields()
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
		"pedal_nav":
			fields = pedal_fields()
	if fields.is_empty():
		return
	fields.append({"id": "back", "label": t("APP_BACK"), "type": "action", "run": _pop_section})
	# A coast or back on a page goes through _pop_section too, so it ends a key capture (W3 ZIH-4).
	var list := open_fields(fields, _pop_section)
	if section == "trainer":
		_trainer_menu = list
	if section == "sensors":
		_sensors_menu = list
	_refresh_status(section)


func _pop_section() -> void:
	_end_capture()
	if menus.size() > 1:
		pop_menu()
	_trainer_menu = null
	_sensors_menu = null
	_refresh_status("")


# --- trainer ---------------------------------------------------------------------------------


func trainer_fields() -> Array:
	var fields: Array = [
		{
			"id": "status",
			"label": t("APP_SET_TRAINER_STATUS"),
			"type": "info",
			"get": trainer_status_text
		},
		{
			"id": "scan",
			"label": t("APP_SET_TRAINER_SCAN"),
			"type": "action",
			"run": scan_trainers,
			"enabled": func() -> bool: return _connection != null
		},
	]
	for d: Dictionary in found_devices:
		var addr := str(d.get("address", ""))
		fields.append(
			{
				"id": "dev:" + addr,
				"label":
				t("APP_SET_TRAINER_CONNECT").format(
					[str(d.get("name", addr)), int(d.get("rssi", 0))]
				),
				"type": "action",
				"run": connect_trainer.bind(addr)
			}
		)
	fields.append(
		{"id": "mock", "label": t("APP_SET_TRAINER_MOCK"), "type": "action", "run": use_mock}
	)
	if services.trainer != null and services.trainer.is_mock():
		fields.append(
			{
				"id": "mock_keyboard",
				"label": t("APP_SET_TRAINER_MOCK_KEYS"),
				"type": "toggle",
				"get": mock_keyboard_on,
				"set": func(v: Variant) -> void: set_setting("mock_keyboard", bool(v))
			}
		)
	fields.append(
		{
			"id": "sensors",
			"label": t("APP_SET_SENSORS"),
			"type": "action",
			"run": open_section.bind("sensors")
		}
	)
	fields.append(
		{
			"id": "disconnect",
			"label": t("APP_SET_TRAINER_DISCONNECT"),
			"type": "action",
			"run": disconnect_trainer,
			"enabled": func() -> bool: return _connection != null
		}
	)
	return fields


## The Settings key mock_keyboard (or --mock-keyboard): the keyboard drives the mock trainer.
func mock_keyboard_on() -> bool:
	if CmdLine.get_bool("mock-keyboard", false):
		return true
	return services.settings != null and bool(services.settings.get_value("mock_keyboard", false))


func trainer_status_text() -> String:
	return AppLobbyCard.trainer_text(services.trainer.status() if services.trainer != null else "")


func scan_trainers() -> void:
	found_devices.clear()
	if _connection != null:
		_connection.scan(10.0)
	_refresh_status("trainer")


## Connect to `address` (TrainerService.connect_trainer): a switch from another linked trainer
## makes that one safe first (SIM flat, then Stop, then the link drops); the trainer that is
## already linked, or none, connects at once and the menu rider stays as it is (W4r2 R7).
func connect_trainer(address: String) -> void:
	if _connection == null or services.trainer == null:
		_refresh_status("trainer")
		return
	services.trainer.connect_trainer(address)
	_watch_unlink()


## Use the mock trainer (TrainerService.use_mock): a real trainer is made safe first.
func use_mock() -> void:
	if services.trainer != null:
		services.trainer.use_mock(MOCK_SPEC)
	_sync_connection()
	_watch_unlink()
	_rebuild_trainer_page()


## Disconnect (TrainerService.disconnect_trainer): the rider's governor goes SIM flat, then
## Stop, and the link drops once the control point sent both (or after the service's timeout).
## The next trainer that is ready gets a new menu rider.
func disconnect_trainer() -> void:
	if _connection == null or services.trainer == null:
		_rebuild_trainer_page()
		return
	services.trainer.disconnect_trainer()
	_watch_unlink()
	_rebuild_trainer_page()


## True while TrainerService waits for the old trainer's SIM flat and Stop before a link drops.
func is_making_trainer_safe() -> bool:
	return services != null and services.trainer != null and services.trainer.is_unlinking()


func _watch_unlink() -> void:
	_unlink_shown = is_making_trainer_safe()
	_refresh_status("trainer")


func _on_device_found(info: Dictionary) -> void:
	var addr := str(info.get("address", ""))
	for d: Dictionary in found_devices:
		if str(d.get("address", "")) == addr:
			return
	found_devices.append(info.duplicate(true))
	_rebuild_trainer_page()


func _rebuild_trainer_page() -> void:
	if (
		_trainer_menu == null
		or not is_instance_valid(_trainer_menu)
		or not menus.has(_trainer_menu)
	):
		return
	var fields := trainer_fields()
	fields.append({"id": "back", "label": t("APP_BACK"), "type": "action", "run": _pop_section})
	_fields_by_menu[_trainer_menu.get_instance_id()] = fields
	refresh_menu(items_for(fields), _trainer_menu)
	_refresh_status("trainer")


func _on_trainer_status(_status: String, _detail: String) -> void:
	_sync_connection()
	_sync_hr()
	refresh_fields()


## Follow TrainerService's connection manager (the mock has none; the old one is freed once its
## safe unlink ran), so Scan and Disconnect never reach a retired manager.
func _sync_connection() -> void:
	var now: FtmsConnectionManager = (
		services.trainer.connection() if services.trainer != null else null
	)
	if _connection != null and not is_instance_valid(_connection):
		_connection = null
	if now == _connection:
		return
	if _connection != null and _connection.device_found.is_connected(_on_device_found):
		_connection.device_found.disconnect(_on_device_found)
	_connection = now
	if _connection != null:
		_connection.device_found.connect(_on_device_found)


# --- sensors ---------------------------------------------------------------------------------


func sensors_fields() -> Array:
	var fields: Array = [
		{
			"id": "hr_status",
			"label": t("APP_SET_SENSORS_STATUS"),
			"type": "info",
			"get": sensor_status_text
		},
		{"id": "hr_bpm", "label": t("APP_SET_SENSORS_BPM"), "type": "info", "get": heart_rate_text},
		{
			"id": "hr_scan",
			"label": t("APP_SET_SENSORS_SCAN"),
			"type": "action",
			"run": scan_sensors,
			"enabled": func() -> bool: return _hr != null
		},
	]
	for d: Dictionary in found_sensors:
		var addr := str(d.get("address", ""))
		var label := str(d.get("name", ""))
		fields.append(
			{
				"id": "hr:" + addr,
				"label":
				t("APP_SET_SENSORS_PAIR").format(
					[label if label != "" else addr, int(d.get("rssi", 0))]
				),
				"type": "action",
				"run": pair_sensor.bind(addr, label)
			}
		)
	fields.append(
		{
			"id": "hr_forget",
			"label": t("APP_SET_SENSORS_FORGET"),
			"type": "action",
			"run": forget_sensor,
			"enabled": _has_sensor
		}
	)
	return fields


## "Ready (Polar H10)", "Connecting to ..." or "No sensor": the manager's status and detail.
func sensor_status_text() -> String:
	if _hr == null:
		return t("APP_SET_SENSORS_NONE_AVAILABLE")
	var detail := _hr.status_detail()
	if _hr.status() == TrainerDevice.STATUS_DISCONNECTED and detail == "":
		var last := _hr.last_sensor()
		return (
			t("APP_SET_SENSORS_NONE")
			if last.is_empty()
			else t("APP_SET_SENSORS_REMEMBERED").format([str(last.get("name", last["address"]))])
		)
	return detail if detail != "" else _hr.status()


func heart_rate_text() -> String:
	if _hr == null or not _hr.is_ready():
		return "—"
	if _hr.no_contact():
		return t("APP_SET_SENSORS_NO_CONTACT")
	var bpm := _hr.current_bpm()
	return t("APP_SET_SENSORS_BPM_VALUE").format([bpm]) if bpm > 0 else "—"


func scan_sensors() -> void:
	found_sensors.clear()
	if _hr != null:
		_hr.scan(10.0)
	_rebuild_sensors_page()


func pair_sensor(address: String, sensor_name: String) -> void:
	if _hr != null:
		_hr.connect_to(address, sensor_name)
	_rebuild_sensors_page()


func forget_sensor() -> void:
	if _hr != null:
		_hr.forget()
	_rebuild_sensors_page()


func _has_sensor() -> bool:
	return _hr != null and (not _hr.sensor().is_empty() or not _hr.last_sensor().is_empty())


func _rebuild_sensors_page() -> void:
	if (
		_sensors_menu == null
		or not is_instance_valid(_sensors_menu)
		or not menus.has(_sensors_menu)
	):
		return
	var fields := sensors_fields()
	fields.append({"id": "back", "label": t("APP_BACK"), "type": "action", "run": _pop_section})
	_fields_by_menu[_sensors_menu.get_instance_id()] = fields
	refresh_menu(items_for(fields), _sensors_menu)


## Follow TrainerService's heart rate sensor manager (created with the FTMS path).
func _sync_hr() -> void:
	var now: HrSensorManager = services.trainer.hr_manager() if services.trainer != null else null
	if _hr != null and not is_instance_valid(_hr):
		_hr = null
	if now == _hr:
		return
	_link_hr(false)
	_hr = now
	_link_hr(true)


func _link_hr(on: bool) -> void:
	if _hr == null or not is_instance_valid(_hr):
		return
	for pair: Array in [
		[_hr.device_found, _on_sensor_found],
		[_hr.status_changed, _on_sensor_status],
		[_hr.heart_rate, _on_heart_rate],
	]:
		var sig: Signal = pair[0]
		if on and not sig.is_connected(pair[1]):
			sig.connect(pair[1])
		elif not on and sig.is_connected(pair[1]):
			sig.disconnect(pair[1])


func _on_sensor_found(info: Dictionary) -> void:
	var addr := str(info.get("address", ""))
	for d: Dictionary in found_sensors:
		if str(d.get("address", "")) == addr:
			return
	found_sensors.append(info.duplicate(true))
	_rebuild_sensors_page()


func _on_sensor_status(_status: String, _detail: String) -> void:
	_rebuild_sensors_page()


func _on_heart_rate(bpm: int) -> void:
	if bpm != _shown_bpm:
		_shown_bpm = bpm
		_rebuild_sensors_page()


# --- strava ----------------------------------------------------------------------------------


func strava_connected() -> bool:
	return services.rides != null and services.rides.strava_connected()


func strava_fields() -> Array:
	var fields: Array = [
		{
			"id": "strava_status",
			"label": t("APP_SET_STRAVA_STATUS"),
			"type": "info",
			"get": strava_status_text
		},
		{
			"id": "client_id",
			"label": t("APP_SET_STRAVA_ID"),
			"type": "text",
			"rows": AppTextField.ROWS_DIGITS,
			"max_length": 12,
			"get": func() -> Variant: return strava_client_id,
			"set": func(v: Variant) -> void: strava_client_id = str(v).strip_edges()
		},
		{
			"id": "client_secret",
			"label": t("APP_SET_STRAVA_SECRET"),
			"type": "text",
			"rows": AppTextField.ROWS_HEX,
			"max_length": 64,
			"secret": true,
			"get": func() -> Variant: return strava_client_secret,
			"set": func(v: Variant) -> void: strava_client_secret = str(v).strip_edges()
		},
		{
			"id": "connect",
			"label": t("APP_SET_STRAVA_CONNECT"),
			"type": "action",
			"run": strava_connect,
			"enabled": can_connect_strava
		},
		{
			"id": "disconnect",
			"label": t("APP_SET_STRAVA_DISCONNECT"),
			"type": "action",
			"run": strava_disconnect,
			"enabled": strava_connected
		},
		{
			"id": "auto_upload",
			"label": t("APP_SET_STRAVA_AUTO"),
			"type": "toggle",
			"get": func() -> Variant: return p().strava_auto_upload,
			"set": func(v: Variant) -> void: _set_profile("strava_auto_upload", bool(v))
		},
	]
	fields.append_array(strava_import_fields())
	return fields


func can_connect_strava() -> bool:
	return strava_client_id != "" and strava_client_secret != "" and not strava_connected()


## The opt-in FTP and weight import (BRIEF 3.2, 3.8 P1): connect with profile:read_all, choose
## FTP and/or weight, import (an imported FTP is verified and CP follows it).
func strava_import_fields() -> Array:
	return [
		{
			"id": "connect_profile",
			"label": t("APP_SET_STRAVA_CONNECT_PROFILE"),
			"type": "action",
			"run": strava_connect_profile,
			"enabled": can_connect_profile
		},
		{
			"id": "import_ftp",
			"label": t("APP_SET_STRAVA_IMPORT_FTP"),
			"type": "toggle",
			"get": func() -> Variant: return import_ftp,
			"set": func(v: Variant) -> void: import_ftp = bool(v)
		},
		{
			"id": "import_weight",
			"label": t("APP_SET_STRAVA_IMPORT_WEIGHT"),
			"type": "toggle",
			"get": func() -> Variant: return import_weight,
			"set": func(v: Variant) -> void: import_weight = bool(v)
		},
		{
			"id": "import",
			"label": t("APP_SET_STRAVA_IMPORT"),
			"type": "action",
			"run": strava_import,
			"enabled": can_import
		},
	]


func can_connect_profile() -> bool:
	return strava_client_id != "" and strava_client_secret != "" and not strava_has_profile_scope()


func can_import() -> bool:
	return strava_connected() and not importing and (import_ftp or import_weight)


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
	if (
		services.rides == null
		or not strava_connected()
		or importing
		or not (import_ftp or import_weight)
	):
		return {}
	importing = true
	refresh_fields()
	var res: Dictionary = await import_from_strava(services, p(), import_ftp, import_weight)
	importing = false
	var applied: Array = res.get("applied", [])
	if applied.is_empty():
		import_result = t("APP_STRAVA_IMPORT_NONE")
	else:
		var parts: PackedStringArray = []
		if applied.has("ftp"):
			parts.append(t("APP_STRAVA_IMPORT_FTP_DONE").format([int(round(p().ftp_w))]))
		if applied.has("weight"):
			parts.append(
				t("APP_STRAVA_IMPORT_WEIGHT_DONE").format(
					[AppStyle.weight_text(p().weight_kg, p().units)]
				)
			)
		import_result = ", ".join(parts)
	if is_inside_tree():
		refresh_fields()
		_refresh_status("strava")
	return res


## The import itself (Rides.strava_import_athlete, then the profile saved and profile_changed).
## Rides writes the imported values into the live profile while GET /athlete runs, so the save
## must not depend on the page: a static coroutine has no page instance to lose, so leaving the
## page mid-request still saves the import (W4r2 R20). Returns Rides' result.
static func import_from_strava(
	s: AppServices, profile: RiderProfile, ftp: bool, weight: bool
) -> Dictionary:
	if s == null or s.rides == null or profile == null:
		return {}
	var res: Dictionary = await s.rides.strava_import_athlete(profile, ftp, weight)
	if not (res.get("applied", []) as Array).is_empty():
		if s.settings != null:
			s.settings.save_profile()
		if s.bus != null:
			s.bus.profile_changed.emit()
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
		{
			"id": "haptics_on",
			"label": t("APP_SET_HAPTICS_ON"),
			"type": "toggle",
			"get": func() -> Variant: return p().haptics_on,
			"set": func(v: Variant) -> void: _set_profile("haptics_on", bool(v))
		},
		{
			"id": "haptic_intensity",
			"label": t("APP_SET_HAPTICS_INTENSITY"),
			"type": "stepper",
			"min": 0.0,
			"max": 100.0,
			"step": 10.0,
			"unit": "%",
			"get": func() -> Variant: return p().haptic_intensity_pct,
			"set": func(v: Variant) -> void: _set_profile("haptic_intensity_pct", float(v)),
			"enabled": func() -> bool: return p().haptics_on
		},
	]


func audio_fields() -> Array:
	return [
		{
			"id": "volume",
			"label": t("APP_SET_VOLUME"),
			"type": "stepper",
			"min": -30.0,
			"max": 0.0,
			"step": 3.0,
			"unit": "dB",
			"get": current_volume_db,
			"set": set_volume
		},
		_bus_field("vol_machines", "APP_SET_VOL_MACHINES", AudioBuses.MACHINES),
		_bus_field("vol_ambience", "APP_SET_VOL_AMBIENCE", AudioBuses.AMBIENCE),
		_bus_field("vol_sfx", "APP_SET_VOL_SFX", AudioBuses.SFX),
		_bus_field("vol_ui", "APP_SET_VOL_UI", AudioBuses.UI),
		{
			"id": "metronome",
			"label": t("APP_SET_METRONOME"),
			"type": "toggle",
			"get": func() -> Variant: return p().metronome,
			"set": func(v: Variant) -> void: _set_profile("metronome", bool(v))
		},
		{
			"id": "fullscreen",
			"label": t("APP_SET_FULLSCREEN"),
			"type": "toggle",
			"get": fullscreen_on,
			"set": set_fullscreen
		},
	]


func _bus_field(id: String, label_key: String, bus: String) -> Dictionary:
	return {
		"id": id,
		"label": t(label_key),
		"type": "stepper",
		"min": -30.0,
		"max": 0.0,
		"step": 3.0,
		"unit": "dB",
		"get": _bus_db.bind(bus),
		"set": _set_bus_db.bind(bus)
	}


func _bus_db(bus: String) -> float:
	return AudioBuses.user_db(bus)


## The Settings key of a bus level, applied at once.
func _set_bus_db(v: Variant, bus: String) -> void:
	var db := float(v)
	set_setting(AudioBuses.SETTING_KEYS[bus], db)
	AudioBuses.set_user_db(bus, db)


func fullscreen_on() -> bool:
	return WlWindowMode.stored(services.settings)


## The Settings key `fullscreen`, applied to the window at once (WlWindowMode).
func set_fullscreen(v: Variant) -> void:
	WlWindowMode.set_fullscreen(services.settings, bool(v))


func current_volume_db() -> float:
	return (
		float(services.settings.get_value("master_volume_db", 0.0))
		if services.settings != null
		else 0.0
	)


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
		{
			"id": "relay",
			"label": t("APP_SET_RELAY"),
			"type": "text",
			"rows": AppTextField.ROWS_URL,
			"max_length": 120,
			"get": current_relay_url,
			"set": func(v: Variant) -> void: set_setting("relay_url", normalized_relay(v))
		},
	]


static func normalized_relay(typed: Variant) -> String:
	return RelayTransport.normalize_url(str(typed))


## The Relay field: blank while no relay is chosen (rooms run on the host's PC).
func current_relay_url() -> String:
	if services.settings == null:
		return ""
	var url := services.settings.relay_url()
	return "" if url == RelayTransport.DEFAULT_URL else url


func pedal_fields() -> Array:
	return [
		{
			"id": "pedal_nav",
			"label": t("APP_SET_PEDAL_NAV_ON"),
			"type": "toggle",
			"get": func() -> Variant: return p().pedal_nav,
			"set": set_pedal_nav
		},
		{
			"id": "scan_interval",
			"label": t("APP_SET_SCAN_INTERVAL"),
			"type": "stepper",
			"min": 0.8,
			"max": 4.0,
			"step": 0.2,
			"unit": "s",
			"decimals": 1,
			"enabled": func() -> bool: return p().pedal_nav,
			"get": func() -> Variant: return p().scan_interval_s,
			"set": set_scan_interval
		},
	]


func set_pedal_nav(v: Variant) -> void:
	_set_profile("pedal_nav", bool(v))
	set_scanning(scanning_enabled())


func set_scan_interval(v: Variant) -> void:
	_set_profile("scan_interval_s", float(v))
	for m in menus:
		m.scan_interval_s = p().scan_interval_s


# --- controls ----------------------------------------------------------------------------------


## The Controls page's rows: Reset to defaults first, then one row per action. Esc and B cancel
## a capture, so they can never be captured: Reset is how a rider who moved `back` off them gets
## them back (BRIEF 3.5 defaults). It comes first, where it is on screen when the page opens; the
## action rows and Back run below a 1080p screen and scroll into view as they are highlighted.
func controls_fields() -> Array:
	var fields: Array = [
		{
			"id": "reset_controls",
			"label": t("APP_SET_CONTROLS_RESET"),
			"type": "action",
			"run": ask_reset_controls
		}
	]
	for a: StringName in InputBindings.actions():
		var label := "%s: %s" % [t("APP_ACTION_" + String(a).to_upper()), compact_binding_text(a)]
		fields.append(
			{
				"id": "bind:" + String(a),
				"label": label,
				"type": "action",
				"run": start_capture.bind(a)
			}
		)
	return fields


## True for a Controls page menu (its rows rebind actions).
func _is_controls_menu(list: PedalScanList) -> bool:
	for f: Dictionary in fields_of(list):
		if str(f.get("id", "")).begins_with("bind:"):
			return true
	return false


## Ask before Reset to defaults: Keep (highlighted first, so a stray surge keeps the bindings)
## or Reset. Back, a coast or Keep returns to the Controls page unchanged.
func ask_reset_controls() -> void:
	_end_capture()
	if _reset_menu != null and menus.has(_reset_menu):
		return
	var fields: Array = [
		{
			"id": "keep",
			"label": t("APP_SET_CONTROLS_RESET_KEEP"),
			"type": "action",
			"run": close_reset_controls
		},
		{
			"id": "reset",
			"label": t("APP_SET_CONTROLS_RESET_YES"),
			"type": "action",
			"run": reset_controls
		},
	]
	_reset_menu = open_fields(fields, close_reset_controls, 0)
	_refresh_status("controls_reset")


## Put every action back to its project.godot binding (Esc and B on `back` again) and save
## input.cfg (InputRouter.reset_bindings, save_bindings), then return to the Controls page.
func reset_controls() -> void:
	if services.input != null:
		services.input.reset_bindings()
		services.input.save_bindings()
	close_reset_controls()


## Close the Reset to defaults confirm (if open) and show the Controls page as it is now.
func close_reset_controls() -> void:
	if _reset_menu != null and is_instance_valid(_reset_menu) and active_menu() == _reset_menu:
		pop_menu()
	_reset_menu = null
	_refresh_controls_menus()


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
	for a: StringName in InputBindings.actions():
		var labels := binding_labels(a)
		lines.append(
			(
				"%s: %s"
				% [
					t("APP_ACTION_" + String(a).to_upper()),
					", ".join(labels) if not labels.is_empty() else "—"
				]
			)
		)
	return "\n".join(lines)


## Wait for the next key, button or stick move and bind it to `action` (Esc or B cancels).
func start_capture(action: StringName) -> void:
	capturing = action
	if value_label != null:
		value_label.text = t("APP_SET_CAPTURE").format(
			[t("APP_ACTION_" + String(action).to_upper())]
		)


func capture_event(event: InputEvent) -> bool:
	if capturing == &"" or WlWindowMode.is_toggle_event(event):
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
	_refresh_controls_menus()


## Rebuild every open Controls page's rows (each shows its action's bindings now) and, when one
## is on show, the content column's list of every binding.
func _refresh_controls_menus() -> void:
	var on_controls := false
	for m in menus:
		if _is_controls_menu(m):
			var fresh := controls_fields()
			fresh.append(
				{"id": "back", "label": t("APP_BACK"), "type": "action", "run": _pop_section}
			)
			_fields_by_menu[m.get_instance_id()] = fresh
			refresh_menu(items_for(fresh), m)
			on_controls = on_controls or m == active_menu()
	# The content column lists every binding: a rebind changes this action's line and, since
	# InputBindings.rebind takes the input away from any other action, maybe others (W4r2 R28).
	if on_controls:
		_refresh_status("controls")


func _input(event: InputEvent) -> void:
	if capture_event(event):
		get_viewport().set_input_as_handled()


func _handle_action(_action: StringName) -> bool:
	return capturing != &"" or _capture_cooldown


func _tick(_dt: float) -> void:
	_capture_cooldown = false
	# The status line drops its "making the trainer safe" note once the link action ran.
	if _unlink_shown and not is_making_trainer_safe():
		_unlink_shown = false
		_rebuild_trainer_page()


func _refresh_status(section: String) -> void:
	if status_label == null:
		return
	if controls_help_label != null:
		controls_help_label.visible = section == "controls"
	# One line per action: the Controls list uses the small size so every row fits at 1080p.
	status_label.add_theme_font_size_override(
		"font_size", AppStyle.FONT_SMALL if section == "controls" else AppStyle.FONT_BODY
	)
	match section:
		"strava":
			status_label.text = t("APP_SET_STRAVA_HELP")
			if import_result != "":
				status_label.text += "\n" + import_result
		"trainer":
			var d := services.trainer.device() if services.trainer != null else null
			status_label.text = t("APP_SET_TRAINER_HELP").format(
				[d.device_name() if d != null else "—"]
			)
			if is_making_trainer_safe():
				status_label.text += "\n" + t("APP_SET_TRAINER_SAFE")
		"sensors":
			status_label.text = t("APP_SET_SENSORS_HELP")
		"controls":
			status_label.text = all_bindings_text()
		"controls_reset":
			status_label.text = t("APP_SET_CONTROLS_RESET_ASK")
		_:
			status_label.text = ""
