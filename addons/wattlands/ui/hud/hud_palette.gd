class_name HudPalette
extends RefCounted
## A game's colors for the neutral chrome of the HUD kit (HudSpec.palette): panels, text and
## bars. A key the game leaves out keeps the kit default, so an empty palette is today's look.
## Safety and warning colors (the rescue, warm-up, pause and trainer banners, WlTheme.WARN,
## the in-band glow) are not palette keys: a game cannot recolor a safety signal.

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
const KEYS: Array[String] = [
	PANEL, PANEL_BORDER, TEXT, TEXT_DIM, BAR_BG, BAR_FG, ACCENT, BANNER_BG, BANNER_TEXT
]

## key -> Color, only the keys the game set.
var colors: Dictionary = {}


## The palette for a HudSpec.palette dictionary: unknown keys and non-Color values are
## dropped with a warning.
static func from_dict(d: Dictionary) -> HudPalette:
	var p := HudPalette.new()
	for k: Variant in d.keys():
		if not KEYS.has(str(k)):
			push_warning("HudPalette: unknown key '%s' (use %s)" % [k, ", ".join(KEYS)])
		elif not d[k] is Color:
			push_warning("HudPalette: key '%s' is not a Color" % k)
		else:
			p.colors[str(k)] = d[k]
	return p


func has_key(key: String) -> bool:
	return colors.has(key)


## The game's color for `key`, else `fallback` (the kit default at that spot).
func pick(key: String, fallback: Color) -> Color:
	return colors.get(key, fallback)


func is_default() -> bool:
	return colors.is_empty()
