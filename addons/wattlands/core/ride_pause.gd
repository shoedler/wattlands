class_name RidePause
extends RefCounted
## Pause on not pedaling (BRIEF 3.5): the shared not_pedaling detector
## (GestureRecognizer.is_not_pedaling) held for ENTER_S pauses the rider; RESUME_S of
## pedaling at >= RESUME_RPM resumes. Pure: LocalRider feeds it the rider's held power and
## cadence once per tick on platform time, so both times count from the tick in which the
## sample that meets (or breaks) the condition arrived.
## It is a timer/clock feature layered on top of the governor, which keeps every 4.6 rule of
## its own (coasting floor at 3 s, the solo pause or AFK at 10 s, the ramp back); ENTER_S
## matches that 10 s, so a stop pauses once, never before the governor's own limit.

const ENTER_S := 10.0
const RESUME_S := 1.0
const RESUME_RPM := 30.0
const _EPS := 1e-6

## True from ENTER_S of not pedaling until RESUME_S of pedaling at >= RESUME_RPM.
var paused: bool = false

var _np_since: float = -1.0
var _ok_since: float = -1.0


## Feed the latest held values at platform time `t`; returns true when `paused` changed.
func update(t: float, power_w: float, cadence_rpm: float) -> bool:
	if not paused:
		if not GestureRecognizer.is_not_pedaling(power_w, cadence_rpm):
			_np_since = -1.0
			return false
		if _np_since < 0.0:
			_np_since = t
		if t - _np_since < ENTER_S - _EPS:
			return false
		paused = true
		_np_since = -1.0
		_ok_since = -1.0
		return true
	if cadence_rpm < RESUME_RPM:
		_ok_since = -1.0
		return false
	if _ok_since < 0.0:
		_ok_since = t
	if t - _ok_since < RESUME_S - _EPS:
		return false
	paused = false
	_ok_since = -1.0
	return true


func reset() -> void:
	paused = false
	_np_since = -1.0
	_ok_since = -1.0
