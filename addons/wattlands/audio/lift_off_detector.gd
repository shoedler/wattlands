class_name LiftOffDetector
extends RefCounted
## Finds a rider lifting off the power, for an engine's exhaust crackle (SPEC_AUDIO 1.2). Pure.
const DROP := 0.25  ## a power-ratio fall of this much within WINDOW_S
const WINDOW_S := 1.0
const HOLD_S := 0.8

var _t: float = 0.0
var _times: PackedFloat64Array = PackedFloat64Array()
var _values: PackedFloat64Array = PackedFloat64Array()
var _level: float = 0.0


## 1 on the drop, linear to 0 over HOLD_S.
func update(power_ratio: float, dt: float) -> float:
	_t += dt
	_times.append(_t)
	_values.append(power_ratio)
	while _t - _times[0] > WINDOW_S:
		_times.remove_at(0)
		_values.remove_at(0)
	var peak := power_ratio
	for v in _values:
		peak = maxf(peak, v)
	if peak - power_ratio >= DROP:
		_level = 1.0
		_times = PackedFloat64Array([_t])
		_values = PackedFloat64Array([power_ratio])
	else:
		_level = maxf(_level - dt / HOLD_S, 0.0)
	return _level
