class_name HudPowerGauge
extends HudWidget
## Kit widget `power_gauge` (BRIEF 3.9; HudSpec.POWER_GAUGE): the rider's raw watts as a key
## number, %FTP and (if opted in) W/kg, and a bar with the target band that glows while the
## power is in band. ERG: the band is the applied target +-5%; SIM: the band published with
## ctx.hud.power_band (none until one is set). Options: {"peer": int} (default: the local
## rider). base_size 420 x 136; min_rect 300 x 106.

## Half-width of the ERG band around the applied target (fraction).
const ERG_BAND := 0.05

## The peer whose band this gauge shows (HudLayer sets it to the local rider).
var peer: int = 0

var _power_w: float = 0.0
var _ftp_pct: float = 0.0
var _mode: String = Wl.OFF
var _target_w: float = 0.0
var _pub_lo: float = 0.0
var _pub_hi: float = 0.0

var _watts: Label = null
var _unit: Label = null
var _pct: Label = null
var _wkg: Label = null
var _target: Label = null
var _bar: HudBar = null


func _init() -> void:
	_ensure_base()
	widget_id = HudSpec.POWER_GAUGE
	var top := _hbox("Top", 10)
	_content.add_child(top)
	_watts = _make_label("Watts", WlTheme.KEY_NUMBER_PX, WlTheme.TEXT, true)
	_watts.text = "0"
	top.add_child(_watts)
	_unit = _make_label("Unit", WlTheme.LABEL_PX, WlTheme.TEXT_DIM)
	_unit.text = _t("UI_HUD_W")
	_unit.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	top.add_child(_unit)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 0)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(side)
	_pct = _make_label("FtpPct", WlTheme.BODY_PX)
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	side.add_child(_pct)
	_wkg = _make_label("Wkg", WlTheme.SMALL_PX, WlTheme.TEXT_DIM)
	_wkg.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_wkg.visible = false
	side.add_child(_wkg)
	var low := _hbox("BarRow", 10)
	_content.add_child(low)
	_bar = HudBar.new()
	_bar.name = "Bar"
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	low.add_child(_bar)
	_scale_box(_bar, 0.0, 20.0)
	_target = _make_label("Target", WlTheme.SMALL_PX, WlTheme.TEXT_DIM)
	low.add_child(_target)
	set_ui_scale(1.0)
	_refresh()


func base_size() -> Vector2:
	return Vector2(420, 136)


func min_rect() -> Vector2:
	return Vector2(300, 106)


func set_telemetry(t: Telemetry) -> void:
	if t == null:
		return
	_power_w = t.power_w
	_ftp_pct = t.ftp_pct
	if _ftp_pct <= 0.0 and _power_w > 0.0 and ftp_w > 0.0:
		_ftp_pct = _power_w / ftp_w * 100.0
	_mode = t.mode
	_target_w = float(t.applied_target_w)
	_refresh()


## The SIM band published with ctx.hud.power_band (0, 0 clears it).
func set_power_band(lo_w: float, hi_w: float) -> void:
	if hi_w <= 0.0 or hi_w < lo_w:
		_pub_lo = 0.0
		_pub_hi = 0.0
	else:
		_pub_lo = maxf(0.0, lo_w)
		_pub_hi = hi_w
	_refresh()


## The band shown now as Vector2(lo, hi) in watts; Vector2.ZERO when none.
func band() -> Vector2:
	if _mode == Wl.ERG:
		if _target_w > 0.0:
			return Vector2(_target_w * (1.0 - ERG_BAND), _target_w * (1.0 + ERG_BAND))
		return Vector2.ZERO
	if _mode == Wl.SIM and _pub_hi > 0.0:
		return Vector2(_pub_lo, _pub_hi)
	return Vector2.ZERO


func in_band() -> bool:
	var b := band()
	return b.y > 0.0 and _power_w >= b.x and _power_w <= b.y


func power_w() -> float:
	return _power_w


func watts_label() -> Label:
	return _watts


func pct_label() -> Label:
	return _pct


func wkg_label() -> Label:
	return _wkg


func bar() -> HudBar:
	return _bar


func _refresh() -> void:
	if _watts == null:
		return
	_watts.text = "%d" % roundi(_power_w)
	_pct.text = _t("UI_HUD_PCT_FTP", [roundi(_ftp_pct)])
	_wkg.visible = weight_kg > 0.0
	if weight_kg > 0.0:
		_wkg.text = _t("UI_HUD_WKG", ["%.1f" % (_power_w / weight_kg)])
	var b := band()
	var glowing := in_band()
	var top := maxf(maxf(ftp_w * 1.5, b.y * 1.25), maxf(_power_w * 1.1, 100.0))
	_bar.set_state(_power_w, top, b.x, b.y, _target_w if _mode == Wl.ERG and _target_w > 0.0 else -1.0, glowing)
	_watts.label_settings.font_color = WlTheme.GLOW if glowing else WlTheme.TEXT
	if _mode == Wl.ERG and _target_w > 0.0:
		_target.text = _t("UI_HUD_TARGET", [roundi(_target_w)])
	elif b.y > 0.0:
		_target.text = _t("UI_HUD_BAND_W", [roundi(b.x), roundi(b.y)])
	else:
		_target.text = ""
	_target.visible = not _target.text.is_empty()
