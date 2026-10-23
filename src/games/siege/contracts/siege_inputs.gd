class_name SiegeInputs
extends RefCounted
## What SiegeRules.step(state, inputs, dt) reads each tick (G0 contract). The module (B2) builds
## it from the InputFrame with from_frame(); the headless sim (B4) and unit tests build it
## directly. The rules read nothing else: no ctx, no frame, no clock.

var tick: int = 0
## Game seconds (frame.t).
var t: float = 0.0
## The shared phase (every slot rides the same phases; from the first slot's frame.phase).
var phase: SiegePhaseInfo = SiegePhaseInfo.new()
## One per slot, in slot order (ctx.players order), bots included.
var riders: Array[SiegeRiderInput] = []


## Builds the inputs for one tick. `plans`: peer -> the EffortPlan this module built (the
## validator's appended cool-down is past its end; role_of() reports it). `intents`: peer ->
## Array of intents already normalized (SiegeIntents.normalize) and rate-limited
## (SiegeIntentLimiter), in arrival order; a missing peer has none. `rescue` / `afk`: peer ->
## bool from on_rescue / on_afk (the module keeps them; a dropped client is AFK).
static func from_frame(
	frame: InputFrame,
	players: Array[PlayerSlot],
	plans: Dictionary,
	intents: Dictionary,
	rescue: Dictionary,
	afk: Dictionary
) -> SiegeInputs:
	var inp := SiegeInputs.new()
	inp.tick = frame.tick
	inp.t = frame.t
	if not players.is_empty():
		var first := players[0].peer_id
		var ps := frame.phase_of(first)
		var plan: EffortPlan = plans.get(first)
		if ps != null:
			inp.phase = SiegePhaseInfo.from_phase(ps, SiegePlanBuilder.role_of(plan, ps.index))
	for p in players:
		var ri := SiegeRiderInput.new()
		ri.peer = p.peer_id
		ri.slot = p.slot_index
		var tm := frame.telemetry(p.peer_id)
		if tm != null:
			ri.power_w = tm.power_w
			ri.p_eff_w = tm.p_eff_w
			ri.cadence_rpm = tm.cadence_rpm
			ri.connected = tm.connected
			ri.mode = tm.mode
		var ps := frame.phase_of(p.peer_id)
		var plan: EffortPlan = plans.get(p.peer_id)
		if ps != null:
			ri.planned_pct = ps.planned_pct
			if plan != null and ps.index >= 0 and ps.index < plan.size():
				ri.phase_mean_pct = SiegePlanBuilder.mean_pct(plan.phase(ps.index))
			else:
				ri.phase_mean_pct = ps.planned_pct
		ri.rescue = bool(rescue.get(p.peer_id, false))
		ri.afk = bool(afk.get(p.peer_id, false)) or not ri.connected
		var list: Array = intents.get(p.peer_id, [])
		for it: Variant in list:
			if it is Dictionary:
				ri.intents.append(it)
		inp.riders.append(ri)
	return inp


## The input of `peer`, or null.
func rider(peer: int) -> SiegeRiderInput:
	for r in riders:
		if r.peer == peer:
			return r
	return null
