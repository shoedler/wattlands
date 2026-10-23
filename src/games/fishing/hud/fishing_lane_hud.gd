class_name FishingLaneHud
extends FishingHudControl
## The compact HUD of another rider's lane (brief 3.5): the slot chip (colour and shape), the
## lane's snapshot W and rpm at >= 32 px (LANE_NUMBER_PX), the band published for it (snapshot
## band lo/hi) with a cadence marker from its EMA cadence, both meters (zigzag and loop icons),
## and the species and distance, or the lane's status when no fish is on.

const BAND_LO_RPM := 50.0
const BAND_SPAN_RPM := 80.0

var slot: int = 0
## The model of the last refresh (tests read it).
var watts: int = 0
var rpm: int = 0
var band_lo: int = 0
var band_hi: int = 0
var strain: float = 0.0
var slack: float = 0.0
var in_fight: bool = false
var detail: String = ""


static func make(p_game: FishingGame, p_slot: int) -> FishingLaneHud:
	var h := FishingLaneHud.new()
	h.game = p_game
	h.slot = p_slot
	h.name = "FishingLaneHud_%d" % p_slot
	h.design_h = float(FishingLayout.ROW_H * 3)
	return h


func refresh() -> void:
	var l := game.state.lane(slot) if game != null and game.state != null else null
	if l == null:
		return
	watts = roundi(l.power_w)
	rpm = roundi(l.cadence_ema)
	band_lo = l.pub_lo
	band_hi = l.pub_hi
	in_fight = l.state == FishingConst.ST_FIGHT
	strain = l.strain if in_fight else 0.0
	slack = l.slack if in_fight else 0.0
	var row := FishingHudModel.fish_row(game, l)
	if bool(row["visible"]):
		var tx := FishingHudModel.strings_of(game)
		detail = "%s  %s" % [row["name"], tx.t(FishingHudModel.KEY_DISTANCE, [str(row["d_m"])])]
	else:
		detail = FishingHudModel.status_text(game, l)


func _draw() -> void:
	if game == null or game.state == null:
		return
	var s := k()
	var tx := FishingHudModel.strings_of(game)
	draw_rect(Rect2(Vector2.ZERO, size), WlTheme.PANEL)
	var look := FishingHudModel.look(game, slot)
	var col: Color = look["color"]
	FishingHudDraw.shape(
		self,
		str(look["shape"]),
		Vector2(24, 26) * s,
		15.0 * s,
		col,
		bool(look.get("hollow", false))
	)
	var num := px(FishingHudModel.LANE_NUMBER_PX)
	var x := 50.0 * s
	x += FishingHudDraw.text(
		self,
		Vector2(x, 38.0 * s),
		"%d %s" % [watts, tx.t(FishingHudModel.KEY_WATTS)],
		num,
		WlTheme.TEXT,
		true
	)
	x += 20.0 * s
	x += FishingHudDraw.text(
		self,
		Vector2(x, 38.0 * s),
		"%d %s" % [rpm, tx.t(FishingHudModel.KEY_RPM)],
		num,
		WlTheme.TEXT,
		true
	)
	x += 20.0 * s
	FishingHudDraw.text(self, Vector2(x, 36.0 * s), detail, px(WlTheme.SMALL_PX), WlTheme.TEXT_DIM)
	var band := Rect2(12.0 * s, 62.0 * s, 330.0 * s, 26.0 * s)
	draw_rect(band, WlTheme.BAR_BG)
	if band_hi > band_lo:
		var a := band.position.x + band.size.x * FishingHudModel.rpm_frac(float(band_lo))
		var b := band.position.x + band.size.x * FishingHudModel.rpm_frac(float(band_hi))
		var inside := rpm >= band_lo and rpm <= band_hi
		draw_rect(
			Rect2(a, band.position.y, b - a, band.size.y),
			FishingHudDraw.BAND_IN if inside else WlTheme.BAND
		)
	draw_rect(band, WlTheme.OUTLINE, false, 2.0)
	var mx := band.position.x + band.size.x * FishingHudModel.rpm_frac(float(rpm))
	var tri := PackedVector2Array(
		[
			Vector2(mx - 9 * s, band.position.y - 4 * s),
			Vector2(mx + 9 * s, band.position.y - 4 * s),
			Vector2(mx, band.position.y + 12 * s)
		]
	)
	draw_colored_polygon(tri, WlTheme.TEXT)
	tri.append(tri[0])
	draw_polyline(tri, WlTheme.OUTLINE, 2.0)
	if not in_fight:
		return
	var mx0 := 360.0 * s
	FishingHudDraw.zigzag(self, Rect2(mx0, 64.0 * s, 22.0 * s, 20.0 * s), FishingHudDraw.STRAIN)
	FishingHudDraw.bar(
		self, Rect2(mx0 + 28.0 * s, 64.0 * s, 100.0 * s, 20.0 * s), strain, FishingHudDraw.STRAIN
	)
	var mx1 := mx0 + 140.0 * s
	FishingHudDraw.loop(self, Rect2(mx1, 62.0 * s, 24.0 * s, 24.0 * s), FishingHudDraw.SLACK)
	FishingHudDraw.bar(
		self, Rect2(mx1 + 30.0 * s, 64.0 * s, 100.0 * s, 20.0 * s), slack, FishingHudDraw.SLACK
	)
