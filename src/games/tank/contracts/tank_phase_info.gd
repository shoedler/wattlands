class_name TankPhaseInfo
extends RefCounted
## The group's phase as the rules see it (G0 contract): the PhaseState of the rider in the lowest
## segment plus the Tank segment from PlanPhase.meta (TankPlanBuilder writes it). The rules
## never infer a segment from `kind`: the drill's skirmish is a WARMUP-kind combat segment.
##
## PlanPhase.meta (per rider and phase): {"seg": TankIds.SEG_*, "stage": int, "segment": the
## mission segment index, "engine": TankIds.ENGINE_* that rider works there, "mission": id}, and
## (v3) for open-ended segments "seg_min_s" (the segment's own min_s from the mission file); a
## phase that is the rest of a segment after a seat switch (TankSeatPlan) also carries "offset_s"
## (seconds into the segment it starts). The appended cool-down has no meta: seg is
## TankIds.SEG_COOLDOWN there.
##
## v3: `index` is the segment's index (the phase index of the unsplit plans, which have one phase
## per segment; the segment count in the cool-down), and the clock and bounds are the segment's:
## elapsed_s adds the phase's offset_s, min_s is the segment's seg_min_s, max_s and duration_s
## add the offset. So a rider whose plan was split by a seat switch reports the same segment, at
## the same time, as one whose plan was not.

var index: int = -1
## Wl.WARMUP / WORK / RECOVERY / COOLDOWN.
var kind: String = ""
## Wl.ERG / Wl.SIM of the group's rider (riders on other engines may differ).
var mode: String = ""
var seg: String = TankIds.SEG_NONE
var stage: int = 0
## The mission segment index; -1 in the cool-down.
var segment: int = -1
var elapsed_s: float = 0.0
## Nominal for open-ended phases.
var duration_s: float = 0.0
var open_ended: bool = false
var min_s: float = 0.0
var max_s: float = 0.0
var remaining_s: float = 0.0
var plan_elapsed_s: float = 0.0
## How the previous phase ended ("max_s" is an overrun of the previous segment).
var prev_ended_by: String = ""


## From the platform's PhaseState and the phase's meta ({} for the cool-down).
static func from_phase(ps: PhaseState, meta: Dictionary) -> TankPhaseInfo:
	var p := TankPhaseInfo.new()
	if ps == null:
		return p
	var offset := float(meta.get("offset_s", 0.0))
	p.index = ps.index
	p.kind = ps.kind
	p.mode = ps.mode
	p.elapsed_s = ps.elapsed_s + offset
	p.duration_s = ps.duration_s + offset
	p.open_ended = ps.open_ended
	p.min_s = float(meta.get("seg_min_s", ps.min_s))
	p.max_s = ps.max_s + offset if ps.open_ended else ps.max_s
	p.remaining_s = ps.remaining_s
	p.plan_elapsed_s = ps.plan_elapsed_s
	p.prev_ended_by = ps.prev_ended_by
	if ps.is_cooldown():
		p.seg = TankIds.SEG_COOLDOWN
	else:
		p.seg = str(meta.get("seg", TankIds.SEG_NONE))
		p.stage = int(meta.get("stage", 0))
		p.segment = int(meta.get("segment", ps.index))
		p.index = p.segment
	return p


func is_cooldown() -> bool:
	return kind == Wl.COOLDOWN or seg == TankIds.SEG_COOLDOWN


## The previous segment was ended by the platform at max_s (brief 2.4 overrun).
func overran_previous() -> bool:
	return prev_ended_by == Wl.ENDED_MAX_S


## In the first 300 s of the plan, where evade, Overpressure and haptics are off.
func in_first_window() -> bool:
	return TankConst.in_first_window(plan_elapsed_s)
