class_name FishingMeter
extends FishingHudControl
## The local rider's strain meter (surface teal; left of the cadence widget) or slack meter
## (sage; right of it): on its own deep-teal panel, a vertical bar filling 0..1 from the rider
## state the host owns, turning to the alert accent with a frame past ALERT_AT, all in art
## pixels. Shown only in a fight.

const STRAIN := "strain"
const SLACK := "slack"
const ALERT_AT := 0.75
## The bar's inset on its own panel (art px).
const PAD_PX := 2.0

var kind: String = STRAIN
## The fill shown and whether the meter shows (tests read these).
var fill: float = 0.0
var shown: bool = false


static func make(p_game: FishingGame, p_kind: String) -> FishingMeter:
	var m := FishingMeter.new()
	m.game = p_game
	m.kind = p_kind
	m.name = "FishingMeter_" + p_kind
	m.design_h = 102.0
	return m


func refresh() -> void:
	var r := FishingHudModel.own_rider(game)
	shown = r != null and r.action == FishingConst.A_FIGHT
	fill = (r.strain if kind == STRAIN else r.slack) if shown else 0.0


func color() -> Color:
	if fill > ALERT_AT:
		return FishingHudDraw.ALERT
	return FishingHudDraw.STRAIN if kind == STRAIN else FishingHudDraw.SLACK


func _draw() -> void:
	if not shown:
		return
	var u := float(FishingHudDraw.unit(k()))
	var box := Rect2(Vector2.ZERO, (size / u).floor() * u)
	FishingHudDraw.panel(self, box)
	var bar := box.grow(-PAD_PX * u)
	FishingHudDraw.bar(self, bar, fill, color(), true, u)
	if fill > ALERT_AT:
		FishingHudDraw.frame(self, bar, u, FishingHudDraw.ALERT)
