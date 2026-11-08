class_name TankViewBase
extends Node2D
## TankView's lowest layer (TankView's header has the picture; the chain is Base, Motion, Seats, World, Hud,
## TankView, each calling only down): every constant and per-frame var, the rules-to-art mapping, the guns
## as drawn and the snapshot history. Only TankView is ever instantiated.

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
## The dark line round a near threat, so two in a crowd part.
const NEAR_HALO := 0.8
## Its exhaust puffs per second, and a leaf burst's particles and colour when it bursts from the bushes.
const NEAR_EXHAUST_S := 20.0
const NEAR_EXHAUST := Color(0.44, 0.45, 0.45)
## A running one's exhaust is a streak flying back toward us: its speed, its life and how long a wisp of it stretches.
const NEAR_STREAK_V := 105.0
const NEAR_STREAK_S := 0.85
const NEAR_STREAK_LEN := 15.0
## So many near threats' worth of smoke and dust at most: a crowd shares them.
const NEAR_EMIT_MAX := 4
## Dust kicked up behind a running near threat, per second, low at its rear wheels and under its sprite; a paused one's
## settles at this share.
const NEAR_DUST_S := 34.0
const NEAR_DUST_PAUSED := 0.12
const NEAR_DUST := Color(0.42, 0.36, 0.28)
const LEAF_BURST := 14
const LEAF := Color(0.3, 0.3, 0.14)
const LEAF_SPEED := 70.0
## The leaves still fluttering down after the burst, the bush's colours, and how fast a bursting threat keeps
## throwing them (per second) while it comes out.
const LEAF_DRIFT := 22
const LEAF_DRIFT_S := 3.4
const LEAF_LIT := Color(0.36, 0.43, 0.27)
const LEAF_DARK := Color(0.2, 0.3, 0.2)
const LEAF_RATE := 24.0
## A bush a threat burst from goes on shedding for this long (s).
const LEAF_SHED_S := 1.9
## How far a threat may be from a bush and still be bursting out of it.
const LEAF_BUSH_PX := 70.0
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
const BOW_MIN_DEG := -12.0
const BOW_MAX_DEG := 12.0
const BOW_SLEW := 24.0
## The bow guns' kick (px) and how long it lasts (s).
const BOW_KICK := 1.0
const BOW_KICK_S := 0.05
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
## The dust on the road: drawn behind the near threats' wheels, not over them.
var dust_fx: TankFx = TankFx.new()
var dof: TankDof = null
var far: TankFarPanel = null
var seam: TankSeam = null
var pip: TankPip = null
var body: TankBody = null
var interior: TankInterior = null
var ground: TankGround = null
var firing: TankFiring = TankFiring.new()
var history: TankSnapHistory = TankSnapHistory.new()
## The host and SOLO see every 0.05 s tick; _build sets the client's delay on a client.
var clock: SnapRenderClock = SnapRenderClock.new(SnapRenderClock.HOST_DELAY_S)
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
## The hangar's look this frame (TankHangar.look): empty-ish outside the Hangar and the Roll-out.
var hangar_look: Dictionary = {}
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
var _near_dust_acc: float = 0.0
## The bushes threats have just burst from: [{at (stage px), left (s)}].
var _shedding: Array[Dictionary] = []
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


func far_panel_x() -> float:
	return (panels["far"] as Rect2).position.x


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
