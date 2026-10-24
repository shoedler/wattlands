class_name HudPalette
extends RefCounted
## A game's look for the neutral chrome of the HUD kit (HudSpec.palette): panels, text, bars
## and, optionally, the type and the panel corners. A key the game leaves out keeps the kit
## default, so an empty palette is today's look.
## Colour keys: panel, panel_border, text, text_dim, bar_bg, bar_fg, accent, banner_bg,
## banner_text, band (the target band's fill), glow (the in-band bar outline), glow_text (key
## numbers while in band). Style keys: font (a Font for every kit label, the toasts and the game
## banner), font_scale_px (int > 0: label sizes snap to its nearest multiple, for a pixel font;
## key numbers never below WlTheme.KEY_NUMBER_MIN_PX),
## corner_radius (int >= 0: panel corners; 0 = square, without anti-aliasing) and text_outline
## (bool: false drops the label outlines).
## Safety and warning colors (the rescue, warm-up, pause and trainer banners, WlTheme.WARN) are
## not palette keys: a game cannot recolor a safety signal, and the safety banners keep the kit
## font too.

const PANEL := "panel"
const PANEL_BORDER := "panel_border"
const TEXT := "text"
const TEXT_DIM := "text_dim"
const BAR_BG := "bar_bg"
const BAR_FG := "bar_fg"
const ACCENT := "accent"
## Background of the game banners (ctx.hud.banner) and of toasts.
const BANNER_BG := "banner_bg"
const BANNER_TEXT := "banner_text"
const BAND := "band"
const GLOW := "glow"
const GLOW_TEXT := "glow_text"
const KEYS: Array[String] = [
	PANEL,
	PANEL_BORDER,
	TEXT,
	TEXT_DIM,
	BAR_BG,
	BAR_FG,
	ACCENT,
	BANNER_BG,
	BANNER_TEXT,
	BAND,
	GLOW,
	GLOW_TEXT,
]
const FONT := "font"
const FONT_SCALE_PX := "font_scale_px"
const CORNER_RADIUS := "corner_radius"
const TEXT_OUTLINE := "text_outline"
const STYLE_KEYS: Array[String] = [FONT, FONT_SCALE_PX, CORNER_RADIUS, TEXT_OUTLINE]

## key -> Color, only the colour keys the game set.
var colors: Dictionary = {}
## key -> value, only the style keys the game set.
var style: Dictionary = {}


## The palette for a HudSpec.palette dictionary: unknown keys and values of the wrong type are
## dropped with a warning.
static func from_dict(d: Dictionary) -> HudPalette:
	var p := HudPalette.new()
	for k: Variant in d.keys():
		var key := str(k)
		var v: Variant = d[k]
		if KEYS.has(key):
			if v is Color:
				p.colors[key] = v
			else:
				push_warning("HudPalette: key '%s' is not a Color" % key)
		elif key == FONT:
			if v is Font:
				p.style[key] = v
			else:
				push_warning("HudPalette: key 'font' is not a Font")
		elif key == FONT_SCALE_PX or key == CORNER_RADIUS:
			if v is int and int(v) >= (1 if key == FONT_SCALE_PX else 0):
				p.style[key] = v
			else:
				push_warning("HudPalette: key '%s' needs a whole number" % key)
		elif key == TEXT_OUTLINE:
			if v is bool:
				p.style[key] = v
			else:
				push_warning("HudPalette: key 'text_outline' is not a bool")
		else:
			var all := KEYS + STYLE_KEYS
			push_warning("HudPalette: unknown key '%s' (use %s)" % [key, ", ".join(all)])
	return p


func has_key(key: String) -> bool:
	return colors.has(key) or style.has(key)


## The game's color for `key`, else `fallback` (the kit default at that spot).
func pick(key: String, fallback: Color) -> Color:
	return colors.get(key, fallback)


func is_default() -> bool:
	return colors.is_empty() and style.is_empty()


## The game's font, else `fallback`.
func font_or(fallback: Font) -> Font:
	return style.get(FONT, fallback)


## `px` snapped to the nearest multiple of font_scale_px (at least one, and at least `min_px`),
## or `px` without it.
func snap_px(px: int, min_px: int = 0) -> int:
	var unit := int(style.get(FONT_SCALE_PX, 0))
	if unit <= 0:
		return px
	var v := maxi(unit, roundi(float(px) / float(unit)) * unit)
	while v < min_px:
		v += unit
	return v


## False when the game turned the label outlines off.
func text_outline() -> bool:
	return bool(style.get(TEXT_OUTLINE, true))


## Style a label the kit made at `px` (font, snapped size never under `min_px`, outline); `bold`
## picks the kit's bold font when the game sets none.
func style_label(ls: LabelSettings, px: int, bold: bool = false, min_px: int = 0) -> void:
	if ls == null:
		return
	ls.font = font_or(WlTheme.bold_font() if bold else WlTheme.font())
	ls.font_size = snap_px(px, min_px)
	if text_outline():
		ls.outline_size = maxi(2, roundi(WlTheme.OUTLINE_PX * ls.font_size / 64.0))
		ls.outline_color = WlTheme.OUTLINE
	else:
		ls.outline_size = 0


## A game font is drawn with nearest filtering on `item` and its children (a pixel font stays
## crisp at its whole multiples); nothing changes without one.
func style_item(item: CanvasItem) -> void:
	if item != null and style.has(FONT):
		item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Apply the game's corners to a panel style (nothing without corner_radius).
func style_panel(sb: StyleBoxFlat) -> void:
	if sb == null or not style.has(CORNER_RADIUS):
		return
	var r := int(style[CORNER_RADIUS])
	sb.set_corner_radius_all(r)
	sb.anti_aliasing = r > 0
