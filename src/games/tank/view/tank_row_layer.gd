class_name TankRowLayer
extends Node2D
## Draws an ordered list of rows in one canvas item: sprites (with flip and tint), lines, rects and
## small HP bars. The view builds the rows from the state each frame (enemies, wrecks, props, the
## Behemoth's parts, shells and trajectory dots), so the picture can be tested as plain data and the
## layer costs one batch however many things are on screen. No texture or node is created per frame.
##
## Rows: {"t": "sprite", "id": String, "pos": Vector2, "size": Vector2, "flip": bool, "tint": Color}
##       {"t": "line", "a": Vector2, "b": Vector2, "w": float, "c": Color}
##       {"t": "rect", "r": Rect2, "c": Color}
##       {"t": "bar", "pos": Vector2, "w": float, "frac": float}
##       {"t": "poly", "pts": PackedVector2Array, "c": Color} (a filled polygon)
##       {"t": "polyline", "pts": PackedVector2Array, "w": float, "c": Color}

var rows: Array[Dictionary] = []


## Replaces the rows and redraws.
func set_rows(p_rows: Array[Dictionary]) -> void:
	rows = p_rows
	queue_redraw()


func _draw() -> void:
	for row in rows:
		match str(row.get("t", "")):
			"sprite":
				_sprite(row)
			"line":
				draw_line(row["a"], row["b"], row["c"], float(row.get("w", 1.0)))
			"rect":
				draw_rect(row["r"], row["c"])
			"bar":
				_bar(row)
			"poly":
				draw_colored_polygon(row["pts"], row["c"])
			"polyline":
				draw_polyline(row["pts"], row["c"], float(row.get("w", 1.0)))


func _sprite(row: Dictionary) -> void:
	var pos: Vector2 = row["pos"]
	var size: Vector2 = row["size"]
	var tint: Color = row.get("tint", Color.WHITE)
	var tex := TankSprites.tex(str(row["id"]))
	if bool(row.get("flip", false)):
		draw_texture_rect(tex, Rect2(pos.x + size.x, pos.y, -size.x, size.y), false, tint)
	else:
		draw_texture_rect(tex, Rect2(pos, size), false, tint)


func _bar(row: Dictionary) -> void:
	var pos: Vector2 = row["pos"]
	var w := float(row["w"])
	var frac := clampf(float(row["frac"]), 0.0, 1.0)
	# Dim and short: a dark slot with a muted steel fill (rust when low), no white.
	draw_rect(Rect2(pos, Vector2(w, 3)), TankPalette.with_alpha(TankPalette.SOOT, 0.7))
	var col := TankPalette.STEEL_LIGHT if frac > 0.34 else TankPalette.RUST_LIGHT
	draw_rect(Rect2(pos + Vector2(1, 1), Vector2(maxf(roundf((w - 2.0) * frac), 0.0), 1)), col)
