class_name HudToasts
extends VBoxContainer
## The toast area (BRIEF 3.9): short messages stacked newest last, each shown for
## `seconds` (default 3 s) and faded out over its last 0.3 s; at most max_visible at once
## (MAX_VISIBLE, fewer in a small rect; the oldest goes first). Time advances through
## tick(dt) (HudLayer: the session's platform time). Toasts line up on `side` (HudLayer sets it
## from the anchor: left in a left corner, right in a right corner). Owned by ui-hud.

const MAX_VISIBLE := 3
const DEFAULT_S := 3.0
const FADE_S := 0.3
## Panel margins and border around a toast label.
const PANEL_PAD := 40.0
## Toast text never shrinks below this in a small rect (readable from 3 m); fewer toasts show
## at once instead (max_visible).
const MIN_FONT_PX := 24
## One toast's height per font pixel (line height, panel margins and the gap).
const ROW_PER_PX := 1.9

var font_px: int = WlTheme.TOAST_PX
## Toasts shown at once (fit_to lowers it for a small rect; the oldest goes first).
var max_visible: int = MAX_VISIBLE
## Widest a toast may get (HudLayer keeps centre stacks clear of the corners); text wraps
## past it.
var max_width: float = INF
## Which side the toasts line up on: -1 left, 0 centre, 1 right.
var side: int = 0
## The game's colors (HudWidget.set_palette): banner_bg, banner_text, accent (the border).
var palette: HudPalette = HudPalette.new()

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
	panel.size_flags_horizontal = side_flags(side)
	_style_panel(panel)
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.label_settings = WlTheme.label_settings(
		font_px, palette.pick(HudPalette.BANNER_TEXT, WlTheme.TEXT)
	)
	if not palette.style.is_empty():
		palette.style_label(l.label_settings, font_px)
	l.horizontal_alignment = side_alignment(side)
	l.text = text
	HudWidget.wrap_label(l, max_width - PANEL_PAD)
	panel.add_child(l)
	add_child(panel)
	HudPalette.snap_tree(self, palette.grid_px())
	_items.append({"panel": panel, "label": l, "left": maxf(seconds, 0.1), "text": text})
	_trim()


## Use `p` for the toast panels and text (null = the kit look).
func set_palette(p: HudPalette) -> void:
	palette = p if p != null else HudPalette.new()
	palette.style_item(self)
	for it in _items:
		_style_panel(it["panel"] as PanelContainer)
		var ls := (it["label"] as Label).label_settings
		ls.font_color = palette.pick(HudPalette.BANNER_TEXT, WlTheme.TEXT)
		if not palette.style.is_empty():
			palette.style_label(ls, font_px)
	if palette.grid_px() > 0:
		for it2 in _items:
			_style_panel(it2["panel"] as PanelContainer)
	HudPalette.snap_tree(self, palette.grid_px())


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


## Line the toasts up on `s` (-1 left, 0 centre, 1 right). Additive (W2).
func set_side(s: int) -> void:
	side = clampi(s, -1, 1)
	for it in _items:
		(it["panel"] as Control).size_flags_horizontal = side_flags(side)
		(it["label"] as Label).horizontal_alignment = side_alignment(side)


## Size flags for a panel lined up on `s` (-1 left, 0 centre, 1 right).
static func side_flags(s: int) -> int:
	if s < 0:
		return Control.SIZE_SHRINK_BEGIN
	if s > 0:
		return Control.SIZE_SHRINK_END
	return Control.SIZE_SHRINK_CENTER


## Text alignment inside a panel lined up on `s`.
static func side_alignment(s: int) -> HorizontalAlignment:
	if s < 0:
		return HORIZONTAL_ALIGNMENT_LEFT
	if s > 0:
		return HORIZONTAL_ALIGNMENT_RIGHT
	return HORIZONTAL_ALIGNMENT_CENTER


func set_max_width(w: float) -> void:
	max_width = maxf(w, 1.0)
	for it in _items:
		HudWidget.wrap_label(it["label"] as Label, max_width - PANEL_PAD)


func clear() -> void:
	while not _items.is_empty():
		_drop(0)


## Text size and count for the rect the toasts sit in (HudLayer, Rect2i areas): as many
## toasts as fit (up to MAX_VISIBLE) at up to TOAST_PX, never below MIN_FONT_PX.
func fit_to(avail: Vector2) -> void:
	var px := WlTheme.TOAST_PX
	var n := MAX_VISIBLE
	if avail.y > 0.0:
		n = clampi(floori(avail.y / (WlTheme.TOAST_PX * ROW_PER_PX)), 1, MAX_VISIBLE)
		px = clampi(floori(avail.y / (n * ROW_PER_PX)), MIN_FONT_PX, WlTheme.TOAST_PX)
	font_px = px
	max_visible = n
	for it in _items:
		var ls := (it["label"] as Label).label_settings
		if palette.style.is_empty():
			ls.font_size = px
			ls.outline_size = maxi(2, roundi(WlTheme.OUTLINE_PX * px / 64.0))
		else:
			palette.style_label(ls, px)
	_trim()
	set_max_width(avail.x if avail.x > 0.0 else INF)


func _style_panel(panel: PanelContainer) -> void:
	var sb := WlTheme.panel_style(
		palette.pick(HudPalette.BANNER_BG, Color(0.08, 0.1, 0.13, 0.92)),
		palette.pick(HudPalette.ACCENT, WlTheme.ACCENT),
		2
	)
	palette.style_panel(sb)
	if palette.grid_px() > 0:
		sb.set_content_margin_all(3.0 * palette.grid_px())
	panel.add_theme_stylebox_override("panel", sb)


func _trim() -> void:
	while _items.size() > maxi(1, max_visible):
		_drop(0)


func _drop(i: int) -> void:
	var panel: Control = _items[i]["panel"]
	_items.remove_at(i)
	remove_child(panel)
	panel.free()
