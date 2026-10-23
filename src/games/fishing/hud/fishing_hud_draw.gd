class_name FishingHudDraw
extends RefCounted
## Drawing helpers for Fishing's HUD Controls, in HUD canvas pixels (1080p units): outlined text
## in the kit's font, meter bars, and the icons that pair every colour with a shape (BRIEF 3.9):
## the strain zigzag, the slack loop, slot shapes, a fish silhouette and the trophy star.

const STRAIN := Color("#e0413a")
const SLACK := Color("#f6d33c")
const GAFF := Color("#e8b730")
const STAMINA := Color("#56B4E9")
const BAND_IN := Color(0.741, 0.922, 1.0, 0.55)


## Text with the kit's dark outline; `pos` is the baseline's left end. Returns its width.
static func text(
	c: CanvasItem, pos: Vector2, s: String, px: int, col: Color = WlTheme.TEXT, bold: bool = false
) -> float:
	var font := WlTheme.bold_font() if bold else WlTheme.font()
	var size := maxi(px, WlTheme.MIN_TEXT_PX)
	var outline := maxi(roundi(float(WlTheme.OUTLINE_PX) * float(size) / 64.0) + 2, 3)
	c.draw_string_outline(
		font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, WlTheme.OUTLINE
	)
	c.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## A bar filled `frac` (0..1) of the way (bottom-up when vertical), outlined.
static func bar(c: CanvasItem, r: Rect2, frac: float, col: Color, vertical: bool = false) -> void:
	c.draw_rect(r, WlTheme.BAR_BG)
	var f := clampf(frac, 0.0, 1.0)
	if vertical:
		var h := r.size.y * f
		c.draw_rect(Rect2(r.position.x, r.end.y - h, r.size.x, h), col)
	else:
		c.draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), col)
	c.draw_rect(r, WlTheme.OUTLINE, false, 2.0)


## The strain icon: a zigzag (a taut, jagged line).
static func zigzag(c: CanvasItem, r: Rect2, col: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 4
	for i in steps + 1:
		var x := r.position.x + r.size.x * float(i) / float(steps)
		var y := r.position.y + (r.size.y if i % 2 == 1 else 0.0)
		pts.append(Vector2(x, y))
	c.draw_polyline(pts, WlTheme.OUTLINE, maxf(r.size.y * 0.3, 3.0) + 2.0)
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
	c.draw_polyline(pts, WlTheme.OUTLINE, 5.0)
	c.draw_polyline(pts, col, 3.0)


## A slot shape (circle, triangle, square, diamond) filled in `col`, hollow when `hollow`.
static func shape(
	c: CanvasItem, kind: String, center: Vector2, r: float, col: Color, hollow: bool = false
) -> void:
	var pts := FishingView.shape_points(kind, center, r)
	if not hollow:
		c.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	c.draw_polyline(pts, WlTheme.OUTLINE if not hollow else col, 3.0)


## A fish silhouette facing left, `w` wide, centred at `center`.
static func fish_icon(c: CanvasItem, center: Vector2, w: float, col: Color) -> void:
	var h := w * 0.42
	var pts := PackedVector2Array(
		[
			center + Vector2(-w * 0.5, 0),
			center + Vector2(-w * 0.2, -h * 0.5),
			center + Vector2(w * 0.25, -h * 0.35),
			center + Vector2(w * 0.5, -h * 0.55),
			center + Vector2(w * 0.38, 0),
			center + Vector2(w * 0.5, h * 0.55),
			center + Vector2(w * 0.25, h * 0.35),
			center + Vector2(-w * 0.2, h * 0.5),
		]
	)
	c.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	c.draw_polyline(pts, WlTheme.OUTLINE, 2.0)


## A four-pointed star (the trophy mark).
static func star(c: CanvasItem, center: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := TAU * float(i) / 8.0 - PI * 0.5
		var rr := r if i % 2 == 0 else r * 0.4
		pts.append(center + Vector2(cos(a), sin(a)) * rr)
	c.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	c.draw_polyline(pts, WlTheme.OUTLINE, 2.0)
