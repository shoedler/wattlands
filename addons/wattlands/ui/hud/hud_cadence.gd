class_name HudCadence
extends HudWidget
## Kit widget `cadence` (BRIEF 3.9; HudSpec.CADENCE): rpm as a key number and a bar with the
## optional band published by ctx.directives.cadence_band, glowing in band. Data older than
## 3 s (Telemetry.cadence_age_s) dims the widget. Options: {"peer": int} (default: the local
## rider). base_size 360 x 124; min_rect 290 x 98.

const STALE_S := 3.0

var peer: int = 0

var _rpm: float = 0.0
var _lo: float = 0.0
var _hi: float = 0.0
var _stale: bool = false

var _value: Label = null
var _unit: Label = null
var _band: Label = null
var _bar: HudBar = null


func _init() -> void:
	_ensure_base()
	widget_id = HudSpec.CADENCE
	var top := _hbox("Top", 10)
	_content.add_child(top)
	_value = _make_label("Rpm", WlTheme.KEY_NUMBER_PX, WlTheme.TEXT, true)
	_value.text = "0"
	top.add_child(_value)
	_unit = _make_label("Unit", WlTheme.LABEL_PX, WlTheme.TEXT_DIM)
	_unit.text = _t("UI_HUD_RPM")
	_unit.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	top.add_child(_unit)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	_band = _make_label("Band", WlTheme.SMALL_PX, WlTheme.TEXT_DIM)
	_band.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_band)
	_bar = HudBar.new()
	_bar.name = "Bar"
	_content.add_child(_bar)
	_scale_box(_bar, 0.0, 20.0)
	set_ui_scale(1.0)
	_refresh()


func base_size() -> Vector2:
	return Vector2(360, 124)


func min_rect() -> Vector2:
	return Vector2(290, 98)


func set_telemetry(t: Telemetry) -> void:
	if t == null:
		return
	_rpm = t.cadence_rpm
	_stale = t.cadence_age_s > STALE_S
	_refresh()


## The published cadence band (0, 0 clears it).
func set_cadence_band(lo_rpm: float, hi_rpm: float) -> void:
	if hi_rpm <= 0.0 or hi_rpm < lo_rpm:
		_lo = 0.0
		_hi = 0.0
	else:
		_lo = maxf(0.0, lo_rpm)
		_hi = hi_rpm
	_refresh()


func band() -> Vector2:
	return Vector2(_lo, _hi) if _hi > 0.0 else Vector2.ZERO


func in_band() -> bool:
	return _hi > 0.0 and not _stale and _rpm >= _lo and _rpm <= _hi


func is_stale() -> bool:
	return _stale


func rpm_label() -> Label:
	return _value


func bar() -> HudBar:
	return _bar


func _refresh() -> void:
	if _value == null:
		return
	_value.text = "%d" % roundi(_rpm)
	var glowing := in_band()
	_bar.dim = _stale
	_bar.set_state(_rpm, maxf(130.0, maxf(_hi * 1.2, _rpm * 1.1)), _lo, _hi, -1.0, glowing)
	var c := WlTheme.GLOW if glowing else WlTheme.TEXT
	_value.label_settings.font_color = Color(c, 0.5) if _stale else c
	_band.text = _t("UI_HUD_BAND_RPM", [roundi(_lo), roundi(_hi)]) if _hi > 0.0 else ""
	_band.visible = not _band.text.is_empty()
