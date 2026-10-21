class_name FtmsCodec
extends RefCounted
## Pure, static FTMS byte codec (BRIEF 4.3). Owned by trainer-core.
##
## Little-endian throughout. Parsers take the raw bytes of one read or notification and
## return a Dictionary of named fields, or {} after a push_error when the bytes are too short
## or malformed (every field is bounds-checked). Encoders return a control-point payload
## (opcode + parameters), clamping each field to its range after rounding half away from zero.
## tests/vectors/ftms.json holds byte-exact golden vectors for every parser and encoder (its
## "_doc" key describes the format); tools/trainer_bridge's Python tests reuse them.
##
## Indoor Bike Data (0x2AD2): uint16 flags, then the fields of each set bit in bit order.
## Bit 0 is "More Data" and INVERTED: 0 means the instantaneous speed field is present. A
## record may span several notifications: a notification with More Data set carries part of
## a record, and BikeDataAssembler merges parts until one arrives with More Data clear.
##
## Output keys (Indoor Bike Data): flags, more_data, speed_kmh, avg_speed_kmh, cadence_rpm,
## avg_cadence_rpm, distance_m, resistance_level, power_w, avg_power_w, total_energy_kcal,
## energy_per_hour_kcal, energy_per_minute_kcal, heart_rate_bpm, met, elapsed_s, remaining_s
## (assembled records add "parts"). Scaled values are floats (raw / 10^n, so 3050 -> 30.5
## exactly as JSON writes it); unscaled values are ints. Trailing bytes after the last
## flagged field and the reserved flag bits 13-15 are ignored.

# Services and characteristics (16-bit UUIDs on the Bluetooth base UUID).
const SERVICE_FTMS := "1826"
const CHAR_FEATURE := "2acc"
const CHAR_INDOOR_BIKE_DATA := "2ad2"
const CHAR_TRAINING_STATUS := "2ad3"
const CHAR_RESISTANCE_RANGE := "2ad6"
const CHAR_POWER_RANGE := "2ad8"
const CHAR_CONTROL_POINT := "2ad9"
const CHAR_MACHINE_STATUS := "2ada"
const SERVICE_CYCLING_POWER := "1818"
const CHAR_CP_MEASUREMENT := "2a63"
const CHAR_CP_FEATURE := "2a65"
const SERVICE_DEVICE_INFO := "180a"
## Device Information characteristics read for diagnostics, keyed by the name they get.
const DEVICE_INFO_CHARS: Dictionary = {
	"manufacturer": "2a29",
	"model": "2a24",
	"serial": "2a25",
	"hardware_revision": "2a27",
	"firmware_revision": "2a26",
	"software_revision": "2a28",
}

# Control point op codes.
const OP_REQUEST_CONTROL := 0x00
const OP_RESET := 0x01
const OP_SET_TARGET_RESISTANCE := 0x04
const OP_SET_TARGET_POWER := 0x05
const OP_START_RESUME := 0x07
const OP_STOP_PAUSE := 0x08
const OP_SET_SIMULATION := 0x11
const OP_RESPONSE := 0x80
## Stop or Pause parameter.
const STOP_PARAM_STOP := 1
const STOP_PARAM_PAUSE := 2

# Control point result codes.
const RESULT_SUCCESS := 0x01
const RESULT_NOT_SUPPORTED := 0x02
const RESULT_INVALID_PARAMETER := 0x03
const RESULT_OPERATION_FAILED := 0x04
const RESULT_CONTROL_NOT_PERMITTED := 0x05

# Machine Status (0x2ADA) op codes.
const STATUS_RESET := 0x01
const STATUS_STOPPED_BY_USER := 0x02
const STATUS_STOPPED_BY_SAFETY_KEY := 0x03
const STATUS_STARTED_BY_USER := 0x04
const STATUS_TARGET_RESISTANCE_CHANGED := 0x07
const STATUS_TARGET_POWER_CHANGED := 0x08
const STATUS_SIMULATION_CHANGED := 0x12
const STATUS_SPIN_DOWN := 0x14
const STATUS_TARGET_CADENCE_CHANGED := 0x15
const STATUS_CONTROL_PERMISSION_LOST := 0xFF

# Fitness Machine Feature bits (BRIEF 4.3).
const MACHINE_CADENCE := 1 << 1
const MACHINE_TOTAL_DISTANCE := 1 << 2
const MACHINE_RESISTANCE_LEVEL := 1 << 7
const MACHINE_POWER_MEASUREMENT := 1 << 14
const TARGET_RESISTANCE := 1 << 2
const TARGET_POWER := 1 << 3
const TARGET_SIMULATION := 1 << 13
const TARGET_WHEEL_CIRCUMFERENCE := 1 << 14
const TARGET_SPIN_DOWN := 1 << 15
const TARGET_CADENCE := 1 << 16

# Indoor Bike Data flag bits.
const IBD_MORE_DATA := 1 << 0
const IBD_AVG_SPEED := 1 << 1
const IBD_CADENCE := 1 << 2
const IBD_AVG_CADENCE := 1 << 3
const IBD_DISTANCE := 1 << 4
const IBD_RESISTANCE := 1 << 5
const IBD_POWER := 1 << 6
const IBD_AVG_POWER := 1 << 7
const IBD_ENERGY := 1 << 8
const IBD_HEART_RATE := 1 << 9
const IBD_MET := 1 << 10
const IBD_ELAPSED := 1 << 11
const IBD_REMAINING := 1 << 12

## Set Target Resistance Level encodings (the brief keeps it configurable): uint8 in 0.1
## units (FTMS 1.0) or sint16 in 0.1 units (seen on some firmware).
const RESISTANCE_UINT8 := "uint8_0.1"
const RESISTANCE_SINT16 := "sint16_0.1"

## Keys of an Indoor Bike Data record that are fields (not flags/more_data/parts).
const IBD_META_KEYS: Array[String] = ["flags", "more_data", "parts"]


# --- Parsers -------------------------------------------------------------------------

## Parse one Indoor Bike Data notification. {} (after push_error) when malformed.
static func parse_indoor_bike_data(data: PackedByteArray) -> Dictionary:
	var what := "indoor bike data"
	if data.size() < 2:
		return _error(what, "truncated flags (%d bytes)" % data.size())
	var r := ByteReader.new(data)
	var flags := r.u16()
	var rec: Dictionary = {"flags": flags, "more_data": (flags & IBD_MORE_DATA) != 0}
	# Each entry: [flag bit (0 = inverted speed rule), key, type, divisor (1 = int)].
	var layout: Array = [
		[IBD_MORE_DATA, "speed_kmh", "u16", 100],
		[IBD_AVG_SPEED, "avg_speed_kmh", "u16", 100],
		[IBD_CADENCE, "cadence_rpm", "u16", 2],
		[IBD_AVG_CADENCE, "avg_cadence_rpm", "u16", 2],
		[IBD_DISTANCE, "distance_m", "u24", 1],
		[IBD_RESISTANCE, "resistance_level", "s16", 1],
		[IBD_POWER, "power_w", "s16", 1],
		[IBD_AVG_POWER, "avg_power_w", "s16", 1],
		[IBD_ENERGY, "total_energy_kcal", "u16", 1],
		[IBD_ENERGY, "energy_per_hour_kcal", "u16", 1],
		[IBD_ENERGY, "energy_per_minute_kcal", "u8", 1],
		[IBD_HEART_RATE, "heart_rate_bpm", "u8", 1],
		[IBD_MET, "met", "u8", 10],
		[IBD_ELAPSED, "elapsed_s", "u16", 1],
		[IBD_REMAINING, "remaining_s", "u16", 1],
	]
	for f: Array in layout:
		var bit := int(f[0])
		var present := (flags & bit) == 0 if bit == IBD_MORE_DATA else (flags & bit) != 0
		if not present:
			continue
		if not _read_into(r, rec, str(f[1]), str(f[2]), int(f[3])):
			return _error(what, _truncated(str(f[1]), r))
	return rec


## Fitness Machine Feature (0x2ACC): {"machine": int, "target": int}.
static func parse_feature(data: PackedByteArray) -> Dictionary:
	if data.size() < 8:
		return _error("feature", "needs 8 bytes, got %d" % data.size())
	var r := ByteReader.new(data)
	return {"machine": r.u32(), "target": r.u32()}


## Supported Power Range (0x2AD8): {"min_w", "max_w", "step_w"} (ints).
static func parse_power_range(data: PackedByteArray) -> Dictionary:
	if data.size() < 6:
		return _error("power range", "needs 6 bytes, got %d" % data.size())
	var r := ByteReader.new(data)
	return {"min_w": r.s16(), "max_w": r.s16(), "step_w": r.u16()}


## Supported Resistance Level Range (0x2AD6): {"min", "max", "step"} in level units (0.1).
static func parse_resistance_range(data: PackedByteArray) -> Dictionary:
	if data.size() < 6:
		return _error("resistance range", "needs 6 bytes, got %d" % data.size())
	var r := ByteReader.new(data)
	return {"min": r.s16() / 10.0, "max": r.s16() / 10.0, "step": r.u16() / 10.0}


## Machine Status (0x2ADA): {"code", "params": PackedByteArray} plus decoded parameters for
## the codes the platform uses: 0x02 stop_pause (1 stop, 2 pause), 0x07 target_resistance,
## 0x08 target_power_w, 0x12 wind_mps/grade_pct/crr/cw, 0x14 spin_down_status,
## 0x15 target_cadence_rpm. A known code with too few parameter bytes is malformed.
static func parse_machine_status(data: PackedByteArray) -> Dictionary:
	var what := "machine status"
	if data.size() < 1:
		return _error(what, "empty")
	var r := ByteReader.new(data)
	var code := r.u8()
	var rec: Dictionary = {"code": code, "params": data.slice(1)}
	var fields: Array = []
	match code:
		STATUS_STOPPED_BY_USER:
			fields = [["stop_pause", "u8", 1]]
		STATUS_TARGET_RESISTANCE_CHANGED:
			fields = [["target_resistance", "u8", 10]]
		STATUS_TARGET_POWER_CHANGED:
			fields = [["target_power_w", "s16", 1]]
		STATUS_SIMULATION_CHANGED:
			fields = [["wind_mps", "s16", 1000], ["grade_pct", "s16", 100], ["crr", "u8", 10000], ["cw", "u8", 100]]
		STATUS_SPIN_DOWN:
			fields = [["spin_down_status", "u8", 1]]
		STATUS_TARGET_CADENCE_CHANGED:
			fields = [["target_cadence_rpm", "u16", 2]]
	for f: Array in fields:
		if not _read_into(r, rec, str(f[0]), str(f[1]), int(f[2])):
			return _error(what, "code 0x%02x: %s" % [code, _truncated(str(f[0]), r)])
	return rec


## Control point response indication (0x80, request opcode, result code, params...):
## {"request_opcode", "result", "params": PackedByteArray}.
static func parse_control_response(data: PackedByteArray) -> Dictionary:
	var what := "control point response"
	if data.size() < 3:
		return _error(what, "needs 3 bytes, got %d" % data.size())
	if data[0] != OP_RESPONSE:
		return _error(what, "not a response (first byte 0x%02x)" % data[0])
	return {"request_opcode": int(data[1]), "result": int(data[2]), "params": data.slice(3)}


## Cycling Power Measurement (0x2A63), the power fallback: {"flags", "power_w"} plus
## pedal_power_balance_pct, accumulated_torque_nm, wheel_revs/wheel_event_time_s and
## crank_revs/crank_event_time_s when flagged. Later optional fields are ignored.
static func parse_cycling_power_measurement(data: PackedByteArray) -> Dictionary:
	var what := "cycling power measurement"
	if data.size() < 4:
		return _error(what, "needs 4 bytes, got %d" % data.size())
	var r := ByteReader.new(data)
	var flags := r.u16()
	var rec: Dictionary = {"flags": flags, "power_w": r.s16()}
	var layout: Array = [
		[1 << 0, "pedal_power_balance_pct", "u8", 2],
		[1 << 2, "accumulated_torque_nm", "u16", 32],
		[1 << 4, "wheel_revs", "u32", 1],
		[1 << 4, "wheel_event_time_s", "u16", 2048],
		[1 << 5, "crank_revs", "u16", 1],
		[1 << 5, "crank_event_time_s", "u16", 1024],
	]
	for f: Array in layout:
		if (flags & int(f[0])) == 0:
			continue
		if not _read_into(r, rec, str(f[1]), str(f[2]), int(f[3])):
			return _error(what, _truncated(str(f[1]), r))
	return rec


## Merges Indoor Bike Data notifications into records (see the class doc). push() returns
## the records completed by this notification: usually 0 or 1, 2 when a part repeats a field
## of the pending record (the pending one is then flushed incomplete, with more_data true;
## this keeps devices that set More Data on every notification working). A malformed
## notification is dropped (push_error) and the pending record kept.
class BikeDataAssembler:
	extends RefCounted

	## A pending record is flushed incomplete after this many parts.
	const MAX_PARTS := 8

	var _pending: Dictionary = {}
	var _parts: int = 0

	func push(data: PackedByteArray) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		var rec := FtmsCodec.parse_indoor_bike_data(data)
		if rec.is_empty():
			return out
		if _parts > 0 and _repeats_a_field(rec):
			out.append(_finish(false))
		if _parts == 0:
			_pending = {"flags": 0}
		for key: String in rec.keys():
			if not FtmsCodec.IBD_META_KEYS.has(key):
				_pending[key] = rec[key]
		_pending["flags"] = int(_pending["flags"]) | int(rec["flags"])
		_parts += 1
		if not bool(rec["more_data"]):
			out.append(_finish(true))
		elif _parts >= MAX_PARTS:
			out.append(_finish(false))
		return out

	## True while part of a record waits for its last notification.
	func has_pending() -> bool:
		return _parts > 0

	func reset() -> void:
		_pending = {}
		_parts = 0

	func _repeats_a_field(rec: Dictionary) -> bool:
		for key: String in rec.keys():
			if not FtmsCodec.IBD_META_KEYS.has(key) and _pending.has(key):
				return true
		return false

	func _finish(complete: bool) -> Dictionary:
		var rec := _pending
		rec["parts"] = _parts
		rec["more_data"] = not complete
		if complete:
			rec["flags"] = int(rec["flags"]) & ~FtmsCodec.IBD_MORE_DATA
		_pending = {}
		_parts = 0
		return rec


## Runs a list of notifications (PackedByteArray or hex String) through one assembler and
## returns every completed record in order.
static func assemble_indoor_bike_data(notifications: Array) -> Array[Dictionary]:
	var a := BikeDataAssembler.new()
	var out: Array[Dictionary] = []
	for n: Variant in notifications:
		var bytes: PackedByteArray = from_hex(str(n)) if n is String else n
		out.append_array(a.push(bytes))
	return out


# --- Encoders ------------------------------------------------------------------------

static func encode_request_control() -> PackedByteArray:
	return PackedByteArray([OP_REQUEST_CONTROL])


static func encode_reset() -> PackedByteArray:
	return PackedByteArray([OP_RESET])


static func encode_start_resume() -> PackedByteArray:
	return PackedByteArray([OP_START_RESUME])


## Stop or Pause: param 1 = stop, 2 = pause. Any other value push_errors and returns empty.
static func encode_stop_pause(param: int = STOP_PARAM_STOP) -> PackedByteArray:
	if param != STOP_PARAM_STOP and param != STOP_PARAM_PAUSE:
		push_error("FtmsCodec: stop/pause parameter must be 1 or 2, got %d" % param)
		return PackedByteArray()
	return PackedByteArray([OP_STOP_PAUSE, param])


## Set Target Power (ERG): sint16 watts, clamped to 0..32767 (a negative target is never sent).
static func encode_target_power(watts: int) -> PackedByteArray:
	var out := PackedByteArray([OP_SET_TARGET_POWER])
	_put_int(out, clampi(watts, 0, 32767), 2)
	return out


## Set Target Resistance Level in 0.1 units: RESISTANCE_UINT8 (0..25.5) or RESISTANCE_SINT16
## (-3276.8..3276.7). An unknown encoding push_errors and returns empty.
static func encode_target_resistance(level: float, encoding: String = RESISTANCE_UINT8) -> PackedByteArray:
	var out := PackedByteArray([OP_SET_TARGET_RESISTANCE])
	match encoding:
		RESISTANCE_UINT8:
			_put_int(out, _scaled(level, 10.0, 0, 255), 1)
		RESISTANCE_SINT16:
			_put_int(out, _scaled(level, 10.0, -32768, 32767), 2)
		_:
			push_error("FtmsCodec: unknown resistance encoding \"%s\"" % encoding)
			return PackedByteArray()
	return out


## Set Indoor Bike Simulation (SIM): sint16 wind 0.001 m/s, sint16 grade 0.01 %, uint8 crr
## 0.0001, uint8 cw 0.01 kg/m, each rounded and clamped to its field range. Safety limits
## (grade -10..+16 % and the rest of BRIEF 4.6.6) are the governor's, not the codec's.
static func encode_indoor_bike_simulation(wind_mps: float, grade_pct: float, crr: float, cw: float) -> PackedByteArray:
	var out := PackedByteArray([OP_SET_SIMULATION])
	_put_int(out, _scaled(wind_mps, 1000.0, -32768, 32767), 2)
	_put_int(out, _scaled(grade_pct, 100.0, -32768, 32767), 2)
	_put_int(out, _scaled(crr, 10000.0, 0, 255), 1)
	_put_int(out, _scaled(cw, 100.0, 0, 255), 1)
	return out


## Indoor Bike Data from a record with parse_indoor_bike_data's keys (test doubles and the
## bridge's fake device). Without speed_kmh, More Data is set. Energy fields go together.
static func encode_indoor_bike_data(fields: Dictionary) -> PackedByteArray:
	var flags := 0 if fields.has("speed_kmh") else IBD_MORE_DATA
	var body := PackedByteArray()
	if fields.has("speed_kmh"):
		_put_int(body, _scaled(float(fields["speed_kmh"]), 100.0, 0, 65535), 2)
	var layout: Array = [
		[IBD_AVG_SPEED, "avg_speed_kmh", 2, 100.0, 0, 65535],
		[IBD_CADENCE, "cadence_rpm", 2, 2.0, 0, 65535],
		[IBD_AVG_CADENCE, "avg_cadence_rpm", 2, 2.0, 0, 65535],
		[IBD_DISTANCE, "distance_m", 3, 1.0, 0, 0xFFFFFF],
		[IBD_RESISTANCE, "resistance_level", 2, 1.0, -32768, 32767],
		[IBD_POWER, "power_w", 2, 1.0, -32768, 32767],
		[IBD_AVG_POWER, "avg_power_w", 2, 1.0, -32768, 32767],
	]
	for f: Array in layout:
		if fields.has(f[1]):
			flags |= int(f[0])
			_put_int(body, _scaled(float(fields[f[1]]), float(f[3]), int(f[4]), int(f[5])), int(f[2]))
	if fields.has("total_energy_kcal") or fields.has("energy_per_hour_kcal") or fields.has("energy_per_minute_kcal"):
		flags |= IBD_ENERGY
		_put_int(body, _scaled(float(fields.get("total_energy_kcal", 0)), 1.0, 0, 65535), 2)
		_put_int(body, _scaled(float(fields.get("energy_per_hour_kcal", 0)), 1.0, 0, 65535), 2)
		_put_int(body, _scaled(float(fields.get("energy_per_minute_kcal", 0)), 1.0, 0, 255), 1)
	var tail: Array = [
		[IBD_HEART_RATE, "heart_rate_bpm", 1, 1.0, 0, 255],
		[IBD_MET, "met", 1, 10.0, 0, 255],
		[IBD_ELAPSED, "elapsed_s", 2, 1.0, 0, 65535],
		[IBD_REMAINING, "remaining_s", 2, 1.0, 0, 65535],
	]
	for f: Array in tail:
		if fields.has(f[1]):
			flags |= int(f[0])
			_put_int(body, _scaled(float(fields[f[1]]), float(f[3]), int(f[4]), int(f[5])), int(f[2]))
	var out := PackedByteArray()
	_put_int(out, flags, 2)
	out.append_array(body)
	return out


# --- Names and hex -------------------------------------------------------------------

static func opcode_name(opcode: int) -> String:
	match opcode:
		OP_REQUEST_CONTROL:
			return "Request Control"
		OP_RESET:
			return "Reset"
		OP_SET_TARGET_RESISTANCE:
			return "Set Target Resistance Level"
		OP_SET_TARGET_POWER:
			return "Set Target Power"
		OP_START_RESUME:
			return "Start or Resume"
		OP_STOP_PAUSE:
			return "Stop or Pause"
		OP_SET_SIMULATION:
			return "Set Indoor Bike Simulation"
	return "op 0x%02x" % opcode


static func result_name(result: int) -> String:
	match result:
		RESULT_SUCCESS:
			return "success"
		RESULT_NOT_SUPPORTED:
			return "not supported"
		RESULT_INVALID_PARAMETER:
			return "invalid parameter"
		RESULT_OPERATION_FAILED:
			return "operation failed"
		RESULT_CONTROL_NOT_PERMITTED:
			return "control not permitted"
	return "result 0x%02x" % result


## Lower-case hex without separators ("05c800").
static func to_hex(bytes: PackedByteArray) -> String:
	return bytes.hex_encode()


## Bytes from hex; spaces, ":" and "-" are ignored. Bad input push_errors and returns empty.
static func from_hex(text: String) -> PackedByteArray:
	var clean := text.strip_edges().to_lower().replace(" ", "").replace(":", "").replace("-", "")
	var out := PackedByteArray()
	var digits := "0123456789abcdef"
	var bad := clean.length() % 2 != 0
	for i in clean.length():
		if not bad and digits.find(clean[i]) < 0:
			bad = true
	if bad:
		push_error("FtmsCodec: bad hex \"%s\"" % text)
		return out
	for i in range(0, clean.length(), 2):
		out.append(digits.find(clean[i]) * 16 + digits.find(clean[i + 1]))
	return out


# --- Helpers -------------------------------------------------------------------------

## Bounds-checked little-endian reader; a read past the end returns 0 and clears ok.
class ByteReader:
	extends RefCounted

	var data: PackedByteArray
	var pos: int = 0
	var ok: bool = true
	## Bytes the last failed read needed.
	var wanted: int = 0

	func _init(p_data: PackedByteArray, p_pos: int = 0) -> void:
		data = p_data
		pos = p_pos

	func remaining() -> int:
		return data.size() - pos

	func read_uint(n: int) -> int:
		if not ok or pos + n > data.size():
			ok = false
			wanted = n
			return 0
		var v := 0
		for i in n:
			v |= int(data[pos + i]) << (8 * i)
		pos += n
		return v

	func u8() -> int:
		return read_uint(1)

	func u16() -> int:
		return read_uint(2)

	func u24() -> int:
		return read_uint(3)

	func u32() -> int:
		return read_uint(4)

	func s16() -> int:
		var v := read_uint(2)
		return v - 0x10000 if v >= 0x8000 else v


static func _read_into(r: ByteReader, rec: Dictionary, key: String, kind: String, divisor: int) -> bool:
	var v := 0
	match kind:
		"u8":
			v = r.u8()
		"u16":
			v = r.u16()
		"s16":
			v = r.s16()
		"u24":
			v = r.u24()
		"u32":
			v = r.u32()
	if not r.ok:
		return false
	if divisor == 1:
		rec[key] = v
	else:
		rec[key] = v / float(divisor)
	return true


static func _truncated(key: String, r: ByteReader) -> String:
	return "truncated %s (needs %d bytes at offset %d, %d left)" % [key, r.wanted, r.pos, r.remaining()]


## value x scale, rounded half away from zero, clamped to [lo, hi] (NaN -> 0).
static func _scaled(value: float, scale: float, lo: int, hi: int) -> int:
	if is_nan(value):
		return clampi(0, lo, hi)
	var x := clampf(value * scale, float(lo), float(hi))
	return clampi(roundi(x), lo, hi)


## Appends `value` as an n-byte little-endian integer (two's complement for negatives).
static func _put_int(out: PackedByteArray, value: int, n: int) -> void:
	var v := value
	if v < 0:
		v += 1 << (8 * n)
	for i in n:
		out.append((v >> (8 * i)) & 0xFF)


static func _error(what: String, why: String) -> Dictionary:
	push_error("FtmsCodec: malformed %s: %s" % [what, why])
	return {}
