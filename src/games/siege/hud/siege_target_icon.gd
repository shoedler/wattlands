class_name SiegeTargetIcon
extends Control
## A routing target as a small icon (the teammate strip): a toothed gear for the generator, a
## block tower with its pad number for a pad. Drawn in the rider's slot color with a dark
## outline; the shape and the number tell targets apart without color.

var target: int = SiegeIds.TARGET_GEN
var color: Color = Color.WHITE
## Dim while the rider's output is not reaching it (reconnecting, AFK).
var dim: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(40, 40)


func set_target(p_target: int, p_color: Color, p_dim: bool) -> void:
	if p_target == target and p_color == color and p_dim == dim:
		return
	target = p_target
	color = p_color
	dim = p_dim
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var col := Color(color.r, color.g, color.b, 0.45 if dim else 1.0)
	if SiegeIds.is_pad(target):
		var body := Rect2(c.x - 11, c.y - 6, 22, 20)
		draw_rect(body, col)
		for dx: float in [-11.0, -3.0, 5.0]:
			draw_rect(Rect2(c.x + dx, c.y - 13, 6, 7), col)
		draw_rect(body, WlTheme.OUTLINE, false, 2.0)
		var font := WlTheme.bold_font()
		var txt := str(target)
		var lum := Color.BLACK if col.get_luminance() > 0.45 else Color.WHITE
		draw_string(font, Vector2(c.x - 5, c.y + 11), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, lum)
	else:
		var teeth := 8
		for k in teeth:
			var a := TAU * float(k) / float(teeth)
			var d := Vector2(cos(a), sin(a))
			draw_line(c + d * 12.0, c + d * 18.0, col, 5.0)
		draw_circle(c, 13.0, col)
		draw_circle(c, 5.0, WlTheme.PANEL)
		draw_arc(c, 13.0, 0.0, TAU, 20, WlTheme.OUTLINE, 2.0)
