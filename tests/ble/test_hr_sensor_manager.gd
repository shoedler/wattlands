extends GutTest
## HrSensorManager with a fake transport: the scan filter (0x180D or a heart-rate-like name),
## connect -> discover -> subscribe 0x2A37 -> ready, notifications -> current_bpm() (stale,
## zero and no-contact readings are 0), remembering and forgetting the sensor, auto-connect to
## the remembered sensor, the reconnect backoff, a transport that is not there yet, and that
## the sensor is never written to. Every file goes to a temp Paths dir.

const FakeHr := preload("res://tests/ble/fake_hr_transport.gd")

const DT := 0.05
const ADDR := "E8:11:22:33:44:55"
const NAME := "Polar H10 1A2B3C4D"
const HRS := "0000180d-0000-1000-8000-00805f9b34fb"

var _dir: String = ""
var _t: FakeHr = null
var _m: HrSensorManager = null
var _bpms: Array = []
var _found: Array = []


func before_each() -> void:
	_dir = Paths.make_temp_dir("wattlands_hr_test")
	Paths.set_override(_dir)
	_bpms = []
	_found = []
	_t = FakeHr.new()
	_m = _new_manager(func() -> BleTransport: return _t)
	add_child_autofree(_m)


func after_each() -> void:
	Paths.set_override("")
	_remove_tree(_dir)
	if is_instance_valid(_t) and _t.get_parent() == null:
		_t.free()
	_t = null


func _new_manager(factory: Callable) -> HrSensorManager:
	var m := HrSensorManager.new()
	m.manual_clock = true
	m.make_transport = factory
	m.heart_rate.connect(func(b: int) -> void: _bpms.append(b))
	m.device_found.connect(func(i: Dictionary) -> void: _found.append(i))
	return m


static func _remove_tree(dir: String) -> void:
	if dir.is_empty() or not DirAccess.dir_exists_absolute(dir):
		return
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _run(seconds: float) -> void:
	for i in roundi(seconds / DT):
		_m.tick(DT)


func _pair() -> void:
	_m.connect_to(ADDR, NAME)
	assert_true(_m.is_ready(), "precondition: ready")


func test_scan_lists_heart_rate_sensors_only() -> void:
	_m.scan(10.0)
	assert_eq(_t.count("start_scan"), 1)
	assert_eq(_m.status(), TrainerDevice.STATUS_SCANNING)
	_t.advertise(ADDR, "", [HRS])
	_t.advertise("AA:00:00:00:00:01", "KICKR CORE 2B7E", ["00001826-0000-1000-8000-00805f9b34fb"])
	_t.advertise("AA:00:00:00:00:02", "Forerunner 255")
	_t.advertise("AA:00:00:00:00:03", "TICKR X 1234")
	_t.advertise("AA:00:00:00:00:04", "HR-Strap")
	_t.advertise("AA:00:00:00:00:05", "Chrome")
	var addrs: Array = []
	for d: Dictionary in _m.found_devices():
		addrs.append(d["address"])
	assert_eq(addrs, ["AA:00:00:00:00:02", "AA:00:00:00:00:03", "AA:00:00:00:00:04", ADDR])
	assert_eq(_found.size(), 4)
	_run(10.0)
	assert_eq(_m.status(), TrainerDevice.STATUS_DISCONNECTED, "the scan window ended")


func test_pair_subscribes_and_never_writes() -> void:
	_pair()
	assert_eq(_t.count("discover_services"), 1)
	assert_eq(_t.last("subscribe_characteristic"), ["subscribe_characteristic", "180d", "2a37"])
	assert_eq(_t.count("write_characteristic"), 0, "a heart rate sensor is never written to")
	assert_eq(_m.status(), TrainerDevice.STATUS_READY)
	assert_eq(HrSensorManager.read_last_sensor(), {"address": ADDR, "name": NAME}, "remembered")


func test_notifications_give_the_heart_rate() -> void:
	_pair()
	assert_eq(_m.current_bpm(), 0, "nothing measured yet")
	_t.measure(PackedByteArray([0x06, 128]))
	assert_eq(_m.current_bpm(), 128)
	assert_eq(_bpms, [128])
	_t.measure(PackedByteArray([0x04, 131]))
	assert_eq(_m.current_bpm(), 0, "no skin contact")
	assert_true(_m.no_contact())
	_t.measure(PackedByteArray([0x01, 0x8C, 0x00]))
	assert_eq(_m.current_bpm(), 140, "uint16 heart rate without contact detection")
	_run(4.9)
	assert_eq(_m.current_bpm(), 140)
	_run(0.2)
	assert_eq(_m.current_bpm(), 0, "stale after 5 s without a measurement")


func test_other_characteristics_are_ignored() -> void:
	_pair()
	_t.characteristic_notified.emit("00002a19-0000-1000-8000-00805f9b34fb", PackedByteArray([90]))
	assert_eq(_m.current_bpm(), 0)


func test_a_device_without_the_heart_rate_service_is_refused() -> void:
	_t.services = [{"uuid": "0000180f-0000-1000-8000-00805f9b34fb", "characteristics": []}]
	_m.connect_to(ADDR, "Speaker")
	assert_false(_m.is_ready())
	assert_eq(_t.count("subscribe_characteristic"), 0)
	assert_eq(_t.count("disconnect_device"), 1)
	assert_eq(HrSensorManager.read_last_sensor(), {}, "not remembered")


func test_a_lost_link_reconnects_with_backoff() -> void:
	_pair()
	_t.measure(PackedByteArray([0x00, 120]))
	_t.connect_result = "fail"
	_t.drop(ADDR)
	assert_false(_m.is_ready())
	assert_eq(_m.current_bpm(), 0, "no heart rate while the link is down")
	assert_eq(_bpms.back(), 0)
	var connects := _t.count("connect_device")
	_run(0.95)
	assert_eq(_t.count("connect_device"), connects, "first retry after 1 s")
	_run(0.1)
	assert_eq(_t.count("connect_device"), connects + 1)
	_run(1.9)
	assert_eq(_t.count("connect_device"), connects + 1, "then 2 s")
	_run(0.15)
	assert_eq(_t.count("connect_device"), connects + 2)
	_t.connect_result = "ok"
	_run(4.1)
	assert_true(_m.is_ready(), "reconnected after 4 s more")
	assert_eq(_t.count("subscribe_characteristic"), 2, "subscribed again")
	assert_eq(_t.count("write_characteristic"), 0)


func test_disconnect_and_forget() -> void:
	_pair()
	_m.disconnect_sensor()
	assert_false(_m.is_ready())
	_t.drop(ADDR, "local")
	_run(20.0)
	assert_eq(_t.count("connect_device"), 1, "no reconnect after a requested disconnect")
	assert_false(HrSensorManager.read_last_sensor().is_empty(), "still remembered")
	_m.forget()
	assert_true(HrSensorManager.read_last_sensor().is_empty(), "forgotten")
	assert_false(FileAccess.file_exists(Paths.last_hr_sensor_path()))


func test_start_connects_the_remembered_sensor_when_seen() -> void:
	HrSensorManager.write_last_sensor(ADDR, NAME)
	_m.start(true)
	assert_eq(_t.count("start_scan"), 1, "looks for the remembered sensor")
	_t.advertise("AA:00:00:00:00:09", "HRM-Dual", [HRS])
	assert_eq(_t.count("connect_device"), 0, "not another sensor")
	_t.advertise(ADDR.to_lower(), NAME, [HRS])
	assert_true(_m.is_ready(), "connected the remembered sensor")
	assert_eq(_m.sensor()["address"], ADDR.to_lower())


func test_start_without_a_remembered_sensor_stays_idle() -> void:
	_m.start(true)
	_run(60.0)
	assert_eq(_t.count("initialize"), 0, "no Bluetooth work until a scan")
	assert_eq(_m.status(), TrainerDevice.STATUS_DISCONNECTED)


func test_waits_for_a_transport() -> void:
	var available := [false]
	var made: Array = []
	var m := _new_manager(
		func() -> BleTransport:
			if not available[0]:
				return null
			made.append(_t)
			return _t
	)
	add_child_autofree(m)
	m.scan(10.0)
	assert_eq(m.status(), TrainerDevice.STATUS_DISCONNECTED)
	assert_ne(m.status_detail(), "", "says why")
	available[0] = true
	for i in roundi(3.1 / DT):
		m.tick(DT)
	assert_eq(made.size(), 1, "asked again after 3 s")
	assert_eq(_t.count("start_scan"), 1, "the queued scan runs once the adapter is ready")


func test_adapter_loss_drops_the_transport() -> void:
	_pair()
	_t.adapter_ready.emit(false, "adapter lost")
	assert_false(_m.is_ready())
	assert_eq(_m.current_bpm(), 0)
	await wait_process_frames(1)
	assert_null(_m.transport(), "dropped; asked for again on the next attempt")
