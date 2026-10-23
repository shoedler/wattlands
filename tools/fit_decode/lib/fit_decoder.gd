class_name QaFitDecoder
extends RefCounted
## An independent FIT decoder (BRIEF 3.8): the fallback that tools/fit_check/check.mjs runs when
## @garmin/fitsdk can't be loaded, and the decoder the B 7.4/7.5 scenario tests use in-process.
## Owned by qa. Written from the FIT protocol document, not from the rides encoder, so it checks
## that encoder independently.
##
## It checks the file header (size, ".FIT", data size, header CRC), the file CRC (the FIT SDK's
## CRC-16), every definition and data message (normal and compressed-timestamp headers, little
## and big endian, developer fields kept as raw bytes), chained files, and the messages Wattlands
## writes: file_id (type activity 4), device_info, event, record, lap (its name from the developer
## field that a field_description message calls "lap_name"), session (sport cycling 2, sub_sport
## virtual_activity 58) and activity. decode_bytes() returns the per-file summary that
## tools/fit_decode/decode.gd prints (the JSON schema is documented in docs/decisions/qa.md):
##   {path, ok, errors: [String], warnings: [String], header: {...}, crc_ok, segments,
##    messages: {name: count}, file_id: {...}, records, record_span_s, record_gaps,
##    first_record_ts, last_record_ts, laps: [{index, name, start_time, start_s, duration_s,
##    timer_s, distance_m, work_kj, avg_power_w, max_power_w, avg_cadence_rpm,
##    max_cadence_rpm}], session: {...} or {}, sessions, activity: {...} or {}, events,
##    timer_starts, timer_stops (every timer event that isn't a start), device_infos}
## tests/scenarios/unit/test_fit_decoder_vs_sdk.gd checks it against @garmin/fitsdk on real
## rides-encoder files.
## Times in the summary are seconds; FIT timestamps (start_time) stay raw FIT seconds.
## "decode_errors" holds the structural problems only (header, CRCs, truncation, undefined
## messages); "errors" adds the Wattlands checks (file type, one session and activity, sport,
## records, laps).
##
## tools/fit_check/check.mjs (rides) calls the fallback as
## `decode.gd -- --json-out=<abs path> --file=<abs path>...` and reads the JSON that
## rides_contract() builds (schema in tools/fit_check/README.md, "Fallback decoder contract").

## FIT time zero, 1989-12-31 00:00:00 UTC, in Unix seconds (BRIEF 3.8).
const FIT_EPOCH_UNIX := 631065600

const MESG_FILE_ID := 0
const MESG_SESSION := 18
const MESG_LAP := 19
const MESG_RECORD := 20
const MESG_EVENT := 21
const MESG_DEVICE_INFO := 23
const MESG_ACTIVITY := 34
const MESG_FIELD_DESCRIPTION := 206
## The developer field (described by a field_description message) that names laps.
const LAP_NAME_FIELD := "lap_name"

const MESG_NAMES: Dictionary = {
	0: "file_id",
	18: "session",
	19: "lap",
	20: "record",
	21: "event",
	23: "device_info",
	34: "activity",
	49: "file_creator",
	206: "field_description",
	207: "developer_data_id",
}

const FILE_TYPE_ACTIVITY := 4
const SPORT_CYCLING := 2
const SUB_SPORT_VIRTUAL_ACTIVITY := 58
const EVENT_TIMER := 0
const EVENT_TYPE_START := 0
const EVENT_TYPE_STOP := 1
const EVENT_TYPE_STOP_ALL := 4
const FIELD_TIMESTAMP := 253

## Base types by number (the base type byte's low 5 bits): [name, size, invalid value].
## Invalid values of 64-bit types are compared bit for bit (GDScript ints are signed 64-bit).
const BASE_TYPES: Array = [
	["enum", 1, 0xFF],
	["sint8", 1, 0x7F],
	["uint8", 1, 0xFF],
	["sint16", 2, 0x7FFF],
	["uint16", 2, 0xFFFF],
	["sint32", 4, 0x7FFFFFFF],
	["uint32", 4, 0xFFFFFFFF],
	["string", 1, 0x00],
	["float32", 4, 0xFFFFFFFF],
	["float64", 8, -1],
	["uint8z", 1, 0x00],
	["uint16z", 2, 0x0000],
	["uint32z", 4, 0x00000000],
	["byte", 1, 0xFF],
	["sint64", 8, 0x7FFFFFFFFFFFFFFF],
	["uint64", 8, -1],
	["uint64z", 8, 0],
]

const CRC_TABLE: Array[int] = [
	0x0000,
	0xCC01,
	0xD801,
	0x1400,
	0xF001,
	0x3C00,
	0x2800,
	0xE401,
	0xA001,
	0x6C00,
	0x7800,
	0xB401,
	0x5000,
	0x9C01,
	0x8801,
	0x4400,
]

## Stop collecting errors after this many per file (a corrupt file can produce thousands).
const MAX_ERRORS := 50


## The FIT SDK's CRC-16 over bytes[from, to) (to = -1: the end), starting from `crc`.
static func crc16(bytes: PackedByteArray, from: int = 0, to: int = -1, crc: int = 0) -> int:
	var end := bytes.size() if to < 0 else mini(to, bytes.size())
	var c := crc
	for i in range(from, end):
		var b := bytes[i]
		var tmp := CRC_TABLE[c & 0xF]
		c = (c >> 4) & 0x0FFF
		c = c ^ tmp ^ CRC_TABLE[b & 0xF]
		tmp = CRC_TABLE[c & 0xF]
		c = (c >> 4) & 0x0FFF
		c = c ^ tmp ^ CRC_TABLE[(b >> 4) & 0xF]
	return c


## Unix seconds for a FIT timestamp.
static func fit_to_unix(fit_ts: int) -> int:
	return fit_ts + FIT_EPOCH_UNIX


## Decode a file on disk. `opts`: {"expect_laps": int (-1 = no check)}.
static func decode_file(path: String, opts: Dictionary = {}) -> Dictionary:
	if not FileAccess.file_exists(path):
		var missing := _empty_summary(path)
		_derr(missing, "no such file: %s" % path)
		missing["ok"] = false
		return missing
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty() and FileAccess.get_open_error() != OK:
		var unreadable := _empty_summary(path)
		_derr(unreadable, "cannot read %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		unreadable["ok"] = false
		return unreadable
	return decode_bytes(bytes, path, opts)


## Decode FIT bytes and summarize them. Never push_errors: problems go into "errors".
static func decode_bytes(
	bytes: PackedByteArray, path: String = "", opts: Dictionary = {}
) -> Dictionary:
	var s := _empty_summary(path)
	var messages: Array[Dictionary] = []
	var offset := 0
	var segment := 0
	var crc_ok := true
	while offset < bytes.size():
		if segment > 0 and not _looks_like_header(bytes, offset):
			_derr(
				s,
				(
					"%d trailing byte(s) after the file CRC at offset %d"
					% [bytes.size() - offset, offset]
				)
			)
			break
		var seg := _decode_segment(bytes, offset, s, messages)
		if seg["header"] is Dictionary and segment == 0:
			s["header"] = seg["header"]
		if segment == 0:
			s["is_fit"] = bool(seg["header_ok"])
		if not bool(seg["crc_ok"]):
			crc_ok = false
		segment += 1
		if not bool(seg["ok"]):
			break
		offset = int(seg["next"])
	if bytes.is_empty():
		_derr(s, "empty file")
		crc_ok = false
	s["segments"] = segment
	s["crc_ok"] = crc_ok
	s["integrity"] = bool(s["is_fit"]) and crc_ok
	_summarize(s, messages, opts)
	s["ok"] = (s["errors"] as Array).is_empty()
	return s


## Command line of tools/fit_decode/decode.gd:
##   <file|dir>... [--file=<path>]... [--expect-laps=<n>] [--json] [--out=<file>] [--json-out=<file>]
## Returns {"code": int, "out": PackedStringArray, "err": PackedStringArray, "result": Dictionary}.
## Exit codes: 0 every file decoded without errors, 1 any error, 2 usage error. --json-out writes
## the JSON tools/fit_check/check.mjs reads (rides_contract(), decode errors only) and then exits 0
## even for bad files, as that contract asks. Relative paths resolve against the project root
## (Godot runs with --path).
static func run_cli(argv: PackedStringArray) -> Dictionary:
	var out := PackedStringArray()
	var err := PackedStringArray()
	var as_json := false
	var expect_laps := -1
	var out_file := ""
	var json_out := ""
	var inputs: Array[String] = []
	for a in argv:
		if a == "--json":
			as_json = true
		elif a == "--help" or a == "-h":
			out.append(usage())
			return {"code": 0, "out": out, "err": err, "result": {}}
		elif a.begins_with("--expect-laps="):
			var v := a.substr("--expect-laps=".length())
			if not v.is_valid_int() or int(v) < 0:
				err.append('fit_decode: --expect-laps needs a whole number >= 0, got "%s"' % v)
				err.append(usage())
				return {"code": 2, "out": out, "err": err, "result": {}}
			expect_laps = int(v)
		elif a.begins_with("--out=") or a.begins_with("--json-out="):
			var target := a.substr(a.find("=") + 1)
			if target == "":
				err.append("fit_decode: %s needs a file path" % a.substr(0, a.find("=")))
				return {"code": 2, "out": out, "err": err, "result": {}}
			if a.begins_with("--out="):
				out_file = target
			else:
				json_out = target
		elif a.begins_with("--file="):
			var f := a.substr("--file=".length())
			if f == "":
				err.append("fit_decode: --file needs a path")
				return {"code": 2, "out": out, "err": err, "result": {}}
			inputs.append(f)
		elif a.begins_with("--"):
			err.append('fit_decode: unknown option "%s"' % a)
			err.append(usage())
			return {"code": 2, "out": out, "err": err, "result": {}}
		elif a != "":
			inputs.append(a)
	if inputs.is_empty():
		err.append("fit_decode: no FIT file or directory given")
		err.append(usage())
		return {"code": 2, "out": out, "err": err, "result": {}}

	var files: Array[Dictionary] = []
	for input in inputs:
		var p := resolve_path(input)
		if DirAccess.dir_exists_absolute(p):
			var found: Array[String] = []
			_collect_fit_files(p, found)
			found.sort()
			if found.is_empty():
				var none := _empty_summary(p)
				_derr(none, "no FIT files under %s" % p)
				none["ok"] = false
				files.append(none)
			for f in found:
				files.append(decode_file(f, {"expect_laps": expect_laps}))
		else:
			var one := decode_file(p, {"expect_laps": expect_laps})
			one["input"] = input
			files.append(one)
	var failed := 0
	for f in files:
		if not bool(f["ok"]):
			failed += 1
	var result := {
		"decoder": "wattlands-fit-decode-gd",
		"version": 1,
		"ok": failed == 0,
		"files": files,
		"failed": failed,
	}
	if out_file != "":
		var why := _write_json(out_file, result)
		if why != "":
			err.append("fit_decode: %s" % why)
			return {"code": 2, "out": out, "err": err, "result": result}
	if json_out != "":
		var contract: Array = []
		for f in files:
			contract.append(rides_contract(f))
		var why2 := _write_json(json_out, {"decoder": "gdscript", "files": contract})
		if why2 != "":
			err.append("fit_decode: %s" % why2)
			return {"code": 2, "out": out, "err": err, "result": result}
	if as_json:
		out.append(JSON.stringify(result, "", true))
	elif json_out == "":
		for f in files:
			out.append_array(format_text(f))
		out.append("fit_decode: %d file(s), %d with errors" % [files.size(), failed])
	else:
		out.append(
			(
				"fit_decode: %d file(s), %d with errors, JSON in %s"
				% [files.size(), failed, resolve_path(json_out)]
			)
		)
	var code := 0 if failed == 0 or (json_out != "" and out_file == "" and not as_json) else 1
	return {"code": code, "out": out, "err": err, "result": result}


static func _write_json(path: String, value: Dictionary) -> String:
	var target := resolve_path(path)
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var fa := FileAccess.open(target, FileAccess.WRITE)
	if fa == null:
		return "cannot write %s (%s)" % [target, error_string(FileAccess.get_open_error())]
	fa.store_string(JSON.stringify(value, "  ", true) + "\n")
	fa.close()
	return ""


static func usage() -> String:
	return (
		"usage: tools/godot.sh --headless --path . -s tools/fit_decode/decode.gd -- <file|dir>... "
		+ "[--file=<path>]... [--expect-laps=<n>] [--json] [--out=<file>] [--json-out=<file>]"
	)


## Absolute OS path for a CLI argument: res:// and user:// are globalized, relative paths are
## taken from the project root.
static func resolve_path(p: String) -> String:
	var q := p.strip_edges()
	if q.begins_with("res://") or q.begins_with("user://"):
		return ProjectSettings.globalize_path(q).replace("\\", "/")
	q = q.replace("\\", "/")
	if q.is_absolute_path():
		return q.simplify_path()
	return ProjectSettings.globalize_path("res://").replace("\\", "/").path_join(q).simplify_path()


## The text summary of one file (the same layout as tools/fit_check/check.mjs).
static func format_text(f: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var errors: Array = f.get("errors", [])
	lines.append("%s: %s" % [str(f.get("path", "")), "OK" if bool(f.get("ok", false)) else "FAIL"])
	lines.append("  errors: %d" % errors.size())
	for e: Variant in errors:
		lines.append("    - %s" % str(e))
	for w: Variant in f.get("warnings", []):
		lines.append("  warning: %s" % str(w))
	lines.append(
		(
			"  records: %d (span %s s)"
			% [int(f.get("records", 0)), _num(float(f.get("record_span_s", 0.0)))]
		)
	)
	var laps: Array = f.get("laps", [])
	lines.append("  laps: %d" % laps.size())
	for lap: Variant in laps:
		var l: Dictionary = lap
		lines.append(
			(
				"    %d: start %s s, duration %s s"
				% [
					int(l.get("index", 0)) + 1,
					_num(float(l.get("start_s", 0.0))),
					_num(float(l.get("duration_s", 0.0)))
				]
			)
		)
	var ses: Dictionary = f.get("session", {})
	if ses.is_empty():
		lines.append("  session: none")
	else:
		var line := (
			"  session: sport %s, sub_sport %s, elapsed %s s, timer %s s, distance %s m, "
			+ "work %s kJ, avg %s W, max %s W, avg cadence %s rpm, max cadence %s rpm"
		)
		(
			lines
			. append(
				(
					line
					% [
						str(ses.get("sport", "?")),
						str(ses.get("sub_sport", "?")),
						_num(float(ses.get("elapsed_s", 0.0))),
						_num(float(ses.get("timer_s", 0.0))),
						_num(float(ses.get("distance_m", 0.0))),
						_num(float(ses.get("work_kj", 0.0))),
						_num(float(ses.get("avg_power_w", 0.0))),
						_num(float(ses.get("max_power_w", 0.0))),
						_num(float(ses.get("avg_cadence_rpm", 0.0))),
						_num(float(ses.get("max_cadence_rpm", 0.0))),
					]
				)
			)
		)
	return lines


# ---------------------------------------------------------------------------------------------
# Segment decoding


static func _looks_like_header(bytes: PackedByteArray, at: int) -> bool:
	if at + 12 > bytes.size():
		return false
	var hs := bytes[at]
	if hs != 12 and hs != 14:
		return false
	return bytes.slice(at + 8, at + 12).get_string_from_ascii() == ".FIT"


## One FIT file starting at `start`. Appends its messages. Returns {ok, next, crc_ok, header}.
static func _decode_segment(
	bytes: PackedByteArray, start: int, s: Dictionary, messages: Array[Dictionary]
) -> Dictionary:
	var res := {
		"ok": false, "next": bytes.size(), "crc_ok": false, "header": null, "header_ok": false
	}
	if start + 12 > bytes.size():
		_derr(s, "file too short for a FIT header (%d bytes)" % (bytes.size() - start))
		return res
	var hs := bytes[start]
	if hs != 12 and hs != 14:
		_derr(s, "bad header size %d (expected 12 or 14)" % hs)
		return res
	if start + hs > bytes.size():
		_derr(s, "file too short for its %d-byte header" % hs)
		return res
	var sig := bytes.slice(start + 8, start + 12).get_string_from_ascii()
	var header := {
		"size": hs,
		"protocol_version": bytes[start + 1],
		"profile_version": bytes.decode_u16(start + 2),
		"data_size": bytes.decode_u32(start + 4),
		"data_type": sig,
		"header_crc": -1,
		"header_crc_ok": true,
	}
	res["header"] = header
	if sig != ".FIT":
		_derr(s, 'missing ".FIT" signature in the header')
		return res
	res["header_ok"] = true
	if (int(header["protocol_version"]) >> 4) > 2:
		_derr(
			s,
			(
				"unsupported protocol version %d.%d"
				% [int(header["protocol_version"]) >> 4, int(header["protocol_version"]) & 0xF]
			)
		)
	if hs == 14:
		var hcrc := bytes.decode_u16(start + 12)
		header["header_crc"] = hcrc
		if hcrc != 0:
			var calc := crc16(bytes, start, start + 12)
			if calc != hcrc:
				header["header_crc_ok"] = false
				_derr(s, "header CRC mismatch: stored 0x%04X, computed 0x%04X" % [hcrc, calc])
	var data_start := start + hs
	var data_size := int(header["data_size"])
	var data_end := data_start + data_size
	if data_end + 2 > bytes.size():
		_derr(
			s,
			(
				"data size %d plus the 2-byte CRC runs past the end of the file (%d bytes after the header)"
				% [data_size, bytes.size() - data_start]
			)
		)
		data_end = mini(data_end, bytes.size())
		_decode_records(bytes, data_start, data_end, s, messages)
		return res
	var stored := bytes.decode_u16(data_end)
	var computed := crc16(bytes, start, data_end)
	res["crc_ok"] = stored == computed and bool(header["header_crc_ok"])
	if stored != computed:
		_derr(s, "file CRC mismatch: stored 0x%04X, computed 0x%04X" % [stored, computed])
	_decode_records(bytes, data_start, data_end, s, messages)
	res["ok"] = true
	res["next"] = data_end + 2
	return res


## Decode the definition and data messages in bytes[from, to).
static func _decode_records(
	bytes: PackedByteArray, from: int, to: int, s: Dictionary, messages: Array[Dictionary]
) -> void:
	var defs: Dictionary = {}
	var last_ts := -1
	var p := from
	while p < to:
		var h := bytes[p]
		p += 1
		if (h & 0x80) != 0:
			# Compressed timestamp header: local type in bits 5-6, time offset in bits 0-4.
			var local_c := (h >> 5) & 0x3
			var offset := h & 0x1F
			if not defs.has(local_c):
				_derr(
					s,
					(
						"compressed-timestamp data message for undefined local type %d at offset %d"
						% [local_c, p - 1]
					)
				)
				return
			if last_ts < 0:
				_derr(s, "compressed timestamp at offset %d before any full timestamp" % (p - 1))
				return
			var ts := (last_ts & ~0x1F) + offset
			if offset < (last_ts & 0x1F):
				ts += 0x20
			var dm := _read_data(bytes, p, to, defs[local_c], s)
			if dm.is_empty():
				return
			p = int(dm["next"])
			var fields: Dictionary = dm["fields"]
			fields[FIELD_TIMESTAMP] = ts
			last_ts = ts
			messages.append({"num": dm["num"], "fields": fields})
			continue
		var local := h & 0x0F
		if (h & 0x40) != 0:
			var d := _read_definition(bytes, p, to, (h & 0x20) != 0, s)
			if d.is_empty():
				return
			p = int(d["next"])
			defs[local] = d
		else:
			if not defs.has(local):
				_derr(s, "data message for undefined local type %d at offset %d" % [local, p - 1])
				return
			var dm2 := _read_data(bytes, p, to, defs[local], s)
			if dm2.is_empty():
				return
			p = int(dm2["next"])
			var f2: Dictionary = dm2["fields"]
			if f2.has(FIELD_TIMESTAMP) and f2[FIELD_TIMESTAMP] is int:
				last_ts = int(f2[FIELD_TIMESTAMP])
			messages.append({"num": dm2["num"], "fields": f2})


## {num, big, fields: [[num, size, base]], dev_size, next} or {} on a truncated definition.
static func _read_definition(
	bytes: PackedByteArray, p: int, to: int, has_dev: bool, s: Dictionary
) -> Dictionary:
	if p + 5 > to:
		_derr(s, "truncated definition message at offset %d" % (p - 1))
		return {}
	var big := bytes[p + 1] == 1
	if bytes[p + 1] > 1:
		_derr(s, "bad architecture byte %d in a definition at offset %d" % [bytes[p + 1], p - 1])
		return {}
	var num := _read_uint(bytes, p + 2, 2, big)
	var n := bytes[p + 4]
	var q := p + 5
	if q + n * 3 > to:
		_derr(s, "truncated field definitions at offset %d" % (p - 1))
		return {}
	var fields: Array = []
	for i in n:
		var fnum := bytes[q]
		var fsize := bytes[q + 1]
		var base := bytes[q + 2] & 0x1F
		if base >= BASE_TYPES.size():
			_warn(
				s,
				(
					"unknown base type 0x%02X for field %d of message %d (read as bytes)"
					% [bytes[q + 2], fnum, num]
				)
			)
			base = 13
		var bsize := int((BASE_TYPES[base] as Array)[1])
		if fsize == 0 or fsize % bsize != 0:
			_warn(
				s,
				(
					"field %d of message %d has size %d, not a multiple of its base type size %d (read as bytes)"
					% [fnum, num, fsize, bsize]
				)
			)
			base = 13
		fields.append([fnum, fsize, base])
		q += 3
	var dev_size := 0
	var dev_fields: Array = []
	if has_dev:
		if q + 1 > to:
			_derr(s, "truncated developer field count at offset %d" % (p - 1))
			return {}
		var nd := bytes[q]
		q += 1
		if q + nd * 3 > to:
			_derr(s, "truncated developer field definitions at offset %d" % (p - 1))
			return {}
		for i in nd:
			dev_fields.append([bytes[q], bytes[q + 1], bytes[q + 2]])
			dev_size += bytes[q + 1]
			q += 3
	return {
		"num": num,
		"big": big,
		"fields": fields,
		"dev_fields": dev_fields,
		"dev_size": dev_size,
		"next": q
	}


## {num, fields: {field num: value}, next} or {} when the message runs past `to`.
static func _read_data(
	bytes: PackedByteArray, p: int, to: int, def: Dictionary, s: Dictionary
) -> Dictionary:
	var q := p
	var big: bool = def["big"]
	var values: Dictionary = {}
	for fd: Variant in def["fields"]:
		var f: Array = fd
		var fsize := int(f[1])
		if q + fsize > to:
			_derr(s, "truncated data message (global %d) at offset %d" % [int(def["num"]), p - 1])
			return {}
		var v: Variant = _read_value(bytes, q, fsize, int(f[2]), big)
		if v != null:
			values[int(f[0])] = v
		q += fsize
	var dev := int(def["dev_size"])
	if q + dev > to:
		_derr(s, "truncated developer fields (global %d) at offset %d" % [int(def["num"]), p - 1])
		return {}
	# Developer fields stay raw bytes under "dev_<developer index>_<field number>".
	for df: Variant in def.get("dev_fields", []):
		var d: Array = df
		values["dev_%d_%d" % [int(d[2]), int(d[0])]] = bytes.slice(q, q + int(d[1]))
		q += int(d[1])
	return {"num": def["num"], "fields": values, "next": q}


## One field value: a scalar, an Array for multi-value fields, a String for strings; null when
## every element holds the base type's invalid value.
static func _read_value(
	bytes: PackedByteArray, at: int, size: int, base: int, big: bool
) -> Variant:
	var bt: Array = BASE_TYPES[base]
	var bsize := int(bt[1])
	if str(bt[0]) == "string":
		var raw := bytes.slice(at, at + size)
		var end := raw.find(0)
		if end >= 0:
			raw = raw.slice(0, end)
		if raw.is_empty():
			return null
		return raw.get_string_from_utf8()
	var count := size / bsize
	var vals: Array = []
	var any_valid := false
	for i in count:
		var v: Variant = _read_scalar(bytes, at + i * bsize, base, big)
		if v != null:
			any_valid = true
		vals.append(v)
	if not any_valid:
		return null
	if count == 1:
		return vals[0]
	return vals


static func _read_scalar(bytes: PackedByteArray, at: int, base: int, big: bool) -> Variant:
	var bt: Array = BASE_TYPES[base]
	var name := str(bt[0])
	var size := int(bt[1])
	var invalid := int(bt[2])
	match name:
		"float32":
			var raw32 := _read_uint(bytes, at, 4, big)
			if raw32 == 0xFFFFFFFF:
				return null
			var tmp := PackedByteArray()
			tmp.resize(4)
			tmp.encode_u32(0, raw32)
			return tmp.decode_float(0)
		"float64":
			var tmp8 := bytes.slice(at, at + 8)
			if big:
				tmp8.reverse()
			if tmp8.count(0xFF) == 8:
				return null
			return tmp8.decode_double(0)
	var u := _read_uint(bytes, at, size, big)
	if name.begins_with("uint64") or name == "sint64":
		if (name == "uint64" and u == -1) or u == invalid:
			return null
		return u
	if u == invalid:
		return null
	if name.begins_with("sint"):
		var bits := size * 8
		if u >= (1 << (bits - 1)):
			u -= (1 << bits)
	return u


static func _read_uint(bytes: PackedByteArray, at: int, size: int, big: bool) -> int:
	var v := 0
	for i in size:
		var b := bytes[at + i]
		if big:
			v = (v << 8) | b
		else:
			v |= b << (8 * i)
	return v


# ---------------------------------------------------------------------------------------------
# Summary


static func _empty_summary(path: String) -> Dictionary:
	return {
		"path": path,
		"ok": false,
		"errors": [],
		"decode_errors": [],
		"warnings": [],
		"is_fit": false,
		"integrity": false,
		"header": {},
		"crc_ok": false,
		"segments": 0,
		"messages": {},
		"file_id": {},
		"records": 0,
		"record_span_s": 0.0,
		"record_gaps": 0,
		"record_timestamps_monotonic": true,
		"has_gps": false,
		"first_record_ts": -1,
		"last_record_ts": -1,
		"laps": [],
		"session": {},
		"sessions": 0,
		"activity": {},
		"activity_count": 0,
		"events": 0,
		"timer_starts": 0,
		"timer_stops": 0,
		"device_infos": 0,
	}


static func _summarize(s: Dictionary, messages: Array[Dictionary], opts: Dictionary) -> void:
	var counts: Dictionary = {}
	var records: Array[Dictionary] = []
	var laps: Array[Dictionary] = []
	var sessions: Array[Dictionary] = []
	var activities: Array[Dictionary] = []
	## "dev_<developer index>_<field number>" -> field name, from field_description messages.
	var dev_names: Dictionary = {}
	for m in messages:
		var num := int(m["num"])
		var name: String = MESG_NAMES.get(num, "mesg_%d" % num)
		counts[name] = int(counts.get(name, 0)) + 1
		var f: Dictionary = m["fields"]
		match num:
			MESG_RECORD:
				records.append(f)
			MESG_LAP:
				laps.append(f)
			MESG_SESSION:
				sessions.append(f)
			MESG_ACTIVITY:
				activities.append(f)
			MESG_EVENT:
				s["events"] = int(s["events"]) + 1
				# Like the FIT SDK model check.mjs uses: every timer event that isn't a start
				# (stop, stop_all, stop_disable, ...) counts as a stop.
				if int(f.get(0, -1)) == EVENT_TIMER and f.has(1):
					if int(f[1]) == EVENT_TYPE_START:
						s["timer_starts"] = int(s["timer_starts"]) + 1
					else:
						s["timer_stops"] = int(s["timer_stops"]) + 1
			MESG_DEVICE_INFO:
				s["device_infos"] = int(s["device_infos"]) + 1
			MESG_FIELD_DESCRIPTION:
				# developer_data_index (0), field_definition_number (1), field_name (3).
				var fname: Variant = f.get(3, null)
				if f.has(0) and f.has(1) and fname != null:
					var label := str((fname as Array)[0]) if fname is Array else str(fname)
					dev_names["dev_%d_%d" % [int(f[0]), int(f[1])]] = label
	var lap_name_key := ""
	for k: Variant in dev_names.keys():
		if str(dev_names[k]) == LAP_NAME_FIELD:
			lap_name_key = str(k)
			break
	s["messages"] = counts
	if not (s["errors"] as Array).is_empty() and messages.is_empty():
		return

	# file_id: present and first.
	if messages.is_empty() or int(messages[0]["num"]) != MESG_FILE_ID:
		_err(s, "the first message is not file_id")
	for m in messages:
		if int(m["num"]) == MESG_FILE_ID:
			var fid: Dictionary = m["fields"]
			s["file_id"] = {
				"type": fid.get(0, null),
				"manufacturer": fid.get(1, null),
				"product": fid.get(2, null),
				"serial_number": fid.get(3, null),
				"time_created": fid.get(4, null),
			}
			if int(fid.get(0, -1)) != FILE_TYPE_ACTIVITY:
				_err(
					s,
					(
						"file_id.type is %s, expected %d (activity)"
						% [str(fid.get(0, "missing")), FILE_TYPE_ACTIVITY]
					)
				)
			break

	# Records: count, span, monotonic timestamps, gaps.
	s["records"] = records.size()
	if records.is_empty():
		_err(s, "no record messages")
	else:
		var prev := -1
		var first := -1
		var last := -1
		var backwards := 0
		var gaps := 0
		var missing_ts := 0
		for r in records:
			if r.has(0) or r.has(1):
				s["has_gps"] = true
			if not r.has(FIELD_TIMESTAMP):
				missing_ts += 1
				continue
			var ts := int(r[FIELD_TIMESTAMP])
			if first < 0:
				first = ts
			if prev >= 0:
				if ts < prev:
					backwards += 1
				elif ts - prev > 1:
					gaps += 1
			prev = ts
			last = maxi(last, ts)
		if missing_ts > 0:
			_err(s, "%d record(s) without a timestamp" % missing_ts)
		if backwards > 0:
			_err(s, "record timestamps go backwards %d time(s)" % backwards)
		s["record_timestamps_monotonic"] = backwards == 0 and missing_ts == 0
		s["first_record_ts"] = first
		s["last_record_ts"] = last
		s["record_span_s"] = float(last - first) if first >= 0 else 0.0
		s["record_gaps"] = gaps

	# Session.
	s["sessions"] = sessions.size()
	var ses_start := -1
	if sessions.is_empty():
		_err(s, "no session message")
	else:
		if sessions.size() > 1:
			_err(s, "%d session messages, expected 1" % sessions.size())
		var sf: Dictionary = sessions[0]
		ses_start = int(sf.get(2, -1))
		var ses := {
			"start_time": sf.get(2, null),
			"timestamp": sf.get(FIELD_TIMESTAMP, null),
			"sport": sf.get(5, null),
			"sub_sport": sf.get(6, null),
			"elapsed_s": _scaled(sf, 7, 1000.0),
			"timer_s": _scaled(sf, 8, 1000.0),
			"distance_m": _scaled(sf, 9, 100.0),
			"work_kj": _scaled(sf, 48, 1000.0),
			"avg_power_w": _scaled(sf, 20, 1.0),
			"max_power_w": _scaled(sf, 21, 1.0),
			"avg_cadence_rpm": _scaled(sf, 18, 1.0),
			"max_cadence_rpm": _scaled(sf, 19, 1.0),
			"avg_heart_rate_bpm": _opt_value(sf, 16),
			"max_heart_rate_bpm": _opt_value(sf, 17),
			"avg_speed_mps": _scaled(sf, 14, 1000.0),
			"max_speed_mps": _scaled(sf, 15, 1000.0),
			"normalized_power_w": _scaled(sf, 34, 1.0),
			"num_laps": sf.get(26, null),
			"first_lap_index": sf.get(25, null),
		}
		s["session"] = ses
		if int(sf.get(5, -1)) != SPORT_CYCLING:
			_err(
				s,
				(
					"session.sport is %s, expected %d (cycling)"
					% [str(sf.get(5, "missing")), SPORT_CYCLING]
				)
			)
		if int(sf.get(6, -1)) != SUB_SPORT_VIRTUAL_ACTIVITY:
			_err(
				s,
				(
					"session.sub_sport is %s, expected %d (virtual_activity)"
					% [str(sf.get(6, "missing")), SUB_SPORT_VIRTUAL_ACTIVITY]
				)
			)
		if not sf.has(7):
			_err(s, "session has no total_elapsed_time")
		if sf.has(26) and int(sf[26]) != laps.size():
			_err(
				s,
				"session.num_laps is %d but the file holds %d lap(s)" % [int(sf[26]), laps.size()]
			)

	# Laps.
	var origin := ses_start
	if origin < 0:
		origin = int(s["first_record_ts"])
	if origin < 0 and not laps.is_empty():
		origin = int(laps[0].get(2, -1))
	var lap_out: Array = []
	var i := 0
	for lf in laps:
		var lst := int(lf.get(2, -1))
		(
			lap_out
			. append(
				{
					"index": i,
					"name": _dev_string(lf, lap_name_key) if lap_name_key != "" else "",
					"start_time": lf.get(2, null),
					"start_s": float(lst - origin) if lst >= 0 and origin >= 0 else 0.0,
					"duration_s": _scaled(lf, 7, 1000.0),
					"timer_s": _scaled(lf, 8, 1000.0),
					"distance_m": _scaled(lf, 9, 100.0),
					"work_kj": _scaled(lf, 41, 1000.0),
					"avg_power_w": _scaled(lf, 19, 1.0),
					"max_power_w": _scaled(lf, 20, 1.0),
					"avg_cadence_rpm": _scaled(lf, 17, 1.0),
					"max_cadence_rpm": _scaled(lf, 18, 1.0),
				}
			)
		)
		if not lf.has(2):
			_err(s, "lap %d has no start_time" % (i + 1))
		if not lf.has(7):
			_err(s, "lap %d has no total_elapsed_time" % (i + 1))
		i += 1
	s["laps"] = lap_out
	if laps.is_empty():
		_err(s, "no lap messages")
	var expect := int(opts.get("expect_laps", -1))
	if expect >= 0 and laps.size() != expect:
		_err(s, "expected %d lap(s), found %d" % [expect, laps.size()])

	# Activity.
	s["activity_count"] = activities.size()
	if activities.is_empty():
		_err(s, "no activity message")
	else:
		var af: Dictionary = activities[0]
		s["activity"] = {
			"timestamp": af.get(FIELD_TIMESTAMP, null),
			"timer_s": _scaled(af, 0, 1000.0),
			"num_sessions": af.get(1, null),
			"type": af.get(2, null),
			"event": af.get(3, null),
			"event_type": af.get(4, null),
		}
		if af.has(1) and int(af[1]) != sessions.size():
			_err(
				s,
				(
					"activity.num_sessions is %d but the file holds %d session(s)"
					% [int(af[1]), sessions.size()]
				)
			)

	# Messages the rides encoder writes that only rate a warning when missing.
	if int(s["device_infos"]) == 0:
		_warn(s, "no device_info message")
	if int(s["timer_starts"]) == 0:
		_warn(s, "no timer start event")


## One file in the JSON tools/fit_check/check.mjs reads from the fallback (tools/fit_check/README.md):
## physical values, enum numbers, times in Unix seconds, and "errors" holding decode errors only
## (check.mjs applies the Wattlands checks itself).
static func rides_contract(s: Dictionary) -> Dictionary:
	var laps: Array = []
	for lap: Variant in s["laps"]:
		var l: Dictionary = lap
		(
			laps
			. append(
				{
					"start_time": _unix_or_null(l.get("start_time", null)),
					"total_elapsed_time": l["duration_s"],
					"total_timer_time": l["timer_s"],
					"total_distance": l["distance_m"],
					"total_work": float(l["work_kj"]) * 1000.0,
					"avg_power": l["avg_power_w"],
					"name": l.get("name", ""),
				}
			)
		)
	var fid: Dictionary = s["file_id"]
	var out := {
		"path": s.get("input", s["path"]),
		"is_fit": s["is_fit"],
		"integrity": s["integrity"],
		"errors": (s["decode_errors"] as Array).duplicate(),
		"file_id": {"type": fid.get("type", null), "manufacturer": fid.get("manufacturer", null)},
		"records": s["records"],
		"record_timestamps_monotonic": s["record_timestamps_monotonic"],
		"has_gps": s["has_gps"],
		"laps": laps,
		"session_count": s["sessions"],
		"activity_count": s["activity_count"],
		"session": null,
		"timer_events": {"start": s["timer_starts"], "stop": s["timer_stops"]},
	}
	var ses: Dictionary = s["session"]
	if not ses.is_empty():
		out["session"] = {
			"sport": ses["sport"],
			"sub_sport": ses["sub_sport"],
			"start_time": _unix_or_null(ses.get("start_time", null)),
			"total_elapsed_time": ses["elapsed_s"],
			"total_timer_time": ses["timer_s"],
			"total_distance": ses["distance_m"],
			"total_work": float(ses["work_kj"]) * 1000.0,
			"avg_power": ses["avg_power_w"],
			"max_power": ses["max_power_w"],
			"avg_cadence": ses["avg_cadence_rpm"],
			"max_cadence": ses["max_cadence_rpm"],
			"avg_heart_rate": ses["avg_heart_rate_bpm"],
			"max_heart_rate": ses["max_heart_rate_bpm"],
			"num_laps": ses["num_laps"],
		}
	return out


static func _unix_or_null(fit_ts: Variant) -> Variant:
	if fit_ts == null:
		return null
	return fit_to_unix(int(fit_ts))


## A developer string field (raw bytes) as text, "" when absent.
static func _dev_string(fields: Dictionary, key: String) -> String:
	if not fields.has(key):
		return ""
	var raw: PackedByteArray = fields[key]
	var end := raw.find(0)
	if end >= 0:
		raw = raw.slice(0, end)
	return raw.get_string_from_utf8()


## A field's value, or null when absent or invalid (heart rate: a ride without one).
static func _opt_value(fields: Dictionary, num: int) -> Variant:
	var v: Variant = fields.get(num, null)
	if v is Array:
		v = (v as Array)[0] if not (v as Array).is_empty() else null
	return float(v) if v != null else null


static func _scaled(fields: Dictionary, num: int, scale: float) -> float:
	if not fields.has(num):
		return 0.0
	var v: Variant = fields[num]
	if v is Array:
		v = (v as Array)[0]
	if v == null:
		return 0.0
	return float(v) / scale


static func _collect_fit_files(dir: String, out: Array[String]) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.include_hidden = false
	for f in da.get_files():
		if f.get_extension().to_lower() == "fit":
			out.append(dir.path_join(f))
	for sub in da.get_directories():
		_collect_fit_files(dir.path_join(sub), out)


static func _err(s: Dictionary, msg: String) -> void:
	var errors: Array = s["errors"]
	if errors.size() < MAX_ERRORS:
		errors.append(msg)
	elif errors.size() == MAX_ERRORS:
		errors.append("too many errors, the rest are not listed")


## A structural decode error: listed in "decode_errors" and in "errors".
static func _derr(s: Dictionary, msg: String) -> void:
	var de: Array = s["decode_errors"]
	if de.size() < MAX_ERRORS:
		de.append(msg)
	_err(s, msg)


static func _warn(s: Dictionary, msg: String) -> void:
	var warnings: Array = s["warnings"]
	if warnings.size() < MAX_ERRORS:
		warnings.append(msg)


static func _num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return "%.3f" % v if absf(v) < 10.0 else "%.1f" % v
