class_name AudioCurve
extends RefCounted
## The bank's parameter curves (SPEC_AUDIO 1.2). Pure and static.
## {"param": name, "points": [[x, y], ...]} is piecewise linear and clamped at both ends;
## {"param": name, "ratio": r} is value / r. A missing param reads 0.


static func eval(curve: Dictionary, params: Dictionary) -> float:
	var value := float(params.get(curve.get("param", ""), 0.0))
	if curve.has("ratio"):
		var ratio := float(curve["ratio"])
		return value / ratio if ratio != 0.0 else 0.0
	var points: Array = curve.get("points", [])
	if points.is_empty():
		return 0.0
	var first: Array = points[0]
	if value <= float(first[0]):
		return float(first[1])
	for i in range(1, points.size()):
		var b: Array = points[i]
		var bx := float(b[0])
		if value <= bx:
			var a: Array = points[i - 1]
			var ax := float(a[0])
			var span := bx - ax
			return float(b[1]) if span <= 0.0 else lerpf(a[1], b[1], (value - ax) / span)
	var last: Array = points[points.size() - 1]
	return float(last[1])


static func sum_db(curves: Array, params: Dictionary) -> float:
	var total := 0.0
	for curve: Dictionary in curves:
		total += eval(curve, params)
	return total


## 1.0 for [].
static func product(curves: Array, params: Dictionary) -> float:
	var total := 1.0
	for curve: Dictionary in curves:
		total *= eval(curve, params)
	return total


## {"param", "min"?, "max"?}; {} passes. One param only: a gate on two needs one composite param from the adapter.
static func passes(when: Dictionary, params: Dictionary) -> bool:
	if when.is_empty():
		return true
	var value := float(params.get(when.get("param", ""), 0.0))
	if when.has("min") and value < float(when["min"]):
		return false
	return not (when.has("max") and value > float(when["max"]))
