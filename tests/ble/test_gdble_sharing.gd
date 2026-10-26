extends GutTest
## Two GdbleTransports on one BluetoothManager (the trainer and a heart rate sensor): the second
## shares the first's manager and never initializes the adapter again, each transport reports
## only its own device's link and notifications, one scan serves both, and the sharing
## transport loses the adapter with its primary. Nothing here touches Bluetooth.

const FakeManager := preload("res://tests/ble/fake_bluetooth_manager.gd")
const FakeDevice := preload("res://tests/ble/fake_ble_device.gd")

const KICKR := "C4:9D:A1:00:2B:7E"
const HRM := "E8:11:22:33:44:55"
const HR_CHAR := "00002a37-0000-1000-8000-00805f9b34fb"

var _mgr: FakeManager = null
var _trainer: GdbleTransport = null
var _hr: GdbleTransport = null
var _hr_events: Array = []
var _trainer_events: Array = []


func before_each() -> void:
	_hr_events = []
	_trainer_events = []
	_mgr = FakeManager.new()
	_trainer = GdbleTransport.new()
	_trainer.manager_factory = func() -> Node: return _mgr
	add_child_autofree(_trainer)
	_hr = GdbleTransport.new()
	_hr.share_manager_of(_trainer)
	add_child_autofree(_hr)
	_record(_trainer, _trainer_events)
	_record(_hr, _hr_events)


func after_each() -> void:
	if is_instance_valid(_mgr) and _mgr.get_parent() == null:
		_mgr.free()
	_mgr = null


func _record(t: GdbleTransport, into: Array) -> void:
	t.adapter_ready.connect(
		func(ok: bool, e: String) -> void: into.append(["adapter_ready", ok, e])
	)
	t.device_connected.connect(func(a: String) -> void: into.append(["connected", a]))
	t.device_disconnected.connect(
		func(a: String, r: String) -> void: into.append(["disconnected", a, r])
	)
	t.characteristic_notified.connect(
		func(c: String, d: PackedByteArray) -> void: into.append(["notified", c, d])
	)


func _named(events: Array, what: String) -> Array:
	return events.filter(func(e: Array) -> bool: return e[0] == what)


func test_the_second_transport_never_initializes_the_adapter_again() -> void:
	_trainer.initialize()
	assert_eq(_mgr.count("initialize"), 1)
	_hr.initialize()
	await wait_process_frames(1)
	assert_eq(_mgr.count("initialize"), 1, "the trainer's manager is not initialized twice")
	assert_eq(_named(_hr_events, "adapter_ready"), [["adapter_ready", true, ""]])
	assert_eq(_named(_trainer_events, "adapter_ready").size(), 1, "the trainer hears nothing new")
	assert_true(_hr.is_available())
	assert_eq(_hr.primary(), _trainer)


func test_before_the_primary_has_a_manager_it_reports_not_ready() -> void:
	_hr.initialize()
	await wait_process_frames(1)
	assert_eq(_named(_hr_events, "adapter_ready").size(), 1)
	assert_false(_named(_hr_events, "adapter_ready")[0][1])


func test_each_transport_reports_only_its_own_device() -> void:
	_trainer.initialize()
	_hr.initialize()
	await wait_process_frames(1)
	_trainer.connect_device(KICKR)
	_hr.connect_device(HRM)
	var hr_dev: FakeDevice = _mgr.devices[HRM.to_lower()]
	var kickr_dev: FakeDevice = _mgr.devices[KICKR.to_lower()]
	assert_ne(hr_dev, kickr_dev)
	hr_dev.connected.emit()
	kickr_dev.connected.emit()
	_mgr.device_connected.emit(HRM)
	assert_eq(_named(_hr_events, "connected"), [["connected", HRM]])
	assert_eq(_named(_trainer_events, "connected"), [["connected", KICKR]])
	_hr.subscribe_characteristic("180d", "2a37")
	assert_eq(hr_dev.last("subscribe_characteristic")[2], HR_CHAR)
	hr_dev.characteristic_notified.emit(HR_CHAR, PackedByteArray([0, 120]))
	assert_eq(_named(_hr_events, "notified").size(), 1)
	assert_eq(_named(_trainer_events, "notified").size(), 0)
	_mgr.device_disconnected.emit(HRM)
	assert_eq(_named(_hr_events, "disconnected").size(), 1)
	assert_eq(_named(_trainer_events, "disconnected").size(), 0, "the trainer stays linked")


func test_one_scan_serves_both() -> void:
	_trainer.initialize()
	_hr.initialize()
	await wait_process_frames(1)
	_trainer.start_scan(30.0)
	_hr.start_scan(10.0)
	assert_eq(_mgr.count("start_scan"), 2)
	assert_eq(_mgr.count("stop_scan"), 1, "restarted, not started twice")
	assert_almost_eq(float(_mgr.calls.back()[1]), 30.0, 0.5, "covers the longer window")
	_hr.stop_scan()
	assert_eq(_mgr.count("stop_scan"), 1, "the trainer's window still runs")
	_trainer.stop_scan()
	assert_eq(_mgr.count("stop_scan"), 2)


func test_the_sharing_transport_loses_the_adapter_with_its_primary() -> void:
	_trainer.initialize()
	_hr.initialize()
	await wait_process_frames(1)
	_hr.connect_device(HRM)
	(_mgr.devices[HRM.to_lower()] as FakeDevice).connected.emit()
	remove_child(_trainer)
	assert_eq(_named(_hr_events, "disconnected"), [["disconnected", HRM, "adapter lost"]])
	assert_eq(_named(_hr_events, "adapter_ready").back(), ["adapter_ready", false, "adapter lost"])
	assert_false(_hr.is_link_up())
	add_child(_trainer)


## App quit: the sensor's transport leaves the tree before the trainer's, so the primary's
## departure must not report an adapter loss (no "backend unavailable" warning at quit).
func test_a_sharer_already_out_of_the_tree_stays_quiet() -> void:
	_trainer.initialize()
	_hr.initialize()
	await wait_process_frames(1)
	_hr.connect_device(HRM)
	(_mgr.devices[HRM.to_lower()] as FakeDevice).connected.emit()
	var before := _hr_events.size()
	remove_child(_hr)
	remove_child(_trainer)
	assert_eq(_hr_events.size(), before, "nothing reported")
	assert_null(_hr.primary(), "but it let go of the manager")
	add_child(_trainer)
	add_child(_hr)


## GDBLE's structured subscribe success becomes subscribed(char_uuid).
func test_a_subscribe_success_is_reported() -> void:
	_trainer.initialize()
	_hr.initialize()
	await wait_process_frames(1)
	_hr.connect_device(HRM)
	var dev := _mgr.devices[HRM.to_lower()] as FakeDevice
	dev.connected.emit()
	var got: Array = []
	_hr.subscribed.connect(func(c: String) -> void: got.append(c))
	dev.ble_event.emit(
		{"operation": &"subscribe", "phase": &"started", "characteristic_uuid": HR_CHAR}
	)
	assert_eq(got, [], "not before it succeeded")
	dev.ble_event.emit(
		{"operation": &"subscribe", "phase": &"succeeded", "characteristic_uuid": HR_CHAR}
	)
	assert_eq(got, [HR_CHAR])
