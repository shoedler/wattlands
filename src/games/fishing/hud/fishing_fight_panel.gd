class_name FishingFightPanel
extends FishingHudControl
## Beside the local rider's meters, on an abyss-teal panel: in a fight the species, the line out
## and the fish's stamina; in the Landing the gaff meter (Sprint! then Easy spin, a star for a
## trophy); otherwise the zone under the boat and the depth to the floor.

const ART := Rect2i(239, 322, 200, 34)
## The bar's height and its gap under the descenders, in glyph pixels.
const BAR_ROWS := 4.0
const GAP_ROWS := 1.0

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
			place += " " + dist


func _draw() -> void:
	var s := k()
	var u := float(FishingHudDraw.unit(s))
	var pad := 3.0 * u
	var line_h := float(FishingHudDraw.LINE_ROWS) * u
	# The cap starts at the padding (the line box's leading sits in it), the bar under the
	# descenders and a gap, then the same padding.
	var top := pad - float(FishingHudDraw.LEAD_ROWS) * u
	var text_rows := float(FishingHudDraw.LINE_ROWS - FishingHudDraw.LEAD_ROWS)
	var bar_y := pad + (text_rows + GAP_ROWS) * u
	var panel := Rect2(0, 0, size.x - 2.0 * u, bar_y + BAR_ROWS * u + pad)
	var bar := Rect2(pad, bar_y, panel.size.x - 2.0 * pad, BAR_ROWS * u)
	if bool(gaff.get("visible", false)) or bool(fish.get("visible", false)):
		FishingHudDraw.panel(self, panel)
	if bool(gaff.get("visible", false)):
		var label := FishingHudModel.tr_key(game, str(gaff["phase"]))
		FishingHudDraw.text_line(self, pad, top, label, s, FishingHudDraw.GAFF)
		FishingHudDraw.bar(self, bar, float(gaff["fill"]), FishingHudDraw.GAFF)
		var star_at := Vector2(bar.end.x - 3.0 * u, bar.get_center().y)
		FishingHudDraw.star(self, star_at, 3.0 * u, FishingPalette.FOAM)
		return
	if bool(fish.get("visible", false)):
		var dist := FishingHudModel.tr_key(game, FishingHudModel.KEY_DISTANCE, [str(fish["d_m"])])
		var line := "%s %s" % [fish["name"], dist]
		FishingHudDraw.text_line(self, pad, top, line, s, FishingPalette.HUD_TEXT)
		FishingHudDraw.bar(self, bar, float(fish["stamina"]), FishingHudDraw.STAMINA)
		return
	var box := Vector2(FishingHudDraw.text_w(place, s) + 2.0 * pad, line_h + 2.0 * pad)
	var at := Vector2(0, size.y - box.y)
	FishingHudDraw.panel(self, Rect2(at, box))
	FishingHudDraw.text_line(self, pad, at.y + pad, place, s, FishingPalette.HUD_DIM)
