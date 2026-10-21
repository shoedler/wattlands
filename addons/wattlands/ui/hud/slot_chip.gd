class_name SlotChip
extends Control
## A rider's session look as a chip (BRIEF 3.9, Wl.slot_look): the slot color filling a
## shape (circle, triangle, square, diamond) with a pattern mark (solid: none, dashed: two
## bars, dotted: three dots, double: an inner outline). Slots 4-7 are hollow: an outline in
## the slot color with the pattern drawn in that color. Color always comes with shape and
## pattern, so the chip reads without color vision. Owned by ui-hud; the app shell's lobby
## and games may use it too.

var color: Color = Wl.SLOT_COLORS[0]
var shape: String = "circle"
var pattern: String = "solid"
var hollow: bool = false
var slot_index: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(44, 44)


## Take the look of `p_slot_index` from Wl.slot_look.
func set_slot(p_slot_index: int) -> void:
	slot_index = p_slot_index
	set_look(Wl.slot_look(p_slot_index))


## {color, shape, pattern, hollow} (Wl.slot_look's keys).
func set_look(look: Dictionary) -> void:
	color = look.get("color", color)
	shape = str(look.get("shape", shape))
	pattern = str(look.get("pattern", pattern))
	hollow = bool(look.get("hollow", hollow))
	queue_redraw()


func look() -> Dictionary:
	return {"color": color, "shape": shape, "pattern": pattern, "hollow": hollow}


## The shape's outline points inside `r` (closed polygon; circles use 24 points).
static func shape_points(p_shape: String, r: Rect2) -> PackedVector2Array:
	var c := r.get_center()
	var hw := r.size.x * 0.5
	var hh := r.size.y * 0.5
	var pts := PackedVector2Array()
	match p_shape:
		"triangle":
			pts = PackedVector2Array(
				[Vector2(c.x, c.y - hh), Vector2(c.x + hw, c.y + hh), Vector2(c.x - hw, c.y + hh)]
			)
		"square":
			var s := minf(hw, hh) * 0.9
			pts = PackedVector2Array(
				[
					Vector2(c.x - s, c.y - s),
					Vector2(c.x + s, c.y - s),
					Vector2(c.x + s, c.y + s),
					Vector2(c.x - s, c.y + s)
				]
			)
		"diamond":
			pts = PackedVector2Array(
				[
					Vector2(c.x, c.y - hh),
					Vector2(c.x + hw, c.y),
					Vector2(c.x, c.y + hh),
					Vector2(c.x - hw, c.y)
				]
			)
		_:
			for i in 24:
				var a := TAU * i / 24.0
				pts.append(c + Vector2(cos(a) * hw, sin(a) * hh))
	return pts


func _draw() -> void:
	var side := minf(size.x, size.y)
	if side <= 2.0:
		return
	var r := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side)).grow(-3.0)
	var pts := shape_points(shape, r)
	var closed := pts.duplicate()
	closed.append(pts[0])
	var line_w := maxf(2.0, side * 0.09)
	var mark := color if hollow else Color(0.05, 0.06, 0.08, 0.9)
	if hollow:
		draw_colored_polygon(pts, Color(0.05, 0.06, 0.08, 0.85))
		draw_polyline(closed, color, line_w, true)
	else:
		draw_colored_polygon(pts, color)
		draw_polyline(closed, Color(0, 0, 0, 0.8), maxf(1.5, side * 0.04), true)
	# Pattern marks sit in the shape's inner area (the middle third of the chip).
	var c := r.get_center()
	var u := side * 0.12
	match pattern:
		"dashed":
			draw_rect(Rect2(c.x - 2.0 * u, c.y - 1.4 * u, 4.0 * u, 0.8 * u), mark)
			draw_rect(Rect2(c.x - 2.0 * u, c.y + 0.6 * u, 4.0 * u, 0.8 * u), mark)
		"dotted":
			for k: int in [-1, 0, 1]:
				draw_circle(
					c + Vector2(k * 1.6 * u, 0.6 * u if shape == "triangle" else 0.0), 0.6 * u, mark
				)
		"double":
			var inner := shape_points(shape, Rect2(c - r.size * 0.25, r.size * 0.5))
			var inner_closed := inner.duplicate()
			inner_closed.append(inner[0])
			draw_polyline(inner_closed, mark, maxf(2.0, side * 0.07), true)
