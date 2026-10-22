class_name SiegeEnemyInterp
extends RefCounted
## Smooths enemy motion between sim states for the view. The host's state changes every 0.05 s
## tick and a client's only when a snapshot arrives (about every 0.1 s, about 1 s under the
## 8-rider load), so the view draws each enemy between its progress at the previous state and
## at the newest one, on a render clock that runs behind the newest state by their mean spacing
## (like Workout's WorkoutSnapHistory; GAME_SDK 12). Everything is keyed by enemy id and by the
## state's tick, never by a wall clock. This is the one place the view reads enemy progress
## from: if the module later exposes its own snapshot history, only this class changes.

## A gap longer than this between states (a rejoin, a stall) restarts the history.
const MAX_GAP_S := 1.5
const MIN_SPACING_S := 0.05
const MAX_SPACING_S := 1.2

var spacing_s: float = MIN_SPACING_S
## Host times of the previous and the newest state (tick x 0.05).
var t_prev: float = 0.0
var t_cur: float = 0.0
var render_t: float = 0.0
var _tick: int = -1
var _prev_prog: Dictionary = {}
var _prev_lat: Dictionary = {}
var _cur_prog: Dictionary = {}
var _cur_lat: Dictionary = {}


func reset() -> void:
	_tick = -1
	_prev_prog.clear()
	_prev_lat.clear()
	_cur_prog.clear()
	_cur_lat.clear()
	spacing_s = MIN_SPACING_S


## Records `state` when its tick is new (call every frame, cheap otherwise).
func observe(state: SiegeState) -> void:
	if state.tick == _tick:
		return
	var t := float(state.tick) * Wl.SIM_DT
	if _tick < 0 or t < t_cur or t - t_cur > MAX_GAP_S:
		reset()
		t_prev = t
		t_cur = t
		render_t = t
	else:
		var gap := t - t_cur
		spacing_s = clampf(lerpf(spacing_s, gap, 0.3), MIN_SPACING_S, MAX_SPACING_S)
		t_prev = t_cur
		t_cur = t
		_prev_prog = _cur_prog
		_prev_lat = _cur_lat
	_tick = state.tick
	_cur_prog = {}
	_cur_lat = {}
	for e in state.enemies:
		_cur_prog[e.id] = e.prog_m
		_cur_lat[e.id] = e.lat_m


## Advances the render clock by `dt` seconds of frame time.
func advance(dt: float) -> void:
	var goal := t_cur - spacing_s
	render_t += dt
	render_t = lerpf(render_t, goal, 0.08)
	render_t = clampf(render_t, minf(t_prev, goal), t_cur)


## 0..1 between the previous state (0) and the newest (1) at the render clock.
func alpha() -> float:
	if t_cur <= t_prev:
		return 1.0
	return clampf((render_t - t_prev) / (t_cur - t_prev), 0.0, 1.0)


## Road progress of `e` at the render clock.
func prog_of(e: SiegeEnemyState) -> float:
	return lerpf(float(_prev_prog.get(e.id, e.prog_m)), e.prog_m, alpha())


func lat_of(e: SiegeEnemyState) -> float:
	return lerpf(float(_prev_lat.get(e.id, e.lat_m)), e.lat_m, alpha())


## Ground position (x, z) of `e` at the render clock.
func pos_of(e: SiegeEnemyState, map: SiegeMap) -> Vector2:
	return map.point_at(e.road, prog_of(e), lat_of(e))
