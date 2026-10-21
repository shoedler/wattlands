class_name WorkoutSprintTracker
extends RefCounted
## Scores one rider's FREE sprint under the platform's sprint rule (BRIEF 3.5, 3.7):
## SprintRule (window 0: power >= 1.2 x FTP each step) on the game clock. Tracks the peak,
## the longest streak the rule held (SprintRule.best_s) and the total time it held. A sprint
## is a hit once the rule held for HIT_S seconds in a row.

const HIT_S := 3.0

var phase_index: int = -1
var threshold_w: float = 240.0
var peak_w: float = 0.0
## The current streak (SprintRule.held_s), the longest one and the total time held.
var streak_s: float = 0.0
var best_s: float = 0.0
var held_s: float = 0.0
## The platform's rule; its clock is this sprint's own time, starting at 0.
var rule: SprintRule = null
var _t: float = 0.0


static func create(ftp_w: float, p_phase_index: int = -1) -> WorkoutSprintTracker:
	var t := WorkoutSprintTracker.new()
	t.rule = SprintRule.create(ftp_w, 0.0)
	t.threshold_w = t.rule.threshold_w()
	t.phase_index = p_phase_index
	# The first update only marks the start, so the sprint's first step counts as time held.
	t.rule.update(0.0, 0.0)
	return t


## One step of `dt` seconds at `power_w`.
func update(power_w: float, dt: float) -> void:
	peak_w = maxf(peak_w, power_w)
	_t += dt
	rule.update(_t, power_w)
	if rule.holds():
		held_s += dt
	streak_s = rule.held_s()
	best_s = rule.best_s()


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
