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

static var _font: Font = null
static var _icons: Dictionary = {}


## The pixel font: its space narrowed to SPACE_ADVANCE glyph pixels and every glyph hung from
## the baseline by the cap height (the Image Font importer hangs a glyph by half its cell, which
## draws the caps 3 rows under a Label's box and the descenders out of it).
static func font() -> Font:
	if _font == null:
		_font = load(FONT_PATH) as Font
		var ff := _font as FontFile
		if ff != null:
			for i in ff.get_cache_count():
				for sz in ff.get_size_cache_list(i):
					for g in ff.get_glyph_list(i, sz):
						ff.set_glyph_offset(i, sz, g, Vector2(0, -CAP_ROWS))
					ff.set_glyph_advance(i, sz.x, 32, Vector2(SPACE_ADVANCE, 0))
	return _font


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


## Sprite `id` frame `k` recoloured to the palette (foam pixels take `col`, every other pixel
## keeps its palette colour), each art pixel `px` HUD px, top-left at `pos`.
static func icon(c: CanvasItem, id: String, k: int, pos: Vector2, px: int, col: Color) -> void:
	var tex := FishingSprites.frame(id, k)
	if tex == null:
		return
	var key := "%s:%d:%s" % [id, posmod(k, maxi(FishingSprites.count(id), 1)), col.to_html()]
	if not _icons.has(key):
		var img := tex.get_image()
		img.convert(Image.FORMAT_RGBA8)
		var foam := FishingPalette.FOAM.to_html(false)
		for y in img.get_height():
			for x in img.get_width():
				var p := img.get_pixel(x, y)
				if p.a > 0.5 and p.to_html(false) == foam:
					img.set_pixel(x, y, col)
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
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] == "#":
				c.draw_rect(Rect2(pos + Vector2(x, y) * u, Vector2(u, u)), col)


## The trophy star.
const STAR: Array[String] = ["..#..", ".###.", "#####", ".###.", "..#.."]


## A flat panel in the HUD's panel teal.
static func panel(c: CanvasItem, r: Rect2, col: Color = FishingPalette.HUD_PANEL) -> void:
	c.draw_rect(r, col)
