class_name Protocol
extends RefCounted
## Message encoding, decoding and validation (BRIEF 5.5) with the NetMessages tables.
## Owned by net-client; public API frozen after W0.
## decode() converts peer, host, from, to, seq, proto, max, every "*_id" key and the
## schema's int fields to int (Godot's JSON parser returns every number as a float),
## converts peer-keyed dictionaries' keys to int, and rejects (returns {} and push_warning)
## any message that fails its schema or has another schema version. Round trips through
## JSON.stringify and JSON.parse_string are exact for every message type.


## Relay envelope + game message -> JSON text.
static func encode(_msg: Dictionary) -> String:
	return ""


## JSON text -> validated, int-converted message, or {} if invalid.
static func decode(_text: String) -> Dictionary:
	return {}


## A game message ("type" + "v" + payload) ready for Transport.send.
static func game_msg(type: String, payload: Dictionary = {}) -> Dictionary:
	var d := payload.duplicate(true)
	d["type"] = type
	d["v"] = NetMessages.VERSION
	return d


## Validate and int-convert a game message Dictionary already parsed from JSON.
## Returns {} (and push_warning) if invalid.
static func decode_game(_data: Dictionary) -> Dictionary:
	return {}


## Convert the given dotted paths (with "[]" and "{}" wildcards) to int in place and
## return `data`. Used for games' int_fields() on snapshots and events.
static func apply_int_fields(data: Variant, _paths: Array) -> Variant:
	return data
