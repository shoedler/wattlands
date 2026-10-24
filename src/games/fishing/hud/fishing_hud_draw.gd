class_name FishingHudDraw
extends RefCounted
## Drawing helpers for Turbo Reel's HUD Controls, in HUD canvas pixels (1080p units), all in the
## game palette: square abyss-teal panels, foam text in the game's pixel font (FONT, drawn at
## whole multiples of its 9 px cell, no outline), haze for secondary text, surface bars in a
## surface frame on a deep track, the accent only for alerts and the gaff. Also the pixel
## sprites at a whole-number scale and the meter icons that pair every colour with a shape
## (BRIEF 3.9): the strain zigzag and the slack loop.

const STRAIN := FishingPalette.SURFACE
const SLACK := FishingPalette.SAGE
const GAFF := FishingPalette.ACCENT
const STAMINA := FishingPalette.SURFACE
const ALERT := FishingPalette.HUD_ALERT
const OUTLINE := FishingPalette.ABYSS
## The pixel font (FishingFontGrids through the Image Font importer) and its cell height.
const FONT_PATH := "res://assets/fishing/font/turbo_reel_5x7.png"
const FONT_PX := 9

static var _font: Font = null


## The pixel font.
static func font() -> Font:
	if _font == null:
		_font = load(FONT_PATH) as Font
	return _font


## `px` snapped up to a whole multiple of the font's cell (at least two).
static func snap_px(px: int) -> int:
	return maxi(2, ceili(float(px) / float(FONT_PX))) * FONT_PX


## Text in the pixel font at `px` snapped to its cell; `pos` is the baseline's left end, on a
## whole pixel. Returns its width. (`_bold` is kept for the callers; the font has one weight.)
static func text(
	c: CanvasItem,
	pos: Vector2,
	s: String,
	px: int,
	col: Color = FishingPalette.HUD_TEXT,
	_bold: bool = false
) -> float:
	var size := snap_px(px)
	c.draw_string(font(), pos.round(), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## The width `s` takes at `px`.
static func text_w(s: String, px: int, _bold: bool = false) -> float:
	return font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, snap_px(px)).x


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


## Sprite `id` frame `k` with its top-left at `pos`, each art pixel `scale` HUD px, modulated.
static func sprite(
	c: CanvasItem, id: String, k: int, pos: Vector2, scale: float, col: Color = Color.WHITE
) -> void:
	var tex := FishingSprites.frame(id, k)
	if tex == null:
		return
	c.draw_texture_rect(tex, Rect2(pos.round(), Vector2(tex.get_size()) * scale), false, col)


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
