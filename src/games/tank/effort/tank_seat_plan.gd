class_name TankSeatPlan
extends RefCounted
## How a rider's trainer follows its seat (0.3.1: no seat lock; owner: rules, effort). Pure and
## static: TankDirector sends what follow() decides, the rules show its wait (mode_wait_s).
##
## A seat move lands at once (TankSeats): the stations, the seat event and the HUD follow in the
## same tick. The rider's plan (its trainer) then follows the seat:
## - Same mode (Drive, Loader and Secondaries are SIM; Gun and Lights ERG; every seat ERG 50% in a
##   checkpoint): a split at once. The rest of the current phase becomes a phase of its own for the
##   new seat (lap false, meta "offset_s" = seconds into the segment it starts, "seg_min_s" kept),
##   then every later segment for the new seat, sent with ctx.directives.split: the platform ends
##   the current phase at the end of this tick whatever its min_s, open-ended or fixed.
## - ERG <-> SIM: a split at once when the rider's last switch (any cause: a split, a segment
##   boundary) is SWITCH_GAP_S (30 s, BRIEF 4.5) or more ago. Otherwise the trainer stays in its
##   mode and switches when the 30 s are up (WAIT), unless the rest of the segment could not hold
##   the switch then (a fixed phase or max_s ending within 30 s of it with another switch): then
##   the later segments are replanned and the trainer switches at the segment's end (BOUNDARY).
##   Once the segment's objective is done the switch waits for its end too.
## - Back and forth: the trainer always heads for the rider's current seat; a move back to the
##   trainer's seat cancels a waiting switch and restores the later segments.
##
## Spacing. The platform's split validates the plan with the current phase at the length it ran
## (PlanValidator.split_model); an open phase counts at its min_s. A phase that starts with a switch
## (a cross-mode split) gets min_s >= MODEL_GAP_S, so the model never puts two switches closer than
## 30 s when they are not; a rest whose end switches gets the time left to 30 s since the model's
## last switch. check() refuses any plan the PlanValidator warns about. In real time a switch comes
## only 30 s or more after the last (follow's WAIT), and the segment's end waits for a rest's min_s
## ("Regroup"), so every real ERG <-> SIM switch is 30 s or more from the next (asserted on the
## trainer's trace by the simulations).

## The shortest rest phase (a min_s must be > 0): one tick.
const MIN_REST_S := Wl.SIM_DT
## A rider's ERG <-> SIM switches are at least this far apart in real time (BRIEF 4.5).
const SWITCH_GAP_S := TankConst.SWITCH_GAP_S
## The PlanValidator warns at switches closer than this in its min_s model (BRIEF 4.5).
const MODEL_GAP_S := 30.0
const EPS := 1e-6

## follow() actions.
const FOLLOW_NONE := 0
const FOLLOW_SPLIT := 1
const FOLLOW_WAIT := 2
const FOLLOW_BOUNDARY := 3
## mode_wait_s when the switch waits for the segment's end.
const WAIT_SEGMENT_END := -1.0


## The replan's remaining phases for a rider in phase `cur_index` of `plan` moving to `engine`, or
## null when there is none. `split`: the rest of the current segment first, starting `offset_s`
## seconds into the segment, the current phase closed `elapsed_s` into itself; else only the later
## segments (null when there are none).
static func tail(
	content: TankContent,
	plan: EffortPlan,
	cur_index: int,
	engine: String,
	split: bool,
	offset_s: float,
	elapsed_s: float = 0.0
) -> EffortPlan:
	if content == null or plan == null or cur_index < 0 or cur_index >= plan.size():
		return null
	var cur := plan.phase(cur_index)
	var seg := int(cur.meta.get("segment", cur_index))
	var segs := content.segments()
	if seg < 0 or seg >= segs.size():
		return null
	var out := EffortPlan.new()
	if split:
		var rest := _rest_phase(
			content, plan, cur_index, segs[seg], seg, engine, offset_s, elapsed_s
		)
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
## and with the cool-down appended every ERG <-> SIM switch is MODEL_GAP_S or more from the next,
## open phases counted at their min_s and at their max_s. With `cur_index` >= 0 it is a split: phase
## `cur_index` counts as `elapsed_s` long (what DirectiveSink.split validates).
static func check(whole_plan: EffortPlan, cur_index: int = -1, elapsed_s: float = 0.0) -> bool:
	if whole_plan == null or whole_plan.size() == 0:
		return false
	var model := whole_plan
	if cur_index >= 0:
		model = PlanValidator.split_model(whole_plan, cur_index, elapsed_s)
	var v := PlanValidator.validate(model)
	if not bool(v["ok"]) or not (v["warnings"] as Array).is_empty():
		return false
	var fin := PlanValidator.finalize(model)
	if fin == null:
		return false
	return (
		min_switch_gap(fin, false) >= MODEL_GAP_S - EPS
		and min_switch_gap(fin, true) >= MODEL_GAP_S - EPS
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


## The mode a rider on `engine` rides in segment `segment` of the content ("" outside it).
static func seat_mode(content: TankContent, segment: int, engine: String) -> String:
	if content == null or engine == "":
		return ""
	var segs := content.segments()
	if segment < 0 or segment >= segs.size():
		return ""
	var entry := content.plan_entry(engine, str(segs[segment].get("type", "")))
	return str(entry.get("mode", Wl.ERG))


## The planned ERG target (% FTP) of `engine` in segment `segment` (0 for a SIM seat or outside).
static func seat_target_pct(content: TankContent, segment: int, engine: String) -> float:
	if content == null or engine == "":
		return 0.0
	var segs := content.segments()
	if segment < 0 or segment >= segs.size():
		return 0.0
	var entry := content.plan_entry(engine, str(segs[segment].get("type", "")))
	if str(entry.get("mode", Wl.ERG)) != Wl.ERG:
		return 0.0
	return float(entry.get("target_pct", 0.0))


## What the trainer of rider `ri` (its plan, phase, elapsed and offset) does for the rider sitting
## on `seat`, `now_s` game seconds, its last ERG <-> SIM switch at `last_switch_s`; `hold_end`: the
## segment is ending (its objective done, or this tick). Returns {"action": FOLLOW_*, "plan": the
## remaining phases to send (split or replan) or null, "wait_s": seconds until the trainer switches
## (0 none, WAIT_SEGMENT_END at the segment's end), "mode_to": the mode it will switch to ("" none)}.
## `allow_split` false (the segment ends this tick): never a split, only the later segments.
static func follow(
	content: TankContent,
	ri: TankRiderInput,
	seat: String,
	last_switch_s: float,
	now_s: float,
	hold_end: bool,
	allow_split: bool = true
) -> Dictionary:
	var out := {"action": FOLLOW_NONE, "plan": null, "wait_s": 0.0, "mode_to": ""}
	var plan := ri.plan
	var idx := ri.phase_index
	if content == null or plan == null or seat == "" or idx < 0 or idx >= plan.size():
		return out
	var cur := plan.phase(idx)
	if cur.kind == Wl.COOLDOWN or ri.phase_kind == Wl.COOLDOWN:
		return out
	var seg := int(cur.meta.get("segment", idx))
	var mode := seat_mode(content, seg, seat)
	if mode == "":
		return out
	var elapsed := ri.phase_elapsed_s
	var offset := float(cur.meta.get("offset_s", 0.0))
	if str(cur.meta.get("engine", "")) == seat:
		# The trainer follows the seat; the later segments must too (a move and its way back).
		if _later_differ(plan, idx, seat):
			var later := tail(content, plan, idx, seat, false, 0.0)
			if later != null and check(whole(plan, idx, later)):
				out["action"] = FOLLOW_BOUNDARY
				out["plan"] = later
		return out
	var cross := mode != cur.mode
	if cross:
		out["mode_to"] = mode
		var since := now_s - last_switch_s
		if not hold_end and since < SWITCH_GAP_S - EPS:
			var wait := SWITCH_GAP_S - since
			var later_rest := tail(
				content, plan, idx, seat, true, offset + elapsed + wait, elapsed + wait
			)
			if later_rest != null:
				out["action"] = FOLLOW_WAIT
				out["wait_s"] = wait
				return out
			# Too close to the last switch now, and no room for the rest then: the segment's end.
			return _boundary(content, plan, idx, seat, cross, out)
	if allow_split and not (cross and hold_end):
		var rest := tail(content, plan, idx, seat, true, offset + elapsed + Wl.SIM_DT, elapsed)
		if rest != null and check(whole(plan, idx, rest), idx, elapsed):
			out["action"] = FOLLOW_SPLIT
			out["plan"] = rest
			out["mode_to"] = ""
			return out
	return _boundary(content, plan, idx, seat, cross, out)


## The later segments for `seat`, the trainer switching at the segment's end.
static func _boundary(
	content: TankContent, plan: EffortPlan, idx: int, seat: String, cross: bool, out: Dictionary
) -> Dictionary:
	if not _later_differ(plan, idx, seat):
		out["wait_s"] = WAIT_SEGMENT_END if cross else 0.0
		return out
	var later := tail(content, plan, idx, seat, false, 0.0)
	if later == null or not check(whole(plan, idx, later)):
		out["mode_to"] = ""
		return out
	out["action"] = FOLLOW_BOUNDARY
	out["plan"] = later
	out["wait_s"] = WAIT_SEGMENT_END if cross else 0.0
	return out


## True when a plan phase after `idx` of `plan` (before the cool-down) is for another seat.
static func _later_differ(plan: EffortPlan, idx: int, seat: String) -> bool:
	for i in range(idx + 1, plan.size()):
		var ph := plan.phase(i)
		if ph.kind == Wl.COOLDOWN:
			break
		if str(ph.meta.get("engine", seat)) != seat:
			return true
	return false


# --- Internals ------------------------------------------------------------------------------------


## The rest of segment `s` (index `seg`) for `engine` from `offset_s` seconds into it, the current
## phase closed `elapsed_s` into itself; null when it cannot fit (see the class doc).
static func _rest_phase(
	content: TankContent,
	plan: EffortPlan,
	cur_index: int,
	s: Dictionary,
	seg: int,
	engine: String,
	offset_s: float,
	elapsed_s: float
) -> PlanPhase:
	var ph := TankPlanBuilder.phase_for(content, s, engine, seg)
	var split_switch := plan.phase(cur_index).mode != ph.mode
	var end_switch := _next_mode(content, s, seg, engine) != ph.mode
	var need := MIN_REST_S
	if split_switch:
		need = MODEL_GAP_S
	elif end_switch:
		need = maxf(need, _spacing_need(plan, cur_index, elapsed_s))
	if ph.open_ended:
		# A mission's plan_min_s (free roam) stands for the segment's own min_s here too.
		var seg_min := float(s.get("plan_min_s", s.get("min_s", ph.min_s)))
		need = maxf(need, seg_min - offset_s)
		var max_s := float(s.get("max_s", ph.max_s)) - offset_s
		if max_s < need - EPS:
			return null
		ph.min_s = need
		ph.max_s = max_s
		ph.duration_s = maxf(float(s.get("duration_s", 0.0)) - offset_s, 0.0)
	else:
		var dur := float(s.get("duration_s", ph.duration_s)) - offset_s
		if dur < MIN_REST_S - EPS or (split_switch and end_switch and dur < need - EPS):
			return null
		if ph.mode == Wl.ERG and ph.ramp_to_pct != PlanPhase.NONE:
			ph.target_pct = ph.planned_pct_at(offset_s)
		ph.duration_s = dur
	ph.lap = false
	var meta := ph.meta.duplicate()
	meta["offset_s"] = offset_s
	ph.meta = meta
	return ph


## The mode a rider on `engine` rides after segment `s` (index `seg`): the next segment's, or the
## cool-down's ERG after the last.
static func _next_mode(content: TankContent, _s: Dictionary, seg: int, engine: String) -> String:
	var segs := content.segments()
	if seg + 1 >= segs.size():
		return Wl.ERG
	var entry := content.plan_entry(engine, str(segs[seg + 1].get("type", "")))
	return str(entry.get("mode", Wl.ERG))


## How long a rest that does not switch at its start must be in the model so that a switch at its
## end sits MODEL_GAP_S after the model's last switch: phases before `cur_index` at their min_s or
## duration, phase `cur_index` closed at `elapsed_s`.
static func _spacing_need(plan: EffortPlan, cur_index: int, elapsed_s: float) -> float:
	var t := 0.0
	var last := -INF
	var prev := ""
	for i in cur_index + 1:
		var ph := plan.phase(i)
		if prev != "" and ph.mode != prev:
			last = t
		prev = ph.mode
		t += elapsed_s if i == cur_index else _len(ph, false)
	return maxf(MODEL_GAP_S - (t - last), 0.0)


static func _len(ph: PlanPhase, use_max: bool) -> float:
	if ph.open_ended:
		return ph.max_s if use_max else ph.min_s
	return ph.duration_s
