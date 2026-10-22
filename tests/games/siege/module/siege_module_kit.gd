class_name SiegeModuleKit
extends RefCounted
## Helpers for the module tests (B2): bare states for Autopilot, hand-made enemies, frames with
## extra intents, and a module stepped to a given game time.

const F := preload("res://tests/games/siege/siege_fakes.gd")


## A bare state (pad 3 Ballista, pad 4 Scorpion) in `role`, `humans` + `bots` riders on the
## generator, the clock at `t`.
static func state(
	role: String = SiegeIds.ROLE_WAVE, humans: int = 2, bots: int = 0, t: float = 100.0
) -> SiegeState:
	var st := SiegeState.create(F.content("short"), F.make_slots(humans, bots), Wl.FAIR_FTP, null)
	st.role = role
	st.t = t
	st.phase_kind = Wl.WORK
	return st


## Adds an enemy at `pos` (ground plane) to `st`.
static func enemy(
	st: SiegeState,
	pos: Vector2,
	hp: float = 20.0,
	type: int = SiegeIds.ENEMY_RAIDERS,
	road: int = 1
) -> SiegeEnemyState:
	var e := SiegeEnemyState.new()
	e.id = st.next_enemy_id
	st.next_enemy_id += 1
	e.type = type
	e.road = road
	e.hp = hp
	e.max_hp = hp
	e.pos = pos
	st.enemies.append(e)
	return e


## Builds `type` at `pad` with `level`.
static func tower(st: SiegeState, pad: int, type: int, level: int = 0) -> void:
	var tw := st.pad(pad)
	tw.type = type
	tw.level = level


## A configured module for `humans` + `bots` riders of `content_id`, plans built.
static func game(
	humans: int = 1,
	bots: int = 0,
	content_id: String = "short",
	role: String = Wl.SOLO,
	local_peer: int = 1
) -> SiegeGame:
	var g := F.make_game(F.make_ctx(humans, bots, content_id, role, local_peer))
	if role != Wl.CLIENT:
		g.plans = F.plans_of(g)
	return g


## Steps `g` from `tick` to game time `until_s` with no intents; returns the next tick.
static func run_to(g: SiegeGame, tick: int, until_s: float) -> int:
	return F.run(g, g.plans, tick, until_s - tick * Wl.SIM_DT)


## One sim step at `tick` with `intents` (peer -> raw intents) and optional telemetry overrides.
static func step(
	g: SiegeGame, tick: int, intents: Dictionary = {}, opts: Dictionary = {}
) -> InputFrame:
	var f := F.frame(g.ctx, g.plans, tick, 100.0, intents, opts)
	g.sim_step(Wl.SIM_DT, f)
	return f


static func directives(g: SiegeGame) -> F.Directives:
	return g.ctx.directives as F.Directives


static func hud(g: SiegeGame) -> F.Hud:
	return g.ctx.hud as F.Hud


## The toast calls recorded so far: [key, args, peer].
static func toasts(g: SiegeGame) -> Array:
	var out: Array = []
	for c: Array in hud(g).of("toast"):
		out.append([c[1], c[2], c[3]])
	return out


## A host and a client module wired like the platform does: the host's events (through JSON and
## the client's int_fields) go to apply_event, and every second tick its snapshot goes to
## apply_snapshot, then client_predict runs with the client's own telemetry.
class Link:
	extends RefCounted
	var host: SiegeGame
	var client: SiegeGame
	var queue: Array = []
	## Every event the host sent, in order.
	var sent: Array[Dictionary] = []

	func _init(p_host: SiegeGame, p_client: SiegeGame) -> void:
		host = p_host
		client = p_client
		host.game_event.connect(_on_event)

	func _on_event(e: Dictionary) -> void:
		queue.append(e)
		sent.append(e)

	## One host tick, then the delivery; returns the host's frame.
	func step(tick: int, intents: Dictionary = {}) -> InputFrame:
		var f := F.frame(host.ctx, host.plans, tick, 100.0, intents)
		host.sim_step(Wl.SIM_DT, f)
		for e: Dictionary in queue:
			client.apply_event(_wire(e, client.int_fields().get(str(e["type"]), [])))
		queue.clear()
		if tick % 2 == 0:
			client.apply_snapshot(_wire(host.snapshot(), client.int_fields()["snapshot"]))
		client.client_predict(Wl.SIM_DT, f.players[client.ctx.local_peer])
		return f

	## Runs ticks from..until_s and on to an even tick, whose snapshot has just been applied;
	## returns the next tick.
	func run(from_tick: int, until_s: float) -> int:
		var tick := from_tick
		while tick * Wl.SIM_DT < until_s or (tick - 1) % 2 != 0:
			step(tick)
			tick += 1
		return tick

	static func _wire(d: Dictionary, paths: Array) -> Dictionary:
		return Protocol.apply_int_fields(JSON.parse_string(JSON.stringify(d)), paths)
