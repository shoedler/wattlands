class_name SiegeV2WorldLayer
extends Node2D
## The baked static world (assets/siege/bake/world.png), its design frame at art pixel 0, 0:
## everything that never moves or changes colour, already lit, outlined and graded. Sit it first in
## the view; the depth-tested batches drawn after it test against its depth image. A canvas bigger
## than the image (a window far outside what the bake covers; see README) continues past each edge
## with that edge's margin mirrored back and forth: real terrain, never the fort, never black.

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
	for t: Dictionary in tiles(canvas, view_offset, bank.world_origin, bank.world_size):
		var src: Rect2i = t["src"]
		var flip: Vector2i = t["flip"]
		var at := Vector2(t["at"] as Vector2i - bank.world_origin)
		at += Vector2(src.size * flip)
		draw_set_transform(at, 0.0, Vector2(Vector2i.ONE - flip * 2))
		draw_texture_rect_region(bank.world_texture, Rect2(Vector2.ZERO, src.size), Rect2(src))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## What a canvas needs drawn: the whole world image, and only when the canvas runs past it, the image's
## margins mirrored on from each edge. Entries {"at": Vector2i (top-left, in the image's pixels), "src":
## Rect2i (of the image), "flip": Vector2i (1 where that axis is mirrored)}; the image first.
static func tiles(
	p_canvas: Vector2i, offset: Vector2i, origin: Vector2i, size: Vector2i
) -> Array[Dictionary]:
	var from := origin - offset
	var to := from + p_canvas
	var out: Array[Dictionary] = []
	for y: PackedInt32Array in _spans(from.y, to.y, size.y, origin.y):
		for x: PackedInt32Array in _spans(from.x, to.x, size.x, origin.x):
			var src := Rect2i(x[2], y[2], x[1], y[1])
			out.append({"at": Vector2i(x[0], y[0]), "src": src, "flip": Vector2i(x[3], y[3])})
	return out


## One axis of tiles(): [where, length, source start, mirrored] for the image, then for the copies of
## its margin past either end that reach into from..to.
static func _spans(from: int, to: int, size: int, margin: int) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = [PackedInt32Array([0, size, 0, 0])]
	var step := margin if margin > 0 else size
	var at := size
	var mirrored := 1
	while at < to:
		out.append(PackedInt32Array([at, step, size - step, mirrored]))
		at += step
		mirrored = 1 - mirrored
	at = 0
	mirrored = 1
	while at > from:
		at -= step
		out.append(PackedInt32Array([at, step, 0, mirrored]))
		mirrored = 1 - mirrored
	return out


## The world's depth (x + y + z) at an art pixel, -1e9 for the sky.
func depth_at(px: Vector2i) -> float:
	return bank.world_depth_at(px)


## Whether a world point is hidden by the baked world (behind it at its own art pixel).
func occluded(p: Vector3, bias: float = 0.04) -> bool:
	return SiegeBakeBank.depth_of(p) < bank.world_depth_at(bank.art_pixel(p)) - bias


func sun_at(px: Vector2i) -> float:
	return bank.sun_at(px)
