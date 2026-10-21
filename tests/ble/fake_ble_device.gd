extends RefCounted
## Test double mimicking GDBLE 0.6's BleDevice surface (BRIEF 4.2, docs/deps.d/gdble.md):
## the same method names, argument counts and signals. It never touches Bluetooth; tests
## drive its signals through the emit_* helpers and read `calls`.

signal connected
signal disconnected
signal connection_failed(error: String)
signal services_discovered(services: Array)
signal characteristic_read(char_uuid: String, data: PackedByteArray)
signal characteristic_written(char_uuid: String)
signal characteristic_notified(char_uuid: String, data: PackedByteArray)
signal operation_failed(operation: String, error: String)
signal ble_event(event: Dictionary)

var address: String = ""
## Every call as [method, args...].
var calls: Array = []
var _next_id: int = 1


func _init(p_address: String = "") -> void:
	address = p_address


func connect_async() -> int:
	calls.append(["connect_async"])
	return _id()


func discover_services() -> int:
	calls.append(["discover_services"])
	return _id()


func read_characteristic(service_uuid: String, char_uuid: String) -> int:
	calls.append(["read_characteristic", service_uuid, char_uuid])
	return _id()


func write_characteristic(service_uuid: String, char_uuid: String, data: PackedByteArray, with_response: bool) -> int:
	calls.append(["write_characteristic", service_uuid, char_uuid, data, with_response])
	return _id()


func subscribe_characteristic(service_uuid: String, char_uuid: String) -> int:
	calls.append(["subscribe_characteristic", service_uuid, char_uuid])
	return _id()


## GDBLE's zero-argument disconnect(). Callers reach it only through call(&"disconnect"),
## exactly as with the real class; Object's own disconnect stays reachable via Signal.
@warning_ignore("native_method_override")
func disconnect(_signal_name: StringName = &"", _callable: Callable = Callable()) -> void:
	calls.append(["disconnect"])


func get_address() -> String:
	return address


func count(method: String) -> int:
	var n := 0
	for c: Array in calls:
		if c[0] == method:
			n += 1
	return n


func last(method: String) -> Array:
	for i in range(calls.size() - 1, -1, -1):
		if calls[i][0] == method:
			return calls[i]
	return []


func _id() -> int:
	_next_id += 1
	return _next_id - 1
