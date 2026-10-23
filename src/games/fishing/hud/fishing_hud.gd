class_name FishingHud
extends RefCounted
## hud_spec() for Big Game Fishing (brief 3.5, G0 decision "HUD layout"; FishingLayout holds the
## rects). G0 stub: the kit widgets in the local lane's zone and the deck bar; the view and HUD
## builder adds the game's own Controls (strain and slack bars, deck bar, FishingLaneHud).


static func spec(game: FishingGame) -> HudSpec:
	var ctx := game.ctx
	var n := maxi(ctx.players.size(), 1)
	var local := ctx.local_player()
	var i := local.slot_index if local != null else 0
	var r := FishingLayout.local_hud(i, n)
	var spec := HudSpec.new()
	if (r["timeline"] as Rect2i).size != Vector2i.ZERO:
		spec.add(HudSpec.TIMELINE, r["timeline"])
	(
		spec
		. add(HudSpec.POWER_GAUGE, r["power"])
		. add(HudSpec.CADENCE, r["cadence"])
		. add(HudSpec.WBAL, FishingLayout.deck_wbal_rect())
		. add(HudSpec.GEAR, FishingLayout.deck_gear_rect())
		. toasts_at(FishingLayout.toast_rect())
		. banners_at(FishingLayout.banner_rect(i, n))
	)
	return spec
