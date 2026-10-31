class_name HudArtDraw
extends RefCounted
## The drawing every game's art-pixel HUD does the same way. It takes the Control to draw on, so it
## runs inside that Control's _draw, under whatever scale it set.


## A pixel pattern ("#" ink, rows top-down), top-left at `p`, each pattern pixel `m` px.
static func pixels(c: CanvasItem, rows: Array, p: Vector2, col: Color, m: float = 1.0) -> void:
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] == "#":
				c.draw_rect(Rect2(p + Vector2(x, y) * m, Vector2(m, m)), col)


## A frame `m` px wide just inside `r`. Each corner is drawn once, so it is safe with alpha.
static func frame(c: CanvasItem, r: Rect2, col: Color, m: float = 1.0) -> void:
	for side: Rect2 in frame_rects(r, m):
		c.draw_rect(side, col)


## The four sides frame() draws: top and bottom run the full width, the sides fit between them.
static func frame_rects(r: Rect2, m: float = 1.0) -> Array[Rect2]:
	var inner_h := r.size.y - 2.0 * m
	return [
		Rect2(r.position, Vector2(r.size.x, m)),
		Rect2(r.position.x, r.end.y - m, r.size.x, m),
		Rect2(r.position.x, r.position.y + m, m, inner_h),
		Rect2(r.end.x - m, r.position.y + m, m, inner_h),
	]
