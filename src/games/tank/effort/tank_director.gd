class_name TankDirector
extends RefCounted
## The effort director (brief 2.3 directive patterns, 2.7 haptics): the only Tank code that calls
## ctx.directives, plus the per-rider power band (ctx.hud.power_band). Host / SOLO only; the module
## calls step() once per sim_step, right after TankRules.step, with that tick's events. It reads
## TankState and never mutates rule state; its own bookkeeping (sub-step schedules, last sent
## grades, haptic cooldowns, which phases it ended) lives here. Owner: effort.
##
## G0 ships the parts every session needs to run: end_phase for every rider in one step once the
## objective is done and min_s has passed (ADR "Who calls end_phase"), the cadence band (60, 120)
## at each segment start, and the 76-105% FTP power band for diesel and Bulwark riders in SIM
## phases (cleared otherwise). G1 (effort) adds patterns 1-4 (bank sub-steps, boiler, hoist,
## terrain at 2 Hz), the loader's (50, 120) band and the haptics of 2.7, keeping this API.

var ctx: GameContext = null
var content: TankContent = null
## peer -> EffortPlan (the module's, without the cool-down).
var plans: Dictionary = {}

## Phase indexes this director already ended (end_phase once per phase).
var _ended: Dictionary = {}
## peer -> the phase index whose start this director handled.
var _started: Dictionary = {}


func _init(p_ctx: GameContext, p_content: TankContent, p_plans: Dictionary) -> void:
	ctx = p_ctx
	content = p_content
	plans = p_plans


## Sends this tick's directives. `events`: what TankRules.step returned this tick.
func step(state: TankState, inputs: TankInputs, _events: Array[Dictionary]) -> void:
	if ctx == null or state == null:
		return
	for ri in inputs.riders:
		if ri.phase_index != int(_started.get(ri.peer, -1)):
			_started[ri.peer] = ri.phase_index
			_segment_start(ri)
	_maybe_end_phase(state, inputs)


func _segment_start(ri: TankRiderInput) -> void:
	var plan: EffortPlan = plans.get(ri.peer)
	if plan == null or ri.phase_index < 0 or ri.phase_index >= plan.size():
		return  # the cool-down: the platform clears every band and refuses directives
	var band: Array = content.value("stations", "cadence_band.default", [60, 120])
	ctx.directives.cadence_band(ri.peer, float(band[0]), float(band[1]))
	var ph := plan.phase(ri.phase_index)
	var engine := str(ph.meta.get("engine", ""))
	var drives := engine == TankIds.ENGINE_DIESEL or engine == TankIds.ENGINE_BULWARK
	var slot := ctx.player(ri.peer)
	if slot == null:
		return
	if ph.mode == Wl.SIM and drives:
		var pb: Array = content.value("stations", "power_band_pct", [76, 105])
		ctx.hud.power_band(
			ri.peer, float(pb[0]) / 100.0 * slot.ftp, float(pb[1]) / 100.0 * slot.ftp
		)
	else:
		ctx.hud.power_band(ri.peer, 0.0, 0.0)


## end_phase for every rider of the group's phase in one step, once the objective is done and
## min_s has passed (until then the tank holds: "Regroup").
func _maybe_end_phase(state: TankState, inputs: TankInputs) -> void:
	var ph := inputs.phase
	if not ph.open_ended or ph.is_cooldown() or _ended.has(ph.index):
		return
	if not state.seg.objective_done or ph.elapsed_s < ph.min_s:
		return
	_ended[ph.index] = true
	for ri in inputs.riders:
		if ri.phase_index == ph.index:
			ctx.directives.end_phase(ri.peer)
