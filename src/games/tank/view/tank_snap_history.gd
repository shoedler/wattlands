class_name TankSnapHistory
extends RefCounted
## What moves between snapshots, keyed by the host's game time (snapshot tick x Wl.SIM_DT): the
## hull's x (the camera), the boss x, every enemy's x, every shell's position and every rider's
## watts and cadence. TankView pushes one entry per snapshot a client applies (TankGame.
## snapshot_applied) and one per sim tick it sees on the host or SOLO, then draws the world at
## TankRenderClock.render_t, a little behind the newest entry (brief 2.6: 100 ms interpolation).
## The view only reads this; times come from ticks, never from a clock. Like WorkoutSnapHistory.

## Entries kept: 0.8 s at 10 Hz, like NetSession's snapshot buffer.
const CAPACITY := 8
## An entry more than this after the newest (a rejoin, a long stall) starts the history over.
const MAX_GAP_S := 1.5

## Oldest first: {"t", "tick", "hull": float, "boss": float, "br": the boss's range_m, "e": {id: x},
## "er": {id: range_m}, "s": {id: Vector2}, "sl": {id: left_s},
## "r": {peer: Vector2(raw_w, cadence_rpm)}}.
var entries: Array[Dictionary] = []


func clear() -> void:
	entries.clear()


func is_empty() -> bool:
	return entries.is_empty()


## The newest entry's host time (0 when empty).
func newest_t() -> float:
	return float(entries.back()["t"]) if not entries.is_empty() else 0.0


## The newest entry's tick (-1 when empty).
func newest_tick() -> int:
	return int(entries.back()["tick"]) if not entries.is_empty() else -1


## The mean host time between neighbouring entries (0 with fewer than two).
func mean_spacing() -> float:
	if entries.size() < 2:
		return 0.0
	return (newest_t() - float(entries.front()["t"])) / float(entries.size() - 1)


## Records `state` at host tick `tick`. The same time as the newest replaces it; an earlier one (a
## new session) or one more than MAX_GAP_S later starts over.
func push(tick: int, state: TankState) -> void:
	var t := float(tick) * Wl.SIM_DT
	var enemies := {}
	var ranges := {}
	for e in state.enemies:
		enemies[e.id] = e.x_px
		ranges[e.id] = e.range_m
	var shells := {}
	var lefts := {}
	for s in state.shells:
		shells[s.id] = Vector2(s.x, s.y)
		lefts[s.id] = s.left_s
	var riders := {}
	for r in state.riders:
		riders[r.peer] = Vector2(r.raw_w, r.cadence_rpm)
	if not entries.is_empty():
		var newest := newest_t()
		if t < newest - 1e-6 or t - newest > MAX_GAP_S:
			entries.clear()
		elif absf(t - newest) <= 1e-6:
			entries.pop_back()
	entries.append(
		{
			"t": t,
			"tick": tick,
			"hull": state.hull.x_px,
			"boss": state.boss.x_px,
			"br": state.boss.range_m,
			"e": enemies,
			"er": ranges,
			"s": shells,
			"sl": lefts,
			"r": riders
		}
	)
	while entries.size() > CAPACITY:
		entries.pop_front()


func hull_x_at(t: float, fallback: float) -> float:
	return float(_sample(t, "hull", null, fallback))


func boss_x_at(t: float, fallback: float) -> float:
	return float(_sample(t, "boss", null, fallback))


func enemy_x_at(id: int, t: float, fallback: float) -> float:
	return float(_sample(t, "e", id, fallback))


## v4: a far enemy's range (m) at host time `t`.
func enemy_range_at(id: int, t: float, fallback: float) -> float:
	return float(_sample(t, "er", id, fallback))


## v4: the Behemoth's range (m) at host time `t`.
func boss_range_at(t: float, fallback: float) -> float:
	return float(_sample(t, "br", null, fallback))


## v4: a far shell's seconds until it lands at host time `t`.
func shell_left_at(id: int, t: float, fallback: float) -> float:
	return float(_sample(t, "sl", id, fallback))


func shell_at(id: int, t: float, fallback: Vector2) -> Vector2:
	return _sample(t, "s", id, fallback) as Vector2


## (raw watts, cadence rpm) of `peer` at host time `t`.
func rider_at(peer: int, t: float, fallback: Vector2) -> Vector2:
	return _sample(t, "r", peer, fallback) as Vector2


## `field` (or `field[key]`) at host time `t`: linear between the two entries around `t`, the
## oldest entry's value before it and the newest's after it (never extrapolated); `fallback` when
## no entry has it.
func _sample(t: float, field: String, key: Variant, fallback: Variant) -> Variant:
	var prev_v: Variant = null
	var prev_t := 0.0
	for e in entries:
		var v: Variant = e[field]
		if key != null:
			var d: Dictionary = v
			if not d.has(key):
				continue
			v = d[key]
		var et := float(e["t"])
		if et >= t:
			if prev_v == null:
				return v
			var alpha := clampf((t - prev_t) / (et - prev_t), 0.0, 1.0) if et > prev_t else 1.0
			return lerp(prev_v, v, alpha)
		prev_v = v
		prev_t = et
	return fallback if prev_v == null else prev_v
