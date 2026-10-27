class_name TankHudGeom
extends RefCounted
## Where the world tags (TankHudTags) go on the art canvas (art px, 0,0 the canvas' top left), and
## the gun's elevation arc. It only reads.
##
## The view answers when it has this public API (the v2 view, requested from the view builder):
##   hud_world_x(world_x_px: float) -> float   a rules world x (TankState units) on the canvas
##   hud_ground_y() -> float                   the road line under the tank
##   hud_tank_point(anchor: String) -> Vector2 kit.json anchors as drawn now (facing, elevation,
##                                             hull bob): "barrel_pivot", "muzzle", "rear" (the
##                                             road under the hull's rear end)
##   hud_enemy_rect(id: int) -> Rect2          an enemy's sprite (Rect2() when not drawn)
##   hud_boss_rect() -> Rect2                  the Behemoth's sprite (Rect2() when not drawn)
##   hud_barrel_dir() -> float                 the barrel as drawn: 1 right .. -1 left (traverse)
##   hud_tank_rects() -> Array[Rect2]          the turret (as it faces) and the hull, kept clear
##   hud_variant() -> String                   the variant drawn
## The HUD finds the view through the game's meta VIEW_META (the view sets it), else by looking
## for a node with hud_world_x() in the tree. Without one (tests, headless runs, the v1 view) the
## same comes from the state, TankConst and kit.json: rules px x 1.5 with the hull's rear at
## canvas x REAR_X, the road at GROUND, the variant's anchors at TANK_POS (the approved mock's
## framing).

const VIEW_META := "tank_view"
const KIT := "res://assets/tank/v2/kit.json"
const VARIANTS: Array[String] = ["tank_1rider", "tank_2rider", "tank_3rider", "tank_4rider"]
const SCALE := 1.5
const REAR_X := 24.0
const GROUND := 340.0
const TANK_POS := Vector2(6, 107)
## The gun's reach (brief 2.4) and the arc: drawn beyond the muzzle, so never on the barrel.
const ELEV_MIN := -12.0
const ELEV_MAX := 30.0
## The barrel sprite past the muzzle anchor (its brake) and its half height at the mantlet.
const BARREL_OVERHANG := 3.0
const BARREL_HALF := 10.0
## The arc's gap beyond the barrel's tip.
const ARC_GAP := 8.0
## The arc keeps this clear of the tank's body, stepping out ARC_STEP at a time, at most ARC_PUSH_MAX.
const ARC_CLEAR := 2.0
const ARC_STEP := 2.0
const ARC_PUSH_MAX := 60.0
## The view's barrel counts as turned (an arc drawn) once |hud_barrel_dir| reaches this.
const TURNED := 0.98

static var _kit: Dictionary = {}

var state: TankState = null
## The view when it has the API (else null: the fallback).
var view: Object = null


static func make(p_state: TankState, p_view: Object) -> TankHudGeom:
	var g := TankHudGeom.new()
	g.state = p_state
	if p_view != null and p_view.has_method("hud_world_x"):
		g.view = p_view
	return g


func world_x(wx: float) -> float:
	if view != null:
		return float(view.call("hud_world_x", wx))
	return REAR_X + (wx - state.camera_x() - float(TankConst.REAR_SCREEN_X)) * SCALE


func ground_y() -> float:
	if view != null:
		return float(view.call("hud_ground_y"))
	return GROUND


## A tank anchor on the canvas: "barrel_pivot", "muzzle" (at the barrel's elevation), "rear".
func tank_point(anchor: String) -> Vector2:
	if view != null:
		return view.call("hud_tank_point", anchor)
	var a := kit_anchors(state.riders.size())
	var left := state.hull.facing == TankIds.FACE_LEFT
	var piv := _kit_point(a, "barrel_pivot")
	var tp := _kit_point(a, "turret_pivot")
	if left:
		piv.x = 2.0 * tp.x - piv.x
	match anchor:
		"barrel_pivot":
			return piv
		"muzzle":
			var length := _kit_point(a, "muzzle").distance_to(_kit_point(a, "barrel_pivot"))
			return piv + dir(state.hull.elev_deg, left) * length
		"rear":
			return Vector2(REAR_X + 12.0, ground_y())
	return _kit_point(a, anchor)


func enemy_rect(e: TankEnemyState) -> Rect2:
	if view != null:
		return view.call("hud_enemy_rect", e.id)
	var w := float(e.w) * SCALE
	var h := float(e.h) * SCALE
	var cx := world_x(e.x_px + float(e.w) * 0.5)
	return Rect2(cx - w * 0.5, ground_y() - h, w, h)


func boss_rect() -> Rect2:
	if view != null:
		return view.call("hud_boss_rect")
	return Rect2(world_x(state.boss.x_px), ground_y() - 150.0, 260.0, 150.0)


## The barrel as drawn: {pivot, length (pivot to the muzzle at full length), left, turning}. The
## side comes from the barrel the view draws (hud_barrel_dir), not from the ordered facing, so the
## arc follows the gun through a traverse; `turning` while the turret is part way round (no arc).
func barrel() -> Dictionary:
	var piv := tank_point("barrel_pivot")
	var left := state.hull.facing == TankIds.FACE_LEFT
	if mirrored():
		left = not left
	var turning := false
	if view != null and view.has_method("hud_barrel_dir"):
		var d := float(view.call("hud_barrel_dir"))
		left = d < 0.0
		turning = absf(d) < TURNED
	var a := kit_anchors(state.riders.size())
	if view != null and view.has_method("hud_variant"):
		a = (kit_variant_of(str(view.call("hud_variant"))).get("anchors", {}) as Dictionary)
	var length := _kit_point(a, "muzzle").distance_to(_kit_point(a, "barrel_pivot"))
	return {"pivot": piv, "length": maxf(length, 1.0), "left": left, "turning": turning}


## The tank's body on the canvas (the turret as it faces, the hull below it): the world tags keep
## out of these rects.
func tank_rects() -> Array[Rect2]:
	if view != null and view.has_method("hud_tank_rects"):
		return view.call("hud_tank_rects")
	var v := kit_variant(state.riders.size())
	var tr := TankKit.turret_rect_of(v)
	if state.hull.facing == TankIds.FACE_LEFT:
		var tp := _kit_point(v.get("anchors", {}), "turret_pivot").x - TANK_POS.x
		tr.position.x = 2.0 * tp - tr.end.x
	var out: Array[Rect2] = []
	for r: Rect2 in [tr, TankKit.hull_rect_of(v)]:
		out.append(Rect2(r.position + TANK_POS, r.size))
	return out


## The elevation arc as it will be drawn for the barrel `b` (barrel()), its label `label_size` art
## px: {radius, label (Rect2; empty when it would touch the tank), keep_out (Array[Rect2])}. The arc
## starts ARC_GAP past the barrel's tip and steps out (ARC_STEP) until neither the arc, its ticks
## (every elevation, radius - 2 .. + 6) nor its label touch the tank's body (`keep_out` grown by
## ARC_CLEAR), at most ARC_PUSH_MAX; the painter then skips any pixel still inside (arc_px_ok), so
## the arc is never drawn on the tank.
static func arc_layout(b: Dictionary, label_size: Vector2, keep_out: Array[Rect2]) -> Dictionary:
	var piv: Vector2 = b["pivot"]
	var left := bool(b["left"])
	var base := arc_radius(float(b["length"]))
	var grown: Array[Rect2] = []
	for k in keep_out:
		grown.append(k.grow(ARC_CLEAR))
	var radius := base
	while radius < base + ARC_PUSH_MAX:
		if _clear(arc_reach(piv, radius, left), label_rect(piv, radius, left, label_size), grown):
			break
		radius += ARC_STEP
	var lr := label_rect(piv, radius, left, label_size)
	for k2 in grown:
		if lr.intersects(k2):
			lr = Rect2()
			break
	return {"radius": radius, "label": lr, "keep_out": grown}


## True when the arc may paint pixel `p` (outside every keep-out rect of arc_layout()).
static func arc_px_ok(p: Vector2i, keep_out: Array) -> bool:
	for r: Rect2 in keep_out:
		if r.has_point(Vector2(p) + Vector2(0.5, 0.5)):
			return false
	return true


## Every pixel the arc can paint at `radius`: the arc and a tick at every degree from radius - 2
## to radius + 6 (the 10-degree ticks, the ordered and the actual elevation's marks).
static func arc_reach(piv: Vector2, radius: float, left: bool) -> Array[Vector2i]:
	var px := arc_pixels(piv, radius, left)
	var deg := ELEV_MIN
	while deg <= ELEV_MAX + 0.001:
		px.append_array(tick_pixels(piv, deg, left, radius - 2.0, radius + 6.0))
		deg += 1.0
	return px


static func _clear(px: Array[Vector2i], label: Rect2, rects: Array[Rect2]) -> bool:
	for r in rects:
		if label.size != Vector2.ZERO and label.intersects(r):
			return false
	for p in px:
		if not arc_px_ok(p, rects):
			return false
	return true


## True while the view draws the world mirrored (free roam, driving west; the view's hud_mirrored(),
## else the travel direction).
func mirrored() -> bool:
	if view != null and view.has_method("hud_mirrored"):
		return bool(view.call("hud_mirrored"))
	return state.roam.active and state.hull.dir < 0


static func kit_anchors(crew: int) -> Dictionary:
	return kit_variant(crew).get("anchors", {})


## kit.json's entry of the variant for `crew` riders.
static func kit_variant(crew: int) -> Dictionary:
	return kit_variant_of(VARIANTS[clampi(crew, 1, 4) - 1])


static func kit_variant_of(vn: String) -> Dictionary:
	if _kit.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIT))
		_kit = parsed if parsed is Dictionary else {"tank": {"variants": {}}}
	var variants: Dictionary = (_kit.get("tank", {}) as Dictionary).get("variants", {})
	return variants.get(vn, {})


static func _kit_point(anchors: Dictionary, key: String) -> Vector2:
	var a: Variant = anchors.get(key)
	if a is Array and (a as Array).size() >= 2:
		return TANK_POS + Vector2(float(a[0]), float(a[1]))
	return TANK_POS


# --- The elevation arc (pure) ------------------------------------------------------------------


## The screen direction of elevation `deg` (y down), mirrored when facing left.
static func dir(deg: float, left: bool) -> Vector2:
	var r := deg_to_rad(deg)
	return Vector2(cos(r) * (-1.0 if left else 1.0), -sin(r))


## The arc's radius for a barrel of `length`: past the barrel's tip by ARC_GAP.
static func arc_radius(length: float) -> float:
	return length + BARREL_OVERHANG + ARC_GAP


## The arc's pixels (ELEV_MIN..ELEV_MAX at `radius` round `pivot`).
static func arc_pixels(pivot: Vector2, radius: float, left: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var a := ELEV_MIN
	while a <= ELEV_MAX + 0.001:
		var p := Vector2i((pivot + dir(a, left) * radius).round())
		if out.is_empty() or out[-1] != p:
			out.append(p)
		a += 0.25
	return out


## A tick along elevation `deg` from radius `r0` to `r1` (whole pixels).
static func tick_pixels(
	pivot: Vector2, deg: float, left: bool, r0: float, r1: float
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var d := dir(deg, left)
	var r := r0
	while r <= r1 + 0.001:
		out.append(Vector2i((pivot + d * r).round()))
		r += 1.0
	return out


## The degrees label's rect (`size` art px) just past the arc's upper end.
static func label_rect(pivot: Vector2, radius: float, left: bool, size: Vector2) -> Rect2:
	var end := pivot + dir(ELEV_MAX, left) * (radius + 3.0)
	var x := end.x + 2.0 if not left else end.x - 2.0 - size.x
	return Rect2(roundf(x), roundf(end.y - size.y - 1.0), size.x, size.y)


## Every pixel the barrel sprite can cover at elevation `deg` (tests): the rotated box from just
## behind the pivot to the brake, BARREL_HALF above and below the bore line.
static func barrel_pixels(pivot: Vector2, length: float, deg: float, left: bool) -> Dictionary:
	var out := {}
	var d := dir(deg, left)
	var n := Vector2(d.y, -d.x) if not left else Vector2(-d.y, d.x)
	var along := -2.0
	while along <= length + BARREL_OVERHANG:
		var off := -BARREL_HALF
		while off <= BARREL_HALF:
			out[Vector2i((pivot + d * along + n * off).round())] = true
			off += 0.5
		along += 0.5
	return out
