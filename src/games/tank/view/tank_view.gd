class_name TankView
extends Node2D
## The 2D view (docs/games/tank.md v3 and 3): the night forest road at 960 x 540 art px with the one
## v3 tank (the reference's landship rebuilt as pixel art, r6). make_view() returns this Node2D; the
## PixelViewport shows it. It only reads TankGame.state and the cue events; it never writes the state.
##
## Layers, back to front (all under `stage`, offset vertically on taller or shorter canvases and by
## the screen shake): Back (the forest planes at their parallax, the verge, the road band following
## the relief, the near shoulder; TankForest), World (the little bases, the halt line, obstacles,
## wrecks aging on sim time, enemies in their depth lanes on the relief, the Behemoth;
## TankWorldDraw), WorldLight (additive: every world light, behind the tank: the bases' and the halt
## line's lamps, fires, the tank's pools on the road), Tank (the tank: TankBody's sprite drawn
## rotated as a whole onto the terrain, then the main gun's blast and the bow guns' rounds;
## TankFiring), Light (additive: the tank's own lights rotated with the hull: room lamps, the
## headlight, both searchlights, the position lights, the scene flash, shells and flashes;
## TankLightDraw), Front (smoke and the foreground plane), Post (the tilt-shift shading); then the
## per-frame depth of field (TankDof) over the whole canvas.
##
## The tank (TankBody, a SubViewport): the base art with the rooms painted live (TankInterior: each
## seat's machine turning on its rider's crank, a rider on each manned seat, a bare saddle and a
## still crank on an empty one; the ready rack and the breech in their turret windows; both
## bow-gun receivers), the track and the road wheels on per-wheel suspension (TankSuspension) over
## the relief (TankGround: the rules' terrain plus seeded bumps), the hull fitted to the contacts
## and bobbing on its springs, the main gun at its elevation with the r6 recoil, the bow guns
## tilting toward their target. Firing (TankFiring): the blast, the recoil, the hull's rock, the
## jolt, the scene flash and the screen shake (the stage's offset, never Engine time).
##
## Scale: the rules' 640 x 360 units x 1.5 (sx/sy). The hull's rules span maps onto the art hull
## and the ground ahead onto the rest of the canvas; a wider canvas (pixel_flex) keeps that scale
## and shows more world on the right, a narrower one squeezes the ground ahead.
##
## Time: positions come from a snapshot history (TankSnapHistory) drawn at TankRenderClock.render_t.
## Machines turn by their rider's cadence integrated over render time; cosmetic randomness comes
## from TankFx.rng and TankGround's phases, seeded from ctx.seed.
##
## Free roam: the planes scroll with the hull's place on the valley road (plane_x); while the tank
## drives west the World, WorldLight, Tank, Light and Front layers are drawn mirrored; a turn hides
## the flip behind a dust cloud; a turning place stands at each end of the road.
##
## Hooks: play_evade(kind), fire(kind) (a shot's effects; the `shot` cue calls it), power_ratio(),
## set_canvas_size() (tests), and the HUD's geometry (hud_*), found through the game's meta
## TankHudGeom.VIEW_META, which the view sets.

const BASE := Vector2(960, 540)
## Rules px -> art px.
const S := 1.5
## The road line (stage y) at the flat, and where enemies stand on it.
const GROUND := 385.0
const ROAD_ENEMY_Y := 388.0
## The tank sprite's top-left on the base canvas at rest (its track bottom on the road line).
const TANK_AT := Vector2(18, 176)
## The hull's rear (sprite x).
const ART_REAR := 14.0
## Of a canvas wider than the base, this share moves the tank inward (the rest shows more world).
const WIDE_SHIFT := 0.3
## The road band (stage y): sharp under the depth of field.
const BAND := Vector2(195, 405)
const MAX_WRECKS := 8
## Depth lanes on the road (each LANE_LIFT art px further back, smaller, darker and hazier).
const LANES := 4
const LANE_LIFT := 12.0
const LANE_SCALE: Array[float] = [1.0, 0.84, 0.7, 0.58]
const WRECK_HULK_S := 5.0
const WRECK_COLLAPSE_S := 3.0
const WRECK_BURN_S := 30.0
const WRECK_GONE_S := 240.0
const MAX_CUES_PER_FRAME := 24
const CUE_QUEUE_MAX := 64
const TURN_DUST_GAIN := 1.8
## The layers mirrored while the tank drives west (the planes behind and the HUD never are).
const MIRROR_LAYERS: Array[String] = ["World", "WorldLight", "Tank", "Light", "Front"]
## The turret's width end on, a share of its side view (a traverse squeezes it to this).
const TURRET_MIN_W := 0.55
## The hull's springs: stiffness (1/s^2) and damping (1/s) of the bob, for the angle and the lift.
const SPRING_K := 90.0
const SPRING_D := 9.0
## The bow guns' tilt: rest, limits (degrees up) and slew (degrees/s).
const BOW_REST_DEG := 2.0
const BOW_MIN_DEG := -6.0
const BOW_MAX_DEG := 12.0
const BOW_SLEW := 24.0
## The bow guns' kick (px) and how long it lasts (s).
const BOW_KICK := 1.5
const BOW_KICK_S := 0.06
const MAX_ROUNDS_PER_FRAME := 4
## Both searchlights fade in and out over SEARCH_FADE_S and hold SEARCH_HOLD_S after the Lights
## seat's rider drops out of band before they fade (a rider wobbling at the band's edge does not
## flicker them).
const SEARCH_FADE_S := 0.4
const SEARCH_HOLD_S := 2.0
## The rooms' backup lighting (the Lights seat unpowered) fades in and out over BACKUP_FADE_S, with
## the same hold.
const BACKUP_FADE_S := 0.5

var game: TankGame = null
var audio: TankAudio = null
## Turn off to drive advance() yourself (tests, screenshots).
var auto_process: bool = true
var rig: TankRig = null
var kit: TankKit = null
var fx: TankFx = TankFx.new()
var dof: TankDof = null
var body: TankBody = null
var interior: TankInterior = null
var ground: TankGround = null
var firing: TankFiring = TankFiring.new()
var history: TankSnapHistory = TankSnapHistory.new()
var clock: TankRenderClock = TankRenderClock.new()
var stage: Node2D = null
## Fixed canvas size (tests); zero = the viewport's (the PixelViewport's art size).
var canvas_override: Vector2 = Vector2.ZERO

# --- Per frame (read by the draw classes and the tests) ---------------------------------------------------
var canvas: Vector2 = BASE
var y_off: float = 0.0
## The screen shake this frame (canvas px; the stage is moved by it).
var shake_px: Vector2 = Vector2.ZERO
var cam_x: float = 0.0
var scroll_px: float = 0.0
## The sprite's top-left at rest this frame (stage px, the wide shift included).
var tank_pos: Vector2 = TANK_AT
## The tank's sprite -> stage transform as drawn (suspension, bob, rock, jolt, lurch, hit shake).
var xf: Transform2D = Transform2D.IDENTITY
## The hull's angle as drawn (radians; negative: nose up) and its spring state.
var hull_rot: float = 0.0
var hull_lift: float = 0.0
## The road wheels' centres as drawn (sprite px) and where their tracks touch the road (stage px).
var wheel_centres: Array[Vector2] = []
## Track travel (art px).
var travel: float = 0.0
## seat id -> TankRiderState (null when empty), the station's slot (-1 empty), crank revolutions,
## cadence, power ratio.
var seat_riders: Dictionary = {}
var seat_slots: Dictionary = {}
var phases: Dictionary = {}
var cadences: Dictionary = {}
var powers: Dictionary = {}
## Enemy id -> Rect2 (stage px) as drawn, its depth lane, and its angle on the relief.
var enemy_rects: Dictionary = {}
var lanes: Dictionary = {}
var enemy_rots: Dictionary = {}
var wrecks: Array[Dictionary] = []
## A gun line's base slide (rules px, NAN for none), latched per gun line (TankForest.gun_line_base).
var base_slides: Dictionary = {}
## The barrel's swing during a traverse: 1 facing right .. -1 facing left.
var barrel_dir: float = 1.0
## The bow guns' tilt (degrees up) and where they aim (stage px; ZERO none).
var bow_elev: float = BOW_REST_DEG
var bow_target: Vector2 = Vector2.ZERO
## Hit shake (decays) and the evade lurch / smoke screen timers (s; < 0 when idle).
var shake: float = 0.0
var lurch_s: float = -1.0
var screen_s: float = -1.0
var frames: int = 0
## The view's own frame clock (s): flicker and drift only.
var time: float = 0.0
var dt: float = 0.0
var mirrored: bool = false
var plane_x: float = 0.0
var map_m: float = 0.0
var hull_x: float = 0.0
var _dir_seen: int = 0

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
var _kick_acc: float = 0.0
var _steam_acc: float = 0.0
var _rounds_seen: int = -1
var _rot_v: float = 0.0
var _lift_v: float = 0.0
var _pose_primed: bool = false
## The searchlights' level (0 off .. 1 on; search_fade()) and its hold left (s).
var search_level: float = 0.0
var _search_hold: float = 0.0
var _search_primed: bool = false
## The rooms' backup lighting (0 the warm lamps .. 1 the dim backup: the Lights seat unpowered) and
## its hold left (s).
var backup_level: float = 0.0
var _backup_hold: float = 0.0


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
	rig = TankRig.shared()
	kit = TankKit.shared()
	var ctx := game.ctx
	var sd := ctx.seed if ctx != null else 1
	fx.seed_rng(sd)
	ground = TankGround.new(sd)
	ground.base_y = GROUND
	if ctx != null:
		clock.min_delay_s = (
			TankRenderClock.CLIENT_DELAY_S
			if ctx.role == Wl.CLIENT
			else TankRenderClock.HOST_DELAY_S
		)
	interior = TankInterior.new(rig)
	body = TankBody.new(rig)
	body.interior = interior.tex
	add_child(body)
	stage = Node2D.new()
	stage.name = "Stage"
	add_child(stage)
	for n: String in ["Back", "World", "WorldLight", "Tank", "Light", "Front", "Post"]:
		var l := Node2D.new()
		l.name = n
		l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if n == "Light" or n == "WorldLight":
			var m := CanvasItemMaterial.new()
			m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			l.material = m
			l.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		if n == "Back":
			l.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		stage.add_child(l)
		_layers[n] = l
	(_layers["Back"] as Node2D).draw.connect(_draw_back)
	(_layers["World"] as Node2D).draw.connect(_draw_world)
	(_layers["WorldLight"] as Node2D).draw.connect(_draw_world_light)
	(_layers["Tank"] as Node2D).draw.connect(_draw_tank)
	(_layers["Light"] as Node2D).draw.connect(_draw_light)
	(_layers["Front"] as Node2D).draw.connect(_draw_front)
	(_layers["Post"] as Node2D).draw.connect(_draw_post)
	dof = TankDof.new()
	dof.enabled = miniature_option()
	add_child(dof)
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


func set_miniature(on: bool) -> void:
	if dof != null:
		dof.enabled = on


func set_canvas_size(size: Vector2) -> void:
	canvas_override = size


func layer(n: String) -> Node2D:
	return _layers.get(n, null)


# --- Frame ---------------------------------------------------------------------------------------------


## One frame of `delta` seconds: history and render clock, layout, the relief, seats and machines,
## cues, the tank's pose, effects, the layers' redraw and the audio.
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
	_layout()
	hull_x = history.hull_x_at(rt, state.hull.x_px) if clock.is_set() else state.hull.x_px
	cam_x = hull_x - float(TankConst.REAR_SCREEN_X)
	_roam_frame(state)
	var cam_px := cam_x * S
	scroll_px = cam_px - _prev_cam_px if _cam_primed else 0.0
	if absf(scroll_px) > 200.0:
		scroll_px = 0.0
	_prev_cam_px = cam_px
	_cam_primed = true
	travel += state.hull.speed_mps * TankConst.PX_PER_M * S * render_dt
	_relief(state)
	var feed := rider_feed(state, rt)
	# render_t stalls at the newest snapshot then catches up (tank_render_clock.gd): on a client that
	# would make the strokes lurch, so a client's machines run on the frame's dt.
	var phase_dt := dt if game.ctx != null and game.ctx.role == Wl.CLIENT else render_dt
	_seats(state, feed, phase_dt)
	_turret(state)
	_search(state, dt)
	_process_cues(state)
	_feed_rounds(state)
	firing.step(dt, scroll_px)
	_track_enemies(state)
	_bow_aim(state, dt)
	_pose(dt)
	_paint(state)
	_age_wrecks(state)
	_emit(state, feed, dt)
	fx.step(dt, scroll_px)
	_shake_frame()
	if dof != null:
		dof.update(canvas, BAND + Vector2(y_off, y_off))
	body.refresh()
	for l: Node2D in _layers.values():
		l.queue_redraw()
	if audio != null:
		audio.update(state, delta, game.ctx.local_peer if game.ctx != null else 0, feed)


func _layout() -> void:
	canvas = canvas_size()
	y_off = roundf((canvas.y - BASE.y) * 0.5)
	tank_pos = Vector2(TANK_AT.x + maxf(canvas.x - BASE.x, 0.0) * WIDE_SHIFT, TANK_AT.y)


## The canvas the view draws on (art px): the override, else the PixelViewport's SubViewport.
func canvas_size() -> Vector2:
	if canvas_override != Vector2.ZERO:
		return canvas_override
	var vp := get_viewport() if is_inside_tree() else null
	if vp is SubViewport:
		return Vector2((vp as SubViewport).size)
	return BASE


## The stage's offset: the canvas' vertical offset plus the shot's screen shake (a camera offset).
func _shake_frame() -> void:
	shake_px = Vector2(firing.screen_shake())
	if stage != null:
		stage.position = Vector2(0, y_off) + shake_px


# --- Free roam -----------------------------------------------------------------------------------------


func _roam_frame(state: TankState) -> void:
	var r := state.roam
	var dir := state.hull.dir if r.active else TankIds.DIR_RIGHT
	if r.active and _dir_seen != 0 and dir != _dir_seen:
		_mirror_wrecks(state)
	_dir_seen = dir
	mirrored = r.active and dir < 0
	if r.active and state.roam_map != null:
		map_m = r.map_m + (hull_x - state.hull.x_px) / TankConst.PX_PER_M * float(dir)
		plane_x = map_m * TankConst.PX_PER_M
	else:
		plane_x = cam_x
	for n: String in MIRROR_LAYERS:
		var l: Node2D = _layers.get(n, null)
		if l != null:
			l.scale = Vector2(-1, 1) if mirrored else Vector2.ONE
			l.position = Vector2(canvas.x, 0) if mirrored else Vector2.ZERO


## The travel-frame x (rules px) of map metre `m` as drawn this frame.
func travel_x(state: TankState, m: float) -> float:
	var cx := hull_x + float(state.hull.hull_w) * 0.5
	return cx + (m - map_m) * float(state.hull.dir) * TankConst.PX_PER_M


func _mirror_wrecks(state: TankState) -> void:
	var cx := state.hull.x_px + float(state.hull.hull_w) * 0.5
	for w in wrecks:
		w["x"] = 2.0 * cx - float(w["x"])
		w["side"] = -int(w.get("side", 1))


## How thick the turn's dust cloud is (0..1).
func turn_dust(state: TankState) -> float:
	var r := state.roam
	if not r.active or r.turn_s <= 0.0:
		return 0.0
	var half := 0.5 * (state.content.num("valley", "turn.stop_s", 8.0) if state.content else 8.0)
	var k := 1.0 - absf(r.turn_s - half) / maxf(half, 0.01)
	return clampf(k * TURN_DUST_GAIN, 0.0, 1.0)


func _hud_x(x: float) -> float:
	return canvas.x - x if mirrored else x


func _hud_rect(r: Rect2) -> Rect2:
	if not mirrored or r.size == Vector2.ZERO:
		return r
	return Rect2(Vector2(canvas.x - r.end.x, r.position.y), r.size)


# --- Mapping -------------------------------------------------------------------------------------------


## World x (rules px) -> stage x (art px, the travel frame).
func sx(world_x: float) -> float:
	var s := world_x - cam_x
	var rear := float(TankConst.REAR_SCREEN_X)
	var rf := rear + float(game.state.hull.hull_w)
	var art_rear := tank_pos.x + ART_REAR
	var front := tank_pos.x + headlight_x()
	if s <= rf:
		return art_rear + (s - rear) * (front - art_rear) / maxf(rf - rear, 1.0)
	var right := minf(canvas.x, BASE.x) - 20.0 + (tank_pos.x - TANK_AT.x)
	var k := (right - front) / maxf(float(TankConst.SCREEN_W) - rf, 1.0)
	return front + (s - rf) * k


## World y (rules px) -> stage y.
func sy(world_y: float) -> float:
	return GROUND - (float(TankConst.GROUND_Y) - world_y) * S


func headlight_x() -> float:
	var hl := rig.detail("headlight")
	return (hl["at"] as Vector2).x if not hl.is_empty() else 453.0


## The road's stage y under travel-frame stage x `x` (the relief; mirrored layers read it mirrored).
func ground_y(x: float) -> float:
	return ground.y_at(canvas.x - x if mirrored else x)


## A sprite point (sprite px) on the stage as drawn this frame.
func at_sprite(p: Vector2) -> Vector2:
	return xf * p


## A turret point (sprite px) on the stage: through the traverse's mirror, then the hull.
func at_turret(p: Vector2) -> Vector2:
	return xf * (body.turret_xf() * p)


# --- The relief and the pose ------------------------------------------------------------------------------


func _relief(state: TankState) -> void:
	var hull_cx := tank_pos.x + rig.size.x * 0.5
	var key := ""
	var points: Array = []
	var hm := 0.0
	if state.roam.active and state.roam_map != null:
		key = "roam %d" % state.roam.map_seed
		hm = map_m
		points = state.roam_map.terrain
	elif state.content != null:
		key = "seg %d" % state.seg.phase_index
		var t: Variant = state.content.segment(state.seg.phase_index).get("terrain", [])
		points = t if t is Array else []
		hm = hull_x / TankConst.PX_PER_M
	if mirrored:
		hull_cx = canvas.x - hull_cx
	ground.frame(plane_x * S, hull_cx, hm, key, points)


## The tank's pose: the fit of the relief under the wheels and their springs' lift (the targets),
## the hull's angle and lift following them on a damped spring (the bob), the shot's rock and jolt,
## the evade lurch and the hit shake; then each wheel on its arm within its travel.
func _pose(step_dt: float) -> void:
	var cx := tank_pos.x + rig.size.x * 0.5
	var gfn := Callable(self, "ground_y")
	var fit := TankSuspension.fit(rig.wheels, rig.size, cx, gfn)
	var trot := float(fit["rot"])
	var at: Vector2 = fit["at"]
	var g := rig.gear
	var t_track := float(g.get("T", 5.0))
	var up := float(g.get("up", 7.0))
	var droop := float(g.get("droop", 5.0))
	var x0 := TankSuspension.xform(rig.size, rig.ground, at, trot, 0.0)
	var c0 := TankSuspension.wheel_centres(rig.wheels, x0, gfn, t_track, up, droop)
	var tlift := TankSuspension.lift_of(rig.wheels, c0)
	if not _pose_primed or step_dt <= 0.0:
		hull_rot = trot
		hull_lift = tlift
		_pose_primed = true
	else:
		var n := maxi(ceili(step_dt / 0.01), 1)
		var h := step_dt / float(n)
		for i in n:
			_rot_v += (SPRING_K * (trot - hull_rot) - SPRING_D * _rot_v) * h
			hull_rot += _rot_v * h
			_lift_v += (SPRING_K * (tlift - hull_lift) - SPRING_D * _lift_v) * h
			hull_lift += _lift_v * h
	var rot := hull_rot + deg_to_rad(firing.rock())
	shake = maxf(shake - step_dt * 3.0, 0.0)
	var off := Vector2.ZERO
	if shake > 0.0:
		off = Vector2(roundf(sin(time * 61.0) * 2.0 * shake), roundf(cos(time * 47.0) * shake))
	if lurch_s >= 0.0:
		lurch_s += step_dt
		off.x += roundf(sin(minf(lurch_s / 1.2, 1.0) * PI) * 6.0)
		if lurch_s > 1.2:
			lurch_s = -1.0
	if screen_s >= 0.0:
		screen_s += step_dt
		if screen_s > 6.0:
			screen_s = -1.0
	off -= Vector2(firing.jolt(), 0).rotated(rot)
	xf = TankSuspension.xform(rig.size, rig.ground, at + off, rot, hull_lift)
	wheel_centres = TankSuspension.wheel_centres(rig.wheels, xf, gfn, t_track, up, droop)


## The road under wheel `i` (stage px): where its track touches the road.
func wheel_contact(i: int) -> Vector2:
	var w := rig.wheels[i]
	var c := xf * wheel_centres[i]
	var down := xf.basis_xform(Vector2.DOWN).normalized()
	return c + down * (w.z + float(rig.gear.get("T", 5.0)))


# --- History and time ---------------------------------------------------------------------------------


func _on_snapshot_applied(tick: int) -> void:
	if game != null and game.state != null:
		history.push(tick, game.state)
		_last_tick = tick


func _poll_history(state: TankState) -> void:
	if state.tick != _last_tick:
		history.push(state.tick, state)
		_last_tick = state.tick


func enemy_x(e: TankEnemyState) -> float:
	return history.enemy_x_at(e.id, clock.render_t, e.x_px) if clock.is_set() else e.x_px


func boss_x(state: TankState) -> float:
	return history.boss_x_at(clock.render_t, state.boss.x_px) if clock.is_set() else state.boss.x_px


func shell_pos(s: TankShellState) -> Vector2:
	var live := Vector2(s.x, s.y)
	return history.shell_at(s.id, clock.render_t, live) if clock.is_set() else live


## peer -> Vector2(raw_w, cadence): live for the host, SOLO and the local rider, interpolated
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


# --- Seats and machines ----------------------------------------------------------------------------------


## The power the machines show: watts over the rider's target (1 = in band, 0.84-1.17).
static func power_ratio(r: TankRiderState) -> float:
	if r == null:
		return 0.0
	if r.target_pct > 0.0 and r.ftp > 0.0:
		return clampf(r.raw_w / (r.ftp * r.target_pct / 100.0), 0.0, 1.6)
	return TankMech.rider_power(r.ftp_pct)


## The station of a seat (TankIds.SEATS: by its engine), or null.
func seat_station(state: TankState, seat: String) -> TankStationState:
	return state.station(str((rig.seats.get(seat, {}) as Dictionary).get("engine", "")))


## The seat a station's engine works (or "").
func seat_of_engine(engine: String) -> String:
	for s: String in rig.seats:
		if str(rig.seats[s]["engine"]) == engine:
			return s
	return ""


func _seats(state: TankState, feed: Dictionary, render_dt: float) -> void:
	seat_riders.clear()
	seat_slots.clear()
	for seat in TankRig.SEATS:
		var st := seat_station(state, seat)
		var slot := st.slot if st != null and not st.is_empty() else -1
		var r: TankRiderState = state.rider_at(slot) if slot >= 0 else null
		seat_riders[seat] = r
		seat_slots[seat] = slot if r != null else -1
		var rpm := 0.0
		if r != null and not state.all_afk:
			var f: Vector2 = feed.get(r.peer, Vector2(r.raw_w, r.cadence_rpm))
			rpm = f.y if f.y > 1.0 else 0.0
		cadences[seat] = rpm
		phases[seat] = float(phases.get(seat, 0.0)) + rpm / 60.0 * render_dt
		powers[seat] = power_ratio(r)


## What the audio reads per seat (SPEC_AUDIO 2.2): its crank revolutions, rpm (0 when the picture
## stops the machine, as `on` in _paint), power and whether the local rider leads it.
func audio_feed(state: TankState) -> Dictionary:
	var out := {}
	var me := game.ctx.local_peer if game.ctx != null else 0
	for seat: String in TankRig.SEATS:
		var r := rider_on(seat)
		out[seat] = {
			"revs": machine_phase(seat),
			"rpm": 0.0 if state.hull.breakdown else float(cadences.get(seat, 0.0)),
			"power": machine_power(seat),
			"lead": r != null and r.peer == me,
		}
	return out


## The rider on a seat, or null (an empty seat).
func rider_on(seat: String) -> TankRiderState:
	return seat_riders.get(seat, null)


## The rider working an engine's room (v2 names: diesel, steam, dynamo, arc, bulwark), or null.
func rider_of(engine: String) -> TankRiderState:
	return rider_on(seat_of_engine(engine))


## Crank revolutions of a seat's machine (its rider's cadence integrated over render time).
func machine_phase(seat: String) -> float:
	return float(phases.get(seat, 0.0))


func machine_power(seat: String) -> float:
	return float(powers.get(seat, 0.0))


## How bright the searchlights are (0.15..1): the arc generator's (lit while its rider is in band,
## dimmed when stalled or out of band); without an arc room, lit.
func searchlight_k(state: TankState) -> float:
	var arc := seat_station(state, "lights") as TankArcState
	if arc == null:
		return 1.0
	if state.hull.breakdown or arc.stalled or arc.unpowered:
		return 0.15
	return 1.0 if arc.lit else 0.3


## The Lights seat is powered while it is manned and its arc lit, its rider in band (brief v3
## "Lights"; tank 0.3.1: Simon). Both searchlights burn then (turret: forward about 11 degrees
## down; rear: aft about 13 degrees down) and the rooms have their warm lamps; unpowered, the
## searchlights go out (a standby glow on their lenses) and the rooms fall back to their dim backup
## lighting. search_level and backup_level fade them (search_fade()).
func lights_powered(state: TankState) -> bool:
	return rider_on("lights") != null and searchlight_k(state) >= 1.0


## The turret searchlight's rule (lights_powered(); kept for its callers).
func turret_search_on(state: TankState) -> bool:
	return lights_powered(state)


## The searchlights' and the backup lighting's levels this frame: powered (lights_powered) the
## searchlights fade up and the backup down; unpowered, both hold SEARCH_HOLD_S first while the
## seat's rider stays on it (dropped out of band), then the searchlights fade down and the backup
## up. An empty seat or a breakdown skips the hold.
func _search(state: TankState, step_dt: float) -> void:
	var want := lights_powered(state)
	if not _search_primed:
		_search_primed = true
		search_level = 1.0 if want else 0.0
		_search_hold = SEARCH_HOLD_S if want else 0.0
		backup_level = 0.0 if want else 1.0
		_backup_hold = _search_hold
		return
	if not want and (rider_on("lights") == null or state.hull.breakdown):
		_search_hold = 0.0
		_backup_hold = 0.0
	var lh := search_fade(search_level, _search_hold, want, step_dt)
	search_level = lh.x
	_search_hold = lh.y
	var bh := fade(1.0 - backup_level, _backup_hold, want, step_dt, BACKUP_FADE_S, SEARCH_HOLD_S)
	backup_level = 1.0 - bh.x
	_backup_hold = bh.y


## One step of the searchlights' fade (fade() over SEARCH_FADE_S, holding SEARCH_HOLD_S).
static func search_fade(level: float, hold: float, want: bool, step_dt: float) -> Vector2:
	return fade(level, hold, want, step_dt, SEARCH_FADE_S, SEARCH_HOLD_S)


## One step of a light's fade: Vector2(level, hold left) after `step_dt` s from `level` (0..1) and
## `hold` (s) with it wanted on or not. On: up by step_dt / `fade_s`, the hold refilled to
## `hold_s`. Off: the hold runs out first, the rest of the step fades it down.
static func fade(
	level: float, hold: float, want: bool, step_dt: float, fade_s: float, hold_s: float
) -> Vector2:
	if want:
		var up := level + step_dt / fade_s
		return Vector2(1.0 if up > 0.999 else up, hold_s)
	var left := hold - step_dt
	if left >= 0.0:
		return Vector2(level, left)
	var down := level + left / fade_s
	return Vector2(0.0 if down < 0.001 else down, 0.0)


## The loader's picture from the contracts' rack, load_t and chamber_s: {lt (s into the r6 7 s
## cycle, < 0 idle), ready (rounds in the rack), fire_t}. See TankFiring.loader_view.
func loader_view(state: TankState) -> Dictionary:
	return TankFiring.loader_view(state, seat_station(state, "loader"), firing.fire_t)


func _paint(state: TankState) -> void:
	var inp := {"t": time}
	for seat in TankRig.SEATS:
		inp[seat] = {
			"slot": int(seat_slots.get(seat, -1)),
			"revs": machine_phase(seat),
			"on": float(cadences.get(seat, 0.0)) > 1.0 and not state.hull.breakdown,
		}
	inp["loader_seat"] = inp["loader"]
	var lv := loader_view(state)
	lv["elev"] = state.hull.elev_deg
	inp["loader"] = lv
	var sec: Dictionary = inp["sec"]
	inp["bow"] = {"revs": machine_phase("sec") if bool(sec["on"]) else -1.0}
	var feed := seat_station(state, "sec") as TankFeedState
	if feed != null and feed.rpm <= 0.0:
		inp["bow"] = {"revs": -1.0}
	if interior.paints == 0:
		interior.paint_all(inp)
	else:
		interior.paint(inp, time)
	body.travel = travel
	body.wheels = wheel_centres
	body.elev_deg = state.hull.elev_deg
	body.recoil = firing.recoil()
	body.turret_sx = turret_sx()
	body.bow_elev_deg = bow_elev
	for k in 2:
		body.bow_kick[k] = BOW_KICK if firing.bow_kicking(k, BOW_KICK_S) else 0.0
	body.search_lit = search_level >= 0.5
	body.rear_lit = search_level >= 0.5
	body.backup = backup_level


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


## The bow guns tilt toward the nearest enemy ahead (cosmetic; the rules aim them), back to rest
## without one, slewing at BOW_SLEW.
func _bow_aim(state: TankState, step_dt: float) -> void:
	bow_target = Vector2.ZERO
	var piv := at_sprite(rig.bow[0]["pivot"]) if not rig.bow.is_empty() else Vector2.ZERO
	var best := INF
	for id: int in enemy_rects:
		var e := state.enemy(id)
		if e == null or e.side < 0:
			continue
		var r: Rect2 = enemy_rects[id]
		var dx := r.get_center().x - piv.x
		if dx > 20.0 and dx < best:
			best = dx
			bow_target = r.get_center() + Vector2(0, r.size.y * 0.1)
	var want := BOW_REST_DEG
	if bow_target != Vector2.ZERO:
		var d := bow_target - piv
		want = clampf(-rad_to_deg(d.angle() - hull_rot), BOW_MIN_DEG, BOW_MAX_DEG)
	bow_elev = move_toward(bow_elev, want, BOW_SLEW * step_dt)


# --- Public effects -------------------------------------------------------------------------------------


## The evade effect: "lurch" (the drive surges the tank forward with a burst of dust) or "smoke"
## (the boiler blows a smoke screen).
func play_evade(kind: String) -> void:
	if not _built:
		return
	if kind == "smoke":
		screen_s = 0.0
		var vent := at_sprite(rig.exhaust) + Vector2(40, -6)
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
		var rear := Vector2(tank_pos.x + ART_REAR + 30.0, GROUND - 2.0)
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


## A shot of the tank's own: "main" (the main gun: blast, recoil, rock, jolt, scene flash, shake)
## or "bow" (one round from bow gun `gun`, alternating when -1). The `shot` cue and the feed's
## round count call it.
func fire(kind: String, gun: int = -1) -> void:
	if not _built:
		return
	if kind == "bow":
		var k := firing.bow_round(gun)
		var m := bow_muzzle(k)
		var tgt := bow_target if bow_target != Vector2.ZERO else m + Vector2(260, 14)
		if bow_target != Vector2.ZERO:
			fx.spark_burst(tgt, 2, Color(1.0, 0.8, 0.4), 40.0)
		return
	var mz := muzzle()
	firing.fire_main(mz, barrel_vector().angle())
	fx.light_scene(mz, 1.0, Color(1.0, 0.72, 0.4))


## The Secondaries' new rounds (TankFeedState.rounds; round k from gun (k - 1) mod 2): a flash, a
## tracer and a case each, at most MAX_ROUNDS_PER_FRAME a frame (a late snapshot catches up).
func _feed_rounds(state: TankState) -> void:
	var feed := seat_station(state, "sec") as TankFeedState
	if feed == null:
		return
	if _rounds_seen < 0 or feed.rounds < _rounds_seen:
		_rounds_seen = feed.rounds
		return
	var from := maxi(_rounds_seen + 1, feed.rounds - MAX_ROUNDS_PER_FRAME + 1)
	for k in range(from, feed.rounds + 1):
		fire("bow", posmod(k - 1, 2))
	_rounds_seen = feed.rounds


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
			fx.boom(at_sprite(rig.exhaust) + Vector2(30, 40), 18.0, 8)


## How the evade looks, from the evade event's `s`: the loader's boiler blows a smoke screen; the
## drive (or an unknown slot) lurches the tank.
func evade_kind(state: TankState, slot: int) -> String:
	var st := state.station_of(slot) if slot >= 0 else null
	if st != null and st.engine == TankIds.ENGINE_STEAM:
		return "smoke"
	return "lurch"


func _cue_shot(state: TankState, data: Dictionary) -> void:
	var sh := int(data.get("sh", 0))
	var slot := int(data.get("s", -1))
	if slot >= 0 and sh in [TankIds.SHELL_LIGHT, TankIds.SHELL_HEAVY, TankIds.SHELL_OVER]:
		fire("main")
	elif slot >= 0 and sh == TankIds.SHELL_BOW:
		# The Secondaries' rounds come from TankFeedState.rounds (_feed_rounds); without a feed
		# station a bow shot is one round.
		if seat_station(state, "sec") == null:
			fire("bow")
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


func _cue_hit(state: TankState, data: Dictionary) -> void:
	var on := int(data.get("on", -1))
	var id := int(data.get("id", 0))
	var dmg := float(data.get("dmg", 0))
	if on == TankEvents.ON_TANK:
		shake = clampf(0.4 + dmg / 12.0, 0.4, 1.0)
		var p := at_sprite(Vector2(headlight_x() - 30.0, 140.0))
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


## Depth lanes: each live enemy in the lane the rules hold it in (TankEnemyState.lane).
func _lanes(state: TankState) -> Dictionary:
	var out := {}
	for e in state.enemies:
		if e.mode != TankIds.EM_DEAD:
			out[e.id] = clampi(e.lane, 0, LANES - 1)
	return out


func _track_enemies(state: TankState) -> void:
	lanes = _lanes(state)
	enemy_rects.clear()
	enemy_rots.clear()
	for e in state.enemies:
		if not lanes.has(e.id):
			continue
		var lane := int(lanes[e.id])
		var mid := enemy_x(e) + float(e.w) * 0.5
		var r := lane_rect(enemy_kind(e), sx(mid), lane)
		var pose := enemy_pose(r, lane)
		enemy_rects[e.id] = Rect2(r.position + Vector2(0, -float(pose["lift"])), r.size)
		enemy_rots[e.id] = float(pose["rot"])
		_seen[e.id] = {"x": mid, "kind": enemy_kind(e), "lane": lane, "side": e.side}
	for id: int in _seen.keys():
		if state.enemy(id) == null:
			_seen.erase(id)


## An enemy's pose on the relief (the tank's suspension fit over its track footprint): {rot
## (radians), lift (px it stands above its lane's flat foot)}. Back lanes stand level on their flat
## berms, lifted with the relief at their middle (the road's slope is not theirs).
func enemy_pose(r: Rect2, lane: int) -> Dictionary:
	var cx := r.get_center().x
	var half := r.size.x * 0.38
	var pts: Array[Vector2] = []
	for i in 5:
		var x := cx + lerpf(-half, half, float(i) / 4.0)
		pts.append(Vector2(x, ground_y(x)))
	var rot := TankSuspension.fit_angle(pts) if lane == 0 else 0.0
	var mean := 0.0
	for q in pts:
		mean += q.y
	mean /= float(pts.size())
	var bob := 0.5 * sin(time * 5.0 + cx * 0.05)
	return {"rot": rot, "lift": roundf(GROUND - mean + bob)}


func lane_rect(kind: String, cx: float, lane: int) -> Rect2:
	var sz: Vector2 = kit.enemies.get(kind, {}).get("size", Vector2(120, 50))
	sz = (sz * lane_scale(lane)).round()
	return Rect2(Vector2(roundf(cx - sz.x * 0.5), lane_foot(lane) - sz.y), sz)


static func lane_scale(lane: int) -> float:
	return LANE_SCALE[clampi(lane, 0, LANE_SCALE.size() - 1)]


static func lane_foot(lane: int) -> float:
	return roundf(ROAD_ENEMY_Y - LANE_LIFT * float(clampi(lane, 0, LANES - 1)))


func wreck_age(w: Dictionary) -> float:
	return game.state.t - float(w["t"])


func wreck_collapse(w: Dictionary) -> float:
	return clampf((wreck_age(w) - WRECK_HULK_S) / WRECK_COLLAPSE_S, 0.0, 1.0)


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


func enemy_muzzle(e: TankEnemyState, r: Rect2) -> Vector2:
	var m: Vector2 = kit.enemies[enemy_kind(e)]["muzzle"]
	if e.side < 0:
		return Vector2(r.end.x - m.x, r.position.y + m.y)
	return r.position + m


## The Behemoth's sprite (stage px): its left edge where the rules have it, on the road.
func boss_rect(state: TankState) -> Rect2:
	var sz: Vector2 = kit.enemies.get("behemoth", {}).get("size", Vector2(583, 297))
	return Rect2(Vector2(roundf(sx(boss_x(state))), roundf(ROAD_ENEMY_Y + 4.0 - sz.y)), sz)


func boss_muzzle() -> Vector2:
	return kit.enemies.get("behemoth", {}).get("muzzle", Vector2(16, 140))


func boss_visible(state: TankState) -> bool:
	return state.boss.phase != TankIds.BOSS_NONE and state.boss.phase != TankIds.BOSS_WITHDRAWN


# --- The gun --------------------------------------------------------------------------------------------


func barrel_angle() -> float:
	return -deg_to_rad(game.state.hull.elev_deg)


## The barrel's unit direction (stage px), facing, traverse and the hull's angle included.
func barrel_vector() -> Vector2:
	var a := barrel_angle()
	return xf.basis_xform(body.turret_xf().basis_xform(Vector2(cos(a), sin(a)))).normalized()


## The turret's horizontal scale about its pivot as drawn: 1 forward, -1 facing back, in between
## through a traverse, never thinner than TURRET_MIN_W.
func turret_sx() -> float:
	var s := signf(barrel_dir) if barrel_dir != 0.0 else 1.0
	return s * lerpf(TURRET_MIN_W, 1.0, absf(barrel_dir))


## The barrel's trunnion (stage px).
func barrel_pivot() -> Vector2:
	return at_turret(rig.trunnion)


## The main gun's muzzle (stage px) at its elevation and recoil.
func muzzle() -> Vector2:
	return xf * (body.barrel_xf() * Vector2(rig.gun_len + 1.0, 0))


## Bow gun `k`'s muzzle (stage px) at its tilt.
func bow_muzzle(k: int) -> Vector2:
	var b: Dictionary = rig.bow[clampi(k, 0, rig.bow.size() - 1)]
	return xf * (body.bow_xf(k, false) * Vector2(float(b["len"]) + 1.0, 0))


## Bow gun `k`'s bore direction (stage px).
func bow_vector(k: int) -> Vector2:
	return xf.basis_xform(body.bow_xf(k, false).basis_xform(Vector2.RIGHT)).normalized()


# --- Emitters (view-only) --------------------------------------------------------------------------------


func _emit(state: TankState, feed: Dictionary, step_dt: float) -> void:
	var hull := state.hull
	var rd := rider_on("drive")
	var w := 0.0
	if rd != null:
		w = (feed.get(rd.peer, Vector2(rd.raw_w, rd.cadence_rpm)) as Vector2).x
	_smoke_acc += step_dt * (3.0 + w / 30.0)
	var ex := at_sprite(rig.exhaust)
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
	# Steam from the boiler's stack while the loader pedals, the safety valve over band.
	var lr := rig.seat_room("loader")
	var pw := machine_power("loader")
	var cad := float(cadences.get("loader", 0.0))
	_steam_acc += step_dt * (cad / 30.0 + (6.0 if pw > 1.18 else 0.0))
	while _steam_acc >= 1.0:
		_steam_acc -= 1.0
		var over := pw > 1.18
		fx.puff(
			at_sprite(Vector2(lr.position.x + 24.0, 114.0)) + Vector2(fx.rng.randf_range(-2, 2), 0),
			Vector2(-6.0, -22.0 - (14.0 if over else 0.0)),
			2.2,
			Vector2(3.0, 16.0 if over else 10.0),
			0.16 if over else 0.08,
			Color(0.78, 0.8, 0.82),
			0.3
		)
	# Dust and grit from the tracks at speed (thick while the tank turns).
	var px_s := hull.speed_mps * TankConst.PX_PER_M * S
	_dust_acc += step_dt * clampf(px_s / 8.0, 0.0, 6.0)
	_dust_acc += step_dt * 12.0 * turn_dust(state)
	while _dust_acc >= 1.0:
		_dust_acc -= 1.0
		var i := fx.rng.randi_range(0, 2)
		fx.puff(
			wheel_contact(i) + Vector2(fx.rng.randf_range(-10, 10), -1.0),
			Vector2(fx.rng.randf_range(-14, -4), fx.rng.randf_range(-6, -2)),
			1.4,
			Vector2(2.0, 9.0),
			0.18,
			Color(0.3, 0.25, 0.2),
			1.0
		)
	_kick_acc += step_dt * clampf(px_s / 6.0, 0.0, 10.0)
	var sp := TankRig.vec((rig.gear["sprocket"] as Dictionary)["c"])
	while _kick_acc >= 1.0:
		_kick_acc -= 1.0
		var kick := at_sprite(Vector2(sp.x + fx.rng.randf_range(-6.0, 8.0), rig.ground - 2.0))
		fx.puff(
			kick,
			Vector2(fx.rng.randf_range(-22, -8), fx.rng.randf_range(-10, -3)),
			0.9,
			Vector2(1.5, 6.0),
			0.16,
			Color(0.42, 0.36, 0.28),
			1.0
		)
	for wk in wrecks:
		var fire_k := wreck_fire(wk)
		if fire_k > 0.0 and fx.rng.randf() < step_dt * 6.0 * (0.3 + fire_k):
			var hp := TankWorldDraw.wreck_hatch(self, wk)
			if hp.x > -40.0 and hp.x < canvas.x + 40.0:
				var j2 := fx.rng.randf()
				fx.puff(
					hp + Vector2(j2 * 2.0 - 1.0, -2.0),
					Vector2(-3.0 - j2 * 3.0, -20.0 - j2 * 6.0),
					4.0,
					Vector2(2.0, 14.0 + j2 * 8.0),
					0.26,
					Color(0.2, 0.19, 0.18).lerp(Color(0.12, 0.11, 0.11), j2),
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
			var dr := rig.seat_room("drive")
			fx.spark_burst(at_sprite(dr.get_center()), 4, Color(1, 0.7, 0.3), 40.0, 0.0)


## Shells as drawn this frame: [{at, dir, friendly, type}], easing from the art muzzle onto the
## rules' path over their first 260 px.
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
				start = muzzle() if s.type != TankIds.SHELL_BOW else bow_muzzle(0)
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


func hud_world_x(world_x_px: float) -> float:
	return _hud_x(sx(world_x_px))


func hud_mirrored() -> bool:
	return mirrored


## The road line under the tank (the flat line; the relief moves it a few px).
func hud_ground_y() -> float:
	return GROUND + y_off


## A tank point as drawn now: "barrel_pivot" (the trunnion), "muzzle" (at the elevation, facing and
## recoil), "rear" (the road under the hull's rear end), "turret_pivot", "headlight", "exhaust",
## "bow_gun_upper_pivot" / "_muzzle", "bow_gun_lower_pivot" / "_muzzle", "searchlight_turret_lens",
## "searchlight_rear_lens".
func hud_tank_point(name: String) -> Vector2:
	var p := Vector2.ZERO
	match name:
		"barrel_pivot", "trunnion":
			p = barrel_pivot()
		"muzzle":
			p = muzzle()
		"rear":
			p = Vector2(at_sprite(Vector2(ART_REAR, rig.ground)).x, GROUND)
		"turret_pivot":
			p = at_sprite(Vector2(rig.turret_pivot_x, rig.turret_rect.end.y))
		"headlight":
			p = at_sprite(rig.detail("headlight")["at"])
		"exhaust":
			p = at_sprite(rig.exhaust)
		"bow_gun_upper_pivot":
			p = at_sprite(rig.bow[0]["pivot"])
		"bow_gun_upper_muzzle":
			p = bow_muzzle(0)
		"bow_gun_lower_pivot":
			p = at_sprite(rig.bow[1]["pivot"])
		"bow_gun_lower_muzzle":
			p = bow_muzzle(1)
		"searchlight_turret_lens":
			p = at_turret(TankRig.lens_of(rig.detail("searchlight")))
		"searchlight_rear_lens":
			p = at_sprite(TankRig.lens_of(rig.detail("searchlight_rear")))
		_:
			p = at_sprite(Vector2(rig.size.x * 0.5, rig.ground))
	return Vector2(_hud_x(p.x), p.y + y_off)


## The bow guns' muzzles on the canvas.
func hud_bow_muzzles() -> Array[Vector2]:
	return [hud_tank_point("bow_gun_upper_muzzle"), hud_tank_point("bow_gun_lower_muzzle")]


## The barrel's length (art px, trunnion to the muzzle).
func hud_barrel_length() -> float:
	return rig.gun_len + 1.0


func hud_barrel_dir() -> float:
	return -barrel_dir if mirrored else barrel_dir


## The tank's body on the canvas as drawn now, which the world tags keep out of: the hitbox's turret
## (as it faces) and its hull joined with the track run, each the bounds of the rect as rotated,
## rounded out to whole art px.
func hud_tank_rects() -> Array[Rect2]:
	var off := Vector2(0, y_off)
	var hull := rig.hit_rect("hull").merge(rig.hit_rect("track_run"))
	var out: Array[Rect2] = []
	out.append(_bounds(xf * body.turret_xf(), rig.hit_rect("turret")))
	out.append(_bounds(xf, hull))
	for i in out.size():
		var h := _hud_rect(out[i])
		var a := (h.position + off).floor()
		out[i] = Rect2(a, (h.end + off).ceil() - a)
	return out


static func _bounds(t: Transform2D, r: Rect2) -> Rect2:
	var a := t * r.position
	var out := Rect2(a, Vector2.ZERO)
	for c: Vector2 in [Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		out = out.expand(t * c)
	return out


func hud_enemy_rect(id: int) -> Rect2:
	if not enemy_rects.has(id):
		return Rect2()
	var r: Rect2 = _hud_rect(enemy_rects[id])
	return Rect2(r.position + Vector2(0, y_off), r.size)


func hud_boss_rect() -> Rect2:
	if game == null or game.state == null or not boss_visible(game.state):
		return Rect2()
	var r := _hud_rect(boss_rect(game.state))
	return Rect2(r.position + Vector2(0, y_off), r.size)


func hud_boss_muzzle() -> Vector2:
	var r := hud_boss_rect()
	return Vector2.ZERO if r.size == Vector2.ZERO else r.position + boss_muzzle()


# --- Layers ---------------------------------------------------------------------------------------------


func _draw_back() -> void:
	if _built and game.state != null:
		TankForest.draw_back(layer("Back"), self)


func _draw_world() -> void:
	if _built and game.state != null:
		TankWorldDraw.draw_world(layer("World"), self, game.state)


func _draw_world_light() -> void:
	if _built and game.state != null:
		TankLightDraw.draw_world(layer("WorldLight"), self, game.state)


## The tank: its sprite (TankBody) rotated as a whole, nearest; the turn's dust; the blast and the
## bow guns' rounds.
func _draw_tank() -> void:
	if not _built or game.state == null:
		return
	var ci := layer("Tank")
	ci.draw_set_transform_matrix(xf)
	ci.draw_texture(body.get_texture(), -Vector2(TankBody.PAD, TankBody.PAD))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	TankWorldDraw.draw_turn_dust(ci, self, game.state)
	firing.draw(ci, self)


func _draw_light() -> void:
	if _built and game.state != null:
		TankLightDraw.draw(layer("Light"), self, game.state)


func _draw_front() -> void:
	if not _built or game.state == null:
		return
	var ci := layer("Front")
	fx.draw_solid(ci)
	fx.draw_smoke(ci)
	if mirrored:
		ci.draw_set_transform(Vector2(canvas.x, 0), 0.0, Vector2(-1, 1))
	TankForest.draw_front(ci, self)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Tilt-shift shading: the top and the bottom of the frame darkened (the planes carry the blur).
func _draw_post() -> void:
	if not _built:
		return
	var ci := layer("Post")
	var w := canvas.x
	var top := -y_off - 4.0
	var clear := Color(0, 0, 0, 0)
	var t1 := Color(0, 0, 0, 0.16)
	ci.draw_polygon(
		PackedVector2Array([Vector2(0, top), Vector2(w, top), Vector2(w, 215), Vector2(0, 215)]),
		PackedColorArray([t1, t1, clear, clear])
	)
	var b1 := Color(0, 0, 0, 0.45)
	var bottom := canvas.y - y_off + 4.0
	ci.draw_polygon(
		PackedVector2Array(
			[Vector2(0, 445), Vector2(w, 445), Vector2(w, bottom), Vector2(0, bottom)]
		),
		PackedColorArray([clear, clear, b1, b1])
	)
