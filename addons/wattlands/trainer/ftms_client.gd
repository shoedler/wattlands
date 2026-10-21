class_name FtmsClient
extends Node
## FTMS over a BleTransport (BRIEF 4.1, 4.3, 4.4): discovery, subscriptions, the
## control-point queue and parsing. Owned by trainer-core; public API frozen after W0.
##
## begin() runs the 4.4 flow once the transport is connected: discover services, read
## Feature (0x2ACC) and the ranges (0x2AD6, 0x2AD8), subscribe to Indoor Bike Data (0x2AD2)
## and Machine Status (0x2ADA), enable indications on the Control Point (0x2AD9) FIRST,
## Request Control (0x00), set SIM flat (grade 0), then emit client_ready. Control-point writes are
## serialized: one in flight, 2 s timeout, two retries.
##
## Hardware lock (BRIEF 1): while OS env WATTLANDS_NO_HW_CONTROL=1, Request Control and
## every control-point write are refused and logged "hardware control locked" (scan, read
## and subscribe still work). Only FtmsTrainer calls write_control (4.6.11).
##
## W1 details:
## - States (state(), state_changed): idle, discovering, reading, subscribing,
##   requesting_control, setting_sim, ready, read_only, control_lost, failed, disconnected.
## - Service discovery that has not answered after DISCOVER_TIMEOUT_S fails the flow.
## - Reads go one at a time (Feature is required; the ranges and Device Information 0x180A are
##   optional and keep their defaults when missing); each has the control point's 2 s timeout
##   and two retries.
## - After subscribing, the flow waits SUBSCRIBE_SETTLE_S (the transport has no subscribe ack)
##   before Request Control.
## - Under the hardware lock the flow stops after subscribing: state read_only, a
##   "hardware control locked" warning, and client_ready, so telemetry still flows; is_ready()
##   stays false and every write is refused.
## - Coalescing (BRIEF 4.5, drop superseded commands): a new Set Target Resistance/Power/
##   Simulation write replaces the last queued (unsent) write when that has the same op code
##   and the write going out just before it (queued or in flight) has that op code too.
##   Otherwise it is appended. So writes never change order (the newest command always goes
##   out last), and the first write of each mode, such as the SIM grade 0 or the low ERG entry
##   of a ramped mode switch, is never dropped.
## - A response with result 0x05 (control not permitted) or Machine Status 0xFF emits
##   control_lost("another app may hold control") and clears the queue. A write that is still
##   unanswered after its two retries emits failed() (the link is presumed dead; the
##   FtmsConnectionManager then reconnects, W4 ftms-ble-1).
## - (W4) A write the transport rejects synchronously, inside the write call itself (GDBLE's
##   BUSY or QUEUE_FULL), is retried on the next tick, not from inside that call: three
##   rejections in a row no longer recurse into failed() within one write.
## - Cycling Power fallback: when the Feature lacks power measurement (machine bit 14) and the
##   trainer offers 0x1818, the client subscribes to 0x2A63 and fills power_w (with
##   "power_source": "cps") into bike data records that lack it.
## - Time: tick(dt) counts timeouts and the settle delay. A client inside the tree ticks itself
##   from _process (PROCESS_MODE_ALWAYS, so pausing the tree never stops it) unless
##   process_self is false; a client outside the tree is ticked by its owner (FtmsTrainer.tick).

signal client_ready
## Parsed Indoor Bike Data record (FtmsCodec.parse_indoor_bike_data output).
signal bike_data(record: Dictionary)
signal control_response(opcode: int, result: int)
signal machine_status(code: int, data: PackedByteArray)
## Request Control failed with 0x05 or status reported 0xFF (another app holds control).
signal control_lost(detail: String)
signal failed(reason: String)
## The flow's state changed (one of the STATE_* constants) with a human-readable detail.
signal state_changed(state: String, detail: String)

const STATE_IDLE := "idle"
const STATE_DISCOVERING := "discovering"
const STATE_READING := "reading"
const STATE_SUBSCRIBING := "subscribing"
const STATE_REQUESTING_CONTROL := "requesting_control"
const STATE_SETTING_SIM := "setting_sim"
const STATE_READY := "ready"
const STATE_READ_ONLY := "read_only"
const STATE_CONTROL_LOST := "control_lost"
const STATE_FAILED := "failed"
const STATE_DISCONNECTED := "disconnected"

const CP_TIMEOUT_S := 2.0
const CP_RETRIES := 2
const READ_TIMEOUT_S := 2.0
const READ_RETRIES := 2
const SUBSCRIBE_SETTLE_S := 0.25
## Service discovery that takes longer fails the flow (the connection manager reconnects).
const DISCOVER_TIMEOUT_S := 10.0
## Timers compare with this slack, so summed 0.05 s steps hit 2 s exactly.
const TIME_EPSILON := 1e-6
## SIM flat after Request Control (BRIEF 4.4, 4.5 defaults).
const FLAT_CRR := 0.004
const FLAT_CW := 0.51
## control_lost detail (BRIEF 4.4) and its translation key in content/strings/trainer.csv.
const DETAIL_ANOTHER_APP := "another app may hold control"
const KEY_ANOTHER_APP := "TRAINER_ANOTHER_APP_CONTROL"
const KEY_HW_LOCKED := "TRAINER_HW_LOCKED"
## Op codes whose queued (unsent) write is replaced by a newer one.
const COALESCED_OPS: Array[int] = [
	FtmsCodec.OP_SET_TARGET_RESISTANCE,
	FtmsCodec.OP_SET_TARGET_POWER,
	FtmsCodec.OP_SET_SIMULATION,
]

## When true and inside the tree, _process ticks the client.
var process_self: bool = true

var _transport: BleTransport = null
var _state: String = STATE_IDLE
var _detail: String = ""
var _features: Dictionary = {"machine": 0, "target": 0}
var _power_range: Dictionary = {"min_w": 0, "max_w": 1800, "step_w": 1}
var _resistance_range: Dictionary = {"min": 0.0, "max": 100.0, "step": 0.1}
var _device_info: Dictionary = {}
## Expanded service uuid -> Array of expanded characteristic uuids ([] when unknown).
var _services: Dictionary = {}
var _cps_fallback: bool = false
var _cps_power_w: int = -1
var _read_queue: Array[Dictionary] = []
var _read: Dictionary = {}
var _settle_left_s: float = -1.0
var _discover_left_s: float = -1.0
var _queue: Array[Dictionary] = []
var _in_flight: Dictionary = {}
var _assembler: FtmsCodec.BikeDataAssembler = FtmsCodec.BikeDataAssembler.new()
## True while the transport's write call runs (a failure it reports then is synchronous).
var _sending: bool = false
var _stats: Dictionary = {
	"cp_writes": 0, "cp_retries": 0, "cp_timeouts": 0, "refused_locked": 0, "records": 0
}


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if process_self:
		tick(delta)


func attach(transport: BleTransport) -> void:
	if _transport == transport:
		return
	if _transport != null:
		_disconnect_transport(_transport)
	_transport = transport
	if _transport == null:
		return
	_transport.services_discovered.connect(_on_services_discovered)
	_transport.characteristic_read.connect(_on_characteristic_read)
	_transport.characteristic_notified.connect(_on_characteristic_notified)
	_transport.operation_failed.connect(_on_operation_failed)
	_transport.device_disconnected.connect(_on_device_disconnected)


## Run the 4.4 flow on the attached, connected transport.
func begin() -> void:
	if _transport == null:
		_fail("no transport attached")
		return
	_reset_link_state()
	_set_state(STATE_DISCOVERING, "discovering services")
	_discover_left_s = DISCOVER_TIMEOUT_S
	_transport.discover_services()


## Queue a control-point write (opcode + parameters). Refused under the hardware lock.
func write_control(payload: PackedByteArray) -> void:
	var opcode := int(payload[0]) if payload.size() > 0 else -1
	if _is_hw_locked():
		_refuse_locked(opcode)
		return
	if payload.is_empty():
		push_error("FtmsClient.write_control: empty payload")
		return
	if _state != STATE_READY:
		push_warning(
			"FtmsClient: not in control (%s); dropped %s" % [_state, FtmsCodec.opcode_name(opcode)]
		)
		return
	_enqueue(payload)


## True while WATTLANDS_NO_HW_CONTROL=1 is set in the environment.
static func hardware_locked() -> bool:
	return OS.get_environment("WATTLANDS_NO_HW_CONTROL") == "1"


func is_ready() -> bool:
	return _state == STATE_READY


## {"machine": int, "target": int}
func features() -> Dictionary:
	return _features.duplicate()


## {"min_w", "max_w", "step_w"}; KICKR defaults until read.
func power_range() -> Dictionary:
	return _power_range.duplicate()


## {"min", "max", "step"} resistance level range (0.1 units).
func resistance_range() -> Dictionary:
	return _resistance_range.duplicate()


# --- Added in W1 ----------------------------------------------------------------------


## Advance timeouts and the settle delay by dt seconds (see the class doc for who calls it).
func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	if _discover_left_s >= 0.0:
		_discover_left_s -= dt
		if _discover_left_s <= TIME_EPSILON:
			_discover_left_s = -1.0
			if _state == STATE_DISCOVERING:
				_fail("service discovery timed out after %d s" % roundi(DISCOVER_TIMEOUT_S))
	if _settle_left_s >= 0.0:
		_settle_left_s -= dt
		if _settle_left_s <= TIME_EPSILON:
			_settle_left_s = -1.0
			_after_subscribe()
	if not _read.is_empty():
		_read["elapsed"] = float(_read["elapsed"]) + dt
		if float(_read["elapsed"]) >= READ_TIMEOUT_S - TIME_EPSILON:
			_retry_read("timeout")
	if not _in_flight.is_empty():
		if _in_flight.has("rejected"):
			# A synchronous rejection from the last send: retry now, one tick later.
			var why := str(_in_flight["rejected"])
			_in_flight.erase("rejected")
			_retry_write(why)
		else:
			_in_flight["elapsed"] = float(_in_flight["elapsed"]) + dt
			if float(_in_flight["elapsed"]) >= CP_TIMEOUT_S - TIME_EPSILON:
				_retry_write("timeout")


## Re-request control after control_lost (or to refresh it while ready): Request Control,
## then SIM flat, then client_ready again. Refused under the hardware lock.
func request_control() -> void:
	if _is_hw_locked():
		_refuse_locked(FtmsCodec.OP_REQUEST_CONTROL)
		return
	if _state != STATE_CONTROL_LOST and _state != STATE_READY:
		push_warning("FtmsClient: request_control in state %s ignored" % _state)
		return
	_queue = []
	_in_flight = {}
	_set_state(STATE_REQUESTING_CONTROL, "requesting control")
	_enqueue(FtmsCodec.encode_request_control())


func state() -> String:
	return _state


func state_detail() -> String:
	return _detail


## True once the flow finished under the hardware lock (telemetry only, no control).
func is_read_only() -> bool:
	return _state == STATE_READ_ONLY


## Device Information (0x180A) strings read during the flow: manufacturer, model, serial,
## hardware_revision, firmware_revision, software_revision (only those the trainer has).
func device_info() -> Dictionary:
	return _device_info.duplicate()


## True when power comes from the Cycling Power service (0x2A63).
func cps_fallback_active() -> bool:
	return _cps_fallback


## Counters for diagnostics: cp_writes, cp_retries, cp_timeouts, refused_locked, records.
func stats() -> Dictionary:
	return _stats.duplicate()


## Control-point writes waiting behind the one in flight.
func queued_count() -> int:
	return _queue.size()


## Op code of the write in flight, or -1.
func in_flight_opcode() -> int:
	return int(_in_flight["opcode"]) if not _in_flight.is_empty() else -1


# --- Internals ------------------------------------------------------------------------


## The hardware lock as this instance sees it. Production code always reads the environment;
## only a test-only subclass talking to a fake transport overrides it.
func _is_hw_locked() -> bool:
	return hardware_locked()


func _refuse_locked(opcode: int) -> void:
	_stats["refused_locked"] = int(_stats["refused_locked"]) + 1
	push_warning("FtmsClient: %s: refused %s" % [Locks.HW_MESSAGE, FtmsCodec.opcode_name(opcode)])


func _disconnect_transport(t: BleTransport) -> void:
	var pairs: Array = [
		[t.services_discovered, _on_services_discovered],
		[t.characteristic_read, _on_characteristic_read],
		[t.characteristic_notified, _on_characteristic_notified],
		[t.operation_failed, _on_operation_failed],
		[t.device_disconnected, _on_device_disconnected],
	]
	for pair: Array in pairs:
		var sig: Signal = pair[0]
		var cb: Callable = pair[1]
		if sig.is_connected(cb):
			sig.disconnect(cb)


func _reset_link_state() -> void:
	_services = {}
	_read_queue = []
	_read = {}
	_settle_left_s = -1.0
	_discover_left_s = -1.0
	_queue = []
	_in_flight = {}
	_cps_fallback = false
	_cps_power_w = -1
	_assembler.reset()


func _set_state(s: String, detail: String = "") -> void:
	_state = s
	_detail = detail
	state_changed.emit(s, detail)


func _fail(reason: String) -> void:
	_queue = []
	_in_flight = {}
	_read = {}
	_read_queue = []
	_settle_left_s = -1.0
	_discover_left_s = -1.0
	push_warning("FtmsClient: %s" % reason)
	_set_state(STATE_FAILED, reason)
	failed.emit(reason)


func _lose_control(detail: String) -> void:
	_queue = []
	_in_flight = {}
	push_warning("FtmsClient: control lost: %s" % detail)
	_set_state(STATE_CONTROL_LOST, detail)
	control_lost.emit(detail)


func _has_char(service: String, chr: String) -> bool:
	var s := BleTransport.expand_uuid(service)
	if not _services.has(s):
		return false
	var chars: Array = _services[s]
	return chars.is_empty() or chars.has(BleTransport.expand_uuid(chr))


# --- Flow -----------------------------------------------------------------------------


func _on_services_discovered(services: Array) -> void:
	if _state != STATE_DISCOVERING:
		return
	_discover_left_s = -1.0
	_services = {}
	for svc: Variant in services:
		if not svc is Dictionary:
			continue
		var d: Dictionary = svc
		var chars: Array = []
		for c: Variant in d.get("characteristics", []):
			if c is Dictionary:
				chars.append(BleTransport.expand_uuid(str((c as Dictionary).get("uuid", ""))))
		_services[BleTransport.expand_uuid(str(d.get("uuid", "")))] = chars
	if not _services.has(BleTransport.expand_uuid(FtmsCodec.SERVICE_FTMS)):
		_fail("no Fitness Machine service (0x1826)")
		return
	var ftms := FtmsCodec.SERVICE_FTMS
	_read_queue = [
		{"service": ftms, "char": FtmsCodec.CHAR_FEATURE, "key": "feature", "required": true}
	]
	if _has_char(ftms, FtmsCodec.CHAR_POWER_RANGE):
		_read_queue.append(
			{
				"service": ftms,
				"char": FtmsCodec.CHAR_POWER_RANGE,
				"key": "power_range",
				"required": false
			}
		)
	if _has_char(ftms, FtmsCodec.CHAR_RESISTANCE_RANGE):
		_read_queue.append(
			{
				"service": ftms,
				"char": FtmsCodec.CHAR_RESISTANCE_RANGE,
				"key": "resistance_range",
				"required": false
			}
		)
	var dis := FtmsCodec.SERVICE_DEVICE_INFO
	var dis_chars: Dictionary = FtmsCodec.DEVICE_INFO_CHARS
	for key: String in dis_chars.keys():
		var chr: String = dis_chars[key]
		if _has_char(dis, chr):
			_read_queue.append(
				{"service": dis, "char": chr, "key": "dis:" + key, "required": false}
			)
	_set_state(STATE_READING, "reading features and ranges")
	_next_read()


func _next_read() -> void:
	if _read_queue.is_empty():
		_read = {}
		_after_reads()
		return
	_read = _read_queue.pop_front()
	_read["attempts"] = 1
	_read["elapsed"] = 0.0
	_transport.read_characteristic(
		BleTransport.expand_uuid(str(_read["service"])),
		BleTransport.expand_uuid(str(_read["char"]))
	)


func _on_characteristic_read(char_uuid: String, data: PackedByteArray) -> void:
	if _read.is_empty() or not BleTransport.same_uuid(char_uuid, str(_read["char"])):
		return
	var entry := _read
	_read = {}
	var key := str(entry["key"])
	var ok := true
	if key == "feature":
		var f := FtmsCodec.parse_feature(data)
		ok = not f.is_empty()
		if ok:
			_features = f
	elif key == "power_range":
		var p := FtmsCodec.parse_power_range(data)
		ok = not p.is_empty()
		if ok:
			_power_range = p
	elif key == "resistance_range":
		var rr := FtmsCodec.parse_resistance_range(data)
		ok = not rr.is_empty()
		if ok:
			_resistance_range = rr
	elif key.begins_with("dis:"):
		_device_info[key.substr(4)] = data.get_string_from_utf8().strip_edges()
	if not ok:
		if bool(entry["required"]):
			_fail("could not read %s" % key)
			return
		push_warning("FtmsClient: %s unreadable, keeping defaults" % key)
	_next_read()


func _retry_read(why: String) -> void:
	if int(_read["attempts"]) <= READ_RETRIES:
		_read["attempts"] = int(_read["attempts"]) + 1
		_read["elapsed"] = 0.0
		_transport.read_characteristic(
			BleTransport.expand_uuid(str(_read["service"])),
			BleTransport.expand_uuid(str(_read["char"]))
		)
		return
	var entry := _read
	_read = {}
	if bool(entry["required"]):
		_fail("read %s failed (%s)" % [str(entry["key"]), why])
		return
	push_warning("FtmsClient: read %s failed (%s), keeping defaults" % [str(entry["key"]), why])
	_next_read()


func _after_reads() -> void:
	var has_power := (int(_features.get("machine", 0)) & FtmsCodec.MACHINE_POWER_MEASUREMENT) != 0
	_cps_fallback = (
		not has_power and _has_char(FtmsCodec.SERVICE_CYCLING_POWER, FtmsCodec.CHAR_CP_MEASUREMENT)
	)
	_set_state(STATE_SUBSCRIBING, "subscribing")
	var ftms := BleTransport.expand_uuid(FtmsCodec.SERVICE_FTMS)
	_transport.subscribe_characteristic(
		ftms, BleTransport.expand_uuid(FtmsCodec.CHAR_INDOOR_BIKE_DATA)
	)
	_transport.subscribe_characteristic(
		ftms, BleTransport.expand_uuid(FtmsCodec.CHAR_MACHINE_STATUS)
	)
	if _cps_fallback:
		_transport.subscribe_characteristic(
			BleTransport.expand_uuid(FtmsCodec.SERVICE_CYCLING_POWER),
			BleTransport.expand_uuid(FtmsCodec.CHAR_CP_MEASUREMENT)
		)
	# Indications on the control point before the first control-point write (BRIEF 4.3).
	_transport.subscribe_characteristic(
		ftms, BleTransport.expand_uuid(FtmsCodec.CHAR_CONTROL_POINT)
	)
	_settle_left_s = SUBSCRIBE_SETTLE_S


func _after_subscribe() -> void:
	if _state != STATE_SUBSCRIBING:
		return
	if _is_hw_locked():
		_refuse_locked(FtmsCodec.OP_REQUEST_CONTROL)
		_set_state(STATE_READ_ONLY, Locks.HW_MESSAGE)
		client_ready.emit()
		return
	_set_state(STATE_REQUESTING_CONTROL, "requesting control")
	_enqueue(FtmsCodec.encode_request_control())


# --- Control point queue ------------------------------------------------------------


## Queues a write (coalescing rule in the class doc) and sends it when nothing is in flight.
func _enqueue(payload: PackedByteArray) -> void:
	var opcode := int(payload[0])
	if COALESCED_OPS.has(opcode) and not _queue.is_empty():
		var tail: Dictionary = _queue.back()
		if int(tail["opcode"]) == opcode and _opcode_before_tail() == opcode:
			tail["payload"] = payload
			_pump_queue()
			return
	_queue.append({"opcode": opcode, "payload": payload})
	_pump_queue()


## Op code of the write that goes out just before the queue's last entry: the entry before it,
## else the write in flight (-1 when there is none).
func _opcode_before_tail() -> int:
	if _queue.size() >= 2:
		return int(_queue[_queue.size() - 2]["opcode"])
	return in_flight_opcode()


func _pump_queue() -> void:
	if not _in_flight.is_empty() or _queue.is_empty():
		return
	_in_flight = _queue.pop_front()
	_in_flight["attempts"] = 1
	_in_flight["elapsed"] = 0.0
	_send_in_flight()


## The only place that writes the control point; it checks the hardware lock again.
func _send_in_flight() -> void:
	var payload: PackedByteArray = _in_flight["payload"]
	if _is_hw_locked():
		_in_flight = {}
		_queue = []
		_refuse_locked(int(payload[0]))
		return
	if _transport == null or not is_instance_valid(_transport):
		# The transport is gone (the app is tearing the stack down): nothing can go out.
		_in_flight = {}
		_queue = []
		push_warning(
			"FtmsClient: no transport; dropped %s" % FtmsCodec.opcode_name(int(payload[0]))
		)
		return
	_stats["cp_writes"] = int(_stats["cp_writes"]) + 1
	_sending = true
	_transport.write_characteristic(
		BleTransport.expand_uuid(FtmsCodec.SERVICE_FTMS),
		BleTransport.expand_uuid(FtmsCodec.CHAR_CONTROL_POINT),
		payload,
		true
	)
	_sending = false


func _retry_write(why: String) -> void:
	if int(_in_flight["attempts"]) <= CP_RETRIES:
		_in_flight["attempts"] = int(_in_flight["attempts"]) + 1
		_in_flight["elapsed"] = 0.0
		_stats["cp_retries"] = int(_stats["cp_retries"]) + 1
		_send_in_flight()
		return
	var opcode := int(_in_flight["opcode"])
	_stats["cp_timeouts"] = int(_stats["cp_timeouts"]) + 1
	_fail(
		(
			"control point %s unanswered after %d attempts (%s)"
			% [FtmsCodec.opcode_name(opcode), CP_RETRIES + 1, why]
		)
	)


func _on_control_point_indication(data: PackedByteArray) -> void:
	var resp := FtmsCodec.parse_control_response(data)
	if resp.is_empty():
		return
	var opcode := int(resp["request_opcode"])
	var result := int(resp["result"])
	if _in_flight.is_empty() or int(_in_flight["opcode"]) != opcode:
		push_warning(
			(
				"FtmsClient: unexpected response to %s (%s)"
				% [FtmsCodec.opcode_name(opcode), FtmsCodec.result_name(result)]
			)
		)
		return
	_in_flight = {}
	control_response.emit(opcode, result)
	if result == FtmsCodec.RESULT_CONTROL_NOT_PERMITTED:
		_lose_control(DETAIL_ANOTHER_APP)
		return
	if _state == STATE_REQUESTING_CONTROL and opcode == FtmsCodec.OP_REQUEST_CONTROL:
		if result != FtmsCodec.RESULT_SUCCESS:
			_fail("Request Control failed: %s" % FtmsCodec.result_name(result))
			return
		_set_state(STATE_SETTING_SIM, "setting SIM flat")
		_enqueue(FtmsCodec.encode_indoor_bike_simulation(0.0, 0.0, FLAT_CRR, FLAT_CW))
		return
	if _state == STATE_SETTING_SIM and opcode == FtmsCodec.OP_SET_SIMULATION:
		if result != FtmsCodec.RESULT_SUCCESS:
			push_warning(
				"FtmsClient: SIM flat refused (%s); continuing" % FtmsCodec.result_name(result)
			)
		_set_state(STATE_READY, "ready")
		client_ready.emit()
		_pump_queue()
		return
	if result != FtmsCodec.RESULT_SUCCESS:
		push_warning(
			"FtmsClient: %s: %s" % [FtmsCodec.opcode_name(opcode), FtmsCodec.result_name(result)]
		)
	_pump_queue()


# --- Notifications and errors ----------------------------------------------------------


func _on_characteristic_notified(char_uuid: String, data: PackedByteArray) -> void:
	if BleTransport.same_uuid(char_uuid, FtmsCodec.CHAR_INDOOR_BIKE_DATA):
		for rec: Dictionary in _assembler.push(data):
			if _cps_fallback and not rec.has("power_w") and _cps_power_w >= 0:
				rec["power_w"] = _cps_power_w
				rec["power_source"] = "cps"
			_stats["records"] = int(_stats["records"]) + 1
			bike_data.emit(rec)
	elif BleTransport.same_uuid(char_uuid, FtmsCodec.CHAR_CONTROL_POINT):
		_on_control_point_indication(data)
	elif BleTransport.same_uuid(char_uuid, FtmsCodec.CHAR_MACHINE_STATUS):
		var st := FtmsCodec.parse_machine_status(data)
		if st.is_empty():
			return
		var code := int(st["code"])
		machine_status.emit(code, st["params"])
		var in_control := (
			_state == STATE_READY
			or _state == STATE_SETTING_SIM
			or _state == STATE_REQUESTING_CONTROL
		)
		if code == FtmsCodec.STATUS_CONTROL_PERMISSION_LOST and in_control:
			_lose_control(DETAIL_ANOTHER_APP)
	elif BleTransport.same_uuid(char_uuid, FtmsCodec.CHAR_CP_MEASUREMENT):
		var cps := FtmsCodec.parse_cycling_power_measurement(data)
		if not cps.is_empty():
			_cps_power_w = int(cps["power_w"])


func _on_operation_failed(op: String, error: String) -> void:
	var o := op.to_lower()
	if o.contains("read") and not _read.is_empty():
		_retry_read(error)
	elif o.contains("write") and not _in_flight.is_empty():
		if _sending:
			# Rejected inside the write call (BUSY, QUEUE_FULL): retry on the next tick.
			_in_flight["rejected"] = error
			return
		_retry_write(error)
	elif o.contains("discover") and _state == STATE_DISCOVERING:
		_fail("service discovery failed: %s" % error)
	elif o.contains("subscribe") and _state == STATE_SUBSCRIBING:
		_fail("subscribe failed: %s" % error)
	else:
		push_warning("FtmsClient: %s failed: %s" % [op, error])


func _on_device_disconnected(_address: String, reason: String) -> void:
	_reset_link_state()
	_set_state(STATE_DISCONNECTED, reason)
