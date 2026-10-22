class_name SiegeHud
extends RefCounted
## Siege's HudSpec (brief 3 "HUD"). Owner: B3 "view/hud" (src/games/siege/hud/). The module's
## hud_spec() returns SiegeHud.spec(game).
##
## Layout (1080p px): top left the timeline (+ Siege's rush-marker strip below it); top right
## the gate HP readout and own denarii (>= 48 px); bottom left power gauge, cadence, W'; bottom
## centre the teammate strip (+ Siege's target icons and markers in its own Control); bottom
## right the routing card and the Overdrive button, stacked ABOVE the app's PANIC button (the
## app reserves >= 380 x 100 there; anchored entries move up by themselves). Toasts and the kit's
## rescue banner show; show_safety_banners stays true. The kit's gear widget shows itself while
## the trainer is in SIM (Overdrive). The shop panel uses PedalScanList; tag an auto-confirmed
## pick ("via" == "auto") as {"k": "buy", ..., "auto": 1} (SiegeIntents.buy(item, pad, true)).
##
## Readouts the module feeds with ctx.hud.readout(id, text): READOUT_GATE, READOUT_DENARII.
##
## G0 status: kit widgets only. B3 adds the Siege Controls (routing card, Overdrive button,
## wave info, shop panel, strip overlay, rush strip).

const READOUT_GATE := "siege_gate"
const READOUT_DENARII := "siege_denarii"


static func spec(_game: SiegeGame) -> HudSpec:
	return (
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
			{"source": "custom", "id": READOUT_DENARII, "label": "SIEGE_HUD_DENARII"}
		)
		. add(HudSpec.POWER_GAUGE, HudSpec.BOTTOM_LEFT)
		. add(HudSpec.CADENCE, HudSpec.BOTTOM_LEFT)
		. add(HudSpec.WBAL, HudSpec.BOTTOM_LEFT)
		. add(HudSpec.TEAMMATES, HudSpec.BOTTOM)
		. add(HudSpec.GEAR, HudSpec.BOTTOM_RIGHT)
		. toasts_at(HudSpec.TOP)
		. banners_at(HudSpec.TOP)
	)
