class_name WorkoutTrackLayer
extends Node2D
## The interval strip painted on the bank: the blocks of the plan rolling toward the rider and the
## "now" mark under the local rider. Their zone colours are muted toward the ground and thin enough
## for the mown bands to show through, with a lit edge, a cast shadow and a seam at every minute of
## the plan, so they lie on the grass and leave the eye on the riders. The HUD's timeline carries the
## full colours. It draws the model the WorkoutRideView computed and nothing else.

const COLUMN_W := 2
const STRIP_TOP := 418.0
const STRIP_BOTTOM := 460.0
## How far a block's colour goes toward the ground, and how much of the ground it lets through.
const MUTE := 0.42
const FILL_ALPHA := 0.78
const SHADOW := Color(0.02, 0.05, 0.04, 0.42)
const SHADOW_DROP := 2.0
## A seam at every minute of the plan (art px, at WorkoutRideView.STRIP_PX_PER_S).
const SEAM_PX := 45.0
const HATCH_PX := 3.0

## {blocks: [{points: PackedVector2Array, color: Color, hatched: bool}], now_x: float, canvas_w: float}
var model: Dictionary = {}
## The bank's colour in this row of the morning: what the blocks are muted toward.
var ground: Color = Color.BLACK


func set_model(m: Dictionary) -> void:
	model = m
	queue_redraw()


func _draw() -> void:
	if model.is_empty():
		return
	var right := float(model.get("canvas_w", WorkoutArt.W))
	for b: Dictionary in model.get("blocks", []):
		_block(b, right)
	var now_x := float(model.get("now_x", WorkoutRideView.RIDER_X))
	draw_rect(Rect2(now_x, STRIP_TOP - 4.0, 1.0, STRIP_BOTTOM - STRIP_TOP + 4.0), WorkoutArt.WHITE)
	for r in 3:
		draw_rect(Rect2(now_x - 2.0 + r, STRIP_TOP - 6.0 + r, 5.0 - 2.0 * r, 1.0), WorkoutArt.WHITE)


## The fill a block's zone colour becomes on the ground.
static func muted(color: Color, on_ground: Color) -> Color:
	var c := color.lerp(on_ground, MUTE)
	c.a = FILL_ALPHA
	return c


func _block(b: Dictionary, right: float) -> void:
	var pts: PackedVector2Array = b["points"]
	var x0 := roundf(pts[0].x)
	var x1 := roundf(pts[1].x)
	var base := pts[2].y
	var fill := muted(b["color"], ground)
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(Vector2(roundf(p.x), roundf(p.y)) + Vector2(0.0, SHADOW_DROP))
	draw_colored_polygon(shadow, SHADOW)
	var body := PackedVector2Array()
	for p in pts:
		body.append(Vector2(roundf(p.x), roundf(p.y)))
	draw_colored_polygon(body, fill)
	var seam := fill.darkened(0.3)
	var lo := maxf(x0, 0.0)
	var hi := minf(x1, right)
	var sx := x0 + SEAM_PX
	while sx < hi:
		if sx >= lo:
			var y := roundf(_top_at(pts, sx))
			draw_rect(Rect2(sx, y + 1.0, 1.0, base - y - 1.0), seam)
		sx += SEAM_PX
	if bool(b.get("hatched", false)):
		var hatch := fill.lightened(0.14)
		var hx := x0 + maxf(ceilf((lo - x0) / HATCH_PX), 0.0) * HATCH_PX
		while hx < hi:
			var y := roundf(_top_at(pts, hx))
			draw_rect(Rect2(hx, y + 1.0, 1.0, base - y - 1.0), hatch)
			hx += HATCH_PX
	draw_line(body[0], body[1], fill.lightened(0.28), 1.0)
	draw_rect(Rect2(x0, roundf(pts[0].y) + 1.0, 1.0, base - roundf(pts[0].y) - 1.0), seam)


## The block's top edge at `x`.
static func _top_at(pts: PackedVector2Array, x: float) -> float:
	var span := pts[1].x - pts[0].x
	if span <= 0.0:
		return pts[0].y
	return lerpf(pts[0].y, pts[1].y, clampf((x - pts[0].x) / span, 0.0, 1.0))
