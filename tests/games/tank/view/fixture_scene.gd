extends Control
## A windowed look at the Tank view and HUD for tools/screenshot --scene (GAME_SDK 19.3): a fixture
## state (Stage 2 Advance, its gun line or the boss fight) for the Bulwark, Rampart or Citadel in a
## PixelViewport with the real HUD on top, animated by a tiny fake of the rules (the hull drives,
## enemies keep station, shells fly, the gun fires now and then). Not a test: the view tests build the
## same thing headless.
## Options (user args or the TANK_FIXTURE environment variable, ";"-separated):
##   crew=<1..3>        the tank (default 3)
##   kind=state|gun_line|boss   the fixture (default state)
##   peer=<n>           the local rider's peer (default 1)
##   fire=<s>           seconds between shots (default 2.5, 0 for none)
##   still              the hull holds still
##   stats              print frame times after 300 frames, then quit

const F := preload("res://tests/games/tank/tank_fakes.gd")

var game: TankGame = null
var view: TankView = null
var pv: PixelViewport = null
var hud: HudLayer = null
var state: TankState = null

var _opts: Dictionary = {}
var _acc: float = 0.0
var _fire_in: float = 1.0
var _next_shell_id: int = 900
var _times: Array[float] = []
var _frames: int = 0


func _ready() -> void:
	_opts = _options()
	var crew := clampi(int(_opts.get("crew", 3)), 1, 3)
	match str(_opts.get("kind", "state")):
		"gun_line":
			state = TankFixtures.gun_line(crew)
		"boss":
			state = TankFixtures.boss(crew)
		_:
			state = TankFixtures.state(crew)
	var peer := int(_opts.get("peer", 1))
	var ctx := F.make_ctx(crew, 0, "ashfall_road", Wl.SOLO, peer)
	game = F.make_game(ctx)
	game.state = state
	pv = PixelViewport.new()
	pv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(pv)
	view = game.make_view() as TankView
	pv.set_game_view(view)
	hud = HudLayer.new()
	add_child(hud)
	hud.build(game.hud_spec(), ctx, pv)


func _process(delta: float) -> void:
	_frames += 1
	if _opts.has("stats"):
		_times.append(delta)
		if _frames == 300:
			_print_stats()
			get_tree().quit()
	_acc += delta
	while _acc >= Wl.SIM_DT:
		_acc -= Wl.SIM_DT
		_tick()
	var fire_every := float(_opts.get("fire", 2.5))
	if fire_every > 0.0:
		_fire_in -= delta
		if _fire_in <= 0.0:
			_fire_in = fire_every
			_fire()


func _tick() -> void:
	state.tick += 1
	state.t = state.tick * Wl.SIM_DT
	state.seg.elapsed_s += Wl.SIM_DT
	var dx := 0.0
	if not _opts.has("still") and not state.hull.holding:
		dx = state.hull.speed_mps * TankConst.PX_PER_M * Wl.SIM_DT
	state.hull.x_px += dx
	for e in state.enemies:
		if not e.fixed and not e.gun_line:
			e.x_px += dx
	for r in state.riders:
		r.cadence_rpm = 88.0 + 6.0 * sin(state.t * 1.3 + float(r.slot))
		r.raw_w = r.ftp * (0.9 + 0.12 * sin(state.t * 0.7 + float(r.slot)))
	for st in state.stations:
		if st is TankDynamoState:
			(st as TankDynamoState).bank = fposmod((st as TankDynamoState).bank - 0.4, 100.0)
		elif st is TankSteamState:
			(st as TankSteamState).pressure_pct = fposmod(
				(st as TankSteamState).pressure_pct + 0.8, 150.0
			)
		elif st is TankGearboxState:
			(st as TankGearboxState).hoist_j = fposmod(
				(st as TankGearboxState).hoist_j + 14.0, 4000.0
			)
	var keep: Array[TankShellState] = []
	for s in state.shells:
		s.x += s.vx * Wl.SIM_DT
		s.y += s.vy * Wl.SIM_DT
		s.vy += 300.0 * Wl.SIM_DT
		if (
			s.y < float(TankConst.GROUND_Y)
			and s.x < state.hull.x_px + 1200.0
			and s.x > state.hull.x_px - 400.0
		):
			keep.append(s)
	state.shells = keep


func _fire() -> void:
	var s := TankShellState.new()
	s.id = _next_shell_id
	_next_shell_id += 1
	s.type = TankIds.SHELL_HEAVY
	var geo := TankGeometry.load_default()
	var m := geo.muzzle(state.hull.tank, state.hull.elev_deg, state.hull.facing)
	s.x = state.hull.x_px + m.x
	s.y = float(TankConst.GROUND_Y - 10 - state.hull.hull_h) + m.y
	var v := TankBallistics.velocity(360.0, state.hull.elev_deg, state.hull.facing)
	s.vx = v.x
	s.vy = v.y
	state.shells.append(s)
	game.cue.emit(TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_HEAVY, s.id))


func _options() -> Dictionary:
	var out := {}
	var raw: Array[String] = []
	for a in OS.get_cmdline_user_args():
		raw.append(a)
	for part in OS.get_environment("TANK_FIXTURE").split(";", false):
		raw.append(part)
	for a in raw:
		var s := a.trim_prefix("--")
		var eq := s.find("=")
		if eq >= 0:
			out[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			out[s] = true
	return out


func _print_stats() -> void:
	var sorted := _times.duplicate()
	sorted.sort()
	var mean := 0.0
	for t in _times:
		mean += t
	mean /= float(maxi(_times.size(), 1))
	var low: float = 0.0
	if not sorted.is_empty():
		low = sorted[int(float(sorted.size()) * 0.99)]
	print(
		(
			"tank view fixture: mean %.2f ms, 99th percentile %.2f ms over %d frames"
			% [mean * 1000.0, low * 1000.0, _times.size()]
		)
	)
