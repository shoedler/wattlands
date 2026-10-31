class_name FrameClockLock
extends RefCounted
## How far the frame clock a view integrates runs from real time, less its own slow mean. Pure: the kit hands it both
## times. Godot's delta smoothing hands out whole vsyncs and carries the rest (on a 59.94 Hz display: 1 ms/s behind,
## then 16 ms paid back in a few frames, every 16 s), so `revs` has a sawtooth against real time. A stroke planned at
## revs - rate * lead_s runs on real time instead, while its distance from the view stays at most SNAP_S: nothing to
## integrate per machine, so nothing that could drift, and a jump in a view's revs passes straight through.
## TAU_S is long against the sawtooth's period, and costs nothing in steady state: the lead is bounded by the sawtooth.
const TAU_S := 20.0
## Far past any sawtooth: the frames and real time have really parted (a gap between commits). Follow the frames.
const SNAP_S := 0.04
## Seconds the view runs ahead of the clock strokes are timed on.
var lead_s: float = 0.0

var _gap_s: float = 0.0
var _mean_s: float = 0.0


## One frame: the delta the view integrated and the real seconds it took. Returns lead_s.
func update(dt: float, real_dt: float) -> float:
	_gap_s += dt - real_dt
	_mean_s += (_gap_s - _mean_s) * clampf(real_dt / TAU_S, 0.0, 1.0)
	lead_s = _gap_s - _mean_s
	if absf(lead_s) > SNAP_S:
		_mean_s = _gap_s
		lead_s = 0.0
	return lead_s


func reset() -> void:
	lead_s = 0.0
	_gap_s = 0.0
	_mean_s = 0.0
