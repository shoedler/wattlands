class_name HudWbal
extends HudWidget
## Kit widget `wbal` (BRIEF 3.4, 3.9; HudSpec.WBAL): the W' balance stamina bar with its
## percentage. Below 25% it turns orange and shows "low" text, so it reads without color.
## Options: {"wprime_j": float} (default: the local profile's W', 20000 J).
## base_size 380 x 56; min_rect 240 x 40.

const LOW := 0.25

## The rider's W' in joules (full bar).
var wprime_j: float = 20000.0

var _wbal_j: float = 20000.0
var _caption: Label = null
var _pct: Label = null
var _bar: HudBar = null


func _init() -> void:
	_ensure_base()
	widget_id = HudSpec.WBAL
	var row := _hbox("Row", 12)
	_content.add_child(row)
	_caption = _make_label("Caption", WlTheme.LABEL_PX, WlTheme.TEXT_DIM, false, true)
	_caption.text = _t("UI_HUD_WBAL")
	row.add_child(_caption)
	_bar = HudBar.new()
	_bar.name = "Bar"
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_bar)
	_scale_box(_bar, 120.0, 26.0)
	_pct = _make_label("Pct", WlTheme.BODY_PX)
	_pct.custom_minimum_size = Vector2(96, 0)
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_pct)
	set_ui_scale(1.0)
	_refresh()


func configure(p_options: Dictionary) -> void:
	super.configure(p_options)
	if p_options.has("wprime_j"):
		wprime_j = maxf(1.0, float(p_options["wprime_j"]))


func base_size() -> Vector2:
	return Vector2(380, 56)


func min_rect() -> Vector2:
	return Vector2(240, 40)


func set_telemetry(t: Telemetry) -> void:
	if t == null:
		return
	set_wbal(t.wbal_j)


func set_wbal(wbal_j: float) -> void:
	_wbal_j = wbal_j
	_refresh()


## 0..1 of W' left.
func fraction() -> float:
	return clampf(_wbal_j / maxf(wprime_j, 1.0), 0.0, 1.0)


func is_low() -> bool:
	return fraction() < LOW


func pct_label() -> Label:
	return _pct


func bar() -> HudBar:
	return _bar


func _refresh() -> void:
	if _bar == null:
		return
	var f := fraction()
	_bar.fill_color = WlTheme.WARN if is_low() else WlTheme.ACCENT
	_bar.set_state(f, 1.0)
	_pct.text = ("%d%%" % roundi(f * 100.0)) if not is_low() else _t("UI_HUD_WBAL_LOW", [roundi(f * 100.0)])
	_pct.label_settings.font_color = WlTheme.WARN if is_low() else WlTheme.TEXT
