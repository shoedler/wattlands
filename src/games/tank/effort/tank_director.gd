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
## 2. Arc (the Lights seat, ERG phases with a range_pct, never the depot or checkpoints): the same
##    schedule (stations.json arc) toward arc_target_pct = 65 + 15 x duty, the searchlight load (v3:
##    the share of the last 10 s an enemy stood in range, TankArcState), clamped to the phase's
##    range: {mode ERG, target_pct, reason "arc"} (brief 2.3 pattern 2).
## 3. Boiler (steam, the rider's SIM phases): {mode SIM, mode_grade, reason "boiler"} with
##    boiler_grade_pct, at most once per boiler.min_interval_s, rising at most boiler.max_rise_pct
##    a step, falling (the latch's drop to 0 included) in one step.
## 4. (Retired in v3 with the Bulwark's gearbox: its hoist grade.)
## 5. Terrain: course_grade every terrain.send_every_s (2 Hz) in grade_source "game" phases, the
##    grade under the tank from the mission terrain (warm-up range in WARMUP kinds); in free roam
##    the valley's grade under the hull in its travel direction (TankRoam.grade_pct, the same
##    sampler the drive rolls on: -3..+5%, the warm-up range in the drive-out).
## 6. cadence_band default (60, 120) at each phase start; loader (50, 120) while the Loader idles
##    (v3: the ready rack is full) in a WORK phase (the in-band rule's cadence 50 applies only
##    there), back to the default when it clears.
## 7. Haptics (2.7): {mode SIM, haptic, duration_s, reason} for hit / boss_hit (every rider in
##    SIM), never in WARMUP kinds, the first 300 s, the cool-down, ERG, to an opted-out or reserve
##    rider, nor within haptics.cooldown_s of the end of the last one. (v2 removed the Ram haptic.)
## 8. end_phase for every rider of the group's segment in one step once the objective is done,
##    the segment's min_s has passed and every rider is past its own phase's min_s (v3: a seat
##    switch's split phase may hold it; ADR "Who calls end_phase"); a refused rider is retried.
## 9. The trainer follows the seat (0.3.1, no seat lock): a seat move lands at once (TankSeats);
##    every tick TankSeatPlan.follow decides for each rider whose plan is set up for another seat:
##    a split now (ctx.directives.split: the rest of the segment for the new seat, ending the current
##    phase this tick), a wait (an ERG <-> SIM switch within 30 s of the rider's last; the rider's
##    TankRiderState.mode_wait_s and mode_to say when and to what), or the later segments only (the
##    switch at the segment's end). `plans` follows every accepted split or replan (the module shares
##    the dictionary). While a switch waits, the trainer keeps the plan's seat: its ERG pattern holds
##    (that seat stands empty, so its bank or load does not move) and its SIM grade goes flat (no
##    boiler grade, no terrain) until the switch.
## 10. Repair (v4; the Repairs seat, ERG phases with a range_pct, never the depot or checkpoints): the
##     same schedule (stations.json repair) toward repair_target_pct = 55 + 15 x duty, the share of the
##     last 10 s the hull stood below its maximum (TankRepairState), clamped to the phase's range:
##     {mode ERG, target_pct, reason "repair"}.
## A tank under tow (v4, TankHullState.tow_s) gets course grade 0: the rider pedals flat, and no other
## directive, plan or phase changes for it. Nothing in effort/ reads the game's difficulty level.
## Sprints (evade, Overpressure) send nothing: they are the rider's own in the phase's SIM.
## A rider on reserve (dropped or AFK) gets no bank, arc or boiler request: a dropped peer never
## receives them, so the director's idea of the held target would run away from the rider's real
## one. Its bank and grade memory is erased, and on the tick it is back the bank restarts from what
## the rider's governor holds (applied target), the boiler from 0, so the first update after a
## rejoin is again within the 10-point / 0.5% limits of the rider's real value.
## The power band: tanks.json in_band.sim_ftp_pct for Drive and Secondaries riders in WORK SIM
## phases, cleared (0, 0) everywhere else, at each phase start.

const HAPTIC_NONE := ""
const HAPTIC_HIT := "hit"
const HAPTIC_BOSS_HIT := "boss_hit"

const SOURCE := "tank"
const REASON_BANK := "bank"
const REASON_ARC := "arc"
const REASON_REPAIR := "repair"
const REASON_BOILER := "boiler"

## Changes smaller than this are float noise, not worth a directive.
const EPS := 1e-6
## How long before max_s the director ends a phase whose death-beat hold would run into it.
const END_MARGIN_S := 0.2
## Spacing of end_phase retries after the first one (a refusal is logged by the router).
const END_RETRY_S := 1.0
## BRIEF 4.6.1: the governor applies ERG targets x0.85 while FTP is unverified.
const UNVERIFIED_FACTOR := 0.85
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
## peer -> {"key": "phase:seat:action", "retry": tick}: the last split or replan pattern 9 sent for
## the rider (an accepted one is not repeated; a refused one is retried after END_RETRY_S).
var _seat_sent: Dictionary = {}
## peer -> the phase index whose start this director handled.
var _started: Dictionary = {}
## peer -> the tick that phase started on.
var _start_tick: Dictionary = {}
## peer -> {"cur": last sent %, "from": update start %, "goal": update goal %} of the rider's bank
## (dynamo), arc load (arc generator) or repair pattern in its current phase.
var _bank: Dictionary = {}
## peer -> the last boiler mode grade sent in this phase (the platform resets the channel
## at every phase change).
var _grade: Dictionary = {}
## peer -> the tick of the last boiler send (kept across phases: at most once per second).
var _boiler_tick: Dictionary = {}
## peer -> true while the loader band (50, 120) is published.
var _loader: Dictionary = {}
## peer -> the game time the receiver's last haptic ends.
var _haptic_end: Dictionary = {}
## peer -> true while the rider is on reserve (bank and boiler memory erased).
var _reserve: Dictionary = {}
## peer -> true on the tick the rider came back from reserve (the bank reseeds from the governor).
var _returned: Dictionary = {}
## Phase index -> the peers whose end_phase was refused and is still to be retried.
var _end_pending: Dictionary = {}
## peer -> the phase tick (e) of the rider's first ERG tick in a phase that began in the switch
## ramp (-1 until then; 0 for a phase in ERG from its first tick).
var _erg_from: Dictionary = {}
## Phase index -> the tick of the next end_phase retry.
var _end_retry_tick: Dictionary = {}
## Phase index -> how many retry rounds ran.
var _end_retries: Dictionary = {}


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
		if not _reserve_step(ri):
			# On reserve nothing held is sent (it may never arrive) or remembered as sent.
			_bank_step(state, ri, ph, e)
			_boiler_step(state, ri, inputs.tick)
		_terrain_step(state, ri, ph, e)
		_loader_step(state, ri)
	_haptics(state, inputs, events)
	var ending := _maybe_end_phase(state, inputs)
	_seat_step(state, inputs, ending)


## The rider's PlanPhase, or null in the cool-down (past the plan) or without a phase or plan.
func _phase(ri: TankRiderInput) -> PlanPhase:
	var plan: EffortPlan = plans.get(ri.peer)
	if plan == null or ri.phase_index < 0 or ri.phase_index >= plan.size():
		return null
	if ri.phase_kind == Wl.COOLDOWN:
		return null
	return plan.phase(ri.phase_index)


## True while `ri` is on reserve. Terrain, the cadence band and the power band carry on (they are
## resent from the current state or resynced by the host). Erases the bank and grade memory (a
## restarted client resumes at the plan, an in-process one at what it held, and the director cannot
## know which) and marks the rider as returned on the first tick it is back.
func _reserve_step(ri: TankRiderInput) -> bool:
	if ri.on_reserve():
		_reserve[ri.peer] = true
		_bank.erase(ri.peer)
		_grade[ri.peer] = 0.0
		return true
	if bool(_reserve.get(ri.peer, false)):
		_reserve[ri.peer] = false
		_returned[ri.peer] = true
	return false


func _segment_start(ri: TankRiderInput) -> void:
	_returned.erase(ri.peer)
	_bank.erase(ri.peer)
	# -1: the phase began in the switch ramp (its first ERG tick is recorded by _bank_step).
	var ramped := ri.phase_mode == Wl.ERG and ri.mode != Wl.ERG and not ri.on_reserve()
	_erg_from[ri.peer] = -1 if ramped else 0
	_grade[ri.peer] = 0.0
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


# --- Patterns 1, 2 and 10: the bank, the arc load and the repair load -----------------------------


## True when pattern 1 runs in `ph` for a rider on `engine`: the dynamo in an ERG phase with a
## range_pct, never the depot or a checkpoint.
static func bank_phase(engine: String, ph: PlanPhase) -> bool:
	return engine == TankIds.ENGINE_DYNAMO and _load_phase(ph)


## True when pattern 2 runs in `ph` for a rider on `engine`: the arc generator in an ERG phase with
## a range_pct, never the depot or a checkpoint.
static func arc_phase(engine: String, ph: PlanPhase) -> bool:
	return engine == TankIds.ENGINE_ARC and _load_phase(ph)


## True when pattern 10 runs in `ph` for a rider on `engine`: the Repairs seat in an ERG phase with a
## range_pct, never the depot or a checkpoint.
static func repair_phase(engine: String, ph: PlanPhase) -> bool:
	return engine == TankIds.ENGINE_REPAIR and _load_phase(ph)


static func _load_phase(ph: PlanPhase) -> bool:
	if ph == null or ph.mode != Wl.ERG or ph.range_pct.size() != 2:
		return false
	var seg := str(ph.meta.get("seg", ""))
	return seg != TankIds.SEG_DEPOT and seg != TankIds.SEG_CHECKPOINT


## Patterns 1, 2 and 10 share one schedule: every <key>.every_s an update toward the engine's goal,
## sent in <key>.substeps sub-steps <key>.substep_s apart (key "bank", "arc" or "repair").
func _bank_step(state: TankState, ri: TankRiderInput, ph: PlanPhase, e: int) -> void:
	if ri.phase_mode != Wl.ERG:
		return
	var key := ""
	var reason := ""
	var dyn: TankDynamoState = null
	var arc: TankArcState = null
	var repair: TankRepairState = null
	if bank_phase(ri.engine, ph):
		key = "bank"
		reason = REASON_BANK
		dyn = state.station(TankIds.ENGINE_DYNAMO) as TankDynamoState
		if dyn == null:
			return
	elif arc_phase(ri.engine, ph):
		key = "arc"
		reason = REASON_ARC
		arc = state.station(TankIds.ENGINE_ARC) as TankArcState
		if arc == null:
			return
	elif repair_phase(ri.engine, ph):
		key = "repair"
		reason = REASON_REPAIR
		repair = state.station(TankIds.ENGINE_REPAIR) as TankRepairState
		if repair == null:
			return
	else:
		return
	var every := _ticks(content.num("stations", key + ".every_s", 5.0))
	var sub := _ticks(content.num("stations", key + ".substep_s", 1.0))
	var n := maxi(int(content.num("stations", key + ".substeps", 3.0)), 1)
	if not _bank.has(ri.peer):
		var start := ph.planned_pct_at(float(e) * Wl.SIM_DT)
		if bool(_returned.get(ri.peer, false)):
			start = held_pct(ri, ph, start)
		_returned.erase(ri.peer)
		_bank[ri.peer] = {"cur": start, "from": start, "goal": start}
	var b: Dictionary = _bank[ri.peer]
	# A phase that began in the platform's switch ramp (SIM -> ERG, _erg_from -1 at its start):
	# nothing until the rider is in ERG, and its first full cycle in ERG keeps the entered target.
	if int(_erg_from.get(ri.peer, 0)) < 0:
		if ri.mode != Wl.ERG:
			return
		_erg_from[ri.peer] = e
	var u := e % every
	var ramp := int(_erg_from.get(ri.peer, 0))
	if u == 0 and ramp > 0 and e - ramp < every:
		# A phase entered through the switch ramp (SIM -> ERG) keeps the entered target for its
		# first full cycle in ERG (S9: an ERG phase starts at its planned target, never above it
		# in its first 5 s); a phase in ERG from its first tick updates as before.
		return
	if u == 0:
		var cur := float(b["cur"])
		b["from"] = cur
		if dyn != null:
			b["goal"] = bank_goal_pct(content, dyn.bank, ph, cur)
		elif arc != null:
			b["goal"] = arc_goal_pct(content, arc.duty, ph, cur)
		else:
			b["goal"] = repair_goal_pct(content, repair.duty, ph, cur)
	if u % sub != 0 or u / sub >= n:
		return
	var from := float(b["from"])
	var goal := float(b["goal"])
	if absf(goal - from) < EPS:
		return
	var pct := bank_substep_pct(from, goal, u / sub + 1, n)
	if _request(ri.peer, {"mode": Wl.ERG, "target_pct": pct, "reason": reason, "source": SOURCE}):
		b["cur"] = pct


## The ERG target in % FTP the rider's governor holds now, for reseeding the bank after a rejoin:
## the applied target (undoing the 0.85 unverified factor of BRIEF 4.6.1) clamped to the phase's
## effective range, or `fallback_pct` (the plan's value) when it holds no ERG target.
static func held_pct(ri: TankRiderInput, ph: PlanPhase, fallback_pct: float) -> float:
	if ri.mode != Wl.ERG or ri.applied_target_w <= 0.0:
		return fallback_pct
	var pct := ri.applied_pct() / (1.0 if ri.ftp_verified else UNVERIFIED_FACTOR)
	var r := ph.effective_range()
	return clampf(pct, float(r[0]), float(r[1]))


## One bank update's goal: bank_target_pct, moved at most bank.max_step_pts from `cur_pct` (the
## last sent target), so the sub-steps climb at most max_step_pts / substeps per substep_s.
static func bank_goal_pct(c: TankContent, bank: float, ph: PlanPhase, cur_pct: float) -> float:
	var step := c.num("stations", "bank.max_step_pts", 10.0)
	var target := bank_target_pct(c, bank, ph)
	return clampf(target, cur_pct - step, cur_pct + step)


## One arc update's goal: arc_target_pct, moved at most arc.max_step_pts from `cur_pct`.
static func arc_goal_pct(c: TankContent, duty: float, ph: PlanPhase, cur_pct: float) -> float:
	var step := c.num("stations", "arc.max_step_pts", 10.0)
	var target := arc_target_pct(c, duty, ph)
	return clampf(target, cur_pct - step, cur_pct + step)


## Pattern 2: the arc generator's ERG target in % FTP, base + span x duty (65 + 15 x duty), clamped
## to the phase's effective_range() (65..80 in a stage, 55..65 in the drill's skirmish). Apply it
## before the <= max_step_pts limit and the sub-steps. Only for phases with a range_pct.
static func arc_target_pct(c: TankContent, duty: float, ph: PlanPhase) -> float:
	var base := c.num("stations", "arc.base_pct", 65.0)
	var span := c.num("stations", "arc.span_pct", 15.0)
	var pct := base + span * clampf(duty, 0.0, 1.0)
	var r := ph.effective_range()
	return clampf(pct, float(r[0]), float(r[1]))


## One repair update's goal: repair_target_pct, moved at most repair.max_step_pts from `cur_pct`.
static func repair_goal_pct(c: TankContent, duty: float, ph: PlanPhase, cur_pct: float) -> float:
	var step := c.num("stations", "repair.max_step_pts", 10.0)
	var target := repair_target_pct(c, duty, ph)
	return clampf(target, cur_pct - step, cur_pct + step)


## Pattern 10: the Repairs seat's ERG target in % FTP, base + span x duty (55 + 15 x duty), clamped
## to the phase's effective_range() (55..70 in a stage, 55..65 in the drill's skirmish). Apply it
## before the <= max_step_pts limit and the sub-steps. Only for phases with a range_pct.
static func repair_target_pct(c: TankContent, duty: float, ph: PlanPhase) -> float:
	var base := c.num("stations", "repair.base_pct", 55.0)
	var span := c.num("stations", "repair.span_pct", 15.0)
	var pct := base + span * clampf(duty, 0.0, 1.0)
	var r := ph.effective_range()
	return clampf(pct, float(r[0]), float(r[1]))


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


# --- Pattern 3: the boiler -----------------------------------------------------------------------


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
	if _waits_for_seat(state, ri):
		want = 0.0  # the rider left the Loader; its trainer switches soon: no boiler grade
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


## Pattern 3: the boiler's mode grade in % before difficulty: grade x min(pressure, 1), with the
## warm-up grade (3%) in WARMUP-kind phases, 0 while a shell is loaded or the breech cycles.
static func boiler_grade_pct(
	c: TankContent, pressure_pct: float, warmup: bool, loaded_or_cycling: bool
) -> float:
	if loaded_or_cycling:
		return 0.0
	var key := "boiler.warmup_grade_pct" if warmup else "boiler.grade_pct"
	var grade := c.num("stations", key, 3.0 if warmup else 8.0)
	return grade * clampf(pressure_pct / 100.0, 0.0, 1.0)


# --- Pattern 5: terrain --------------------------------------------------------------------------


func _terrain_step(state: TankState, ri: TankRiderInput, ph: PlanPhase, e: int) -> void:
	if ri.phase_mode != Wl.SIM or ri.grade_source != Wl.GRADE_GAME:
		return
	if e % _ticks(content.num("stations", "terrain.send_every_s", 0.5)) != 0:
		return
	var g := 0.0
	if _waits_for_seat(state, ri):
		ctx.directives.course_grade(ri.peer, 0.0)  # the rider left Drive: flat until the switch
		return
	if state.hull.tow_s > 0.0:
		ctx.directives.course_grade(ri.peer, 0.0)  # the tow: the rider pedals flat, TankDrive too
		return
	if state.roam.active:
		g = TankRoam.grade_pct(state, ri.in_warmup())
	else:
		var seg := int(ph.meta.get("segment", ri.phase_index))
		g = terrain_grade_pct(content, seg, state.hull.distance_m, ri.in_warmup())
	ctx.directives.course_grade(ri.peer, g)


## Pattern 5: the grade under the tank `distance_m` into mission segment `segment`: the shared
## sampler `TankTerrain.for_segment`, the same function the rules roll the hull on.
static func terrain_grade_pct(
	c: TankContent, segment: int, distance_m: float, warmup: bool
) -> float:
	return TankTerrain.for_segment(c, segment, distance_m, warmup)


# --- Pattern 6: the loader's cadence band --------------------------------------------------------


func _loader_step(state: TankState, ri: TankRiderInput) -> void:
	if TankAux.of(state).cover.has(ri.peer):
		return  # a bot covers this rider's seat: its band stays as it was until it is back
	var want := false
	var r := state.rider(ri.peer)
	var seat := r.engine if r != null else ri.engine
	if seat == TankIds.ENGINE_STEAM and ri.phase_kind == Wl.WORK:
		var steam := state.station(TankIds.ENGINE_STEAM) as TankSteamState
		want = steam != null and (steam.loaded or steam.cycling)
	if want == bool(_loader.get(ri.peer, false)):
		return
	_loader[ri.peer] = want
	var key := "cadence_band.loader" if want else "cadence_band.default"
	var band: Array = content.value("stations", key, [50, 120] if want else [60, 120])
	ctx.directives.cadence_band(ri.peer, float(band[0]), float(band[1]))


# --- Pattern 7: haptics --------------------------------------------------------------------------


func _haptics(state: TankState, inputs: TankInputs, events: Array[Dictionary]) -> void:
	var kind := crew_haptic(events, content.num("stations", "haptics.hit.min_damage", 4.0))
	if kind == HAPTIC_NONE:
		return
	var cool := content.num("stations", "haptics.cooldown_s", 15.0)
	for ri in inputs.riders:
		if not haptic_allowed(ri, _phase(ri), _haptics_on(state, ri)):
			continue
		if inputs.t + EPS < float(_haptic_end.get(ri.peer, -INF)) + cool:
			continue  # inside the receiver's 15 s spacing: dropped, never queued
		var d := haptic_directive(content, kind)
		if _request(ri.peer, d):
			_haptic_end[ri.peer] = inputs.t + float(d["duration_s"])


## The haptic request of `kind` (hit or boss_hit), exactly as brief 2.7's table.
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
## receiver per tick, TankEvents doc), or HAPTIC_NONE.
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
## Drive (diesel) and Secondaries (feed) in WORK SIM phases (the tempo the in-band rule scores),
## else [0, 0] (cleared): never a tempo band in the warm-up (BRIEF 4.6.8), checkpoints or ERG, and
## never for the Loader (its 90% rule stays on the station card).
static func power_band_pct(c: TankContent, ph: PlanPhase) -> Array[float]:
	var engine := str(ph.meta.get("engine", ""))
	var drives := engine == TankIds.ENGINE_DIESEL or engine == TankIds.ENGINE_FEED
	if ph.kind != Wl.WORK or ph.mode != Wl.SIM or not drives:
		return [0.0, 0.0]
	var b: Array = c.value("tanks", "in_band.sim_ftp_pct", [76, 105])
	return [float(b[0]), float(b[1])]


## end_phase for every rider of the group's segment in one step, once the objective is done, min_s
## has passed (until then the tank holds: "Regroup"), every rider of the segment is past its own
## phase's min_s (v3: a seat switch's split phase may hold the end; TankSegments.riders_may_end)
## and the segment's `end_hold_s` (mission file, default 0; the boss uses it for the Behemoth's
## death beat) has run since the objective was done. The hold never runs the segment into max_s:
## it ends END_MARGIN_S before it, so a won mission is not scored as an overrun. A rider whose
## end_phase is refused is retried (the next tick, then once a second) until it is accepted or the
## group has moved on. Returns true on the tick it ends the segment (the first round of calls).
## (v3 solo balance) True while the segment's end waits for a solo rider the Autopilot seats: its
## minimum stay (TankSeats.auto_stay_s) still runs, it wants another seat for the next fight segment
## (TankAutopilot's solo loop), and the wait stays inside that stay + 2 s of the objective and the
## phase's max_s. Once the stay is over the seating moves it within a second.
func _solo_seat_wait(state: TankState, ph: TankPhaseInfo, done_at: float) -> bool:
	if state.riders.size() != 1:
		return false
	var r := state.riders[0]
	if not (r.fallback or r.autopilot or r.is_bot) or r.afk:
		return false
	var stay := TankSeats.auto_stay_s(state)
	var stay_left := maxf(stay - TankSeats.stay_s(state, r.peer), 0.0)
	if ph.elapsed_s - done_at > stay + 2.0:
		return false
	if ph.max_s > 0.0 and ph.elapsed_s + stay_left + 2.0 > ph.max_s - END_MARGIN_S:
		return false
	var nxt := TankAutopilot.next_fight_segment(state)
	if nxt == "":
		return false
	var want := TankAutopilot.seat_wanted_solo(state, r, TankAutopilot.expected(state, nxt), nxt)
	return want != "" and want != r.engine


func _maybe_end_phase(state: TankState, inputs: TankInputs) -> bool:
	var ph := inputs.phase
	if not ph.open_ended or ph.is_cooldown() or _ended.has(ph.index):
		return false
	if not state.seg.objective_done:
		return false
	if not _done_at.has(ph.index):
		_done_at[ph.index] = ph.elapsed_s
	if ph.elapsed_s < ph.min_s:
		return false
	var first := false
	if not _end_pending.has(ph.index):
		var hold := float(content.segment(ph.segment).get("end_hold_s", 0.0))
		var held := ph.elapsed_s - float(_done_at[ph.index]) >= hold - EPS
		var out_of_time := ph.max_s > 0.0 and ph.elapsed_s >= ph.max_s - END_MARGIN_S - EPS
		if not held and not out_of_time:
			return false
		if not TankSegments.riders_may_end(inputs):
			return false
		if not out_of_time and _solo_seat_wait(state, ph, float(_done_at[ph.index])):
			return false
		var peers: Array = []
		for ri in inputs.riders:
			if ri.segment == ph.index:
				peers.append(ri.peer)
		_end_pending[ph.index] = peers
		_end_retry_tick[ph.index] = inputs.tick
		_end_retries[ph.index] = 0
		first = true
	elif inputs.tick < int(_end_retry_tick[ph.index]):
		return false
	var here := {}
	for ri in inputs.riders:
		if ri.segment == ph.index:
			here[ri.peer] = true
	var left: Array = []
	for peer: int in _end_pending[ph.index]:
		# A rider that already moved on is never asked to end its next phase.
		if here.has(peer) and not ctx.directives.end_phase(peer):
			left.append(peer)
	if left.is_empty():
		_ended[ph.index] = true
		_end_pending.erase(ph.index)
		return first
	_end_pending[ph.index] = left
	var tries := int(_end_retries[ph.index]) + 1
	_end_retries[ph.index] = tries
	_end_retry_tick[ph.index] = inputs.tick + (1 if tries <= 1 else _ticks(END_RETRY_S))
	return first


# --- Pattern 9: seat switches (v3) ---------------------------------------------------------------


## The trainer follows every rider's seat (see the class doc). `ending`: this tick ends the
## group's segment, so nobody splits it now (the later segments carry the seat instead).
func _seat_step(state: TankState, inputs: TankInputs, ending: bool) -> void:
	var aux := TankAux.of(state)
	for ri in inputs.riders:
		var r := state.rider(ri.peer)
		var plan: EffortPlan = plans.get(ri.peer)
		if r == null:
			continue
		if plan == null or ri.phase_index < 0 or ri.phase_index >= plan.size() or ri.on_reserve():
			r.mode_wait_s = 0.0
			r.mode_to = ""
			continue
		var f := TankSeatPlan.follow(
			content,
			ri,
			r.engine,
			float(aux.last_switch_s.get(ri.peer, -INF)),
			state.t,
			ending or (state.seg.objective_done and state.seg.open_ended),
			not ending,
			r.is_bot
		)
		r.mode_wait_s = float(f["wait_s"])
		r.mode_to = str(f["mode_to"])
		var action := int(f["action"])
		if action != TankSeatPlan.FOLLOW_SPLIT and action != TankSeatPlan.FOLLOW_BOUNDARY:
			continue
		var key := "%d:%s:%d" % [ri.phase_index, r.engine, action]
		var sent: Dictionary = _seat_sent.get(ri.peer, {})
		if str(sent.get("key", "")) == key and inputs.tick < int(sent.get("retry", 0)):
			continue
		var rest: EffortPlan = f["plan"]
		var ok := (
			ctx.directives.split(ri.peer, rest)
			if action == TankSeatPlan.FOLLOW_SPLIT
			else ctx.directives.replan(ri.peer, rest)
		)
		if ok:
			plans[ri.peer] = TankSeatPlan.whole(plan, ri.phase_index, rest)
			# Sent: a boundary replan is not repeated in this phase for this seat.
			_seat_sent[ri.peer] = {"key": key, "retry": 1 << 40}
		else:
			_seat_sent[ri.peer] = {"key": key, "retry": inputs.tick + _ticks(END_RETRY_S)}


# --- Helpers -------------------------------------------------------------------------------------


## True while rider `ri` sits on another seat than the one its plan phase is set up for (its
## trainer has not yet followed the seat; pattern 9). Never while a bot covers it: the swap is the bot's,
## the plan stays the rider's own, and nothing on its trainer moves (TankBots.cover).
static func _waits_for_seat(state: TankState, ri: TankRiderInput) -> bool:
	var r := state.rider(ri.peer)
	if r == null or r.engine == "" or r.engine == ri.engine:
		return false
	return not TankAux.of(state).cover.has(ri.peer)


func _request(peer: int, fields: Dictionary) -> bool:
	var r := ctx.directives.request(peer, EffortDirective.from_dict(fields))
	return r != null and r.accepted


## Whole ticks in `seconds` (at least 1).
static func _ticks(seconds: float) -> int:
	return maxi(roundi(seconds / Wl.SIM_DT), 1)
