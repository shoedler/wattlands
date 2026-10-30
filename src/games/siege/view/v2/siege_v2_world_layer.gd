class_name SiegeV2WorldLayer
extends Node2D
## The baked static world (assets/siege/bake/world.png) at art pixel 0, 0: everything that
## never moves or changes colour, already lit, outlined and graded. Sit it first in the view;
## the depth-tested batches drawn after it test against its depth image.

var bank: SiegeBakeBank = null


func _init(b: SiegeBakeBank = null) -> void:
	bank = b
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	if bank == null:
		bank = SiegeBakeBank.shared()
	queue_redraw()


func _draw() -> void:
	if bank != null and bank.world_texture != null:
		draw_texture(bank.world_texture, Vector2.ZERO)


## The world's depth (x + y + z) at an art pixel, -1e9 for the sky.
func depth_at(px: Vector2i) -> float:
	return bank.world_depth_at(px)


## Whether a world point is hidden by the baked world (behind it at its own art pixel).
func occluded(p: Vector3, bias: float = 0.04) -> bool:
	return SiegeBakeBank.depth_of(p) < bank.world_depth_at(bank.art_pixel(p)) - bias


func sun_at(px: Vector2i) -> float:
	return bank.sun_at(px)
