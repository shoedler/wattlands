class_name FishingMeter
extends FishingHudControl
## The local rider's strain meter (surface teal, zigzag icon; left of the cadence widget) or
## slack meter (sage, loop icon; right of it): a vertical bar filling 0..1 from the rider state
## the host owns, turning to the alert accent (framed) past ALERT_AT, all in art pixels. Shown
## only in a fight.

const STRAIN := "strain"
const SLACK := "slack"
const ALERT_AT := 0.75
## The icon's rows above the bar (one pixel between them).
const ICON_ROWS := 5

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
	var w := floorf(size.x / u) * u
	var icon := FishingHudDraw.ZIGZAG if kind == STRAIN else FishingHudDraw.LOOP
	FishingHudDraw.pixels(self, icon, Vector2.ZERO, u, color())
	var top := float(ICON_ROWS + 1) * u
	var bar := Rect2(0.0, top, w, floorf(size.y / u) * u - top)
	FishingHudDraw.bar(self, bar, fill, color(), true, u)
	if fill > ALERT_AT:
		FishingHudDraw.frame(self, bar, u, FishingHudDraw.ALERT)
