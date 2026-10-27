class_name TankViewUtil
extends RefCounted
## Helpers for the view tests: fixture states for every crew size (the Bastion's 4th rider on the arc
## generator included), a TankGame around one and a TankView built from it, driven by hand.

const F := preload("res://tests/games/tank/tank_fakes.gd")


## The fixture state `kind` ("state", "gun_line" or "boss") for `crew` 1..4 (4: the Bastion, its
## fourth rider on the arc generator).
static func fixture(kind: String, crew: int) -> TankState:
	match kind:
		"gun_line":
			return TankFixtures.gun_line(crew)
		"boss":
			return TankFixtures.boss(crew)
	return TankFixtures.state(crew)


## A configured module whose state is `state` (a fixture), local peer `local_peer`.
static func make_game(state: TankState, role: String = Wl.SOLO, local_peer: int = 1) -> TankGame:
	var ctx := F.make_ctx(clampi(state.riders.size(), 1, 4), 0, "ashfall_road", role, local_peer)
	var g := F.make_game(ctx)
	g.state = state
	return g


## A view for `g`, parented under `test` (freed with it), driven by hand (no _process), advanced
## once. `size`: the canvas (art px), the base 960 x 540 by default.
static func make_view(test: GutTest, g: TankGame, size: Vector2 = Vector2(960, 540)) -> TankView:
	var v := g.make_view() as TankView
	v.auto_process = false
	v.set_canvas_size(size)
	test.add_child_autofree(v)
	v.advance(1.0 / 60.0)
	return v


## A game and its view in one call.
static func view_of(
	test: GutTest,
	state: TankState,
	role: String = Wl.SOLO,
	local_peer: int = 1,
	size: Vector2 = Vector2(960, 540)
) -> TankView:
	var g := make_game(state, role, local_peer)
	test.autofree(g)
	return make_view(test, g, size)


## Runs `frames` frames of `dt` seconds, the sim advancing with them (state.t and tick).
static func run(v: TankView, frames: int, dt: float = 1.0 / 60.0, sim: bool = true) -> void:
	for _i in frames:
		if sim:
			var s := v.game.state
			s.t += dt
			s.tick = int(s.t / Wl.SIM_DT)
		v.advance(dt)


## The rider feed {peer: Vector2(watts, cadence)} for every rider of `state`.
static func feed_of(state: TankState, watts: float, cadence: float) -> Dictionary:
	var out := {}
	for r in state.riders:
		out[r.peer] = Vector2(watts, cadence)
	return out
