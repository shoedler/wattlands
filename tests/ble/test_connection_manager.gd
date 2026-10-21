extends GutTest
## FtmsConnectionManager (BRIEF 4.2, 4.4) with fake transports and a fake FtmsClient:
## backend choice (GDBLE, then the bridge, then none with a clear status), the scan filter,
## connect -> FtmsClient.attach + begin -> trainer_ready, last-device persistence,
## auto-connect, the reconnect backoff (1, 2, 4, 8, 15, 15 s) on tick(dt), resubscribe and
## re-request control (begin again) followed by reconnected, control lost, timeouts and the
## hardware lock. Nothing here touches Bluetooth; every file goes to a temp Paths dir.

const FakeTransport := preload("res://tests/ble/fake_transport.gd")
const FakeClient := preload("res://tests/ble/fake_ftms_client.gd")
const FakeManager := preload("res://tests/ble/fake_bluetooth_manager.gd")
const FakeDevice := preload("res://tests/ble/fake_ble_device.gd")

const DT := 0.05
const ADDR := "C4:9D:A1:00:2B:7E"
const NAME := "KICKR CORE 2B7E"
const FTMS := "00001826-0000-1000-8000-00805f9b34fb"

var _dir: String = ""
var _gdble: FakeTransport = null
var _bridge: FakeTransport = null
var _client: FakeClient = null
var _m: FtmsConnectionManager = null
var _statuses: Array = []
var _ready_devices: Array = []
var _reconnected: Array = []
var _found: Array = []
var _control: Array = []
var _made: Array = []


func before_each() -> void:
	_dir = Paths.make_temp_dir("wattlands_ble_test")
	Paths.set_override(_dir)
	_statuses = []
	_ready_devices = []
	_reconnected = []
	_found = []
	_control = []
	_made = []
	_gdble = FakeTransport.new()
	_bridge = FakeTransport.new()
	_bridge.init_error = "bridge not reachable"
	_client = FakeClient.new()
	_m = _new_manager()
	add_child_autofree(_m)


func after_each() -> void:
	Paths.set_override("")
	_remove_tree(_dir)
	for v: Variant in [_gdble, _bridge, _client]:
		if not is_instance_valid(v):
			continue
		var n: Node = v
		if n.get_parent() == null and not n.is_queued_for_deletion():
			n.free()
	_gdble = null
	_bridge = null
	_client = null
	_m = null


func _new_manager() -> FtmsConnectionManager:
	var m := FtmsConnectionManager.new()
	m.manual_clock = true
	m.make_gdble = func() -> BleTransport: return _gdble
	m.make_bridge = func() -> BleTransport: return _bridge
	m.make_client = func() -> FtmsClient: return _client
	m.make_trainer = func(c: FtmsClient, n: String) -> TrainerDevice:
		_made.append([c, n])
		return TrainerDevice.new()
	m.status_changed.connect(func(s: String, d: String) -> void: _statuses.append([s, d]))
	m.trainer_ready.connect(func(d: TrainerDevice) -> void: _ready_devices.append(d))
	m.reconnected.connect(func(d: TrainerDevice) -> void: _reconnected.append(d))
	m.device_found.connect(func(info: Dictionary) -> void: _found.append(info))
	m.control_lost.connect(func(detail: String) -> void: _control.append(detail))
	return m


static func _remove_tree(dir: String) -> void:
	if dir.is_empty() or not DirAccess.dir_exists_absolute(dir):
		return
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in da.get_directories():
		_remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


func _run(seconds: float) -> void:
	for i in roundi(seconds / DT):
		_m.tick(DT)


func _ready_on(transport: FakeTransport) -> TrainerDevice:
	_m.start(false)
	transport.advertise(ADDR, NAME)
	_m.connect_to(ADDR)
	assert_eq(_ready_devices.size(), 1, "trainer ready")
	return _m.device()


func _last_status() -> Array:
	return _statuses.back() if not _statuses.is_empty() else []


# --- pure rules ------------------------------------------------------------------------

func test_backoff_delays() -> void:
	var got: Array[float] = []
	for n in 7:
		got.append(FtmsConnectionManager.backoff_delay(n))
	assert_eq(got, [1.0, 2.0, 4.0, 8.0, 15.0, 15.0, 15.0] as Array[float])


func test_scan_filter() -> void:
	assert_true(FtmsConnectionManager.is_trainer({"name": "", "services": [FTMS]}))
	assert_true(FtmsConnectionManager.is_trainer({"name": "", "services": ["00001826-0000-1000-8000-00805F9B34FB"]}))
	assert_true(FtmsConnectionManager.is_trainer({"name": "", "services": ["1826"]}))
	assert_true(FtmsConnectionManager.is_trainer({"name": "KICKR CORE 1A2B", "services": []}))
	assert_true(FtmsConnectionManager.is_trainer({"name": "my kickr", "services": []}))
	assert_true(FtmsConnectionManager.is_trainer({"name": "KiCkR", "services": ["180d"]}))
	assert_false(FtmsConnectionManager.is_trainer({"name": "HRM-Pro", "services": ["180d"]}))
	assert_false(FtmsConnectionManager.is_trainer({"name": null, "services": []}))
	assert_false(FtmsConnectionManager.is_trainer({}))
	assert_false(FtmsConnectionManager.is_trainer({"name": "Speed", "services": ["00001826-0000-1000-8000-00805f9b34fc"]}))


# --- backend choice ----------------------------------------------------------------------

func test_gdble_first() -> void:
	_m.start(false)
	assert_eq(_m.backend_name(), "gdble")
	assert_same(_m.transport(), _gdble)
	assert_eq(_gdble.count("initialize"), 1)
	assert_eq(_bridge.count("initialize"), 0)
	assert_eq(_gdble.last("start_scan"), ["start_scan", FtmsConnectionManager.DEFAULT_SCAN_S])
	assert_eq(_m.status(), TrainerDevice.STATUS_SCANNING)
	assert_eq(_gdble.get_parent(), _m)
	assert_eq(_gdble.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(_m.process_mode, Node.PROCESS_MODE_ALWAYS)


func test_bridge_when_gdble_is_not_loaded() -> void:
	_gdble.available = false
	_m.start(false)
	assert_eq(_m.backend_name(), "bridge")
	assert_same(_m.transport(), _bridge)
	assert_false(is_instance_valid(_gdble), "the unusable GDBLE transport is freed")
	assert_eq(_bridge.count("start_scan"), 1)


func test_no_adapter_falls_back_to_the_bridge_then_reports_it() -> void:
	_gdble.init_result = "fail"
	_bridge.init_result = "fail"
	_m.start(false)
	assert_eq(_m.backend_name(), "")
	assert_null(_m.transport())
	assert_eq(_bridge.count("initialize"), 1, "the bridge was tried after GDBLE had no adapter")
	assert_eq(_last_status(), [TrainerDevice.STATUS_DISCONNECTED, tr("BLE_STATUS_NO_ADAPTER")])
	assert_ne(tr("BLE_STATUS_NO_ADAPTER"), "BLE_STATUS_NO_ADAPTER", "translated")
	assert_push_warning("backend unavailable")


func test_nothing_available() -> void:
	_gdble.available = false
	_bridge.init_result = "fail"
	_m.start(false)
	assert_eq(_m.backend_name(), "")
	assert_eq(_last_status(), [TrainerDevice.STATUS_DISCONNECTED, tr("BLE_STATUS_NO_BACKEND")])
	assert_push_warning("no backend available")
	_m.scan()
	assert_push_warning("cannot scan")
	_m.connect_to(ADDR)
	assert_push_warning("cannot connect")


func test_start_again_after_nothing_was_available() -> void:
	_gdble.available = false
	_bridge.init_result = "fail"
	_m.start(false)
	_gdble = FakeTransport.new()
	_gdble.available = false
	_bridge = FakeTransport.new()
	_m.start(false)
	assert_eq(_m.backend_name(), "bridge", "a second start() tries the backends again")


func test_backend_that_never_answers_is_skipped() -> void:
	_gdble.init_result = "silent"
	_m.start(false)
	_run(FtmsConnectionManager.INIT_TIMEOUT_S - 0.5)
	assert_eq(_m.backend_name(), "", "still starting")
	assert_eq(_bridge.count("initialize"), 0)
	_run(0.5)
	assert_push_warning("no answer within")
	assert_eq(_m.backend_name(), "bridge")
	assert_eq(_bridge.count("start_scan"), 1)
	_gdble.adapter_ready.emit(true, "")
	assert_eq(_m.backend_name(), "bridge", "a late answer from the dropped backend is ignored")


func test_connect_during_start_up_waits_for_the_backend() -> void:
	_gdble.init_result = "silent"
	_m.start(false)
	_m.connect_to(ADDR)
	assert_eq(_gdble.count("initialize"), 1, "no second initialize() while starting")
	assert_eq(_gdble.count("connect_device"), 0)
	assert_eq(_m.status(), TrainerDevice.STATUS_CONNECTING)
	_gdble.adapter_ready.emit(true, "")
	assert_eq(_gdble.count("connect_device"), 1, "connects as soon as the backend is ready")
	assert_eq(_gdble.count("start_scan"), 0, "no scan while connecting")
	assert_true(_m.is_ready())


func test_connect_during_start_up_moves_to_the_bridge() -> void:
	_gdble.init_result = "silent"
	_m.start(false)
	_m.connect_to(ADDR)
	_gdble.adapter_ready.emit(false, "no adapter")
	assert_push_warning("backend unavailable")
	assert_eq(_m.backend_name(), "bridge")
	assert_eq(_bridge.count("connect_device"), 1)
	assert_true(_m.is_ready())


func test_connect_during_start_up_with_no_backend_stops() -> void:
	_gdble.init_result = "silent"
	_bridge.init_result = "fail"
	_m.start(false)
	_m.connect_to(ADDR)
	_gdble.adapter_ready.emit(false, "no adapter")
	assert_push_warning("no backend available")
	assert_eq(_m.backend_name(), "")
	assert_eq(_last_status(), [TrainerDevice.STATUS_DISCONNECTED, tr("BLE_STATUS_NO_ADAPTER")])
	_run(60.0)
	assert_false(_m.is_reconnecting())
	assert_eq(_m.retry_in(), 0.0)
	assert_eq(_last_status(), [TrainerDevice.STATUS_DISCONNECTED, tr("BLE_STATUS_NO_ADAPTER")], "the status stays clear")


func test_adapter_lost_while_idle_then_scan_initializes_again() -> void:
	_m.start(false)
	_gdble.adapter_ready.emit(false, "ADAPTER_UNAVAILABLE")
	assert_push_warning("adapter lost")
	assert_eq(_last_status(), [TrainerDevice.STATUS_DISCONNECTED, tr("BLE_STATUS_NO_ADAPTER")])
	_run(FtmsConnectionManager.DEFAULT_SCAN_S)
	assert_eq(_last_status(), [TrainerDevice.STATUS_DISCONNECTED, tr("BLE_STATUS_NO_ADAPTER")], "no scan end over it")
	_m.scan(5.0)
	assert_eq(_gdble.count("initialize"), 2, "initialize() again first")
	assert_eq(_gdble.last("start_scan"), ["start_scan", 5.0])
	assert_eq(_gdble.count("start_scan"), 2)
	assert_eq(_m.status(), TrainerDevice.STATUS_SCANNING)


func test_start_again_after_the_adapter_was_lost() -> void:
	FtmsConnectionManager.write_last_device(ADDR, NAME)
	_m.start(false)
	_gdble.adapter_ready.emit(false, "ADAPTER_UNAVAILABLE")
	_gdble.init_result = "fail"
	_m.scan()
	assert_eq(_gdble.count("start_scan"), 1, "no scan while the adapter is still gone")
	assert_eq(_last_status(), [TrainerDevice.STATUS_DISCONNECTED, tr("BLE_STATUS_NO_ADAPTER")])
	_gdble.init_result = "ok"
	_m.start(true)
	assert_eq(_gdble.last("start_scan"), ["start_scan", FtmsConnectionManager.AUTO_SCAN_S])
	_gdble.advertise(ADDR, NAME)
	assert_true(_m.is_ready(), "auto-connected once the adapter is back")


func test_scan_requested_while_the_backend_starts_is_queued() -> void:
	_gdble.init_result = "silent"
	_m.start(false)
	_m.scan(5.0)
	assert_eq(_gdble.count("start_scan"), 0)
	_gdble.adapter_ready.emit(true, "")
	assert_eq(_gdble.last("start_scan"), ["start_scan", 5.0])


# --- scanning ----------------------------------------------------------------------------

func test_scan_reports_trainers_only_once_each() -> void:
	_m.start(false)
	_gdble.advertise(ADDR, NAME)
	_gdble.advertise("11:11:11:11:11:11", "HRM-Pro", ["180d"])
	_gdble.advertise("22:22:22:22:22:22", "Trainer X", [FTMS])
	_gdble.advertise(ADDR.to_lower(), NAME)
	assert_eq(_found.size(), 2)
	assert_eq(_found[0]["address"], ADDR)
	assert_eq(_found[1]["address"], "22:22:22:22:22:22")
	var addrs: Array = []
	for d: Dictionary in _m.found_devices():
		addrs.append(d["address"])
	assert_eq(addrs, ["22:22:22:22:22:22", ADDR.to_lower()], "sorted, latest info kept")


func test_scan_ends_on_tick() -> void:
	_m.start(false)
	_run(FtmsConnectionManager.DEFAULT_SCAN_S - 0.5)
	assert_eq(_m.status(), TrainerDevice.STATUS_SCANNING)
	_run(0.5)
	assert_eq(_last_status(), [TrainerDevice.STATUS_DISCONNECTED, tr("BLE_STATUS_NONE_FOUND")])


func test_stop_scan() -> void:
	_m.start(false)
	_m.stop_scan()
	assert_eq(_gdble.count("stop_scan"), 1)
	assert_eq(_m.status(), TrainerDevice.STATUS_DISCONNECTED)


# --- connecting --------------------------------------------------------------------------

func test_connect_flow() -> void:
	_m.start(false)
	_gdble.advertise(ADDR, NAME)
	_m.connect_to(ADDR)
	assert_eq(_gdble.count("stop_scan"), 1, "connecting ends the scan")
	assert_eq(_gdble.last("connect_device"), ["connect_device", ADDR])
	assert_eq(_client.attached.size(), 1)
	assert_same(_client.attached[0], _gdble, "FtmsClient.attach(transport)")
	assert_eq(_client.begin_count, 1, "FtmsClient.begin()")
	assert_eq(_ready_devices.size(), 1)
	assert_same(_ready_devices[0], _m.device())
	assert_eq(_made, [[_client, NAME]], "FtmsTrainer created with the client and the name")
	assert_eq(_reconnected.size(), 0)
	assert_true(_m.is_ready())
	assert_eq(_last_status(), [TrainerDevice.STATUS_READY, tr("BLE_STATUS_READY").format({"name": NAME})])
	var states: Array = []
	for s: Array in _statuses:
		states.append(s[0])
	assert_eq(states, [TrainerDevice.STATUS_DISCONNECTED, TrainerDevice.STATUS_SCANNING,
		TrainerDevice.STATUS_CONNECTING, TrainerDevice.STATUS_CONNECTED, TrainerDevice.STATUS_READY])
	assert_eq(_client.get_parent(), _m)
	assert_eq(_client.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(_m.device().get_parent(), _m)
	assert_eq(_m.device().process_mode, Node.PROCESS_MODE_ALWAYS)


func test_connect_to_an_empty_address_is_an_error() -> void:
	_m.start(false)
	_m.connect_to("   ")
	assert_push_error("empty address")
	assert_eq(_gdble.count("connect_device"), 0)


func test_connect_timeout_retries() -> void:
	_m.start(false)
	_gdble.connect_result = "hang"
	_m.connect_to(ADDR)
	_run(FtmsConnectionManager.CONNECT_TIMEOUT_S - DT)
	assert_eq(_m.status(), TrainerDevice.STATUS_CONNECTING)
	_m.tick(DT)
	assert_eq(_gdble.count("disconnect_device"), 1, "the hung attempt is cancelled")
	assert_eq(_m.status(), TrainerDevice.STATUS_DISCONNECTED)
	assert_eq(_m.retry_in(), 1.0)
	_run(1.0)
	assert_eq(_gdble.count("connect_device"), 2)


func test_connect_to_while_connecting_sends_one_request() -> void:
	_m.start(false)
	_gdble.connect_result = "hang"
	_m.connect_to(ADDR)
	_m.connect_to(ADDR.to_lower())
	assert_eq(_gdble.count("connect_device"), 1, "already connecting: no second request")
	_run(FtmsConnectionManager.CONNECT_TIMEOUT_S)
	assert_eq(_m.retry_in(), 1.0)
	_m.connect_to(ADDR)
	assert_eq(_gdble.count("connect_device"), 2, "during a backoff wait it tries at once")
	_gdble.connect_result = "fail"
	_gdble.drop(ADDR)
	_m.connect_to(ADDR)
	assert_eq(_gdble.count("connect_device"), 3)
	assert_eq(_m.retry_in(), 1.0, "a manual try starts the backoff over")


func test_setup_timeout() -> void:
	_m.start(false)
	_client.begin_result = "silent"
	_m.connect_to(ADDR)
	assert_eq(_m.status(), TrainerDevice.STATUS_CONNECTED)
	_run(FtmsConnectionManager.SETUP_TIMEOUT_S)
	if Locks.hw_locked():
		assert_eq(_m.status(), TrainerDevice.STATUS_ERROR, "read-only under the lock: no retry loop")
		_run(60.0)
		assert_eq(_gdble.count("connect_device"), 1)
	else:
		assert_eq(_m.status(), TrainerDevice.STATUS_DISCONNECTED)
		assert_eq(_gdble.count("disconnect_device"), 1)


func test_setup_failure_under_the_hardware_lock_keeps_the_link() -> void:
	if not Locks.hw_locked():
		pending("needs WATTLANDS_NO_HW_CONTROL=1 (run through tools/godot.sh)")
		return
	_client.begin_result = "fail"
	_client.fail_reason = Locks.HW_MESSAGE
	_m.start(false)
	_m.connect_to(ADDR)
	assert_eq(_m.status(), TrainerDevice.STATUS_ERROR)
	assert_string_contains(_m.status_detail(), tr("BLE_STATUS_HW_LOCKED"))
	assert_eq(_ready_devices.size(), 0)
	_run(60.0)
	assert_eq(_gdble.count("connect_device"), 1, "no reconnect loop")
	assert_eq(_gdble.count("disconnect_device"), 0, "the read-only link stays")


func test_switching_to_another_trainer() -> void:
	var first := _ready_on(_gdble)
	_m.connect_to("11:22:33:44:55:66")
	assert_eq(_gdble.count("disconnect_device"), 1)
	assert_eq(_gdble.last("connect_device"), ["connect_device", "11:22:33:44:55:66"])
	assert_eq(_ready_devices.size(), 2)
	assert_ne(_ready_devices[1], first, "a new device for a new trainer")
	assert_eq(_reconnected.size(), 0, "not a reconnect")
	assert_true(first.is_queued_for_deletion())
	_gdble.drop(ADDR)
	assert_true(_m.is_ready(), "the old trainer's disconnect is ignored")


# --- last device -------------------------------------------------------------------------

func test_last_device_is_saved_when_ready() -> void:
	assert_eq(_m.last_device(), {})
	_ready_on(_gdble)
	assert_eq(_m.last_device(), {"address": ADDR, "name": NAME})
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(Paths.last_device_path()))
	assert_eq(parsed, {"address": ADDR, "name": NAME})
	assert_true(Paths.last_device_path().begins_with(_dir), "under the test profile dir")


func test_last_device_file_errors_are_warnings() -> void:
	var f := FileAccess.open(Paths.last_device_path(), FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	assert_eq(FtmsConnectionManager.read_last_device(), {})
	assert_push_warning("unreadable last device")
	f = FileAccess.open(Paths.last_device_path(), FileAccess.WRITE)
	f.store_string("{\"name\": \"KICKR\"}")
	f.close()
	assert_eq(FtmsConnectionManager.read_last_device(), {})
	assert_push_warning("without an address")
	assert_true(FtmsConnectionManager.write_last_device(" AA:BB ", "KICKR"))
	assert_eq(FtmsConnectionManager.read_last_device(), {"address": "AA:BB", "name": "KICKR"})


# --- auto-connect ------------------------------------------------------------------------

func test_auto_connect_to_the_last_device() -> void:
	FtmsConnectionManager.write_last_device(ADDR, NAME)
	_m.start(true)
	assert_eq(_gdble.last("start_scan"), ["start_scan", FtmsConnectionManager.AUTO_SCAN_S])
	_gdble.advertise("22:22:22:22:22:22", "KICKR CORE 2222")
	assert_eq(_gdble.count("connect_device"), 0, "another trainer is not auto-connected")
	_gdble.advertise(ADDR.to_lower(), NAME, [FTMS])
	assert_eq(_gdble.last("connect_device"), ["connect_device", ADDR.to_lower()])
	assert_eq(_gdble.count("stop_scan"), 1)
	assert_eq(_ready_devices.size(), 1)
	assert_eq(_made[0][1], NAME)


func test_auto_connect_keeps_looking_for_the_last_device() -> void:
	FtmsConnectionManager.write_last_device(ADDR, NAME)
	_m.start(true)
	_run(FtmsConnectionManager.AUTO_SCAN_S)
	assert_eq(_gdble.count("start_scan"), 2, "a new window when the first ends")
	assert_eq(_m.status(), TrainerDevice.STATUS_SCANNING, "still looking, no 'none found'")
	_run(FtmsConnectionManager.AUTO_SCAN_S * 2)
	assert_eq(_gdble.count("start_scan"), 4)
	_gdble.advertise(ADDR, NAME)
	assert_true(_m.is_ready(), "a trainer switched on later is still picked up")
	_run(FtmsConnectionManager.AUTO_SCAN_S * 2)
	assert_eq(_gdble.count("start_scan"), 4, "no scanning once linked")


func test_stop_scan_ends_the_auto_connect_search() -> void:
	FtmsConnectionManager.write_last_device(ADDR, NAME)
	_m.start(true)
	_m.stop_scan()
	_run(FtmsConnectionManager.AUTO_SCAN_S * 2)
	assert_eq(_gdble.count("start_scan"), 1)
	assert_eq(_m.status(), TrainerDevice.STATUS_DISCONNECTED)
	_gdble.advertise(ADDR, NAME)
	assert_eq(_gdble.count("connect_device"), 0, "auto-connect is off until start(true)")
	_m.start(true)
	assert_eq(_gdble.count("start_scan"), 2)
	_gdble.advertise(ADDR, NAME)
	assert_true(_m.is_ready())


func test_no_auto_connect_when_off() -> void:
	FtmsConnectionManager.write_last_device(ADDR, NAME)
	_m.start(false)
	assert_eq(_gdble.last("start_scan"), ["start_scan", FtmsConnectionManager.DEFAULT_SCAN_S])
	_gdble.advertise(ADDR, NAME)
	assert_eq(_gdble.count("connect_device"), 0)
	assert_eq(_found.size(), 1)


func test_auto_connect_with_no_last_device_only_scans() -> void:
	_m.start(true)
	_gdble.advertise(ADDR, NAME)
	assert_eq(_gdble.count("connect_device"), 0)
	assert_eq(_found.size(), 1)


# --- reconnect ---------------------------------------------------------------------------

func test_backoff_sequence_on_tick() -> void:
	_ready_on(_gdble)
	_gdble.connect_result = "fail"
	_gdble.drop(ADDR)
	assert_eq(_last_status(), [TrainerDevice.STATUS_DISCONNECTED, tr("BLE_STATUS_LOST").format({"s": 1, "error": ""})])
	assert_true(_m.is_reconnecting())
	var attempts_at: Array[float] = []
	var seen := _gdble.count("connect_device")
	var steps := roundi(46.0 / DT)
	for i in steps:
		_m.tick(DT)
		var n := _gdble.count("connect_device")
		if n > seen:
			attempts_at.append((i + 1) * DT)
			seen = n
	assert_eq(attempts_at.size(), 6, "attempts at %s" % [attempts_at])
	var gaps: Array[float] = []
	var prev := 0.0
	for t: float in attempts_at:
		gaps.append(snappedf(t - prev, 0.01))
		prev = t
	assert_eq(gaps, [1.0, 2.0, 4.0, 8.0, 15.0, 15.0] as Array[float])


func test_reconnect_resubscribes_and_signals_the_governor() -> void:
	var dev := _ready_on(_gdble)
	_gdble.drop(ADDR)
	_run(0.95)
	assert_eq(_gdble.count("connect_device"), 1, "waits the first 1 s")
	_run(0.05)
	assert_eq(_gdble.count("connect_device"), 2)
	assert_eq(_client.begin_count, 2, "begin() again: resubscribe and re-request control")
	assert_eq(_client.attached.size(), 1, "attached once per transport")
	assert_eq(_ready_devices, [dev, dev], "the same device, ready again")
	assert_eq(_reconnected, [dev], "the governor is asked to restore the last safe mode")
	assert_eq(_made.size(), 1)
	assert_false(_m.is_reconnecting())
	# The backoff starts over after a good reconnect.
	_gdble.drop(ADDR)
	_run(1.0)
	assert_eq(_gdble.count("connect_device"), 3)
	assert_eq(_reconnected.size(), 2)


func test_failed_attempt_then_success() -> void:
	_ready_on(_gdble)
	_gdble.connect_result = "fail"
	_gdble.drop(ADDR)
	_run(1.0)
	assert_string_contains(_m.status_detail(), "unreachable")
	_gdble.connect_result = "ok"
	_run(2.0)
	assert_eq(_reconnected.size(), 1)
	assert_true(_m.is_ready())


func test_disconnect_trainer_stops_reconnecting() -> void:
	_ready_on(_gdble)
	_m.disconnect_trainer()
	assert_eq(_gdble.count("disconnect_device"), 1)
	assert_eq(_last_status(), [TrainerDevice.STATUS_DISCONNECTED, tr("BLE_STATUS_DISCONNECTED")])
	_gdble.drop(ADDR, "local")
	_run(30.0)
	assert_eq(_gdble.count("connect_device"), 1, "no reconnect after a requested disconnect")


func test_gatt_reset_runs_begin_again() -> void:
	var dev := _ready_on(_gdble)
	_gdble.operation_failed.emit(GdbleTransport.OP_GATT_RESET, "SERVICES_CHANGED")
	assert_eq(_client.begin_count, 2)
	assert_eq(_reconnected, [dev])
	assert_eq(_gdble.count("connect_device"), 1, "the link stays up")


func test_adapter_lost_reinitializes_before_reconnecting() -> void:
	var dev := _ready_on(_gdble)
	_gdble.adapter_ready.emit(false, "bridge closed")
	assert_push_warning("adapter lost")
	_gdble.drop(ADDR, "bridge closed")
	assert_true(_m.is_reconnecting())
	_run(1.0)
	assert_eq(_gdble.count("initialize"), 2, "initialize() again first")
	assert_eq(_gdble.count("connect_device"), 2)
	assert_eq(_reconnected, [dev])


func test_adapter_lost_under_a_gdble_link_reconnects_for_real() -> void:
	# The real GdbleTransport over the fake GDBLE manager: after the adapter comes back the
	# reconnect must call connect_async() again, not take the "already linked" shortcut.
	var fake_mgr: FakeManager = FakeManager.new()
	var gt := GdbleTransport.new()
	gt.manager_factory = func() -> Node: return fake_mgr
	_m.make_gdble = func() -> BleTransport: return gt
	_m.start(false)
	assert_eq(_m.backend_name(), "gdble")
	_m.connect_to(ADDR)
	var d: FakeDevice = fake_mgr.devices[ADDR.to_lower()]
	d.connected.emit()
	assert_true(_m.is_ready())
	fake_mgr.ble_event.emit({"operation": &"initialize", "phase": &"failed", "operation_id": 0,
		"terminal": false, "device_address": "", "service_uuid": "", "characteristic_uuid": "",
		"data": null, "error": {"code": "ADAPTER_UNAVAILABLE", "message": "", "retryable": true, "details": {}}})
	assert_push_warning("adapter unavailable")
	assert_false(gt.is_link_up())
	assert_true(_m.is_reconnecting())
	_run(1.0)
	assert_eq(fake_mgr.count("initialize"), 2, "the adapter is initialized again first")
	assert_eq(d.count("connect_async"), 2, "a real reconnect")
	d.connected.emit()
	assert_true(_m.is_ready())
	assert_eq(_reconnected.size(), 1)


func test_adapter_still_missing_backs_off() -> void:
	_ready_on(_gdble)
	_gdble.adapter_ready.emit(false, "ADAPTER_UNAVAILABLE")
	_gdble.init_result = "fail"
	_run(1.0)
	assert_eq(_gdble.count("initialize"), 2)
	assert_eq(_gdble.count("connect_device"), 1)
	assert_eq(_m.retry_in(), 2.0)


func test_process_drives_the_clock() -> void:
	_ready_on(_gdble)
	_gdble.drop(ADDR)
	_m.manual_clock = false
	_m._process(1.0)
	assert_eq(_gdble.count("connect_device"), 2)
	_m.manual_clock = true
	_gdble.drop(ADDR)
	_m._process(5.0)
	assert_eq(_gdble.count("connect_device"), 2, "manual_clock stops _process")


# --- control -----------------------------------------------------------------------------

func test_control_lost_during_setup() -> void:
	_client.begin_result = "control_lost"
	_m.start(false)
	_m.connect_to(ADDR)
	assert_eq(_m.status(), TrainerDevice.STATUS_CONTROL_LOST)
	assert_string_contains(_m.status_detail().to_lower(), "another app may hold control")
	assert_eq(_control, [_m.status_detail()])
	assert_eq(_ready_devices.size(), 0)
	_run(60.0)
	assert_eq(_client.begin_count, 1, "no automatic grab of control")
	assert_eq(_gdble.count("connect_device"), 1)
	_client.begin_result = "ready"
	_m.retry_control()
	assert_eq(_client.begin_count, 2)
	assert_eq(_ready_devices.size(), 1)
	assert_eq(_reconnected.size(), 0, "first time ready")


func test_control_lost_while_riding() -> void:
	var dev := _ready_on(_gdble)
	_client.control_lost.emit("Machine Status 0xFF")
	assert_eq(_m.status(), TrainerDevice.STATUS_CONTROL_LOST)
	assert_eq(_control.size(), 1)
	assert_false(_m.is_ready())
	_m.retry_control()
	assert_true(_m.is_ready())
	assert_eq(_reconnected, [dev], "the governor restores the last safe mode")


func test_connect_to_the_linked_trainer() -> void:
	_ready_on(_gdble)
	_m.connect_to(ADDR.to_lower())
	assert_eq(_gdble.count("connect_device"), 1, "already ready: nothing to do")
	_client.control_lost.emit("Machine Status 0xFF")
	_m.connect_to(ADDR)
	assert_eq(_gdble.count("connect_device"), 1, "no second connect")
	assert_eq(_client.begin_count, 2, "begin() again after the control loss")
	assert_true(_m.is_ready())


func test_gatt_reset_after_a_control_loss_does_not_take_control() -> void:
	_ready_on(_gdble)
	_client.control_lost.emit("Machine Status 0xFF")
	_gdble.operation_failed.emit(GdbleTransport.OP_GATT_RESET, "SERVICES_CHANGED")
	assert_eq(_client.begin_count, 1, "no begin(): it would request control again")
	assert_eq(_m.status(), TrainerDevice.STATUS_CONTROL_LOST)
	_m.retry_control()
	assert_eq(_client.begin_count, 2)
	assert_true(_m.is_ready())


func test_retry_control_only_when_lost() -> void:
	_ready_on(_gdble)
	_m.retry_control()
	assert_eq(_client.begin_count, 1)


func test_runs_while_the_tree_is_paused() -> void:
	_ready_on(_gdble)
	var tree := get_tree()
	tree.paused = true
	var running := [_m.can_process(), _m.transport().can_process(), _m.client().can_process(),
		_m.device().can_process()]
	tree.paused = false
	assert_eq(running, [true, true, true, true], "manager, transport, client and device keep running")


# --- strings and defaults ----------------------------------------------------------------

func test_status_strings_are_translated() -> void:
	for key: String in ["BLE_STATUS_STARTING", "BLE_STATUS_NO_ADAPTER", "BLE_STATUS_NO_BACKEND",
			"BLE_STATUS_SCANNING", "BLE_STATUS_NONE_FOUND", "BLE_STATUS_CONNECTING", "BLE_STATUS_SETUP",
			"BLE_STATUS_READY", "BLE_STATUS_LOST", "BLE_STATUS_RETRY", "BLE_STATUS_SETUP_FAILED",
			"BLE_STATUS_HW_LOCKED", "BLE_STATUS_CONTROL_HELD", "BLE_STATUS_DISCONNECTED"]:
		assert_ne(tr(key), key, key)
	assert_string_contains(tr("BLE_STATUS_CONTROL_HELD").to_lower(), "another app may hold control")


func test_default_trainer_factory() -> void:
	_m.make_trainer = Callable()
	_ready_on(_gdble)
	assert_true(_m.device() is FtmsTrainer)


func test_default_transport_factories() -> void:
	var m := FtmsConnectionManager.new()
	var g := m._make_transport(FtmsConnectionManager.BACKEND_GDBLE)
	var b := m._make_transport(FtmsConnectionManager.BACKEND_BRIDGE)
	assert_true(g is GdbleTransport)
	assert_true(b is BridgeTransport)
	assert_null(m._make_transport("dircon"))
	g.free()
	b.free()
	m.free()
