extends GutTest
## The break shop keeps every behaviour in its new plate (SiegeShopPanel, docs/games/siege.md 3):
## the rows' order and prices, paging to every item the rules sell, buys and the "auto" tag, an
## auto-confirm on a later page, the countdown, the pedal hint, and the rows as drawn.

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


func test_the_panel_sends_buys_and_tags_auto_picks() -> void:
	var g := _break_game(500.0, 2.0)
	var pick := SiegeIntents.normalize(SiegeIntents.buy(SiegeIds.ITEM_UPGRADE, 2, true))
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
	assert_false(sent[0].has("auto"))
	panel.list.item_picked.emit(1, panel.entries[1]["id"], "action")
	assert_eq(sent.size(), 1, "Save gold sends nothing")
	panel.list.item_picked.emit(0, panel.entries[0]["id"], "auto")
	assert_eq(int(sent[1]["auto"]), 1, "an auto-confirmed pick is tagged")


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
	var pick := SiegeIntents.normalize(SiegeIntents.buy(SiegeIds.ITEM_SCORPION, 3, true))
	var rows := SiegeShopModel.entries(g.state, g.state.rider_at(0), GameStrings.new(), [pick])
	assert_eq(str(rows[0]["id"]["item"]), SiegeIds.ITEM_SCORPION)
	assert_eq(int(rows[0]["id"]["at"]), 3)
	assert_true(bool(rows[0]["recommended"]))
	assert_eq(str(rows[1]["id"]["item"]), SiegeIds.ITEM_SAVE)


func test_auto_confirm_on_a_later_page_turns_back_instead_of_buying() -> void:
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
		(g.ctx.intents as F.Intents).sent.size(), 0, "pedalling alone never buys deep in the list"
	)
	assert_eq(panel.page, 0)
	panel.list.item_picked.emit(0, panel.list.items()[0]["id"], "action")
	assert_eq((g.ctx.intents as F.Intents).sent.size(), 0, "Save gold sends nothing")


func test_the_list_follows_the_trainer_and_stays_live() -> void:
	var panel := _panel(_break_game())
	assert_true(panel.list.follow_local_mode)
	assert_true(panel.list.erg_auto_confirm)
	assert_true(panel.list.is_visible_in_tree(), "it must tick and hear the router")


func test_pedal_nav_turns_on_the_hint_and_the_auto_pick() -> void:
	var g := _break_game()
	g.ctx.local_player().pedal_nav = false
	var panel := _panel(g)
	assert_false(panel.list.pedal_nav)
	assert_eq(panel.model["hint"], "", "keyboard riders get no hint row")
	g.ctx.local_player().pedal_nav = true
	panel.refresh()
	assert_true(panel.list.pedal_nav)
	panel.list.set_local_mode(Wl.ERG)
	panel.list.tick(0.1)
	panel.refresh()
	assert_ne(panel.model["hint"], "", "the auto-pick countdown")
	assert_eq(panel.model["hint"], panel.hint_text())
	await wait_physics_frames(2)
	assert_gt(panel.draws, 0, "the taller plate draws")


func test_auto_confirm_picks_the_top_row_in_erg() -> void:
	var g := _break_game(500.0, 2.0)
	g.ctx.local_player().pedal_nav = true
	var pick := SiegeIntents.normalize(SiegeIntents.buy(SiegeIds.ITEM_UPGRADE, 2, true))
	var panel := _panel(g, [pick])
	panel.list.real_time = false
	panel.list.listen_to_input = false
	panel.list.follow_local_mode = false
	panel.list.set_local_mode(Wl.ERG)
	panel.list.erg_auto_confirm = true
	panel.list.tick(panel.list.auto_confirm_after_s() + 0.01)
	var sent: Array = (g.ctx.intents as F.Intents).sent
	assert_eq(sent.size(), 1)
	assert_eq(int(sent[0]["auto"]), 1)


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
	var pick := SiegeIntents.normalize(SiegeIntents.buy(SiegeIds.ITEM_REPAIR, 0, true))
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


func test_a_long_row_is_cut_to_fit() -> void:
	var g := _break_game(500.0, 2.0)
	var panel := _panel(g)
	await wait_physics_frames(2)
	assert_gt(panel.draws, 0)
	for e in panel.entries:
		var room := SiegeShopPanel.W - 50 - 20 - 6 - 46
		var cut := SiegeHudType.fit(str(e["name"]), "BODY", room)
		assert_lte(SiegeHudType.width(cut, "BODY"), room, str(e["name"]))


func test_the_highlight_redraws_at_once() -> void:
	var g := _break_game()
	var panel := _panel(g)
	await wait_physics_frames(2)
	var before := panel.draws
	panel.list.feed_action(&"down")
	assert_eq(panel.model["highlight"], panel.list.highlighted())
	await wait_physics_frames(2)
	assert_gt(panel.draws, before)
