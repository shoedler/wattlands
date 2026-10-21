extends RefCounted
## A small FIT reader for the rides tests (decodes our own FitEncoder output; independent
## of it: it reads the bytes by the FIT protocol, not by the encoder's tables).
## read(bytes) -> {ok, errors: [...], header: {...}, messages: [{global, local, fields:
## {field number: value}, dev: {field number: PackedByteArray}}], definitions: [...]}.
## Strings decode to String (up to the first zero), bytes to PackedByteArray, numbers to int.


static func read(bytes: PackedByteArray) -> Dictionary:
	var out := {"ok": false, "errors": [], "header": {}, "messages": [], "definitions": []}
	var errors: Array = out["errors"]
	if bytes.size() < 14:
		errors.append("too short")
		return out
	var hs := bytes[0]
	var header := {
		"size": hs,
		"protocol": bytes[1],
		"profile": bytes.decode_u16(2),
		"data_size": bytes.decode_u32(4),
		"type": bytes.slice(8, 12).get_string_from_ascii(),
		"crc": bytes.decode_u16(12) if hs == 14 else -1,
	}
	out["header"] = header
	if header["type"] != ".FIT":
		errors.append("bad data type")
	var data_end: int = hs + int(header["data_size"])
	if data_end + 2 != bytes.size():
		errors.append("size mismatch: header says %d data bytes, file has %d" % [header["data_size"], bytes.size() - hs - 2])
		return out
	if hs == 14 and int(header["crc"]) != FitCrc.compute(bytes, 0, 12):
		errors.append("header crc")
	if bytes.decode_u16(data_end) != FitCrc.compute(bytes, 0, data_end):
		errors.append("file crc")
	var defs := {}
	var pos: int = hs
	while pos < data_end:
		var rh := bytes[pos]
		pos += 1
		if rh & 0x80:
			errors.append("compressed timestamp header at %d" % (pos - 1))
			return out
		var local := rh & 0x0F
		if rh & 0x40:
			var dev := (rh & 0x20) != 0
			var arch := bytes[pos + 1]
			var global := bytes.decode_u16(pos + 2) if arch == 0 else (bytes[pos + 2] << 8) | bytes[pos + 3]
			var n := bytes[pos + 4]
			pos += 5
			var fields: Array = []
			for i in n:
				fields.append([bytes[pos], bytes[pos + 1], bytes[pos + 2]])
				pos += 3
			var dev_fields: Array = []
			if dev:
				var nd := bytes[pos]
				pos += 1
				for i in nd:
					dev_fields.append([bytes[pos], bytes[pos + 1], bytes[pos + 2]])
					pos += 3
			var d := {"global": global, "local": local, "fields": fields, "dev_fields": dev_fields, "arch": arch}
			defs[local] = d
			(out["definitions"] as Array).append(d)
		else:
			if not defs.has(local):
				errors.append("data for undefined local type %d" % local)
				return out
			var d: Dictionary = defs[local]
			var m := {"global": d["global"], "local": local, "fields": {}, "dev": {}}
			for f: Array in d["fields"]:
				(m["fields"] as Dictionary)[int(f[0])] = _value(bytes, pos, int(f[1]), int(f[2]))
				pos += int(f[1])
			for f: Array in d["dev_fields"]:
				(m["dev"] as Dictionary)[int(f[0])] = bytes.slice(pos, pos + int(f[1]))
				pos += int(f[1])
			(out["messages"] as Array).append(m)
	if pos != data_end:
		errors.append("ran past the data")
	out["ok"] = errors.is_empty()
	return out


static func _value(bytes: PackedByteArray, pos: int, size: int, base_type: int) -> Variant:
	match base_type:
		0x00, 0x02, 0x0A:
			return bytes[pos]
		0x84, 0x8B:
			return bytes.decode_u16(pos)
		0x86, 0x8C:
			return bytes.decode_u32(pos)
		0x07:
			var raw := bytes.slice(pos, pos + size)
			var z := raw.find(0)
			if z >= 0:
				raw = raw.slice(0, z)
			return raw.get_string_from_utf8()
		_:
			return bytes.slice(pos, pos + size)


## Messages with global number `global`.
static func of(decoded: Dictionary, global: int) -> Array:
	var out: Array = []
	for m: Dictionary in decoded["messages"]:
		if int(m["global"]) == global:
			out.append(m)
	return out


## A developer string field as text.
static func dev_string(raw: PackedByteArray) -> String:
	var z := raw.find(0)
	return (raw.slice(0, z) if z >= 0 else raw).get_string_from_utf8()
