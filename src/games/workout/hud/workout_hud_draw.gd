class_name WorkoutHudDraw
extends RefCounted
## Drawing helpers for Workout's own HUD. Every call takes art px of the 960 x 540 base: each
## WorkoutHudCtl sets draw_set_transform(scale = screen px per art px, 2 at 1080p) before it draws,
## and the Controls filter nearest, so every pixel lands on the art grid. The look: an enamel road
## sign, not iron and not stone: a dark blue-black panel, a 1 px steel frame with a darker inner line
## and 2 x 2 corner studs, cream text, amber only where a thing needs the eye.

const PANEL := Color("#141a24")
const PANEL_LIFT := Color("#1d2533")
const FRAME := Color("#56708a")
const FRAME_HI := Color("#f2b94a")
const FRAME_IN := Color("#2a3646")
const TEXT := Color("#eef0e6")
const NUM := Color("#f4e9c8")
const DIM := Color("#93a3b2")
const AMBER := Color("#f2b94a")
const UNDER := Color("#7fb0d8")
const OVER := Color("#e8683c")
const GOOD := Color("#6fcf7a")
const TRACK := Color("#2a3442")
## The gauge's band shade.
const BAND := Color("#46617a")
const LAMP_OFF := Color("#2a3442")
const LAMP_OFF_GLASS := Color("#46546a")
const STUD := Color("#8fa6bb")
const SHADOW := Color(0.0, 0.0, 0.0, 0.62)

const TEXT_PNG := "res://assets/workout/hud/wo_text_5x7.png"
const TALL_PNG := "res://assets/workout/hud/wo_tall_5x9.png"
const DIGITS_PNG := "res://assets/workout/hud/wo_digits_14x24.png"
const CRANK_PNG := "res://assets/workout/hud/hud_crank.png"
## The font's cap rows and cell height.
const CAP := 7
const CELL_H := 9
const TALL_CAP := 9
const TALL_H := 11
const SPACE_ADVANCE := 3
const DIGIT_CHARS := "0123456789:.-"
const DIGIT_CELL := Vector2i(14, 24)
const DIGIT_ADVANCE := {":": 9, ".": 7}
const DIGIT_ADVANCE_DEFAULT := 16
const CRANK_CELL := 27
const ELLIPSIS := "…"

## The slot shapes (Wl.SLOT_SHAPES order), 5 x 5, so a rider's colour always pairs with a shape.
const SHAPES := [
	[".###.", "#####", "#####", "#####", ".###."],
	["..#..", ".###.", ".###.", "#####", "#####"],
	["#####", "#####", "#####", "#####", "#####"],
	["..#..", ".###.", "#####", ".###.", "..#.."],
]
## The same shapes hollow, for slots 4-7 (Wl.slot_look's `hollow`).
const SHAPES_HOLLOW := [
	[".###.", "#...#", "#...#", "#...#", ".###."],
	["..#..", ".#.#.", ".#.#.", "#...#", "#####"],
	["#####", "#...#", "#...#", "#...#", "#####"],
	["..#..", ".#.#.", "#...#", ".#.#.", "..#.."],
]
const LAMP_ROWS := [".###.", "#####", "#####", "#####", ".###."]
const HATCH_SIZE := 4

static var _digits: Texture2D = null
static var _crank: Texture2D = null
static var _hatch: ImageTexture = null


## The 5 x 7 face: the space narrowed and every glyph hung from the baseline by the cap height (the
## Image Font importer hangs a glyph by half its cell).
static func font() -> Font:
	return PixelFont.hang(TEXT_PNG, CAP, SPACE_ADVANCE)


## The tall 5 x 9 face, hung from the baseline like font().
static func font_tall() -> Font:
	return PixelFont.hang(TALL_PNG, TALL_CAP, SPACE_ADVANCE + 1)


static func digits() -> Texture2D:
	if _digits == null:
		_digits = load(DIGITS_PNG) as Texture2D
	return _digits


static func crank_texture() -> Texture2D:
	if _crank == null:
		_crank = load(CRANK_PNG) as Texture2D
	return _crank


## A small diagonal hatch, tiled over the SIM and FREE blocks of the timeline (the Control sets
## texture_repeat), so a whole session of them is one draw call per block.
static func hatch() -> ImageTexture:
	if _hatch == null:
		var img := Image.create_empty(HATCH_SIZE, HATCH_SIZE, false, Image.FORMAT_RGBA8)
		for y in HATCH_SIZE:
			for x in HATCH_SIZE:
				if (x + y) % HATCH_SIZE == 0:
					img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.42))
		_hatch = ImageTexture.create_from_image(img)
	return _hatch


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


## Text with its cap top at `top`, left at `x`, `m` glyph px per art px. Returns its width.
static func text(
	c: CanvasItem, x: float, top: float, s: String, col: Color = TEXT, m: int = 1
) -> float:
	c.draw_string(
		font(),
		Vector2(roundf(x), roundf(top) + CAP * m),
		s,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		CELL_H * m,
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


static func text_w(s: String, m: int = 1) -> float:
	# the last glyph's 1 px gap is not ink
	var w := font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, CELL_H * m).x
	return maxf(w - float(m), 0.0)


## The key-number face: `s` (digits, ':', '.', '-') with its top at `top`, left at `x`. Returns its
## width. Unknown characters advance a digit and draw nothing.
static func big(c: CanvasItem, x: float, top: float, s: String, col: Color = TEXT) -> float:
	var tex := digits()
	var px := roundf(x)
	for i in s.length():
		var ch := s[i]
		var k := DIGIT_CHARS.find(ch)
		if k >= 0 and tex != null:
			var src := Rect2(k * DIGIT_CELL.x, 0, DIGIT_CELL.x, DIGIT_CELL.y)
			c.draw_texture_rect_region(
				tex, Rect2(px, roundf(top), src.size.x, src.size.y), src, col
			)
		px += _big_advance(ch)
	return big_w(s)


static func _big_advance(ch: String) -> int:
	return 6 if ch == " " else int(DIGIT_ADVANCE.get(ch, DIGIT_ADVANCE_DEFAULT))


static func big_w(s: String) -> float:
	var w := 0
	for i in s.length():
		w += _big_advance(s[i])
	return maxf(float(w) - 2.0, 0.0)


static func big_r(c: CanvasItem, right: float, top: float, s: String, col: Color = TEXT) -> float:
	var w := big_w(s)
	big(c, right - w, top, s, col)
	return w


static func rect(c: CanvasItem, r: Rect2, col: Color) -> void:
	c.draw_rect(r, col)


## A one-pixel frame just inside `r`.
static func frame(c: CanvasItem, r: Rect2, col: Color) -> void:
	HudArtDraw.frame(c, r, col)


## An enamel plate filling `r`: the panel, a 1 px frame (`edge`) with the darker inner line, a lighter
## lip under the top edge and, with `studs`, 2 x 2 studs in the corners.
static func plate(c: CanvasItem, r: Rect2, edge: Color = FRAME, studs: bool = true) -> void:
	r = Rect2(r.position.round(), r.size.round())
	c.draw_rect(r, PANEL)
	c.draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4, 1)), PANEL_LIFT)
	frame(c, r, edge)
	frame(c, r.grow(-1), FRAME_IN)
	if not studs:
		return
	for p: Vector2 in [
		r.position + Vector2(2, 2),
		Vector2(r.end.x - 4, r.position.y + 2),
		Vector2(r.position.x + 2, r.end.y - 4),
		r.end - Vector2(4, 4)
	]:
		c.draw_rect(Rect2(p, Vector2(2, 2)), STUD)
		c.draw_rect(Rect2(p + Vector2(1, 1), Vector2(1, 1)), FRAME_IN)


## A bar filled `frac` of the way on its track, in whole pixels.
static func bar(c: CanvasItem, r: Rect2, frac: float, col: Color, track: Color = TRACK) -> void:
	c.draw_rect(r, track)
	var w := roundf(r.size.x * clampf(frac, 0.0, 1.0))
	if w > 0.0:
		c.draw_rect(Rect2(r.position, Vector2(w, r.size.y)), col)


## A gauge: the track, the band [lo, hi] (0..1 of the scale) shaded with amber ends, ticks every
## `tick_n`-th of the scale, and a 1 px needle at `v` (0..1) that stands 2 px proud; `v` < 0 has no
## needle (no data).
static func gauge(
	c: CanvasItem, r: Rect2, lo: float, hi: float, v: float, needle: Color, tick_n: int = 0
) -> void:
	c.draw_rect(r, TRACK)
	var x0 := r.position.x + roundf(r.size.x * clampf(lo, 0.0, 1.0))
	var x1 := r.position.x + roundf(r.size.x * clampf(hi, 0.0, 1.0))
	if x1 > x0:
		c.draw_rect(Rect2(x0, r.position.y, x1 - x0, r.size.y), BAND)
	if tick_n > 1:
		for i in range(1, tick_n):
			var tx := r.position.x + roundf(r.size.x * float(i) / tick_n)
			c.draw_rect(Rect2(tx, r.end.y - 2, 1, 2), PANEL)
	if x1 > x0:
		c.draw_rect(Rect2(x0, r.position.y - 1, 1, r.size.y + 2), AMBER)
		c.draw_rect(Rect2(x1 - 1, r.position.y - 1, 1, r.size.y + 2), AMBER)
	if v < 0.0:
		return
	var nx := r.position.x + roundf((r.size.x - 1.0) * clampf(v, 0.0, 1.0))
	c.draw_rect(Rect2(nx, r.position.y - 2, 1, r.size.y + 4), needle)


## A pixel pattern ("#" ink), top-left at `p`, `m` px per pattern pixel.
static func pixels(c: CanvasItem, rows: Array, p: Vector2, col: Color, m: float = 1.0) -> void:
	HudArtDraw.pixels(c, rows, p, col, m)


## Slot `slot`'s chip: its shape in its colour, hollow for slots 4-7.
static func chip(c: CanvasItem, slot: int, p: Vector2) -> void:
	var look := Wl.slot_look(slot)
	var set_of: Array = SHAPES_HOLLOW if bool(look["hollow"]) else SHAPES
	pixels(c, set_of[posmod(slot, 4)], p, _lifted(look["color"]))


## A slot colour lifted for the dark plates (blue would sink otherwise).
static func _lifted(col: Color) -> Color:
	return col.lerp(Color.WHITE, 0.3) if col.get_luminance() < 0.45 else col


## An indicator lamp (5 x 5, round): lit in `col` with a 1 px halo, or a dark glass.
static func lamp(c: CanvasItem, p: Vector2, lit: bool, col: Color = GOOD) -> void:
	if lit:
		c.draw_rect(Rect2(p - Vector2(1, 1), Vector2(7, 7)), Color(col.r, col.g, col.b, 0.25))
		pixels(c, LAMP_ROWS, p, col)
		c.draw_rect(Rect2(p + Vector2(1, 1), Vector2(1, 1)), Color(1, 1, 1, 0.85))
	else:
		pixels(c, LAMP_ROWS, p, LAMP_OFF)
		c.draw_rect(Rect2(p + Vector2(1, 1), Vector2(1, 1)), LAMP_OFF_GLASS)


## The crank icon's frame `frame_index`, top-left at `p`, tinted `col`.
static func crank(c: CanvasItem, frame_index: int, p: Vector2, col: Color) -> void:
	var tex := crank_texture()
	if tex == null:
		return
	var src := Rect2(frame_index * CRANK_CELL, 0, CRANK_CELL, CRANK_CELL)
	c.draw_texture_rect_region(tex, Rect2(p, src.size), src, col)


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
