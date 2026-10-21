extends GutTest
## BRIEF 4.2: whenever the GDBLE library is loaded (ClassDB.class_exists("BluetoothManager")),
## every method and signal the brief lists exists with the expected argument count, plus
## the 0.6 extras GdbleTransport uses when present. Introspection only: no test here ever
## creates a manager, calls initialize() or scans. Also checks that GdbleTransport never
## uses a GDBLE class name as a static type, and that no other ble file names them.

const MANAGER := "BluetoothManager"
const DEVICE := "BleDevice"

## BRIEF 4.2 (the 0.5.x surface) with argument counts.
const MANAGER_METHODS := {
	"initialize": 0, "start_scan": 1, "stop_scan": 0, "connect_device": 1, "get_device": 1,
}
const MANAGER_SIGNALS := {
	"adapter_initialized": 2, "device_discovered": 1, "device_connected": 1, "device_disconnected": 1,
}
const DEVICE_METHODS := {
	"connect_async": 0, "discover_services": 0, "read_characteristic": 2,
	"write_characteristic": 4, "subscribe_characteristic": 2, "disconnect": 0,
}
const DEVICE_SIGNALS := {
	"connected": 0, "disconnected": 0, "connection_failed": 1, "services_discovered": 1,
	"characteristic_read": 2, "characteristic_written": 1, "characteristic_notified": 2,
	"operation_failed": 2,
}
## 0.6 extras GdbleTransport connects or calls when present (docs/deps.d/gdble.md).
const MANAGER_EXTRA_METHODS := {"get_discovered_devices": 0}
const MANAGER_EXTRA_SIGNALS := {"device_updated": 1, "error_occurred": 1, "ble_event": 1}

const BLE_DIR := "res://addons/wattlands/trainer/ble/"
const TRANSPORT := "res://addons/wattlands/trainer/ble/gdble_transport.gd"


func _loaded() -> bool:
	return ClassDB.class_exists(MANAGER) and ClassDB.class_exists(DEVICE)


static func _method_args(cls: String, method: String) -> int:
	for m: Dictionary in ClassDB.class_get_method_list(cls, true):
		if String(m["name"]) == method:
			return (m["args"] as Array).size()
	return -1


static func _signal_args(cls: String, sig: String) -> int:
	for s: Dictionary in ClassDB.class_get_signal_list(cls, true):
		if String(s["name"]) == sig:
			return (s["args"] as Array).size()
	return -1


func _check_methods(cls: String, expected: Dictionary) -> void:
	for method: String in expected:
		assert_true(ClassDB.class_has_method(cls, method, true), "%s.%s exists" % [cls, method])
		assert_eq(_method_args(cls, method), int(expected[method]), "%s.%s argument count" % [cls, method])


func _check_signals(cls: String, expected: Dictionary) -> void:
	for sig: String in expected:
		assert_true(ClassDB.class_has_signal(cls, sig), "%s signal %s exists" % [cls, sig])
		assert_eq(_signal_args(cls, sig), int(expected[sig]), "%s signal %s argument count" % [cls, sig])


func test_manager_surface() -> void:
	if not _loaded():
		pending("GDBLE is not loaded in this process: surface not checked")
		return
	_check_methods(MANAGER, MANAGER_METHODS)
	_check_signals(MANAGER, MANAGER_SIGNALS)
	assert_true(ClassDB.is_parent_class(MANAGER, "Node"), "BluetoothManager is a Node (held as Node)")
	assert_true(ClassDB.can_instantiate(MANAGER))


func test_device_surface() -> void:
	if not _loaded():
		pending("GDBLE is not loaded in this process: surface not checked")
		return
	_check_methods(DEVICE, DEVICE_METHODS)
	_check_signals(DEVICE, DEVICE_SIGNALS)
	assert_true(ClassDB.is_parent_class(DEVICE, "RefCounted"), "BleDevice is RefCounted (held as RefCounted)")


func test_extras_the_transport_uses() -> void:
	if not _loaded():
		pending("GDBLE is not loaded in this process: surface not checked")
		return
	_check_methods(MANAGER, MANAGER_EXTRA_METHODS)
	_check_signals(MANAGER, MANAGER_EXTRA_SIGNALS)


func test_transport_availability_follows_the_library() -> void:
	assert_eq(GdbleTransport.library_loaded(), ClassDB.class_exists(MANAGER))
	var t: GdbleTransport = autofree(GdbleTransport.new())
	assert_eq(t.is_available(), ClassDB.class_exists(MANAGER))


func test_no_static_gdble_types_in_the_transport() -> void:
	var src := _code_only(FileAccess.get_file_as_string(TRANSPORT))
	assert_false(src.is_empty(), "transport source readable")
	var re := RegEx.new()
	re.compile("(:\\s*|->\\s*|\\bas\\s+|\\bis\\s+|\\bextends\\s+)(BluetoothManager|BleDevice)\\b|\\b(BluetoothManager|BleDevice)\\s*\\.")
	var hit := re.search(src)
	assert_null(hit, "GDBLE class used as a static type: %s" % (hit.get_string() if hit != null else ""))


func test_only_the_gdble_transport_names_gdble_classes() -> void:
	var dir := DirAccess.open(BLE_DIR)
	assert_not_null(dir)
	var re := RegEx.new()
	re.compile("\\b(BluetoothManager|BleDevice)\\b")
	for f: String in dir.get_files():
		if f.get_extension() != "gd" or BLE_DIR + f == TRANSPORT:
			continue
		var src := _code_only(FileAccess.get_file_as_string(BLE_DIR + f))
		assert_null(re.search(src), "%s names a GDBLE class outside gdble_transport.gd" % f)


## Drops comment text so prose about the classes doesn't count.
static func _code_only(src: String) -> String:
	var out := PackedStringArray()
	for line: String in src.split("\n"):
		var cut := line.find("#")
		out.append(line if cut < 0 else line.substr(0, cut))
	return "\n".join(out)
