class_name FishingJigPanel
extends FishingBoatPanel
## The jig panel (mockup "Jig it home"), in the fight panel's box style just under the local boat,
## on the side away from the lure, while the lure is out in Free Roam (the cast and the wait): the
## title and the line out, a bar that fills as the lure comes home, "Hold" the watts that count
## (40 % of FTP) and "now" the watts now (in the accent while under), the cadence row with the
## lure band lit, and what it does: bites come sooner (bright while the jig is on, dim while it
## is not) and that the lure recasts at the boat. SIM throughout: it asks nothing of the trainer.

const W := FishingPanelRows.W
const PAD := FishingPanelRows.PAD
const CAP := FishingPanelRows.CAP
const BIG_CAP := FishingPanelRows.BIG_CAP
const BAR_ROWS := FishingPanelRows.BAR_ROWS
const CUE_ROW := FishingPanelRows.CUE_ROW

var row: Dictionary = {}
var numbers: Dictionary = {}
var band: Vector2 = Vector2.ZERO
var _dx0: float = 0.0


static func make(p_game: FishingGame, rect: Rect2i) -> FishingJigPanel:
	var p := FishingJigPanel.new()
	p.game = p_game
	p.name = "FishingJigPanel"
	p.place_at(rect)
	return p


## The panel's height (art px): the fight panel's rows down to the cadence row's limits, then two
## text lines.
static func panel_h() -> int:
	# title, bar, labels, the big numbers, the cadence row, its limits, the two text lines
	var rows: Array[int] = [PAD, CAP, 3, BAR_ROWS, 4, CAP, 2, BIG_CAP, 5, CAP, 3, CAP, CUE_ROW]
	var out := PAD + CUE_ROW
	for r in rows:
		out += r
	return out


func refresh() -> void:
	var r := FishingHudModel.own_rider(game)
	numbers = local_numbers(r)
	_dx0 = FishingHudModel.jig_dx0(game, r, _dx0)
	row = FishingHudModel.jig_row(game, r, _dx0, float(numbers["power"]), float(numbers["cadence"]))
	band = Vector2(r.pub_lo, r.pub_hi) if r != null else Vector2.ZERO
	track_boat(r, "lure")


func _draw() -> void:
	panel_rect = Rect2i()
	if not bool(row.get("visible", false)):
		return
	var s := k()
	var u := float(FishingHudDraw.unit(s))
	panel_rect = place_panel(panel_h())
	var o := Vector2(panel_rect.position) * u
	var inner := float(W - 2 * PAD) * u
	FishingHudDraw.panel(self, Rect2(o, Vector2(panel_rect.size) * u), u)
	var y := PAD + CAP
	var text := FishingPalette.HUD_TEXT
	var dim := FishingPalette.HUD_DIM
	var title := FishingHudModel.tr_key(game, FishingHudModel.KEY_JIG)
	FishingHudDraw.text(self, o + Vector2(PAD, y) * u, title, s, text)
	var dist := FishingHudModel.tr_key(game, FishingHudModel.KEY_DISTANCE, [str(row["d_m"])])
	FishingPanelRows.right(self, o, y, dist, s, text)
	y += 3
	var bar := Rect2(o + Vector2(PAD, y) * u, Vector2(inner, BAR_ROWS * u))
	FishingHudDraw.bar(self, bar, float(row["fill"]), FishingHudDraw.STAMINA, false, u)
	y += BAR_ROWS + 4 + CAP
	var power := float(numbers["power"])
	var under := roundi(power) < int(row["hold_w"])
	var watts := FishingHudModel.tr_key(game, FishingHudModel.KEY_WATTS)
	var labels := [
		FishingHudModel.tr_key(game, FishingHudModel.KEY_JIG_HOLD),
		FishingHudModel.tr_key(game, FishingHudModel.KEY_NOW)
	]
	var now_col := FishingHudDraw.ALERT if under else dim
	FishingPanelRows.numbers(
		self, game, o, y, s, labels, [str(int(row["hold_w"])), watts + "+"], str(roundi(power)), now_col
	)
	y += 2 + BIG_CAP + 5 + CAP
	var base := FishingPanelRows.cadence(self, game, o, y, s, float(numbers["cadence"]), band)
	var jig_in := FishingHudModel.tr_key(game, FishingHudModel.KEY_JIG_IN)
	FishingHudDraw.text(self, base + Vector2(PAD * u, 0), jig_in, s, text if bool(row["on"]) else dim)
	var recast := FishingHudModel.tr_key(game, FishingHudModel.KEY_JIG_RECAST)
	FishingHudDraw.text(self, base + Vector2(PAD * u, float(CUE_ROW) * u), recast, s, dim)
