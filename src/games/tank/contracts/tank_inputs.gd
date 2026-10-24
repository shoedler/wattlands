class_name TankInputs
extends RefCounted
## What TankRules.step(state, inputs, dt) reads each tick (G0 contract). The module builds it
## from the InputFrame with from_frame(); the rules-level harness and unit tests build it
## directly. The rules read nothing else: no ctx, no frame, no clock.

var tick: int = 0
## Game seconds (frame.t).
var t: float = 0.0
## The group's phase: the PhaseState of the rider in the lowest phase index, with its meta.
var phase: TankPhaseInfo = TankPhaseInfo.new()
## One per slot, in slot order (ctx.players order).
var riders: Array[TankRiderInput] = []
## Session options (ctx.options; "rotation" is fixed in the plans, the rules only report it).
var options: Dictionary = {}


## Builds the inputs for one tick. `plans`: peer -> the EffortPlan this module built (the
## validator's appended cool-down lies past its end and has no meta). `intents`: peer -> Array
## of intents already normalized, rate-limited and ownership-filtered, in arrival order.
## `rescue` / `afk`: peer -> bool from on_rescue / on_afk (a dropped client is AFK).
static func from_frame(
	frame: InputFrame,
	players: Array[PlayerSlot],
	plans: Dictionary,
	intents: Dictionary,
	rescue: Dictionary,
	afk: Dictionary
) -> TankInputs:
	var inp := TankInputs.new()
	inp.tick = frame.tick
	inp.t = frame.t
	var group_peer := 0
	var group_index := 1 << 30
	for p in players:
		var ps := frame.phase_of(p.peer_id)
		if ps != null and ps.index < group_index:
			group_index = ps.index
			group_peer = p.peer_id
	if group_peer != 0:
		var gps := frame.phase_of(group_peer)
		inp.phase = TankPhaseInfo.from_phase(gps, meta_of(plans.get(group_peer), gps.index))
	for p in players:
		var ri := TankRiderInput.new()
		ri.peer = p.peer_id
		ri.slot = p.slot_index
		ri.ftp = p.ftp
		ri.ftp_verified = p.ftp_verified
		ri.rider_mass_kg = p.rider_mass_kg
		ri.autopilot = p.autopilot or p.is_bot
		var ps := frame.phase_of(p.peer_id)
		if ps != null:
			ri.phase_index = ps.index
			ri.phase_kind = ps.kind
			ri.phase_mode = ps.mode
			ri.plan_elapsed_s = ps.plan_elapsed_s
			ri.engine = str(meta_of(plans.get(p.peer_id), ps.index).get("engine", ""))
			ri.grade_source = grade_source_of(plans.get(p.peer_id), ps.index)
		var tm := frame.telemetry(p.peer_id)
		if tm != null:
			ri.power_w = tm.power_w
			ri.p_eff_w = tm.p_eff_w
			ri.cadence_rpm = tm.cadence_rpm
			ri.ftp_pct = tm.ftp_pct
			ri.mode = tm.mode
			ri.applied_target_w = float(tm.applied_target_w)
			ri.wbal_j = tm.wbal_j
			ri.connected = tm.connected
		ri.rescue = bool(rescue.get(p.peer_id, false))
		ri.afk = bool(afk.get(p.peer_id, false)) or not ri.connected
		for it: Variant in intents.get(p.peer_id, []):
			if it is Dictionary:
				ri.intents.append(it)
		inp.riders.append(ri)
	return inp


## The meta of phase `index` of `plan` ({} past its end: the appended cool-down, or no plan).
static func meta_of(plan: Variant, index: int) -> Dictionary:
	if not (plan is EffortPlan):
		return {}
	var ep: EffortPlan = plan
	if index < 0 or index >= ep.size():
		return {}
	return ep.phase(index).meta


## The grade_source of SIM phase `index` of `plan` ("" for ERG, past its end, or no plan).
static func grade_source_of(plan: Variant, index: int) -> String:
	if not (plan is EffortPlan):
		return ""
	var ep: EffortPlan = plan
	if index < 0 or index >= ep.size() or ep.phase(index).mode != Wl.SIM:
		return ""
	return ep.phase(index).grade_source


## The input of `peer`, or null.
func rider(peer: int) -> TankRiderInput:
	for r in riders:
		if r.peer == peer:
			return r
	return null
