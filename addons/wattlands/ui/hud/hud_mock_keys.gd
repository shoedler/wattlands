class_name HudMockKeys
extends Label
## The mock-trainer keyboard readout (a test aid): one small line in the bottom-right corner of
## the session HUD, "MOCK 270 W 92 rpm [keys]", shown only while the TrainerService's device is a
## MockTrainer with keyboard control on. The platform draws it, no game; it uses the game's
## HUD palette (dim text) when one is set. HudLayer adds it to its root and calls refresh() every
## frame and layout() on every relayout. Owned by platform. Sizes are 1080p pixels.

const TEXT_PX := 20
## Distance from the screen's right and bottom edges, inside the HUD's own margin.
const EDGE_PX := 8.0

## The mock to read; null looks up the TrainerService autoload's device (tests set it).
var source: MockTrainer = null

var _palette: HudPalette = HudPalette.new()
var _settings: LabelSettings = null
var _shown_text: String = ""
var _screen: Vector2 = Vector2(1920, 1080)


func _init() -> void:
	name = "MockKeys"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	visible = false
	_apply_style()


func set_palette(palette: HudPalette) -> void:
	_palette = palette if palette != null else HudPalette.new()
	_apply_style()


## The text for a rider at `power_w` and `cadence_rpm`.
static func readout_text(power_w: float, cadence_rpm: float) -> String:
	return HudWidget._t("UI_MOCK_KEYS", [roundi(power_w), roundi(cadence_rpm)])


## The mock whose keyboard control is on, else null.
func active_mock() -> MockTrainer:
	var m := source
	if m == null:
		var svc := AutoloadLookup.trainer_service()
		if svc != null:
			m = svc.device() as MockTrainer
	if m == null or not is_instance_valid(m) or not m.is_keyboard_enabled():
		return null
	return m


## Show or hide the line and update its text from the mock's live power and cadence.
func refresh() -> void:
	var m := active_mock()
	visible = m != null
	if m == null:
		return
	var t := readout_text(m.instantaneous_power_w(), m.instantaneous_cadence_rpm())
	if t != _shown_text:
		_shown_text = t
		text = t
		layout(_screen)


## Place the line at the bottom-right corner of a screen of `screen` size.
func layout(screen: Vector2) -> void:
	_screen = screen
	reset_size()
	position = screen - size - Vector2(EDGE_PX, EDGE_PX)


func _apply_style() -> void:
	var ls := LabelSettings.new()
	ls.font_color = _palette.pick(HudPalette.TEXT_DIM, WlTheme.TEXT_DIM)
	_palette.style_label(ls, TEXT_PX)
	_settings = ls
	label_settings = ls
