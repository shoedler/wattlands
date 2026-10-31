class_name HudArtControl
extends Control
## Base of a game's own HUD Controls. Each sits alone in a Rect2i of the HudSpec (`art_rect`, art px
## of the art canvas); the HudLayer anchors that rect on the current canvas (PixelViewport) and sizes
## the Control to it on screen. It draws in art px under a scale transform (u() screen px per art px)
## with nearest filtering, so everything lands on the art grid. It ignores the mouse, refreshes every
## frame and gets the local rider's telemetry from the HudLayer (set_telemetry, found by has_method).
## A game's base adds its typed game and state and overrides has_state().
##
## paint() under that scale is the default path, and a new game should use it. Two games step off it,
## which is why neither part is a rule of this class: FishingHudControl's panels override _draw and
## draw in HUD px, and its place_at keeps the Control's name; SiegeHudCtl overrides _process and _draw
## to refresh its model every 0.1 s, so tick() and refresh() never run there.

## The rect the spec places it in (art px).
var art_rect: Rect2i = Rect2i(0, 0, 960, 540)
## The local rider's latest telemetry (null until the HUD sends one; the rider state stands in).
var tm: Telemetry = null
## How many times _draw ran (tests).
var draws: int = 0
## u() before the Control has a size (the art scale at 1080p).
var default_u: float = 2.0
var _layer: HudLayer = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = false


## Sets the rect the spec places the Control in, names it after its class.
func place_at(rect: Rect2i) -> void:
	art_rect = rect
	var s: Variant = get_script()
	if s is Script:
		name = (s as Script).get_global_name()


## The HudLayer's per-tick local telemetry.
func set_telemetry(t: Telemetry) -> void:
	tm = t


func _process(delta: float) -> void:
	tick(delta)
	if has_state():
		refresh()
	queue_redraw()


## Wall-clock animation (subclasses); tests call it directly.
func tick(_delta: float) -> void:
	pass


## Recomputes what the Control shows (subclasses).
func refresh() -> void:
	pass


## Draws in art px of art_rect (subclasses).
func paint() -> void:
	pass


## Whether there is anything to show yet (subclasses).
func has_state() -> bool:
	return true


## Screen px per art px.
func u() -> float:
	if size.x <= 0.0 or art_rect.size.x <= 0:
		return default_u
	return size.x / float(art_rect.size.x)


func _draw() -> void:
	draws += 1
	if not has_state():
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(u(), u()))
	paint()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The HudLayer this Control sits in (null without one).
func hud_layer() -> HudLayer:
	if _layer == null or not is_instance_valid(_layer):
		_layer = null
		var p := get_parent()
		while p != null and not p is HudLayer:
			p = p.get_parent()
		_layer = p as HudLayer
	return _layer


## The art canvas the HUD lays out on (the HudLayer's flex size; `base` without one).
func canvas_or(base: Vector2i) -> Vector2i:
	var hl := hud_layer()
	if hl != null:
		var a := hl.art_size()
		if a.x > 0 and a.y > 0:
			return a
	return base
