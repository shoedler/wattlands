class_name HudReadout
extends HudWidget
## Kit widget `readout` (BRIEF 3.9; HudSpec.READOUT): a big number (72 px at 1080p, never
## below 48) with a caption. Options: {"source": "power_w" | "cadence_rpm" | "ftp_pct" |
## "wkg" | "custom" (default "power_w"), "id": String (custom readouts, fed by
## ctx.hud.readout(id, text); local only), "label": String key (the caption; default per
## source)}. W/kg shows "--" unless the rider opted in (weight_kg > 0).
## base_size 240 x 150; min_rect 170 x 108.

const SOURCES: Array[String] = ["power_w", "cadence_rpm", "ftp_pct", "wkg", "custom"]

var source: String = "power_w"
var readout_id: String = ""

var _value: Label = null
var _caption: Label = null


func _init() -> void:
	_ensure_base()
	widget_id = HudSpec.READOUT
	_value = _make_label("Value", WlTheme.BIG_READOUT_PX, WlTheme.TEXT, true)
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value.text = "0"
	_content.add_child(_value)
	_caption = _make_label("Caption", WlTheme.LABEL_PX, WlTheme.TEXT_DIM)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(_caption)
	set_ui_scale(1.0)
	_set_caption()


func configure(p_options: Dictionary) -> void:
	super.configure(p_options)
	var s := str(p_options.get("source", "power_w"))
	if not SOURCES.has(s):
		push_error("HudReadout: unknown source '%s' (use %s)" % [s, ", ".join(SOURCES)])
		s = "power_w"
	source = s
	readout_id = str(p_options.get("id", ""))
	if source == "custom" and readout_id.is_empty():
		push_warning('HudReadout: a custom readout needs an "id"')
	_value.text = "" if source == "custom" else "0"
	_set_caption()


func base_size() -> Vector2:
	return Vector2(240, 150)


func min_rect() -> Vector2:
	return Vector2(170, 108)


func set_telemetry(t: Telemetry) -> void:
	if t == null:
		return
	match source:
		"power_w":
			_value.text = "%d" % roundi(t.power_w)
		"cadence_rpm":
			_value.text = "%d" % roundi(t.cadence_rpm)
		"ftp_pct":
			var pct := t.ftp_pct
			if pct <= 0.0 and t.power_w > 0.0 and ftp_w > 0.0:
				pct = t.power_w / ftp_w * 100.0
			_value.text = "%d%%" % roundi(pct)
		"wkg":
			_value.text = ("%.1f" % (t.power_w / weight_kg)) if weight_kg > 0.0 else "--"


## Custom readouts: the text to show.
func set_text(text: String) -> void:
	_value.text = text


func value_text() -> String:
	return _value.text


func value_label() -> Label:
	return _value


func _set_caption() -> void:
	var key := str(options.get("label", ""))
	if key.is_empty():
		match source:
			"power_w":
				key = "UI_HUD_W"
			"cadence_rpm":
				key = "UI_HUD_RPM"
			"ftp_pct":
				key = "UI_HUD_FTP"
			"wkg":
				key = "UI_HUD_WKG_UNIT"
	_caption.text = _t(key) if not key.is_empty() else ""
	_caption.visible = not _caption.text.is_empty()
