class_name WorkoutParallaxLayer
extends Node2D
## One horizontally tiled parallax strip of the ride view: draws `texture` at `top_y`,
## repeated across the 640 px view and scrolled by a world x the view sets each frame
## (factor 0 stays put, 1 moves with the road). Deterministic: no time, only the scroll.
##
## Workout keeps this tiny layer of its own because the world2d ParallaxStrip had no W0
## stub to code against (see docs/decisions/workout.md); it can switch once that lands.

var texture: Texture2D = null
var factor: float = 1.0
var top_y: float = 0.0
var view_width: float = 640.0
## Current world scroll (px) times `factor` decides the offset.
var scroll_x: float = 0.0


static func make(p_texture: Texture2D, p_factor: float, p_top_y: float) -> WorkoutParallaxLayer:
	var layer := WorkoutParallaxLayer.new()
	layer.texture = p_texture
	layer.factor = p_factor
	layer.top_y = p_top_y
	return layer


func set_scroll(world_x: float) -> void:
	if is_equal_approx(world_x, scroll_x):
		return
	scroll_x = world_x
	queue_redraw()


## X of the first tile (<= 0).
func first_tile_x() -> float:
	if texture == null:
		return 0.0
	var w := float(texture.get_width())
	return -fposmod(floor(scroll_x * factor), w)


func _draw() -> void:
	if texture == null:
		return
	var w := float(texture.get_width())
	var x := first_tile_x()
	while x < view_width:
		draw_texture(texture, Vector2(x, top_y))
		x += w
