class_name FishingSnapHistory
extends RefCounted
## Client: the lanes of the last few snapshots keyed by the host's game time (the snapshot's tick
## x Wl.SIM_DT), so the view draws other lanes between two snapshots with its render clock behind
## the newest by mean_spacing() (Workout's WorkoutSnapHistory pattern; GAME_SDK 12). FishingGame
## calls push(t, state) once per applied snapshot; the view only reads (value_at). Times come
## from the host's ticks, never from a clock.

const CAPACITY := 8
## A snapshot more than this after the newest (a rejoin, a long stall) starts the history over.
const MAX_GAP_S := 1.5
## The values kept per lane: fish distance (m), depth, stamina, EMA cadence (rpm), power (W).
const KEYS: Array[String] = ["d", "z", "s", "cad", "w"]

## Oldest first: [{"t": host seconds, "lanes": {slot: {"d", "z", "s", "cad", "w"}}}].
var entries: Array[Dictionary] = []


func clear() -> void:
	entries.clear()


func is_empty() -> bool:
	return entries.is_empty()


func newest_t() -> float:
	return float(entries[-1]["t"]) if not entries.is_empty() else 0.0


## Records the lanes of the snapshot just applied to `state`, at host time `t`. A time equal to
## the newest replaces it; an earlier one (a new session) or one more than MAX_GAP_S later starts
## the history over.
func push(t: float, state: FishingState) -> void:
	if not entries.is_empty() and (t < newest_t() or t - newest_t() > MAX_GAP_S):
		entries.clear()
	var lanes := {}
	for l in state.lanes:
		lanes[l.slot] = {
			"d": l.fish.d, "z": l.fish.z, "s": l.fish.s, "cad": l.cadence_ema, "w": l.power_w
		}
	if not entries.is_empty() and is_equal_approx(t, newest_t()):
		entries[-1] = {"t": t, "lanes": lanes}
	else:
		entries.append({"t": t, "lanes": lanes})
	while entries.size() > CAPACITY:
		entries.pop_front()


## Mean host time between neighbouring entries (0.1 s at 10 Hz); 0 with fewer than two.
func mean_spacing() -> float:
	if entries.size() < 2:
		return 0.0
	return (newest_t() - float(entries[0]["t"])) / float(entries.size() - 1)


## Lane `slot`'s value `key` at host time `t`: linear between the two entries around `t`, the
## oldest entry's value before it and the newest's after it (never extrapolated); `fallback`
## when no entry has the lane.
func value_at(slot: int, key: String, t: float, fallback: float) -> float:
	var prev: Dictionary = {}
	for e in entries:
		var lanes: Dictionary = e["lanes"]
		if not lanes.has(slot):
			continue
		var et := float(e["t"])
		if et >= t:
			var now := float((lanes[slot] as Dictionary).get(key, fallback))
			if prev.is_empty():
				return now
			var pt := float(prev["t"])
			var alpha := clampf((t - pt) / (et - pt), 0.0, 1.0) if et > pt else 1.0
			var before := float(((prev["lanes"] as Dictionary)[slot] as Dictionary).get(key, now))
			return lerpf(before, now, alpha)
		prev = e
	if prev.is_empty():
		return fallback
	return float(((prev["lanes"] as Dictionary)[slot] as Dictionary).get(key, fallback))
