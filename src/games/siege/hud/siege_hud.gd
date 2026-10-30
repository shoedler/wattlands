class_name SiegeHud
extends RefCounted
## Siege's HudSpec (docs/games/siege.md 3 "HUD"). This is the rules builder's minimal spec: the
## view builder replaces it with the route card, the wave info, the teammate strip and the shop
## panel. The module feeds the custom readouts through ctx.hud.readout (READOUT_GATE,
## READOUT_GOLD).

const READOUT_GATE := "siege_gate"
const READOUT_GOLD := "siege_gold"


static func spec(game: SiegeGame) -> HudSpec:
	var s := (
		HudSpec
		. new()
		. add(HudSpec.TIMELINE, HudSpec.TOP_LEFT)
		. add(
			HudSpec.READOUT,
			HudSpec.TOP_RIGHT,
			{"source": "custom", "id": READOUT_GATE, "label": "SIEGE_HUD_GATE"}
		)
		. add(
			HudSpec.READOUT,
			HudSpec.TOP_RIGHT,
			{"source": "custom", "id": READOUT_GOLD, "label": "SIEGE_HUD_GOLD"}
		)
		. add(HudSpec.POWER_GAUGE, HudSpec.BOTTOM_LEFT)
		. add(HudSpec.CADENCE, HudSpec.BOTTOM_LEFT)
		. add(HudSpec.TEAMMATES, HudSpec.BOTTOM)
		. toasts_at(HudSpec.TOP_RIGHT)
		. banners_at(HudSpec.TOP_LEFT)
	)
	s.help = help(game)
	return s


## The help overlay's entries (art pixels on 960 x 540): your wheel, the stations, the road, the
## gate.
static func help(game: SiegeGame) -> Array[Dictionary]:
	var path: SiegePath = null
	if game != null and game.state != null:
		path = game.state.path
	var out: Array[Dictionary] = []
	if path == null:
		return out
	var slot := 0
	if game.ctx != null:
		var me := game.state.rider(game.ctx.local_peer)
		slot = me.slot if me != null else 0
	var wheel := path.to_art(path.wheels[clampi(slot, 0, 3)])
	var onager := path.to_art(path.station_pos[SiegeIds.STATION_ONAGER])
	var road := path.to_art(path.point_at(path.length_m * 0.5))
	var gate := path.to_art(path.gate_pos)
	out.append({"text": "SIEGE_HELP_WHEEL", "at": wheel + Vector2(0, -60), "arrow_to": wheel})
	out.append({"text": "SIEGE_HELP_STATIONS", "at": onager + Vector2(80, -40), "arrow_to": onager})
	out.append({"text": "SIEGE_HELP_ROAD", "at": road + Vector2(0, -50), "arrow_to": road})
	out.append({"text": "SIEGE_HELP_GATE", "at": gate + Vector2(120, 30), "arrow_to": gate})
	return out
