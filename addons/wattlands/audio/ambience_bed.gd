class_name AmbienceBed
extends RefCounted
## One environment (SPEC_AUDIO 1.2, 1.5): layered loops plus spot details on seeded timers. Pure. Own
## RandomNumberGenerator seeded with p_seed, so the same seed and params give the same spots. Bursts expand to several
## entries with at_s offsets up to 1 s (the kit's pending queue handles them).
const BURST_MAX_S := 1.0
var loops: LayeredLoop
var trim_db: float = 0.0  ## added to every layer and spot: the kit's crossfade and pause drop

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _spots: Array = []
var _left: PackedFloat64Array = PackedFloat64Array()
var _variant: PackedInt32Array = PackedInt32Array()


func _init(p_spec: Dictionary, p_seed: int) -> void:
	_rng.seed = p_seed
	loops = LayeredLoop.new(p_spec.get("layers", []))
	_spots = p_spec.get("spots", [])
	_left.resize(_spots.size())
	_variant.resize(_spots.size())
	for i in _spots.size():
		var spot: Dictionary = _spots[i]
		_left[i] = _pick(spot.get("gap_s", 1.0))
		_variant[i] = 0


## Spots due now: {"sound", "variant", "at_s", "db", "pitch"}. A spot whose `when` fails stays quiet this round.
func update(params: Dictionary, dt: float) -> Array[Dictionary]:
	loops.update(params, trim_db, true, dt)
	var out: Array[Dictionary] = []
	for i in _spots.size():
		_left[i] -= dt
		if _left[i] > 0.0:
			continue
		var spot: Dictionary = _spots[i]
		_left[i] = _pick(spot.get("gap_s", 1.0))
		if not AudioCurve.passes(spot.get("when", {}), params):
			continue
		_expand(i, spot, params, out)
	return out


func _expand(i: int, spot: Dictionary, params: Dictionary, out: Array[Dictionary]) -> void:
	var burst: Variant = spot.get("burst", 1)
	var n := int(burst) if burst is float or burst is int else _pick_int(burst)
	var gap := float(spot.get("burst_gap_s", 0.0))
	for k in maxi(n, 1):
		var at_s := float(k) * gap
		if at_s > BURST_MAX_S:
			break
		var level := _pick(spot.get("db", 0.0)) + AudioCurve.sum_db(spot.get("db_by", []), params)
		var entry := {
			"sound": str(spot.get("sound", "")),
			"variant": _variant[i],
			"at_s": at_s,
			"db": level + trim_db,
			"pitch": _pick(spot.get("pitch", 1.0)),
		}
		out.append(entry)
		_variant[i] += 1


## A [lo, hi] range drawn from the bed's RNG, or a plain number.
func _pick(v: Variant) -> float:
	if v is Array:
		var r: Array = v
		return _rng.randf_range(float(r[0]), float(r[1]))
	return float(v)


func _pick_int(v: Variant) -> int:
	var r: Array = v
	return _rng.randi_range(int(r[0]), int(r[1]))
