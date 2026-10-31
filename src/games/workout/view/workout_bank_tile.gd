class_name WorkoutBankTile
extends RefCounted
## The earth bank as paint: mown bands that widen toward the viewer, a stony ditch under the verge,
## grass strokes, worn earth and stamps of tufts and stones, all as ramp indices in one tile, so the
## time of day only changes the ramp. Built once, deterministic, from the bank's two colours of each
## row of the morning, so it stays in the world's light.

const W := 512
## The ground's rows from the bank's top; the stage's bottom is at most this far below a high road.
const GROUND_H := 212
## Stamps: a row of cells under the ground, feet on the cell's last row.
const STAMP_CELL := Vector2i(16, 16)
const H := GROUND_H + STAMP_CELL.y
const INDEX_SCALE := 17

const DEEP := 0
const SHADE := 1
const BASE := 2
const LIGHT := 3
const PALE := 4
const HI := 5
const EARTH_DARK := 6
const EARTH := 7
const EARTH_LIGHT := 8
const STONE_DARK := 9
const STONE := 10
const STONE_LIGHT := 11
const NOTHING := 15

## Where each band starts (rows from the bank's top) and its tone: the light top line, the ditch, the
## ditch's grassy lip, then mown bands, each wider than the one above, the last ones in the shade.
const BAND_TOPS: Array[int] = [0, 1, 6, 11, 18, 27, 38, 52, 70, 92, 118, 148, 182]
const BAND_TONES: Array[int] = [
	HI, EARTH_DARK, SHADE, BASE, LIGHT, BASE, LIGHT, BASE, LIGHT, BASE, SHADE, BASE, SHADE
]
const FIRST_MOWN_BAND := 3
const EARTH_PATCHES := 9
const DITCH_STONES := 16
const STAMPS: Array = [
	[
		".......p........",
		"...l...pl...p...",
		"...lp..lp..pl...",
		"....lp.ll.pl....",
		".....l.ls.l.....",
		".....ls.lsl.s...",
		"...s.lslslss....",
		"....sslsslss....",
		".....dddddd.....",
	],
	[
		"..........l.....",
		"....p....ll.....",
		"....lp..ls......",
		".....l..ls..l...",
		"..s..ls.l..ls...",
		"...s.ls.l.ls....",
		"....sdsdsdd.....",
	],
	[
		"......l.........",
		"..l..pl.........",
		"..ll.pl..l......",
		"...l.l..ls......",
		"...lsl.ls.......",
		"....ddddd.......",
	],
	[
		"......NNn.......",
		"....NNNnnnk.....",
		"...NNnnnnnkk....",
		"...nnnnnnkkkd...",
		"....kkkkkkkdd...",
	],
	[
		".....Nn.........",
		"...NNnnk..Nnk...",
		"...nnnkkd.nkkd..",
		"....kkkd..kkd...",
	],
	[
		"....ff..fE......",
		"..fEEEEEEEe.....",
		".fEEeEEEEeEee...",
		"..eEEeeEEeee....",
		"....eeeeee......",
	],
]
const STAMP_INDEX := {
	"d": DEEP,
	"s": SHADE,
	"b": BASE,
	"l": LIGHT,
	"p": PALE,
	"h": HI,
	"e": EARTH_DARK,
	"E": EARTH,
	"f": EARTH_LIGHT,
	"k": STONE_DARK,
	"n": STONE,
	"N": STONE_LIGHT,
}
## Earth and stone by full daylight; the ramp dims them with the bank.
const EARTH_COLORS: Array[Color] = [Color("#3f2d20"), Color("#59412c"), Color("#70563a")]
const STONE_COLORS: Array[Color] = [Color("#48493f"), Color("#70716a"), Color("#96968b")]
const DAY_LUMA := 0.27

static var _texture: ImageTexture = null


## The shared tile (one R8 texture for every view).
static func texture() -> ImageTexture:
	if _texture == null:
		var img := Image.create_from_data(W, H, false, Image.FORMAT_R8, indices())
		_texture = ImageTexture.create_from_image(img)
	return _texture


## The ramp for a row of the morning, in the shader's index order. Shadows lean to blue, light to the
## bank's own highlight; earth and stones dim with the bank and take the riders' tint.
static func ramp(bank: Color, hi: Color, tint: Color) -> PackedVector3Array:
	var dim := clampf(bank.get_luminance() / DAY_LUMA, 0.3, 1.0)
	var tones: Array[Color] = [
		Color(bank.r * 0.5, bank.g * 0.54, bank.b * 0.72),
		Color(bank.r * 0.74, bank.g * 0.78, bank.b * 0.88),
		bank,
		bank.lerp(hi, 0.3),
		bank.lerp(hi, 0.62),
		hi,
	]
	for c in EARTH_COLORS:
		tones.append(_lit(c, dim, tint))
	for c in STONE_COLORS:
		tones.append(_lit(c, dim, tint))
	var out := PackedVector3Array()
	for c in tones:
		out.append(Vector3(c.r, c.g, c.b))
	while out.size() < NOTHING:
		out.append(Vector3.ZERO)
	return out


static func _lit(c: Color, dim: float, tint: Color) -> Color:
	return Color(c.r * dim * tint.r, c.g * dim * tint.g, c.b * dim * tint.b)


## The tile's bytes, W x H, R = index * INDEX_SCALE. The same every time.
static func indices() -> PackedByteArray:
	var px := PackedByteArray()
	px.resize(W * H)
	px.fill(NOTHING * INDEX_SCALE)
	_bands(px)
	_strokes(px)
	_earth(px)
	_stones(px)
	_stamps(px)
	return px


static func stamp_count() -> int:
	return STAMPS.size()


static func _bands(px: PackedByteArray) -> void:
	for x in W:
		var wave := 1.5 * sin(TAU * 2.0 * x / W + 1.0) + sin(TAU * 5.0 * x / W)
		var band := 0
		for y in GROUND_H:
			while band + 1 < BAND_TOPS.size() and y >= _band_top(band + 1, wave):
				band += 1
			var tone: int = BAND_TONES[band]
			# A dithered edge, one row of the band above, so the bands read as mown, not ruled.
			if band >= FIRST_MOWN_BAND and y == _band_top(band, wave) and (x + y) % 2 == 0:
				tone = BAND_TONES[band - 1]
			_put(px, x, y, tone)


## A mown band's edge wanders with the wave, more so toward the viewer.
static func _band_top(band: int, wave: float) -> int:
	if band <= FIRST_MOWN_BAND:
		return BAND_TOPS[band]
	return BAND_TOPS[band] + roundi(wave * float(band) / 6.0)


## Short blades: shorter and denser far away, longer and wider apart near. One tone lighter than the
## band with a dark foot, so each is a mark and not a speckle.
static func _strokes(px: PackedByteArray) -> void:
	for band in range(FIRST_MOWN_BAND, BAND_TOPS.size()):
		var top: int = BAND_TOPS[band]
		var bottom: int = BAND_TOPS[band + 1] if band + 1 < BAND_TOPS.size() else GROUND_H
		var cell := Vector2i(4 + band, 3 + band / 2)
		var length := 1 + band / 3
		var tone: int = BAND_TONES[band]
		for cy in range(top, bottom, cell.y):
			for cx in range(0, W, cell.x):
				var h := _hash(cx, cy + band * 1009)
				if h % 3 == 0:
					continue
				var x := cx + (h >> 4) % cell.x
				var y := cy + (h >> 9) % cell.y
				var blade: int = LIGHT if tone <= BASE else PALE
				for k in length:
					_put(px, x + (1 if k == 0 and h & 64 != 0 else 0), y - k, blade)
				_put(px, x, y + 1, tone - 1 if tone > DEEP else DEEP)


## Worn patches in the lower bands: flat ellipses of earth, a lit top edge, a dark lower one, a few
## clods on them, and a fringe of grass over the bottom.
static func _earth(px: PackedByteArray) -> void:
	for i in EARTH_PATCHES:
		var h := _hash(i, 7001)
		var cy := 44 + (h >> 3) % 150
		var depth := float(cy) / float(GROUND_H)
		var rx := 10 + roundi(26.0 * depth) + (h >> 11) % 7
		var ry := 2 + roundi(4.0 * depth) + (h >> 15) % 2
		var cx := (i * W) / EARTH_PATCHES + (h >> 17) % 40
		for dy in range(-ry, ry + 1):
			var half := roundi(float(rx) * sqrt(1.0 - pow(float(dy) / float(ry + 1), 2.0)))
			half += _hash(i, dy + 40) % 5 - 2
			for dx in range(-half, half + 1):
				var tone := EARTH
				if dy == -ry or (absi(dx) >= half - 1 and dy < 0):
					tone = EARTH_LIGHT
				elif dy >= ry - 1 or absi(dx) >= half - 1:
					tone = EARTH_DARK
				elif (dx + dy * 3) % 7 == 0 and _hash(cx + dx, dy) % 2 == 0:
					tone = EARTH_DARK
				_put(px, cx + dx, cy + dy, tone)
			if dy == ry:
				for dx in range(-half, half + 1, 3):
					_put(px, cx + dx, cy + dy, BASE)
					_put(px, cx + dx, cy + dy - 1, LIGHT)


## Stones in the ditch: a lit top, a dark foot.
static func _stones(px: PackedByteArray) -> void:
	for i in DITCH_STONES:
		var h := _hash(i, 3301)
		var x := (i * W) / DITCH_STONES + (h >> 5) % 24
		var y := 2 + (h >> 11) % 3
		var w := 2 + (h >> 13) % 3
		for dx in w:
			_put(px, x + dx, y, STONE_LIGHT if dx < w - 1 else STONE)
			_put(px, x + dx, y + 1, STONE if dx < w - 1 else STONE_DARK)
			_put(px, x + dx, y + 2, DEEP)


static func _stamps(px: PackedByteArray) -> void:
	for s in STAMPS.size():
		var rows: Array = STAMPS[s]
		var y0 := GROUND_H + STAMP_CELL.y - rows.size()
		for r in rows.size():
			var row: String = rows[r]
			for c in row.length():
				if STAMP_INDEX.has(row[c]):
					var i := (y0 + r) * W + s * STAMP_CELL.x + c
					px[i] = int(STAMP_INDEX[row[c]]) * INDEX_SCALE


## The ground wraps in x, so it tiles; it never spills into the stamps.
static func _put(px: PackedByteArray, x: int, y: int, tone: int) -> void:
	if y >= 0 and y < GROUND_H:
		px[y * W + posmod(x, W)] = tone * INDEX_SCALE


static func _hash(a: int, b: int) -> int:
	var h := ((a * 73856093) ^ (b * 19349663)) & 0x7fffffff
	h ^= h >> 13
	h = (h * 1274126177) & 0x7fffffff
	return h ^ (h >> 16)
