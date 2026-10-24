class_name FishingFightPanel
extends FishingHudControl
## Beside the local rider's meters: in a fight the species, the line out and the fish's stamina;
## in the Landing the gaff meter (Sprint! then Easy spin, a star for a trophy); otherwise the
## zone under the boat and the depth to the floor.

const ART := Rect2i(222, 322, 200, 34)

var fish: Dictionary = {}
var gaff: Dictionary = {}
var place: String = ""


static func make(p_game: FishingGame) -> FishingFightPanel:
	var p := FishingFightPanel.new()
	p.game = p_game
	p.name = "FishingFightPanel"
	p.design_h = float(ART.size.y * 3)
	return p


func refresh() -> void:
	var r := FishingHudModel.own_rider(game)
	fish = FishingHudModel.fish_row(game, r)
	gaff = FishingHudModel.gaff(r)
	place = ""
	if r != null and game.state.world != null:
		var w := game.state.world
		var tx := FishingHudModel.strings_of(game)
		var key := "FISHING_ZONE_" + w.zone_at(r.x_m).to_upper()
		place = tx.t(key) if tx.has(key) else w.zone_at(r.x_m).capitalize()
		var d := w.floor_depth_m(r.x_m)
		if not is_inf(d):
			var dist := FishingHudModel.tr_key(game, FishingHudModel.KEY_DISTANCE, [roundi(d)])
			place += "  " + dist


func _draw() -> void:
	var s := k()
	var big := px(WlTheme.LABEL_PX)
	var small := px(WlTheme.SMALL_PX)
	if bool(gaff.get("visible", false)):
		var label := FishingHudModel.tr_key(game, str(gaff["phase"]))
		FishingHudDraw.text(self, Vector2(6, 30) * s, label, big, FishingHudDraw.GAFF, true)
		var bar := Rect2(Vector2(6, 46) * s, Vector2(size.x - 18.0 * s, 26.0 * s))
		FishingHudDraw.bar(self, bar, float(gaff["fill"]), FishingHudDraw.GAFF)
		var star_at := Vector2(bar.end.x - 14.0 * s, bar.get_center().y)
		FishingHudDraw.star(self, star_at, 10.0 * s, FishingPalette.BRASS_1)
		return
	if bool(fish.get("visible", false)):
		var dist := FishingHudModel.tr_key(game, FishingHudModel.KEY_DISTANCE, [str(fish["d_m"])])
		var line := "%s  %s" % [fish["name"], dist]
		FishingHudDraw.text(self, Vector2(6, 30) * s, line, big, WlTheme.TEXT, true)
		var bar2 := Rect2(Vector2(6, 48) * s, Vector2(size.x - 18.0 * s, 20.0 * s))
		FishingHudDraw.bar(self, bar2, float(fish["stamina"]), FishingHudDraw.STAMINA)
		return
	FishingHudDraw.text(self, Vector2(6, 64) * s, place, small, WlTheme.TEXT_DIM)
