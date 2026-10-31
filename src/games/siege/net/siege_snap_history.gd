class_name SiegeSnapHistory
extends SnapHistory
## Client: every enemy's path position in the last few snapshots, keyed by the host's game time
## (the snapshot's tick x Wl.SIM_DT), so the view can draw enemies between two snapshots (brief
## 2.6; BRIEF 5.1). Like WorkoutSnapHistory: a game has no NetSession handle, so the render clock
## runs behind the newest snapshot by their mean spacing (0.1 s at 10 Hz, about 1 s under the
## 8-rider load) and never passes the newest snapshot (no extrapolation) nor goes backwards.
## SiegeGame.apply_snapshot pushes one entry per snapshot; the view calls advance(delta) every
## frame and reads pos_of() / prog_of(). Times come from the host's ticks, never from a clock.

## The shortest delay: NetSession's documented 100 ms interpolation at 10 Hz.
const DELAY_MIN_S := 0.1

## Rows, oldest first: {"t": host seconds, "e": {enemy id: PackedFloat32Array [prog_m, lat_m]}}.

## The path positions are computed on (SiegeSnapHistory.pos_of); may be null (prog_of still works).
var path: SiegePath = null
## The host time the view draws (advance() moves it).
var render_t: float:
	get:
		return _clock.render_t
	set(value):
		_clock.render_t = value

var _clock: SnapRenderClock = SnapRenderClock.new()


func _init(p_path: SiegePath = null) -> void:
	path = p_path
	_clock.min_delay_s = DELAY_MIN_S
	_clock.never_back = true


func clear() -> void:
	super()
	_clock.reset()


## How far render_t runs behind the newest snapshot (s): the mean spacing, clamped to
## DELAY_MIN_S..SnapRenderClock.MAX_DELAY_S (DELAY_MIN_S before two snapshots are in).
func delay() -> float:
	return _clock.delay(self)


## Records the enemies of the snapshot just applied, at host time `t`.
func push(t: float, enemies: Array[SiegeEnemyState]) -> void:
	var e := {}
	for en in enemies:
		e[en.id] = PackedFloat32Array([en.prog_m, en.lat_m])
	add(t, {"e": e})


## Moves render_t by the frame time `delta` (SnapRenderClock): it follows the frame clock, catches up
## softly when behind newest - delay(), jumps when RESYNC_S off (the first snapshot, a rejoin, a
## stall), and stops at the newest snapshot. A delay that grows leaves render_t ahead of its goal: it
## waits at the newest snapshot, never back. Returns render_t.
func advance(delta: float) -> float:
	_clock.advance(delta, self)
	return render_t


## Enemy `id`'s [prog_m, lat_m] at host time `t`: linear between the two entries around `t`,
## the oldest entry's value before it and the newest's after (never extrapolated); an empty
## array when no entry has the enemy.
func state_at(id: int, t: float) -> PackedFloat32Array:
	var prev: Dictionary = {}
	for entry in entries:
		var e: Dictionary = entry["e"]
		if not e.has(id):
			continue
		var et := float(entry["t"])
		if et >= t:
			if prev.is_empty():
				return e[id]
			var pt := float(prev["t"])
			var alpha := clampf((t - pt) / (et - pt), 0.0, 1.0) if et > pt else 1.0
			var a: PackedFloat32Array = (prev["e"] as Dictionary)[id]
			var b: PackedFloat32Array = e[id]
			return _blend(a, b, alpha)
		prev = entry
	if prev.is_empty():
		return PackedFloat32Array()
	return (prev["e"] as Dictionary)[id]


## Path progress (m) of enemy `id` at render_t; `fallback` when it isn't in the history.
func prog_of(id: int, fallback: float) -> float:
	var s := state_at(id, render_t)
	return s[0] if s.size() == 2 else fallback


## Lateral offset (m) of enemy `id` at render_t; `fallback` when it isn't in the history.
func lat_of(id: int, fallback: float) -> float:
	var s := state_at(id, render_t)
	return s[1] if s.size() == 2 else fallback


## World position of enemy `id` at render_t on the path; `fallback` without a path or history
## for it.
func pos_of(id: int, fallback: Vector3) -> Vector3:
	var s := state_at(id, render_t)
	if s.size() != 2 or path == null:
		return fallback
	return path.point_at(s[0], s[1])


static func _blend(
	a: PackedFloat32Array, b: PackedFloat32Array, alpha: float
) -> PackedFloat32Array:
	return PackedFloat32Array([lerpf(a[0], b[0], alpha), lerpf(a[1], b[1], alpha)])
