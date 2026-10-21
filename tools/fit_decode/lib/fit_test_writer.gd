class_name QaFitWriter
extends RefCounted
## A minimal FIT writer for qa's decoder tests and fixtures (owned by qa). It is deliberately
## not the rides encoder: it builds arbitrary definition and data messages (little or big endian,
## developer fields, compressed timestamps) so tools/fit_decode can be tested on its own, and it
## can corrupt headers and CRCs on purpose.
##
## [codeblock]
## var w := QaFitWriter.new()
## w.define(0, QaFitDecoder.MESG_FILE_ID, [[0, 1, QaFitWriter.ENUM], [1, 2, QaFitWriter.UINT16]])
## w.data(0, [4, 255])
## var bytes := w.to_bytes()
## [/codeblock]

const ENUM := 0x00
const SINT8 := 0x01
const UINT8 := 0x02
const SINT16 := 0x83
const UINT16 := 0x84
const SINT32 := 0x85
const UINT32 := 0x86
const STRING := 0x07
const FLOAT32 := 0x88
const UINT8Z := 0x0A
const UINT16Z := 0x8B
const UINT32Z := 0x8C
const BYTE := 0x0D

## Local type -> {big: bool, fields: [[num, size, base]], dev: [[num, size, index]]}.
var _defs: Dictionary = {}
var _body := PackedByteArray()


## Write a definition message for `local` (0..15) and global message `global`.
## fields: [[field num, size, base type], ...]; dev_fields: [[num, size, developer index], ...].
func define(
	local: int, global: int, fields: Array, big_endian: bool = false, dev_fields: Array = []
) -> QaFitWriter:
	var h := 0x40 | (local & 0x0F)
	if not dev_fields.is_empty():
		h |= 0x20
	_body.append(h)
	_body.append(0)
	_body.append(1 if big_endian else 0)
	_put_uint(global, 2, big_endian)
	_body.append(fields.size())
	for f: Variant in fields:
		var fa: Array = f
		_body.append(int(fa[0]))
		_body.append(int(fa[1]))
		_body.append(int(fa[2]))
	if not dev_fields.is_empty():
		_body.append(dev_fields.size())
		for d: Variant in dev_fields:
			var da: Array = d
			_body.append(int(da[0]))
			_body.append(int(da[1]))
			_body.append(int(da[2]))
	_defs[local] = {
		"big": big_endian, "fields": fields.duplicate(true), "dev": dev_fields.duplicate(true)
	}
	return self


## Write a data message for `local` with one value per field, in definition order. A value may be
## an int, a float, a String or an Array (multi-value field); null writes the invalid value.
## dev_bytes fills the developer fields (zeros when short).
func data(local: int, values: Array, dev_bytes: PackedByteArray = PackedByteArray()) -> QaFitWriter:
	_body.append(local & 0x0F)
	_write_values(local, values, dev_bytes)
	return self


## A data message with a compressed timestamp header (local 0..3, offset 0..31).
func compressed(local: int, time_offset: int, values: Array) -> QaFitWriter:
	_body.append(0x80 | ((local & 0x3) << 5) | (time_offset & 0x1F))
	_write_values(local, values, PackedByteArray())
	return self


## Raw bytes appended to the data section (to build broken files).
func raw(bytes: PackedByteArray) -> QaFitWriter:
	_body.append_array(bytes)
	return self


func data_size() -> int:
	return _body.size()


## The whole file. opts: header_size (12 or 14), header_crc (true: computed, false: 0),
## protocol (0x20), profile (2132), data_size (override), bad_header_crc, bad_file_crc,
## signature (".FIT").
func to_bytes(opts: Dictionary = {}) -> PackedByteArray:
	var hs := int(opts.get("header_size", 14))
	var out := PackedByteArray()
	out.append(hs)
	out.append(int(opts.get("protocol", 0x20)))
	var tmp := PackedByteArray()
	tmp.resize(4)
	tmp.encode_u16(0, int(opts.get("profile", 2132)))
	out.append(tmp[0])
	out.append(tmp[1])
	tmp.encode_u32(0, int(opts.get("data_size", _body.size())))
	out.append_array(tmp)
	out.append_array(str(opts.get("signature", ".FIT")).to_ascii_buffer())
	if hs == 14:
		var hcrc := QaFitDecoder.crc16(out, 0, 12) if bool(opts.get("header_crc", true)) else 0
		if bool(opts.get("bad_header_crc", false)):
			hcrc = hcrc ^ 0x5A5A
		tmp.encode_u16(0, hcrc)
		out.append(tmp[0])
		out.append(tmp[1])
	out.append_array(_body)
	var crc := QaFitDecoder.crc16(out)
	if bool(opts.get("bad_file_crc", false)):
		crc = crc ^ 0x00FF
	tmp.encode_u16(0, crc)
	out.append(tmp[0])
	out.append(tmp[1])
	return out


## A Wattlands-shaped activity: file_id, device_info, timer start, 1 Hz records, laps of the
## given lengths, timer stop, session and activity. opts: records (120), laps ([60, 60]),
## start (FIT timestamp, 1_100_000_000), power (150), cadence (90), speed_mps (8.0), sport (2),
## sub_sport (58), file_type (4), num_laps (lap count), skip ([] message names to leave out:
## "file_id", "device_info", "event", "lap", "session", "activity").
static func activity(opts: Dictionary = {}) -> PackedByteArray:
	return activity_writer(opts).to_bytes(opts)


static func activity_writer(opts: Dictionary = {}) -> QaFitWriter:
	var n := int(opts.get("records", 120))
	var lap_lengths: Array = opts.get("laps", [60, 60])
	var start := int(opts.get("start", 1_100_000_000))
	var power := int(opts.get("power", 150))
	var cadence := int(opts.get("cadence", 90))
	var speed := float(opts.get("speed_mps", 8.0))
	var skip: Array = opts.get("skip", [])
	var w := QaFitWriter.new()
	if not skip.has("file_id"):
		w.define(
			0,
			QaFitDecoder.MESG_FILE_ID,
			[[0, 1, ENUM], [1, 2, UINT16], [2, 2, UINT16], [3, 4, UINT32Z], [4, 4, UINT32]]
		)
		w.data(0, [int(opts.get("file_type", 4)), 255, 1, 12345, start])
	if not skip.has("device_info"):
		w.define(
			1,
			QaFitDecoder.MESG_DEVICE_INFO,
			[[253, 4, UINT32], [0, 1, UINT8], [2, 2, UINT16], [4, 2, UINT16]]
		)
		w.data(1, [start, 0, 255, 1])
	w.define(2, QaFitDecoder.MESG_EVENT, [[253, 4, UINT32], [0, 1, ENUM], [1, 1, ENUM]])
	if not skip.has("event"):
		w.data(2, [start, 0, 0])
	w.define(
		3,
		QaFitDecoder.MESG_RECORD,
		[[253, 4, UINT32], [7, 2, UINT16], [4, 1, UINT8], [6, 2, UINT16], [5, 4, UINT32]]
	)
	var dist := 0.0
	for i in n:
		w.data(
			3, [start + i, power, cadence, int(roundf(speed * 1000.0)), int(roundf(dist * 100.0))]
		)
		dist += speed
	if not skip.has("event"):
		w.data(2, [start + n, 0, 4])
	w.define(
		4,
		QaFitDecoder.MESG_LAP,
		[
			[253, 4, UINT32],
			[254, 2, UINT16],
			[2, 4, UINT32],
			[7, 4, UINT32],
			[8, 4, UINT32],
			[9, 4, UINT32],
			[41, 4, UINT32],
			[19, 2, UINT16],
			[20, 2, UINT16],
			[17, 1, UINT8],
			[18, 1, UINT8]
		]
	)
	var t := 0
	var li := 0
	if not skip.has("lap"):
		for len_v: Variant in lap_lengths:
			var length := int(len_v)
			w.data(
				4,
				[
					start + t + length,
					li,
					start + t,
					length * 1000,
					length * 1000,
					int(roundf(length * speed * 100.0)),
					length * power,
					power,
					power,
					cadence,
					cadence
				]
			)
			t += length
			li += 1
	if not skip.has("session"):
		w.define(
			5,
			QaFitDecoder.MESG_SESSION,
			[
				[253, 4, UINT32],
				[2, 4, UINT32],
				[5, 1, ENUM],
				[6, 1, ENUM],
				[7, 4, UINT32],
				[8, 4, UINT32],
				[9, 4, UINT32],
				[48, 4, UINT32],
				[20, 2, UINT16],
				[21, 2, UINT16],
				[18, 1, UINT8],
				[19, 1, UINT8],
				[26, 2, UINT16]
			]
		)
		w.data(
			5,
			[
				start + n,
				start,
				int(opts.get("sport", 2)),
				int(opts.get("sub_sport", 58)),
				n * 1000,
				n * 1000,
				int(roundf(n * speed * 100.0)),
				n * power,
				power,
				power,
				cadence,
				cadence,
				int(opts.get("num_laps", li))
			]
		)
	if not skip.has("activity"):
		w.define(
			6,
			QaFitDecoder.MESG_ACTIVITY,
			[
				[253, 4, UINT32],
				[0, 4, UINT32],
				[1, 2, UINT16],
				[2, 1, ENUM],
				[3, 1, ENUM],
				[4, 1, ENUM]
			]
		)
		w.data(6, [start + n, n * 1000, 1, 0, 26, 1])
	return w


func _write_values(local: int, values: Array, dev_bytes: PackedByteArray) -> void:
	var def: Dictionary = _defs.get(local, {})
	var fields: Array = def.get("fields", [])
	var big: bool = def.get("big", false)
	for i in fields.size():
		var f: Array = fields[i]
		var v: Variant = values[i] if i < values.size() else null
		_put_field(v, int(f[1]), int(f[2]), big)
	var dev_total := 0
	for d: Variant in def.get("dev", []):
		dev_total += int((d as Array)[1])
	for i in dev_total:
		_body.append(dev_bytes[i] if i < dev_bytes.size() else 0)


func _put_field(v: Variant, size: int, base: int, big: bool) -> void:
	var b := base & 0x1F
	var bt: Array = QaFitDecoder.BASE_TYPES[b]
	var bsize := int(bt[1])
	if str(bt[0]) == "string":
		var s := (str(v) if v != null else "").to_utf8_buffer()
		for i in size:
			_body.append(s[i] if i < s.size() else 0)
		return
	var count := size / bsize
	for i in count:
		var item: Variant = v
		if v is Array:
			item = (v as Array)[i] if i < (v as Array).size() else null
		if item == null:
			_put_uint(int(bt[2]), bsize, big)
		elif str(bt[0]) == "float32":
			var tmp := PackedByteArray()
			tmp.resize(4)
			tmp.encode_float(0, float(item))
			_put_uint(tmp.decode_u32(0), 4, big)
		else:
			_put_uint(int(item), bsize, big)


func _put_uint(v: int, size: int, big: bool) -> void:
	for i in size:
		var shift := 8 * (size - 1 - i) if big else 8 * i
		_body.append((v >> shift) & 0xFF)
