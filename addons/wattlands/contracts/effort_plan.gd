class_name EffortPlan
extends RefCounted
## A rider's plan for the whole session: an ordered list of PlanPhase (BRIEF 3.6).
## Contract, frozen after W0.
##
## Games return one plan per peer from `build_effort_plans()`. The PlanValidator
## checks it against BRIEF 4.6 and the warm-up limits, then appends the 3-minute
## cool-down at 50% FTP (`cooldown_appended` becomes true). A game never writes its
## own cool-down.

var phases: Array[PlanPhase] = []
## Set by the PlanValidator once it appended the cool-down phase.
var cooldown_appended: bool = false


static func of(p_phases: Array) -> EffortPlan:
	var plan := EffortPlan.new()
	for p: Variant in p_phases:
		if p is PlanPhase:
			plan.phases.append(p)
	return plan


func add(phase: PlanPhase) -> EffortPlan:
	phases.append(phase)
	return self


func size() -> int:
	return phases.size()


func phase(index: int) -> PlanPhase:
	if index < 0 or index >= phases.size():
		return null
	return phases[index]


## Sum of nominal phase lengths (open-ended phases count their duration_s).
func nominal_length_s() -> float:
	var total := 0.0
	for p in phases:
		total += p.duration_s
	return total


## Sum of worst-case phase lengths (open-ended phases count max_s).
func max_length_s() -> float:
	var total := 0.0
	for p in phases:
		total += p.worst_case_length_s()
	return total


## Index of the appended cool-down phase, or -1.
func cooldown_index() -> int:
	if cooldown_appended and not phases.is_empty():
		return phases.size() - 1
	return -1


func duplicate_plan() -> EffortPlan:
	return EffortPlan.from_dict(to_dict())


func to_dict() -> Dictionary:
	var arr: Array = []
	for p in phases:
		arr.append(p.to_dict())
	return {"phases": arr, "cooldown_appended": cooldown_appended}


static func from_dict(d: Dictionary) -> EffortPlan:
	var plan := EffortPlan.new()
	var arr: Variant = d.get("phases", [])
	if arr is Array:
		for pd: Variant in arr:
			if pd is Dictionary:
				plan.phases.append(PlanPhase.from_dict(pd))
	plan.cooldown_appended = bool(d.get("cooldown_appended", false))
	return plan
