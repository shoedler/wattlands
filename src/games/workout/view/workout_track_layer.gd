class_name WorkoutTrackLayer
extends Node2D
## The ride view's foreground: the ground and the road (following the course profile in
## Rolling road), the interval blocks drawn on the ground, the "now" mark and one pennant
## per rider. It draws the model the WorkoutRideView computed and nothing else.

## {road: PackedFloat64Array (road y per COLUMN_W px), dash_offset: float,
##  blocks: [{points: PackedVector2Array, color: Color, hatched: bool}], now_x: float,
##  markers: [{x, y, shapes: Array[Dictionary], edge: -1|0|1}]}
var model: Dictionary = {}

const COLUMN_W := 2
## Bottom of the near tree strip (WorkoutRideView places it at 366).
const BANK_Y := 365.0
const STRIP_TOP := 418.0
const STRIP_BOTTOM := 460.0


func set_model(m: Dictionary) -> void:
	model = m
	queue_redraw()


func _draw() -> void:
	if model.is_empty():
		return
	var road: PackedFloat64Array = model.get("road", PackedFloat64Array())
	# The tree bank continues down to the road wherever the road dips below it.
	draw_rect(Rect2(0, BANK_Y, WorkoutArt.W, WorkoutArt.H - BANK_Y), WorkoutArt.NEAR_TREES)
	for i in road.size():
		var x := float(i * COLUMN_W)
		var y := road[i]
		draw_rect(Rect2(x, y, COLUMN_W, WorkoutArt.H - y), WorkoutArt.GRASS)
		draw_rect(Rect2(x, y + 6.0, COLUMN_W, 2.0), WorkoutArt.GRASS_DARK)
		draw_rect(Rect2(x, y - 3.0, COLUMN_W, 5.0), WorkoutArt.ASPHALT)
		draw_rect(Rect2(x, y - 4.0, COLUMN_W, 1.0), WorkoutArt.ROAD_EDGE)
	var dash := float(model.get("dash_offset", 0.0))
	var dx := -dash
	while dx < float(WorkoutArt.W):
		var col := clampi(int(floor(maxf(dx, 0.0) / COLUMN_W)), 0, maxi(road.size() - 1, 0))
		if not road.is_empty():
			draw_rect(Rect2(dx, road[col] - 1.0, 6.0, 1.0), WorkoutArt.ROAD_DASH)
		dx += 16.0
	draw_rect(Rect2(0, STRIP_TOP, WorkoutArt.W, STRIP_BOTTOM - STRIP_TOP), WorkoutArt.DIRT)
	draw_rect(Rect2(0, STRIP_TOP, WorkoutArt.W, 1.0), WorkoutArt.DIRT_DARK)
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
	var now_x := float(model.get("now_x", 300.0))
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
	for m: Dictionary in model.get("markers", []):
		var foot := Vector2(float(m["x"]), float(m["y"]) - 2.0)
		for s: Dictionary in m["shapes"]:
			var pts: PackedVector2Array = s["points"]
			var moved := PackedVector2Array()
			for p in pts:
				moved.append(p + foot)
			draw_colored_polygon(moved, s["color"])
		var edge := int(m.get("edge", 0))
		if edge != 0:
			# An arrow on the road, past the flag, pointing at the rider off screen.
			var ax := foot.x + (24.0 if edge > 0 else -5.0)
			var ay := foot.y - 5.0
			draw_colored_polygon(
				PackedVector2Array(
					[
						Vector2(ax, ay - 3.0),
						Vector2(ax + 4.0 * float(edge), ay),
						Vector2(ax, ay + 3.0)
					]
				),
				WorkoutArt.WHITE
			)
