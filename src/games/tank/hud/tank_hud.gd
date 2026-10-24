class_name TankHud
extends RefCounted
## hud_spec() for Diesel Domestiques (brief 3 HUD; GAME_SDK 10). Owner: hud.
##
## Every widget sits at an explicit Rect2i in art px of 640 x 360 (ADR "HUD layout"): the HUD
## covers only y 0-60 and 300-360, the app's PANIC button owns x >= 503 and y >= 316, and every
## kit widget gets at least its 1080p min_rect() / 3. The Tank Controls (TankStationCard,
## TankObjectiveLine, TankBossBars) read TankGame.state themselves and sit at their rects.

## Name -> Rect2i (art px). The widths and heights are checked in tests against the kit minimums.
const RECTS := {
	"timeline": Rect2i(4, 2, 200, 36),
	"hull_hp": Rect2i(206, 2, 60, 36),
	"teammates": Rect2i(268, 2, 140, 22),
	"boss_bars": Rect2i(410, 2, 226, 22),
	"toasts": Rect2i(268, 26, 368, 13),
	"banners": Rect2i(206, 40, 430, 19),
	"power_gauge": Rect2i(4, 302, 100, 36),
	"cadence": Rect2i(106, 302, 98, 36),
	"watts": Rect2i(206, 302, 60, 36),
	"wbal": Rect2i(4, 342, 100, 15),
	"gear": Rect2i(106, 342, 98, 15),
	"station_card": Rect2i(268, 302, 232, 56),
	"objective": Rect2i(504, 300, 132, 15),
}
## The custom readout ids the module feeds with ctx.hud.readout.
const READOUT_HULL := "hull_hp"


## The HudSpec: kit widgets and Tank Controls at RECTS; safety banners on. The prompts ("Surge to
## ram", "Surge to dodge", "Surge to overpressure") are kit toasts the module raises.
static func spec(game: TankGame) -> HudSpec:
	var card := TankStationCard.new()
	card.game = game
	var objective := TankObjectiveLine.new()
	objective.game = game
	var boss := TankBossBars.new()
	boss.game = game
	return (
		HudSpec
		. new()
		. add(HudSpec.TIMELINE, RECTS["timeline"])
		. add(
			HudSpec.READOUT,
			RECTS["hull_hp"],
			{"source": "custom", "id": READOUT_HULL, "label": "TANK_HUD_HULL"}
		)
		. add(HudSpec.TEAMMATES, RECTS["teammates"])
		. add(HudSpec.POWER_GAUGE, RECTS["power_gauge"])
		. add(HudSpec.CADENCE, RECTS["cadence"])
		. add(HudSpec.READOUT, RECTS["watts"], {"source": "power_w", "label": "TANK_HUD_WATTS"})
		. add(HudSpec.WBAL, RECTS["wbal"])
		. add(HudSpec.GEAR, RECTS["gear"])
		. add_control(card, RECTS["station_card"])
		. add_control(objective, RECTS["objective"])
		. add_control(boss, RECTS["boss_bars"])
		. toasts_at(RECTS["toasts"])
		. banners_at(RECTS["banners"])
	)
