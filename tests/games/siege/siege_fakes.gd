class_name SiegeFakes
extends RefCounted
## Shared test doubles for Siege's unit tests (every builder uses them): a GameContext whose
## sinks record every call, a stand-in for the GameHost's phase clock (fixed phases), synthetic
## InputFrames with per-peer intents, rescue and power, and content loading without a ctx.
##
## Directives can play the governor: `host_refuse` refuses every request with that reason
## (DirectiveResult.accepted false, plus the refused record on ctx.events like the router);
## `governor_refuse` accepts on the host but emits a refused applied record inside request()
## (a local rider's governor); `defer_acks` holds the records until flush_acks() (a remote rider).

const GAME_ID := "siege"
const GAME_DIR := "res://src/games/siege"
const CONTENT_DIR := "res://content/siege"


class Directives:
	extends DirectiveSink
	## [[peer, EffortDirective.to_dict()]] in call order (refused ones included).
	var requests: Array = []
	var cadence_bands: Array = []
	var course_grades: Array = []
	var ended: Array = []
	var replans: Array = []
	var host_refuse: String = ""
	var governor_refuse: String = ""
	var defer_acks: bool = false
	var bus: WlEventBus = null
	var _held: Array = []

	func request(peer: int, directive: EffortDirective) -> DirectiveResult:
		var d := directive.to_dict()
		requests.append([peer, d])
		var id := requests.size()
		if host_refuse != "":
			_emit(
				peer,
				{
					"id": id,
					"kind": "request",
					"requested": d,
					"refused": true,
					"reason": host_refuse
				}
			)
			return DirectiveResult.refused(host_refuse, id)
		var rec := {
			"id": id,
			"kind": "request",
			"requested": d,
			"applied": {"sim_block": true},
			"refused": governor_refuse != "",
			"reason": governor_refuse
		}
		if defer_acks:
			_held.append([peer, rec])
		else:
			_emit(peer, rec)
		return DirectiveResult.ok(id)

	## Emits the held records (a remote rider's acks arriving with its telemetry).
	func flush_acks() -> void:
		for h: Array in _held:
			_emit(int(h[0]), h[1])
		_held.clear()

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

	func _emit(peer: int, rec: Dictionary) -> void:
		if bus != null:
			bus.directive_applied.emit(peer, rec)


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


## Validated content for `shift_id`, read straight from content/siege (no ctx).
static func content(shift_id: String = "short") -> SiegeContent:
	return SiegeContent.from_dicts(SiegeContent.read_files(), shift_id)


## Player slots like the GameHost builds: humans 1..n (1 is the host), then bots -1..-m;
## FTP 200 + 20 x slot, verified, FAIR_FTP.
static func make_slots(humans: int = 1, bots: int = 0) -> Array[PlayerSlot]:
	var m := manifest()
	var out: Array[PlayerSlot] = []
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
		out.append(s)
	return out


## A context like the GameHost builds (ctx.events is a fresh WlEventBus: free it with
## free_ctx()).
static func make_ctx(
	humans: int = 1,
	bots: int = 0,
	content_id: String = "short",
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
	ctx.assets_dir = "res://assets/siege"
	ctx.options = option_defaults(m.get("options", []))
	ctx.events = WlEventBus.new()
	var dirs := Directives.new()
	dirs.bus = ctx.events
	ctx.directives = dirs
	ctx.hud = Hud.new()
	ctx.intents = Intents.new()
	ctx.stats = Stats.new()
	ctx.strings = GameStrings.new()
	ctx.progress = ProgressStore.open(GAME_ID, "")
	ctx.players = make_slots(humans, bots)
	return ctx


static func free_ctx(ctx: GameContext) -> void:
	if ctx != null and is_instance_valid(ctx.events):
		ctx.events.free()


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
		if t < start + ph.duration_s - 1e-9 or i == plan.size() - 1:
			s.index = i
			s.kind = ph.kind
			s.mode = ph.mode
			s.elapsed_s = t - start
			s.duration_s = ph.duration_s
			s.label = ph.label
			s.planned_pct = ph.planned_pct_at(s.elapsed_s) if ph.mode == Wl.ERG else 0.0
			s.remaining_s = maxf(ph.duration_s - s.elapsed_s, 0.0)
			s.count = plan.size()
			s.plan_elapsed_s = t
			return s
		start += ph.duration_s
	return s


## Game time at which phase `index` of `plan` starts.
static func phase_start(plan: EffortPlan, index: int) -> float:
	var t := 0.0
	for i in mini(index, plan.size()):
		t += plan.phase(i).duration_s
	return t


## One InputFrame: every rider rides `power_pct` of its planned target at 90 rpm.
## `intents`: peer -> Array of raw intents this frame; `opts`: {"power_w": {peer: W},
## "connected": {peer: bool}} overrides.
static func frame(
	ctx: GameContext,
	plans: Dictionary,
	tick: int,
	power_pct: float = 100.0,
	intents: Dictionary = {},
	opts: Dictionary = {}
) -> InputFrame:
	var f := InputFrame.new()
	f.tick = tick
	f.t = tick * Wl.SIM_DT
	var pw: Dictionary = opts.get("power_w", {})
	var conn: Dictionary = opts.get("connected", {})
	for p in ctx.players:
		var ph := phase_at(plans[p.peer_id], f.t)
		var tm := Telemetry.new()
		tm.peer_id = p.peer_id
		tm.t = f.t
		tm.mode = Wl.ERG
		tm.applied_target_w = int(ph.planned_pct / 100.0 * p.ftp)
		tm.power_w = float(pw.get(p.peer_id, tm.applied_target_w * power_pct / 100.0))
		tm.p_eff_w = tm.power_w * p.p_eff_per_w
		tm.ftp_pct = tm.power_w / p.ftp * 100.0
		tm.cadence_rpm = 90.0
		tm.phase_index = ph.index
		tm.connected = bool(conn.get(p.peer_id, true))
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


## A configured module ready to step (node not in the tree; free it with free_game()).
static func make_game(ctx: GameContext) -> SiegeGame:
	var g := SiegeGame.new()
	g.configure(ctx)
	return g


static func free_game(g: SiegeGame) -> void:
	if g == null:
		return
	free_ctx(g.ctx)
	g.free()


## SiegeInputs for the pure rules at `tick` of `plans` (peer -> plan with cool-down): every
## rider at `power_pct` of its planned target; `intents`: peer -> normalized intents.
static func inputs(
	slots: Array[PlayerSlot],
	plans: Dictionary,
	tick: int,
	power_pct: float = 100.0,
	intents: Dictionary = {}
) -> SiegeInputs:
	var f := InputFrame.new()
	f.tick = tick
	f.t = tick * Wl.SIM_DT
	for p in slots:
		var ph := phase_at(plans[p.peer_id], f.t)
		var tm := Telemetry.new()
		tm.peer_id = p.peer_id
		tm.power_w = ph.planned_pct / 100.0 * p.ftp * power_pct / 100.0
		tm.p_eff_w = tm.power_w * p.p_eff_per_w
		tm.cadence_rpm = 90.0
		f.players[p.peer_id] = tm
		f.phase[p.peer_id] = ph
	return SiegeInputs.from_frame(f, slots, plans, intents, {}, {})
