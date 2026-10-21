class_name ParallaxStrip
extends Node2D
## A horizontally repeating backdrop strip for 2D pixel views (BRIEF 3.9).
##
## The strip repeats `texture` side by side from local x 0 across `cover_width` (default:
## the viewport's width, i.e. the PixelViewport's pixel_base.x). The view sets `world_x`
## (its camera or world position in art pixels) every frame; the strip scrolls left by
## world_x * factor, so it is deterministic: the same world_x always draws the same pixels.
##
## - `factor` >= 0: 0 stays still (sky), 0.2 far city, 1.0 moves with the ground, > 1 for
##   foreground debris that passes faster than the ground.
## - `mirror_alternate`: tiles alternate normal and horizontally flipped copies, so the
##   left and right edges of a segment that was never made seamless still meet (B 3.10
##   `tile` + `mirror` sprites, Tank's 240 x 80 `bg_ground`, Fishing's clouds).
## - Vertical placement: the strip's top edge sits at `position.y` (use `align_bottom` to
##   place it by its bottom edge instead).
## - `drift_px_s` adds a constant scroll (clouds) advanced by tick(dt).
##
## Place strips in screen space: in a view without a Camera2D, or inside a CanvasLayer.
## [codeblock]
## var far := ParallaxStrip.new()
## far.texture = preload("res://assets/tank/sprites/bg_city_far.png")
## far.factor = 0.2
## far.position.y = 120
## view.add_child(far)
## # every frame:
## far.world_x = tank_x
## [/codeblock]

## The repeated image (drawn at its own size; nearest filtering comes from the PixelViewport).
var texture: Texture2D = null:
	set(value):
		texture = value
		queue_redraw()

## Parallax factor (>= 0; negative values are clamped to 0 with a warning).
var factor: float = 1.0:
	set(value):
		if value < 0.0:
			push_warning("ParallaxStrip: factor %s < 0 clamped to 0" % value)
		factor = maxf(value, 0.0)
		queue_redraw()

## Alternate normal and horizontally flipped copies so edges match.
var mirror_alternate: bool = false:
	set(value):
		mirror_alternate = value
		queue_redraw()

## The camera or world x the view sets (art pixels).
var world_x: float = 0.0:
	set(value):
		world_x = value
		queue_redraw()

## A constant extra scroll in art pixels (to offset strips that share a texture).
var offset_x: float = 0.0:
	set(value):
		offset_x = value
		queue_redraw()

## Constant drift in art pixels per second, advanced by tick(dt) (clouds).
var drift_px_s: float = 0.0

## Width to cover in art pixels; 0 = the viewport's visible width.
var cover_width: float = 0.0:
	set(value):
		cover_width = maxf(value, 0.0)
		queue_redraw()

## Place the strip by its bottom edge (position.y is the bottom) instead of its top edge.
var align_bottom: bool = false:
	set(value):
		align_bottom = value
		queue_redraw()

## Round the scroll to whole art pixels (crisp pixel art).
var pixel_snap: bool = true:
	set(value):
		pixel_snap = value
		queue_redraw()

## Advance the drift from _process(delta) (a view that drives time itself sets this false
## and calls tick(dt)).
var auto_process: bool = true

var _drift: float = 0.0


func _process(delta: float) -> void:
	if auto_process and drift_px_s != 0.0:
		tick(delta)


## Advance the drift by dt seconds.
func tick(dt: float) -> void:
	if dt <= 0.0 or drift_px_s == 0.0:
		return
	_drift += drift_px_s * dt
	var p := period()
	if p > 0.0:
		_drift = fposmod(_drift, p)
	queue_redraw()


## The current scroll in art pixels: world_x * factor + drift + offset_x (snapped).
func scroll() -> float:
	var s := world_x * factor + _drift + offset_x
	return roundf(s) if pixel_snap else s


## Width of one tile (the texture width), 0 without a texture.
func tile_width() -> float:
	return float(texture.get_width()) if texture != null else 0.0


## The distance after which the strip looks the same again: one tile, or two when mirrored.
func period() -> float:
	return tile_width() * (2.0 if mirror_alternate else 1.0)


## The width this strip covers (cover_width, else the viewport width, else 640).
func covered_width() -> float:
	if cover_width > 0.0:
		return cover_width
	if is_inside_tree():
		return get_viewport_rect().size.x
	return 640.0


## The local y of the strip's top edge: 0, or minus the texture height with align_bottom
## (position.y is then the bottom edge, e.g. a ground line).
func top_y() -> float:
	if align_bottom and texture != null:
		return -float(texture.get_height())
	return 0.0


## The tiles drawn for the current scroll: [{"x": float (local left edge), "index": int
## (tile number along the strip), "flipped": bool}], left to right, covering 0..covered_width().
func visible_tiles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var w := tile_width()
	if w <= 0.0:
		return out
	var s := scroll()
	var cover := covered_width()
	var i := int(floor(s / w))
	var x := float(i) * w - s
	while x < cover:
		out.append({"x": x, "index": i, "flipped": mirror_alternate and posmod(i, 2) == 1})
		x += w
		i += 1
	return out


func _draw() -> void:
	if texture == null:
		return
	var w := tile_width()
	var y := top_y()
	for tile: Dictionary in visible_tiles():
		var x: float = tile["x"]
		if tile["flipped"]:
			draw_set_transform(Vector2(x + w, y), 0.0, Vector2(-1.0, 1.0))
			draw_texture(texture, Vector2.ZERO)
		else:
			draw_set_transform(Vector2(x, y), 0.0, Vector2.ONE)
			draw_texture(texture, Vector2.ZERO)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
