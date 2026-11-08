class_name TankFarPanel
extends SubViewport
## v4: the far panel (SPEC_TANK 4.2, 4.3): a long-lens view of the enemy, in its own SubViewport so it never
## runs the depth of field. `Back` is the night sky, a faint Milky Way and a few soft stars, the mountains over the firs
## (TankFarSky) at a third of the near panel's parallax, a glow of moonlit air on the horizon, three walls of firs with
## mist at their feet and the ground band over them; `Base` a stage's little base far off at the treeline's foot, a dark
## silhouette (TankForest.far_base), `BaseLight` its lamps, `Scrub` the scrub and the mist it stands its foot in, all
## behind every enemy; `World` the
## wrecks and the far enemies back to front by range and the Behemoth; `Light` (additive) slit glows, the moon on each
## enemy, the firing mark (a hot line along a shooter's bore), the searchlight's cold pool on
## the target, fires, shells and impact flashes from the panel's own TankFx; `Veil` the dark a tow fades it to, the
## forest's silhouette still under it. TankView draws its texture over the near stage.
##
## Frames: "panel" px have x from the near-side edge (TankFarMap.range_x) and y on the stage (the road line at
## TankView.GROUND); World and Light mirror about the panel when the tank drives west, Back never does.
## canvas_rect() and canvas_point() turn panel px into canvas px for the HUD and the view.

const PLANE_PARALLAX := 0.3
## How fast the sky and the mountains slide against the near panel's road, at PLANE_PARALLAX.
const SKY_SLIDE := 0.04
const RIDGE_SLIDE := 0.12
## The ground band's top (stage y): above the feet of the rearmost lane at the far end (338).
const GROUND_TOP := 326.0
const GROUND_H := 170.0
const GROUND_EARTH := Color(0.062, 0.07, 0.058)
const GROUND_DARK := Color(0.03, 0.036, 0.032)
const GROUND_LIP := Color(0.1, 0.12, 0.09)
const SHADE_TOP := Color(0, 0, 0, 0.22)
const SHADE_BOTTOM := Color(0, 0, 0, 0.4)
const SHADE_TOP_END := 150.0
const SHADE_BOTTOM_START := 440.0
## The sky, its own grade as the near panel's: darker at the top.
const SKY_TOP := Color(0.03, 0.078, 0.092)
const SKY_LOW := Color(0.05, 0.125, 0.145)
const SKY_LOW_Y := 280.0
## The moonlit air the treeline stands against: from clear at its top to this at the horizon.
const HORIZON_GLOW := Color(0.14, 0.26, 0.3, 0.34)
const HORIZON_TOP := 150.0
const HORIZON_END := 300.0
## The firs, far to near (TankEnemyKit.far_forest_rects): the stage y of each wall's foot, how fast it slides against
## the near panel's road. Each wall's foot row is stretched down to the next, so no sky shows under a wall.
const FOREST_FOOT: Array[float] = [270.0, 296.0, 334.0]
const FOREST_SLIDE: Array[float] = [0.18, 0.34, 0.6]
## The mist at a wall's foot: its rows up from the foot, its colour at the foot, one soft rise: no band's edge.
const MIST := Color(0.2, 0.33, 0.36, 0.3)
const MIST_ROWS := 26.0
const MIST_BELOW := 18.0
## A stage's base stands far off at the treeline's foot, never under an enemy's tracks: a dark shape in the far air,
## its foot in the scrub and in a mist that has no edge, and its lamp off any hull that stands before it.
const BASE_FOOT := 345.0
const BASE_NIGHT := Color(0.26, 0.34, 0.38)
const BASE_MIST := Color(0.2, 0.33, 0.36, 0.24)
const BASE_MIST_ROWS := 34.0
const BASE_MIST_BELOW := 12.0
const LAMP_CLEAR := 6.0
## The scrub along the treeline's foot (TankEnemyKit.far_scrub_rect), its foot and slide.
const SCRUB_FOOT := 346.0
const SCRUB_SLIDE := 0.7
## Dim moonlight on an enemy: a cold wash over its top, its pool on the ground.
const MOON := Color(0.5, 0.68, 0.82)
const MOON_WASH := 0.06
const MOON_POOL := 0.07
const OVERDRAW := 4.0
## A sprite's haze across the field; the night it comes out of over the first third of its entry.
const HAZE_NEAR := 0.12
const HAZE_SPAN := 0.38
const ENTER_S := 10.0
## How much the far end of the field dims: by range, so farther is always darker, whatever the lane.
const RANGE_DIM := 0.1
## How fast a sprite slides to its new place (px/s) when another one's range pushes it.
const PLACE_PX_S := 24.0
## The Behemoth is wider than some panels: its bow and gun stay whole this far off the near-side edge, its stern may go.
const BOSS_EDGE := 6.0
## Tracks: art px per metre of range change, and per metre the hull drives (they pace us).
const TRAVEL_PER_M := 1.0
const TRAVEL_PACE := 6.0
const RECOIL_PX := 4.0
const RECOIL_DECAY := 2.5
const TELEGRAPH_PULSE := 30.0
## The veil of a shooter in its telegraph: a pulse the plates still show through (at 0.25 + 0.25 sin, the
## first number, TankEnemyDraw's veil made it a pale ghost for the whole telegraph). The muzzle's glow warns.
const TELEGRAPH_FLASH := 0.03
const MAX_WRECKS := 8
const WRECK_DIM := 0.25
const COLD := Color(0.66, 0.82, 1.0)
const FIRE := Color(1.0, 0.42, 0.12)
const FIRE_CORE := Color(1.0, 0.75, 0.35)
const MUZZLE := Color(1.0, 0.55, 0.25)
const SHELL_OURS := Color(1.0, 0.75, 0.35)
const SHELL_THEIRS := Color(1.0, 0.35, 0.2)
## A shell's drop: the corner it starts from sits this high above its landing; theirs rises to the edge.
const THEIRS_RISE := 70.0
## A shell of ours landing this near the target's range comes down on the sprite (its place may be pushed).
const LAND_ON_TARGET_M := 90.0
const SHAKE_DECAY := 3.0
const SHAKE_PX := 2.0
const SEARCH_POOL_R := 40.0
const BOGIE_U: Array[float] = [0.2, 0.5, 0.8]
const BOGIE_V := 0.85
const TURRET_AT := Vector2(0.55, 0.3)
## The tow's dark: its fade in (s), how black at its deepest (the forest's silhouette stays under it, so it reads as
## a fade, never a crash), the noise rows, their refresh (Hz) and their strongest alpha.
const VEIL_IN_S := 1.0
const VEIL_DEEP := 0.8
const VEIL_ROWS := 5
const VEIL_NOISE_HZ := 12.0
const VEIL_NOISE := Color(0.32, 0.36, 0.34)
const VEIL_NOISE_A := 0.05
## The firing mark: a hot barrel down the bore and a short flare off the muzzle, in a colour and a shape no idle cue
## uses (the exhausts and vents are round warm orange, the slits cold). Only the soonest shots burn; the rest of a
## crowded field keep the cross on the muzzle and the HUD's tick, so it never turns into a laser show.
const SIGNAL := Color(1.0, 0.1, 0.26)
const SIGNAL_CORE := Color(1.0, 0.86, 0.8)
const SIGNAL_HZ := 7.0
const SIGNAL_FLARE := 4.0
const SIGNAL_CROSS := 3.0
const SIGNAL_BURNS := 3
## A smashed bogie's fire: the flame's height and where it stands over the part's middle.
const BOGIE_FLAME := 14.0
const BOGIE_FLAME_UP := 2.0

var v: TankView = null
var kit: TankEnemyKit = TankEnemyKit.shared()
var fx: TankFx = TankFx.new()
## Enemy id -> Rect2 in panel px, and its foot.
var rects: Dictionary = {}
var feet: Dictionary = {}
## {range, lane, kind, t}
var wrecks: Array[Dictionary] = []
## The Behemoth's foot in panel px and its rect (size 0 when it is not drawn).
var boss_foot: Vector2 = Vector2.ZERO
var boss_box: Rect2 = Rect2()
var far_w: float = TankFarMap.far_w(960.0)
var shake: float = 0.0
## How black the panel is (0..1): up while the tank is towed, down at the restart's pace after it.
var veil: float = 0.0

var _root: Node2D = null
var _back: Node2D = null
var _base: Node2D = null
var _base_light: Node2D = null
var _scrub_layer: Node2D = null
var _world: Node2D = null
var _light: Node2D = null
var _veil: Node2D = null
var _mirrored: bool = false
var _y_off: float = 0.0
## Enemy id -> {t0, travel, recoil, last, kind, lane, range}; _boss the same for the Behemoth.
var _seen: Dictionary = {}
var _boss: Dictionary = {}
var _smoke_acc: float = 0.0
## The sim time the wrecks last closed in at (a wreck stands in the world, so the hull's travel brings it
## nearer, close_wrecks).
var _close_t: float = -1.0


func _init(view: TankView, sd: int) -> void:
	v = view
	name = "TankFarPanel"
	transparent_bg = false
	disable_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	fx.seed_rng(sd + 1)
	_root = Node2D.new()
	_root.name = "Root"
	add_child(_root)
	_back = _layer("Back")
	_back.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_base = _layer("Base")
	_base.modulate = BASE_NIGHT
	_base_light = _layer("BaseLight")
	_scrub_layer = _layer("Scrub")
	_world = _layer("World")
	_light = _layer("Light")
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for l: Node2D in [_base_light, _light]:
		l.material = add
		l.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_veil = _layer("Veil")
	_back.draw.connect(_draw_back)
	_base.draw.connect(_draw_base)
	_base_light.draw.connect(_draw_base_light)
	_scrub_layer.draw.connect(_draw_scrub)
	_world.draw.connect(_draw_world)
	_light.draw.connect(_draw_light)
	_veil.draw.connect(_draw_veil)


func _layer(n: String) -> Node2D:
	var l := Node2D.new()
	l.name = n
	_root.add_child(l)
	return l


func layer(n: String) -> Node2D:
	return _root.get_node_or_null(n) as Node2D


## The panel's size follows the flex canvas; World and Light mirror about it going west.
func layout(canvas: Vector2, mirrored: bool, y_off: float) -> void:
	far_w = TankFarMap.far_w(canvas.x)
	_mirrored = mirrored
	_y_off = y_off
	var want := Vector2i(int(far_w), int(canvas.y))
	if size != want:
		size = want
	for l: Node2D in [_base, _base_light, _scrub_layer, _world, _light]:
		l.scale = Vector2(-1, 1) if mirrored else Vector2.ONE
		l.position = Vector2(far_w, 0) if mirrored else Vector2.ZERO


# --- Mapping ------------------------------------------------------------------------------------------


## A sprite's foot x: the range's x, held whole inside the panel (a wider sprite centred).
static func foot_x(range_m: float, half_w: float, panel_w: float) -> float:
	var x := TankFarMap.range_x(range_m, panel_w)
	if half_w * 2.0 >= panel_w:
		return roundf(panel_w * 0.5)
	return roundf(clampf(x, half_w + 1.0, panel_w - half_w - 1.0))


## The Behemoth's foot x: as foot_x, its bow and gun whole BOSS_EDGE off the near-side edge on every canvas.
static func boss_foot_x(range_m: float, half_w: float, panel_w: float) -> float:
	var x := TankFarMap.range_x(range_m, panel_w)
	return roundf(maxf(minf(x, panel_w - half_w - 1.0), half_w + BOSS_EDGE))


static func haze_at(range_m: float) -> float:
	var k := (
		(range_m - TankFarMap.RANGE_NEAR_M) / (TankFarMap.RANGE_FAR_M - TankFarMap.RANGE_NEAR_M)
	)
	return HAZE_NEAR + HAZE_SPAN * clampf(k, 0.0, 1.0)


## A panel point on the canvas.
func canvas_point(p: Vector2, panel_x: float) -> Vector2:
	var x := far_w - p.x if _mirrored else p.x
	return Vector2(panel_x + x, p.y + _y_off)


## A panel rect on the canvas.
func canvas_rect(r: Rect2, panel_x: float) -> Rect2:
	var x := far_w - r.end.x if _mirrored else r.position.x
	return Rect2(Vector2(panel_x + x, r.position.y + _y_off), r.size)


func _rect_of(kind: String, foot: Vector2) -> Rect2:
	var sz: Vector2 = kit.kind(kind)["size"]
	return Rect2(foot - Vector2(roundf(sz.x * 0.5), sz.y), sz)


# --- Frame --------------------------------------------------------------------------------------------


## One frame: who stands where, their tracks and recoil, the emitters, the particles and the shake.
func frame(state: TankState, dt: float) -> void:
	_track(state, dt)
	_track_boss(state, dt)
	_emit(state, dt)
	close_wrecks(state)
	fx.step(dt, 0.0)
	shake = maxf(shake - dt * SHAKE_DECAY, 0.0)
	var off := Vector2.ZERO
	if shake > 0.0:
		var t := v.time
		off = Vector2(roundf(sin(t * 61.0) * SHAKE_PX * shake), roundf(cos(t * 47.0) * shake))
	_root.position = Vector2(0, _y_off) + off
	var towed := state.hull.tow_s > 0.0
	veil = move_toward(
		veil, 1.0 if towed else 0.0, dt / (VEIL_IN_S if towed else TankView.RESTART_FADE_S)
	)
	for l: Node2D in [_back, _base, _base_light, _scrub_layer, _world, _light, _veil]:
		l.queue_redraw()


func _record(key: int, kind: String, lane: int, range_m: float, state: TankState) -> Dictionary:
	var rec: Dictionary = _seen.get(key, {})
	if rec.is_empty():
		rec = {"t0": state.t, "travel": 0.0, "recoil": 0.0, "last": range_m}
		_seen[key] = rec
	rec["kind"] = kind
	rec["lane"] = lane
	rec["range"] = range_m
	return rec


func _advance_rec(rec: Dictionary, range_m: float, state: TankState, dt: float) -> void:
	var moved := absf(range_m - float(rec["last"])) * TRAVEL_PER_M
	moved += state.hull.speed_mps * TRAVEL_PACE * dt
	rec["travel"] = float(rec["travel"]) + moved
	rec["last"] = range_m
	rec["recoil"] = maxf(float(rec["recoil"]) - dt * RECOIL_DECAY, 0.0)


func _track(state: TankState, dt: float) -> void:
	rects.clear()
	feet.clear()
	var alive := {}
	var rows: Array = []
	var fresh: Array[int] = []
	for e in state.enemies:
		if e.is_near() or e.mode == TankIds.EM_DEAD:
			continue
		alive[e.id] = true
		var rng := v.far_range_of(e)
		var kind := TankIds.enemy_of(e.code)
		if not _seen.has(e.id):
			fresh.append(e.id)
		var rec := _record(e.id, kind, e.lane, rng, state)
		_advance_rec(rec, rng, state, dt)
		var half := float(kit.kind(kind)["size"].x) * 0.5
		var row := {"id": e.id, "range_m": rng, "lane": e.lane, "half_w": half}
		row.merge(_anatomy(kind, rng))
		rows.append(row)
	var placed := TankFarMap.place(rows, far_w)
	for row: Dictionary in rows:
		var id: int = row["id"]
		var rec2: Dictionary = _seen[id]
		var goal: Vector2 = placed[id]
		var foot: Vector2 = rec2.get("foot", goal)
		foot = foot.move_toward(goal, PLACE_PX_S * dt)
		rec2["foot"] = foot
		foot = foot.round()
		feet[id] = foot
		rects[id] = _rect_of(str(rec2["kind"]), foot)
		var e2 := state.enemy(id)
		if fresh.has(id) and e2 != null and e2.mode == TankIds.EM_ENTER:
			_dust(foot, float(row["half_w"]))
	for id2: int in _seen.keys():
		if not alive.has(id2):
			_seen.erase(id2)


## What TankFarMap.place needs to keep this kind's muzzle off a nearer tank's turret: both from the foot.
func _anatomy(kind: String, rng: float) -> Dictionary:
	var row := kit.kind(kind)
	var out := {}
	if not row.has("gun"):
		return out
	var elev := TankBallistics.far_elevation(rng, v.far_v0(), v.far_g())
	var pose := {"elev_deg": elev if not is_nan(elev) else 0.0}
	out["muzzle"] = TankEnemyDraw.muzzle(kit, kind, Vector2.ZERO, pose)
	if row.has("turret"):
		var t: Dictionary = row["turret"]
		var sz: Vector2 = row["size"]
		var from := Vector2(sz.x * 0.5, float(row["ground"]))
		out["turret"] = Rect2((t["at"] as Vector2) - from, (t["rect"] as Rect2).size)
	return out


func _track_boss(state: TankState, dt: float) -> void:
	boss_box = Rect2()
	if not v.boss_visible(state):
		_boss.clear()
		return
	var rng := v.far_boss_range(state)
	if _boss.is_empty():
		_boss = {"t0": state.t, "travel": 0.0, "recoil": 0.0, "last": rng}
	_advance_rec(_boss, rng, state, dt)
	var half := float(kit.kind(TankIds.BOSS_ID)["size"].x) * 0.5
	boss_foot = Vector2(boss_foot_x(rng, half, far_w), TankFarMap.foot_y(rng, 0))
	boss_box = _rect_of(TankIds.BOSS_ID, boss_foot)


## The ground under a far sprite (a Callable for the kit's suspension): small bumps rolling past.
func ground_at(x: float, foot_y: float) -> float:
	var s := v.plane_x * TankView.S * PLANE_PARALLAX
	return foot_y + roundf(sin((x + s) * 0.07) + 0.6 * sin((x + s) * 0.19))


## A far enemy's pose (SPEC_TANK 5.4).
func pose_of(e: TankEnemyState, foot: Vector2) -> Dictionary:
	var rng := v.far_range_of(e)
	var rec: Dictionary = _seen.get(e.id, {})
	var haze := haze_at(rng)
	if e.mode == TankIds.EM_ENTER and not rec.is_empty():
		var u := clampf((v.game.state.t - float(rec["t0"])) / (ENTER_S / 3.0), 0.0, 1.0)
		haze = lerpf(1.0, haze, u)
	return _pose(
		rng,
		foot,
		float(rec.get("travel", 0.0)),
		float(rec.get("recoil", 0.0)),
		haze,
		_range_dim(rng),
		_pulse(e.telegraph_s)
	)


func boss_pose(state: TankState) -> Dictionary:
	var rng := v.far_boss_range(state)
	var p := _pose(
		rng,
		boss_foot,
		float(_boss.get("travel", 0.0)),
		float(_boss.get("recoil", 0.0)),
		haze_at(rng),
		0.0,
		_pulse(state.boss.telegraph_s)
	)
	var broken: Array[bool] = []
	for hp in state.boss.bogie_hp:
		broken.append(hp <= 0.0)
	p["bogies_wrecked"] = broken
	p["wrecked"] = state.boss.phase == TankIds.BOSS_DEAD
	return p


func _pose(
	rng: float, foot: Vector2, travel: float, recoil: float, haze: float, dim: float, flash: float
) -> Dictionary:
	var elev := TankBallistics.far_elevation(rng, v.far_v0(), v.far_g())
	return {
		"travel": travel,
		"turret_sx": 1.0,
		"elev_deg": elev if not is_nan(elev) else 0.0,
		"recoil": recoil * RECOIL_PX,
		"dim": dim,
		"haze": haze,
		"flash": flash,
		"ground": Callable(self, "ground_at").bind(foot.y),
		"wrecked": false,
		"bogies_wrecked": [] as Array[bool],
		"flip": false,
		"time": v.time,
	}


static func _range_dim(range_m: float) -> float:
	var k := (
		(range_m - TankFarMap.RANGE_NEAR_M) / (TankFarMap.RANGE_FAR_M - TankFarMap.RANGE_NEAR_M)
	)
	return RANGE_DIM * clampf(k, 0.0, 1.0)


func _pulse(telegraph_s: float) -> float:
	return TELEGRAPH_FLASH * (1.0 + sin(v.time * TELEGRAPH_PULSE)) if telegraph_s > 0.0 else 0.0


## An enemy's muzzle in panel px (or Vector2.ZERO when it is not drawn).
func muzzle_of(e: TankEnemyState) -> Vector2:
	if not feet.has(e.id):
		return Vector2.ZERO
	var foot: Vector2 = feet[e.id]
	return TankEnemyDraw.muzzle(kit, TankIds.enemy_of(e.code), foot, pose_of(e, foot))


func boss_muzzle(state: TankState) -> Vector2:
	if boss_box.size == Vector2.ZERO:
		return Vector2.ZERO
	return TankEnemyDraw.muzzle(kit, TankIds.BOSS_ID, boss_foot, boss_pose(state))


## Boss part `part`'s centre in panel px: bogie 0 nearest the tank, TURRET_PART the turret.
func boss_part_at(part: int) -> Vector2:
	var u := TURRET_AT
	if part >= 0 and part < BOGIE_U.size():
		u = Vector2(BOGIE_U[part], BOGIE_V)
	return boss_box.position + boss_box.size * u


# --- Effects (TankView's cues) ------------------------------------------------------------------------


## Theirs fired: muzzle flash, the gun's recoil.
func on_fired(state: TankState, src: int, shell: int) -> void:
	var e := state.enemy(src)
	if e != null and feet.has(src):
		var rec: Dictionary = _seen.get(src, {})
		rec["recoil"] = 1.0
		_flash(muzzle_of(e), 18.0, 0.35)
	elif shell == TankIds.SHELL_BOSS_MAIN and boss_box.size != Vector2.ZERO:
		_boss["recoil"] = 1.0
		_flash(boss_muzzle(state), 34.0, 0.8)


func _flash(at: Vector2, r: float, k: float) -> void:
	fx.flash(at, r, 0.12, MUZZLE, Vector2.LEFT)
	fx.light_scene(at, k, MUZZLE)


## Our shell struck enemy `id`.
func on_enemy_hit(id: int) -> void:
	if rects.has(id):
		var r: Rect2 = rects[id]
		fx.boom(r.get_center() + Vector2(fx.rng.randf_range(-8, 8), 0), 14.0, 4)
		shake = maxf(shake, 0.5)


func on_boss_hit(part: int) -> void:
	if boss_box.size != Vector2.ZERO:
		fx.boom(boss_part_at(part), 18.0, 6)
		shake = maxf(shake, 0.7)


## A shell of ours landing on nothing at `range_m`: earth thrown up.
func on_splash(range_m: float) -> void:
	var at := Vector2(TankFarMap.range_x(range_m, far_w), TankFarMap.foot_y(range_m, 0))
	fx.boom(at, 8.0, 3)
	_dust(at, 8.0)


## Enemy `id` died: its wreck stays at its range, burning. False when it never stood here.
func on_kill(state: TankState, id: int) -> bool:
	if not _seen.has(id):
		return false
	var rec: Dictionary = _seen[id]
	(
		wrecks
		. append(
			{
				"range": float(rec["range"]),
				"lane": int(rec["lane"]),
				"kind": str(rec["kind"]),
				"t": state.t,
			}
		)
	)
	while wrecks.size() > MAX_WRECKS:
		wrecks.pop_front()
	if rects.has(id):
		var r: Rect2 = rects[id]
		fx.boom(r.get_center(), 24.0, 8)
		fx.light_scene(r.get_center(), 0.6, FIRE)
		shake = 1.0
	return true


func on_boss_kill() -> void:
	if boss_box.size == Vector2.ZERO:
		return
	for i in 5:
		fx.boom(boss_box.position + boss_box.size * Vector2(0.2 + 0.15 * i, 0.5), 30.0, 8)
	fx.light_scene(boss_box.get_center(), 1.0, FIRE)
	shake = 1.0


func _dust(at: Vector2, half: float) -> void:
	for i in 5:
		var j := fx.rng.randf()
		fx.puff(
			at + Vector2(lerpf(-half, half, j), -1.0),
			Vector2(fx.rng.randf_range(-6, 6), fx.rng.randf_range(-8, -2)),
			1.6,
			Vector2(3.0, 16.0),
			0.22,
			Color(0.3, 0.27, 0.22),
			0.0
		)


func _emit(state: TankState, dt: float) -> void:
	_smoke_acc += dt * (1.2 * float(feet.size()) + 2.0 * float(wrecks.size()))
	while _smoke_acc >= 1.0:
		_smoke_acc -= 1.0
		var n := feet.size() + wrecks.size()
		if n == 0:
			continue
		var pick := fx.rng.randi_range(0, n - 1)
		if pick < feet.size():
			_exhaust(feet.keys()[pick])
		else:
			_wreck_smoke(state, wrecks[pick - feet.size()])


func _exhaust(id: int) -> void:
	var r: Rect2 = rects[id]
	var row := kit.kind(str((_seen[id] as Dictionary)["kind"]))
	var at: Vector2 = row.get("exhaust", r.size * Vector2(0.85, 0.3))
	fx.puff(
		r.position + at,
		Vector2(fx.rng.randf_range(2, 6), fx.rng.randf_range(-10, -5)),
		1.8,
		Vector2(1.5, 8.0),
		0.14,
		Color(0.2, 0.2, 0.2),
		0.0
	)


func _wreck_smoke(state: TankState, w: Dictionary) -> void:
	var k := wreck_fire(w, state.t)
	if k <= 0.0:
		return
	var j := fx.rng.randf()
	fx.puff(
		_wreck_hatch(w) + Vector2(j * 2.0 - 1.0, -2.0),
		Vector2(1.0 + j * 2.0, -14.0 - j * 6.0),
		3.0,
		Vector2(2.0, 12.0),
		0.24,
		Color(0.16, 0.15, 0.14),
		0.0
	)


func wreck_fire(w: Dictionary, t: float) -> float:
	return clampf(1.0 - (t - float(w["t"])) / TankView.WRECK_BURN_S, 0.0, 1.0)


func _wreck_foot(w: Dictionary) -> Vector2:
	var half := float(kit.kind(str(w["kind"]))["size"].x) * 0.5
	var rng := float(w["range"])
	return Vector2(foot_x(rng, half, far_w), TankFarMap.foot_y(rng, int(w["lane"])))


func _wreck_hatch(w: Dictionary) -> Vector2:
	var r := _rect_of(str(w["kind"]), _wreck_foot(w))
	return r.position + r.size * Vector2(0.45, 0.25)


## A far wreck stands where it fell: the hull's travel since the last call (its ground speed over the sim time
## that passed) brings it nearer, and one that has come inside RANGE_NEAR_M is behind the panel's near
## edge, so it goes. Sim time, so a pause or a client's snapshot step moves it exactly as far as the hull went.
func close_wrecks(state: TankState) -> void:
	var step_s := state.t - _close_t if _close_t >= 0.0 else 0.0
	_close_t = state.t
	if step_s <= 0.0 or step_s > 1.0 or wrecks.is_empty():
		return
	var travelled := TankSegments.ground_mps(state) * step_s
	if travelled <= 0.0:
		return
	var keep: Array[Dictionary] = []
	for w in wrecks:
		w["range"] = float(w["range"]) - travelled
		if float(w["range"]) >= TankFarMap.RANGE_NEAR_M:
			keep.append(w)
	wrecks = keep


## Drops wrecks older than TankView.WRECK_GONE_S.
func age_wrecks(t: float) -> void:
	var keep: Array[Dictionary] = []
	for w in wrecks:
		if t - float(w["t"]) <= TankView.WRECK_GONE_S and t >= float(w["t"]):
			keep.append(w)
	wrecks = keep


# --- Shells -------------------------------------------------------------------------------------------


## The far shells on this panel now (SPEC_TANK 4.4): [{at, from (the tail), friendly}] in panel px. Ours in
## their last ARRIVE_S, dropping from the top near-side corner onto where they land; theirs in their first
## LEAVE_S, from their muzzle to the near-side edge.
func shells_drawn(state: TankState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in state.shells:
		if not s.far:
			continue
		var left := v.shell_left(s)
		if s.friendly:
			var k := TankShellPath.arrive_k(left)
			if k < 0.0:
				continue
			var land := TankShellPath.landing_m(s.x, s.vx, s.left_s)
			var to := _landing(state, land)
			var top := Vector2(0.0, -_y_off)
			out.append(_shell_row(top.lerp(to, k), top, true))
			continue
		var flight := TankShellPath.flight_s(s.left_s, s.vy, v.far_g())
		var age := flight - left
		var k2 := TankShellPath.leave_k(age)
		if k2 < 0.0:
			continue
		var from_m := TankShellPath.launch_m(s.x, s.vx, flight - s.left_s)
		var mz := _shooter_muzzle(state, s, from_m)
		var edge := Vector2(-OVERDRAW, mz.y - THEIRS_RISE)
		out.append(_shell_row(mz.lerp(edge, k2), mz, false))
	return out


func _shell_row(at: Vector2, start: Vector2, friendly: bool) -> Dictionary:
	var d := (at - start).normalized()
	var tail := at - d * minf(at.distance_to(start), 16.0)
	return {"at": at, "from": tail, "friendly": friendly}


## Where a shell of ours landing `land` m out comes down: on the target where it stands, when it lands by it.
func _landing(state: TankState, land: float) -> Vector2:
	var e := state.enemy(state.hull.target_id)
	if e != null and feet.has(e.id) and absf(v.far_range_of(e) - land) < LAND_ON_TARGET_M:
		return (feet[e.id] as Vector2) - Vector2(0, 6)
	var lane := e.lane if e != null else 0
	return Vector2(TankFarMap.range_x(land, far_w), TankFarMap.foot_y(land, lane) - 6.0)


## Where a shell of theirs left from: the source's muzzle, the enemy standing nearest the range it left
## from on a client (`source` is host only), else a point above the ground there.
func _shooter_muzzle(state: TankState, s: TankShellState, from_m: float) -> Vector2:
	var e := state.enemy(s.source)
	if e == null or not feet.has(e.id):
		e = null
		var best := INF
		for c in state.enemies:
			if feet.has(c.id) and absf(v.far_range_of(c) - from_m) < best:
				best = absf(v.far_range_of(c) - from_m)
				e = c
	if s.type == TankIds.SHELL_BOSS_MAIN and boss_box.size != Vector2.ZERO:
		return boss_muzzle(state)
	if e != null:
		return muzzle_of(e)
	return Vector2(TankFarMap.range_x(from_m, far_w), TankFarMap.foot_y(from_m, 0) - 30.0)


# --- Layers -------------------------------------------------------------------------------------------


func _draw_back() -> void:
	if v == null or not _ready_to_draw():
		return
	var ci := _back
	var top := -_y_off - OVERDRAW
	var w := far_w + OVERDRAW * 2.0
	var bottom := float(size.y) - _y_off + OVERDRAW
	ci.draw_rect(Rect2(-OVERDRAW, top, w, bottom - top), SKY_LOW)
	_band(ci, top, SKY_LOW_Y, SKY_TOP, SKY_LOW)
	var tint := TankForest.forest_tint(v, v.game.state)
	_tile(ci, TankFarSky.sky(), SKY_SLIDE, Color.WHITE)
	_tile(ci, TankFarSky.ridge(), RIDGE_SLIDE, tint)
	_band(ci, HORIZON_TOP, HORIZON_END, Color(HORIZON_GLOW, 0.0), HORIZON_GLOW)
	_forest(ci, tint)
	_ground(ci, bottom)
	var clear := Color(0, 0, 0, 0)
	_band(ci, top, SHADE_TOP_END, SHADE_TOP, clear)
	_band(ci, SHADE_BOTTOM_START, bottom, clear, SHADE_BOTTOM)


## A baked layer (TankFarSky) tiled across the panel, at its slide.
func _tile(ci: CanvasItem, tex: Texture2D, slide: float, mod: Color) -> void:
	var w := float(tex.get_width())
	var x := -fposmod(v.plane_x * TankView.S * PLANE_PARALLAX * slide, w)
	while x < far_w + OVERDRAW:
		ci.draw_texture(tex, Vector2(roundf(x), 0.0), mod)
		x += w


func _ready_to_draw() -> bool:
	return v.game != null and v.game.state != null and v.rig != null


## The treeline, far to near, each wall's foot in its mist.
func _forest(ci: CanvasItem, tint: Color) -> void:
	var tex := kit.far_forest()
	var rects := kit.far_forest_rects()
	if tex == null:
		return
	for i in mini(rects.size(), FOREST_FOOT.size()):
		var r: Rect2 = rects[i]
		var foot := FOREST_FOOT[i]
		var low := GROUND_TOP + GROUND_H * 0.1
		var slide := v.plane_x * TankView.S * PLANE_PARALLAX * FOREST_SLIDE[i]
		var x := -fposmod(slide, r.size.x) - r.size.x
		var last := Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1.0)
		while x < far_w + OVERDRAW:
			var at := Vector2(roundf(x), foot - r.size.y)
			ci.draw_texture_rect_region(tex, Rect2(at, r.size), r, tint)
			if low > foot:
				ci.draw_texture_rect_region(
					tex, Rect2(at.x, foot, r.size.x, low - foot), last, tint
				)
			x += r.size.x
		_mist(ci, foot)


func _mist(ci: CanvasItem, foot: float) -> void:
	_band(ci, foot - MIST_ROWS, foot, Color(MIST, 0.0), MIST)
	_band(ci, foot, foot + MIST_BELOW, MIST, Color(MIST, 0.0))


func _ground(ci: CanvasItem, bottom: float) -> void:
	var tex := kit.far_ground()
	var end_y := GROUND_TOP + GROUND_H
	if tex != null:
		var w := float(tex.get_width())
		var x := -fposmod(v.plane_x * TankView.S * PLANE_PARALLAX, w) - w
		while x < far_w + OVERDRAW:
			ci.draw_texture(tex, Vector2(roundf(x), GROUND_TOP))
			x += w
	else:
		_ground_stub(ci)
	if bottom > end_y:
		ci.draw_rect(Rect2(-OVERDRAW, end_y, far_w + OVERDRAW * 2.0, bottom - end_y), GROUND_DARK)


## Until builder A's far_ground.png: plain earth, darker downward, a broken lip.
func _ground_stub(ci: CanvasItem) -> void:
	var a := Vector2(-OVERDRAW, GROUND_TOP)
	var b := Vector2(far_w + OVERDRAW, GROUND_TOP)
	var low := Vector2(0, GROUND_H)
	ci.draw_polygon(
		PackedVector2Array([a, b, b + low, a + low]),
		PackedColorArray([GROUND_EARTH, GROUND_EARTH, GROUND_DARK, GROUND_DARK])
	)
	var s := v.plane_x * TankView.S * PLANE_PARALLAX
	var x := -OVERDRAW
	while x < far_w + OVERDRAW:
		var h := TankDraw.hash01(floorf(x + s) * 0.37)
		if h > 0.4:
			ci.draw_rect(Rect2(Vector2(x, GROUND_TOP - roundf(h * 2.0)), Vector2(1, 2)), GROUND_LIP)
		x += 1.0


func _band(ci: CanvasItem, y0: float, y1: float, c0: Color, c1: Color) -> void:
	var l := -OVERDRAW
	var r := far_w + OVERDRAW
	ci.draw_polygon(
		PackedVector2Array([Vector2(l, y0), Vector2(r, y0), Vector2(r, y1), Vector2(l, y1)]),
		PackedColorArray([c0, c0, c1, c1])
	)


## A stage's little base stands behind every enemy: its lamps light the base, never through a hull.
func _draw_base() -> void:
	if v == null or not _ready_to_draw():
		return
	var bx := TankForest.far_base(v, v.game.state)
	if not is_nan(bx):
		TankForest.draw_base(_base, v, bx, BASE_FOOT, lamp_clear(bx))


## False while a far sprite stands across the base's lamp post: it would rise out of the hull like a lamp on the tank.
func lamp_clear(bx: float) -> bool:
	var x := bx + TankForest.LAMP_X
	for r: Rect2 in rects.values():
		if x >= r.position.x - LAMP_CLEAR and x <= r.end.x + LAMP_CLEAR:
			return false
	if boss_box.size != Vector2.ZERO:
		return x < boss_box.position.x - LAMP_CLEAR or x > boss_box.end.x + LAMP_CLEAR
	return true


## The base's foot in its mist, soft at both edges, and the scrub along the treeline, over both.
func _draw_scrub() -> void:
	if v == null or not _ready_to_draw():
		return
	if not is_nan(TankForest.far_base(v, v.game.state)):
		var ci := _scrub_layer
		_band(ci, BASE_FOOT - BASE_MIST_ROWS, BASE_FOOT, Color(BASE_MIST, 0.0), BASE_MIST)
		_band(ci, BASE_FOOT, BASE_FOOT + BASE_MIST_BELOW, BASE_MIST, Color(BASE_MIST, 0.0))
	_scrub()


## The treeline's foot is no ruled line: scrub and low firs stand along it, over the ground's top.
func _scrub() -> void:
	var r := kit.far_scrub_rect()
	var tex := kit.far_forest()
	if tex == null or r.size == Vector2.ZERO:
		return
	var slide := v.plane_x * TankView.S * PLANE_PARALLAX * SCRUB_SLIDE
	var x := -fposmod(slide, r.size.x) - r.size.x
	var tint := TankForest.forest_tint(v, v.game.state)
	while x < far_w + OVERDRAW:
		var at := Rect2(Vector2(roundf(x), SCRUB_FOOT - r.size.y), r.size)
		_scrub_layer.draw_texture_rect_region(tex, at, r, tint)
		x += r.size.x


func _draw_base_light() -> void:
	if v == null or not _ready_to_draw():
		return
	var bx := TankForest.far_base(v, v.game.state)
	if not is_nan(bx):
		TankForest.draw_base_light(_base_light, v, bx, BASE_FOOT, lamp_clear(bx))


func _draw_world() -> void:
	if v == null or not _ready_to_draw():
		return
	var state := v.game.state
	var ci := _world
	TankHangar.draw_far(ci, self, v.hangar_look)
	if boss_box.size != Vector2.ZERO:
		TankEnemyDraw.draw(ci, kit, TankIds.BOSS_ID, boss_foot, boss_pose(state))
	for row: Dictionary in _depth_order(state):
		if row.has("wreck"):
			_wreck(ci, row["wreck"])
		else:
			_enemy(ci, row["enemy"])
	fx.draw_solid(ci)
	fx.draw_smoke(ci)


## The wrecks and the far enemies back to front: by their feet, the highest (the farthest) first.
func _depth_order(state: TankState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for w in wrecks:
		out.append({"y": _wreck_foot(w).y, "wreck": w})
	for e in state.enemies:
		if feet.has(e.id):
			out.append({"y": (feet[e.id] as Vector2).y, "enemy": e})
	out.sort_custom(_higher)
	return out


static func _higher(a: Dictionary, b: Dictionary) -> bool:
	return float(a["y"]) < float(b["y"])


func _enemy(ci: CanvasItem, e: TankEnemyState) -> void:
	var foot: Vector2 = feet[e.id]
	var r: Rect2 = rects[e.id]
	TankEnemyDraw.draw(ci, kit, TankIds.enemy_of(e.code), foot, pose_of(e, foot))
	TankEnemyDraw.hp_bar(ci, r, r.position.y - 5.0, e.hp, e.hp_max)


func _wreck(ci: CanvasItem, w: Dictionary) -> void:
	var age := v.game.state.t - float(w["t"])
	var dim := WRECK_DIM * clampf(age / TankView.WRECK_BURN_S, 0.0, 1.0)
	TankEnemyDraw.draw(ci, kit, str(w["kind"]), _wreck_foot(w), _wreck_pose(w, dim))


func _wreck_pose(w: Dictionary, dim: float) -> Dictionary:
	return {
		"travel": 0.0,
		"turret_sx": 1.0,
		"elev_deg": 0.0,
		"recoil": 0.0,
		"dim": dim,
		"haze": haze_at(float(w["range"])),
		"flash": 0.0,
		"ground": null,
		"wrecked": true,
		"bogies_wrecked": [] as Array[bool],
		"flip": false,
		"time": v.time,
	}


func _draw_light() -> void:
	if v == null or not _ready_to_draw():
		return
	var state := v.game.state
	var ci := _light
	TankHangar.draw_far_light(ci, self, v.hangar_look)
	_search_pool(ci, state)
	var burning := burning_shots(state)
	for e in state.enemies:
		if not feet.has(e.id):
			continue
		var foot: Vector2 = feet[e.id]
		var pose := pose_of(e, foot)
		_moonlight(ci, rects[e.id])
		TankEnemyDraw.draw_light(ci, kit, TankIds.enemy_of(e.code), foot, pose)
		if e.telegraph_s > 0.0:
			var bore := TankEnemyDraw.bore(kit, TankIds.enemy_of(e.code), foot, pose)
			if burning.has(e.id):
				_telegraph(ci, bore, 1.0)
			else:
				_muzzle_cross(ci, bore[1], 1.0)
	_boss_light(ci, state)
	for w in wrecks:
		_wreck_fire(ci, w, state.t)
	_shells(ci, state)
	fx.draw_light(ci)
	if fx.wash > 0.0:
		var c := fx.wash_color
		TankDraw.glow_at(ci, fx.wash_pos, 160.0, Color(c.r, c.g, c.b, 0.16 * fx.wash))


## The moon on a far sprite: a cold wash from above its top, a dim pool on the earth beside its tracks.
func _moonlight(ci: CanvasItem, r: Rect2) -> void:
	var top := r.position + Vector2(r.size.x * 0.42, r.size.y * 0.22)
	TankDraw.glow_at(ci, top, r.size.x * 0.62, Color(MOON, MOON_WASH))
	var pool := Vector2(r.get_center().x, r.end.y + 1.0)
	TankLightDraw.ground_glow(ci, pool, r.size.x * 0.6, Color(MOON, MOON_POOL))


## The enemies whose barrels burn this frame: the soonest shots, the Behemoth's taking a place of its own.
func burning_shots(state: TankState) -> Array[int]:
	var due: Array[TankEnemyState] = []
	for e in state.enemies:
		if feet.has(e.id) and e.telegraph_s > 0.0:
			due.append(e)
	due.sort_custom(_due_sooner)
	var n := SIGNAL_BURNS
	if boss_box.size != Vector2.ZERO and state.boss.telegraph_s > 0.0:
		n -= 1
	var out: Array[int] = []
	for i in mini(n, due.size()):
		out.append(due[i].id)
	return out


static func _due_sooner(a: TankEnemyState, b: TankEnemyState) -> bool:
	return a.telegraph_s < b.telegraph_s


## The firing mark, above every nearer tank (the Light layer): the barrel burns along its bore from breech to muzzle,
## a short flare off its end, a hard cross on the tip, all blinking fast. No orb: the warm orbs are the exhausts' and
## the vents'.
func _telegraph(ci: CanvasItem, bore: Array[Vector2], size_k: float) -> void:
	var from := bore[0]
	var tip := bore[1]
	var d := (tip - from).normalized()
	var beat := 0.65 + 0.35 * signf(sin(v.time * TAU * SIGNAL_HZ))
	var n := maxi(ceili(from.distance_to(tip)), 1)
	for i in n + 1:
		var u := float(i) / float(n)
		var p := from.lerp(tip, u).floor()
		ci.draw_rect(Rect2(p, Vector2.ONE), Color(SIGNAL, (0.3 + 0.7 * u) * beat))
		ci.draw_rect(Rect2(p + Vector2(0, -1), Vector2.ONE), Color(SIGNAL, 0.32 * u * beat))
	var flare := int(SIGNAL_FLARE * size_k * (0.7 + 0.3 * beat))
	for j in flare:
		var q := (tip + d * float(j)).floor()
		ci.draw_rect(Rect2(q, Vector2.ONE), Color(SIGNAL, beat * (1.0 - float(j) / float(flare))))
	_muzzle_cross(ci, tip, size_k)


## A shot due: the hard cross on the muzzle, blinking.
func _muzzle_cross(ci: CanvasItem, tip: Vector2, size_k: float) -> void:
	var beat := 0.65 + 0.35 * signf(sin(v.time * TAU * SIGNAL_HZ))
	var at := tip.floor()
	var arm := int(SIGNAL_CROSS * size_k)
	ci.draw_rect(Rect2(at + Vector2(0, -arm), Vector2(1, arm * 2 + 1)), Color(SIGNAL, 0.8 * beat))
	ci.draw_rect(Rect2(at + Vector2(-arm, 0), Vector2(arm * 2 + 1, 1)), Color(SIGNAL, 0.8 * beat))
	ci.draw_rect(Rect2(at + Vector2(-1, -1), Vector2(3, 3)), Color(SIGNAL_CORE, beat))


## The searchlight's cold pool on the target's front edge while the Lights seat is powered.
func _search_pool(ci: CanvasItem, state: TankState) -> void:
	if v.search_level <= 0.0:
		return
	var box := Rect2()
	if rects.has(state.hull.target_id):
		box = rects[state.hull.target_id]
	elif TankBossState.is_part_id(state.hull.target_id):
		box = boss_box
	if box.size == Vector2.ZERO:
		return
	var k := v.search_level
	var edge := Vector2(box.position.x + 4.0, box.end.y)
	TankLightDraw.ground_glow(ci, edge + Vector2(0, 2), SEARCH_POOL_R, Color(COLD, 0.34 * k))
	TankDraw.glow_at(ci, edge - Vector2(0, box.size.y * 0.5), box.size.y, Color(COLD, 0.12 * k))


func _boss_light(ci: CanvasItem, state: TankState) -> void:
	if boss_box.size == Vector2.ZERO:
		return
	var pose := boss_pose(state)
	_moonlight(ci, boss_box)
	TankEnemyDraw.draw_light(ci, kit, TankIds.BOSS_ID, boss_foot, pose)
	var b := state.boss
	for i in mini(b.bogie_hp.size(), BOGIE_U.size()):
		if b.bogie_hp[i] > 0.0 and b.phase != TankIds.BOSS_DEAD:
			continue
		var at := boss_part_at(i) - Vector2(0, BOGIE_FLAME_UP)
		TankEnemyDraw.burn(ci, kit, TankIds.BOSS_ID, at, BOGIE_FLAME, v.time, float(i) * 3.7)
	if b.telegraph_s > 0.0:
		_telegraph(ci, TankEnemyDraw.bore(kit, TankIds.BOSS_ID, boss_foot, pose), 1.6)


func _wreck_fire(ci: CanvasItem, w: Dictionary, t: float) -> void:
	var k := wreck_fire(w, t)
	var c := _wreck_hatch(w)
	if k <= 0.0:
		if t - float(w["t"]) < TankView.WRECK_BURN_S * 2.0:
			TankDraw.glow_at(ci, c, 3.0, Color(1.0, 0.35, 0.1, 0.35))
		return
	TankEnemyDraw.draw_light(ci, kit, str(w["kind"]), _wreck_foot(w), _wreck_pose(w, 1.0 - k))


func _shells(ci: CanvasItem, state: TankState) -> void:
	for s in shells_drawn(state):
		var at: Vector2 = s["at"]
		var col := SHELL_OURS if bool(s["friendly"]) else SHELL_THEIRS
		ci.draw_line(s["from"], at, Color(col, 0.4), 2.0)
		TankDraw.glow_at(ci, at, 5.0, Color(col, 0.6))
		ci.draw_rect(Rect2(at.round(), Vector2.ONE), Color(1, 0.95, 0.8, 0.95))


## The tow's black over the whole panel, with a lost signal's rows of noise.
func _draw_veil() -> void:
	if veil <= 0.0:
		return
	var top := -_y_off - OVERDRAW
	var h := float(size.y) + OVERDRAW * 2.0
	var ci := _veil
	ci.draw_rect(Rect2(-OVERDRAW, top, far_w + OVERDRAW * 2.0, h), Color(0, 0, 0, veil * VEIL_DEEP))
	var frame_n := floorf(v.time * VEIL_NOISE_HZ)
	for i in VEIL_ROWS:
		var a := TankDraw.hash01(frame_n * 0.37 + float(i) * 2.1)
		var b := TankDraw.hash01(frame_n * 0.71 + float(i) * 5.3)
		var y := roundf(top + a * h)
		var c := Color(VEIL_NOISE, VEIL_NOISE_A * b * veil)
		ci.draw_rect(Rect2(-OVERDRAW, y, far_w + OVERDRAW * 2.0, 1.0 + roundf(b)), c)
