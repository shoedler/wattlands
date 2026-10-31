class_name SiegeHudCockpit
extends SiegeHudCtl
## The cockpit, the one place a rider on the rivet looks (bottom centre): the interval clock, the
## watts and the cadence side by side at 72 px, one instruction, what comes next, and the optional
## heart rate cell. No sensor: no cell, and the plate is NARROW wide instead of WIDE. All of it
## comes from SiegeCockpitModel. The plaque above the frame says whose it is and where they ride.

const X := 479
const Y := 16
const WIDE := 404
const NARROW := 344
const H := 112
## The art rect: the plate, its shadow and the plaque above it.
## Starts just left of the base's middle, so it stays centred on a flex canvas and, at the narrowest,
## ends up right of the road's east hairpin.
const RECT := Rect2i(479, 404, 408, 130)

const CAP_Y := Y + 6
const NUM_Y := Y + 21
const GAUGE_Y := Y + 60
const RULE_TOP := Y + 6
const RULE_H := 58
## The clock's column is 4 px wider than the mock's so COOL-DOWN clears its rule; the watts give
## them back, so the narrow plate keeps its width.
const CLOCK_W := 96
const WATTS_W := 128
const CAD_W := 86
const CAD_FROM := 30.0
const CAD_SPAN := 120.0

var cockpit := SiegeCockpitModel.new()


func set_telemetry(t: Telemetry) -> void:
	super.set_telemetry(t)
	cockpit.feed(t)


func build() -> Dictionary:
	var hl := hud_layer()
	if hl != null:
		cockpit.wkg_override_kg = hl.wkg_weight_kg
	return cockpit.face(game)


## The plate's width now.
func plate_w() -> int:
	return (
		NARROW if int(model.get("hr", HudRiderNumbers.HR_NONE)) == HudRiderNumbers.HR_NONE else WIDE
	)


func paint() -> void:
	var w := plate_w()
	D.plate(self, X - RECT.position.x, Y, w, H)
	_tag(w)
	var x := 0
	_num_cell(x + 9, "clock_cap", "clock", D.GOLD if bool(model["clock_soon"]) else D.TEXT)
	x = 9 + CLOCK_W
	_rule(x)
	x = _watts(x + 7)
	_rule(x)
	x = _cadence(x + 7)
	if int(model["hr"]) != HudRiderNumbers.HR_NONE:
		_rule(x + 4)
		_heart(x + 10)
	_lower(w)


func _rule(x: int) -> void:
	SiegeHudDraw.rect(self, x, RULE_TOP, 1, RULE_H, SiegeHudDraw.WAX_LINE)


func _num_cell(x: int, cap_key: String, num_key: String, col: Color) -> void:
	SiegeHudType.draw(self, str(model[cap_key]), x, CAP_Y, "BODY", SiegeHudDraw.DIM)
	SiegeHudType.draw(self, str(model[num_key]), x, NUM_Y, "KEY36", col)


func _watts(x: int) -> int:
	var stale := int(model["w"]) < 0
	var col := D.DIM if stale else D.TEXT
	SiegeHudType.draw(self, str(model["target_cap"]), x, CAP_Y, "BODY", D.DIM)
	SiegeHudType.draw(self, str(model["w_text"]), x, NUM_Y, "KEY36", col)
	var side := x + 78
	SiegeHudType.draw(self, str(model["pct_text"]), side, NUM_Y + 1, "NUM", col)
	var state := int(model["state"])
	if state != HudRiderNumbers.IN_BAND and not stale:
		var under := state == HudRiderNumbers.UNDER
		D.icon(self, "up" if under else "down", side + 34, NUM_Y + 3, D.UNDER if under else D.AMBER)
	if str(model["wkg"]) != "":
		var wkg := SiegeHudModel.strings_of(game).t("SIEGE_HUD_WKG", [str(model["wkg"])])
		SiegeHudType.draw(self, wkg, side, NUM_Y + 22, "LABEL", D.DIM)
	# the band, flat, with a needle
	var scale_w := maxf(float(model["scale"]), 1.0)
	D.rect(self, x, GAUGE_Y, WATTS_W, 5, D.TRACK)
	var band: Vector2 = model["band"]
	if band != Vector2.ZERO:
		var bx := roundi(WATTS_W * minf(band.x / scale_w, 1.0))
		var bw := roundi(WATTS_W * minf((band.y - band.x) / scale_w, 1.0))
		D.rect(self, x + bx, GAUGE_Y, mini(bw, WATTS_W - bx), 5, D.VERD)
	if not stale:
		var nx := mini(WATTS_W - 2, roundi(WATTS_W * float(model["w"]) / scale_w))
		D.rect(self, x + nx, GAUGE_Y - 2, 2, 9, D.TEXT)
	return x + WATTS_W + 5


func _cadence(x: int) -> int:
	var low := bool(model["cad_low"])
	var stale := bool(model["cad_stale"])
	if low:
		D.rect(self, x - 2, NUM_Y - D.GLYPH_CHIP_PAD, 66, 36 + D.GLYPH_CHIP_PAD * 2, D.ALARM)
	SiegeHudType.draw(self, str(model["cad_cap"]), x, CAP_Y, "BODY", D.DIM)
	SiegeHudType.draw(self, str(model["cad_text"]), x, NUM_Y, "KEY36", D.DIM if stale else D.TEXT)
	if low:
		D.icon(self, "up", x + 54, NUM_Y + 1, D.TEXT)
	elif bool(model["cad_nudge"]):
		D.icon(self, "up", x + 54, NUM_Y + 1, D.UNDER)
	D.rect(self, x, GAUGE_Y, CAD_W, 5, D.TRACK)
	var band: Vector2 = model["cband"]
	var from := roundi(CAD_W * (band.x - CAD_FROM) / CAD_SPAN)
	var span := roundi(CAD_W * (band.y - band.x) / CAD_SPAN)
	D.rect(self, x + from, GAUGE_Y, span, 5, D.VERD)
	if not stale:
		var at := clampi(roundi(CAD_W * (float(model["cad"]) - CAD_FROM) / CAD_SPAN), 0, CAD_W - 2)
		D.rect(self, x + at, GAUGE_Y - 2, 2, 9, D.TEXT)
	return x + CAD_W


func _heart(x: int) -> void:
	var live := int(model["hr"]) == HudRiderNumbers.HR_LIVE
	D.icon(self, "heart", x, CAP_Y + 3, D.HEART)
	var bpm := SiegeHudModel.strings_of(game).t("SIEGE_HUD_BPM")
	SiegeHudType.draw(self, bpm, x + 9, CAP_Y, "BODY", D.DIM)
	var col := D.TEXT if live else D.DIM
	SiegeHudType.draw(self, str(model["hr_text"]), x, NUM_Y + 6, "KEY", col)


func _lower(w: int) -> void:
	var tx := SiegeHudModel.strings_of(game)
	D.rect(self, 3, Y + 69, w - 6, 1, D.WAX_LINE)
	var right := w - 9
	var chip_w := 0
	if str(model["line_kind"]) == SiegeCockpitModel.LINE_NO_DATA:
		pass  # the mode is not known, and the long line needs the room
	elif bool(model["sim"]):
		chip_w = SiegeHudType.width(tx.t("SIEGE_HUD_SIM"), "LABEL") + 6
		D.chip(self, tx.t("SIEGE_HUD_SIM"), right, Y + 75, "LABEL", true, D.BRONZE, D.INK)
	else:
		chip_w = SiegeHudType.draw_r(self, tx.t("SIEGE_HUD_ERG"), right, Y + 75, "LABEL", D.DIM)
		chip_w = right - chip_w
	# one instruction, from the state; only an alarm sits on a red chip
	var line := SiegeHudType.fit(str(model["line"]), "LINE", w - 9 - 6 - chip_w - 9 - 6)
	if bool(model["line_alarm"]):
		D.chip(self, line, 9, Y + 73, "LINE")
	else:
		SiegeHudType.draw(self, line, 9, Y + 73, "LINE", D.GOLD)
	D.rect(self, 3, Y + 90, w - 6, 1, D.WAX_LINE)
	var text := str(model["next"])
	var used := _reserve_or_gear(right, tx, SiegeHudType.width(text, "BODY"))
	SiegeHudType.draw(
		self, SiegeHudType.fit(text, "BODY", right - used - 9 - 6), 9, Y + 94, "BODY", D.TEXT
	)


## The reserve (a thin bar; a number only when it matters), or the gear in SIM. A long next line on
## the narrow plate shortens the bar so its watts stay whole. Returns its width.
func _reserve_or_gear(right: int, tx: GameStrings, next_w: int) -> int:
	if bool(model["sim"]):
		var gear := str(model["gear"])
		var left := SiegeHudType.draw_r(self, gear, right, Y + 93, "NUM", D.BRONZE_HI)
		var lab := SiegeHudType.draw_r(
			self, tx.t("SIEGE_HUD_GEAR"), left - 4, Y + 96, "LABEL", D.TEXT
		)
		return right - lab
	var text := str(model["wbal_text"])
	var low := text != ""
	var used := 72
	var bar_w := 26 if low else 56
	if not low and 9 + next_w + 6 > right - used:
		used = 72 - 26
		bar_w = 30
	SiegeHudType.draw(self, tx.t("SIEGE_HUD_WPRIME"), right - used, Y + 96, "LABEL", D.DIM)
	D.bar(self, right - used + 16, Y + 99, bar_w, 3, float(model["wbal"]), D.UNDER)
	if low:
		SiegeHudType.draw_r(self, text, right, Y + 96, "LABEL", D.TEXT)
	return used


## Whose: a plaque on the frame, right-aligned, in the rider's colour and shape, with the station.
func _tag(w: int) -> void:
	var station := str(model["station"])
	var room := w - 40 - SiegeHudType.width(" · " + station, "LABEL")
	var text := "%s · %s" % [SiegeHudType.fit(str(model["name"]), "LABEL", room), station]
	var tag_w := SiegeHudType.width(text, "LABEL") + 21
	var tx := w - tag_w - 12
	SiegeHudDraw.ansata(self, tx, Y - 14, text, "LABEL", 11)
	SiegeHudDraw.shape(self, str(model["shape"]), tx + 4, Y - 10, model["color"])
