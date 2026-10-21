class_name PixelViewport
extends SubViewportContainer
## Renders a 2D game's Node2D at its game.json pixel_base with nearest filtering and
## integer scaling to the window, letterboxing the rest (BRIEF 3.9). Owned by world-kits;
## public API frozen after W0. The HUD draws at native resolution above it and maps art-pixel
## Rect2i positions through art_rect_to_screen().

## Art resolution, e.g. Vector2i(640, 360).
var pixel_base: Vector2i = Vector2i(640, 360)


## Put the game's view root inside the pixel viewport (replaces any previous one).
func set_game_view(_view: Node2D) -> void:
	pass


func game_view() -> Node2D:
	return null


## The current integer scale (>= 1).
func integer_scale() -> int:
	return 1


## Top-left offset of the scaled image inside this control (letterbox), screen pixels.
func letterbox_offset() -> Vector2:
	return Vector2.ZERO


## An art-pixel rect -> screen rect (global coordinates of this control's viewport).
func art_rect_to_screen(r: Rect2i) -> Rect2:
	return Rect2(r)


## The rendered frame as an Image (screenshots).
func capture() -> Image:
	return null
