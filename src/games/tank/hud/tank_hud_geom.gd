class_name TankHudGeom
extends RefCounted
## Where the world tags (TankHudTags) go on the art canvas (art px, 0,0 the canvas' top left), and
## the gun's elevation arc. It only reads.
##
## The view answers when it has this public API (the v3 view):
##   hud_world_x(world_x_px: float) -> float   a rules world x (TankState units) on the canvas
##   hud_ground_y() -> float                   the road line under the tank
##   hud_tank_point(anchor: String) -> Vector2 a tank point as drawn now (facing, elevation,
##                                             recoil, hull pose): "barrel_pivot" (the trunnion),
##                                             "muzzle", "rear" (the road under the hull's rear
##                                             end), "turret_pivot", "headlight", "exhaust",
##                                             "bow_gun_upper_pivot" / "_muzzle",
##                                             "bow_gun_lower_pivot" / "_muzzle",
##                                             "searchlight_turret_lens", "searchlight_rear_lens"
##   hud_barrel_length() -> float              the main gun, trunnion to muzzle
##   hud_bow_muzzles() -> Array[Vector2]       the bow guns' muzzles as drawn
##   hud_enemy_rect(id: int) -> Rect2          an enemy's sprite (Rect2() when not drawn)
##   hud_boss_rect() -> Rect2                  the Behemoth's sprite (Rect2() when not drawn)
##   hud_barrel_dir() -> float                 the barrel as drawn: 1 right .. -1 left (traverse)
##   hud_tank_rects() -> Array[Rect2]          the hitbox's turret (as it faces) and its hull with
##                                             the track run, rotated with the hull: kept clear
##   hud_mirrored() -> bool                    the world drawn mirrored (free roam, west)
## The HUD finds the view through the game's meta VIEW_META (the view sets it), else by looking
## for a node with hud_world_x() in the tree. Without one (tests, headless runs) the same comes
## from the state, TankConst and the v3 tank kit (TankRig: the r6 landship, its hitbox and
## anchors) at rest: rules px x SCALE with the hull's rear at canvas x REAR_X, the road at GROUND,
## the tank sprite's top left at TANK_POS (TankView.TANK_AT), unrotated.

const VIEW_META := "tank_view"
const SCALE := 1.5
## The v3 view's frame at rest on the 960 x 540 base: the sprite's top left (TankView.TANK_AT), the
## hull's rear in the sprite (TankView.ART_REAR) and the road line (TankView.GROUND).
const TANK_POS := Vector2(18, 176)
const ART_REAR := 14.0
const REAR_X := TANK_POS.x + ART_REAR
const GROUND := 385.0
## The bow guns' tilt at rest (TankBody.bow_elev_deg's default).
const BOW_REST_DEG := 2.0
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


## A tank point on the canvas (the names hud_tank_point() takes): the view's as drawn, else the
## v3 kit's at rest (the turret's points mirrored about its pivot when the gun faces back).
func tank_point(anchor: String) -> Vector2:
	if view != null:
		return view.call("hud_tank_point", anchor)
	var rig := TankRig.shared()
	var left := state.hull.facing == TankIds.FACE_LEFT
	var tp := rig.turret_pivot_x
	var piv := rig.trunnion
	if left:
		piv.x = 2.0 * tp - piv.x
	var p := Vector2(rig.size.x * 0.5, rig.ground)
	match anchor:
		"barrel_pivot", "trunnion":
			p = piv
		"muzzle":
			p = piv + dir(state.hull.elev_deg, left) * (rig.gun_len + 1.0)
		"rear":
			return Vector2(TANK_POS.x + ART_REAR, ground_y())
		"turret_pivot":
			p = Vector2(tp, rig.turret_rect.end.y)
		"headlight":
			p = rig.detail("headlight").get("at", p)
		"exhaust":
			p = rig.exhaust
		"bow_gun_upper_pivot", "bow_gun_lower_pivot":
			p = _bow(rig, 0 if anchor.contains("upper") else 1, false)
		"bow_gun_upper_muzzle", "bow_gun_lower_muzzle":
			p = _bow(rig, 0 if anchor.contains("upper") else 1, true)
		"searchlight_turret_lens":
			var d := rig.detail("searchlight")
			p = TankRig.lens_of(d) if not d.is_empty() else p
			if left:
				p.x = 2.0 * tp - p.x
		"searchlight_rear_lens":
			var d2 := rig.detail("searchlight_rear")
			p = TankRig.lens_of(d2) if not d2.is_empty() else p
	return p + TANK_POS


## Bow gun `k`'s pivot, or its muzzle at the rest tilt (sprite px).
static func _bow(rig: TankRig, k: int, muzzle: bool) -> Vector2:
	if rig.bow.is_empty():
		return Vector2(rig.size.x, rig.ground * 0.5)
	var b: Dictionary = rig.bow[clampi(k, 0, rig.bow.size() - 1)]
	var piv: Vector2 = b["pivot"]
	return piv + dir(BOW_REST_DEG, false) * (float(b["len"]) + 1.0) if muzzle else piv


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
	var length := TankRig.shared().gun_len + 1.0
	if view != null and view.has_method("hud_barrel_dir"):
		var d := float(view.call("hud_barrel_dir"))
		left = d < 0.0
		turning = absf(d) < TURNED
	if view != null and view.has_method("hud_barrel_length"):
		length = float(view.call("hud_barrel_length"))
	return {"pivot": piv, "length": maxf(length, 1.0), "left": left, "turning": turning}


## The tank's body on the canvas (the hitbox's turret as it faces, the hull with the track run
## below it): the world tags keep out of these rects.
func tank_rects() -> Array[Rect2]:
	if view != null and view.has_method("hud_tank_rects"):
		return view.call("hud_tank_rects")
	var rig := TankRig.shared()
	var tr := rig.hit_rect("turret")
	if state.hull.facing == TankIds.FACE_LEFT:
		tr.position.x = 2.0 * rig.turret_pivot_x - tr.end.x
	var hull := rig.hit_rect("hull").merge(rig.hit_rect("track_run"))
	var out: Array[Rect2] = []
	for r: Rect2 in [tr, hull]:
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
