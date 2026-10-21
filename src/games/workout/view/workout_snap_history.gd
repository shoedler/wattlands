class_name WorkoutSnapHistory
extends RefCounted
## Client: every rider's distance in the last few snapshots, keyed by the host's game time
## (the snapshot's tick x Wl.SIM_DT), so the ride view can draw the other riders between two
## snapshots (BRIEF 5.1; NetSession's 100 ms interpolation). WorkoutGame.apply_snapshot pushes
## one entry per snapshot it applies; the view only reads it. Times come from the host's
## ticks, never from a clock.

## Entries kept: 0.8 s at 10 Hz, like NetSession's snapshot buffer.
const CAPACITY := 8
## A snapshot more than this after the newest (a rejoin, a long stall) starts the history over,
## so the view never draws a rider between two snapshots that far apart. Snapshots about a
## second apart (the 8-rider load) still interpolate.
const MAX_GAP_S := 1.5

## Oldest first: [{"t": host seconds, "d": {peer: distance_m}}].
var entries: Array[Dictionary] = []


func clear() -> void:
	entries.clear()


func is_empty() -> bool:
	return entries.is_empty()


## The newest entry's host time (0 when empty).
func newest_t() -> float:
	return float(entries.back()["t"]) if not entries.is_empty() else 0.0


## Records the distances of the snapshot just applied to `state`, at host time `t`. A time
## equal to the newest replaces it; an earlier one (the host's clock went back: a new session)
## or one more than MAX_GAP_S later starts the history over.
func push(t: float, state: WorkoutState) -> void:
	var d := {}
	for peer: int in state.order:
		d[peer] = state.rider(peer).distance_m()
	if not entries.is_empty():
		var newest := newest_t()
		if t < newest or t - newest > MAX_GAP_S:
			entries.clear()
		elif is_equal_approx(t, newest):
			entries.pop_back()
	entries.append({"t": t, "d": d})
	while entries.size() > CAPACITY:
		entries.pop_front()


## `peer`'s distance at host time `t`: linear between the two entries around `t`, the oldest
## entry's value before it and the newest's after it (never extrapolated); `fallback` when no
## entry has the peer.
func distance_at(peer: int, t: float, fallback: float) -> float:
	var prev: Dictionary = {}
	for e in entries:
		var d: Dictionary = e["d"]
		if not d.has(peer):
			continue
		var et := float(e["t"])
		if et >= t:
			if prev.is_empty():
				return float(d[peer])
			var pt := float(prev["t"])
			var alpha := clampf((t - pt) / (et - pt), 0.0, 1.0) if et > pt else 1.0
			return lerpf(float((prev["d"] as Dictionary)[peer]), float(d[peer]), alpha)
		prev = e
	if prev.is_empty():
		return fallback
	return float((prev["d"] as Dictionary)[peer])
