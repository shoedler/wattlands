class_name WorkoutTrackLayer
extends Node2D
## The interval strip drawn on the bank: the blocks of the plan rolling toward the rider and the
## "now" mark under the local rider. It draws the model the WorkoutRideView computed and nothing else.

## {blocks: [{points: PackedVector2Array, color: Color, hatched: bool}], now_x: float}
var model: Dictionary = {}

const COLUMN_W := 2
const STRIP_TOP := 418.0
const STRIP_BOTTOM := 460.0


func set_model(m: Dictionary) -> void:
	model = m
	queue_redraw()


func _draw() -> void:
	if model.is_empty():
		return
	for b: Dictionary in model.get("blocks", []):
		var pts: PackedVector2Array = b["points"]
		var color: Color = b["color"]
		draw_colored_polygon(pts, color)
		if bool(b.get("hatched", false)):
			var lo := pts[0].x
			var hi := pts[1].x
			var hx := ceilf(lo / 3.0) * 3.0
			while hx < hi:
				draw_rect(
					Rect2(hx, pts[1].y + 1.0, 1.0, pts[2].y - pts[1].y - 1.0), color.lightened(0.25)
				)
				hx += 3.0
		draw_line(pts[0], pts[1], color.lightened(0.35), 1.0)
	var now_x := float(model.get("now_x", WorkoutRideView.RIDER_X))
	draw_rect(Rect2(now_x, STRIP_TOP - 4.0, 1.0, STRIP_BOTTOM - STRIP_TOP + 4.0), WorkoutArt.WHITE)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(now_x - 3.0, STRIP_TOP - 6.0),
				Vector2(now_x + 4.0, STRIP_TOP - 6.0),
				Vector2(now_x + 0.5, STRIP_TOP - 2.0)
			]
		),
		WorkoutArt.WHITE
	)
