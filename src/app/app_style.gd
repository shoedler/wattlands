class_name AppStyle
extends RefCounted
## Sizes, colours and small Control builders for the app shell (BRIEF 3.9). The window's base
## size is 1920 x 1080 with canvas_items stretch, so every size here is in 1080p pixels.
## Readable from 3 m: key numbers (room code, grade, FTP, watts) are at least 48 px.
## The shared kit Theme (ui-hud) is used when it exists; otherwise a fallback Theme with the
## same body size is built here.

const FONT_SMALL := 28
const FONT_BODY := 34
const FONT_HEADING := 56
## Key numbers (FTP, watts, timers, XP): never below 48 px (BRIEF 3.5, 3.9).
const FONT_NUMBER := 64
## The room code as K7Q-X2M.
const FONT_CODE := 112
const FONT_TITLE := 120
const FONT_GRADE := 200
const KEY_NUMBER_MIN := 48

const BG := Color("#14161c")
const PANEL := Color("#1f232c")
const PANEL_HI := Color("#2c3340")
const TEXT := Color("#f2f2f2")
const TEXT_DIM := Color("#a9b0bd")
const ACCENT := Color("#f0a030")
const GOOD := Color("#3fbf7f")
const WARN := Color("#ffcc4d")
const BAD := Color("#ff6b5e")
const MARGIN := 48

## Where ui-hud may ship the shared Theme (BRIEF 6: addons/wattlands/ui/theme/).
const THEME_CANDIDATES: Array[String] = [
	"res://addons/wattlands/ui/theme/wattlands_theme.tres",
	"res://addons/wattlands/ui/theme/theme.tres",
]

static var _theme: Theme = null


## The app Theme: the kit's shared Theme if present, else a fallback with FONT_BODY text.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	for path: String in THEME_CANDIDATES:
		if ResourceLoader.exists(path):
			var res: Resource = load(path)
			if res is Theme:
				_theme = res as Theme
				return _theme
	var t := Theme.new()
	t.default_font_size = FONT_BODY
	_theme = t
	return _theme


static func label(text: String, size: int = FONT_BODY, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


## Pounds per kilogram (imperial weight display; the profile always stores kg).
const LB_PER_KG := 2.20462262
## The weight field's range in kg (Settings accepts 20-300; the fields offer 30-200).
const WEIGHT_MIN_KG := 30.0
const WEIGHT_MAX_KG := 200.0


## A weight in the rider's units: "70 kg" (metric) or "154 lb" (imperial).
static func weight_text(kg: float, units: String) -> String:
	if units == "imperial":
		return "%d lb" % roundi(kg * LB_PER_KG)
	return "%d kg" % roundi(kg)


## A wrapping paragraph label.
static func paragraph(text: String, size: int = FONT_BODY, color: Color = TEXT_DIM) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(200, 0)
	return l


## The font size a Label was given with label() (theme default otherwise).
static func font_size_of(l: Label) -> int:
	if l.has_theme_font_size_override("font_size"):
		return l.get_theme_font_size("font_size")
	return theme().default_font_size


static func panel(color: Color = PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	p.add_theme_stylebox_override("panel", sb)
	return p


static func vbox(separation: int = 16) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	return b


static func hbox(separation: int = 24) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	return b


## A full-rect background ColorRect.
static func background(color: Color = BG) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Seconds as m:ss (or h:mm:ss).
static func duration_text(seconds: float) -> String:
	var s := maxi(int(round(seconds)), 0)
	var h := s / 3600
	var m := (s % 3600) / 60
	var sec := s % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, sec]
	return "%d:%02d" % [m, sec]


## A stable, readable card colour for a game id (generated title cards).
static func color_for_id(id: String) -> Color:
	var h := id.hash()
	var hue := float(absi(h) % 360) / 360.0
	return Color.from_hsv(hue, 0.55, 0.55)
