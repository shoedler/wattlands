class_name SiegeHud
extends RefCounted
## Siege's HudSpec (docs/games/siege.md 3 "HUD"). The module's hud_spec() returns
## SiegeHud.spec(game).
##
## Layout (1080p px; the 960 x 540 art is 2x):
##   top left      the kit's phase timeline, Siege's rush-marker strip, then the wave info
##                 ("Wave 2/3", enemies left by type, the engine and siege-tower warnings);
##   top right     the gate HP (kit readout, fed by the module: READOUT_GATE), the tar curtain
##                 (SiegeCurtainCard) and the rider's own gold (READOUT_GOLD), all >= 48 px;
##                 toasts below them;
##   bottom left   power gauge (watts >= 48 px), cadence, W' bar;
##   bottom centre Siege's teammate strip (SiegeStripOverlay; the kit's card strip is left out);
##   bottom right  the gear (SIM only), the Overdrive button and the route card (the five
##                 stations, caps, who is where, the 2 s coupling bar);
##   right middle  the break shop (SHOP_RECT, text >= 32 px) over the vicus, only in breaks,
##                 when the route card and the Overdrive button step aside.
## The centre (the fort, the junction and the road's last loop) stays clear during waves.

const READOUT_GATE := "siege_gate"
const READOUT_GOLD := "siege_gold"
## The shop's place in art pixels (2x on screen): east of the fort, below the top-right stack.
const SHOP_RECT := Rect2i(604, 264, 336, 196)
## Where the help panels point at the HUD's own cards (art pixels).
const ROUTE_CARD_AT := Vector2(856, 410)


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
	var s := (
		HudSpec
		. new()
		. add(HudSpec.TIMELINE, HudSpec.TOP_LEFT)
		. add_control(rush, HudSpec.TOP_LEFT)
		. add_control(wave, HudSpec.TOP_LEFT)
		. add(
			HudSpec.READOUT,
			HudSpec.TOP_RIGHT,
			{"source": "custom", "id": READOUT_GATE, "label": "SIEGE_HUD_GATE"}
		)
		. add_control(curtain, HudSpec.TOP_RIGHT)
		. add(
			HudSpec.READOUT,
			HudSpec.TOP_RIGHT,
			{"source": "custom", "id": READOUT_GOLD, "label": "SIEGE_HUD_GOLD"}
		)
		. add(HudSpec.POWER_GAUGE, HudSpec.BOTTOM_LEFT)
		. add(HudSpec.CADENCE, HudSpec.BOTTOM_LEFT)
		. add(HudSpec.WBAL, HudSpec.BOTTOM_LEFT)
		. add_control(strip, HudSpec.BOTTOM)
		. add(HudSpec.GEAR, HudSpec.BOTTOM_RIGHT)
		. add_control(od, HudSpec.BOTTOM_RIGHT)
		. add_control(route, HudSpec.BOTTOM_RIGHT)
		. add_control(shop, SHOP_RECT)
		. toasts_at(HudSpec.TOP_RIGHT)
		. banners_at(HudSpec.TOP_LEFT)
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
	out.append(entry("SIEGE_HELP_ROUTE_CARD", ROUTE_CARD_AT + Vector2(-230, 40), ROUTE_CARD_AT))
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
