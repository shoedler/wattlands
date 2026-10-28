class_name TankKit
extends RefCounted
## The v2 kit's pieces the v3 game still uses (assets/tank/v2/kit.json): the enemies and the
## Behemoth (procedural sprites in the reference's style, with their shading masks), and the
## content cards. The v3 tank is TankRig's (assets/tank/v3/). kit.json's "tank" section keeps the v2
## variants' numbers for TankHudGeom's fallback only (turret_rect_of, hull_rect_of); their sprites
## are gone. Loaded once and shared (shared()); the view only reads it. check() lists what is wrong
## with a manifest for the tests.

const DIR := "res://assets/tank/v2/"
const MANIFEST := DIR + "kit.json"
const ENEMY_KINDS: Array[String] = ["light", "medium", "destroyer", "heavy", "dugin"]
## The v2 turret block's geometry (TankHudGeom's fallback).
const TURRET_REAR := 89.0
const CREW_H := 22.0
const HULL_REAR_X := 18.0
const HULL_DECK_RISE := 15.0

static var _shared: TankKit = null

var manifest: Dictionary = {}
## kind -> {tex, size, muzzle, meta, sil, rim}; "behemoth" too.
var enemies: Dictionary = {}


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
	var en: Dictionary = manifest.get("enemies", {})
	for kind: String in en:
		var e: Dictionary = en[kind]
		var tex := _tex(str(e["file"]))
		if tex == null:
			continue
		enemies[kind] = {
			"tex": tex,
			"size": Vector2(tex.get_size()),
			"muzzle": vec(e.get("muzzle", [0, 0])),
			"meta": e,
		}
		if kind != "behemoth":
			_shades(enemies[kind], tex)


func _tex(rel: String) -> Texture2D:
	var path := DIR + rel
	if not ResourceLoader.exists(path):
		push_warning("TankKit: missing %s" % path)
		return null
	return load(path) as Texture2D


## An enemy sprite's shading masks (white, the sprite's alpha): "sil" its silhouette (the depth
## lanes' haze, a wreck's char) and "rim" its edges facing the tank, the top and the gun end (the
## sprites face left), which the tank's beams light.
static func _shades(row: Dictionary, tex: Texture2D) -> void:
	var img := tex.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var sil := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rim := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var a := img.get_pixel(x, y).a
			if a < 0.5:
				continue
			sil.set_pixel(x, y, Color(1, 1, 1, 1))
			var k := 0.0
			for d in 2:
				if y - 1 - d < 0 or img.get_pixel(x, y - 1 - d).a < 0.5:
					k = maxf(k, 1.0 - 0.5 * d)
				if x - 1 - d < 0 or img.get_pixel(x - 1 - d, y).a < 0.5:
					k = maxf(k, 0.8 - 0.4 * d)
			if k > 0.0:
				rim.set_pixel(x, y, Color(1, 1, 1, k))
	row["sil"] = ImageTexture.create_from_image(sil)
	row["rim"] = ImageTexture.create_from_image(rim)


## A v2 variant's kit.json entry (numbers only; TankHudGeom's fallback and the v2 HUD tests).
func variant(vn: String) -> Dictionary:
	return (manifest.get("tank", {}) as Dictionary).get("variants", {}).get(vn, {})


## The v2 turret block of a kit.json variant entry (TankHudGeom's fallback).
static func turret_rect_of(v: Dictionary) -> Rect2:
	var a: Dictionary = v.get("anchors", {})
	var sc := float(v.get("turret_scale", 1.0))
	var tp := vec(a.get("turret_pivot", [0, 0]))
	var x0 := floorf(tp.x - TURRET_REAR * sc)
	var x1 := ceilf(vec(a.get("barrel_pivot", [0, 0])).x + 3.0)
	var top := floorf(vec(a.get("turret_roof_commander_feet", [0, 0])).y - CREW_H)
	return Rect2(x0, top, x1 - x0, tp.y - top)


## The v2 hull below the turret of a kit.json variant entry (TankHudGeom's fallback).
static func hull_rect_of(v: Dictionary) -> Rect2:
	var a: Dictionary = v.get("anchors", {})
	var tp := vec(a.get("turret_pivot", [0, 0]))
	var top := tp.y - HULL_DECK_RISE
	var ground := float(a.get("road_wheel_line", {}).get("ground_contact_y", 233.0))
	var front := vec(a.get("headlight", [0, 0])).x + 4.0
	return Rect2(HULL_REAR_X, top, front - HULL_REAR_X, ground - top)


static func vec(a: Variant) -> Vector2:
	if a is Array and (a as Array).size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO


## Every problem of manifest `m` (empty when sound): a missing enemy or card file, an enemy without
## a muzzle inside its sprite, a missing enemy kind.
static func check(m: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if not m.has("enemies"):
		out.append("no enemies section")
	var en: Dictionary = m.get("enemies", {})
	for kind in ENEMY_KINDS + ["behemoth"]:
		if not en.has(kind):
			out.append("no enemy %s" % kind)
	for kind2: String in en:
		var e: Dictionary = en[kind2]
		_check_file(out, str(e.get("file", "")))
		var es := vec(e.get("size", [0, 0]))
		if not Rect2(Vector2.ZERO, es).grow(1.0).has_point(vec(e.get("muzzle", [-9, -9]))):
			out.append("enemy %s muzzle outside its sprite" % kind2)
	for c: String in m.get("cards", {}):
		_check_file(out, str(m["cards"][c]))
	return out


static func _check_file(out: Array[String], rel: String) -> void:
	if rel == "" or not ResourceLoader.exists(DIR + rel):
		out.append("missing file %s" % rel)
