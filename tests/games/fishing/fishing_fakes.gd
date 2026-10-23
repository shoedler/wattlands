class_name FishingFakes
extends RefCounted
## Test doubles for the fishing game's unit tests: a GameContext whose sinks record every call,
## plus two stand-ins for the GameHost's phase clock, so the module can be driven with synthetic
## InputFrames without the platform runtime:
##   - phase_at() / frame() / run(): stateless, fixed phases only (an open-ended phase runs its
##     nominal duration_s);
##   - Clock (clock_for()): the platform's own PhaseTracker, as the GameHost drives it. Open-ended
##     phases end at max_s; ctx.directives.end_phase() after min_s ends the phase at the end of
##     that tick (the next frame shows the next phase; before min_s it is refused and returns
##     false); finished() moves every rider to the cool-down at the end of the tick; the
##     cool-down's end marks the rider done. Telemetry follows the latest ERG request of the
##     current phase (else the planned target), so whole trips run with the stub rules or the
##     real ones.

const GAME_ID := "fishing"
const GAME_DIR := "res://src/games/fishing"
const CONTENT_DIR := "res://content/fishing"


class Directives:
	extends DirectiveSink
	## [[peer, EffortDirective.to_dict()]] in call order.
	var requests: Array = []
	## [[peer, lo_rpm, hi_rpm]]
	var cadence_bands: Array = []
	var course_grades: Array = []
	var ended: Array = []
	## [[peer, EffortPlan]]
	var replans: Array = []
	## [[peer, refusal]] of end_phase calls a Clock refused.
	var refused_ends: Array = []
	## Set by a Clock: end_phase goes through its PhaseTracker (min_s, open-ended only).
	var tracker: PhaseTracker = null

	func request(peer: int, directive: EffortDirective) -> DirectiveResult:
		requests.append([peer, directive.to_dict()])
		return DirectiveResult.ok(requests.size())

	func course_grade(peer: int, grade_pct: float) -> void:
		course_grades.append([peer, grade_pct])

	func end_phase(peer: int) -> bool:
		if tracker != null:
			var why := tracker.request_end(peer)
			if why != "":
				refused_ends.append([peer, why])
				return false
		ended.append(peer)
		return true

	func cadence_band(peer: int, lo_rpm: float, hi_rpm: float) -> void:
		cadence_bands.append([peer, lo_rpm, hi_rpm])

	func replan(peer: int, plan: EffortPlan) -> bool:
		replans.append([peer, plan])
		return true


class Hud:
	extends HudFeed
	## [name, args...] in call order.
	var calls: Array = []

	func power_band(peer: int, lo_w: float, hi_w: float) -> void:
		calls.append(["power_band", peer, lo_w, hi_w])

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


## A context like the GameHost builds: humans 1..n (1 is the host), then bots -1..-m.
static func make_ctx(
	humans: int = 1,
	bots: int = 0,
	content_id: String = "e2e_2min",
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
	ctx.assets_dir = "res://assets/fishing"
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
		s.autopilot = s.is_bot
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
			s.remaining_s = maxf(ph.duration_s - s.elapsed_s, 0.0)
			s.count = plan.size()
			s.plan_elapsed_s = t
			return s
		start += ph.duration_s
	return s


## One InputFrame: every rider rides `power_pct` of its applied target in ERG at 90 rpm.
## `intents` maps peer -> Array of intents for this frame.
static func frame(
	ctx: GameContext,
	plans: Dictionary,
	tick: int,
	power_pct: float = 100.0,
	intents: Dictionary = {}
) -> InputFrame:
	var f := InputFrame.new()
	f.tick = tick
	f.t = tick * Wl.SIM_DT
	for p in ctx.players:
		var ph := phase_at(plans[p.peer_id], f.t)
		var tm := Telemetry.new()
		tm.peer_id = p.peer_id
		tm.t = f.t
		tm.mode = Wl.ERG
		tm.applied_target_w = int(ph.planned_pct / 100.0 * p.ftp)
		tm.power_w = tm.applied_target_w * power_pct / 100.0
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


## Steps `game` from tick `from_tick` for `seconds` of game time; returns the next tick.
static func run(
	game: GameModule, plans: Dictionary, from_tick: int, seconds: float, power_pct: float = 100.0
) -> int:
	var tick := from_tick
	for _i in roundi(seconds / Wl.SIM_DT):
		game.sim_step(Wl.SIM_DT, frame(game.ctx, plans, tick, power_pct))
		tick += 1
	return tick


## A configured module ready to step (node not in the tree).
static func make_game(ctx: GameContext) -> FishingGame:
	var g := FishingGame.new()
	g.configure(ctx)
	return g


## A GameHost-like phase clock over the platform's PhaseTracker for `game` (its plans with the
## cool-down appended, or `plans` when given). Free it with the game (RefCounted).
static func clock_for(game: FishingGame, plans: Dictionary = {}) -> Clock:
	var c := Clock.new()
	c.setup(game, plans if not plans.is_empty() else plans_of(game))
	return c


class Clock:
	extends RefCounted
	var game: FishingGame = null
	var ctx: GameContext = null
	var tracker: PhaseTracker = PhaseTracker.new()
	var plans: Dictionary = {}
	## The next game tick to simulate.
	var tick: int = 0
	## Riders ride this % of the applied ERG target (SIM phases: this % of FTP).
	var power_pct: float = 100.0
	var sim_power_pct: float = 100.0
	## peer -> cadence (default 90 rpm).
	var cadence: Dictionary = {}
	## peer -> % FTP of the latest ERG request in the current phase.
	var applied_pct: Dictionary = {}
	## [{peer, index, ended_by, t}] for every phase change after the start.
	var changes: Array = []
	var finished_reasons: Array = []
	var _seen_requests: int = 0

	func setup(p_game: FishingGame, p_plans: Dictionary) -> void:
		game = p_game
		ctx = p_game.ctx
		plans = p_plans
		for p in ctx.players:
			tracker.add_rider(p.peer_id, plans[p.peer_id])
		tracker.start()
		(ctx.directives as Directives).tracker = tracker
		game.finished.connect(_on_finished)

	func _on_finished(reason: String) -> void:
		finished_reasons.append(reason)
		tracker.finish_all()

	## The InputFrame the GameHost would build for `tick`.
	func frame(intents: Dictionary = {}) -> InputFrame:
		var f := InputFrame.new()
		f.tick = tick
		f.t = tick * Wl.SIM_DT
		for p in ctx.players:
			var ph := tracker.state(p.peer_id)
			var tm := Telemetry.new()
			tm.peer_id = p.peer_id
			tm.t = f.t
			tm.mode = ph.mode if ph.mode != "" else Wl.ERG
			if tm.mode == Wl.ERG:
				var pct := float(applied_pct.get(p.peer_id, ph.planned_pct))
				tm.applied_target_w = int(pct / 100.0 * p.ftp)
				tm.power_w = tm.applied_target_w * power_pct / 100.0
			else:
				tm.power_w = p.ftp * sim_power_pct / 100.0
			tm.p_eff_w = tm.power_w * p.p_eff_per_w
			tm.ftp_pct = tm.power_w / p.ftp * 100.0
			tm.cadence_rpm = float(cadence.get(p.peer_id, 90.0))
			tm.phase_index = ph.index
			tm.intents = (intents.get(p.peer_id, []) as Array).duplicate(true)
			f.players[p.peer_id] = tm
			f.phase[p.peer_id] = ph
		return f

	## One tick: sim_step, then the tracker applies the tick's end_phase, max_s, duration and
	## finished like the GameHost.
	func step(intents: Dictionary = {}) -> void:
		game.sim_step(Wl.SIM_DT, frame(intents))
		var reqs: Array = (ctx.directives as Directives).requests
		while _seen_requests < reqs.size():
			var r: Array = reqs[_seen_requests]
			var d: Dictionary = r[1]
			if str(d.get("mode", Wl.ERG)) == Wl.ERG and d.has("target_pct"):
				applied_pct[int(r[0])] = float(d["target_pct"])
			_seen_requests += 1
		for c: Dictionary in tracker.advance(tick):
			applied_pct.erase(int(c["peer"]))
			changes.append(
				{"peer": c["peer"], "index": c["index"], "ended_by": c["ended_by"], "t": tick_t()}
			)
		tick += 1

	func run(seconds: float) -> void:
		for _i in roundi(seconds / Wl.SIM_DT):
			step()

	## Steps until every rider finished its cool-down (or `max_s` of game time); true when done.
	func run_until_done(max_s: float) -> bool:
		var limit := tick + roundi(max_s / Wl.SIM_DT)
		while not tracker.all_done() and tick < limit:
			step()
		return tracker.all_done()

	func tick_t() -> float:
		return (tick + 1) * Wl.SIM_DT

	func index_of(peer: int) -> int:
		return tracker.index_of(peer)

	## Labels of the phases `peer` entered, in order (the start included).
	func labels(peer: int) -> Array:
		return tracker.history(peer).map(func(h: Dictionary) -> String: return str(h["label"]))
