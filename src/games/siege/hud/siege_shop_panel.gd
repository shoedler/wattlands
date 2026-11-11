class_name SiegeShopPanel
extends SiegeHudCtl
## The break shop (docs/games/siege.md 2.4 "Shop", 3 HUD), bottom left over the road's west loop,
## which is empty in breaks: a Quartermaster plate with its rows in the BODY face. The top entry is
## Autopilot's pick for the rider, the second "Save gold", then what else they could buy
## (SiegeShopModel). A pick adds the item to the shared receipt (SiegeReceiptPanel above this
## plate), takes your own back, or votes on someone else's; a row marks your own items "ADDED" and
## the others' with the picker's name; the lit row of an added item says what a surge will do
## (TAKE BACK, VOTE NO or UNDO NO) in place of the tag.
##
## The pick logic is the platform's PedalScanList (scanning, surge to pick, keys), with one
## difference: its ERG auto-confirm is off here (follow_local_mode false, erg_auto_confirm false;
## the local mode is still told to the list, so coasting in ERG never backs out). Pedalling alone
## adds nothing: Autopilot's picks come from the host's rules for a rider who does nothing. A pick
## that still arrives tagged "auto" is dropped. A pick sends SiegeIntents.pick(item, at) through
## ctx.intents. The list stays in the tree (it must be visible to tick and to hear the router)
## inside a zero-size clipped holder; this plate draws its rows and highlight instead.
## Everything the rules sell is reachable: the list shows SiegeShopModel.ROWS rows a page, and a
## page's last row "More items" turns to the next (the last page's back to the first). An
## auto-confirmed pick on a later page only turns back to the first page, so pedalling alone
## never changes the receipt. With pedal navigation on, a hint row sits under the rows and the
## plate grows upward for it.

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
	list.follow_local_mode = false
	list.erg_auto_confirm = false
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
	list.show_hint = false
	if tm != null and tm.mode != "":
		list.set_local_mode(tm.mode)
	var tx := SiegeHudModel.strings_of(game)
	if _list_since >= LIST_REFRESH_S or entries.is_empty():
		_list_since = 0.0
		rebuild(tx, r)
	var left := _autobuy_in_s(s, r)
	return {
		"title": tx.t("SIEGE_SHOP_TITLE"),
		"countdown": tx.t("SIEGE_SHOP_COUNTDOWN", [ceili(left)]) if left > 0.0 else "",
		"hint": tx.t("SIEGE_SHOP_HINT") if list.pedal_nav else "",
		"highlight": list.highlighted(),
		"rows": rows_face(tx, r),
	}


## The rows as drawn: [{"text", "cost" (-1: none), "ok", "note", "mark", "mark_mine", "mark_no",
## "act"}]. "note" is what the row lacks or recommends, "mark" what the receipt says of it: ADDED for
## the rider's own item, the picker's name for another's (terracotta when the rider voted no on it),
## and "act" what a pick of it does now (shown on the lit row only).
func rows_face(tx: GameStrings, r: SiegeRiderState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var free := floori(game.state.spendable(r))
	for it: Dictionary in list.items():
		var id: Variant = it.get("id", {})
		var e := _entry_of(id)
		var item := str((id as Dictionary).get("item", "")) if id is Dictionary else ""
		var plain := item == SiegeIds.ITEM_SAVE or item == SiegeShopModel.ITEM_MORE or e.is_empty()
		var ok := not bool(it.get("disabled", false))
		var added := not plain and bool(e.get("added", false))
		var note := ""
		var mark := ""
		var act := ""
		if added:
			mark = tx.t("SIEGE_SHOP_ADDED") if bool(e["mine"]) else str(e["by"])
			if bool(e["mine"]):
				act = tx.t("SIEGE_SHOP_ACT_TAKE_BACK")
			elif bool(e["my_no"]):
				act = tx.t("SIEGE_SHOP_ACT_UNDO_NO")
			else:
				act = tx.t("SIEGE_SHOP_ACT_VOTE_NO")
		elif not ok and not plain:
			note = tx.t("SIEGE_SHOP_SHORT", [maxi(int(e["cost"]) - free, 0)])
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
					"mark": mark,
					"mark_mine": added and bool(e["mine"]),
					"mark_no": added and bool(e["my_no"]),
					"act": act,
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
	var mark := str(row["mark"])
	var act := str(row["act"])
	if cost >= 0:
		SiegeHudType.draw_r(self, str(cost), right, ry + 5, "BODY", col)
		D.icon(self, "denarius", COIN_X, ry + 6, col)
		right = COIN_X - 6
	if act != "" and index == int(model["highlight"]):
		right = SiegeHudType.draw_r(self, act, right, ry + 7, "LABEL", D.GOLD) - 6
	elif mark != "":
		var mark_col := (
			D.GOOD if bool(row["mark_mine"]) else (D.NO_VOTE if bool(row["mark_no"]) else D.DIM)
		)
		right = SiegeHudType.draw_r(self, mark, right, ry + 7, "LABEL", mark_col) - 6
	elif note != "":
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
		# blind to the receipt: the list keeps its order while items are added and taken back
		picks = SiegeAutopilot.shop_picks(s, r, 1, true)
	entries = SiegeShopModel.entries(s, r, tx, picks, _names())
	var pages := SiegeShopModel.pages(entries, tx)
	page_count = pages.size()
	page = clampi(page, 0, page_count - 1)
	var shown: Array = pages[page]
	var sig := "%d|%s" % [page, SiegeShopModel.signature(shown)]
	if sig == signature:
		return
	signature = sig
	var was: Variant = list.highlighted_id()
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
	_keep_highlight(was)


## set_items puts the highlight on the first row; a refresh puts it back on the row it was on (by
## its id, quietly), so a receipt change never moves the rider's cursor to another item.
func _keep_highlight(was: Variant) -> void:
	if was == null:
		return
	var rows := list.items()
	for i in rows.size():
		if rows[i].get("id") == was:
			if i != list.highlighted() and list.is_item_enabled(i):
				var loud := list.sounds
				list.sounds = false
				list.set_highlight(i)
				list.sounds = loud
			return


## Slot -> name of every rider, for the "by" of an added item.
func _names() -> Dictionary:
	var out := {}
	for rd in game.state.riders:
		out[rd.slot] = SiegeHudModel.rider_name(game, rd)
	return out


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
	var lvl := int((id as Dictionary).get("lvl", 0))
	if item == SiegeShopModel.ITEM_MORE or (via == "auto" and page != 0):
		_turn_to(at if item == SiegeShopModel.ITEM_MORE and via != "auto" else 0)
		return
	# an auto-confirm (the list has it off here) never reaches the receipt
	if via == "auto" or item == SiegeIds.ITEM_SAVE or item == "":
		return
	if game != null and game.ctx != null and game.ctx.intents != null:
		game.ctx.intents.send(SiegeIntents.pick(item, at, false, lvl))
