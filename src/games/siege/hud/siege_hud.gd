class_name SiegeHud
extends RefCounted
## Siege's HudSpec (docs/games/siege.md 3 "HUD"). The module's hud_spec() returns
## SiegeHud.spec(game).
##
## Every entry sits in a Rect2i (art pixels, 2x at 1080p) off the field: the road runs down the
## left edge (screen x < 280), loops along the bottom (y > 830 left of x 900) and climbs to the
## bridge (about 700, 650); the fort spans x 480..1474, y 120..760. What is left is the top band
## over the camp and the mountain, the right edge over the quarry, and the bottom right over the
## wadi:
##   top left band   the kit's timeline (x 300..900), the wave line (enemies left, the urgent
##                   warning), the banners (above the north-west tower's ballista);
##   top band        Siege's compact teammate strip over the mountain, the rush strip
##                   (endurance) and the toasts below it, above the wheels;
##   right column    the gate (kit readout, fed by the module: READOUT_GATE), the tar curtain,
##                   the gold (READOUT_GOLD), all >= 48 px; the route card (five stations with
##                   cap pips and the coupling bar) and the Overdrive button;
##   bottom right    power gauge (watts >= 48 px), cadence, W' and the gear in one low row;
##   breaks          the shop (4 rows at 32 px) east of the fort where the route card and the
##                   Overdrive button step aside.
## The centre, the road loops, the bridge and the plaza stay clear.

const READOUT_GATE := "siege_gate"
const READOUT_GOLD := "siege_gold"
const TIMELINE_RECT := Rect2i(150, 8, 300, 75)
const WAVE_RECT := Rect2i(150, 85, 300, 18)
const RUSH_RECT := Rect2i(465, 50, 352, 24)
const BANNER_RECT := Rect2i(150, 105, 300, 28)
const STRIP_RECT := Rect2i(465, 8, 352, 40)
const TOAST_RECT := Rect2i(470, 76, 330, 26)
const GATE_RECT := Rect2i(818, 12, 130, 58)
const CURTAIN_RECT := Rect2i(818, 73, 130, 52)
const GOLD_RECT := Rect2i(818, 128, 130, 58)
const ROUTE_RECT := Rect2i(818, 190, 130, 118)
const OD_RECT := Rect2i(818, 312, 130, 32)
const POWER_RECT := Rect2i(460, 466, 160, 62)
const CADENCE_RECT := Rect2i(624, 466, 146, 62)
const WBAL_RECT := Rect2i(774, 466, 174, 20)
const GEAR_RECT := Rect2i(774, 490, 174, 38)
## The shop's place in breaks (no attackers then): east of the plaza over the aqueduct and the
## vicus, clipping the fort's south-east corner; it never covers the road or the bridge.
const SHOP_RECT := Rect2i(600, 326, 348, 138)
## Where the help panels point at the HUD's own cards (art pixels).
const ROUTE_CARD_AT := Vector2(838, 249)


static func spec(game: SiegeGame) -> HudSpec:
	var rush := SiegeRushStrip.new()
	rush.game = game
	var wave := SiegeWaveInfo.new()
	wave.game = game
	var curtain := SiegeCurtainCard.new()
	curtain.game = game
	var strip := SiegeStripOverlay.new()
	strip.game = game
	var od := SiegeOverdriveButton.new()
	od.game = game
	var route := SiegeRouteCard.new()
	route.game = game
	var shop := SiegeShopPanel.new()
	shop.game = game
	var gate := {"source": "custom", "id": READOUT_GATE, "label": "SIEGE_HUD_GATE"}
	var gold := {"source": "custom", "id": READOUT_GOLD, "label": "SIEGE_HUD_GOLD"}
	var s := (
		HudSpec
		. new()
		. add(HudSpec.TIMELINE, TIMELINE_RECT)
		. add_control(wave, WAVE_RECT)
		. add_control(rush, RUSH_RECT)
		. add_control(strip, STRIP_RECT)
		. add(HudSpec.READOUT, GATE_RECT, gate)
		. add_control(curtain, CURTAIN_RECT)
		. add(HudSpec.READOUT, GOLD_RECT, gold)
		. add_control(route, ROUTE_RECT)
		. add_control(od, OD_RECT)
		. add(HudSpec.POWER_GAUGE, POWER_RECT)
		. add(HudSpec.CADENCE, CADENCE_RECT)
		. add(HudSpec.WBAL, WBAL_RECT)
		. add(HudSpec.GEAR, GEAR_RECT)
		. add_control(shop, SHOP_RECT)
		. toasts_at(TOAST_RECT)
		. banners_at(BANNER_RECT)
	)
	s.help = help(game)
	return s


## The help overlay (art pixels on 960 x 540): your wheel, your powered path, the stations, the
## road, the gate and its curtain, the route card and the shop.
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
	var shop := Vector2(SHOP_RECT.get_center())
	out.append(entry("SIEGE_HELP_WHEEL", wheel + Vector2(0, -78), wheel))
	out.append(entry("SIEGE_HELP_PATH", lane + Vector2(-150, -20), lane))
	out.append(entry("SIEGE_HELP_STATIONS", onager + Vector2(-60, 70), onager))
	out.append(entry("SIEGE_HELP_ROAD", road + Vector2(70, -40), road))
	out.append(entry("SIEGE_HELP_GATE", gate + Vector2(-40, 90), gate))
	out.append(entry("SIEGE_HELP_ROUTE_CARD", ROUTE_CARD_AT + Vector2(-200, 10), ROUTE_CARD_AT))
	out.append(entry("SIEGE_HELP_SHOP", shop + Vector2(-210, -70), shop))
	return out


static func entry(key: String, at: Vector2, arrow_to: Vector2) -> Dictionary:
	var a := Vector2(clampf(at.x, 90.0, 870.0), clampf(at.y, 30.0, 510.0))
	return {"text": key, "at": a, "arrow_to": arrow_to}


## The clutch drum where slot `slot`'s lane meets station `target`'s column (the lit path's
## heart), in world metres (src/games/siege/art/scene.mjs LANE_Y and GEAR_X).
static func route_point(slot: int, target: int) -> Vector3:
	var lane_y: Array[float] = [18.8, 21.4, 24.0, 26.6]
	var gear_x: Array[float] = [60.0, 17.0, 36.0, 47.0, 52.0]
	return Vector3(gear_x[clampi(target, 0, 4)], lane_y[clampi(slot, 0, 3)], 3.0)
