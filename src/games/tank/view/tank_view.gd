class_name TankView
extends Node2D
## The 2D view (docs/games/tank.md 3): the reference's night diorama at 960 x 540 art px from the v2
## kit (TankKit). make_view() returns this Node2D; the PixelViewport shows it. It only reads
## TankGame.state and the cue events; it never writes the state.
##
## Layers, back to front (all under `stage`, which is offset vertically on taller or shorter
## canvases): the planes (far: sky, Milky Way, mountains, the pale cliff and the misty lake; the
## forest; the road; TankWorldDraw), the world on the road (the halt line, obstacles, wrecks aging on
## sim time, enemies in depth lanes, the Behemoth), the tank (TankHullDraw: the variant for the crew
## size cut from the reference, its barrel at the gun's elevation and traverse, running gear,
## the machines in the rooms in sync with their riders, crew, plaques, bow guns), the additive light
## (TankLightDraw: room lamps in slot colours, beams, position lights, fires, flashes, shells), the
## smoke and the foreground plane, the tilt-shift shading; then the per-frame depth of field
## (TankDof) over the whole canvas.
##
## Scale: the rules' 640 x 360 units x 1.5 (TankView.sx/sy). The art tank is a little longer than
## the rules' hull, so the hull's span maps onto the art hull and the ground ahead onto the rest of
## the base canvas; a wider canvas (pixel_flex) keeps that scale and shows more world on the right,
## a narrower one squeezes the ground ahead so the rules' screen still fits.
##
## Time: positions come from a snapshot history (TankSnapHistory) drawn at TankRenderClock.render_t
## (a client records one entry per applied snapshot, the host and SOLO one per sim tick). Machines
## turn by their rider's cadence integrated over render time; cosmetic randomness comes from
## TankFx.rng, seeded from ctx.seed.
##
## Hooks: play_evade(kind) (the evade lurch or smoke screen; the `evade` cue calls it too),
## power_ratio(rider) (watts over the rider's target), set_canvas_size(size) (tests), and the HUD's
## geometry (hud_world_x, hud_ground_y, hud_tank_point, hud_enemy_rect, hud_boss_rect,
## hud_boss_muzzle), found through the game's meta TankHudGeom.VIEW_META, which the view sets.

const BASE := Vector2(960, 540)
## Rules px -> art px.
const S := 1.5
## The road's ground line (stage y) and where enemies stand on it.
const GROUND := 340.0
const ROAD_ENEMY_Y := 343.0
## The variant's top-left on the base canvas (the reference's framing).
const TANK_POS := Vector2(6, 107)
## The hull's rear in variant px.
const ART_REAR := 18.0
## Of a canvas wider than the base, this share moves the tank inward (the rest shows more world).
const WIDE_SHIFT := 0.3
## The road band (stage y): sharp under the depth of field; the HUD keeps clear of it.
const BAND := Vector2(150, 360)
## The rooms with a machine (and a rider), rear to front.
const MACHINE_ROOMS: Array[String] = ["diesel", "steam", "dynamo", "arc"]
const MAX_WRECKS := 8
## Depth lanes on the road (each LANE_LIFT art px further back, dimmer).
const LANES := 4
## How much higher each lane further back stands (art px): enough that sprites of neighbouring
## lanes read as one behind the other at a crowded gun line (the Bastion's short field).
const LANE_LIFT := 15.0
## A wreck burns as a hulk this long, then collapses into a heap over WRECK_COLLAPSE_S; its fire
## dies over WRECK_BURN_S; it is gone after WRECK_GONE_S (or once it scrolled off).
const WRECK_HULK_S := 5.0
const WRECK_COLLAPSE_S := 3.0
const WRECK_BURN_S := 30.0
const WRECK_GONE_S := 240.0
const MAX_CUES_PER_FRAME := 24
const CUE_QUEUE_MAX := 64

var game: TankGame = null
var audio: TankAudio = null
## Turn off to drive advance() yourself (tests, screenshots).
var auto_process: bool = true
var kit: TankKit = null
var fx: TankFx = TankFx.new()
var crew: TankCrew = TankCrew.new()
var dof: TankDof = null
var history: TankSnapHistory = TankSnapHistory.new()
var clock: TankRenderClock = TankRenderClock.new()
var stage: Node2D = null
## Fixed canvas size (tests); zero = the viewport's (the PixelViewport's art size).
var canvas_override: Vector2 = Vector2.ZERO

# --- Per frame (read by the draw classes and the tests) ---------------------------------------------------
## The canvas (art px) and the stage's vertical offset on it.
var canvas: Vector2 = BASE
var y_off: float = 0.0
## The camera's world x (rules px) and the frame's scroll (art px).
var cam_x: float = 0.0
var scroll_px: float = 0.0
var variant: String = "tank_3rider"
## The variant's top-left this frame (stage px; shake and lurch included) and without them.
var origin: Vector2 = TANK_POS
var tank_pos: Vector2 = TANK_POS
## Room engine -> the rider working it (TankRiderState), from state.stations.
var room_riders: Dictionary = {}
## Room engine -> crank revolutions / power ratio / cadence.
var phases: Dictionary = {}
var powers: Dictionary = {}
var cadences: Dictionary = {}
## Room id -> Rect2 (variant px) of the current variant.
var room_rects: Dictionary = {}
## Enemy id -> Rect2 (stage px) as drawn, and its depth lane.
var enemy_rects: Dictionary = {}
var lanes: Dictionary = {}
## {x: world x of its middle, kind, lane, side, t: sim time of the kill}.
var wrecks: Array[Dictionary] = []
var recoil: float = 0.0
## The barrel's swing during a traverse: 1 facing right .. -1 facing left.
var barrel_dir: float = 1.0
## Hit shake (decays) and the evade lurch / smoke screen timers (s; < 0 when idle).
var shake: float = 0.0
var lurch_s: float = -1.0
var screen_s: float = -1.0
var frames: int = 0
## The view's own frame clock (s): flicker and drift only.
var time: float = 0.0
var dt: float = 0.0

var _built: bool = false
var _layers: Dictionary = {}
var _last_tick: int = -1
var _last_render_t: float = -1.0
var _last_sim_t: float = -1.0
var _prev_cam_px: float = 0.0
var _cam_primed: bool = false
var _traverse_from: float = 0.0
var _seen: Dictionary = {}
var _shell_seen: Dictionary = {}
var _cues: Array[Dictionary] = []
var _smoke_acc: float = 0.0
var _dust_acc: float = 0.0
var _steam_acc: float = 0.0
var _gun_shots: int = 0


func _ready() -> void:
	audio = TankAudio.new()
	audio.game = game
	add_child(audio)
	if game != null:
		game.cue.connect(audio.on_cue)
		game.cue.connect(_on_cue)
		game.snapshot_applied.connect(_on_snapshot_applied)
	_build()


func _process(delta: float) -> void:
	if auto_process:
		advance(delta)


# --- Build ---------------------------------------------------------------------------------------------


func _build() -> void:
	if _built or game == null or game.state == null:
		return
	_built = true
	kit = TankKit.shared()
	var ctx := game.ctx
	fx.seed_rng(ctx.seed if ctx != null else 1)
	if ctx != null:
		clock.min_delay_s = (
			TankRenderClock.CLIENT_DELAY_S
			if ctx.role == Wl.CLIENT
			else TankRenderClock.HOST_DELAY_S
		)
	stage = Node2D.new()
	stage.name = "Stage"
	add_child(stage)
	for n: String in ["Back", "World", "Tank", "Light", "Front", "Post"]:
		var l := Node2D.new()
		l.name = n
		if n == "Light":
			var m := CanvasItemMaterial.new()
			m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			l.material = m
		stage.add_child(l)
		_layers[n] = l
	(_layers["Back"] as Node2D).draw.connect(_draw_back)
	(_layers["World"] as Node2D).draw.connect(_draw_world)
	(_layers["Tank"] as Node2D).draw.connect(_draw_tank)
	(_layers["Light"] as Node2D).draw.connect(_draw_light)
	(_layers["Front"] as Node2D).draw.connect(_draw_front)
	(_layers["Post"] as Node2D).draw.connect(_draw_post)
	dof = TankDof.new()
	dof.enabled = miniature_option()
	add_child(dof)
	# The HUD's world tags find the view here (TankHudGeom.VIEW_META).
	game.set_meta(TankHudGeom.VIEW_META, self)


func _exit_tree() -> void:
	if (
		game != null
		and game.has_meta(TankHudGeom.VIEW_META)
		and game.get_meta(TankHudGeom.VIEW_META) == self
	):
		game.remove_meta(TankHudGeom.VIEW_META)


## The local rider's `miniature` player option (default on).
func miniature_option() -> bool:
	if game == null or game.ctx == null:
		return true
	var me := game.ctx.local_player()
	if me == null:
		return true
	return bool(me.options.get("miniature", true))


## Turns the per-frame depth of field on or off (the option; the auto-off still applies).
func set_miniature(on: bool) -> void:
	if dof != null:
		dof.enabled = on


func set_canvas_size(size: Vector2) -> void:
	canvas_override = size


func layer(n: String) -> Node2D:
	return _layers.get(n, null)


# --- Frame ---------------------------------------------------------------------------------------------


## One frame of `delta` seconds: history and render clock, layout, riders and machines, cues,
## effects, the layers' redraw and the audio.
func advance(delta: float) -> void:
	if game == null or game.state == null:
		return
	_build()
	if not _built:
		return
	var state := game.state
	frames += 1
	dt = minf(delta, 0.1)
	time += dt
	_poll_history(state)
	clock.advance(delta, history)
	var rt := clock.render_t
	var render_dt := 0.0
	if _last_render_t >= 0.0 and clock.is_set():
		render_dt = clampf(rt - _last_render_t, 0.0, 0.25)
	_last_render_t = rt
	var sim_adv := 0.0
	if _last_sim_t >= 0.0:
		sim_adv = maxf(state.t - _last_sim_t, 0.0)
	_last_sim_t = state.t
	if dof != null:
		dof.note_frame(delta, sim_adv)
	_layout(state)
	var hull_x := history.hull_x_at(rt, state.hull.x_px) if clock.is_set() else state.hull.x_px
	cam_x = hull_x - float(TankConst.REAR_SCREEN_X)
	var cam_px := cam_x * S
	scroll_px = cam_px - _prev_cam_px if _cam_primed else 0.0
	if absf(scroll_px) > 200.0:
		scroll_px = 0.0
	_prev_cam_px = cam_px
	_cam_primed = true
	var feed := rider_feed(state, rt)
	_riders(state, feed, render_dt)
	_turret(state)
	_motion(dt)
	_process_cues(state)
	_track_enemies(state)
	_age_wrecks(state)
	_emit(state, feed, dt)
	fx.step(dt, scroll_px)
	if dof != null:
		dof.update(canvas, BAND + Vector2(y_off, y_off))
	for l: Node2D in _layers.values():
		l.queue_redraw()
	if audio != null:
		audio.update(state, delta, game.ctx.local_peer if game.ctx != null else 0, feed)


func _layout(state: TankState) -> void:
	canvas = canvas_size()
	y_off = roundf((canvas.y - BASE.y) * 0.5)
	if stage != null:
		stage.position = Vector2(0, y_off)
	variant = TankKit.variant_for(state.hull.tank, state.crew)
	if _arc_station(state) != null:
		variant = "tank_4rider"
	if not kit.variants.has(variant):
		variant = "tank_3rider"
	tank_pos = Vector2(TANK_POS.x + maxf(canvas.x - BASE.x, 0.0) * WIDE_SHIFT, TANK_POS.y)
	room_rects.clear()
	for room: Dictionary in kit.rooms(variant):
		room_rects[str(room["id"])] = TankKit.rect_of(room)


## The canvas the view draws on (art px): the override, else the PixelViewport's SubViewport.
func canvas_size() -> Vector2:
	if canvas_override != Vector2.ZERO:
		return canvas_override
	var vp := get_viewport() if is_inside_tree() else null
	if vp is SubViewport:
		return Vector2((vp as SubViewport).size)
	return BASE


func _arc_station(state: TankState) -> TankStationState:
	for st in state.stations:
		if st.engine == TankIds.ENGINE_ARC:
			return st
	return null


# --- Mapping -------------------------------------------------------------------------------------------


## World x (rules px) -> stage x (art px).
func sx(world_x: float) -> float:
	var s := world_x - cam_x
	var rear := float(TankConst.REAR_SCREEN_X)
	var rf := rear + float(game.state.hull.hull_w)
	var art_rear := tank_pos.x + ART_REAR
	var front := tank_pos.x + kit.anchor(variant, "headlight").x
	if s <= rf:
		return art_rear + (s - rear) * (front - art_rear) / maxf(rf - rear, 1.0)
	var right := minf(canvas.x, BASE.x) - 20.0 + (tank_pos.x - TANK_POS.x)
	var k := (right - front) / maxf(float(TankConst.SCREEN_W) - rf, 1.0)
	return front + (s - rf) * k


## World y (rules px) -> stage y.
func sy(world_y: float) -> float:
	return GROUND - (float(TankConst.GROUND_Y) - world_y) * S


## A variant anchor in stage px (this frame's origin).
func anchor(name: String) -> Vector2:
	return origin + kit.anchor(variant, name)


# --- History and time ---------------------------------------------------------------------------------


func _on_snapshot_applied(tick: int) -> void:
	if game != null and game.state != null:
		history.push(tick, game.state)
		_last_tick = tick


## The host and SOLO have no snapshot signal: record every sim tick the state reaches.
func _poll_history(state: TankState) -> void:
	if state.tick != _last_tick:
		history.push(state.tick, state)
		_last_tick = state.tick


## The x an enemy is drawn at (world, left edge).
func enemy_x(e: TankEnemyState) -> float:
	return history.enemy_x_at(e.id, clock.render_t, e.x_px) if clock.is_set() else e.x_px


func boss_x(state: TankState) -> float:
	return history.boss_x_at(clock.render_t, state.boss.x_px) if clock.is_set() else state.boss.x_px


## Where a shell is drawn (world).
func shell_pos(s: TankShellState) -> Vector2:
	var live := Vector2(s.x, s.y)
	return history.shell_at(s.id, clock.render_t, live) if clock.is_set() else live


## peer -> Vector2(raw_w, cadence): live for the host, SOLO and the local rider, the interpolated
## snapshot values for the other riders on a client.
func rider_feed(state: TankState, t: float) -> Dictionary:
	var out := {}
	var client := game.ctx != null and game.ctx.role == Wl.CLIENT
	var me := game.ctx.local_peer if game.ctx != null else 0
	for r in state.riders:
		var live := Vector2(r.raw_w, r.cadence_rpm)
		if client and r.peer != me and clock.is_set():
			live = history.rider_at(r.peer, t, live)
		out[r.peer] = live
	return out


# --- Riders and machines --------------------------------------------------------------------------------


## The power the machines show: watts over the rider's target (1 = in band, 0.84-1.17): raw W /
## (target_pct / 100 x FTP), the host's TankRiderState.target_pct; %FTP over the SIM band's centre
## (TankMech.rider_power) while it is 0 (no phase yet).
static func power_ratio(r: TankRiderState) -> float:
	if r == null:
		return 0.0
	if r.target_pct > 0.0 and r.ftp > 0.0:
		return clampf(r.raw_w / (r.ftp * r.target_pct / 100.0), 0.0, 1.6)
	return TankMech.rider_power(r.ftp_pct)


## The room an engine works in (the Bulwark's gearbox diesel is the diesel room).
static func room_of(engine: String) -> String:
	return TankIds.ENGINE_DIESEL if engine == TankIds.ENGINE_BULWARK else engine


func _riders(state: TankState, feed: Dictionary, render_dt: float) -> void:
	room_riders.clear()
	for st in state.stations:
		if st.slot < 0:
			continue
		var r := state.rider_at(st.slot)
		if r != null:
			room_riders[room_of(st.engine)] = r
	if state.stations.is_empty():
		for r2 in state.riders:
			if r2.engine != "":
				room_riders[room_of(r2.engine)] = r2
	for e: String in MACHINE_ROOMS:
		var r3: TankRiderState = room_riders.get(e, null)
		var rpm := 0.0
		if r3 != null:
			var f: Vector2 = feed.get(r3.peer, Vector2(r3.raw_w, r3.cadence_rpm))
			rpm = f.y if f.y > 1.0 else 0.0
		cadences[e] = rpm
		phases[e] = float(phases.get(e, 0.0)) + rpm / 60.0 * render_dt
		powers[e] = power_ratio(r3)


## The rider of a room's engine, or null.
func rider_of(engine: String) -> TankRiderState:
	return room_riders.get(engine, null)


## Crank revolutions of a room's machine (its rider's cadence integrated over render time).
func machine_phase(engine: String) -> float:
	return float(phases.get(engine, 0.0))


func machine_power(engine: String) -> float:
	return float(powers.get(engine, 0.0))


## How bright the searchlights are (0.15..1): the Bastion's follow its arc generator (lit while its
## rider is in band, dimmed when stalled or out of band, TankArcState); the others are always lit.
func searchlight_k(state: TankState) -> float:
	var arc := _arc_station(state) as TankArcState
	if arc == null:
		return 1.0
	if state.hull.breakdown or arc.stalled or arc.unpowered:
		return 0.15
	return 1.0 if arc.lit else 0.3


func _turret(state: TankState) -> void:
	var h := state.hull
	var face := 1.0 if h.facing == TankIds.FACE_RIGHT else -1.0
	if h.traverse_s > 0.0:
		_traverse_from = maxf(_traverse_from, h.traverse_s)
		var p := 1.0 - h.traverse_s / maxf(_traverse_from, 0.001)
		barrel_dir = face * cos(p * PI)
	else:
		_traverse_from = 0.0
		barrel_dir = face


func _motion(step_dt: float) -> void:
	recoil = maxf(recoil - step_dt * 6.0, 0.0)
	shake = maxf(shake - step_dt * 3.0, 0.0)
	var off := Vector2.ZERO
	if shake > 0.0:
		off = Vector2(roundf(sin(time * 61.0) * 2.0 * shake), roundf(cos(time * 47.0) * shake))
	if lurch_s >= 0.0:
		lurch_s += step_dt
		# A surge forward and a settle back over 1.2 s.
		var k := lurch_s / 1.2
		off.x += roundf(sin(minf(k, 1.0) * PI) * 6.0)
		if lurch_s > 1.2:
			lurch_s = -1.0
	if screen_s >= 0.0:
		screen_s += step_dt
		if screen_s > 6.0:
			screen_s = -1.0
	origin = tank_pos + off


# --- Public effects -------------------------------------------------------------------------------------


## The evade effect (docs/games/tank.md 2.4): "lurch" (the diesel or the Bulwark surges the tank
## forward with a burst of dust) or "smoke" (the steam boiler blows a smoke screen). The `evade` cue
## with ok 1 calls it; the module may call it too.
func play_evade(kind: String) -> void:
	if not _built:
		return
	if kind == "smoke":
		screen_s = 0.0
		var vent := anchor("exhaust") + Vector2(40, -6)
		for i in 26:
			var j := fx.rng.randf()
			fx.puff(
				vent + Vector2(i * 9.0, fx.rng.randf_range(-6.0, 6.0)),
				Vector2(fx.rng.randf_range(10.0, 40.0), fx.rng.randf_range(-10.0, 2.0)),
				5.0 + j * 2.0,
				Vector2(10.0, 50.0 + j * 20.0),
				0.4,
				Color(0.62, 0.62, 0.6).lerp(Color(0.5, 0.48, 0.45), j),
				0.6
			)
	else:
		lurch_s = 0.0
		var rear := Vector2(origin.x + ART_REAR + 30.0, GROUND - 2.0)
		for i in 10:
			fx.puff(
				rear + Vector2(i * 8.0, 0),
				Vector2(fx.rng.randf_range(-30.0, -10.0), fx.rng.randf_range(-12.0, -4.0)),
				1.6,
				Vector2(4.0, 18.0),
				0.35,
				Color(0.36, 0.3, 0.24),
				1.0
			)


# --- Cues -----------------------------------------------------------------------------------------------


func _on_cue(kind: String, data: Dictionary) -> void:
	if _cues.size() >= CUE_QUEUE_MAX:
		_cues.pop_front()
	_cues.append({"kind": kind, "data": data})


func _process_cues(state: TankState) -> void:
	var n := 0
	while not _cues.is_empty() and n < MAX_CUES_PER_FRAME:
		var c: Dictionary = _cues.pop_front()
		apply_cue(state, str(c["kind"]), c["data"])
		n += 1


## One event's effects (shots, hits, kills, the evade, breakdowns).
func apply_cue(state: TankState, kind: String, data: Dictionary) -> void:
	match kind:
		TankEvents.SHOT:
			_cue_shot(state, data)
		TankEvents.HIT:
			_cue_hit(state, data)
		TankEvents.KILL:
			_cue_kill(state, data)
		TankEvents.EVADE:
			if int(data.get("ok", 0)) == 1:
				play_evade(evade_kind(state, int(data.get("s", -1))))
		TankEvents.BREAKDOWN:
			shake = 1.0
			fx.boom(anchor("exhaust") + Vector2(30, 40), 18.0, 8)


## How the evade looks (brief 2.4), from the evade event's `s`, the slot whose surge made the shot
## miss: on the steam engine the boiler blows a smoke screen; on the diesel or the Bulwark (or an
## unknown slot) the tank lurches.
func evade_kind(state: TankState, slot: int) -> String:
	var st := state.station_of(slot) if slot >= 0 else null
	if st != null and st.engine == TankIds.ENGINE_STEAM:
		return "smoke"
	return "lurch"


func _cue_shot(state: TankState, data: Dictionary) -> void:
	var sh := int(data.get("sh", 0))
	var slot := int(data.get("s", -1))
	if slot >= 0 and sh in [TankIds.SHELL_LIGHT, TankIds.SHELL_HEAVY, TankIds.SHELL_OVER]:
		var d := barrel_vector()
		var m := muzzle()
		var r := 34.0 if sh != TankIds.SHELL_LIGHT else 26.0
		fx.flash(m + d * 4.0, r, 0.16, Color(1.0, 0.7, 0.3), d)
		fx.light_scene(m, 1.0 if sh != TankIds.SHELL_LIGHT else 0.7, Color(1.0, 0.72, 0.4))
		recoil = 1.0
		_gun_shots += 1
		for i in 4:
			fx.puff(
				m + d * (6.0 + i * 6.0),
				d * (10.0 + i * 6.0) + Vector2(0, -6.0),
				1.6,
				Vector2(4.0, 16.0 + i * 2.0),
				0.35,
				Color(0.3, 0.28, 0.26),
				0.5
			)
	elif slot >= 0 and sh == TankIds.SHELL_BOW:
		_bow_burst()
	elif slot < 0:
		var src := int(data.get("src", 0))
		var e := state.enemy(src)
		if e != null and enemy_rects.has(src):
			var er: Rect2 = enemy_rects[src]
			var mz := enemy_muzzle(e, er)
			var dir := Vector2.RIGHT if e.side < 0 else Vector2.LEFT
			fx.flash(mz, 18.0, 0.12, Color(1.0, 0.55, 0.25), dir)
			fx.light_scene(mz, 0.35, Color(1.0, 0.55, 0.25))
		elif sh == TankIds.SHELL_BOSS_MAIN:
			var bm := boss_rect(state).position + boss_muzzle()
			fx.flash(bm - Vector2(4, 0), 40.0, 0.18, Color(1.0, 0.55, 0.25), Vector2.LEFT)
			fx.light_scene(bm, 0.8, Color(1.0, 0.55, 0.25))


## The bow guns' burst: a flash at each muzzle, a stream of tracers at the nearest enemy ahead (or
## down the road) and brass falling from the breeches.
func _bow_burst() -> void:
	var target := Vector2.ZERO
	var best := INF
	var front := anchor("headlight").x
	for id: int in enemy_rects:
		var r: Rect2 = enemy_rects[id]
		var cx := r.get_center().x
		if cx > front and cx - front < best:
			best = cx - front
			target = r.get_center() + Vector2(0, r.size.y * 0.1)
	for n: String in ["bow_gun_upper_muzzle", "bow_gun_lower_muzzle"]:
		var m := anchor(n)
		fx.flash(m, 12.0, 0.08, Color(1.0, 0.8, 0.4), Vector2.RIGHT)
		var tgt := target if target != Vector2.ZERO else m + Vector2(260, 14)
		for i in 3:
			var jitter := Vector2(fx.rng.randf_range(-6, 6), fx.rng.randf_range(-4, 4))
			fx.tracer(m, tgt + jitter, Color(1.0, 0.78, 0.35), 0.18 + 0.07 * i)
		fx.casing(m + Vector2(-24, 2), GROUND - 2.0)
		fx.casing(m + Vector2(-26, 3), GROUND - 2.0)
	if target != Vector2.ZERO:
		fx.spark_burst(target, 5, Color(1.0, 0.8, 0.4), 50.0)


func _cue_hit(state: TankState, data: Dictionary) -> void:
	var on := int(data.get("on", -1))
	var id := int(data.get("id", 0))
	var dmg := float(data.get("dmg", 0))
	if on == TankEvents.ON_TANK:
		shake = clampf(0.4 + dmg / 12.0, 0.4, 1.0)
		var p := origin + Vector2(kit.anchor(variant, "headlight").x - 30.0, 120.0)
		fx.boom(p + Vector2(fx.rng.randf_range(-60, 10), fx.rng.randf_range(-40, 10)), 14.0, 4)
		return
	if on == TankEvents.ON_ENEMY and enemy_rects.has(id):
		var r: Rect2 = enemy_rects[id]
		fx.boom(r.get_center() + Vector2(fx.rng.randf_range(-8, 8), 0), 16.0, 4)
		return
	if on == TankEvents.ON_BOSS and state.boss.phase != TankIds.BOSS_NONE:
		var br := boss_rect(state)
		var part := TankBossState.part_of(id)
		var at := br.get_center()
		var meta: Dictionary = kit.enemies.get("behemoth", {}).get("meta", {})
		if part >= 0 and part < 3:
			var b: Array = meta.get("bogies_at", [])
			if part < b.size():
				at = br.position + br.size * TankKit.vec(b[part])
		elif part == TankBossState.TURRET_PART:
			at = br.position + br.size * TankKit.vec(meta.get("turret_at", [0.6, 0.3]))
		fx.boom(at, 22.0, 6)
		return
	var x := float(data.get("x", 0))
	if x != 0.0:
		fx.boom(Vector2(sx(x), GROUND - 18.0), 16.0, 4)


func _cue_kill(state: TankState, data: Dictionary) -> void:
	var id := int(data.get("id", 0))
	if int(data.get("e", 0)) == TankIds.BOSS_CODE:
		var br := boss_rect(state)
		for i in 5:
			fx.boom(br.position + br.size * Vector2(0.2 + 0.15 * i, 0.5 + 0.08 * (i % 2)), 40.0, 8)
		fx.light_scene(br.get_center(), 1.0, Color(1.0, 0.5, 0.2))
		return
	if not _seen.has(id):
		return
	var w: Dictionary = (_seen[id] as Dictionary).duplicate()
	w["t"] = state.t
	wrecks.append(w)
	while wrecks.size() > MAX_WRECKS:
		wrecks.pop_front()
	if enemy_rects.has(id):
		var r: Rect2 = enemy_rects[id]
		fx.boom(r.get_center(), 30.0, 8)
		fx.light_scene(r.get_center(), 0.6, Color(1.0, 0.5, 0.2))


# --- Enemies and wrecks ---------------------------------------------------------------------------------


func enemy_kind(e: TankEnemyState) -> String:
	var k := TankIds.enemy_of(e.code)
	return k if kit.enemies.has(k) else "medium"


## Depth lanes (brief 2.4 Spacing): each live enemy is drawn in the lane the rules hold it in
## (TankEnemyState.lane, in the snapshot), 0 the front lane .. LANES - 1 the back one, so the view
## and the rules agree on who stands where (the rules keep held positions in a lane apart).
func _lanes(state: TankState) -> Dictionary:
	var out := {}
	for e in state.enemies:
		if e.mode != TankIds.EM_DEAD:
			out[e.id] = clampi(e.lane, 0, LANES - 1)
	return out


func _track_enemies(state: TankState) -> void:
	lanes = _lanes(state)
	enemy_rects.clear()
	for e in state.enemies:
		if not lanes.has(e.id):
			continue
		var lane := int(lanes[e.id])
		var sz: Vector2 = kit.enemies[enemy_kind(e)]["size"]
		var mid := enemy_x(e) + float(e.w) * 0.5
		var lift := LANE_LIFT * float(lane) + (6.0 if enemy_kind(e) == "dugin" else 0.0)
		var r := Rect2(
			Vector2(roundf(sx(mid) - sz.x * 0.5), roundf(ROAD_ENEMY_Y - sz.y - lift)), sz
		)
		enemy_rects[e.id] = r
		_seen[e.id] = {"x": mid, "kind": enemy_kind(e), "lane": lane, "side": e.side}
	for id: int in _seen.keys():
		if state.enemy(id) == null:
			_seen.erase(id)


## A wreck's age (sim seconds).
func wreck_age(w: Dictionary) -> float:
	return game.state.t - float(w["t"])


## 0 a burning hulk .. 1 a collapsed debris heap.
func wreck_collapse(w: Dictionary) -> float:
	return clampf((wreck_age(w) - WRECK_HULK_S) / WRECK_COLLAPSE_S, 0.0, 1.0)


## How hard it still burns (1 .. 0).
func wreck_fire(w: Dictionary) -> float:
	return clampf(1.0 - wreck_age(w) / WRECK_BURN_S, 0.0, 1.0)


func _age_wrecks(state: TankState) -> void:
	var keep: Array[Dictionary] = []
	for w in wrecks:
		var age := state.t - float(w["t"])
		if age < 0.0 or age > WRECK_GONE_S or sx(float(w["x"])) < -260.0:
			continue
		keep.append(w)
	wrecks = keep


## Where an enemy's gun fires from (stage px).
func enemy_muzzle(e: TankEnemyState, r: Rect2) -> Vector2:
	var m: Vector2 = kit.enemies[enemy_kind(e)]["muzzle"]
	if e.side < 0:
		return Vector2(r.end.x - m.x, r.position.y + m.y)
	return r.position + m


## The Behemoth's sprite (stage px): its left edge where the rules have it (boss.x_px, no clamp),
## standing on the road, so its parts are drawn where the rules hit them (rigs.json boss is the
## kit sprite in rules px).
func boss_rect(state: TankState) -> Rect2:
	var sz: Vector2 = kit.enemies.get("behemoth", {}).get("size", Vector2(583, 297))
	return Rect2(Vector2(roundf(sx(boss_x(state))), roundf(ROAD_ENEMY_Y + 4.0 - sz.y)), sz)


func boss_muzzle() -> Vector2:
	return kit.enemies.get("behemoth", {}).get("muzzle", Vector2(16, 140))


func boss_visible(state: TankState) -> bool:
	return state.boss.phase != TankIds.BOSS_NONE and state.boss.phase != TankIds.BOSS_WITHDRAWN


# --- The gun --------------------------------------------------------------------------------------------


## The barrel's angle (radians, screen: negative is up) at the gun's elevation.
func barrel_angle() -> float:
	return -deg_to_rad(game.state.hull.elev_deg)


## The barrel's unit direction (stage px), facing and traverse included.
func barrel_vector() -> Vector2:
	var a := barrel_angle()
	return Vector2(cos(a) * barrel_dir, sin(a))


## The pivot the barrel turns on (stage px): mirrored about the turret's pivot while it faces left.
func barrel_pivot() -> Vector2:
	var piv := anchor("barrel_pivot")
	var tp := anchor("turret_pivot")
	var u := (barrel_dir + 1.0) * 0.5
	return Vector2(lerpf(2.0 * tp.x - piv.x, piv.x, u), piv.y)


func muzzle() -> Vector2:
	var blen := kit.anchor(variant, "muzzle").x - kit.anchor(variant, "barrel_pivot").x
	return barrel_pivot() + barrel_vector() * blen


# --- Emitters (view-only) --------------------------------------------------------------------------------


func _emit(state: TankState, feed: Dictionary, step_dt: float) -> void:
	var hull := state.hull
	# The diesel's exhaust by watts: more and darker puffs as the rider pushes.
	var rd := rider_of(TankIds.ENGINE_DIESEL)
	var w := 0.0
	if rd != null:
		w = (feed.get(rd.peer, Vector2(rd.raw_w, rd.cadence_rpm)) as Vector2).x
	var rate := 3.0 + w / 30.0
	_smoke_acc += step_dt * rate
	var ex := anchor("exhaust")
	var soot := clampf(w / 400.0, 0.0, 1.0)
	while _smoke_acc >= 1.0:
		_smoke_acc -= 1.0
		var j := fx.rng.randf()
		fx.puff(
			ex + Vector2(j * 3.0 - 1.5, 0),
			Vector2(-12.0 - j * 10.0, -14.0 - j * 6.0 - soot * 6.0),
			6.0 + j * 2.0,
			Vector2(6.0, 52.0 + j * 22.0),
			0.12 + 0.1 * soot,
			Color(0.42, 0.42, 0.44).lerp(Color(0.2, 0.18, 0.16), soot * 0.7).lerp(
				Color(0.48, 0.41, 0.35), j * 0.4
			),
			0.3
		)
	# Steam: a plume from the boiler's stack while the steam rider pedals, the safety valve over band.
	if room_rects.has("steam"):
		var sr: Rect2 = room_rects["steam"]
		var pw := machine_power(TankIds.ENGINE_STEAM)
		var cad := float(cadences.get(TankIds.ENGINE_STEAM, 0.0))
		_steam_acc += step_dt * (cad / 30.0 + (6.0 if pw > 1.18 else 0.0))
		while _steam_acc >= 1.0:
			_steam_acc -= 1.0
			var top := origin + Vector2(sr.end.x - 6.0, sr.position.y - 34.0)
			var over := pw > 1.18
			fx.puff(
				top + Vector2(fx.rng.randf_range(-2, 2), 0),
				Vector2(-6.0, -22.0 - (14.0 if over else 0.0)),
				2.2,
				Vector2(3.0, 16.0 if over else 10.0),
				0.16 if over else 0.08,
				Color(0.78, 0.8, 0.82),
				0.3
			)
	# Dust and mud from the tracks at speed; burning wrecks smoke.
	var px_s := hull.speed_mps * TankConst.PX_PER_M * S
	_dust_acc += step_dt * clampf(px_s / 8.0, 0.0, 6.0)
	while _dust_acc >= 1.0:
		_dust_acc -= 1.0
		var rw: Dictionary = kit.spec(variant).get("anchors", {}).get("road_wheel_line", {})
		var gy := float(rw.get("ground_contact_y", 233.0))
		var x0 := float(rw.get("x_from", 80.0))
		var at := origin + Vector2(x0 - 10.0 + fx.rng.randf_range(0, 30), gy - 1.0)
		fx.puff(
			at,
			Vector2(fx.rng.randf_range(-14, -4), fx.rng.randf_range(-6, -2)),
			1.4,
			Vector2(2.0, 9.0),
			0.18,
			Color(0.3, 0.25, 0.2),
			1.0
		)
	for wk in wrecks:
		var fire := wreck_fire(wk)
		if fire > 0.0 and fx.rng.randf() < step_dt * 3.0 * (0.3 + fire):
			var wx := sx(float(wk["x"]))
			if wx > -40.0 and wx < canvas.x + 40.0:
				fx.puff(
					Vector2(wx, ROAD_ENEMY_Y - 8.0),
					Vector2(-4.0, -18.0),
					5.0,
					Vector2(5.0, 34.0),
					0.3,
					Color(0.14, 0.13, 0.13),
					1.0
				)
	if hull.breakdown and fx.rng.randf() < step_dt * 4.0:
		fx.puff(
			ex + Vector2(20, 10),
			Vector2(-6, -16),
			4.0,
			Vector2(6.0, 30.0),
			0.35,
			Color(0.1, 0.09, 0.09)
		)
		if fx.rng.randf() < 0.3:
			fx.spark_burst(
				origin + room_rects.get("diesel", Rect2()).get_center(),
				4,
				Color(1, 0.7, 0.3),
				40.0,
				0.0
			)


## Shells as drawn this frame: [{at: stage px, dir, friendly, type}], easing from the art muzzle
## onto the rules' path over their first 260 px (the art gun is not where the rules' gun is).
func shells_drawn(state: TankState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var alive := {}
	for s in state.shells:
		alive[s.id] = true
		var wp := shell_pos(s)
		var p := Vector2(sx(wp.x), sy(wp.y))
		var info: Dictionary = _shell_seen.get(s.id, {})
		if info.is_empty():
			var start := p
			if s.friendly:
				start = muzzle() if s.type != TankIds.SHELL_BOW else anchor("bow_gun_upper_muzzle")
			info = {"first": p, "off": start - p}
			_shell_seen[s.id] = info
		var first: Vector2 = info["first"]
		var k := clampf(1.0 - first.distance_to(p) / 260.0, 0.0, 1.0)
		var v := Vector2(s.vx, s.vy).normalized()
		if v == Vector2.ZERO:
			v = Vector2.RIGHT if s.friendly else Vector2.LEFT
		out.append(
			{
				"at": p + (info["off"] as Vector2) * k,
				"dir": v,
				"friendly": s.friendly,
				"type": s.type
			}
		)
	for id: int in _shell_seen.keys():
		if not alive.has(id):
			_shell_seen.erase(id)
	return out


# --- The HUD's geometry (TankHudGeom; canvas art px, 0,0 the canvas' top left) ----------------------


## A rules world x on the canvas.
func hud_world_x(world_x_px: float) -> float:
	return sx(world_x_px)


## The road line under the tank.
func hud_ground_y() -> float:
	return GROUND + y_off


## A tank point as drawn now: "barrel_pivot", "muzzle" (at the elevation and facing), "rear" (the
## road under the hull's rear end), or any kit.json anchor.
func hud_tank_point(name: String) -> Vector2:
	var off := Vector2(0, y_off)
	match name:
		"barrel_pivot":
			return barrel_pivot() + off
		"muzzle":
			return muzzle() + off
		"rear":
			return Vector2(origin.x + ART_REAR, GROUND) + off
	return anchor(name) + off


## An enemy's sprite (Rect2() when it is not drawn).
func hud_enemy_rect(id: int) -> Rect2:
	if not enemy_rects.has(id):
		return Rect2()
	var r: Rect2 = enemy_rects[id]
	return Rect2(r.position + Vector2(0, y_off), r.size)


## The Behemoth's sprite (Rect2() when it is not drawn).
func hud_boss_rect() -> Rect2:
	if game == null or game.state == null or not boss_visible(game.state):
		return Rect2()
	var r := boss_rect(game.state)
	return Rect2(r.position + Vector2(0, y_off), r.size)


## The Behemoth's main gun (Vector2.ZERO when it is not drawn).
func hud_boss_muzzle() -> Vector2:
	var r := hud_boss_rect()
	return Vector2.ZERO if r.size == Vector2.ZERO else r.position + boss_muzzle()


# --- Layers ---------------------------------------------------------------------------------------------


func _draw_back() -> void:
	if _built and game.state != null:
		TankWorldDraw.draw_back(layer("Back"), self)


func _draw_world() -> void:
	if _built and game.state != null:
		TankWorldDraw.draw_world(layer("World"), self, game.state)


func _draw_tank() -> void:
	if _built and game.state != null:
		TankHullDraw.draw(layer("Tank"), self, game.state)


func _draw_light() -> void:
	if _built and game.state != null:
		TankLightDraw.draw(layer("Light"), self, game.state)


func _draw_front() -> void:
	if not _built or game.state == null:
		return
	var ci := layer("Front")
	fx.draw_solid(ci)
	fx.draw_smoke(ci)
	TankWorldDraw.draw_front(ci, self)


## Tilt-shift shading: the top and the bottom of the frame darkened (the planes carry the blur).
func _draw_post() -> void:
	if not _built:
		return
	var ci := layer("Post")
	var w := canvas.x
	var top := -y_off
	var clear := Color(0, 0, 0, 0)
	var t1 := Color(0, 0, 0, 0.16)
	ci.draw_polygon(
		PackedVector2Array([Vector2(0, top), Vector2(w, top), Vector2(w, 170), Vector2(0, 170)]),
		PackedColorArray([t1, t1, clear, clear])
	)
	var b1 := Color(0, 0, 0, 0.45)
	var bottom := canvas.y - y_off
	ci.draw_polygon(
		PackedVector2Array(
			[Vector2(0, 400), Vector2(w, 400), Vector2(w, bottom), Vector2(0, bottom)]
		),
		PackedColorArray([clear, clear, b1, b1])
	)
