extends GutTest
## The shared receipt (brief 2.4 "Shop"): a pick adds to it and holds the picker's gold, your own pick
## again takes it back, someone else's votes no (and again, yes), a majority no or a tie takes the
## item off at once, and what is left is bought in the order it was added when the break ends.

const BAND := SiegeIds.STATION_BALLISTA


func _rig(humans: int = 2, bots: int = 0, gold: float = 200.0) -> SiegeRig:
	var rig := SiegeRig.new("short", humans, bots)
	rig.power_pct = 0.0  # nobody pedals into the mine, so the gold in these tests is exact
	rig.enter(1, 0.0)
	rig.manual()
	for r in rig.state.riders:
		r.gold = gold
	return rig


func _pick(rig: SiegeRig, peer: int, item: String, at: int = 0) -> Array[Dictionary]:
	rig.send(peer, SiegeIntents.pick(item, at))
	return rig.step()


func _acts(events: Array, act: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in events:
		if e["type"] == SiegeIds.EV_RECEIPT and int(e["act"]) == act:
			out.append(e)
	return out


func _keys(rig: SiegeRig) -> Array[String]:
	var out: Array[String] = []
	for line in rig.state.receipt:
		out.append(line.key())
	return out


# --- add, hold, take back ------------------------------------------------------------------------


func test_a_pick_goes_on_the_receipt_and_holds_the_pickers_gold() -> void:
	var rig := _rig()
	var ev := _pick(rig, 1, SiegeIds.ITEM_UPGRADE, BAND)
	assert_eq(_keys(rig), ["upgrade/1"])
	assert_eq(rig.state.receipt[0].cost, 40)
	assert_eq(rig.state.receipt[0].slot, 0)
	assert_eq(rig.rider(1).gold, 200.0, "nothing is spent yet")
	assert_eq(rig.state.held_by(0), 40)
	assert_eq(rig.state.spendable(rig.rider(1)), 160.0)
	assert_eq(rig.state.spendable(rig.rider(2)), 200.0, "the other rider's gold is theirs")
	assert_eq(rig.state.station(BAND).level, 0, "no upgrade yet")
	var added := _acts(ev, SiegeIds.RC_ADD)
	assert_eq(added.size(), 1)
	assert_eq(added[0]["item"], SiegeIds.ITEM_UPGRADE)
	assert_eq(int(added[0]["station"]), BAND)
	assert_eq(int(added[0]["picker"]), 0)
	assert_eq(SiegeEvents.check(added[0]), "")


func test_picking_your_own_item_again_takes_it_back() -> void:
	var rig := _rig()
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	assert_eq(rig.state.held_by(0), 60)
	var ev := _pick(rig, 1, SiegeIds.ITEM_MINE)
	assert_eq(_keys(rig), [])
	assert_eq(rig.state.held_by(0), 0, "the gold is free again")
	assert_eq(_acts(ev, SiegeIds.RC_TAKE).size(), 1)
	assert_eq(rig.rider(1).gold, 200.0)


func test_a_pick_never_takes_more_gold_than_the_picker_has_free() -> void:
	var rig := _rig(1, 0, 100.0)
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	assert_eq(rig.state.spendable(rig.rider(1)), 40.0)
	_pick(rig, 1, SiegeIds.ITEM_UPGRADE, BAND)
	assert_eq(_keys(rig), ["mine/0", "upgrade/1"], "40 is exactly enough")
	assert_eq(rig.state.spendable(rig.rider(1)), 0.0)
	var ev := _pick(rig, 1, SiegeIds.ITEM_CAULDRON)
	var refused := rig.of_type(SiegeIds.EV_BUY, ev)
	assert_eq(refused.size(), 1)
	assert_eq(refused[0]["why"], SiegeIds.BUY_FUNDS)
	assert_eq(_keys(rig), ["mine/0", "upgrade/1"])
	assert_gte(rig.state.spendable(rig.rider(1)), 0.0)


func test_held_gold_can_never_pass_the_riders_gold() -> void:
	var rig := _rig(1, 0, 130.0)
	for item: String in [
		SiegeIds.ITEM_MINE, SiegeIds.ITEM_CAULDRON, SiegeIds.ITEM_RESERVE, SiegeIds.ITEM_IRON_BANDS
	]:
		_pick(rig, 1, item)
		assert_lte(float(rig.state.held_by(0)), rig.rider(1).gold)
	assert_eq(_keys(rig), ["mine/0", "spare_cauldron/0"], "60 + 60, the next 80 and 45 don't fit")


func test_an_item_can_not_be_on_the_receipt_twice() -> void:
	var rig := _rig(3)
	_pick(rig, 1, SiegeIds.ITEM_IRON_BANDS)
	_pick(rig, 2, SiegeIds.ITEM_IRON_BANDS)
	assert_eq(rig.state.receipt.size(), 1, "the second pick of it is a vote, not a second line")
	assert_eq(rig.state.receipt[0].no, [1])


func test_nothing_goes_on_the_receipt_past_its_limit() -> void:
	var rig := _rig(1)
	rig.state.iron_bands = 2
	var ev := _pick(rig, 1, SiegeIds.ITEM_IRON_BANDS)
	assert_eq(rig.of_type(SiegeIds.EV_BUY, ev)[0]["why"], SiegeIds.BUY_LIMIT)
	ev = _pick(rig, 1, SiegeIds.ITEM_REPAIR)
	assert_eq(rig.of_type(SiegeIds.EV_BUY, ev)[0]["why"], SiegeIds.BUY_GATE_FULL)
	rig.state.station(BAND).level = 3
	ev = _pick(rig, 1, SiegeIds.ITEM_UPGRADE, BAND)
	assert_eq(rig.of_type(SiegeIds.EV_BUY, ev)[0]["why"], SiegeIds.BUY_MAX_LEVEL)
	rig.state.perks.append(SiegeIds.PERK_RESERVE)
	ev = _pick(rig, 1, SiegeIds.ITEM_RESERVE)
	assert_eq(rig.of_type(SiegeIds.EV_BUY, ev)[0]["why"], SiegeIds.BUY_LIMIT)
	ev = _pick(rig, 1, SiegeIds.ITEM_SCORPION, 1)
	assert_eq(rig.of_type(SiegeIds.EV_BUY, ev)[0]["why"], SiegeIds.BUY_PAD_TAKEN)
	ev = _pick(rig, 1, SiegeIds.ITEM_PAD_UPGRADE, 4)
	assert_eq(rig.of_type(SiegeIds.EV_BUY, ev)[0]["why"], SiegeIds.BUY_NO_PAD)
	assert_eq(rig.state.receipt.size(), 0)


func test_two_scorpions_for_the_same_pad_are_one_line() -> void:
	var rig := _rig(3)
	_pick(rig, 1, SiegeIds.ITEM_SCORPION, 2)
	_pick(rig, 2, SiegeIds.ITEM_SCORPION, 2)
	_pick(rig, 1, SiegeIds.ITEM_SCORPION, 3)
	assert_eq(_keys(rig), ["scorpion/2", "scorpion/3"])


func test_a_pick_while_the_shop_is_closed_is_ignored() -> void:
	var rig := SiegeRig.new("short", 1)
	rig.manual()
	rig.rider().gold = 500.0
	var ev := _pick(rig, 1, SiegeIds.ITEM_MINE)
	assert_eq(rig.state.receipt.size(), 0)
	assert_eq(rig.of_type(SiegeIds.EV_BUY, ev), [], "no refusal event either")
	assert_eq(rig.of_type(SiegeIds.EV_RECEIPT, ev), [])
	rig.enter(2, 0.0)
	assert_eq(rig.state.role, SiegeIds.ROLE_WAVE)
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	assert_eq(rig.state.receipt.size(), 0)


func test_an_auto_confirmed_pick_never_reaches_the_receipt() -> void:
	var rig := _rig(1)
	rig.send(1, SiegeIntents.pick(SiegeIds.ITEM_MINE, 0, true))
	var ev := rig.step()
	assert_eq(rig.state.receipt.size(), 0)
	assert_eq(rig.of_type(SiegeIds.EV_RECEIPT, ev), [])
	assert_eq(rig.of_type(SiegeIds.EV_BUY, ev), [])
	rig.rider().shop_fallback = true
	rig.send(1, SiegeIntents.pick(SiegeIds.ITEM_MINE, 0, true))
	rig.step()
	assert_true(rig.rider().shop_fallback, "an auto pick never ends the fallback either")
	assert_eq(rig.state.receipt.size(), 0)


func test_a_manual_pick_ends_the_shop_fallback() -> void:
	var rig := _rig(1)
	rig.rider().shop_fallback = true
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	assert_false(rig.rider().shop_fallback)


# --- the vote ---------------------------------------------------------------------------------------


func test_picking_someone_elses_item_votes_no_and_again_returns_yes() -> void:
	var rig := _rig(3)
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	var ev := _pick(rig, 2, SiegeIds.ITEM_MINE)
	assert_eq(rig.state.receipt[0].no, [1])
	var no := _acts(ev, SiegeIds.RC_NO)
	assert_eq(no.size(), 1)
	assert_eq(int(no[0]["no"]), 1)
	assert_eq(int(no[0]["yes"]), 2)
	assert_eq(rig.state.held_by(0), 60, "still held: one no of three is not enough")
	ev = _pick(rig, 2, SiegeIds.ITEM_MINE)
	assert_eq(rig.state.receipt[0].no, [])
	assert_eq(_acts(ev, SiegeIds.RC_YES).size(), 1)


func test_a_majority_no_takes_the_item_off_and_returns_the_gold() -> void:
	var rig := _rig(3)
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	_pick(rig, 2, SiegeIds.ITEM_MINE)
	var ev := _pick(rig, 3, SiegeIds.ITEM_MINE)
	assert_eq(rig.state.receipt.size(), 0, "two no against one yes")
	assert_eq(_acts(ev, SiegeIds.RC_REJECT).size(), 1)
	assert_eq(int(_acts(ev, SiegeIds.RC_REJECT)[0]["picker"]), 0)
	assert_eq(rig.state.spendable(rig.rider(1)), 200.0)
	assert_eq(rig.rider(1).gold, 200.0)


func test_a_tie_rejects_with_two_riders() -> void:
	var rig := _rig(2)
	_pick(rig, 1, SiegeIds.ITEM_CAULDRON)
	var ev := _pick(rig, 2, SiegeIds.ITEM_CAULDRON)
	assert_eq(rig.state.receipt.size(), 0, "1 yes, 1 no is a tie")
	assert_eq(_acts(ev, SiegeIds.RC_REJECT).size(), 1)
	assert_eq(_acts(ev, SiegeIds.RC_NO).size(), 1, "the no that did it is on record first")


func test_four_riders_need_two_no_votes() -> void:
	var rig := _rig(4)
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	_pick(rig, 2, SiegeIds.ITEM_MINE)
	assert_eq(rig.state.receipt.size(), 1, "3 yes, 1 no")
	_pick(rig, 3, SiegeIds.ITEM_MINE)
	assert_eq(rig.state.receipt.size(), 0, "2 yes, 2 no is a tie")


func test_a_solo_riders_own_pick_never_rejects() -> void:
	var rig := _rig(1)
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	rig.run(5.0)
	assert_eq(_keys(rig), ["mine/0"])
	var tv := rig.state.vote_on(rig.state.receipt[0])
	assert_eq(tv.yes_count(), 1)
	assert_eq(tv.no_count(), 0)
	assert_false(tv.rejected())
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	assert_eq(_keys(rig), [], "pick again is the take-back, never a no vote")


func test_bots_vote_yes_and_a_human_can_still_vote_no_on_theirs() -> void:
	var rig := _rig(1, 2)
	var bot := rig.state.riders[1]
	assert_true(bot.is_bot)
	rig.send(bot.peer, SiegeIntents.pick(SiegeIds.ITEM_MINE))
	rig.step()
	assert_eq(rig.state.receipt.size(), 1, "a bot's pick goes on the receipt")
	assert_eq(rig.state.receipt[0].slot, bot.slot)
	var tv := rig.state.vote_on(rig.state.receipt[0])
	assert_eq(tv.yes_count(), 3, "everyone is a yes until they say no")
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	assert_eq(rig.state.receipt.size(), 1, "one no of three")
	assert_eq(rig.state.receipt[0].no, [0])


func test_a_rejected_item_leaves_no_trace_and_can_be_picked_again() -> void:
	var rig := _rig(2)
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	_pick(rig, 2, SiegeIds.ITEM_MINE)
	assert_eq(rig.state.receipt.size(), 0)
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	assert_eq(_keys(rig), ["mine/0"], "a fresh line, with no old votes")
	assert_eq(rig.state.receipt[0].no, [])


# --- the break ends ---------------------------------------------------------------------------------


func test_the_receipt_is_bought_in_the_order_it_was_added() -> void:
	var rig := _rig(2)
	_pick(rig, 2, SiegeIds.ITEM_MINE)
	_pick(rig, 1, SiegeIds.ITEM_UPGRADE, BAND)
	_pick(rig, 2, SiegeIds.ITEM_CAULDRON)
	assert_eq(rig.state.receipt_total(), 160)
	rig.goto(rig.phase_start(2))
	var ev := rig.step()
	var buys := rig.of_type(SiegeIds.EV_BUY, ev)
	assert_eq(buys.size(), 3)
	assert_eq(
		[buys[0]["item"], buys[1]["item"], buys[2]["item"]], ["mine", "upgrade", "spare_cauldron"]
	)
	assert_eq([int(buys[0]["slot"]), int(buys[1]["slot"]), int(buys[2]["slot"])], [1, 0, 1])
	for b in buys:
		assert_eq(int(b["ok"]), 1)
	assert_eq(rig.state.receipt.size(), 0, "the receipt is empty after")
	assert_eq(rig.state.mine_level, 1)
	assert_eq(rig.state.station(BAND).level, 1)
	assert_true(rig.state.perks.has(SiegeIds.PERK_CAULDRON))
	assert_almost_eq(rig.rider(1).gold, 160.0, 5.0, "slot 0 paid the upgrade")
	assert_almost_eq(rig.rider(2).gold, 80.0, 5.0, "slot 1 paid the mine level and the cauldron")


func test_two_picks_in_one_tick_are_bought_in_slot_order() -> void:
	var rig := _rig(2)
	rig.send(2, SiegeIntents.pick(SiegeIds.ITEM_MINE))
	rig.send(1, SiegeIntents.pick(SiegeIds.ITEM_CAULDRON))
	rig.step()
	assert_eq(
		_keys(rig), ["spare_cauldron/0", "mine/0"], "slot order inside a tick, not send order"
	)


func test_gold_is_spent_when_the_break_ends_and_never_goes_negative() -> void:
	var rig := _rig(1, 0, 100.0)
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	_pick(rig, 1, SiegeIds.ITEM_UPGRADE, BAND)
	assert_eq(rig.rider(1).gold, 100.0)
	rig.goto(rig.phase_start(2))
	rig.step()
	assert_almost_eq(rig.rider(1).gold, 0.0, 1.0)
	assert_gte(rig.rider(1).gold, 0.0)


func test_the_break_ending_with_an_empty_receipt_buys_nothing() -> void:
	var rig := _rig(2)
	rig.goto(rig.phase_start(2))
	var ev := rig.step()
	assert_eq(rig.of_type(SiegeIds.EV_BUY, ev), [])
	assert_eq(rig.of_type(SiegeIds.EV_RECEIPT, ev), [])
	assert_eq(rig.rider(1).gold, 200.0)


func test_a_voted_off_item_is_never_bought() -> void:
	var rig := _rig(2)
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	_pick(rig, 2, SiegeIds.ITEM_MINE)
	_pick(rig, 1, SiegeIds.ITEM_CAULDRON)
	rig.goto(rig.phase_start(2))
	rig.step()
	assert_eq(rig.state.mine_level, 0)
	assert_true(rig.state.perks.has(SiegeIds.PERK_CAULDRON))


func test_the_build_break_is_bought_at_its_end_too() -> void:
	var rig := SiegeRig.new("short", 1)
	rig.state.role = SiegeIds.ROLE_BUILD_BREAK
	rig.rider().gold = 100.0
	var events: Array[Dictionary] = []
	assert_true(SiegeReceipt.add(rig.state, rig.rider(), SiegeIds.ITEM_MINE, 0, 0, events))
	assert_eq(rig.state.receipt.size(), 1)
	SiegeReceipt.buy_all(rig.state, events)
	assert_eq(rig.state.mine_level, 1)
	assert_eq(rig.state.receipt.size(), 0)


func test_a_purchase_the_state_no_longer_allows_is_refused_and_costs_nothing() -> void:
	var rig := _rig(1, 0, 100.0)
	_pick(rig, 1, SiegeIds.ITEM_RESERVE)
	rig.state.perks.append(SiegeIds.PERK_RESERVE)
	var events: Array[Dictionary] = []
	SiegeReceipt.buy_all(rig.state, events)
	assert_eq(int(events[0]["ok"]), 0)
	assert_eq(events[0]["why"], SiegeIds.BUY_LIMIT)
	assert_eq(rig.rider(1).gold, 100.0)


# --- a rider leaves ---------------------------------------------------------------------------------


func test_a_rider_who_leaves_takes_their_items_off_and_keeps_their_gold() -> void:
	var rig := _rig(3)
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	_pick(rig, 3, SiegeIds.ITEM_CAULDRON)
	_pick(rig, 2, SiegeIds.ITEM_CAULDRON)
	assert_eq(_keys(rig), ["mine/0", "spare_cauldron/0"], "one no of three on the cauldron")
	rig.connected[3] = false
	var ev := rig.step()
	assert_eq(_keys(rig), ["mine/0"], "slot 2's item left with them")
	assert_eq(_acts(ev, SiegeIds.RC_DROP).size(), 1)
	assert_eq(rig.rider(3).gold, 200.0, "their gold was never spent")


func test_a_voter_who_leaves_changes_the_count() -> void:
	var rig := _rig(3)
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	_pick(rig, 2, SiegeIds.ITEM_MINE)
	assert_eq(rig.state.receipt.size(), 1, "one no of three")
	rig.connected[3] = false
	var ev := rig.step()
	assert_eq(rig.state.receipt.size(), 0, "two voters left: 1 yes, 1 no is a tie")
	assert_eq(_acts(ev, SiegeIds.RC_REJECT).size(), 1)


func test_a_leaving_voters_no_is_dropped() -> void:
	var rig := _rig(3)
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	_pick(rig, 2, SiegeIds.ITEM_MINE)
	rig.connected[2] = false
	rig.step()
	assert_eq(rig.state.receipt.size(), 1)
	assert_eq(rig.state.receipt[0].no, [], "their no left with them")


func test_a_disconnected_rider_cannot_pick() -> void:
	var rig := _rig(2)
	rig.connected[2] = false
	rig.step()
	_pick(rig, 2, SiegeIds.ITEM_MINE)
	assert_eq(rig.state.receipt.size(), 0)


# --- determinism ------------------------------------------------------------------------------------


func _script(rig: SiegeRig) -> Array:
	var log: Array = []
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	_pick(rig, 2, SiegeIds.ITEM_UPGRADE, BAND)
	_pick(rig, 3, SiegeIds.ITEM_MINE)
	_pick(rig, 3, SiegeIds.ITEM_UPGRADE, BAND)
	_pick(rig, 2, SiegeIds.ITEM_MINE)
	rig.run(10.0)
	rig.goto(rig.phase_start(2))
	rig.step()
	for e: Dictionary in rig.events:
		if e["type"] == SiegeIds.EV_RECEIPT or e["type"] == SiegeIds.EV_BUY:
			log.append(e)
	return log


func test_a_replay_gives_the_same_receipt_events_and_state() -> void:
	var a := _rig(3, 1)
	var b := _rig(3, 1)
	var la := _script(a)
	var lb := _script(b)
	assert_gt(la.size(), 4)
	assert_eq(la, lb)
	assert_eq(SiegeSnapshot.encode(a.state), SiegeSnapshot.encode(b.state))
	assert_eq(a.state.mine_level, b.state.mine_level)


# --- Autopilot and bots -----------------------------------------------------------------------------


func test_autopilot_adds_its_picks_to_the_receipt_and_buys_them_at_the_end() -> void:
	var rig := SiegeRig.new("short", 1, 1)
	rig.enter(1, 0.0)
	for r in rig.state.riders:
		r.gold = 1000.0
	rig.run(12.0)
	assert_eq(rig.state.receipt.size(), 4, "two each, still on the receipt")
	for r in rig.state.riders:
		assert_gte(r.gold, 1000.0, "nothing spent mid-break")
	assert_gt(rig.state.receipt_total(), 0)
	rig.goto(rig.phase_start(2))
	var ev := rig.step()
	assert_eq(rig.of_type(SiegeIds.EV_BUY, ev).size(), 4)
	assert_eq(rig.state.receipt.size(), 0)


func test_autopilot_does_not_pick_what_is_on_the_receipt() -> void:
	var rig := _rig(2)
	var blind := SiegeAutopilot.shop_picks(rig.state, rig.rider(1), 1, true)
	assert_eq(blind.size(), 1)
	var first := blind[0]
	_pick(rig, 2, str(first["item"]), SiegeIntents.at_of(first))
	var then := SiegeAutopilot.shop_picks(rig.state, rig.rider(1), 1)
	assert_eq(then.size(), 1)
	assert_ne(
		SiegeReceiptLine.key_of(str(then[0]["item"]), SiegeIntents.at_of(then[0])),
		SiegeReceiptLine.key_of(str(first["item"]), SiegeIntents.at_of(first)),
		"the next pick is a different item"
	)


func test_autopilot_picks_only_what_the_rider_has_free() -> void:
	var rig := _rig(1, 0, 60.0)
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	var picks := SiegeAutopilot.shop_picks(rig.state, rig.rider(1), 2)
	assert_eq(picks, [], "60 is all held: nothing left to pick")
	var blind := SiegeAutopilot.shop_picks(rig.state, rig.rider(1), 1, true)
	assert_eq(blind.size(), 1, "the list's own pick ignores the receipt")


# --- the wire ---------------------------------------------------------------------------------------


func test_the_receipt_survives_a_snapshot_round_trip_with_its_votes() -> void:
	var rig := _rig(3)
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	_pick(rig, 2, SiegeIds.ITEM_MINE)
	_pick(rig, 3, SiegeIds.ITEM_SCORPION, 3)
	var snap := SiegeSnapshot.encode(rig.state)
	assert_eq(snap["rc"], [[2, 0, 60, 0, 1], [3, 3, 40, 2]])
	var fresh := SiegeKit.state("short", 3)
	SiegeSnapshot.apply(fresh, JSON.parse_string(JSON.stringify(snap)))
	assert_eq(fresh.receipt.size(), 2)
	assert_eq(fresh.receipt[0].key(), "mine/0")
	assert_eq(fresh.receipt[0].no, [1])
	assert_eq(fresh.receipt[1].key(), "scorpion/3")
	assert_eq(fresh.receipt[1].cost, 40)
	assert_eq(fresh.receipt[1].slot, 2)
	assert_eq(fresh.held_by(0), 60)
	assert_eq(fresh.vote_on(fresh.receipt[0]).no_count(), 1)


func test_an_empty_receipt_adds_no_key_and_clears_a_clients_old_one() -> void:
	var rig := _rig(2)
	assert_false(SiegeSnapshot.encode(rig.state).has("rc"))
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	var client := SiegeKit.state("short", 2)
	SiegeSnapshot.apply(client, SiegeSnapshot.encode(rig.state))
	assert_eq(client.receipt.size(), 1)
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	SiegeSnapshot.apply(client, SiegeSnapshot.encode(rig.state))
	assert_eq(client.receipt.size(), 0)


func test_a_hostile_receipt_snapshot_is_read_safely() -> void:
	var client := SiegeKit.state("short", 2)
	var rig := _rig(2)
	var snap := SiegeSnapshot.encode(rig.state)
	var rows: Array = [
		null,
		"x",
		[],
		[1, 2, 3],
		[99, 0, 40, 0],
		[1, 0, 40, 9],
		[1, 0, -5, 0, 0, 0, 1, 1, 1, 1, 1],
		[1, 0, 60, 0, "a", 99, 1.5],
		[1, 0, 60, 0],
		[[1]],
	]
	for i in 100:
		rows.append([2, 0, 60, 1])
	snap["rc"] = rows
	SiegeSnapshot.apply(client, snap)
	assert_lte(client.receipt.size(), 3)
	for line in client.receipt:
		assert_true(SiegeIds.ITEMS.has(line.item))
		assert_gte(line.cost, 0)
		assert_false(line.no.has(line.slot))
	snap["rc"] = "nope"
	SiegeSnapshot.apply(client, snap)
	assert_eq(client.receipt.size(), 0)


func test_the_receipt_event_checks_out_and_a_junk_one_does_not() -> void:
	var ev := SiegeEvents.receipt(0, "mine", 0, 0, SiegeIds.RC_ADD, 0, 1, 0)
	assert_eq(SiegeEvents.check(ev), "")
	var bad := ev.duplicate()
	bad["item"] = 5
	assert_ne(SiegeEvents.check(bad), "")
	bad = ev.duplicate()
	bad.erase("act")
	assert_ne(SiegeEvents.check(bad), "")
	assert_true(SiegeEvents.int_fields().has(SiegeIds.EV_RECEIPT))


func test_the_state_round_trips_its_receipt_through_a_dict() -> void:
	var rig := _rig(2)
	_pick(rig, 1, SiegeIds.ITEM_MINE)
	_pick(rig, 2, SiegeIds.ITEM_MINE)
	_pick(rig, 2, SiegeIds.ITEM_CAULDRON)
	var back := SiegeState.from_dict(rig.state.to_dict(), rig.content)
	assert_eq(back.receipt.size(), 1, "the mine was voted off by the tie")
	assert_eq(back.receipt[0].key(), "spare_cauldron/0")
	assert_eq(back.receipt[0].cost, 60)
