class_name TankSeam
extends Node2D
## v4: the riveted iron column between the near and the far panel (SPEC_TANK 4.6), full height, with the
## range plate of the current target centred on it. The HUD's tags layer draws above it; it never shakes.

const IRON := Color("#17140f")
const EDGE := Color("#8a6a3a")
const TICK_EVERY := 40.0
const PLATE_Y := 216.0
const PLATE_SIZE := Vector2(46, 14)

var v: TankView = null
var rect: Rect2 = Rect2()


func _init(view: TankView) -> void:
	v = view
	name = "Seam"


## The range plate on the canvas.
func plate_rect() -> Rect2:
	return Rect2(Vector2(roundf(rect.get_center().x - PLATE_SIZE.x * 0.5), PLATE_Y), PLATE_SIZE)


func _draw() -> void:
	if v == null or v.game == null or v.game.state == null:
		return
	draw_rect(rect, IRON)
	draw_rect(Rect2(rect.position, Vector2(1, rect.size.y)), EDGE)
	draw_rect(Rect2(Vector2(rect.end.x - 1.0, rect.position.y), Vector2(1, rect.size.y)), EDGE)
	var y := TICK_EVERY
	while y < rect.size.y:
		draw_rect(Rect2(rect.position + Vector2(2, y), Vector2(rect.size.x - 4.0, 1)), EDGE)
		TankHudDraw.rivet(self, rect.position + Vector2(3, y + 10.0))
		y += TICK_EVERY
	var p := plate_rect()
	TankHudDraw.plate(self, p, EDGE, 0)
	var label := TankPip.range_label(v.target_range_m(v.game.state))
	TankHudDraw.text_c(self, p.get_center().x, p.position.y + 3.0, label, TankHudDraw.NUM)
