class_name HudSpec
extends RefCounted
## Which HUD kit widgets a game shows and where, plus its own Control widgets
## (`GameModule.hud_spec()`, BRIEF 3.6, 3.9). Contract, frozen after W0.
##
## Every entry sits at a named anchor (TOP_LEFT, TOP, TOP_RIGHT, BOTTOM_LEFT, BOTTOM,
## BOTTOM_RIGHT) or, in a 2D game, at a Rect2i in art pixels that the HUD maps through the
## PixelViewport's integer scale and letterbox offset. Several entries at one anchor stack
## in the order added (top anchors stack downward, bottom anchors upward).
## The HUD draws at native resolution above the game view.
##
## [codeblock]
## return HudSpec.new() \
##     .add(HudSpec.TIMELINE, HudSpec.TOP_LEFT) \
##     .add(HudSpec.POWER_GAUGE, HudSpec.BOTTOM_LEFT) \
##     .add(HudSpec.CADENCE, HudSpec.BOTTOM_LEFT) \
##     .add(HudSpec.READOUT, HudSpec.TOP_RIGHT, {"source": "power_w"}) \
##     .add_control(my_card, Rect2i(427, 24, 212, 80)) \
##     .toasts_at(HudSpec.TOP).banners_at(HudSpec.TOP)
## [/codeblock]

# Anchors
const TOP_LEFT := "top_left"
const TOP := "top"
const TOP_RIGHT := "top_right"
const BOTTOM_LEFT := "bottom_left"
const BOTTOM := "bottom"
const BOTTOM_RIGHT := "bottom_right"
const ANCHORS: Array[String] = [TOP_LEFT, TOP, TOP_RIGHT, BOTTOM_LEFT, BOTTOM, BOTTOM_RIGHT]

# Kit widgets (BRIEF 3.9)
## Power gauge with target band (glows in band). ERG: the applied target; SIM: the band set
## with ctx.hud.power_band. Options: {"peer": int (default local rider)}.
const POWER_GAUGE := "power_gauge"
## Cadence with the optional band published by ctx.directives.cadence_band.
const CADENCE := "cadence"
## W' balance (stamina) bar.
const WBAL := "wbal"
## Phase timeline with a preview of the next phase.
const TIMELINE := "timeline"
## Teammate strip: each rider's color and shape chip, raw W, %FTP, compliance/in-band,
## rescue, AFK, connection and the latest teammate_status.
const TEAMMATES := "teammates"
## Big numeric readout (>= 48 px at 1080p). Options: {"source": "power_w" | "cadence_rpm" |
## "ftp_pct" | "wkg" | "custom", "id": String (custom readouts, fed by ctx.hud.readout),
## "label": String key}.
const READOUT := "readout"
## Virtual gear indicator (shown whenever the local trainer is in SIM: SIM phases and SIM
## blocks inside ERG phases).
const GEAR := "gear"
const KIT_WIDGETS: Array[String] = [POWER_GAUGE, CADENCE, WBAL, TIMELINE, TEAMMATES, READOUT, GEAR]

## [{"widget": String, "at": String or Rect2i, "options": Dictionary}]
var widgets: Array[Dictionary] = []
## [{"control": Control, "at": String or Rect2i}]
var controls: Array[Dictionary] = []
## Where toasts and the warm-up/rescue banners appear (anchor or Rect2i).
var toast_area: Variant = TOP
var banner_area: Variant = TOP
## Show the kit's warm-up and pause banners (on by default). The rescue banner (BRIEF 4.6.3)
## and the trainer notice (4.4, another app may hold control) always show: false hides only
## the warm-up and pause banners.
var show_safety_banners: bool = true
## Optional colors for the kit's neutral chrome so the widgets match a game's art (default {}
## = the kit look). Keys (Color values, any may be left out): panel, panel_border, text,
## text_dim, bar_bg, bar_fg, accent, banner_bg, banner_text. Safety and warning colors (rescue,
## warm-up, pause and trainer banners, WlTheme.WARN, the in-band glow) ignore it.
var palette: Dictionary = {}
## The game's help overlay (F1, and once when a rider first plays the game): entries
## {"text": String (string key or text), "at": Vector2 (art px for 2D games, else 0..1 of
## the screen), "arrow_to": Vector2 (optional, same space)}. Empty = no help.
var help: Array[Dictionary] = []


func add(widget: String, at: Variant, options: Dictionary = {}) -> HudSpec:
	widgets.append({"widget": widget, "at": at, "options": options})
	return self


func add_control(control: Control, at: Variant) -> HudSpec:
	controls.append({"control": control, "at": at})
	return self


func toasts_at(at: Variant) -> HudSpec:
	toast_area = at
	return self


func banners_at(at: Variant) -> HudSpec:
	banner_area = at
	return self


func has_widget(widget: String) -> bool:
	for w in widgets:
		if w.get("widget", "") == widget:
			return true
	return false


## True if `at` is a valid anchor name or a Rect2i.
static func is_valid_position(at: Variant) -> bool:
	if at is Rect2i:
		return true
	if at is String or at is StringName:
		return ANCHORS.has(str(at))
	return false
