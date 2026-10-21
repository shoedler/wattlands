class_name Protocol
extends RefCounted
## Message encoding, decoding and validation (BRIEF 5.5) with the NetMessages tables.
## Owned by net-client; public API frozen after W0.
## decode() converts peer, host, from, to, seq, proto, max, every "*_id" key and the
## schema's int fields to int (Godot's JSON parser returns every number as a float),
## converts peer-keyed dictionaries' keys to int, and rejects (returns {} and push_warning)
## any message that fails its schema or has another schema version. Round trips through
## JSON.stringify and JSON.parse_string are exact for every message type.
##
## Conversion rules (docs/PROTOCOL.md "Int conversion"):
## - The keys in TOP_INT_KEYS, at the top level of the relay envelope and of the game
##   message, become ints when they hold a whole number.
## - Every Dictionary key ending in "_id", at any depth, holding a whole number becomes an
##   int, except inside telemetry intents (games cast intents themselves, OWNERSHIP PR4).
## - The schema's int paths (NetMessages "ints") and a game's int_fields() paths become
##   ints (rounded); "[]" walks every array element, "{}" every dictionary value; an Array
##   or Dictionary found at a matched path is left unchanged (OWNERSHIP 3.1 C10).
## - Dictionaries stored under a NetMessages.PEER_KEYED field name get int keys (only keys
##   that spell an integer, so option ids stay strings), outside game payloads
##   (snapshot "state", event "events") and telemetry intents.
## - "refused" is accepted whatever its "v", so a peer on another schema version can always
##   read why it was refused.
## - A `hud` message's `args` (an Array or a Dictionary of display values) get whole numbers
##   back as ints.
## - apply_game_int_fields() also converts the platform's own events (PLATFORM_EVENT_INTS).

## Envelope and game-message keys converted at the top level only.
const TOP_INT_KEYS: Array[String] = ["peer", "host", "from", "to", "seq", "proto", "max", "v"]

## Required-field types checked after presence. NUMBER accepts int or float.
const NUMBER := -1
const RELAY_TYPES: Dictionary = {
	"hello": {"proto": NUMBER, "game": TYPE_STRING, "build": TYPE_STRING},
	"create": {"max": NUMBER},
	"created": {"code": TYPE_STRING, "peer": NUMBER, "token": TYPE_STRING},
	"join": {"code": TYPE_STRING},
	"joined": {"peer": NUMBER, "host": NUMBER, "token": TYPE_STRING},
	"error": {"code": TYPE_STRING},
	"msg": {"d": TYPE_DICTIONARY},
	"peer_joined": {"peer": NUMBER},
	"peer_left": {"peer": NUMBER},
	"ping": {"ts": NUMBER},
	"pong": {"ts": NUMBER},
}
const GAME_TYPES: Dictionary = {
	"player_info": {"name": TYPE_STRING, "ftp": NUMBER, "ftp_verified": TYPE_BOOL,
		"p_eff_per_w": NUMBER, "preferred_cadence_rpm": NUMBER, "haptics_on": TYPE_BOOL,
		"autopilot": TYPE_BOOL, "player_options": TYPE_DICTIONARY, "games": TYPE_DICTIONARY},
	"ready": {"ready": TYPE_BOOL},
	"telemetry": {"tm": TYPE_DICTIONARY},
	"clock_ping": {"t0": NUMBER},
	"lobby_state": {"players": TYPE_ARRAY, "game_id": TYPE_STRING, "content_id": TYPE_STRING,
		"scaling": TYPE_STRING, "settings": TYPE_DICTIONARY},
	"session_start": {"game_id": TYPE_STRING, "content_id": TYPE_STRING, "seed": NUMBER,
		"players": TYPE_ARRAY, "options": TYPE_DICTIONARY, "scaling": TYPE_STRING,
		"start_tick": NUMBER},
	"snapshot": {"game_id": TYPE_STRING, "seq": NUMBER, "state": TYPE_DICTIONARY},
	"event": {"seq": NUMBER, "events": TYPE_ARRAY},
	"roster": {"riders": TYPE_DICTIONARY},
	"results": {"results": TYPE_DICTIONARY},
	"session_end": {"reason": TYPE_STRING},
	"refused": {"reason": TYPE_STRING},
	"plan": {"plan": TYPE_DICTIONARY},
	"phase": {"index": NUMBER, "start_tick": NUMBER, "ended_by": TYPE_STRING},
	"directive": {"kind": TYPE_STRING},
	"hud": {"kind": TYPE_STRING, "key": TYPE_STRING},
	"clock_pong": {"t0": NUMBER, "th": NUMBER},
}

## Int paths of net-client's own fields beyond the NetMessages contract (requested there
## as an additive change): lobby settings that are whole numbers.
const EXTRA_INTS: Dictionary = {
	"lobby_state": ["settings.bot_ftp", "settings.max_players", "settings.min_players"],
}

## Int paths of the platform's own events inside `event` batches (the GameHost's
## phase_started), applied by apply_game_int_fields() whatever the game declares.
const PLATFORM_EVENT_INTS: Dictionary = {
	"phase_started": ["peer", "index", "tick", "start_tick"],
}

## Game payloads where peer-keyed key conversion does not apply.
const GAME_PAYLOAD_FIELDS: Dictionary = {"snapshot": "state", "event": "events"}

const _HINT_ID := 1
const _HINT_PEER_KEYED := 2
const _HINT_ALL := 3
const _MAX_SAFE_INT := 9007199254740992.0

## Why the latest decode()/decode_game() call returned {} ("" after a success):
## "bad_json", "not_object", "unknown_type", "version_mismatch", "missing_field:<f>",
## "bad_type:<f>", "bad_kind".
static var last_error: String = ""


## Relay envelope + game message -> JSON text. Keeps insertion order and writes floats at
## full precision (Godot's default 14 digits loses information).
static func encode(msg: Dictionary) -> String:
	return JSON.stringify(msg, "", false, true)


## JSON text -> validated, int-converted message, or {} if invalid.
## Accepts a relay envelope ("t") or a bare game message ("type").
static func decode(text: String) -> Dictionary:
	var parsed: Variant = parse_json(text)
	if parsed == null:
		return _reject("bad_json", "Protocol: not valid JSON (%d bytes)" % text.length())
	if not parsed is Dictionary:
		return _reject("not_object", "Protocol: a message must be a JSON object")
	var msg: Dictionary = parsed
	var hints := _hints_for(text)
	# A game message always has "type" (and may have its own "t", e.g. snapshot time);
	# a relay envelope has "t" and never "type".
	if msg.has("type"):
		if _decode_game_in_place(msg, hints):
			return msg
		return {}
	if msg.has("t"):
		return _decode_envelope(msg, hints)
	return _reject("unknown_type", "Protocol: message has neither \"t\" nor \"type\"")


## A game message ("type" + "v" + payload) ready for Transport.send.
static func game_msg(type: String, payload: Dictionary = {}) -> Dictionary:
	var d := payload.duplicate(true)
	d["type"] = type
	d["v"] = NetMessages.VERSION
	return d


## Validate and int-convert a game message Dictionary already parsed from JSON.
## Returns {} (and push_warning) if invalid. The argument itself is not modified.
static func decode_game(data: Dictionary) -> Dictionary:
	var d: Dictionary = data.duplicate(true)
	if _decode_game_in_place(d, _HINT_ALL):
		return d
	return {}


## Convert the given dotted paths (with "[]" and "{}" wildcards) to int in place and
## return `data`. Used for games' int_fields() on snapshots and events.
static func apply_int_fields(data: Variant, paths: Array) -> Variant:
	var out: Variant = data
	for p: Variant in paths:
		var tokens := _path_tokens(str(p))
		if tokens.is_empty():
			continue
		out = _apply_tokens(out, tokens, 0)
	return out


# --- additions (public) ------------------------------------------------------------------

## JSON text -> Variant without logging engine errors (JSON.parse_string logs one on bad
## input, which fails GUT tests); null when the text is not valid JSON.
static func parse_json(text: String) -> Variant:
	var j := JSON.new()
	if j.parse(text) != OK:
		return null
	return j.data


## The UTF-8 byte size of `msg` once encoded (the relay's 16 KB limit counts these bytes).
static func encoded_size(msg: Dictionary) -> int:
	return encode(msg).to_utf8_buffer().size()


## Validate a relay envelope's required fields and types (no conversion). "" when valid,
## else the reason (as in last_error).
static func check_envelope(msg: Dictionary) -> String:
	var t: Variant = msg.get("t")
	if not t is String or not NetMessages.RELAY.has(t):
		return "unknown_type"
	return _check_fields(msg, NetMessages.RELAY[t]["req"], RELAY_TYPES.get(t, {}))


## Validate a game message's type, version and required fields (no conversion). "" when
## valid, else the reason (as in last_error).
static func check_game(d: Dictionary) -> String:
	var type: Variant = d.get("type")
	if not type is String or not NetMessages.GAME.has(type):
		return "unknown_type"
	if type != "refused":
		var v: Variant = d.get("v")
		if not _is_number(v) or float(v) != float(NetMessages.VERSION):
			return "version_mismatch"
	var err := _check_fields(d, NetMessages.GAME[type]["req"], GAME_TYPES.get(type, {}))
	if err != "":
		return err
	if type == "directive" and not NetMessages.DIRECTIVE_KINDS.has(str(d["kind"])):
		return "bad_kind"
	return ""


## The schema int paths of a game message type from NetMessages (empty if unknown).
static func schema_int_paths(type: String) -> Array:
	if not NetMessages.GAME.has(type):
		return []
	return NetMessages.GAME[type]["ints"]


## Apply a game's int_fields() to a decoded snapshot or event message in place: the
## snapshot's "state" gets fields["snapshot"]; each event in "events" gets
## fields[event.type], and the platform's own events (PLATFORM_EVENT_INTS) their paths.
## Returns `msg`.
static func apply_game_int_fields(msg: Dictionary, fields: Dictionary) -> Dictionary:
	var type := str(msg.get("type", ""))
	if type == "snapshot" and fields.has("snapshot") and msg.get("state") is Dictionary:
		msg["state"] = apply_int_fields(msg["state"], fields["snapshot"])
	elif type == "event" and msg.get("events") is Array:
		var events: Array = msg["events"]
		for i in events.size():
			var e: Variant = events[i]
			if e is Dictionary:
				var et := str((e as Dictionary).get("type", ""))
				if et == "" or et == "snapshot":
					continue
				if PLATFORM_EVENT_INTS.has(et):
					e = apply_int_fields(e, PLATFORM_EVENT_INTS[et])
				if fields.has(et):
					e = apply_int_fields(e, fields[et])
				events[i] = e
	return msg


# --- internals ---------------------------------------------------------------------------

static func _decode_envelope(msg: Dictionary, hints: int) -> Dictionary:
	var err := check_envelope(msg)
	if err != "":
		return _reject(err, "Protocol: relay message \"%s\" rejected (%s)" % [str(msg.get("t", "")), err])
	_convert_top(msg)
	if msg["t"] == "msg":
		var d: Dictionary = msg["d"]
		if not _decode_game_in_place(d, hints):
			return {}
	last_error = ""
	return msg


static func _decode_game_in_place(d: Dictionary, hints: int) -> bool:
	var err := check_game(d)
	if err != "":
		_reject(err, "Protocol: game message \"%s\" rejected (%s)" % [str(d.get("type", "")), err])
		return false
	var type: String = d["type"]
	_convert_top(d)
	# Telemetry intents are never converted: take them out while walking.
	var intents: Variant = null
	var tm: Variant = d.get("tm")
	if type == "telemetry" and tm is Dictionary and (tm as Dictionary).has("intents"):
		intents = (tm as Dictionary)["intents"]
		(tm as Dictionary).erase("intents")
	if hints != 0:
		var payload_field: String = GAME_PAYLOAD_FIELDS.get(type, "")
		for k: Variant in d.keys():
			var child: Variant = d[k]
			if child is Dictionary or child is Array:
				var in_payload: bool = k == payload_field
				# Inside a game payload only the "_id" rule applies.
				if in_payload and (hints & _HINT_ID) == 0:
					continue
				d[k] = _walk(child, str(k), hints, not in_payload)
			elif (hints & _HINT_ID) != 0 and k is String and (k as String).ends_with("_id"):
				d[k] = _whole_to_int(child)
	if intents != null:
		(tm as Dictionary)["intents"] = intents
	apply_int_fields(d, NetMessages.GAME[type]["ints"])
	if EXTRA_INTS.has(type):
		apply_int_fields(d, EXTRA_INTS[type])
	if type == "hud":
		_whole_args_to_int(d.get("args"))
	last_error = ""
	return true


## A toast's or banner's `args` ({0} or {name} values) are display values: whole numbers
## come back as ints, so a client draws "2" where the host drew 2, not "2.0".
static func _whole_args_to_int(args: Variant) -> void:
	if args is Array:
		var arr: Array = args
		for i in arr.size():
			arr[i] = _whole_to_int(arr[i])
	elif args is Dictionary:
		var dict: Dictionary = args
		for k: Variant in dict.keys():
			dict[k] = _whole_to_int(dict[k])


## Generic conversions below the top level: "_id" keys and peer-keyed dictionaries.
static func _walk(node: Variant, key_name: String, hints: int, allow_peer: bool) -> Variant:
	if node is Array:
		var arr: Array = node
		for i in arr.size():
			var e: Variant = arr[i]
			if e is Dictionary or e is Array:
				arr[i] = _walk(e, "", hints, allow_peer)
		return arr
	if node is Dictionary:
		var dict: Dictionary = node
		var rekey := allow_peer and (hints & _HINT_PEER_KEYED) != 0 \
			and NetMessages.PEER_KEYED.has(key_name) and _has_int_like_key(dict)
		var out: Dictionary = {} if rekey else dict
		for k: Variant in dict.keys():
			var v: Variant = dict[k]
			if v is Dictionary or v is Array:
				v = _walk(v, str(k), hints, allow_peer)
			elif (hints & _HINT_ID) != 0 and k is String and (k as String).ends_with("_id"):
				v = _whole_to_int(v)
			if rekey:
				var nk: Variant = k
				if k is String and (k as String).is_valid_int():
					nk = (k as String).to_int()
				out[nk] = v
			else:
				dict[k] = v
		return out
	return node


static func _has_int_like_key(dict: Dictionary) -> bool:
	for k: Variant in dict.keys():
		if k is String and (k as String).is_valid_int():
			return true
	return false


static func _convert_top(d: Dictionary) -> void:
	for k in TOP_INT_KEYS:
		if d.has(k):
			d[k] = _whole_to_int(d[k])


static func _check_fields(d: Dictionary, req: Array, types: Dictionary) -> String:
	for f: Variant in req:
		if not d.has(f):
			return "missing_field:%s" % f
		if types.has(f):
			var want: int = types[f]
			var v: Variant = d[f]
			if want == NUMBER:
				if not _is_number(v):
					return "bad_type:%s" % f
			elif typeof(v) != want:
				return "bad_type:%s" % f
	return ""


static func _is_number(v: Variant) -> bool:
	return v is int or v is float


## A float holding a whole number becomes an int; anything else is returned unchanged.
static func _whole_to_int(v: Variant) -> Variant:
	if v is float:
		var f: float = v
		if is_finite(f) and f == floorf(f) and absf(f) <= _MAX_SAFE_INT:
			return int(f)
	return v


## A declared int field: numbers are rounded to int; other values are left alone.
static func _declared_to_int(v: Variant) -> Variant:
	if v is float:
		var f: float = v
		if is_finite(f) and absf(f) <= _MAX_SAFE_INT:
			return roundi(f)
	return v


static func _path_tokens(path: String) -> Array[String]:
	var tokens: Array[String] = []
	for seg in path.split(".", false):
		var name_end := seg.length()
		var a := seg.find("[]")
		var b := seg.find("{}")
		if a >= 0:
			name_end = mini(name_end, a)
		if b >= 0:
			name_end = mini(name_end, b)
		var name := seg.substr(0, name_end)
		if name != "":
			tokens.append(name)
		var rest := seg.substr(name_end)
		while rest.length() >= 2:
			var w := rest.substr(0, 2)
			if w != "[]" and w != "{}":
				break
			tokens.append(w)
			rest = rest.substr(2)
	return tokens


static func _apply_tokens(node: Variant, tokens: Array[String], i: int) -> Variant:
	var n := tokens.size()
	if i >= n:
		return _declared_to_int(node)
	var tok := tokens[i]
	var last := i == n - 1
	if tok == "[]":
		if node is Array:
			var arr: Array = node
			if last:
				# Hot path (compact int arrays in snapshots): convert in place, no calls.
				for j in arr.size():
					var v: Variant = arr[j]
					if typeof(v) == TYPE_FLOAT:
						var f: float = v
						if is_finite(f) and absf(f) <= _MAX_SAFE_INT:
							arr[j] = roundi(f)
			else:
				for j in arr.size():
					var e: Variant = arr[j]
					if typeof(e) == TYPE_ARRAY or typeof(e) == TYPE_DICTIONARY:
						_apply_tokens(e, tokens, i + 1)
		return node
	if tok == "{}":
		if node is Dictionary:
			var dict: Dictionary = node
			for k: Variant in dict.keys():
				if last:
					dict[k] = _declared_to_int(dict[k])
				else:
					var e: Variant = dict[k]
					if typeof(e) == TYPE_ARRAY or typeof(e) == TYPE_DICTIONARY:
						_apply_tokens(e, tokens, i + 1)
		return node
	if node is Dictionary:
		var dict: Dictionary = node
		if dict.has(tok):
			if last:
				dict[tok] = _declared_to_int(dict[tok])
			else:
				var e: Variant = dict[tok]
				if typeof(e) == TYPE_ARRAY or typeof(e) == TYPE_DICTIONARY:
					_apply_tokens(e, tokens, i + 1)
	return node


## Cheap text scans that let decode() skip walks that cannot change anything.
static func _hints_for(text: String) -> int:
	var h := 0
	if _has_numeric_id(text):
		h |= _HINT_ID
	for k in NetMessages.PEER_KEYED:
		if text.contains("\"" + k + "\""):
			h |= _HINT_PEER_KEYED
			break
	return h


## True if some key ending in "_id" holds a number (`_id"`, a colon, then a digit or "-",
## with any JSON whitespace between), so a message whose only *_id keys hold strings
## (game_id, content_id) skips the walk.
static func _has_numeric_id(text: String) -> bool:
	var n := text.length()
	var from := 0
	while true:
		var at := text.find("_id\"", from)
		if at < 0:
			return false
		from = at + 4
		var k := _skip_ws(text, from, n)
		if k >= n or text.unicode_at(k) != 58:  # ':'
			continue
		k = _skip_ws(text, k + 1, n)
		if k < n:
			var c := text.unicode_at(k)
			if (c >= 48 and c <= 57) or c == 45:
				return true
	return false


## The first index at or after `k` that is not JSON whitespace (space, tab, LF, CR).
static func _skip_ws(text: String, k: int, n: int) -> int:
	while k < n:
		var c := text.unicode_at(k)
		if c != 32 and c != 9 and c != 10 and c != 13:
			return k
		k += 1
	return k


static func _reject(reason: String, text: String) -> Dictionary:
	last_error = reason
	push_warning(text)
	return {}
