class_name HudTeammateCard
extends PanelContainer
## One rider in the teammate strip: the slot chip (color + shape + pattern, hollow for slots
## 4-7), name, raw W, %FTP, and one status line: rescue, AFK, offline, or the game's
## teammate_status text, with its icon. In band (teammate_status.in_band) shows a bright
## border and an "in band" text, so it reads without color. Owned by ui-hud.

var peer_id: int = 0
var is_local: bool = false

var _entry: Dictionary = {}
var _chip: SlotChip = null
var _name: Label = null
var _watts: Label = null
var _pct: Label = null
var _status: Label = null
var _icon: TextureRect = null
var _icon_path: String = ""
var _scale: float = 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.name = "Row"
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 10)
	add_child(hb)
	_chip = SlotChip.new()
	_chip.name = "Chip"
	_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(_chip)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 0)
	hb.add_child(vb)
	_name = _label("Name", WlTheme.SMALL_PX, WlTheme.TEXT_DIM)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vb.add_child(_name)
	var nums := HBoxContainer.new()
	nums.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nums.add_theme_constant_override("separation", 8)
	vb.add_child(nums)
	_watts = _label("Watts", WlTheme.BODY_PX, WlTheme.TEXT, true)
	nums.add_child(_watts)
	_pct = _label("FtpPct", WlTheme.SMALL_PX, WlTheme.TEXT_DIM)
	_pct.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	nums.add_child(_pct)
	_status = _label("Status", WlTheme.SMALL_PX, WlTheme.TEXT)
	vb.add_child(_status)
	_icon = TextureRect.new()
	_icon.name = "Icon"
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.visible = false
	hb.add_child(_icon)
	set_card_scale(1.0)


func set_card_scale(s: float) -> void:
	_scale = s
	_chip.custom_minimum_size = Vector2(44, 44) * s
	_icon.custom_minimum_size = Vector2(40, 40) * s
	custom_minimum_size = Vector2(200, 0) * s
	for l: Label in [_name, _watts, _pct, _status]:
		var base: int = l.get_meta("base_px", WlTheme.SMALL_PX)
		l.label_settings.font_size = WlTheme.scaled_px(base, s)
	_style()


## A roster entry: {raw_w, cadence_rpm, ftp_pct, rescue, afk, connected,
## status: {in_band, icon, text}, name, slot_index}.
func set_entry(p_peer: int, entry: Dictionary, p_is_local: bool = false) -> void:
	peer_id = p_peer
	is_local = p_is_local
	_entry = entry.duplicate(true)
	_chip.set_slot(int(entry.get("slot_index", 0)))
	_name.text = str(entry.get("name", ""))
	if is_local:
		_name.text = HudWidget._t("UI_HUD_YOU_NAME", [_name.text])
	_watts.text = HudWidget._t("UI_HUD_WATTS", [roundi(float(entry.get("raw_w", 0.0)))])
	_pct.text = HudWidget._t("UI_HUD_PCT", [roundi(float(entry.get("ftp_pct", 0.0)))])
	_status.text = status_text()
	var st: Variant = entry.get("status", {})
	var icon_path := str((st as Dictionary).get("icon", "")) if st is Dictionary else ""
	if icon_path != _icon_path:
		_icon_path = icon_path
		_icon.texture = null
		if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
			_icon.texture = load(icon_path) as Texture2D
	_icon.visible = _icon.texture != null
	modulate.a = 0.55 if not is_connected_rider() or is_afk() else 1.0
	_style()


func entry() -> Dictionary:
	return _entry


func is_connected_rider() -> bool:
	return bool(_entry.get("connected", true))


func is_afk() -> bool:
	return bool(_entry.get("afk", false))


func is_rescue() -> bool:
	return bool(_entry.get("rescue", false))


func in_band() -> bool:
	var st: Variant = _entry.get("status", {})
	return st is Dictionary and bool((st as Dictionary).get("in_band", false))


## The status line: offline > AFK > rescue > the game's text > in band.
func status_text() -> String:
	if not is_connected_rider():
		return HudWidget._t("UI_HUD_OFFLINE")
	if is_afk():
		return HudWidget._t("UI_HUD_AFK")
	if is_rescue():
		return HudWidget._t("UI_HUD_RESCUE")
	var st: Variant = _entry.get("status", {})
	if st is Dictionary:
		var text := str((st as Dictionary).get("text", ""))
		if not text.is_empty():
			return HudWidget._t(text)
	if in_band():
		return HudWidget._t("UI_HUD_IN_BAND")
	return ""


func chip() -> SlotChip:
	return _chip


func watts_label() -> Label:
	return _watts


func icon() -> TextureRect:
	return _icon


func _label(label_name: String, px: int, color: Color, bold: bool = false) -> Label:
	var l := Label.new()
	l.name = label_name
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.label_settings = WlTheme.label_settings(px, color, bold)
	l.set_meta("base_px", px)
	return l


func _style() -> void:
	var border := WlTheme.PANEL_BORDER
	var width := 2
	if in_band():
		border = WlTheme.GLOW
		width = 5
	if is_rescue():
		border = WlTheme.WARN
		width = 5
	if is_local:
		width = maxi(width, 3)
	var sb := WlTheme.panel_style(
		Color(0.055, 0.067, 0.086, 0.8), border, roundi(width * maxf(_scale, 0.5))
	)
	sb.content_margin_left = 10.0 * _scale
	sb.content_margin_right = 10.0 * _scale
	sb.content_margin_top = 6.0 * _scale
	sb.content_margin_bottom = 6.0 * _scale
	add_theme_stylebox_override("panel", sb)
	_status.label_settings.font_color = (
		WlTheme.WARN if is_rescue() else (WlTheme.GLOW if in_band() else WlTheme.TEXT)
	)
