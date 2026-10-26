class_name FishingFightPanel
extends FishingHudControl
## The fight panel (mockup A1), one HUD panel just under the local boat, on the side away from
## the fish: the species and the line out, a reel-in bar (FishingRiderState.reel: how much of
## the line is reeled in, consistent with the metres shown); the target watts and the watts now,
## big (now in the accent when it is more than NOW_BAND off the target), with %FTP; the cadence
## on a bar with the band lit, a marker at the cadence now and the strain and slack cues at its
## ends (filling up, in the accent with a frame past ALERT_AT); the band's limits under it; and a
## 30 s power graph with the target band shaded. In the Landing a slim panel in the same place
## shows the gaff meter (Sprint! then Easy spin, a star for a trophy). Its rect is the whole
## view; the panel follows the boat (FishingView's model).

const W := 128
const PAD := 3
const CAP := 7
const BIG_CAP := 14
const BAR_ROWS := 4
const CAD_ROWS := 6
const CUE_W := 3
const CUE_ROWS := 8
const GRAPH_ROWS := 18
## The panel's top under the surface row, and how far it reaches past the boat's pivot toward
## the fish.
const BELOW_SURFACE := 12
const OVER_PIVOT := 30
## Now is "on target" within this share of it; the graph shades target +/- the same.
const NOW_BAND := 0.05
const ALERT_AT := 0.75
const GRAPH_S := 30.0
## The graph's range as shares of the target.
const GRAPH_TOP := 1.3
const GRAPH_BOTTOM := 0.6
## The cadence bar's scale (rpm) reaches at least this far round the band.
const CAD_MIN := 50.0
const CAD_MAX := 120.0
const CAD_MARGIN := 15.0

var fish: Dictionary = {}
var gaff: Dictionary = {}
var numbers: Dictionary = {}
var band: Vector2 = Vector2.ZERO
var strain: float = 0.0
var slack: float = 0.0
var trace: FishingPowerTrace = FishingPowerTrace.new(GRAPH_S)
## Where the panel sits (art px; Rect2i() when hidden; tests read it).
var panel_rect: Rect2i = Rect2i()
var _anchor: Vector2 = Vector2(-1, -1)
var _fish_left: bool = true


static func make(p_game: FishingGame, rect: Rect2i) -> FishingFightPanel:
	var p := FishingFightPanel.new()
	p.game = p_game
	p.name = "FishingFightPanel"
	p.place_at(rect)
	return p


## The panel's height (art px): the fight panel, or the Landing's slim one with `landing`.
static func panel_h(landing: bool = false) -> int:
	if landing:
		return PAD + CAP + 3 + BAR_ROWS + PAD
	return (
		PAD + CAP + 3 + BAR_ROWS + 4 + CAP + 2 + BIG_CAP + 5 + CAP + 3 + CAP + 4 + GRAPH_ROWS + PAD
	)


func refresh() -> void:
	var r := FishingHudModel.own_rider(game)
	fish = FishingHudModel.fish_row(game, r)
	gaff = FishingHudModel.gaff(r)
	numbers = local_numbers(r)
	var fighting := bool(fish.get("visible", false)) and r.action == FishingConst.A_FIGHT
	trace.add(float(numbers["t"]), float(numbers["power"]), float(numbers["target"]))
	band = Vector2(r.band_lo, r.band_hi) if r != null else Vector2.ZERO
	strain = r.strain if fighting else 0.0
	slack = r.slack if fighting else 0.0
	_anchor = Vector2(-1, -1)
	var v := view()
	if r != null and v != null:
		var boat: Variant = (v.model.get("boats", {}) as Dictionary).get(r.slot)
		if boat is Vector2:
			_anchor = boat
			var mouth: Variant = (v.model.get("mouth", {}) as Dictionary).get(r.slot)
			_fish_left = not (mouth is Vector2) or (mouth as Vector2).x < _anchor.x


## The panel's rect (art px) for a panel `h` rows tall at the boat.
func place_panel(h: int) -> Rect2i:
	var aw := art_rect.size.x
	var x := (aw - W) / 2
	if _anchor.x >= 0.0:
		x = int(_anchor.x) - OVER_PIVOT if _fish_left else int(_anchor.x) + OVER_PIVOT - W
	x = clampi(x, 4, maxi(aw - W - 4, 4))
	return Rect2i(x, FishingScenery.SURF_Y + BELOW_SURFACE, W, h)


func _draw() -> void:
	panel_rect = Rect2i()
	var s := k()
	var u := float(FishingHudDraw.unit(s))
	if bool(gaff.get("visible", false)):
		_draw_gaff(s, u)
	elif FishingHudModel.fight_panel_up(game, FishingHudModel.own_rider(game)):
		_draw_fight(s, u)


func _draw_gaff(s: float, u: float) -> void:
	panel_rect = place_panel(panel_h(true))
	var o := Vector2(panel_rect.position) * u
	FishingHudDraw.panel(self, Rect2(o, Vector2(panel_rect.size) * u), u)
	var label := FishingHudModel.tr_key(game, str(gaff["phase"]))
	FishingHudDraw.text(self, o + Vector2(PAD, PAD + CAP) * u, label, s, FishingHudDraw.GAFF)
	var bar := Rect2(o + Vector2(PAD, PAD + CAP + 3) * u, Vector2(W - 2 * PAD, BAR_ROWS) * u)
	FishingHudDraw.bar(self, bar, float(gaff["fill"]), FishingHudDraw.GAFF, false, u)
	var star_at := o + Vector2(W - PAD - 5, PAD) * u
	FishingHudDraw.pixels(self, FishingHudDraw.STAR, star_at, u, FishingPalette.FOAM)


func _draw_fight(s: float, u: float) -> void:
	panel_rect = place_panel(panel_h())
	var o := Vector2(panel_rect.position) * u
	var inner := float(W - 2 * PAD) * u
	FishingHudDraw.panel(self, Rect2(o, Vector2(panel_rect.size) * u), u)
	var y := PAD + CAP
	var text := FishingPalette.HUD_TEXT
	var dim := FishingPalette.HUD_DIM
	FishingHudDraw.text(self, o + Vector2(PAD, y) * u, str(fish["name"]), s, text)
	var dist := FishingHudModel.tr_key(game, FishingHudModel.KEY_DISTANCE, [str(fish["d_m"])])
	_right(o, y, dist, s, text, false)
	y += 3
	var reel := Rect2(o + Vector2(PAD, y) * u, Vector2(inner, BAR_ROWS * u))
	FishingHudDraw.bar(self, reel, float(fish["reel"]), FishingHudDraw.STAMINA, false, u)
	y += BAR_ROWS + 4 + CAP
	FishingHudDraw.text(
		self,
		o + Vector2(PAD, y) * u,
		FishingHudModel.tr_key(game, FishingHudModel.KEY_TARGET),
		s,
		dim
	)
	var now := FishingHudModel.tr_key(game, FishingHudModel.KEY_NOW)
	_right(o, y, "%d%%  %s" % [roundi(float(numbers["pct"])), now], s, dim, false)
	y += 2 + BIG_CAP
	var target := float(numbers["target"])
	var power := float(numbers["power"])
	var off := target > 0.0 and absf(power - target) > target * NOW_BAND
	var watts := FishingHudModel.tr_key(game, FishingHudModel.KEY_WATTS)
	var tx := FishingHudDraw.text(self, o + Vector2(PAD, y) * u, str(roundi(target)), s, text, true)
	FishingHudDraw.text(self, o + Vector2(PAD, y) * u + Vector2(tx + u, 0), watts, s, dim)
	var ww := FishingHudDraw.text_w(watts, s)
	var right := o.x + float(W - PAD) * u
	FishingHudDraw.text(self, Vector2(right - ww, o.y + float(y) * u), watts, s, dim)
	var now_txt := str(roundi(power))
	var nw := FishingHudDraw.text_w(now_txt, s, true)
	var now_col := FishingHudDraw.ALERT if off else text
	FishingHudDraw.text(
		self, Vector2(right - ww - u - nw, o.y + float(y) * u), now_txt, s, now_col, true
	)
	y += 5 + CAP
	_draw_cadence(o, y, s, u)
	y += 3 + CAP + 4
	var g := Rect2(o + Vector2(PAD, y) * u, Vector2(inner, GRAPH_ROWS * u))
	# zoomed round the target, so the band and the wobble read
	var mid := target if target > 0.0 else maxf(trace.peak(), 100.0)
	var top_w := mid * GRAPH_TOP
	var bottom_w := mid * GRAPH_BOTTOM
	FishingHudDraw.graph(self, g, trace, top_w, u, NOW_BAND, false, FishingPalette.FOAM, bottom_w)


## The cadence row with its baseline on row `y`: "91 rpm", the bar with the band, the marker and
## the strain and slack cues, the band's limits under it.
func _draw_cadence(o: Vector2, y: int, s: float, u: float) -> void:
	var cad := float(numbers["cadence"])
	var x := FishingHudDraw.text(self, o + Vector2(PAD, y) * u, str(roundi(cad)), s)
	var rpm := " " + FishingHudModel.tr_key(game, FishingHudModel.KEY_RPM)
	x += FishingHudDraw.text(
		self, o + Vector2(PAD, y) * u + Vector2(x, 0), rpm, s, FishingPalette.HUD_DIM
	)
	var bx := PAD + ceili(x / u) + 4
	var bw := W - PAD - bx
	var top := y - CAP + (CAP - CAD_ROWS) / 2 - 1
	var lo := minf(CAD_MIN, band.x - CAD_MARGIN) if band.x > 0.0 else CAD_MIN
	var hi := maxf(CAD_MAX, band.y + CAD_MARGIN) if band.y > 0.0 else CAD_MAX
	var track_x := bx + CUE_W + 1
	var track_w := bw - 2 * (CUE_W + 1)
	var track := Rect2(o + Vector2(track_x, top) * u, Vector2(track_w, CAD_ROWS) * u)
	self.draw_rect(track, FishingPalette.HUD_TRACK)
	if band.y > band.x:
		var a := cad_col(band.x, lo, hi, track_w)
		var b := cad_col(band.y, lo, hi, track_w)
		var lit := Rect2(o + Vector2(track_x + a, top) * u, Vector2(b - a + 1, CAD_ROWS) * u)
		self.draw_rect(lit, FishingPalette.SURFACE)
		var la := str(roundi(band.x))
		var lb := str(roundi(band.y))
		var base := o + Vector2(0, y + 3 + CAP) * u
		var law := FishingHudDraw.text_w(la, s)
		var lo_at := base + Vector2(float(track_x + a) * u - law - u, 0)
		FishingHudDraw.text(self, lo_at, la, s, FishingPalette.HUD_DIM)
		var hi_at := base + Vector2(float(track_x + b + 2) * u, 0)
		FishingHudDraw.text(self, hi_at, lb, s, FishingPalette.HUD_DIM)
	var m := cad_col(cad, lo, hi, track_w)
	self.draw_rect(
		Rect2(o + Vector2(track_x + m, top - 1) * u, Vector2(1, CAD_ROWS + 2) * u),
		FishingPalette.FOAM
	)
	_cue(o + Vector2(bx, top - 1) * u, strain, FishingHudDraw.STRAIN, u)
	_cue(o + Vector2(bx + bw - CUE_W, top - 1) * u, slack, FishingHudDraw.SLACK, u)


## A strain or slack cue at `at` (HUD px): a CUE_W x CUE_ROWS meter filling up with `fill`, in
## the accent with a frame past ALERT_AT.
func _cue(at: Vector2, fill: float, col: Color, u: float) -> void:
	var r := Rect2(at, Vector2(CUE_W, CUE_ROWS) * u)
	var alert := fill > ALERT_AT
	FishingHudDraw.bar(self, r, fill, FishingHudDraw.ALERT if alert else col, true, u)


## `t` right-aligned to the panel's inner edge with its baseline on row `y`.
func _right(o: Vector2, y: int, t: String, s: float, col: Color, big: bool) -> void:
	var tw := FishingHudDraw.text_w(t, s, big)
	var at := Vector2(o.x + float(W - PAD) * u_of(s) - tw, o.y + float(y) * u_of(s))
	FishingHudDraw.text(self, at, t, s, col, big)


static func u_of(s: float) -> float:
	return float(FishingHudDraw.unit(s))


## The cadence bar's column (0 .. `w` - 1) of `rpm` on the `lo` .. `hi` scale.
static func cad_col(rpm: float, lo: float, hi: float, w: int) -> int:
	return clampi(roundi((rpm - lo) / maxf(hi - lo, 1.0) * float(w - 1)), 0, w - 1)
