class_name HudToasts
extends VBoxContainer
## The toast area (BRIEF 3.9): short messages stacked newest last, each shown for
## `seconds` (default 3 s) and faded out over its last 0.3 s; at most MAX_VISIBLE at once
## (the oldest goes first). Time advances through tick(dt) (HudLayer._process). Owned by
## ui-hud.

const MAX_VISIBLE := 3
const DEFAULT_S := 3.0
const FADE_S := 0.3
## Panel margins and border around a toast label.
const PANEL_PAD := 40.0

var font_px: int = WlTheme.TOAST_PX
## Widest a toast may get (HudLayer keeps centre stacks clear of the corners); text wraps
## past it.
var max_width: float = INF

## [{"panel": PanelContainer, "label": Label, "left": float, "text": String}]
var _items: Array[Dictionary] = []


func _init() -> void:
	name = "Toasts"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override("separation", 8)


func push(text: String, seconds: float = DEFAULT_S) -> void:
	if text.is_empty():
		return
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", WlTheme.panel_style(Color(0.08, 0.1, 0.13, 0.92), WlTheme.ACCENT, 2))
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.label_settings = WlTheme.label_settings(font_px)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text = text
	HudWidget.wrap_label(l, max_width - PANEL_PAD)
	panel.add_child(l)
	add_child(panel)
	_items.append({"panel": panel, "label": l, "left": maxf(seconds, 0.1), "text": text})
	while _items.size() > MAX_VISIBLE:
		_drop(0)


func tick(dt: float) -> void:
	var i := 0
	while i < _items.size():
		var it := _items[i]
		var left: float = float(it["left"]) - dt
		it["left"] = left
		if left <= 0.0:
			_drop(i)
			continue
		(it["panel"] as Control).modulate.a = clampf(left / FADE_S, 0.0, 1.0)
		i += 1


## The texts shown now, oldest first.
func texts() -> Array[String]:
	var out: Array[String] = []
	for it in _items:
		out.append(str(it["text"]))
	return out


func set_max_width(w: float) -> void:
	max_width = maxf(w, 1.0)
	for it in _items:
		HudWidget.wrap_label(it["label"] as Label, max_width - PANEL_PAD)


func clear() -> void:
	while not _items.is_empty():
		_drop(0)


## Text size for the rect the toasts sit in (HudLayer, Rect2i areas).
func fit_to(avail: Vector2) -> void:
	var px := WlTheme.TOAST_PX
	if avail.y > 0.0:
		px = clampi(roundi(avail.y / (MAX_VISIBLE * 1.9)), WlTheme.MIN_TEXT_PX, WlTheme.TOAST_PX)
	font_px = px
	for it in _items:
		(it["label"] as Label).label_settings.font_size = px
	set_max_width(avail.x if avail.x > 0.0 else INF)


func _drop(i: int) -> void:
	var panel: Control = _items[i]["panel"]
	_items.remove_at(i)
	remove_child(panel)
	panel.free()
