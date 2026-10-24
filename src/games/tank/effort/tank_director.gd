class_name TankDirector
extends RefCounted
## The effort director (brief 2.3 directive patterns, 2.7 haptics): the only Tank code that calls
## ctx.directives, plus the per-rider power band (ctx.hud.power_band). Host / SOLO only; the module
## calls step() once per sim_step, right after TankRules.step, with that tick's events. It reads
## TankState and never mutates rule state; its own bookkeeping (sub-step schedules, last sent
## grades, haptic cooldowns, which phases it ended) lives here. Owner: effort.
##
## Every per-rider gate reads the receiver's own phase (TankRiderInput phase_index, phase_kind,
## phase_mode, grade_source, plan_elapsed_s), never the group's; nothing is sent past the end of
## the rider's plan (the cool-down). Timing counts ticks from the rider's phase start, so the
## schedules are exact on the 0.05 s grid. Every request carries source "tank" and duration_s 0
## (held until superseded or the phase ends), except haptics, which carry their own duration.
##
## 1. Bank (dynamo, ERG phases with a range_pct, never the depot or checkpoints): every
##    bank.every_s an update toward bank_target_pct (clamped to the phase's range), moving at most
##    bank.max_step_pts from the last sent target, sent as bank.substeps sub-steps bank.substep_s
##    apart: {mode ERG, target_pct, reason "bank"} (brief 2.3 pattern 1; in an ERG phase with no SIM
##    block running, mode ERG changes nothing but the target).
## 2. Boiler (steam, the rider's SIM phases): {mode SIM, mode_grade, reason "boiler"} with
##    boiler_grade_pct, at most once per boiler.min_interval_s, rising at most boiler.max_rise_pct
##    a step, falling (the latch's drop to 0 included) in one step.
## 3. Hoist (Bulwark, SIM phases): {mode SIM, mode_grade, reason "hoist"} climbing at
##    hoist.rise_pct_s (one step every hoist.step_s, counted from reaching Hoist) to hoist.grade_pct
##    (warmup_grade_pct in WARMUP kinds) while the lever is on Hoist; 0 in one step on leaving.
## 4. Terrain: course_grade every terrain.send_every_s (2 Hz) in grade_source "game" phases, the
##    grade under the tank from the mission terrain (warm-up range in WARMUP kinds).
## 5. cadence_band default (60, 120) at each segment start; loader (50, 120) while the steam
##    rider's shell is loaded or the breech cycles in a WORK phase (the in-band rule's cadence 50
##    applies only there), back to the default when it clears.
## 6. Haptics (2.7): {mode SIM, haptic, duration_s, reason} for hit / boss_hit (every rider in
##    SIM) and ram (the driver), never in WARMUP kinds, the first 300 s, the cool-down, ERG, to an
##    opted-out or reserve rider, nor within haptics.cooldown_s of the end of the last one.
## 7. end_phase for every rider of the group's phase in one step once the objective is done and
##    min_s has passed (ADR "Who calls end_phase").
## The power band: tanks.json in_band.sim_ftp_pct for diesel and Bulwark riders in WORK SIM
## phases, cleared (0, 0) everywhere else, at each segment start.

const HAPTIC_NONE := ""
const HAPTIC_HIT := "hit"
const HAPTIC_BOSS_HIT := "boss_hit"
const HAPTIC_RAM := "ram"

const SOURCE := "tank"
const REASON_BANK := "bank"
const REASON_BOILER := "boiler"
const REASON_HOIST := "hoist"

## Changes smaller than this are float noise, not worth a directive.
const EPS := 1e-6
## The tick of "never sent".
const NEVER := -(1 << 40)

var ctx: GameContext = null
var content: TankContent = null
## peer -> EffortPlan (the module's, without the cool-down).
var plans: Dictionary = {}

## Phase indexes this director already ended (end_phase once per phase).
var _ended: Dictionary = {}
## Phase index -> the phase's elapsed seconds when its objective was first seen done.
var _done_at: Dictionary = {}
## peer -> the phase index whose start this director handled.
var _started: Dictionary = {}
## peer -> the tick that phase started on.
var _start_tick: Dictionary = {}
## peer -> {"cur": last sent %, "from": update start %, "goal": update goal %}.
var _bank: Dictionary = {}
## peer -> the last boiler / hoist mode grade sent in this phase (the platform resets the channel
## at every phase change).
var _grade: Dictionary = {}
## peer -> the tick of the last boiler send (kept across phases: at most once per second).
var _boiler_tick: Dictionary = {}
## peer -> the tick the lever reached Hoist (or the phase started on Hoist); absent off Hoist.
var _hoist_since: Dictionary = {}
## peer -> true while the loader band (50, 120) is published.
var _loader: Dictionary = {}
## peer -> the game time the receiver's last haptic ends.
var _haptic_end: Dictionary = {}


func _init(p_ctx: GameContext, p_content: TankContent, p_plans: Dictionary) -> void:
	ctx = p_ctx
	content = p_content
	plans = p_plans


## Sends this tick's directives. `events`: what TankRules.step returned this tick.
func step(state: TankState, inputs: TankInputs, events: Array[Dictionary]) -> void:
	if ctx == null or state == null or inputs == null:
		return
	for ri in inputs.riders:
		if ri.phase_index != int(_started.get(ri.peer, -1)):
			_started[ri.peer] = ri.phase_index
			_start_tick[ri.peer] = inputs.tick
			_segment_start(ri)
		var ph := _phase(ri)
		if ph == null:
			continue  # the cool-down: nothing is sent
		var e := inputs.tick - int(_start_tick[ri.peer])
		_bank_step(state, ri, ph, e)
		_boiler_step(state, ri, inputs.tick)
		_hoist_step(state, ri, inputs.tick)
		_terrain_step(state, ri, ph, e)
		_loader_step(state, ri)
	_haptics(state, inputs, events)
	_maybe_end_phase(state, inputs)


## The rider's PlanPhase, or null in the cool-down (past the plan) or without a phase or plan.
func _phase(ri: TankRiderInput) -> PlanPhase:
	var plan: EffortPlan = plans.get(ri.peer)
	if plan == null or ri.phase_index < 0 or ri.phase_index >= plan.size():
		return null
	if ri.phase_kind == Wl.COOLDOWN:
		return null
	return plan.phase(ri.phase_index)


func _segment_start(ri: TankRiderInput) -> void:
	_bank.erase(ri.peer)
	_grade[ri.peer] = 0.0
	_hoist_since.erase(ri.peer)
	_loader[ri.peer] = false
	var ph := _phase(ri)
	if ph == null:
		return  # the cool-down: the platform clears every band and refuses directives
	var band: Array = content.value("stations", "cadence_band.default", [60, 120])
	ctx.directives.cadence_band(ri.peer, float(band[0]), float(band[1]))
	var slot := ctx.player(ri.peer)
	if slot == null:
		return
	var pb := power_band_pct(content, ph)
	ctx.hud.power_band(ri.peer, pb[0] / 100.0 * slot.ftp, pb[1] / 100.0 * slot.ftp)


# --- Pattern 1: the bank -------------------------------------------------------------------------


## True when pattern 1 runs in `ph` for a rider on `engine`: the dynamo in an ERG phase with a
## range_pct, never the depot or a checkpoint.
static func bank_phase(engine: String, ph: PlanPhase) -> bool:
	if engine != TankIds.ENGINE_DYNAMO or ph == null or ph.mode != Wl.ERG:
		return false
	if ph.range_pct.size() != 2:
		return false
	var seg := str(ph.meta.get("seg", ""))
	return seg != TankIds.SEG_DEPOT and seg != TankIds.SEG_CHECKPOINT


func _bank_step(state: TankState, ri: TankRiderInput, ph: PlanPhase, e: int) -> void:
	if ri.phase_mode != Wl.ERG or not bank_phase(ri.engine, ph):
		return
	var dyn := state.station(TankIds.ENGINE_DYNAMO) as TankDynamoState
	if dyn == null:
		return
	var every := _ticks(content.num("stations", "bank.every_s", 5.0))
	var sub := _ticks(content.num("stations", "bank.substep_s", 1.0))
	var n := maxi(int(content.num("stations", "bank.substeps", 3.0)), 1)
	if not _bank.has(ri.peer):
		var planned := ph.planned_pct_at(float(e) * Wl.SIM_DT)
		_bank[ri.peer] = {"cur": planned, "from": planned, "goal": planned}
	var b: Dictionary = _bank[ri.peer]
	var u := e % every
	if u == 0:
		var cur := float(b["cur"])
		b["from"] = cur
		b["goal"] = bank_goal_pct(content, dyn.bank, ph, cur)
	if u % sub != 0 or u / sub >= n:
		return
	var from := float(b["from"])
	var goal := float(b["goal"])
	if absf(goal - from) < EPS:
		return
	var pct := bank_substep_pct(from, goal, u / sub + 1, n)
	if _request(
		ri.peer, {"mode": Wl.ERG, "target_pct": pct, "reason": REASON_BANK, "source": SOURCE}
	):
		b["cur"] = pct


## One bank update's goal: bank_target_pct, moved at most bank.max_step_pts from `cur_pct` (the
## last sent target), so the sub-steps climb at most max_step_pts / substeps per substep_s.
static func bank_goal_pct(c: TankContent, bank: float, ph: PlanPhase, cur_pct: float) -> float:
	var step := c.num("stations", "bank.max_step_pts", 10.0)
	var target := bank_target_pct(c, bank, ph)
	return clampf(target, cur_pct - step, cur_pct + step)


## Sub-step `k` (1..n) of an update from `from_pct` to `goal_pct` (the last one is the goal).
static func bank_substep_pct(from_pct: float, goal_pct: float, k: int, n: int) -> float:
	if k >= n:
		return goal_pct
	return from_pct + (goal_pct - from_pct) * float(k) / float(n)


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


# --- Pattern 2: the boiler -----------------------------------------------------------------------


func _boiler_step(state: TankState, ri: TankRiderInput, tick: int) -> void:
	if ri.engine != TankIds.ENGINE_STEAM or ri.phase_mode != Wl.SIM:
		return
	if ri.phase_kind != Wl.WORK and ri.phase_kind != Wl.WARMUP:
		return
	var steam := state.station(TankIds.ENGINE_STEAM) as TankSteamState
	if steam == null:
		return
	var interval := _ticks(content.num("stations", "boiler.min_interval_s", 1.0))
	if tick - int(_boiler_tick.get(ri.peer, NEVER)) < interval:
		return
	var want := boiler_grade_pct(
		content, steam.pressure_pct, ri.in_warmup(), steam.loaded or steam.cycling
	)
	var last := float(_grade.get(ri.peer, 0.0))
	var next := boiler_next_pct(content, last, want)
	if absf(next - last) < EPS:
		return
	var d := {"mode": Wl.SIM, "mode_grade": next, "reason": REASON_BOILER, "source": SOURCE}
	if _request(ri.peer, d):
		_grade[ri.peer] = next
		_boiler_tick[ri.peer] = tick


## The boiler grade to send after `last_pct` toward `want_pct`: a rise of at most
## boiler.max_rise_pct, a fall in one step.
static func boiler_next_pct(c: TankContent, last_pct: float, want_pct: float) -> float:
	if want_pct <= last_pct:
		return want_pct
	return minf(want_pct, last_pct + c.num("stations", "boiler.max_rise_pct", 0.5))


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


# --- Pattern 3: the Bulwark's hoist --------------------------------------------------------------


func _hoist_step(state: TankState, ri: TankRiderInput, tick: int) -> void:
	if ri.engine != TankIds.ENGINE_BULWARK or ri.phase_mode != Wl.SIM:
		return
	if ri.phase_kind != Wl.WORK and ri.phase_kind != Wl.WARMUP:
		return
	var gear := state.station(TankIds.ENGINE_BULWARK) as TankGearboxState
	if gear == null:
		return
	var want := 0.0
	if on_hoist(gear):
		if not _hoist_since.has(ri.peer):
			_hoist_since[ri.peer] = tick
		var held_s := float(tick - int(_hoist_since[ri.peer])) * Wl.SIM_DT
		want = hoist_grade_pct(content, held_s, ri.in_warmup())
	else:
		_hoist_since.erase(ri.peer)
	if absf(want - float(_grade.get(ri.peer, 0.0))) < EPS:
		return
	var d := {"mode": Wl.SIM, "mode_grade": want, "reason": REASON_HOIST, "source": SOURCE}
	if _request(ri.peer, d):
		_grade[ri.peer] = want


## The lever stands on Hoist (not moving to or from it).
static func on_hoist(gear: TankGearboxState) -> bool:
	return (
		gear.lever == TankIds.LEVER_HOIST
		and gear.lever_to == TankIds.LEVER_HOIST
		and gear.move_s <= 0.0
	)


## Pattern 3: the hoist grade `held_s` seconds after reaching Hoist: hoist.rise_pct_s per second
## in whole hoist.step_s steps (never above rise x held_s), up to hoist.grade_pct (warmup_grade_pct
## in WARMUP kinds).
static func hoist_grade_pct(c: TankContent, held_s: float, warmup: bool) -> float:
	var key := "hoist.warmup_grade_pct" if warmup else "hoist.grade_pct"
	var top := c.num("stations", key, 1.0 if warmup else 4.0)
	var rise := c.num("stations", "hoist.rise_pct_s", 1.0)
	var step_s := maxf(c.num("stations", "hoist.step_s", 1.0), Wl.SIM_DT)
	var steps := floorf((held_s + EPS) / step_s)
	return minf(top, rise * step_s * steps)


# --- Pattern 4: terrain --------------------------------------------------------------------------


func _terrain_step(state: TankState, ri: TankRiderInput, ph: PlanPhase, e: int) -> void:
	if ri.phase_mode != Wl.SIM or ri.grade_source != Wl.GRADE_GAME:
		return
	if e % _ticks(content.num("stations", "terrain.send_every_s", 0.5)) != 0:
		return
	var seg := int(ph.meta.get("segment", ri.phase_index))
	var g := terrain_grade_pct(content, seg, state.hull.distance_m, ri.in_warmup())
	ctx.directives.course_grade(ri.peer, g)


## Pattern 4: the grade under the tank `distance_m` into mission segment `segment`: the shared
## sampler `TankTerrain.for_segment`, the same function the rules roll the hull on.
static func terrain_grade_pct(
	c: TankContent, segment: int, distance_m: float, warmup: bool
) -> float:
	return TankTerrain.for_segment(c, segment, distance_m, warmup)


# --- Pattern 5: the loader's cadence band --------------------------------------------------------


func _loader_step(state: TankState, ri: TankRiderInput) -> void:
	var want := false
	if ri.engine == TankIds.ENGINE_STEAM and ri.phase_kind == Wl.WORK:
		var steam := state.station(TankIds.ENGINE_STEAM) as TankSteamState
		want = steam != null and (steam.loaded or steam.cycling)
	if want == bool(_loader.get(ri.peer, false)):
		return
	_loader[ri.peer] = want
	var key := "cadence_band.loader" if want else "cadence_band.default"
	var band: Array = content.value("stations", key, [50, 120] if want else [60, 120])
	ctx.directives.cadence_band(ri.peer, float(band[0]), float(band[1]))


# --- Pattern 6: haptics --------------------------------------------------------------------------


func _haptics(state: TankState, inputs: TankInputs, events: Array[Dictionary]) -> void:
	var crew := crew_haptic(events, content.num("stations", "haptics.hit.min_damage", 8.0))
	var drivers := {}
	for e in events:
		if str(e.get("type", "")) == TankEvents.RAM:
			drivers[int(e.get("s", -1))] = true
	if crew == HAPTIC_NONE and drivers.is_empty():
		return
	var cool := content.num("stations", "haptics.cooldown_s", 15.0)
	for ri in inputs.riders:
		var kind := HAPTIC_RAM if drivers.has(ri.slot) else crew
		if kind == HAPTIC_NONE or not haptic_allowed(ri, _phase(ri), _haptics_on(state, ri)):
			continue
		if inputs.t + EPS < float(_haptic_end.get(ri.peer, -INF)) + cool:
			continue  # inside the receiver's 15 s spacing: dropped, never queued
		var d := haptic_directive(content, kind)
		if _request(ri.peer, d):
			_haptic_end[ri.peer] = inputs.t + float(d["duration_s"])


## The haptic request of `kind` (hit, boss_hit or ram), exactly as brief 2.7's table.
static func haptic_directive(c: TankContent, kind: String) -> Dictionary:
	var cfg: Dictionary = c.value("stations", "haptics." + kind, {})
	return {
		"mode": Wl.SIM,
		"haptic": float(cfg.get("haptic", 0.0)),
		"duration_s": float(cfg.get("duration_s", 0.0)),
		"reason": kind,
		"source": SOURCE
	}


## The rider may receive a haptic now: in a SIM phase of its plan that is not a WARMUP kind,
## past its first 300 s, applied mode not ERG, haptics on, not on reserve.
static func haptic_allowed(ri: TankRiderInput, ph: PlanPhase, haptics_on: bool) -> bool:
	if ph == null or not haptics_on or ri.on_reserve():
		return false
	if ph.mode != Wl.SIM or ri.phase_mode != Wl.SIM or ri.mode == Wl.ERG:
		return false
	if ri.phase_kind == "" or ri.phase_kind == Wl.WARMUP or ri.phase_kind == Wl.COOLDOWN:
		return false
	return not ri.in_first_window()


func _haptics_on(state: TankState, ri: TankRiderInput) -> bool:
	var slot := ctx.player(ri.peer)
	if slot != null:
		return slot.haptics_on
	var r := state.rider(ri.peer)
	return r != null and r.haptics_on


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


# --- Power band and end_phase --------------------------------------------------------------------


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


## end_phase for every rider of the group's phase in one step, once the objective is done, min_s
## has passed (until then the tank holds: "Regroup") and the segment's `end_hold_s` (mission file,
## default 0; the boss uses it for the Behemoth's death beat) has run since the objective was done.
func _maybe_end_phase(state: TankState, inputs: TankInputs) -> void:
	var ph := inputs.phase
	if not ph.open_ended or ph.is_cooldown() or _ended.has(ph.index):
		return
	if not state.seg.objective_done:
		return
	if not _done_at.has(ph.index):
		_done_at[ph.index] = ph.elapsed_s
	if ph.elapsed_s < ph.min_s:
		return
	var hold := float(content.segment(ph.segment).get("end_hold_s", 0.0))
	if ph.elapsed_s - float(_done_at[ph.index]) < hold - EPS:
		return
	_ended[ph.index] = true
	for ri in inputs.riders:
		if ri.phase_index == ph.index:
			ctx.directives.end_phase(ri.peer)


# --- Helpers -------------------------------------------------------------------------------------


func _request(peer: int, fields: Dictionary) -> bool:
	var r := ctx.directives.request(peer, EffortDirective.from_dict(fields))
	return r != null and r.accepted


## Whole ticks in `seconds` (at least 1).
static func _ticks(seconds: float) -> int:
	return maxi(roundi(seconds / Wl.SIM_DT), 1)
