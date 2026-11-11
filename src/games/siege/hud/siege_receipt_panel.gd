class_name SiegeReceiptPanel
extends SiegeHudCtl
## The shared receipt (docs/games/siege.md 2.4 "Shop", 3 HUD), left, over the road's west loop and
## just above the shop, in breaks only: every item picked and not yet bought with its cost, who
## picked it and YES n / NO n, then the total, when it is bought ("BOUGHT WHEN THE BREAK ENDS") and
## the two rules. Everyone sees the same receipt (it comes from the snapshot). It only reads.
##
## The rect is the strip just above the shop, in the lower half of the base like the shop, so on
## every flex canvas the two move together (anchor_rect) and stay side by side. The plate is as tall
## as its rows and grows upward from the rect's bottom edge, past the rect's top (a Control draws
## outside its rect): at most MAX_H tall, which clears the session plate on the narrowest canvas
## (a test checks it).

const RECT := Rect2i(8, 270, 366, 94)
const W := 364
const HEAD_H := 46
const ROW_STEP := 34
const NOTE_H := 14
const TOTAL_H := 26
const RULES_H := 23
## The rules' two lines this far apart.
const RULE_STEP := 12
const FOOT_PAD := 5
const TEXT_X := 10
## Columns of a row's second line (art px of the plate).
const YES_X := 96
const NO_X := 140
## The coin's column, the shop's: a longer number moves its coin left, clear of the digits.
const COIN_X := W - 44
const COIN_GAP := 12
## The tallest plate: HEAD_H, MAX_ROWS rows, the total, the rules and the foot.
const MAX_H := HEAD_H + SiegeReceiptModel.MAX_ROWS * ROW_STEP + TOTAL_H + RULES_H + FOOT_PAD

var plate_h: int = 0


func _init() -> void:
	super._init()
	name = "SiegeReceiptPanel"
	visible = false


## Visible while the shop is open for the local rider.
func build() -> Dictionary:
	var s := st()
	if own() == null or not s.shop_open():
		visible = false
		return {}
	visible = true
	var out := SiegeReceiptModel.face(game)
	out["plate_h"] = plate_height(out)
	plate_h = int(out["plate_h"])
	return out


## The plate's height for `face`'s rows.
static func plate_height(face: Dictionary) -> int:
	var rows := (face["rows"] as Array).size()
	var body := rows * ROW_STEP
	if str(face["empty"]) != "":
		body = NOTE_H
	if int(face["hidden"]) > 0:
		body += NOTE_H
	return HEAD_H + body + TOTAL_H + RULES_H + FOOT_PAD


func paint() -> void:
	var h := int(model["plate_h"])
	var y := RECT.size.y - h - 2
	D.plate(self, 0, y, W, h)
	D.ansata(self, 10, y + 5, str(model["title"]))
	var bought := SiegeHudType.fit(str(model["bought"]), "LABEL", W - 2 * TEXT_X)
	SiegeHudType.draw(self, bought, TEXT_X, y + 30, "LABEL", D.BRONZE_HI)
	var at := y + HEAD_H
	var rows: Array = model["rows"]
	for row: Dictionary in rows:
		_row(at, row)
		at += ROW_STEP
	if str(model["empty"]) != "":
		SiegeHudType.draw(self, str(model["empty"]), TEXT_X, at + 1, "LABEL", D.DIM)
		at += NOTE_H
	if int(model["hidden"]) > 0:
		SiegeHudType.draw(self, str(model["more"]), TEXT_X, at + 1, "LABEL", D.DIM)
		at += NOTE_H
	D.rect(self, 8, at, W - 16, 1, D.WAX_LINE)
	SiegeHudType.draw(self, str(model["total_label"]), TEXT_X, at + 9, "BODY", D.TEXT)
	_cost(at + 9, int(model["total"]), D.GOLD)
	var rules: Array = model["rules"]
	for i in rules.size():
		var line := SiegeHudType.fit(str(rules[i]), "LABEL", W - 2 * TEXT_X)
		SiegeHudType.draw(self, line, TEXT_X, at + TOTAL_H + 1 + i * RULE_STEP, "LABEL", D.DIM)


func _row(ry: int, row: Dictionary) -> void:
	_cost(ry, int(row["cost"]), D.GOLD)
	var text := SiegeHudType.fit(str(row["name"]), "BODY", COIN_X - COIN_GAP - TEXT_X)
	SiegeHudType.draw(self, text, TEXT_X, ry, "BODY", D.TEXT)
	var low := ry + 17
	var by := SiegeHudType.fit(str(row["by"]), "LABEL", YES_X - 6 - TEXT_X)
	SiegeHudType.draw(self, by, TEXT_X, low, "LABEL", D.GOLD if bool(row["mine"]) else D.DIM)
	var tx := SiegeHudModel.strings_of(game)
	SiegeHudType.draw(
		self, tx.t("SIEGE_RECEIPT_YES", [int(row["yes"])]), YES_X, low, "LABEL", D.GOOD
	)
	if int(row["no"]) > 0:
		var no_text := tx.t("SIEGE_RECEIPT_NO", [int(row["no"])])
		SiegeHudType.draw(self, no_text, NO_X, low, "LABEL", D.NO_VOTE)
	if bool(row["my_no"]):
		SiegeHudType.draw_r(self, tx.t("SIEGE_RECEIPT_YOUR_NO"), W - 9, low, "LABEL", D.NO_VOTE)


## A cost on the right: the coin, then the number; a number wider than the coin's column leaves
## moves the coin left of it.
func _cost(ry: int, cost: int, col: Color) -> void:
	var num := str(cost)
	SiegeHudType.draw_r(self, num, W - 9, ry, "BODY", col)
	var coin_x := mini(COIN_X, W - 9 - SiegeHudType.width(num, "BODY") - COIN_GAP)
	D.icon(self, "denarius", coin_x, ry + 1, col)
