class_name FishingHudDraw
extends RefCounted
## Drawing helpers for Turbo Reel's HUD Controls, in HUD canvas pixels (1080p units), all in the
## game palette: square opaque abyss-teal panels, foam text in the game's pixel font (FONT) at
## one scale (a glyph pixel is one art pixel, `unit()` HUD px; BIG text doubles it), no outline,
## centred on the cap height in its line box (text_line()), haze for secondary text, surface bars in
## a surface frame on a deep track, the accent only for alerts and the gaff. Also the pixel
## icons recoloured to the palette (icon()) and the meter icons that pair every colour with a
## shape (BRIEF 3.9): the strain zigzag and the slack loop.

const STRAIN := FishingPalette.SURFACE
const SLACK := FishingPalette.SAGE
const GAFF := FishingPalette.ACCENT
const STAMINA := FishingPalette.SURFACE
const ALERT := FishingPalette.HUD_ALERT
const OUTLINE := FishingPalette.ABYSS
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


## A bar filled `frac` (0..1) of the way (bottom-up when vertical) on its deep track, framed.
static func bar(c: CanvasItem, r: Rect2, frac: float, col: Color, vertical: bool = false) -> void:
	c.draw_rect(r, FishingPalette.HUD_TRACK)
	var f := clampf(frac, 0.0, 1.0)
	if vertical:
		var h := r.size.y * f
		c.draw_rect(Rect2(r.position.x, r.end.y - h, r.size.x, h), col)
	else:
		c.draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), col)
	c.draw_rect(r, FishingPalette.HUD_BAR, false, 3.0)


## The strain icon: a zigzag (a taut, jagged line).
static func zigzag(c: CanvasItem, r: Rect2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 5:
		var x := r.position.x + r.size.x * float(i) / 4.0
		pts.append(Vector2(x, r.position.y + (r.size.y if i % 2 == 1 else 0.0)))
	c.draw_polyline(pts, OUTLINE, maxf(r.size.y * 0.3, 3.0) + 2.0)
	c.draw_polyline(pts, col, maxf(r.size.y * 0.3, 3.0))


## The slack icon: a loop of loose line.
static func loop(c: CanvasItem, r: Rect2, col: Color) -> void:
	var pts := PackedVector2Array()
	var cx := r.get_center()
	for i in 17:
		var a := TAU * float(i) / 16.0
		pts.append(
			cx + Vector2(cos(a) * r.size.x * 0.32, sin(a) * r.size.y * 0.32 - r.size.y * 0.1)
		)
	pts.append(Vector2(r.position.x, r.end.y))
	c.draw_polyline(pts, OUTLINE, 5.0)
	c.draw_polyline(pts, col, 3.0)


## A four-pointed star (the trophy mark).
static func star(c: CanvasItem, center: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := TAU * float(i) / 8.0 - PI * 0.5
		var rr := r if i % 2 == 0 else r * 0.4
		pts.append(center + Vector2(cos(a), sin(a)) * rr)
	c.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	c.draw_polyline(pts, OUTLINE, 2.0)


## A flat panel in the HUD's abyss teal.
static func panel(c: CanvasItem, r: Rect2, col: Color = FishingPalette.HUD_PANEL) -> void:
	c.draw_rect(r, col)
