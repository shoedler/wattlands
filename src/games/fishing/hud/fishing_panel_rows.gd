class_name FishingPanelRows
extends RefCounted
## The rows the boat's panels share (the fight panel, the jig panel; the crew strips take the
## metrics and the same colours), drawn on the art grid in HUD px from a panel's origin `o`:
## the metrics (width, padding, row heights), right-aligned text, the label row over the big
## numbers (a value in the text colour at the left, the watts now at the right) and the cadence
## row (the rpm, a bar with the band lit and a marker at the cadence now, the band's limits
## centred under its edges).

const W := 128
const PAD := 3
const CAP := 7
const BIG_CAP := 14
const BAR_ROWS := 4
const CAD_ROWS := 6
## Now is "on target" within this share of it; the graph shades target +/- the same.
const NOW_BAND := 0.05
## The row the cadence row's cue text takes under the band's limits.
const CUE_ROW := CAP + 2
## The cadence bar's scale (rpm): CAD_MARGIN either side of the band (CAD_MIN .. CAD_MAX
## without one).
const CAD_MIN := 50.0
const CAD_MAX := 120.0
const CAD_MARGIN := 25.0


static func u_of(s: float) -> float:
	return float(FishingHudDraw.unit(s))


## `t` right-aligned to the panel's inner edge with its baseline on row `y`.
static func right(
	c: CanvasItem, o: Vector2, y: int, t: String, s: float, col: Color, big: bool = false
) -> void:
	var u := u_of(s)
	var tw := FishingHudDraw.text_w(t, s, big)
	var at := Vector2(o.x + float(W - PAD) * u - tw, o.y + float(y) * u)
	FishingHudDraw.text(c, at, t, s, col, big)


## True when `power` is more than NOW_BAND off `target` (a target of 0 is never off).
static func off_target(power: float, target: float) -> bool:
	return target > 0.0 and absf(power - target) > target * NOW_BAND


## "label value unit" on one baseline from `at` (the baseline's left end, HUD px): the label and the
## unit dim, the value in `col` (bright to hold, dim or the accent for "now"). Returns the width.
static func pair(
	c: CanvasItem, at: Vector2, label: String, value: String, unit: String, s: float, col: Color
) -> float:
	var x := FishingHudDraw.text(c, at, label + " ", s, FishingPalette.HUD_DIM)
	x += FishingHudDraw.text(c, at + Vector2(x, 0), value, s, col)
	x += FishingHudDraw.text(c, at + Vector2(x, 0), " " + unit, s, FishingPalette.HUD_DIM)
	return x


## The width pair() takes.
static func pair_w(label: String, value: String, unit: String, s: float) -> float:
	return FishingHudDraw.text_w(label + " " + value + " " + unit, s)


## The label row on baseline `y` (`labels` [left, right]: "Target" and "now", both dim) over the
## big numbers: `left` [value, unit]: the value big in the text colour with its dim unit after it,
## and the watts now at the right, big in `now_col` with the dim watts unit.
static func numbers(
	c: CanvasItem,
	game: FishingGame,
	o: Vector2,
	y: int,
	s: float,
	labels: Array,
	left: Array,
	now_value: String,
	now_col: Color
) -> void:
	var u := u_of(s)
	var dim := FishingPalette.HUD_DIM
	FishingHudDraw.text(c, o + Vector2(PAD, y) * u, str(labels[0]), s, dim)
	right(c, o, y, str(labels[1]), s, dim)
	y += 2 + BIG_CAP
	var tx := FishingHudDraw.text(
		c, o + Vector2(PAD, y) * u, str(left[0]), s, FishingPalette.HUD_TEXT, true
	)
	FishingHudDraw.text(c, o + Vector2(PAD, y) * u + Vector2(tx + u, 0), str(left[1]), s, dim)
	var watts := FishingHudModel.tr_key(game, FishingHudModel.KEY_WATTS)
	var ww := FishingHudDraw.text_w(watts, s)
	var edge := o.x + float(W - PAD) * u
	FishingHudDraw.text(c, Vector2(edge - ww, o.y + float(y) * u), watts, s, dim)
	var nw := FishingHudDraw.text_w(now_value, s, true)
	FishingHudDraw.text(
		c, Vector2(edge - ww - u - nw, o.y + float(y) * u), now_value, s, now_col, true
	)


## The cadence row with its baseline on row `y`: "91 rpm", the bar with the band lit (when
## `band` is one: y > x) and a marker at the cadence now; under it the band's limits, each
## centred on its edge (pushed apart when they would touch). Returns the baseline (HUD px) of
## the row under the limits, where a panel puts its own text.
static func cadence(
	c: CanvasItem, game: FishingGame, o: Vector2, y: int, s: float, cad: float, band: Vector2
) -> Vector2:
	var u := u_of(s)
	var dim := FishingPalette.HUD_DIM
	var x := FishingHudDraw.text(c, o + Vector2(PAD, y) * u, str(roundi(cad)), s)
	var rpm := " " + FishingHudModel.tr_key(game, FishingHudModel.KEY_RPM)
	x += FishingHudDraw.text(c, o + Vector2(PAD, y) * u + Vector2(x, 0), rpm, s, dim)
	var bx := PAD + ceili(x / u) + 4
	var bw := W - PAD - bx
	var top := y - CAP + (CAP - CAD_ROWS) / 2 - 1
	var has_band := band.y > band.x
	var lo := band.x - CAD_MARGIN if has_band else CAD_MIN
	var hi := band.y + CAD_MARGIN if has_band else CAD_MAX
	var track := Rect2(o + Vector2(bx, top) * u, Vector2(bw, CAD_ROWS) * u)
	c.draw_rect(track, FishingPalette.HUD_TRACK)
	var base := o + Vector2(0, y + 3 + CAP) * u
	if has_band:
		var a := cad_col(band.x, lo, hi, bw)
		var b := cad_col(band.y, lo, hi, bw)
		var lit := Rect2(o + Vector2(bx + a, top) * u, Vector2(b - a + 1, CAD_ROWS) * u)
		c.draw_rect(lit, FishingPalette.SURFACE)
		var la := str(roundi(band.x))
		var lb := str(roundi(band.y))
		var law := ceili(FishingHudDraw.text_w(la, s) / u)
		var lbw := ceili(FishingHudDraw.text_w(lb, s) / u)
		var xa := bx + a - law / 2
		var xb := bx + b - lbw / 2 + 1
		var gap := xb - (xa + law) - 2
		if gap < 0:
			xa += gap / 2 - 1
			xb -= gap / 2 - 1
		FishingHudDraw.text(c, base + Vector2(float(xa) * u, 0), la, s, dim)
		FishingHudDraw.text(c, base + Vector2(float(xb) * u, 0), lb, s, dim)
	var m := cad_col(cad, lo, hi, bw)
	c.draw_rect(
		Rect2(o + Vector2(bx + m, top - 1) * u, Vector2(1, CAD_ROWS + 2) * u), FishingPalette.FOAM
	)
	return base + Vector2(0, CUE_ROW) * u


## The cadence bar's column (0 .. `w` - 1) of `rpm` on the `lo` .. `hi` scale.
static func cad_col(rpm: float, lo: float, hi: float, w: int) -> int:
	return clampi(roundi((rpm - lo) / maxf(hi - lo, 1.0) * float(w - 1)), 0, w - 1)
