class_name HudGear
extends HudWidget
## Kit widget `gear` (BRIEF 4.5, 3.9; HudSpec.GEAR): the virtual gear (1-24) in one compact
## row: caption, number (48 px at full size) and a 24-step bar. Shown whenever the local
## trainer is in SIM (SIM phases and SIM blocks inside ERG phases), hidden otherwise;
## set_telemetry drives the visibility. The gear is not a key number, so it shrinks with
## its rect. base_size 300 x 80; min_rect 150 x 42.

const GEARS := 24

var _gear: int = 12
var _caption: Label = null
var _value: Label = null
var _bar: HudBar = null


func _init() -> void:
	_ensure_base()
	widget_id = HudSpec.GEAR
	var row := _hbox("Row", 12)
	_content.add_child(row)
	_caption = _make_label("Caption", WlTheme.LABEL_PX, WlTheme.TEXT_DIM)
	_caption.text = _t("UI_HUD_GEAR")
	row.add_child(_caption)
	_value = _make_label("Gear", WlTheme.KEY_NUMBER_MIN_PX, WlTheme.TEXT, false, true)
	row.add_child(_value)
	_bar = HudBar.new()
	_bar.name = "Bar"
	_bar.segments = GEARS
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_bar)
	_scale_box(_bar, 96.0, 14.0)
	set_ui_scale(1.0)
	visible = false
	_refresh()


func base_size() -> Vector2:
	return Vector2(300, 80)


func min_rect() -> Vector2:
	return Vector2(150, 42)


func set_telemetry(t: Telemetry) -> void:
	if t == null:
		return
	visible = t.mode == Wl.SIM
	set_gear(t.gear)


func set_gear(gear: int) -> void:
	_gear = clampi(gear, 1, GEARS)
	_refresh()


func gear() -> int:
	return _gear


func gear_label() -> Label:
	return _value


func _refresh() -> void:
	if _value == null:
		return
	_value.text = "%d" % _gear
	_bar.set_state(float(_gear), float(GEARS))
