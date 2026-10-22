extends GutTest
## SiegeRouting (brief 2.4 "Routing", 2.5 "Zero input"): intents, the ring, the 2-rider limit,
## the 2 s reconnect, breaks, and Autopilot's once-a-second routing through the rules.

const VALLEY := SiegeIds.ROAD_VALLEY

var _rig: SiegeRig


func after_each() -> void:
	SiegeRouting.route_hook = Callable()
	SiegeShop.shop_hook = Callable()


func _wave(humans: int = 3, bots: int = 0) -> SiegeRig:
	_rig = SiegeRig.new("short", humans, bots)
	_rig.enter(2, 10.0)
	for r in _rig.state.riders:
		r.route_fallback = false
		r.shop_fallback = false
	return _rig


func _route(peer: int, to: Variant, via: String = SiegeIds.VIA_ACTION) -> void:
	_rig.send(peer, SiegeIntents.route(to, via))
	_rig.step()


func _build(pad: int, type: int = SiegeIds.TOWER_BALLISTA) -> void:
	_rig.state.pad(pad).type = type


func test_everyone_starts_on_the_generator() -> void:
	_rig = SiegeRig.new("short", 4)
	for r in _rig.state.riders:
		assert_eq(r.target, SiegeIds.TARGET_GEN)
		assert_eq(r.reconnect_s, 0.0)
	_rig.enter(2, 10.0)
	for r in _rig.state.riders:
		assert_eq(r.target, SiegeIds.TARGET_GEN, "the wave does not move anyone")


func test_a_pad_route_reconnects_for_two_seconds_with_no_output() -> void:
	_wave()
	_rig.p_eff[1] = 250.0
	_route(1, 3)
	var r := _rig.rider(1)
	assert_eq(r.target, 3)
	assert_almost_eq(r.reconnect_s, 2.0, 0.051, "2 s")
	assert_eq(_rig.of_type(SiegeIds.EV_ROUTE).size(), 1)
	assert_eq(_rig.of_type(SiegeIds.EV_ROUTE)[0]["slot"], 0)
	assert_eq(_rig.of_type(SiegeIds.EV_ROUTE)[0]["to"], 3)
	assert_eq(r.routed_t, _rig.state.t)
	var gen := r.gen_denarii
	var silent := 1
	for _i in 60:
		_rig.step()
		if _rig.state.pad(3).m > 0.0:
			break
		silent += 1
	assert_eq(silent, 40, "40 ticks (2 s) without output")
	assert_eq(r.gen_denarii, gen, "and no generator pay either")
	assert_almost_eq(_rig.state.pad(3).m, 1.0, 1e-6, "then the tower is powered")


func test_a_switch_between_towers_also_reconnects() -> void:
	_wave()
	_rig.put(1, 3)
	_route(1, 4)
	assert_eq(_rig.rider(1).target, 4)
	assert_gt(_rig.rider(1).reconnect_s, 1.9)


func test_routing_to_the_current_target_is_a_no_op() -> void:
	_wave()
	_rig.put(1, 3)
	_route(1, 3)
	assert_eq(_rig.rider(1).reconnect_s, 0.0)
	assert_eq(_rig.of_type(SiegeIds.EV_ROUTE).size(), 0)
	_route(1, "gen")
	assert_eq(_rig.rider(1).target, 0)
	_route(1, "gen")
	assert_eq(_rig.of_type(SiegeIds.EV_ROUTE).size(), 1)


func test_an_empty_pad_cannot_be_routed_to() -> void:
	_wave()
	_route(1, 5)
	assert_eq(_rig.rider(1).target, SiegeIds.TARGET_GEN)
	assert_eq(_rig.of_type(SiegeIds.EV_ROUTE).size(), 0)


func test_next_walks_the_ring_clockwise_and_skips_empty_pads() -> void:
	_wave()
	_route(1, "next")
	assert_eq(_rig.rider(1).target, 3, "pads 1 and 2 are empty")
	_route(1, "next")
	assert_eq(_rig.rider(1).target, 4)
	_route(1, "next")
	assert_eq(_rig.rider(1).target, SiegeIds.TARGET_GEN, "round to the generator")
	_route(1, "next")
	assert_eq(_rig.rider(1).target, 3)


func test_prev_walks_it_the_other_way() -> void:
	_wave()
	_route(1, "prev")
	assert_eq(_rig.rider(1).target, 4)
	_route(1, "prev")
	assert_eq(_rig.rider(1).target, 3)
	_route(1, "prev")
	assert_eq(_rig.rider(1).target, SiegeIds.TARGET_GEN)


func test_next_follows_the_map_ring_with_more_towers() -> void:
	_wave()
	_build(1)
	_build(6)
	var seen: Array[int] = []
	for _i in 6:
		_route(1, "next")
		seen.append(_rig.rider(1).target)
	assert_eq(seen, [1, 3, 4, 6, 0, 1] as Array[int])


func test_a_tower_with_two_riders_is_skipped_and_refused() -> void:
	_wave()
	_rig.put(1, 3)
	_rig.put(2, 3)
	_route(3, "next")
	assert_eq(_rig.rider(3).target, 4, "pad 3 is full")
	_rig.put(3, SiegeIds.TARGET_GEN)
	_route(3, 3)
	assert_eq(_rig.rider(3).target, SiegeIds.TARGET_GEN, "a direct route is refused too")
	_route(3, "prev")
	assert_eq(_rig.rider(3).target, 4)


func test_a_rider_already_on_a_full_tower_keeps_it() -> void:
	_wave()
	_rig.put(1, 3)
	_rig.put(2, 3)
	_route(1, 3)
	assert_eq(_rig.rider(1).target, 3)
	_route(1, "next")
	assert_eq(_rig.rider(1).target, 4)


func test_up_goes_to_the_generator() -> void:
	_wave()
	_rig.put(1, 4)
	_route(1, "gen")
	assert_eq(_rig.rider(1).target, SiegeIds.TARGET_GEN)


func test_hot_goes_to_the_tower_with_the_most_enemy_hp_in_range() -> void:
	_wave()
	_build(6)
	_rig.spawn(SiegeIds.ENEMY_SHIELD_WALL, SiegeIds.ROAD_WEST, 45.7)
	_rig.spawn(SiegeIds.ENEMY_RAIDERS, VALLEY, _rig.road_end(VALLEY) - 4.0)
	assert_gt(_rig.state.enemy_hp_in_range(6), _rig.state.enemy_hp_in_range(3))
	assert_gt(_rig.state.enemy_hp_in_range(3), 0.0)
	_route(1, "hot")
	assert_eq(_rig.rider(1).target, 6)


func test_hot_with_nothing_in_range_changes_nothing() -> void:
	_wave()
	_rig.put(1, 4)
	_route(1, "hot")
	assert_eq(_rig.rider(1).target, 4)


func test_hot_ties_go_to_the_lower_pad() -> void:
	_wave()
	_rig.spawn(SiegeIds.ENEMY_RAIDERS, VALLEY, _rig.road_end(VALLEY) - 1.0)
	_rig.state.enemies[0].pos = Vector2(0.0, 26.0)
	assert_eq(_rig.state.enemy_hp_in_range(3), _rig.state.enemy_hp_in_range(4))
	assert_gt(_rig.state.enemy_hp_in_range(3), 0.0)
	assert_eq(SiegeRouting.hot_pad(_rig.state, _rig.rider(1)), 3)


func test_hot_skips_a_full_tower() -> void:
	_wave()
	_rig.spawn(SiegeIds.ENEMY_SHIELD_WALL, VALLEY, _rig.road_end(VALLEY) - 1.0)
	_rig.state.enemies[0].pos = Vector2(0.0, 26.0)
	_rig.put(1, 3)
	_rig.put(2, 3)
	assert_eq(SiegeRouting.hot_pad(_rig.state, _rig.rider(3)), 4)


func test_breaks_send_all_output_to_the_generator_and_keep_the_target() -> void:
	_wave()
	_rig.put(1, 3)
	_rig.enter(3, 0.0)
	assert_eq(_rig.state.role, SiegeIds.ROLE_BREAK)
	_rig.p_eff[1] = 250.0
	var gen := _rig.rider(1).gen_denarii
	_rig.run(10.0)
	assert_eq(_rig.rider(1).target, 3, "the target is kept")
	assert_almost_eq(_rig.rider(1).gen_denarii - gen, 2.5, 0.05, "10 s x 250 W = 2.5 kJ")
	assert_eq(_rig.state.pad(3).m, 0.0, "towers idle")
	_route(1, 4)
	assert_eq(_rig.rider(1).target, 3, "no routing in a break")
	_rig.enter(4, 5.0)
	assert_eq(_rig.rider(1).target, 3, "and the next wave finds it where it was")


func test_a_route_in_the_cooldown_is_ignored() -> void:
	_wave()
	_rig.enter(7, 5.0)
	assert_eq(_rig.state.role, SiegeIds.ROLE_COOLDOWN)
	_route(1, 3)
	assert_eq(_rig.rider(1).target, SiegeIds.TARGET_GEN)


# --- zero input: Autopilot routes while the fallback holds ---------------------------------------


func _hook(calls: Array, answer: Callable) -> void:
	SiegeRouting.route_hook = func(_s: SiegeState, r: SiegeRiderState) -> int:
		calls.append(r.slot)
		return int(answer.call(r))


func test_autopilot_routes_once_a_second_in_slot_order() -> void:
	_rig = SiegeRig.new("short", 3)
	_rig.enter(2, 10.0)
	var calls: Array = []
	_hook(calls, func(_r: SiegeRiderState) -> int: return -1)
	calls.clear()
	_rig.run(3.0)
	assert_eq(calls, [0, 1, 2, 0, 1, 2, 0, 1, 2], "every 20 ticks, slots in order")


func test_autopilot_routing_applies_the_choice_and_respects_the_limit() -> void:
	_rig = SiegeRig.new("short", 3)
	_rig.enter(2, 10.0)
	var calls: Array = []
	_hook(calls, func(_r: SiegeRiderState) -> int: return 3)
	_rig.run(1.1)
	assert_eq(_rig.rider(1).target, 3)
	assert_eq(_rig.rider(2).target, 3)
	assert_eq(_rig.rider(3).target, SiegeIds.TARGET_GEN, "pad 3 is full: the third stays")
	assert_eq(_rig.of_type(SiegeIds.EV_ROUTE).size(), 2)


func test_a_human_stops_being_autopiloted_with_the_first_route_intent() -> void:
	_rig = SiegeRig.new("short", 2)
	_rig.enter(2, 10.0)
	var calls: Array = []
	_hook(calls, func(_r: SiegeRiderState) -> int: return -1)
	_rig.send(1, SiegeIntents.route(4))
	_rig.step()
	assert_false(_rig.rider(1).route_fallback)
	assert_true(_rig.rider(2).route_fallback)
	calls.clear()
	_rig.run(1.1)
	assert_eq(calls, [1], "only the rider who never routed")


func test_overdrive_and_auto_intents_do_not_end_the_routing_fallback() -> void:
	_rig = SiegeRig.new("short", 1)
	_rig.enter(2, 10.0)
	_rig.send(1, SiegeIntents.overdrive(SiegeIds.VIA_SURGE))
	_rig.step()
	assert_true(_rig.rider(1).route_fallback)
	_rig.send(1, SiegeIntents.route(3, SiegeIds.VIA_AUTO))
	_rig.step()
	assert_true(_rig.rider(1).route_fallback)
	assert_eq(_rig.rider(1).target, SiegeIds.TARGET_GEN, "an auto route is ignored")


func test_bots_and_autopilot_humans_are_always_autopiloted() -> void:
	_rig = SiegeRig.new("short", 2, 1)
	_rig.enter(2, 10.0)
	_rig.rider(2).autopilot = true
	_rig.rider(2).route_fallback = false
	_rig.rider(1).route_fallback = false
	var calls: Array = []
	_hook(calls, func(_r: SiegeRiderState) -> int: return -1)
	calls.clear()
	_rig.run(1.0)
	assert_eq(calls, [1, 2], "the Autopilot-on human (slot 1) and the bot (slot 2)")
	_rig.send(-1, SiegeIntents.route(3))
	_rig.step()
	assert_true(_rig.rider(-1).route_fallback, "bots never clear it")


func test_autopilot_does_not_route_afk_reconnecting_or_break_riders() -> void:
	_rig = SiegeRig.new("short", 3)
	_rig.enter(2, 10.0)
	var calls: Array = []
	_hook(calls, func(_r: SiegeRiderState) -> int: return -1)
	_rig.afk[1] = true
	_rig.rider(2).reconnect_s = 5.0
	calls.clear()
	_rig.run(1.0)
	assert_eq(calls, [2], "slot 0 is AFK, slot 1 is reconnecting")
	_rig.afk[1] = false
	_rig.enter(3, 0.0)
	calls.clear()
	_rig.run(3.0)
	assert_eq(calls, [], "no routing in a break")


func test_autopilot_keeps_the_target_on_minus_one() -> void:
	_rig = SiegeRig.new("short", 1)
	_rig.enter(2, 10.0)
	_rig.put(1, 4)
	_rig.rider(1).route_fallback = true
	_hook([], func(_r: SiegeRiderState) -> int: return -1)
	_rig.run(2.0)
	assert_eq(_rig.rider(1).target, 4)
