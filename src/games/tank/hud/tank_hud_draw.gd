class_name TankHudDraw
extends RefCounted
## Drawing helpers for Diesel Domestiques' own HUD (brief 3.6). Every call takes art px of the
## 960 x 540 base: each TankHudCtl sets draw_set_transform(scale = screen px per art px, 2 at
## 1080p) before it draws, and the Controls filter nearest, so every pixel lands on the art grid.
## The look: riveted dark-iron plates (panel #17140f, a 1 px brass frame #8a6a3a with a darker
## inner line, rivet pixels along it and 2 x 2 rivets in the corners), warm paper text #e8dcc0 and
## dim #a3937a in the stencil faces (TankHudFont), key numbers in the 14 x 24 digit face, bar
## tracks #3a3128 with brass / amber #e3a24a fills, red #c4553c only past a limit, riders only in
## slot colours.

const PANEL := Color("#17140f")
const PANEL_LIFT := Color("#211c15")
const FRAME := Color("#8a6a3a")
const FRAME_HI := Color("#e3a24a")
const FRAME_IN := Color("#3a2c1b")
const RIVET_HI := Color("#d9b56e")
const RIVET_LO := Color("#070605")
const TEXT := Color("#e8dcc0")
## The key numerals: a warmer, darker paper than TEXT, so the plates never outshine the tank.
const NUM := Color("#cdb88f")
## Power state: under the band (desaturated blue), over it (orange-red), in it (NUM).
const UNDER := Color("#7f9bb0")
const OVER := Color("#e0673c")
const GOOD := Color("#6fae6a")
const COOL := Color("#9fd4ec")
const DIM := Color("#a3937a")
const AMBER := Color("#e3a24a")
const TRACK := Color("#3a3128")
const BRASS := Color("#b08a4a")
const RED := Color("#c4553c")
const SHADOW := Color(0.0, 0.0, 0.0, 0.62)
## The font's cap rows and cell height (TankHudFont.CELL.y).
const CAP := 7
const CELL_H := 9
const SPACE_ADVANCE := 3
const DIGIT_H := 24

const ICONS := {
	"diesel": ["...#...", "..###..", ".#####.", ".#####.", "#######", ".#####.", "..###.."],
	"bulwark": ["...#...", "..###..", ".#####.", ".#####.", "#######", ".#####.", "..###.."],
	"steam": [".#..#..", "..#..#.", ".#..#..", ".......", "#######", "#.....#", "#######"],
	"dynamo": ["....##.", "...##..", "..##...", ".#####.", "...##..", "..##...", ".##...."],
	"arc": ["#.....#", "#.###.#", "##...##", "#.....#", "#..#..#", "#.###.#", "#.....#"],
	"feed": ["..#.#..", ".##.##.", ".##.##.", ".##.##.", ".##.##.", ".......", "#######"],
}
## The slot shapes (Wl.SLOT_SHAPES order), 5 x 5, so a rider's colour always pairs with a shape.
const SHAPES := [
	[".###.", "#####", "#####", "#####", ".###."],
	["..#..", ".###.", ".###.", "#####", "#####"],
	["#####", "#####", "#####", "#####", "#####"],
	["..#..", ".###.", "#####", ".###.", "..#.."],
]

const ELLIPSIS := "…"
const TALL_CAP := 9
const TALL_H := 11

static var _font: Font = null
static var _tall: Font = null
static var _digits: Texture2D = null


## The stencil 5 x 7 face: the space narrowed and every glyph hung from the baseline by the cap
## height (the Image Font importer hangs a glyph by half its cell).
static func font() -> Font:
	if _font == null:
		_font = load(TankHudFont.TEXT_PNG) as Font
		var ff := _font as FontFile
		if ff != null:
			for i in ff.get_cache_count():
				for sz in ff.get_size_cache_list(i):
					for g in ff.get_glyph_list(i, sz):
						ff.set_glyph_offset(i, sz, g, Vector2(0, -CAP))
					ff.set_glyph_advance(i, sz.x, 32, Vector2(SPACE_ADVANCE, 0))
	return _font


## The tall 5 x 9 face (TankHudFont.TALL_PNG), hung from the baseline like font().
static func font_tall() -> Font:
	if _tall == null:
		_tall = load(TankHudFont.TALL_PNG) as Font
		var ff := _tall as FontFile
		if ff != null:
			for i in ff.get_cache_count():
				for sz in ff.get_size_cache_list(i):
					for g in ff.get_glyph_list(i, sz):
						ff.set_glyph_offset(i, sz, g, Vector2(0, -TALL_CAP))
					ff.set_glyph_advance(i, sz.x, 32, Vector2(SPACE_ADVANCE + 1, 0))
	return _tall


## Tall-face text (9 px cap) with its cap top at `top`. Returns its width.
static func tall(c: CanvasItem, x: float, top: float, s: String, col: Color = TEXT) -> float:
	c.draw_string(
		font_tall(),
		Vector2(roundf(x), roundf(top) + TALL_CAP),
		s,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		TALL_H,
		col
	)
	return tall_w(s)


static func tall_w(s: String) -> float:
	var w := font_tall().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, TALL_H).x
	return maxf(w - 1.0, 0.0)


static func tall_r(c: CanvasItem, right: float, top: float, s: String, col: Color = TEXT) -> float:
	var w := tall_w(s)
	tall(c, right - w, top, s, col)
	return w


static func tall_c(c: CanvasItem, cx: float, top: float, s: String, col: Color = TEXT) -> float:
	var w := tall_w(s)
	tall(c, roundf(cx - w * 0.5), top, s, col)
	return w


static func tall_shadow(c: CanvasItem, x: float, top: float, s: String, col: Color = TEXT) -> float:
	tall(c, x + 1, top + 1, s, SHADOW)
	return tall(c, x, top, s, col)


## A gauge: the track, the band [lo, hi] (0..1 of the scale) shaded with brass ends, ticks every
## `tick_n`-th of the scale, and a 1 px needle at `v` (0..1) that stands 2 px proud.
static func gauge(
	c: CanvasItem, r: Rect2, lo: float, hi: float, v: float, needle: Color, tick_n: int = 0
) -> void:
	c.draw_rect(r, TRACK)
	var x0 := r.position.x + roundf(r.size.x * clampf(lo, 0.0, 1.0))
	var x1 := r.position.x + roundf(r.size.x * clampf(hi, 0.0, 1.0))
	if x1 > x0:
		c.draw_rect(Rect2(x0, r.position.y, x1 - x0, r.size.y), Color("#6b5230"))
		c.draw_rect(Rect2(x0, r.position.y - 1, 1, r.size.y + 2), BRASS)
		c.draw_rect(Rect2(x1 - 1, r.position.y - 1, 1, r.size.y + 2), BRASS)
	if tick_n > 1:
		for i in range(1, tick_n):
			var tx := r.position.x + roundf(r.size.x * float(i) / tick_n)
			c.draw_rect(Rect2(tx, r.end.y - 2, 1, 2), PANEL)
	var nx := r.position.x + roundf((r.size.x - 1.0) * clampf(v, 0.0, 1.0))
	c.draw_rect(Rect2(nx, r.position.y - 2, 1, r.size.y + 4), needle)


static func digits() -> Texture2D:
	if _digits == null:
		_digits = load(TankHudFont.DIGITS_PNG) as Texture2D
	return _digits


## Text with its cap top at `top`, left at `x`, `m` glyph px per art px (1 or 2). Returns its width.
static func text(
	c: CanvasItem, x: float, top: float, s: String, col: Color = TEXT, m: int = 1
) -> float:
	var size := CELL_H * m
	c.draw_string(
		font(),
		Vector2(roundf(x), roundf(top) + CAP * m),
		s,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		size,
		col
	)
	return text_w(s, m)


## Text right-aligned to `right`.
static func text_r(
	c: CanvasItem, right: float, top: float, s: String, col: Color = TEXT, m: int = 1
) -> float:
	var w := text_w(s, m)
	text(c, right - w, top, s, col, m)
	return w


## Text centred on `cx`.
static func text_c(
	c: CanvasItem, cx: float, top: float, s: String, col: Color = TEXT, m: int = 1
) -> float:
	var w := text_w(s, m)
	text(c, roundf(cx - w * 0.5), top, s, col, m)
	return w


static func text_w(s: String, m: int = 1) -> float:
	# the last glyph's 1 px gap is not ink
	var w := font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, CELL_H * m).x
	return maxf(w - float(m), 0.0)


## Text with a 1 px dark shadow below-right (for world tags over the scene).
static func text_shadow(
	c: CanvasItem, x: float, top: float, s: String, col: Color = TEXT, m: int = 1
) -> float:
	text(c, x + m, top + m, s, SHADOW, m)
	return text(c, x, top, s, col, m)


## The key-number face: `s` (digits, ':', '.', '-') with its top at `top`, left at `x`. Returns
## its width. Unknown characters advance a digit and draw nothing.
static func big(c: CanvasItem, x: float, top: float, s: String, col: Color = TEXT) -> float:
	var tex := digits()
	var px := roundf(x)
	for i in s.length():
		var ch := s[i]
		var k := TankHudFont.DIGIT_CHARS.find(ch)
		var adv := int(TankHudFont.DIGIT_ADVANCE.get(ch, TankHudFont.DIGIT_ADVANCE_DEFAULT))
		if ch == " ":
			adv = 6
		if k >= 0 and tex != null:
			var src := Rect2(k * TankHudFont.DIGIT_CELL.x, 0, TankHudFont.DIGIT_CELL.x, DIGIT_H)
			c.draw_texture_rect_region(
				tex, Rect2(px, roundf(top), src.size.x, src.size.y), src, col
			)
		px += adv
	return big_w(s)


static func big_w(s: String) -> float:
	var w := 0.0
	for i in s.length():
		var ch := s[i]
		w += (
			6.0
			if ch == " "
			else float(TankHudFont.DIGIT_ADVANCE.get(ch, TankHudFont.DIGIT_ADVANCE_DEFAULT))
		)
	return maxf(w - 2.0, 0.0)


static func big_r(c: CanvasItem, right: float, top: float, s: String, col: Color = TEXT) -> float:
	var w := big_w(s)
	big(c, right - w, top, s, col)
	return w


static func rect(c: CanvasItem, r: Rect2, col: Color) -> void:
	c.draw_rect(r, col)


## A one-pixel frame just inside `r`.
static func frame(c: CanvasItem, r: Rect2, col: Color) -> void:
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), col)
	c.draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), col)
	c.draw_rect(Rect2(r.position.x, r.position.y + 1, 1, r.size.y - 2), col)
	c.draw_rect(Rect2(r.end.x - 1, r.position.y + 1, 1, r.size.y - 2), col)


## A 2 x 2 rivet, lit from the top left.
static func rivet(c: CanvasItem, p: Vector2) -> void:
	c.draw_rect(Rect2(p, Vector2(2, 2)), BRASS)
	c.draw_rect(Rect2(p, Vector2(1, 1)), RIVET_HI)
	c.draw_rect(Rect2(p + Vector2(1, 1), Vector2(1, 1)), RIVET_LO)


## A riveted dark-iron plate filling `r`: the panel, a 1 px frame (`edge`, brass by default)
## with the darker inner line, rivet pixels every `pitch` px along the top and bottom edges and
## 2 x 2 rivets in the corners.
static func plate(c: CanvasItem, r: Rect2, edge: Color = FRAME, pitch: int = 18) -> void:
	r = Rect2(r.position.round(), r.size.round())
	c.draw_rect(r, PANEL)
	# a lighter band under the top edge: the plate's rolled lip
	c.draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4, 1)), PANEL_LIFT)
	frame(c, r, edge)
	frame(c, r.grow(-1), FRAME_IN)
	if pitch > 0 and r.size.x > 24:
		var n := floori((r.size.x - 12.0) / float(pitch))
		var x0 := r.position.x + roundf((r.size.x - float(n) * pitch) * 0.5)
		for i in n + 1:
			var x := x0 + float(i) * pitch
			if x < r.position.x + 7 or x > r.end.x - 8:
				continue
			c.draw_rect(Rect2(x, r.position.y, 1, 1), RIVET_HI)
			c.draw_rect(Rect2(x, r.end.y - 1, 1, 1), RIVET_HI)
	for p in [
		r.position + Vector2(2, 2),
		Vector2(r.end.x - 4, r.position.y + 2),
		Vector2(r.position.x + 2, r.end.y - 4),
		r.end - Vector2(4, 4)
	]:
		rivet(c, p)


## A bar filled `frac` of the way on its track, in whole pixels.
static func bar(c: CanvasItem, r: Rect2, frac: float, col: Color, track: Color = TRACK) -> void:
	c.draw_rect(r, track)
	var w := roundf(r.size.x * clampf(frac, 0.0, 1.0))
	if w > 0.0:
		c.draw_rect(Rect2(r.position, Vector2(w, r.size.y)), col)


## A pixel pattern ("#" ink), top-left at `p`, `m` px per pattern pixel.
static func pixels(c: CanvasItem, rows: Array, p: Vector2, col: Color, m: float = 1.0) -> void:
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] == "#":
				c.draw_rect(Rect2(p + Vector2(x, y) * m, Vector2(m, m)), col)


static func icon(c: CanvasItem, engine: String, p: Vector2, col: Color) -> void:
	pixels(c, ICONS.get(engine, ICONS["diesel"]), p, col)


## Slot `slot`'s chip: its shape in its colour.
static func chip(c: CanvasItem, slot: int, p: Vector2, col: Color) -> void:
	pixels(c, SHAPES[posmod(slot, 4)], p, col)


## A slot colour lifted for text on the dark plates (blue would sink otherwise).
static func slot_text(col: Color) -> Color:
	return col.lerp(Color.WHITE, 0.3) if col.get_luminance() < 0.45 else col


## An indicator lamp (5 x 5, round): lit in `col` with a 1 px halo, or a dark glass.
static func lamp(c: CanvasItem, p: Vector2, lit: bool, col: Color = AMBER) -> void:
	var rows := [".###.", "#####", "#####", "#####", ".###."]
	if lit:
		c.draw_rect(Rect2(p - Vector2(1, 1), Vector2(7, 7)), Color(col.r, col.g, col.b, 0.25))
		pixels(c, rows, p, col)
		c.draw_rect(Rect2(p + Vector2(1, 1), Vector2(1, 1)), Color(1, 1, 1, 0.85))
	else:
		pixels(c, rows, p, Color("#2a231b"))
		c.draw_rect(Rect2(p + Vector2(1, 1), Vector2(1, 1)), Color("#4a4033"))


## `s` cut to fit `max_w` art px in the tall face, an ellipsis replacing the cut ("" when not even
## the ellipsis fits).
static func fit_tall(s: String, max_w: float) -> String:
	if tall_w(s) <= max_w:
		return s
	var cut := s
	while cut.length() > 0:
		cut = cut.substr(0, cut.length() - 1).strip_edges()
		if tall_w(cut + ELLIPSIS) <= max_w:
			return cut + ELLIPSIS
	return ELLIPSIS if tall_w(ELLIPSIS) <= max_w else ""


static func clock(s: float) -> String:
	var t := maxi(ceili(s), 0)
	return "%d:%02d" % [t / 60, t % 60]
