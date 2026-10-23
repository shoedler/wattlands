class_name FishingSprites
extends RefCounted
## Loads Turbo Reel's sprites: res://assets/fishing/sprites/<id>.png holds a sprite's frames side
## by side; sprites.json gives each one's frame size, frame count and anchor (written by
## tools/fishing_write_sprites.gd from FishingArtGrids). Textures and frames are cached.

const DIR := "res://assets/fishing/sprites"
const INDEX := "res://assets/fishing/sprites/sprites.json"

static var _meta: Dictionary = {}
static var _strips: Dictionary = {}
static var _frames: Dictionary = {}


## Frame `k` of sprite `id` (wraps; null when the sprite is missing).
static func frame(id: String, k: int = 0) -> Texture2D:
	var all := frames(id)
	if all.is_empty():
		return null
	return all[posmod(k, all.size())]


## Every frame of `id` (cached AtlasTextures over the strip; [] when the sprite is missing).
static func frames(id: String) -> Array[Texture2D]:
	if _frames.has(id):
		return _frames[id]
	var out: Array[Texture2D] = []
	var strip := texture(id)
	if strip != null:
		var size := size_of(id)
		var n := maxi(int(meta(id).get("frames", 1)), 1)
		for k in n:
			var a := AtlasTexture.new()
			a.atlas = strip
			a.region = Rect2(k * size.x, 0, size.x, size.y)
			out.append(a)
	_frames[id] = out
	return out


## The whole strip of `id` (null and a warning when its PNG is missing).
static func texture(id: String) -> Texture2D:
	if _strips.has(id):
		return _strips[id]
	var path := DIR.path_join(id + ".png")
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		push_warning("FishingSprites: no sprite %s" % id)
	_strips[id] = tex
	return tex


## Frames in `id` (0 when missing).
static func count(id: String) -> int:
	return frames(id).size()


## One frame's size in art pixels.
static func size_of(id: String) -> Vector2i:
	var s: Variant = meta(id).get("size", [1, 1])
	return (
		Vector2i(int(s[0]), int(s[1])) if s is Array and (s as Array).size() == 2 else Vector2i.ONE
	)


## The sprite's pivot in art pixels (fish: the mouth).
static func anchor(id: String) -> Vector2i:
	var a: Variant = meta(id).get("anchor", [0, 0])
	return (
		Vector2i(int(a[0]), int(a[1])) if a is Array and (a as Array).size() == 2 else Vector2i.ZERO
	)


## sprites.json's entry for `id` ({} when unknown).
static func meta(id: String) -> Dictionary:
	if _meta.is_empty() and FileAccess.file_exists(INDEX):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
		if d is Dictionary and (d as Dictionary).get("sprites") is Dictionary:
			_meta = d["sprites"]
	return _meta.get(id, {})


## Every sprite id in sprites.json.
static func ids() -> Array[String]:
	meta("")
	var out: Array[String] = []
	out.assign(_meta.keys())
	return out


static func clear_cache() -> void:
	_meta.clear()
	_strips.clear()
	_frames.clear()
