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


## The barrel as drawn: {pivot, length (pivot to muzzle), left}.
func barrel() -> Dictionary:
	var piv := tank_point("barrel_pivot")
	var muzzle := tank_point("muzzle")
	var left := state.hull.facing == TankIds.FACE_LEFT
	return {"pivot": piv, "length": maxf(piv.distance_to(muzzle), 1.0), "left": left}


static func kit_anchors(crew: int) -> Dictionary:
	if _kit.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIT))
		_kit = parsed if parsed is Dictionary else {"tank": {"variants": {}}}
	var variants: Dictionary = (_kit.get("tank", {}) as Dictionary).get("variants", {})
	var v: Dictionary = variants.get(VARIANTS[clampi(crew, 1, 4) - 1], {})
	return v.get("anchors", {})


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
