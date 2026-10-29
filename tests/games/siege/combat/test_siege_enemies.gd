extends GutTest
## Enemies on the road (brief 2.4 "Enemies", "Gate and Breach"; 4): walking at their speeds,
## chariot speed changes, the coated bridge, leaks and gate damage, the ram's battering, the
## siege tower docking and its boarders, retreat, the Breach and its gold cut, the warm-up floor.

var _s: SiegeState


func before_each() -> void:
	_s = SiegeKit.state("short", 2)
	_s.pad(1).type = SiegeIds.PAD_NONE


func _run(seconds: float) -> Array[Dictionary]:
	return SiegeKit.run_combat(_s, seconds)


func test_walkers_move_at_their_speed() -> void:
	var sp := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, 10.0)
	var sh := SiegeKit.enemy(_s, SiegeIds.ENEMY_SHIELD, 10.0)
	var ram := SiegeKit.enemy(_s, SiegeIds.ENEMY_RAM, 10.0)
	var tw := SiegeKit.enemy(_s, SiegeIds.ENEMY_TOWER, 10.0)
	_run(10.0)
	assert_almost_eq(sp.prog_m, 28.0, 0.01, "1.8 m/s")
	assert_almost_eq(sh.prog_m, 22.0, 0.01, "1.2 m/s")
	assert_almost_eq(ram.prog_m, 18.0, 0.01, "0.8 m/s")
	assert_almost_eq(tw.prog_m, 15.0, 0.01, "0.5 m/s")


func test_pos_follows_prog_and_lateral_offset() -> void:
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, 50.0, -1.2)
	_run(1.0)
	assert_true(e.pos.is_equal_approx(_s.path.point_at(e.prog_m, -1.2)))


func test_a_chariot_draws_speeds_within_30_percent() -> void:
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_CHARIOT, 10.0)
	e.redraw_s = 0.0
	var seen: Array[float] = []
	for _i in 120:
		_run(0.5)
		seen.append(e.want_mps)
		if e.prog_m > 300.0:
			e.prog_m = 10.0
	var lo := seen.min() as float
	var hi := seen.max() as float
	assert_gte(lo, 6.0 * 0.7 - 1e-6)
	assert_lte(hi, 6.0 * 1.3 + 1e-6)
	assert_gt(hi - lo, 1.0, "the speed really changes")


func test_a_chariot_redraws_every_3_to_6_s() -> void:
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_CHARIOT, 10.0)
	e.redraw_s = 0.0
	var changes := 0
	var last := -1.0
	for _i in 600:
		_run(0.05)
		if e.want_mps != last:
			changes += 1
			last = e.want_mps
		if e.prog_m > 300.0:
			e.prog_m = 10.0
	assert_between(changes, 30.0 / 6.0, 30.0 / 3.0 + 2.0, "30 s: 5 to 10 draws")


func test_a_chariot_accelerates_at_2_m_per_s2() -> void:
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_CHARIOT, 10.0)
	e.speed_mps = 4.2
	e.want_mps = 7.8
	e.redraw_s = 100.0
	_run(1.0)
	assert_almost_eq(e.speed_mps, 6.2, 0.01)
	_run(1.0)
	assert_almost_eq(e.speed_mps, 7.8, 0.01, "and holds at its wish")


func test_spawned_chariots_start_at_their_drawn_speed() -> void:
	SiegeSpawner.enqueue(_s, SiegeIds.ENEMY_CHARIOT, 0.0)
	SiegeSpawner.drain(_s, SiegeKit.table(_s), [])
	var e := _s.enemies[0]
	assert_eq(e.speed_mps, e.want_mps)
	assert_between(e.redraw_s, 3.0, 6.0)


func test_the_coated_bridge_slows_everything_on_it() -> void:
	_s.tar.curtain_hp = 150.0
	var on := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, _s.path.bridge_from_m + 1.0)
	var off := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, _s.path.bridge_from_m - 40.0)
	_run(0.05)
	_run(2.0)
	assert_almost_eq(on.speed_mps, 0.9, 0.01, "x (1 - 0.5 x coat)")
	assert_almost_eq(off.speed_mps, 1.8, 0.01)


func test_chariots_on_a_coated_bridge_lose_their_speed_changes() -> void:
	_s.tar.curtain_hp = 150.0
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_CHARIOT, _s.path.bridge_from_m + 0.5)
	e.want_mps = 7.5
	e.speed_mps = 7.5
	_run(0.05)
	_run(0.05)
	assert_almost_eq(e.speed_mps, 3.0, 0.01, "the base speed, halved")
	assert_eq(e.want_mps, 6.0)


func test_a_spearman_at_the_gate_leaks_2_hp_and_is_gone() -> void:
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, _s.path.length_m - 0.05)
	var ev := _run(0.05)
	assert_eq(_s.gate_hp, 128.0)
	var leaks := SiegeKit.of_type(ev, SiegeIds.EV_LEAK)
	assert_eq(leaks.size(), 1)
	assert_eq(leaks[0], SiegeEvents.leak(e.id, SiegeIds.ENEMY_SPEAR, 2))
	assert_true(_s.enemies.is_empty())
	assert_eq(_s.leaks, 1)


func test_gate_damage_per_type() -> void:
	for spec: Array in [[SiegeIds.ENEMY_SHIELD, 6.0], [SiegeIds.ENEMY_CHARIOT, 4.0]]:
		_s.gate_hp = 130.0
		SiegeKit.enemy(_s, int(spec[0]), _s.path.length_m - 0.01)
		_run(0.05)
		assert_eq(_s.gate_hp, 130.0 - float(spec[1]), "type %d" % spec[0])


func test_leaks_in_the_warm_up_are_not_counted_for_results() -> void:
	_s.role = SiegeIds.ROLE_WARMUP_WAVE
	SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, _s.path.length_m - 0.01)
	_run(0.05)
	assert_eq(_s.leaks, 0)
	assert_eq(_s.wave.leaks, 1)


func test_a_ram_batters_its_rate_with_one_leak_per_hp() -> void:
	var ram := SiegeKit.enemy(_s, SiegeIds.ENEMY_RAM, _s.path.length_m - 0.02)
	_run(0.05)
	assert_eq(ram.st, SiegeIds.EN_BATTER)
	assert_true(ram.reached)
	var rate := float(_s.content.enemy_def(SiegeIds.ENEMY_RAM)["gate_hp_per_s"])
	var ev := _run(10.0)
	assert_almost_eq(_s.gate_hp, 130.0 - 10.0 * rate, 0.2)
	assert_eq(SiegeKit.of_type(ev, SiegeIds.EV_LEAK).size(), floori(10.0 * rate + 1e-6))
	assert_eq(ram.speed_mps, 0.0)


func test_the_curtain_takes_the_ram_first() -> void:
	SiegeKit.enemy(_s, SiegeIds.ENEMY_RAM, _s.path.length_m)
	_s.tar.curtain_hp = 50.0
	_run(0.05)
	_run(5.0)
	assert_eq(_s.gate_hp, 130.0)
	assert_lt(_s.tar.curtain_hp, 50.0 - 15.0 + 0.5)


func test_the_siege_tower_docks_at_the_moat_edge() -> void:
	var t := SiegeKit.enemy(_s, SiegeIds.ENEMY_TOWER, _s.path.moat_edge_m - 0.02)
	var ev := _run(0.05)
	assert_eq(t.st, SiegeIds.EN_DOCKED)
	assert_eq(t.prog_m, _s.path.moat_edge_m)
	assert_true(t.reached)
	assert_true(_s.tar.boarded)
	assert_eq(SiegeKit.of_type(ev, SiegeIds.EV_DOCK), [SiegeEvents.dock(t.id)])
	_run(5.0)
	assert_eq(t.prog_m, _s.path.moat_edge_m, "it stays")
	assert_eq(_s.gate_hp, 130.0, "a docked tower never batters the gate")


func test_boarders_leave_with_the_tower() -> void:
	var t := SiegeKit.enemy(_s, SiegeIds.ENEMY_TOWER, _s.path.moat_edge_m)
	t.st = SiegeIds.EN_DOCKED
	_run(0.05)
	assert_true(_s.tar.boarded)
	t.hp = 0.0
	_run(0.05)
	assert_false(_s.tar.boarded)


func test_arrivals_vanish_without_damage_in_a_breach() -> void:
	_s.breach_s = 5.0
	SiegeKit.enemy(_s, SiegeIds.ENEMY_SHIELD, _s.path.length_m - 0.01)
	var ev := _run(0.05)
	assert_eq(_s.gate_hp, 130.0)
	assert_eq(_s.enemies.size(), 0)
	assert_eq(int(SiegeKit.of_type(ev, SiegeIds.EV_LEAK)[0]["dmg"]), 0)


func test_rams_pause_in_a_breach() -> void:
	var ram := SiegeKit.enemy(_s, SiegeIds.ENEMY_RAM, _s.path.length_m)
	ram.st = SiegeIds.EN_BATTER
	_s.gate_hp = 20.0
	_s.breach_s = 3.0
	_run(2.0)
	assert_eq(_s.gate_hp, 20.0)


func test_the_gate_breaches_at_0_and_restores_to_30_after_10_s() -> void:
	_s.gate_hp = 2.0
	SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, _s.path.length_m - 0.01)
	var ev := _run(0.05)
	assert_eq(_s.gate_hp, 0.0)
	assert_eq(_s.breaches, 1)
	assert_eq(SiegeKit.of_type(ev, SiegeIds.EV_BREACH), [SiegeEvents.breach(1)])
	assert_almost_eq(_s.breach_s, 10.0, 1e-6)
	ev = _run(9.95)
	assert_eq(SiegeKit.of_type(ev, SiegeIds.EV_GATE_RESTORED).size(), 0)
	ev = _run(0.05)
	assert_eq(SiegeKit.of_type(ev, SiegeIds.EV_GATE_RESTORED), [SiegeEvents.gate_restored(30.0)])
	assert_eq(_s.gate_hp, 30.0)


func test_a_breach_costs_every_rider_30_percent_of_their_gold_rounded_down() -> void:
	_s.rider(1).gold = 101.6
	_s.rider(2).gold = 9.0
	_s.gate_hp = 1.0
	SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, _s.path.length_m - 0.01)
	_run(10.05)
	assert_almost_eq(_s.rider(1).gold, 101.6 - 30.0, 1e-6, "floor(0.3 x floor(101.6)) = 30")
	assert_almost_eq(_s.rider(2).gold, 7.0, 1e-6, "floor(2.7) = 2")


func test_the_warm_up_gate_stays_at_or_above_50() -> void:
	_s.role = SiegeIds.ROLE_WARMUP_WAVE
	_s.gate_hp = 54.0
	var ev: Array[Dictionary] = []
	SiegeCombat.damage_gate(_s, 10.0, ev)
	assert_eq(_s.gate_hp, 50.0)
	SiegeCombat.damage_gate(_s, 10.0, ev)
	assert_eq(_s.gate_hp, 50.0)
	assert_eq(_s.breaches, 0)


func test_no_floor_outside_the_warm_up() -> void:
	_s.gate_hp = 54.0
	var ev: Array[Dictionary] = []
	SiegeCombat.damage_gate(_s, 10.0, ev)
	assert_eq(_s.gate_hp, 44.0)


func test_gate_damage_is_counted_for_the_wave() -> void:
	var ev: Array[Dictionary] = []
	SiegeCombat.damage_gate(_s, 7.0, ev)
	assert_eq(_s.wave.gate_damage, 7.0)
	assert_eq(_s.gate_damage, 7.0)


func test_retreating_enemies_walk_back_and_vanish_after_3_s() -> void:
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, 100.0)
	e.st = SiegeIds.EN_RETREAT
	e.retreat_s = 3.0
	_run(2.0)
	assert_almost_eq(e.prog_m, 100.0 - 3.6, 0.01)
	assert_eq(_s.enemies.size(), 1)
	_run(1.05)
	assert_eq(_s.enemies.size(), 0)


func test_retreating_enemies_never_reach_the_gate_or_pay() -> void:
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, _s.path.length_m - 0.01)
	e.st = SiegeIds.EN_RETREAT
	e.retreat_s = 3.0
	var gold := _s.rider(1).gold
	_run(3.1)
	assert_eq(_s.gate_hp, 130.0)
	assert_eq(_s.rider(1).gold, gold)


func test_bodies_do_not_collide() -> void:
	var a := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, 50.0, 0.0)
	var b := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, 50.0, 0.0)
	_run(2.0)
	assert_eq(a.prog_m, b.prog_m)
	assert_eq(a.pos, b.pos)
