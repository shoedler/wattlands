class_name TankFarPanel
extends SubViewport
## v4: the far panel (SPEC_TANK 4.2, 4.3): a long-lens view of the enemy, in its own SubViewport so it never
## runs the depth of field. `Back` is the same night forest at a third of the near panel's parallax and
## lower (a long lens sees less sky), over the ground band; `World` a stage's little base (TankForest.far_base),
## the wrecks, the far enemies by lane back to front and the Behemoth; `Light` (additive) the base's lamps, slit
## glows, telegraph pulses, the searchlight's cold pool on the target, fires, shells and impact flashes from
## the panel's own TankFx; `Veil` the black a tow fades it to, with rows of noise. TankView draws its texture over
## the near stage.
##
## Frames: "panel" px have x from the near-side edge (TankFarMap.range_x) and y on the stage (the road line at
## TankView.GROUND); World and Light mirror about the panel when the tank drives west, Back never does.
## canvas_rect() and canvas_point() turn panel px into canvas px for the HUD and the view.

const PLANE_PARALLAX := 0.3
const PLANE_DROP := 40.0
## The ground band's top (stage y): above the feet of the rearmost lane at the far end (338).
const GROUND_TOP := 326.0
const GROUND_H := 170.0
const GROUND_EARTH := Color(0.062, 0.07, 0.058)
const GROUND_DARK := Color(0.03, 0.036, 0.032)
const GROUND_LIP := Color(0.1, 0.12, 0.09)
const SHADE_TOP := Color(0, 0, 0, 0.3)
const SHADE_BOTTOM := Color(0, 0, 0, 0.5)
const SHADE_TOP_END := 215.0
const SHADE_BOTTOM_START := 400.0
const OVERDRAW := 4.0
## A sprite's haze across the field; the night it comes out of over the first third of its entry.
const HAZE_NEAR := 0.12
const HAZE_SPAN := 0.38
const ENTER_S := 10.0
## How far back each lane dims.
const LANE_DIM := 0.08
## Tracks: art px per metre of range change, and per metre the hull drives (they pace us).
const TRAVEL_PER_M := 1.0
const TRAVEL_PACE := 6.0
const RECOIL_PX := 4.0
const RECOIL_DECAY := 2.5
const TELEGRAPH_PULSE := 30.0
## The veil of a shooter in its telegraph: a pulse the plates still show through (at 0.25 + 0.25 sin, the
## first number, TankEnemyDraw's veil made it a pale ghost for the whole telegraph). The muzzle's glow warns.
const TELEGRAPH_FLASH := 0.07
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
const SHAKE_DECAY := 3.0
const SHAKE_PX := 2.0
const SEARCH_POOL_R := 40.0
const BOGIE_U: Array[float] = [0.2, 0.5, 0.8]
const BOGIE_V := 0.85
const TURRET_AT := Vector2(0.55, 0.3)
## The tow's black: its fade in (s), the noise rows, their refresh (Hz) and their strongest alpha.
const VEIL_IN_S := 1.0
const VEIL_ROWS := 16
const VEIL_NOISE_HZ := 12.0
const VEIL_NOISE := Color(0.32, 0.36, 0.34)
const VEIL_NOISE_A := 0.16

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
var _world: Node2D = null
var _light: Node2D = null
var _veil: Node2D = null
var _mirrored: bool = false
var _y_off: float = 0.0
## Enemy id -> {t0, travel, recoil, last, kind, lane, range}; _boss the same for the Behemoth.
var _seen: Dictionary = {}
var _boss: Dictionary = {}
var _smoke_acc: float = 0.0


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
	_world = _layer("World")
	_light = _layer("Light")
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_light.material = add
	_light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_veil = _layer("Veil")
	_back.draw.connect(_draw_back)
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
	for l: Node2D in [_world, _light]:
		l.scale = Vector2(-1, 1) if mirrored else Vector2.ONE
		l.position = Vector2(far_w, 0) if mirrored else Vector2.ZERO


# --- Mapping ------------------------------------------------------------------------------------------


## A sprite's foot x: the range's x, held whole inside the panel (a wider sprite centred).
static func foot_x(range_m: float, half_w: float, panel_w: float) -> float:
	var x := TankFarMap.range_x(range_m, panel_w)
	if half_w * 2.0 >= panel_w:
		return roundf(panel_w * 0.5)
	return roundf(clampf(x, half_w + 1.0, panel_w - half_w - 1.0))


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
	for l: Node2D in [_back, _world, _light, _veil]:
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
	for e in state.enemies:
		if e.is_near() or e.mode == TankIds.EM_DEAD:
			continue
		alive[e.id] = true
		var rng := v.far_range_of(e)
		var kind := TankIds.enemy_of(e.code)
		var fresh := not _seen.has(e.id)
		var rec := _record(e.id, kind, e.lane, rng, state)
		_advance_rec(rec, rng, state, dt)
		var half := float(kit.kind(kind)["size"].x) * 0.5
		var foot := Vector2(foot_x(rng, half, far_w), TankFarMap.foot_y(rng, e.lane))
		feet[e.id] = foot
		rects[e.id] = _rect_of(kind, foot)
		if fresh and e.mode == TankIds.EM_ENTER:
			_dust(foot, half)
	for id: int in _seen.keys():
		if not alive.has(id):
			_seen.erase(id)


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
	boss_foot = Vector2(foot_x(rng, half, far_w), TankFarMap.foot_y(rng, 0))
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
		LANE_DIM * float(clampi(e.lane, 0, 3)),
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
			var lane := _target_lane(state)
			var to := Vector2(TankFarMap.range_x(land, far_w), TankFarMap.foot_y(land, lane) - 6.0)
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


func _target_lane(state: TankState) -> int:
	var e := state.enemy(state.hull.target_id)
	return e.lane if e != null else 0


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
	ci.draw_rect(Rect2(-OVERDRAW, top, w, bottom - top), TankForest.SKY)
	var tint := TankForest.forest_tint(v, v.game.state)
	for p in v.rig.planes:
		if str(p["layer"]) == "back":
			_plane(ci, p, tint if str(p["name"]) in ["forest", "ridge"] else Color.WHITE)
	_ground(ci, bottom)
	var clear := Color(0, 0, 0, 0)
	_band(ci, top, SHADE_TOP_END, SHADE_TOP, clear)
	_band(ci, SHADE_BOTTOM_START, bottom, clear, SHADE_BOTTOM)


func _ready_to_draw() -> bool:
	return v.game != null and v.game.state != null and v.rig != null


func _plane(ci: CanvasItem, p: Dictionary, mod: Color) -> void:
	var w: float = p["w"]
	var x := -fposmod(v.plane_x * TankView.S * float(p["parallax"]) * PLANE_PARALLAX, w) - w
	var tex: Texture2D = p["tex"]
	while x < far_w + OVERDRAW:
		ci.draw_texture(tex, Vector2(roundf(x), float(p["y0"]) + PLANE_DROP), mod)
		x += w


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


func _draw_world() -> void:
	if v == null or not _ready_to_draw():
		return
	var state := v.game.state
	var ci := _world
	var bx := TankForest.far_base(v, state)
	if not is_nan(bx):
		TankForest.draw_base(ci, v, bx)
	if boss_box.size != Vector2.ZERO:
		TankEnemyDraw.draw(ci, kit, TankIds.BOSS_ID, boss_foot, boss_pose(state))
	for lane in [3, 2, 1, 0]:
		for w in wrecks:
			if clampi(int(w["lane"]), 0, 3) == lane:
				_wreck(ci, w)
		for e in state.enemies:
			if feet.has(e.id) and clampi(e.lane, 0, 3) == lane:
				_enemy(ci, e)
	fx.draw_solid(ci)
	fx.draw_smoke(ci)


func _enemy(ci: CanvasItem, e: TankEnemyState) -> void:
	var foot: Vector2 = feet[e.id]
	var r: Rect2 = rects[e.id]
	TankEnemyDraw.draw(ci, kit, TankIds.enemy_of(e.code), foot, pose_of(e, foot))
	if e.hp_max > 0.0 and e.hp < e.hp_max:
		var bw := roundf(r.size.x * 0.4)
		var bp := Vector2(roundf(r.position.x + r.size.x * 0.3), r.position.y - 5.0)
		ci.draw_rect(Rect2(bp, Vector2(bw, 2)), Color(0, 0, 0, 0.5))
		var fill := roundf(bw * clampf(e.hp / e.hp_max, 0.0, 1.0))
		ci.draw_rect(Rect2(bp, Vector2(fill, 2)), Color(0.78, 0.3, 0.2, 0.75))


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
	var bx := TankForest.far_base(v, state)
	if not is_nan(bx):
		TankForest.draw_base_light(ci, v, bx)
	_search_pool(ci, state)
	for e in state.enemies:
		if not feet.has(e.id):
			continue
		var foot: Vector2 = feet[e.id]
		var pose := pose_of(e, foot)
		TankEnemyDraw.draw_light(ci, kit, TankIds.enemy_of(e.code), foot, pose)
		if e.telegraph_s > 0.0:
			_telegraph(ci, muzzle_of(e), 12.0)
	_boss_light(ci, state)
	for w in wrecks:
		_wreck_fire(ci, w, state.t)
	_shells(ci, state)
	fx.draw_light(ci)
	if fx.wash > 0.0:
		var c := fx.wash_color
		TankDraw.glow_at(ci, fx.wash_pos, 160.0, Color(c.r, c.g, c.b, 0.16 * fx.wash))


func _telegraph(ci: CanvasItem, at: Vector2, r: float) -> void:
	TankDraw.glow_at(ci, at, r, Color(1.0, 0.4, 0.15, 0.6))
	TankDraw.glow_at(ci, at, r * 0.3, Color(1.0, 0.8, 0.5, 0.8))


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
	TankEnemyDraw.draw_light(ci, kit, TankIds.BOSS_ID, boss_foot, pose)
	var b := state.boss
	for i in mini(b.bogie_hp.size(), BOGIE_U.size()):
		if b.bogie_hp[i] > 0.0 and b.phase != TankIds.BOSS_DEAD:
			continue
		var at := boss_part_at(i)
		var fl := 0.7 + 0.3 * sin(v.time * 8.0 + i * 2.0) * sin(v.time * 4.7 + i)
		TankDraw.glow_at(ci, at, 22.0, Color(FIRE, 0.5 * fl))
		TankDraw.glow_at(ci, at + Vector2(0, -4), 7.0, Color(FIRE_CORE, 0.8 * fl))
	if b.telegraph_s > 0.0:
		_telegraph(ci, boss_muzzle(state), 22.0)


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
	ci.draw_rect(Rect2(-OVERDRAW, top, far_w + OVERDRAW * 2.0, h), Color(0, 0, 0, veil))
	var frame_n := floorf(v.time * VEIL_NOISE_HZ)
	for i in VEIL_ROWS:
		var a := TankDraw.hash01(frame_n * 0.37 + float(i) * 2.1)
		var b := TankDraw.hash01(frame_n * 0.71 + float(i) * 5.3)
		var y := roundf(top + a * h)
		var c := Color(VEIL_NOISE, VEIL_NOISE_A * b * veil)
		ci.draw_rect(Rect2(-OVERDRAW, y, far_w + OVERDRAW * 2.0, 1.0 + roundf(b)), c)
