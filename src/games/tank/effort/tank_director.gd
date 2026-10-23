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
## at each segment start, and the in-band power band (tanks.json in_band.sim_ftp_pct, 76-105% FTP)
## for diesel and Bulwark riders in WORK SIM phases, cleared (0, 0) in every other phase (WARMUP,
## RECOVERY, ERG). It also ships the pure helpers the patterns must use: bank_target_pct (pattern
## 1, clamped to the phase's range), boiler_grade_pct (pattern 2, min(pressure, 1) everywhere) and
## crew_haptic (one crew-wide haptic per tick, boss_hit first). G1 (effort) adds patterns 1-4 (bank
## sub-steps, boiler, hoist, terrain at 2 Hz), the loader's (50, 120) band and the haptics of 2.7,
## keeping this API. Every per-rider gate reads the receiver's own phase (TankRiderInput
## phase_kind, phase_mode, grade_source, plan_elapsed_s), never the group's.

const HAPTIC_NONE := ""
const HAPTIC_HIT := "hit"
const HAPTIC_BOSS_HIT := "boss_hit"

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
	var slot := ctx.player(ri.peer)
	if slot == null:
		return
	var pb := power_band_pct(content, plan.phase(ri.phase_index))
	ctx.hud.power_band(ri.peer, pb[0] / 100.0 * slot.ftp, pb[1] / 100.0 * slot.ftp)


## The SIM power band in % FTP to publish for a rider in `ph`: tanks.json in_band.sim_ftp_pct for
## the diesel and the Bulwark in WORK SIM phases (the tempo the in-band rule scores), else [0, 0]
## (cleared): never a tempo band in the warm-up (BRIEF 4.6.8), checkpoints or ERG, and never for
## the steam engine (its 90% rule stays on the station card).
static func power_band_pct(c: TankContent, ph: PlanPhase) -> Array[float]:
	var engine := str(ph.meta.get("engine", ""))
	var drives := engine == TankIds.ENGINE_DIESEL or engine == TankIds.ENGINE_BULWARK
	if ph.kind != Wl.WORK or ph.mode != Wl.SIM or not drives:
		return [0.0, 0.0]
	var b: Array = c.value("tanks", "in_band.sim_ftp_pct", [76, 105])
	return [float(b[0]), float(b[1])]


## Pattern 1: the bank's ERG target in % FTP, base + span x (1 - bank / 100), clamped to the
## phase's effective_range() (stations.json bank.clamp_to_range; 55..65 in the drill's skirmish).
## Apply it before the <= max_step_pts limit and the sub-steps. Only for phases with a range_pct
## (never the depot or checkpoints).
static func bank_target_pct(c: TankContent, bank: float, ph: PlanPhase) -> float:
	var base := c.num("stations", "bank.base_pct", 55.0)
	var span := c.num("stations", "bank.span_pct", 45.0)
	var pct := base + span * (1.0 - clampf(bank, 0.0, 100.0) / 100.0)
	var r := ph.effective_range()
	return clampf(pct, float(r[0]), float(r[1]))


## Pattern 2: the boiler's mode grade in % before difficulty: grade x min(pressure, 1), with the
## warm-up grade (3%) in WARMUP-kind phases, 0 while a shell is loaded or the breech cycles.
static func boiler_grade_pct(
	c: TankContent, pressure_pct: float, warmup: bool, loaded_or_cycling: bool
) -> float:
	if loaded_or_cycling:
		return 0.0
	var key := "boiler.warmup_grade_pct" if warmup else "boiler.grade_pct"
	var grade := c.num("stations", key, 3.0 if warmup else 8.0)
	return grade * clampf(pressure_pct / 100.0, 0.0, 1.0)


## The crew-wide haptic this tick's events call for: HAPTIC_BOSS_HIT over HAPTIC_HIT (one per
## receiver per tick, TankEvents doc), or HAPTIC_NONE. The ram haptic is the driver's own.
static func crew_haptic(events: Array[Dictionary], min_damage: float) -> String:
	var out := HAPTIC_NONE
	for e in events:
		if TankEvents.is_boss_main_hit(e):
			return HAPTIC_BOSS_HIT
		if TankEvents.is_tank_hit(e, min_damage):
			out = HAPTIC_HIT
	return out


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
