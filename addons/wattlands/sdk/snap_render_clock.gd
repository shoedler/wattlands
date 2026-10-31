class_name SnapRenderClock
extends RefCounted
## The clock a view draws the world at, reading a SnapHistory (BRIEF 5.1; GAME_SDK 12): render_t runs
## on the frame clock `delay()` behind the newest entry's host time and never passes the newest entry
## (no extrapolation). The delay is the history's mean spacing, at least min_delay_s and at most
## MAX_DELAY_S. Under the 8-rider load snapshots arrive about once a second; a fixed 0.1 s delay would
## hold the world at the newest snapshot for most of each second and then hurry it on. A render_t
## further than RESYNC_S from where it belongs (the first entry, a rejoin, a stall) jumps there.

## NetSession's documented 100 ms interpolation at 10 Hz.
const CLIENT_DELAY_S := 0.1
## The host and SOLO see every 0.05 s tick, so one tick.
const HOST_DELAY_S := Wl.SIM_DT
const RESYNC_S := 1.5
## Under RESYNC_S so a render_t held at the newest entry is never resynced when the delay grows.
const MAX_DELAY_S := RESYNC_S - 0.1
## A render_t that fell behind (a late snapshot held it at the newest) catches up with this tau.
const CATCHUP_TAU_S := 0.25

## The smallest delay: CLIENT_DELAY_S on a client, HOST_DELAY_S otherwise.
var min_delay_s: float = CLIENT_DELAY_S
## True: render_t never goes back, even when the newest entry falls behind it (it waits there).
var never_back: bool = false
## The host time the world is drawn at.
var render_t: float = 0.0
var _placed: bool = false


func _init(p_min_delay_s: float = CLIENT_DELAY_S) -> void:
	min_delay_s = p_min_delay_s


## True once render_t has been placed (after the first entry).
func is_set() -> bool:
	return _placed


func reset() -> void:
	_placed = false
	render_t = 0.0


## Puts render_t at `t` and marks it placed: for a game that runs its own goal over this clock.
func place(t: float) -> void:
	render_t = t
	_placed = true


## How far render_t runs behind the newest entry (s). A null history reads as no spacing.
func delay(history: SnapHistory) -> float:
	var spacing := history.mean_spacing() if history != null else 0.0
	return clampf(spacing, min_delay_s, MAX_DELAY_S)


## One frame of `delta` seconds. Does nothing without history.
func advance(delta: float, history: SnapHistory) -> void:
	if history == null or history.is_empty():
		return
	var newest := history.newest_t()
	var goal := newest - delay(history)
	if not _placed or absf(goal - render_t) > RESYNC_S:
		place(goal)
		return
	var was := render_t
	var step := maxf(delta, 0.0)
	render_t += step
	var behind := goal - render_t
	if behind > 0.0:
		render_t += behind * (1.0 - exp(-step / CATCHUP_TAU_S))
	render_t = minf(render_t, newest)
	if never_back:
		render_t = maxf(render_t, was)
