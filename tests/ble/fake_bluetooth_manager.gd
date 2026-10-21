extends Node
## Test double mimicking GDBLE 0.6's BluetoothManager surface (BRIEF 4.2,
## docs/deps.d/gdble.md): the same method names, argument counts and signals. It never
## touches Bluetooth. connect_device() is a factory, as in GDBLE: it returns the device
## handle (the same one for the same address) and does not connect.

signal adapter_initialized(success: bool, error: String)
signal device_discovered(device_info: Dictionary)
signal device_updated(device_info: Dictionary)
signal device_connected(address: String)
signal device_disconnected(address: String)
signal error_occurred(error_message: String)
signal ble_event(event: Dictionary)

const FakeDevice := preload("res://tests/ble/fake_ble_device.gd")

## Every call as [method, args...].
var calls: Array = []
var adapter_ok: bool = true
var adapter_error: String = ""
## Emit adapter_initialized from inside initialize() (GDBLE answers asynchronously; tests
## may set this false and emit it themselves).
var answer_initialize: bool = true
## lower-case address -> FakeDevice
var devices: Dictionary = {}
## connect_device() returns null for these addresses (lower case).
var unknown: Array[String] = []
var discovered: Array[Dictionary] = []
var _next_id: int = 1


func initialize() -> int:
	calls.append(["initialize"])
	if answer_initialize:
		adapter_initialized.emit(adapter_ok, adapter_error)
	return _id()


func start_scan(timeout_seconds: float) -> int:
	calls.append(["start_scan", timeout_seconds])
	return _id()


func stop_scan() -> int:
	calls.append(["stop_scan"])
	return 0


func connect_device(address: String) -> RefCounted:
	calls.append(["connect_device", address])
	var key := address.strip_edges().to_lower()
	if key in unknown:
		return null
	if not devices.has(key):
		devices[key] = FakeDevice.new(address)
	return devices[key]


func get_device(address: String) -> RefCounted:
	return devices.get(address.strip_edges().to_lower())


func get_discovered_devices() -> Array:
	return discovered.duplicate()


func count(method: String) -> int:
	var n := 0
	for c: Array in calls:
		if c[0] == method:
			n += 1
	return n


func _id() -> int:
	_next_id += 1
	return _next_id - 1
