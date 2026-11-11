extends GutTest
## The break shop keeps every behaviour in its new plate (SiegeShopPanel, docs/games/siege.md 3):
## the rows' order and prices, paging to every item the rules sell, picks (which go to the shared
## receipt), the ERG auto-confirm that adds nothing, the countdown, the pedal hint, the rows as
## drawn and their ADDED / picker marks.

const K := preload("res://tests/games/siege/hud/siege_hud_kit.gd")
const F := preload("res://tests/games/siege/siege_fakes.gd")

var _games: Array[SiegeGame] = []


func after_each() -> void:
	for g in _games:
		F.free_game(g)
	_games.clear()


func _break_game(gold: float = 5000.0, elapsed_s: float = 20.0) -> SiegeGame:
	var g := K.game(3, elapsed_s)
	_games.append(g)
	g.state.rider_at(0).gold = gold
	return g


func _panel(g: SiegeGame, picks: Variant = []) -> SiegeShopPanel:
	var panel := K.ctl(SiegeShopPanel.new(), g, SiegeShopPanel.RECT) as SiegeShopPanel
	panel.picks_override = picks
	add_child_autofree(panel)
	panel.refresh()
	return panel


## Every [item, at] the rules would sell to the rider now, found by buying it on a copy.
func _sellable(st: SiegeState, slot: int) -> Dictionary:
	var out := {}
	var at_values := {
		SiegeIds.ITEM_UPGRADE: [1, 2, 3, 4],
		SiegeIds.ITEM_SCORPION: [1, 2, 3, 4],
		SiegeIds.ITEM_PAD_UPGRADE: [1, 2, 3, 4],
	}
	for item: String in SiegeIds.ITEMS:
		for at: int in at_values.get(item, [0]):
			var copy := SiegeState.from_dict(st.to_dict(), st.content)
			var r := copy.rider_at(slot)
			var station := at if SiegeIds.STATION_ITEMS.has(item) else 0
			var pad := at if SiegeIds.PAD_ITEMS.has(item) else 0
			var res := SiegeShop.purchase(copy, r, item, station, pad)
			if str(res["why"]) == SiegeIds.BUY_OK:
				out["%s/%d" % [item, at]] = true
	return out


## Every id the panel's list shows, following its More rows through every page.
func _listed(panel: SiegeShopPanel) -> Dictionary:
	var seen := {}
	for _guard in 20:
		var more := -1
		var items := panel.list.items()
		for i in items.size():
			var id: Dictionary = items[i]["id"]
			if str(id["item"]) == "more":
				more = i
			else:
				seen["%s/%d" % [id["item"], id["at"]]] = true
		if more < 0:
			break
		panel.list.item_picked.emit(more, items[more]["id"], "action")
		panel.refresh()
		if panel.page == 0:
			break
	return seen


func test_rows_put_autopilots_pick_first_and_save_second() -> void:
	var g := _break_game(500.0, 2.0)
	var st := g.state
	var r := st.rider_at(0)
	var picks := SiegeAutopilot.shop_picks(st, r, 1)
	var rows := SiegeShopModel.entries(st, r, GameStrings.new(), picks)
	assert_gt(rows.size(), 3)
	if not picks.is_empty():
		assert_true(bool(rows[0]["recommended"]))
		assert_eq(str(rows[0]["id"]["item"]), str(picks[0]["item"]))
		assert_eq(str(rows[1]["id"]["item"]), SiegeIds.ITEM_SAVE)
	else:
		assert_eq(str(rows[0]["id"]["item"]), SiegeIds.ITEM_SAVE)
	for row: Dictionary in rows:
		var id: Dictionary = row["id"]
		if str(id["item"]) == SiegeIds.ITEM_SAVE:
			continue
		var price := SiegeShop.price(st, str(id["item"]), int(id["at"]), int(id["at"]))
		assert_eq(int(row["cost"]), price, str(id))
		assert_false(bool(row["disabled"]), "500 gold buys anything")
		assert_ne(str(row["name"]), "")
		assert_true(str(row["text"]).begins_with(str(row["name"])))
	r.gold = 0.0
	for row: Dictionary in SiegeShopModel.entries(st, r, GameStrings.new(), []):
		if str(row["id"]["item"]) != SiegeIds.ITEM_SAVE:
			assert_true(bool(row["disabled"]), "nothing is affordable at 0 gold")


func test_the_panel_sends_picks_and_drops_auto_ones() -> void:
	var g := _break_game(500.0, 2.0)
	var pick := SiegeIntents.normalize(SiegeIntents.pick(SiegeIds.ITEM_UPGRADE, 2, true))
	var panel := _panel(g, [pick])
	assert_true(panel.visible)
	assert_eq(panel.list.item_count(), mini(panel.entries.size(), SiegeShopModel.ROWS))
	assert_eq(str(panel.entries[0]["id"]["item"]), SiegeIds.ITEM_UPGRADE)
	assert_eq(int(panel.entries[0]["id"]["at"]), 2)
	assert_eq(str(panel.entries[1]["id"]["item"]), SiegeIds.ITEM_SAVE)
	panel.list.item_picked.emit(0, panel.entries[0]["id"], "action")
	var sent: Array = (g.ctx.intents as F.Intents).sent
	assert_eq(sent.size(), 1)
	assert_eq(str(sent[0]["item"]), SiegeIds.ITEM_UPGRADE)
	assert_eq(int(sent[0]["station"]), 2)
	assert_eq(str(sent[0]["k"]), SiegeIds.INTENT_PICK)
	assert_false(sent[0].has("auto"))
	panel.list.item_picked.emit(1, panel.entries[1]["id"], "action")
	assert_eq(sent.size(), 1, "Save gold sends nothing")
	panel.list.item_picked.emit(0, panel.entries[0]["id"], "auto")
	assert_eq(sent.size(), 1, "an auto-confirmed pick never leaves the panel")
	panel.list.item_picked.emit(0, panel.entries[0]["id"], "surge")
	assert_eq(sent.size(), 2, "a surge pick does")


func test_the_shop_closes_outside_breaks() -> void:
	var g := _break_game()
	var panel := _panel(g)
	assert_true(panel.visible)
	K.stand(g, 4, 10.0)
	panel.refresh()
	assert_false(panel.visible, "closed in waves")
	assert_eq(panel.model, {})


func test_every_item_the_rules_sell_is_reachable() -> void:
	var g := _break_game()
	var st := g.state
	var panel := _panel(g)
	assert_lte(panel.list.item_count(), SiegeShopModel.ROWS)
	var want := _sellable(st, 0)
	assert_gt(want.size(), 8)
	var seen := _listed(panel)
	var missing := []
	for k: String in want:
		if not seen.has(k):
			missing.append(k)
	assert_eq(missing, [], "every purchasable item is reachable")
	assert_eq(str(panel.list.items()[0]["id"]["item"]), SiegeIds.ITEM_SAVE, "back on page one")


func test_a_recommended_scorpion_stays_on_top() -> void:
	var g := _break_game(100.0)
	var pick := SiegeIntents.normalize(SiegeIntents.pick(SiegeIds.ITEM_SCORPION, 3, true))
	var rows := SiegeShopModel.entries(g.state, g.state.rider_at(0), GameStrings.new(), [pick])
	assert_eq(str(rows[0]["id"]["item"]), SiegeIds.ITEM_SCORPION)
	assert_eq(int(rows[0]["id"]["at"]), 3)
	assert_true(bool(rows[0]["recommended"]))
	assert_eq(str(rows[1]["id"]["item"]), SiegeIds.ITEM_SAVE)


func test_auto_confirm_on_a_later_page_turns_back_instead_of_picking() -> void:
	var g := _break_game()
	var panel := _panel(g)
	assert_gt(panel.page_count, 1)
	var items := panel.list.items()
	var more: Dictionary = items[items.size() - 1]["id"]
	assert_eq(str(more["item"]), SiegeShopModel.ITEM_MORE)
	panel.list.item_picked.emit(items.size() - 1, more, "action")
	assert_eq(panel.page, 1)
	var first: Dictionary = panel.list.items()[0]["id"]
	panel.list.item_picked.emit(0, first, "auto")
	assert_eq(
		(g.ctx.intents as F.Intents).sent.size(), 0, "pedalling alone never picks deep in the list"
	)
	assert_eq(panel.page, 0)
	panel.list.item_picked.emit(0, panel.list.items()[0]["id"], "action")
	assert_eq((g.ctx.intents as F.Intents).sent.size(), 0, "Save gold sends nothing")


func test_the_list_has_no_auto_confirm_but_stays_live() -> void:
	var panel := _panel(_break_game())
	assert_false(panel.list.follow_local_mode, "it no longer follows the trainer into auto-picks")
	assert_false(panel.list.erg_auto_confirm)
	assert_true(panel.list.is_visible_in_tree(), "it must tick and hear the router")


func test_pedal_nav_turns_on_the_hint_that_says_pedalling_adds_nothing() -> void:
	var g := _break_game()
	g.ctx.local_player().pedal_nav = false
	var panel := _panel(g)
	assert_false(panel.list.pedal_nav)
	assert_eq(panel.model["hint"], "", "keyboard riders get no hint row")
	g.ctx.local_player().pedal_nav = true
	panel.refresh()
	assert_true(panel.list.pedal_nav)
	assert_eq(panel.model["hint"], SiegeHudModel.strings_of(g).t("SIEGE_SHOP_HINT"))
	assert_ne(panel.model["hint"], "")
	await wait_physics_frames(2)
	assert_gt(panel.draws, 0, "the taller plate draws")


func test_pedalling_alone_in_erg_adds_nothing_to_the_receipt() -> void:
	var g := _break_game(500.0, 2.0)
	g.ctx.local_player().pedal_nav = true
	var pick := SiegeIntents.normalize(SiegeIntents.pick(SiegeIds.ITEM_UPGRADE, 2, true))
	var panel := _panel(g, [pick])
	panel.list.real_time = false
	panel.list.listen_to_input = false
	panel.list.set_local_mode(Wl.ERG)
	var sent: Array = (g.ctx.intents as F.Intents).sent
	for _i in 8:
		panel.list.tick(panel.list.scan_interval_s * 6.0)
	assert_eq(sent.size(), 0, "two scan cycles, and a dozen more: nothing is picked")


func test_a_platform_auto_confirm_would_still_add_nothing() -> void:
	var g := _break_game(500.0, 2.0)
	g.ctx.local_player().pedal_nav = true
	var pick := SiegeIntents.normalize(SiegeIntents.pick(SiegeIds.ITEM_UPGRADE, 2, true))
	var panel := _panel(g, [pick])
	panel.list.real_time = false
	panel.list.listen_to_input = false
	panel.list.set_local_mode(Wl.ERG)
	panel.list.erg_auto_confirm = true
	panel.list.tick(panel.list.auto_confirm_after_s() + 0.01)
	assert_eq((g.ctx.intents as F.Intents).sent.size(), 0, "the panel drops an auto pick itself")


func test_coasting_in_erg_never_backs_out_of_the_list() -> void:
	var g := _break_game()
	g.ctx.local_player().pedal_nav = true
	var panel := _panel(g)
	panel.list.real_time = false
	panel.list.listen_to_input = false
	var tm := K.tm(0.0, 100.0, 90.0, 190, Wl.ERG)
	panel.set_telemetry(tm)
	panel.refresh()
	var backed := []
	panel.list.backed_out.connect(func() -> void: backed.append(1))
	panel.list.feed_gesture(Wl.G_COAST)
	assert_eq(backed, [], "the list knows the rider is in ERG")


func test_an_added_item_shows_added_and_another_riders_shows_their_name() -> void:
	var g := _break_game(500.0, 2.0)
	var st := g.state
	var tx := SiegeHudModel.strings_of(g)
	var mine := SiegeReceiptLine.new()
	mine.item = SiegeIds.ITEM_REPAIR
	mine.cost = 20
	mine.slot = 0
	st.gate_hp = st.gate_max - 30.0
	var theirs := SiegeReceiptLine.new()
	theirs.item = SiegeIds.ITEM_UPGRADE
	theirs.at = SiegeIds.STATION_BALLISTA
	theirs.lvl = st.station(SiegeIds.STATION_BALLISTA).level + 1
	theirs.cost = 40
	theirs.slot = 1
	theirs.no = [0]
	st.receipt.assign([mine, theirs])
	var panel := _panel(g)
	var rows := panel.model["rows"] as Array
	var by_text := {}
	for row: Dictionary in rows:
		by_text[str(row["text"])] = row
	var repair: Dictionary = by_text[SiegeShopModel.text_of(st, tx, SiegeIds.ITEM_REPAIR, 0)]
	assert_eq(str(repair["mark"]).to_upper(), "ADDED")
	assert_true(bool(repair["mark_mine"]))
	var mine_row: Dictionary = by_text[SiegeShopModel.text_of(
		st, tx, SiegeIds.ITEM_UPGRADE, SiegeIds.STATION_BALLISTA
	)]
	assert_eq(str(mine_row["mark"]), SiegeHudModel.rider_name(g, st.rider_at(1)))
	assert_true(bool(mine_row["mark_no"]), "the rider voted no on it")
	assert_false(bool(mine_row["mark_mine"]))
	assert_true(bool(mine_row["ok"]), "an item on the receipt stays pickable")


func test_a_receipt_item_stays_pickable_when_the_gold_is_held() -> void:
	var g := _break_game(60.0, 2.0)
	var st := g.state
	var line := SiegeReceiptLine.new()
	line.item = SiegeIds.ITEM_MINE
	line.lvl = st.mine_level + 1
	line.cost = 60
	line.slot = 0
	st.receipt.assign([line])
	var rows := SiegeShopModel.entries(st, st.rider_at(0), GameStrings.new(), [])
	for e: Dictionary in rows:
		var id: Dictionary = e["id"]
		if str(id["item"]) == SiegeIds.ITEM_SAVE:
			continue
		if str(id["item"]) == SiegeIds.ITEM_MINE and int(id["lvl"]) == line.lvl:
			assert_false(bool(e["disabled"]), "pick it again to take it back")
			assert_true(bool(e["mine"]))
		else:
			assert_true(bool(e["disabled"]), "all 60 gold is held: %s" % str(id))


func _rows_of(g: SiegeGame, item: String, at: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var st := g.state
	for e: Dictionary in SiegeShopModel.entries(st, st.rider_at(0), GameStrings.new(), []):
		var id: Dictionary = e["id"]
		if str(id["item"]) == item and int(id["at"]) == at:
			out.append(e)
	return out


func test_level_1_on_the_receipt_adds_a_row_for_level_2_priced_at_that_level() -> void:
	var g := _break_game(500.0, 2.0)
	var st := g.state
	var at := SiegeIds.STATION_BALLISTA
	st.station(at).level = 0
	assert_eq(_rows_of(g, "upgrade", at).size(), 1, "level 1 only")
	SiegeReceipt.add(st, st.rider_at(1), "upgrade", at, 0, [])
	var rows := _rows_of(g, "upgrade", at)
	assert_eq(rows.size(), 2, "level 1 (added) and a row for level 2")
	assert_true(bool(rows[0]["added"]))
	assert_eq(int(rows[0]["id"]["lvl"]), 1)
	assert_false(bool(rows[1]["added"]))
	assert_eq(int(rows[1]["id"]["lvl"]), 2)
	assert_eq(int(rows[1]["cost"]), 50, "priced at level 2")
	assert_ne(rows[0]["name"], rows[1]["name"], "each level has its own name")
	SiegeReceipt.add(st, st.rider_at(0), "upgrade", at, 0, [])
	assert_eq(_rows_of(g, "upgrade", at).size(), 3, "and level 3 after level 2")
	SiegeReceipt.add(st, st.rider_at(0), "upgrade", at, 0, [])
	assert_eq(_rows_of(g, "upgrade", at).size(), 3, "never past level 3")


func test_a_level_2_pick_goes_out_with_its_level() -> void:
	var g := _break_game(500.0, 2.0)
	var st := g.state
	var at := SiegeIds.STATION_BALLISTA
	st.station(at).level = 0
	SiegeReceipt.add(st, st.rider_at(1), "upgrade", at, 0, [])
	var panel := _panel(g)
	var rows := panel.entries.filter(
		func(e: Dictionary) -> bool: return e["id"]["item"] == "upgrade" and e["id"]["at"] == at
	)
	assert_eq(rows.size(), 2)
	panel.list.item_picked.emit(0, rows[1]["id"], "surge")
	var sent: Array = (g.ctx.intents as F.Intents).sent
	assert_eq(int(sent[0]["lvl"]), 2)
	assert_eq(int(sent[0]["station"]), at)


func test_the_lit_row_says_what_a_surge_does() -> void:
	var g := _break_game(500.0, 2.0)
	var st := g.state
	var tx := SiegeHudModel.strings_of(g)
	st.gate_hp = st.gate_max - 30.0
	var mine := SiegeReceiptLine.new()
	mine.item = SiegeIds.ITEM_REPAIR
	mine.cost = 20
	mine.slot = 0
	var other := SiegeReceiptLine.new()
	other.item = SiegeIds.ITEM_UPGRADE
	other.at = SiegeIds.STATION_BALLISTA
	other.lvl = st.station(SiegeIds.STATION_BALLISTA).level + 1
	other.cost = 40
	other.slot = 1
	var undone := SiegeReceiptLine.new()
	undone.item = SiegeIds.ITEM_UPGRADE
	undone.at = SiegeIds.STATION_ONAGER
	undone.lvl = st.station(SiegeIds.STATION_ONAGER).level + 1
	undone.cost = 40
	undone.slot = 1
	undone.no.assign([0])
	st.receipt.assign([mine, other, undone])
	var panel := _panel(g)
	var acts := {}
	for p in panel.page_count:
		panel._turn_to(p)
		for row: Dictionary in panel.model["rows"]:
			if str(row["act"]) != "":
				acts[str(row["text"])] = str(row["act"]).to_upper()
	assert_true(acts.values().has("TAKE BACK"))
	assert_true(acts.values().has("VOTE NO"))
	assert_true(acts.values().has("UNDO NO"))
	assert_eq(tx.t("SIEGE_SHOP_ADDED").to_upper(), "ADDED", "the other rows keep their tags")


func test_a_receipt_change_keeps_the_riders_cursor_on_its_row() -> void:
	var g := _break_game(500.0, 2.0)
	var panel := _panel(g)
	panel.list.sounds = false
	panel.list.set_highlight(2)
	var id: Variant = panel.list.highlighted_id()
	var line := SiegeReceiptLine.new()
	line.item = SiegeIds.ITEM_REPAIR
	line.cost = 20
	line.slot = 1
	g.state.gate_hp = g.state.gate_max - 30.0
	g.state.receipt.assign([line])
	panel._list_since = 1.0
	panel.refresh()
	assert_eq(panel.list.highlighted_id(), id, "the same item, wherever it sits now")


func test_the_title_says_pick_to_add() -> void:
	var panel := _panel(_break_game())
	assert_eq(str(panel.model["title"]).to_upper(), "QUARTERMASTER  PICK TO ADD")


func test_the_countdown_shows_for_a_rider_on_the_fallback() -> void:
	var g := _break_game(100.0, 2.0)
	var r := g.state.rider_at(0)
	r.shop_fallback = true
	var panel := _panel(g)
	assert_true(SiegeShop.autopiloted(r))
	assert_ne(panel.model["countdown"], "", "picks in a few seconds")
	r.shop_fallback = false
	r.autopilot = false
	panel.refresh()
	assert_eq(panel.model["countdown"], "", "after a manual buy, no countdown")


func test_rows_say_what_is_best_and_what_is_short() -> void:
	var g := _break_game(40.0, 2.0)
	var pick := SiegeIntents.normalize(SiegeIntents.pick(SiegeIds.ITEM_REPAIR, 0, true))
	g.state.gate_hp = g.state.gate_max - 30.0
	var panel := _panel(g, [pick])
	var rows: Array = panel.model["rows"]
	assert_eq(rows[0]["note"].to_upper(), "BEST")
	assert_eq(rows[1]["cost"], -1, "Save gold has no price")
	assert_eq(rows[1]["note"], "")
	for row: Dictionary in rows:
		if not bool(row["ok"]) and int(row["cost"]) >= 0:
			assert_eq(row["note"].to_upper(), "%d MORE" % (int(row["cost"]) - 40))
	var last: Dictionary = rows[rows.size() - 1]
	assert_true(last["text"].to_upper().begins_with("MORE ITEMS:"), last["text"])
	assert_eq(last["cost"], -1)


func test_every_name_clears_its_note_with_the_coin_in_its_column() -> void:
	var g := _break_game(500.0, 2.0)
	var panel := _panel(g)
	await wait_physics_frames(2)
	assert_gt(panel.draws, 0)
	assert_eq(SiegeShopPanel.W, 364)
	var note := SiegeHudType.width("100 MORE", "LABEL")
	var room := SiegeShopPanel.COIN_X - 6 - note - 6 - SiegeShopPanel.TEXT_X
	for e in panel.entries:
		assert_lte(SiegeHudType.width(str(e["name"]), "BODY"), room, str(e["name"]))


func test_the_wider_plate_still_clears_the_cockpit() -> void:
	assert_lt(SiegeShopPanel.RECT.end.x, SiegeHudCockpit.RECT.position.x)


func test_the_highlight_redraws_at_once() -> void:
	var g := _break_game()
	var panel := _panel(g)
	await wait_physics_frames(2)
	var before := panel.draws
	panel.list.feed_action(&"down")
	assert_eq(panel.model["highlight"], panel.list.highlighted())
	await wait_physics_frames(2)
	assert_gt(panel.draws, before)
