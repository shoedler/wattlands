class_name TankPlaceholderArt
extends RefCounted
## Procedural stand-ins for every sprite id in assets/tank/art.json (brief 3: "draws any missing
## sprite at its size from palette shapes and logs once"). Owner: artqa (G0 wrote this first
## version: a flat palette block per id, so the view works with no PNG at all).
##
## The view asks texture(id) for every sprite; it returns the pixelated PNG from
## assets/tank/sprites/<id>.png when it exists, else a generated texture of the sprite's size.

const ART_JSON := "res://assets/tank/art.json"
const SPRITES_DIR := "res://assets/tank/sprites"

static var _art: Dictionary = {}
static var _cache: Dictionary = {}
static var _logged: Dictionary = {}


## The sprite's texture: the generated PNG when present, else a placeholder of its size.
static func texture(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var path := SPRITES_DIR.path_join(id + ".png")
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		tex = ImageTexture.create_from_image(placeholder_image(id))
		if not _logged.has(id):
			_logged[id] = true
			print("tank: placeholder art for %s" % id)
	_cache[id] = tex
	return tex


## The sprite's size in art px from art.json (16 x 16 for an unknown id).
static func size_of(id: String) -> Vector2i:
	var s: Dictionary = sprite_def(id)
	var size: Array = s.get("size", [16, 16])
	return Vector2i(int(size[0]), int(size[1]))


## The art.json entry of `id` ({} when unknown).
static func sprite_def(id: String) -> Dictionary:
	for s: Variant in _art_json().get("sprites", []):
		if s is Dictionary and str(s.get("id", "")) == id:
			return s
	return {}


## Every sprite id of art.json, in file order.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for s: Variant in _art_json().get("sprites", []):
		if s is Dictionary:
			out.append(str(s.get("id", "")))
	return out


## The palette of art.json as Colors.
static func palette() -> Array[Color]:
	var out: Array[Color] = []
	for c: Variant in _art_json().get("palette", []):
		out.append(Color(str(c)))
	return out


## A flat block of one palette color with a darker frame, at the sprite's size.
static func placeholder_image(id: String) -> Image:
	var size := size_of(id)
	var img := Image.create(maxi(size.x, 1), maxi(size.y, 1), false, Image.FORMAT_RGBA8)
	var pal := palette()
	var fill := Color("#444b52")
	var frame := Color("#161a1e")
	if pal.size() >= 8:
		fill = pal[(absi(id.hash()) % 6) + 4]
		frame = pal[1]
	img.fill(fill)
	for x in size.x:
		img.set_pixel(x, 0, frame)
		img.set_pixel(x, size.y - 1, frame)
	for y in size.y:
		img.set_pixel(0, y, frame)
		img.set_pixel(size.x - 1, y, frame)
	return img


static func _art_json() -> Dictionary:
	if _art.is_empty() and FileAccess.file_exists(ART_JSON):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(ART_JSON))
		_art = d if d is Dictionary else {}
	return _art
