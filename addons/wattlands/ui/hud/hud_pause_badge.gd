class_name HudPauseBadge
extends Control
## The pause symbol (BRIEF 3.5): a large pause sign (two bars), UI_PAUSE_TITLE and the resume
## hint UI_PAUSE_HINT, centred near the top of the screen above every game. HudLayer adds it
## to its root and shows it whenever the local rider is paused (the session is paused, or
## Telemetry.paused: the rider's own pause on not pedaling), whatever the game's HudSpec says.
## Owned by platform. Sizes are 1080p pixels.

const BAR_SIZE := Vector2(30, 104)
const BAR_GAP := 30.0
## Top of the symbol: below the top HUD strips, above the pause overlay's menu.
const TOP_FRACTION := 0.15
const DISC_COLOR := Color(0.055, 0.067, 0.086, 0.8)

var _symbol: Control = null
var _title: Label = null
var _hint: Label = null


func _init() -> void:
	name = "PauseBadge"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var box := VBoxContainer.new()
	box.name = "Box"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.add_theme_constant_override("separation", 8)
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(box)
	_symbol = Control.new()
	_symbol.name = "Symbol"
	_symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_symbol.custom_minimum_size = Vector2(BAR_SIZE.y * 1.6, BAR_SIZE.y * 1.6)
	_symbol.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_symbol.draw.connect(_draw_symbol)
	box.add_child(_symbol)
	_title = _label("Title", WlTheme.BANNER_PX, WlTheme.TEXT)
	box.add_child(_title)
	_hint = _label("Hint", WlTheme.BODY_PX, WlTheme.TEXT_DIM)
	box.add_child(_hint)
	_title.text = HudWidget._t("UI_PAUSE_TITLE")
	_hint.text = HudWidget._t("UI_PAUSE_HINT")


## Place the symbol for a screen of `screen` size (HudLayer calls it on every relayout).
func layout(screen: Vector2) -> void:
	position = Vector2(0.0, roundf(screen.y * TOP_FRACTION))
	size = Vector2(screen.x, 0.0)


func set_paused(paused: bool) -> void:
	visible = paused


func title_label() -> Label:
	return _title


func hint_label() -> Label:
	return _hint


func _draw_symbol() -> void:
	var s := _symbol.size
	var c := s * 0.5
	_symbol.draw_circle(c, minf(s.x, s.y) * 0.5, DISC_COLOR)
	_symbol.draw_arc(c, minf(s.x, s.y) * 0.5 - 2.0, 0.0, TAU, 64, WlTheme.PAUSED, 4.0, true)
	var x0 := c.x - BAR_GAP * 0.5 - BAR_SIZE.x
	var y0 := c.y - BAR_SIZE.y * 0.5
	_symbol.draw_rect(Rect2(Vector2(x0, y0), BAR_SIZE), WlTheme.TEXT)
	_symbol.draw_rect(Rect2(Vector2(c.x + BAR_GAP * 0.5, y0), BAR_SIZE), WlTheme.TEXT)


static func _label(label_name: String, px: int, color: Color) -> Label:
	var l := Label.new()
	l.name = label_name
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ls := LabelSettings.new()
	ls.font_size = px
	ls.font_color = color
	ls.outline_size = 8
	ls.outline_color = WlTheme.OUTLINE
	l.label_settings = ls
	return l
