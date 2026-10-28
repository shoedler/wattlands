class_name TankSeatPlan
extends RefCounted
## The replan of a seat switch (v3 brief "Seat choice and switching"; owner: rules, effort). Pure
## and static: the rules use it to judge a seat intent, the director to build the replan it sends.
##
## A move lands one of two ways:
## - Split: the rest of the current segment becomes a phase of its own for the new seat (lap false,
##   meta "offset_s" = seconds into the segment it starts, "seg_min_s" kept), then every later
##   segment for the new seat. The director sends it with ctx.directives.replan and ends the
##   current phase with end_phase in the same tick, so the new seat's mode and targets apply from
##   the next tick (the platform ramps an ERG <-> SIM switch, BRIEF 4.5). Only an open-ended phase
##   past its own min_s can end early, so a split waits for that.
## - At the boundary: every later segment for the new seat; the move lands when the current phase
##   ends (a fixed phase such as the depot, an open-ended one before its min_s, or the segment's
##   end coming first).
##
## Spacing (BRIEF 4.5, the brief's 60 s): the PlanValidator models an open-ended phase at its min_s,
## so the rest phase's min_s is at least what keeps every ERG <-> SIM switch in that model 60 s from
## the one before it (60 s when the split itself switches modes), and at least the segment's own
## min_s left. Real time is never shorter than the model (a phase lasts at least its min_s), and the
## seat lock keeps every move 60 s or more after the rider's last plan boundary. A move whose plan
## fails check() is refused: the PlanValidator must pass it with no warning, and every switch must
## sit 60 s from the next, with open phases at their min_s and at their max_s.

## The shortest rest phase (a min_s must be > 0): one tick.
const MIN_REST_S := Wl.SIM_DT
## Every ERG <-> SIM switch of a rider is at least this far from the next (brief v3, BRIEF 4.5).
const SWITCH_GAP_S := TankConst.SEAT_LOCK_S
const EPS := 1e-6


## The replan's remaining phases for a rider in phase `cur_index` of `plan` moving to `engine`, or
## null when there is none. `split`: the rest of the current segment first, starting `offset_s`
## seconds into it (the current phase must be open-ended); else only the later segments (null when
## there are none: the move could only land in the cool-down).
static func tail(
	content: TankContent,
	plan: EffortPlan,
	cur_index: int,
	engine: String,
	split: bool,
	offset_s: float
) -> EffortPlan:
	if content == null or plan == null or cur_index < 0 or cur_index >= plan.size():
		return null
	var cur := plan.phase(cur_index)
	var seg := int(cur.meta.get("segment", cur_index))
	var segs := content.segments()
	var out := EffortPlan.new()
	if split:
		if not cur.open_ended or seg < 0 or seg >= segs.size():
			return null
		var rest := _rest_phase(content, plan, cur_index, segs[seg], seg, engine, offset_s)
		if rest == null:
			return null
		out.add(rest)
	for i in range(seg + 1, segs.size()):
		out.add(TankPlanBuilder.phase_for(content, segs[i], engine, i))
	return out if out.size() > 0 else null


## The plan the platform holds after the replan: phases 0..cur_index of `plan` and then `rest`.
static func whole(plan: EffortPlan, cur_index: int, rest: EffortPlan) -> EffortPlan:
	return PlanValidator.spliced(plan, cur_index, rest)


## True when `whole_plan` (no cool-down) may be sent: the PlanValidator passes it with no warning,
## and with the cool-down appended every ERG <-> SIM switch is SWITCH_GAP_S or more from the next,
## open phases counted at their min_s and at their max_s.
static func check(whole_plan: EffortPlan) -> bool:
	if whole_plan == null or whole_plan.size() == 0:
		return false
	var v := PlanValidator.validate(whole_plan)
	if not bool(v["ok"]) or not (v["warnings"] as Array).is_empty():
		return false
	var fin := PlanValidator.finalize(whole_plan)
	if fin == null:
		return false
	return (
		min_switch_gap(fin, false) >= SWITCH_GAP_S - EPS
		and min_switch_gap(fin, true) >= SWITCH_GAP_S - EPS
	)


## The shortest time between two ERG <-> SIM switches of `plan` (INF with fewer than two), every
## open phase at its min_s (or its max_s with `use_max`).
static func min_switch_gap(plan: EffortPlan, use_max: bool) -> float:
	var t := 0.0
	var last := -INF
	var gap := INF
	var mode := ""
	for i in plan.size():
		var ph := plan.phase(i)
		if mode != "" and ph.mode != mode:
			gap = minf(gap, t - last)
			last = t
		mode = ph.mode
		t += _len(ph, use_max)
	return gap


## The move's replan now: {"plan": the remaining phases, "split": bool} for a rider in phase
## `cur_index` of `plan`, `elapsed_s` into it (`offset_s` = the phase's own offset into its
## segment), moving to `engine`; split when `split_now` and the split passes check(), else the
## boundary landing when that passes; {} when neither does.
static func move_now(
	content: TankContent,
	plan: EffortPlan,
	cur_index: int,
	elapsed_s: float,
	offset_s: float,
	engine: String,
	split_now: bool
) -> Dictionary:
	if split_now:
		var rest := tail(content, plan, cur_index, engine, true, offset_s + elapsed_s + Wl.SIM_DT)
		if rest != null and check(whole(plan, cur_index, rest)):
			return {"plan": rest, "split": true}
	var later := tail(content, plan, cur_index, engine, false, 0.0)
	if later != null and check(whole(plan, cur_index, later)):
		return {"plan": later, "split": false}
	return {}


## True when a move to `engine` can land at all from phase `cur_index` (open-ended `open_ended`,
## `elapsed_s` into it, min_s `min_s`, offset `offset_s`): a split now or once the phase reaches
## its min_s, or at the boundary.
static func can_move(
	content: TankContent,
	plan: EffortPlan,
	cur_index: int,
	open_ended: bool,
	elapsed_s: float,
	min_s: float,
	offset_s: float,
	engine: String
) -> bool:
	if open_ended:
		var at := maxf(elapsed_s, min_s)
		if not move_now(content, plan, cur_index, at, offset_s, engine, true).is_empty():
			return true
	return not move_now(content, plan, cur_index, elapsed_s, offset_s, engine, false).is_empty()


# --- Internals ------------------------------------------------------------------------------------


## The rest of segment `s` (index `seg`) for `engine` from `offset_s` seconds into it, with the
## min_s that keeps the switch spacing (see the class doc); null when it cannot fit before max_s.
static func _rest_phase(
	content: TankContent,
	plan: EffortPlan,
	cur_index: int,
	s: Dictionary,
	seg: int,
	engine: String,
	offset_s: float
) -> PlanPhase:
	var ph := TankPlanBuilder.phase_for(content, s, engine, seg)
	if not ph.open_ended:
		return null
	var seg_min := float(s.get("min_s", ph.min_s))
	var seg_max := float(s.get("max_s", ph.max_s))
	var max_s := seg_max - offset_s
	var need := maxf(seg_min - offset_s, MIN_REST_S)
	need = maxf(need, _spacing_need(plan, cur_index, ph.mode))
	if max_s < need - EPS:
		return null
	ph.min_s = need
	ph.max_s = max_s
	ph.duration_s = maxf(float(s.get("duration_s", 0.0)) - offset_s, 0.0)
	ph.lap = false
	var meta := ph.meta.duplicate()
	meta["offset_s"] = offset_s
	ph.meta = meta
	return ph


## How long the rest phase must be (in the min_s model) so that a switch at its end would sit
## SWITCH_GAP_S after the last switch before it: SWITCH_GAP_S when the split itself switches modes
## (from phase `cur_index`'s mode to `mode`), else what is left of it since the last switch.
static func _spacing_need(plan: EffortPlan, cur_index: int, mode: String) -> float:
	var t := 0.0
	var last := -INF
	var prev := ""
	for i in cur_index + 1:
		var ph := plan.phase(i)
		if prev != "" and ph.mode != prev:
			last = t
		prev = ph.mode
		t += _len(ph, false)
	if mode != prev:
		return SWITCH_GAP_S
	return maxf(SWITCH_GAP_S - (t - last), 0.0)


static func _len(ph: PlanPhase, use_max: bool) -> float:
	if ph.open_ended:
		return ph.max_s if use_max else ph.min_s
	return ph.duration_s
