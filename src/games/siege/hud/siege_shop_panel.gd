class_name SiegeShopPanel
extends SiegeHudCtl
## The break shop (docs/games/siege.md 2.4 "Shop", 3 HUD), bottom left over the road's west loop,
## which is empty in breaks: a Quartermaster plate with its rows in the BODY face. The top entry is
## Autopilot's pick for the rider, the second "Save gold", then what else they could buy
## (SiegeShopModel).
##
## The pick logic is the platform's PedalScanList, whole: it follows the local trainer mode, so in
## an ERG break a rider with pedal navigation on (PlayerSlot.pedal_nav) who only pedals gets the
## top entry auto-confirmed after two scan cycles; that pick goes out tagged "auto" and never ends
## the rider's zero-input shop fallback. A pick sends SiegeIntents.buy(item, at, via == "auto")
## through ctx.intents. The list stays in the tree (it must be visible to tick and to hear the
## router) inside a zero-size clipped holder; this plate draws its rows and highlight instead.
## Everything the rules sell is reachable: the list shows SiegeShopModel.ROWS rows a page, and a
## page's last row "More items" turns to the next (the last page's back to the first). An
## auto-confirmed pick on a later page only turns back to the first page, so pedalling alone
## never buys from deep in the list. With pedal navigation on, a hint row (with the ERG auto-pick
## countdown) sits under the rows and the plate grows upward for it.

## The plate's rect in breaks; RECT holds its shadow and the hint row above it.
const RECT := Rect2i(8, 368, 366, 166)
const W := 364
const H := 150
const HINT_H := 14
const ROW_STEP := 24
const ROW_H := 22
const TEXT_X := 20
## The coin's fixed column on every priced row.
const COIN_X := W - 44
const LIST_REFRESH_S := 0.25

var list: PedalScanList = null
## Tests set this to stand in for SiegeAutopilot.shop_picks (an Array of normalized buys).
var picks_override: Variant = null
var signature: String = ""
var entries: Array[Dictionary] = []
## The page shown (0 first) and how many there are.
var page: int = 0
var page_count: int = 1
var _list_since: float = LIST_REFRESH_S
var _holder: Control = null


func _init() -> void:
	super._init()
	name = "SiegeShopPanel"
	_holder = Control.new()
	_holder.name = "ListHolder"
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.clip_contents = true
	_holder.custom_minimum_size = Vector2.ZERO
	add_child(_holder)
	list = PedalScanList.new()
	list.name = "Items"
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", 0)
	list.follow_local_mode = true
	list.erg_auto_confirm = true
	list.item_picked.connect(_on_item_picked)
	list.highlight_changed.connect(_on_highlight_changed)
	_holder.add_child(list)
	visible = false


func _process(delta: float) -> void:
	_list_since += delta
	super._process(delta)


## Visible while the shop is open for the local rider; refreshes the entries a few times a second
## and rebuilds the list only when they changed (set_items restarts the scan).
func build() -> Dictionary:
	var s := st()
	var r := own()
	if r == null or not s.shop_open():
		visible = false
		return {}
	visible = true
	var me := game.ctx.local_player() if game.ctx != null else null
	list.pedal_nav = me != null and me.pedal_nav
	list.show_hint = list.pedal_nav
	var tx := SiegeHudModel.strings_of(game)
	if _list_since >= LIST_REFRESH_S or entries.is_empty():
		_list_since = 0.0
		rebuild(tx, r)
	var left := _autobuy_in_s(s, r)
	return {
		"title": tx.t("SIEGE_SHOP_TITLE"),
		"countdown": tx.t("SIEGE_SHOP_COUNTDOWN", [ceili(left)]) if left > 0.0 else "",
		"hint": hint_text(),
		"highlight": list.highlighted(),
		"rows": rows_face(tx, r),
	}


## The list's hint (how to pick, the ERG auto-pick countdown) while pedal navigation is on.
func hint_text() -> String:
	if not list.pedal_nav:
		return ""
	var hint := list.get_node_or_null("Hint") as Label
	return hint.text if hint != null else ""


## The rows as drawn: [{"text", "cost" (-1: none), "ok", "note"}].
func rows_face(tx: GameStrings, r: SiegeRiderState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var gold := floori(r.gold)
	for it: Dictionary in list.items():
		var id: Variant = it.get("id", {})
		var e := _entry_of(id)
		var item := str((id as Dictionary).get("item", "")) if id is Dictionary else ""
		var plain := item == SiegeIds.ITEM_SAVE or item == SiegeShopModel.ITEM_MORE or e.is_empty()
		var ok := not bool(it.get("disabled", false))
		var note := ""
		if not ok and not plain:
			note = tx.t("SIEGE_SHOP_SHORT", [maxi(int(e["cost"]) - gold, 0)])
		elif not plain and bool(e.get("recommended", false)):
			note = tx.t("SIEGE_SHOP_BEST")
		(
			out
			. append(
				{
					"text":
					(
						str(e.get("name", it.get("text", "")))
						if not plain
						else str(it.get("text", ""))
					),
					"cost": -1 if plain else int(e["cost"]),
					"ok": ok,
					"note": note,
				}
			)
		)
	return out


func _entry_of(id: Variant) -> Dictionary:
	for e in entries:
		if e["id"] == id:
			return e
	return {}


func paint() -> void:
	var hint := str(model["hint"])
	var plate_h := H + (HINT_H if hint != "" else 0)
	var y := RECT.size.y - H - 2 - (HINT_H if hint != "" else 0)
	D.plate(self, 0, y, W, plate_h)
	D.ansata(self, 10, y + 5, str(model["title"]))
	var countdown := str(model["countdown"])
	if countdown != "":
		SiegeHudType.draw_r(self, countdown, W - 9, y + 9, "LABEL", D.GOLD)
	var rows: Array = model["rows"]
	for i in rows.size():
		_row(y + 26 + i * ROW_STEP, i, rows[i])
	if hint != "":
		var ht := SiegeHudType.fit(hint, "LABEL", W - 18)
		SiegeHudType.draw(self, ht, 9, y + H - 2, "LABEL", D.DIM)


func _row(ry: int, index: int, row: Dictionary) -> void:
	var ok := bool(row["ok"])
	if index == int(model["highlight"]):
		D.rect(self, 4, ry, W - 8, ROW_H, D.BRONZE_LO)
		D.rect(self, 4, ry, 2, ROW_H, D.BRONZE_HI)
		SiegeHudType.draw(self, ">", 9, ry + 5, "BODY", D.GOLD)
	var right := W - 9
	var cost := int(row["cost"])
	var col := D.GOLD if ok else D.DIM
	var note := str(row["note"])
	if cost >= 0:
		SiegeHudType.draw_r(self, str(cost), right, ry + 5, "BODY", col)
		D.icon(self, "denarius", COIN_X, ry + 6, col)
		right = COIN_X - 6
	if note != "":
		right = SiegeHudType.draw_r(self, note, right, ry + 7, "LABEL", col) - 6
	var text := SiegeHudType.fit(str(row["text"]), "BODY", right - TEXT_X)
	SiegeHudType.draw(self, text, TEXT_X, ry + 5, "BODY", D.TEXT if ok else D.DIM)


## Seconds until Autopilot buys for a rider still on the zero-input shop fallback (0: never).
func _autobuy_in_s(s: SiegeState, r: SiegeRiderState) -> float:
	if not SiegeShop.autopiloted(r) or s.content == null:
		return 0.0
	var at: Variant = (s.content.balance.get("autopilot", {}) as Dictionary).get("shop_at_s", [])
	var first := float((at as Array)[0]) if at is Array and not (at as Array).is_empty() else 0.0
	return maxf(first - s.phase_elapsed_s, 0.0)


## Recomputes the entries and rebuilds the list when they changed.
func rebuild(tx: GameStrings, r: SiegeRiderState) -> void:
	var s := game.state
	var picks: Array[Dictionary] = []
	if picks_override is Array:
		picks.assign(picks_override)
	else:
		picks = SiegeAutopilot.shop_picks(s, r, 1)
	entries = SiegeShopModel.entries(s, r, tx, picks)
	var pages := SiegeShopModel.pages(entries, tx)
	page_count = pages.size()
	page = clampi(page, 0, page_count - 1)
	var shown: Array = pages[page]
	var sig := "%d|%s" % [page, SiegeShopModel.signature(shown)]
	if sig == signature:
		return
	signature = sig
	var items: Array = []
	for e: Dictionary in shown:
		items.append(
			{
				"id": e["id"],
				"text": e["text"],
				"detail": e["detail"],
				"disabled": bool(e["disabled"])
			}
		)
	list.set_items(items)


func _turn_to(p: int) -> void:
	page = p
	signature = ""
	if game != null and game.state != null:
		var r := SiegeHudModel.own_rider(game)
		if r != null:
			rebuild(SiegeHudModel.strings_of(game), r)
	_list_since = 0.0
	refresh()


func _on_highlight_changed(_index: int) -> void:
	if not model.is_empty():
		model["highlight"] = list.highlighted()
		_signature = model.hash()
		queue_redraw()


func _on_item_picked(_index: int, id: Variant, via: String) -> void:
	if not (id is Dictionary):
		return
	var item := str((id as Dictionary).get("item", ""))
	var at := int((id as Dictionary).get("at", 0))
	if item == SiegeShopModel.ITEM_MORE or (via == "auto" and page != 0):
		_turn_to(at if item == SiegeShopModel.ITEM_MORE and via != "auto" else 0)
		return
	if item == SiegeIds.ITEM_SAVE or item == "":
		return
	if game != null and game.ctx != null and game.ctx.intents != null:
		game.ctx.intents.send(SiegeIntents.buy(item, at, via == "auto"))
