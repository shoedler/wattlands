class_name HudBanner
extends VBoxContainer
## The banner area (BRIEF 3.9, 4.6.3, 4.6.8): the kit's safety banner and the latest game
## banner. The safety banner shows the most urgent of paused, rescue (4.6.3) and warm-up
## (4.6.8), each with its own text and color (paused grey, rescue orange, warm-up purple, all
## with text so color is never the only cue); the warm-up banner is smaller. Game banners
## (ctx.hud.banner) show for their `seconds`; a new one replaces the old. Owned by ui-hud.

const SAFETY_NONE := ""
const SAFETY_WARMUP := "warmup"
const SAFETY_RESCUE := "rescue"
const SAFETY_PAUSED := "paused"
## Panel margins and border around a banner label.
const PANEL_PAD := 44.0

## Show the kit's safety banners (HudSpec.show_safety_banners).
var show_safety: bool = true:
	set(value):
		show_safety = value
		if _safety_panel != null:
			_refresh()
var font_px: int = WlTheme.BANNER_PX
## Widest a banner may get (HudLayer keeps centre stacks clear of the corners); text wraps
## past it.
var max_width: float = INF

var _warmup: bool = false
var _rescue: bool = false
var _paused: bool = false
var _game_left: float = 0.0
var _game_text: String = ""

var _safety_panel: PanelContainer = null
var _safety_label: Label = null
var _game_panel: PanelContainer = null
var _game_label: Label = null


func _init() -> void:
	name = "Banners"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override("separation", 10)
	_safety_panel = _panel("Safety")
	_safety_label = _safety_panel.get_child(0) as Label
	_game_panel = _panel("Game")
	_game_label = _game_panel.get_child(0) as Label
	_game_panel.add_theme_stylebox_override("panel", WlTheme.panel_style(Color(0.08, 0.1, 0.13, 0.94), WlTheme.TEXT, 3))
	_refresh()


func set_safety(warmup_active: bool, rescue: bool, paused: bool) -> void:
	if warmup_active == _warmup and rescue == _rescue and paused == _paused:
		return
	_warmup = warmup_active
	_rescue = rescue
	_paused = paused
	_refresh()


## The banner state shown: "", "warmup", "rescue" or "paused".
func safety_state() -> String:
	if not show_safety:
		return SAFETY_NONE
	if _paused:
		return SAFETY_PAUSED
	if _rescue:
		return SAFETY_RESCUE
	if _warmup:
		return SAFETY_WARMUP
	return SAFETY_NONE


func show_game_banner(text: String, seconds: float = 3.0) -> void:
	_game_text = text
	_game_left = maxf(seconds, 0.1)
	_refresh()


func tick(dt: float) -> void:
	if _game_left > 0.0:
		_game_left -= dt
		if _game_left <= 0.0:
			_game_left = 0.0
			_game_text = ""
			_refresh()


func set_max_width(w: float) -> void:
	max_width = maxf(w, 1.0)
	_refresh()


func game_text() -> String:
	return _game_text


func safety_text() -> String:
	return _safety_label.text if _safety_panel.visible else ""


func safety_label() -> Label:
	return _safety_label


func game_label() -> Label:
	return _game_label


## Text size for the rect the banners sit in (HudLayer, Rect2i areas).
func fit_to(avail: Vector2) -> void:
	var px := WlTheme.BANNER_PX
	if avail.y > 0.0:
		px = clampi(roundi(avail.y / 4.0), WlTheme.MIN_TEXT_PX, WlTheme.BANNER_PX)
	font_px = px
	max_width = avail.x if avail.x > 0.0 else INF
	_refresh()


func _panel(panel_name: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = panel_name
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.name = "Text"
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.label_settings = WlTheme.label_settings(font_px, WlTheme.TEXT, true)
	p.add_child(l)
	add_child(p)
	return p


func _refresh() -> void:
	var state := safety_state()
	_safety_panel.visible = state != SAFETY_NONE
	var bg := WlTheme.PAUSED
	var key := ""
	var px := font_px
	match state:
		SAFETY_PAUSED:
			bg = WlTheme.PAUSED
			key = "UI_BANNER_PAUSED"
		SAFETY_RESCUE:
			bg = WlTheme.WARN
			key = "UI_BANNER_RESCUE"
		SAFETY_WARMUP:
			bg = WlTheme.WARMUP
			key = "UI_BANNER_WARMUP"
			px = maxi(WlTheme.MIN_TEXT_PX, roundi(font_px * 0.6))
	if state != SAFETY_NONE:
		_safety_label.text = HudWidget._t(key)
		_safety_label.label_settings.font_size = px
		_safety_label.label_settings.font_color = WlTheme.text_on(bg)
		_safety_label.label_settings.outline_size = 0
		_safety_panel.add_theme_stylebox_override("panel", WlTheme.panel_style(Color(bg, 0.95), Color.BLACK, 3))
	_game_panel.visible = not _game_text.is_empty()
	_game_label.text = _game_text
	_game_label.label_settings.font_size = font_px
	HudWidget.wrap_label(_safety_label, max_width - PANEL_PAD)
	HudWidget.wrap_label(_game_label, max_width - PANEL_PAD)
