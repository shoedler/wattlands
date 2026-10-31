class_name SnapHistory
extends RefCounted
## What moves between snapshots, in rows keyed by the host's game time (tick x Wl.SIM_DT), so a view
## can draw between two of them (BRIEF 5.1; GAME_SDK 12). A game has no NetSession handle, so it
## keeps its own. A game's subclass builds a row from its state, hands it to add() and names its
## fields through sample() or sample_sub(); SnapRenderClock says which time to read. Times come from
## ticks, never from a clock. Subclasses never redeclare CAPACITY, MAX_GAP_S or entries: a parse
## error. They read them through inheritance.

## Entries kept: 0.8 s at 10 Hz, like NetSession's snapshot buffer.
const CAPACITY := 8
## An entry more than this after the newest (a rejoin, a long stall) starts the history over, so a
## view never draws between two snapshots that far apart. Snapshots about a second apart (the
## 8-rider load) still interpolate.
const MAX_GAP_S := 1.5
## Two times this close are the same time. Fixed, not is_equal_approx: that tolerance is relative,
## and from about 5000 s on it is wider than a 0.05 s tick.
const SAME_T_S := 1e-6

## Oldest first. Each row has "t" and whatever its subclass's add() calls put there.
var entries: Array[Dictionary] = []


func clear() -> void:
	entries.clear()


func is_empty() -> bool:
	return entries.is_empty()


## The newest entry's host time (0 when empty).
func newest_t() -> float:
	return float(entries.back()["t"]) if not entries.is_empty() else 0.0


## The mean host time between neighbouring entries (s): 0.1 at 10 Hz, about 1 under the 8-rider
## load (NetSession's send budget). 0 with fewer than two entries.
func mean_spacing() -> float:
	if entries.size() < 2:
		return 0.0
	return (newest_t() - float(entries.front()["t"])) / float(entries.size() - 1)


## Records `row` at host time `t` (add sets its "t"). The same time as the newest replaces it; an
## earlier one (the host's clock went back: a new session) or one more than MAX_GAP_S later starts
## the history over.
func add(t: float, row: Dictionary) -> void:
	row["t"] = t
	if not entries.is_empty():
		var newest := newest_t()
		if t < newest - SAME_T_S or t - newest > MAX_GAP_S:
			entries.clear()
		elif absf(t - newest) <= SAME_T_S:
			entries.pop_back()
	entries.append(row)
	while entries.size() > CAPACITY:
		entries.pop_front()


## `field` (or `field[key]`, when `key` is not null) at host time `t`: linear between the two entries
## around `t`, the oldest entry's value before it and the newest's after it (never extrapolated);
## `fallback` when no entry has it. Lerps float and Vector2.
func sample(t: float, field: String, key: Variant, fallback: Variant) -> Variant:
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


## `field[key][sub]` at host time `t`, a float: as sample(), for rows that keep a dictionary per key.
## An entry whose `field[key]` lacks `sub` reads `fallback`, or the later entry's value when it is
## the earlier of two. `fallback` when no entry has `key`.
func sample_sub(t: float, field: String, key: Variant, sub: String, fallback: float) -> float:
	var prev: Dictionary = {}
	for e in entries:
		var rows: Dictionary = e[field]
		if not rows.has(key):
			continue
		var et := float(e["t"])
		if et >= t:
			var now := float((rows[key] as Dictionary).get(sub, fallback))
			if prev.is_empty():
				return now
			var pt := float(prev["t"])
			var alpha := clampf((t - pt) / (et - pt), 0.0, 1.0) if et > pt else 1.0
			var before := float(((prev[field] as Dictionary)[key] as Dictionary).get(sub, now))
			return lerpf(before, now, alpha)
		prev = e
	if prev.is_empty():
		return fallback
	return float(((prev[field] as Dictionary)[key] as Dictionary).get(sub, fallback))
