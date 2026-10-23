class_name FishingRulesPull
extends RefCounted
## FishingRules' door to FishingPullScheduler (fish-plan's file). The frozen API (begin,
## start_run, set_staggered, step, end) is called directly. Two functions fish-plan adds in G1,
## init_lane(ps, seed, slot_index) and run_blocked_by_gap(ps, slot, t) -> bool, are looked up
## once on the scheduler script and called when present; before that merge the fallbacks below
## stand in, so the rules parse and behave on both sides of it:
##   init_lane            nothing (the lane keeps its own pull stream, FishingLaneState.pull_rng)
##   run_blocked_by_gap   a jump waits until slot.run_min_gap_s has passed since the last one

static var _probed: bool = false
static var _has_init_lane: bool = false
static var _has_gap: bool = false


static func _probe() -> void:
	if _probed:
		return
	var script: Script = FishingPullScheduler
	_has_init_lane = script.has_method("init_lane")
	_has_gap = script.has_method("run_blocked_by_gap")
	_probed = true


## Seeds the lane's pull state (fish-plan's init_lane) when the scheduler has it.
static func init_lane(ps: FishingPullState, seed: int, slot_index: int) -> void:
	_probe()
	if _has_init_lane:
		var script: Script = FishingPullScheduler
		script.call("init_lane", ps, seed, slot_index)


## True while a jump that came due must still wait for the minimum gap after the last one.
static func run_blocked_by_gap(
	ps: FishingPullState, slot: FishingPlanSlot, t: float, fish: FishingFishState
) -> bool:
	_probe()
	if _has_gap:
		var script: Script = FishingPullScheduler
		return bool(script.call("run_blocked_by_gap", ps, slot, t))
	return slot.run_min_gap_s > 0.0 and t - fish.last_jump_t < slot.run_min_gap_s


static func begin(
	ps: FishingPullState, slot: FishingPlanSlot, t: float, l: FishingLaneState
) -> void:
	FishingPullScheduler.begin(ps, slot, t, l.ftp, l.pull_rng)


static func start_run(
	ps: FishingPullState, slot: FishingPlanSlot, k: int, t: float, ftp_w: float
) -> bool:
	return FishingPullScheduler.start_run(ps, slot, k, t, ftp_w)


static func set_staggered(ps: FishingPullState, active: bool, t: float) -> void:
	FishingPullScheduler.set_staggered(ps, active, t)


static func step(
	ps: FishingPullState, slot: FishingPlanSlot, t: float, l: FishingLaneState
) -> Array:
	return FishingPullScheduler.step(ps, slot, t, l.ftp, l.pull_rng)


static func end(ps: FishingPullState) -> void:
	FishingPullScheduler.end(ps)
