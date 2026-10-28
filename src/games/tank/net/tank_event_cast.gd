class_name TankEventCast
extends RefCounted
## Casts an event's numbers to int (GAME_SDK 12): Protocol.decode() already does it for the paths
## int_fields() declares, and apply_event() casts again so an event that reaches the game by another
## road (a test, a replay) is just as clean. The declared fields are TankEvents.INT_FIELDS; a path
## ending in "[]" casts every number of a (nested) array (the reserved rotation event's "r[][]").


## A copy of `event` with every declared int field cast; unknown keys are kept as they are.
static func cast(event: Dictionary) -> Dictionary:
	var out := event.duplicate(true)
	var type := str(out.get("type", ""))
	for path: String in TankEvents.INT_FIELDS.get(type, []):
		_cast_path(out, path)
	return out


static func _cast_path(node: Dictionary, path: String) -> void:
	var depth := 0
	var key := path
	while key.ends_with("[]"):
		key = key.substr(0, key.length() - 2)
		depth += 1
	if not node.has(key):
		return
	node[key] = _cast_value(node[key], depth)


static func _cast_value(v: Variant, depth: int) -> Variant:
	if depth == 0:
		return int(v) if (v is float or v is int or v is bool) else v
	if not (v is Array):
		return v
	var out: Array = []
	for x: Variant in v:
		out.append(_cast_value(x, depth - 1))
	return out
