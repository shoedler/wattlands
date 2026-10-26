class_name FishingSnapHistory
extends RefCounted
## The riders of the last few states keyed by the game time (tick x Wl.SIM_DT), so the view
## draws every boat and fish between two of them: on a client between snapshots with its render
## clock behind the newest by mean_spacing() (GAME_SDK 12), on the host and in SOLO between sim
## steps one step behind. push(t, state) records a state (the view pushes every frame; a push at
## the newest time replaces it); the view reads value_at().

const CAPACITY := 8
## A snapshot more than this after the newest (a rejoin, a long stall) starts the history over.
const MAX_GAP_S := 1.5
## The values kept per rider: boat x (m), signed trim (deg, bow up positive), wake, braking
## (0..1), the fish's dx and depth (m), the wobbler's dx and depth (m), EMA cadence (rpm), heave
## (m, up positive).
const KEYS: Array[String] = [
	"x", "pitch", "wake", "brake", "fdx", "fz", "ldx", "lz", "cad", "heave"
]

## Oldest first: [{"t": host seconds, "r": {slot: {key: value}}}].
var entries: Array[Dictionary] = []


func clear() -> void:
	entries.clear()


func is_empty() -> bool:
	return entries.is_empty()


func newest_t() -> float:
	return float(entries[-1]["t"]) if not entries.is_empty() else 0.0


## The values KEYS names for rider `r`.
static func values_of(r: FishingRiderState) -> Dictionary:
	return {
		"x": r.x_m,
		"pitch": r.pitch_deg,
		"wake": r.wake,
		"brake": r.brake,
		"fdx": r.fish_dx(),
		"fz": r.fish.depth_m(),
		"ldx": r.lure_dx,
		"lz": r.lure_depth,
		"cad": r.cadence_ema,
		"heave": r.heave_m,
	}


## Records the riders of the snapshot just applied to `state`, at host time `t`. A time equal to
## the newest replaces it; an earlier one or one more than MAX_GAP_S later starts over.
func push(t: float, state: FishingState) -> void:
	if not entries.is_empty() and (t < newest_t() or t - newest_t() > MAX_GAP_S):
		entries.clear()
	var rows := {}
	for r in state.riders:
		rows[r.slot] = values_of(r)
	if not entries.is_empty() and is_equal_approx(t, newest_t()):
		entries[-1] = {"t": t, "r": rows}
	else:
		entries.append({"t": t, "r": rows})
	while entries.size() > CAPACITY:
		entries.pop_front()


## Mean host time between neighbouring entries (0.1 s at 10 Hz); 0 with fewer than two.
func mean_spacing() -> float:
	if entries.size() < 2:
		return 0.0
	return (newest_t() - float(entries[0]["t"])) / float(entries.size() - 1)


## Rider `slot`'s value `key` at host time `t`: linear between the two entries around `t`, the
## oldest entry's before it and the newest's after it (never extrapolated); `fallback` when no
## entry has the rider.
func value_at(slot: int, key: String, t: float, fallback: float) -> float:
	var prev: Dictionary = {}
	for e in entries:
		var rows: Dictionary = e["r"]
		if not rows.has(slot):
			continue
		var et := float(e["t"])
		if et >= t:
			var now := float((rows[slot] as Dictionary).get(key, fallback))
			if prev.is_empty():
				return now
			var pt := float(prev["t"])
			var alpha := clampf((t - pt) / (et - pt), 0.0, 1.0) if et > pt else 1.0
			var before := float(((prev["r"] as Dictionary)[slot] as Dictionary).get(key, now))
			return lerpf(before, now, alpha)
		prev = e
	if prev.is_empty():
		return fallback
	return float(((prev["r"] as Dictionary)[slot] as Dictionary).get(key, fallback))
