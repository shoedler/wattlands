class_name FishingCruisePanel
extends FishingHudControl
## The bottom-left box outside a fight (mockup B2), on the art grid in the HUD panel teal: the
## left box has the watts big and the cadence and %FTP under them; with a heart rate sensor the
## right box has a muted red heart (FishingHudDraw.HEART, the HUD's one off-palette colour) and
## the bpm big; without one the left box alone is 1.5 boxes wide. Under both, as wide as the
## boxes, a 30 s power graph (FishingPowerTrace, filled; 1.25 x FTP or the window's most at the
## top). Right of the box, bottom-aligned at one x (tag_x()), the zone under the boat and the
## depth to the floor in a small tag, the kit gear right above it. Hidden while a fish is on in a
## fight (FishingFightPanel shows the numbers there).

## One box's width, the gap round everything and the rows (art px): the big line's cap, the
## small line under it, the graph.
const BOX_W := 96
const PAD := 3
const BIG_CAP := 14
const SMALL_CAP := 7
const ROW_GAP := 4
const GRAPH_ROWS := 15
const TAG_GAP := 4
## The zone tag's height (art px); it sits bottom-aligned right of the box at tag_x(), the kit
## gear (FishingHud) right above it, both in one place with or without the heart rate box.
const TAG_H := 13
const GRAPH_S := 30.0

var shown: bool = false
var numbers: Dictionary = {}
var place: String = ""
var trace: FishingPowerTrace = FishingPowerTrace.new(GRAPH_S)
## The panel (and the tag) drawn last, in art px of the rect (tests read them).
var panel_rect: Rect2i = Rect2i()
var tag_rect: Rect2i = Rect2i()


static func make(p_game: FishingGame, rect: Rect2i) -> FishingCruisePanel:
	var p := FishingCruisePanel.new()
	p.game = p_game
	p.name = "FishingCruisePanel"
	p.place_at(rect)
	return p


## The panel's size in art px (with or without the heart rate box).
static func panel_size(with_hr: bool) -> Vector2i:
	var w := 2 * BOX_W if with_hr else BOX_W * 3 / 2
	return Vector2i(w, PAD + BIG_CAP + ROW_GAP + SMALL_CAP + ROW_GAP + GRAPH_ROWS + PAD)


func refresh() -> void:
	var r := FishingHudModel.own_rider(game)
	numbers = local_numbers(r)
	trace.add(float(numbers["t"]), float(numbers["power"]), 0.0)
	shown = r != null and not FishingHudModel.fight_panel_up(game, r)
	place = ""
	if r != null and game.state.world != null:
		var w := game.state.world
		var tx := FishingHudModel.strings_of(game)
		var key := "FISHING_ZONE_" + w.zone_at(r.x_m).to_upper()
		place = tx.t(key) if tx.has(key) else w.zone_at(r.x_m).capitalize()
		var d := w.floor_depth_m(r.x_m)
		if not is_inf(d):
			place += " " + FishingHudModel.tr_key(game, FishingHudModel.KEY_DISTANCE, [roundi(d)])


func _draw() -> void:
	if not shown:
		return
	var s := k()
	var u := float(FishingHudDraw.unit(s))
	var hr := int(numbers.get("hr", 0))
	var ps := panel_size(hr > 0)
	var top := art_rect.size.y - ps.y
	panel_rect = Rect2i(Vector2i(0, top), ps)
	var box := Rect2(Vector2(panel_rect.position) * u, Vector2(ps) * u)
	FishingHudDraw.panel(self, box, u)
	var big_base := float(top + PAD + BIG_CAP) * u
	var small_base := big_base + float(ROW_GAP + SMALL_CAP) * u
	var x := float(PAD) * u
	var watts := str(roundi(float(numbers["power"])))
	x += FishingHudDraw.text(self, Vector2(x, big_base), watts, s, FishingPalette.HUD_TEXT, true)
	var unit_w := FishingHudModel.tr_key(game, FishingHudModel.KEY_WATTS)
	FishingHudDraw.text(self, Vector2(x + u, big_base), unit_w, s, FishingPalette.HUD_DIM)
	x = float(PAD) * u
	var rpm := str(roundi(float(numbers["cadence"])))
	x += FishingHudDraw.text(self, Vector2(x, small_base), rpm, s, FishingPalette.HUD_TEXT)
	var rpm_w := " " + FishingHudModel.tr_key(game, FishingHudModel.KEY_RPM)
	x += FishingHudDraw.text(self, Vector2(x, small_base), rpm_w, s, FishingPalette.HUD_DIM)
	var pct := FishingHudModel.tr_key(
		game, FishingHudModel.KEY_FTP, [roundi(float(numbers["pct"]))]
	)
	FishingHudDraw.text(
		self, Vector2(x + 2.0 * u, small_base), "  " + pct, s, FishingPalette.HUD_DIM
	)
	if hr > 0:
		var bx := float(BOX_W) * u
		var line := Rect2(bx, float(top + 1) * u, u, float(PAD + BIG_CAP + ROW_GAP + SMALL_CAP) * u)
		self.draw_rect(line, FishingPalette.HUD_PANEL_FRAME)
		var heart_at := Vector2(bx + float(PAD + 1) * u, big_base - float(BIG_CAP - 4) * u)
		FishingHudDraw.pixels(self, FishingHudDraw.HEART_ROWS, heart_at, u, FishingHudDraw.HEART)
		var hx := bx + float(PAD + 1 + 7 + 3) * u
		FishingHudDraw.text(self, Vector2(hx, big_base), str(hr), s, FishingPalette.HUD_TEXT, true)
		var bpm := FishingHudModel.tr_key(game, FishingHudModel.KEY_BPM)
		FishingHudDraw.text(self, Vector2(hx, small_base), bpm, s, FishingPalette.HUD_DIM)
	var gy := top + PAD + BIG_CAP + ROW_GAP + SMALL_CAP + ROW_GAP
	var g := Rect2(Vector2(PAD, gy) * u, Vector2(ps.x - 2 * PAD, GRAPH_ROWS) * u)
	# B2's strip: a mid-teal ground, a surface-teal fill under a haze trace
	self.draw_rect(g, FishingPalette.MID)
	var top_w := FishingFightPanel.graph_top(trace, r_ftp())
	FishingHudDraw.graph(
		self, g, trace, top_w, u, 0.0, true, FishingPalette.HAZE, 0.0, FishingPalette.SURFACE
	)
	tag_rect = Rect2i()
	if place != "":
		var tw := ceili(FishingHudDraw.text_w(place, s) / u) + 2 * PAD
		var th := TAG_H
		tag_rect = Rect2i(tag_x(), art_rect.size.y - th, tw, th)
		FishingHudDraw.panel(
			self, Rect2(Vector2(tag_rect.position) * u, Vector2(tag_rect.size) * u), u
		)
		var base := float(tag_rect.position.y + PAD + SMALL_CAP) * u
		FishingHudDraw.text(
			self,
			Vector2(float(tag_rect.position.x + PAD) * u, base),
			place,
			s,
			FishingPalette.HUD_DIM
		)


## The zone tag's x (art px from the rect's left): right of the two-box width, always.
static func tag_x() -> int:
	return panel_size(true).x + TAG_GAP


## The local rider's FTP (200 W without a rider).
func r_ftp() -> float:
	var r := FishingHudModel.own_rider(game)
	return r.ftp if r != null else 200.0
