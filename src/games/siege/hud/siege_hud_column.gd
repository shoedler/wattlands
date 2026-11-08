class_name SiegeHudColumn
extends SiegeHudCtl
## The right column, top to bottom: the gate plate (its number on a filled chip and the frame red
## when low) with the tar row under it, the gold plate (NUM in waves, KEY while the shop is open),
## the stations card (your own row in bronze, the hot station as a thin red bar on the left edge,
## each rider's shape and hollow pegs for the room left, the coupling bar while you reconnect) and
## the Overdrive plate (ready, prompt, active, recharging, or closed with its honest reason).
## Routing stays on the controls (left, right, up, down, swap). Pressing the Overdrive plate sends
## the same intent as ability_1; only that plate takes the mouse, and only when a press would start
## Overdrive.

## Ends on the base's middle row, so on a flex canvas the column stays at the top right. Its tallest
## content (the shop's gold and a coupling bar at once, for a moment) runs 5 px past the rect, over
## nothing.
const RECT := Rect2i(804, 8, 150, 262)
const W := 148
const FORT_H := 68
const GOLD_Y := 70
const GOLD_H := 24
const GOLD_H_BIG := 36
const ROW_H := 17
const STATIONS_HEAD := 23
const COUPLING_H := 13
const OD_H := 36

## The Overdrive plate in art px of this Control, as of the last refresh.
var od_rect: Rect2i = Rect2i()
## Where the local rider still is while it couples (-1: not known yet).
var _here: int = -1


func _init() -> void:
	super._init()
	mouse_filter = Control.MOUSE_FILTER_STOP


func build() -> Dictionary:
	var s := st()
	var r := own()
	var tx := SiegeHudModel.strings_of(game)
	if r != null and (_here < 0 or r.reconnect_s <= 0.0):
		_here = r.target
	var coupling := -1.0
	if r != null and r.reconnect_s > 0.0:
		var full := maxf(s.content.num("reconnect_s", 2.0), 0.01)
		coupling = 1.0 - clampf(r.reconnect_s / full, 0.0, 1.0)
	var rows := SiegeHudModel.station_rows(s, tx, r, _here)
	for row in rows:
		var looks: Array[Dictionary] = []
		for slot: int in row["riders"]:
			looks.append(SiegeHudModel.look_of(game, slot))
		row["looks"] = looks
	var out := SiegeHudModel.fort_face(s, r)
	out["rows"] = rows
	out["coupling"] = coupling
	out["od"] = SiegeHudModel.overdrive_face(game)
	var stations_y := GOLD_Y + (GOLD_H_BIG if bool(out["gold_big"]) else GOLD_H) + 2
	var od_y := stations_y + _stations_h(coupling) + 2
	out["stations_y"] = stations_y
	out["od_y"] = od_y
	od_rect = Rect2i(0, od_y, W, OD_H)
	return out


static func _stations_h(coupling: float) -> int:
	return STATIONS_HEAD + ROW_H * SiegeIds.STATION_COUNT + (COUPLING_H if coupling >= 0.0 else 0)


func paint() -> void:
	_fort()
	_gold()
	_stations(int(model["stations_y"]))
	_overdrive(int(model["od_y"]))


func _fort() -> void:
	var low := bool(model["low"])
	D.plate(self, 0, 0, W, FORT_H, low)
	D.ansata(self, 8, 6, SiegeHudModel.strings_of(game).t("SIEGE_HUD_GATE"))
	var limit := "/%d" % int(model["gate_max"])
	SiegeHudType.draw_r(self, limit, W - 7, 19, "LABEL", D.DIM)
	var gr := W - 7 - SiegeHudType.width(limit, "LABEL") - 2
	var gate := str(int(model["gate"]))
	if low:
		var gw := SiegeHudType.width(gate, "KEY28")
		D.rect(self, gr - gw - 3, 3, gw + 6, 28 + D.GLYPH_CHIP_PAD * 2, D.ALARM)
	SiegeHudType.draw_r(self, gate, gr, 3 + D.GLYPH_CHIP_PAD, "KEY28", D.TEXT)
	D.bar(self, 7, 37, W - 14, 3, float(model["gate_frac"]), D.ALARM if low else D.STONE)
	var tx := SiegeHudModel.strings_of(game)
	SiegeHudType.draw(self, tx.t("SIEGE_HUD_TAR"), 7, 44, "LABEL", D.BRONZE_HI)
	var curtain := int(model["curtain"])
	var cut := D.TEXT if curtain > 0 else D.DIM
	var end := SiegeHudType.draw(self, str(curtain), 36, 41, "NUM", cut)
	SiegeHudType.draw(self, "/%d" % int(model["curtain_max"]), end + 2, 46, "LABEL", D.DIM)
	var litres := tx.t("SIEGE_HUD_LITRES", [int(model["litres"])])
	SiegeHudType.draw_r(self, litres, W - 7, 46, "LABEL", D.DIM)
	var frac := float(model["curtain_frac"])
	D.bar(self, 7, 58, W - 14, 4, frac, D.PITCH)
	if curtain > 0:
		D.rect(self, 7, 58, roundf((W - 14) * clampf(frac, 0.0, 1.0)), 1, D.BRONZE_HI)


func _gold() -> void:
	var big := bool(model["gold_big"])
	var h := GOLD_H_BIG if big else GOLD_H
	var held := int(model["held"])
	D.plate(self, 0, GOLD_Y, W, h)
	var label := SiegeHudModel.strings_of(game).t("SIEGE_HUD_GOLD")
	# with gold on the receipt the label rides high and the held sum sits under it
	var top := GOLD_Y + 6 if held > 0 and big else GOLD_Y + floori((h - 9) / 2.0)
	D.icon(self, "denarius", 8, top, D.GOLD)
	SiegeHudType.draw(self, label, 22, top, "LABEL", D.GOLD)
	if held > 0 and big:
		var on := SiegeHudModel.strings_of(game).t("SIEGE_HUD_ON_RECEIPT", [held])
		SiegeHudType.draw(self, on, 8, GOLD_Y + 21, "LABEL", D.DIM)
	var face := "KEY" if big else "NUM"
	var cap := 24 if big else 14
	var at := GOLD_Y + floori((h - cap) / 2.0)
	SiegeHudType.draw_r(self, str(int(model["gold"])), W - 7, at, face, D.GOLD)


func _stations(y: int) -> void:
	var coupling := float(model["coupling"])
	D.plate(self, 0, y, W, _stations_h(coupling))
	var tx := SiegeHudModel.strings_of(game)
	D.ansata(self, 8, y + 4, tx.t("SIEGE_HUD_ROUTE"))
	SiegeHudType.draw_r(self, "< >", W - 7, y + 8, "LABEL", D.DIM)
	var rows: Array = model["rows"]
	for i in rows.size():
		_row(y + STATIONS_HEAD + i * ROW_H, rows[i])
	if coupling >= 0.0:
		var by := y + STATIONS_HEAD + ROW_H * rows.size()
		SiegeHudType.draw(self, tx.t("SIEGE_HUD_CONNECTING"), 7, by, "LABEL", D.BRONZE_HI)
		D.bar(self, 76, by + 2, W - 83, 5, coupling, D.BRONZE_HI)


func _row(ry: int, row: Dictionary) -> void:
	var here := bool(row["mine"])
	if here:
		D.rect(self, 3, ry - 2, W - 6, ROW_H - 1, D.BRONZE_LO)
		D.rect(self, 3, ry - 2, 2, ROW_H - 1, D.BRONZE_HI)
	elif bool(row["going"]):
		D.rect(self, 3, ry - 2, 2, ROW_H - 1, D.BRONZE_HI)
	if bool(row["hot"]) and not here:
		D.rect(self, 3, ry - 1, 2, ROW_H - 3, D.ALARM)
	D.icon(self, str(row["icon"]), 6, ry, D.TEXT if here else D.STONE)
	var cap := int(row["cap"])
	var room := W - 6 - cap * 8 - 21 - 2
	var row_name := SiegeHudType.fit(str(row["name"]), "LABEL", room)
	SiegeHudType.draw(self, row_name, 21, ry + 2, "LABEL", D.TEXT)
	var looks: Array = row["looks"]
	for c in cap:
		var px := W - 6 - (cap - c) * 8
		if c < looks.size():
			D.shape(self, str(looks[c]["shape"]), px, ry + 2, looks[c]["color"])
		else:
			D.icon(self, "peg", px + 1, ry + 3, D.DIM)


func _overdrive(y: int) -> void:
	var o: Dictionary = model["od"]
	var mode := str(o["mode"])
	var lit := mode == SiegeHudModel.OD_PROMPT or mode == SiegeHudModel.OD_ACTIVE
	D.plate(self, 0, y, W, OD_H, false, D.LIT if lit else D.WAX)
	D.rect(self, 8, y + 7, 3, 22, D.BRONZE_LO)
	D.rect(self, 6, y + 23 if mode == SiegeHudModel.OD_ACTIVE else y + 7, 7, 4, D.BRONZE_HI)
	SiegeHudType.draw(self, str(o["top"]), 18, y + 7, "LABEL", D.GOLD if lit else D.TEXT)
	var sub := SiegeHudType.fit(str(o["sub"]), "LABEL", W - 18 - 6)
	SiegeHudType.draw(self, sub, 18, y + 18, "LABEL", D.TEXT if lit else D.DIM)
	var fill := float(o["fill"])
	if fill > 0.0 and fill < 1.0:
		D.bar(self, 18, y + 30, 122, 2, fill, D.GOLD)


## Only the Overdrive plate, and only when a press would start it, takes the mouse.
func _has_point(point: Vector2) -> bool:
	if model.is_empty() or not bool((model["od"] as Dictionary)["enabled"]):
		return false
	return Rect2(od_rect).has_point(point / u())


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		press_overdrive()
		accept_event()


## The plate's press: the same intent as ability_1 (the rules decide).
func press_overdrive() -> void:
	if game != null and game.ctx != null and game.ctx.intents != null:
		game.ctx.intents.send(SiegeIntents.overdrive(SiegeIds.VIA_BUTTON))
