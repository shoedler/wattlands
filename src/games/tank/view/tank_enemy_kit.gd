class_name TankEnemyKit
extends RefCounted
## v4: the enemies' kit (assets/tank/v4/enemies.json, SPEC_TANK 5.4), baked by
## assets/tank/v4/tools_src/enemy_bake.gd. Loaded once and shared. kind() gives a row with Rect2 and Vector2
## values, in sprite px on the one atlas (texture()). Beside SPEC_TANK 5.4's "atlas" and "kinds", the manifest
## holds two top-level keys, for the art the near and far scenes draw (4.3, 4.7):
##   "bushes": {"atlas": "bushes.png", "rects": [[x, y, w, h], ...]}
##   "far_ground": "far_ground.png"
##   "far_forest": {"atlas": "far_forest.png", "rects": [[x, y, w, h], ...] (far to near), "scrub": [x, y, w, h]}
## Without the manifest (a broken bake) every kind still has its frozen size and the art is null, so a view
## guards on null and draws nothing.

const DIR := "res://assets/tank/v4/"
const MANIFEST := DIR + "enemies.json"

## kind -> [art w, art h, faces (+1 right, -1 left)] (SPEC_TANK 5.2, frozen).
const SIZES := {
	"tankette": [56, 26, 1],
	"recon": [78, 36, 1],
	"light": [96, 44, -1],
	"medium": [128, 58, -1],
	"heavy": [168, 72, -1],
	"destroyer": [150, 54, -1],
	"behemoth": [300, 148, -1],
}
## The row's keys that are rects and points in the manifest's plain arrays.
const RECT_KEYS: Array[String] = ["base", "front", "sil", "wreck", "wreck_sil", "shadow", "glow"]
const POINT_KEYS: Array[String] = [
	"muzzle_at_0", "exhaust", "hit_centre", "wreck_fire", "secondary_muzzle", "shadow_at"
]

static var _shared: TankEnemyKit = null

var manifest: Dictionary = {}

var _kinds: Dictionary = {}
var _tex: Texture2D = null
var _bushes: Texture2D = null
var _bush_rects: Array[Rect2] = []
var _ground: Texture2D = null
var _forest: Texture2D = null
var _forest_rects: Array[Rect2] = []
var _scrub_rect: Rect2 = Rect2()


static func shared() -> TankEnemyKit:
	if _shared == null:
		_shared = TankEnemyKit.new()
		_shared.load_all()
	return _shared


static func load_manifest() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if parsed is Dictionary else {}


func load_all() -> void:
	manifest = load_manifest()
	if manifest.is_empty():
		push_warning("TankEnemyKit: %s is missing or not JSON" % MANIFEST)
		return
	var rows: Dictionary = manifest.get("kinds", {})
	for k: String in rows:
		_kinds[k] = _row(rows[k])
	_tex = _load(str(manifest.get("atlas", "enemies.png")))
	var bushes_row: Dictionary = manifest.get("bushes", {})
	if not bushes_row.is_empty():
		_bushes = _load(str(bushes_row.get("atlas", "bushes.png")))
		for r: Array in bushes_row.get("rects", []):
			_bush_rects.append(rect_of(r))
	_ground = _load(str(manifest.get("far_ground", "far_ground.png")))
	var forest_row: Dictionary = manifest.get("far_forest", {})
	if not forest_row.is_empty():
		_forest = _load(str(forest_row.get("atlas", "far_forest.png")))
		for r2: Array in forest_row.get("rects", []):
			_forest_rects.append(rect_of(r2))
		if forest_row.has("scrub"):
			_scrub_rect = rect_of(forest_row["scrub"])


static func _load(file: String) -> Texture2D:
	var path := DIR + file
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func rect_of(a: Array) -> Rect2:
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


static func vec_of(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## A manifest row with Rect2 and Vector2 values (nested ones too), and the prepared wheels and belts the
## draw reads every frame.
static func _row(m: Dictionary) -> Dictionary:
	var row := m.duplicate(true)
	row["size"] = vec_of(m["size"])
	row["ground"] = float(m["ground"])
	row["faces"] = int(m["faces"])
	for k: String in RECT_KEYS:
		if m.has(k):
			row[k] = rect_of(m[k])
	for k2: String in POINT_KEYS:
		if m.has(k2):
			row[k2] = vec_of(m[k2])
	if m.has("turret"):
		var t: Dictionary = m["turret"]
		var ti: Dictionary = {
			"rect": rect_of(t["rect"]), "at": vec_of(t["at"]), "pivot": vec_of(t["pivot"])
		}
		if t.has("sil"):
			ti["sil"] = rect_of(t["sil"])
		row["turret"] = ti
	var g: Dictionary = m["gun"]
	var gi: Dictionary = {
		"rect": rect_of(g["rect"]),
		"trunnion": vec_of(g["trunnion"]),
		"len": float(g["len"]),
		"origin": vec_of(g["origin"]),
	}
	if g.has("sil"):
		gi["sil"] = rect_of(g["sil"])
	if g.has("elev"):
		gi["elev"] = vec_of(g["elev"])
	row["gun"] = gi
	row["gear"] = _gear_of(m["gear"])
	var sheets := {}
	var ms: Dictionary = m.get("sheets", {})
	for s: String in ms:
		var e: Dictionary = (ms[s] as Dictionary).duplicate()
		e["rect"] = rect_of(e["rect"])
		e["frames"] = int(e["frames"])
		e["size"] = float(e["size"])
		sheets[s] = e
	row["sheets"] = sheets
	if m.has("track"):
		var tr: Dictionary = (m["track"] as Dictionary).duplicate()
		tr["rect"] = rect_of(tr["rect"])
		row["track"] = tr
	if m.has("bogies"):
		var out: Array = []
		for b: Dictionary in m["bogies"]:
			var bi := b.duplicate(true)
			bi["rect"] = rect_of(b["rect"])
			bi["at"] = vec_of(b["at"])
			bi["wrecked"] = rect_of(b["wrecked"])
			bi["wrecked_at"] = vec_of(b["wrecked_at"])
			bi["wheels"] = _wheels_of(b["wheels"])
			bi["rollers"] = _circles_of(b["rollers"])
			bi["sprocket"] = _circle_of(b["sprocket"])
			out.append(bi)
		row["bogies"] = out
	return row


static func _gear_of(g: Dictionary) -> Dictionary:
	var o := {
		"T": float(g["T"]),
		"up": float(g["up"]),
		"droop": float(g["droop"]),
		"wheels": _wheels_of(g["wheels"]),
		"rollers": _circles_of(g.get("rollers", [])),
	}
	if g.has("sprocket"):
		o["sprocket"] = _circle_of(g["sprocket"])
	if g.has("idler"):
		o["idler"] = _circle_of(g["idler"])
	var far: Array[bool] = []
	for w: Dictionary in g["wheels"]:
		far.append(bool(w.get("far", false)))
	o["far"] = far
	return o


static func _wheels_of(rows: Array) -> Array[Vector3]:
	var o: Array[Vector3] = []
	for w: Dictionary in rows:
		o.append(Vector3(float(w["x"]), float(w["y"]), float(w["r"])))
	return o


static func _circles_of(rows: Array) -> Array[Vector3]:
	var o: Array[Vector3] = []
	for r: Dictionary in rows:
		o.append(_circle_of(r))
	return o


static func _circle_of(r: Dictionary) -> Vector3:
	var c := vec_of(r["c"])
	return Vector3(c.x, c.y, float(r["r"]))


## The row with Rect2 and Vector2 values; "size" always there (a medium's for an unknown kind).
func kind(k: String) -> Dictionary:
	if _kinds.has(k):
		return _kinds[k]
	var row: Array = SIZES.get(k, SIZES["medium"])
	var size := Vector2(float(row[0]), float(row[1]))
	return {
		"size": size,
		"ground": size.y - 4.0,
		"faces": int(row[2]),
		"muzzle_at_0": Vector2(size.x if int(row[2]) > 0 else 0.0, size.y * 0.3),
		"hit_centre": size * 0.5,
	}


## The atlas (null without the bake).
func texture() -> Texture2D:
	return _tex


## The roadside bush sheet (null without the bake). Frames in bush_rects().
func bushes() -> Texture2D:
	return _bushes


## The bush frames in bushes(), foot at the bottom centre of each.
func bush_rects() -> Array[Rect2]:
	return _bush_rects


## The far panel's ground band, 1024 x 170 and tiling (null without the bake).
func far_ground() -> Texture2D:
	return _ground


## The far panel's treeline sheet (null without the bake). Strips in far_forest_rects(), far to near.
func far_forest() -> Texture2D:
	return _forest


func far_forest_rects() -> Array[Rect2]:
	return _forest_rects


## The scrub along the treeline's foot on the same sheet; empty without the bake.
func far_scrub_rect() -> Rect2:
	return _scrub_rect


## Every problem of manifest `m` (empty when sound): a kind missing or without a size, no bushes, no
## far ground, no treeline.
static func check(m: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var kinds: Variant = m.get("kinds")
	if not (kinds is Dictionary):
		return ["no kinds"]
	for k: String in SIZES:
		var row: Variant = (kinds as Dictionary).get(k)
		if not (row is Dictionary) or not (row as Dictionary).has("size"):
			out.append("no enemy %s" % k)
	var bush_sheet: Variant = m.get("bushes")
	if not (bush_sheet is Dictionary) or (bush_sheet as Dictionary).get("rects", []).is_empty():
		out.append("no bushes")
	if not (m.get("far_ground") is String):
		out.append("no far_ground")
	var forest: Variant = m.get("far_forest")
	if not (forest is Dictionary) or (forest as Dictionary).get("rects", []).is_empty():
		out.append("no far_forest")
	return out
