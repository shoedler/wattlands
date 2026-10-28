class_name TankSegments
extends RefCounted
## The crew's place in the mission (brief 2.3 segment table, 2.4 objectives; owner: rules): follows
## the group's phase, sets each segment up (TankEncounters), tracks the objectives and the hold
## before min_s ("Regroup"), and answers the depot drill questions. The director ends the phase
## (ADR "Who calls end_phase"); the platform cuts it at max_s, which plays as an overrun here.


## Follows the group's phase: on a new segment records the previous one's HP, counts an overrun,
## credits clean stages, heals at checkpoints, sets the world up, and raises the `segment` event.
static func track(
	state: TankState, inputs: TankInputs, aux: TankAux, events: Array[Dictionary]
) -> void:
	var ph := inputs.phase
	var sg := state.seg
	if ph.index != sg.phase_index and ph.index >= 0:
		if sg.phase_index >= 0 and sg.phase_index >= state.score.hp_by_segment.size():
			state.score.hp_by_segment.append(ceili(state.hull.hp))
		var prev_seg := sg.seg
		sg.phase_index = ph.index
		sg.segment_index = ph.segment
		sg.seg = ph.seg
		sg.stage = ph.stage
		sg.kind = ph.kind
		sg.objective_done = false
		sg.regroup = false
		sg.overrun = ph.overran_previous()
		sg.next_encounter = 0
		if not state.roam.active:
			# Free roam keeps one continuous road (TankRoam): the world never resets.
			state.hull.distance_m = 0.0
			state.hull.x_px = 0.0
		var s: Dictionary = state.content.segment(ph.segment) if state.content != null else {}
		sg.length_m = float(s.get("length_m", 0.0))
		if sg.overrun:
			var prev_stage := _prev_stage(state, ph.segment)
			state.score.overruns += 1
			if prev_stage >= 1 and prev_stage <= 3:
				state.score.stage_overrun[prev_stage - 1] = true
			events.append(TankEvents.overrun(_prev_seg(state, ph.segment), prev_stage))
		if (
			sg.seg == TankIds.SEG_CHECKPOINT
			and sg.stage >= 1
			and sg.stage <= 3
			and not state.score.stage_overrun[sg.stage - 1]
		):
			state.score.stages_clean += 1
		if sg.seg == TankIds.SEG_COOLDOWN and state.outcome == "":
			state.outcome = _outcome(state)
		if sg.seg == TankIds.SEG_CHECKPOINT:
			var bonus := state.content.num("tanks", "hull.checkpoint_hp", 20.0)
			state.hull.hp_max += bonus
			state.hull.hp = minf(state.hull.hp + bonus, state.hull.hp_max)
		state.gun_line.active = sg.seg == TankIds.SEG_GUN_LINE
		events.append(TankEvents.segment(ph.index, sg.seg, sg.stage))
		TankEncounters.begin(state, aux, prev_seg, sg.overrun, events)
	sg.elapsed_s = ph.elapsed_s
	sg.min_s = ph.min_s
	sg.max_s = ph.max_s
	sg.open_ended = ph.open_ended
	sg.plan_elapsed_s = ph.plan_elapsed_s


## The mission's result once the plan's last segment ended: victory when the Behemoth died,
## withdrawn when a mission with a boss ended without its death, complete without a boss (drill),
## time_up for a free roam (brief 2.10).
static func _outcome(state: TankState) -> String:
	if state.roam.active:
		return TankIds.OUTCOME_TIME_UP
	if state.score.behemoth_killed:
		return TankIds.OUTCOME_VICTORY
	if state.content != null:
		for s: Variant in state.content.segments():
			if str(s.get("type", "")) == TankIds.SEG_BOSS:
				return TankIds.OUTCOME_WITHDRAWN
	return TankIds.OUTCOME_COMPLETE


## The segment before mission segment `segment` (the cool-down's is the mission's last).
static func _prev(state: TankState, segment: int) -> Dictionary:
	if state.content == null:
		return {}
	var n := state.content.segments().size()
	var i: int = (n - 1) if segment < 0 else (segment - 1)
	return state.content.segment(i)


static func _prev_seg(state: TankState, segment: int) -> String:
	return str(_prev(state, segment).get("type", ""))


static func _prev_stage(state: TankState, segment: int) -> int:
	return int(_prev(state, segment).get("stage", 0))


## Objectives (brief 2.4): an Advance is done at the halt line, a gun line when every gun fell,
## the boss when the Behemoth died. Once done the tank holds ("Regroup") until min_s, and (v3) until
## every rider of the segment may end its phase: a rider whose seat switch split the segment has the
## rest of it as a phase whose own min_s keeps its next mode change 60 s away (TankSeatPlan).
static func objectives(state: TankState, inputs: TankInputs = null) -> void:
	var sg := state.seg
	if not sg.objective_done and sg.length_m >= 0.0:
		match sg.seg:
			TankIds.SEG_ADVANCE:
				sg.objective_done = (
					state.hull.distance_m >= sg.length_m - 1e-6 and sg.length_m > 0.0
				)
			TankIds.SEG_GUN_LINE:
				sg.objective_done = (
					state.gun_line.guns_total > 0 and state.gun_line.guns_left <= 0
				)
			TankIds.SEG_BOSS:
				sg.objective_done = state.boss.phase == TankIds.BOSS_DEAD
	sg.regroup = (sg.objective_done and (sg.elapsed_s < sg.min_s or not riders_may_end(inputs)))


## True when every rider in the group's segment is past its own phase's min_s (v3: a split phase
## may hold the segment's end; TankDirector waits for it). True without inputs.
static func riders_may_end(inputs: TankInputs) -> bool:
	if inputs == null:
		return true
	for ri in inputs.riders:
		if ri.segment != inputs.phase.segment or not ri.phase_open_ended:
			continue
		if ri.phase_elapsed_s < ri.phase_min_s - 1e-6:
			return false
	return true


# --- Depot drills -------------------------------------------------------------------------------


## The depot drill running now ("drive", "aim", "fire"), or "" outside the depot's drill windows.
static func drill_at(state: TankState) -> String:
	if state.seg.seg != TankIds.SEG_DEPOT:
		return ""
	var aux := TankAux.of(state)
	for d: Variant in aux.drills:
		if (
			state.seg.elapsed_s >= float(d.get("from_s", 0.0))
			and state.seg.elapsed_s < float(d.get("to_s", 0.0))
		):
			return str(d.get("drill", ""))
	return ""


## The depot's fire drill: each loaded shell fires at a drill wreck.
static func fire_drill(state: TankState) -> bool:
	return drill_at(state) == "fire"


## The depot's drill wrecks are targets (aim and fire drills).
static func drill_targets(state: TankState) -> bool:
	var d := drill_at(state)
	return d == "aim" or d == "fire"


## The tank may drive in the depot: during a "drive" drill, or always when the depot has none.
static func depot_driving(state: TankState) -> bool:
	var aux := TankAux.of(state)
	if aux.drills.is_empty():
		return true
	return drill_at(state) == "drive"
