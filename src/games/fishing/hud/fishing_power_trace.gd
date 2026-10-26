class_name FishingPowerTrace
extends RefCounted
## The local rider's power for the HUD graphs: one sample (power, target) every STEP_S of
## telemetry time, the last `window_s` kept, oldest first. A time going backwards (a new session,
## a rejoin) starts over.

const STEP_S := 0.25

var window_s: float = 30.0
## [Vector2(power W, target W)], oldest first.
var samples: Array[Vector2] = []
var _last_t: float = -INF


func _init(p_window_s: float = 30.0) -> void:
	window_s = p_window_s


## Records `power_w` and `target_w` at time `t` (s) when a step has passed since the last one.
func add(t: float, power_w: float, target_w: float) -> void:
	if t < _last_t:
		samples.clear()
		_last_t = -INF
	if t - _last_t < STEP_S:
		return
	_last_t = t
	samples.append(Vector2(maxf(power_w, 0.0), maxf(target_w, 0.0)))
	var most := ceili(window_s / STEP_S)
	while samples.size() > most:
		samples.pop_front()


func capacity() -> int:
	return ceili(window_s / STEP_S)


## The largest power or target kept (0 when empty).
func peak() -> float:
	var out := 0.0
	for s in samples:
		out = maxf(out, maxf(s.x, s.y))
	return out


## Column `i` of `n` across the window, the newest at the right: the sample there (Vector2(-1, -1)
## where the window is not filled yet).
func at_column(i: int, n: int) -> Vector2:
	var cap := capacity()
	var k := int(floor(float(i) * float(cap) / float(maxi(n, 1))))
	var idx := k - (cap - samples.size())
	if idx < 0 or idx >= samples.size():
		return Vector2(-1, -1)
	return samples[idx]
