class_name FishingFightPanel
extends FishingBoatPanel
## The fight panel (mockup A1), one HUD panel just under the local boat, on the side away from
## the fish: the species and the line out, a reel-in bar (FishingRiderState.reel: how much of
## the line is reeled in, consistent with the metres shown) over a slim strip of the fish's
## stamina; the target watts and the watts now, big (the target bright, now muted and in the
## accent when it is more than NOW_BAND off); the cadence on a bar with the band lit and a
## marker at the cadence now, the band's limits centred under its edges; a row with %FTP and,
## while the line strains or goes slack off the target or the band, that word with a small
## meter at its side; and a 30 s power graph
## with the target band shaded (1.25 x FTP or the window's most at the top). In the Landing a
## slim panel in the same place shows the gaff meter (Sprint! then Easy spin, a star for a
## trophy). Its rect is the whole view; the panel follows the boat (FishingView's model). The rows
## it shares with the jig panel (the big numbers, the cadence row) are FishingPanelRows'.

const W := FishingPanelRows.W
const PAD := FishingPanelRows.PAD
const CAP := FishingPanelRows.CAP
const BIG_CAP := FishingPanelRows.BIG_CAP
const BAR_ROWS := FishingPanelRows.BAR_ROWS
const CUE_W := 3
const CUE_ROWS := 7
const GRAPH_ROWS := 18
## Now is "on target" within this share of it; the graph shades target +/- the same.
const NOW_BAND := FishingPanelRows.NOW_BAND
const ALERT_AT := 0.75
const GRAPH_S := 30.0
## The graph's top is GRAPH_FTP x FTP or the window's most; a strain or slack cue shows past
## CUE_AT.
const GRAPH_FTP := 1.25
const CUE_AT := 0.5
## The row the strain and slack cues' labels take under the band's limits.
const CUE_ROW := FishingPanelRows.CUE_ROW

var fish: Dictionary = {}
var gaff: Dictionary = {}
var numbers: Dictionary = {}
var band: Vector2 = Vector2.ZERO
var strain: float = 0.0
var slack: float = 0.0
var trace: FishingPowerTrace = FishingPowerTrace.new(GRAPH_S)


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
	# the rows top-down: title, reel bar, labels, the big numbers, the cadence row, its limits,
	# the cue labels, the graph
	var rows: Array[int] = [
		PAD, CAP, 3, BAR_ROWS, 4, CAP, 2, BIG_CAP, 5, CAP, 3, CAP, CUE_ROW, 4, GRAPH_ROWS, PAD
	]
	var out := 0
	for r in rows:
		out += r
	return out


func refresh() -> void:
	var r := FishingHudModel.own_rider(game)
	fish = FishingHudModel.fish_row(game, r)
	gaff = FishingHudModel.gaff(r)
	numbers = local_numbers(r)
	var fighting := bool(fish.get("visible", false)) and r.action == FishingConst.A_FIGHT
	trace.add(float(numbers["t"]), float(numbers["power"]), float(numbers["target"]))
	band = Vector2(r.pub_lo, r.pub_hi) if r != null else Vector2.ZERO
	strain = r.strain if fighting else 0.0
	slack = r.slack if fighting else 0.0
	track_boat(r, "mouth")


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
	FishingHudDraw.text(self, o + Vector2(PAD, y) * u, str(fish["name"]), s, text)
	var dist := FishingHudModel.tr_key(game, FishingHudModel.KEY_DISTANCE, [str(fish["d_m"])])
	FishingPanelRows.right(self, o, y, dist, s, text)
	y += 3
	# the line reeled in (fills as the fish comes in), the fish's stamina a slim strip under it
	var reel := Rect2(o + Vector2(PAD, y) * u, Vector2(inner, (BAR_ROWS - 1) * u))
	FishingHudDraw.bar(self, reel, float(fish["reel"]), FishingHudDraw.STAMINA, false, u)
	var stam := Rect2(o + Vector2(PAD, y + BAR_ROWS - 1) * u, Vector2(inner, u))
	FishingHudDraw.bar(self, stam, float(fish["stamina"]), FishingPalette.SAGE, false, u)
	y += BAR_ROWS + 4 + CAP
	var target := float(numbers["target"])
	var power := float(numbers["power"])
	# the target is the bright number to hold; now is muted, the accent when off the target
	var now_col := (
		FishingHudDraw.ALERT
		if FishingPanelRows.off_target(power, target)
		else FishingPalette.HUD_DIM
	)
	var target_label := FishingHudModel.tr_key(game, FishingHudModel.KEY_TARGET)
	var now_label := FishingHudModel.tr_key(game, FishingHudModel.KEY_NOW)
	var watts := FishingHudModel.tr_key(game, FishingHudModel.KEY_WATTS)
	FishingPanelRows.numbers(
		self,
		game,
		o,
		y,
		s,
		[target_label, now_label],
		[str(roundi(target)), watts],
		str(roundi(power)),
		now_col
	)
	y += 2 + BIG_CAP + 5 + CAP
	var base := FishingPanelRows.cadence(self, game, o, y, s, float(numbers["cadence"]), band)
	_draw_cue_row(base, s, u)
	y += 3 + CAP + CUE_ROW + 4
	var g := Rect2(o + Vector2(PAD, y) * u, Vector2(inner, GRAPH_ROWS * u))
	var top_w := graph_top(trace, r_ftp())
	FishingHudDraw.graph(self, g, trace, top_w, u, NOW_BAND, false, FishingPalette.FOAM)


## The graphs' top (W): 1.25 x FTP or the window's most, so steady power sits mid-height.
static func graph_top(tr: FishingPowerTrace, ftp: float) -> float:
	return maxf(maxf(GRAPH_FTP * ftp, tr.peak()), 100.0)


## The local rider's FTP (200 W without a rider).
func r_ftp() -> float:
	var r := FishingHudModel.own_rider(game)
	return r.ftp if r != null else 200.0


## The row under the band's limits: %FTP at the left, apart from the band's numbers, and while
## the line strains (after it) or goes slack (at the right) past CUE_AT, and the rider is off
## the target or the band, that word with a small meter, in the accent past ALERT_AT.
func _draw_cue_row(base: Vector2, s: float, u: float) -> void:
	var dim := FishingPalette.HUD_DIM
	var pct := FishingHudModel.tr_key(
		game, FishingHudModel.KEY_FTP, [roundi(float(numbers["pct"]))]
	)
	var pw := FishingHudDraw.text(self, base + Vector2(PAD * u, 0), pct, s, dim)
	var cad := float(numbers["cadence"])
	var target := float(numbers["target"])
	var on_target := target > 0.0 and absf(float(numbers["power"]) - target) <= target * NOW_BAND
	var in_band := band.y <= band.x or (cad >= band.x and cad <= band.y)
	var steady := on_target and in_band
	var meter_at := base + Vector2(0, -CAP) * u
	if strain > CUE_AT and not steady:
		var word := FishingHudModel.tr_key(game, FishingHudModel.KEY_STRAIN)
		var x0 := PAD * u + roundf(pw / u) * u + 6.0 * u
		var ww := FishingHudDraw.text(self, base + Vector2(x0, 0), word, s, _cue_col(strain))
		_cue(meter_at + Vector2(x0 + ww + u, 0), strain, FishingHudDraw.STRAIN, u)
	if slack > CUE_AT and not steady:
		var word := FishingHudModel.tr_key(game, FishingHudModel.KEY_SLACK)
		var sw := FishingHudDraw.text_w(word, s)
		var x := float(W - PAD) * u - sw
		FishingHudDraw.text(self, base + Vector2(x, 0), word, s, _cue_col(slack))
		_cue(meter_at + Vector2(x - float(CUE_W + 1) * u, 0), slack, FishingHudDraw.SLACK, u)


static func _cue_col(fill: float) -> Color:
	return FishingHudDraw.ALERT if fill > ALERT_AT else FishingPalette.HUD_DIM


## A strain or slack meter at `at` (HUD px): a CUE_W x CUE_ROWS bar filling up with `fill`, in
## the accent with a frame past ALERT_AT.
func _cue(at: Vector2, fill: float, col: Color, u: float) -> void:
	var r := Rect2(at, Vector2(CUE_W, CUE_ROWS) * u)
	var alert := fill > ALERT_AT
	FishingHudDraw.bar(self, r, fill, FishingHudDraw.ALERT if alert else col, true, u)
