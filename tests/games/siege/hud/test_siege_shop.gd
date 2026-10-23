extends GutTest
## The break shop (brief 2.4 "Shop", 3 HUD): the entries (the Autopilot's recommendation first,
## "Save denarii" second), the PedalScanList panel with text of at least 32 px, picks as buy
## intents with the auto tag for an ERG auto-confirm, and visibility only in breaks.

var _game: SiegeGame = null
var _state: SiegeState = null
var _tx: GameStrings = null


func before_each() -> void:
	_state = SiegeFixtures.mid_wave()
	_state.role = SiegeIds.ROLE_BREAK
	_state.wave_no = 2
	_state.phase_kind = Wl.RECOVERY
	_game = SiegeHudUtil.make_game(_state)
	_tx = _game.ctx.strings


func after_each() -> void:
	SiegeHudUtil.free_game(_game)


func _rec(item: String, pad: int = 0) -> Dictionary:
	return SiegeIntents.normalize(SiegeIntents.buy(item, pad, true))


func _entries(picks: Array[Dictionary] = []) -> Array[Dictionary]:
	return SiegeShopModel.entries(_state, _state.rider_at(0), _tx, picks)


func _item_of(e: Dictionary) -> String:
	return str((e["id"] as Dictionary)["item"])


# --- the model ---------------------------------------------------------------------------------------


func test_top_entry_is_the_recommendation_and_second_is_save() -> void:
	var list := _entries([_rec(SiegeIds.ITEM_BUILD_BALLISTA, 5)])
	assert_eq(_item_of(list[0]), SiegeIds.ITEM_BUILD_BALLISTA)
	assert_eq((list[0]["id"] as Dictionary)["pad"], 5)
	assert_true(list[0]["recommended"])
	assert_eq(list[0]["detail"], "Autopilot's pick")
	assert_eq(_item_of(list[1]), SiegeIds.ITEM_SAVE)
	assert_eq(list[1]["text"], "Save denarii")
	assert_false(list[1]["recommended"])


func test_without_a_recommendation_save_is_first() -> void:
	var list := _entries()
	assert_eq(_item_of(list[0]), SiegeIds.ITEM_SAVE)
	assert_false(list[0]["recommended"])


func test_the_recommendation_is_not_listed_twice() -> void:
	var list := _entries([_rec(SiegeIds.ITEM_REPAIR)])
	var n := 0
	for e in list:
		if _item_of(e) == SiegeIds.ITEM_REPAIR:
			n += 1
	assert_eq(n, 1)


func test_an_impossible_recommendation_is_dropped() -> void:
	# Pad 3 already has a tower.
	var list := _entries([_rec(SiegeIds.ITEM_BUILD_BALLISTA, 3)])
	assert_eq(_item_of(list[0]), SiegeIds.ITEM_SAVE)


func test_costs_and_text() -> void:
	var list := _entries()
	var by_item := {}
	for e in list:
		by_item["%s/%d" % [_item_of(e), int((e["id"] as Dictionary)["pad"])]] = e
	var repair: Dictionary = by_item["repair/0"]
	assert_eq(repair["cost"], 20)
	assert_eq(repair["text"], "Repair the gate: +20 HP (20)")
	assert_eq(SiegeShopModel.cost_of(_state, SiegeIds.ITEM_GENERATOR, 0), 90, "level 2 costs 90")
	var more := _entries([_rec(SiegeIds.ITEM_GENERATOR)])
	assert_eq(more[0]["text"], "Generator level 2 (90)")
	assert_eq(SiegeShopModel.cost_of(_state, SiegeIds.ITEM_IRON_BANDS, 0), 45)
	assert_eq(SiegeShopModel.cost_of(_state, SiegeIds.ITEM_RESERVE, 0), -1, "the fixture owns it")
	_state.perks.clear()
	assert_eq(SiegeShopModel.cost_of(_state, SiegeIds.ITEM_RESERVE, 0), 80)
	assert_eq(SiegeShopModel.cost_of(_state, SiegeIds.ITEM_AQUEDUCT, 0), 100)
	assert_eq(SiegeShopModel.cost_of(_state, SiegeIds.ITEM_UPGRADE, 4), 40, "pad 4 is level 0")
	assert_eq(SiegeShopModel.cost_of(_state, SiegeIds.ITEM_BUILD_CALTROP, 1), 45, "G2: 45")


func test_entries_are_disabled_when_the_rider_cannot_afford_them() -> void:
	_state.rider_at(0).denarii = 30.0
	var list := _entries()
	for e in list:
		if _item_of(e) == SiegeIds.ITEM_SAVE:
			assert_false(e["disabled"])
		elif int(e["cost"]) > 30:
			assert_true(e["disabled"], "%s costs %d" % [e["text"], e["cost"]])
		else:
			assert_false(e["disabled"])


func test_repair_only_while_the_gate_is_damaged() -> void:
	_state.gate_hp = _state.gate_max
	for e in _entries():
		assert_ne(_item_of(e), SiegeIds.ITEM_REPAIR)
	assert_eq(SiegeShopModel.cost_of(_state, SiegeIds.ITEM_REPAIR, 0), -1)


func test_perks_and_bands_leave_the_list_once_bought() -> void:
	_state.perks = [SiegeIds.PERK_RESERVE, SiegeIds.PERK_AQUEDUCT]
	_state.iron_bands = 2
	var items := _entries().map(_item_of)
	assert_false(items.has(SiegeIds.ITEM_RESERVE))
	assert_false(items.has(SiegeIds.ITEM_AQUEDUCT))
	assert_false(items.has(SiegeIds.ITEM_IRON_BANDS))
	_state.gen_level = 3
	assert_eq(SiegeShopModel.cost_of(_state, SiegeIds.ITEM_GENERATOR, 0), -1)


func test_a_build_item_names_an_empty_pad_near_a_road() -> void:
	var pad := SiegeShopModel.suggest_pad(_state)
	assert_true(SiegeIds.is_pad(pad))
	assert_false(_state.pad(pad).built())
	var map := _state.content.map
	var best := INF
	for p in range(1, 9):
		if _state.pad(p).built():
			continue
		var d := INF
		for road in 3:
			d = minf(d, map.distance_to_road(map.pad_pos(p), road))
		best = minf(best, d)
	var chosen := INF
	for road in 3:
		chosen = minf(chosen, map.distance_to_road(map.pad_pos(pad), road))
	assert_almost_eq(chosen, best, 1e-3)


func test_the_pad_follows_the_road_with_the_most_gate_damage() -> void:
	_state.gate_damage_by_road = [0.0, 0.0, 50.0]
	var pad := SiegeShopModel.suggest_pad(_state)
	var map := _state.content.map
	var d_east := map.distance_to_road(map.pad_pos(pad), SiegeIds.ROAD_EAST)
	for p in range(1, 9):
		if not _state.pad(p).built():
			assert_lte(d_east, map.distance_to_road(map.pad_pos(p), SiegeIds.ROAD_EAST) + 1e-3)


func test_upgrade_goes_to_the_lowest_tower() -> void:
	assert_eq(SiegeShopModel.upgrade_pad(_state), 4, "pad 4 is the level-0 Scorpion")
	_state.pad(4).level = 3
	assert_eq(SiegeShopModel.upgrade_pad(_state), 3, "then pad 3 at level 1 (pad 2 is level 2)")
	for tw in _state.pads:
		if tw.built():
			tw.level = 3
	assert_eq(SiegeShopModel.upgrade_pad(_state), 0)


func test_the_list_is_capped() -> void:
	assert_lte(_entries([_rec(SiegeIds.ITEM_BUILD_CALTROP, 1)]).size(), SiegeShopModel.MAX_ENTRIES)


func test_signature_changes_with_content_and_affordability() -> void:
	var a := SiegeShopModel.signature(_entries())
	assert_eq(a, SiegeShopModel.signature(_entries()))
	_state.rider_at(0).denarii = 10.0
	assert_ne(a, SiegeShopModel.signature(_entries()))


# --- the panel -------------------------------------------------------------------------------------------


func _panel(picks: Array[Dictionary] = [], pedal_nav: bool = true) -> SiegeShopPanel:
	_game.ctx.local_player().pedal_nav = pedal_nav
	var p := SiegeShopPanel.new()
	p.game = _game
	p.picks_override = picks
	add_child_autofree(p)
	p.list.listen_to_input = false
	p.list.real_time = false
	p.list.sounds = false
	p.list.follow_local_mode = false
	p.set_process(false)
	p.refresh()
	return p


func test_the_panel_is_visible_only_in_a_break() -> void:
	var p := _panel()
	assert_true(p.visible)
	_state.role = SiegeIds.ROLE_WAVE
	p.refresh()
	assert_false(p.visible)
	_state.role = SiegeIds.ROLE_BUILD_BREAK
	p.refresh()
	assert_true(p.visible, "the build break has the shop too")
	_state.role = SiegeIds.ROLE_COOLDOWN
	p.refresh()
	assert_false(p.visible, "the shop is closed in the cool-down")


func test_the_panel_lists_the_entries_with_text_of_at_least_32_px() -> void:
	_state.rider_at(0).denarii = 80.0  # a Ballista costs 65 (G2), more than the fixture's 57
	var p := _panel([_rec(SiegeIds.ITEM_BUILD_BALLISTA, 5)])
	assert_gte(p.list.item_font_px, 32)
	assert_eq(p.list.item_count(), p.entries.size())
	var items := p.list.items()
	assert_eq((items[0]["id"] as Dictionary)["item"], SiegeIds.ITEM_BUILD_BALLISTA)
	assert_eq((items[1]["id"] as Dictionary)["item"], SiegeIds.ITEM_SAVE)
	var text: Label = p.list.row(0).find_child("Text", true, false)
	assert_gte(text.label_settings.font_size, 32)
	assert_eq(p.list.highlighted(), 0, "the recommendation is highlighted first")
	assert_eq(p.title_label.text, "Shop: 80 denarii")


func test_the_panel_follows_the_local_trainer_mode() -> void:
	var p := SiegeShopPanel.new()
	assert_true(p.list.follow_local_mode)
	p.free()


func test_a_pick_sends_a_buy_intent_with_the_pad() -> void:
	_state.rider_at(0).denarii = 80.0
	var p := _panel([_rec(SiegeIds.ITEM_BUILD_BALLISTA, 5)])
	p.list.feed_gesture(Wl.G_SURGE)
	var sent := SiegeHudUtil.intents_sent(_game)
	assert_eq(sent.size(), 1)
	assert_eq(sent[0]["k"], "buy")
	assert_eq(sent[0]["item"], SiegeIds.ITEM_BUILD_BALLISTA)
	assert_eq(sent[0]["pad"], 5)
	assert_false(sent[0].has("auto"), "a deliberate pick carries no auto tag")
	assert_false(SiegeIntents.normalize(sent[0])["auto"])


func test_an_erg_auto_confirm_is_tagged_auto() -> void:
	_state.rider_at(0).denarii = 80.0
	var p := _panel([_rec(SiegeIds.ITEM_BUILD_BALLISTA, 5)])
	p.list.erg_auto_confirm = true
	var after := p.list.auto_confirm_after_s()
	var t := 0.0
	while t < after + 0.5 and SiegeHudUtil.intents_sent(_game).is_empty():
		p.list.tick(0.1)
		t += 0.1
	var sent := SiegeHudUtil.intents_sent(_game)
	assert_eq(sent.size(), 1, "auto-confirmed after two scan cycles")
	assert_eq(sent[0]["item"], SiegeIds.ITEM_BUILD_BALLISTA, "the top entry, after two full cycles")
	assert_eq(sent[0]["auto"], 1)
	assert_true(SiegeIntents.normalize(sent[0])["auto"])
	assert_almost_eq(t, after, 0.2)


func test_without_pedal_navigation_the_shop_takes_keyboard_and_controller_only() -> void:
	_state.rider_at(0).denarii = 80.0
	var p := _panel([_rec(SiegeIds.ITEM_BUILD_BALLISTA, 5)], false)
	assert_false(p.list.pedal_nav, "the rider's slot has pedal navigation off")
	p.list.erg_auto_confirm = true
	for _i in 400:
		p.list.tick(0.1)
	p.list.feed_gesture(Wl.G_SURGE)
	assert_eq(SiegeHudUtil.intents_sent(_game).size(), 0, "no scan, no auto-confirm, no surge pick")
	assert_eq(p.list.highlighted(), 0, "the highlight never cycled")
	p.list.feed_action(&"confirm")
	var sent := SiegeHudUtil.intents_sent(_game)
	assert_eq(sent.size(), 1, "confirm still buys")
	assert_eq(sent[0]["item"], SiegeIds.ITEM_BUILD_BALLISTA)
	_game.ctx.local_player().pedal_nav = true
	p.refresh()
	assert_true(p.list.pedal_nav, "turning it on in Settings reaches the open shop")


func test_picking_save_sends_nothing() -> void:
	var p := _panel()
	assert_eq(str((p.list.highlighted_id() as Dictionary)["item"]), SiegeIds.ITEM_SAVE)
	p.list.feed_gesture(Wl.G_SURGE)
	assert_eq(SiegeHudUtil.intents_sent(_game).size(), 0)


func test_a_pick_by_action_is_tagged_action_not_auto() -> void:
	var p := _panel([_rec(SiegeIds.ITEM_REPAIR)])
	p.list.feed_action(&"confirm")
	var sent := SiegeHudUtil.intents_sent(_game)
	assert_eq(sent.size(), 1)
	assert_eq(sent[0]["item"], SiegeIds.ITEM_REPAIR)
	assert_false(sent[0].has("auto"))
	assert_false(sent[0].has("pad"), "repair has no pad")


func test_the_list_is_rebuilt_only_when_its_content_changes() -> void:
	_state.rider_at(0).denarii = 80.0
	var p := _panel([_rec(SiegeIds.ITEM_REPAIR)])
	p.list.set_highlight(2)
	for i in 3:
		p.rebuild(_tx, _state.rider_at(0))
	assert_eq(p.list.highlighted(), 2, "no rebuild, so the scan position stays")
	_state.rider_at(0).denarii = 5.0
	p.rebuild(_tx, _state.rider_at(0))
	assert_eq(
		p.list.highlighted(),
		1,
		"a spend rebuilds from the top: repair is out of reach, Save is next"
	)


func test_the_countdown_shows_in_the_last_10_seconds() -> void:
	_state.phase_duration_s = 180.0
	_state.phase_elapsed_s = 100.0
	var p := _panel()
	assert_false(p.countdown_label.visible)
	_state.phase_elapsed_s = 175.0
	p.refresh()
	assert_true(p.countdown_label.visible)
	assert_eq(p.countdown_label.text, "Shop closes in 5 s")
