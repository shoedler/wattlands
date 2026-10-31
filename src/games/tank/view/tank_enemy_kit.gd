class_name TankEnemyKit
extends RefCounted
## v4: the enemies' kit (assets/tank/v4/enemies.json, SPEC_TANK 5.4). Stub until builder A: nothing is
## loaded, kind() returns each kind's frozen size from a table. Loaded once and shared.
## Beside SPEC_TANK 5.4's "atlas" and "kinds", the manifest holds two top-level keys, for the art the near
## and far scenes draw (4.3, 4.7):
##   "bushes": {"atlas": "bushes.png", "rects": [[x, y, w, h], ...]}
##   "far_ground": "far_ground.png"
## The stub returns null and an empty list, so a view guards on null and draws nothing until A bakes them.

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

static var _shared: TankEnemyKit = null


static func shared() -> TankEnemyKit:
	if _shared == null:
		_shared = TankEnemyKit.new()
	return _shared


## The row with Rect2 and Vector2 values; "size" always there (a medium's for an unknown kind).
func kind(k: String) -> Dictionary:
	var row: Array = SIZES.get(k, SIZES["medium"])
	var size := Vector2(float(row[0]), float(row[1]))
	return {
		"size": size,
		"ground": size.y - 4.0,
		"faces": int(row[2]),
		"muzzle_at_0": Vector2(size.x if int(row[2]) > 0 else 0.0, size.y * 0.3),
		"hit_centre": size * 0.5,
	}


## The atlas (null until builder A bakes it).
func texture() -> Texture2D:
	return null


## The roadside bush sheet (null until builder A bakes it). Frames in bush_rects().
func bushes() -> Texture2D:
	return null


## The bush frames in bushes(), foot at the bottom centre of each (empty until builder A).
func bush_rects() -> Array[Rect2]:
	return []


## The far panel's ground band, 1024 x 170 and tiling (null until builder A bakes it).
func far_ground() -> Texture2D:
	return null


## Every problem of manifest `m` (empty when sound): a kind missing or without a size, no bushes, no
## far ground.
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
	return out
