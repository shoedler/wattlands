class_name PixelPainter
extends RefCounted
## Procedural pixel-art images (static helpers): sprites from text rows, gears, discs,
## dithered gradients and tileable hill silhouettes. The world2d demo draws everything with
## them; games use them for code-drawn parts and placeholder art (Tank's placeholder_art.gd
## draws a missing sprite at its size from palette shapes). Deterministic: no global RNG.
## Images are RGBA8 without mipmaps; wrap one with PixelPainter.texture(img).

## 4 x 4 ordered-dither (Bayer) thresholds, 0..15.
const BAYER4: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]


## An ImageTexture of `img`.
static func texture(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


## A sprite from text rows: each character maps to a Color in `palette` (String -> Color);
## '.' and ' ' (and characters missing from the palette) are transparent. Rows may differ in
## length; the width is the longest row.
static func from_rows(rows: PackedStringArray, palette: Dictionary) -> Image:
	var w := 1
	for r: String in rows:
		w = maxi(w, r.length())
	var img := Image.create_empty(w, maxi(rows.size(), 1), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if ch == "." or ch == " " or not palette.has(ch):
				continue
			img.set_pixel(x, y, palette[ch])
	return img


## A gear seen face-on: `teeth` square teeth `tooth_depth` px deep around `radius`, a darker
## rim pixel, four lightening holes (so rotation reads) and a hub. Size 2 * radius.
static func gear(radius: int, teeth: int, body: Color, edge: Color, hub: Color, tooth_depth: int = 2) -> Image:
	var r := maxi(radius, 3)
	var size := r * 2
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(r, r)
	var n := maxi(teeth, 3)
	var root := float(r - maxi(tooth_depth, 1))
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5) - c
			var d := p.length()
			var a := fposmod(p.angle(), TAU)
			var on_tooth := fposmod(a * float(n) / TAU, 1.0) < 0.5
			var outer := float(r) if on_tooth else root
			if d > outer:
				continue
			var col := body
			if d > outer - 1.0 or (not on_tooth and d > root - 1.0):
				col = edge
			var hole_r := root * 0.55
			var hole_a := fposmod(a, TAU / 4.0) - TAU / 8.0
			if absf(d - hole_r) < root * 0.16 and absf(hole_a) < 0.32:
				continue
			if d < maxf(root * 0.28, 1.5):
				col = hub
			if d < 1.0:
				col = edge
			img.set_pixel(x, y, col)
	return img


## A filled disc with a 1 px outline. Size 2 * radius.
static func disc(radius: int, fill: Color, outline: Color) -> Image:
	var r := maxi(radius, 1)
	var img := Image.create_empty(r * 2, r * 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(r, r)
	for y in r * 2:
		for x in r * 2:
			var d := (Vector2(x + 0.5, y + 0.5) - c).length()
			if d <= float(r):
				img.set_pixel(x, y, outline if d > float(r) - 1.0 else fill)
	return img


## A vertical gradient from `top` to `bottom` in `bands` flat colors, ordered-dithered at the
## band edges when `dither` (classic 16-bit skies and water).
static func vertical_gradient(w: int, h: int, top: Color, bottom: Color, bands: int = 8, dither: bool = true) -> Image:
	var img := Image.create_empty(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGBA8)
	var n := maxi(bands, 2)
	for y in img.get_height():
		var t := float(y) / float(maxi(img.get_height() - 1, 1)) * float(n - 1)
		for x in img.get_width():
			var level := floorf(t)
			if dither and BAYER4[(y % 4) * 4 + (x % 4)] < int((t - level) * 16.0):
				level += 1.0
			img.set_pixel(x, y, top.lerp(bottom, clampf(level / float(n - 1), 0.0, 1.0)))
	return img


## Column heights (pixels from the top, 0..h) of a hill line that tiles seamlessly across
## `w` (whole sine periods). `seed` picks the shape; base and amplitude are fractions of h.
static func hill_heights(w: int, h: int, seed: int, base_frac: float = 0.5, amp_frac: float = 0.25, waves: int = 3) -> PackedFloat32Array:
	var rng := SeededRng.make(seed)
	var freqs: Array[int] = []
	var phases: Array[float] = []
	var amps: Array[float] = []
	for i in maxi(waves, 1):
		freqs.append(i + 1 + rng.randi_range(0, 1) * (i + 1))
		phases.append(rng.randf() * TAU)
		amps.append(1.0 / float(i + 1))
	var total := 0.0
	for a: float in amps:
		total += a
	var out := PackedFloat32Array()
	out.resize(maxi(w, 1))
	for x in out.size():
		var v := 0.0
		for i in freqs.size():
			v += amps[i] * sin(TAU * float(freqs[i]) * float(x) / float(maxi(w, 1)) + phases[i])
		out[x] = clampf(float(h) * (base_frac - amp_frac * v / total), 0.0, float(h))
	return out


## A silhouette strip: each column filled from its height (pixels from the top) to the
## bottom, with a 1 px `edge` color on top.
static func silhouette(w: int, h: int, heights: PackedFloat32Array, fill: Color, edge: Color) -> Image:
	var img := Image.create_empty(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in img.get_width():
		var top := int(roundf(heights[x % heights.size()])) if heights.size() > 0 else h
		for y in range(clampi(top, 0, h), h):
			img.set_pixel(x, y, edge if y == top else fill)
	return img


## Horizontal bands of colors, each `band_h` px tall, repeating (ground, wave crests).
static func bands(w: int, h: int, colors: PackedColorArray, band_h: int = 2) -> Image:
	var img := Image.create_empty(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGBA8)
	if colors.is_empty():
		img.fill(Color(0, 0, 0, 0))
		return img
	for y in img.get_height():
		var col := colors[floori(float(y) / float(maxi(band_h, 1))) % colors.size()]
		for x in img.get_width():
			img.set_pixel(x, y, col)
	return img
