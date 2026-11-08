class_name FishingCrewStrips
extends FishingHudControl
## The crew's fight strips (mockups): one slim strip per other rider with a fish on, as wide as the
## leaderboard and stacked right under it, shown during your own fight too. Rows, in the fight
## panel's metrics and colours: "name . species" with the line out at the right, a thin reel-in
## bar, then "Target N W" and, at the right, "now N W": dim on target, in the accent when more
## than NOW_BAND off. The rect is the board's column; the strips start under the board's rows.

const W := FishingPanelRows.W
const PAD := FishingPanelRows.PAD
const CAP := FishingPanelRows.CAP
const BAR_ROWS := 2
## A strip's height (art px): padding, title, a gap, the reel bar, a gap, the numbers, padding.
const H := PAD + CAP + 3 + BAR_ROWS + 4 + CAP + PAD
## The gap between the board and the first strip, and between strips (art px).
const GAP := 4
## The separator between a rider's name and the species: a middle dot.
const DOT := " · "

var strips: Array[Dictionary] = []
var rows: Array[Dictionary] = []
var time_text: String = ""
## The strips drawn last, in art px of the view (tests read them).
var strip_rects: Array[Rect2i] = []


static func make(p_game: FishingGame, rect: Rect2i) -> FishingCrewStrips:
	var c := FishingCrewStrips.new()
	c.game = p_game
	c.name = "FishingCrewStrips"
	c.place_at(rect)
	return c


## The rect's height (art px) that holds a board of `riders` rows and CREW_MAX strips.
static func rect_h(riders: int) -> int:
	var board := ceili(FishingBoard.height_px(riders, 1.0) / float(FishingHudDraw.unit(1.0)))
	return 2 + board + FishingHudModel.CREW_MAX * (GAP + H)


func refresh() -> void:
	strips = FishingHudModel.crew(game)
	rows = FishingHudModel.board(game)
	time_text = FishingHudModel.time_text(game)


func _draw() -> void:
	strip_rects.clear()
	if strips.is_empty() or game == null or game.state == null:
		return
	var s := k()
	var u := float(FishingHudDraw.unit(s))
	var x0 := floorf((size.x - FishingBoard.width_px(game, rows, time_text, s)) / u) * u
	var w := size.x - x0
	var inner := w - 2.0 * float(PAD) * u
	var y := FishingBoard.height_px(rows.size(), s) + float(GAP) * u
	var text := FishingPalette.HUD_TEXT
	for st in strips:
		var o := Vector2(x0, y)
		FishingHudDraw.panel(self, Rect2(o, Vector2(w, float(H) * u)), u)
		var at := Vector2i((o / u).round()) + art_rect.position
		strip_rects.append(Rect2i(at, Vector2i(roundi(w / u), H)))
		var base := float(PAD + CAP) * u
		var dist := FishingHudModel.tr_key(game, FishingHudModel.KEY_DISTANCE, [str(st["d_m"])])
		var dw := FishingHudDraw.text_w(dist, s)
		var room := inner - dw - 4.0 * u
		var title := fit(str(st["name"]) + DOT + str(st["species"]), room, s)
		FishingHudDraw.text(self, o + Vector2(float(PAD) * u, base), title, s, text)
		FishingHudDraw.text(self, o + Vector2(w - float(PAD) * u - dw, base), dist, s, text)
		var bar_top := o.y + float(PAD + CAP + 3) * u
		var bar := Rect2(o.x + float(PAD) * u, bar_top, inner, float(BAR_ROWS) * u)
		FishingHudDraw.bar(self, bar, float(st["reel"]), FishingHudDraw.STAMINA, false, u)
		var row_y := o.y + float(PAD + CAP + 3 + BAR_ROWS + 4 + CAP) * u
		var target := FishingHudModel.tr_key(game, FishingHudModel.KEY_CREW_TARGET, [st["target_w"]])
		FishingHudDraw.text(self, Vector2(o.x + float(PAD) * u, row_y), target, s, text)
		var now := FishingHudModel.tr_key(game, FishingHudModel.KEY_CREW_NOW, [st["now_w"]])
		var nw := FishingHudDraw.text_w(now, s)
		var col := FishingHudDraw.ALERT if bool(st["off"]) else FishingPalette.HUD_DIM
		FishingHudDraw.text(self, Vector2(o.x + w - float(PAD) * u - nw, row_y), now, s, col)
		y += float(H + GAP) * u


## `t` cut to fit `room` HUD px at draw scale `s`, with an ellipsis where it was cut.
func fit(t: String, room: float, s: float) -> String:
	if FishingHudDraw.text_w(t, s) <= room:
		return t
	var n := t.length()
	while n > 1 and FishingHudDraw.text_w(t.substr(0, n) + "…", s) > room:
		n -= 1
	return t.substr(0, n) + "…"
