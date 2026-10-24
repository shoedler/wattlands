class_name TankFakes
extends RefCounted
## Test doubles for Tank's unit tests: a GameContext whose sinks record every call, plus stand-ins
## for the GameHost's phase clock, so the module can be driven with synthetic InputFrames without
## the platform runtime. Lead-owned (G0).
##
## Two clocks: phase_at() is a fixed nominal clock (open-ended phases run their nominal
## duration_s; for single frames and short runs), and PhaseClock follows the platform's rules
## (an open-ended phase ends on end_phase once min_s passed, else at max_s; fixed phases at
## duration_s), so whole sessions behave like the GameHost whatever the rules take.

## Longer than any session: 41 min at most (brief 2.3) plus the 180 s cool-down and a margin.
const SESSION_LIMIT_S := 2460.0 + 180.0 + 30.0

const GAME_ID := "tank"
const GAME_DIR := "res://src/games/tank"
const CONTENT_DIR := "res://content/tank"


class Directives:
	extends DirectiveSink
	## The game time of the tick being stepped (run() sets it).
	var t: float = 0.0
	## [[peer, EffortDirective.to_dict()]] in call order.
	var requests: Array = []
	## [[peer, lo_rpm, hi_rpm]]
	var cadence_bands: Array = []
	## [[t, peer, lo_rpm, hi_rpm]] (cadence_bands with the time).
	var cadence_at: Array = []
	var course_grades: Array = []
	var ended: Array = []
	## [[peer, EffortPlan]]
	var replans: Array = []

	func request(peer: int, directive: EffortDirective) -> DirectiveResult:
		requests.append([peer, directive.to_dict()])
		return DirectiveResult.ok(requests.size())

	func course_grade(peer: int, grade_pct: float) -> void:
		course_grades.append([peer, grade_pct])

	func end_phase(peer: int) -> bool:
		ended.append(peer)
		return true

	func cadence_band(peer: int, lo_rpm: float, hi_rpm: float) -> void:
		cadence_bands.append([peer, lo_rpm, hi_rpm])
		cadence_at.append([t, peer, lo_rpm, hi_rpm])

	func replan(peer: int, plan: EffortPlan) -> bool:
		replans.append([peer, plan])
		return true


class Hud:
	extends HudFeed
	## The game time of the tick being stepped (run() sets it).
	var t: float = 0.0
	## [name, args...] in call order.
	var calls: Array = []
	## [[t, peer, lo_w, hi_w]] (power_band calls with the time).
	var power_band_at: Array = []

	func power_band(peer: int, lo_w: float, hi_w: float) -> void:
		calls.append(["power_band", peer, lo_w, hi_w])
		power_band_at.append([t, peer, lo_w, hi_w])

	func teammate_status(peer: int, status: Dictionary) -> void:
		calls.append(["teammate_status", peer, status])

	func toast(key: String, args: Variant = [], peer: int = 0) -> void:
		calls.append(["toast", key, args, peer])

	func banner(key: String, args: Variant = [], seconds: float = 3.0, peer: int = 0) -> void:
		calls.append(["banner", key, args, seconds, peer])

	func readout(id: String, text: String) -> void:
		calls.append(["readout", id, text])

	func of(call_name: String) -> Array:
		return calls.filter(func(c: Array) -> bool: return c[0] == call_name)


## The GameHost's phase rules for test runs: per rider, an open-ended phase ends by end_phase (at
## the end of the tick that called it, refused before min_s) or at max_s; a fixed phase at its
## duration_s; the last phase (the cool-down) holds.
class PhaseClock:
	extends RefCounted
	## peer -> EffortPlan with the cool-down.
	var plans: Dictionary = {}
	var dirs: Directives = null
	## Every end_phase batch: {t, index, peers, elapsed_s, min_s, refused}, in order.
	var batches: Array = []
	## Every phase start: {t, peer, index, ended_by} (index 0 at t 0 included).
	var changes: Array = []
	## peer -> [index, start_t, prev_ended_by]
	var _at: Dictionary = {}
	var _seen: int = 0

	func _init(p_plans: Dictionary, p_dirs: Directives) -> void:
		plans = p_plans
		dirs = p_dirs
		for peer: int in plans:
			_at[peer] = [0, 0.0, ""]
			changes.append({"t": 0.0, "peer": peer, "index": 0, "ended_by": ""})

	## Applies the end_phase calls made since the last call, then the platform's own ends, so
	## phase() is right at game time `t` (the start of the tick about to be stepped).
	func advance(t: float) -> void:
		var peers: Array = []
		while _seen < dirs.ended.size():
			peers.append(int(dirs.ended[_seen]))
			_seen += 1
		if not peers.is_empty():
			_end_batch(peers, t)
		for peer: int in _at:
			var plan: EffortPlan = plans[peer]
			while int(_at[peer][0]) < plan.size() - 1:
				var ph := plan.phase(int(_at[peer][0]))
				var end_s := ph.max_s if ph.open_ended else ph.duration_s
				var start := float(_at[peer][1])
				if t + 1e-6 < start + end_s:
					break
				var by := Wl.ENDED_MAX_S if ph.open_ended else Wl.ENDED_DURATION
				_next(peer, start + end_s, by)

	func _end_batch(peers: Array, t: float) -> void:
		var at: Array = _at[peers[0]]
		var ph := (plans[peers[0]] as EffortPlan).phase(int(at[0]))
		var elapsed := t - float(at[1])
		var refused := not ph.open_ended or elapsed + 1e-6 < ph.min_s
		var batch := {
			"t": t,
			"index": int(at[0]),
			"peers": peers,
			"elapsed_s": elapsed,
			"min_s": ph.min_s,
			"refused": refused
		}
		batches.append(batch)
		if not refused:
			for peer: int in peers:
				_next(peer, t, Wl.ENDED_END_PHASE)

	func _next(peer: int, t: float, ended_by: String) -> void:
		var index := int(_at[peer][0]) + 1
		_at[peer] = [index, t, ended_by]
		changes.append({"t": t, "peer": peer, "index": index, "ended_by": ended_by})

	## The PhaseState of `peer` at game time `t` (call advance(t) first).
	func phase(peer: int, t: float) -> PhaseState:
		var plan: EffortPlan = plans[peer]
		var at: Array = _at[peer]
		var ph := plan.phase(int(at[0]))
		var s := PhaseState.new()
		s.index = int(at[0])
		s.kind = ph.kind
		s.mode = ph.mode
		s.elapsed_s = t - float(at[1])
		s.duration_s = ph.duration_s
		s.label = ph.label
		s.open_ended = ph.open_ended
		s.min_s = ph.min_s
		s.max_s = ph.max_s
		s.planned_pct = ph.planned_pct_at(s.elapsed_s) if ph.mode == Wl.ERG else 0.0
		var end_s := ph.max_s if ph.open_ended else ph.duration_s
		s.remaining_s = maxf(end_s - s.elapsed_s, 0.0)
		s.prev_ended_by = str(at[2])
		s.count = plan.size()
		s.plan_elapsed_s = t
		return s

	func all_in_cooldown() -> bool:
		for peer: int in _at:
			if int(_at[peer][0]) < (plans[peer] as EffortPlan).size() - 1:
				return false
		return not _at.is_empty()

	## The game time `peer` started phase `index` (-1 if it never did).
	func start_of(peer: int, index: int) -> float:
		for c: Dictionary in changes:
			if int(c["peer"]) == peer and int(c["index"]) == index:
				return float(c["t"])
		return -1.0


class Intents:
	extends IntentSink
	var sent: Array = []

	func send(intent: Dictionary) -> void:
		sent.append(intent)


class Stats:
	extends SessionStats
	## peer -> partial base row (missing keys are zeros).
	var rows: Dictionary = {}

	func base_row(peer: int) -> Dictionary:
		var row := super.base_row(peer)
		row.merge(rows.get(peer, {}), true)
		return row

	func kj(peer: int) -> float:
		return float(base_row(peer)["kj"])


static func manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(GAME_DIR.path_join("game.json")))


## Defaults of a manifest option list ({id: default}).
static func option_defaults(entries: Variant) -> Dictionary:
	var out := {}
	for e: Variant in entries if entries is Array else []:
		out[str(e["id"])] = e["default"]
	return out


## A context like the GameHost builds: humans 1..n (1 is the host). Tank has no bots; `bots` is
## kept for the scaffold's signature and must stay 0 for Tank.
static func make_ctx(
	humans: int = 1,
	bots: int = 0,
	content_id: String = "ashfall_road",
	role: String = Wl.SOLO,
	local_peer: int = 1,
	rng_seed: int = 7
) -> GameContext:
	var m := manifest()
	var ctx := GameContext.new()
	ctx.game_id = GAME_ID
	ctx.manifest = m
	ctx.content_id = content_id
	ctx.seed = rng_seed
	ctx.role = role
	ctx.local_peer = local_peer
	ctx.rng = RandomNumberGenerator.new()
	ctx.rng.seed = rng_seed
	ctx.game_dir = GAME_DIR
	ctx.content_dir = CONTENT_DIR
	ctx.assets_dir = "res://assets/tank"
	ctx.options = option_defaults(m.get("options", []))
	ctx.directives = Directives.new()
	ctx.hud = Hud.new()
	ctx.intents = Intents.new()
	ctx.stats = Stats.new()
	ctx.strings = GameStrings.new()
	ctx.progress = ProgressStore.open(GAME_ID, "")
	for i in humans + bots:
		var s := PlayerSlot.new()
		s.is_bot = i >= humans
		s.peer_id = -(i - humans + 1) if s.is_bot else i + 1
		s.name = "Bot %d" % (i - humans + 1) if s.is_bot else "Rider %d" % (i + 1)
		s.apply_look(i)
		s.ftp = 200.0 + 20.0 * i
		s.ftp_verified = true
		s.autopilot = true
		s.p_eff_per_w = 250.0 / s.ftp
		s.options = option_defaults(m.get("player_options", []))
		ctx.players.append(s)
	return ctx


## The plan with the platform's cool-down appended (what the PlanValidator returns).
static func with_cooldown(plan: EffortPlan) -> EffortPlan:
	var p := plan.duplicate_plan()
	p.add(PlanValidator.cooldown_phase())
	p.cooldown_appended = true
	return p


## The PhaseState of a fixed-length `plan` at game time `t` (the last phase holds past its end).
static func phase_at(plan: EffortPlan, t: float) -> PhaseState:
	var s := PhaseState.new()
	var start := 0.0
	for i in plan.size():
		var ph := plan.phase(i)
		if t < start + ph.duration_s or i == plan.size() - 1:
			s.index = i
			s.kind = ph.kind
			s.mode = ph.mode
			s.elapsed_s = t - start
			s.duration_s = ph.duration_s
			s.label = ph.label
			s.open_ended = ph.open_ended
			s.min_s = ph.min_s
			s.max_s = ph.max_s
			s.planned_pct = ph.planned_pct_at(s.elapsed_s) if ph.mode == Wl.ERG else 0.0
			var end_s := ph.max_s if ph.open_ended else ph.duration_s
			s.remaining_s = maxf(end_s - s.elapsed_s, 0.0)
			s.prev_ended_by = "" if i == 0 else Wl.ENDED_DURATION
			s.count = plan.size()
			s.plan_elapsed_s = t
			return s
		start += ph.duration_s
	return s


## One InputFrame: in ERG every rider rides `power_pct` of its applied target, in SIM `power_pct`
## of 90% FTP (the erg mock's SIM rule), at 90 rpm. `intents` maps peer -> Array of intents. With
## a `clock` the phases come from it (advance it first), else from phase_at().
static func frame(
	ctx: GameContext,
	plans: Dictionary,
	tick: int,
	power_pct: float = 100.0,
	intents: Dictionary = {},
	clock: PhaseClock = null
) -> InputFrame:
	var f := InputFrame.new()
	f.tick = tick
	f.t = tick * Wl.SIM_DT
	for p in ctx.players:
		var ph := clock.phase(p.peer_id, f.t) if clock != null else phase_at(plans[p.peer_id], f.t)
		var tm := Telemetry.new()
		tm.peer_id = p.peer_id
		tm.t = f.t
		tm.mode = Wl.ERG if ph.mode == Wl.ERG or ph.kind == Wl.COOLDOWN else Wl.SIM
		if tm.mode == Wl.ERG:
			tm.applied_target_w = int(ph.planned_pct / 100.0 * p.ftp)
			tm.power_w = tm.applied_target_w * power_pct / 100.0
		else:
			tm.power_w = 0.9 * p.ftp * power_pct / 100.0
		tm.p_eff_w = tm.power_w * p.p_eff_per_w
		tm.ftp_pct = tm.power_w / p.ftp * 100.0
		tm.cadence_rpm = 90.0
		tm.phase_index = ph.index
		tm.intents = (intents.get(p.peer_id, []) as Array).duplicate(true)
		f.players[p.peer_id] = tm
		f.phase[p.peer_id] = ph
	return f


## Plans from the module, each with the cool-down appended.
static func plans_of(game: GameModule) -> Dictionary:
	var out := {}
	var built := game.build_effort_plans()
	for peer: int in built:
		out[peer] = with_cooldown(built[peer])
	return out


## Steps `game` from tick `from_tick` for `seconds` of game time; returns the next tick. With a
## `clock` the phases follow the platform's rules (PhaseClock), else the nominal phase_at().
static func run(
	game: GameModule,
	plans: Dictionary,
	from_tick: int,
	seconds: float,
	power_pct: float = 100.0,
	clock: PhaseClock = null
) -> int:
	var tick := from_tick
	for _i in roundi(seconds / Wl.SIM_DT):
		_step(game, plans, tick, power_pct, clock)
		tick += 1
	return tick


## Steps `game` with a PhaseClock until every rider is in the cool-down (at most
## SESSION_LIMIT_S), then `extra_s` more; returns the next tick.
static func run_session(
	game: GameModule, clock: PhaseClock, extra_s: float = 1.0, power_pct: float = 100.0
) -> int:
	var tick := 0
	while not clock.all_in_cooldown() and tick * Wl.SIM_DT < SESSION_LIMIT_S:
		_step(game, clock.plans, tick, power_pct, clock)
		tick += 1
	return run(game, clock.plans, tick, extra_s, power_pct, clock)


## A PhaseClock over the module's plans (plans_of) and its recording directives.
static func clock_of(game: GameModule) -> PhaseClock:
	return PhaseClock.new(plans_of(game), game.ctx.directives as Directives)


static func _step(
	game: GameModule, plans: Dictionary, tick: int, power_pct: float, clock: PhaseClock
) -> void:
	var t := tick * Wl.SIM_DT
	if clock != null:
		clock.advance(t)
	if game.ctx.directives is Directives:
		(game.ctx.directives as Directives).t = t
	if game.ctx.hud is Hud:
		(game.ctx.hud as Hud).t = t
	game.sim_step(Wl.SIM_DT, frame(game.ctx, plans, tick, power_pct, {}, clock))


## A configured module ready to step (node not in the tree).
static func make_game(ctx: GameContext) -> TankGame:
	var g := TankGame.new()
	g.configure(ctx)
	return g
