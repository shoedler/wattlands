class_name SiegeDepthBatch
extends Node2D
## A batched drawer of baked frames with the depth-tested sprite shader (siege_depth_sprite):
## one RenderingServer canvas item per bake atlas, each with that atlas's material, so a whole
## crowd or a whole fort of machines costs one draw call per atlas. Queue frames between
## begin() and commit(); within an atlas they are drawn far to near by their sort key (the
## anchor depth unless given), and atlases in id order. The node's position must be the art
## origin of the view it sits in (normally 0, 0 of the PixelViewport's game view).

## Most entries a batch takes per commit (more are dropped and counted in `dropped`).
const MAX_ENTRIES := 8192
const SORT_SCALE := 64.0

var bank: SiegeBakeBank = null
## Entries dropped by the last commit for want of room.
var dropped: int = 0

var _items: Array[RID] = []
var _atlas := PackedInt32Array()
var _sort := PackedFloat64Array()
var _rects: Array[Rect2] = []
var _srcs: Array[Rect2] = []
var _mods := PackedColorArray()
var _count: int = 0
var _committed: int = 0


func _init(b: SiegeBakeBank = null) -> void:
	bank = b
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	if bank == null:
		bank = SiegeBakeBank.shared()
	_ensure_items()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for rid in _items:
			RenderingServer.free_rid(rid)
		_items.clear()


func _ensure_items() -> void:
	if bank == null or not bank.ok or not is_inside_tree():
		return
	while _items.size() < bank.atlases.size():
		var rid := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(rid, get_canvas_item())
		RenderingServer.canvas_item_set_material(rid, bank.material(_items.size()).get_rid())
		RenderingServer.canvas_item_set_default_texture_filter(
			rid, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		)
		_items.append(rid)


## Starts a new frame's queue.
func begin() -> void:
	_count = 0
	dropped = 0
	_atlas.resize(0)
	_sort.resize(0)
	_rects.clear()
	_srcs.clear()
	_mods.resize(0)


## Queues frame `index` of `part` hanging on world point `anchor`. `row` is the ramp row
## (SiegeBakeBank.ramp_row_for), `shade` the sun 0..1 (1 for parts baked in place), `sort_key`
## the draw order within the atlas (NAN: the anchor's depth). Returns false for an empty frame.
func add(
	part: String,
	index: int,
	anchor: Vector3,
	row: int = 0,
	shade: float = 1.0,
	alpha: float = 1.0,
	sort_key: float = NAN
) -> bool:
	var fr := bank.frames_of(part)
	if index < 0 or index * 7 + 7 > fr.size():
		return false
	var o := index * 7
	if fr[o] < 0:
		return false
	var px := bank.art_pixel(anchor)
	var d := SiegeBakeBank.depth_of(anchor)
	_push(
		fr[o],
		Rect2(px.x - fr[o + 5], px.y - fr[o + 6], fr[o + 3], fr[o + 4]),
		Rect2(fr[o + 1], fr[o + 2], fr[o + 3], fr[o + 4]),
		bank.pack_modulate(d, row, shade, alpha),
		d if is_nan(sort_key) else sort_key
	)
	return true


## Queues a cell of the `px` palette part (frame `index`) as a size x size block at art pixel
## `at` with depth `depth` (projectile pixels, trails, shadows, hp bars).
func add_px(
	index: int, at: Vector2i, depth: float, alpha: float = 1.0, size: Vector2i = Vector2i.ONE
) -> void:
	var fr := bank.frames_of("px")
	if index < 0 or index * 7 + 7 > fr.size():
		return
	var o := index * 7
	_push(
		fr[o],
		Rect2(at.x, at.y, size.x, size.y),
		Rect2(fr[o + 1], fr[o + 2], 1, 1),
		bank.pack_modulate(depth, 0, 1.0, alpha),
		depth + 1000.0
	)


func _push(atlas: int, rect: Rect2, src: Rect2, mod: Color, key: float) -> void:
	if _count >= MAX_ENTRIES:
		dropped += 1
		return
	_atlas.append(atlas)
	_sort.append(floorf((key + 1000.0) * SORT_SCALE) * float(MAX_ENTRIES) + float(_count))
	_rects.append(rect)
	_srcs.append(src)
	_mods.append(mod)
	_count += 1


## Entries queued since begin().
func entry_count() -> int:
	return _count


## Entries the last commit drew.
func committed_count() -> int:
	return _committed


## Sends the queue to the RenderingServer, sorted.
func commit() -> void:
	_ensure_items()
	for rid in _items:
		RenderingServer.canvas_item_clear(rid)
	_committed = 0
	if _items.is_empty():
		return
	var keys := _sort.duplicate()
	keys.sort()
	for key in keys:
		var i := int(fmod(key, float(MAX_ENTRIES)))
		var a := _atlas[i]
		if a < 0 or a >= _items.size():
			continue
		RenderingServer.canvas_item_add_texture_rect_region(
			_items[a], _rects[i], bank.atlases[a].get_rid(), _srcs[i], _mods[i], false, false
		)
		_committed += 1
