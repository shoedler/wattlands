extends GutTest
## Routing (brief 2.4 "Routing", 4 "caps per station"): station targets, the caps, next / prev /
## mine / hot, skipping full stations, the 2 s reconnect, waves only, the zero-input fallback.

var _rig: SiegeRig


func after_each() -> void:
	SiegeRouting.route_hook = Callable()


func _wave(humans: int = 4) -> SiegeRig:
	_rig = SiegeRig.new("short", humans)
	_rig.enter(2, 10.0)
	_rig.manual()
	return _rig


func _route(peer: int, to: Variant) -> Array[Dictionary]:
	_rig.send(peer, SiegeIntents.route(to))
	return _rig.step()


func test_everyone_starts_on_the_mine() -> void:
	_rig = SiegeRig.new("short", 4)
	for r in _rig.state.riders:
		assert_eq(r.target, SiegeIds.STATION_MINE)


func test_route_to_a_station_starts_a_2_s_reconnect() -> void:
	_wave()
	var ev := _route(1, SiegeIds.STATION_ONAGER)
	var r := _rig.rider(1)
	assert_eq(r.target, SiegeIds.STATION_ONAGER)
	assert_almost_eq(r.reconnect_s, 2.0 - 0.05, 1e-6)
	assert_false(r.delivering())
	assert_eq(_rig.of_type(SiegeIds.EV_ROUTE, ev), [SiegeEvents.route(0, SiegeIds.STATION_ONAGER)])


func test_no_output_during_the_reconnect() -> void:
	_wave(1)
	_rig.p_eff[1] = 250.0
	_route(1, SiegeIds.STATION_ONAGER)
	var on: Array[float] = []
	for _i in 41:
		_rig.step()
		on.append(_rig.state.station(SiegeIds.STATION_ONAGER).m)
	assert_eq(on[37], 0.0, "still reconnecting")
	assert_gt(on[40], 0.0, "2 s later: coupled")


func test_next_and_prev_step_through_the_stations() -> void:
	_wave(1)
	_route(1, "next")
	assert_eq(_rig.rider(1).target, SiegeIds.STATION_BALLISTA)
	_route(1, "next")
	assert_eq(_rig.rider(1).target, SiegeIds.STATION_ONAGER)
	_route(1, "prev")
	assert_eq(_rig.rider(1).target, SiegeIds.STATION_BALLISTA)
	_route(1, "prev")
	assert_eq(_rig.rider(1).target, SiegeIds.STATION_MINE)
	_route(1, "prev")
	assert_eq(_rig.rider(1).target, SiegeIds.STATION_TAR, "wraps 0 -> 4")
	_route(1, "next")
	assert_eq(_rig.rider(1).target, SiegeIds.STATION_MINE, "wraps 4 -> 0")


func test_up_is_the_mine_and_gen_is_accepted() -> void:
	_wave(1)
	_rig.put(1, SiegeIds.STATION_ARROWS)
	_route(1, "mine")
	assert_eq(_rig.rider(1).target, SiegeIds.STATION_MINE)
	_rig.put(1, SiegeIds.STATION_ARROWS)
	_route(1, "gen")
	assert_eq(_rig.rider(1).target, SiegeIds.STATION_MINE)


func test_caps_per_station() -> void:
	_wave(4)
	_route(1, SiegeIds.STATION_BALLISTA)
	_route(2, SiegeIds.STATION_BALLISTA)
	assert_eq(_rig.rider(2).target, SiegeIds.STATION_MINE, "the ballista holds 1")
	_route(2, SiegeIds.STATION_TAR)
	_route(3, SiegeIds.STATION_TAR)
	assert_eq(_rig.rider(3).target, SiegeIds.STATION_MINE, "the tar works hold 1")
	_route(3, SiegeIds.STATION_ONAGER)
	_route(4, SiegeIds.STATION_ONAGER)
	assert_eq(_rig.state.routed_count(SiegeIds.STATION_ONAGER), 2, "the onager holds 2")


func test_the_onager_and_arrows_hold_two_and_refuse_a_third() -> void:
	_wave(4)
	for id in [SiegeIds.STATION_ONAGER, SiegeIds.STATION_ARROWS]:
		for r in _rig.state.riders:
			_rig.put(r.peer, SiegeIds.STATION_MINE)
		_route(1, id)
		_route(2, id)
		_route(3, id)
		assert_eq(_rig.state.routed_count(id), 2, "station %d" % id)
		assert_eq(_rig.rider(3).target, SiegeIds.STATION_MINE)


func test_the_mine_holds_two_once_people_have_left_it() -> void:
	_wave(4)
	_rig.put(1, SiegeIds.STATION_ONAGER)
	_rig.put(2, SiegeIds.STATION_ONAGER)
	_route(1, "mine")
	assert_eq(_rig.rider(1).target, SiegeIds.STATION_ONAGER, "3 and 4 hold the mine's 2")


func test_caps_never_push_anyone_off() -> void:
	_wave(4)
	assert_eq(_rig.state.routed_count(SiegeIds.STATION_MINE), 4, "the start is over the cap")
	_rig.step()
	for r in _rig.state.riders:
		assert_eq(r.target, SiegeIds.STATION_MINE)


func test_next_skips_full_stations() -> void:
	_wave(3)
	_rig.put(2, SiegeIds.STATION_BALLISTA)
	_route(1, "next")
	assert_eq(_rig.rider(1).target, SiegeIds.STATION_ONAGER, "the ballista is full")
	_rig.put(3, SiegeIds.STATION_ARROWS)
	_rig.put(2, SiegeIds.STATION_ARROWS)
	_route(1, "next")
	assert_eq(_rig.rider(1).target, SiegeIds.STATION_TAR, "the arrow organ is full")


func test_prev_skips_full_stations() -> void:
	_wave(2)
	_rig.put(2, SiegeIds.STATION_TAR)
	_route(1, "prev")
	assert_eq(_rig.rider(1).target, SiegeIds.STATION_ARROWS)


func test_a_route_to_the_current_station_changes_nothing() -> void:
	_wave(1)
	_rig.put(1, SiegeIds.STATION_ONAGER)
	var ev := _route(1, SiegeIds.STATION_ONAGER)
	assert_eq(_rig.of_type(SiegeIds.EV_ROUTE, ev).size(), 0)
	assert_eq(_rig.rider(1).reconnect_s, 0.0)


func test_hot_takes_autopilot_s_pick() -> void:
	_wave(1)
	var p := SiegeKit.prog_in_band(_rig.state, SiegeIds.STATION_BALLISTA)
	for i in 3:
		_rig.spawn(SiegeIds.ENEMY_RAM, p + float(i))
	var want := SiegeAutopilot.hot_target(_rig.state, _rig.rider(1))
	assert_true(SiegeIds.is_weapon(want))
	_route(1, "hot")
	assert_eq(_rig.rider(1).target, want)


func test_hot_with_nothing_in_reach_stays_put() -> void:
	_wave(1)
	_rig.state.enemies.clear()
	_rig.state.queue.clear()
	_route(1, "hot")
	assert_eq(_rig.rider(1).target, SiegeIds.STATION_MINE)


func test_routing_happens_in_waves_only() -> void:
	_rig = SiegeRig.new("short", 1)
	_rig.enter(1, 5.0)
	_rig.manual()
	_route(1, SiegeIds.STATION_ONAGER)
	assert_eq(_rig.rider(1).target, SiegeIds.STATION_MINE, "the build break")
	_rig.enter(3, 5.0)
	_route(1, SiegeIds.STATION_ONAGER)
	assert_eq(_rig.rider(1).target, SiegeIds.STATION_MINE, "a break")


func test_breaks_keep_the_target() -> void:
	_wave(1)
	_rig.put(1, SiegeIds.STATION_ARROWS)
	_rig.enter(3, 5.0)
	assert_eq(_rig.rider(1).target, SiegeIds.STATION_ARROWS)
	_rig.enter(4, 1.0)
	assert_eq(_rig.rider(1).target, SiegeIds.STATION_ARROWS, "and the next wave starts there")


func test_auto_route_intents_are_ignored() -> void:
	_wave(1)
	_rig.send(1, {"k": "route", "to": 2, "auto": 1})
	_rig.step()
	assert_eq(_rig.rider(1).target, SiegeIds.STATION_MINE)


func test_a_deliberate_route_ends_the_routing_fallback() -> void:
	_rig = SiegeRig.new("short", 1)
	_rig.enter(2, 10.0)
	assert_true(_rig.rider(1).route_fallback)
	_route(1, SiegeIds.STATION_ONAGER)
	assert_false(_rig.rider(1).route_fallback)
	assert_true(_rig.rider(1).shop_fallback, "the shop fallback is separate")


func test_autopilot_routes_once_a_second_in_slot_order() -> void:
	_rig = SiegeRig.new("short", 2)
	_rig.enter(2, 10.0)
	var calls: Array = []
	SiegeRouting.route_hook = func(_st: SiegeState, r: SiegeRiderState) -> int:
		calls.append([_rig.tick, r.slot])
		return -1
	_rig.run(2.0)
	assert_eq(calls.size(), 4, "two riders, two seconds")
	assert_eq(int(calls[0][1]), 0)
	assert_eq(int(calls[1][1]), 1)


func test_autopilot_skips_afk_and_reconnecting_riders() -> void:
	_rig = SiegeRig.new("short", 2)
	_rig.enter(2, 10.0)
	_rig.afk[1] = true
	_rig.rider(2).reconnect_s = 5.0
	var calls := []
	SiegeRouting.route_hook = func(_st: SiegeState, r: SiegeRiderState) -> int:
		calls.append(r.slot)
		return -1
	_rig.run(1.0)
	assert_eq(calls, [])


func test_autopilot_respects_the_caps() -> void:
	_rig = SiegeRig.new("short", 2)
	_rig.enter(2, 10.0)
	_rig.put(2, SiegeIds.STATION_BALLISTA)
	_rig.rider(2).route_fallback = false
	SiegeRouting.route_hook = func(_st: SiegeState, _r: SiegeRiderState) -> int:
		return SiegeIds.STATION_BALLISTA
	_rig.run(1.0)
	assert_eq(_rig.rider(1).target, SiegeIds.STATION_MINE, "the ballista is full")


func test_the_reconnect_runs_down_at_the_end_of_the_tick() -> void:
	_wave(1)
	_route(1, SiegeIds.STATION_ARROWS)
	_rig.run(1.9)
	assert_gt(_rig.rider(1).reconnect_s, 0.0)
	_rig.run(0.06)
	assert_eq(_rig.rider(1).reconnect_s, 0.0)


func test_routed_t_stamps_the_change() -> void:
	_wave(1)
	_route(1, SiegeIds.STATION_ONAGER)
	assert_almost_eq(_rig.rider(1).routed_t, _rig.state.t, 1e-6)


func test_resolve_and_can_route_to() -> void:
	var s := SiegeKit.state("short", 2)
	var r := s.rider(1)
	assert_true(SiegeRouting.can_route_to(s, r, SiegeIds.STATION_TAR))
	assert_false(SiegeRouting.can_route_to(s, r, 5))
	assert_false(SiegeRouting.can_route_to(s, r, -1))
	SiegeKit.put(s, 2, SiegeIds.STATION_TAR)
	assert_false(SiegeRouting.can_route_to(s, r, SiegeIds.STATION_TAR))
	assert_true(SiegeRouting.can_route_to(s, s.rider(2), SiegeIds.STATION_TAR), "its own")
	assert_eq(SiegeRouting.resolve(s, r, SiegeIds.STATION_TAR), -1)
	assert_eq(SiegeRouting.resolve(s, r, SiegeIds.ROUTE_NEXT), SiegeIds.STATION_BALLISTA)


func test_next_from_the_tar_works_skips_a_full_mine() -> void:
	var s := SiegeKit.state("short", 4)
	SiegeKit.put(s, 1, SiegeIds.STATION_TAR)
	assert_eq(s.routed_count(SiegeIds.STATION_MINE), 3)
	assert_eq(SiegeRouting.step_from(s, s.rider(1), 1), SiegeIds.STATION_BALLISTA)
	assert_eq(SiegeRouting.step_from(s, s.rider(1), -1), SiegeIds.STATION_ARROWS)
