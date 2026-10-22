class_name SiegeTune
extends RefCounted
## Reads tuning numbers that live in content/siege/waves.json by dotted path, with a default
## (balance.json numbers go through SiegeContent.num). Pure; used at wave and group boundaries,
## never per enemy.


## A number at `path` in waves.json ("spawn.spread_m"), or `default`.
static func wave_num(c: SiegeContent, path: String, default: float) -> float:
	var v: Variant = _at(c.waves, path)
	return float(v) if (v is float or v is int) else default


## A [lo, hi] pair at `path` in waves.json as a Vector2, or `default`.
static func wave_pair(c: SiegeContent, path: String, default: Vector2) -> Vector2:
	var v: Variant = _at(c.waves, path)
	if v is Array and (v as Array).size() == 2:
		var a: Variant = v[0]
		var b: Variant = v[1]
		if (a is float or a is int) and (b is float or b is int):
			return Vector2(float(a), float(b))
	return default


static func _at(d: Dictionary, path: String) -> Variant:
	var v: Variant = d
	for k in path.split("."):
		if not (v is Dictionary) or not (v as Dictionary).has(k):
			return null
		v = v[k]
	return v
