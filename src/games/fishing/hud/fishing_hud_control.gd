class_name FishingHudControl
extends Control
## Base of Fishing's own HUD Controls: each sits alone in a Rect2i of the HudSpec, so the HUD
## sizes it to that rect mapped to the screen (art px x 3 at 1080p); it fills it, ignores the
## mouse, refreshes its model every frame and draws scaled to its size (`k()` = 1 at 1080p).

## The rect's height in 1080p canvas px at scale 3 (set by each subclass).
var design_h: float = 72.0
var game: FishingGame = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	theme = WlTheme.get_theme()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(_delta: float) -> void:
	refresh()
	queue_redraw()


## Recomputes what the Control shows (subclasses).
func refresh() -> void:
	pass


## Draw scale: the Control's height over its design height (1 at 1080p).
func k() -> float:
	return size.y / design_h if size.y > 0.0 else 1.0


func px(base: int) -> int:
	return maxi(roundi(float(base) * k()), WlTheme.MIN_TEXT_PX)
