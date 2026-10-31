class_name WorkoutSnapHistory
extends SnapHistory
## Client: every rider's distance in the last few snapshots, keyed by the host's game time
## (the snapshot's tick x Wl.SIM_DT), so the ride view can draw the other riders between two
## snapshots (BRIEF 5.1; 100 ms behind at 10 Hz like NetSession, longer when snapshots arrive
## less often: mean_spacing()). WorkoutGame.apply_snapshot pushes
## one entry per snapshot it applies; the view only reads it. Times come from the host's
## ticks, never from a clock.

## Rows, oldest first: {"t": host seconds, "d": {peer: distance_m}}.


## Records the distances of the snapshot just applied to `state`, at host time `t`.
func push(t: float, state: WorkoutState) -> void:
	var d := {}
	for peer: int in state.order:
		d[peer] = state.rider(peer).distance_m()
	add(t, {"d": d})


## `peer`'s distance at host time `t`: linear between the two entries around `t`, the oldest
## entry's value before it and the newest's after it (never extrapolated); `fallback` when no
## entry has the peer.
func distance_at(peer: int, t: float, fallback: float) -> float:
	return float(sample(t, "d", peer, fallback))
