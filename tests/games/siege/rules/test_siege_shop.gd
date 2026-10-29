extends GutTest
## The shop (brief 2.4 "Shop", 2.5 "Zero input"; 4): every item, its price and limit, closed in
## waves, refusals as buy events, personal gold, Autopilot's two picks per break, no double
## purchase with auto-confirms.

var _s: SiegeState


func before_each() -> void:
	_s = SiegeKit.state("short", 2, 0, 1, SiegeIds.ROLE_BREAK)


func _buy(item: String, at: int = 0, peer: int = 1) -> Dictionary:
	var it := SiegeIntents.normalize(SiegeIntents.buy(item, at))
	return SiegeShop.buy(_s, _s.rider(peer), it)


func _gold(g: float, peer: int = 1) -> void:
	_s.rider(peer).gold = g


func test_station_upgrades_cost_40_50_70_and_are_team_wide() -> void:
	_gold(500.0)
	for lvl in [1, 2, 3]:
		var ev := _buy(SiegeIds.ITEM_UPGRADE, SiegeIds.STATION_ONAGER)
		assert_eq(int(ev["ok"]), 1)
		assert_eq(int(ev["lvl"]), lvl)
		assert_eq(int(ev["station"]), SiegeIds.STATION_ONAGER)
	assert_eq(_s.station(SiegeIds.STATION_ONAGER).level, 3)
	assert_eq(_s.rider(1).gold, 500.0 - 160.0)
	var no := _buy(SiegeIds.ITEM_UPGRADE, SiegeIds.STATION_ONAGER)
	assert_eq(no["why"], SiegeIds.BUY_MAX_LEVEL)


func test_every_upgradable_station_takes_upgrades() -> void:
	_gold(1000.0)
	for id in SiegeIds.UPGRADABLE:
		assert_eq(int(_buy(SiegeIds.ITEM_UPGRADE, id)["ok"]), 1, "station %d" % id)


func test_the_mine_is_not_a_station_upgrade() -> void:
	_gold(1000.0)
	var ev := SiegeShop.buy(_s, _s.rider(1), {"item": "upgrade", "station": 0, "pad": 0})
	assert_eq(ev["why"], SiegeIds.BUY_NO_STATION)


func test_tar_upgrade_2_raises_the_curtain() -> void:
	_gold(1000.0)
	_buy(SiegeIds.ITEM_UPGRADE, SiegeIds.STATION_TAR)
	_buy(SiegeIds.ITEM_UPGRADE, SiegeIds.STATION_TAR)
	assert_eq(_s.tar.curtain_max, 250.0)


func test_mine_levels_cost_60_90_130_and_add_20_percent() -> void:
	_gold(500.0)
	for lvl in [1, 2, 3]:
		assert_eq(int(_buy(SiegeIds.ITEM_MINE)["lvl"]), lvl)
	assert_eq(_s.mine_level, 3)
	assert_eq(_s.rider(1).gold, 500.0 - 280.0)
	assert_almost_eq(SiegeEconomy.mine_rate(_s), 1.6, 1e-6)
	assert_eq(_buy(SiegeIds.ITEM_MINE)["why"], SiegeIds.BUY_MAX_LEVEL)


func test_a_scorpion_costs_40_on_an_empty_pad() -> void:
	_gold(100.0)
	var ev := _buy(SiegeIds.ITEM_SCORPION, 3)
	assert_eq(int(ev["ok"]), 1)
	assert_eq(_s.pad(3).type, SiegeIds.PAD_SCORPION)
	assert_eq(_s.pad(3).built_by, 0)
	assert_eq(_s.rider(1).gold, 60.0)
	assert_eq(_buy(SiegeIds.ITEM_SCORPION, 3)["why"], SiegeIds.BUY_PAD_TAKEN)
	assert_eq(_buy(SiegeIds.ITEM_SCORPION, 1)["why"], SiegeIds.BUY_PAD_TAKEN, "pad 1 starts built")


func test_all_four_pads_can_be_built() -> void:
	_gold(500.0)
	for n in [2, 3, 4]:
		assert_eq(int(_buy(SiegeIds.ITEM_SCORPION, n)["ok"]), 1)
	assert_eq(_s.built_pads(), [1, 2, 3, 4])


func test_pad_upgrades_cost_40_50_70() -> void:
	_gold(500.0)
	for lvl in [1, 2, 3]:
		assert_eq(int(_buy(SiegeIds.ITEM_PAD_UPGRADE, 1)["lvl"]), lvl)
	assert_eq(_s.rider(1).gold, 500.0 - 160.0)
	assert_eq(_buy(SiegeIds.ITEM_PAD_UPGRADE, 1)["why"], SiegeIds.BUY_MAX_LEVEL)
	assert_eq(_buy(SiegeIds.ITEM_PAD_UPGRADE, 2)["why"], SiegeIds.BUY_NO_PAD, "an empty pad")


func test_iron_bands_add_25_max_and_current_twice() -> void:
	_gold(500.0)
	_s.gate_hp = 100.0
	assert_eq(int(_buy(SiegeIds.ITEM_IRON_BANDS)["lvl"]), 1)
	assert_eq(_s.gate_max, 155.0)
	assert_eq(_s.gate_hp, 125.0)
	assert_eq(int(_buy(SiegeIds.ITEM_IRON_BANDS)["lvl"]), 2)
	assert_eq(_s.gate_max, 180.0)
	assert_eq(_buy(SiegeIds.ITEM_IRON_BANDS)["why"], SiegeIds.BUY_LIMIT)
	assert_eq(_s.rider(1).gold, 500.0 - 90.0)


func test_repair_adds_20_up_to_the_max() -> void:
	_gold(100.0)
	_s.gate_hp = 100.0
	assert_eq(int(_buy(SiegeIds.ITEM_REPAIR)["lvl"]), 120)
	assert_eq(int(_buy(SiegeIds.ITEM_REPAIR)["lvl"]), 130, "capped at the max")
	assert_eq(_buy(SiegeIds.ITEM_REPAIR)["why"], SiegeIds.BUY_GATE_FULL)
	assert_eq(_s.rider(1).gold, 60.0)


func test_perks_once_each_at_80_100_60() -> void:
	_gold(500.0)
	assert_eq(int(_buy(SiegeIds.ITEM_RESERVE)["ok"]), 1)
	assert_eq(int(_buy(SiegeIds.ITEM_AQUEDUCT)["ok"]), 1)
	assert_eq(int(_buy(SiegeIds.ITEM_CAULDRON)["ok"]), 1)
	assert_eq(_s.rider(1).gold, 500.0 - 240.0)
	assert_eq(_s.perks, [SiegeIds.PERK_RESERVE, SiegeIds.PERK_AQUEDUCT, SiegeIds.PERK_CAULDRON])
	for item: String in [SiegeIds.ITEM_RESERVE, SiegeIds.ITEM_AQUEDUCT, SiegeIds.ITEM_CAULDRON]:
		assert_eq(_buy(item)["why"], SiegeIds.BUY_LIMIT)


func test_the_spare_cauldron_adds_100_litres_of_room() -> void:
	_gold(100.0)
	_buy(SiegeIds.ITEM_CAULDRON)
	assert_eq(_s.tar.cauldron_max_l, 400.0)


func test_too_little_gold_is_refused_and_costs_nothing() -> void:
	_gold(39.0)
	var ev := _buy(SiegeIds.ITEM_SCORPION, 2)
	assert_eq(int(ev["ok"]), 0)
	assert_eq(ev["why"], SiegeIds.BUY_FUNDS)
	assert_eq(int(ev["lvl"]), 0)
	assert_eq(_s.rider(1).gold, 39.0)
	assert_false(_s.pad(2).built())


func test_exactly_enough_gold_is_enough() -> void:
	_gold(40.0)
	assert_eq(int(_buy(SiegeIds.ITEM_UPGRADE, SiegeIds.STATION_BALLISTA)["ok"]), 1)
	assert_eq(_s.rider(1).gold, 0.0)


func test_the_shop_is_closed_in_waves_and_the_cool_down() -> void:
	_gold(500.0)
	for role: String in [SiegeIds.ROLE_WAVE, SiegeIds.ROLE_WARMUP_WAVE, SiegeIds.ROLE_COOLDOWN]:
		_s.role = role
		assert_eq(_buy(SiegeIds.ITEM_MINE)["why"], SiegeIds.BUY_CLOSED, role)
	assert_eq(_s.mine_level, 0)


func test_the_build_break_is_open() -> void:
	_s.role = SiegeIds.ROLE_BUILD_BREAK
	_gold(500.0)
	assert_eq(int(_buy(SiegeIds.ITEM_MINE)["ok"]), 1)


func test_gold_is_personal_and_anyone_may_buy_anything() -> void:
	_gold(10.0, 1)
	_gold(100.0, 2)
	assert_eq(_buy(SiegeIds.ITEM_UPGRADE, 2, 1)["why"], SiegeIds.BUY_FUNDS)
	assert_eq(int(_buy(SiegeIds.ITEM_UPGRADE, 2, 2)["ok"]), 1)
	assert_eq(_s.rider(1).gold, 10.0)
	assert_eq(_s.rider(2).gold, 60.0)
	assert_eq(
		int(_buy(SiegeIds.ITEM_UPGRADE, 2, 2)["lvl"]), 2, "the next level, whoever bought the first"
	)


func test_checks_run_closed_then_limit_then_funds() -> void:
	_gold(0.0)
	_s.iron_bands = 2
	assert_eq(_buy(SiegeIds.ITEM_IRON_BANDS)["why"], SiegeIds.BUY_LIMIT, "the limit before funds")
	_s.role = SiegeIds.ROLE_WAVE
	assert_eq(_buy(SiegeIds.ITEM_IRON_BANDS)["why"], SiegeIds.BUY_CLOSED, "closed first")


func test_price_reports_the_next_cost() -> void:
	assert_eq(SiegeShop.price(_s, SiegeIds.ITEM_UPGRADE, SiegeIds.STATION_ARROWS), 40)
	_s.station(SiegeIds.STATION_ARROWS).level = 2
	assert_eq(SiegeShop.price(_s, SiegeIds.ITEM_UPGRADE, SiegeIds.STATION_ARROWS), 70)
	_s.station(SiegeIds.STATION_ARROWS).level = 3
	assert_eq(SiegeShop.price(_s, SiegeIds.ITEM_UPGRADE, SiegeIds.STATION_ARROWS), -1)
	assert_eq(SiegeShop.price(_s, SiegeIds.ITEM_MINE), 60)
	assert_eq(SiegeShop.price(_s, SiegeIds.ITEM_SCORPION, 0, 2), 40)
	assert_eq(SiegeShop.price(_s, SiegeIds.ITEM_PAD_UPGRADE, 0, 1), 40)
	assert_eq(SiegeShop.price(_s, SiegeIds.ITEM_PAD_UPGRADE, 0, 2), -1)
	assert_eq(SiegeShop.price(_s, SiegeIds.ITEM_CAULDRON), 60)
	assert_eq(SiegeShop.price(_s, "nope"), -1)


func test_buy_events_carry_the_buyers_slot() -> void:
	_gold(0.0, 2)
	var ev := _buy(SiegeIds.ITEM_REPAIR, 0, 2)
	assert_eq(int(ev["slot"]), 1)
	assert_eq(SiegeEvents.check(ev), "")


# --- through the rules: intents, Autopilot, no double purchase ------------------------------------


func _break_rig(humans: int = 1, bots: int = 0) -> SiegeRig:
	var rig := SiegeRig.new("short", humans, bots)
	rig.enter(1, 0.0)
	return rig


func test_a_manual_buy_ends_the_shop_fallback() -> void:
	var rig := _break_rig()
	assert_true(rig.rider().shop_fallback)
	rig.send(1, SiegeIntents.buy(SiegeIds.ITEM_MINE))
	rig.step()
	assert_false(rig.rider().shop_fallback)
	assert_true(rig.rider().route_fallback, "routing is separate")


func test_auto_confirmed_buys_never_end_it_and_are_ignored_while_it_lasts() -> void:
	var rig := _break_rig()
	rig.rider().gold = 1000.0
	rig.send(1, SiegeIntents.buy(SiegeIds.ITEM_MINE, 0, true))
	var ev := rig.step()
	assert_true(rig.rider().shop_fallback)
	assert_eq(rig.of_type(SiegeIds.EV_BUY, ev), [], "no event, no purchase")
	assert_eq(rig.state.mine_level, 0)


func test_after_the_fallback_ends_auto_confirmed_buys_count() -> void:
	var rig := _break_rig()
	rig.manual()
	rig.rider().gold = 1000.0
	rig.send(1, SiegeIntents.buy(SiegeIds.ITEM_MINE, 0, true))
	rig.step()
	assert_eq(rig.state.mine_level, 1)


func test_autopilot_buys_at_most_two_items_per_break_at_4_and_9_s() -> void:
	var rig := _break_rig(1, 1)
	for r in rig.state.riders:
		r.gold = 1000.0
	var times := []
	for _i in roundi(30.0 / Wl.SIM_DT):
		for e in rig.step():
			if e["type"] == SiegeIds.EV_BUY:
				times.append([snappedf(rig.state.phase_elapsed_s, 0.05), int(e["slot"])])
	assert_eq(times.size(), 4, "two per rider")
	assert_almost_eq(float(times[0][0]), 4.0, 0.06)
	assert_almost_eq(float(times[2][0]), 9.0, 0.06)
	assert_eq(int(times[0][1]), 0, "slot order")
	assert_eq(int(times[1][1]), 1)


func test_autopilot_s_count_resets_every_break() -> void:
	var rig := _break_rig()
	rig.rider().gold = 1000.0
	rig.run(20.0)
	assert_eq(rig.rider().ap_buys, 2)
	rig.enter(3, 0.0)
	assert_eq(rig.rider().ap_buys, 0)


func test_autopilot_saves_when_nothing_is_affordable() -> void:
	var rig := _break_rig()
	rig.rider().gold = 5.0
	var ev := rig.run(20.0)
	assert_eq(rig.of_type(SiegeIds.EV_BUY, ev), [])
	assert_almost_eq(rig.rider().gold, 5.0 + rig.rider().mine_gold, 0.01)


func test_the_shop_hook_replaces_autopilot_s_picks() -> void:
	var rig := _break_rig()
	rig.rider().gold = 500.0
	SiegeShop.shop_hook = func(_st: SiegeState, _r: SiegeRiderState, _n: int) -> Array:
		return [SiegeIntents.normalize(SiegeIntents.buy(SiegeIds.ITEM_CAULDRON, 0, true))]
	rig.run(5.0)
	SiegeShop.shop_hook = Callable()
	assert_true(rig.state.perks.has(SiegeIds.PERK_CAULDRON))


func test_no_autopilot_shopping_in_waves() -> void:
	var rig := SiegeRig.new("short", 1)
	rig.rider().gold = 1000.0
	var ev := rig.run(20.0)
	assert_eq(rig.of_type(SiegeIds.EV_BUY, ev), [])
