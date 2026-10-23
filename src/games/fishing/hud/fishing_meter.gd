class_name FishingMeter
extends FishingHudControl
## The local rider's strain meter (red, zigzag icon; left of the cadence widget) or slack meter
## (yellow, loop icon; right of it): a vertical bar filling 0..1 from the lane state the host
## owns (brief 2.4 "Meters", 3.5). Hidden outside fights; the ride out's practice band shows no
## meters (brief 2.4).

const STRAIN := "strain"
const SLACK := "slack"

var kind: String = STRAIN
## The fill shown and whether the meter shows (tests read these).
var fill: float = 0.0
var shown: bool = false


static func make(p_game: FishingGame, p_kind: String) -> FishingMeter:
	var m := FishingMeter.new()
	m.game = p_game
	m.kind = p_kind
	m.name = "FishingMeter_" + p_kind
	m.design_h = float(FishingLayout.ROW_H * 3)
	return m


func refresh() -> void:
	var l := FishingHudModel.local_lane(game)
	shown = l != null and l.state == FishingConst.ST_FIGHT
	fill = (l.strain if kind == STRAIN else l.slack) if shown else 0.0


func color() -> Color:
	return FishingHudDraw.STRAIN if kind == STRAIN else FishingHudDraw.SLACK


func _draw() -> void:
	if not shown:
		return
	var w := size.x
	var icon := Rect2(1.0, 2.0, w - 2.0, w - 2.0)
	if kind == STRAIN:
		FishingHudDraw.zigzag(self, icon.grow(-2.0), color())
	else:
		FishingHudDraw.loop(self, icon, color())
	var bar := Rect2(1.0, w + 4.0, w - 2.0, size.y - w - 6.0)
	FishingHudDraw.bar(self, bar, fill, color(), true)
	if fill > 0.75:
		draw_rect(bar.grow(1.0), WlTheme.WARN, false, 2.0)
