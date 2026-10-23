class_name FishingSnapHistory
extends RefCounted
## Client: the lanes of the last few snapshots keyed by the host's game time (the snapshot's tick
## x Wl.SIM_DT), so the view draws other lanes between two snapshots with its render clock behind
## the newest by mean_spacing() (Workout's WorkoutSnapHistory pattern; GAME_SDK 12). FishingGame
## calls push(t, state) once per applied snapshot; the view only reads. G0 stub with the frozen
## API; the view builder owns this file.

const CAPACITY := 8
const MAX_GAP_S := 1.5

## Oldest first: [{"t": host seconds, "lanes": {slot: {"d", "z", "s", "cad", "w"}}}].
var entries: Array[Dictionary] = []


func clear() -> void:
	entries.clear()


func is_empty() -> bool:
	return entries.is_empty()


func newest_t() -> float:
	return float(entries[-1]["t"]) if not entries.is_empty() else 0.0


## Records the lanes of the snapshot just applied to `state`, at host time `t`.
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
