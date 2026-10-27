class_name TankKit
extends RefCounted
## The v2 art kit (docs/games/tank.md 3; assets/tank/v2/kit.json, its single manifest): the planes
## with their baked tilt-shift blur, the four tank variants cut from the reference (their baked
## barrel erased, the barrel drawn by the view at its elevation), the 20 px crewmen, the enemies and
## the Behemoth. Loaded once and shared (shared()); the view only reads it. check() lists what is
## wrong with a manifest (missing files, rooms or anchors outside their image) for the tests.

const DIR := "res://assets/tank/v2/"
const MANIFEST := DIR + "kit.json"
## Index = crew size - 1.
const VARIANTS: Array[String] = ["tank_1rider", "tank_2rider", "tank_3rider", "tank_4rider"]
## TankHullState.tank -> variant (the Bastion is the contracts builder's 4th tank).
const TANK_VARIANT := {
	"bulwark": "tank_1rider",
	"rampart": "tank_2rider",
	"citadel": "tank_3rider",
	"bastion": "tank_4rider",
}
const ENEMY_KINDS: Array[String] = ["light", "medium", "destroyer", "heavy", "dugin"]
## Anchors every variant has (kit.json tank.variants.*.anchors).
const ANCHORS: Array[String] = [
	"muzzle",
	"barrel_pivot",
	"turret_pivot",
	"turret_roof_commander_feet",
	"searchlight_turret_lens",
	"headlight",
	"running_light_red_front",
	"running_light_red_rear",
	"running_light_green_rear",
	"exhaust",
	"bow_gun_upper_muzzle",
	"bow_gun_upper_pivot",
	"bow_gun_lower_muzzle",
	"bow_gun_lower_pivot",
	"drive_sprocket_centre",
]

static var _shared: TankKit = null

var manifest: Dictionary = {}
## Back to front: {name, tex, w, y0, parallax, layer}.
var planes: Array[Dictionary] = []
## variant -> {hull: Texture2D, barrel: Texture2D, barrel_off: Vector2, v: Dictionary (kit.json)}.
var variants: Dictionary = {}
## pose -> Array of Texture2D.
var crew: Dictionary = {}
var crew_meta: Dictionary = {}
## kind -> {tex: Texture2D, size: Vector2, muzzle: Vector2, meta: Dictionary}; "behemoth" too.
var enemies: Dictionary = {}


## The kit every view shares (loaded on first use).
static func shared() -> TankKit:
	if _shared == null:
		_shared = TankKit.new()
		_shared.load_all()
	return _shared


static func load_manifest() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if parsed is Dictionary else {}


func load_all() -> void:
	manifest = load_manifest()
	if manifest.is_empty():
		push_warning("TankKit: %s is missing or not JSON" % MANIFEST)
		return
	for p: Dictionary in manifest.get("planes", []):
		var tex := _tex(str(p["file"]))
		if tex == null:
			continue
		var row := p.duplicate()
		row["tex"] = tex
		row["w"] = float(tex.get_width())
		planes.append(row)
	_load_variants()
	crew_meta = manifest.get("crew", {})
	var frames: Dictionary = crew_meta.get("frames", {})
	for pose: String in frames:
		var arr: Array[Texture2D] = []
		for path: String in frames[pose]:
			var t := _tex(path)
			if t != null:
				arr.append(t)
		crew[pose] = arr
	var en: Dictionary = manifest.get("enemies", {})
	for kind: String in en:
		var e: Dictionary = en[kind]
		var tex2 := _tex(str(e["file"]))
		if tex2 == null:
			continue
		enemies[kind] = {
			"tex": tex2,
			"size": Vector2(tex2.get_size()),
			"muzzle": vec(e.get("muzzle", [0, 0])),
			"meta": e,
		}


func _tex(rel: String) -> Texture2D:
	var path := DIR + rel
	if not ResourceLoader.exists(path):
		push_warning("TankKit: missing %s" % path)
		return null
	return load(path) as Texture2D


## Each variant's hull with its baked barrel erased (it only crosses sky in front of the turret),
## and the shared barrel cut to its used rect, scaled with the variant's turret.
func _load_variants() -> void:
	var tank: Dictionary = manifest.get("tank", {})
	var all: Dictionary = tank.get("variants", {})
	var barrel_tex := _tex(str(tank.get("barrel", "turret_barrel.png")))
	var bar_img: Image = barrel_tex.get_image() if barrel_tex != null else null
	var bused := Rect2i()
	if bar_img != null:
		if bar_img.is_compressed():
			bar_img.decompress()
		bar_img.convert(Image.FORMAT_RGBA8)
		bused = bar_img.get_used_rect()
	var piv3 := Vector2.ZERO
	if all.has("tank_3rider"):
		piv3 = vec(all["tank_3rider"]["anchors"]["barrel_pivot"])
	for vn: String in VARIANTS:
		if not all.has(vn):
			continue
		var v: Dictionary = all[vn]
		var hull_tex := _tex(str(v["file"]))
		if hull_tex == null:
			continue
		var row := {"hull": hull_tex, "barrel": null, "barrel_off": Vector2.ZERO, "v": v}
		var img: Image = hull_tex.get_image()
		if img != null and bar_img != null and bused.size.x > 0:
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			var piv := vec(v["anchors"]["barrel_pivot"])
			var muz := vec(v["anchors"]["muzzle"])
			for y in range(int(piv.y) - 5, int(piv.y) + 6):
				for x in range(int(piv.x) + 2, mini(int(muz.x) + 5, img.get_width())):
					img.set_pixel(x, y, Color(0, 0, 0, 0))
			row["hull"] = ImageTexture.create_from_image(img)
			var sc := float(v.get("turret_scale", 1.0))
			var b := bar_img.get_region(bused)
			var off := Vector2(bused.position) - piv3
			if not is_equal_approx(sc, 1.0):
				b.resize(
					roundi(b.get_width() * sc),
					maxi(1, roundi(b.get_height() * sc)),
					Image.INTERPOLATE_BILINEAR
				)
				off *= sc
			row["barrel"] = ImageTexture.create_from_image(b)
			row["barrel_off"] = off
		variants[vn] = row


## The variant for a hull's tank id (falls back on the crew size).
static func variant_for(tank: String, crew_size: int) -> String:
	if TANK_VARIANT.has(tank):
		return TANK_VARIANT[tank]
	return VARIANTS[clampi(crew_size, 1, 4) - 1]


func variant(vn: String) -> Dictionary:
	return variants.get(vn, {})


## kit.json's entry of a variant (rooms, anchors, size).
func spec(vn: String) -> Dictionary:
	var row: Dictionary = variants.get(vn, {})
	return row.get("v", {})


func anchor(vn: String, name: String) -> Vector2:
	var a: Dictionary = spec(vn).get("anchors", {})
	return vec(a[name]) if a.has(name) else Vector2.ZERO


func has_anchor(vn: String, name: String) -> bool:
	return (spec(vn).get("anchors", {}) as Dictionary).has(name)


func rooms(vn: String) -> Array:
	return spec(vn).get("rooms", [])


## A room's rect (variant px), or an empty Rect2.
func room_rect(vn: String, id: String) -> Rect2:
	for room: Dictionary in rooms(vn):
		if str(room["id"]) == id:
			return rect_of(room)
	return Rect2()


func plane(name: String) -> Dictionary:
	for p in planes:
		if str(p["name"]) == name:
			return p
	return {}


static func vec(a: Variant) -> Vector2:
	if a is Array and (a as Array).size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO


static func rect_of(room: Dictionary) -> Rect2:
	var r: Array = room["rect"]
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))


## Every problem of manifest `m` (empty when sound): a referenced file that does not exist, a variant
## without a room per engine or an anchor, a room or an anchor outside its image, an enemy without a
## muzzle inside its sprite.
static func check(m: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key: String in ["planes", "tank", "crew", "enemies"]:
		if not m.has(key):
			out.append("no %s section" % key)
	for p: Dictionary in m.get("planes", []):
		_check_file(out, str(p.get("file", "")))
	var tank: Dictionary = m.get("tank", {})
	_check_file(out, str(tank.get("barrel", "")))
	var all: Dictionary = tank.get("variants", {})
	for vn: String in VARIANTS:
		if not all.has(vn):
			out.append("no variant %s" % vn)
			continue
		var v: Dictionary = all[vn]
		_check_file(out, str(v.get("file", "")))
		var size := vec(v.get("size", [0, 0]))
		var img_rect := Rect2(Vector2.ZERO, size)
		for room: Dictionary in v.get("rooms", []):
			var r := rect_of(room)
			if not img_rect.encloses(r):
				out.append("%s room %s outside the image" % [vn, room.get("id", "?")])
		var anchors: Dictionary = v.get("anchors", {})
		for a: String in ANCHORS:
			if not anchors.has(a):
				out.append("%s has no anchor %s" % [vn, a])
			elif not img_rect.grow(4.0).has_point(vec(anchors[a])):
				out.append("%s anchor %s outside the image" % [vn, a])
		var wl: Dictionary = anchors.get("road_wheel_line", {})
		for x: float in wl.get("wheel_centres_x", []):
			if x < 0.0 or x > size.x:
				out.append("%s wheel at %s outside the image" % [vn, x])
	for vn2: String in VARIANTS:
		if not all.has(vn2):
			continue
		var engines: Array[String] = []
		for room2: Dictionary in all[vn2].get("rooms", []):
			if room2.has("engine"):
				engines.append(str(room2["engine"]))
		var want: Array = [["diesel"], ["diesel", "dynamo"], ["diesel", "steam", "dynamo"]]
		want.append(["diesel", "steam", "dynamo", "arc"])
		var w: Array = want[VARIANTS.find(vn2)]
		if engines != w:
			out.append("%s engine rooms %s, want %s" % [vn2, engines, w])
	var crew_frames: Dictionary = m.get("crew", {}).get("frames", {})
	for pose: String in crew_frames:
		for f: String in crew_frames[pose]:
			_check_file(out, f)
	for kind: String in m.get("enemies", {}):
		var e: Dictionary = m["enemies"][kind]
		_check_file(out, str(e.get("file", "")))
		var es := vec(e.get("size", [0, 0]))
		if not Rect2(Vector2.ZERO, es).grow(1.0).has_point(vec(e.get("muzzle", [-9, -9]))):
			out.append("enemy %s muzzle outside its sprite" % kind)
	for c: String in m.get("cards", {}):
		_check_file(out, str(m["cards"][c]))
	return out


static func _check_file(out: Array[String], rel: String) -> void:
	if rel == "" or not ResourceLoader.exists(DIR + rel):
		out.append("missing file %s" % rel)
