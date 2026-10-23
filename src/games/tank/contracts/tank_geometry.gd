class_name TankGeometry
extends RefCounted
## Gameplay geometry (G0 contract): the frozen keys of assets/tank/rigs.json that the rules read
## (muzzles, the barrel pivot, part and hit boxes), in their documented frames. artqa owns the
## file and re-measures the values; the key names and frames below never change, and rules code
## and tests read geometry only through this class (never hard-coded numbers), so a re-measure
## moves the game without breaking a test. validate() checks the keys and the gun invariant.
##
## Frames (rigs.json _doc): tank points are in the hull frame (the hull sprite's top-left, y down,
## negative y above the roof), facing right; enemy points are in their sprite's frame facing left;
## boss points in boss_hull's frame facing left.

const PATH := "res://assets/tank/rigs.json"
## The frozen key paths; "*" is every tank id.
const FROZEN_KEYS: Array[String] = [
	"tanks.*.turret.ring",
	"tanks.*.turret.trunnion",
	"tanks.*.turret.barrel_px",
	"tanks.*.muzzle",
	"tanks.citadel.secondaries",
	"enemies.enemy_light.muzzle",
	"enemies.enemy_medium.muzzle",
	"enemies.enemy_heavy.muzzle",
	"enemies.enemy_destroyer.muzzle",
	"enemies.enemy_dugin.muzzle",
	"enemies.enemy_dugin.hitbox",
	"boss.bogies",
	"boss.turret.rect",
	"boss.turret.muzzle",
	"boss.secondary_muzzle",
]

var data: Dictionary = {}


## Reads rigs.json (an empty geometry, which validate() reports, when the file is missing).
static func load_default() -> TankGeometry:
	var parsed: Variant = null
	if FileAccess.file_exists(PATH):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return from_dict(parsed if parsed is Dictionary else {})


static func from_dict(d: Dictionary) -> TankGeometry:
	var g := TankGeometry.new()
	g.data = d
	return g


## Every problem with the frozen keys ([] when usable): each present with the right shape, the
## Citadel's two secondaries with muzzle and facing, three bogies, and muzzle == trunnion +
## [barrel_px, 0] at 0 degrees for every tank.
func validate() -> Array[String]:
	var errors: Array[String] = []
	for key in FROZEN_KEYS:
		var paths: Array[String] = []
		if key.contains("*"):
			for t: String in TankIds.TANKS:
				paths.append(key.replace("*", t))
		else:
			paths.append(key)
		for p in paths:
			if TankContentSchema.dig(data, p) == null:
				errors.append("rigs.json %s: missing" % p)
	if not errors.is_empty():
		return errors
	for t: String in TankIds.TANKS:
		var want := trunnion(t) + Vector2(barrel_px(t), 0.0)
		if not muzzle(t, 0.0, TankIds.FACE_RIGHT).is_equal_approx(want):
			errors.append("rigs.json tanks.%s: muzzle must equal trunnion + [barrel_px, 0]" % t)
	if secondary_muzzles(TankIds.TANK_CITADEL).size() != 2:
		errors.append("rigs.json tanks.citadel.secondaries: fore and aft, each with a muzzle")
	if (TankContentSchema.dig(data, "boss.bogies") as Array).size() != 3:
		errors.append(
			"rigs.json boss.bogies: three [x, y, w, h] boxes, lowest x (nearest the tank) first"
		)
	return errors


## The barrel's pivot, hull frame.
func trunnion(tank: String) -> Vector2:
	return _vec("tanks.%s.turret.trunnion" % tank)


## The turret ring's centre (the mirror axis when facing left), hull frame.
func ring(tank: String) -> Vector2:
	return _vec("tanks.%s.turret.ring" % tank)


func barrel_px(tank: String) -> float:
	return float(TankContentSchema.dig(data, "tanks.%s.turret.barrel_px" % tank))


## The main gun's muzzle at `elev_deg` (positive up) facing TankIds.FACE_RIGHT or FACE_LEFT, hull
## frame. At 0 degrees facing right it is the file's `muzzle`.
func muzzle(tank: String, elev_deg: float, facing: int) -> Vector2:
	if is_zero_approx(elev_deg) and facing == TankIds.FACE_RIGHT:
		return _vec("tanks.%s.muzzle" % tank)
	var a := deg_to_rad(elev_deg)
	var p := trunnion(tank) + barrel_px(tank) * Vector2(cos(a), -sin(a))
	if facing == TankIds.FACE_LEFT:
		p.x = 2.0 * ring(tank).x - p.x
	return p


## [[muzzle (hull frame), facing], ...] of the tank's secondaries (empty for none).
func secondary_muzzles(tank: String) -> Array:
	var out: Array = []
	var secs: Variant = TankContentSchema.dig(data, "tanks.%s.secondaries" % tank)
	for s: Variant in secs if secs is Array else []:
		if s is Dictionary and s.get("muzzle") is Array:
			out.append([_to_vec(s["muzzle"]), int(s.get("facing", TankIds.FACE_RIGHT))])
	return out


## An enemy's muzzle in its sprite's frame (art.json sprite id, e.g. "enemy_light").
func enemy_muzzle(sprite: String) -> Vector2:
	return _vec("enemies.%s.muzzle" % sprite)


## An enemy's own hit box in its sprite's frame, or an empty Rect2 when the whole sprite is one.
func enemy_hitbox(sprite: String) -> Rect2:
	return _rect("enemies.%s.hitbox" % sprite)


## The hit box of boss part `index` (0..2 bogies, index 0 nearest the tank, 3 the turret), boss_hull frame.
func boss_part_rect(index: int) -> Rect2:
	if index == TankBossState.TURRET_PART:
		return _rect("boss.turret.rect")
	var bogies: Variant = TankContentSchema.dig(data, "boss.bogies")
	if bogies is Array and index >= 0 and index < (bogies as Array).size():
		return _to_rect(bogies[index])
	return Rect2()


func boss_muzzle() -> Vector2:
	return _vec("boss.turret.muzzle")


func boss_secondary_muzzle() -> Vector2:
	return _vec("boss.secondary_muzzle")


func _vec(path: String) -> Vector2:
	return _to_vec(TankContentSchema.dig(data, path))


func _rect(path: String) -> Rect2:
	return _to_rect(TankContentSchema.dig(data, path))


static func _to_vec(v: Variant) -> Vector2:
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO


static func _to_rect(v: Variant) -> Rect2:
	if v is Array and (v as Array).size() >= 4:
		return Rect2(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
	return Rect2()
