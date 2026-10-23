class_name FishingSprites
extends RefCounted
## Loads Big Game Fishing's sprites (brief 3.3, docs/ART_PIPELINE.md) and caches the textures:
##  1. res://assets/fishing/sprites/<id>.png (and <id>__<part>.png) when the art pipeline wrote it,
##     with sizes and anchors from sprites.json;
##  2. else the art builder's fallback script, asked by path (its class may not exist in every
##     branch): load(FALLBACK_SCRIPT).call("image", id) -> Image at the sprite's art.json size;
##  3. else FishingPlaceholderArt's palette shapes at the art.json size.
## A part missing as a file is cut from the whole sprite by its art.json rect.

const SPRITE_DIR := "res://assets/fishing/sprites"
const ART_JSON := "res://assets/fishing/art.json"
const SPRITES_JSON := "res://assets/fishing/sprites/sprites.json"
const FALLBACK_SCRIPT := "res://src/games/fishing/tools/fishing_fallback_sprites.gd"
const SRC_PNG := "png"
const SRC_FALLBACK := "fallback"
const SRC_PLACEHOLDER := "placeholder"
## Brief 3.3's sizes, used when art.json can't be read (an export without the JSON).
const SIZES := {
	"boat": [80, 32],
	"rig_bike": [24, 16],
	"rig_angler": [14, 12],
	"rig_crank": [10, 10],
	"rig_reel": [10, 10],
	"fish_mackerel": [24, 8],
	"fish_mahi": [40, 16],
	"fish_tuna": [44, 16],
	"fish_marlin": [64, 22],
	"gull_up": [10, 8],
	"gull_down": [10, 8],
	"bait_ball": [32, 12],
	"sonar_mark": [8, 5],
	"current_seam": [48, 4],
	"splash": [20, 12],
	"spray": [32, 24],
	"catch_flash": [24, 24],
	"trophy_badge": [16, 16],
	"clouds": [320, 24],
	"islands_far": [256, 12],
	"island_palm": [80, 24],
	"sun": [12, 12],
	"wake": [32, 6],
	"surface_strip": [64, 6],
	"light_rays": [128, 64],
	"reef_back": [416, 28],
	"reef_front": [416, 18],
	"sand_strip": [64, 8],
	"picker_card": [160, 90],
}
const ALIGN_ANCHORS := {
	"top_left": Vector2(0, 0),
	"top_center": Vector2(0.5, 0),
	"top_right": Vector2(1, 0),
	"center_left": Vector2(0, 0.5),
	"center": Vector2(0.5, 0.5),
	"center_right": Vector2(1, 0.5),
	"bottom_left": Vector2(0, 1),
	"bottom_center": Vector2(0.5, 1),
	"bottom_right": Vector2(1, 1),
}

static var _textures: Dictionary = {}
static var _sources: Dictionary = {}
static var _art: Dictionary = {}
static var _sheet: Dictionary = {}
static var _loaded: bool = false


## The sprite's texture (cached).
static func texture(id: String) -> Texture2D:
	if _textures.has(id):
		return _textures[id]
	_load_meta()
	var tex: Texture2D = null
	var path := SPRITE_DIR.path_join(id + ".png")
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
		if tex != null:
			_sources[id] = SRC_PNG
	if tex == null:
		tex = ImageTexture.create_from_image(image(id))
	_textures[id] = tex
	return tex


## A named part (`<id>__<part>.png`, else cut from the whole sprite by its art.json rect).
static func part(id: String, part_name: String) -> Texture2D:
	var key := id + "__" + part_name
	if _textures.has(key):
		return _textures[key]
	var path := SPRITE_DIR.path_join(key + ".png")
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		var whole := texture(id)
		var r := part_rect(id, part_name)
		var img: Image = null
		if source(id) == SRC_PNG:
			img = whole.get_image()
		else:
			img = image(id)
		var fits := img != null and not img.is_empty() and r.size.x > 0 and r.size.y > 0
		if fits and Rect2i(Vector2i.ZERO, img.get_size()).encloses(r):
			tex = ImageTexture.create_from_image(img.get_region(r))
		else:
			tex = whole
	_textures[key] = tex
	return tex


## The Image a sprite falls back to when it has no PNG: the art builder's fallback, else ours.
static func image(id: String) -> Image:
	var size := size_of(id)
	if ResourceLoader.exists(FALLBACK_SCRIPT):
		var script := load(FALLBACK_SCRIPT) as Script
		if script != null and _has_static(script, "image"):
			var img: Variant = script.call("image", id)
			if img is Image and not (img as Image).is_empty():
				_sources[id] = SRC_FALLBACK
				return img
	_sources[id] = SRC_PLACEHOLDER
	return FishingPlaceholderArt.image(id, size)


## Where a sprite came from: "png", "fallback" or "placeholder" ("" before it loaded).
static func source(id: String) -> String:
	return str(_sources.get(id, ""))


## The sprite's size in art pixels: the loaded texture's, else art.json's, else brief 3.3's.
static func size_of(id: String) -> Vector2i:
	_load_meta()
	if _textures.has(id):
		return Vector2i((_textures[id] as Texture2D).get_size())
	var sheet: Dictionary = _sheet.get(id, {})
	if sheet.get("size") is Array:
		return _vec2i(sheet["size"], Vector2i(8, 8))
	var art: Dictionary = _art.get(id, {})
	if art.get("size") is Array:
		return _vec2i(art["size"], Vector2i(8, 8))
	return _vec2i(SIZES.get(id, [8, 8]), Vector2i(8, 8))


## The sprite's pivot in art pixels (sprites.json `anchor`, else its align, else bottom_center).
static func anchor(id: String) -> Vector2i:
	_load_meta()
	var sheet: Dictionary = _sheet.get(id, {})
	if sheet.get("anchor") is Array:
		return _vec2i(sheet["anchor"], Vector2i.ZERO)
	var art: Dictionary = _art.get(id, {})
	var a: Variant = art.get("anchor", art.get("align", "bottom_center"))
	if a is Array:
		return _vec2i(a, Vector2i.ZERO)
	var f: Vector2 = ALIGN_ANCHORS.get(str(a), Vector2(0.5, 1))
	return Vector2i((Vector2(size_of(id)) * f).round())


## A part's rect inside the whole sprite (sprites.json, else art.json; Rect2i() when unknown).
static func part_rect(id: String, part_name: String) -> Rect2i:
	_load_meta()
	var parts: Variant = (_sheet.get(id, {}) as Dictionary).get("parts", {})
	if parts is Dictionary and (parts as Dictionary).has(part_name):
		var p: Variant = parts[part_name]
		var r: Variant = p.get("rect", []) if p is Dictionary else p
		if r is Array and (r as Array).size() == 4:
			return Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
	var art_parts: Variant = (_art.get(id, {}) as Dictionary).get("parts", {})
	if art_parts is Dictionary and (art_parts as Dictionary).has(part_name):
		var r2: Variant = art_parts[part_name]
		if r2 is Array and (r2 as Array).size() == 4:
			return Rect2i(int(r2[0]), int(r2[1]), int(r2[2]), int(r2[3]))
	return Rect2i()


## Every sprite id art.json lists (brief 3.3's when it can't be read).
static func ids() -> Array[String]:
	_load_meta()
	var out: Array[String] = []
	for k: String in _art.keys() if not _art.is_empty() else SIZES.keys():
		out.append(k)
	return out


static func clear_cache() -> void:
	_textures.clear()
	_sources.clear()
	_art.clear()
	_sheet.clear()
	_loaded = false


static func _load_meta() -> void:
	if _loaded:
		return
	_loaded = true
	var art: Variant = _read_json(ART_JSON)
	if art is Dictionary and (art as Dictionary).get("sprites") is Array:
		for e: Variant in art["sprites"]:
			if e is Dictionary and (e as Dictionary).has("id"):
				_art[str(e["id"])] = e
	var sheet: Variant = _read_json(SPRITES_JSON)
	if sheet is Dictionary:
		var entries: Variant = (sheet as Dictionary).get("sprites", sheet)
		if entries is Dictionary:
			for k: String in entries:
				if entries[k] is Dictionary:
					_sheet[k] = entries[k]
		elif entries is Array:
			for e: Variant in entries:
				if e is Dictionary and (e as Dictionary).has("id"):
					_sheet[str(e["id"])] = e


static func _has_static(script: Script, method: String) -> bool:
	for m: Dictionary in script.get_script_method_list():
		if str(m.get("name", "")) == method:
			return true
	return false


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func _vec2i(a: Variant, fallback: Vector2i) -> Vector2i:
	if a is Array and (a as Array).size() >= 2:
		return Vector2i(int(a[0]), int(a[1]))
	return fallback
