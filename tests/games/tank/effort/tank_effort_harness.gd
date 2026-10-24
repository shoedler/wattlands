extends RefCounted
## Drives one TankDirector tick by tick with hand-built TankInputs, the way TankGame does after
## TankRules.step, and records every call with its tick. Effort-owned test helper (no class_name;
## preload it). Every rider stands in the phase index passed to step(); the phase's elapsed time
## counts from the tick that index was first stepped, and plan_elapsed_s is the phase's nominal
## start (the sum of the earlier phases' duration_s) plus that elapsed time, unless overridden.

const F := preload("res://tests/games/tank/tank_fakes.gd")

var ctx: GameContext = null
var content: TankContent = null
## peer -> EffortPlan (without the cool-down, as the module keeps them).
var plans: Dictionary = {}
var state: TankState = null
var director: TankDirector = null
var tick: int = 0
## [tick, peer, request dict, phase index] for every request.
var requests: Array = []
## [tick, peer, grade, phase index] for every course_grade.
var grades: Array = []
## [tick, peer, lo, hi, phase index] for every cadence_band.
var bands: Array = []
## [tick, peer] for every end_phase.
## The plan_elapsed_s of the latest step.
var plan_elapsed: float = 0.0
var ended: Array = []
## Overrides plan_elapsed_s at the phase start (-1: the nominal start).
var plan_start_s: float = -1.0
## The applied mode each rider reports (default: the phase's own mode).
var applied_mode: Dictionary = {}
## peer -> true for riders on reserve (AFK).
var afk: Dictionary = {}
## peer -> false for a dropped rider (default connected).
var connected: Dictionary = {}
## peer -> the ERG target in % FTP the rider's governor holds (default: none reported, 0 W).
var held_pct: Dictionary = {}

var _index: int = -1
var _index_tick: int = 0


## A director over `crew` riders on `mission` (FTP 200, 220, 240, all verified).
func build(crew: int, mission: String = "ashfall_road", rotation: bool = true) -> void:
	ctx = F.make_ctx(crew, 0, mission)
	content = TankFixtures.content(mission)
	plans = TankPlanBuilder.build_all(content, ctx.players, rotation)
	state = TankState.create(content, ctx.players, mission, rotation, ctx.rng)
	director = TankDirector.new(ctx, content, plans)


func dirs() -> F.Directives:
	return ctx.directives as F.Directives


func hud() -> F.Hud:
	return ctx.hud as F.Hud


func plan(peer: int) -> EffortPlan:
	return plans[peer]


## The nominal plan start of phase `index` (sum of the earlier duration_s).
func nominal_start(index: int) -> float:
	var t := 0.0
	var p: EffortPlan = plans[ctx.players[0].peer_id]
	for i in mini(index, p.size()):
		t += p.phase(i).duration_s
	return t


## The peer of the rider on `engine` in phase `index` (0 if none).
func peer_on(engine: String, index: int) -> int:
	for p in ctx.players:
		var pl: EffortPlan = plans[p.peer_id]
		if index < pl.size() and str(pl.phase(index).meta.get("engine", "")) == engine:
			return p.peer_id
	return 0


## One director tick with every rider in phase `index` (plan.size() is the cool-down).
func step(index: int, events: Array[Dictionary] = []) -> void:
	if index != _index:
		_index = index
		_index_tick = tick
	var elapsed := float(tick - _index_tick) * Wl.SIM_DT
	var start := plan_start_s if plan_start_s >= 0.0 else nominal_start(index)
	plan_elapsed = start + elapsed
	var inp := inputs(index, elapsed, plan_elapsed)
	var d := dirs()
	var n_req := d.requests.size()
	var n_grade := d.course_grades.size()
	var n_band := d.cadence_bands.size()
	var n_end := d.ended.size()
	d.t = inp.t
	hud().t = inp.t
	director.step(state, inp, events)
	for i in range(n_req, d.requests.size()):
		requests.append([tick, d.requests[i][0], d.requests[i][1], index])
	for i in range(n_grade, d.course_grades.size()):
		grades.append([tick, d.course_grades[i][0], d.course_grades[i][1], index])
	for i in range(n_band, d.cadence_bands.size()):
		var b: Array = d.cadence_bands[i]
		bands.append([tick, b[0], b[1], b[2], index])
	for i in range(n_end, d.ended.size()):
		ended.append([tick, d.ended[i]])
	tick += 1


## `n` ticks in phase `index` (no events).
func run(index: int, n: int) -> void:
	for _i in n:
		step(index)


## Seconds of ticks in phase `index`.
func run_s(index: int, seconds: float) -> void:
	run(index, roundi(seconds / Wl.SIM_DT))


## TankInputs with every rider in phase `index`, `elapsed` s in, `at_plan_s` s into the plan.
func inputs(index: int, elapsed: float, at_plan_s: float) -> TankInputs:
	var inp := TankInputs.new()
	inp.tick = tick
	inp.t = tick * Wl.SIM_DT
	var ps := phase_state(plans[ctx.players[0].peer_id], index, elapsed, at_plan_s)
	inp.phase = TankPhaseInfo.from_phase(
		ps, TankInputs.meta_of(plans[ctx.players[0].peer_id], index)
	)
	for p in ctx.players:
		var pl: EffortPlan = plans[p.peer_id]
		var ri := TankRiderInput.new()
		ri.peer = p.peer_id
		ri.slot = p.slot_index
		ri.ftp = p.ftp
		ri.ftp_verified = p.ftp_verified
		var rps := phase_state(pl, index, elapsed, at_plan_s)
		ri.phase_index = rps.index
		ri.phase_kind = rps.kind
		ri.phase_mode = rps.mode
		ri.plan_elapsed_s = at_plan_s
		ri.engine = str(TankInputs.meta_of(pl, index).get("engine", ""))
		ri.grade_source = TankInputs.grade_source_of(pl, index)
		ri.mode = str(applied_mode.get(p.peer_id, rps.mode))
		ri.power_w = 0.9 * p.ftp
		ri.cadence_rpm = 90.0
		ri.connected = bool(connected.get(p.peer_id, true))
		ri.afk = bool(afk.get(p.peer_id, false)) or not ri.connected
		if held_pct.has(p.peer_id):
			var f := 1.0 if p.ftp_verified else 0.85
			ri.applied_target_w = float(held_pct[p.peer_id]) / 100.0 * p.ftp * f
		inp.riders.append(ri)
	return inp


## The PhaseState of phase `index` of `pl` (the standard cool-down past its end).
static func phase_state(pl: EffortPlan, index: int, elapsed: float, at_plan_s: float) -> PhaseState:
	var ph := pl.phase(index) if index < pl.size() else PlanValidator.cooldown_phase()
	var s := PhaseState.new()
	s.index = index
	s.kind = ph.kind
	s.mode = ph.mode
	s.elapsed_s = elapsed
	s.duration_s = ph.duration_s
	s.label = ph.label
	s.open_ended = ph.open_ended
	s.min_s = ph.min_s
	s.max_s = ph.max_s
	s.planned_pct = ph.planned_pct_at(elapsed) if ph.mode == Wl.ERG else 0.0
	s.count = pl.size() + 1
	s.plan_elapsed_s = at_plan_s
	return s


## The requests sent to `peer` with `reason` ([tick, dict]).
func sent(peer: int, reason: String) -> Array:
	var out: Array = []
	for r: Array in requests:
		if int(r[1]) == peer and str((r[2] as Dictionary).get("reason", "")) == reason:
			out.append([r[0], r[2]])
	return out


## The course grades sent to `peer` ([tick, grade]).
func grades_of(peer: int) -> Array:
	var out: Array = []
	for g: Array in grades:
		if int(g[1]) == peer:
			out.append([g[0], g[2]])
	return out


## The cadence bands sent to `peer` ([tick, lo, hi]).
func bands_of(peer: int) -> Array:
	var out: Array = []
	for b: Array in bands:
		if int(b[1]) == peer:
			out.append([b[0], b[2], b[3]])
	return out


func clear() -> void:
	requests.clear()
	grades.clear()
	bands.clear()
	ended.clear()
