extends BleTransport
## Test double: a KICKR CORE emulated at the GATT level for FtmsClient and FtmsTrainer tests.
## No class_name (tests load it by path), so it never collides with another module's double.
##
## Services: Fitness Machine 0x1826 (0x2ACC, 0x2AD2, 0x2AD3, 0x2AD6, 0x2AD8, 0x2AD9, 0x2ADA),
## Cycling Power 0x1818 (0x2A63, 0x2A65) and Device Information 0x180A. Reads answer from the
## golden vectors (tests/vectors/ftms.json: feature_kickr_core, power_range_kickr_core,
## resistance_range_0_to_100). A control-point write is answered by an indication
## (0x80, op, result) only while 0x2AD9 is subscribed, with 0x05 until Request Control has
## been granted (or always, with other_app_has_control); successful commands also notify
## Machine Status like the trainer does. Every event is queued and delivered by flush() (or
## by _process when deliver_in_process is set), never from inside the call that caused it.

const VECTORS_PATH := "res://tests/vectors/ftms.json"

## Every call in order: "discover", "read 2acc", "subscribe 2ad2", "write 2ad9 05c800", ...
var ops: Array[String] = []
## Control-point writes (payloads) in order.
var cp_writes: Array[PackedByteArray] = []
var subscribed: Array[String] = []
var auto_respond: bool = true
var other_app_has_control: bool = false
var control_granted: bool = false
var emit_status: bool = true
## Op code -> result code to answer instead of the normal one.
var result_override: Dictionary = {}
## Ignore the next n control-point writes (no indication: the client times out).
var drop_writes: int = 0
## Fail the next n control-point writes with operation_failed("write", ...).
var fail_writes: int = 0
## Short uuids whose reads are never answered.
var unreadable: Array[String] = []
## Short uuid -> bytes returned by reads.
var read_values: Dictionary = {}
var services: Array = []
## False: discover_services() is never answered (the client's discovery timeout runs).
var answer_discover: bool = true
var deliver_in_process: bool = false

var _events: Array = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	services = [
		{"uuid": BleTransport.expand_uuid("1826"), "characteristics": _chars(["2acc", "2ad2", "2ad3", "2ad6", "2ad8", "2ad9", "2ada"])},
		{"uuid": BleTransport.expand_uuid("1818"), "characteristics": _chars(["2a63", "2a65"])},
		{"uuid": BleTransport.expand_uuid("180a"), "characteristics": _chars(["2a29", "2a24", "2a26"])},
	]
	read_values = {
		"2acc": vector_bytes("feature_kickr_core"),
		"2ad8": vector_bytes("power_range_kickr_core"),
		"2ad6": vector_bytes("resistance_range_0_to_100"),
		"2a29": "Wahoo Fitness".to_utf8_buffer(),
		"2a24": "KICKR CORE".to_utf8_buffer(),
		"2a26": "4.2.1".to_utf8_buffer(),
	}


func _process(_delta: float) -> void:
	if deliver_in_process:
		flush()


## The hex of a "parse" case in the golden vectors, as bytes.
static func vector_bytes(case_name: String) -> PackedByteArray:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(VECTORS_PATH))
	for c: Dictionary in doc["parse"]:
		if c["name"] == case_name:
			return FtmsCodec.from_hex(str(c["hex"]))
	return PackedByteArray()


static func short(uuid: String) -> String:
	var u := BleTransport.expand_uuid(uuid)
	return u.substr(4, 4) if u.ends_with(BleTransport.BASE_UUID_SUFFIX) else u


func is_available() -> bool:
	return true


func discover_services() -> void:
	ops.append("discover")
	if answer_discover:
		_queue("services_discovered", [services.duplicate(true)])


func read_characteristic(_service_uuid: String, char_uuid: String) -> void:
	var s := short(char_uuid)
	ops.append("read " + s)
	if unreadable.has(s):
		return
	_queue("characteristic_read", [BleTransport.expand_uuid(s), read_values.get(s, PackedByteArray())])


func subscribe_characteristic(_service_uuid: String, char_uuid: String) -> void:
	var s := short(char_uuid)
	ops.append("subscribe " + s)
	if not subscribed.has(s):
		subscribed.append(s)


func write_characteristic(_service_uuid: String, char_uuid: String, data: PackedByteArray, _with_response: bool) -> void:
	var s := short(char_uuid)
	ops.append("write %s %s" % [s, FtmsCodec.to_hex(data)])
	if s == FtmsCodec.CHAR_CONTROL_POINT:
		_on_cp_write(data)


## Queue a notification on a characteristic (short or full uuid).
func notify(char_uuid: String, data: PackedByteArray) -> void:
	_queue("characteristic_notified", [BleTransport.expand_uuid(char_uuid), data])


## Queue an Indoor Bike Data notification built from a record (FtmsCodec keys).
func send_bike_data(fields: Dictionary) -> void:
	notify(FtmsCodec.CHAR_INDOOR_BIKE_DATA, FtmsCodec.encode_indoor_bike_data(fields))


## Another app takes control: Machine Status 0xFF; later writes answer 0x05.
func revoke_control() -> void:
	control_granted = false
	notify(FtmsCodec.CHAR_MACHINE_STATUS, PackedByteArray([0xFF]))


func drop_link(reason: String = "link lost") -> void:
	_queue("device_disconnected", ["AA:BB:CC:DD:EE:FF", reason])


## Deliver every queued event (including ones queued while delivering). Returns the count.
func flush() -> int:
	var n := 0
	while not _events.is_empty() and n < 1000:
		var e: Array = _events.pop_front()
		callv("emit_signal", [StringName(e[0])] + (e[1] as Array))
		n += 1
	return n


func pending_events() -> int:
	return _events.size()


## Control-point writes with this op code so far.
func writes_with_op(opcode: int) -> int:
	var n := 0
	for w in cp_writes:
		if w.size() > 0 and w[0] == opcode:
			n += 1
	return n


func _on_cp_write(data: PackedByteArray) -> void:
	cp_writes.append(data)
	if fail_writes > 0:
		fail_writes -= 1
		_queue("operation_failed", ["write", "simulated write failure"])
		return
	if drop_writes > 0:
		drop_writes -= 1
		return
	if not auto_respond or not subscribed.has(FtmsCodec.CHAR_CONTROL_POINT) or data.is_empty():
		return
	var op := int(data[0])
	var result := FtmsCodec.RESULT_SUCCESS
	if op == FtmsCodec.OP_REQUEST_CONTROL:
		if other_app_has_control:
			result = FtmsCodec.RESULT_CONTROL_NOT_PERMITTED
		else:
			control_granted = true
	elif not control_granted:
		result = FtmsCodec.RESULT_CONTROL_NOT_PERMITTED
	if result_override.has(op):
		result = int(result_override[op])
	_queue("characteristic_written", [BleTransport.expand_uuid(FtmsCodec.CHAR_CONTROL_POINT)])
	notify(FtmsCodec.CHAR_CONTROL_POINT, PackedByteArray([FtmsCodec.OP_RESPONSE, op, result]))
	if result != FtmsCodec.RESULT_SUCCESS or not emit_status:
		return
	var status := PackedByteArray()
	match op:
		FtmsCodec.OP_SET_TARGET_POWER:
			status = PackedByteArray([FtmsCodec.STATUS_TARGET_POWER_CHANGED]) + data.slice(1)
		FtmsCodec.OP_SET_SIMULATION:
			status = PackedByteArray([FtmsCodec.STATUS_SIMULATION_CHANGED]) + data.slice(1)
		FtmsCodec.OP_STOP_PAUSE:
			status = PackedByteArray([FtmsCodec.STATUS_STOPPED_BY_USER]) + data.slice(1)
		FtmsCodec.OP_START_RESUME:
			status = PackedByteArray([FtmsCodec.STATUS_STARTED_BY_USER])
	if not status.is_empty() and subscribed.has(FtmsCodec.CHAR_MACHINE_STATUS):
		notify(FtmsCodec.CHAR_MACHINE_STATUS, status)


func _queue(signal_name: String, args: Array) -> void:
	_events.append([signal_name, args])


static func _chars(shorts: Array) -> Array:
	var out: Array = []
	for s: String in shorts:
		out.append({"uuid": BleTransport.expand_uuid(s), "properties": []})
	return out
