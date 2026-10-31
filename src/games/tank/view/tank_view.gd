class_name TankView
extends Node2D
## The 2D view (docs/games/tank.md v3 and 3): the night forest road at 960 x 540 art px with the one
## v3 tank (the reference's landship rebuilt as pixel art, r6). make_view() returns this Node2D; the
## PixelViewport shows it. It only reads TankGame.state and the cue events; it never writes the state.
##
## Layers, back to front (all under `stage`, offset vertically on taller or shorter canvases and by
## the screen shake): Back (the forest planes at their parallax, the verge, the road band following
## the relief, the near shoulder; TankForest), World (free roam's little bases, the halt line, bushes,
## obstacles, wrecks aging on sim time, the near threats in their two lanes on the relief;
## TankWorldDraw), WorldLight (additive: every world light, behind the tank: the bases' and the halt
## line's lamps, fires, the tank's pools on the road), Tank (the tank: TankBody's sprite drawn
## rotated as a whole onto the terrain, then the main gun's blast and the bow guns' rounds;
## TankFiring), Light (additive: the tank's own lights rotated with the hull: room lamps, the
## headlight, both searchlights, the position lights, the scene flash, shells and flashes;
## TankLightDraw), Front (smoke and the foreground plane), Post (the tilt-shift shading); then the
## per-frame depth of field (TankDof) over the near panel.
##
## The split screen (v4, SPEC_TANK section 4; TankFarMap holds the rects): the near panel on the left,
## a riveted seam (TankSeam) with the target's range, the far panel on the right (TankFarPanel, a
## SubViewport with its own night forest, drawn opaque over the near stage), with the shell screen
## (TankPip) in its top. Far enemies, the Behemoth and a stage's little base live there; near threats,
## obstacles and drill wrecks on the near stage, in rules px, 0..NEAR_SPAN_PX past the nose mapped onto
## the road up to the seam (sx). A far shell crosses all three (TankShellPath).
##
## Tank lost (SPEC_TANK 4.7): a boom and a short dim, then while hull.tow_s runs the tank creeps back with
## its tracks reversed under heavy smoke and the far panel goes black (its veil); stage_restart forgets
## the history and fades up from black.
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
## and the ground ahead onto the near panel's road (near_k); a wider canvas (pixel_flex) stretches that
## up to the art's own scale and shows more road past it, a narrower one squeezes it.
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
## The road line (stage y) at the flat, and where a barricade's hulk stands on it.
const GROUND := 385.0
const ROAD_ENEMY_Y := 388.0
## The near panel's road: where NEAR_SPAN_PX ends, inside the seam, and the art's own scale as its cap.
const NEAR_END_PAD := 6.0
const NEAR_K_MAX := 1.5
## The tank sprite's top-left on the base canvas at rest (its track bottom on the road line).
const TANK_AT := Vector2(18, 176)
## The hull's rear (sprite x).
const ART_REAR := 14.0
## Of a canvas wider than the base, this share moves the tank inward (the rest shows more world).
const WIDE_SHIFT := 0.3
## The road band (stage y): sharp under the depth of field.
const BAND := Vector2(195, 405)
const MAX_WRECKS := 8
## The near threats' lanes on the road: the feet (stage y) at the flat, in front of and behind the road
## line (SPEC_TANK 4.7).
const LANES := 2
const LANE_FOOT: Array[float] = [396.0, 380.0]
## A near threat's gun: the elevation it lays on the hull at (degrees), the recoil's px and its decay.
const NEAR_ELEV_MAX := 14.0
const NEAR_RECOIL_PX := 2.0
const NEAR_RECOIL_DECAY := 6.0
## Its exhaust puffs per second, and a leaf burst's particles and colour when it bursts from the bushes.
const NEAR_EXHAUST_S := 2.5
const LEAF_BURST := 14
const LEAF := Color(0.3, 0.3, 0.14)
const LEAF_SPEED := 70.0
## A tank lost: the creep back (art px/s) and how far it goes, the dim's length and depth, the heavy smoke
## per second, the fade from black at the restart.
const TOW_PX_S := 12.0
const TOW_MAX_PX := 96.0
const TOW_DIM_S := 0.4
const TOW_DIM_ALPHA := 0.55
const TOW_SMOKE_S := 9.0
const RESTART_FADE_S := 0.5
const WRECK_HULK_S := 5.0
const WRECK_COLLAPSE_S := 3.0
const WRECK_BURN_S := 30.0
const WRECK_GONE_S := 240.0
const MAX_CUES_PER_FRAME := 24
const CUE_QUEUE_MAX := 64
const TURN_DUST_GAIN := 1.8
## The layers mirrored while the tank drives west (the planes behind and the HUD never are).
const MIRROR_LAYERS: Array[String] = ["World", "WorldLight", "Tank", "Light", "Front"]
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
## Their shells that miss: rules px of near road per metre the splash event names (40-90 m ahead).
const SPLASH_PX_PER_M := 2.0
## An incoming far shell's last stretch: where it enters at the near panel's edge (stage y), where it
## strikes on the tank (sprite px from the nose, as _cue_hit) and how far ahead it falls when it will miss.
const INCOMING_Y := 170.0
const INCOMING_HIT := Vector2(-30, 140)
const INCOMING_MISS_PX := Vector2(70, 170)

var game: TankGame = null
var audio: TankAudio = null
## Turn off to drive advance() yourself (tests, screenshots).
var auto_process: bool = true
var rig: TankRig = null
var enemy_kit: TankEnemyKit = TankEnemyKit.shared()
var fx: TankFx = TankFx.new()
var dof: TankDof = null
var far: TankFarPanel = null
var seam: TankSeam = null
var pip: TankPip = null
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
## The split screen this frame: {near, seam, far, pip: Rect2} on the canvas (TankFarMap.panels).
var panels: Dictionary = {}
## A far enemy's id -> Rect2 (canvas px) as drawn in the far panel.
var far_rects: Dictionary = {}
## A near enemy's id -> Rect2 (stage px) as drawn, its foot on the road, and its lane.
var enemy_rects: Dictionary = {}
var enemy_feet: Dictionary = {}
var lanes: Dictionary = {}
var wrecks: Array[Dictionary] = []
## A tank lost: how far the tow has drawn the tank back (art px); the dim's and the fade's time left (s).
var tow_px: float = 0.0
var tow_dim_s: float = 0.0
var restart_fade_s: float = 0.0
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
var _far_sprite: Node2D = null
var _far_v0: float = 560.0
var _far_g: float = 70.0
var _layers: Dictionary = {}
var _last_tick: int = -1
var _last_render_t: float = -1.0
var _last_sim_t: float = -1.0
var _prev_cam_px: float = 0.0
var _cam_primed: bool = false
var _seen: Dictionary = {}
## A near enemy's id -> {travel, recoil, last}: its tracks and gun, kept between frames.
var _near: Dictionary = {}
var _near_smoke_acc: float = 0.0
var _tow_smoke_acc: float = 0.0
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
	_build_panels(sd)
	game.set_meta(TankHudGeom.VIEW_META, self)


## The far panel's SubViewport and, over the near stage in this order, its sprite, the seam and the PiP.
func _build_panels(sd: int) -> void:
	if game.state.content != null:
		_far_v0 = game.state.content.num("tanks", "gun.far.v0_mps", _far_v0)
		_far_g = game.state.content.num("tanks", "gun.far.g_mps2", _far_g)
	far = TankFarPanel.new(self, sd)
	add_child(far)
	_far_sprite = Node2D.new()
	_far_sprite.name = "FarSprite"
	_far_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_far_sprite.draw.connect(_draw_far)
	add_child(_far_sprite)
	seam = TankSeam.new(self)
	add_child(seam)
	pip = TankPip.new(self)
	add_child(pip)


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
	_panels_frame()
	var cam_px := cam_x * S
	scroll_px = cam_px - _prev_cam_px if _cam_primed else 0.0
	if absf(scroll_px) > 200.0:
		scroll_px = 0.0
	_prev_cam_px = cam_px
	_cam_primed = true
	travel += state.hull.speed_mps * TankConst.PX_PER_M * S * render_dt
	_tow_frame(state, dt)
	_relief(state)
	var feed := rider_feed(state, rt)
	# render_t stalls at the newest snapshot then catches up (tank_render_clock.gd): on a client that
	# would make the strokes lurch, so a client's machines run on the frame's dt.
	var phase_dt := dt if game.ctx != null and game.ctx.role == Wl.CLIENT else render_dt
	_seats(state, feed, phase_dt)
	_search(state, dt)
	_process_cues(state)
	_feed_rounds(state)
	firing.step(dt, scroll_px)
	_track_enemies(state)
	_far_frame(state, dt)
	_bow_aim(dt)
	_pose(dt)
	_paint(state)
	_age_wrecks(state)
	_emit(state, feed, dt)
	fx.step(dt, scroll_px)
	_shake_frame()
	if dof != null:
		dof.update(canvas, BAND + Vector2(y_off, y_off), panels["near"])
	body.refresh()
	for l: Node2D in _layers.values():
		l.queue_redraw()
	for n: Node2D in [_far_sprite, seam, pip]:
		n.queue_redraw()
	if audio != null:
		audio.update(state, delta, game.ctx.local_peer if game.ctx != null else 0, feed)


func _layout() -> void:
	canvas = canvas_size()
	y_off = roundf((canvas.y - BASE.y) * 0.5)
	tank_pos = Vector2(TANK_AT.x + maxf(canvas.x - BASE.x, 0.0) * WIDE_SHIFT, TANK_AT.y)


## The split screen on this frame's canvas (mirrored going west: far on the left).
func _panels_frame() -> void:
	panels = TankFarMap.panels(canvas, mirrored)
	far.layout(canvas, mirrored, y_off)
	seam.rect = Rect2(panels["seam"])
	pip.rect = Rect2(panels["pip"])
	pip.position = pip.rect.position


## The far panel's frame, and its enemies' and the Behemoth's rects on the canvas.
func _far_frame(state: TankState, step_dt: float) -> void:
	far.frame(state, step_dt)
	far.age_wrecks(state.t)
	far_rects.clear()
	for id: int in far.rects:
		far_rects[id] = far.canvas_rect(far.rects[id], far_panel_x())


func far_panel_x() -> float:
	return (panels["far"] as Rect2).position.x


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
	return front + (s - rf) * near_k()


## Art px per rules px on the road ahead: TankConst.NEAR_SPAN_PX past the nose ends just inside the seam,
## never above the art's own scale (a wide canvas shows more road past the span instead).
func near_k() -> float:
	var front := tank_pos.x + headlight_x()
	var end := TankFarMap.near_end_x(canvas.x) - NEAR_END_PAD
	return minf((end - front) / TankConst.NEAR_SPAN_PX, NEAR_K_MAX)


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
	off.x -= tow_px
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


## A far enemy's range as drawn (m). 0 on a far kind means the old frame's rules: it stands at the
## panel's near end.
func far_range_of(e: TankEnemyState) -> float:
	var r := (
		history.enemy_range_at(e.id, clock.render_t, e.range_m) if clock.is_set() else e.range_m
	)
	return r if r > 0.0 else TankFarMap.RANGE_NEAR_M


## The Behemoth's range as drawn (m), as far_range_of().
func far_boss_range(state: TankState) -> float:
	var live := state.boss.range_m
	var r := history.boss_range_at(clock.render_t, live) if clock.is_set() else live
	return r if r > 0.0 else TankFarMap.RANGE_NEAR_M


## A shell's seconds until it lands, as drawn.
func shell_left(s: TankShellState) -> float:
	return history.shell_left_at(s.id, clock.render_t, s.left_s) if clock.is_set() else s.left_s


func far_v0() -> float:
	return _far_v0


func far_g() -> float:
	return _far_g


## The current target's range (m); 0 without a far target (a barricade, a drill wreck, none).
func target_range_m(state: TankState) -> float:
	var id := state.hull.target_id
	if id == 0:
		return 0.0
	if TankBossState.is_part_id(id):
		return far_boss_range(state) + boss_part_offset(state, TankBossState.part_of(id))
	var e := state.enemy(id)
	if e == null or e.is_near():
		return 0.0
	return far_range_of(e)


## Boss part `part`'s metres behind bogie 0 (enemies.json boss.far.part_offset_m).
func boss_part_offset(state: TankState, part: int) -> float:
	if state.content == null:
		return 0.0
	var off: Variant = (state.content.boss_def().get("far", {}) as Dictionary).get("part_offset_m")
	if off is Array and part >= 0 and part < (off as Array).size():
		return float((off as Array)[part])
	return 0.0


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
	var inp := paint_input(state)
	if interior.paints == 0:
		interior.paint_all(inp)
	else:
		interior.paint(inp, time)
	body.travel = travel
	body.wheels = wheel_centres
	body.elev_deg = state.hull.elev_deg
	body.recoil = firing.recoil()
	body.bow_elev_deg = bow_elev
	for k in 2:
		body.bow_kick[k] = BOW_KICK if firing.bow_kicking(k, BOW_KICK_S) else 0.0
	body.search_lit = search_level >= 0.5
	body.rear_lit = search_level >= 0.5
	body.backup = backup_level


## What the rooms are painted from this frame (TankInterior.paint).
func paint_input(state: TankState) -> Dictionary:
	var inp := {"t": time}
	for seat in TankRig.SEATS:
		inp[seat] = {
			"slot": int(seat_slots.get(seat, -1)),
			"revs": machine_phase(seat),
			"on": float(cadences.get(seat, 0.0)) > 1.0 and not state.hull.breakdown,
		}
	var rp := seat_station(state, "repair") as TankRepairState
	if rp != null:
		inp["repair"]["press_t"] = rp.press_t
		inp["repair"]["patches"] = rp.patches
	inp["loader_seat"] = inp["loader"]
	var lv := loader_view(state)
	lv["elev"] = state.hull.elev_deg
	inp["loader"] = lv
	var sec: Dictionary = inp["sec"]
	inp["bow"] = {"revs": machine_phase("sec") if bool(sec["on"]) else -1.0}
	var feed := seat_station(state, "sec") as TankFeedState
	if feed != null and feed.rpm <= 0.0:
		inp["bow"] = {"revs": -1.0}
	return inp


## The bow guns tilt toward the nearest near threat ahead (cosmetic; the rules aim them), back to rest
## without one, slewing at BOW_SLEW.
func _bow_aim(step_dt: float) -> void:
	bow_target = Vector2.ZERO
	var piv := at_sprite(rig.bow[0]["pivot"]) if not rig.bow.is_empty() else Vector2.ZERO
	var best := INF
	for id: int in enemy_rects:
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
		TankEvents.SPLASH:
			_cue_splash(data)
		TankEvents.EVADE:
			if int(data.get("ok", 0)) == 1:
				play_evade(evade_kind(state, int(data.get("s", -1))))
		TankEvents.BREAKDOWN:
			shake = 1.0
			fx.boom(at_sprite(rig.exhaust) + Vector2(30, 40), 18.0, 8)
		TankEvents.AMBUSH:
			_cue_ambush(state, int(data.get("id", 0)))
		TankEvents.TANK_LOST:
			_cue_tank_lost()
		TankEvents.STAGE_RESTART:
			_cue_restart()


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
		if e != null and e.is_near():
			_near_fired(e)
		else:
			far.on_fired(state, src, sh)


## A near threat's round: the recoil, a small flash back along its reversed gun.
func _near_fired(e: TankEnemyState) -> void:
	if not enemy_feet.has(e.id):
		return
	_near_rec(e)["recoil"] = 1.0
	var mz := near_muzzle(e)
	fx.flash(mz, 10.0, 0.1, Color(1.0, 0.62, 0.3), Vector2.LEFT)
	fx.light_scene(mz, 0.15, Color(1.0, 0.62, 0.3))


## A near threat bursts from the bushes: leaves thrown up where it is now (it may not be tracked yet).
func _cue_ambush(state: TankState, id: int) -> void:
	var e := state.enemy(id)
	if e == null or not e.is_near():
		return
	fx.spark_burst(near_foot(e) + Vector2(0, -8), LEAF_BURST, LEAF, LEAF_SPEED, 0.0)


## The tank is lost: a boom in its hull, the scene dims for a moment. Its tow runs from hull.tow_s.
func _cue_tank_lost() -> void:
	shake = 1.0
	tow_dim_s = TOW_DIM_S
	fx.boom(at_sprite(rig.size * 0.5), 30.0, 12)
	fx.light_scene(at_sprite(rig.size * 0.5), 0.7, Color(1.0, 0.5, 0.2))


## The stage starts over: what was on the road is forgotten, the picture fades up from black.
func _cue_restart() -> void:
	restart_fade_s = RESTART_FADE_S
	tow_dim_s = 0.0
	history.clear()
	clock.reset()
	_last_tick = -1
	_cam_primed = false
	wrecks.clear()
	far.wrecks.clear()
	_seen.clear()
	_near.clear()
	_shell_seen.clear()


## While hull.tow_s runs the tank creeps back with its tracks reversed; its dim and fade run down.
func _tow_frame(state: TankState, step_dt: float) -> void:
	if state.hull.tow_s > 0.0:
		var was := tow_px
		tow_px = minf(tow_px + TOW_PX_S * step_dt, TOW_MAX_PX)
		travel -= tow_px - was
	else:
		tow_px = 0.0
	tow_dim_s = maxf(tow_dim_s - step_dt, 0.0)
	restart_fade_s = maxf(restart_fade_s - step_dt, 0.0)


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
	if on == TankEvents.ON_ENEMY and far.rects.has(id):
		far.on_enemy_hit(id)
		return
	if on == TankEvents.ON_BOSS and state.boss.phase != TankIds.BOSS_NONE:
		far.on_boss_hit(TankBossState.part_of(id))
		return
	var x := float(data.get("x", 0))
	if x != 0.0:
		fx.boom(Vector2(sx(x), GROUND - 18.0), 16.0, 4)


## A far shell landed on nothing: ours throws up earth in the far panel at its range; theirs on the road
## ahead (`r` metres squeezed into the near panel's span).
func _cue_splash(data: Dictionary) -> void:
	var r := float(data.get("r", 0))
	if int(data.get("f", 0)) == 1:
		far.on_splash(r)
		return
	var ahead := minf(r * SPLASH_PX_PER_M, TankConst.NEAR_SPAN_PX * 0.95)
	var x := minf(
		sx(hull_x + float(game.state.hull.hull_w) + ahead), TankFarMap.near_end_x(canvas.x) - 6.0
	)
	fx.boom(Vector2(x, ground_y(x) - 6.0), 12.0, 4)


func _cue_kill(state: TankState, data: Dictionary) -> void:
	var id := int(data.get("id", 0))
	if int(data.get("e", 0)) == TankIds.BOSS_CODE:
		far.on_boss_kill()
		return
	if far.on_kill(state, id) or not _seen.has(id):
		return
	var w: Dictionary = (_seen[id] as Dictionary).duplicate()
	w["t"] = state.t
	wrecks.append(w)
	while wrecks.size() > MAX_WRECKS:
		wrecks.pop_front()
	if enemy_rects.has(id):
		var r: Rect2 = enemy_rects[id]
		fx.boom(r.get_center(), 18.0, 6)
		fx.light_scene(r.get_center(), 0.4, Color(1.0, 0.5, 0.2))


# --- Enemies and wrecks ---------------------------------------------------------------------------------


func enemy_kind(e: TankEnemyState) -> String:
	return TankIds.enemy_of(e.code)


## Depth lanes on the near stage: each live near threat in the lane the rules hold it in.
func _lanes(state: TankState) -> Dictionary:
	var out := {}
	for e in state.enemies:
		if e.mode != TankIds.EM_DEAD and e.is_near():
			out[e.id] = clampi(e.lane, 0, LANES - 1)
	return out


func _track_enemies(state: TankState) -> void:
	lanes = _lanes(state)
	enemy_rects.clear()
	enemy_feet.clear()
	for e in state.enemies:
		if not lanes.has(e.id):
			continue
		var foot := near_foot(e)
		var x := enemy_x(e)
		enemy_feet[e.id] = foot
		enemy_rects[e.id] = _rect_at(enemy_kind(e), foot)
		_seen[e.id] = {"x": x + float(e.w) * 0.5, "kind": enemy_kind(e), "lane": lanes[e.id]}
		var rec := _near_rec(e)
		rec["travel"] = float(rec["travel"]) + absf(x - float(rec["last"])) * S
		rec["last"] = x
		rec["recoil"] = maxf(float(rec["recoil"]) - dt * NEAR_RECOIL_DECAY, 0.0)
	for id: int in _seen.keys():
		if state.enemy(id) == null:
			_seen.erase(id)
	for id: int in _near.keys():
		if state.enemy(id) == null:
			_near.erase(id)


func _near_rec(e: TankEnemyState) -> Dictionary:
	var rec: Dictionary = _near.get(e.id, {})
	if rec.is_empty():
		rec = {"travel": 0.0, "recoil": 0.0, "last": enemy_x(e)}
		_near[e.id] = rec
	return rec


## A near threat's foot on the stage: over its rules x, on its lane of the road (the relief included).
func near_foot(e: TankEnemyState) -> Vector2:
	var x := sx(enemy_x(e) + float(e.w) * 0.5)
	return Vector2(x, near_ground(x, clampi(e.lane, 0, LANES - 1)))


## The ground under near lane `lane` at stage x `x` (TankEnemyDraw's pose.ground).
func near_ground(x: float, lane: int) -> float:
	return ground_y(x) + lane_foot(lane) - GROUND


## A near threat's pose (SPEC_TANK 5.4): running away with its turret traversed back at us (turret_sx -1),
## laid on the hull. Its tracks run with its own speed on the road, its gun kicks on a shot.
func near_pose(e: TankEnemyState) -> Dictionary:
	var rec: Dictionary = _near.get(e.id, {})
	var lane := clampi(e.lane, 0, LANES - 1)
	var foot: Vector2 = enemy_feet.get(e.id, Vector2.ZERO)
	var front := tank_pos.x + headlight_x()
	var elev := rad_to_deg(atan2(40.0, maxf(foot.x - front, 20.0)))
	return {
		"travel": float(rec.get("travel", 0.0)),
		"turret_sx": -1.0,
		"elev_deg": minf(elev, NEAR_ELEV_MAX),
		"recoil": float(rec.get("recoil", 0.0)) * NEAR_RECOIL_PX,
		"dim": 1.0 - TankWorldDraw.lane_dim(lane),
		"haze": TankWorldDraw.lane_fog(lane),
		"flash": 0.0,
		"ground": Callable(self, "near_ground").bind(lane),
		"wrecked": false,
		"bogies_wrecked": [] as Array[bool],
		"flip": false,
		"time": time,
	}


## Where a near threat's rounds leave its gun (stage px).
func near_muzzle(e: TankEnemyState) -> Vector2:
	var foot: Vector2 = enemy_feet.get(e.id, near_foot(e))
	return TankEnemyDraw.muzzle(enemy_kit, enemy_kind(e), foot, near_pose(e))


func _rect_at(kind: String, foot: Vector2) -> Rect2:
	var sz: Vector2 = enemy_kit.kind(kind)["size"]
	return Rect2(foot - Vector2(roundf(sz.x * 0.5), sz.y), sz)


## The rect of a `kind` standing in lane `lane` at stage x `cx`, at the flat.
func lane_rect(kind: String, cx: float, lane: int) -> Rect2:
	return _rect_at(kind, Vector2(roundf(cx), lane_foot(lane)))


static func lane_foot(lane: int) -> float:
	return LANE_FOOT[clampi(lane, 0, LANES - 1)]


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


func boss_visible(state: TankState) -> bool:
	return state.boss.phase != TankIds.BOSS_NONE and state.boss.phase != TankIds.BOSS_WITHDRAWN


# --- The gun --------------------------------------------------------------------------------------------


func barrel_angle() -> float:
	return -deg_to_rad(game.state.hull.elev_deg)


## The barrel's unit direction (stage px), the hull's angle included. The turret always faces forward:
## nothing comes from behind.
func barrel_vector() -> Vector2:
	var a := barrel_angle()
	return xf.basis_xform(Vector2(cos(a), sin(a))).normalized()


## The barrel's trunnion (stage px).
func barrel_pivot() -> Vector2:
	return at_sprite(rig.trunnion)


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
	_emit_near(state, step_dt)
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
	if hull.tow_s > 0.0:
		_tow_smoke_acc += step_dt * TOW_SMOKE_S
		while _tow_smoke_acc >= 1.0:
			_tow_smoke_acc -= 1.0
			var j3 := fx.rng.randf()
			fx.puff(
				ex + Vector2(20.0 + j3 * 160.0, 14.0 - j3 * 10.0),
				Vector2(-8.0 - j3 * 8.0, -20.0 - j3 * 10.0),
				7.0 + j3 * 3.0,
				Vector2(8.0, 44.0 + j3 * 20.0),
				0.42,
				Color(0.09, 0.08, 0.08).lerp(Color(0.16, 0.14, 0.13), j3),
				0.3
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


## The near threats' exhaust: a thin dark puff from each now and then.
func _emit_near(state: TankState, step_dt: float) -> void:
	_near_smoke_acc += step_dt * NEAR_EXHAUST_S * float(enemy_feet.size())
	while _near_smoke_acc >= 1.0:
		_near_smoke_acc -= 1.0
		if enemy_feet.is_empty():
			continue
		var ids: Array = enemy_feet.keys()
		var id: int = ids[fx.rng.randi_range(0, ids.size() - 1)]
		var e := state.enemy(id)
		if e == null:
			continue
		var row := enemy_kit.kind(enemy_kind(e))
		var sz: Vector2 = row["size"]
		var at: Vector2 = row.get("exhaust", sz * Vector2(0.12, 0.45))
		fx.puff(
			(enemy_feet[id] as Vector2) - Vector2(sz.x * 0.5, float(row["ground"])) + at,
			Vector2(fx.rng.randf_range(-14, -6), fx.rng.randf_range(-10, -5)),
			1.8,
			Vector2(1.5, 8.0),
			0.16,
			Color(0.2, 0.2, 0.2),
			1.0
		)


## Shells on the near stage this frame: [{at, dir, friendly, type}]. A near shell eases from the art
## muzzle onto the rules' path over its first 260 px; a far one shows only on its near stretches
## (_far_shell_near).
func shells_drawn(state: TankState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var alive := {}
	for s in state.shells:
		alive[s.id] = true
		if s.far:
			var row := _far_shell_near(s)
			if not row.is_empty():
				out.append(row)
			continue
		var wp := shell_pos(s)
		var p := Vector2(sx(wp.x), sy(wp.y))
		var info: Dictionary = _shell_seen.get(s.id, {})
		if info.is_empty():
			var start := p
			var src := state.enemy(s.source)
			if s.friendly:
				start = muzzle() if s.type != TankIds.SHELL_BOW else bow_muzzle(0)
			elif src != null and enemy_feet.has(src.id):
				start = near_muzzle(src)
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


## A far shell on the near stage (SPEC_TANK 4.4), or {}: ours for its first LEAVE_S, from the muzzle along
## the barrel off the near edge; theirs for its last ARRIVE_S, from the near edge onto the tank or, on a
## peer that knows it will miss (will_hit is host only), the road ahead.
func _far_shell_near(s: TankShellState) -> Dictionary:
	var edge := TankFarMap.near_end_x(canvas.x)
	var left := shell_left(s)
	var from: Vector2
	var to: Vector2
	var k: float
	if s.friendly:
		k = TankShellPath.leave_k(TankShellPath.flight_s(s.left_s, s.vy, _far_g) - left)
		if k < 0.0:
			return {}
		var info: Dictionary = _shell_seen.get(s.id, {})
		if info.is_empty():
			info = {"from": muzzle(), "dir": barrel_vector()}
			_shell_seen[s.id] = info
		from = info["from"]
		var d: Vector2 = info["dir"]
		to = from + d * (edge + 8.0 - from.x) / maxf(d.x, 0.1)
	else:
		k = TankShellPath.arrive_k(left)
		if k < 0.0:
			return {}
		from = Vector2(edge + 8.0, INCOMING_Y)
		to = _incoming_aim(s)
	var at := from.lerp(to, k)
	return {"at": at, "dir": (to - from).normalized(), "friendly": s.friendly, "type": s.type}


## Where an incoming far shell strikes on the near stage.
func _incoming_aim(s: TankShellState) -> Vector2:
	var client := game.ctx != null and game.ctx.role == Wl.CLIENT
	if s.will_hit or client:
		return at_sprite(Vector2(headlight_x(), 0.0) + INCOMING_HIT)
	var h := TankDraw.hash01(float(s.id) * 0.73)
	var x := tank_pos.x + headlight_x() + lerpf(INCOMING_MISS_PX.x, INCOMING_MISS_PX.y, h)
	x = minf(x, TankFarMap.near_end_x(canvas.x) - 6.0)
	return Vector2(x, ground_y(x) - 2.0)


# --- The HUD's geometry (TankHudGeom; canvas art px, 0,0 the canvas' top left) ----------------------


func hud_world_x(world_x_px: float) -> float:
	return _hud_x(sx(world_x_px))


func hud_mirrored() -> bool:
	return mirrored


## The road line under the tank (the flat line; the relief moves it a few px).
func hud_ground_y() -> float:
	return GROUND + y_off


## A tank point as drawn now: "barrel_pivot" (the trunnion), "muzzle" (at the elevation and recoil),
## "rear" (the road under the hull's rear end), "turret_pivot", "headlight", "exhaust",
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
			p = at_sprite(TankRig.lens_of(rig.detail("searchlight")))
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


## The barrel always faces the way the tank drives.
func hud_barrel_dir() -> float:
	return -1.0 if mirrored else 1.0


## The tank's body on the canvas as drawn now, which the world tags keep out of: the hitbox's turret
## and its hull joined with the track run, each the bounds of the rect as rotated,
## rounded out to whole art px.
func hud_tank_rects() -> Array[Rect2]:
	var off := Vector2(0, y_off)
	var hull := rig.hit_rect("hull").merge(rig.hit_rect("track_run"))
	var out: Array[Rect2] = []
	out.append(_bounds(xf, rig.hit_rect("turret")))
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


## An enemy's sprite on the canvas: in the far panel (canvas px already) or on the near stage.
func hud_enemy_rect(id: int) -> Rect2:
	if far_rects.has(id):
		return far_rects[id]
	if not enemy_rects.has(id):
		return Rect2()
	var r: Rect2 = _hud_rect(enemy_rects[id])
	return Rect2(r.position + Vector2(0, y_off), r.size)


func hud_boss_rect() -> Rect2:
	if game == null or game.state == null or far == null or not boss_visible(game.state):
		return Rect2()
	return far.canvas_rect(far.boss_box, far_panel_x())


func hud_boss_muzzle() -> Vector2:
	if hud_boss_rect().size == Vector2.ZERO:
		return Vector2.ZERO
	return far.canvas_point(far.boss_muzzle(game.state), far_panel_x())


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


## The far panel's picture over the near stage, opaque.
func _draw_far() -> void:
	if _built and far != null and not panels.is_empty():
		_far_sprite.draw_texture(far.get_texture(), (panels["far"] as Rect2).position)


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
	var black := maxf(TOW_DIM_ALPHA * tow_dim_s / TOW_DIM_S, restart_fade_s / RESTART_FADE_S)
	if black > 0.0:
		ci.draw_rect(Rect2(0, top, w, bottom - top), Color(0, 0, 0, black))
