class_name WlMarqueeLabel
extends Control
## A one-line label for any width (menu rows: PedalScanList). Text that fits stays still; text
## wider than the space it gets rests at its start, scrolls left to its end, rests, and scrolls
## back, so the whole of it can be read. Its minimum width is 0, so a long text never widens
## its container (and never runs off the screen). Owned by ui-hud.
## Time advances in _process while visible (real_time) or through step(dt) in headless tests.

## Scroll speed in 1080p pixels per second.
const SPEED_PX_S := 90.0
## Seconds the text rests at each end.
const REST_S := 1.5

## _process advances the scroll while the label is visible (tests turn it off and call step).
var real_time: bool = true
## The label inside (its own name and label_settings; WlMarqueeLabel only places it).
var label: Label = null
## The text shown; a new text starts again at its start.
var text: String:
	get:
		return label.text
	set(value):
		label.text = value
		restart()

var _t: float = 0.0


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	label.minimum_size_changed.connect(_on_label_changed)
	resized.connect(_place)


func _get_minimum_size() -> Vector2:
	return Vector2(0.0, label.get_combined_minimum_size().y)


func _process(delta: float) -> void:
	if real_time and is_visible_in_tree():
		step(delta)


## Advance the scroll by dt seconds.
func step(dt: float) -> void:
	var cycle := cycle_s()
	_t = fmod(_t + maxf(dt, 0.0), cycle) if cycle > 0.0 else 0.0
	_place()


## How many pixels the text is wider than the label (0 when it fits).
func overflow_px() -> float:
	return maxf(0.0, label.get_combined_minimum_size().x - size.x)


## Seconds for one full rest-scroll-rest-scroll-back cycle (0 when the text fits).
func cycle_s() -> float:
	var over := overflow_px()
	return 0.0 if over <= 0.0 else 2.0 * (REST_S + over / SPEED_PX_S)


## How far the text is scrolled left now, in pixels (0 at its start, overflow_px() at its end).
func offset_px() -> float:
	var over := overflow_px()
	if over <= 0.0:
		return 0.0
	var travel := over / SPEED_PX_S
	var t := _t
	if t < REST_S:
		return 0.0
	t -= REST_S
	if t < travel:
		return t * SPEED_PX_S
	t -= travel
	if t < REST_S:
		return over
	t -= REST_S
	return maxf(0.0, over - t * SPEED_PX_S)


## Back to the start (new text).
func restart() -> void:
	_t = 0.0
	_place()


func _on_label_changed() -> void:
	update_minimum_size()
	restart()


func _place() -> void:
	var natural := label.get_combined_minimum_size()
	label.size = Vector2(maxf(natural.x, size.x), natural.y)
	label.position = Vector2(-offset_px(), floorf((size.y - natural.y) * 0.5))
