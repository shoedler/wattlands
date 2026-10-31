class_name TankFarSky
extends RefCounted
## v4: what stands over the far panel's treeline, baked once from hashes so a long lens sees a real night and not a
## blank plate: `sky()` a very faint Milky Way with dust in it and a dozen soft stars in the near sky's style, scattered
## and quieter than it; `ridge()` two ranges of mountains at a value just off the sky, lit from the top left as
## everything is, with a broken moonlit rim. Both tile by W and are clear where they show nothing. Pure of the state.

const W := 512
const H := 340
## The soft stars per tile (the panel, 286-420 px wide, shows 8-12), their rows, how far apart, how bright at most.
const STARS := 15
const STAR_ROWS := Vector2(10.0, 124.0)
const STAR_APART := 36.0
const STAR := Color(0.72, 0.86, 0.9)
const STAR_A := Vector2(0.2, 0.46)
const STAR_HALO := 0.3
## The Milky Way: a soft band running down to the left, where it stands at the top, its slope, half width and strongest
## alpha; it fades out before it reaches the mountains.
const BAND := Color(0.36, 0.56, 0.62)
const BAND_X := 235.0
const BAND_SLOPE := -0.62
const BAND_W := 30.0
const BAND_A := 0.2
const BAND_END := Vector2(70.0, 170.0)
const BAND_STEPS := 48.0
const DUST := 44
const DUST_A := Vector2(0.08, 0.26)
## The far range: its foot, the height its peaks reach over it, and the near range under it (one step darker).
const BACK_FOOT := 196.0
const BACK_RISE := 92.0
const FRONT_FOOT := 226.0
const FRONT_RISE := 42.0
const BACK := Color(0.034, 0.08, 0.093)
const BACK_LIT := Color(0.058, 0.118, 0.134)
const BACK_RIM := Color(0.07, 0.136, 0.152)
const FRONT := Color(0.024, 0.056, 0.066)
const FRONT_LIT := Color(0.038, 0.08, 0.092)
const FRONT_RIM := Color(0.044, 0.09, 0.102)
## The lit faces: how deep they run under the crest, the width of a facet, and the steps of their light.
const FACE_DEEP := 40.0
const FACET := 11.0
const FACE_STEPS := 3.0

static var _sky: Texture2D = null
static var _ridge: Texture2D = null


static func sky() -> Texture2D:
	if _sky == null:
		_sky = ImageTexture.create_from_image(sky_image())
	return _sky


static func ridge() -> Texture2D:
	if _ridge == null:
		_ridge = ImageTexture.create_from_image(ridge_image())
	return _ridge


## The soft stars' top-left corners (each one 2 x 2 with a cut-cornered halo): scattered by hash, none near another.
static func stars() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var i := 0
	while out.size() < STARS and i < STARS * 40:
		var x := roundi(TankDraw.hash01(float(i) * 1.37 + 2.0) * float(W - 1))
		var h := TankDraw.hash01(float(i) * 2.71 + 9.0)
		var y := roundi(lerpf(STAR_ROWS.x, STAR_ROWS.y, h))
		i += 1
		var at := Vector2i(x, y)
		var clear := true
		for o in out:
			if _wrapped(float(o.x - x)) < STAR_APART and absi(o.y - y) < STAR_APART:
				clear = false
				break
		if clear:
			out.append(at)
	return out


static func sky_image() -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in int(BAND_END.y):
		var fade := 1.0 - clampf((float(y) - BAND_END.x) / (BAND_END.y - BAND_END.x), 0.0, 1.0)
		var cx := band_x(float(y))
		for x in W:
			var d := _wrapped(float(x) - cx) / BAND_W
			if d > 2.4:
				continue
			var cloud := (
				_noise2(float(x), float(y), 19.0) * 0.6 + _noise2(float(x), float(y), 7.0) * 0.4
			)
			var a := BAND_A * exp(-d * d) * (0.35 + 0.65 * cloud) * fade
			# in pixel steps, broken by a hash: a grain of far stars, no smooth airbrush
			a = (
				floorf(a * BAND_STEPS + TankDraw.hash01(float(x) * 0.91 + float(y) * 3.3))
				/ BAND_STEPS
			)
			if a > 0.0:
				img.set_pixel(x, y, Color(BAND, a))
	for i in DUST:
		var y2 := int(TankDraw.hash01(float(i) * 3.17 + 1.0) * (BAND_END.y - 10.0))
		var off := (TankDraw.hash01(float(i) * 5.21 + 4.0) - 0.5) * BAND_W * 2.4
		var x2 := posmod(roundi(band_x(float(y2)) + off), W)
		var ad := lerpf(DUST_A.x, DUST_A.y, TankDraw.hash01(float(i) * 7.3 + 8.0))
		img.set_pixel(x2, y2, Color(STAR, ad))
	var stars_at := stars()
	for j in stars_at.size():
		var p := stars_at[j]
		var ha := TankDraw.hash01(float(j) * 4.13 + 5.0)
		_star(img, p, lerpf(STAR_A.x, STAR_A.y, ha * ha))
	return img


## The band's middle (x) at row `y`.
static func band_x(y: float) -> float:
	return BAND_X + BAND_SLOPE * y


## The far range's crest (stage y) at `x`: a tall peak and its fellows, shoulders and a rough edge. It tiles by W.
static func back_top(x: float) -> float:
	var u := x / float(W)
	var big := pow(1.0 - absf(sin(PI * (u * 2.0) + 0.4)), 1.3)
	var mid := 1.0 - absf(sin(PI * (u * 5.0) + 1.7))
	return (
		BACK_FOOT
		- (
			BACK_RISE
			* (0.62 * big + 0.2 * mid + 0.13 * _noise1(x, 23.0, 3.0) + 0.05 * _noise1(x, 7.0, 7.0))
		)
	)


## The near range's crest at `x`, lower and rounder.
static func front_top(x: float) -> float:
	var u := x / float(W)
	var big := 1.0 - absf(sin(PI * (u * 3.0) + 2.3))
	var mid := 1.0 - absf(sin(PI * (u * 7.0) + 0.6))
	return (
		FRONT_FOOT
		- (
			FRONT_RISE
			* (
				0.6 * big
				+ 0.22 * mid
				+ 0.13 * _noise1(x, 17.0, 11.0)
				+ 0.05 * _noise1(x, 5.0, 13.0)
			)
		)
	)


static func ridge_image() -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for x in W:
		_column(img, x, Callable(TankFarSky, "back_top"), [BACK, BACK_LIT, BACK_RIM])
		_column(img, x, Callable(TankFarSky, "front_top"), [FRONT, FRONT_LIT, FRONT_RIM])
	return img


## One column of a range: its rim, the faces toward the moon in steps under the crest, the dark body to the bottom.
static func _column(img: Image, x: int, top_at: Callable, cols: Array[Color]) -> void:
	var fx := float(x)
	var top := roundi(float(top_at.call(fx)))
	var rise := float(top_at.call(fx - 3.0)) - float(top_at.call(fx + 3.0))
	var lit := clampf(rise * 0.2, 0.0, 1.0)
	for y in range(maxi(top, 0), H):
		var depth := float(y - top)
		var col: Color = cols[0]
		if depth == 0.0 and _noise1(fx, 13.0, 21.0) > 0.46:
			col = cols[2]
		else:
			var facet := TankDraw.hash01(floorf((fx + depth * 0.8) / FACET) * 1.91)
			var k := lit * (0.35 + 0.65 * facet) * (1.0 - clampf(depth / FACE_DEEP, 0.0, 1.0))
			col = (cols[0] as Color).lerp(cols[1], roundf(k * FACE_STEPS) / FACE_STEPS)
		img.set_pixel(x, y, col)


## A soft star: a 2 x 2 core, a cut-cornered halo round it.
static func _star(img: Image, p: Vector2i, a: float) -> void:
	for dy in range(-1, 3):
		for dx in range(-1, 3):
			var core := dx >= 0 and dx < 2 and dy >= 0 and dy < 2
			var corner := (dx == -1 or dx == 2) and (dy == -1 or dy == 2)
			if corner:
				continue
			var x := posmod(p.x + dx, W)
			img.set_pixel(x, p.y + dy, Color(STAR, a if core else a * STAR_HALO))


## The shortest way round the tile.
static func _wrapped(dx: float) -> float:
	var d := fposmod(dx, float(W))
	return minf(d, float(W) - d)


## Smooth noise along x, tiling by W.
static func _noise1(x: float, cell: float, seed_v: float) -> float:
	var cells := maxf(roundf(float(W) / cell), 1.0)
	var c := float(W) / cells
	var i := floorf(x / c)
	var t := x / c - i
	t = t * t * (3.0 - 2.0 * t)
	var a := TankDraw.hash01(fposmod(i, cells) * 1.13 + seed_v)
	var b := TankDraw.hash01(fposmod(i + 1.0, cells) * 1.13 + seed_v)
	return lerpf(a, b, t)


## Smooth noise on the plane, tiling by W in x.
static func _noise2(x: float, y: float, cell: float) -> float:
	var cells := maxf(roundf(float(W) / cell), 1.0)
	var c := float(W) / cells
	var i := floorf(x / c)
	var j := floorf(y / c)
	var tx := x / c - i
	var ty := y / c - j
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var i0 := fposmod(i, cells)
	var i1 := fposmod(i + 1.0, cells)
	var a := TankDraw.hash01(i0 * 1.71 + j * 3.37)
	var b := TankDraw.hash01(i1 * 1.71 + j * 3.37)
	var d := TankDraw.hash01(i0 * 1.71 + (j + 1.0) * 3.37)
	var e := TankDraw.hash01(i1 * 1.71 + (j + 1.0) * 3.37)
	return lerpf(lerpf(a, b, tx), lerpf(d, e, tx), ty)
