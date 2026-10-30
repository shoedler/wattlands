extends GutTest
## Review fixes in the HUD: every item the shop sells is reachable, a recommended pad item stays
## on top, no rush warning without a rush ahead, and the Overdrive button follows the rules'
## preconditions.

const F := preload("res://tests/games/siege/siege_fakes.gd")
const FIX := preload("res://tests/games/siege/fixtures/siege_fixtures.gd")


func _break_game(gold: float = 5000.0) -> SiegeGame:
	var st := FIX.mid_wave()
	st.role = SiegeIds.ROLE_BREAK
	st.phase_kind = Wl.RECOVERY
	st.phase_elapsed_s = 20.0
	st.enemies.clear()
	st.rider_at(0).gold = gold
	var g := F.make_game(F.make_ctx(3, 1, "vo2", Wl.SOLO, 1))
	g.state = st
	g.content = st.content
	return g


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
		if int(panel.get("page")) == 0:
			break
	return seen


func test_every_item_the_rules_sell_is_reachable_in_the_shop() -> void:
	var g := _break_game()
	var st := g.state
	var panel := SiegeShopPanel.new()
	panel.game = g
	panel.picks_override = []
	add_child_autofree(panel)
	panel.refresh()
	assert_true(panel.visible)
	assert_lte(panel.list.item_count(), 4, "a page holds four rows at 32 px")
	var want := _sellable(st, 0)
	assert_gt(want.size(), 8)
	var seen := _listed(panel)
	var missing := []
	for k: String in want:
		if not seen.has(k):
			missing.append(k)
	assert_eq(missing, [], "every purchasable item is reachable")
	assert_eq(str(panel.list.items()[0]["id"]["item"]), SiegeIds.ITEM_SAVE, "back on page one")
	F.free_game(g)


func test_a_recommended_scorpion_stays_on_top() -> void:
	var g := _break_game(100.0)
	var pick := SiegeIntents.normalize(SiegeIntents.buy(SiegeIds.ITEM_SCORPION, 3, true))
	var rows := SiegeShopModel.entries(g.state, g.state.rider_at(0), GameStrings.new(), [pick])
	assert_eq(str(rows[0]["id"]["item"]), SiegeIds.ITEM_SCORPION)
	assert_eq(int(rows[0]["id"]["at"]), 3)
	assert_true(bool(rows[0]["recommended"]))
	assert_eq(str(rows[1]["id"]["item"]), SiegeIds.ITEM_SAVE)
	F.free_game(g)


func _rush_state() -> SiegeState:
	var st := SiegeKit.state("endurance")
	var phases: Array = st.content.shift["phases"]
	for i in phases.size():
		if not (phases[i] as Dictionary).get("rushes_at_s", []).is_empty():
			st.phase_index = i
			st.phase_duration_s = float(phases[i]["duration_s"])
			break
	st.enemies.clear()
	return st


func test_no_rush_warning_without_a_rush_ahead() -> void:
	var st := _rush_state()
	var rushes := SiegeHudModel.rush_times(st)
	assert_gt(rushes.size(), 1, "the endurance wave has rushes")
	# a restarted client: rush_next 0, the first rush long past, the next one far off
	st.wave.rush_next = 0
	st.phase_elapsed_s = rushes[0] + 40.0
	if rushes[1] - st.phase_elapsed_s <= 15.0:
		st.phase_elapsed_s = rushes[0] + 1.0
	var w := SiegeHudModel.warning(st)
	assert_false(not w.is_empty() and w["key"] == "SIEGE_WARN_RUSH", "no warning for a past rush")
	# 10 s before the next rush it warns
	st.phase_elapsed_s = rushes[1] - 10.0
	w = SiegeHudModel.warning(st)
	assert_eq(w.get("key", ""), "SIEGE_WARN_RUSH")


func test_overdrive_button_follows_the_rules_preconditions() -> void:
	var st := FIX.mid_wave()
	var g := F.make_game(F.make_ctx(3, 1, "vo2", Wl.SOLO, 1))
	g.state = st
	g.content = st.content
	var r := st.rider(1)
	r.od_state = SiegeIds.OD_READY
	r.od_prompt = false
	r.rescue = false
	r.raw_w = 220.0
	r.cadence_rpm = 90.0
	assert_true(bool(SiegeHudModel.overdrive_face(g)["enabled"]), "ready in a WORK wave")
	r.rescue = true
	assert_false(bool(SiegeHudModel.overdrive_face(g)["enabled"]), "never in rescue")
	r.rescue = false
	st.phase_remaining_s = 20.0
	st.phase_elapsed_s = st.phase_duration_s - 20.0
	assert_false(bool(SiegeHudModel.overdrive_face(g)["enabled"]), "not with < 30 s left")
	st.phase_remaining_s = 70.0
	st.phase_elapsed_s = 50.0
	st.phase_kind = Wl.RECOVERY
	assert_false(bool(SiegeHudModel.overdrive_face(g)["enabled"]), "only in WORK")
	F.free_game(g)


func test_auto_confirm_on_a_later_page_turns_back_instead_of_buying() -> void:
	var g := _break_game()
	var panel := SiegeShopPanel.new()
	panel.game = g
	panel.picks_override = []
	add_child_autofree(panel)
	panel.refresh()
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
	F.free_game(g)
