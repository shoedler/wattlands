class_name HudWidget
extends PanelContainer
## Base of the HUD kit widgets (BRIEF 3.9; HudSpec.KIT_WIDGETS). Owned by ui-hud.
## Each widget is a Control usable on its own (add it anywhere and feed it with
## set_telemetry/set_phase and its own setters) or through HudSpec and HudLayer.
##
## Sizes are 1080p pixels. base_size() is the natural size at ui_scale 1.0; fit_to(rect size)
## shrinks a widget to fit a rect (never grows it above 1.0). Key numbers (own watts, rpm,
## gear, big readouts) never go below WlTheme.KEY_NUMBER_MIN_PX (48 px), so a widget asked
## to fit a rect smaller than min_rect() overflows it instead of shrinking those numbers.
## Options (HudSpec.add(..., options)): "panel": false drops the dark background panel.

## The kit widget id (HudSpec.POWER_GAUGE, ...).
var widget_id: String = ""
## Options from HudSpec.add().
var options: Dictionary = {}
## 1.0 = full size at 1080p.
var ui_scale: float = 1.0
## The local rider's FTP in watts (for %FTP when telemetry lacks it, and gauge ranges).
var ftp_w: float = 200.0
## > 0 when the rider opted in to W/kg: the weight used for it.
var weight_kg: float = 0.0

var _content: VBoxContainer = null
## Labels that follow ui_scale: {"label": Label, "px": int, "key": bool}.
var _scaled: Array[Dictionary] = []
## Controls whose minimum height follows ui_scale: {"node": Control, "h": float, "w": float}.
var _scaled_boxes: Array[Dictionary] = []


func _init() -> void:
	_ensure_base()


## Shared setup (idempotent): subclasses call it first in their own _init.
func _ensure_base() -> void:
	if _content != null:
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	var sb := WlTheme.panel_style(Color(0.055, 0.067, 0.086, 0.74), Color(0.227, 0.271, 0.322, 0.9), 2)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 6.0
	add_theme_stylebox_override("panel", sb)
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override("separation", 4)
	add_child(_content)


## Apply options (call before adding to the tree; HudLayer does).
func configure(p_options: Dictionary) -> void:
	options = p_options.duplicate(true)
	if options.get("panel", true) == false:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())


## Natural size at ui_scale 1.0 (1080p pixels).
func base_size() -> Vector2:
	return Vector2(300, 100)


## The smallest rect (1080p pixels) in which nothing overflows and key numbers stay >= 48 px.
func min_rect() -> Vector2:
	return base_size() * 0.75


## Shrink to fit `avail` (1080p pixels); never above 1.0.
func fit_to(avail: Vector2) -> void:
	var b := base_size()
	var s := 1.0
	if avail.x > 0.0 and avail.y > 0.0 and b.x > 0.0 and b.y > 0.0:
		s = minf(1.0, minf(avail.x / b.x, avail.y / b.y))
	set_ui_scale(maxf(s, 0.25))


func set_ui_scale(s: float) -> void:
	ui_scale = clampf(s, 0.25, 4.0)
	custom_minimum_size = base_size() * ui_scale
	for e in _scaled:
		var lbl: Label = e["label"]
		var px: int = e["px"]
		if lbl.label_settings != null:
			lbl.label_settings.font_size = WlTheme.key_px(ui_scale * px / float(WlTheme.KEY_NUMBER_PX)) if e["key"] else WlTheme.scaled_px(px, ui_scale)
			lbl.label_settings.outline_size = maxi(2, roundi(WlTheme.OUTLINE_PX * lbl.label_settings.font_size / 64.0))
	for e in _scaled_boxes:
		var n: Control = e["node"]
		n.custom_minimum_size = Vector2(float(e["w"]) * ui_scale, float(e["h"]) * ui_scale)
	var sb := get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null and has_theme_stylebox_override("panel"):
		sb.content_margin_left = 12.0 * ui_scale
		sb.content_margin_right = 12.0 * ui_scale
		sb.content_margin_top = 4.0 * ui_scale
		sb.content_margin_bottom = 6.0 * ui_scale
	_on_scale_changed()


## The latest local telemetry (HudLayer.update calls it every tick).
func set_telemetry(_t: Telemetry) -> void:
	pass


## The current phase and the local plan (timeline).
func set_phase(_phase: PhaseState, _plan: EffortPlan) -> void:
	pass


## Font size of `label` right now (tests, layout checks).
static func font_px(label: Label) -> int:
	if label == null:
		return 0
	if label.label_settings != null:
		return label.label_settings.font_size
	return label.get_theme_font_size("font_size")


# --- helpers for subclasses ------------------------------------------------------------------

## A Label using the kit font. key = a key number (>= 48 px at any scale).
func _make_label(label_name: String, px: int, color: Color = WlTheme.TEXT, key: bool = false, bold: bool = false) -> Label:
	var l := Label.new()
	l.name = label_name
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.label_settings = WlTheme.label_settings(px, color, bold or key)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_scaled.append({"label": l, "px": px, "key": key})
	return l


## Register a control whose minimum size follows ui_scale (bars, chips, strips).
func _scale_box(node: Control, w: float, h: float) -> void:
	_scaled_boxes.append({"node": node, "w": w, "h": h})


func _hbox(box_name: String, separation: int = 8) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.name = box_name
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", separation)
	return hb


func _on_scale_changed() -> void:
	pass


## Translated text for a platform or game key; plain text passes through.
static func _t(key: String, args: Variant = []) -> String:
	var text := String(TranslationServer.translate(key))
	if args is Array and not (args as Array).is_empty():
		return text.format(args)
	if args is Dictionary and not (args as Dictionary).is_empty():
		return text.format(args)
	return text


## m:ss (or h:mm:ss).
static func clock_text(seconds: float) -> String:
	var s := maxi(0, ceili(seconds - 1e-6))
	var h := s / 3600
	var m := (s % 3600) / 60
	var sec := s % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, sec]
	return "%d:%02d" % [m, sec]
