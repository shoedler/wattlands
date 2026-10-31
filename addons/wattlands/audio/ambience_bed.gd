class_name AmbienceBed
extends RefCounted
## One environment (SPEC_AUDIO 1.2, 1.5): layered loops plus spot details on seeded timers. Pure. Own
## RandomNumberGenerator seeded with p_seed, so the same seed and params give the same spots. Bursts expand to several
## entries with at_s offsets up to 1 s (the kit's pending queue handles them). A spot's gap_s never follows a param: for
## a gap by speed, write one spot per speed band, each with its own gap_s and a `when` on speed. A bed's spot_min_gap_s
## (default 0, off) keeps its details apart: a spot whose gap can't fall under it waits until that long after the last
## such spot's last burst, and a little more so no one spot always wins. A spot whose gap can (a cricket train) is a
## texture and neither waits nor holds others up.
const BURST_MAX_S := 1.0
var loops: LayeredLoop
var trim_db: float = 0.0  ## added to every layer and spot: the kit's crossfade and pause drop

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _spots: Array = []
var _left: PackedFloat64Array = PackedFloat64Array()
var _variant: Dictionary = {}  ## a running count per sound: a sound split into several spots by `when` keeps its round
var _spot_min_gap_s: float = 0.0
var _since_detail: float = INF


func _init(p_spec: Dictionary, p_seed: int) -> void:
	_rng.seed = p_seed
	loops = LayeredLoop.new(p_spec.get("layers", []))
	_spots = p_spec.get("spots", [])
	_spot_min_gap_s = float(p_spec.get("spot_min_gap_s", 0.0))
	_left.resize(_spots.size())
	for i in _spots.size():
		var spot: Dictionary = _spots[i]
		_left[i] = _pick(spot.get("gap_s", 1.0))


## Spots due now: {"sound", "variant", "at_s", "db", "pitch"}. A spot whose `when` fails stays quiet this round.
func update(params: Dictionary, dt: float) -> Array[Dictionary]:
	loops.update(params, trim_db, true, dt)
	var out: Array[Dictionary] = []
	_since_detail += dt
	for i in _spots.size():
		_left[i] -= dt
		if _left[i] > 0.0:
			continue
		var spot: Dictionary = _spots[i]
		var detail := _is_detail(spot)
		if detail and _since_detail < _spot_min_gap_s:
			_left[i] = _spot_min_gap_s * (1.0 + _rng.randf()) - _since_detail
			continue
		_left[i] = _pick(spot.get("gap_s", 1.0))
		if not AudioCurve.passes(spot.get("when", {}), params):
			continue
		_expand(spot, params, out)
		if detail:
			_since_detail = -float(out[-1]["at_s"])
	return out


func _is_detail(spot: Dictionary) -> bool:
	if _spot_min_gap_s <= 0.0:
		return false
	var gap: Variant = spot.get("gap_s", 1.0)
	var shortest: float = float((gap as Array)[0]) if gap is Array else float(gap)
	return shortest >= _spot_min_gap_s


func _expand(spot: Dictionary, params: Dictionary, out: Array[Dictionary]) -> void:
	var sound := str(spot.get("sound", ""))
	var burst: Variant = spot.get("burst", 1)
	var n := int(burst) if burst is float or burst is int else _pick_int(burst)
	var gap := float(spot.get("burst_gap_s", 0.0))
	for k in maxi(n, 1):
		var at_s := float(k) * gap
		if at_s > BURST_MAX_S:
			break
		var level := _pick(spot.get("db", 0.0)) + AudioCurve.sum_db(spot.get("db_by", []), params)
		var entry := {
			"sound": sound,
			"variant": int(_variant.get(sound, 0)),
			"at_s": at_s,
			"db": level + trim_db,
			"pitch": _pick(spot.get("pitch", 1.0)),
		}
		out.append(entry)
		_variant[sound] = int(_variant.get(sound, 0)) + 1


## A [lo, hi] range drawn from the bed's RNG, or a plain number.
func _pick(v: Variant) -> float:
	if v is Array:
		var r: Array = v
		return _rng.randf_range(float(r[0]), float(r[1]))
	return float(v)


func _pick_int(v: Variant) -> int:
	var r: Array = v
	return _rng.randi_range(int(r[0]), int(r[1]))
