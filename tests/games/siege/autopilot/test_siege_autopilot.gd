extends GutTest
## Autopilot (brief 2.5; 4 "Autopilot scores, hysteresis, shop order, never Overdrive, and the
## zero-input fallback with no double purchase").

const F := preload("res://tests/games/siege/siege_fakes.gd")

var _s: SiegeState


func before_each() -> void:
	_s = SiegeKit.state("short", 4)
	_s.t = 100.0


func _w(station: String, enemy: String) -> float:
	return float(_s.content.balance["autopilot"]["weights"][station][enemy])


# --- scores -----------------------------------------------------------------------------------


func test_nothing_in_reach_leaves_only_the_mine_score() -> void:
	var sc := SiegeAutopilot.scores(_s)
	assert_eq(sc[SiegeIds.STATION_MINE], _s.content.num("autopilot.mine_score"))
	for id in [1, 2, 3, 4]:
		assert_eq(sc[id], 0.0, "station %d" % id)


func test_a_weapon_scores_hp_times_its_weight() -> void:
	var p := SiegeKit.prog_in_band(_s, SiegeIds.STATION_ARROWS)
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, p)
	var sc := SiegeAutopilot.scores(_s)
	assert_almost_eq(sc[SiegeIds.STATION_ARROWS], e.hp * _w("arrows", "spear"), 1e-4)


func test_weights_favour_the_brief_s_matchups() -> void:
	assert_gt(_w("ballista", "ram"), _w("ballista", "spear"), "the ballista: engines")
	assert_gt(_w("ballista", "shield"), _w("ballista", "spear"), "and shield bearers")
	assert_gt(_w("onager", "spear"), _w("onager", "chariot"), "the onager: blocks")
	assert_gt(_w("onager", "ram"), _w("onager", "chariot"), "and engines")
	assert_gt(_w("arrows", "spear"), _w("arrows", "shield"), "the arrow organ: spearmen")
	assert_gt(_w("arrows", "chariot"), _w("arrows", "ram"), "and chariots")


func test_an_enemy_coming_into_the_band_within_10_s_counts() -> void:
	var progs := SiegeKit.band_progs(_s, SiegeIds.STATION_ONAGER)
	var first := progs[0]
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_CHARIOT, maxf(first - 20.0, 0.0))
	e.speed_mps = 6.0
	if _s.in_band(SiegeIds.STATION_ONAGER, e.pos):
		pass_test("the band starts at the camp")
		return
	assert_gt(SiegeAutopilot.scores(_s)[SiegeIds.STATION_ONAGER], 0.0, "in range in ~3 s")
	e.speed_mps = 0.5
	assert_eq(SiegeAutopilot.scores(_s)[SiegeIds.STATION_ONAGER], 0.0, "too slow to arrive in 10 s")


func test_retreating_enemies_score_nothing() -> void:
	var e := SiegeKit.enemy(
		_s, SiegeIds.ENEMY_SPEAR, SiegeKit.prog_in_band(_s, SiegeIds.STATION_ARROWS)
	)
	e.st = SiegeIds.EN_RETREAT
	assert_eq(SiegeAutopilot.scores(_s)[SiegeIds.STATION_ARROWS], 0.0)


func test_the_tar_works_score_an_engine_within_60_m_with_full_cauldrons() -> void:
	SiegeKit.enemy(_s, SiegeIds.ENEMY_RAM, _s.path.length_m - 50.0)
	var want := _s.content.num("autopilot.tar_scale") * 20.0
	assert_almost_eq(SiegeAutopilot.tar_score(_s), want, 1e-4)


func test_the_tar_works_score_any_enemy_within_40_m() -> void:
	SiegeKit.enemy(_s, SiegeIds.ENEMY_SHIELD, _s.path.length_m - 30.0)
	assert_almost_eq(
		SiegeAutopilot.tar_score(_s), _s.content.num("autopilot.tar_scale") * 6.0, 1e-4
	)
	_s.enemies.clear()
	SiegeKit.enemy(_s, SiegeIds.ENEMY_SHIELD, _s.path.length_m - 45.0)
	assert_eq(SiegeAutopilot.tar_score(_s), 0.0, "45 m out")


func test_the_tar_works_need_two_thirds_full_cauldrons() -> void:
	SiegeKit.enemy(_s, SiegeIds.ENEMY_RAM, _s.path.length_m - 20.0)
	_s.tar.cauldron_l = 190.0
	assert_eq(SiegeAutopilot.tar_score(_s), 0.0)
	_s.tar.cauldron_l = 201.0
	assert_gt(SiegeAutopilot.tar_score(_s), 0.0)


func test_the_tar_works_score_nothing_with_boarders_on_the_wall() -> void:
	SiegeKit.enemy(_s, SiegeIds.ENEMY_RAM, _s.path.length_m - 20.0)
	_s.tar.boarded = true
	assert_eq(SiegeAutopilot.tar_score(_s), 0.0)


# --- route_choice ------------------------------------------------------------------------------


func test_the_best_scoring_station_wins() -> void:
	SiegeKit.enemy(
		_s, SiegeIds.ENEMY_RAM, SiegeKit.prog_in_band(_s, SiegeIds.STATION_BALLISTA, 0.1)
	)
	var r := _s.rider(1)
	var best := SiegeAutopilot.route_choice(_s, r)
	assert_true(SiegeIds.is_weapon(best))
	var sc := SiegeAutopilot.scores(_s)
	for id in 5:
		assert_lte(sc[id], sc[best] + 1e-6)


func _two_away() -> void:
	SiegeKit.put(_s, 3, SiegeIds.STATION_ONAGER)
	SiegeKit.put(_s, 4, SiegeIds.STATION_ONAGER)


func test_the_mine_when_nothing_is_in_reach() -> void:
	_two_away()
	var r := SiegeKit.put(_s, 1, SiegeIds.STATION_ARROWS)
	r.routed_t = 0.0
	assert_eq(SiegeAutopilot.route_choice(_s, r), SiegeIds.STATION_MINE)


func test_at_most_one_switch_per_8_s() -> void:
	_two_away()
	var r := SiegeKit.put(_s, 1, SiegeIds.STATION_ARROWS)
	r.routed_t = _s.t - 7.9
	assert_eq(SiegeAutopilot.route_choice(_s, r), -1)
	r.routed_t = _s.t - 8.0
	assert_eq(SiegeAutopilot.route_choice(_s, r), SiegeIds.STATION_MINE)


func test_only_for_a_score_at_least_25_percent_higher() -> void:
	var r := SiegeKit.put(_s, 1, SiegeIds.STATION_ARROWS)
	r.routed_t = 0.0
	var sc := PackedFloat32Array([40.0, 0.0, 124.0, 100.0, 0.0])
	assert_eq(SiegeAutopilot.route_choice(_s, r, sc), -1, "124 < 125")
	sc[2] = 125.0
	assert_eq(SiegeAutopilot.route_choice(_s, r, sc), SiegeIds.STATION_ONAGER)


func test_idle_riders_kept_off_a_full_mine_do_not_wander() -> void:
	var r := SiegeKit.put(_s, 1, SiegeIds.STATION_ARROWS)
	r.routed_t = 0.0
	assert_eq(SiegeAutopilot.route_choice(_s, r), -1, "the mine is full; no station is better")


func test_choices_stay_within_the_caps() -> void:
	SiegeKit.put(_s, 2, SiegeIds.STATION_BALLISTA)
	var r := _s.rider(1)
	r.routed_t = 0.0
	var sc := PackedFloat32Array([40.0, 9999.0, 50.0, 10.0, 0.0])
	assert_eq(
		SiegeAutopilot.route_choice(_s, r, sc), SiegeIds.STATION_ONAGER, "the ballista is taken"
	)


func test_ties_go_to_the_lower_station() -> void:
	var r := _s.rider(1)
	r.routed_t = 0.0
	var sc := PackedFloat32Array([0.0, 0.0, 300.0, 300.0, 0.0])
	assert_eq(SiegeAutopilot.best_station(_s, r, sc), SiegeIds.STATION_ONAGER)


func test_nothing_outside_waves_or_for_afk_riders() -> void:
	var r := _s.rider(1)
	r.routed_t = 0.0
	var sc := PackedFloat32Array([0.0, 500.0, 0.0, 0.0, 0.0])
	_s.role = SiegeIds.ROLE_BREAK
	assert_eq(SiegeAutopilot.route_choice(_s, r, sc), -1)
	_s.role = SiegeIds.ROLE_WAVE
	r.afk = true
	assert_eq(SiegeAutopilot.route_choice(_s, r, sc), -1)


func test_hot_is_the_best_station_with_room() -> void:
	SiegeKit.enemy(
		_s, SiegeIds.ENEMY_SPEAR, SiegeKit.prog_in_band(_s, SiegeIds.STATION_ARROWS), 0.0, 100.0
	)
	assert_eq(SiegeAutopilot.hot_target(_s, _s.rider(1)), SiegeIds.STATION_ARROWS)
	SiegeKit.put(_s, 1, SiegeIds.STATION_ARROWS)
	assert_eq(SiegeAutopilot.hot_target(_s, _s.rider(1)), -1, "already there")


func test_a_team_spreads_over_the_stations_by_the_caps() -> void:
	var rig := SiegeRig.new("short", 4)
	rig.enter(2, 0.0)
	for id in SiegeIds.WEAPONS:
		var p := SiegeKit.prog_in_band(rig.state, id)
		for i in 3:
			rig.spawn(SiegeIds.ENEMY_SHIELD, p + float(i), 0.0, 40.0)
	rig.run(2.0)
	for id in 5:
		assert_lte(rig.state.routed_count(id), rig.state.station_cap(id), "station %d" % id)
	var on_weapons := 0
	for r in rig.state.riders:
		on_weapons += int(SiegeIds.is_weapon(r.target))
	assert_gte(on_weapons, 3, "enemies in reach: weapons get riders")


func test_autopilot_never_starts_overdrive() -> void:
	var rig := SiegeRig.new("short", 1, 1)
	rig.enter(2, 10.0)
	rig.spawn(SiegeIds.ENEMY_SPEAR, SiegeKit.prog_in_band(rig.state, SiegeIds.STATION_ARROWS))
	rig.run(30.0)
	for r in rig.state.riders:
		assert_eq(r.od_count, 0)
	assert_eq(rig.of_type(SiegeIds.EV_OVERDRIVE), [])


# --- shop_picks ---------------------------------------------------------------------------------


func _shop(gold: float) -> Array[Dictionary]:
	_s.role = SiegeIds.ROLE_BREAK
	_s.rider(1).gold = gold
	return SiegeAutopilot.shop_picks(_s, _s.rider(1), 2)


func _items(picks: Array[Dictionary]) -> Array:
	return picks.map(func(p: Dictionary) -> String: return p["item"])


func test_repair_first_when_the_gate_is_below_half() -> void:
	_s.gate_hp = 60.0
	var picks := _shop(500.0)
	assert_eq(picks[0]["item"], SiegeIds.ITEM_REPAIR)
	assert_eq(picks.size(), 2)


func test_no_repair_at_half_or_more() -> void:
	_s.gate_hp = 65.0
	assert_ne(_shop(500.0)[0]["item"], SiegeIds.ITEM_REPAIR)


func test_then_an_upgrade_for_the_station_that_did_the_most_damage() -> void:
	_s.station(SiegeIds.STATION_ARROWS).damage_wave = 900.0
	_s.station(SiegeIds.STATION_ONAGER).damage_wave = 300.0
	var picks := _shop(45.0)
	assert_eq(picks.size(), 1)
	assert_eq(picks[0]["item"], SiegeIds.ITEM_UPGRADE)
	assert_eq(picks[0]["station"], SiegeIds.STATION_ARROWS)


func test_the_second_pick_sees_the_first() -> void:
	_s.station(SiegeIds.STATION_ONAGER).damage_wave = 300.0
	var picks := _shop(500.0)
	assert_eq(_items(picks), [SiegeIds.ITEM_UPGRADE, SiegeIds.ITEM_UPGRADE])
	assert_eq(picks[0]["station"], SiegeIds.STATION_ONAGER)
	assert_eq(
		picks[1]["station"], SiegeIds.STATION_BALLISTA, "no level 2 of the onager: the next one"
	)


func test_an_item_on_the_receipt_is_not_picked_again() -> void:
	_s.station(SiegeIds.STATION_ONAGER).damage_wave = 300.0
	var line := SiegeReceiptLine.new()
	line.item = SiegeIds.ITEM_UPGRADE
	line.at = SiegeIds.STATION_ONAGER
	line.cost = 40
	line.slot = 1
	_s.receipt.assign([line])
	var picks := _shop(500.0)
	assert_eq(picks[0]["item"], SiegeIds.ITEM_UPGRADE)
	assert_eq(
		picks[0]["station"], SiegeIds.STATION_BALLISTA, "someone else's upgrade counts as taken"
	)
	var blind := SiegeAutopilot.shop_picks(_s, _s.riders[0], 1, true)
	assert_eq(blind[0]["item"], SiegeIds.ITEM_UPGRADE, "the list's blind pick ignores the receipt")


func test_a_taken_upgrade_passes_to_the_next_weapon_by_damage() -> void:
	_s.station(SiegeIds.STATION_ARROWS).damage_wave = 900.0
	_s.station(SiegeIds.STATION_ONAGER).damage_wave = 300.0
	var line := SiegeReceiptLine.new()
	line.item = SiegeIds.ITEM_UPGRADE
	line.at = SiegeIds.STATION_ARROWS
	line.cost = 40
	line.slot = 1
	_s.receipt.assign([line])
	var picks := _shop(500.0)
	assert_eq(picks[0]["item"], SiegeIds.ITEM_UPGRADE)
	assert_eq(
		picks[0]["station"], SiegeIds.STATION_ONAGER, "the arrow organ's is taken: the onager"
	)
	assert_eq(SiegeAutopilot.weapons_by_damage(_s), [3, 2, 1])


func test_picks_use_the_gold_left_after_what_the_receipt_holds() -> void:
	_s.station(SiegeIds.STATION_ONAGER).damage_wave = 300.0
	var line := SiegeReceiptLine.new()
	line.item = SiegeIds.ITEM_MINE
	line.cost = 60
	line.slot = _s.riders[0].slot
	_s.receipt.assign([line])
	assert_eq(_shop(70.0).size(), 0, "70 gold, 60 of it held")


func test_then_a_scorpion_on_the_first_empty_pad() -> void:
	_s.station(SiegeIds.STATION_BALLISTA).level = 3
	var picks := _shop(45.0)
	assert_eq(picks[0]["item"], SiegeIds.ITEM_SCORPION)
	assert_eq(picks[0]["pad"], 2, "pad 1 has one already")


func test_then_a_mine_level_then_iron_bands_then_perks() -> void:
	_s.station(SiegeIds.STATION_BALLISTA).level = 3
	for pd in _s.pads:
		pd.type = SiegeIds.PAD_SCORPION
	assert_eq(_shop(70.0)[0]["item"], SiegeIds.ITEM_MINE)
	_s.mine_level = 3
	assert_eq(_shop(70.0)[0]["item"], SiegeIds.ITEM_IRON_BANDS)
	_s.iron_bands = 2
	assert_eq(_shop(85.0)[0]["item"], SiegeIds.ITEM_RESERVE)
	_s.perks = [SiegeIds.PERK_RESERVE]
	assert_eq(_shop(105.0)[0]["item"], SiegeIds.ITEM_AQUEDUCT)
	_s.perks = [SiegeIds.PERK_RESERVE, SiegeIds.PERK_AQUEDUCT]
	assert_eq(_shop(65.0)[0]["item"], SiegeIds.ITEM_CAULDRON)
	_s.perks = [SiegeIds.PERK_RESERVE, SiegeIds.PERK_AQUEDUCT, SiegeIds.PERK_CAULDRON]
	assert_eq(_shop(999.0), [], "everything bought: save")


func test_an_unaffordable_step_falls_through() -> void:
	_s.station(SiegeIds.STATION_BALLISTA).level = 2
	var picks := _shop(45.0)
	assert_eq(picks[0]["item"], SiegeIds.ITEM_SCORPION, "70 for the upgrade is too dear")


func test_too_poor_to_buy_anything_saves() -> void:
	assert_eq(_shop(10.0), [])


func test_picks_are_normalized_auto_buys() -> void:
	for p in _shop(500.0):
		assert_true(p["auto"])
		assert_eq(p["via"], SiegeIds.VIA_AUTO)
		assert_eq(p, SiegeIntents.normalize(p))


func test_nothing_outside_breaks() -> void:
	_s.rider(1).gold = 500.0
	assert_eq(SiegeAutopilot.shop_picks(_s, _s.rider(1), 2), [])


func test_top_weapon_defaults_to_the_ballista() -> void:
	assert_eq(SiegeAutopilot.top_weapon(_s), SiegeIds.STATION_BALLISTA)
	_s.station(SiegeIds.STATION_ARROWS).damage_wave = 1.0
	assert_eq(SiegeAutopilot.top_weapon(_s), SiegeIds.STATION_ARROWS)


func test_a_client_picks_like_the_host_from_the_snapshot() -> void:
	var host := SiegeFixtures.mid_wave()
	host.role = SiegeIds.ROLE_BREAK
	var client := SiegeState.create(host.content, SiegeFixtures.slots(), Wl.FAIR_FTP, null)
	client.role = SiegeIds.ROLE_BREAK
	SiegeSnapshot.apply(client, JSON.parse_string(JSON.stringify(SiegeSnapshot.encode(host))))
	for slot in 4:
		assert_eq(
			SiegeAutopilot.shop_picks(client, client.rider_at(slot), 2),
			SiegeAutopilot.shop_picks(host, host.rider_at(slot), 2),
			"slot %d" % slot
		)


# --- zero input -------------------------------------------------------------------------------


func test_a_human_counts_as_autopilot_until_their_first_route_intent() -> void:
	var rig := SiegeRig.new("short", 1)
	rig.enter(2, 0.0)
	for id in SiegeIds.WEAPONS:
		rig.spawn(SiegeIds.ENEMY_SHIELD, SiegeKit.prog_in_band(rig.state, id), 0.0, 40.0)
	rig.run(3.0)
	assert_true(SiegeIds.is_weapon(rig.rider().target), "Autopilot routed the silent human")
	rig.send(1, SiegeIntents.route("mine"))
	rig.step()
	rig.run(20.0)
	assert_eq(rig.rider().target, SiegeIds.STATION_MINE, "after a route intent it stays put")


func test_overdrive_intents_never_end_the_fallbacks() -> void:
	var rig := SiegeRig.new("short", 1)
	rig.enter(2, 10.0)
	rig.send(1, SiegeIntents.overdrive(SiegeIds.VIA_SURGE))
	rig.step()
	assert_true(rig.rider().route_fallback)
	assert_true(rig.rider().shop_fallback)


func test_bots_never_leave_autopilot() -> void:
	var rig := SiegeRig.new("short", 0, 1)
	rig.enter(2, 10.0)
	rig.send(-1, SiegeIntents.route(2))
	rig.step()
	assert_true(rig.rider(-1).route_fallback)
	assert_true(rig.rider(-1).autopilot)


func test_a_zero_input_break_adds_autopilots_two_and_none_of_the_auto_confirms() -> void:
	var rig := SiegeRig.new("short", 1)
	rig.enter(1, 0.0)
	rig.rider().gold = 300.0
	var adds := 0
	for i in roundi(30.0 / Wl.SIM_DT):
		if i % 20 == 0:
			rig.send(1, SiegeIntents.pick(SiegeIds.ITEM_MINE, 0, true))
		for e in rig.step():
			if e["type"] == SiegeIds.EV_RECEIPT and int(e["act"]) == SiegeIds.RC_ADD:
				adds += 1
	assert_eq(adds, 2, "Autopilot's two, none of the auto-confirms")
	assert_eq(rig.state.mine_level, 0, "nothing bought until the break ends")
	rig.goto(rig.phase_start(2))
	var buys := 0
	for e in rig.step():
		if e["type"] == SiegeIds.EV_BUY and int(e["ok"]) == 1:
			buys += 1
	assert_eq(buys, 2, "and bought then, once each")
