class_name TankWorldDraw
extends RefCounted
## The world on the road (docs/games/tank.md v3 "World", 3.5), drawn by TankView's World layer in
## stage px (the planes and the road band are TankForest's): free roam's little bases, the tank's contact
## shadow under its track run, the halt line (concrete teeth, a post with a hooded amber lamp), the
## roadside bushes, obstacles (wire, hulks, tank traps), wrecks aging on sim time from a burning hulk
## into a debris heap, the near threats in their two lanes, on the relief (TankEnemyDraw fits them).
## Far enemies, the Behemoth and a stage's little base stand in the far panel (TankFarPanel). Free roam:
## the turning places at the road's ends; the turn's dust cloud. No people.

const LANE_DIM: Array[float] = [1.0, 0.86]
## How much night haze each lane carries.
const LANE_FOG: Array[float] = [0.0, 0.1]
## Roadside bushes (SPEC_TANK 4.7): one every 90-160 rules px of road, on the verge (stage y above the road).
const BUSH_PITCH := 125.0
const BUSH_JITTER := 35.0
const BUSH_VERGE := 12.0
## A wreck's hulk sits this far into its lane's ground; the fire through its hatch.
const WRECK_SINK := 2.0
const FIRE := Color(1.0, 0.55, 0.18)
const FIRE_HI := Color(1.0, 0.85, 0.45)
const CONCRETE := Color(0.2, 0.195, 0.18)
const CONCRETE_DK := Color(0.1, 0.1, 0.095)
const CONCRETE_HI := Color(0.3, 0.28, 0.25)
const CONCRETE_TOP := Color(0.38, 0.36, 0.32)
const IRON := Color(0.15, 0.13, 0.11)
const IRON_HI := Color(0.3, 0.26, 0.21)
const AMBER := Color(1.0, 0.68, 0.3)
const WOOD := Color(0.24, 0.18, 0.12)
const WIRE := Color(0.42, 0.42, 0.4)
## Free roam: the turning place's barrier and the start of its gravel loop, metres inside the road's end.
const TURN_BARRIER_M := 15.0
const TURN_LOOP_M := 70.0
const GRAVEL := Color(0.2, 0.18, 0.15)
const GRAVEL_DK := Color(0.12, 0.11, 0.09)


static func draw_world(ci: CanvasItem, v: TankView, state: TankState) -> void:
	for bx in TankForest.bases(v, state):
		TankForest.draw_base(ci, v, bx)
	_tank_contact(ci, v)
	if state.roam.active and state.roam_map != null:
		_turning_places(ci, v, state)
	_bushes(ci, v)
	_halt_line(ci, v, state)
	for ob in state.obstacles:
		_obstacle(ci, v, ob)
	# The back lane first, each lane's wrecks before its live near threats.
	for want in [1, 0]:
		for w in v.wrecks:
			if clampi(int(w.get("lane", 0)), 0, TankView.LANES - 1) == want:
				_wreck(ci, v, w)
		for e in state.enemies:
			if v.lanes.has(e.id) and int(v.lanes[e.id]) == want:
				_enemy(ci, v, e)


## The tank's contact with the road: a dark shadow along the track run under the road wheels'
## contacts, soft at its ends.
static func _tank_contact(ci: CanvasItem, v: TankView) -> void:
	var n := v.wheel_centres.size()
	if n == 0:
		return
	var a := v.wheel_contact(0) + Vector2(-26, 0)
	var b := v.wheel_contact(n - 1) + Vector2(40, 0)
	var rows: Array[float] = [0.7, 0.55, 0.32, 0.16]
	var steps := maxi(int((b.x - a.x) / 4.0), 1)
	for k in rows.size():
		for i in steps:
			var u := float(i) / float(steps)
			var x := lerpf(a.x, b.x, u)
			var y := roundf(v.ground_y(x + 2.0)) - 1.0 + float(k)
			var edge := clampf(minf(u, 1.0 - u) * 8.0, 0.0, 1.0)
			ci.draw_rect(
				Rect2(Vector2(roundf(x), y), Vector2(4, 1)),
				Color(0.02, 0.018, 0.015, rows[k] * edge)
			)


# --- Bushes --------------------------------------------------------------------------------


## Bush `n`'s world x (rules px): every BUSH_PITCH along the road, moved by its hash, so the gaps stay
## within 90-160.
static func bush_x(n: int) -> float:
	return BUSH_PITCH * float(n) + (TankDraw.hash01(float(n) * 0.77) - 0.5) * BUSH_JITTER


## The bushes on the near panel this frame: [{x (stage), n}], from behind the tank's rear to past the seam.
static func bushes_at(v: TankView) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var end := TankFarMap.near_end_x(v.canvas.x) + 60.0
	var n := floori((v.cam_x - BUSH_PITCH) / BUSH_PITCH)
	var x := v.sx(bush_x(n))
	while x < end:
		out.append({"x": x, "n": n})
		n += 1
		x = v.sx(bush_x(n))
	return out


## The roadside bushes (the kit's sprites; none until its art), on the verge behind the road, picked and
## flipped by hash. The near threats burst out past them.
static func _bushes(ci: CanvasItem, v: TankView) -> void:
	var tex := v.enemy_kit.bushes()
	var rects := v.enemy_kit.bush_rects()
	if tex == null or rects.is_empty():
		return
	for b in bushes_at(v):
		var n := int(b["n"])
		var h := TankDraw.hash01(float(n) * 1.91 + 3.0)
		var src := rects[mini(int(h * float(rects.size())), rects.size() - 1)]
		var x := roundf(float(b["x"]))
		var foot := roundf(v.ground_y(x)) - BUSH_VERGE
		var at := Vector2(x - roundf(src.size.x * 0.5), foot - src.size.y)
		var dst := Rect2(at, src.size)
		if posmod(n, 2) == 1:
			dst = Rect2(at, Vector2(-src.size.x, src.size.y))
		ci.draw_texture_rect_region(tex, dst, src)


# --- Enemies, wrecks ------------------------------------------------------------------------


## A near threat: TankEnemyDraw at its foot in its pose, a shadow under it, a small bar once it is hurt.
static func _enemy(ci: CanvasItem, v: TankView, e: TankEnemyState) -> void:
	var r: Rect2 = v.enemy_rects[e.id]
	var foot: Vector2 = v.enemy_feet[e.id]
	contact_shadow(ci, Vector2(r.position.x + 3.0, foot.y), r.size.x - 6.0)
	TankEnemyDraw.draw(ci, v.enemy_kit, v.enemy_kind(e), foot, v.near_pose(e))
	if e.hp_max > 0.0 and e.hp < e.hp_max:
		var bw := roundf(r.size.x * 0.4)
		var bp := Vector2(roundf(r.position.x + r.size.x * 0.3), r.position.y - 5.0)
		ci.draw_rect(Rect2(bp, Vector2(bw, 2)), Color(0, 0, 0, 0.5))
		var fill := roundf(bw * clampf(e.hp / e.hp_max, 0.0, 1.0))
		ci.draw_rect(Rect2(bp, Vector2(fill, 2)), Color(0.78, 0.3, 0.2, 0.75))


## How bright a lane's sprites are (1 the front lane, darker further back).
static func lane_dim(lane: int) -> float:
	return LANE_DIM[clampi(lane, 0, LANE_DIM.size() - 1)]


static func lane_fog(lane: int) -> float:
	return LANE_FOG[clampi(lane, 0, LANE_FOG.size() - 1)]


## A soft dark shadow `w` px long starting at `p` (its left end on the ground line).
static func contact_shadow(ci: CanvasItem, p: Vector2, w: float) -> void:
	var rows: Array[float] = [0.65, 0.45, 0.22]
	for k in rows.size():
		var inset := float(k) * 4.0 + 3.0
		var y := p.y - 1.0 + float(k)
		var col := Color(0.02, 0.018, 0.015, rows[k])
		var half := Color(col.r, col.g, col.b, rows[k] * 0.5)
		ci.draw_rect(Rect2(Vector2(p.x + inset, y), Vector2(maxf(w - inset * 2.0, 1.0), 1)), col)
		ci.draw_rect(Rect2(Vector2(p.x + inset - 3.0, y), Vector2(3, 1)), half)
		ci.draw_rect(Rect2(Vector2(p.x + w - inset, y), Vector2(3, 1)), half)


## The wreck's footprint (stage px): the hulk's sprite rect in its lane (a little sunk into the
## lane's ground), and the heap's.
static func wreck_rect(v: TankView, w: Dictionary) -> Rect2:
	var r := v.lane_rect(str(w["kind"]), v.sx(float(w["x"])), int(w.get("lane", 0)))
	return Rect2(r.position + Vector2(0, WRECK_SINK), r.size)


static func heap_rect(v: TankView, w: Dictionary) -> Rect2:
	var r := wreck_rect(v, w)
	var wd := roundf(r.size.x * 0.55)
	return Rect2(Vector2(roundf(r.get_center().x - wd * 0.5), r.end.y - 6.0), Vector2(wd, 6.0))


## Where a wreck's fire shows through its open hatch (stage px): its roof, a third from its gun end.
static func wreck_hatch(v: TankView, w: Dictionary) -> Vector2:
	var r := wreck_rect(v, w)
	var sink := roundf(v.wreck_collapse(w) * r.size.y * 0.7)
	return Vector2(
		roundf(r.position.x + r.size.x * 0.62), r.position.y + sink + roundf(r.size.y * 0.3)
	)


## A wreck (brief 3.5): the kit's charred hulk, fire flickering through its open hatch, sinking into a
## debris heap as it collapses, a shadow under it. The beams light it (TankLightDraw).
static func _wreck(ci: CanvasItem, v: TankView, w: Dictionary) -> void:
	var r := wreck_rect(v, w)
	if r.position.x > v.canvas.x + 10.0 or r.end.x < -10.0:
		return
	contact_shadow(ci, Vector2(r.position.x + 3.0, r.end.y - WRECK_SINK), r.size.x - 6.0)
	var collapse := v.wreck_collapse(w)
	if collapse < 1.0:
		_hulk(ci, v, w, r, collapse)
		var fire := v.wreck_fire(w)
		if fire > 0.0:
			var hp := wreck_hatch(v, w)
			var f := posmod(int(floorf(v.time * 9.0 + float(w["x"]))), 3)
			var fh := roundf((3.0 + float(f)) * fire * (1.0 - collapse * 0.6))
			for i in 3:
				var hh := maxf(fh - float(absi(i - 1)) * 2.0, 1.0)
				var fx := hp.x - 1.0 + float(i)
				ci.draw_rect(Rect2(Vector2(fx, hp.y - hh), Vector2(1, hh)), FIRE)
				ci.draw_rect(Rect2(Vector2(fx, hp.y - 1.0), Vector2(1, 1)), FIRE_HI)
	# The debris heap: a low charred mound, a bit of track and a barrel sticking out.
	var h := heap_rect(v, w)
	var ha := clampf(collapse * 1.5, 0.0, 1.0)
	if ha <= 0.0:
		return
	var n := int(h.size.x)
	var seed_v := float(w["x"])
	for i in n:
		var u := float(i) / maxf(h.size.x - 1.0, 1.0)
		var bump := 0.6 + 0.4 * TankDraw.hash01(seed_v + i * 1.7)
		var hgt := roundf((1.0 - pow(u * 2.0 - 1.0, 2.0)) * h.size.y * bump)
		if hgt < 1.0:
			continue
		var col := Color(0.09, 0.07, 0.06, ha) if i % 3 else Color(0.2, 0.14, 0.1, ha)
		ci.draw_rect(Rect2(Vector2(h.position.x + i, h.end.y - hgt), Vector2(1, hgt)), col)
	ci.draw_rect(
		Rect2(h.position + Vector2(h.size.x * 0.2, h.size.y - 2.0), Vector2(h.size.x * 0.6, 1)),
		Color(0.25, 0.2, 0.15, ha)
	)
	ci.draw_line(
		h.get_center() + Vector2(-2, -1),
		h.get_center() + Vector2(-10, -6),
		Color(0.14, 0.11, 0.09, ha),
		1.0
	)


## The hulk, its bottom sunk away as it collapses; the kit's stub box until its art, gone half way down.
static func _hulk(ci: CanvasItem, v: TankView, w: Dictionary, r: Rect2, collapse: float) -> void:
	var kind := str(w["kind"])
	var row := v.enemy_kit.kind(kind)
	var tex := v.enemy_kit.texture()
	var dim := lane_dim(int(w.get("lane", 0)))
	var tone := Color(dim, dim, dim)
	if tex != null and row.has("wreck"):
		var src: Rect2 = row["wreck"]
		var sink := roundf(collapse * r.size.y * 0.7)
		var keep := 1.0 - sink / r.size.y
		var dst := Rect2(r.position + Vector2(0, sink), Vector2(r.size.x, r.size.y - sink))
		ci.draw_texture_rect_region(
			tex, dst, Rect2(src.position, src.size * Vector2(1, keep)), tone
		)
	elif collapse < 0.5:
		var foot := Vector2(r.get_center().x, r.end.y)
		TankEnemyDraw.draw(ci, v.enemy_kit, kind, foot, {"wrecked": true, "dim": 1.0 - dim})


# --- The halt line, obstacles, the depot -------------------------------------------------------------------


## The halt line's world x in an Advance (where the hull's front is when its rear reaches the end of
## the road), or NAN elsewhere.
static func halt_x(state: TankState) -> float:
	if state.seg.seg != TankIds.SEG_ADVANCE or state.content == null:
		return NAN
	var length_m := float(state.content.segment(state.seg.phase_index).get("length_m", 0.0))
	if length_m <= 0.0:
		return NAN
	return TankConst.m_to_px(length_m) + float(state.hull.hull_w)


## The halt line: three concrete dragon's teeth across the road (far to near, each lower and
## larger) and a post with a hooded amber lamp (its light is the light layer's).
static func _halt_line(ci: CanvasItem, v: TankView, state: TankState) -> void:
	var hx := halt_x(state)
	if is_nan(hx):
		return
	var x := roundf(v.sx(hx))
	if x < -60.0 or x > v.canvas.x + 60.0:
		return
	var g := roundf(v.ground_y(x + 20.0))
	for t: Vector3 in [Vector3(18, -6, 13), Vector3(39, -3, 16), Vector3(8, 2, 19)]:
		tooth(ci, Vector2(x + t.x, g + t.y), t.z)
	var post := Rect2(Vector2(x, g - 36.0), Vector2(3, 36))
	ci.draw_rect(post, IRON)
	ci.draw_rect(Rect2(post.position, Vector2(1, post.size.y)), IRON_HI)
	var hood := post.position + Vector2(-4, -4)
	ci.draw_rect(Rect2(hood, Vector2(11, 4)), Color(0.08, 0.07, 0.06))
	ci.draw_rect(Rect2(hood, Vector2(11, 1)), IRON_HI)
	ci.draw_rect(Rect2(hood + Vector2(3, 4), Vector2(5, 1)), AMBER)


## Where the halt line's lamp hangs (stage px), or NAN.x when no halt line shows.
static func halt_lamp(v: TankView, state: TankState) -> Vector2:
	var hx := halt_x(state)
	if is_nan(hx):
		return Vector2(NAN, NAN)
	var x := roundf(v.sx(hx))
	return Vector2(x + 1.5, roundf(v.ground_y(x + 20.0)) - 35.0)


## One concrete tooth (a blunt pyramid seen from the side) on `foot`, `s` px tall: the face toward
## the tank lit (the headlight comes from the left), the far face in shadow, a pale flat top, a
## shadow cast along the ground away from the light and a few chips in the lit face.
static func tooth(ci: CanvasItem, foot: Vector2, s: float) -> void:
	foot = foot.round()
	var half := roundf(s * 0.6)
	var cap := maxf(roundf(s * 0.16), 1.0)
	var top := foot + Vector2(-roundf(s * 0.06), -roundf(s))
	var mid := foot + Vector2(roundf(s * 0.12), 0)
	ci.draw_polygon(
		PackedVector2Array([mid, top + Vector2(cap, 0), foot + Vector2(half, 0)]),
		PackedColorArray([CONCRETE_DK])
	)
	ci.draw_polygon(
		PackedVector2Array(
			[foot + Vector2(-half, 0), top + Vector2(-cap, 0), top + Vector2(cap, 0), mid]
		),
		PackedColorArray([CONCRETE])
	)
	ci.draw_line(foot + Vector2(-half, -1.0), top + Vector2(-cap, 0), CONCRETE_HI, 1.0)
	ci.draw_rect(Rect2(top + Vector2(-cap, -1.0), Vector2(cap * 2.0 + 1.0, 1)), CONCRETE_TOP)
	ci.draw_rect(
		Rect2(foot + Vector2(-half, 0), Vector2(half * 2.0 + 5.0, 1)), Color(0.03, 0.025, 0.02, 0.8)
	)
	ci.draw_rect(Rect2(foot + Vector2(half, -1.0), Vector2(4, 1)), Color(0.03, 0.025, 0.02, 0.45))
	for i in 3:
		var h := TankDraw.hash01(foot.x * 0.71 + float(i) * 4.3)
		var c := foot + Vector2(-half * 0.55 + h * half * 0.6, -roundf(s * (0.2 + 0.5 * h)))
		ci.draw_rect(Rect2(c.round(), Vector2(1, 1)), CONCRETE_DK)
		ci.draw_rect(Rect2(c.round() + Vector2(1, 0), Vector2(1, 1)), CONCRETE_HI.darkened(0.15))


static func _obstacle(ci: CanvasItem, v: TankView, ob: TankObstacleState) -> void:
	if ob.cleared:
		return
	var x0 := v.sx(ob.x_px)
	var x1 := v.sx(ob.x_px + float(ob.w))
	if x1 < -20.0 or x0 > v.canvas.x + 20.0:
		return
	var g := roundf(v.ground_y((x0 + x1) * 0.5))
	match TankIds.obstacle_of(ob.code):
		TankIds.OBST_WIRE:
			# Wooden trestles with barbed wire strung between them.
			var n := maxi(int((x1 - x0) / 22.0), 2)
			for i in n + 1:
				var px := roundf(lerpf(x0, x1, float(i) / n))
				ci.draw_line(Vector2(px - 5, g), Vector2(px + 5, g - 14), WOOD, 1.0)
				ci.draw_line(Vector2(px + 5, g), Vector2(px - 5, g - 14), WOOD, 1.0)
			for k in 3:
				var y := g - 4.0 - k * 4.0
				var xx := x0
				while xx < x1:
					TankDraw.px(ci, Vector2(xx, y + (1.0 if int(xx) % 5 == 0 else 0.0)), WIRE)
					xx += 1.0
		TankIds.OBST_TANK_TRAPS:
			var m := maxi(int((x1 - x0) / 20.0), 1)
			for i2 in m:
				tooth(
					ci,
					Vector2(roundf(lerpf(x0, x1, (i2 + 0.5) / m)), g + float(i2 % 2) * 2.0),
					14.0
				)
		_:
			# A burnt-out hulk across the road (a wreck, the drill's targets).
			var foot := Vector2(roundf((x0 + x1) * 0.5), TankView.ROAD_ENEMY_Y)
			var sz: Vector2 = v.enemy_kit.kind(TankIds.ENEMY_MEDIUM)["size"]
			contact_shadow(ci, foot - Vector2(sz.x * 0.5 - 3.0, 0.0), sz.x - 6.0)
			TankEnemyDraw.draw(
				ci, v.enemy_kit, TankIds.ENEMY_MEDIUM, foot, {"wrecked": true, "dim": 0.25}
			)


# --- Free roam ---------------------------------------------------------------------------------------------


## The turning places at the road's ends (brief 2.10): a widened gravel loop on the road, churned
## track marks, a timber barrier with hatched boards (no text) and a hooded amber lamp on a post.
static func _turning_places(ci: CanvasItem, v: TankView, state: TankState) -> void:
	var map := state.roam_map
	for end in [-1, 1]:
		var at := map.length_m if end > 0 else 0.0
		var barrier_m := at - float(end) * TURN_BARRIER_M
		var bx := roundf(v.sx(v.travel_x(state, barrier_m)))
		var lx := v.sx(v.travel_x(state, at - float(end) * TURN_LOOP_M))
		var x0 := minf(lx, bx)
		var x1 := maxf(lx, bx)
		if x1 < -80.0 or x0 > v.canvas.x + 80.0:
			continue
		var g := roundf(v.ground_y(bx))
		for i in int(x1 - x0):
			var x := x0 + float(i)
			var h := TankDraw.hash01(x * 0.37 + float(end) * 11.0)
			ci.draw_rect(
				Rect2(Vector2(x, g - 3.0 + roundf(h * 2.0)), Vector2(1, 3)),
				GRAVEL.lerp(GRAVEL_DK, h)
			)
		for k in 3:
			var y := g - 1.0 + float(k) * 2.0
			ci.draw_line(
				Vector2(x0 + 8.0, y), Vector2(x1 - 8.0, y + 1.0), Color(0.06, 0.05, 0.04, 0.8), 1.0
			)
		var dir := -float(end) if not v.mirrored else float(end)
		_barrier(ci, bx, g, dir)
		var post := Vector2(bx - 26.0 * float(end) * (-1.0 if v.mirrored else 1.0), g)
		ci.draw_rect(Rect2(post + Vector2(0, -46), Vector2(2, 46)), IRON)
		ci.draw_rect(Rect2(post + Vector2(-4, -49), Vector2(10, 3)), Color(0.08, 0.07, 0.06))
		ci.draw_rect(Rect2(post + Vector2(-2, -46), Vector2(6, 1)), AMBER)


## A timber barrier across the road: two posts, two hatched boards, stones at its foot.
static func _barrier(ci: CanvasItem, x: float, g: float, _dir: float) -> void:
	for px: float in [x - 14.0, x + 12.0]:
		ci.draw_rect(Rect2(Vector2(px, g - 26.0), Vector2(3, 26)), WOOD)
		ci.draw_rect(Rect2(Vector2(px, g - 26.0), Vector2(1, 26)), Color(0.32, 0.24, 0.16))
	for by: float in [g - 22.0, g - 13.0]:
		ci.draw_rect(Rect2(Vector2(x - 18.0, by), Vector2(36, 5)), Color(0.2, 0.15, 0.1))
		var k := 0
		while k < 36:
			ci.draw_rect(
				Rect2(Vector2(x - 18.0 + k, by), Vector2(3, 5)), Color(0.42, 0.33, 0.2, 0.55)
			)
			k += 7
		ci.draw_rect(Rect2(Vector2(x - 18.0, by), Vector2(36, 1)), Color(0.36, 0.28, 0.18))
	for sx: float in [-20.0, -9.0, 4.0, 17.0]:
		ci.draw_rect(Rect2(Vector2(x + sx, g - 3.0), Vector2(6, 3)), CONCRETE)


## Where the turning places' lamps hang (stage px) this frame (the light layer lights them).
static func turn_lamps(v: TankView, state: TankState) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if not state.roam.active or state.roam_map == null:
		return out
	for end in [-1, 1]:
		var at := state.roam_map.length_m if end > 0 else 0.0
		var bx := roundf(v.sx(v.travel_x(state, at - float(end) * TURN_BARRIER_M)))
		var px := bx - 26.0 * float(end) * (-1.0 if v.mirrored else 1.0)
		if px > -40.0 and px < v.canvas.x + 40.0:
			out.append(Vector2(px + 1.0, roundf(v.ground_y(bx)) - 45.0))
	return out


## The turn's dust cloud (brief 2.10), drawn on the tank layer so the lamps and the headlight glow
## through it: billows churned up from the tracks, thick over the running gear (about the hull's
## lower 40 %), a thin haze above (alpha at most 0.35, a little more at the very flip), each billow
## swelling and fading over about 1.5 s.
static func draw_turn_dust(ci: CanvasItem, v: TankView, state: TankState) -> void:
	var k := v.turn_dust(state)
	if k <= 0.0:
		return
	var size := v.rig.size
	var o := v.tank_pos
	var ground := o.y + v.rig.ground
	var gear_top := ground - size.y * 0.4
	var half := 0.5 * (state.content.num("valley", "turn.stop_s", 8.0) if state.content else 8.0)
	var peak := clampf(1.0 - absf(state.roam.turn_s - half) / 0.6, 0.0, 1.0)
	var haze := minf(0.2 * k + 0.15 * peak, 0.35)
	TankDraw.soft_at(
		ci, Vector2(o.x + size.x * 0.5, gear_top + 14.0), size.x * 0.55, Color(0.3, 0.26, 0.2, haze)
	)
	# A skirt of dust along the tracks, then billows rolling up from them.
	for j in 9:
		var sx := o.x + size.x * (0.08 + 0.1 * float(j))
		var wob := sin(v.time * 1.3 + float(j)) * 4.0
		TankDraw.soft_at(
			ci, Vector2(sx + wob, ground - 6.0), 30.0, Color(0.42, 0.36, 0.28, 0.5 * k)
		)
	for i in 34:
		var h := TankDraw.hash01(float(i) * 7.13)
		var h2 := TankDraw.hash01(float(i) * 3.71 + 1.0)
		var life := fposmod(v.time / 1.5 + h, 1.0)
		var x := o.x + size.x * (0.04 + 0.92 * h) - life * 14.0
		var y := ground - 6.0 - (ground - gear_top) * (0.15 + 0.7 * h2) * (0.5 + 0.5 * life)
		var r := (14.0 + 16.0 * h2) * (0.6 + 0.6 * life)
		var a := 0.55 * k * sin(life * PI)
		var c := Color(0.48, 0.41, 0.32).lerp(Color(0.34, 0.29, 0.23), h)
		TankDraw.soft_at(ci, Vector2(x, y), r, Color(c.r, c.g, c.b, a))
