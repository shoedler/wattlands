class_name TankViewUtil
extends RefCounted
## Helpers for the view tests: fixture states for every crew size (the Bastion's 4th rider on the arc
## generator included), a TankGame around one and a TankView built from it, driven by hand.

const F := preload("res://tests/games/tank/tank_fakes.gd")
const ENGINE_ARC := "arc"


## The fixture state `kind` ("state", "gun_line" or "boss") for `crew` 1..4. Crew 4 is the Citadel's
## fixture plus a fourth rider on the arc generator and the Bastion's hull (the contracts builder adds
## the real one).
static func fixture(kind: String, crew: int) -> TankState:
	var base := clampi(crew, 1, 3)
	var s: TankState
	match kind:
		"gun_line":
			s = TankFixtures.gun_line(base)
		"boss":
			s = TankFixtures.boss(base)
		_:
			s = TankFixtures.state(base)
	if crew >= 4:
		add_arc_rider(s)
	return s


## Adds slot 3 (peer 4) on the arc generator's station and makes the hull the Bastion.
static func add_arc_rider(s: TankState) -> void:
	var r := TankRiderState.new()
	r.slot = 3
	r.peer = 4
	r.engine = ENGINE_ARC
	r.ftp = 260.0
	r.raw_w = 170.0
	r.cadence_rpm = 88.0
	r.ftp_pct = 65.0
	r.in_band = true
	s.riders.append(r)
	var st := TankStationState.make(ENGINE_ARC)
	st.slot = 3
	st.peer = 4
	st.in_band = true
	s.stations.append(st)
	s.crew = 4
	s.hull.tank = "bastion"


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
