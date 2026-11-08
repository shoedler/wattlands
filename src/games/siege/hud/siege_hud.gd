class_name SiegeHud
extends RefCounted
## hud_spec() for Castellum Rotae (docs/games/siege.md 3 "HUD"; GAME_SDK 10): the game's own Roman
## HUD, no kit widgets, only Siege's Controls (SiegeHudCtl) at Rect2i placements in art px of the
## 960 x 540 base (the HudLayer anchors them on the flex canvas, pixel_flex min 852 x 480; no two
## overlap down to that), drawn on the art grid in the mock's materials and letter (SiegeHudDraw,
## SiegeHudType; the approved mock is src/games/siege/art/hud_mock.mjs):
##  - top left: the session plate (SiegeHudSession: title, ENDS IN, profile strip, enemies, news);
##  - top centre: the teammate cards (SiegeHudCrew), the platform's banners under them and the
##    toasts under those, above the wheels;
##  - right column: the gate and tar, the gold, the stations, Overdrive (SiegeHudColumn);
##  - bottom centre: the cockpit (SiegeHudCockpit: clock, watts, cadence, heart rate, one
##    instruction, what comes next), over the wadi;
##  - bottom left, in breaks: the shop (SiegeShopPanel), over the road's west loop, empty then, and
##    above it the shared receipt (SiegeReceiptPanel) with the votes;
##  - pinned to the world, under the plates: the tags on rams and towers and the gate's banner
##    (SiegeHudWorld).
## The centre, the road in waves, the bridge and the plaza stay clear. The cockpit shows raw W and
## %FTP, so the spec sets shows_power. Platform banners keep the kit's colours and font; toasts, the
## game banner and the help take the palette.

const BASE := Vector2i(960, 540)
## The platform's banners, under the crew: as wide as stays clear of the session plate and the right
## column on the narrowest flex canvas. A panel shrinks to its text and a long one wraps.
const BANNER_RECT := Rect2i(464, 69, 286, 27)
const TOAST_RECT := Rect2i(464, 100, 286, 40)
## The palette for the platform's toasts, game banner and help, from the mock.
const PALETTE := {
	"panel": SiegeHudDraw.WAX,
	"panel_border": SiegeHudDraw.STONE,
	"text": SiegeHudDraw.TEXT,
	"text_dim": SiegeHudDraw.DIM,
	"bar_bg": SiegeHudDraw.TRACK,
	"bar_fg": SiegeHudDraw.BRONZE,
	"accent": SiegeHudDraw.BRONZE_HI,
	"banner_bg": SiegeHudDraw.WAX,
	"banner_text": SiegeHudDraw.TEXT,
	"band": SiegeHudDraw.VERD,
	"glow": SiegeHudDraw.GOLD,
	"glow_text": SiegeHudDraw.TEXT,
	"font_scale_px": SiegeHudType.KIT_FONT_PX,
	"text_px": SiegeHudType.KIT_FONT_PX * 2,
	"key_px": SiegeHudType.KIT_FONT_PX * 4,
	"grid_px": 2,
	"corner_radius": 0,
	"text_outline": false,
}
## Where the help panels point at the HUD's own cards (art pixels).
const ROUTE_CARD_AT := Vector2(804, 150)
const SHOP_AT := Vector2(178, 458)
const RECEIPT_AT := Vector2(190, 312)
## Where the help panels sit (art pixels), clear of each other, the title and most plates.
const HELP_AT := {
	"SIEGE_HELP_WHEEL": Vector2(660, 112),
	"SIEGE_HELP_PATH": Vector2(330, 442),
	"SIEGE_HELP_STATIONS": Vector2(330, 468),
	"SIEGE_HELP_ROAD": Vector2(160, 326),
	"SIEGE_HELP_GATE": Vector2(470, 362),
	"SIEGE_HELP_ROUTE_CARD": Vector2(651, 158),
	"SIEGE_HELP_SHOP": Vector2(178, 368),
	"SIEGE_HELP_RECEIPT": Vector2(30, 120),
}


static func spec(game: SiegeGame) -> HudSpec:
	var hs := HudSpec.new()
	_add(hs, SiegeHudSession.new(), game, SiegeHudSession.RECT)
	_add(hs, SiegeHudCrew.new(), game, SiegeHudCrew.RECT)
	_add(hs, SiegeHudColumn.new(), game, SiegeHudColumn.RECT)
	_add(hs, SiegeHudCockpit.new(), game, SiegeHudCockpit.RECT)
	_add(hs, SiegeShopPanel.new(), game, SiegeShopPanel.RECT)
	_add(hs, SiegeReceiptPanel.new(), game, SiegeReceiptPanel.RECT)
	# the world's tags last and under the plates (its z_index): the plates come first so a help
	# point on one follows that plate, and every other point follows the world
	_add(hs, SiegeHudWorld.new(), game, SiegeHudWorld.RECT)
	hs.toasts_at(TOAST_RECT)
	hs.banners_at(BANNER_RECT)
	hs.shows_power = true
	hs.help = help(game)
	var pal := PALETTE.duplicate()
	var font := SiegeHudType.kit_font()
	if font != null:
		pal["font"] = font
	hs.palette = pal
	return hs


static func _add(hs: HudSpec, c: SiegeHudCtl, game: SiegeGame, r: Rect2i) -> void:
	hs.add_control(c.setup(game, r), r)


## The plates, for telling a help point on one from a point on the world (SiegeHudWorld).
static func plate_rects() -> Array[Rect2i]:
	return [
		SiegeHudSession.RECT,
		SiegeHudCrew.RECT,
		SiegeHudColumn.RECT,
		SiegeHudCockpit.RECT,
		SiegeShopPanel.RECT,
		SiegeReceiptPanel.RECT,
	]


## The help overlay (art pixels on 960 x 540): your wheel, your powered path, the stations, the
## road, the gate and its curtain, the stations card, the shop and the receipt.
static func help(game: SiegeGame) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var path: SiegePath = null
	if game != null and game.state != null:
		path = game.state.path
	if path == null:
		return out
	var slot := 0
	var target := SiegeIds.STATION_MINE
	var me := SiegeHudModel.own_rider(game)
	if me != null:
		slot = clampi(me.slot, 0, 3)
		target = me.target
	var wheel := path.to_art(path.wheels[slot])
	var lane := path.to_art(route_point(slot, target))
	var onager := path.to_art(path.station_pos[SiegeIds.STATION_ONAGER])
	var road := path.to_art(path.point_at(path.length_m * 0.4))
	var gate := path.to_art(path.gate_pos + Vector3(0, 2, 3))
	out.append(entry("SIEGE_HELP_WHEEL", wheel))
	out.append(entry("SIEGE_HELP_PATH", lane))
	out.append(entry("SIEGE_HELP_STATIONS", onager))
	out.append(entry("SIEGE_HELP_ROAD", road))
	out.append(entry("SIEGE_HELP_GATE", gate))
	out.append(entry("SIEGE_HELP_ROUTE_CARD", ROUTE_CARD_AT))
	out.append(entry("SIEGE_HELP_SHOP", SHOP_AT))
	out.append(entry("SIEGE_HELP_RECEIPT", RECEIPT_AT))
	return out


static func entry(key: String, arrow_to: Vector2) -> Dictionary:
	return {"text": key, "at": HELP_AT[key], "arrow_to": arrow_to}


## The clutch drum where slot `slot`'s lane meets station `target`'s column (the lit path's
## heart), in world metres (src/games/siege/art/scene.mjs LANE_Y and GEAR_X).
static func route_point(slot: int, target: int) -> Vector3:
	var lane_y: Array[float] = [18.8, 21.4, 24.0, 26.6]
	var gear_x: Array[float] = [60.0, 17.0, 36.0, 47.0, 52.0]
	return Vector3(gear_x[clampi(target, 0, 4)], lane_y[clampi(slot, 0, 3)], 3.0)
