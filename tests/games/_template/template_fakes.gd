class_name TemplateFakes
extends TestGameFakes
## Test doubles for the template game's unit tests: a GameContext whose sinks record every call,
## plus a tiny stand-in for the GameHost's phase clock (fixed phases only), so the module can be
## driven with synthetic InputFrames without the platform runtime.

const GAME_ID := "_template"
const GAME_DIR := "res://src/games/_template"
const CONTENT_DIR := "res://content/_template"


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

	func replan(peer: int, plan: EffortPlan) -> bool:
		replans.append([peer, plan])
		return true


static func manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(GAME_DIR.path_join("game.json")))


## A context like the GameHost builds: humans 1..n (1 is the host), then bots -1..-m.
static func make_ctx(
	humans: int = 1,
	bots: int = 0,
	content_id: String = "default",
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
	ctx.assets_dir = "res://assets/_template"
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
static func make_game(ctx: GameContext) -> TemplateGame:
	var g := TemplateGame.new()
	g.configure(ctx)
	return g
