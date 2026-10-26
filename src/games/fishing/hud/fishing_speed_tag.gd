class_name FishingSpeedTag
extends FishingHudControl
## The boat's speed on the water behind the local boat's stern (mockup B3): the knots in the deep
## teal, under them faint (upper teal) the speed the rider's watts would ride on a flat road
## (FishingHudModel.flat_kmh), on the art grid, no panel. Shown while the boat drives (and in
## the menu's drift); its rect is a strip under the surface across the view.

## The text's offset behind the stern pivot (art px) and the gap between its two lines.
const BEHIND_PX := 46
const TOP_PX := 6
const LINE_GAP := 4
const CAP := 7
const MIN_MPS := 0.5

var shown: bool = false
var knots: String = ""
var kmh: String = ""
## The text block drawn last (art px of the rect; tests read it).
var text_rect: Rect2i = Rect2i()
var _stern_x: float = -1.0
var _heading: int = 1


static func make(p_game: FishingGame, rect: Rect2i) -> FishingSpeedTag:
	var t := FishingSpeedTag.new()
	t.game = p_game
	t.name = "FishingSpeedTag"
	t.place_at(rect)
	return t


func refresh() -> void:
	var r := FishingHudModel.own_rider(game)
	shown = false
	if r == null or absf(r.v_mps) < MIN_MPS:
		return
	if not r.action in [FishingConst.A_DRIVE, FishingConst.A_HOME, FishingConst.A_DRIFT]:
		return
	var v := view()
	if v == null:
		return
	var boat: Variant = (v.model.get("boats", {}) as Dictionary).get(r.slot)
	if not boat is Vector2:
		return
	shown = true
	_heading = r.heading
	_stern_x = (boat as Vector2).x - float(BEHIND_PX * r.heading)
	knots = FishingHudModel.tr_key(
		game, FishingHudModel.KEY_KNOTS, [FishingHudModel.knots_text(r.v_mps)]
	)
	var n := local_numbers(r)
	var kg := 75.0
	if game.ctx != null and game.ctx.local_player() != null:
		kg = game.ctx.local_player().rider_mass_kg
	var flat := FishingHudModel.flat_kmh(float(n["power"]), kg)
	kmh = FishingHudModel.tr_key(game, FishingHudModel.KEY_KMH, [roundi(flat)])


func _draw() -> void:
	text_rect = Rect2i()
	if not shown:
		return
	var s := k()
	var u := float(FishingHudDraw.unit(s))
	var w1 := ceili(FishingHudDraw.text_w(knots, s) / u)
	var w2 := ceili(FishingHudDraw.text_w(kmh, s) / u)
	var w := maxi(w1, w2)
	var x := int(_stern_x) - (w if _heading > 0 else 0)
	x = clampi(x, 2, maxi(art_rect.size.x - w - 2, 2))
	var y1 := TOP_PX + CAP
	var y2 := y1 + LINE_GAP + CAP
	text_rect = Rect2i(x, TOP_PX, w, y2 - TOP_PX + 2)
	var right := x + w
	FishingHudDraw.text(self, Vector2(right - w1, y1) * u, knots, s, FishingPalette.DEEP)
	FishingHudDraw.text(self, Vector2(right - w2, y2) * u, kmh, s, FishingPalette.UPPER)
