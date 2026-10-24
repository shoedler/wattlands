class_name FishingHudDraw
extends RefCounted
## Drawing helpers for Turbo Reel's HUD Controls, in HUD canvas pixels (1080p units), all in the
## game palette: abyss-teal panels, foam text with an abyss outline, haze for secondary text,
## surface bars on a deep track, the accent only for alerts and the gaff. Also the pixel
## sprites at a whole-number scale and the meter icons that pair every colour with a shape
## (BRIEF 3.9): the strain zigzag and the slack loop.

const STRAIN := FishingPalette.SURFACE
const SLACK := FishingPalette.SAGE
const GAFF := FishingPalette.ACCENT
const STAMINA := FishingPalette.SURFACE
const ALERT := FishingPalette.HUD_ALERT
const OUTLINE := FishingPalette.ABYSS


## Text with an abyss outline; `pos` is the baseline's left end. Returns its width.
static func text(
	c: CanvasItem,
	pos: Vector2,
	s: String,
	px: int,
	col: Color = FishingPalette.HUD_TEXT,
	bold: bool = false
) -> float:
	var font := WlTheme.bold_font() if bold else WlTheme.font()
	var size := maxi(px, WlTheme.MIN_TEXT_PX)
	var outline := maxi(roundi(float(WlTheme.OUTLINE_PX) * float(size) / 64.0) + 2, 3)
	c.draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, OUTLINE)
	c.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## The width `s` takes at `px`.
static func text_w(s: String, px: int, bold: bool = false) -> float:
	var font := WlTheme.bold_font() if bold else WlTheme.font()
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(px, WlTheme.MIN_TEXT_PX)).x


## A bar filled `frac` (0..1) of the way (bottom-up when vertical) on its deep track, framed.
static func bar(c: CanvasItem, r: Rect2, frac: float, col: Color, vertical: bool = false) -> void:
	c.draw_rect(r, FishingPalette.HUD_TRACK)
	var f := clampf(frac, 0.0, 1.0)
	if vertical:
		var h := r.size.y * f
		c.draw_rect(Rect2(r.position.x, r.end.y - h, r.size.x, h), col)
	else:
		c.draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), col)
	c.draw_rect(r, OUTLINE, false, 2.0)


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
