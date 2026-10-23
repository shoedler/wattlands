class_name TankRigs
extends RefCounted
## assets/tank/rigs.json for the view: the cutaway anchors (rooms, machinery, running gear,
## turrets) in the hull frame. The gameplay keys (muzzles, trunnions, boxes) are the rules' contract
## and are read through TankGeometry; the view reads the same file for its own anchors. artqa
## re-measures the values; names and frames stay.

static var _data: Dictionary = {}


## The parsed rigs.json (cached; {} when missing).
static func data() -> Dictionary:
	if _data.is_empty():
		_data = TankGeometry.load_default().data
	return _data


## rigs.json `tanks.<tank>` ({} when unknown).
static func tank_def(tank: String) -> Dictionary:
	return (data().get("tanks", {}) as Dictionary).get(tank, {})


## rigs.json `machinery`.
static func machinery() -> Dictionary:
	return data().get("machinery", {})


## [x, y] as a Vector2 (ZERO for anything else).
static func vec(v: Variant) -> Vector2:
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO


## [x, y, w, h] as a Rect2 (empty for anything else).
static func rect(v: Variant) -> Rect2:
	if v is Array and (v as Array).size() >= 4:
		return Rect2(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
	return Rect2()
