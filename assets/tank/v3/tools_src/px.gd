extends RefCounted
## Pixel helpers for the v3 tank mock generator: drawing on the pixel grid, deterministic noise,
## ordered dither, nearest and RotSprite-style rotation, the v2 stencil font. Image API only.

const BAYER4: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
const FONT_TALL := "res://assets/tank/v2/hud/tank_stencil_5x9.png"
const FONT_TEXT := "res://assets/tank/v2/hud/tank_stencil_5x7.png"

static var _font_tall: Image
static var _font_text: Image


static func blank(w: int, h: int, bg := Color(0, 0, 0, 0)) -> Image:
	var i := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	i.fill(bg)
	return i


static func inside(i: Image, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < i.get_width() and y < i.get_height()


static func put(i: Image, x: int, y: int, c: Color) -> void:
	if inside(i, x, y):
		i.set_pixel(x, y, c)


## Alpha-over `c` at strength `a` onto an existing pixel (keeps the pixel's alpha, or takes `a`).
static func mix(i: Image, x: int, y: int, c: Color, a: float) -> void:
	if not inside(i, x, y):
		return
	var o := i.get_pixel(x, y)
	if o.a < 0.01:
		return
	var r := o.lerp(c, clampf(a, 0.0, 1.0))
	r.a = o.a
	i.set_pixel(x, y, r)


## Additive light onto an opaque pixel.
static func add(i: Image, x: int, y: int, c: Color, a: float) -> void:
	if not inside(i, x, y):
		return
	var o := i.get_pixel(x, y)
	if o.a < 0.01:
		return
	i.set_pixel(x, y, Color(minf(o.r + c.r * a, 1.0), minf(o.g + c.g * a, 1.0), minf(o.b + c.b * a, 1.0), o.a))


static func rect(i: Image, r: Rect2i, c: Color) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			put(i, x, y, c)


static func line(i: Image, a: Vector2i, b: Vector2i, c: Color) -> void:
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var x := a.x
	var y := a.y
	while true:
		put(i, x, y, c)
		if x == b.x and y == b.y:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy


static func linef(i: Image, a: Vector2, b: Vector2, c: Color) -> void:
	line(i, Vector2i(floori(a.x), floori(a.y)), Vector2i(floori(b.x), floori(b.y)), c)


static func disc(i: Image, c: Vector2, r: float, col: Color) -> void:
	for y in range(floori(c.y - r), ceili(c.y + r) + 1):
		for x in range(floori(c.x - r), ceili(c.x + r) + 1):
			if Vector2(x + 0.5, y + 0.5).distance_to(c) <= r:
				put(i, x, y, col)


## Deterministic hash in [0, 1).
static func h2(x: int, y: int, s: int = 0) -> float:
	var n := (x * 374761393 + y * 668265263 + s * 1442695041) & 0xFFFFFFFF
	n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
	n = n ^ (n >> 16)
	return float(n & 0xFFFF) / 65536.0


## Smooth value noise in [0, 1) at cell size `cell`.
static func vnoise(x: float, y: float, cell: float, s: int = 0) -> float:
	var fx := x / cell
	var fy := y / cell
	var ix := floori(fx)
	var iy := floori(fy)
	var tx := fx - ix
	var ty := fy - iy
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var a := lerpf(h2(ix, iy, s), h2(ix + 1, iy, s), tx)
	var b := lerpf(h2(ix, iy + 1, s), h2(ix + 1, iy + 1, s), tx)
	return lerpf(a, b, ty)


## Ordered-dither pick from `ramp` for value v in [0, 1].
static func dither(ramp: Array, v: float, x: int, y: int) -> Color:
	var n := ramp.size() - 1
	var f := clampf(v, 0.0, 1.0) * n
	var lo := floori(f)
	if lo >= n:
		return ramp[n]
	var t := f - lo
	var th := (BAYER4[(y & 3) * 4 + (x & 3)] + 0.5) / 16.0
	return ramp[lo + 1] if t > th else ramp[lo]


static func in_poly(p: Vector2, poly: PackedVector2Array) -> bool:
	var c := false
	var j := poly.size() - 1
	for i in poly.size():
		var a := poly[i]
		var b := poly[j]
		if (a.y > p.y) != (b.y > p.y) and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
			c = not c
		j = i
	return c


static func poly_bounds(poly: PackedVector2Array) -> Rect2i:
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for p in poly:
		mn = mn.min(p)
		mx = mx.max(p)
	return Rect2i(floori(mn.x), floori(mn.y), ceili(mx.x) - floori(mn.x) + 1, ceili(mx.y) - floori(mn.y) + 1)


## Copy `src` onto `dst` at `at`, opaque pixels only (alpha > 0.5).
static func blit(dst: Image, src: Image, at: Vector2i) -> void:
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			if c.a > 0.5:
				put(dst, at.x + x, at.y + y, c)


static func scaled(src: Image, k: int) -> Image:
	var o := src.duplicate() as Image
	o.resize(src.get_width() * k, src.get_height() * k, Image.INTERPOLATE_NEAREST)
	return o


## Nearest rotation of `src` about `piv_src` by `ang` (radians, y down: positive turns clockwise),
## drawn onto `dst` with the pivot at `piv_dst` (floats: exactly what a GPU with nearest sampling does).
static func rotate_nearest(src: Image, ang: float, piv_src: Vector2, dst: Image, piv_dst: Vector2) -> void:
	var ca := cos(ang)
	var sa := sin(ang)
	var bb := _rot_bounds(src, ang, piv_src, piv_dst)
	var sw := src.get_width()
	var sh := src.get_height()
	for y in range(bb.position.y, bb.end.y):
		for x in range(bb.position.x, bb.end.x):
			var d := Vector2(x + 0.5, y + 0.5) - piv_dst
			var qx := ca * d.x + sa * d.y + piv_src.x
			var qy := -sa * d.x + ca * d.y + piv_src.y
			var ix := floori(qx)
			var iy := floori(qy)
			if ix < 0 or iy < 0 or ix >= sw or iy >= sh:
				continue
			var c := src.get_pixel(ix, iy)
			if c.a > 0.5:
				put(dst, x, y, c)


static func _rot_bounds(src: Image, ang: float, piv_src: Vector2, piv_dst: Vector2) -> Rect2i:
	var pts := [Vector2.ZERO, Vector2(src.get_width(), 0), Vector2(0, src.get_height()), Vector2(src.get_size())]
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for p: Vector2 in pts:
		var q := (p - piv_src).rotated(ang) + piv_dst
		mn = mn.min(q)
		mx = mx.max(q)
	return Rect2i(floori(mn.x) - 1, floori(mn.y) - 1, ceili(mx.x - mn.x) + 3, ceili(mx.y - mn.y) + 3)


# --- RotSprite (Scale2x three times, rotate at 8x, take each 8x8 block's centre sample) ---------


static func _scale2x(d: PackedInt32Array, w: int, h: int) -> PackedInt32Array:
	var o := PackedInt32Array()
	o.resize(w * h * 4)
	var w2 := w * 2
	for y in h:
		var ym := maxi(y - 1, 0) * w
		var yp := mini(y + 1, h - 1) * w
		var yr := y * w
		for x in w:
			var xm := maxi(x - 1, 0)
			var xp := mini(x + 1, w - 1)
			var e := d[yr + x]
			var b := d[ym + x]
			var hh := d[yp + x]
			var dd := d[yr + xm]
			var f := d[yr + xp]
			var e0 := e
			var e1 := e
			var e2 := e
			var e3 := e
			if b != hh and dd != f:
				if dd == b:
					e0 = dd
				if b == f:
					e1 = f
				if dd == hh:
					e2 = dd
				if hh == f:
					e3 = f
			var i0 := 2 * y * w2 + 2 * x
			o[i0] = e0
			o[i0 + 1] = e1
			o[i0 + w2] = e2
			o[i0 + w2 + 1] = e3
	return o


## One 8x sample at 8x coords (X, Y) from the 4x array (the third Scale2x, evaluated lazily).
static func _s8(d4: PackedInt32Array, w4: int, h4: int, xx: int, yy: int) -> int:
	var x := xx >> 1
	var y := yy >> 1
	var xm := maxi(x - 1, 0)
	var xp := mini(x + 1, w4 - 1)
	var ym := maxi(y - 1, 0) * w4
	var yp := mini(y + 1, h4 - 1) * w4
	var yr := y * w4
	var e := d4[yr + x]
	var b := d4[ym + x]
	var hh := d4[yp + x]
	var dd := d4[yr + xm]
	var f := d4[yr + xp]
	if b == hh or dd == f:
		return e
	var q := (yy & 1) * 2 + (xx & 1)
	if q == 0:
		return dd if dd == b else e
	if q == 1:
		return f if b == f else e
	if q == 2:
		return dd if dd == hh else e
	return f if hh == f else e


## Precomputes the 4x Scale2x array of `src` (RotSprite's first two passes).
static func rotsprite_prep(src: Image) -> Dictionary:
	var s := src.duplicate() as Image
	s.convert(Image.FORMAT_RGBA8)
	var w := s.get_width()
	var h := s.get_height()
	var d := s.get_data().to_int32_array()
	var d2 := _scale2x(d, w, h)
	var d4 := _scale2x(d2, w * 2, h * 2)
	return {"d4": d4, "w4": w * 4, "h4": h * 4, "w": w, "h": h}


## RotSprite rotation of a prepared sprite (rotsprite_prep) onto `dst`, same contract as rotate_nearest.
static func rotate_rotsprite(prep: Dictionary, ang: float, piv_src: Vector2, dst: Image, piv_dst: Vector2) -> void:
	var w: int = prep["w"]
	var h: int = prep["h"]
	var d4: PackedInt32Array = prep["d4"]
	var w4: int = prep["w4"]
	var h4: int = prep["h4"]
	var ca := cos(ang)
	var sa := sin(ang)
	var tmp := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var bb := _rot_bounds(tmp, ang, piv_src, piv_dst)
	for y in range(bb.position.y, bb.end.y):
		for x in range(bb.position.x, bb.end.x):
			var dv := Vector2(x + 0.5, y + 0.5) - piv_dst
			var qx := ca * dv.x + sa * dv.y + piv_src.x
			var qy := -sa * dv.x + ca * dv.y + piv_src.y
			if qx < 0.0 or qy < 0.0 or qx >= w or qy >= h:
				continue
			var v := _s8(d4, w4, h4, floori(qx * 8.0), floori(qy * 8.0))
			if ((v >> 24) & 0xFF) > 127:
				put(dst, x, y, Color8(v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, 255))


# --- Text (the v2 stencil faces) --------------------------------------------------------------


static func _glyph_index(ch: String) -> int:
	var u := ch.unicode_at(0)
	if u >= 32 and u <= 126:
		return u - 32
	var extra := [0x2013, 0xB7, 0x2026, 0xB0]
	var k := extra.find(u)
	return 95 + k if k >= 0 else 0


## Draws `text` with the tall (9 px cap) or the text (7 px cap) face; returns the advance.
static func text(i: Image, x: int, y: int, s: String, c: Color, tall := true, shadow := true) -> int:
	if _font_tall == null:
		_font_tall = Image.load_from_file(ProjectSettings.globalize_path(FONT_TALL))
		_font_text = Image.load_from_file(ProjectSettings.globalize_path(FONT_TEXT))
	var f := _font_tall if tall else _font_text
	var cell := Vector2i(6, 11) if tall else Vector2i(6, 9)
	var cx := x
	for k in s.length():
		var gi := _glyph_index(s[k])
		var gx := (gi % 16) * cell.x
		var gy := (gi / 16) * cell.y
		for yy in cell.y:
			for xx in 5:
				if f.get_pixel(gx + xx, gy + yy).a > 0.5:
					if shadow:
						put(i, cx + xx + 1, y + yy + 1, Color(0, 0, 0, 1))
					put(i, cx + xx, y + yy, c)
		cx += 6
	return cx - x


static func text_w(s: String) -> int:
	return s.length() * 6


# --- Oriented profiles (barrels, shells, rods), drawn per pixel at any angle ------------------


## Draws a profile along direction `ang` from `o`: segs = [[u0, u1, hw0, hw1, top, mid, bot], ...]
## (half-width tapering hw0 -> hw1; top = the side towards -normal, lit). An outline of `outline`
## colour rings it unless that is transparent. `clip` (w*h bytes, 0 = skip) limits it when not empty;
## `clip_keep` = the clip value range to draw on (anything non-zero when 0).
static func profile(
	i: Image, o: Vector2, ang: float, segs: Array, outline := Color("#0b0806"), clip := PackedByteArray()
) -> void:
	var dir := Vector2(cos(ang), sin(ang))
	var nrm := Vector2(-dir.y, dir.x)
	var umin := 1e9
	var umax := -1e9
	var hmax := 0.0
	for s: Array in segs:
		umin = minf(umin, float(s[0]))
		umax = maxf(umax, float(s[1]))
		hmax = maxf(hmax, maxf(float(s[2]), float(s[3])))
	var pts := [o + dir * umin, o + dir * umax]
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for p: Vector2 in pts:
		mn = mn.min(p - Vector2.ONE * (hmax + 2))
		mx = mx.max(p + Vector2.ONE * (hmax + 2))
	var w := i.get_width()
	for y in range(floori(mn.y), ceili(mx.y) + 1):
		for x in range(floori(mn.x), ceili(mx.x) + 1):
			if not inside(i, x, y):
				continue
			if clip.size() > 0 and clip[y * w + x] == 0:
				continue
			var d := Vector2(x + 0.5, y + 0.5) - o
			var u := d.dot(dir)
			var v := d.dot(nrm)
			var best := Color(0, 0, 0, 0)
			var edge := false
			for s: Array in segs:
				var u0 := float(s[0])
				var u1 := float(s[1])
				if u < u0 - 0.7 or u > u1 + 0.7:
					continue
				var t := clampf((u - u0) / maxf(u1 - u0, 0.001), 0.0, 1.0)
				var hw := lerpf(float(s[2]), float(s[3]), t)
				if u >= u0 and u <= u1 and absf(v) <= hw:
					if v < -hw + 1.0:
						best = s[4]
					elif v > hw - 1.0:
						best = s[6]
					else:
						best = s[5]
				elif absf(v) <= hw + 0.85:
					edge = true
			if best.a > 0.0:
				i.set_pixel(x, y, best)
			elif edge and outline.a > 0.0:
				i.set_pixel(x, y, outline)
