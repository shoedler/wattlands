class_name SiegeV2WorldLayer
extends Node2D
## The baked static world (assets/siege/bake/world.png), its design frame at art pixel 0, 0:
## everything that never moves or changes colour, already lit, outlined and graded. Sit it first in
## the view; the depth-tested batches drawn after it test against its depth image. A canvas bigger
## than the image (a window far outside what the bake covers; see README) shows mirrored copies of
## it past the edges, real terrain with nothing on it that plays, so no canvas pixel stays black.

var bank: SiegeBakeBank = null
## The art canvas, and where the design frame's top-left lies on it.
var canvas: Vector2i = SiegeBakeBank.ART_SIZE
var view_offset: Vector2i = Vector2i.ZERO


func _init(b: SiegeBakeBank = null) -> void:
	bank = b
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	if bank == null:
		bank = SiegeBakeBank.shared()
	queue_redraw()


func set_canvas(p_canvas: Vector2i, offset: Vector2i) -> void:
	canvas = p_canvas
	view_offset = offset
	queue_redraw()


func _draw() -> void:
	if bank == null or bank.world_texture == null:
		return
	var size := bank.world_size
	for t: Dictionary in tiles(canvas, view_offset, bank.world_origin, size):
		var cell: Vector2i = t["cell"]
		var at := Vector2(cell * size - bank.world_origin)
		var flip := Vector2.ONE
		if posmod(cell.x, 2) == 1:
			flip.x = -1.0
			at.x += size.x
		if posmod(cell.y, 2) == 1:
			flip.y = -1.0
			at.y += size.y
		draw_set_transform(at, 0.0, flip)
		draw_texture(bank.world_texture, Vector2.ZERO)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The copies of the world image a canvas needs: one {"cell": Vector2i} per copy, in image-sized
## cells round the image itself (cell 0, 0; an odd cell is mirrored on that axis).
static func tiles(
	p_canvas: Vector2i, offset: Vector2i, origin: Vector2i, size: Vector2i
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# the canvas in the image's own pixels
	var from := -offset + origin
	var to := from + p_canvas - Vector2i.ONE
	for y in range(floori(float(from.y) / size.y), floori(float(to.y) / size.y) + 1):
		for x in range(floori(float(from.x) / size.x), floori(float(to.x) / size.x) + 1):
			out.append({"cell": Vector2i(x, y)})
	return out


## The world's depth (x + y + z) at an art pixel, -1e9 for the sky.
func depth_at(px: Vector2i) -> float:
	return bank.world_depth_at(px)


## Whether a world point is hidden by the baked world (behind it at its own art pixel).
func occluded(p: Vector3, bias: float = 0.04) -> bool:
	return SiegeBakeBank.depth_of(p) < bank.world_depth_at(bank.art_pixel(p)) - bias


func sun_at(px: Vector2i) -> float:
	return bank.sun_at(px)
