extends RefCounted
## The Foundry Pact's hand: the enemy's armour, in the same hand as our tank (assets/tank/v3/tools_src/hull.gd: a 1 px
## outline, plates lit along their top and left and dark along their right and bottom, a one-pixel rivet head with its
## shadow down-right) and the opposite logic: ours is patched and open, theirs is sealed factory slab. Flat decks,
## straight facets, welded seams (a dashed bead, 2 on, 1 off), rivets only where the layout asks for them (skirts,
## hatches, mantlets, access plates), stowage, stencilled marks. Everything is painted straight onto the final palette:
## a pixel keeps its ramp, so grey stays grey and dark yellow stays yellow.
##
## A picture is painted on a canvas (canvas()): part() for each plated part, then details, mud(), streaks(), moon(),
## rivets(). No noise is filtered away afterwards, because none is put on.

const Px = preload("res://assets/tank/v3/tools_src/px.gd")
const Hull = preload("res://assets/tank/v3/tools_src/hull.gd")

const OUTLINE := Color("#040504")
const GREY: Array[Color] = [
	Color("#0c100f"), Color("#151b19"), Color("#202825"), Color("#2d3733"), Color("#434f48")
]
const YELLOW: Array[Color] = [
	Color("#16160d"), Color("#26251a"), Color("#39371f"), Color("#4f4c30")
]
const GRIME: Array[Color] = [Color("#1b1a10"), Color("#2c2a17")]
const CHIP := Color("#4a4f4c")
## The moon's cold rim, on top edges with open sky over them.
const MOON: Array[Color] = [Color("#46555a"), Color("#5c6e75")]
## The stencil's paint: the mark and the numbers. The one pale thing on the armour.
const BONE := Color("#a8ad9c")
## Fastener heads, in colours nothing else uses.
const RIV_LIT := Color("#505b4f")
const RIV_DIM := Color("#384139")
const RIV_LOW := Color("#262c27")
## A head on a plate darker than this (L, 0..255) is a step over it and no more.
const RIV_LOW_UNDER := 22.0
## Slit and lamp glass.
const SLIT_CORE := Color("#d8fff4")
const SLIT_GLOW := Color("#7fe0d0")
const GLASS_DARK := Color("#0f1a1c")

const PAINT_GREY := 0
const PAINT_YELLOW := 1

## The value a plate is painted at, by the share of the way from the deck to the road: decks near the moon, the hull's
## middle, then a fall towards the road. Three values from across a field.
const DECK_L := 40.0
const MID_L := 27.0
const LOW_L := 13.0
const DECK_SHARE := 0.2
const MID_SHARE := 0.45
## Each plate's own value on its part: enough to move a band's edge a few rows, never a patchwork.
const PLATE_TONES: Array[float] = [0.9, 1.15, 1.0, 0.85, 1.2, 1.05]
## A level top edge shows the moon only with this much open sky over it.
const RIM_CLEAR := 5
## A turret's plates stand this far over the hull's: it stands nearer the moon.
const TURRET_BOOST := 1.3
## A rivet's pace along its row, about 7 px, and how a stepped paint band leans.
const RIVET_PACE := 7
const BAND_STEP_ROWS := 4
const BAND_CHIP_ROWS := 3
const BAND_CHIP := 2
## The stencil digits, only those a mirror leaves alone: a turret's traverse and a flip mirror them.
const DIGITS_3X5 := {
	"0": ["###", "#.#", "#.#", "#.#", "###"],
	"1": ["###", ".#.", ".#.", ".#.", "###"],
	"8": ["###", "#.#", "###", "#.#", "###"],
}
const DIGITS_5X7 := {
	"0": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"1": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
}

static var _steps: Dictionary = {}


## L, 0..255.
static func luma(c: Color) -> float:
	return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255.0


static func ramp(paint: int) -> Array[Color]:
	return YELLOW if paint == PAINT_YELLOW else GREY


## The step of a ramp nearest to the value `l`.
static func snap(paint: int, l: float) -> Color:
	var best := GREY[0]
	var bd := INF
	for c in ramp(paint):
		var d := absf(luma(c) - l)
		if d < bd:
			bd = d
			best = c
	return best


## `n` steps up or down the ramp `c` lies on. A colour on no ramp stays.
static func shift(c: Color, n: int) -> Color:
	if _steps.is_empty():
		for r: Array in [GREY, YELLOW, GRIME]:
			for i in r.size():
				_steps[(r[i] as Color).to_html(false)] = [r, i]
	var at: Variant = _steps.get(c.to_html(false))
	if at == null:
		return c
	var r2: Array = at[0]
	return r2[clampi(int(at[1]) + n, 0, r2.size() - 1)]


## True on a ramp: paint, not a head, glass, a mark or the outline.
static func is_paint(c: Color) -> bool:
	if c.a < 0.5:
		return false
	shift(c, 0)
	return _steps.has(c.to_html(false))


# --- the canvas -----------------------------------------------------------------------------------------------


## A picture being painted. `span`: the rows the value falls over (deck, road). `bands`: [x0, x1, lean], the stretches
## in the other paint, their edges stepping `lean` px every BAND_STEP_ROWS rows. `paint`: the hull's main paint.
## `boost`: a turret stands nearer the moon.
static func canvas(
	sz: Vector2i, span: Vector2i, bands: Array, paint: int, boost: float, seed: int
) -> Dictionary:
	var ids := PackedInt32Array()
	ids.resize(sz.x * sz.y)
	ids.fill(-1)
	return {
		"img": Px.blank(sz.x, sz.y),
		"ids": ids,
		"plates": 0,
		"span": span,
		"bands": bands,
		"paint": paint,
		"boost": boost,
		"band_step": 0,
		"seed": seed,
	}


static func paint_at(cv: Dictionary, x: int, y: int) -> int:
	var main := int(cv["paint"])
	return (PAINT_GREY if main == PAINT_YELLOW else PAINT_YELLOW) if in_band(cv, x, y) else main


## True in one of the canvas's bands. Each band's edge leans in hard steps and is chipped every BAND_CHIP_ROWS, on its
## own hash at each side, so no edge runs straight and no two edges match.
static func in_band(cv: Dictionary, x: int, y: int) -> bool:
	var row := floori(float(y) / BAND_CHIP_ROWS)
	for i in (cv["bands"] as Array).size():
		var b: Array = cv["bands"][i]
		var off := int(b[2]) * floori(float(y) / BAND_STEP_ROWS)
		var left := int(b[0]) + off + _chip(row, i * 2, int(cv["seed"]))
		var right := int(b[1]) + off + _chip(row, i * 2 + 1, int(cv["seed"]))
		if x >= left and x < right:
			return true
	return false


## A band edge's chip at a run of rows: -BAND_CHIP..BAND_CHIP px, on nothing regular, so it never reads as a zig-zag.
static func _chip(row: int, edge: int, seed: int) -> int:
	return roundi((Px.h2(row, edge, seed + 37) - 0.5) * 2.0 * BAND_CHIP)


static func value_at(cv: Dictionary, y: int) -> float:
	var span: Vector2i = cv["span"]
	var t := clampf(float(y - span.x) / maxf(float(span.y - span.x), 1.0), 0.0, 1.0)
	if t <= DECK_SHARE:
		return DECK_L
	if t <= MID_SHARE:
		return MID_L
	return lerpf(MID_L, LOW_L, (t - MID_SHARE) / (1.0 - MID_SHARE))


## One plated part: its plates filled, each at its own value and paint; its seams welded; its edges lit top and left,
## dark right and bottom; its outline. Keys: poly, seams_x, seams_y, seed, step (ramp steps on the whole part),
## row_steps (ramp steps per row of plates), col_steps (per column of plates, cycled), paint (the part's own paint,
## over the bands), cast (no seams: lit by how near an edge it is), row_weld (false: a row seam is a bare break of value,
## a bend in one plate and no weld).
static func part(cv: Dictionary, p: Dictionary) -> void:
	var img: Image = cv["img"]
	var ids: PackedInt32Array = cv["ids"]
	var w := img.get_width()
	var h := img.get_height()
	var poly: PackedVector2Array = p["poly"]
	var bb := Px.poly_bounds(poly)
	var seed := int(p.get("seed", 0))
	var cast := bool(p.get("cast", false))
	var own := PackedByteArray()
	own.resize(w * h)
	for y in range(maxi(bb.position.y, 0), mini(bb.end.y, h)):
		for x in range(maxi(bb.position.x, 0), mini(bb.end.x, w)):
			if Px.in_poly(Vector2(x + 0.5, y + 0.5), poly):
				own[y * w + x] = 1
	var plates: Array[Rect2i] = Hull._plates(
		bb, p.get("seams_x", []), p.get("seams_y", []), seed, false
	)
	var ys: Array = p.get("seams_y", [])
	var row_steps: Array = p.get("row_steps", [])
	var col_steps: Array = p.get("col_steps", [])
	var xs: Array = p.get("seams_x", [])
	var first := int(cv["plates"])
	for k in plates.size():
		var pr := plates[k]
		var tone: float = PLATE_TONES[posmod(k + seed, PLATE_TONES.size())]
		# a plate is one clean paint, its value taken at its middle, so the value falls in steps on the seams
		var l := value_at(cv, pr.get_center().y) * tone * float(cv["boost"])
		var extra := int(p.get("step", 0))
		if not row_steps.is_empty():
			extra += int(row_steps[mini(_band_of(ys, pr.position.y), row_steps.size() - 1)])
		if not col_steps.is_empty():
			extra += int(col_steps[posmod(_band_of(xs, pr.position.x), col_steps.size())])
		for y in range(maxi(pr.position.y, 0), mini(pr.end.y, h)):
			for x in range(maxi(pr.position.x, 0), mini(pr.end.x, w)):
				if own[y * w + x] == 0:
					continue
				var paint := int(p["paint"]) if p.has("paint") else paint_at(cv, x, y)
				var col := snap(paint, l)
				var d := extra
				if int(cv["band_step"]) != 0 and not p.has("paint") and in_band(cv, x, y):
					d += int(cv["band_step"])
				if _is_edge(own, w, h, x, y):
					img.set_pixel(x, y, OUTLINE)
					ids[y * w + x] = -1
					continue
				if cast:
					d += _cast_step(own, w, h, x, y)
				else:
					d += _edge_step(own, w, h, x, y, pr, seed, bool(p.get("row_weld", true)))
				img.set_pixel(x, y, shift(col, d))
				ids[y * w + x] = first + k
	cv["plates"] = first + plates.size()


static func _band_of(seams: Array, at: int) -> int:
	var n := 0
	for s: int in seams:
		if at >= s:
			n += 1
	return n


static func _own(own: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h and own[y * w + x] != 0


static func _is_edge(own: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
	return (
		not _own(own, w, h, x - 1, y)
		or not _own(own, w, h, x + 1, y)
		or not _own(own, w, h, x, y - 1)
		or not _own(own, w, h, x, y + 1)
	)


## The plate-edge rule and the welds, in ramp steps: top and left lit, a seam's far side dark (at a part's right and
## bottom the outline is the dark). A seam's weld is a dashed bead, 2 on, 1 off.
static func _edge_step(
	own: PackedByteArray, w: int, h: int, x: int, y: int, pr: Rect2i, seed: int, row_weld: bool
) -> int:
	if _under_top(own, w, h, x, y) and (_under_top(own, w, h, x - 1, y) or _under_top(own, w, h, x + 1, y)):
		return 1
	if not _own(own, w, h, x, y - 2):
		return 0
	if row_weld and y == pr.position.y:
		return 1 if posmod(x + seed, 3) != 2 else 0
	if row_weld and y == pr.end.y - 1:
		return -1
	if not _own(own, w, h, x - 2, y) and _own(own, w, h, x - 2, y - 1) == _own(own, w, h, x - 2, y):
		return 1
	if x == pr.position.x:
		return 1 if posmod(y + seed, 3) != 2 else 0
	if x == pr.end.x - 1:
		return -1
	return 0


## True on the row just under a part's top outline. A stair of single pixels takes no lit edge: it would be pepper.
static func _under_top(own: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
	return _own(own, w, h, x, y) and _own(own, w, h, x, y - 1) and not _own(own, w, h, x, y - 2)


## A cast part reads by its form: lit where it faces the moon, dark on its lower right.
static func _cast_step(own: PackedByteArray, w: int, h: int, x: int, y: int) -> int:
	var up := 3
	for k in range(1, 4):
		if not _own(own, w, h, x, y - k):
			up = k - 1
			break
	if up < 2:
		return 1
	if not _own(own, w, h, x, y + 2) or not _own(own, w, h, x + 2, y):
		return -1
	return 0


## The plate colour under a point, or `fallback` off the armour.
static func under(cv: Dictionary, q: Vector2i, fallback: Color) -> Color:
	var img: Image = cv["img"]
	if not Px.inside(img, q.x, q.y):
		return fallback
	var c := img.get_pixel(q.x, q.y)
	return c if is_paint(c) else fallback


# --- what lies over the plates ----------------------------------------------------------------------------------


## The mud line over the low third of a run of rows: dried grime with a torn upper edge. Nothing but paint takes it, and
## nothing at or under `floor_y` (the belly).
static func mud(cv: Dictionary, top: int, low: int, floor_y: int) -> void:
	var img: Image = cv["img"]
	var ids: PackedInt32Array = cv["ids"]
	var w := img.get_width()
	var seed := int(cv["seed"])
	var line := low - (low - top) / 3
	var solid := low - (low - top) / 6
	for x in w:
		var edge := line + roundi((Px.vnoise(float(x), 0.0, 9.0, seed + 61) - 0.5) * 7.0)
		# the odd splash up the plate, 2 px wide
		var splash := Px.h2(x / 2, 1, seed + 62) > 0.84
		for y in range(edge, mini(low + 1, floor_y)):
			if not Px.inside(img, x, y) or ids[y * w + x] < 0:
				continue
			# high up only where a splash ran down, whole near the road
			if y < solid and not splash:
				continue
			var c := img.get_pixel(x, y)
			if is_paint(c):
				img.set_pixel(x, y, GRIME[1] if luma(c) >= 45.0 else GRIME[0])


## Grime run down the plates, one to about `every` px of hull: 1 px wide, 4-12 long, from a seam. Darker on a lit plate,
## on a dark plate a dried pale line. Stops at the plate's end.
static func streaks(cv: Dictionary, every: int) -> void:
	var img: Image = cv["img"]
	var ids: PackedInt32Array = cv["ids"]
	var w := img.get_width()
	var h := img.get_height()
	var seed := int(cv["seed"]) + 70
	var x := 2 + floori(Px.h2(seed, 1, 3) * float(every))
	while x < w - 2:
		for y0 in range(1, h - 1):
			var id := ids[y0 * w + x]
			if id >= 0 and ids[(y0 - 1) * w + x] != id:
				if Px.h2(x, y0, seed) < 0.75:
					_run(img, ids, Vector2i(x, y0 + 1), 4 + floori(Px.h2(y0, x, seed) * 9.0))
		x += every - 2 + floori(Px.h2(x, 3, seed) * 5.0)


## One streak from `at`, keeping to its plate.
static func _run(img: Image, ids: PackedInt32Array, at: Vector2i, n: int) -> void:
	var w := img.get_width()
	var h := img.get_height()
	if at.y >= h:
		return
	var id := ids[at.y * w + at.x]
	for i in n:
		var y := at.y + i
		if y >= h or ids[y * w + at.x] != id or id < 0:
			return
		var c := img.get_pixel(at.x, y)
		if not is_paint(c):
			return
		img.set_pixel(at.x, y, streak_of(c))


## A streak's colour on a plate: always a visible step off it.
static func streak_of(c: Color) -> Color:
	var l := luma(c)
	if l >= 32.0:
		return GRIME[0]
	if l >= 20.0:
		return GREY[0]
	return GRIME[0]


## The moon: a cold rim under the outline on a top edge with open sky over it, in long broken runs, its bright step only
## on a level edge (`hot_all`: everywhere). `share` of the edge takes it.
static func moon(cv: Dictionary, share: float = 0.66, hot_all: bool = false) -> void:
	var img: Image = cv["img"]
	var src := img.duplicate() as Image
	var w := src.get_width()
	var h := src.get_height()
	for x in w:
		for y in range(1, h - 1):
			if src.get_pixel(x, y).a < 0.5 or src.get_pixel(x, y - 1).a > 0.5:
				continue
			var open := true
			for k in range(2, RIM_CLEAR + 1):
				if y - k >= 0 and src.get_pixel(x, y - k).a > 0.5:
					open = false
					break
			if not open or Px.vnoise(float(x), float(y), 5.0, 7) > share:
				continue
			# a stair of single pixels takes none: it would be pepper
			if not _flat_run(src, x, y):
				continue
			var level := _level_edge(src, x, y)
			var hot := hot_all or (level and Px.h2(x / 3, y, 7) > 0.55)
			_moon_px(img, src, x, y + 1, MOON[1] if hot else MOON[0])
	_no_lone_moon(img)


## A rim runs: a moon pixel with no moon beside it goes back to the plate's lit edge.
static func _no_lone_moon(img: Image) -> void:
	var src := img.duplicate() as Image
	for y in range(1, src.get_height() - 1):
		for x in range(1, src.get_width() - 1):
			if not _is_moon(src.get_pixel(x, y)):
				continue
			var near := false
			for q: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
				near = near or _is_moon(src.get_pixel(x + q.x, y + q.y))
			if not near:
				img.set_pixel(x, y, src.get_pixel(x, y + 1) if is_paint(src.get_pixel(x, y + 1)) else GREY[3])


static func _is_moon(c: Color) -> bool:
	return c.is_equal_approx(MOON[0]) or c.is_equal_approx(MOON[1])


## True when a top edge has a neighbour on its own row, with sky over them both.
static func _flat_run(src: Image, x: int, y: int) -> bool:
	for q: int in [x - 1, x + 1]:
		if q < 0 or q >= src.get_width():
			continue
		if src.get_pixel(q, y).a > 0.5 and src.get_pixel(q, y - 1).a < 0.5:
			return true
	return false


static func _level_edge(src: Image, x: int, y: int) -> bool:
	for dx in range(-3, 4):
		var q := x + dx
		if q < 0 or q >= src.get_width():
			return false
		if src.get_pixel(q, y).a < 0.5 or src.get_pixel(q, y - 1).a > 0.5:
			return false
	return true


static func _moon_px(img: Image, src: Image, x: int, y: int, c: Color) -> void:
	if y >= src.get_height():
		return
	var under_px := src.get_pixel(x, y)
	if is_paint(under_px):
		img.set_pixel(x, y, c)


## One rivet row: [x0, x1, y] along a row, at about RIVET_PACE, some dimmed, some gone, the odd one off its line.
static func rivet_row(cv: Dictionary, row: Array) -> void:
	var seed := int(cv["seed"]) + 80
	var x := int(row[0])
	var y := int(row[2])
	while x <= int(row[1]):
		var jog := 1 if Px.h2(x, y, seed + 3) > 0.9 else 0
		head(cv, Vector2i(x, y + jog))
		x += _pace(x, y, seed)


## One rivet column: [x, y0, y1].
static func rivet_col(cv: Dictionary, col: Array) -> void:
	var seed := int(cv["seed"]) + 90
	var y := int(col[1])
	while y <= int(col[2]):
		head(cv, Vector2i(int(col[0]), y))
		y += _pace(int(col[0]), y, seed)


## The next head's distance: 6, 7 or 8 px.
static func _pace(a: int, b: int, seed: int) -> int:
	var k := Px.h2(a, b, seed)
	return RIVET_PACE - 1 if k < 0.3 else (RIVET_PACE + 1 if k > 0.7 else RIVET_PACE)


## One head: 1 px, its shadow down-right. Grime takes some and dims others; a few weep a streak.
static func head(cv: Dictionary, p: Vector2i) -> void:
	var img: Image = cv["img"]
	if not Px.inside(img, p.x, p.y) or not Px.inside(img, p.x + 1, p.y + 1):
		return
	var c := img.get_pixel(p.x, p.y)
	if not is_paint(c):
		return
	var seed := int(cv["seed"]) + 95
	var roll := Px.h2(p.x, p.y, seed)
	var grime := Px.vnoise(float(p.x), float(p.y), 11.0, seed + 1)
	if roll < 0.07 or (grime > 0.8 and roll < 0.4):
		return
	var dim := roll < 0.6 or grime > 0.66
	var col := RIV_DIM if dim else RIV_LIT
	if luma(c) < RIV_LOW_UNDER:
		col = RIV_LOW
	img.set_pixel(p.x, p.y, col)
	# a lit head throws its shadow; grime fills in under a dim one
	if not dim:
		for q: Vector2i in [Vector2i(1, 1), Vector2i(0, 1)]:
			var low := img.get_pixel(p.x + q.x, p.y + q.y)
			if is_paint(low):
				img.set_pixel(p.x + q.x, p.y + q.y, shift(low, -2))
	if Px.h2(p.x, p.y, seed + 2) > 0.86:
		_run(img, cv["ids"], Vector2i(p.x, p.y + 2), 3 + floori(Px.h2(p.y, p.x, seed + 3) * 5.0))


## Chipped paint: a short run of bare steel on a lit edge, one to about `every` px of the picture's width.
static func chips(cv: Dictionary, every: int) -> void:
	var img: Image = cv["img"]
	var ids: PackedInt32Array = cv["ids"]
	var w := img.get_width()
	var h := img.get_height()
	var seed := int(cv["seed"]) + 110
	var x := every / 2
	while x < w - 2:
		for y in range(2, h - 2):
			if ids[y * w + x] >= 0 and ids[(y - 1) * w + x] < 0 and Px.h2(x, y, seed) > 0.5:
				for k in 2:
					if is_paint(img.get_pixel(x + k, y)):
						img.set_pixel(x + k, y, CHIP)
				break
		x += every - 3 + floori(Px.h2(x, 2, seed) * 7.0)


# --- details ------------------------------------------------------------------------------------------------------


## What a layout's detail paints. Colours on the plate's own ramp where the detail is part of the plate.
static func detail(cv: Dictionary, d: Dictionary) -> void:
	var img: Image = cv["img"]
	match str(d["kind"]):
		"hatch":
			_hatch(cv, d["rect"])
		"access":
			_access(cv, d["rect"], bool(d.get("rows", true)))
		"louvre":
			_louvre(cv, d["rect"])
		"box":
			_box(cv, d["rect"], int(d.get("paint", PAINT_GREY)))
		"can":
			_can(img, d["rect"], int(d.get("paint", PAINT_YELLOW)))
		"links":
			_links(img, d["a"], d["b"], int(d.get("n", 3)))
		"rail":
			_rail(img, d["a"], d["b"], int(d.get("drop", 2)), int(d.get("every", 12)))
		"antenna":
			_antenna(img, d["at"], int(d["h"]))
		"stack":
			_stack(img, int(d["x"]), int(d["y0"]), int(d["y1"]))
		"soot":
			_soot(cv, d["rect"])
		"vent":
			_vent(img, d["at"])
		"cable":
			_cable(img, d["a"], d["b"])
		"shovel":
			_shovel(img, d["at"])
		"pick":
			_pick(img, d["at"])
		"bar":
			_bar(img, d["at"], int(d.get("w", 24)))
		"mark":
			_mark(img, d["at"], int(d.get("size", 5)))
		"digits":
			_digits(img, d["at"], str(d["text"]), int(d.get("tall", 5)))
		_:
			push_error("enemy_paint: no detail %s" % d["kind"])


## A shut door: an outlined leaf a step over its plate, a lit top, a dark sill, hinges at its left, a handle, a row of
## heads. No window, no warmth.
static func _hatch(cv: Dictionary, r: Rect2i) -> void:
	var img: Image = cv["img"]
	var at := under(cv, r.position + r.size / 2, GREY[1])
	Px.rect(img, r, OUTLINE)
	var inner := r.grow(-1)
	Px.rect(img, inner, shift(at, 1))
	Px.rect(img, Rect2i(inner.position.x, inner.position.y, inner.size.x, 1), shift(at, 2))
	Px.rect(img, Rect2i(inner.position.x, inner.end.y - 1, inner.size.x, 1), shift(at, -1))
	for hy: int in [r.position.y + 1, r.end.y - 3]:
		Px.rect(img, Rect2i(r.position.x - 1, hy, 2, 2), OUTLINE)
		Px.put(img, r.position.x - 1, hy, GREY[3])
	Px.rect(img, Rect2i(r.end.x - 3, r.position.y + r.size.y / 2 - 1, 1, 2), OUTLINE)
	if r.size.x >= 9:
		rivet_row(cv, [r.position.x + 2, r.end.x - 3, r.end.y - 3])


## A bolted access plate: a dark line round it, its own top lit, a row of heads along its top and its bottom (`rows`
## false: the layout's own rivet rows bolt it).
static func _access(cv: Dictionary, r: Rect2i, rows: bool) -> void:
	var img: Image = cv["img"]
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := img.get_pixel(x, y) if Px.inside(img, x, y) else Color(0, 0, 0, 0)
			if not is_paint(c):
				continue
			var low := y == r.end.y - 1 or x == r.end.x - 1
			var lit := y == r.position.y or x == r.position.x
			img.set_pixel(x, y, shift(c, -1 if low else (1 if lit else 0)))
	if not rows:
		return
	rivet_row(cv, [r.position.x + 2, r.end.x - 3, r.position.y + 2])
	if r.size.y >= 7:
		rivet_row(cv, [r.position.x + 3, r.end.x - 3, r.end.y - 3])


## Engine slats: TankEnemyDraw lights every other row from behind. A row is under 3 tall so the light is a slat, never a
## block.
static func _louvre(cv: Dictionary, r: Rect2i) -> void:
	var img: Image = cv["img"]
	Px.rect(img, r.grow(1), OUTLINE)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var side := x == r.position.x or x == r.end.x - 1
			var col := GREY[2] if side else (GREY[1] if (y - r.position.y) % 2 == 0 else OUTLINE)
			Px.put(img, x, y, col)


## A stowage bin: lid, lid line, body, two latches.
static func _box(cv: Dictionary, r: Rect2i, paint: int) -> void:
	var img: Image = cv["img"]
	var rp := ramp(paint)
	Px.rect(img, r.grow(1), OUTLINE)
	Px.rect(img, r, rp[1])
	Px.rect(img, Rect2i(r.position.x, r.position.y, r.size.x, 1), rp[2])
	if r.size.y >= 4:
		Px.rect(img, Rect2i(r.position.x, r.position.y + 1, r.size.x, 1), rp[1])
		Px.rect(img, Rect2i(r.position.x, r.position.y + 2, r.size.x, 1), OUTLINE)
	for x: int in [r.position.x + 2, r.end.x - 3]:
		Px.put(img, x, r.position.y + 1, CHIP)
	Px.rect(img, Rect2i(r.position.x, r.end.y - 1, r.size.x, 1), rp[0])


## A jerrycan standing on the deck: a body in the rect, a lit shoulder, a dark waist, an outline on its open sides.
static func _can(img: Image, r: Rect2i, paint: int) -> void:
	var rp := ramp(paint)
	Px.rect(img, r.grow(1), OUTLINE)
	Px.rect(img, r, rp[1])
	Px.rect(img, Rect2i(r.position.x, r.position.y, r.size.x, 1), rp[2])
	Px.rect(img, Rect2i(r.position.x, r.position.y + r.size.y / 2, r.size.x, 1), rp[0])


## Spare track links hung along a line.
static func _links(img: Image, a: Vector2, b: Vector2, n: int) -> void:
	var ang := (b - a).angle()
	for k in n:
		var q := a.lerp(b, (float(k) + 0.5) / float(n))
		var half := Vector2(2.2, 2.6)
		var ri := ceili(half.length()) + 1
		for y in range(floori(q.y) - ri, ceili(q.y) + ri):
			for x in range(floori(q.x) - ri, ceili(q.x) + ri):
				var u := (Vector2(x + 0.5, y + 0.5) - q).rotated(-ang)
				if absf(u.x) > half.x or absf(u.y) > half.y:
					continue
				var edge := absf(u.x) > half.x - 1.0 or absf(u.y) > half.y - 1.0
				Px.put(img, x, y, OUTLINE if edge else (GREY[4] if u.y < 0.0 else GREY[2]))


## A rail or a catwalk's handrail: a pale tube, an outline under it, stanchions every `every` px dropping `drop` rows.
static func _rail(img: Image, a: Vector2i, b: Vector2i, drop: int, every: int) -> void:
	var run := maxi(absi(b.x - a.x), 1)
	var k := 0
	while k <= run:
		var x := a.x + (b.x - a.x) * k / run
		var y := a.y + (b.y - a.y) * k / run
		for i in range(1, drop + 1):
			Px.put(img, x, y + i, GREY[2])
			Px.put(img, x + 1, y + i, OUTLINE)
		k += every
	for k2 in run + 1:
		var x2 := a.x + (b.x - a.x) * k2 / run
		var y2 := a.y + (b.y - a.y) * k2 / run
		Px.put(img, x2, y2, GREY[4])
		if not Px.inside(img, x2, y2 + 1) or img.get_pixel(x2, y2 + 1).a < 0.5:
			continue
		if not img.get_pixel(x2, y2 + 1).is_equal_approx(GREY[2]):
			img.set_pixel(x2, y2 + 1, OUTLINE)


static func _antenna(img: Image, at: Vector2i, h: int) -> void:
	for y in range(at.y - h, at.y):
		Px.put(img, at.x, y, GREY[3] if (y - at.y) % 5 == 0 else GREY[2])
	Px.rect(img, Rect2i(at.x - 2, at.y - 2, 5, 3), OUTLINE)
	Px.rect(img, Rect2i(at.x - 1, at.y - 1, 3, 1), GREY[3])


## An exhaust stack: a column lit at its left, its clamp, a capped and sooted head.
static func _stack(img: Image, x0: int, ya: int, yb: int) -> void:
	for y in range(ya, yb):
		Px.put(img, x0 - 2, y, OUTLINE)
		Px.put(img, x0 - 1, y, GREY[4])
		Px.put(img, x0, y, GREY[3])
		Px.put(img, x0 + 1, y, GREY[2])
		Px.put(img, x0 + 2, y, OUTLINE)
	Px.rect(img, Rect2i(x0 - 3, ya - 2, 7, 3), OUTLINE)
	Px.rect(img, Rect2i(x0 - 2, ya - 1, 5, 1), GRIME[1])
	Px.rect(img, Rect2i(x0 - 1, ya - 1, 3, 1), GREY[0])
	Px.rect(img, Rect2i(x0 - 2, yb - 5, 5, 1), GREY[4])


## Soot fanned down from an exhaust: a hard wedge of paint a step darker.
static func _soot(cv: Dictionary, r: Rect2i) -> void:
	var img: Image = cv["img"]
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if not Px.inside(img, x, y):
				continue
			var c := img.get_pixel(x, y)
			if not is_paint(c):
				continue
			var f := 1.0 - float(y - r.position.y) / r.size.y
			var cx := absf(x - r.position.x - r.size.x * 0.5) / (r.size.x * 0.5)
			if f * (1.0 - cx) > 0.25:
				img.set_pixel(x, y, shift(c, -1))


## A mushroom vent on a deck.
static func _vent(img: Image, p: Vector2i) -> void:
	Px.rect(img, Rect2i(p.x - 3, p.y - 3, 7, 4), OUTLINE)
	Px.rect(img, Rect2i(p.x - 2, p.y - 2, 5, 2), GREY[3])
	Px.rect(img, Rect2i(p.x - 2, p.y - 2, 5, 1), GREY[4])
	Px.rect(img, Rect2i(p.x - 1, p.y, 3, 1), GREY[1])


## Tow cable along the hull in clamps, an eye at each end.
static func _cable(img: Image, a: Vector2i, b: Vector2i) -> void:
	for x in range(a.x, b.x + 1):
		Px.put(img, x, a.y, GREY[4] if (x - a.x) % 4 < 2 else GREY[2])
		Px.put(img, x, a.y + 1, OUTLINE)
	for x2 in range(a.x + 6, b.x - 4, 18):
		Px.rect(img, Rect2i(x2, a.y - 1, 2, 2), GREY[3])
	for e: int in [a.x - 3, b.x + 1]:
		Px.rect(img, Rect2i(e, a.y - 1, 3, 3), GREY[3])
		Px.put(img, e + 1, a.y, OUTLINE)


static func _shovel(img: Image, a: Vector2i) -> void:
	Px.line(img, a + Vector2i(0, 1), a + Vector2i(16, 1), OUTLINE)
	Px.line(img, a, a + Vector2i(15, 0), GRIME[1])
	Px.rect(img, Rect2i(a.x + 16, a.y - 2, 5, 5), OUTLINE)
	Px.rect(img, Rect2i(a.x + 16, a.y - 1, 4, 3), GREY[4])
	Px.put(img, a.x - 1, a.y, OUTLINE)
	for k: int in [4, 12]:
		Px.rect(img, Rect2i(a.x + k, a.y, 2, 1), GREY[3])


static func _pick(img: Image, a: Vector2i) -> void:
	Px.line(img, a + Vector2i(0, 1), a + Vector2i(17, 1), OUTLINE)
	Px.line(img, a, a + Vector2i(16, 0), GRIME[1])
	Px.line(img, a + Vector2i(17, -4), a + Vector2i(19, 4), OUTLINE)
	Px.line(img, a + Vector2i(18, -3), a + Vector2i(20, 3), GREY[4])
	Px.rect(img, Rect2i(a.x + 5, a.y, 2, 1), GREY[3])


static func _bar(img: Image, a: Vector2i, w: int) -> void:
	Px.line(img, a + Vector2i(0, 1), a + Vector2i(w, 1), OUTLINE)
	Px.line(img, a, a + Vector2i(w, 0), GREY[3])


## The Pact's mark: a hollow bone diamond on a dark plate, its centre always the plate, so no cross can form in it. `size`
## 3 on a plate of 5 x 3, 5 on 7 x 7, 9 on 11 x 11. `at` is the plate's top left.
static func _mark(img: Image, at: Vector2i, size: int) -> void:
	var r := size / 2
	# the little one, on a box of four open rows, has no room for a plate above and below it
	var pad_y := 0 if size == 3 else 1
	Px.rect(img, Rect2i(at, Vector2i(size + 2, size + pad_y * 2)), GREY[0])
	var c := at + Vector2i(r + 1, r + pad_y)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if absi(dx) + absi(dy) == r:
				Px.put(img, c.x + dx, c.y + dy, BONE)


## Stencil digits: `tall` 5 is 3 x 5, 7 is 5 x 7, a clear column between them.
static func _digits(img: Image, at: Vector2i, text: String, tall: int) -> void:
	var table: Dictionary = DIGITS_5X7 if tall == 7 else DIGITS_3X5
	var x := at.x
	for ch in text:
		var rows: Array = table[ch]
		for j in rows.size():
			var row: String = rows[j]
			for i in row.length():
				if row[i] == "#":
					Px.put(img, x + i, at.y + j, BONE)
		x += (rows[0] as String).length() + 1
