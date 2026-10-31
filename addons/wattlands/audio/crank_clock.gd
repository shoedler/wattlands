class_name CrankClock
extends RefCounted
## One rider's crank phase, integrated from cadence. Pure. One per phase source: audio and view read
## the same `revs`, so they cannot drift apart. At or below STOP_RPM it stands still (TankViewSeats._seats runs on it).
const STOP_RPM := 1.0
var revs: float = 0.0


## Returns the whole revolutions crossed by this call.
func advance(rpm: float, dt: float) -> int:
	if rpm <= STOP_RPM or dt <= 0.0:
		return 0
	var was := floori(revs)
	revs += rpm / 60.0 * dt
	return floori(revs) - was


func frac() -> float:
	return fposmod(revs, 1.0)


func angle() -> float:
	return frac() * TAU


## Total whole revolutions so far.
func crossings() -> int:
	return floori(revs)


func reset() -> void:
	revs = 0.0
