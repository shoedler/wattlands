class_name FishingHud
extends RefCounted
## hud_spec() for Turbo Reel (brief 3.5, G0 decision "HUD layout"; FishingLayout holds the
## rects, all in art pixels of the 640 x 360 view):
##  - the local lane's HUD zone: the kit timeline (left out where the row would reach PANIC),
##    then one row: power gauge, the strain meter (red, zigzag), cadence (with the band published
##    by cadence_band), the slack meter (yellow, loop);
##  - the deck bar: FishingDeckBar (trip clock, phase chip, fish row or gaff meter), the kit gear
##    and W' widgets in their rects, FishingCatchBoard (points, fish, hookup level, catches);
##  - one FishingLaneHud at the top of every other lane's zone;
##  - toasts below the deck bar, banners over the local lane's left two-thirds.
## Nothing reaches into the PANIC corner (art x >= 503 and y >= 316) at any lane count.


static func spec(game: FishingGame) -> HudSpec:
	var ctx := game.ctx
	var n := clampi(ctx.players.size(), 1, 4)
	var local := ctx.local_player()
	var i := local.slot_index if local != null else 0
	var r := FishingLayout.local_hud(i, n)
	var spec := HudSpec.new()
	if (r["timeline"] as Rect2i).size != Vector2i.ZERO:
		spec.add(HudSpec.TIMELINE, r["timeline"])
	(
		spec
		. add(HudSpec.POWER_GAUGE, r["power"])
		. add_control(FishingMeter.make(game, FishingMeter.STRAIN), r["strain"])
		. add(HudSpec.CADENCE, r["cadence"])
		. add_control(FishingMeter.make(game, FishingMeter.SLACK), r["slack"])
		. add_control(FishingDeckBar.make(game), FishingLayout.deck_left_rect())
		. add(HudSpec.GEAR, FishingLayout.deck_gear_rect())
		. add(HudSpec.WBAL, FishingLayout.deck_wbal_rect())
		. add_control(FishingCatchBoard.make(game), FishingLayout.deck_right_rect())
	)
	for p in ctx.players:
		if p.slot_index != i and p.slot_index < n:
			spec.add_control(
				FishingLaneHud.make(game, p.slot_index), FishingLayout.lane_hud(p.slot_index, n)
			)
	spec.toasts_at(FishingLayout.toast_rect())
	spec.banners_at(FishingLayout.banner_rect(i, n))
	return spec
