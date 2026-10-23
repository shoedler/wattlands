class_name TankViewUtil
extends RefCounted
## Helpers for the view tests: a TankGame around a fixture state and a TankView built from it.

const F := preload("res://tests/games/tank/tank_fakes.gd")


## The fixture state `kind` ("state", "gun_line" or "boss") for `crew`.
static func fixture(kind: String, crew: int) -> TankState:
	match kind:
		"gun_line":
			return TankFixtures.gun_line(crew)
		"boss":
			return TankFixtures.boss(crew)
	return TankFixtures.state(crew)


## A configured module whose state is `state` (a fixture), local peer `local_peer`.
static func make_game(state: TankState, role: String = Wl.SOLO, local_peer: int = 1) -> TankGame:
	var ctx := F.make_ctx(state.crew, 0, "ashfall_road", role, local_peer)
	var g := F.make_game(ctx)
	g.state = state
	return g


## A view for `g`, parented under `test` (freed with it), driven by hand (no _process), advanced once.
static func make_view(test: GutTest, g: TankGame) -> TankView:
	var v := g.make_view() as TankView
	v.auto_process = false
	test.add_child_autofree(v)
	v.advance(1.0 / 60.0)
	return v


## A game and its view in one call.
static func view_of(
	test: GutTest, state: TankState, role: String = Wl.SOLO, local_peer: int = 1
) -> TankView:
	var g := make_game(state, role, local_peer)
	test.autofree(g)
	return make_view(test, g)


## Runs `frames` frames of `dt` seconds.
static func run(v: TankView, frames: int, dt: float = 1.0 / 60.0) -> void:
	for _i in frames:
		v.advance(dt)


## A rig built standalone with its own effects and lights (for the machinery tests).
static func make_rig(test: GutTest, tank: String, seed_value: int = 7) -> TankRig:
	var hub := TankRigHub.new()
	hub.fx = TankFx.new()
	hub.fx.seed_rng(seed_value)
	hub.lights = TankLights.new()
	test.add_child_autofree(hub.fx)
	test.add_child_autofree(hub.lights)
	var rig := TankRig.new()
	rig.setup(tank, hub)
	test.add_child_autofree(rig)
	return rig


## The rider feed {peer: Vector2(watts, cadence)} for every rider of `state`.
static func feed_of(state: TankState, watts: float, cadence: float) -> Dictionary:
	var out := {}
	for r in state.riders:
		out[r.peer] = Vector2(watts, cadence)
	return out
