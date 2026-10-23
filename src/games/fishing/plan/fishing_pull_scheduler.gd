class_name FishingPullScheduler
extends RefCounted
## The Fight's ERG directives (brief 2.3 "Load changes"): pull changes, runs and jumps, pauses,
## all pure over one lane's FishingPullState. G0 stub with the frozen API; fish-plan owns this
## file and implements it in G1. FishingRules calls, for the lane in a Fight:
##   begin(ps, slot, t, ftp_w, rng)            once at the Fight's start
##   start_run(ps, slot, k, t, ftp_w) -> bool   when run k (0-based) comes due (false: skipped)
##   set_staggered(ps, active, t)               when a rescue or AFK starts or ends
##   step(ps, slot, t, ftp_w, rng) -> Array     every tick: EffortDirective dictionaries to send
##   end(ps)                                    at the Fight's end
## Every directive is {"mode": "ERG", "target_pct", "duration_s", "reason": "pull" | "run" |
## "jump", "source": "fishing"} inside the slot's range_pct; none is sent while staggered.


static func begin(
	ps: FishingPullState, slot: FishingPlanSlot, t: float, _ftp_w: float, _rng: FishingRandom
) -> void:
	ps.base_pct = slot.base_pct
	ps.target_pct = slot.base_pct
	ps.next_change_t = t + FishingConst.PULL_CHANGE_MAX_S
	ps.queue.clear()
	ps.run_active = false
	ps.staggered = false
	ps.above_105_run_s = 0.0
	ps.above_105_fight_s = 0.0


static func start_run(
	_ps: FishingPullState, _slot: FishingPlanSlot, _k: int, _t: float, _ftp_w: float
) -> bool:
	return false


static func set_staggered(ps: FishingPullState, active: bool, t: float) -> void:
	ps.staggered = active
	if not active:
		ps.paused_until_t = t + FishingConst.PULL_RESUME_AFTER_STAGGER_S


static func step(
	_ps: FishingPullState, _slot: FishingPlanSlot, _t: float, _ftp_w: float, _rng: FishingRandom
) -> Array:
	return []


static func end(ps: FishingPullState) -> void:
	ps.queue.clear()
	ps.run_active = false
