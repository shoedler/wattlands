class_name HudHelp
extends Control
## The help overlay (HudSpec.help, v0.3.0): one small panel per entry with its text and an
## optional arrow from the panel to the entry's `arrow_to`, plus a title strip with the close
## hint, above the game and the rest of the HUD. HudLayer owns it (show_help, hide_help,
## toggle_help); the GameHost toggles it on the `help` action (F1, the left stick click) and
## closes it on `back` or `confirm`. It hides itself AUTO_HIDE_S after it opened, on the time
## HudLayer.tick() advances (the session's platform time). The game keeps running underneath.
##
## Positions: with a PixelViewport (2D games) `at` and `arrow_to` are art pixels, else 0..1 of
## the screen. A panel is centred on `at` and kept on screen. In a 2D game whose palette sets
## grid_px, panels sit on whole art pixels and the arrow is drawn in art pixels (a Bresenham
## line one art pixel wide with a pixel head); otherwise the arrow is a smooth screen-space
## line with a triangle head. Styling follows HudSpec.palette: panel, panel_border, text,
## accent (the arrow), font and grid_px. Owned by platform. Sizes are 1080p pixels.

const AUTO_HIDE_S := 20.0
## The title strip's top, as a fraction of the screen height (the pause badge's height).
const TITLE_FRACTION := 0.15
const MAX_PANEL_W := 560.0
const ARROW_W := 4.0
const HEAD_PX := 20.0
const MARGIN := float(WlTheme.MARGIN_PX)

var palette: HudPalette = HudPalette.new()

## [{"text": String (resolved), "at": Vector2, "arrow_to": Vector2 or null}]
var _entries: Array[Dictionary] = []
var _panels: Array[PanelContainer] = []
var _title: PanelContainer = null
var _title_label: Label = null
var _pv: PixelViewport = null
var _screen: Vector2 = HudLayer.BASE_SIZE
var _left_s: float = 0.0
## (Vector2 art px laid out on pixel_base) -> Vector2 art px now. Identity until a flex
## Maps an entry's art point (laid out on pixel_base) to the current art canvas; HudLayer sets
## HudLayer.help_art_point (the HUD's flex anchoring) so help points follow the HUD.
var art_map: Callable = Callable()


func _init() -> void:
	name = "Help"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_title = PanelContainer.new()
	_title.name = "Title"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label = _make_label(HudWidget._t("UI_HELP_TITLE"))
	_title.add_child(_title_label)
	add_child(_title)
	_style_panel(_title)


## Entries already resolved by HudLayer: {"text": String, "at": Vector2, "arrow_to": Vector2
## (optional)}. Rebuilds the panels.
func set_entries(entries: Array[Dictionary]) -> void:
	for p in _panels:
		p.queue_free()
	_panels.clear()
	_entries = entries.duplicate(true)
	for e in _entries:
		var panel := PanelContainer.new()
		panel.name = "Entry%d" % _panels.size()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := _make_label(str(e.get("text", "")))
		HudWidget.wrap_label(l, MAX_PANEL_W)
		panel.add_child(l)
		_style_panel(panel)
		add_child(panel)
		_panels.append(panel)
	HudPalette.snap_tree(self, palette.grid_px())
	if visible:
		layout(_screen, _pv)


func entry_count() -> int:
	return _entries.size()


## The panel of entry `i` (tests).
func panel(i: int) -> PanelContainer:
	return _panels[i] if i >= 0 and i < _panels.size() else null


func title_label() -> Label:
	return _title_label


## The text of every entry, in order (tests).
func texts() -> Array[String]:
	var out: Array[String] = []
	for e in _entries:
		out.append(str(e.get("text", "")))
	return out


## Use `p` for panels, text and the arrow (null = the kit look).
func set_palette(p: HudPalette) -> void:
	palette = p if p != null else HudPalette.new()
	palette.style_item(self)
	for pc: PanelContainer in [_title] + _panels:
		_style_panel(pc)
		var l := pc.get_child(0) as Label
		if l != null:
			_style_label(l.label_settings)
	HudPalette.snap_tree(self, palette.grid_px())
	queue_redraw()


## Show it for `seconds` (AUTO_HIDE_S by default).
func open(seconds: float = AUTO_HIDE_S) -> void:
	_left_s = maxf(seconds, 0.0)
	visible = true
	layout(_screen, _pv)


func close() -> void:
	visible = false
	_left_s = 0.0


## Seconds until it hides itself (0 while hidden).
func left_s() -> float:
	return _left_s if visible else 0.0


func tick(dt: float) -> void:
	if not visible or dt <= 0.0:
		return
	_left_s -= dt
	if _left_s <= 1e-9:
		close()


## Place the panels for a screen of `screen` size; `pv` maps art pixels (null: 0..1 of the
## screen). HudLayer calls it on every relayout.
func layout(screen: Vector2, pv: PixelViewport = null) -> void:
	_screen = screen
	_pv = pv if pv != null and is_instance_valid(pv) else null
	position = Vector2.ZERO
	size = screen
	var tsz := _title.get_combined_minimum_size()
	_title.size = tsz
	_title.position = _on_grid(
		Vector2(roundf((screen.x - tsz.x) * 0.5), roundf(screen.y * TITLE_FRACTION))
	)
	for i in _panels.size():
		var p := _panels[i]
		var sz := p.get_combined_minimum_size()
		p.size = sz
		var c := to_screen(_entries[i].get("at", Vector2.ZERO))
		var pos := (c - sz * 0.5).round()
		pos.x = clampf(pos.x, MARGIN, maxf(MARGIN, screen.x - sz.x - MARGIN))
		pos.y = clampf(pos.y, MARGIN, maxf(MARGIN, screen.y - sz.y - MARGIN))
		p.position = _on_grid(pos)
	queue_redraw()


## An entry point (art pixels with a PixelViewport, else 0..1 of the screen) on screen.
func to_screen(v: Variant) -> Vector2:
	var p: Vector2 = v if v is Vector2 else Vector2.ZERO
	if _pv != null:
		return _pv.art_to_screen(art_point(p))
	return p * _screen


## An entry's art point (laid out on pixel_base) in the current art size: art_map when set,
## else unchanged.
func art_point(p: Vector2) -> Vector2:
	if art_map.is_valid():
		return art_map.call(p)
	return p


## The arrow of entry `i` on screen: [from, to] (from the panel's edge), or [] without one.
func arrow_of(i: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if i < 0 or i >= _entries.size() or not (_entries[i].get("arrow_to") is Vector2):
		return out
	var r := Rect2(_panels[i].position, _panels[i].size)
	var target := to_screen(_entries[i]["arrow_to"])
	if r.has_point(target):
		return out
	var c := r.get_center()
	var d := target - c
	var half := r.size * 0.5
	var s := INF
	if absf(d.x) > 1e-6:
		s = minf(s, half.x / absf(d.x))
	if absf(d.y) > 1e-6:
		s = minf(s, half.y / absf(d.y))
	out.append(c + d * minf(s, 1.0))
	out.append(target)
	return out


## True when the arrows are drawn in art pixels (a 2D game whose palette sets grid_px).
func pixel_arrows() -> bool:
	return _pv != null and palette.grid_px() > 0


## The art pixels of entry `i`'s pixel arrow (pixel_arrows()), line then head.
func arrow_pixels(i: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var a := arrow_of(i)
	if a.is_empty() or _pv == null:
		return out
	var from := Vector2i(_pv.screen_to_art(a[0]).floor())
	var to := Vector2i(art_point(_entries[i]["arrow_to"] as Vector2).floor())
	out = line_pixels(from, to)
	var d := Vector2(to - from)
	if d.length() < 1e-6:
		return out
	d = d.normalized()
	var perp := Vector2i(roundi(-d.y), roundi(d.x))
	if perp == Vector2i.ZERO:
		perp = Vector2i(1, 0)
	for back in [1, 2]:
		var b := to - Vector2i((d * float(back)).round())
		for k in range(1, back + 1):
			for px: Vector2i in [b + perp * k, b - perp * k]:
				if not out.has(px):
					out.append(px)
	return out


## The pixels of a line from `a` to `b` (Bresenham, both ends included).
static func line_pixels(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	return PixelPainter.line_pixels(a, b)


func _draw() -> void:
	var col := palette.pick(HudPalette.ACCENT, WlTheme.ACCENT)
	for i in _entries.size():
		var a := arrow_of(i)
		if a.is_empty():
			continue
		if pixel_arrows():
			for px in arrow_pixels(i):
				var r := _pv.art_rect_to_screen(Rect2i(px, Vector2i.ONE))
				draw_rect(Rect2(r.position - global_position, r.size), col)
			continue
		var from := a[0] - global_position
		var to := a[1] - global_position
		var d := (to - from).normalized()
		var perp := Vector2(-d.y, d.x)
		var base := to - d * HEAD_PX
		draw_line(from, base, WlTheme.OUTLINE, ARROW_W + 4.0, true)
		draw_line(from, base, col, ARROW_W, true)
		var head := PackedVector2Array(
			[to, base + perp * HEAD_PX * 0.6, base - perp * HEAD_PX * 0.6]
		)
		draw_colored_polygon(head, col)


func _on_grid(pos: Vector2) -> Vector2:
	if _pv == null or palette.grid_px() <= 0:
		return pos
	return _pv.art_to_screen(_pv.screen_to_art(pos).round())


func _make_label(text: String) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.label_settings = WlTheme.label_settings(WlTheme.BODY_PX)
	_style_label(l.label_settings)
	l.text = text
	return l


func _style_label(ls: LabelSettings) -> void:
	if ls == null:
		return
	ls.font_color = palette.pick(HudPalette.TEXT, WlTheme.TEXT)
	if not palette.style.is_empty():
		palette.style_label(ls, WlTheme.BODY_PX)


func _style_panel(pc: PanelContainer) -> void:
	var sb := WlTheme.panel_style(
		palette.pick(HudPalette.PANEL, WlTheme.PANEL),
		palette.pick(HudPalette.PANEL_BORDER, WlTheme.PANEL_BORDER),
		2
	)
	palette.style_panel(sb)
	if palette.grid_px() > 0:
		sb.set_content_margin_all(3.0 * palette.grid_px())
	pc.add_theme_stylebox_override("panel", sb)
