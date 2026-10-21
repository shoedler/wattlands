extends BleTransport
## Scriptable BleTransport double for FtmsConnectionManager tests. Records every call;
## answers initialize() and connect_device() synchronously according to its settings, or
## not at all, so tests control timing through the manager's tick(dt).

var available: bool = true
## initialize(): "ok", "fail" or "silent"
var init_result: String = "ok"
var init_error: String = "no adapter"
## connect_device(): "ok", "fail" or "hang"
var connect_result: String = "ok"
var connect_error: String = "unreachable"
## Every call as [method, args...].
var calls: Array = []


func is_available() -> bool:
	return available


func initialize() -> void:
	calls.append(["initialize"])
	match init_result:
		"ok":
			adapter_ready.emit(true, "")
		"fail":
			adapter_ready.emit(false, init_error)
		_:
			pass


func start_scan(seconds: float) -> void:
	calls.append(["start_scan", seconds])


func stop_scan() -> void:
	calls.append(["stop_scan"])


func connect_device(address: String) -> void:
	calls.append(["connect_device", address])
	match connect_result:
		"ok":
			device_connected.emit(address)
		"fail":
			operation_failed.emit("connect", connect_error)
		_:
			pass


func disconnect_device() -> void:
	calls.append(["disconnect_device"])


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


## Test helpers: what a real transport would report.
func advertise(address: String, device_name: Variant, services: Array = []) -> void:
	device_found.emit({"address": address, "name": device_name, "rssi": -60, "services": services})


func drop(address: String, reason: String = "remote") -> void:
	device_disconnected.emit(address, reason)
