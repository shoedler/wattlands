class_name FitEncoder
extends RefCounted
## FIT activity file encoder in pure GDScript (BRIEF 3.8). Protocol 2.0, a 14-byte header
## with its CRC, definition and data messages, and the file CRC (FitCrc, the FIT SDK's
## CRC-16). Messages: file_id (type activity, manufacturer development), developer_data_id and
## field_description (one developer field, the lap name), device_info, event (timer start
## and stop), record (timestamp, power, cadence, speed, distance, and heart rate when the ride
## has one; no GPS), lap, session (sport cycling, sub_sport virtual_activity, totals, and
## average and maximum heart rate when the ride has one) and activity.
##
## Field numbers, base types and scales follow the FIT SDK profile (checked against
## @garmin/fitsdk 21.218.0, see docs/deps.d/garmin-fitsdk.md). Timestamps are FIT times:
## seconds since 1989-12-31 00:00:00 UTC (Unix time - 631065600).
##
## Use the builder methods in file order and call finish(), or encode_ride() with the data a
## RideRecorder collects. Values that are absent (negative cadence or speed) are written as
## the base type's invalid value.

## Unix time of the FIT epoch (1989-12-31T00:00:00Z).
const FIT_EPOCH_UNIX := 631065600
const HEADER_SIZE := 14
## Protocol 2.0 (major in the upper nibble).
const PROTOCOL_VERSION := 0x20
## Profile 21.40 (major * 100 + minor, the encoding every decoder reads); every field used
## here exists in it.
const PROFILE_VERSION := 2140

# Global message numbers.
const MESG_FILE_ID := 0
const MESG_SESSION := 18
const MESG_LAP := 19
const MESG_RECORD := 20
const MESG_EVENT := 21
const MESG_DEVICE_INFO := 23
const MESG_ACTIVITY := 34
const MESG_FIELD_DESCRIPTION := 206
const MESG_DEVELOPER_DATA_ID := 207

# Base types (FIT base type ids).
const BT_ENUM := 0x00
const BT_UINT8 := 0x02
const BT_STRING := 0x07
const BT_BYTE := 0x0D
const BT_UINT16 := 0x84
const BT_UINT32 := 0x86
const BT_UINT32Z := 0x8C

# Enum values (FIT SDK profile types).
const FILE_ACTIVITY := 4
const MANUFACTURER_DEVELOPMENT := 255
const SPORT_CYCLING := 2
const SUB_SPORT_VIRTUAL_ACTIVITY := 58
const EVENT_TIMER := 0
const EVENT_SESSION := 8
const EVENT_LAP := 9
const EVENT_ACTIVITY := 26
const EVENT_TYPE_START := 0
const EVENT_TYPE_STOP := 1
const EVENT_TYPE_STOP_ALL := 4
const TIMER_TRIGGER_MANUAL := 0
const LAP_TRIGGER_MANUAL := 0
const LAP_TRIGGER_SESSION_END := 7
const SESSION_TRIGGER_ACTIVITY_END := 0
const ACTIVITY_TYPE_MANUAL := 0
const DEVICE_INDEX_CREATOR := 0
const SOURCE_TYPE_LOCAL := 5

## Our product id under manufacturer "development" and the product name.
const PRODUCT_ID := 1
const PRODUCT_NAME := "Wattlands"
const NAME_FIELD_SIZE := 16
## Developer data: the lap name field (developer data index 0, field 0, a 32-byte string).
const DEV_INDEX := 0
const DEV_FIELD_LAP_NAME := 0
const LAP_NAME_SIZE := 32
## A fixed application id for Wattlands' developer data (16 bytes).
const APPLICATION_ID: Array[int] = [
	0x57,
	0x61,
	0x74,
	0x74,
	0x6C,
	0x61,
	0x6E,
	0x64,
	0x73,
	0x2D,
	0x72,
	0x69,
	0x64,
	0x65,
	0x73,
	0x01,
]

# Local message types, one per global message (all fit in the 4-bit field).
const LOCAL_FILE_ID := 0
const LOCAL_DEVELOPER_DATA_ID := 1
const LOCAL_FIELD_DESCRIPTION := 2
const LOCAL_DEVICE_INFO := 3
const LOCAL_EVENT := 4
const LOCAL_RECORD := 5
const LOCAL_LAP := 6
const LOCAL_SESSION := 7
const LOCAL_ACTIVITY := 8

# Field definitions: [field number, size in bytes, base type].
const DEF_FILE_ID: Array = [
	[0, 1, BT_ENUM],
	[1, 2, BT_UINT16],
	[2, 2, BT_UINT16],
	[3, 4, BT_UINT32Z],
	[4, 4, BT_UINT32],
	[8, NAME_FIELD_SIZE, BT_STRING],
]
const DEF_DEVELOPER_DATA_ID: Array = [
	[1, 16, BT_BYTE],
	[3, 1, BT_UINT8],
	[4, 4, BT_UINT32],
]
const DEF_FIELD_DESCRIPTION: Array = [
	[0, 1, BT_UINT8],
	[1, 1, BT_UINT8],
	[2, 1, BT_UINT8],
	[3, NAME_FIELD_SIZE, BT_STRING],
]
const DEF_DEVICE_INFO: Array = [
	[253, 4, BT_UINT32],
	[0, 1, BT_UINT8],
	[2, 2, BT_UINT16],
	[3, 4, BT_UINT32Z],
	[4, 2, BT_UINT16],
	[5, 2, BT_UINT16],
	[25, 1, BT_ENUM],
	[27, NAME_FIELD_SIZE, BT_STRING],
]
const DEF_EVENT: Array = [
	[253, 4, BT_UINT32],
	[0, 1, BT_ENUM],
	[1, 1, BT_ENUM],
	[3, 4, BT_UINT32],
	[4, 1, BT_UINT8],
]
const DEF_RECORD: Array = [
	[253, 4, BT_UINT32],
	[7, 2, BT_UINT16],
	[4, 1, BT_UINT8],
	[6, 2, BT_UINT16],
	[5, 4, BT_UINT32],
]
## The record definition of a ride with heart rate: DEF_RECORD plus heart_rate (3, bpm).
const DEF_RECORD_HR: Array = [
	[253, 4, BT_UINT32],
	[7, 2, BT_UINT16],
	[4, 1, BT_UINT8],
	[6, 2, BT_UINT16],
	[5, 4, BT_UINT32],
	[3, 1, BT_UINT8],
]
const DEF_LAP: Array = [
	[254, 2, BT_UINT16],
	[253, 4, BT_UINT32],
	[0, 1, BT_ENUM],
	[1, 1, BT_ENUM],
	[2, 4, BT_UINT32],
	[7, 4, BT_UINT32],
	[8, 4, BT_UINT32],
	[9, 4, BT_UINT32],
	[13, 2, BT_UINT16],
	[14, 2, BT_UINT16],
	[19, 2, BT_UINT16],
	[20, 2, BT_UINT16],
	[17, 1, BT_UINT8],
	[18, 1, BT_UINT8],
	[41, 4, BT_UINT32],
	[24, 1, BT_ENUM],
	[25, 1, BT_ENUM],
	[39, 1, BT_ENUM],
]
## Lap fields added for a ride with heart rate: avg_heart_rate (15), max_heart_rate (16).
const HR_LAP_FIELDS: Array = [[15, 1, BT_UINT8], [16, 1, BT_UINT8]]
## Session fields added for a ride with heart rate: avg_heart_rate (16), max_heart_rate (17).
const HR_SESSION_FIELDS: Array = [[16, 1, BT_UINT8], [17, 1, BT_UINT8]]
## Developer fields of the lap message: [field number, size, developer data index].
const DEV_DEF_LAP: Array = [[DEV_FIELD_LAP_NAME, LAP_NAME_SIZE, DEV_INDEX]]
const DEF_SESSION: Array = [
	[254, 2, BT_UINT16],
	[253, 4, BT_UINT32],
	[0, 1, BT_ENUM],
	[1, 1, BT_ENUM],
	[2, 4, BT_UINT32],
	[5, 1, BT_ENUM],
	[6, 1, BT_ENUM],
	[7, 4, BT_UINT32],
	[8, 4, BT_UINT32],
	[9, 4, BT_UINT32],
	[14, 2, BT_UINT16],
	[15, 2, BT_UINT16],
	[20, 2, BT_UINT16],
	[21, 2, BT_UINT16],
	[18, 1, BT_UINT8],
	[19, 1, BT_UINT8],
	[48, 4, BT_UINT32],
	[25, 2, BT_UINT16],
	[26, 2, BT_UINT16],
	[28, 1, BT_ENUM],
]
const DEF_ACTIVITY: Array = [
	[253, 4, BT_UINT32],
	[0, 4, BT_UINT32],
	[1, 2, BT_UINT16],
	[2, 1, BT_ENUM],
	[3, 1, BT_ENUM],
	[4, 1, BT_ENUM],
	[5, 4, BT_UINT32],
]

var _data: StreamPeerBuffer = StreamPeerBuffer.new()
## Local types whose definition was written.
var _defined: Dictionary = {}
var _lap_name_declared: bool = false
## Write the heart rate fields (set before the first record, lap or session).
var heart_rate: bool = false


func _init() -> void:
	_data.big_endian = false


## Unix seconds -> FIT seconds.
static func fit_time(unix_s: int) -> int:
	return unix_s - FIT_EPOCH_UNIX


## FIT seconds -> Unix seconds.
static func unix_time(fit_s: int) -> int:
	return fit_s + FIT_EPOCH_UNIX


# --- Builder -------------------------------------------------------------------


func file_id(time_created_unix: int, serial: int) -> void:
	_ensure_def(LOCAL_FILE_ID, MESG_FILE_ID, DEF_FILE_ID)
	_data_mesg(
		LOCAL_FILE_ID,
		DEF_FILE_ID,
		[
			FILE_ACTIVITY,
			MANUFACTURER_DEVELOPMENT,
			PRODUCT_ID,
			_serial(serial),
			fit_time(time_created_unix),
			PRODUCT_NAME,
		]
	)


## Declares the developer field that carries lap names (written once, before any lap).
func declare_lap_name_field() -> void:
	if _lap_name_declared:
		return
	_lap_name_declared = true
	_ensure_def(LOCAL_DEVELOPER_DATA_ID, MESG_DEVELOPER_DATA_ID, DEF_DEVELOPER_DATA_ID)
	var app_id := PackedByteArray()
	for b in APPLICATION_ID:
		app_id.append(b)
	_data_mesg(LOCAL_DEVELOPER_DATA_ID, DEF_DEVELOPER_DATA_ID, [app_id, DEV_INDEX, 1])
	_ensure_def(LOCAL_FIELD_DESCRIPTION, MESG_FIELD_DESCRIPTION, DEF_FIELD_DESCRIPTION)
	_data_mesg(
		LOCAL_FIELD_DESCRIPTION,
		DEF_FIELD_DESCRIPTION,
		[
			DEV_INDEX,
			DEV_FIELD_LAP_NAME,
			BT_STRING,
			"lap_name",
		]
	)


## `software_version_x100`: the version times 100 (0.1.0 -> 10).
func device_info(ts_unix: int, serial: int, software_version_x100: int) -> void:
	_ensure_def(LOCAL_DEVICE_INFO, MESG_DEVICE_INFO, DEF_DEVICE_INFO)
	_data_mesg(
		LOCAL_DEVICE_INFO,
		DEF_DEVICE_INFO,
		[
			fit_time(ts_unix),
			DEVICE_INDEX_CREATOR,
			MANUFACTURER_DEVELOPMENT,
			_serial(serial),
			PRODUCT_ID,
			software_version_x100,
			SOURCE_TYPE_LOCAL,
			PRODUCT_NAME,
		]
	)


## Timer start (running) or stop (stop_all) event.
func timer_event(ts_unix: int, running: bool) -> void:
	_ensure_def(LOCAL_EVENT, MESG_EVENT, DEF_EVENT)
	_data_mesg(
		LOCAL_EVENT,
		DEF_EVENT,
		[
			fit_time(ts_unix),
			EVENT_TIMER,
			EVENT_TYPE_START if running else EVENT_TYPE_STOP_ALL,
			TIMER_TRIGGER_MANUAL,
			0,
		]
	)


## One record. Negative cadence or speed are written as invalid (absent), and so is a heart
## rate of 0 or less (written only with `heart_rate` on).
func record(
	ts_unix: int,
	power_w: float,
	cadence_rpm: float,
	speed_mps: float,
	distance_m: float,
	heart_rate_bpm: float = 0.0
) -> void:
	var def := DEF_RECORD_HR if heart_rate else DEF_RECORD
	_ensure_def(LOCAL_RECORD, MESG_RECORD, def)
	var values := [
		fit_time(ts_unix),
		_u16(power_w),
		_opt_u8(cadence_rpm),
		_opt_scaled_u16(speed_mps, 1000.0),
		_u32(distance_m * 100.0),
	]
	if heart_rate:
		values.append(_opt_hr(heart_rate_bpm))
	_data_mesg(LOCAL_RECORD, def, values)


## A lap. Keys: index, end_unix, start_unix, elapsed_s, timer_s, distance_m, avg_speed_mps,
## max_speed_mps, avg_power_w, max_power_w, avg_cadence_rpm, max_cadence_rpm (-1 = absent),
## work_j, trigger (LAP_TRIGGER_*), name; with `heart_rate` on also avg_heart_rate_bpm and
## max_heart_rate_bpm (<= 0 = absent).
func lap(d: Dictionary) -> void:
	declare_lap_name_field()
	var def := DEF_LAP + HR_LAP_FIELDS if heart_rate else DEF_LAP
	_ensure_def(LOCAL_LAP, MESG_LAP, def, DEV_DEF_LAP)
	var values := (
		[
			int(d.get("index", 0)),
			fit_time(int(d.get("end_unix", 0))),
			EVENT_LAP,
			EVENT_TYPE_STOP,
			fit_time(int(d.get("start_unix", 0))),
			_u32(float(d.get("elapsed_s", 0.0)) * 1000.0),
			_u32(float(d.get("timer_s", 0.0)) * 1000.0),
			_u32(float(d.get("distance_m", 0.0)) * 100.0),
			_opt_scaled_u16(float(d.get("avg_speed_mps", -1.0)), 1000.0),
			_opt_scaled_u16(float(d.get("max_speed_mps", -1.0)), 1000.0),
			_u16(float(d.get("avg_power_w", 0.0))),
			_u16(float(d.get("max_power_w", 0.0))),
			_opt_u8(float(d.get("avg_cadence_rpm", -1.0))),
			_opt_u8(float(d.get("max_cadence_rpm", -1.0))),
			_u32(float(d.get("work_j", 0.0))),
			int(d.get("trigger", LAP_TRIGGER_MANUAL)),
			SPORT_CYCLING,
			SUB_SPORT_VIRTUAL_ACTIVITY,
		]
		+ _hr_values(d)
	)
	_data_mesg(LOCAL_LAP, def, values, [_fixed_string(str(d.get("name", "")), LAP_NAME_SIZE)])


## The session. Keys as lap() plus first_lap_index and num_laps.
func session(d: Dictionary) -> void:
	var def := DEF_SESSION + HR_SESSION_FIELDS if heart_rate else DEF_SESSION
	_ensure_def(LOCAL_SESSION, MESG_SESSION, def)
	var values := (
		[
			0,
			fit_time(int(d.get("end_unix", 0))),
			EVENT_SESSION,
			EVENT_TYPE_STOP,
			fit_time(int(d.get("start_unix", 0))),
			SPORT_CYCLING,
			SUB_SPORT_VIRTUAL_ACTIVITY,
			_u32(float(d.get("elapsed_s", 0.0)) * 1000.0),
			_u32(float(d.get("timer_s", 0.0)) * 1000.0),
			_u32(float(d.get("distance_m", 0.0)) * 100.0),
			_opt_scaled_u16(float(d.get("avg_speed_mps", -1.0)), 1000.0),
			_opt_scaled_u16(float(d.get("max_speed_mps", -1.0)), 1000.0),
			_u16(float(d.get("avg_power_w", 0.0))),
			_u16(float(d.get("max_power_w", 0.0))),
			_opt_u8(float(d.get("avg_cadence_rpm", -1.0))),
			_opt_u8(float(d.get("max_cadence_rpm", -1.0))),
			_u32(float(d.get("work_j", 0.0))),
			int(d.get("first_lap_index", 0)),
			int(d.get("num_laps", 0)),
			SESSION_TRIGGER_ACTIVITY_END,
		]
		+ _hr_values(d)
	)
	_data_mesg(LOCAL_SESSION, def, values)


## The activity (one session). `local_offset_s`: the local time zone's offset from UTC in
## seconds, or null to leave local_timestamp absent.
func activity(ts_unix: int, timer_s: float, local_offset_s: Variant = null) -> void:
	_ensure_def(LOCAL_ACTIVITY, MESG_ACTIVITY, DEF_ACTIVITY)
	var local_ts: Variant = null
	if local_offset_s != null:
		local_ts = fit_time(ts_unix) + int(local_offset_s)
	_data_mesg(
		LOCAL_ACTIVITY,
		DEF_ACTIVITY,
		[
			fit_time(ts_unix),
			_u32(timer_s * 1000.0),
			1,
			ACTIVITY_TYPE_MANUAL,
			EVENT_ACTIVITY,
			EVENT_TYPE_STOP,
			local_ts,
		]
	)


## The complete file: header (with its CRC), the messages and the file CRC.
func finish() -> PackedByteArray:
	var body := _data.data_array
	var out := StreamPeerBuffer.new()
	out.big_endian = false
	out.put_u8(HEADER_SIZE)
	out.put_u8(PROTOCOL_VERSION)
	out.put_u16(PROFILE_VERSION)
	out.put_u32(body.size())
	out.put_data(".FIT".to_ascii_buffer())
	out.put_u16(FitCrc.compute(out.data_array, 0, 12))
	out.put_data(body)
	var bytes := out.data_array
	var crc := FitCrc.compute(bytes)
	bytes.append(crc & 0xFF)
	bytes.append((crc >> 8) & 0xFF)
	return bytes


# --- Whole ride -------------------------------------------------------------------


## Encodes a ride as RideRecorder.fit_data() returns it:
## {utc_start_unix, serial, software_version_x100, local_offset_s (or null),
##  records: [{t (Unix s), power_w, cadence_rpm, speed_mps, distance_m, heart_rate_bpm}],
##  events: [{t, running}], laps: [lap() dictionaries], session: {session() keys},
##  end_unix, timer_s, heart_rate (bool: write the heart rate fields)}.
## Messages are written in time order: laps before the timer events and records of the same
## second, then the last timer stop, the last lap, the session and the activity.
static func encode_ride(ride: Dictionary) -> PackedByteArray:
	var enc := FitEncoder.new()
	enc.heart_rate = bool(ride.get("heart_rate", false))
	var start_unix := int(ride.get("utc_start_unix", 0))
	var serial := int(ride.get("serial", 1))
	enc.file_id(start_unix, serial)
	enc.declare_lap_name_field()
	enc.device_info(start_unix, serial, int(ride.get("software_version_x100", 0)))
	var items: Array = []
	var order := 0
	var laps: Array = ride.get("laps", [])
	for i in laps.size():
		if i == laps.size() - 1:
			break
		var ld: Dictionary = laps[i]
		items.append([int(ld.get("end_unix", 0)), 0, order, "lap", ld])
		order += 1
	var events: Array = ride.get("events", [])
	var last_stop: Variant = null
	for i in events.size():
		var ev: Dictionary = events[i]
		if i == events.size() - 1 and not bool(ev.get("running", true)):
			last_stop = ev
			continue
		items.append([int(ev.get("t", 0)), 1, order, "event", ev])
		order += 1
	for rec: Dictionary in ride.get("records", []):
		items.append([int(rec.get("t", 0)), 2, order, "record", rec])
		order += 1
	items.sort_custom(
		func(a: Array, b: Array) -> bool:
			if int(a[0]) != int(b[0]):
				return int(a[0]) < int(b[0])
			if int(a[1]) != int(b[1]):
				return int(a[1]) < int(b[1])
			return int(a[2]) < int(b[2])
	)
	for it: Array in items:
		var d: Dictionary = it[4]
		match str(it[3]):
			"lap":
				enc.lap(d)
			"event":
				enc.timer_event(int(d.get("t", 0)), bool(d.get("running", true)))
			"record":
				enc.record(
					int(d.get("t", 0)),
					float(d.get("power_w", 0.0)),
					float(d.get("cadence_rpm", -1.0)),
					float(d.get("speed_mps", -1.0)),
					float(d.get("distance_m", 0.0)),
					float(d.get("heart_rate_bpm", 0.0))
				)
	if last_stop != null:
		enc.timer_event(int((last_stop as Dictionary).get("t", 0)), false)
	if not laps.is_empty():
		enc.lap(laps[laps.size() - 1])
	enc.session(ride.get("session", {}))
	enc.activity(
		int(ride.get("end_unix", start_unix)),
		float(ride.get("timer_s", 0.0)),
		ride.get("local_offset_s", null)
	)
	return enc.finish()


# --- Internals -------------------------------------------------------------------


func _ensure_def(local: int, global: int, fields: Array, dev_fields: Array = []) -> void:
	if _defined.has(local):
		return
	_defined[local] = true
	var header := 0x40 | (local & 0x0F)
	if not dev_fields.is_empty():
		header |= 0x20
	_data.put_u8(header)
	_data.put_u8(0)  # reserved
	_data.put_u8(0)  # architecture: little endian
	_data.put_u16(global)
	_data.put_u8(fields.size())
	for f: Array in fields:
		_data.put_u8(int(f[0]))
		_data.put_u8(int(f[1]))
		_data.put_u8(int(f[2]))
	if not dev_fields.is_empty():
		_data.put_u8(dev_fields.size())
		for f: Array in dev_fields:
			_data.put_u8(int(f[0]))
			_data.put_u8(int(f[1]))
			_data.put_u8(int(f[2]))


func _data_mesg(local: int, fields: Array, values: Array, dev_values: Array = []) -> void:
	_data.put_u8(local & 0x0F)
	for i in fields.size():
		var f: Array = fields[i]
		_put_value(int(f[1]), int(f[2]), values[i] if i < values.size() else null)
	for v: Variant in dev_values:
		_data.put_data(v as PackedByteArray)


func _put_value(size: int, base_type: int, value: Variant) -> void:
	match base_type:
		BT_STRING:
			_data.put_data(_fixed_string("" if value == null else str(value), size))
		BT_BYTE:
			var raw := PackedByteArray()
			if value is PackedByteArray:
				raw = value
			raw.resize(size)
			if value == null:
				raw.fill(0xFF)
			_data.put_data(raw)
		BT_ENUM, BT_UINT8:
			_data.put_u8(0xFF if value == null else clampi(int(value), 0, 0xFF))
		BT_UINT16:
			_data.put_u16(0xFFFF if value == null else clampi(int(value), 0, 0xFFFF))
		BT_UINT32:
			_data.put_u32(0xFFFFFFFF if value == null else clampi(int(value), 0, 0xFFFFFFFF))
		BT_UINT32Z:
			_data.put_u32(0 if value == null else clampi(int(value), 0, 0xFFFFFFFF))
		_:
			push_error("FitEncoder: unsupported base type %d" % base_type)


## A UTF-8 string in exactly `size` bytes: truncated on a character boundary so at least one
## terminating zero remains, then zero padded.
static func _fixed_string(text: String, size: int) -> PackedByteArray:
	var raw := text.to_utf8_buffer()
	if raw.size() > size - 1:
		var cut := size - 1
		# Step back over UTF-8 continuation bytes (10xxxxxx) so no character is split.
		while cut > 0 and (raw[cut] & 0xC0) == 0x80:
			cut -= 1
		raw = raw.slice(0, cut)
	raw.resize(size)
	return raw


static func _serial(serial: int) -> int:
	var s := serial & 0xFFFFFFFF
	return s if s != 0 else 1


## Rounded, clamped to the valid uint16 range (0xFFFF is the invalid marker).
static func _u16(v: float) -> int:
	return clampi(roundi(maxf(v, 0.0)), 0, 0xFFFE)


static func _u32(v: float) -> int:
	return clampi(roundi(maxf(v, 0.0)), 0, 0xFFFFFFFE)


static func _opt_u8(v: float) -> Variant:
	if v < 0.0:
		return null
	return clampi(roundi(v), 0, 0xFE)


## A heart rate in bpm (<= 0 = absent).
static func _opt_hr(v: float) -> Variant:
	return _opt_u8(v) if v > 0.0 else null


## The lap or session heart rate values (avg, max) when `heart_rate` is on, else none.
func _hr_values(d: Dictionary) -> Array:
	if not heart_rate:
		return []
	return [
		_opt_hr(float(d.get("avg_heart_rate_bpm", -1.0))),
		_opt_hr(float(d.get("max_heart_rate_bpm", -1.0))),
	]


static func _opt_scaled_u16(v: float, scale: float) -> Variant:
	if v < 0.0:
		return null
	return clampi(roundi(v * scale), 0, 0xFFFE)
