extends GutTest
## SiegeRules.step end to end: the phase flow and its events, the cool-down, Overdrive's
## preconditions through the rules path, rescue and AFK, and determinism.

var _rig: SiegeRig


func after_each() -> void:
	SiegeRouting.route_hook = Callable()
	SiegeShop.shop_hook = Callable()


func _types(list: Array[Dictionary]) -> Array:
	return list.map(func(e: Dictionary) -> String: return e["type"])


func test_wave_start_and_end_events_follow_the_phases() -> void:
	_rig = SiegeRig.new("short", 2)
	for i in 7:
		_rig.enter(i, 0.0)
	_rig.enter(7, 0.0)
	var starts := _rig.of_type(SiegeIds.EV_WAVE_START)
	var ends := _rig.of_type(SiegeIds.EV_WAVE_END)
	assert_eq(starts.size(), 4, "the warm-up wave and three waves")
	assert_eq(ends.size(), 4)
	assert_eq(starts.map(func(e: Dictionary) -> int: return e["n"]), [0, 1, 2, 3])
	assert_eq(starts.map(func(e: Dictionary) -> int: return e["ph"]), [0, 2, 4, 6])
	assert_eq(starts[0]["role"], SiegeIds.ROLE_WARMUP_WAVE)
	assert_eq(starts[1]["role"], SiegeIds.ROLE_WAVE)
	assert_eq(starts[1]["waves"], 3)
	assert_eq(ends.map(func(e: Dictionary) -> int: return e["ph"]), [0, 2, 4, 6])
	assert_eq(ends[3]["n"], 3)
	assert_eq(ends[3]["hp"], 130, "the gate's 130 HP (G2)")
	assert_eq(ends[3]["max"], 130)
	assert_true(_rig.state.done, "after the last wave")
	assert_eq(_rig.state.wave_gate_hp.size(), 3, "the warm-up wave is not scored")
	assert_eq(_rig.state.wave_gate_frac.size(), 3)


func test_done_only_after_the_last_wave_ends() -> void:
	_rig = SiegeRig.new("short", 1)
	for i in 6:
		_rig.enter(i, 0.0)
	assert_false(_rig.state.done)
	_rig.enter(6, 10.0)
	assert_false(_rig.state.done)
	_rig.enter(7, 0.0)
	assert_true(_rig.state.done)


func test_wave_end_reports_the_gate_and_leaks() -> void:
	_rig = SiegeRig.new("short", 1)
	_rig.enter(2, 5.0)
	_rig.spawn(SiegeIds.ENEMY_SHIELD, _rig.state.path.length_m - 0.01)
	_rig.step()
	_rig.enter(3, 0.0)
	var end := _rig.of_type(SiegeIds.EV_WAVE_END)[0]
	assert_eq([end["hp"], end["max"], end["leaks"], end["n"]], [124, 130, 1, 1])
	assert_eq(_rig.state.wave_gate_hp, [124] as Array[int])
	assert_almost_eq(_rig.state.wave_gate_frac[0], 124.0 / 130.0, 1e-9)
	assert_eq(_rig.state.leaks, 1)


func test_the_phase_roles_come_from_the_plan_not_the_kind() -> void:
	_rig = SiegeRig.new("drill", 1)
	_rig.enter(0, 1.0)
	assert_eq([_rig.state.role, _rig.state.phase_kind], [SiegeIds.ROLE_BUILD_BREAK, Wl.WARMUP])
	assert_true(_rig.state.shop_open())
	assert_false(_rig.state.in_wave())
	_rig.enter(1, 1.0)
	assert_eq([_rig.state.role, _rig.state.phase_kind], [SiegeIds.ROLE_WAVE, Wl.WARMUP])
	assert_true(_rig.state.in_wave())
	assert_false(_rig.state.shop_open())


func test_a_full_drill_runs_to_the_cooldown_and_is_done() -> void:
	_rig = SiegeRig.new("drill", 2, 1)
	_rig.run(120.1)
	assert_eq(_rig.state.role, SiegeIds.ROLE_COOLDOWN)
	assert_true(_rig.state.done)
	var kinds := _types(_rig.events)
	assert_eq(kinds.count(SiegeIds.EV_WAVE_START), 1)
	assert_eq(kinds.count(SiegeIds.EV_WAVE_END), 1)
	for e in _rig.events:
		assert_eq(SiegeEvents.check(e), "", "every event is well formed: %s" % [e])
	var sc := SiegeScore.compute(_rig.state)
	assert_true(["S", "A", "B", "C", "D"].has(sc["grade"]))


func test_the_cooldown_spawns_nothing_retreats_enemies_and_closes_shop_and_overdrive() -> void:
	_rig = SiegeRig.new("short", 1)
	_rig.enter(6, 100.0)
	var e := _rig.spawn(SiegeIds.ENEMY_SPEAR, 30.0)
	_rig.enter(7, 0.0)
	assert_eq(_rig.state.role, SiegeIds.ROLE_COOLDOWN)
	assert_eq(e.st, SiegeIds.EN_RETREAT)
	_rig.rider(1).gold = 500.0
	_rig.send(1, SiegeIntents.pick(SiegeIds.ITEM_MINE))
	_rig.send(1, SiegeIntents.overdrive(SiegeIds.VIA_ACTION))
	_rig.step()
	assert_eq(_rig.of_type(SiegeIds.EV_BUY), [], "a pick while the shop is closed is ignored")
	assert_eq(_rig.state.receipt.size(), 0)
	assert_eq(_rig.state.mine_level, 0)
	assert_eq(_rig.rider(1).od_state, SiegeIds.OD_READY)
	assert_true(_rig.state.take_od_requests().is_empty())
	_rig.run(60.0)
	assert_true(_rig.state.enemies.is_empty())
	assert_true(_rig.state.queue.is_empty())
	assert_eq(_rig.of_type(SiegeIds.EV_WAVE_START).size(), 1, "only wave 3's")


# --- Overdrive through the rules ---------------------------------------------------------------------


func _od(peer: int = 1, via: String = SiegeIds.VIA_ACTION) -> void:
	_rig.send(peer, SiegeIntents.overdrive(via))
	_rig.step()


func _started(peer: int = 1) -> bool:
	return _rig.rider(peer).od_state == SiegeIds.OD_PENDING and _rig.state.od_requests.has(peer)


func test_overdrive_starts_in_a_work_wave_with_30_s_left() -> void:
	_rig = SiegeRig.new("short", 1)
	_rig.enter(2, 10.0)
	_od()
	assert_true(_started())


func test_overdrive_is_refused_in_the_warm_up_wave() -> void:
	_rig = SiegeRig.new("short", 1)
	_rig.enter(0, 100.0)
	_od()
	assert_eq(_rig.rider(1).od_state, SiegeIds.OD_READY)
	assert_true(_rig.state.od_requests.is_empty())


func test_overdrive_is_refused_in_breaks() -> void:
	for phase in [1, 3, 5]:
		_rig = SiegeRig.new("short", 1)
		_rig.enter(phase, 10.0)
		_od()
		assert_eq(_rig.rider(1).od_state, SiegeIds.OD_READY, "phase %d" % phase)
		assert_true(_rig.state.od_requests.is_empty())


func test_overdrive_is_refused_in_the_drills_warmup_kind_wave() -> void:
	_rig = SiegeRig.new("drill", 1)
	_rig.enter(1, 10.0)
	_od()
	assert_eq(_rig.rider(1).od_state, SiegeIds.OD_READY)


func test_overdrive_is_refused_with_less_than_30_s_left() -> void:
	_rig = SiegeRig.new("short", 1)
	_rig.enter(2, 269.0)
	_od()
	assert_true(_started(), "31 s left: allowed")
	_rig = SiegeRig.new("short", 1)
	_rig.enter(2, 271.0)
	_od()
	assert_eq(_rig.rider(1).od_state, SiegeIds.OD_READY, "29 s left: refused")
	_rig = SiegeRig.new("short", 1)
	_rig.enter(2, 299.0)
	_od()
	assert_eq(_rig.rider(1).od_state, SiegeIds.OD_READY)


func test_overdrive_is_refused_in_rescue() -> void:
	_rig = SiegeRig.new("short", 1)
	_rig.rescue[1] = true
	_rig.enter(2, 10.0)
	_od()
	assert_eq(_rig.rider(1).od_state, SiegeIds.OD_READY)
	assert_false(_rig.rider(1).od_prompt)


func test_overdrive_is_refused_while_afk_for_bots_and_for_auto_intents() -> void:
	_rig = SiegeRig.new("short", 1, 1)
	_rig.afk[1] = true
	_rig.enter(2, 10.0)
	_od()
	assert_eq(_rig.rider(1).od_state, SiegeIds.OD_READY, "AFK")
	_rig.afk[1] = false
	_od(-1)
	assert_eq(_rig.rider(-1).od_state, SiegeIds.OD_READY, "a bot")
	var raw := SiegeIntents.overdrive(SiegeIds.VIA_ACTION)
	raw["auto"] = 1
	_rig.send(1, raw)
	_rig.step()
	assert_eq(_rig.rider(1).od_state, SiegeIds.OD_READY, "an auto intent (Autopilot's)")


func test_a_surge_needs_the_prompt_but_the_button_does_not() -> void:
	_rig = SiegeRig.new("short", 2)
	_rig.enter(2, 10.0)
	_od(1, SiegeIds.VIA_SURGE)
	assert_eq(_rig.rider(1).od_state, SiegeIds.OD_READY, "no enemy in range of the target")
	assert_false(_rig.rider(1).od_prompt)
	_rig.put(2, SiegeIds.STATION_ONAGER)
	_rig.spawn(SiegeIds.ENEMY_SHIELD, SiegeKit.prog_in_band(_rig.state, SiegeIds.STATION_ONAGER))
	_rig.step()
	assert_true(_rig.rider(2).od_prompt, "an enemy in range of the onager")
	assert_false(_rig.rider(1).od_prompt, "rider 1 is on the mine")
	_od(2, SiegeIds.VIA_SURGE)
	assert_true(_started(2))
	_od(1, SiegeIds.VIA_BUTTON)
	assert_true(_started(1), "the button needs only the safety gate")


func test_the_prompt_shows_during_a_rush() -> void:
	_rig = SiegeRig.new("endurance", 1)
	_rig.enter(2, 10.0)
	_rig.step()
	assert_false(_rig.rider(1).od_prompt)
	_rig.state.wave.rush_s = 10.0
	_rig.step()
	assert_true(_rig.rider(1).od_prompt)
	assert_true(_rig.state.rush_on())


func test_overdrive_ends_at_the_phase_change_with_the_normal_cooldown() -> void:
	_rig = SiegeRig.new("short", 1)
	_rig.enter(2, 10.0)
	_od()
	var r := _rig.rider(1)
	SiegeOverdrive.on_request_result(_rig.state, 1, true, 5, "")
	assert_eq(r.od_state, SiegeIds.OD_ACTIVE)
	_rig.enter(3, 0.0)
	assert_eq(r.od_state, SiegeIds.OD_COOLDOWN)
	assert_almost_eq(r.od_cd_s, 90.0 - 0.05, 1e-6)
	var ev := _rig.of_type(SiegeIds.EV_OVERDRIVE)
	assert_eq(ev[-1]["st"], SiegeIds.OD_EV_END)
	assert_eq(ev[-1]["why"], SiegeOverdrive.END_PHASE)


func test_rescue_or_afk_starting_ends_a_running_overdrive() -> void:
	for flag in ["rescue", "afk"]:
		_rig = SiegeRig.new("short", 1)
		_rig.enter(2, 10.0)
		_od()
		SiegeOverdrive.on_request_result(_rig.state, 1, true, 5, "")
		assert_eq(_rig.rider(1).od_state, SiegeIds.OD_ACTIVE)
		if flag == "rescue":
			_rig.rescue[1] = true
		else:
			_rig.afk[1] = true
		_rig.step()
		assert_eq(_rig.rider(1).od_state, SiegeIds.OD_COOLDOWN, flag)
		assert_eq(_rig.of_type(SiegeIds.EV_OVERDRIVE)[-1]["why"], flag)


func test_overdrive_doubles_station_output_through_the_rules() -> void:
	_rig = SiegeRig.new("short", 1)
	_rig.enter(2, 10.0)
	_rig.put(1, SiegeIds.STATION_ONAGER)
	_rig.p_eff[1] = 250.0
	_rig.power_w[1] = 250.0
	_rig.step()
	assert_almost_eq(_rig.state.station(SiegeIds.STATION_ONAGER).m, 1.0, 1e-6)
	_od()
	SiegeOverdrive.on_request_result(_rig.state, 1, true, 5, "")
	_rig.step()
	assert_almost_eq(
		_rig.state.station(SiegeIds.STATION_ONAGER).m, 2.0, 1e-6, "raw 250 W >= CP 200 W"
	)
	_rig.power_w[1] = 150.0
	_rig.step()
	assert_almost_eq(_rig.state.station(SiegeIds.STATION_ONAGER).m, 1.0, 1e-6, "below CP")


# --- determinism -------------------------------------------------------------------------------------


func _hash(rng_seed: int, humans: int = 3) -> Array:
	_rig = SiegeRig.new("vo2", humans, 0, rng_seed)
	_rig.enter(2, 0.0)
	_rig.put(1, SiegeIds.STATION_ONAGER)
	_rig.put(2, SiegeIds.STATION_ARROWS)
	_rig.run(100.0)
	var enemies := _rig.state.enemies.map(
		func(e: SiegeEnemyState) -> Array: return [e.id, e.type, e.prog_m, e.lat_m, e.hp]
	)
	return [JSON.stringify(_rig.events), JSON.stringify(enemies), _rig.state.next_enemy_id]


func test_the_same_rng_seedgives_identical_events_and_state() -> void:
	var a := _hash(5)
	var b := _hash(5)
	assert_eq(a, b)
	assert_gt(a[2], 20, "something happened")
	assert_ne(a, _hash(6))
