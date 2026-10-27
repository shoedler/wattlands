class_name TankWorldDraw
extends RefCounted
## The world around the tank (docs/games/tank.md 3.1, 3.5), drawn by TankView's layers in stage px:
## the planes with their parallax (far, forest and road behind the tank; the dark foreground in
## front), the depot's yard lamps and drums, the halt line (concrete teeth, a post with a hooded
## amber lamp), obstacles (wire, hulks, tank traps), wrecks aging on sim time from a burning hulk
## into a debris heap, the enemies in their depth lanes (a dark rim, dimmer further back, a warm
## pulse while they telegraph) and the Behemoth. Free roam (brief 2.10, 3.1): the zone's near plane in
## place of the forest plane, cross-faded at a zone's edge, the planes scrolled by the hull's place on
## the road (TankView.plane_x); the turning places at the road's ends; the turn's dust cloud.

const LANE_DIM: Array[float] = [1.0, 0.7, 0.5, 0.4]
const RIM := Color(0.02, 0.025, 0.03, 0.9)
const CONCRETE := Color(0.2, 0.195, 0.18)
const CONCRETE_DK := Color(0.1, 0.1, 0.095)
const CONCRETE_HI := Color(0.3, 0.28, 0.25)
const IRON := Color(0.15, 0.13, 0.11)
const IRON_HI := Color(0.3, 0.26, 0.21)
const AMBER := Color(1.0, 0.68, 0.3)
const WOOD := Color(0.24, 0.18, 0.12)
const WIRE := Color(0.42, 0.42, 0.4)
## Depot props every this many world px (by hash), in the depot only.
const DEPOT_CELL_PX := 170.0
## Free roam: the turning place's barrier and the start of its gravel loop, metres inside the road's end.
const TURN_BARRIER_M := 15.0
const TURN_LOOP_M := 70.0
const GRAVEL := Color(0.2, 0.18, 0.15)
const GRAVEL_DK := Color(0.12, 0.11, 0.09)


## A plane tiled across the canvas at its parallax (scrolled by TankView.plane_x), tinted `mod`.
static func tile(ci: CanvasItem, v: TankView, p: Dictionary, mod: Color = Color.WHITE) -> void:
	var w: float = p["w"]
	var scroll := v.plane_x * TankView.S
	var x := -fposmod(scroll * float(p["parallax"]), w)
	var tex: Texture2D = p["tex"]
	while x < v.canvas.x:
		ci.draw_texture(tex, Vector2(roundf(x), float(p["y0"])), mod)
		x += w


## Free roam: the zone's near plane in place of the replaced one, the next zone's faded in at an edge.
static func _zone_plane(ci: CanvasItem, v: TankView) -> void:
	var mix := v.zone_mix
	var k := float(mix.get("k", 0.0))
	tile(ci, v, v.kit.zone_plane(str(mix.get("a", ""))), Color(1, 1, 1, 1.0 - k))
	if k > 0.0:
		tile(ci, v, v.kit.zone_plane(str(mix.get("b", ""))), Color(1, 1, 1, k))


static func draw_back(ci: CanvasItem, v: TankView) -> void:
	var far := v.kit.plane("far")
	if v.y_off > 0.0 and not far.is_empty():
		# A taller canvas: the night sky continues above the reference's frame.
		ci.draw_rect(Rect2(0, -v.y_off, v.canvas.x, v.y_off + 1.0), Color(0.016, 0.03, 0.035))
	for p in v.kit.planes:
		if str(p.get("layer", "")) == "back":
			if not v.zone_mix.is_empty() and str(p.get("name", "")) == v.kit.zone_replaces:
				_zone_plane(ci, v)
			else:
				tile(ci, v, p)
	for p2 in v.kit.planes:
		if str(p2.get("layer", "")) == "road":
			tile(ci, v, p2)


static func draw_front(ci: CanvasItem, v: TankView) -> void:
	for p in v.kit.planes:
		if str(p.get("layer", "")) == "front":
			tile(ci, v, p)
	var bottom := v.canvas.y - v.y_off
	if bottom > TankView.BASE.y:
		ci.draw_rect(
			Rect2(0, TankView.BASE.y - 1.0, v.canvas.x, bottom - TankView.BASE.y + 1.0),
			Color(0.012, 0.014, 0.014)
		)


static func draw_world(ci: CanvasItem, v: TankView, state: TankState) -> void:
	if state.seg.seg == TankIds.SEG_DEPOT and not state.roam.active:
		_depot(ci, v)
	if state.roam.active and state.roam_map != null:
		_turning_places(ci, v, state)
	_halt_line(ci, v, state)
	for ob in state.obstacles:
		_obstacle(ci, v, ob)
	for w in v.wrecks:
		_wreck(ci, v, w)
	_boss(ci, v, state)
	for want in [3, 2, 1, 0]:
		for e in state.enemies:
			if v.lanes.has(e.id) and int(v.lanes[e.id]) == want:
				_enemy(ci, v, e, want)


# --- Enemies, wrecks, the Behemoth ------------------------------------------------------------------------


static func _enemy(ci: CanvasItem, v: TankView, e: TankEnemyState, lane: int) -> void:
	var r: Rect2 = v.enemy_rects[e.id]
	var tex: Texture2D = v.kit.enemies[v.enemy_kind(e)]["tex"]
	var dim := LANE_DIM[clampi(lane, 0, LANE_DIM.size() - 1)]
	var flash := 0.0
	if e.telegraph_s > 0.0:
		flash = 0.25 + 0.25 * sin(v.time * 30.0)
	var flip := e.side < 0
	for off: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		_sprite(ci, tex, Rect2(r.position + off, r.size), flip, RIM)
	_sprite(ci, tex, r, flip, Color(dim + flash, dim + flash * 0.6, dim, 1.0))
	if e.hp_max > 0.0 and e.hp < e.hp_max:
		var bw := roundf(r.size.x * 0.4)
		var bp := Vector2(roundf(r.position.x + r.size.x * 0.3), r.position.y - 5.0)
		ci.draw_rect(Rect2(bp, Vector2(bw, 2)), Color(0, 0, 0, 0.5))
		var fill := roundf(bw * clampf(e.hp / e.hp_max, 0.0, 1.0))
		ci.draw_rect(Rect2(bp, Vector2(fill, 2)), Color(0.78, 0.3, 0.2, 0.75))


static func _sprite(ci: CanvasItem, tex: Texture2D, r: Rect2, flip: bool, mod: Color) -> void:
	if flip:
		ci.draw_texture_rect(
			tex, Rect2(Vector2(r.end.x, r.position.y), Vector2(-r.size.x, r.size.y)), false, mod
		)
	else:
		ci.draw_texture(tex, r.position, mod)


## The wreck's footprint on the road (stage px), the hulk's sprite rect and the heap's.
static func wreck_rect(v: TankView, w: Dictionary) -> Rect2:
	var sz: Vector2 = v.kit.enemies.get(str(w["kind"]), {}).get("size", Vector2(120, 50))
	var x := v.sx(float(w["x"])) - sz.x * 0.5
	var lift := TankView.LANE_LIFT * float(w.get("lane", 0)) + 4.0
	return Rect2(Vector2(roundf(x), roundf(TankView.ROAD_ENEMY_Y - sz.y - lift)), sz)


static func heap_rect(v: TankView, w: Dictionary) -> Rect2:
	var r := wreck_rect(v, w)
	var wd := roundf(r.size.x * 0.55)
	return Rect2(Vector2(roundf(r.get_center().x - wd * 0.5), r.end.y - 6.0), Vector2(wd, 6.0))


static func _wreck(ci: CanvasItem, v: TankView, w: Dictionary) -> void:
	var r := wreck_rect(v, w)
	if r.position.x > v.canvas.x + 10.0 or r.end.x < -10.0:
		return
	var collapse := v.wreck_collapse(w)
	# The burnt-out hulk, sinking as it collapses.
	if collapse < 1.0:
		var tex: Texture2D = v.kit.enemies[str(w["kind"])]["tex"]
		var sink := roundf(collapse * r.size.y * 0.7)
		var hulk := Rect2(r.position + Vector2(0, sink), Vector2(r.size.x, r.size.y - sink))
		var a := 1.0 - collapse
		var src := Rect2(Vector2.ZERO, Vector2(r.size.x, r.size.y - sink))
		var dst := hulk
		if int(w.get("side", 1)) < 0:
			dst = Rect2(Vector2(hulk.end.x, hulk.position.y), Vector2(-hulk.size.x, hulk.size.y))
		ci.draw_texture_rect_region(tex, dst, src, Color(0.2, 0.17, 0.15, a))
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


static func _boss(ci: CanvasItem, v: TankView, state: TankState) -> void:
	if not v.boss_visible(state):
		return
	var r := v.boss_rect(state)
	var b := state.boss
	var tint := Color(0.66, 0.68, 0.68) if b.phase != TankIds.BOSS_DEAD else Color(0.3, 0.27, 0.25)
	if b.telegraph_s > 0.0:
		tint = tint.lerp(Color(1.3, 0.9, 0.7), 0.3 + 0.2 * sin(v.time * 25.0))
	ci.draw_texture(v.kit.enemies["behemoth"]["tex"], r.position, tint)


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
	var g := TankView.GROUND
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
	return Vector2(roundf(v.sx(hx)) + 1.5, TankView.GROUND - 35.0)


## One concrete tooth (a blunt pyramid seen from the side) on `foot`, `s` px tall.
static func tooth(ci: CanvasItem, foot: Vector2, s: float) -> void:
	var half := s * 0.62
	var cap := s * 0.18
	var top := foot + Vector2(-s * 0.08, -s)
	ci.draw_polygon(
		PackedVector2Array(
			[foot + Vector2(-half, 0), top + Vector2(-cap, 0), top + Vector2(cap * 0.3, 0), foot]
		),
		PackedColorArray([CONCRETE])
	)
	ci.draw_polygon(
		PackedVector2Array(
			[foot, top + Vector2(cap * 0.3, 0), top + Vector2(cap, 0), foot + Vector2(half, 0)]
		),
		PackedColorArray([CONCRETE_DK])
	)
	ci.draw_rect(
		Rect2(foot + Vector2(-half - 1.0, -1.0), Vector2(half * 2.0 + 2.0, 2.0)),
		Color(0.1, 0.08, 0.06)
	)
	ci.draw_line(foot + Vector2(-half, -1.0), top + Vector2(-cap, 0), CONCRETE_HI, 1.0)


static func _obstacle(ci: CanvasItem, v: TankView, ob: TankObstacleState) -> void:
	if ob.cleared:
		return
	var x0 := v.sx(ob.x_px)
	var x1 := v.sx(ob.x_px + float(ob.w))
	if x1 < -20.0 or x0 > v.canvas.x + 20.0:
		return
	var g := TankView.GROUND
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
			var tex: Texture2D = v.kit.enemies["medium"]["tex"]
			var sz: Vector2 = v.kit.enemies["medium"]["size"]
			var hs := sz * 0.8
			var r := Rect2(
				Vector2(roundf((x0 + x1) * 0.5 - hs.x * 0.5), roundf(TankView.ROAD_ENEMY_Y - hs.y)),
				hs
			)
			ci.draw_texture_rect(
				tex,
				Rect2(Vector2(r.end.x, r.position.y), Vector2(-r.size.x, r.size.y)),
				false,
				Color(0.22, 0.2, 0.18)
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
		var g := TankView.GROUND
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
			out.append(Vector2(px + 1.0, TankView.GROUND - 45.0))
	return out


## The turn's dust cloud (brief 2.10): soft brown billows over the tank, thickest at the turn's midpoint
## where the frame flips.
static func draw_turn_dust(ci: CanvasItem, v: TankView, state: TankState) -> void:
	var k := v.turn_dust(state)
	if k <= 0.0:
		return
	var size := _variant_size(v)
	var top := v.origin + Vector2(0, size.y * 0.2)
	TankDraw.soft_at(
		ci, top + size * Vector2(0.5, 0.5), size.x * 0.62, Color(0.2, 0.17, 0.14, 0.8 * k)
	)
	for i in 34:
		var h := TankDraw.hash01(float(i) * 7.13)
		var h2 := TankDraw.hash01(float(i) * 3.71 + 1.0)
		var wob := sin(v.time * (0.7 + h) + float(i)) * 8.0
		var p := top + Vector2(size.x * (0.02 + 0.96 * h) + wob, size.y * (0.1 + 0.7 * h2))
		var r := 40.0 + 46.0 * h2
		var c := Color(0.32, 0.27, 0.21).lerp(Color(0.22, 0.19, 0.16), h)
		TankDraw.soft_at(ci, p, r, Color(c.r, c.g, c.b, 0.85 * k))


static func _variant_size(v: TankView) -> Vector2:
	var s: Variant = v.kit.spec(v.variant).get("size", [480, 240])
	return TankKit.vec(s)


## The depot yard: hooded lamp posts, fuel drums and crates along the road (world-anchored, by hash).
static func _depot(ci: CanvasItem, v: TankView) -> void:
	var g := TankView.GROUND - 4.0
	var first := floorf((v.cam_x - 40.0) / DEPOT_CELL_PX)
	var last := ceilf((v.cam_x + v.canvas.x / TankView.S) / DEPOT_CELL_PX)
	for c in range(int(first), int(last) + 1):
		var h := TankDraw.hash01(float(c) * 3.7 + 11.0)
		var x := roundf(v.sx(c * DEPOT_CELL_PX + h * 60.0))
		if h < 0.4:
			# A lamp post with a hooded lamp.
			ci.draw_rect(Rect2(Vector2(x, g - 44.0), Vector2(2, 44)), IRON)
			ci.draw_rect(Rect2(Vector2(x - 4.0, g - 47.0), Vector2(10, 3)), Color(0.08, 0.07, 0.06))
			ci.draw_rect(Rect2(Vector2(x - 2.0, g - 44.0), Vector2(6, 1)), AMBER)
		elif h < 0.75:
			# Fuel drums.
			for k in 3:
				var dx := x + k * 7.0
				var dh := 9.0 if k != 1 else 10.0
				ci.draw_rect(Rect2(Vector2(dx, g - dh), Vector2(6, dh)), Color(0.18, 0.16, 0.12))
				ci.draw_rect(Rect2(Vector2(dx, g - dh), Vector2(1, dh)), Color(0.3, 0.26, 0.2))
				ci.draw_rect(
					Rect2(Vector2(dx, g - dh * 0.5), Vector2(6, 1)), Color(0.1, 0.09, 0.07)
				)
		else:
			# Crates.
			ci.draw_rect(Rect2(Vector2(x, g - 12.0), Vector2(14, 12)), Color(0.2, 0.15, 0.1))
			ci.draw_rect(Rect2(Vector2(x + 4.0, g - 20.0), Vector2(9, 8)), Color(0.23, 0.17, 0.11))
			ci.draw_line(Vector2(x, g - 12.0), Vector2(x + 14.0, g), Color(0.13, 0.1, 0.07), 1.0)


## Where the depot's lamps hang (stage px) this frame (the light layer lights them).
static func depot_lamps(v: TankView) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var g := TankView.GROUND - 4.0
	var first := floorf((v.cam_x - 40.0) / DEPOT_CELL_PX)
	var last := ceilf((v.cam_x + v.canvas.x / TankView.S) / DEPOT_CELL_PX)
	for c in range(int(first), int(last) + 1):
		var h := TankDraw.hash01(float(c) * 3.7 + 11.0)
		if h < 0.4:
			out.append(Vector2(roundf(v.sx(c * DEPOT_CELL_PX + h * 60.0)) + 1.0, g - 43.0))
	return out
