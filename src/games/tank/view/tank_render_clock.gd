class_name TankRenderClock
extends RefCounted
## The clock the view draws the world at (WorkoutRideView's interpolation, brief 2.6): render_t runs
## on the frame clock `delay()` behind the newest history entry's host time and never passes the
## newest entry (no extrapolation). The delay is the history's mean spacing, at least MIN_DELAY_S
## (a client: NetSession's 100 ms at 10 Hz; the host and SOLO see every 0.05 s tick, so one tick)
## and at most MAX_DELAY_S. A render_t further than RESYNC_S from where it belongs (the first
## entry, a rejoin, a stall) jumps there.

const CLIENT_DELAY_S := 0.1
const HOST_DELAY_S := Wl.SIM_DT
const RESYNC_S := 1.5
## Under RESYNC_S so a render_t held at the newest entry is never resynced when the delay grows.
const MAX_DELAY_S := RESYNC_S - 0.1
## A render_t that fell behind (a late snapshot held it at the newest) catches up with this tau.
const CATCHUP_TAU_S := 0.25

## The smallest delay: CLIENT_DELAY_S on a client, HOST_DELAY_S otherwise.
var min_delay_s: float = HOST_DELAY_S
## The host time the world is drawn at.
var render_t: float = 0.0
var _set: bool = false


## True once render_t has been placed (after the first entry).
func is_set() -> bool:
	return _set


func reset() -> void:
	_set = false
	render_t = 0.0


## How far render_t runs behind the newest entry (s).
func delay(history: TankSnapHistory) -> float:
	var spacing := history.mean_spacing() if history != null else 0.0
	return clampf(spacing, min_delay_s, MAX_DELAY_S)


## One frame of `delta` seconds. Does nothing without history.
func advance(delta: float, history: TankSnapHistory) -> void:
	if history == null or history.is_empty():
		return
	var newest := history.newest_t()
	var goal := newest - delay(history)
	if not _set or absf(goal - render_t) > RESYNC_S:
		render_t = goal
		_set = true
		return
	render_t += delta
	var behind := goal - render_t
	if behind > 0.0:
		render_t += behind * (1.0 - exp(-delta / CATCHUP_TAU_S))
	render_t = minf(render_t, newest)
