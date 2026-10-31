class_name TankHud
extends RefCounted
## hud_spec() for Torque Company (brief 3.6; GAME_SDK 10): the game's own HUD, the way Turbo
## Reel does it. No kit widgets: only Tank Controls (TankHudCtl) at Rect2i placements in art px of
## the 960 x 540 base, which the HUD anchors on the flexible canvas (pixel_flex, min 852 x 480:
## rects in the left / top half stay, rects in the right / bottom half follow that edge, rects
## across the middle stay centred), drawn on the art grid in the brief's palette and the game's own
## pixel type (TankHudFont, TankHudDraw):
##  - top left: the mission plate (TankHudMission: stage, clock, stage strip, objective), the
##    toasts under it;
##  - top right: the hull plate (TankHudHull: HP bar and number, kills), the Behemoth's bars
##    under it (TankHudBoss, only while it is up);
##  - bottom left: my numbers (TankHudMine: watts, %FTP, cadence, their gauges, the instruction
##    line, W' and the gear, the station);
##  - bottom middle: the seat panel (TankHudSeats, v3 seat panel A: one live machine window per
##    seat, Drive, Gun, Loader, Lights, Secondaries and Repairs, manned or empty; your trainer's
##    switch to come and the seat keys' hint over your card);
##  - TANK LOST over the sky, above the banners (TankHudLost, only around a tow);
##  - the world tags (TankHudTags: speed, the halt-line post, SURGE TO EVADE, the gun's elevation
##    arc, the turn marker) over the middle of the canvas;
##  - banners over the sky in the middle, themed by PALETTE; help (F1): eight entries, nine in roam.
## Free roam (brief 2.10, 3.6) has the map strip (TankHudRoamStrip) across the top in place of the
## mission plate, the board (TankHudBoard: time left, points, kills) top right with the hull plate
## under it without its kills, the toasts under the strip, and its own help (ROAM_HELP); each feeds
## its setters from the state in refresh().
## Nothing reaches into the bottom-right 200 x 60 (CLEAR) or, apart from the world tags, the
## tank's band (y 150-360), on any canvas from 852 x 480 up.

const BASE := Vector2i(960, 540)
const FLEX_MIN := Vector2i(852, 480)
## The layout (art px of the 960 x 540 base).
const LAYOUT := {
	"mission": Rect2i(6, 6, 200, 72),
	"toasts": Rect2i(6, 84, 300, 24),
	"hull": Rect2i(818, 6, 136, 48),
	"boss": Rect2i(704, 58, 250, 40),
	"banners": Rect2i(280, 112, 400, 36),
	"lost": Rect2i(360, 72, 240, 36),
	"mine": Rect2i(6, 440, 222, 94),
	"seats": Rect2i(288, 444, 416, 90),
	"tags": Rect2i(54, 30, 852, 480),
	"roam_strip": Rect2i(60, 6, 630, 44),
	"roam_board": Rect2i(754, 6, 200, 44),
	"roam_hull": Rect2i(866, 56, 88, 48),
	"roam_toasts": Rect2i(6, 56, 300, 24),
}
## The bottom-right corner nothing covers, and the tank's band the plates keep out of.
const CLEAR := Rect2i(760, 480, 200, 60)
const TANK_BAND_Y := Vector2i(150, 360)
## The palette for the platform's toasts, banners and help (brief 3.6).
const PALETTE := {
	"panel": Color("#17140f"),
	"panel_border": Color("#8a6a3a"),
	"text": Color("#e8dcc0"),
	"text_dim": Color("#a3937a"),
	"bar_bg": Color("#3a3128"),
	"bar_fg": Color("#b08a4a"),
	"accent": Color("#e3a24a"),
	"banner_bg": Color("#17140f"),
	"banner_text": Color("#e8dcc0"),
	"band": Color("#6b5230"),
	"glow": Color("#e3a24a"),
	"glow_text": Color("#e8dcc0"),
	"font_scale_px": 18,
	"text_px": 36,
	"key_px": 54,
	"grid_px": 2,
	"corner_radius": 0,
	"text_outline": false,
}
## The four v4 entries both helps share: the far panel, the shell's arc, the near threats and Repairs.
## Their arrows end on the panel or the card they explain.
const HELP_V4 := [
	["TANK_HELP_RANGE", Vector2(780, 300), Vector2(800, 350)],
	["TANK_HELP_PIP", Vector2(760, 240), Vector2(720, 190)],
	["TANK_HELP_NEAR", Vector2(540, 345), Vector2(600, 385)],
	["TANK_HELP_REPAIR", Vector2(760, 400), Vector2(690, 470)],
]
## The help overlay: [string key, at, arrow_to] in art px of the base (each arrow ends inside
## the plate it explains, so it moves with that plate).
const HELP := [
	["TANK_HELP_NUMBERS", Vector2(150, 404), Vector2(90, 452)],
	["TANK_HELP_SEATS", Vector2(450, 400), Vector2(420, 452)],
	["TANK_HELP_HULL", Vector2(800, 132), Vector2(880, 40)],
	["TANK_HELP_SURGE", Vector2(330, 300), Vector2(60, 506)],
]
## Free roam's help: the map strip and the board instead of the hull plate, and the turn.
const ROAM_HELP := [
	["TANK_HELP_NUMBERS", Vector2(150, 404), Vector2(90, 452)],
	["TANK_HELP_SEATS", Vector2(450, 400), Vector2(420, 452)],
	["TANK_HELP_ROAM_MAP", Vector2(240, 120), Vector2(300, 40)],
	["TANK_HELP_ROAM_BOARD", Vector2(700, 128), Vector2(850, 40)],
	["TANK_HELP_TURN", Vector2(330, 300), Vector2(60, 506)],
]


## The HudSpec: Tank Controls only, toasts under the mission plate, banners in the middle,
## shows_power (my numbers show raw W and %FTP), the palette and the help.
static func spec(game: TankGame) -> HudSpec:
	var hs := HudSpec.new()
	var roam := is_roam(game)
	if roam:
		_add(hs, TankHudRoamStrip.new(), game, "roam_strip")
		_add(hs, TankHudBoard.new(), game, "roam_board")
		var hull := TankHudHull.new()
		hull.show_kills = false
		_add(hs, hull, game, "roam_hull")
	else:
		_add(hs, TankHudMission.new(), game, "mission")
		_add(hs, TankHudHull.new(), game, "hull")
		_add(hs, TankHudBoss.new(), game, "boss")
	_add(hs, TankHudMine.new(), game, "mine")
	_add(hs, TankHudSeats.new(), game, "seats")
	_add(hs, TankHudLost.new(), game, "lost")
	# last, so a help point inside a plate moves with that plate rather than with the tags
	_add(hs, TankHudTags.new(), game, "tags")
	hs.toasts_at(LAYOUT["roam_toasts" if roam else "toasts"])
	hs.banners_at(LAYOUT["banners"])
	hs.banner_sound = ""
	hs.shows_power = true
	hs.help = help(roam)
	var pal := PALETTE.duplicate()
	pal["font"] = TankHudDraw.font()
	hs.palette = pal
	return hs


static func _add(hs: HudSpec, c: TankHudCtl, game: TankGame, key: String) -> void:
	var r: Rect2i = LAYOUT[key]
	hs.add_control(c.setup(game, r), r)


static func help(roam: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Array in (ROAM_HELP if roam else HELP) + HELP_V4:
		out.append({"text": str(e[0]), "at": e[1], "arrow_to": e[2]})
	return out


## True for a free-roam session (its HUD layout).
static func is_roam(game: TankGame) -> bool:
	return game != null and game.content != null and game.content.ok() and game.content.is_roam()


## `r` (art px of the base) placed on an `art` canvas the way the HUD anchors it.
static func anchored(r: Rect2i, art: Vector2i) -> Rect2i:
	return PixelViewport.anchor_rect(r, BASE, art)


## `key` translated (the game's strings, else the TranslationServer), `{0}`.. filled from `args`.
static func tx(game: TankGame, key: String, args: Array = []) -> String:
	if game != null and game.ctx != null and game.ctx.strings != null:
		return game.ctx.strings.t(key, args)
	var s := String(TranslationServer.translate(key))
	return s.format(args) if not args.is_empty() else s
