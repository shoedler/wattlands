extends Control
## A windowed look at the Tank view and HUD for tools/screenshot --scene (GAME_SDK 19.3): a fixture
## state (Stage 2 Advance, its gun line or the boss fight) for a crew of 1 to 4 (v3: one tank) in a
## PixelViewport with the real HUD on top (or none), animated by a tiny fake of the rules (the hull drives,
## enemies keep station, shells fly, the gun fires now and then). Not a test: the view tests build the
## same thing headless.
## Options (user args or the TANK_FIXTURE environment variable, ";"-separated):
##   crew=<1..4>        the tank (default 3; 4 is the Citadel's fixture with an arc-generator rider)
##   flex               pixel_flex on (min 852 x 480), as the GameHost sets it
##   nohud              no HUD (the picker and content cards are rendered this way)
##   nopip              no shell screen (the cards too)
##   kind=state|gun_line|boss|cap|roam|v4:<name>   the fixture (default state); cap is the Citadel at
##                      the snapshot caps, 16 enemies and 24 shells always in view, the gun firing every
##                      0.4 s; roam is free roam on roam_30's valley (TankViewUtil.roam_state) with the
##                      free-roam HUD; v4:<name> is TankFixturesV4 (SPEC_TANK section 7), moved by its
##                      tick(), no gun firing unless fire= says so
##   dir=-1             (roam) the tank drives west: the world drawn mirrored
##   at=<m>             (roam) the hull's place on the valley road in metres (default its middle)
##   zone=<id>          (roam) the hull in the middle of that zone (lake, village, quarry, meadow, forest)
##   peer=<n>           the local rider's peer (default 1)
##   fire=<s>           seconds between shots (default 2.5, 0 for none)
##   shot_frame=<n>     (with fire=0) the main gun fires on frame n (a firing still with --frames)
##   bow=<n>            the bow guns fire n rounds a second (the feed's round count)
##   sec                the Lights rider moves to the Secondaries seat
##   empty=<engine>     that station's seat empty (slot -1), e.g. empty=arc
##   still              the hull holds still
##   wreck=<m>          a far wreck at that range (m) from frame 3, for a look at it closing in as the hull
##                      drives and dropping out of the far panel at its near edge (TankFarMap.RANGE_NEAR_M)
##   speed=<m/s>        the hull's speed, held (the fixtures' own is 7.4)
##   noenemy            no enemy and no shell on the field (the wreck's frames)
##   stats              print frame times after 300 frames (or seconds=<n> of wall time), then quit
##   seconds=<n>        with stats: measure for n seconds of wall time instead of 300 frames
##   novsync            vsync off, so stats read the real frame time and not the display's 16.7 ms

const F := preload("res://tests/games/tank/tank_fakes.gd")
const U := preload("res://tests/games/tank/view/tank_view_util.gd")

var game: TankGame = null
var view: TankView = null
var pv: PixelViewport = null
var hud: HudLayer = null
var state: TankState = null

var _opts: Dictionary = {}
var _acc: float = 0.0
var _bow_acc: float = 0.0
var _fire_in: float = 1.0
var _next_shell_id: int = 900
var _times: Array[float] = []
var _frames: int = 0
var _elapsed: float = 0.0
var _stats_done: bool = false
## The TankFixturesV4 name of this run ("" for the older kinds).
var _v4: String = ""
var _v4_cues_due: bool = false


func _ready() -> void:
	_opts = _options()
	if _opts.has("novsync"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var crew := clampi(int(_opts.get("crew", 3)), 1, 4)
	var content := "ashfall_road"
	var kind_opt := str(_opts.get("kind", "state"))
	var bots := 0
	if kind_opt.begins_with("v4:"):
		_v4 = kind_opt.trim_prefix("v4:")
		_v4_cues_due = true
		state = TankFixturesV4.make(_v4, crew)
		# the cap fixture fills every field for the snapshot's size: its frame is the crowded field, not a tow
		if _v4 == "cap_v4":
			state.hull.tow_s = 0.0
		content = TankFixturesV4.content_id(_v4)
		crew = state.riders.size()
		for r in state.riders:
			if r.is_bot:
				bots += 1
		crew -= bots
		if not _opts.has("fire"):
			_opts["fire"] = "0"
	match kind_opt if _v4 == "" else "v4":
		"v4":
			pass
		"cap":
			state = _cap_state()
			if not _opts.has("fire"):
				_opts["fire"] = "0.4"
		"roam":
			content = "roam_30"
			var dir := -1 if int(_opts.get("dir", 1)) < 0 else 1
			state = U.roam_state(crew, dir, float(_opts.get("at", -1.0)))
			if _opts.has("zone"):
				for z: Dictionary in state.roam_map.zones:
					if str(z["id"]) == str(_opts["zone"]):
						state.roam.map_m = (float(z["from_m"]) + float(z["to_m"])) * 0.5
						break
		var kind:
			state = U.fixture(kind, crew)
	if _opts.has("sec"):
		var arc := state.station(TankIds.ENGINE_ARC)
		var sec := state.station(TankIds.ENGINE_FEED)
		if arc != null and sec != null and not arc.is_empty():
			sec.slot = arc.slot
			sec.peer = arc.peer
			arc.slot = -1
			arc.peer = 0
	if _opts.has("empty"):
		var st := state.station(str(_opts["empty"]))
		if st != null:
			st.slot = -1
			st.peer = 0
	if _opts.has("noenemy"):
		state.enemies.clear()
		state.shells.clear()
	var peer := int(_opts.get("peer", 1))
	var ctx := F.make_ctx(crew, bots, content, Wl.SOLO, peer)
	game = F.make_game(ctx)
	game.state = state
	pv = PixelViewport.new()
	pv.pixel_base = Vector2i(960, 540)
	if _opts.has("flex"):
		pv.flex_min = Vector2i(852, 480)
	pv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(pv)
	view = game.make_view() as TankView
	pv.set_game_view(view)
	if _opts.has("nopip") and view.pip != null:
		view.pip.visible = false
	if _opts.has("nohud"):
		return
	hud = HudLayer.new()
	add_child(hud)
	hud.build(game.hud_spec(), ctx, pv)


func _process(delta: float) -> void:
	_frames += 1
	if _opts.has("wreck") and _frames == 3:
		(
			view
			. far
			. wrecks
			. append(
				{
					"range": float(_opts["wreck"]),
					"lane": 0,
					"kind": TankIds.ENEMY_MEDIUM,
					"t": state.t,
				}
			)
		)
	if _opts.has("speed"):
		state.hull.speed_mps = float(_opts["speed"])
	if _v4_cues_due and _frames >= 2:
		_v4_cues_due = false
		for e: Dictionary in TankFixturesV4.cues(_v4):
			game.cue.emit(str(e["type"]), e)
	if _opts.has("stats"):
		_times.append(delta)
		_elapsed += delta
		var seconds := float(_opts.get("seconds", 0.0))
		if (seconds > 0.0 and _elapsed >= seconds) or (seconds <= 0.0 and _frames == 300):
			_print_stats()
			get_tree().quit()
	_acc += delta
	while _acc >= Wl.SIM_DT:
		_acc -= Wl.SIM_DT
		_tick()
	if _opts.has("shot_frame") and _frames == int(_opts["shot_frame"]):
		_fire()
	var bow := float(_opts.get("bow", 0.0))
	if bow > 0.0:
		_bow_acc += delta * bow
		var feed := state.station(TankIds.ENGINE_FEED) as TankFeedState
		if feed != null:
			feed.rpm = bow * 60.0
		while _bow_acc >= 1.0:
			_bow_acc -= 1.0
			if feed != null:
				feed.rounds += 1
				feed.fire_tick = state.tick
	var fire_every := float(_opts.get("fire", 2.5))
	if fire_every > 0.0:
		_fire_in -= delta
		if _fire_in <= 0.0:
			_fire_in = fire_every
			_fire()


func _tick() -> void:
	if _v4 != "":
		TankFixturesV4.tick(state, Wl.SIM_DT)
		return
	state.tick += 1
	state.t = state.tick * Wl.SIM_DT
	state.seg.elapsed_s += Wl.SIM_DT
	var dx := 0.0
	if not _opts.has("still") and not state.hull.holding:
		dx = state.hull.speed_mps * TankConst.PX_PER_M * Wl.SIM_DT
	state.hull.x_px += dx
	if state.roam.active and state.roam_map != null:
		state.roam.map_m = clampf(
			state.roam.map_m + dx / TankConst.PX_PER_M * float(state.hull.dir),
			state.roam_map.lo_m,
			state.roam_map.hi_m
		)
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
	if str(_opts.get("kind", "state")) == "cap":
		_top_up_cap()


## The Citadel at the caps (TankConst.MAX_ENEMIES enemies, MAX_SHELLS shells), placed where the camera
## sees them: enemies on both sides of the hull, shells arcing over the field.
func _cap_state() -> TankState:
	var s := TankFixtures.cap()
	s.hull.x_px = 5000.0
	for i in s.enemies.size():
		var e := s.enemies[i]
		var side := 1 if i % 2 == 0 else -1
		e.x_px = s.hull.x_px + float(side) * (150.0 + 55.0 * floorf(float(i) * 0.5))
		e.mode = TankIds.EM_TELEGRAPH
		e.telegraph_s = 3.0
	return s


## Keeps every cap slot busy: shells reborn in the air above the hull, enemies held in telegraph.
func _top_up_cap() -> void:
	for e in state.enemies:
		e.telegraph_s = 3.0
	while state.shells.size() < TankConst.MAX_SHELLS:
		var i := _next_shell_id
		_next_shell_id += 1
		var s := TankShellState.new()
		s.id = i
		s.type = TankIds.SHELL_HEAVY
		s.x = state.hull.x_px - 300.0 + float((i * 97) % 900)
		s.y = float(TankConst.GROUND_Y) - 260.0 - float((i * 31) % 120)
		s.vx = 220.0 * (1.0 if i % 2 == 0 else -1.0)
		s.vy = -80.0
		s.friendly = i % 2 != 0
		state.shells.append(s)


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


## tools/screenshot may quit first (--frames, with vsync off): the frames so far still count.
func _exit_tree() -> void:
	if _opts.has("stats") and not _stats_done and not _times.is_empty():
		_print_stats()


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
	_stats_done = true
	var sorted := _times.duplicate()
	sorted.sort()
	var mean := 0.0
	for t in _times:
		mean += t
	mean /= float(maxi(_times.size(), 1))
	var low: float = 0.0
	if not sorted.is_empty():
		low = sorted[int(float(sorted.size()) * 0.99)]
	var over := 0
	for t in _times:
		if t > 1.0 / 60.0 + 0.0005:
			over += 1
	var worst: float = 0.0 if sorted.is_empty() else sorted.back()
	var fmt := "tank view fixture: mean %.2f ms, p99 %.2f ms, worst %.2f ms, "
	fmt += "%d of %d frames over 16.7 ms, %d enemies, %d shells, %d draw calls"
	var calls := RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)
	print(
		(
			fmt
			% [
				mean * 1000.0,
				low * 1000.0,
				worst * 1000.0,
				over,
				_times.size(),
				state.enemies.size(),
				state.shells.size(),
				calls
			]
		)
	)
