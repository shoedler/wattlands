class_name TankRig
extends RefCounted
## The v3 tank kit (docs/games/tank.md v3 "The tank, in the view"; assets/tank/v3/kit.json, baked by
## assets/tank/v3/tools_src/bake.gd from the r6 generator): the base art (the reference's landship
## re-pixelled, 63 colours, with its static dressing), the live parts' sprites (road wheels,
## sprocket, idler and rollers in frames over their symmetry, one track shoe, the main gun and the
## bow guns at 0 degrees, the turret searchlight's lit lens), the main gun's blast sheets, the forest
## planes, and every rect and anchor the view reads: rooms and seats, windows, the ready rack,
## wheels and suspension travel, lamps and searchlights, the hitbox (r6_hitbox.json). All in sprite
## px (475 x 216, origin top-left, facing right). Loaded once and shared; the view only reads it.
## check() lists what is wrong with a manifest for the tests.

const DIR := "res://assets/tank/v3/"
const MANIFEST := DIR + "kit.json"
## The seats, in the HUD's card order (brief v3 "Seats").
const SEATS: Array[String] = ["drive", "gun", "loader", "lights", "sec"]
## The rooms every seat machine lives in, and the windows the loader and the bow guns show.
const WINDOWS: Array[String] = ["shaft", "rackwin", "breechwin", "boxwin", "boxwin2"]
const GEAR_SHEETS: Array[String] = ["road", "sprocket", "idler", "roller"]
## The blast sheets: on the muzzle (air), latched where the shot left it (smoke, ground).
const BLAST_PARTS: Array[String] = ["air", "smoke", "ground"]

static var _shared: TankRig = null

var manifest: Dictionary = {}
var hitbox: Dictionary = {}
var size: Vector2 = Vector2(475, 216)
## The track's bottom row (sprite y): the road line under the tank.
var ground: float = 209.0
## The base art with its static dressing (an Image for the room painter, a texture to draw).
var base_img: Image = null
var base_tex: Texture2D = null
## The turret searchlight's lit lens and where it goes.
var lit_tex: Texture2D = null
var lit_at: Vector2 = Vector2.ZERO
## The turret block the traverse mirrors (sprite px) and the x it turns about.
var turret_rect: Rect2 = Rect2()
var turret_pivot_x: float = 272.0
## room id -> Rect2; seat id -> {room, engine}; window id -> Rect2.
var rooms: Dictionary = {}
var seats: Dictionary = {}
var windows: Dictionary = {}
var window_lamps: Array[Vector2] = []
var rack: Dictionary = {}
## The running gear: kit.json gear with vectors, and the sheets' textures by kind.
var gear: Dictionary = {}
var wheels: Array[Vector3] = []
var sheets: Dictionary = {}
var track_tex: Texture2D = null
var track: Dictionary = {}
## The main gun (trunnion, length, sprite and its origin) and the bow guns.
var trunnion: Vector2 = Vector2.ZERO
var gun_len: float = 90.0
var barrel_tex: Texture2D = null
var barrel_origin: Vector2 = Vector2.ZERO
## [{pivot, len, tex, origin}], and the ball mount.
var bow: Array[Dictionary] = []
var ball_tex: Texture2D = null
var ball_origin: Vector2 = Vector2.ZERO
## kit.json details (lamps, headlight, searchlights) with their vectors.
var details: Array[Dictionary] = []
var exhaust: Vector2 = Vector2(40, 112)
## The blast sheets: part -> {tex, frames, size, origin}; fps, cols.
var blast: Dictionary = {}
var blast_fps: float = 30.0
var blast_cols: int = 10
## The forest planes back to front: {name, tex, w, y0, parallax, layer}.
var planes: Array[Dictionary] = []


static func shared() -> TankRig:
	if _shared == null:
		_shared = TankRig.new()
		_shared.load_all()
	return _shared


static func load_manifest() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if parsed is Dictionary else {}


static func vec(a: Variant) -> Vector2:
	if a is Array and (a as Array).size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO


static func rect(a: Variant) -> Rect2:
	if a is Array and (a as Array).size() >= 4:
		return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
	return Rect2()


func load_all() -> void:
	manifest = load_manifest()
	if manifest.is_empty():
		push_warning("TankRig: %s is missing or not JSON" % MANIFEST)
		return
	var hb: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(DIR + str(manifest.get("hitbox", "r6_hitbox.json")))
	)
	hitbox = hb if hb is Dictionary else {}
	size = vec(manifest.get("size", [475, 216]))
	ground = float(manifest.get("ground", 209.0))
	base_tex = _tex(str(manifest.get("base", "tank_base.png")))
	if base_tex != null:
		base_img = base_tex.get_image()
		base_img.convert(Image.FORMAT_RGBA8)
	var lit: Dictionary = manifest.get("lit", {})
	lit_tex = _tex(str(lit.get("file", "tank_lit.png")))
	lit_at = vec(lit.get("at", [0, 0]))
	var tu: Dictionary = manifest.get("turret", {})
	turret_rect = rect(tu.get("rect", [176, 0, 196, 113]))
	turret_pivot_x = float(tu.get("pivot_x", 272.0))
	var rm: Dictionary = manifest.get("rooms", {})
	for k: String in rm:
		rooms[k] = rect(rm[k])
	for s: Dictionary in manifest.get("seats", []):
		seats[str(s["id"])] = {"room": str(s["room"]), "engine": str(s["engine"])}
	var wn: Dictionary = manifest.get("windows", {})
	for k2: String in wn:
		windows[k2] = rect(wn[k2])
	for p: Variant in manifest.get("window_lamps", []):
		window_lamps.append(vec(p))
	var rk: Dictionary = manifest.get("rack", {})
	rack = {
		"pivot": vec(rk.get("pivot", [0, 0])),
		"head": vec(rk.get("head", [0, 0])),
		"slots_x": float(rk.get("slots_x", 0.0)),
		"slots_y": rk.get("slots_y", [0, 0, 0]),
	}
	_load_gear()
	_load_guns()
	for d: Dictionary in manifest.get("details", []):
		var row := d.duplicate()
		row["at"] = vec(d.get("at", [0, 0]))
		if d.has("lens"):
			row["lens"] = vec(d["lens"])
		details.append(row)
	exhaust = vec(manifest.get("exhaust", [40, 112]))
	_load_blast()
	for p2: Dictionary in manifest.get("planes", []):
		var t := _tex(str(p2["file"]))
		if t == null:
			continue
		var row2 := p2.duplicate()
		row2["tex"] = t
		row2["w"] = float(t.get_width())
		planes.append(row2)


func _load_gear() -> void:
	gear = (manifest.get("gear", {}) as Dictionary).duplicate(true)
	for w: Dictionary in gear.get("wheels", []):
		wheels.append(Vector3(float(w["x"]), float(w["y"]), float(w["r"])))
	var sh: Dictionary = gear.get("sheets", {})
	for kind: String in sh:
		var row: Dictionary = sh[kind]
		sheets[kind] = {
			"tex": _tex(str(row["file"])),
			"frames": int(row["frames"]),
			"period": float(row["period"]),
			"size": float(row["size"]),
		}
	track = manifest.get("track", {})
	track_tex = _tex(str(track.get("file", "track.png")))


func _load_guns() -> void:
	var g: Dictionary = manifest.get("gun", {})
	trunnion = vec(g.get("trunnion", [350, 103]))
	gun_len = float(g.get("len", 90.0))
	barrel_tex = _tex(str(g.get("file", "barrel.png")))
	barrel_origin = vec(g.get("origin", [0, 7]))
	var b: Dictionary = manifest.get("bow", {})
	for row: Dictionary in b.get("guns", []):
		(
			bow
			. append(
				{
					"pivot": vec(row["pivot"]),
					"len": float(row["len"]),
					"tex": _tex(str(row["file"])),
					"origin": vec(row["origin"]),
				}
			)
		)
	var ball: Dictionary = b.get("ball", {})
	ball_tex = _tex(str(ball.get("file", "bow_ball.png")))
	ball_origin = vec(ball.get("origin", [3, 5]))


func _load_blast() -> void:
	var bl: Dictionary = manifest.get("blast", {})
	blast_fps = float(bl.get("fps", 30.0))
	blast_cols = int(bl.get("cols", 10))
	for part: String in BLAST_PARTS:
		var row: Dictionary = bl.get(part, {})
		if row.is_empty():
			continue
		blast[part] = {
			"tex": _tex(str(row["file"])),
			"frames": int(row["frames"]),
			"size": vec(row["size"]),
			"origin": vec(row["origin"]),
		}


func _tex(rel: String) -> Texture2D:
	var path := DIR + rel
	if not ResourceLoader.exists(path):
		push_warning("TankRig: missing %s" % path)
		return null
	return load(path) as Texture2D


## A detail by kind ("headlight", "searchlight", "searchlight_rear", ...), or {}.
func detail(kind: String) -> Dictionary:
	for d in details:
		if str(d["kind"]) == kind:
			return d
	return {}


## The details of a kind (the red position lamps).
func details_of(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in details:
		if str(d["kind"]) == kind:
			out.append(d)
	return out


## A hitbox rect by name ("hull", "turret", "track_run").
func hit_rect(name: String) -> Rect2:
	return rect((hitbox.get("rects", {}) as Dictionary).get(name, []))


## The room a seat's machine works in, or Rect2().
func seat_room(seat: String) -> Rect2:
	var s: Dictionary = seats.get(seat, {})
	return rooms.get(str(s.get("room", "")), Rect2())


## The searchlight lens (sprite px) of a searchlight detail.
static func lens_of(d: Dictionary) -> Vector2:
	return (d["at"] as Vector2) + (d.get("lens", Vector2.ZERO) as Vector2)


## What is wrong with a manifest (missing files, rooms or anchors outside the sprite, a seat
## without its room); empty when it is sound.
static func check(m: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if m.is_empty():
		out.append("no manifest")
		return out
	var sz := vec(m.get("size", []))
	var bounds := Rect2(Vector2.ZERO, sz)
	for key: String in ["base", "hitbox"]:
		_check_file(out, str(m.get(key, "")))
	_check_file(out, str((m.get("lit", {}) as Dictionary).get("file", "")))
	_check_file(out, str((m.get("track", {}) as Dictionary).get("file", "")))
	_check_file(out, str((m.get("gun", {}) as Dictionary).get("file", "")))
	var gsh: Dictionary = (m.get("gear", {}) as Dictionary).get("sheets", {})
	for kind in GEAR_SHEETS:
		if not gsh.has(kind):
			out.append("gear sheet %s missing" % kind)
		else:
			_check_file(out, str(gsh[kind]["file"]))
	for part: String in BLAST_PARTS:
		var row: Dictionary = (m.get("blast", {}) as Dictionary).get(part, {})
		if row.is_empty():
			out.append("blast %s missing" % part)
		else:
			_check_file(out, str(row["file"]))
	for p: Dictionary in m.get("planes", []):
		_check_file(out, str(p["file"]))
	var rm: Dictionary = m.get("rooms", {})
	for k: String in rm:
		if not bounds.encloses(rect(rm[k])):
			out.append("room %s outside the sprite" % k)
	for s in SEATS:
		var found := false
		for row2: Dictionary in m.get("seats", []):
			if str(row2["id"]) == s:
				found = rm.has(str(row2["room"]))
		if not found:
			out.append("seat %s has no room" % s)
	var wn: Dictionary = m.get("windows", {})
	for w in WINDOWS:
		if not wn.has(w):
			out.append("window %s missing" % w)
		elif not bounds.encloses(rect(wn[w])):
			out.append("window %s outside the sprite" % w)
	for d: Dictionary in m.get("details", []):
		if not bounds.has_point(vec(d.get("at", [-1, -1]))):
			out.append("detail %s outside the sprite" % str(d.get("kind", "?")))
	for w2: Dictionary in (m.get("gear", {}) as Dictionary).get("wheels", []):
		if not bounds.has_point(Vector2(float(w2["x"]), float(w2["y"]))):
			out.append("a road wheel outside the sprite")
	return out


static func _check_file(out: Array[String], rel: String) -> void:
	if rel == "" or not FileAccess.file_exists(DIR + rel):
		out.append("missing file %s" % (rel if rel != "" else "(none)"))
