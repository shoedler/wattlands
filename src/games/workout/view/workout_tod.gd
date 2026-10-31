class_name WorkoutTod
extends RefCounted
## The ride's one morning: session progress picks the time-of-day row of the LUT.

const ROWS := 32


## Share of the session done, 0 for an empty timeline.
static func progress(state: WorkoutState) -> float:
	var total := state.total_s()
	if total <= 0.0:
		return 0.0
	return clampf(state.plan_t / total, 0.0, 1.0)


static func row(p: float) -> int:
	return floori(clampf(p, 0.0, 1.0) * float(ROWS - 1))
