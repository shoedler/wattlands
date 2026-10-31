class_name FishingHudDraw
extends RefCounted
## Drawing helpers for Turbo Reel's HUD Controls, in HUD canvas pixels (1080p units), all in the
## game palette and on its pixel grid (one art pixel is `unit()` HUD px): square opaque
## deep-teal panels, foam text in the game's pixel font (FONT; BIG text doubles it), no outline,
## centred on the cap height in its line box (text_line()), haze for secondary text, surface
## bars on a mid-teal track, the accent only for alerts and the gaff. Also the pixel icons
## recoloured to the palette (icon()) and pixel patterns (pixels()) such as the trophy star.

const STRAIN := FishingPalette.SURFACE
const SLACK := FishingPalette.SAGE
const GAFF := FishingPalette.ACCENT
const STAMINA := FishingPalette.SURFACE
const ALERT := FishingPalette.HUD_ALERT
## The heart rate box's heart: the one colour outside the palette, a muted red, HUD only.
const HEART := Color("#b5675f")
const HEART_ROWS: Array[String] = [
	".##.##.",
	"#######",
	"#######",
	".#####.",
	"..###..",
	"...#...",
]
## The pixel font (FishingFontGrids through the Image Font importer) and its cell height.
const FONT_PATH := "res://assets/fishing/font/turbo_reel_5x7.png"
const FONT_PX := 9
## Glyph rows: the cap height, the leading above it, and a text line's box (leading, cap and
## the 2-row descender, so the cap sits in the middle of the box).
const CAP_ROWS := 7
const LEAD_ROWS := 2
const LINE_ROWS := 11
## The space's advance in glyph pixels (the grid cell is 6).
const SPACE_ADVANCE := 3

static var _icons: Dictionary = {}


## The pixel font: its space narrowed to SPACE_ADVANCE glyph pixels and every glyph hung from
## the baseline by the cap height (the Image Font importer hangs a glyph by half its cell, which
## draws the caps 3 rows under a Label's box and the descenders out of it).
static func font() -> Font:
	return PixelFont.hang(FONT_PATH, CAP_ROWS, SPACE_ADVANCE)


## HUD px per glyph (art) pixel at draw scale `s` (3 at 1080p).
static func unit(s: float = 1.0) -> int:
	return maxi(1, roundi(3.0 * s))


## The font size for text at draw scale `s`: one glyph pixel per unit, two for `big`.
static func size_px(s: float = 1.0, big: bool = false) -> int:
	return FONT_PX * unit(s) * (2 if big else 1)


## Text in the pixel font at draw scale `s`; `pos` is the baseline's left end, on a whole pixel.
## Returns its width.
static func text(
	c: CanvasItem,
	pos: Vector2,
	s: String,
	scale: float = 1.0,
	col: Color = FishingPalette.HUD_TEXT,
	big: bool = false
) -> float:
	var size := size_px(scale, big)
	c.draw_string(font(), pos.round(), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## The width `s` takes at draw scale `scale`.
static func text_w(s: String, scale: float = 1.0, big: bool = false) -> float:
	return font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px(scale, big)).x


## Text in a line box of LINE_ROWS glyph pixels whose top is `top` (LEAD_ROWS above the cap,
## the descender below it), at x `x`. Returns its width.
static func text_line(
	c: CanvasItem, x: float, top: float, s: String, scale: float = 1.0, col: Color = Color.WHITE
) -> float:
	var u := unit(scale)
	return text(c, Vector2(x, top + float(u * (LEAD_ROWS + CAP_ROWS))), s, scale, col)


## Sprite `id` frame `k` recoloured to the palette (foam pixels take `col`; with `body` set the
## abyss strokes take it, for an icon on a panel; every other pixel keeps its palette colour),
## each art pixel `px` HUD px, top-left at `pos`.
static func icon(
	c: CanvasItem,
	id: String,
	k: int,
	pos: Vector2,
	px: int,
	col: Color,
	body: Color = Color(0, 0, 0, 0)
) -> void:
	var tex := FishingSprites.frame(id, k)
	if tex == null:
		return
	var n := maxi(FishingSprites.count(id), 1)
	var key := "%s:%d:%s:%s" % [id, posmod(k, n), col.to_html(), body.to_html()]
	if not _icons.has(key):
		var img := tex.get_image()
		img.convert(Image.FORMAT_RGBA8)
		var foam := FishingPalette.FOAM.to_html(false)
		var abyss := FishingPalette.ABYSS.to_html(false)
		for y in img.get_height():
			for x in img.get_width():
				var p := img.get_pixel(x, y)
				if p.a <= 0.5:
					continue
				if p.to_html(false) == foam:
					img.set_pixel(x, y, col)
				elif body.a > 0.0 and p.to_html(false) == abyss:
					img.set_pixel(x, y, body)
		_icons[key] = ImageTexture.create_from_image(img)
	var t: Texture2D = _icons[key]
	c.draw_texture_rect(t, Rect2(pos.round(), Vector2(t.get_size()) * float(px)), false)


## A bar filled `frac` (0..1) of the way (bottom-up when vertical) on its track, in whole
## pixels of `u` (no frame: the track reads on the panel).
static func bar(
	c: CanvasItem, r: Rect2, frac: float, col: Color, vertical: bool = false, u: float = 3.0
) -> void:
	c.draw_rect(r, FishingPalette.HUD_TRACK)
	var f := clampf(frac, 0.0, 1.0)
	if vertical:
		var h := roundf(r.size.y * f / u) * u
		c.draw_rect(Rect2(r.position.x, r.end.y - h, r.size.x, h), col)
	else:
		var w := roundf(r.size.x * f / u) * u
		c.draw_rect(Rect2(r.position, Vector2(w, r.size.y)), col)


## A frame one pixel of `u` wide just inside `r`.
static func frame(c: CanvasItem, r: Rect2, u: float, col: Color) -> void:
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, u)), col)
	c.draw_rect(Rect2(r.position.x, r.end.y - u, r.size.x, u), col)
	c.draw_rect(Rect2(r.position, Vector2(u, r.size.y)), col)
	c.draw_rect(Rect2(r.end.x - u, r.position.y, u, r.size.y), col)


## A pixel pattern ("#" ink, rows top-down), each pixel `u` HUD px, top-left at `pos`.
static func pixels(c: CanvasItem, rows: Array, pos: Vector2, u: float, col: Color) -> void:
	HudArtDraw.pixels(c, rows, pos, col, u)


## The trophy star.
const STAR: Array[String] = ["..#..", ".###.", "#####", ".###.", "..#.."]


## A power graph over `trace` in `r` (HUD px, on the art grid of `u` px), the newest sample at
## the right, `bottom_w` at the bottom and `top_w` at the top: the target band (each sample's target
## +/- `band` of it, rows lit in FishingPalette.UPPER) behind the power, either an unbroken
## 1-pixel line in `col` or, `filled`, a `fill_col` area under a `col` top edge.
static func graph(
	c: CanvasItem,
	r: Rect2,
	trace: FishingPowerTrace,
	top_w: float,
	u: float,
	band: float = 0.05,
	filled: bool = false,
	col: Color = FishingPalette.FOAM,
	bottom_w: float = 0.0,
	fill_col: Color = FishingPalette.MID
) -> void:
	var n := floori(r.size.x / u)
	var rows := floori(r.size.y / u)
	if n <= 0 or rows <= 1 or top_w <= bottom_w:
		return
	var prev := -1
	for i in n:
		var s := trace.at_column(i, n)
		var x := r.position.x + float(i) * u
		if s.x < 0.0:
			# no history there yet: the line runs along the bottom, so the graph spans its width
			c.draw_rect(Rect2(x, r.position.y + float(rows - 1) * u, u, u), col)
			prev = rows - 1
			continue
		if s.y > 0.0 and band > 0.0:
			var a := graph_row(s.y * (1.0 + band), top_w, rows, bottom_w)
			var b := graph_row(s.y * (1.0 - band), top_w, rows, bottom_w)
			c.draw_rect(Rect2(x, r.position.y + float(a) * u, u, float(b - a + 1) * u), UPPER_BAND)
		var y := graph_row(s.x, top_w, rows, bottom_w)
		if filled:
			var fill_h := float(rows - 1 - y) * u
			c.draw_rect(Rect2(x, r.position.y + float(y + 1) * u, u, fill_h), fill_col)
		# a step joins on this column, from the row after the previous one: an unbroken line
		var y0 := y
		var y1 := y
		if prev >= 0 and prev < y:
			y0 = prev + 1
		elif prev > y:
			y1 = prev - 1
		c.draw_rect(Rect2(x, r.position.y + float(y0) * u, u, float(y1 - y0 + 1) * u), col)
		prev = y


## The graph row (0 at the top of `rows`) of `w` watts on a `bottom_w` .. `top_w` scale.
static func graph_row(w: float, top_w: float, rows: int, bottom_w: float = 0.0) -> int:
	var u := (w - bottom_w) / maxf(top_w - bottom_w, 1.0)
	return clampi(roundi((1.0 - u) * float(rows - 1)), 0, rows - 1)


## The target band's colour in the graphs.
const UPPER_BAND := FishingPalette.UPPER


## A flat panel in the HUD's panel teal inside a one-pixel (`u` px) surface-teal frame, so it
## reads on the deep floors too.
static func panel(c: CanvasItem, r: Rect2, u: float = 3.0) -> void:
	c.draw_rect(r, FishingPalette.HUD_PANEL)
	frame(c, r, u, FishingPalette.HUD_PANEL_FRAME)
