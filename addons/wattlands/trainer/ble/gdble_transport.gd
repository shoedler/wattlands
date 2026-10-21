class_name GdbleTransport
extends BleTransport
## BleTransport over the vendored GDBLE GDExtension (BRIEF 4.2, P0; addons/gdble, v0.6.0).
##
## GDBLE class names are never used as static types: they fail to parse wherever the
## library isn't loaded. The BluetoothManager is created with ClassDB.instantiate() and held
## as a Node, devices are held as RefCounted, and every GDBLE method is called by name
## (call(&"...")) and every GDBLE signal is connected by name. This file is the only place in
## the project that touches GDBLE (CLAUDE.md, docs/deps.d/gdble.md).
##
## Surface used (the 0.5.x surface BRIEF 4.2 lists; 0.6.0 keeps it and returns an int
## operation id from every action method, which is ignored here):
##   BluetoothManager: initialize(), start_scan(s), stop_scan(), connect_device(addr) (a
##     factory: it returns a BleDevice handle and does NOT connect; connect_async() does);
##     signals adapter_initialized(ok, err), device_discovered(info), device_connected(addr),
##     device_disconnected(addr). Optional 0.6 extras when present: device_updated(info),
##     error_occurred(msg), get_discovered_devices().
##   BleDevice: connect_async, discover_services, read_characteristic (svc, chr), the write
##     method (svc, chr, data, with_response), subscribe_characteristic (svc, chr) and
##     disconnect (always as call(&"disconnect"): a direct call is checked against
##     Object.disconnect(signal, callable) and fails to parse); signals connected,
##     disconnected, connection_failed(err), services_discovered(list),
##     characteristic_read(chr, data), characteristic_written(chr),
##     characteristic_notified(chr, data), operation_failed(op, err).
##   Unsolicited ble_event dictionaries (operation id 0) are watched for two cases: a
##     non-terminal initialize failure (ADAPTER_UNAVAILABLE: the adapter went away) becomes
##     adapter_ready(false, code); EVENT_OVERFLOW on the device's notifications or
##     SERVICES_CHANGED becomes operation_failed(OP_GATT_RESET, code), so the manager runs
##     discovery and subscriptions again.
##
## Signals are connected before any request (GDBLE emits invalid-argument and queue
## rejections synchronously, before the call returns). Device events are consumed from the
## device; the manager's device_connected/device_disconnected are used too, deduplicated, so
## a link change is reported exactly once.
##
## Mapping onto BleTransport:
##   adapter_initialized(ok, err) -> adapter_ready(ok, err). ok == false means no adapter
##     (without D-Bus it fails in about 10 ms): push_warning, never an error.
##   device_discovered / device_updated -> device_found({address, name, rssi, services})
##     with every service UUID expanded to lower-case 128-bit form.
##   connected (device) or device_connected (manager) -> device_connected(address)
##   disconnected (device) or device_disconnected (manager) -> device_disconnected(address,
##     "local" after disconnect_device(), else "remote"); a disconnect before the link came up
##     is a failed connect: operation_failed("connect", ...).
##   connection_failed(err) -> operation_failed("connect", err)
##   services_discovered(list) -> services_discovered([{uuid, characteristics: [{uuid,
##     properties: Array[String]}]}]) (GDBLE's property dictionary becomes the list of set flags)
##   characteristic_read / _written / _notified -> the same signals, UUID expanded
##   operation_failed(op, err) -> operation_failed(op, err)
##
## UUIDs: callers may pass 16-bit ("2AD2", "0x2ad2") or full UUIDs in any case; they are
## expanded to GDBLE's lower-case hyphenated form before every call and in every signal,
## and compared with BleTransport.same_uuid (case-insensitive after expansion).
##
## Hardware lock (BRIEF 1), defence in depth behind FtmsClient's own lock: while
## WATTLANDS_NO_HW_CONTROL=1, the write method refuses every write, logs
## "hardware control locked" (push_warning) and emits operation_failed("write", ...).
## Scanning, reading and subscribing still work. The transport never retries or reconnects:
## FtmsConnectionManager does.

const MANAGER_CLASS := "BluetoothManager"
const DEVICE_CLASS := "BleDevice"
## operation_failed op: the GATT state was reset (notification overflow or services
## changed); discover and subscribe again. The link itself is still up.
const OP_GATT_RESET := "gatt_reset"
## RSSI reported when GDBLE has none (its DeviceInfo allows null).
const RSSI_UNKNOWN := -127

## Test seam: a Callable returning a Node that mimics BluetoothManager. When empty, the
## real class is created with ClassDB.instantiate(MANAGER_CLASS).
var manager_factory: Callable = Callable()

var _manager: Node = null
var _device: RefCounted = null
var _address: String = ""
var _initialized: bool = false
var _connecting: bool = false
var _link_up: bool = false
var _disconnect_requested: bool = false
var _services: Array = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## True when the GDBLE library is loaded in this process (introspection only).
static func library_loaded() -> bool:
	return ClassDB.class_exists(MANAGER_CLASS) and ClassDB.can_instantiate(MANAGER_CLASS)


func is_available() -> bool:
	if manager_factory.is_valid():
		return true
	return library_loaded()


## Creates the BluetoothManager on first use (a PROCESS_MODE_ALWAYS child of this node,
## which must be inside the tree for GDBLE to drain its events) and initializes the adapter.
## The result arrives as adapter_ready(ok, error).
func initialize() -> void:
	if _manager == null:
		_manager = _create_manager()
		if _manager == null:
			var err := "GDBLE is not loaded"
			push_warning("Bluetooth: %s" % err)
			adapter_ready.emit(false, err)
			return
		_manager.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_manager)
		_connect_signal(_manager, &"adapter_initialized", _on_adapter_initialized)
		_connect_signal(_manager, &"device_discovered", _on_device_info)
		_connect_signal(_manager, &"device_updated", _on_device_info)
		_connect_signal(_manager, &"device_connected", _on_manager_device_connected)
		_connect_signal(_manager, &"device_disconnected", _on_manager_device_disconnected)
		_connect_signal(_manager, &"error_occurred", _on_manager_error)
		_connect_signal(_manager, &"ble_event", _on_manager_event)
	_manager.call(&"initialize")


func start_scan(seconds: float) -> void:
	if not _require_manager("scan"):
		return
	_manager.call(&"start_scan", maxf(seconds, 0.0))
	# GDBLE deduplicates discovery over the adapter's lifetime, so a device seen by an
	# earlier scan is not announced again: report the cache too.
	if _manager.has_method(&"get_discovered_devices"):
		var cached: Variant = _manager.call(&"get_discovered_devices")
		if cached is Array:
			for info: Variant in cached:
				if info is Dictionary:
					_on_device_info(info)


func stop_scan() -> void:
	if _manager == null:
		return
	_manager.call(&"stop_scan")


## Gets the device handle (connect_device is a factory) and starts connect_async().
## The outcome arrives as device_connected(address) or operation_failed("connect", error).
func connect_device(address: String) -> void:
	if not _require_manager("connect"):
		return
	if _link_up and same_address(address, _address):
		# Already linked: report it again instead of a second connect_async().
		device_connected.emit(_address)
		return
	var handle: Variant = _manager.call(&"connect_device", address)
	if not (handle is RefCounted):
		operation_failed.emit("connect", "device not found: %s" % address)
		return
	_attach_device(handle as RefCounted, address)
	_disconnect_requested = false
	_connecting = true
	_device.call(&"connect_async")


func disconnect_device() -> void:
	if _device == null:
		return
	_disconnect_requested = true
	_device.call(&"disconnect")


func discover_services() -> void:
	if not _require_device("discover_services"):
		return
	_device.call(&"discover_services")


func read_characteristic(service_uuid: String, char_uuid: String) -> void:
	if not _require_device("read"):
		return
	_device.call(&"read_characteristic", expand_uuid(service_uuid), expand_uuid(char_uuid))


## Only FtmsClient calls this (BRIEF 4.6.11). Refused while the hardware lock is set.
func write_characteristic(service_uuid: String, char_uuid: String, data: PackedByteArray, with_response: bool) -> void:
	if Locks.hw_locked():
		push_warning("%s: write to %s refused" % [Locks.HW_MESSAGE, expand_uuid(char_uuid)])
		operation_failed.emit("write", Locks.HW_MESSAGE)
		return
	if not _require_device("write"):
		return
	_device_write(service_uuid, char_uuid, data, with_response)


func subscribe_characteristic(service_uuid: String, char_uuid: String) -> void:
	if not _require_device("subscribe"):
		return
	_device.call(&"subscribe_characteristic", expand_uuid(service_uuid), expand_uuid(char_uuid))


# --- Additive helpers ------------------------------------------------------------------

## The address passed to the last connect_device() ("" before).
func device_address() -> String:
	return _address


## True between device_connected and device_disconnected.
func is_link_up() -> bool:
	return _link_up


## The last services_discovered list (normalized, see the class comment).
func services() -> Array:
	return _services


## True when the last discovered services hold `char_uuid` under `service_uuid`
## (case-insensitive, 16-bit UUIDs expanded).
func has_characteristic(service_uuid: String, char_uuid: String) -> bool:
	for svc: Dictionary in _services:
		if not same_uuid(String(svc.get("uuid", "")), service_uuid):
			continue
		for chr: Dictionary in svc.get("characteristics", []):
			if same_uuid(String(chr.get("uuid", "")), char_uuid):
				return true
	return false


## GDBLE DeviceInfo -> {"address", "name", "rssi", "services"} (name "" and rssi
## RSSI_UNKNOWN when GDBLE reports null; service UUIDs expanded).
static func normalize_device_info(info: Dictionary) -> Dictionary:
	var name_v: Variant = info.get("name")
	var rssi_v: Variant = info.get("rssi")
	var uuids: Array[String] = []
	var raw: Variant = info.get("services", [])
	if raw is Array or raw is PackedStringArray:
		for u: Variant in raw:
			uuids.append(expand_uuid(String(u)))
	return {
		"address": String(info.get("address", "")),
		"name": String(name_v) if name_v != null else "",
		"rssi": int(rssi_v) if (rssi_v is int or rssi_v is float) else RSSI_UNKNOWN,
		"services": uuids,
	}


## GDBLE service list -> [{"uuid", "characteristics": [{"uuid", "properties": Array[String]}]}].
## GDBLE's property dictionary {read: true, notify: true, ...} becomes ["notify", "read"]
## (the set flags, sorted); a property Array is kept as strings.
static func normalize_services(list: Array) -> Array:
	var out: Array = []
	for svc_v: Variant in list:
		if not (svc_v is Dictionary):
			continue
		var svc: Dictionary = svc_v
		var chars: Array = []
		var raw_chars: Variant = svc.get("characteristics", [])
		if raw_chars is Array:
			for chr_v: Variant in raw_chars:
				if not (chr_v is Dictionary):
					continue
				var chr: Dictionary = chr_v
				chars.append({
					"uuid": expand_uuid(String(chr.get("uuid", ""))),
					"properties": _property_list(chr.get("properties", {})),
				})
		out.append({"uuid": expand_uuid(String(svc.get("uuid", ""))), "characteristics": chars})
	return out


static func _property_list(props: Variant) -> Array[String]:
	var out: Array[String] = []
	if props is Dictionary:
		for k: Variant in props:
			if bool(props[k]):
				out.append(String(k))
	elif props is Array or props is PackedStringArray:
		for k: Variant in props:
			out.append(String(k))
	out.sort()
	return out


## Device identities are trimmed and lower case inside GDBLE; display addresses may keep
## the platform's casing.
static func same_address(a: String, b: String) -> bool:
	return a.strip_edges().to_lower() == b.strip_edges().to_lower()


# --- Internals -----------------------------------------------------------------------------

func _create_manager() -> Node:
	if manager_factory.is_valid():
		var made: Variant = manager_factory.call()
		return made as Node if made is Node else null
	if not library_loaded():
		return null
	var obj: Object = ClassDB.instantiate(MANAGER_CLASS)
	if obj is Node:
		return obj as Node
	if obj != null and not (obj is RefCounted):
		obj.free()
	return null


func _require_manager(op: String) -> bool:
	if _manager == null or not _initialized:
		operation_failed.emit(op, "Bluetooth is not initialized")
		return false
	return true


func _require_device(op: String) -> bool:
	if _device == null or not _link_up:
		operation_failed.emit(op, "not connected")
		return false
	return true


## The one place that hands bytes to GDBLE (reached only through write_characteristic,
## behind the hardware lock).
func _device_write(service_uuid: String, char_uuid: String, data: PackedByteArray, with_response: bool) -> void:
	var method := &"write_characteristic"
	_device.call(method, expand_uuid(service_uuid), expand_uuid(char_uuid), data, with_response)


func _attach_device(handle: RefCounted, address: String) -> void:
	_address = address
	if handle == _device:
		return
	_detach_device()
	_device = handle
	_link_up = false
	_services = []
	_connect_signal(_device, &"connected", _on_device_connected)
	_connect_signal(_device, &"disconnected", _on_device_disconnected)
	_connect_signal(_device, &"connection_failed", _on_connection_failed)
	_connect_signal(_device, &"services_discovered", _on_services_discovered)
	_connect_signal(_device, &"characteristic_read", _on_characteristic_read)
	_connect_signal(_device, &"characteristic_written", _on_characteristic_written)
	_connect_signal(_device, &"characteristic_notified", _on_characteristic_notified)
	_connect_signal(_device, &"operation_failed", _on_operation_failed)


func _detach_device() -> void:
	if _device == null:
		return
	for pair: Array in [
		[&"connected", _on_device_connected],
		[&"disconnected", _on_device_disconnected],
		[&"connection_failed", _on_connection_failed],
		[&"services_discovered", _on_services_discovered],
		[&"characteristic_read", _on_characteristic_read],
		[&"characteristic_written", _on_characteristic_written],
		[&"characteristic_notified", _on_characteristic_notified],
		[&"operation_failed", _on_operation_failed],
	]:
		# Signal(...) reaches Object's own disconnect even where a device defines a
		# zero-argument disconnect() of its own.
		var sig := Signal(_device, pair[0])
		var cb: Callable = pair[1]
		if _device.has_signal(pair[0]) and sig.is_connected(cb):
			sig.disconnect(cb)
	_device = null
	_link_up = false
	_connecting = false


static func _connect_signal(obj: Object, signal_name: StringName, cb: Callable) -> void:
	if not obj.has_signal(signal_name):
		return
	var sig := Signal(obj, signal_name)
	if not sig.is_connected(cb):
		sig.connect(cb)


func _on_adapter_initialized(ok: bool, error: String) -> void:
	_initialized = ok
	if not ok:
		push_warning("Bluetooth: no adapter (%s)" % error)
	adapter_ready.emit(ok, error)


func _on_device_info(info: Dictionary) -> void:
	var norm := normalize_device_info(info)
	if String(norm["address"]).is_empty():
		return
	device_found.emit(norm)


func _on_manager_device_connected(address: String) -> void:
	if _device != null and same_address(address, _address):
		_link_came_up()


func _on_manager_device_disconnected(address: String) -> void:
	if _device != null and same_address(address, _address):
		_link_went_down()


func _on_manager_error(message: String) -> void:
	operation_failed.emit("bluetooth", message)


func _on_manager_event(event: Dictionary) -> void:
	var op := String(event.get("operation", ""))
	var phase := String(event.get("phase", ""))
	var code := ""
	var err_v: Variant = event.get("error", {})
	if err_v is Dictionary:
		code = String((err_v as Dictionary).get("code", ""))
	if op == "initialize":
		# A terminal initialize failure also arrives as adapter_initialized(false, ...);
		# only the unsolicited one (adapter powered off later) is reported from here.
		if phase == "failed" and not bool(event.get("terminal", true)) and _initialized:
			_initialized = false
			var reason := code if not code.is_empty() else "ADAPTER_UNAVAILABLE"
			push_warning("Bluetooth: adapter unavailable (%s)" % reason)
			adapter_ready.emit(false, reason)
		return
	var gatt_reset := code == "SERVICES_CHANGED" or (code == "EVENT_OVERFLOW" and op != "scan")
	if not gatt_reset or _device == null or not _link_up:
		return
	var addr := String(event.get("device_address", ""))
	if addr.is_empty() or same_address(addr, _address):
		operation_failed.emit(OP_GATT_RESET, code)


func _on_device_connected() -> void:
	_link_came_up()


func _on_device_disconnected() -> void:
	_link_went_down()


func _link_came_up() -> void:
	_connecting = false
	if _link_up:
		return
	_link_up = true
	device_connected.emit(_address)


func _link_went_down() -> void:
	if not _link_up:
		if _connecting:
			_connecting = false
			operation_failed.emit("connect", "disconnected while connecting")
		return
	_link_up = false
	_services = []
	var reason := "local" if _disconnect_requested else "remote"
	_disconnect_requested = false
	device_disconnected.emit(_address, reason)


func _on_connection_failed(error: String) -> void:
	_connecting = false
	_link_up = false
	operation_failed.emit("connect", error)


func _on_services_discovered(list: Array) -> void:
	_services = normalize_services(list)
	services_discovered.emit(_services)


func _on_characteristic_read(char_uuid: String, data: PackedByteArray) -> void:
	characteristic_read.emit(expand_uuid(char_uuid), data)


func _on_characteristic_written(char_uuid: String) -> void:
	characteristic_written.emit(expand_uuid(char_uuid))


func _on_characteristic_notified(char_uuid: String, data: PackedByteArray) -> void:
	characteristic_notified.emit(expand_uuid(char_uuid), data)


func _on_operation_failed(op: String, error: String) -> void:
	operation_failed.emit(op, error)
