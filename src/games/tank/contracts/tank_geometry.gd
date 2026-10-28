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
##
## v3: the tank's own geometry comes from content/tank/tanks.json tanks.<id>.geometry (the
## landship's, converted from assets/tank/v3/r6_hitbox.json; TankContentSchema.GEOMETRY_SPEC):
## with_tanks() lays it over rigs.json's tanks.<id> in the rig form (turret.ring, turret.trunnion,
## turret.barrel_px, turret.rect, muzzle, bow_guns) plus the v3 keys hull_rect, track_rect,
## headlight and seats, so the frozen accessors read the v3 tank and rigs.json keeps the enemies,
## the dug-in and the Behemoth. load_default() and load_for() both merge it.

const PATH := "res://assets/tank/rigs.json"
## The tanks file whose tanks.<id>.geometry load_default() merges (load_for() takes the content's).
const TANKS_PATH := "res://content/tank/tanks.json"
## The frozen key paths; "*" is every tank id.
const FROZEN_KEYS: Array[String] = [
	"tanks.*.turret.ring",
	"tanks.*.turret.trunnion",
	"tanks.*.turret.barrel_px",
	"tanks.*.muzzle",
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
## Tanks the data may not have yet: until their own rig lands, their gameplay geometry is the named
## tank's. v3: none (the landship's comes from tanks.json; v2's Bastion -> Citadel entry retired with
## both tanks). validate() requires every tank not listed here.
const RIG_FALLBACK := {}

var data: Dictionary = {}


## Reads rigs.json and lays content/tank/tanks.json's tank geometry over it (an empty geometry,
## which validate() reports, when a file is missing).
static func load_default() -> TankGeometry:
	return from_dict(_read(PATH)).with_tanks(_read(TANKS_PATH))


## rigs.json with the tank geometry of the loaded content's tanks.json (the rules: TankAux).
static func load_for(c: TankContent) -> TankGeometry:
	var tanks: Variant = c.data.get("tanks") if c != null else null
	return from_dict(_read(PATH)).with_tanks(tanks if tanks is Dictionary else {})


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func from_dict(d: Dictionary) -> TankGeometry:
	var g := TankGeometry.new()
	g.data = d
	return g


## v3: replaces data.tanks.<id> with the rig form of every tanks.json tank that has a `geometry`
## (`tanks_json` is the parsed tanks.json); returns self. Tanks without one keep rigs.json's.
func with_tanks(tanks_json: Dictionary) -> TankGeometry:
	var defs: Variant = tanks_json.get("tanks")
	if not (defs is Dictionary):
		return self
	data = data.duplicate(true)
	if not (data.get("tanks") is Dictionary):
		data["tanks"] = {}
	for t: String in defs:
		var geo: Variant = (
			(defs[t] as Dictionary).get("geometry") if defs[t] is Dictionary else null
		)
		if geo is Dictionary:
			data["tanks"][t] = rig_from_geometry(geo)
	return self


## The rig form (rigs.json tanks.<id>) of a tanks.json geometry block.
static func rig_from_geometry(geo: Dictionary) -> Dictionary:
	return {
		"turret":
		{
			"ring": geo.get("turret_ring"),
			"trunnion": geo.get("trunnion"),
			"barrel_px": geo.get("barrel_px"),
			"rect": geo.get("turret_rect"),
		},
		"muzzle": geo.get("muzzle"),
		"bow_guns": geo.get("bow_guns", []),
		"hull_rect": geo.get("hull_rect"),
		"track_rect": geo.get("track_rect"),
		"headlight": geo.get("headlight"),
		"seats": geo.get("seats", {}),
		"ground_y": geo.get("ground_y"),
	}


## Every problem with the frozen keys ([] when usable): each present with the right shape, three
## bogies, and muzzle == trunnion + [barrel_px, 0] at 0 degrees for every tank. (v2: the bow guns
## replace the Citadel's secondaries, so the rules no longer need `tanks.citadel.secondaries`; the
## accessor stays for a rig that still has them.)
func validate() -> Array[String]:
	var errors: Array[String] = []
	for key in FROZEN_KEYS:
		var paths: Array[String] = []
		if key.contains("*"):
			for t: String in TankIds.TANKS:
				if not RIG_FALLBACK.has(t) or has_rig(t):
					paths.append(key.replace("*", t))
		else:
			paths.append(key)
		for p in paths:
			if TankContentSchema.dig(data, p) == null:
				errors.append("rigs.json %s: missing" % p)
	if not errors.is_empty():
		return errors
	for t: String in TankIds.TANKS:
		if RIG_FALLBACK.has(t) and not has_rig(rig_of(t)):
			errors.append("rigs.json tanks.%s: missing, and so is its fallback" % t)
			continue
		var want := trunnion(t) + Vector2(barrel_px(t), 0.0)
		if not muzzle(t, 0.0, TankIds.FACE_RIGHT).is_equal_approx(want):
			errors.append("rigs.json tanks.%s: muzzle must equal trunnion + [barrel_px, 0]" % t)
	if (TankContentSchema.dig(data, "boss.bogies") as Array).size() != 3:
		errors.append(
			"rigs.json boss.bogies: three [x, y, w, h] boxes, lowest x (nearest the tank) first"
		)
	return errors


## True when rigs.json has an entry for `tank`.
func has_rig(tank: String) -> bool:
	return TankContentSchema.dig(data, "tanks.%s" % tank) is Dictionary


## The rigs.json tank whose geometry `tank` uses: its own, else its RIG_FALLBACK.
func rig_of(tank: String) -> String:
	if has_rig(tank) or not RIG_FALLBACK.has(tank):
		return tank
	return str(RIG_FALLBACK[tank])


## The barrel's pivot, hull frame.
func trunnion(tank: String) -> Vector2:
	return _vec("tanks.%s.turret.trunnion" % rig_of(tank))


## The turret ring's centre (the mirror axis when facing left), hull frame.
func ring(tank: String) -> Vector2:
	return _vec("tanks.%s.turret.ring" % rig_of(tank))


func barrel_px(tank: String) -> float:
	return float(TankContentSchema.dig(data, "tanks.%s.turret.barrel_px" % rig_of(tank)))


## The main gun's muzzle at `elev_deg` (positive up) facing TankIds.FACE_RIGHT or FACE_LEFT, hull
## frame. At 0 degrees facing right it is the file's `muzzle`.
func muzzle(tank: String, elev_deg: float, facing: int) -> Vector2:
	if is_zero_approx(elev_deg) and facing == TankIds.FACE_RIGHT:
		return _vec("tanks.%s.muzzle" % rig_of(tank))
	var a := deg_to_rad(elev_deg)
	var p := trunnion(tank) + barrel_px(tank) * Vector2(cos(a), -sin(a))
	if facing == TankIds.FACE_LEFT:
		p.x = 2.0 * ring(tank).x - p.x
	return p


## [[muzzle (hull frame), facing], ...] of the tank's secondaries (empty for none).
func secondary_muzzles(tank: String) -> Array:
	var out: Array = []
	var secs: Variant = TankContentSchema.dig(data, "tanks.%s.secondaries" % rig_of(tank))
	for s: Variant in secs if secs is Array else []:
		if s is Dictionary and s.get("muzzle") is Array:
			out.append([_to_vec(s["muzzle"]), int(s.get("facing", TankIds.FACE_RIGHT))])
	return out


## The bow guns' muzzles of `tank` in the hull frame (v2, rigs.json tanks.<id>.bow_guns[].muzzle,
## re-measured from the kit; empty when the rig has none). The rules' bursts are hitscan, so only
## presentation and tests read them.
func bow_muzzles(tank: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var guns: Variant = TankContentSchema.dig(data, "tanks.%s.bow_guns" % rig_of(tank))
	for g: Variant in guns if guns is Array else []:
		if g is Dictionary and g.get("muzzle") is Array:
			out.append(_to_vec(g["muzzle"]))
	return out


## v3: the tank's hit rects in the hull frame, broad phase first: the hull, the track run and the
## turret (tanks.json geometry hull_rect, track_rect, turret_rect); a rect the data lacks is left out.
func hit_rects(tank: String) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for key: String in ["hull_rect", "track_rect", "turret.rect"]:
		var r := _rect("tanks.%s.%s" % [rig_of(tank), key])
		if r.size != Vector2.ZERO:
			out.append(r)
	return out


## v3: the room of seat `engine` in the hull frame (tanks.json geometry seats), or an empty Rect2.
func seat_rect(tank: String, engine: String) -> Rect2:
	return _rect("tanks.%s.seats.%s" % [rig_of(tank), engine])


## v3: the bow guns' pivots in the hull frame (the guns turn about them; empty when none).
func bow_pivots(tank: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var guns: Variant = TankContentSchema.dig(data, "tanks.%s.bow_guns" % rig_of(tank))
	for g: Variant in guns if guns is Array else []:
		if g is Dictionary and g.get("pivot") is Array:
			out.append(_to_vec(g["pivot"]))
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
