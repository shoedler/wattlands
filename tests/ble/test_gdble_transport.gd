extends GutTest
## GdbleTransport (BRIEF 4.2) against a fake GDBLE manager and device (same method and signal
## surface as GDBLE 0.6): signal mapping onto BleTransport, connect_device() as a factory
## followed by connect_async(), exactly-once link events, UUID expansion and matching,
## no-adapter handling (push_warning, never an error), GATT resets, adapter loss and the
## hardware lock on writes. Nothing here touches Bluetooth.

const FakeManager := preload("res://tests/ble/fake_bluetooth_manager.gd")
const FakeDevice := preload("res://tests/ble/fake_ble_device.gd")

const FTMS := "00001826-0000-1000-8000-00805f9b34fb"
const IBD := "00002ad2-0000-1000-8000-00805f9b34fb"
const CP := "00002ad9-0000-1000-8000-00805f9b34fb"
const ADDR := "C4:9D:A1:00:2B:7E"

var _mgr: FakeManager = null
var _t: GdbleTransport = null
var _events: Array = []


func before_each() -> void:
	_events = []
	_mgr = FakeManager.new()
	_t = GdbleTransport.new()
	_t.manager_factory = func() -> Node: return _mgr
	add_child_autofree(_t)
	for sig: String in [
		"adapter_ready",
		"device_found",
		"device_connected",
		"device_disconnected",
		"services_discovered",
		"characteristic_read",
		"characteristic_written",
		"characteristic_notified",
		"operation_failed"
	]:
		_t.connect(sig, _recorder(sig))


func after_each() -> void:
	if is_instance_valid(_mgr) and _mgr.get_parent() == null:
		_mgr.free()
	_mgr = null
	_t = null


func _recorder(sig: String) -> Callable:
	match sig:
		"device_found", "device_connected", "services_discovered", "characteristic_written":
			return func(a: Variant) -> void: _events.append([sig, a])
		_:
			return func(a: Variant, b: Variant) -> void: _events.append([sig, a, b])


func _named(sig: String) -> Array:
	var out: Array = []
	for e: Array in _events:
		if e[0] == sig:
			out.append(e)
	return out


func _device() -> FakeDevice:
	return _mgr.devices.get(ADDR.to_lower())


func _connected() -> FakeDevice:
	_t.initialize()
	_t.connect_device(ADDR)
	var d := _device()
	d.connected.emit()
	_events.clear()
	return d


# --- availability and initialization -------------------------------------------------


func test_available_with_a_factory() -> void:
	assert_true(_t.is_available())


func test_initialize_maps_adapter_initialized() -> void:
	_t.initialize()
	assert_eq(_mgr.count("initialize"), 1)
	assert_eq(_named("adapter_ready"), [["adapter_ready", true, ""]])
	assert_eq(_mgr.get_parent(), _t, "the manager lives under the transport, in the tree")
	assert_eq(_mgr.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(_t.process_mode, Node.PROCESS_MODE_ALWAYS)


func test_initialize_twice_reuses_the_manager() -> void:
	_t.initialize()
	_t.initialize()
	assert_eq(_mgr.count("initialize"), 2)
	assert_eq(_t.get_child_count(), 1)
	assert_eq(
		_named("adapter_ready").size(), 2, "each initialize answers once (signals not doubled)"
	)


func test_no_adapter_is_a_warning_not_an_error() -> void:
	_mgr.adapter_ok = false
	_mgr.adapter_error = "no Bluetooth adapter (D-Bus unavailable)"
	_t.initialize()
	assert_eq(
		_named("adapter_ready"),
		[["adapter_ready", false, "no Bluetooth adapter (D-Bus unavailable)"]]
	)
	assert_push_warning("no adapter")
	_t.start_scan(5.0)
	assert_eq(_mgr.count("start_scan"), 0, "no scan without an adapter")
	assert_eq(_named("operation_failed")[0][1], "scan")


func test_library_missing_reports_no_adapter() -> void:
	var t: GdbleTransport = GdbleTransport.new()
	t.manager_factory = func() -> Variant: return null
	add_child_autofree(t)
	var got: Array = []
	t.adapter_ready.connect(func(ok: bool, err: String) -> void: got.append([ok, err]))
	t.initialize()
	assert_eq(got, [[false, "GDBLE is not loaded"]])
	assert_push_warning("GDBLE is not loaded")


# --- scanning --------------------------------------------------------------------------


func test_scan_maps_discovery_and_expands_service_uuids() -> void:
	_t.initialize()
	_t.start_scan(5.0)
	assert_eq(_mgr.calls.back(), ["start_scan", 5.0])
	_mgr.device_discovered.emit(
		{
			"address": ADDR,
			"name": "KICKR CORE 2B7E",
			"rssi": -61,
			"services": ["00001826-0000-1000-8000-00805F9B34FB", "180A"],
			"manufacturer_data": {}
		}
	)
	_mgr.device_updated.emit({"address": "11:22", "name": null, "rssi": null, "services": []})
	var found := _named("device_found")
	assert_eq(found.size(), 2)
	assert_eq(
		found[0][1],
		{
			"address": ADDR,
			"name": "KICKR CORE 2B7E",
			"rssi": -61,
			"services": [FTMS, "0000180a-0000-1000-8000-00805f9b34fb"]
		}
	)
	assert_eq(
		found[1][1],
		{"address": "11:22", "name": "", "rssi": GdbleTransport.RSSI_UNKNOWN, "services": []}
	)


func test_scan_reports_devices_cached_by_an_earlier_scan() -> void:
	_mgr.discovered = [{"address": ADDR, "name": "KICKR CORE", "rssi": -50, "services": ["1826"]}]
	_t.initialize()
	_t.start_scan(3.0)
	var found := _named("device_found")
	assert_eq(found.size(), 1)
	assert_eq(found[0][1]["services"], [FTMS])


func test_stop_scan() -> void:
	_t.initialize()
	_t.start_scan(0.0)
	_t.stop_scan()
	assert_eq(_mgr.count("stop_scan"), 1)


# --- connecting ----------------------------------------------------------------------------


func test_connect_device_is_a_factory_then_connect_async() -> void:
	_t.initialize()
	_t.connect_device(ADDR)
	assert_eq(_mgr.count("connect_device"), 1)
	var d := _device()
	assert_not_null(d)
	assert_eq(d.count("connect_async"), 1)
	assert_eq(_named("device_connected").size(), 0, "nothing until GDBLE reports the link")
	d.connected.emit()
	_mgr.device_connected.emit(ADDR.to_lower())
	assert_eq(_named("device_connected"), [["device_connected", ADDR]], "exactly once")
	assert_true(_t.is_link_up())


func test_manager_event_alone_brings_the_link_up() -> void:
	_t.initialize()
	_t.connect_device(ADDR)
	_mgr.device_connected.emit("c4:9d:a1:00:2b:7e")
	assert_eq(_named("device_connected").size(), 1, "addresses compare case-insensitively")
	_mgr.device_connected.emit("AA:AA:AA:AA:AA:AA")
	assert_eq(_named("device_connected").size(), 1, "other devices are ignored")


func test_connect_unknown_device_fails() -> void:
	_mgr.unknown = ["de:ad:be:ef:00:01"]
	_t.initialize()
	_t.connect_device("DE:AD:BE:EF:00:01")
	assert_eq(_named("operation_failed").size(), 1)
	assert_eq(_named("operation_failed")[0][1], "connect")


func test_connect_before_initialize_fails() -> void:
	_t.connect_device(ADDR)
	assert_eq(_named("operation_failed")[0][1], "connect")
	assert_eq(_mgr.count("connect_device"), 0)


func test_connection_failed_maps_to_operation_failed() -> void:
	_t.initialize()
	_t.connect_device(ADDR)
	_device().connection_failed.emit("CONNECTION_FAILED: timeout")
	assert_eq(
		_named("operation_failed"), [["operation_failed", "connect", "CONNECTION_FAILED: timeout"]]
	)
	assert_false(_t.is_link_up())


func test_disconnect_while_connecting_is_a_failed_connect() -> void:
	_t.initialize()
	_t.connect_device(ADDR)
	_device().disconnected.emit()
	assert_eq(_named("device_disconnected").size(), 0)
	assert_eq(_named("operation_failed")[0][1], "connect")


func test_remote_disconnect_reported_once() -> void:
	var d := _connected()
	d.disconnected.emit()
	_mgr.device_disconnected.emit(ADDR.to_lower())
	assert_eq(_named("device_disconnected"), [["device_disconnected", ADDR, "remote"]])
	assert_false(_t.is_link_up())


func test_local_disconnect_uses_the_zero_argument_method() -> void:
	var d := _connected()
	_t.disconnect_device()
	assert_eq(d.count("disconnect"), 1, 'reached through call(&"disconnect")')
	_mgr.device_disconnected.emit(ADDR)
	d.disconnected.emit()
	assert_eq(_named("device_disconnected"), [["device_disconnected", ADDR, "local"]])


func test_reconnect_reuses_the_handle_without_doubling_signals() -> void:
	var d := _connected()
	d.disconnected.emit()
	_t.connect_device(ADDR)
	assert_same(_device(), d, "GDBLE returns the same handle for the same address")
	assert_eq(d.count("connect_async"), 2)
	d.connected.emit()
	assert_eq(_named("device_connected").size(), 1, "one link-up event, not two")
	d.characteristic_notified.emit(IBD, PackedByteArray([1, 2]))
	assert_eq(_named("characteristic_notified").size(), 1)


func test_connect_while_linked_reports_the_link_again() -> void:
	var d := _connected()
	_t.connect_device(ADDR.to_lower())
	assert_eq(d.count("connect_async"), 1, "no second connect_async()")
	assert_eq(_named("device_connected"), [["device_connected", ADDR]])


func test_switching_device_detaches_the_old_handle() -> void:
	var d := _connected()
	_t.connect_device("11:22:33:44:55:66")
	var other: FakeDevice = _mgr.devices["11:22:33:44:55:66"]
	other.connected.emit()
	d.characteristic_notified.emit(IBD, PackedByteArray([9]))
	assert_eq(_named("characteristic_notified").size(), 0, "the old device is no longer heard")
	assert_eq(_t.device_address(), "11:22:33:44:55:66")


# --- GATT ----------------------------------------------------------------------------------


func test_uuids_are_expanded_before_every_call() -> void:
	var d := _connected()
	_t.read_characteristic("1826", "2ACC")
	_t.subscribe_characteristic("0x1826", "0X2AD2")
	_t.subscribe_characteristic(FTMS.to_upper(), "2ad9")
	_t.discover_services()
	assert_eq(d.calls[1], ["read_characteristic", FTMS, "00002acc-0000-1000-8000-00805f9b34fb"])
	assert_eq(d.calls[2], ["subscribe_characteristic", FTMS, IBD])
	assert_eq(d.calls[3], ["subscribe_characteristic", FTMS, CP])
	assert_eq(d.count("discover_services"), 1)


func test_values_are_mapped_with_canonical_uuids() -> void:
	var d := _connected()
	var bytes := PackedByteArray([0x44, 0x02, 0x9a, 0x0b])
	d.characteristic_notified.emit("00002AD2-0000-1000-8000-00805F9B34FB", bytes)
	d.characteristic_read.emit("2acc", PackedByteArray([1]))
	d.characteristic_written.emit(CP)
	d.operation_failed.emit("read", "READ_FAILED")
	assert_eq(_named("characteristic_notified"), [["characteristic_notified", IBD, bytes]])
	assert_true(BleTransport.same_uuid(_named("characteristic_notified")[0][1], "2AD2"))
	assert_eq(
		_named("characteristic_read"),
		[["characteristic_read", "00002acc-0000-1000-8000-00805f9b34fb", PackedByteArray([1])]]
	)
	assert_eq(_named("characteristic_written"), [["characteristic_written", CP]])
	assert_eq(_named("operation_failed"), [["operation_failed", "read", "READ_FAILED"]])


func test_services_are_normalized_and_matched_case_insensitively() -> void:
	var d := _connected()
	(
		d
		. services_discovered
		. emit(
			[
				{
					"uuid": "00001826-0000-1000-8000-00805F9B34FB",
					"characteristics":
					[
						{
							"uuid": "00002AD2-0000-1000-8000-00805F9B34FB",
							"properties":
							{
								"read": false,
								"notify": true,
								"indicate": false,
								"write": false,
								"write_without_response": false
							}
						},
						{
							"uuid": "00002ad9-0000-1000-8000-00805f9b34fb",
							"properties":
							{
								"write": true,
								"indicate": true,
								"read": false,
								"notify": false,
								"write_without_response": false
							}
						},
					],
				}
			]
		)
	)
	var expected := [
		{
			"uuid": FTMS,
			"characteristics":
			[
				{"uuid": IBD, "properties": ["notify"]},
				{"uuid": CP, "properties": ["indicate", "write"]},
			]
		}
	]
	assert_eq(_named("services_discovered"), [["services_discovered", expected]])
	assert_eq(_t.services(), expected)
	assert_true(_t.has_characteristic("1826", "2AD9"))
	assert_true(_t.has_characteristic("0x1826", "00002AD2-0000-1000-8000-00805F9B34FB"))
	assert_false(_t.has_characteristic("1826", "2ADA"))
	assert_false(_t.has_characteristic("1818", "2AD2"))


func test_gatt_calls_need_a_link() -> void:
	_t.initialize()
	_t.read_characteristic("1826", "2ACC")
	_t.subscribe_characteristic("1826", "2AD2")
	_t.discover_services()
	var ops: Array = []
	for e: Array in _named("operation_failed"):
		ops.append(e[1])
	assert_eq(ops, ["read", "subscribe", "discover_services"])


func test_writes_honour_the_hardware_lock() -> void:
	var d := _connected()
	_t.write_characteristic("1826", "2AD9", PackedByteArray([0x00]), true)
	if Locks.hw_locked():
		assert_eq(d.count("write_characteristic"), 0, "nothing reaches GDBLE under the lock")
		assert_eq(_named("operation_failed"), [["operation_failed", "write", Locks.HW_MESSAGE]])
		assert_push_warning(Locks.HW_MESSAGE)
	else:
		assert_eq(
			d.last("write_characteristic"),
			["write_characteristic", FTMS, CP, PackedByteArray([0x00]), true]
		)


func test_device_write_mapping() -> void:
	# The bytes path behind the lock, exercised on the fake only.
	var d := _connected()
	_t._device_write("0x1826", "2AD9", PackedByteArray([0x05, 0x64, 0x00]), true)
	assert_eq(
		d.last("write_characteristic"),
		["write_characteristic", FTMS, CP, PackedByteArray([0x05, 0x64, 0x00]), true]
	)


# --- ble_event -----------------------------------------------------------------------------


static func _event(
	op: String, phase: String, code: String, address: String = "", terminal: bool = false
) -> Dictionary:
	return {
		"operation": StringName(op),
		"phase": StringName(phase),
		"operation_id": 0,
		"terminal": terminal,
		"device_address": address,
		"service_uuid": "",
		"characteristic_uuid": "",
		"data": null,
		"error": {"code": code, "message": code, "retryable": true, "details": {}}
	}


func test_notification_overflow_asks_for_a_gatt_reset() -> void:
	_connected()
	_mgr.ble_event.emit(_event("notification", "failed", "EVENT_OVERFLOW", ADDR.to_lower()))
	_mgr.ble_event.emit(_event("discover_services", "failed", "SERVICES_CHANGED", ADDR.to_lower()))
	_mgr.ble_event.emit(_event("scan", "failed", "EVENT_OVERFLOW"))
	_mgr.ble_event.emit(_event("notification", "failed", "EVENT_OVERFLOW", "aa:aa:aa:aa:aa:aa"))
	assert_eq(
		_named("operation_failed"),
		[
			["operation_failed", GdbleTransport.OP_GATT_RESET, "EVENT_OVERFLOW"],
			["operation_failed", GdbleTransport.OP_GATT_RESET, "SERVICES_CHANGED"],
		]
	)


func test_adapter_lost_at_runtime() -> void:
	_t.initialize()
	_events.clear()
	_mgr.ble_event.emit(_event("initialize", "failed", "ADAPTER_UNAVAILABLE"))
	assert_eq(_named("adapter_ready"), [["adapter_ready", false, "ADAPTER_UNAVAILABLE"]])
	assert_push_warning("adapter unavailable")
	_mgr.ble_event.emit(_event("initialize", "failed", "ADAPTER_UNAVAILABLE"))
	assert_eq(_named("adapter_ready").size(), 1, "reported once")
	_t.initialize()
	assert_eq(
		_named("adapter_ready").back(), ["adapter_ready", true, ""], "initialize() again recovers"
	)


func test_adapter_lost_under_a_live_link_drops_the_link_first() -> void:
	var d := _connected()
	_mgr.ble_event.emit(_event("initialize", "failed", "ADAPTER_UNAVAILABLE"))
	assert_eq(
		_events,
		[
			["device_disconnected", ADDR, GdbleTransport.REASON_ADAPTER_LOST],
			["adapter_ready", false, "ADAPTER_UNAVAILABLE"],
		],
		"link down first, then the adapter"
	)
	assert_push_warning("adapter unavailable")
	assert_false(_t.is_link_up())
	assert_eq(_t.services(), [])
	d.disconnected.emit()
	_mgr.device_disconnected.emit(ADDR)
	assert_eq(_named("device_disconnected").size(), 1, "GDBLE's own late report is not doubled")
	assert_eq(_named("operation_failed").size(), 0)
	_t.initialize()
	_t.connect_device(ADDR)
	assert_eq(d.count("connect_async"), 2, "a real reconnect, not the already-linked shortcut")


func test_no_adapter_answer_while_linked_drops_the_link() -> void:
	_connected()
	_mgr.adapter_initialized.emit(false, "ADAPTER_NOT_FOUND")
	assert_eq(
		_events,
		[
			["device_disconnected", ADDR, GdbleTransport.REASON_ADAPTER_LOST],
			["adapter_ready", false, "ADAPTER_NOT_FOUND"],
		]
	)
	assert_push_warning("no adapter")


func test_terminal_initialize_failure_is_not_doubled() -> void:
	_mgr.answer_initialize = false
	_t.initialize()
	_mgr.ble_event.emit(_event("initialize", "failed", "ADAPTER_NOT_FOUND", "", true))
	_mgr.adapter_initialized.emit(false, "ADAPTER_NOT_FOUND")
	assert_eq(_named("adapter_ready"), [["adapter_ready", false, "ADAPTER_NOT_FOUND"]])
	assert_push_warning("no adapter")


func test_manager_error_signal_is_mapped() -> void:
	_t.initialize()
	_mgr.error_occurred.emit("scan failed")
	assert_eq(_named("operation_failed"), [["operation_failed", "bluetooth", "scan failed"]])


func test_real_manager_signals_connect_by_name() -> void:
	# Creates the real BluetoothManager (no initialize(), no scan, never in the tree) and
	# checks that every signal the transport connects by name exists and connects.
	if not GdbleTransport.library_loaded():
		pending("GDBLE is not loaded in this process")
		return
	var t: GdbleTransport = autofree(GdbleTransport.new())
	var m: Node = t._create_manager()
	assert_not_null(m)
	assert_eq(m.get_class(), GdbleTransport.MANAGER_CLASS)
	var cb := func(_a: Variant = null, _b: Variant = null) -> void: pass
	for sig: String in [
		"adapter_initialized",
		"device_discovered",
		"device_updated",
		"device_connected",
		"device_disconnected",
		"error_occurred",
		"ble_event"
	]:
		GdbleTransport._connect_signal(m, StringName(sig), cb)
		assert_true(Signal(m, StringName(sig)).is_connected(cb), sig)
	m.free()


# --- pure helpers --------------------------------------------------------------------------


func test_normalize_services_accepts_property_lists() -> void:
	var out := GdbleTransport.normalize_services(
		[{"uuid": "180A", "characteristics": [{"uuid": "2A29", "properties": ["read"]}]}, "junk"]
	)
	assert_eq(
		out,
		[
			{
				"uuid": "0000180a-0000-1000-8000-00805f9b34fb",
				"characteristics":
				[{"uuid": "00002a29-0000-1000-8000-00805f9b34fb", "properties": ["read"]}]
			}
		]
	)


func test_same_address() -> void:
	assert_true(GdbleTransport.same_address("C4:9D:A1:00:2B:7E", " c4:9d:a1:00:2b:7e "))
	assert_false(GdbleTransport.same_address("C4:9D:A1:00:2B:7E", "C4:9D:A1:00:2B:7F"))
