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


## A free-roam state (brief 2.10) for `crew` 1..4: `content_id` on the valley of `seed_value`, 400 s into
## the roam phase, the hull's centre at map metre `map_m` (the middle of the road when negative)
## travelling `dir`, every rider pedalling, a light ahead in its weave, a medium holding ahead in the
## far lane and a destroyer behind (no RNG: fixed numbers).
static func roam_state(
	crew: int,
	dir: int = TankIds.DIR_RIGHT,
	map_m: float = -1.0,
	seed_value: int = 7,
	content_id: String = "roam_30"
) -> TankState:
	var c := TankFixtures.content(content_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var s := TankRules.new_state(c, TankFixtures.slots(crew), content_id, rng)
	s.rng = null
	var segs := c.segments()
	s.seg.seg = TankIds.SEG_ROAM
	s.seg.stage = 1
	s.seg.phase_index = 1
	s.seg.segment_index = 1
	s.seg.kind = Wl.WORK
	s.seg.elapsed_s = 400.0
	s.seg.min_s = float(segs[1]["min_s"])
	s.seg.max_s = float(segs[1]["max_s"])
	s.seg.open_ended = true
	s.tick = 14000
	s.t = 700.0
	s.hull.x_px = 24000.0
	s.hull.distance_m = s.hull.x_px / TankConst.PX_PER_M
	s.hull.speed_mps = 7.5
	s.hull.dir = dir
	s.hull.facing = TankIds.FACE_RIGHT
	s.roam.map_m = map_m if map_m >= 0.0 else s.roam_map.length_m * 0.5
	s.roam.points = 120
	s.roam.work_s = 400.0
	for r in s.riders:
		r.raw_w = 0.9 * r.ftp
		r.cadence_rpm = 90.0
		r.ftp_pct = 90.0
		r.target_pct = 90.0
		r.in_band = true
	var front := s.hull.x_px + float(s.hull.hull_w)
	s.enemies.append(_roam_enemy(s, 301, TankIds.ENEMY_LIGHT, front + 120.0, 1, 0))
	s.enemies.append(_roam_enemy(s, 302, TankIds.ENEMY_MEDIUM, front + 250.0, 1, 1))
	s.enemies.append(_roam_enemy(s, 303, TankIds.ENEMY_DESTROYER, s.hull.x_px - 101.0, -1, 1))
	return s


static func _roam_enemy(
	s: TankState, id: int, type: String, x: float, side: int, lane: int
) -> TankEnemyState:
	var def := s.content.enemy_def(type)
	var e := TankEnemyState.new()
	e.id = id
	e.code = TankIds.enemy_code(type)
	e.w = int(def["size_px"][0])
	e.h = int(def["size_px"][1])
	e.hp_max = float(def["hp"]) * s.content.enemy_scale(s.hull.tank)
	e.hp = e.hp_max * 0.7
	e.x_px = x
	e.side = side
	e.lane = lane
	e.mode = TankIds.EM_HOLD
	return e


## A configured module on a free-roam content around `state` (its ctx's content is `content_id`).
static func roam_game(
	state: TankState, content_id: String = "roam_30", local_peer: int = 1
) -> TankGame:
	var ctx := F.make_ctx(clampi(state.riders.size(), 1, 4), 0, content_id, Wl.SOLO, local_peer)
	var g := F.make_game(ctx)
	g.state = state
	return g
