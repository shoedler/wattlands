class_name WorkoutSprintTracker
extends RefCounted
## Scores one rider's FREE sprint under the platform's sprint rule (BRIEF 3.5, 3.7):
## power >= SprintRule's threshold (1.2 x FTP). Tracks the peak, the longest streak at or
## above the threshold and the total time above it. A sprint is a hit once the rule held
## for HIT_S seconds in a row.
##
## The threshold comes from SprintRule; the streak counting is Workout's own, so scoring
## doesn't depend on SprintRule's window bookkeeping (window 0 is instantaneous, which is
## exactly this per-step check).

const HIT_S := 3.0

var phase_index: int = -1
var threshold_w: float = 240.0
var peak_w: float = 0.0
var streak_s: float = 0.0
var best_s: float = 0.0
var held_s: float = 0.0


static func create(ftp_w: float, p_phase_index: int = -1) -> WorkoutSprintTracker:
	var t := WorkoutSprintTracker.new()
	t.threshold_w = SprintRule.create(ftp_w, 0.0).threshold_w()
	t.phase_index = p_phase_index
	return t


func update(power_w: float, dt: float) -> void:
	peak_w = maxf(peak_w, power_w)
	if power_w >= threshold_w:
		streak_s += dt
		held_s += dt
		best_s = maxf(best_s, streak_s)
	else:
		streak_s = 0.0


func hit() -> bool:
	return best_s >= HIT_S - 1e-6


## {i, peak_w, best_s, held_s, hit} with whole watts and seconds to 0.1.
func result() -> Dictionary:
	return {
		"i": phase_index,
		"peak_w": int(round(peak_w)),
		"best_s": snappedf(best_s, 0.1),
		"held_s": snappedf(held_s, 0.1),
		"hit": hit(),
	}
