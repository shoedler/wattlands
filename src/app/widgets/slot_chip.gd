class_name AppSlotChip
extends Control
## A rider's session look (BRIEF 3.9): the slot color always paired with a shape (circle,
## triangle, square, diamond) and a border pattern (solid, dashed, dotted, double); slots 4-7
## are hollow. Drawn from Wl.slot_look() so menus, lobby cards and the HUD agree.

var look: Dictionary = {}


static func for_slot(slot_index: int, chip_size: float = 56.0) -> AppSlotChip:
	var c := AppSlotChip.new()
	c.look = Wl.slot_look(slot_index)
	c.custom_minimum_size = Vector2(chip_size, chip_size)
	return c


func _draw() -> void:
	if look.is_empty():
		return
	var col: Color = look.get("color", Color.WHITE)
	var hollow: bool = look.get("hollow", false)
	var r := minf(size.x, size.y) * 0.5 - 4.0
	var c := size * 0.5
	var pts := PackedVector2Array()
	match str(look.get("shape", "circle")):
		"triangle":
			pts = PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, r * 0.85), c + Vector2(-r, r * 0.85)])
		"square":
			pts = PackedVector2Array([c + Vector2(-r, -r), c + Vector2(r, -r), c + Vector2(r, r), c + Vector2(-r, r)])
		"diamond":
			pts = PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		_:
			for i in 24:
				var a := TAU * float(i) / 24.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
	if hollow:
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, col, 5.0)
	else:
		draw_colored_polygon(pts, col)
	_draw_pattern(col)


## The border pattern under the shape.
func _draw_pattern(col: Color) -> void:
	var y := size.y - 2.0
	match str(look.get("pattern", "solid")):
		"dashed":
			var x := 0.0
			while x < size.x:
				draw_line(Vector2(x, y), Vector2(minf(x + 10.0, size.x), y), col, 3.0)
				x += 16.0
		"dotted":
			var x2 := 2.0
			while x2 < size.x:
				draw_circle(Vector2(x2, y), 2.0, col)
				x2 += 8.0
		"double":
			draw_line(Vector2(0, y), Vector2(size.x, y), col, 2.0)
			draw_line(Vector2(0, y - 5.0), Vector2(size.x, y - 5.0), col, 2.0)
		_:
			draw_line(Vector2(0, y), Vector2(size.x, y), col, 3.0)
