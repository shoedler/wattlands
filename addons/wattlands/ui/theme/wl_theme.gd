class_name WlTheme
extends RefCounted
## The shared look of the app and the HUD kit (BRIEF 3.9): a dark background, high contrast,
## large type readable from 3 m, and colorblind-safe colors that always come with a shape,
## a pattern or text. Owned by ui-hud.
##
## Games match the kit by using the same Theme resource (THEME_PATH, set it on a Control's
## `theme`) and these size and color constants. Every size is in 1080p pixels (the window's
## base size is 1920 x 1080 with canvas_items stretch).
##
## Font: Atkinson Hyperlegible (SIL OFL) when its files exist at FONT_REGULAR_PATH and
## FONT_BOLD_PATH; otherwise Godot's default font (see docs/decisions/ui-hud.md). Dropping the
## two .ttf files in place switches every kit widget and the Theme over, with no code change.

const THEME_PATH := "res://addons/wattlands/ui/theme/wattlands_theme.tres"
const FONT_REGULAR_PATH := "res://addons/wattlands/ui/theme/fonts/AtkinsonHyperlegible-Regular.ttf"
const FONT_BOLD_PATH := "res://addons/wattlands/ui/theme/fonts/AtkinsonHyperlegible-Bold.ttf"

# --- Sizes (1080p pixels) ---------------------------------------------------------------
## Key numbers (own watts, rpm, big readouts) at full size.
const KEY_NUMBER_PX := 64
## Key numbers never go below this (BRIEF 3.9: >= 48 px at 1080p).
const KEY_NUMBER_MIN_PX := 48
## The big numeric readout widget.
const BIG_READOUT_PX := 72
## Banners (rescue, warm-up, pause, game banners).
const BANNER_PX := 56
## Menu and pedal-scan items.
const MENU_PX := 40
const TOAST_PX := 36
## Body text, teammate watts, secondary numbers.
const BODY_PX := 32
## Small labels (units, captions).
const LABEL_PX := 26
const SMALL_PX := 22
## Smallest any scaled text gets.
const MIN_TEXT_PX := 14
## Dark outline on HUD text so it reads over any game art.
const OUTLINE_PX := 8
const MARGIN_PX := 32
const GAP_PX := 12
const CORNER_PX := 12

# --- Colors -------------------------------------------------------------------------------
const BG := Color("#0E1116")
const PANEL := Color(0.055, 0.067, 0.086, 0.86)
const PANEL_BORDER := Color("#3A4552")
const TEXT := Color("#F4F6F8")
const TEXT_DIM := Color("#A7B1BC")
const OUTLINE := Color(0.0, 0.0, 0.0, 0.85)
## Okabe-Ito sky blue: target bands, highlights, focus.
const ACCENT := Color("#56B4E9")
## The in-band glow.
const GLOW := Color("#BDEBFF")
const BAND := Color(0.337, 0.706, 0.914, 0.38)
const BAND_IN := Color(0.741, 0.922, 1.0, 0.55)
const BAR_BG := Color(1.0, 1.0, 1.0, 0.12)
const BAR_FILL := Color("#F4F6F8")
## Okabe-Ito orange: warnings, rescue.
const WARN := Color("#E69F00")
## Okabe-Ito reddish purple: warm-up.
const WARMUP := Color("#CC79A7")
const PAUSED := Color("#5B6673")
const DISABLED := Color(1.0, 1.0, 1.0, 0.35)

static var _theme: Theme = null
static var _font: Font = null
static var _font_bold: Font = null
static var _font_checked: bool = false


## The shared Theme (dark, high contrast, large type). Loaded once; the Atkinson font is set
## as its default font when present.
static func get_theme() -> Theme:
	if _theme == null:
		var t: Theme = null
		if ResourceLoader.exists(THEME_PATH):
			t = load(THEME_PATH) as Theme
		if t == null:
			push_warning("WlTheme: %s missing, using a plain Theme" % THEME_PATH)
			t = Theme.new()
			t.default_font_size = BODY_PX
		if has_custom_font():
			t.default_font = font()
		_theme = t
	return _theme


## True when the Atkinson Hyperlegible files are in place.
static func has_custom_font() -> bool:
	_load_fonts()
	return _font != null


## The regular UI font: Atkinson Hyperlegible if present, else Godot's default font.
static func font() -> Font:
	_load_fonts()
	return _font if _font != null else ThemeDB.fallback_font


## The bold font for key numbers (falls back to font()).
static func bold_font() -> Font:
	_load_fonts()
	if _font_bold != null:
		return _font_bold
	return font()


## Font size of a key number at `scale` (1.0 = full size); never below KEY_NUMBER_MIN_PX.
static func key_px(scale: float = 1.0) -> int:
	return maxi(KEY_NUMBER_MIN_PX, roundi(KEY_NUMBER_PX * scale))


## `base_px` scaled, never below MIN_TEXT_PX.
static func scaled_px(base_px: int, scale: float) -> int:
	return maxi(MIN_TEXT_PX, roundi(base_px * scale))


## LabelSettings for HUD text: the kit font, a size, a color and a dark outline.
static func label_settings(
	px: int, color: Color = TEXT, bold: bool = false, outline: bool = true
) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = bold_font() if bold else font()
	ls.font_size = px
	ls.font_color = color
	if outline:
		ls.outline_size = maxi(2, roundi(OUTLINE_PX * px / 64.0))
		ls.outline_color = OUTLINE
	return ls


## A rounded dark panel style (HUD cards, toasts, menu rows).
static func panel_style(
	bg: Color = PANEL, border: Color = PANEL_BORDER, border_px: int = 2
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_px)
	sb.set_corner_radius_all(CORNER_PX)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	sb.anti_aliasing = true
	return sb


## A text color that reads on `bg` (black or near-white).
static func text_on(bg: Color) -> Color:
	return Color.BLACK if bg.get_luminance() > 0.45 else TEXT


static func _load_fonts() -> void:
	if _font_checked:
		return
	_font_checked = true
	if ResourceLoader.exists(FONT_REGULAR_PATH):
		_font = load(FONT_REGULAR_PATH) as Font
	if ResourceLoader.exists(FONT_BOLD_PATH):
		_font_bold = load(FONT_BOLD_PATH) as Font
