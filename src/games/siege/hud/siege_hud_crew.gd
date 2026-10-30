class_name SiegeHudCrew
extends SiegeHudCtl
## The teammate cards, top centre: teammates only (your own numbers are in the cockpit). Each hangs
## a vexillum in the rider's colour, then the rider's shape and name, raw W and %FTP, the station's
## icon, and a lamp for in band or out, or a mark (OD, a RESCUE chip, AFK). Numbers come from the
## state (the snapshot's on a client).

const RECT := Rect2i(470, 8, 278, 62)
const CARD_W := 90
const CARD_H := 60
const CARD_STEP := 92
const AFK_ALPHA := 0.45

## slot -> HudRiderNumbers: the lamps' hysteresis.
var tracks: Dictionary = {}


func build() -> Dictionary:
	return {"cards": SiegeHudModel.crew_cards(game, tracks)}


func paint() -> void:
	var cards: Array = model["cards"]
	for i in cards.size():
		_card(i * CARD_STEP, cards[i])


func _card(x: int, card: Dictionary) -> void:
	var afk := bool(card["afk"])
	var col: Color = card["color"]
	var flag := Color(col, AFK_ALPHA) if afk else col
	D.plate(self, x, 0, CARD_W, CARD_H)
	D.rect(self, x + 3, 3, CARD_W - 6, 8, flag)
	var f := x + 4
	while f < x + CARD_W - 4:
		D.rect(self, f, 11, 1, 1, flag)
		f += 3
	D.shape(self, str(card["shape"]), x + 6, 15, col)
	var name_text := SiegeHudType.fit(str(card["name"]), "LABEL", CARD_W - 22)
	SiegeHudType.draw(self, name_text, x + 16, 14, "LABEL", D.TEXT)
	var w := int(card["w"])
	var w_col := D.DIM if afk or w < 0 else D.TEXT
	var end := SiegeHudType.draw(self, "--" if w < 0 else str(w), x + 6, 26, "NUM", w_col)
	SiegeHudType.draw(self, "W", end + 2, 31, "LABEL", D.DIM)
	var pct := "--" if w < 0 else "%d%%" % int(card["pct"])
	SiegeHudType.draw_r(self, pct, x + CARD_W - 6, 31, "LABEL", D.DIM)
	D.icon(self, str(card["icon"]), x + 6, 44, D.STONE)
	_mark(x, card)


func _mark(x: int, card: Dictionary) -> void:
	var mark := str(card["mark"])
	match str(card["mark_kind"]):
		"alarm":
			D.chip(self, mark, x + CARD_W - 5, 46, "LABEL", true)
		"od":
			SiegeHudType.draw_r(self, mark, x + CARD_W - 6, 46, "LABEL", D.GOLD)
		"dim":
			SiegeHudType.draw_r(self, mark, x + CARD_W - 6, 46, "LABEL", D.DIM)
		_:
			D.rect(self, x + CARD_W - 13, 46, 7, 7, lamp_color(int(card["lamp"])))


static func lamp_color(state: int) -> Color:
	if state == HudRiderNumbers.IN_BAND:
		return SiegeHudDraw.GOOD
	return SiegeHudDraw.UNDER if state == HudRiderNumbers.UNDER else SiegeHudDraw.AMBER
