class_name FishingHud
extends RefCounted
## hud_spec() for Turbo Reel, in art pixels of the 640 x 360 view (the ocean runs under it all):
##  - top: FishingMinimap (the ocean in profile, every rider's action icon) and FishingBoard
##    (time left, the leaderboard);
##  - bottom left: the kit power gauge and cadence with the local fight meters either side of
##    the cadence, FishingFightPanel beside them, the kit gear above (shown in SIM), and in a
##    workout the kit timeline above that;
##  - FishingChips over the view: the stopped menu as chips next to the boat;
##  - toasts under the minimap, banners over the middle of the view.
## Nothing reaches into the PANIC corner (art x >= 503 and y >= 316).

const POWER := Rect2i(4, 322, 100, 34)
const STRAIN := Rect2i(106, 322, 5, 34)
const CADENCE := Rect2i(113, 322, 115, 34)
const SLACK := Rect2i(230, 322, 5, 34)
const GEAR := Rect2i(4, 305, 98, 15)
const TIMELINE := Rect2i(4, 262, 231, 36)
const TOASTS := Rect2i(120, 38, 296, 22)
const BANNERS := Rect2i(120, 150, 400, 60)
## The kit widgets, toasts and the game banner in the art's sea palette and pixel font: square
## panels, no outlines, sizes on the font's 9 px cell.
const PALETTE := {
	"panel": Color("#1c4d65"),
	"panel_border": Color("#2c6778"),
	"text": Color("#ebf2e7"),
	"text_dim": Color("#b6d7cf"),
	"bar_bg": Color("#2c6778"),
	"bar_fg": Color("#91c2c2"),
	"accent": Color("#c98a5e"),
	"banner_bg": Color("#1c4d65"),
	"banner_text": Color("#ebf2e7"),
	"band": Color("#6fa3a6"),
	"glow": Color("#91c2c2"),
	"glow_text": Color("#ebf2e7"),
	"font_scale_px": 9,
	"text_px": 27,
	"key_px": 54,
	"grid_px": 3,
	"corner_radius": 0,
	"text_outline": false,
}


static func spec(game: FishingGame) -> HudSpec:
	var spec := HudSpec.new()
	(
		spec
		. add_control(FishingMinimap.make(game), FishingMinimap.ART)
		. add_control(FishingBoard.make(game), FishingBoard.ART)
		. add_control(FishingChips.make(game), FishingChips.ART)
		. add(HudSpec.POWER_GAUGE, POWER)
		. add_control(FishingMeter.make(game, FishingMeter.STRAIN), STRAIN)
		. add(HudSpec.CADENCE, CADENCE)
		. add_control(FishingMeter.make(game, FishingMeter.SLACK), SLACK)
		. add_control(FishingFightPanel.make(game), FishingFightPanel.ART)
		. add(HudSpec.GEAR, GEAR)
	)
	if not roam(game):
		spec.add(HudSpec.TIMELINE, TIMELINE)
	spec.toasts_at(TOASTS)
	spec.banners_at(BANNERS)
	var palette := PALETTE.duplicate()
	palette["font"] = FishingHudDraw.font()
	spec.palette = palette
	return spec


## Free Roam (no timeline): the state says so, else the content id does.
static func roam(game: FishingGame) -> bool:
	if game != null and game.state != null:
		return game.state.roam
	return game != null and game.ctx != null and game.ctx.content_id.begins_with("roam")


## Every rect the spec can place (tests check them against PANIC).
static func rects() -> Array[Rect2i]:
	return [
		FishingMinimap.ART,
		FishingBoard.ART,
		FishingChips.ART,
		POWER,
		STRAIN,
		CADENCE,
		SLACK,
		FishingFightPanel.ART,
		GEAR,
		TIMELINE,
		TOASTS,
		BANNERS,
	]
