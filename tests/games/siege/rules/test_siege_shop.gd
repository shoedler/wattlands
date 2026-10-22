extends GutTest
## SiegeShop (brief 2.4 "Shop", 2.5 "Zero input"): every item with its price and limit, the buy
## event, the order of purchases, and Autopilot's picks for riders on the shop fallback.

var _rig: SiegeRig


func after_each() -> void:
	SiegeRouting.route_hook = Callable()
	SiegeShop.shop_hook = Callable()


## A break (phase 1 = the build break, 3 = break 1) with riders holding 1000 denarii and no
## fallbacks.
func _shop(phase: int = 1, humans: int = 2, denarii: float = 1000.0) -> SiegeRig:
	_rig = SiegeRig.new("short", humans)
	for p in _rig.slots:
		_rig.power_w[p.peer_id] = 0.0
		_rig.p_eff[p.peer_id] = 0.0
	_rig.enter(phase, 1.0)
	for r in _rig.state.riders:
		r.route_fallback = false
		r.shop_fallback = false
		r.denarii = denarii
	return _rig


func _buy(peer: int, item: String, pad: int = 0, auto: bool = false) -> Dictionary:
	var before := _rig.events.size()
	_rig.send(peer, SiegeIntents.buy(item, pad, auto))
	_rig.step()
	for i in range(before, _rig.events.size()):
		if _rig.events[i]["type"] == SiegeIds.EV_BUY:
			return _rig.events[i]
	return {}


func test_riders_start_with_40_denarii_and_two_towers() -> void:
	_rig = SiegeRig.new("short", 2)
	for r in _rig.state.riders:
		assert_eq(r.denarii, 40.0)
	assert_eq(_rig.state.pad(3).type, SiegeIds.TOWER_BALLISTA)
	assert_eq(_rig.state.pad(4).type, SiegeIds.TOWER_SCORPION)
	assert_eq(_rig.state.built_pads(), [3, 4] as Array[int])
	assert_eq(_rig.state.gen_level, 0)
	assert_eq(_rig.state.perks, [] as Array[int])


func test_the_shop_is_open_in_every_break_including_the_build_break() -> void:
	for phase in [1, 3, 5]:
		_shop(phase)
		assert_true(_rig.state.shop_open(), "phase %d" % phase)
		var ev := _buy(1, SiegeIds.ITEM_REPAIR)
		assert_eq(ev["why"] if ev.has("why") else "", SiegeIds.BUY_GATE_FULL, "answered")


func test_the_shop_is_closed_in_waves_and_the_cooldown() -> void:
	for phase in [0, 2, 4, 6, 7]:
		_shop(phase)
		_rig.state.gate_hp = 50.0
		var ev := _buy(1, SiegeIds.ITEM_REPAIR)
		assert_eq(ev["ok"], 0, "phase %d" % phase)
		assert_eq(ev["why"], SiegeIds.BUY_CLOSED)
		assert_eq(ev["slot"], 0)
		assert_eq(_rig.state.gate_hp, 50.0)
		assert_eq(_rig.rider(1).denarii, 1000.0)


func test_building_costs_50_40_and_35() -> void:
	_shop()
	var want := {
		SiegeIds.ITEM_BUILD_BALLISTA: [SiegeIds.TOWER_BALLISTA, 50],
		SiegeIds.ITEM_BUILD_SCORPION: [SiegeIds.TOWER_SCORPION, 40],
		SiegeIds.ITEM_BUILD_CALTROP: [SiegeIds.TOWER_CALTROP, 35],
	}
	var pads: Array[int] = [1, 2, 5]
	var n := 0
	for item: String in want:
		var pad := pads[n]
		n += 1
		var before := _rig.rider(1).denarii
		var ev := _buy(1, item, pad)
		assert_eq([ev["ok"], ev["item"], ev["pad"], ev["slot"]], [1, item, pad, 0])
		assert_eq(ev["why"], "")
		assert_eq(_rig.state.pad(pad).type, want[item][0])
		assert_eq(_rig.state.pad(pad).level, 0)
		assert_eq(_rig.state.pad(pad).built_by, 0)
		assert_eq(before - _rig.rider(1).denarii, float(want[item][1]))
	assert_eq(_rig.rider(1).towers_built, 3)


func test_a_built_pad_is_refused() -> void:
	_shop()
	var ev := _buy(1, SiegeIds.ITEM_BUILD_CALTROP, 3)
	assert_eq([ev["ok"], ev["why"], ev["lvl"]], [0, SiegeIds.BUY_PAD_TAKEN, 0])
	assert_eq(_rig.state.pad(3).type, SiegeIds.TOWER_BALLISTA)
	assert_eq(_rig.rider(1).denarii, 1000.0)


func test_not_enough_denarii_is_refused_with_the_buyers_slot() -> void:
	_shop(1, 2, 39.0)
	var ev := _buy(2, SiegeIds.ITEM_BUILD_SCORPION, 1)
	assert_eq([ev["ok"], ev["why"], ev["slot"]], [0, SiegeIds.BUY_FUNDS, 1])
	assert_eq(_rig.state.pad(1).type, SiegeIds.TOWER_NONE)
	assert_eq(_rig.rider(2).denarii, 39.0)
	_rig.rider(2).denarii = 40.0
	assert_eq(_buy(2, SiegeIds.ITEM_BUILD_SCORPION, 1)["ok"], 1, "exactly 40 is enough")
	assert_eq(_rig.rider(2).denarii, 0.0)


func test_denarii_are_personal_but_anyone_may_buy_anything() -> void:
	_shop()
	_rig.rider(1).denarii = 10.0
	var ev := _buy(2, SiegeIds.ITEM_BUILD_BALLISTA, 5)
	assert_eq(ev["ok"], 1)
	assert_eq(_rig.rider(1).denarii, 10.0)
	assert_eq(_rig.rider(2).denarii, 950.0)
	assert_eq(_rig.state.pad(5).built_by, 1)


func test_upgrades_cost_40_50_70_in_order() -> void:
	_shop()
	var costs := [40, 50, 70]
	for lvl in 3:
		var before := _rig.rider(1).denarii
		var ev := _buy(1, SiegeIds.ITEM_UPGRADE, 3)
		assert_eq([ev["ok"], ev["lvl"], ev["pad"]], [1, lvl + 1, 3])
		assert_eq(_rig.state.pad(3).level, lvl + 1)
		assert_eq(before - _rig.rider(1).denarii, float(costs[lvl]))
	var ev := _buy(1, SiegeIds.ITEM_UPGRADE, 3)
	assert_eq([ev["ok"], ev["why"]], [0, SiegeIds.BUY_MAX_LEVEL])
	assert_eq(_buy(1, SiegeIds.ITEM_UPGRADE, 6)["why"], SiegeIds.BUY_NO_TOWER, "an empty pad")


func test_generator_levels_cost_60_90_130_and_pay_20_percent_more_each() -> void:
	_shop()
	var costs := [60, 90, 130]
	for lvl in 3:
		var before := _rig.rider(1).denarii
		var ev := _buy(1, SiegeIds.ITEM_GENERATOR)
		assert_eq([ev["ok"], ev["lvl"]], [1, lvl + 1])
		assert_eq(_rig.state.gen_level, lvl + 1)
		assert_eq(before - _rig.rider(1).denarii, float(costs[lvl]))
	assert_eq(_buy(1, SiegeIds.ITEM_GENERATOR)["why"], SiegeIds.BUY_MAX_LEVEL)
	assert_eq(_rig.state.gen_level, 3)


func test_iron_bands_add_25_to_max_and_current_hp_twice() -> void:
	_shop()
	_rig.state.gate_hp = 60.0
	var ev := _buy(1, SiegeIds.ITEM_IRON_BANDS)
	assert_eq([ev["ok"], ev["lvl"]], [1, 1])
	assert_eq(_rig.state.gate_max, 125.0)
	assert_eq(_rig.state.gate_hp, 85.0)
	assert_eq(_rig.state.iron_bands, 1)
	assert_eq(_rig.rider(1).denarii, 1000.0 - 45.0)
	_buy(1, SiegeIds.ITEM_IRON_BANDS)
	assert_eq(_rig.state.gate_max, 150.0)
	assert_eq(_rig.state.gate_hp, 110.0)
	var third := _buy(1, SiegeIds.ITEM_IRON_BANDS)
	assert_eq([third["ok"], third["why"]], [0, SiegeIds.BUY_LIMIT])
	assert_eq(_rig.state.gate_max, 150.0)


func test_repair_adds_20_up_to_the_max() -> void:
	_shop()
	_rig.state.gate_hp = 50.0
	var ev := _buy(1, SiegeIds.ITEM_REPAIR)
	assert_eq(ev["ok"], 1)
	assert_eq(_rig.state.gate_hp, 70.0)
	assert_eq(_rig.rider(1).denarii, 980.0)
	_rig.state.gate_hp = 95.0
	_buy(1, SiegeIds.ITEM_REPAIR)
	assert_eq(_rig.state.gate_hp, 100.0, "not above the max")
	var full := _buy(1, SiegeIds.ITEM_REPAIR)
	assert_eq([full["ok"], full["why"]], [0, SiegeIds.BUY_GATE_FULL])
	assert_eq(_rig.rider(1).denarii, 960.0, "a refused repair costs nothing")


func test_perks_cost_80_and_100_and_sell_once() -> void:
	_shop()
	var a := _buy(1, SiegeIds.ITEM_RESERVE)
	var b := _buy(1, SiegeIds.ITEM_AQUEDUCT)
	assert_eq([a["ok"], b["ok"]], [1, 1])
	assert_eq(_rig.state.perks, [SiegeIds.PERK_RESERVE, SiegeIds.PERK_AQUEDUCT] as Array[int])
	assert_eq(_rig.rider(1).denarii, 1000.0 - 180.0)
	assert_eq(_buy(2, SiegeIds.ITEM_RESERVE)["why"], SiegeIds.BUY_LIMIT, "a team perk: once")
	assert_eq(_buy(2, SiegeIds.ITEM_AQUEDUCT)["why"], SiegeIds.BUY_LIMIT)
	assert_eq(_rig.rider(2).denarii, 1000.0)


func test_a_refused_buy_changes_nothing_but_the_event() -> void:
	_shop(1, 2, 5.0)
	var ev := _buy(1, SiegeIds.ITEM_GENERATOR)
	assert_eq(ev["ok"], 0)
	assert_eq(ev["lvl"], 0)
	assert_eq(_rig.state.gen_level, 0)
	assert_eq(_rig.rider(1).denarii, 5.0, "nothing spent")


func test_purchases_resolve_in_arrival_order() -> void:
	_shop()
	_rig.send(2, SiegeIntents.buy(SiegeIds.ITEM_BUILD_BALLISTA, 1))
	_rig.send(1, SiegeIntents.buy(SiegeIds.ITEM_BUILD_SCORPION, 1))
	_rig.send(1, SiegeIntents.buy(SiegeIds.ITEM_BUILD_CALTROP, 2))
	_rig.step()
	var buys := _rig.of_type(SiegeIds.EV_BUY)
	assert_eq(buys.size(), 3)
	assert_eq(buys[0]["slot"], 0, "slot order first")
	assert_eq(buys[0]["item"], SiegeIds.ITEM_BUILD_SCORPION)
	assert_eq(buys[0]["ok"], 1)
	assert_eq(buys[1]["slot"], 0, "then that rider's own order")
	assert_eq(buys[2]["slot"], 1)
	assert_eq([buys[2]["ok"], buys[2]["why"]], [0, SiegeIds.BUY_PAD_TAKEN], "pad 1 was taken")
	assert_eq(_rig.state.pad(1).type, SiegeIds.TOWER_SCORPION)


func test_a_team_item_goes_up_a_level_for_the_next_buyer() -> void:
	_shop(1, 2, 60.0)
	_rig.send(1, SiegeIntents.buy(SiegeIds.ITEM_GENERATOR))
	_rig.send(2, SiegeIntents.buy(SiegeIds.ITEM_GENERATOR))
	_rig.step()
	var buys := _rig.of_type(SiegeIds.EV_BUY)
	assert_eq([buys[0]["ok"], buys[1]["ok"]], [1, 0], "the second faces level 2: 90")
	assert_eq(buys[1]["why"], SiegeIds.BUY_FUNDS)
	assert_eq(_rig.state.gen_level, 1)


# --- zero input -----------------------------------------------------------------------------------


func test_a_fresh_human_and_every_bot_start_on_the_shop_fallback() -> void:
	_rig = SiegeRig.new("short", 1, 1)
	for r in _rig.state.riders:
		assert_true(r.shop_fallback)
		assert_true(r.route_fallback)


func test_auto_confirmed_buys_from_a_rider_on_the_fallback_are_ignored() -> void:
	_shop()
	_rig.rider(1).shop_fallback = true
	_rig.state.gate_hp = 50.0
	_rig.send(1, SiegeIntents.buy(SiegeIds.ITEM_REPAIR, 0, true))
	_rig.step()
	assert_eq(_rig.state.gate_hp, 50.0)
	assert_eq(_rig.of_type(SiegeIds.EV_BUY).size(), 0)
	assert_true(_rig.rider(1).shop_fallback, "an auto-confirm never ends the fallback")
	assert_eq(_rig.rider(1).denarii, 1000.0)


func test_a_manual_buy_ends_the_shop_fallback_and_auto_buys_then_count() -> void:
	_shop()
	_rig.rider(1).shop_fallback = true
	_rig.state.gate_hp = 50.0
	var first := _buy(1, SiegeIds.ITEM_REPAIR)
	assert_eq(first["ok"], 1)
	assert_false(_rig.rider(1).shop_fallback)
	var auto := _buy(1, SiegeIds.ITEM_REPAIR, 0, true)
	assert_eq(auto["ok"], 1, "now an auto-confirmed pick is a real purchase")
	assert_eq(_rig.state.gate_hp, 90.0)


func test_a_refused_manual_buy_still_ends_the_fallback() -> void:
	_shop(1, 1, 1.0)
	_rig.rider(1).shop_fallback = true
	_buy(1, SiegeIds.ITEM_GENERATOR)
	assert_false(_rig.rider(1).shop_fallback)


func test_bots_never_end_their_shop_fallback() -> void:
	_rig = SiegeRig.new("short", 1, 1)
	_rig.enter(1, 1.0)
	_rig.send(-1, SiegeIntents.buy(SiegeIds.ITEM_REPAIR))
	_rig.step()
	assert_true(_rig.rider(-1).shop_fallback)


func _picks(calls: Array, items: Array) -> void:
	SiegeShop.shop_hook = func(_s: SiegeState, r: SiegeRiderState, n: int) -> Array:
		calls.append([r.slot, n])
		var out: Array = []
		for it: Variant in items:
			out.append(SiegeIntents.normalize(it))
		return out.slice(0, n)


func test_autopilot_buys_at_4_s_and_9_s_at_most_two_per_break() -> void:
	_rig = SiegeRig.new("short", 1)
	_rig.enter(3, 0.0)
	_rig.rider(1).denarii = 1000.0
	_rig.state.gate_hp = 30.0
	var calls: Array = []
	_picks(calls, [SiegeIntents.buy(SiegeIds.ITEM_REPAIR), SiegeIntents.buy(SiegeIds.ITEM_REPAIR)])
	_rig.run(3.9)
	assert_eq(_rig.state.gate_hp, 30.0, "nothing before 4 s")
	_rig.run(0.3)
	assert_eq(_rig.state.gate_hp, 50.0, "the first at 4 s")
	_rig.run(4.0)
	assert_eq(_rig.state.gate_hp, 50.0)
	_rig.run(1.2)
	assert_eq(_rig.state.gate_hp, 70.0, "the second at 9 s")
	_rig.run(30.0)
	assert_eq(_rig.state.gate_hp, 70.0, "never a third")
	assert_eq(_rig.rider(1).ap_buys, 2)
	assert_eq(_rig.of_type(SiegeIds.EV_BUY).size(), 2)
	assert_eq(calls.size(), 2)
	assert_eq(calls[0], [0, 1])


func test_the_per_break_allowance_resets_with_the_next_break() -> void:
	_rig = SiegeRig.new("short", 1)
	_rig.enter(3, 0.0)
	_rig.rider(1).denarii = 1000.0
	_rig.state.gate_hp = 10.0
	_picks([], [SiegeIntents.buy(SiegeIds.ITEM_REPAIR)])
	_rig.run(12.0)
	assert_eq(_rig.rider(1).ap_buys, 2)
	_rig.enter(5, 0.0)
	assert_eq(_rig.rider(1).ap_buys, 0)
	_rig.run(5.0)
	assert_eq(_rig.rider(1).ap_buys, 1)


func test_save_means_no_purchase_and_no_further_calls() -> void:
	_rig = SiegeRig.new("short", 1)
	_rig.enter(3, 0.0)
	var calls: Array = []
	_picks(calls, [])
	_rig.run(20.0)
	assert_eq(calls.size(), 1)
	assert_eq(_rig.of_type(SiegeIds.EV_BUY).size(), 0)


func test_autopilot_does_not_shop_in_waves_or_for_riders_who_shop_by_hand() -> void:
	_rig = SiegeRig.new("short", 2)
	_rig.enter(3, 0.0)
	_rig.rider(1).shop_fallback = false
	var calls: Array = []
	_picks(calls, [SiegeIntents.buy(SiegeIds.ITEM_REPAIR)])
	_rig.run(5.0)
	assert_eq(calls, [[1, 1]], "only slot 1")
	calls.clear()
	_rig.enter(4, 5.0)
	_rig.run(5.0)
	assert_eq(calls, [])


func test_no_double_purchase_when_the_panel_auto_confirms_the_same_pick() -> void:
	_rig = SiegeRig.new("short", 1)
	_rig.enter(3, 0.0)
	_rig.rider(1).denarii = 1000.0
	_rig.state.gate_hp = 30.0
	_picks([], [SiegeIntents.buy(SiegeIds.ITEM_REPAIR)])
	for _i in 6:
		_rig.send(1, SiegeIntents.buy(SiegeIds.ITEM_REPAIR, 0, true))
		_rig.run(2.0)
	assert_eq(_rig.state.gate_hp, 70.0, "two Autopilot repairs, none from the auto-confirms")
	assert_eq(_rig.of_type(SiegeIds.EV_BUY).size(), 2)


func test_an_autopilot_on_human_is_shopped_for_even_after_a_manual_buy() -> void:
	_rig = SiegeRig.new("short", 1)
	_rig.enter(3, 0.0)
	_rig.rider(1).autopilot = true
	_rig.rider(1).shop_fallback = false
	_rig.rider(1).denarii = 1000.0
	_rig.state.gate_hp = 30.0
	var calls: Array = []
	_picks(calls, [SiegeIntents.buy(SiegeIds.ITEM_REPAIR)])
	_rig.send(1, SiegeIntents.buy(SiegeIds.ITEM_REPAIR, 0, true))
	_rig.run(5.0)
	assert_eq(_rig.state.gate_hp, 50.0, "the auto-confirm was ignored, Autopilot bought once")
