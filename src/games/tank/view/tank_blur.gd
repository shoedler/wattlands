class_name TankBlur
extends RefCounted
## Fake depth of field for the diorama (brief 3, "Depth of field"): the Compatibility renderer has
## no depth-of-field post effect, so every plane behind or in front of the tank's is blurred ONCE
## at load into a cached texture and tinted toward the haze colour. Nothing here runs per frame.
##
## The blur is separable: the plane is resampled down by `down` (a cheap box filter in the engine),
## an optional horizontal and vertical box pass of `passes` x radius `box_r` runs on that tiny image
## (at most ~8 000 pixels, so the GDScript loops cost a few milliseconds), the tint toward the haze
## colour is applied there too, and the result is resampled back up with a cubic filter. The
## effective blur is about `down` x (1 + box_r) x 1.2 art px, see PRESETS.

## Per-plane presets: down (resample factor), box_r (extra box radius at the small size, 0 for none),
## passes (box passes per axis), haze (0..1 toward the haze colour), darken (0..1 toward black).
## The blur radii are recorded in docs/decisions/tank.md by the lead (view report).
const PRESETS := {
	"sky": {"down": 3, "box_r": 1, "passes": 1, "haze": 0.12, "darken": 0.0},
	"hills": {"down": 3, "box_r": 1, "passes": 1, "haze": 0.40, "darken": 0.0},
	"near": {"down": 2, "box_r": 0, "passes": 1, "haze": 0.18, "darken": 0.0},
	"ground": {"down": 1, "box_r": 0, "passes": 1, "haze": 0.0, "darken": 0.08},
	"debris": {"down": 4, "box_r": 2, "passes": 2, "haze": 0.0, "darken": 0.55},
	"soft": {"down": 2, "box_r": 0, "passes": 1, "haze": 0.0, "darken": 0.0},
}

static var _cache: Dictionary = {}
static var builds: int = 0


## The cached blurred and hazed texture of sprite `id` for `preset` (a PRESETS key). Built once.
static func plane(id: String, preset: String) -> Texture2D:
	var key := "%s|%s" % [id, preset]
	if _cache.has(key):
		return _cache[key]
	var src := TankPlaceholderArt.texture(id)
	var p: Dictionary = PRESETS.get(preset, PRESETS["soft"])
	var img := blurred_image(src.get_image(), p, TankPalette.HAZE)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	builds += 1
	return tex


static func clear_cache() -> void:
	_cache.clear()


static func cached_count() -> int:
	return _cache.size()


## A blurred, hazed copy of `src` (same size) following a PRESETS entry.
static func blurred_image(src: Image, preset: Dictionary, haze: Color) -> Image:
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var down := maxi(1, int(preset.get("down", 1)))
	var box_r := maxi(0, int(preset.get("box_r", 0)))
	var passes := maxi(1, int(preset.get("passes", 1)))
	var haze_k := clampf(float(preset.get("haze", 0.0)), 0.0, 1.0)
	var dark_k := clampf(float(preset.get("darken", 0.0)), 0.0, 1.0)
	if down > 1 or box_r > 0:
		img.fix_alpha_edges()
	var sw := maxi(1, w / down)
	var sh := maxi(1, h / down)
	if down > 1:
		img.resize(sw, sh, Image.INTERPOLATE_BILINEAR)
	if box_r > 0:
		_box_blur(img, box_r, passes)
	if haze_k > 0.0 or dark_k > 0.0:
		_tint(img, haze, haze_k, dark_k)
	if down > 1:
		img.resize(w, h, Image.INTERPOLATE_CUBIC)
	return img


## Separable box blur (horizontal then vertical, `passes` times) in place on a small image. Edges
## repeat their last pixel, so a mirror-tiled strip keeps matching seams.
static func _box_blur(img: Image, r: int, passes: int) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var n := w * h * 4
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		a[i] = data[i]
	var b := PackedFloat32Array()
	b.resize(n)
	for _p in passes:
		_pass_h(a, b, w, h, r)
		_pass_v(b, a, w, h, r)
	for i in n:
		data[i] = clampi(roundi(a[i]), 0, 255)
	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)


static func _pass_h(
	src: PackedFloat32Array, dst: PackedFloat32Array, w: int, h: int, r: int
) -> void:
	var inv := 1.0 / float(2 * r + 1)
	for y in h:
		var row := y * w * 4
		for c in 4:
			var sum := 0.0
			for k in range(-r, r + 1):
				sum += src[row + clampi(k, 0, w - 1) * 4 + c]
			for x in w:
				dst[row + x * 4 + c] = sum * inv
				var add := x + r + 1
				if add > w - 1:
					add = w - 1
				var rem := x - r
				if rem < 0:
					rem = 0
				sum += src[row + add * 4 + c] - src[row + rem * 4 + c]


static func _pass_v(
	src: PackedFloat32Array, dst: PackedFloat32Array, w: int, h: int, r: int
) -> void:
	var inv := 1.0 / float(2 * r + 1)
	var stride := w * 4
	for x in w:
		for c in 4:
			var col := x * 4 + c
			var sum := 0.0
			for k in range(-r, r + 1):
				sum += src[clampi(k, 0, h - 1) * stride + col]
			for y in h:
				dst[y * stride + col] = sum * inv
				var add := y + r + 1
				if add > h - 1:
					add = h - 1
				var rem := y - r
				if rem < 0:
					rem = 0
				sum += src[add * stride + col] - src[rem * stride + col]


## Lerps every pixel's colour toward `haze` by `haze_k` and toward black by `dark_k` (alpha kept).
static func _tint(img: Image, haze: Color, haze_k: float, dark_k: float) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var hr := haze.r * 255.0 * haze_k
	var hg := haze.g * 255.0 * haze_k
	var hb := haze.b * 255.0 * haze_k
	var keep := (1.0 - haze_k) * (1.0 - dark_k)
	var lift := 1.0 - dark_k
	var n := w * h
	for i in n:
		var o := i * 4
		data[o] = clampi(roundi(data[o] * keep + hr * lift), 0, 255)
		data[o + 1] = clampi(roundi(data[o + 1] * keep + hg * lift), 0, 255)
		data[o + 2] = clampi(roundi(data[o + 2] * keep + hb * lift), 0, 255)
	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)
