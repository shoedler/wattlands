class_name SiegeHud
extends RefCounted
## Siege's HudSpec (brief 3 "HUD"). Owner: B3 "view/hud" (src/games/siege/hud/). The module's
## hud_spec() returns SiegeHud.spec(game).
##
## Layout (1080p px):
##   top left      the kit's phase timeline, Siege's rush-marker strip below it, then wave info
##                 ("Wave 2/3", enemies left by type, the most urgent warning);
##   top right     the gate HP big readout and the rider's own denarii (>= 48 px, fed by the
##                 module through ctx.hud.readout: READOUT_GATE and READOUT_DENARII);
##   bottom left   power gauge (watts >= 48 px), cadence, W' bar;
##   bottom centre Siege's own teammate strip, one low row of four cells (slot chip, target icon,
##                 raw W and %FTP from the snapshot, Overdrive and rescue markers). The kit's
##                 teammate card strip is left out: it showed the same W and %FTP a second time
##                 in a 1070 x 350 block that covered the roads;
##   bottom right  the gear widget (the kit shows it while the trainer is in SIM, i.e. Overdrive),
##                 the routing card and the Overdrive button. The app reserves at least 380 x 100
##                 above the screen corner for its PANIC button; anchored entries stack above it
##                 by themselves. Nothing of Siege's sits in that reserve.
##   below the fort the break shop (text >= 32 px) in a Rect2i between the fort's front wall and
##                 the strip, only visible in breaks: the generator, the drum, the wheels and the
##                 towers stay in view; the centre stays clear during waves.
## Toasts show under the denarii readout (top right); banners go to the top left stack, below the
## wave info, so the kit's warm-up and rescue banners (show_safety_banners stays true: Siege has
## no banners of its own to replace them) never cover the generator and the drum.

const READOUT_GATE := "siege_gate"
const READOUT_DENARII := "siege_denarii"
## Where the shop sits (1080p pixels): on the ground below the fort's front wall (the camera
## frames the wall's foot at about y 455) and above the bottom-centre strip (from about y 950),
## between the corner stacks, clear of the PANIC corner.
const SHOP_RECT := Rect2i(660, 458, 600, 490)


static func spec(game: SiegeGame) -> HudSpec:
	var rush := SiegeRushStrip.new()
	rush.game = game
	var wave := SiegeWaveInfo.new()
	wave.game = game
	var strip := SiegeStripOverlay.new()
	strip.game = game
	var od := SiegeOverdriveButton.new()
	od.game = game
	var route := SiegeRouteCard.new()
	route.game = game
	var shop := SiegeShopPanel.new()
	shop.game = game
	return (
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
		. add(
			HudSpec.READOUT,
			HudSpec.TOP_RIGHT,
			{"source": "custom", "id": READOUT_DENARII, "label": "SIEGE_HUD_DENARII"}
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
