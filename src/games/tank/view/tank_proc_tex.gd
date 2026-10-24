class_name TankProcTex
extends RefCounted
## Small procedural textures the effects share (soft glow, smoke puff, fireball, vignette). They
## are generated once, on first use, and cached, so no frame creates a texture. The generated art
## sprites (muzzle_flash, explosion_*, smoke_puff, ...) replace the fireball and puff when a real
## PNG exists (TankSprites.has_real); lights and halos are always procedural.

static var _tex: Dictionary = {}


## A white radial falloff, 64 x 64, alpha (1 - r)^2: tint with modulate, draw additive.
static func glow() -> Texture2D:
	return _make("glow", 64, _glow_px)


## A soft grey-white round puff, 32 x 32, a smooth falloff with no pattern in it (a striped puff
## stacked into a column reads as a coil): smoke, steam, dust.
static func puff() -> Texture2D:
	return _make("puff", 32, _puff_px)


## How dark a room's wall is outside the reach of its light (the shade texture's edge alpha).
const SHADE_EDGE := 0.82


## A room's darkness around its light source, 48 x 48: clear in the middle, black at SHADE_EDGE
## alpha from about half the radius out (drawn normally over the wall, under the machinery).
static func shade() -> Texture2D:
	return _make("shade", 48, _shade_px)


## A hot disc: white-yellow core, orange rim, 32 x 32.
static func fireball() -> Texture2D:
	return _make("fireball", 32, _fire_px)


## A 80 x 45 darkening toward the screen edges (alpha), drawn scaled over the whole view.
static func vignette() -> Texture2D:
	if _tex.has("vignette"):
		return _tex["vignette"]
	var img := Image.create(80, 45, false, Image.FORMAT_RGBA8)
	for y in 45:
		for x in 80:
			var dx := (float(x) + 0.5) / 80.0 * 2.0 - 1.0
			var dy := (float(y) + 0.5) / 45.0 * 2.0 - 1.0
			var d := clampf((sqrt(dx * dx * 0.8 + dy * dy) - 0.55) / 0.75, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.02, 0.025, 0.035, d * d * 0.62))
	var tex := ImageTexture.create_from_image(img)
	_tex["vignette"] = tex
	return tex


static func _make(key: String, size: int, painter: Callable) -> Texture2D:
	if _tex.has(key):
		return _tex[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var dx := (float(x) + 0.5) / float(size) * 2.0 - 1.0
			var dy := (float(y) + 0.5) / float(size) * 2.0 - 1.0
			img.set_pixel(x, y, painter.call(sqrt(dx * dx + dy * dy), x, y))
	var tex := ImageTexture.create_from_image(img)
	_tex[key] = tex
	return tex


static func _glow_px(d: float, _x: int, _y: int) -> Color:
	var a := clampf(1.0 - d, 0.0, 1.0)
	return Color(1, 1, 1, a * a)


static func _puff_px(d: float, _x: int, _y: int) -> Color:
	var k := clampf(1.0 - d, 0.0, 1.0)
	return Color(0.92, 0.93, 0.95, k * k * (3.0 - 2.0 * k))


static func _shade_px(d: float, _x: int, _y: int) -> Color:
	var k := clampf((d - 0.18) / 0.62, 0.0, 1.0)
	return Color(0.027, 0.031, 0.039, SHADE_EDGE * k * k * (3.0 - 2.0 * k))


static func _fire_px(d: float, _x: int, _y: int) -> Color:
	var core := clampf(1.0 - d / 0.55, 0.0, 1.0)
	var c := TankPalette.FIRE.lerp(TankPalette.WHITE_WARM, core)
	return Color(c.r, c.g, c.b, clampf((1.0 - d) / 0.35, 0.0, 1.0))
