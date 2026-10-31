class_name TankDraw
extends RefCounted
## Small drawing helpers shared by the view's layers (art px, CanvasItem draw calls): soft radial
## glows for the additive light layer, volumetric beams, single pixels and pixel lines, small spoked
## wheels. The textures are made once and shared.

static var _glow: Texture2D = null
static var _soft: Texture2D = null
static var _white: Texture2D = null


## A radial alpha falloff (white), `size` px, edge falloff `power`.
static func radial(size: int, power: float) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / (size * 0.5)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), power)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


static func glow_tex() -> Texture2D:
	if _glow == null:
		_glow = radial(64, 1.6)
	return _glow


static func soft_tex() -> Texture2D:
	if _soft == null:
		_soft = radial(32, 1.0)
	return _soft


## A 1 x 1 white texture (UV 0..1 over any rect it is stretched to).
static func white_tex() -> Texture2D:
	if _white == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	return _white


static func glow_at(ci: CanvasItem, p: Vector2, r: float, c: Color) -> void:
	if r <= 0.0 or c.a <= 0.0:
		return
	ci.draw_texture_rect(glow_tex(), Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, c)


static func soft_at(ci: CanvasItem, p: Vector2, r: float, c: Color) -> void:
	if r <= 0.0 or c.a <= 0.0:
		return
	ci.draw_texture_rect(soft_tex(), Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, c)


## A small light: a halo and a bright core.
static func lamp(ci: CanvasItem, p: Vector2, c: Color, k: float) -> void:
	glow_at(ci, p, 7.0, Color(c.r, c.g, c.b, 0.55 * k))
	glow_at(ci, p, 2.0, Color(c.r * 0.5 + 0.5, c.g * 0.5 + 0.5, c.b * 0.5 + 0.5, k))


## A vertical wash over `rect`, `c` at the top fading to a quarter at the bottom.
static func fill_room(ci: CanvasItem, rect: Rect2, c: Color) -> void:
	var top := Color(c.r, c.g, c.b, c.a)
	var bot := Color(c.r, c.g, c.b, c.a * 0.25)
	var pts := PackedVector2Array(
		[
			rect.position,
			rect.position + Vector2(rect.size.x, 0),
			rect.end,
			rect.position + Vector2(0, rect.size.y)
		]
	)
	ci.draw_polygon(pts, PackedColorArray([top, top, bot, bot]))


## An additive volumetric cone from `p` at angle `ang`, `blen` long, half-spread `half`: a soft core
## and a wide faint halo, fading along its length and toward its edges; `k` scales it.
static func beam(
	ci: CanvasItem, p: Vector2, ang: float, blen: float, half: float, c: Color, k: float
) -> void:
	# A beam with no length (something stands at the lens) has no polygon to triangulate.
	if k <= 0.0 or blen < 8.0:
		return
	var spreads: Array[float] = [1.6, 1.0, 0.55]
	var alphas: Array[float] = [0.3, 0.55, 0.45]
	var clear := Color(c.r, c.g, c.b, 0)
	for layer in 3:
		var hs := half * spreads[layer]
		var a0 := k * alphas[layer]
		var steps := 10
		for i in steps:
			var t0 := float(i) / steps
			var t1 := float(i + 1) / steps
			var w0 := 1.0 - absf(t0 * 2.0 - 1.0)
			var w1 := 1.0 - absf(t1 * 2.0 - 1.0)
			var d0 := Vector2.from_angle(ang - hs + 2.0 * hs * t0)
			var d1 := Vector2.from_angle(ang - hs + 2.0 * hs * t1)
			var pa := p + d0 * blen * 0.45
			var pb := p + d1 * blen * 0.45
			var ca := Color(c.r, c.g, c.b, a0 * pow(w0, 0.8) * 0.55)
			var cb := Color(c.r, c.g, c.b, a0 * pow(w1, 0.8) * 0.55)
			var apex := Color(c.r, c.g, c.b, a0 * (w0 + w1) * 0.5)
			ci.draw_polygon(PackedVector2Array([p, pa, pb]), PackedColorArray([apex, ca, cb]))
			ci.draw_polygon(
				PackedVector2Array([pa, p + d0 * blen, p + d1 * blen, pb]),
				PackedColorArray([ca, clear, clear, cb])
			)


## One art pixel at `p` (floored).
static func px(ci: CanvasItem, p: Vector2, c: Color) -> void:
	ci.draw_rect(Rect2(p.floor(), Vector2.ONE), c)


## A line of single pixels from `a` to `b`.
static func line_px(ci: CanvasItem, a: Vector2, b: Vector2, c: Color) -> void:
	var n := maxi(ceili(maxf(absf(b.x - a.x), absf(b.y - a.y))), 1)
	for i in n + 1:
		px(ci, a.lerp(b, float(i) / n), c)


## A small spoked wheel: a shaded rim ring (lit from the upper left), `n` spokes at `ang`, a brass
## hub. `dark`, `hi`, `glint` and `hub` are the shades.
static func wheel(
	ci: CanvasItem, c: Vector2, r: float, n: int, ang: float, rim: Color, shades: Array[Color]
) -> void:
	var dark := shades[0]
	var hi := shades[1]
	var steps := maxi(roundi(r * 6.0), 12)
	for k0 in steps:
		var a0 := k0 * TAU / steps
		px(ci, c + Vector2(cos(a0), sin(a0)) * (r - 1.0), dark)
	for k in steps:
		var a := k * TAU / steps
		var lit := -0.6 * cos(a) - 0.8 * sin(a)
		var col := rim
		if lit > 0.55:
			col = hi
		elif lit < -0.3:
			col = dark
		px(ci, c + Vector2(cos(a), sin(a)) * r, col)
	for k2 in n:
		var d := Vector2(cos(ang + k2 * TAU / n), sin(ang + k2 * TAU / n))
		line_px(ci, c + d * 1.5 + Vector2(0.6, 0.6), c + d * (r - 1.0) + Vector2(0.6, 0.6), dark)
		line_px(ci, c + d * 1.5, c + d * (r - 1.0), hi)
	px(ci, c + Vector2(-0.6, -0.8) * r, shades[2])
	ci.draw_rect(Rect2(c.floor(), Vector2(2, 2)), shades[3])


## A stable pseudo-random 0..1 from a number (cosmetic flicker; never the rules).
static func hash01(a: float) -> float:
	var s := sin(a * 12.9898 + 78.233) * 43758.5453
	return s - floorf(s)
