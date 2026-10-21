class_name ArtPixelate
extends RefCounted
## Pure pixelation for tools/art/pixelate.gd (BRIEF 3.10, docs/ART_PIPELINE.md).
##
## For each sprite of assets/<id>/art.json it takes only the result the manifest marks `selected`,
## trims transparent margins and, without ever stretching:
## - fits a transparent sprite inside `size` keeping its aspect, padded with transparency toward `align`;
## - scales an opaque sprite to cover `size` and centre-crops it;
## - scales a `tile: true` sprite to the sprite's height and repeats it across the width, alternating
##   flipped copies with `mirror: true`.
## Then it downsamples with area averaging (premultiplied alpha, sRGB values), thresholds alpha to fully
## opaque or fully transparent, quantizes every opaque pixel to the nearest palette color in Oklab (no
## dithering unless `dither: "ordered"`), cuts `parts` and writes PNGs. Same inputs, same bytes.
##
## Outputs (under <root>/assets/<id>/sprites/): `<sprite id>.png`, one `<sprite id>__<part>.png` per
## part, and `sprites.json` (size, anchor, parts and source request of every sprite).

## Pixels with alpha at or above this (0-255) count as content when trimming margins.
const TRIM_ALPHA_MIN: int = 16
## Output pixels with averaged alpha at or above this become opaque; the rest transparent.
const ALPHA_THRESHOLD: float = 0.5
## Ordered dithering moves each channel by up to half of this (sRGB 0-255 units) before quantizing.
const DITHER_SPREAD: float = 32.0
const POINTS: Array[String] = [
	"top_left",
	"top_center",
	"top_right",
	"center_left",
	"center",
	"center_right",
	"bottom_left",
	"bottom_center",
	"bottom_right",
]
const BACKGROUNDS: Array[String] = ["transparent", "opaque"]
const DITHERS: Array[String] = ["none", "ordered"]
const MAX_PALETTE: int = 32
const PART_SEPARATOR: String = "__"
const INDEX_FILE: String = "sprites.json"
## art.json's default `endpoint` (BRIEF 3.10), as in tools/art/lib/config.mjs.
const DEFAULT_ENDPOINT: String = "openai/gpt-image-2.5/sunburst/text-to-image"

## How sprite PNGs get the pixel import preset (filter off, mipmaps off, lossless; OWNERSHIP C36):
## IMPORT_PROJECT_DEFAULTS (the default, the one documented mechanism) writes plain PNGs and relies
## on project.godot's [importer_defaults] texture (lossless, no mipmaps), which run_game checks
## first through world-kits' PixelImportPreset.check_project_defaults(); filtering is per
## CanvasItem (PixelViewport draws nearest). IMPORT_WRITE_FILE (opt-in, for a sprite folder that
## must pin the preset) also writes a `.import` with the preset next to each PNG that has none and
## fixes the preset keys of one that does, keeping its uid (docs/decisions/art-pipeline.md).
const IMPORT_WRITE_FILE: int = 0
const IMPORT_PROJECT_DEFAULTS: int = 1
static var import_preset_mode: int = IMPORT_PROJECT_DEFAULTS

## The preset's [params] in a sprite's .import file.
const IMPORT_PARAMS: Dictionary = {
	"compress/mode": 0,
	"compress/high_quality": false,
	"compress/lossy_quality": 0.7,
	"mipmaps/generate": false,
	"mipmaps/limit": -1,
	"process/fix_alpha_border": true,
	"process/premult_alpha": false,
	"process/size_limit": 0,
	"detect_3d/compress_to": 0,
}


## A fixed palette with Oklab coordinates and a nearest-color cache.
class Palette:
	extends RefCounted

	var rgb: PackedInt32Array = PackedInt32Array()
	var lab: Array[Vector3] = []
	var _cache: Dictionary = {}

	## Index of the palette color nearest to 0xRRGGBB in Oklab (ties: the lower index).
	func nearest(rgb24: int) -> int:
		if _cache.has(rgb24):
			return int(_cache[rgb24])
		var p: Vector3 = ArtPixelate.rgb8_to_oklab(
			(rgb24 >> 16) & 0xff, (rgb24 >> 8) & 0xff, rgb24 & 0xff
		)
		var best: int = 0
		var best_d: float = INF
		for i: int in lab.size():
			var d: float = p.distance_squared_to(lab[i])
			if d < best_d:
				best_d = d
				best = i
		_cache[rgb24] = best
		return best

	func size() -> int:
		return rgb.size()


# ---------------------------------------------------------------- colour


static func srgb_to_linear(c: float) -> float:
	if c <= 0.04045:
		return c / 12.92
	return pow((c + 0.055) / 1.055, 2.4)


## sRGB 8-bit to Oklab (L, a, b), per Björn Ottosson's reference matrices.
static func rgb8_to_oklab(r: int, g: int, b: int) -> Vector3:
	var lr: float = srgb_to_linear(r / 255.0)
	var lg: float = srgb_to_linear(g / 255.0)
	var lb: float = srgb_to_linear(b / 255.0)
	var l: float = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb
	var m: float = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb
	var s: float = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb
	var l_cbrt: float = pow(maxf(l, 0.0), 1.0 / 3.0)
	var m_cbrt: float = pow(maxf(m, 0.0), 1.0 / 3.0)
	var s_cbrt: float = pow(maxf(s, 0.0), 1.0 / 3.0)
	return Vector3(
		0.2104542553 * l_cbrt + 0.7936177850 * m_cbrt - 0.0040720468 * s_cbrt,
		1.9779984951 * l_cbrt - 2.4285922050 * m_cbrt + 0.4505937099 * s_cbrt,
		0.0259040371 * l_cbrt + 0.7827717662 * m_cbrt - 0.8086757660 * s_cbrt
	)


static func is_hex_color(v: Variant) -> bool:
	if typeof(v) != TYPE_STRING:
		return false
	var s: String = v
	return s.length() == 7 and s.begins_with("#") and s.substr(1).is_valid_hex_number(false)


## 0xRRGGBB from "#rrggbb".
static func hex_to_rgb24(hex: String) -> int:
	return hex.substr(1).hex_to_int()


static func make_palette(hexes: Array) -> Palette:
	var p: Palette = Palette.new()
	for h: Variant in hexes:
		var c: int = hex_to_rgb24(str(h))
		p.rgb.append(c)
		p.lab.append(rgb8_to_oklab((c >> 16) & 0xff, (c >> 8) & 0xff, c & 0xff))
	return p


## A 4x4 Bayer threshold in [0, 1).
static func bayer4(x: int, y: int) -> float:
	const M: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
	return (M[(y & 3) * 4 + (x & 3)] + 0.5) / 16.0


# ---------------------------------------------------------------- geometry


## The bounding rect of pixels with alpha >= alpha_min, or Rect2i() when there are none.
static func trim_rect(img: Image, alpha_min: int = TRIM_ALPHA_MIN) -> Rect2i:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var data: PackedByteArray = _rgba8(img).get_data()
	var top: int = -1
	for y: int in h:
		if _row_has(data, w, y, 0, w, alpha_min):
			top = y
			break
	if top < 0:
		return Rect2i()
	var bottom: int = top
	for y: int in range(h - 1, top - 1, -1):
		if _row_has(data, w, y, 0, w, alpha_min):
			bottom = y
			break
	var left: int = 0
	for x: int in w:
		if _col_has(data, w, x, top, bottom + 1, alpha_min):
			left = x
			break
	var right: int = left
	for x: int in range(w - 1, left - 1, -1):
		if _col_has(data, w, x, top, bottom + 1, alpha_min):
			right = x
			break
	return Rect2i(left, top, right - left + 1, bottom - top + 1)


static func _row_has(
	data: PackedByteArray, w: int, y: int, x0: int, x1: int, alpha_min: int
) -> bool:
	var base: int = y * w * 4 + 3
	for x: int in range(x0, x1):
		if data[base + x * 4] >= alpha_min:
			return true
	return false


static func _col_has(
	data: PackedByteArray, w: int, x: int, y0: int, y1: int, alpha_min: int
) -> bool:
	for y: int in range(y0, y1):
		if data[(y * w + x) * 4 + 3] >= alpha_min:
			return true
	return false


## Fractions (0, 0.5 or 1) of a named point: x from left/center/right, y from top/center/bottom.
static func point_fraction(name: String) -> Vector2:
	var v: String = "center"
	var h: String = "center"
	if name != "center":
		var i: int = name.find("_")
		v = name.substr(0, i)
		h = name.substr(i + 1)
	var fx: float = 0.0 if h == "left" else (1.0 if h == "right" else 0.5)
	var fy: float = 0.0 if v == "top" else (1.0 if v == "bottom" else 0.5)
	return Vector2(fx, fy)


## How a transparent sprite's trimmed source `src` maps into `dst` (fit inside, keep aspect, align).
## Returns {"scale", "origin" (source coordinate of output pixel edge 0,0), "clip" (Rect2, source),
## "content" (Rect2, output)}. Output x maps to source u = origin.x + x / scale.
static func fit_mapping(src: Rect2i, dst: Vector2i, align: String) -> Dictionary:
	var scale: float = minf(float(dst.x) / src.size.x, float(dst.y) / src.size.y)
	var cw: float = src.size.x * scale
	var ch: float = src.size.y * scale
	var f: Vector2 = point_fraction(align)
	var ox: float = _align_offset(dst.x - cw, f.x)
	var oy: float = _align_offset(dst.y - ch, f.y)
	return {
		"scale": scale,
		"origin": Vector2(src.position.x - ox / scale, src.position.y - oy / scale),
		"clip": Rect2(src),
		"content": Rect2(ox, oy, cw, ch),
	}


static func _align_offset(room: float, fraction: float) -> float:
	if fraction <= 0.0:
		return 0.0
	if fraction >= 1.0:
		return room
	return floorf(room * 0.5 + 0.5)


## An opaque sprite: scaled to cover `dst` and centre-cropped.
static func cover_mapping(src: Rect2i, dst: Vector2i) -> Dictionary:
	var scale: float = maxf(float(dst.x) / src.size.x, float(dst.y) / src.size.y)
	var vis: Vector2 = Vector2(dst.x / scale, dst.y / scale)
	return {
		"scale": scale,
		"origin":
		Vector2(
			src.position.x + (src.size.x - vis.x) * 0.5, src.position.y + (src.size.y - vis.y) * 0.5
		),
		"clip": Rect2(src),
		"content": Rect2(0, 0, dst.x, dst.y),
	}


## A tile sprite at source resolution: the trimmed segment repeated across the width `dst` needs at
## the sprite's height, every second copy flipped when `mirror`.
static func build_tile_strip(img: Image, src: Rect2i, dst: Vector2i, mirror: bool) -> Image:
	var seg: Image = _rgba8(img).get_region(src)
	var flipped: Image = seg.duplicate() as Image
	flipped.flip_x()
	var scale: float = float(dst.y) / src.size.y
	var strip_w: int = maxi(1, ceili(dst.x / scale - 1e-6))
	var strip: Image = Image.create_empty(strip_w, src.size.y, false, Image.FORMAT_RGBA8)
	var x: int = 0
	var k: int = 0
	while x < strip_w:
		var piece: Image = flipped if (mirror and k % 2 == 1) else seg
		strip.blit_rect(
			piece, Rect2i(0, 0, mini(src.size.x, strip_w - x), src.size.y), Vector2i(x, 0)
		)
		x += src.size.x
		k += 1
	return strip


# ---------------------------------------------------------------- resampling


## Area weights along one axis: output pixel o covers source [origin + o * step, origin + (o+1) * step)
## clipped to [lo, hi). Returns [offsets (n_out + 1), source indices, weights (overlap / step)].
static func axis_weights(n_out: int, origin: float, step: float, lo: float, hi: float) -> Array:
	var offsets: PackedInt32Array = PackedInt32Array()
	offsets.resize(n_out + 1)
	var idx: PackedInt32Array = PackedInt32Array()
	var w: PackedFloat32Array = PackedFloat32Array()
	for o: int in n_out:
		offsets[o] = idx.size()
		var a: float = maxf(origin + o * step, lo)
		var b: float = minf(origin + (o + 1) * step, hi)
		if b <= a:
			continue
		for i: int in range(floori(a), ceili(b)):
			var ov: float = minf(b, i + 1.0) - maxf(a, float(i))
			if ov > 0.0:
				idx.append(i)
				w.append(ov / step)
	offsets[n_out] = idx.size()
	return [offsets, idx, w]


## Area-averaged resample of `img` into `dst` pixels: output (x, y) integrates the source over
## [origin + (x, y) / scale, origin + (x+1, y+1) / scale) clipped to `clip` (outside counts as
## transparent). Returns premultiplied RGBA per pixel: r, g, b in 0-255 sRGB units times alpha, and
## alpha in 0-1.
static func area_resample(
	img: Image, origin: Vector2, scale: float, clip: Rect2, dst: Vector2i
) -> PackedFloat32Array:
	var src: Image = _rgba8(img)
	var sw: int = src.get_width()
	var sh: int = src.get_height()
	var lo: Vector2 = Vector2(maxf(clip.position.x, 0.0), maxf(clip.position.y, 0.0))
	var hi: Vector2 = Vector2(minf(clip.end.x, sw), minf(clip.end.y, sh))
	var step: float = 1.0 / scale
	var wx: Array = axis_weights(dst.x, origin.x, step, lo.x, hi.x)
	var wy: Array = axis_weights(dst.y, origin.y, step, lo.y, hi.y)
	var xo: PackedInt32Array = wx[0]
	var xi: PackedInt32Array = wx[1]
	var xw: PackedFloat32Array = wx[2]
	var yo: PackedInt32Array = wy[0]
	var yi: PackedInt32Array = wy[1]
	var yw: PackedFloat32Array = wy[2]
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(dst.x * dst.y * 4)
	if yi.is_empty() or xi.is_empty():
		return out
	var ymin: int = yi[0]
	var ymax: int = yi[0]
	for v: int in yi:
		ymin = mini(ymin, v)
		ymax = maxi(ymax, v)
	var data: PackedByteArray = src.get_data()
	var nx: int = dst.x
	var tmp: PackedFloat32Array = PackedFloat32Array()
	tmp.resize((ymax - ymin + 1) * nx * 4)
	for y: int in range(ymin, ymax + 1):
		var rb: int = y * sw * 4
		var tb: int = (y - ymin) * nx * 4
		for o: int in nx:
			var r: float = 0.0
			var g: float = 0.0
			var b: float = 0.0
			var a: float = 0.0
			for k: int in range(xo[o], xo[o + 1]):
				var p: int = rb + xi[k] * 4
				var wa: float = xw[k] * data[p + 3] / 255.0
				r += wa * data[p]
				g += wa * data[p + 1]
				b += wa * data[p + 2]
				a += wa
			var t: int = tb + o * 4
			tmp[t] = r
			tmp[t + 1] = g
			tmp[t + 2] = b
			tmp[t + 3] = a
	for oy: int in dst.y:
		for ox: int in nx:
			var r: float = 0.0
			var g: float = 0.0
			var b: float = 0.0
			var a: float = 0.0
			for k: int in range(yo[oy], yo[oy + 1]):
				var t: int = ((yi[k] - ymin) * nx + ox) * 4
				var wv: float = yw[k]
				r += wv * tmp[t]
				g += wv * tmp[t + 1]
				b += wv * tmp[t + 2]
				a += wv * tmp[t + 3]
			var q: int = (oy * nx + ox) * 4
			out[q] = r
			out[q + 1] = g
			out[q + 2] = b
			out[q + 3] = a
	return out


## Thresholds alpha and quantizes premultiplied pixels to the palette: every output pixel is a
## palette color at alpha 255, or (0, 0, 0, 0).
static func quantize(
	premult: PackedFloat32Array,
	size: Vector2i,
	palette: Palette,
	dither: String = "none",
	alpha_threshold: float = ALPHA_THRESHOLD
) -> Image:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(size.x * size.y * 4)
	var ordered: bool = dither == "ordered"
	for y: int in size.y:
		for x: int in size.x:
			var q: int = (y * size.x + x) * 4
			var a: float = premult[q + 3]
			if a < alpha_threshold or a <= 0.0:
				continue
			var off: float = (bayer4(x, y) - 0.5) * DITHER_SPREAD if ordered else 0.0
			var r: int = clampi(roundi(premult[q] / a + off), 0, 255)
			var g: int = clampi(roundi(premult[q + 1] / a + off), 0, 255)
			var b: int = clampi(roundi(premult[q + 2] / a + off), 0, 255)
			var c: int = palette.rgb[palette.nearest((r << 16) | (g << 8) | b)]
			bytes[q] = (c >> 16) & 0xff
			bytes[q + 1] = (c >> 8) & 0xff
			bytes[q + 2] = c & 0xff
			bytes[q + 3] = 255
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, bytes)


# ---------------------------------------------------------------- one sprite


## Processes one raw result into a sprite. `spec` holds "size" (Vector2i), "background", "align",
## "tile", "mirror" and "dither" (normalize_sprite() fills them).
static func process_sprite(raw: Image, spec: Dictionary, palette: Palette) -> Image:
	var img: Image = _rgba8(raw)
	var size: Vector2i = spec["size"]
	var trim: Rect2i = trim_rect(img)
	if trim.size.x <= 0 or trim.size.y <= 0:
		return Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var premult: PackedFloat32Array
	if bool(spec.get("tile", false)):
		var strip: Image = build_tile_strip(img, trim, size, bool(spec.get("mirror", false)))
		var scale: float = float(size.y) / trim.size.y
		premult = area_resample(
			strip, Vector2.ZERO, scale, Rect2(0, 0, size.x / scale, trim.size.y), size
		)
	elif str(spec.get("background", "transparent")) == "opaque":
		var m: Dictionary = cover_mapping(trim, size)
		premult = area_resample(img, m["origin"], m["scale"], m["clip"], size)
	else:
		var m: Dictionary = fit_mapping(trim, size, str(spec.get("align", "bottom_center")))
		premult = area_resample(img, m["origin"], m["scale"], m["clip"], size)
	return quantize(premult, size, palette, str(spec.get("dither", "none")))


## A part of a finished sprite.
static func cut_part(img: Image, rect: Rect2i) -> Image:
	return img.get_region(rect)


## The anchor in art pixels: a named point of the sprite rect, or [x, y] as given.
static func anchor_point(anchor: Variant, size: Vector2i) -> Vector2:
	if typeof(anchor) == TYPE_ARRAY:
		var arr: Array = anchor
		return Vector2(float(arr[0]), float(arr[1]))
	var f: Vector2 = point_fraction(str(anchor))
	return Vector2(size.x * f.x, size.y * f.y)


# ---------------------------------------------------------------- art.json


static func _is_int(v: Variant) -> bool:
	return (
		(typeof(v) == TYPE_INT)
		or (typeof(v) == TYPE_FLOAT and is_finite(float(v)) and float(v) == floorf(float(v)))
	)


static func _is_id(v: Variant) -> bool:
	if typeof(v) != TYPE_STRING:
		return false
	var s: String = v
	if s.is_empty() or s.begins_with("_") or s.ends_with("_") or s.contains("__"):
		return false
	for ch: String in s:
		if not ((ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_"):
			return false
	return true


static func _is_point(v: Variant, size: Vector2i, allow_coords: bool) -> bool:
	if typeof(v) == TYPE_STRING:
		return POINTS.has(str(v))
	if allow_coords and typeof(v) == TYPE_ARRAY:
		var a: Array = v
		if a.size() != 2:
			return false
		for n: Variant in a:
			if typeof(n) != TYPE_INT and typeof(n) != TYPE_FLOAT:
				return false
		return (
			float(a[0]) >= 0.0
			and float(a[1]) >= 0.0
			and float(a[0]) <= size.x
			and float(a[1]) <= size.y
		)
	return false


## Problems with parsed art.json data (empty when valid). generate.mjs validates the same schema with
## more detail; this guards pixelate against files it never saw.
static func validate_art(data: Variant) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if typeof(data) != TYPE_DICTIONARY:
		errors.append("art.json: the top level must be an object")
		return errors
	var art: Dictionary = data
	var palette: Variant = art.get("palette")
	if typeof(palette) != TYPE_ARRAY or (palette as Array).is_empty():
		errors.append('palette: expected a non-empty array of "#rrggbb" colors')
	else:
		var pal: Array = palette
		if pal.size() > MAX_PALETTE:
			errors.append("palette: %d colors, at most %d allowed" % [pal.size(), MAX_PALETTE])
		for i: int in pal.size():
			if not is_hex_color(pal[i]):
				errors.append(
					'palette[%d]: %s is not a "#rrggbb" hex color' % [i, JSON.stringify(pal[i])]
				)
	if typeof(art.get("style")) != TYPE_STRING or str(art.get("style")).strip_edges().is_empty():
		errors.append("style: expected a non-empty string")
	var dither: Variant = art.get("dither", "none")
	if not DITHERS.has(str(dither)):
		errors.append("dither: %s is not one of %s" % [JSON.stringify(dither), ", ".join(DITHERS)])
	var sprites: Variant = art.get("sprites")
	if typeof(sprites) != TYPE_ARRAY or (sprites as Array).is_empty():
		errors.append("sprites: expected a non-empty array")
		return errors
	var ids: Dictionary = {}
	var list: Array = sprites
	for i: int in list.size():
		var where: String = "sprites[%d]" % i
		if typeof(list[i]) != TYPE_DICTIONARY:
			errors.append(where + ": expected an object")
			continue
		var s: Dictionary = list[i]
		if not _is_id(s.get("id")):
			(
				errors
				. append(
					(
						where
						+ ".id: expected lower-case letters and digits in words joined by single underscores"
					)
				)
			)
		elif ids.has(s["id"]):
			errors.append(where + '.id: "%s" is used twice' % s["id"])
		else:
			ids[s["id"]] = true
			where += " (%s)" % s["id"]
		var size: Vector2i = Vector2i.ZERO
		var sz: Variant = s.get("size")
		if (
			typeof(sz) == TYPE_ARRAY
			and (sz as Array).size() == 2
			and _is_int(sz[0])
			and _is_int(sz[1])
			and int(sz[0]) >= 1
			and int(sz[1]) >= 1
		):
			size = Vector2i(int(sz[0]), int(sz[1]))
		else:
			errors.append(where + ".size: expected [width, height] in art pixels, integers >= 1")
		if typeof(s.get("prompt")) != TYPE_STRING or str(s.get("prompt")).strip_edges().is_empty():
			errors.append(where + ".prompt: expected a non-empty string")
		if not BACKGROUNDS.has(str(s.get("background", "transparent"))):
			errors.append(where + ".background: expected transparent or opaque")
		var align: Variant = s.get("align", "bottom_center")
		if not _is_point(align, size, false):
			errors.append(where + ".align: expected one of " + ", ".join(POINTS))
		if not _is_point(s.get("anchor", align), size, true):
			errors.append(
				where + ".anchor: expected [x, y] inside the sprite or one of " + ", ".join(POINTS)
			)
		var tile: Variant = s.get("tile", false)
		var mirror: Variant = s.get("mirror", false)
		if typeof(tile) != TYPE_BOOL:
			errors.append(where + ".tile: expected true or false")
		if typeof(mirror) != TYPE_BOOL:
			errors.append(where + ".mirror: expected true or false")
		elif bool(mirror) and not (typeof(tile) == TYPE_BOOL and bool(tile)):
			errors.append(where + ".mirror: needs tile: true")
		if not DITHERS.has(str(s.get("dither", dither))):
			errors.append(where + ".dither: expected none or ordered")
		var parts: Variant = s.get("parts", {})
		if typeof(parts) != TYPE_DICTIONARY:
			errors.append(where + ".parts: expected an object {name: [x, y, w, h]}")
			continue
		for name: Variant in (parts as Dictionary).keys():
			var r: Variant = (parts as Dictionary)[name]
			if not _is_id(name):
				(
					errors
					. append(
						(
							where
							+ (
								".parts.%s: part names use lower-case letters, digits and single underscores"
								% name
							)
						)
					)
				)
			if typeof(r) != TYPE_ARRAY or (r as Array).size() != 4:
				errors.append(where + ".parts.%s: expected [x, y, w, h] integers" % name)
				continue
			var rr: Array = r
			var ints: bool = true
			for n: Variant in rr:
				ints = ints and _is_int(n)
			if not ints:
				errors.append(where + ".parts.%s: expected [x, y, w, h] integers" % name)
				continue
			var rect: Rect2i = Rect2i(int(rr[0]), int(rr[1]), int(rr[2]), int(rr[3]))
			if (
				rect.size.x < 1
				or rect.size.y < 1
				or rect.position.x < 0
				or rect.position.y < 0
				or rect.end.x > size.x
				or rect.end.y > size.y
			):
				errors.append(
					(
						where
						+ (
							".parts.%s: %s lies outside the %dx%d sprite"
							% [name, JSON.stringify(r), size.x, size.y]
						)
					)
				)
	return errors


## One sprite with every default filled: size as Vector2i, parts as {name: Rect2i}.
static func normalize_sprite(s: Dictionary, art: Dictionary) -> Dictionary:
	var sz: Array = s["size"]
	var parts: Dictionary = {}
	var raw_parts: Dictionary = s.get("parts", {})
	for name: Variant in raw_parts.keys():
		var r: Array = raw_parts[name]
		parts[str(name)] = Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
	var align: String = str(s.get("align", "bottom_center"))
	return {
		"id": str(s["id"]),
		"size": Vector2i(int(sz[0]), int(sz[1])),
		"background": str(s.get("background", "transparent")),
		"align": align,
		"anchor": s.get("anchor", align),
		"tile": bool(s.get("tile", false)),
		"mirror": bool(s.get("mirror", false)),
		"dither": str(s.get("dither", art.get("dither", "none"))),
		"parts": parts,
	}


## {sprite id: manifest entry} for every sprite with a selected, usable ("ok") result.
static func selected_entries(manifest: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var reqs: Variant = manifest.get("requests", [])
	if typeof(reqs) != TYPE_ARRAY:
		return out
	for e: Variant in reqs:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		if d.get("selected", false) == true and str(d.get("status", "")) == "ok":
			out[str(d.get("sprite", ""))] = d
	return out


# ---------------------------------------------------------------- files


static func part_file_name(sprite_id: String, part: String) -> String:
	return "%s%s%s.png" % [sprite_id, PART_SEPARATOR, part]


## The prompt generate.mjs sends for a sprite: the shared style prefix, a space, the sprite prompt.
static func compose_prompt(art: Dictionary, sprite: Dictionary) -> String:
	return (
		"%s %s"
		% [str(art.get("style", "")).strip_edges(), str(sprite.get("prompt", "")).strip_edges()]
	)


## Why the selected manifest entry no longer matches the sprite in art.json (another endpoint,
## prompt or background), or an empty array. Pixelate still uses the entry; the caller warns.
static func selection_mismatches(
	entry: Dictionary, art: Dictionary, sprite: Dictionary
) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var endpoint: String = str(art.get("endpoint", DEFAULT_ENDPOINT))
	if entry.has("endpoint") and str(entry["endpoint"]) != endpoint:
		out.append("it is from %s, art.json's endpoint is %s" % [entry["endpoint"], endpoint])
	var input: Variant = entry.get("input", {})
	if typeof(input) != TYPE_DICTIONARY:
		return out
	var inp: Dictionary = input
	if inp.has("prompt") and str(inp["prompt"]) != compose_prompt(art, sprite):
		out.append("it was generated from another prompt than art.json's")
	var background: String = str(sprite.get("background", "transparent"))
	if inp.has("background") and str(inp["background"]) != background:
		out.append(
			(
				"it was generated with background %s, art.json now says %s"
				% [inp["background"], background]
			)
		)
	return out


## Removes `<sprite id>__<part>.png` files (and their .import) of parts art.json no longer lists, so a
## renamed or dropped part leaves no stale, possibly off-palette PNG behind. Returns the removed names.
static func remove_stale_parts(
	out_dir: String, sprite_id: String, keep: Array
) -> PackedStringArray:
	var wanted: Dictionary = {}
	for name: Variant in keep:
		wanted[part_file_name(sprite_id, str(name))] = true
	var prefix: String = sprite_id + PART_SEPARATOR
	var files: PackedStringArray = DirAccess.get_files_at(out_dir)
	files.sort()
	var removed: PackedStringArray = PackedStringArray()
	for f: String in files:
		if not f.begins_with(prefix) or not f.ends_with(".png") or wanted.has(f):
			continue
		DirAccess.remove_absolute(out_dir.path_join(f))
		if FileAccess.file_exists(out_dir.path_join(f + ".import")):
			DirAccess.remove_absolute(out_dir.path_join(f + ".import"))
		removed.append(f)
	return removed


## Writes `bytes` unless the file already holds exactly them. Returns OK or the error.
static func write_if_changed(path: String, bytes: PackedByteArray) -> Error:
	if FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path) == bytes:
		return OK
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(bytes)
	f.close()
	return OK


## Gives a sprite PNG the pixel import preset according to import_preset_mode.
static func apply_import_preset(png_path: String) -> void:
	if import_preset_mode == IMPORT_WRITE_FILE:
		write_pixel_import_file(png_path)


## The preset as a minimal .import file; Godot fills in uid and dest_files on its next import.
static func import_file_text() -> String:
	var lines: PackedStringArray = PackedStringArray(
		["[remap]", "", 'importer="texture"', 'type="CompressedTexture2D"', "", "[params]", ""]
	)
	for k: String in IMPORT_PARAMS.keys():
		lines.append("%s=%s" % [k, var_to_str(IMPORT_PARAMS[k])])
	return "\n".join(lines) + "\n"


## Writes `<png>.import` with the preset if it is missing. An existing one keeps its uid and every
## other key; only the preset's [params] are corrected when they differ.
static func write_pixel_import_file(png_path: String) -> Error:
	var path: String = png_path + ".import"
	if not FileAccess.file_exists(path):
		var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return FileAccess.get_open_error()
		f.store_string(import_file_text())
		f.close()
		return OK
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(path) != OK:
		return ERR_PARSE_ERROR
	var changed: bool = false
	for k: String in IMPORT_PARAMS.keys():
		if not cfg.has_section_key("params", k) or cfg.get_value("params", k) != IMPORT_PARAMS[k]:
			cfg.set_value("params", k, IMPORT_PARAMS[k])
			changed = true
	return cfg.save(path) if changed else OK


static func _rgba8(img: Image) -> Image:
	if img.get_format() == Image.FORMAT_RGBA8 and not img.has_mipmaps():
		return img
	var c: Image = img.duplicate() as Image
	c.clear_mipmaps()
	if c.is_compressed():
		c.decompress()
	c.convert(Image.FORMAT_RGBA8)
	return c


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var j: JSON = JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return j.data


static func _fail(report: Dictionary, msg: String) -> void:
	push_error("pixelate: " + msg)
	(report["errors"] as Array).append(msg)
	report["ok"] = false


static func _warn(report: Dictionary, msg: String) -> void:
	push_warning("pixelate: " + msg)
	(report["warnings"] as Array).append(msg)


static func _num(v: float) -> Variant:
	return int(v) if v == floorf(v) else v


# ---------------------------------------------------------------- the whole game


## Pixelates every sprite of <root>/assets/<game>/art.json (or only `only`) from its selected
## manifest result. Returns {"ok": bool, "written", "skipped", "removed", "errors", "warnings": Array
## of String}; paths in "written" and "removed" (stale part files) are relative to root. Fatal problems
## push_error; skipped sprites and selected results that no longer match art.json push_warning.
static func run_game(
	root: String, game: String, only: PackedStringArray = PackedStringArray()
) -> Dictionary:
	var report: Dictionary = {
		"ok": true, "written": [], "skipped": [], "removed": [], "errors": [], "warnings": []
	}
	if import_preset_mode == IMPORT_PROJECT_DEFAULTS:
		var preset_problems: PackedStringArray = PixelImportPreset.check_project_defaults()
		if not preset_problems.is_empty():
			_fail(
				report,
				(
					"the pixel import preset relies on project.godot's [importer_defaults] texture: %s"
					% "; ".join(preset_problems)
				)
			)
			return report
	var base: String = root.replace("\\", "/").trim_suffix("/")
	var game_dir: String = base.path_join("assets").path_join(game)
	var art_path: String = game_dir.path_join("art.json")
	var art_v: Variant = _read_json(art_path)
	if art_v == null:
		_fail(report, "%s is missing or not valid JSON" % art_path)
		return report
	var problems: PackedStringArray = validate_art(art_v)
	if not problems.is_empty():
		_fail(report, "%s is invalid:\n  - %s" % [art_path, "\n  - ".join(problems)])
		return report
	var art: Dictionary = art_v
	var manifest_path: String = game_dir.path_join("art_manifest.json")
	var manifest_v: Variant = _read_json(manifest_path)
	if typeof(manifest_v) != TYPE_DICTIONARY:
		_fail(
			report,
			(
				"%s is missing or not valid JSON: run node tools/art/generate.mjs --game=%s first"
				% [manifest_path, game]
			)
		)
		return report
	var selected: Dictionary = selected_entries(manifest_v)
	var ids: Dictionary = {}
	for s: Variant in art["sprites"]:
		ids[str((s as Dictionary)["id"])] = true
	for id: String in only:
		if not ids.has(id):
			_fail(report, '--only: art.json has no sprite "%s"' % id)
	if not report["ok"]:
		return report
	var palette: Palette = make_palette(art["palette"])
	var out_dir: String = game_dir.path_join("sprites")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for s: Variant in art["sprites"]:
		var spec: Dictionary = normalize_sprite(s, art)
		var id: String = spec["id"]
		if not only.is_empty() and not only.has(id):
			continue
		if not selected.has(id):
			_warn(
				report, "%s: no selected result in the manifest; generate it first (skipped)" % id
			)
			(report["skipped"] as Array).append(id)
			continue
		var entry: Dictionary = selected[id]
		var raw_rel: String = str(entry.get("cache", ""))
		var raw_path: String = base.path_join(raw_rel)
		if raw_rel.is_empty() or not FileAccess.file_exists(raw_path):
			_fail(
				report,
				(
					"%s: the selected result %s has no raw image at %s; run generate.mjs to fetch it again"
					% [id, entry.get("request_id", "?"), raw_path]
				)
			)
			continue
		var raw: Image = Image.new()
		if raw.load_png_from_buffer(FileAccess.get_file_as_bytes(raw_path)) != OK:
			_fail(report, "%s: %s is not a readable PNG" % [id, raw_path])
			continue
		var mismatches: PackedStringArray = selection_mismatches(entry, art, s)
		if not mismatches.is_empty():
			_warn(
				report,
				(
					"%s: uses the selected result %s, but %s (run generate.mjs for a matching result, or --select another)"
					% [id, entry.get("request_id", "?"), "; ".join(mismatches)]
				)
			)
		var sprite: Image = process_sprite(raw, spec, palette)
		var out_path: String = out_dir.path_join(id + ".png")
		if write_if_changed(out_path, sprite.save_png_to_buffer()) != OK:
			_fail(report, "%s: cannot write %s" % [id, out_path])
			continue
		apply_import_preset(out_path)
		(report["written"] as Array).append("assets/%s/sprites/%s.png" % [game, id])
		var parts: Dictionary = spec["parts"]
		var names: Array = parts.keys()
		names.sort()
		for name: Variant in names:
			var part_path: String = out_dir.path_join(part_file_name(id, str(name)))
			if (
				write_if_changed(part_path, cut_part(sprite, parts[name]).save_png_to_buffer())
				!= OK
			):
				_fail(report, "%s: cannot write %s" % [id, part_path])
				continue
			apply_import_preset(part_path)
			(report["written"] as Array).append(
				"assets/%s/sprites/%s" % [game, part_file_name(id, str(name))]
			)
		for f: String in remove_stale_parts(out_dir, id, names):
			(report["removed"] as Array).append("assets/%s/sprites/%s" % [game, f])
	_write_index(report, art, selected, out_dir, game)
	return report


## sprites.json: every sprite with a PNG on disk, its size, anchor (art pixels), parts and source.
static func _write_index(
	report: Dictionary, art: Dictionary, selected: Dictionary, out_dir: String, game: String
) -> void:
	var sprites: Dictionary = {}
	for s: Variant in art["sprites"]:
		var spec: Dictionary = normalize_sprite(s, art)
		var id: String = spec["id"]
		if not FileAccess.file_exists(out_dir.path_join(id + ".png")):
			continue
		var size: Vector2i = spec["size"]
		var anchor: Vector2 = anchor_point(spec["anchor"], size)
		var parts: Dictionary = {}
		for name: Variant in (spec["parts"] as Dictionary).keys():
			var r: Rect2i = spec["parts"][name]
			parts[str(name)] = {
				"file": part_file_name(id, str(name)),
				"rect": [r.position.x, r.position.y, r.size.x, r.size.y]
			}
		var item: Dictionary = {
			"file": id + ".png",
			"size": [size.x, size.y],
			"anchor": [_num(anchor.x), _num(anchor.y)],
			"align": spec["align"],
			"background": spec["background"],
			"tile": spec["tile"],
			"mirror": spec["mirror"],
			"parts": parts,
		}
		if selected.has(id):
			var e: Dictionary = selected[id]
			item["source"] = {
				"request_id": str(e.get("request_id", "")), "endpoint": str(e.get("endpoint", ""))
			}
		sprites[id] = item
	var text: String = (
		JSON.stringify({"game": game, "palette": art["palette"], "sprites": sprites}, "  ", true)
		+ "\n"
	)
	if write_if_changed(out_dir.path_join(INDEX_FILE), text.to_utf8_buffer()) != OK:
		_fail(report, "cannot write %s" % out_dir.path_join(INDEX_FILE))
