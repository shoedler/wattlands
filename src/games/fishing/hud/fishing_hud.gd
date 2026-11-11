class_name FishingHud
extends RefCounted
## hud_spec() for Turbo Reel, in art pixels of the current art size (layout(): every rect from
## the view's art size, 640 x 360 at the base; the ocean runs under it all):
##  - top: FishingMinimap (the ocean in profile, every rider's action icon; as wide as the board
##    leaves) and FishingBoard (time left, the leaderboard) at the right, with FishingCrewStrips
##    stacked under the board: one strip per other rider with a fish on;
##  - bottom left: FishingCruisePanel (watts, cadence, %FTP, heart rate, a power graph, the zone
##    tag bottom-aligned right of it) outside a fight, the kit gear (shown in SIM) right above
##    the tag, and in a workout the kit timeline above them;
##  - FishingFightPanel under the boat in a fight and the Landing, FishingJigPanel in its place
##    while the lure is out in Free Roam; FishingSpeedTag on the water
##    behind the stern; FishingChips over the view (the stopped menu next to the boat);
##  - toasts under the minimap, banners over the middle of the view;
##  - help (F1): what each of these is, with arrows (help()).
## The game's own controls show raw W and %FTP (shows_power), so no kit power gauge is added.
## Nothing reaches into the PANIC corner (the bottom-right PANIC_W x PANIC_H art px).

const PANIC_W := 137
const PANIC_H := 44
const MINIMAP_H := 30
const BOARD_W := 212
const BOARD_H := 42
const CRUISE_W := 300
const CRUISE_H := 52
const GEAR_W := 98
const GEAR_H := 15
const TIMELINE_W := 235
const TIMELINE_H := 36
const TOAST_W := 296
const TOAST_H := 22
const BANNER_W := 400
const BANNER_H := 60
const MARGIN := 4
## The jig panel's rect is the view less this many rows, so it differs from the fight panel's.
const JIG_RECT_TRIM := 4
## The help overlay's entries: [string key, layout rect it points at, text offset from it].
const HELP: Array = [
	["FISHING_HELP_MINIMAP", "minimap", Vector2(40, 46)],
	["FISHING_HELP_BOARD", "board", Vector2(-150, 60)],
	["FISHING_HELP_POWER", "cruise", Vector2(40, -64)],
	["FISHING_HELP_SPEED", "speed", Vector2(60, 46)],
	["FISHING_HELP_MENU", "menu", Vector2(80, -30)],
	["FISHING_HELP_FIGHT", "fight", Vector2(150, 30)],
	["FISHING_HELP_GEAR", "gear", Vector2(60, -40)],
	["FISHING_HELP_STOP", "stop", Vector2(-260, -30)],
]
## The kit widgets, toasts and the game banner in the art's sea palette and pixel font, on the
## art's pixel grid: square deep-teal panels in a one-pixel surface-teal frame (lighter than the
## boats), mid-teal bar tracks, sizes on the font's 9 px cell.
const PALETTE := {
	"panel": Color("#2c6778"),
	"panel_border": Color("#91c2c2"),
	"text": Color("#ebf2e7"),
	"text_dim": Color("#b6d7cf"),
	"bar_bg": Color("#4b858f"),
	"bar_fg": Color("#91c2c2"),
	"accent": Color("#c98a5e"),
	"banner_bg": Color("#2c6778"),
	"banner_text": Color("#ebf2e7"),
	"band": Color("#6fa3a6"),
	"glow": Color("#ebf2e7"),
	"glow_text": Color("#ebf2e7"),
	"strip_low": Color("#4b858f"),
	"strip_mid": Color("#6fa3a6"),
	"strip_high": Color("#91c2c2"),
	"font_scale_px": 9,
	"text_px": 27,
	"key_px": 54,
	"grid_px": 3,
	"corner_radius": 0,
	"text_outline": false,
}


static func spec(game: FishingGame) -> HudSpec:
	var art := art_size(game)
	var l := layout(art)
	var spec := HudSpec.new()
	(
		spec
		. add_control(FishingMinimap.make(game, l["minimap"]), l["minimap"])
		. add_control(FishingBoard.make(game, l["board"]), l["board"])
		. add_control(FishingCrewStrips.make(game, l["crew"]), l["crew"])
		. add_control(FishingChips.make(game, l["chips"]), l["chips"])
		. add_control(FishingSpeedTag.make(game, l["speed"]), l["speed"])
		. add_control(FishingFightPanel.make(game, l["fight"]), l["fight"])
		. add_control(FishingJigPanel.make(game, l["jig"]), l["jig"])
		. add_control(FishingCruisePanel.make(game, l["cruise"]), l["cruise"])
		. add(HudSpec.GEAR, l["gear"])
	)
	if not roam(game):
		spec.add(HudSpec.TIMELINE, l["timeline"])
	spec.toasts_at(l["toasts"])
	spec.banners_at(l["banners"])
	spec.shows_power = true
	spec.help = help(art)
	var palette := PALETTE.duplicate()
	palette["font"] = FishingHudDraw.font()
	spec.palette = palette
	return spec


## The art size the view draws (its SubViewport's size once it is in one), else the base size.
static func art_size(game: FishingGame) -> Vector2i:
	if game != null and game.has_meta(FishingView.META):
		var v: Variant = game.get_meta(FishingView.META)
		if v is FishingView and (v as FishingView).is_inside_tree():
			var vp := (v as FishingView).get_viewport()
			if vp is SubViewport:
				return (vp as SubViewport).size
	return Vector2i(FishingConst.PIXEL_W, FishingConst.PIXEL_H)


## Every rect for art size `art` (art px), by name: minimap, board, crew, chips, speed, fight, jig,
## cruise, gear, timeline, toasts, banners; and the help overlay's targets menu and stop.
static func layout(art: Vector2i) -> Dictionary:
	var w := maxi(art.x, 1)
	var h := maxi(art.y, 1)
	var board := Rect2i(w - BOARD_W - MARGIN, 2, BOARD_W, BOARD_H)
	var minimap := Rect2i(MARGIN, 2, board.position.x - 2 * MARGIN - MARGIN, MINIMAP_H)
	var cruise := Rect2i(MARGIN, h - CRUISE_H - MARGIN, CRUISE_W, CRUISE_H)
	var gear_y := cruise.end.y - FishingCruisePanel.TAG_H - 2 - GEAR_H
	var gear := Rect2i(MARGIN + FishingCruisePanel.tag_x(), gear_y, GEAR_W, GEAR_H)
	var crew_h := FishingCrewStrips.rect_h(FishingSnapshotSchema.MAX_RIDERS)
	var tw := mini(TOAST_W, minimap.size.x - 16)
	var bw := mini(BANNER_W, w - 2 * MARGIN)
	return {
		"minimap": minimap,
		"board": board,
		"crew": Rect2i(board.position.x, board.position.y, BOARD_W, crew_h),
		"chips": Rect2i(0, 0, w, h - 60),
		"speed": Rect2i(0, FishingScenery.SURF_Y + FishingScenery.SURFACE_ROWS, w, 30),
		"fight": Rect2i(0, 0, w, h),
		# not the fight panel's rect: the HudLayer stacks controls of one rect and halves their heights
		"jig": Rect2i(0, 0, w, h - JIG_RECT_TRIM),
		"cruise": cruise,
		"gear": gear,
		"timeline": Rect2i(MARGIN, cruise.position.y - TIMELINE_H - 4, TIMELINE_W, TIMELINE_H),
		"toasts": Rect2i(minimap.position.x + (minimap.size.x - tw) / 2, 38, tw, TOAST_H),
		"banners": Rect2i((w - bw) / 2, 150, bw, BANNER_H),
		"menu": Rect2i(w / 3 - 20, FishingScenery.SURF_Y - 40, 40, 30),
		"stop": Rect2i(w - PANIC_W, h - PANIC_H, PANIC_W, PANIC_H),
	}


## The help overlay for art size `art`: each entry's text (a string key) at its target's
## offset, an arrow to the target's nearest edge point.
static func help(art: Vector2i) -> Array[Dictionary]:
	var l := layout(art)
	var out: Array[Dictionary] = []
	for e: Array in HELP:
		var r: Rect2i = l[str(e[1])]
		if str(e[1]) == "fight":
			r = Rect2i(art.x / 2 - 64, FishingScenery.SURF_Y + 12, 128, 90)
		var c := Vector2(r.get_center())
		var off: Vector2 = e[2]
		var at := (c + off).clamp(Vector2(8, 8), Vector2(art) - Vector2(8, 8))
		var to := c.clamp(Vector2(r.position) + Vector2(2, 2), Vector2(r.end) - Vector2(2, 2))
		if str(e[1]) == "speed":
			to = Vector2(art.x / 3 - 46, r.position.y + 8)
		out.append({"text": str(e[0]), "at": at, "arrow_to": to})
	return out


## Free Roam (no timeline): the state says so, else the content id does.
static func roam(game: FishingGame) -> bool:
	if game != null and game.state != null:
		return game.state.roam
	return game != null and game.ctx != null and game.ctx.content_id.begins_with("roam")


## Every rect the spec can place for art size `art` (tests check them against PANIC).
static func rects(art: Vector2i = Vector2i(FishingScenery.W, FishingScenery.H)) -> Array[Rect2i]:
	var l := layout(art)
	var out: Array[Rect2i] = []
	for key: String in [
		"minimap",
		"board",
		"crew",
		"chips",
		"speed",
		"cruise",
		"gear",
		"timeline",
		"toasts",
		"banners",
	]:
		out.append(l[key])
	return out
