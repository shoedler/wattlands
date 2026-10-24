class_name TankPainter
extends Node2D
## A Node2D whose _draw() calls a Callable with itself: small code-drawn pieces (a haze band, a
## front panel of a room, a barrel) without one script per shape. The owner sets `painter` and calls
## queue_redraw() when the picture changes.

var painter: Callable = Callable()


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
