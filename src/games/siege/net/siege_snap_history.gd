class_name SiegeSnapHistory
extends RefCounted
## Client: every enemy's road position in the last few snapshots, keyed by the host's game time
## (the snapshot's tick x Wl.SIM_DT), so the view can draw enemies between two snapshots (brief
## 2.6; BRIEF 5.1). Like WorkoutSnapHistory: a game has no NetSession handle, so the render clock
## runs behind the newest snapshot by their mean spacing (0.1 s at 10 Hz, about 1 s under the
## 8-rider load) and never passes the newest snapshot (no extrapolation) nor goes backwards.
## SiegeGame.apply_snapshot pushes one entry per snapshot; the view calls advance(delta) every
## frame and reads pos_of() / prog_of(). Times come from the host's ticks, never from a clock.

## Entries kept: 0.8 s at 10 Hz, like NetSession's snapshot buffer.
const CAPACITY := 8
## A snapshot more than this after the newest (a rejoin, a long stall) starts the history over.
const MAX_GAP_S := 1.5
## The shortest delay: NetSession's documented 100 ms interpolation at 10 Hz.
const DELAY_MIN_S := 0.1
## render_t further than this from where it belongs jumps there.
const RESYNC_S := 1.5
## The longest delay. It stays under RESYNC_S, so a render_t held at the newest snapshot is never
## resynced (sent back) when the delay grows.
const DELAY_MAX_S := RESYNC_S - 0.1
## A render_t that fell behind catches up with this time constant.
const CATCHUP_TAU_S := 0.25

## Oldest first: [{"t": host seconds, "e": {enemy id: PackedFloat32Array [road, prog_m, lat_m]}}].
var entries: Array[Dictionary] = []
## The map positions are computed on (SiegeSnapHistory.pos_of); may be null (prog_of still works).
var map: SiegeMap = null
## The host time the view draws (advance() moves it).
var render_t: float = 0.0
var _clock_set: bool = false


func _init(p_map: SiegeMap = null) -> void:
	map = p_map


func clear() -> void:
	entries.clear()
	_clock_set = false
	render_t = 0.0


func is_empty() -> bool:
	return entries.is_empty()


## The newest entry's host time (0 when empty).
func newest_t() -> float:
	return float(entries.back()["t"]) if not entries.is_empty() else 0.0


## The mean host time between neighbouring entries (s); 0 with fewer than two entries.
func mean_spacing() -> float:
	if entries.size() < 2:
		return 0.0
	return (newest_t() - float(entries.front()["t"])) / float(entries.size() - 1)


## How far render_t runs behind the newest snapshot (s): the mean spacing, clamped to
## DELAY_MIN_S..DELAY_MAX_S (DELAY_MIN_S before two snapshots are in).
func delay() -> float:
	return clampf(mean_spacing(), DELAY_MIN_S, DELAY_MAX_S)


## Records the enemies of the snapshot just applied, at host time `t`. A time equal to the newest
## replaces it; an earlier one (the host's clock went back: a new session) or one more than
## MAX_GAP_S later starts the history over.
func push(t: float, enemies: Array[SiegeEnemyState]) -> void:
	var e := {}
	for en in enemies:
		e[en.id] = PackedFloat32Array([en.road, en.prog_m, en.lat_m])
	if not entries.is_empty():
		var newest := newest_t()
		if t < newest or t - newest > MAX_GAP_S:
			entries.clear()
		elif is_equal_approx(t, newest):
			entries.pop_back()
	entries.append({"t": t, "e": e})
	while entries.size() > CAPACITY:
		entries.pop_front()


## Moves render_t by the frame time `delta`: it follows the frame clock, catches up softly when
## behind newest - delay(), jumps when RESYNC_S off (the first snapshot, a rejoin, a stall), and
## stops at the newest snapshot. A delay that grows leaves render_t ahead of its goal: it waits
## at the newest snapshot, never back. Returns render_t.
func advance(delta: float) -> float:
	if entries.is_empty():
		return render_t
	var newest := newest_t()
	var goal := newest - delay()
	if not _clock_set or absf(goal - render_t) > RESYNC_S:
		render_t = goal
		_clock_set = true
		return render_t
	var was := render_t
	render_t += maxf(delta, 0.0)
	var behind := goal - render_t
	if behind > 0.0:
		render_t += behind * (1.0 - exp(-maxf(delta, 0.0) / CATCHUP_TAU_S))
	render_t = maxf(minf(render_t, newest), was)
	return render_t


## Enemy `id`'s [road, prog_m, lat_m] at host time `t`: linear between the two entries around `t`,
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


## Road progress (m) of enemy `id` at render_t; `fallback` when it isn't in the history.
func prog_of(id: int, fallback: float) -> float:
	var s := state_at(id, render_t)
	return s[1] if s.size() == 3 else fallback


## Ground position (x, z) of enemy `id` at render_t on the map; `fallback` without a map or
## history for it.
func pos_of(id: int, fallback: Vector2) -> Vector2:
	var s := state_at(id, render_t)
	if s.size() != 3 or map == null or int(s[0]) < 0 or int(s[0]) >= map.road_count():
		return fallback
	return map.point_at(int(s[0]), s[1], s[2])


static func _blend(
	a: PackedFloat32Array, b: PackedFloat32Array, alpha: float
) -> PackedFloat32Array:
	return PackedFloat32Array([b[0], lerpf(a[1], b[1], alpha), lerpf(a[2], b[2], alpha)])
