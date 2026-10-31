class_name SiegeBakeBank
extends RefCounted
## The baked Castellum Rotae v2 art (assets/siege/bake/, written by src/games/siege/art/bake.mjs):
## the world colour and depth images, the sprite atlases with their depth twins, and every
## dynamic part's frames from manifest.json. Loads once (`shared()`); gives frames by part name
## and index, the depth-test material per atlas, the key-ramp recolour table and the encodings.
##
## A frame is drawn with its top-left at floor(to_art(anchor)) - offset, where `anchor` is the
## part's anchor for parts baked where they stand (`place`), or any world point for moving
## sprites (enemies, effects, projectile pixels). Its pixels' depth is the anchor's depth plus
## the depth stored in the frame, and SiegeDepthBatch's shader hides them behind the world.

const DIR := "res://assets/siege/bake/"
const SHADER_PATH := "res://src/games/siege/view/v2/siege_depth_sprite.gdshader"
## The design frame in art pixels (game.json pixel_base). Frames, anchors and to_art() all measure
## from its top-left; the world image reaches beyond it (world_size, world_origin).
const ART_SIZE := Vector2i(960, 540)
## Rows of the ramp table: the four slots' powered ramps, then the idle materials.
const SLOT_ROWS := 4
const SHADE_LEVELS := 15

static var _shared: SiegeBakeBank = null

var ok: bool = false
var error: String = ""
var manifest: Dictionary = {}
var bake_version: int = 0
var world_texture: Texture2D = null
var world_depth_texture: Texture2D = null
var world_depth_image: Image = null
## The world image's size, and where the design frame's top-left lies in it: the bake's extra
## terrain round the frame, for a flex canvas (bake.mjs WORLD_MARGIN).
var world_size: Vector2i = ART_SIZE
var world_origin: Vector2i = Vector2i.ZERO
## Where the design frame's top-left lies on the canvas (SiegeViewMath.view_offset).
var view_offset: Vector2i = Vector2i.ZERO
var atlases: Array[Texture2D] = []
var depth_atlases: Array[Texture2D] = []
var ramp_texture: ImageTexture = null
var ramp_image: Image = null
var cam_k: float = 3.5
var cam_ox: float = 450.0
var cam_oy: float = 127.0
var world_offset: float = -400.0
var world_scale: float = 64.0
var sprite_zero: float = 32768.0
var sprite_scale: float = 256.0
var key_g0: int = 4
var key_step: int = 8
var key_count: int = 16
var halo_alpha: float = 0.45
var ramp_rows: PackedStringArray = PackedStringArray()

## Part name -> 7 ints per frame: atlas, x, y, w, h, anchor offset x, y (atlas -1: empty frame).
var _frames: Dictionary = {}
var _materials: Array[ShaderMaterial] = []
var _dir: String = DIR


## The bank of the committed bake, loaded on first use.
static func shared() -> SiegeBakeBank:
	if _shared == null:
		_shared = load_dir(DIR)
	return _shared


static func load_dir(dir: String) -> SiegeBakeBank:
	var b := SiegeBakeBank.new()
	b._load(dir)
	return b


func _load(dir: String) -> void:
	var text := FileAccess.get_file_as_string(dir.path_join("manifest.json"))
	_dir = dir
	var parsed: Variant = JSON.parse_string(text) if text != "" else null
	if not (parsed is Dictionary):
		error = "no manifest.json in %s" % dir
		push_warning("SiegeBakeBank: " + error)
		return
	manifest = parsed
	bake_version = int(manifest.get("bake_version", 0))
	var cam: Dictionary = manifest.get("camera", {})
	cam_k = float(cam.get("k", cam_k))
	cam_ox = float(cam.get("ox", cam_ox))
	cam_oy = float(cam.get("oy", cam_oy))
	var dep: Dictionary = manifest.get("depth", {})
	var wd: Dictionary = dep.get("world", {})
	world_offset = float(wd.get("offset", world_offset))
	world_scale = float(wd.get("scale", world_scale))
	var sd: Dictionary = dep.get("sprite", {})
	sprite_zero = float(sd.get("zero", sprite_zero))
	sprite_scale = float(sd.get("scale", sprite_scale))
	var key: Dictionary = manifest.get("key", {})
	key_g0 = int(key.get("g0", key_g0))
	key_step = int(key.get("step", key_step))
	key_count = int(key.get("count", key_count))
	halo_alpha = float(manifest.get("halo_alpha", halo_alpha))
	var world: Dictionary = manifest.get("world", {})
	var ws: Array = world.get("size", [ART_SIZE.x, ART_SIZE.y])
	var wo: Array = world.get("origin", [0, 0])
	world_size = Vector2i(int(ws[0]), int(ws[1]))
	world_origin = Vector2i(int(wo[0]), int(wo[1]))
	world_texture = _tex(dir.path_join(str(world.get("color", "world.png"))))
	var depth_path := dir.path_join(str(world.get("depth", "world_depth.png")))
	world_depth_texture = _tex(depth_path)
	world_depth_image = image_of(world_depth_texture, depth_path)
	for a: Variant in manifest.get("atlases", []):
		var ad: Dictionary = a
		atlases.append(_tex(dir.path_join(str(ad.get("color", "")))))
		depth_atlases.append(_tex(dir.path_join(str(ad.get("depth", "")))))
	for name: String in manifest.get("parts", {}) as Dictionary:
		var fr := PackedInt32Array()
		for f: Variant in (manifest["parts"][name] as Dictionary).get("frames", []):
			if f is Array and (f as Array).size() == 7:
				for v: Variant in f:
					fr.append(int(v))
			else:
				fr.append_array(PackedInt32Array([-1, 0, 0, 0, 0, 0, 0]))
		_frames[name] = fr
	_build_ramps()
	ok = world_texture != null and world_depth_image != null and not atlases.has(null)
	if not ok:
		error = "bake textures missing in %s" % dir
		push_warning("SiegeBakeBank: " + error)


func _tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## A texture's pixels: from the GPU copy, or (headless, where the dummy renderer keeps none)
## from the PNG itself.
static func image_of(tex: Texture2D, png_path: String) -> Image:
	var img: Image = tex.get_image() if tex != null else null
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		return img
	if FileAccess.file_exists(png_path):
		img = Image.load_from_file(ProjectSettings.globalize_path(png_path))
		if img != null and not img.is_empty():
			img.convert(Image.FORMAT_RGBA8)
			return img
	return null


## Atlas i's colour (or depth) pixels, for tests and tools.
func atlas_image(i: int, depth: bool = false) -> Image:
	var a: Dictionary = (manifest.get("atlases", []) as Array)[i]
	var path := _dir.path_join(str(a.get("depth" if depth else "color", "")))
	return image_of(depth_atlases[i] if depth else atlases[i], path)


func _build_ramps() -> void:
	for r: Variant in manifest.get("ramp_rows", []):
		ramp_rows.append(str(r))
	var ramps: Dictionary = manifest.get("ramps", {})
	ramp_image = Image.create(
		maxi(key_count, 1), maxi(ramp_rows.size(), 1), false, Image.FORMAT_RGBA8
	)
	for y in ramp_rows.size():
		var row: Array = ramps.get(ramp_rows[y], [])
		for x in mini(row.size(), key_count):
			var c: Array = row[x]
			ramp_image.set_pixel(x, y, Color8(int(c[0]), int(c[1]), int(c[2])))
	ramp_texture = ImageTexture.create_from_image(ramp_image)


# --- Parts and frames ----------------------------------------------------------------------------


func has_part(part: String) -> bool:
	return _frames.has(part)


func part_names() -> PackedStringArray:
	return PackedStringArray(_frames.keys())


func part_info(part: String) -> Dictionary:
	return (manifest.get("parts", {}) as Dictionary).get(part, {})


func frame_count(part: String) -> int:
	return (_frames.get(part, PackedInt32Array()) as PackedInt32Array).size() / 7


## The 7 ints of frame i (atlas, x, y, w, h, offset x, offset y); atlas -1 when it is empty.
func frame_data(part: String, i: int) -> PackedInt32Array:
	var fr: PackedInt32Array = _frames.get(part, PackedInt32Array())
	if i < 0 or i * 7 + 7 > fr.size():
		return PackedInt32Array([-1, 0, 0, 0, 0, 0, 0])
	return fr.slice(i * 7, i * 7 + 7)


## Frame i as {atlas, rect: Rect2i (atlas pixels), offset: Vector2i (anchor pixel in the rect)}.
func frame(part: String, i: int) -> Dictionary:
	var f := frame_data(part, i)
	return {"atlas": f[0], "rect": Rect2i(f[1], f[2], f[3], f[4]), "offset": Vector2i(f[5], f[6])}


## The packed frames of a part (7 ints each), for drawers that look many up per frame.
func frames_of(part: String) -> PackedInt32Array:
	return _frames.get(part, PackedInt32Array())


func anchor(part: String) -> Vector3:
	var a: Array = part_info(part).get("anchor", [0, 0, 0])
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## Anchors of the extra positions a part's frames were baked at (the wheel walkers).
func anchors(part: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for a: Variant in part_info(part).get("anchors", []):
		out.append(Vector3(float(a[0]), float(a[1]), float(a[2])))
	return out


func layout(part: String) -> Dictionary:
	return part_info(part).get("layout", {})


## The ramp row for a part: the slot's when a rider drives it (slot >= 0), else its idle material.
func ramp_row_for(part: String, slot: int) -> int:
	if slot >= 0 and slot < SLOT_ROWS:
		return slot
	var idle: Variant = part_info(part).get("idle")
	var row := ramp_rows.find(str(idle)) if idle != null else -1
	return row if row >= 0 else 0


## The shared depth-test material for atlas i.
func material(i: int) -> ShaderMaterial:
	while _materials.size() < atlases.size():
		var m := ShaderMaterial.new()
		m.shader = load(SHADER_PATH) as Shader
		var k := _materials.size()
		m.set_shader_parameter("depth_atlas", depth_atlases[k])
		m.set_shader_parameter("world_depth", world_depth_texture)
		m.set_shader_parameter("ramps", ramp_texture)
		m.set_shader_parameter("world_offset", world_offset)
		m.set_shader_parameter("world_scale", world_scale)
		m.set_shader_parameter("sprite_zero", sprite_zero)
		m.set_shader_parameter("sprite_scale", sprite_scale)
		m.set_shader_parameter("key_g0", float(key_g0))
		m.set_shader_parameter("key_step", float(key_step))
		m.set_shader_parameter("art_size", Vector2(world_size))
		m.set_shader_parameter("art_origin", Vector2(view_offset - world_origin))
		_materials.append(m)
	return _materials[i] if i >= 0 and i < _materials.size() else null


## Puts the design frame's top-left at `offset` on the canvas: the depth test follows.
func set_view_offset(offset: Vector2i) -> void:
	view_offset = offset
	for m in _materials:
		m.set_shader_parameter("art_origin", Vector2(view_offset - world_origin))


# --- Art space and encodings ---------------------------------------------------------------------


func to_art(p: Vector3) -> Vector2:
	return Vector2((p.x - p.y) * cam_k + cam_ox, (p.x + p.y) * cam_k * 0.5 - p.z * cam_k + cam_oy)


## The art pixel a world point falls in.
func art_pixel(p: Vector3) -> Vector2i:
	var a := to_art(p)
	return Vector2i(floori(a.x), floori(a.y))


static func depth_of(p: Vector3) -> float:
	return p.x + p.y + p.z


func encode_world_depth(d: float) -> int:
	return clampi(roundi((d - world_offset) * world_scale), 1, 65535)


func decode_world_depth(v: int) -> float:
	return -1.0e9 if v <= 0 else float(v) / world_scale + world_offset


func encode_sprite_depth(rel: float) -> int:
	return clampi(roundi(rel * sprite_scale) + int(sprite_zero), 0, 65535)


func decode_sprite_depth(v: int) -> float:
	return (float(v) - sprite_zero) / sprite_scale


static func rg16(c: Color) -> int:
	return c.r8 * 256 + c.g8


## The modulate colour a drawer passes with a sprite: anchor depth in R and G (world encoding),
## ramp row * 16 + shade level in B, opacity in A.
func pack_modulate(anchor_depth: float, row: int, shade: float, alpha: float) -> Color:
	var v := encode_world_depth(anchor_depth)
	var s := clampi(roundi(shade * SHADE_LEVELS), 0, SHADE_LEVELS)
	return Color8(
		v >> 8, v & 255, clampi(row, 0, 15) * 16 + s, clampi(roundi(alpha * 255.0), 0, 255)
	)


## The baked world's depth at an art pixel (-1e9 for the sky or off the picture).
func world_depth_at(px: Vector2i) -> float:
	var q := px + world_origin
	if world_depth_image == null or not Rect2i(Vector2i.ZERO, world_size).has_point(q):
		return -1.0e9
	return decode_world_depth(rg16(world_depth_image.get_pixelv(q)))


## 1 where the world surface at an art pixel is in the sun, 0 in shadow.
func sun_at(px: Vector2i) -> float:
	var q := px + world_origin
	if world_depth_image == null or not Rect2i(Vector2i.ZERO, world_size).has_point(q):
		return 1.0
	return 1.0 if world_depth_image.get_pixelv(q).b8 > 127 else 0.0


## The key index of a colour, or -1 when it is not a key colour.
func key_index(c: Color) -> int:
	if c.r8 < 251 or c.b8 < 251 or c.a8 < 250:
		return -1
	var idx := roundi(float(c.g8 - key_g0) / float(key_step))
	return idx if idx >= 0 and idx < key_count and c.g8 == key_g0 + key_step * idx else -1


func key_color(idx: int) -> Color:
	return Color8(255, key_g0 + key_step * idx, 255)


## The shader's recolour on the CPU: a key colour becomes ramp `row`'s entry, others are kept.
func recolor(c: Color, row: int) -> Color:
	var idx := key_index(c)
	if idx < 0:
		return c
	var r := ramp_image.get_pixel(idx, clampi(row, 0, ramp_image.get_height() - 1))
	return Color(r.r, r.g, r.b, c.a)
