class_name WorkoutCrankClock
extends RefCounted
## Every rider's crank revolutions, integrated from cadence: revs += rpm / 60 * dt. No smoothing and
## no easing, so legs follow the rider's cadence 1:1 and stop dead at 0 rpm. Pure.

## peer -> revolutions so far.
var _revs: Dictionary = {}


func step(peer: int, rpm: float, dt: float) -> void:
	_revs[peer] = revs(peer) + maxf(rpm, 0.0) / 60.0 * dt


func revs(peer: int) -> float:
	return float(_revs.get(peer, 0.0))


func clear() -> void:
	_revs.clear()
