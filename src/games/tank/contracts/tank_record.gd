class_name TankRecord
extends RefCounted
## Base of Tank's plain-data state types (G0 contract, the SiegeRecord pattern): to_dict() /
## load_dict() over every script variable of a JSON-friendly type (bool, int, float, String,
## Vector2 as [x, y], typed Arrays of those). Fixtures and debugging use it; the 10 Hz snapshot is
## TankSnapshot's compact integer form, not this. Variables whose name starts with "_" and
## Object-typed ones are skipped (a subclass handles nested records itself).


func to_dict() -> Dictionary:
	var out := {}
	for p: Dictionary in get_property_list():
		if not _saved(p):
			continue
		var v: Variant = get(p["name"])
		match typeof(v):
			TYPE_VECTOR2:
				out[p["name"]] = [v.x, v.y]
			TYPE_ARRAY:
				out[p["name"]] = (v as Array).duplicate()
			_:
				out[p["name"]] = v
	return out


## Fills the saved variables from `d` (missing keys keep their value), casting JSON numbers to
## each variable's type and typed-array elements to the array's element type.
func load_dict(d: Dictionary) -> TankRecord:
	for p: Dictionary in get_property_list():
		if not _saved(p) or not d.has(p["name"]):
			continue
		var v: Variant = d[p["name"]]
		match int(p["type"]):
			TYPE_INT:
				set(p["name"], int(v))
			TYPE_FLOAT:
				set(p["name"], float(v))
			TYPE_BOOL:
				set(p["name"], bool(v))
			TYPE_STRING:
				set(p["name"], str(v))
			TYPE_VECTOR2:
				set(p["name"], Vector2(float(v[0]), float(v[1])) if v is Array else Vector2.ZERO)
			TYPE_ARRAY:
				_load_array(get(p["name"]), v)
	return self


func _load_array(arr: Array, v: Variant) -> void:
	arr.clear()
	for x: Variant in v if v is Array else []:
		match arr.get_typed_builtin():
			TYPE_INT:
				arr.append(int(x))
			TYPE_FLOAT:
				arr.append(float(x))
			TYPE_STRING:
				arr.append(str(x))
			TYPE_BOOL:
				arr.append(bool(x))
			_:
				arr.append(x)


func _saved(p: Dictionary) -> bool:
	if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
		return false
	if str(p["name"]).begins_with("_"):
		return false
	var t := int(p["type"])
	if t == TYPE_ARRAY:
		var arr: Variant = get(p["name"])
		return arr is Array and (arr as Array).get_typed_builtin() != TYPE_OBJECT
	return t in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_VECTOR2]
