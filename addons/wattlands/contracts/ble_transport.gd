class_name BleTransport
extends Node
## A Bluetooth LE GATT transport (BRIEF 4.1). Contract, frozen after W0.
## Implementations: GdbleTransport (GDBLE GDExtension, P0), BridgeTransport (Python
## bleak bridge over ws://127.0.0.1:8765, P1), DirconTransport (P2).
##
## UUIDs are strings; implementations compare them case-insensitively after expanding
## 16-bit UUIDs onto the Bluetooth base UUID (see expand_uuid). Only FtmsClient calls
## write_characteristic (BRIEF 4.6.11). Transports never retry or reconnect by
## themselves; the connection manager does.

signal adapter_ready(ok: bool, error: String)
## {"address": String, "name": String, "rssi": int, "services": Array[String]}
signal device_found(info: Dictionary)
signal device_connected(address: String)
signal device_disconnected(address: String, reason: String)
## [{"uuid": String, "characteristics": [{"uuid": String, "properties": Array}]}]
signal services_discovered(services: Array)
signal characteristic_read(char_uuid: String, data: PackedByteArray)
signal characteristic_written(char_uuid: String)
signal characteristic_notified(char_uuid: String, data: PackedByteArray)
signal operation_failed(op: String, error: String)

const BASE_UUID_SUFFIX := "-0000-1000-8000-00805f9b34fb"


## Expands a 16-bit ("2ad2", "0x2AD2") or 32-bit UUID to the full lower-case 128-bit form.
static func expand_uuid(uuid: String) -> String:
	var u := uuid.strip_edges().to_lower()
	if u.begins_with("0x"):
		u = u.substr(2)
	if u.length() == 4:
		return "0000" + u + BASE_UUID_SUFFIX
	if u.length() == 8:
		return u + BASE_UUID_SUFFIX
	return u


static func same_uuid(a: String, b: String) -> bool:
	return expand_uuid(a) == expand_uuid(b)


## True when the backend can run here (library loaded, bridge reachable, ...).
func is_available() -> bool:
	return false


func initialize() -> void:
	pass


func start_scan(_seconds: float) -> void:
	pass


func stop_scan() -> void:
	pass


func connect_device(_address: String) -> void:
	pass


func disconnect_device() -> void:
	pass


func discover_services() -> void:
	pass


func read_characteristic(_service_uuid: String, _char_uuid: String) -> void:
	pass


func write_characteristic(_service_uuid: String, _char_uuid: String, _data: PackedByteArray, _with_response: bool) -> void:
	pass


## Enables notifications or indications (btleplug writes the CCCD as Indicate when the
## characteristic supports it, so subscribing to 0x2AD9 enables indications).
func subscribe_characteristic(_service_uuid: String, _char_uuid: String) -> void:
	pass
