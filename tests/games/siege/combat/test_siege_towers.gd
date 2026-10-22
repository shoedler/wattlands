extends GutTest
## SiegeTowers (brief 2.4 "Tower output" and "Towers (P0)"): output m, perks, fire interval,
## targeting, the three towers and their upgrades, damage, bounties and kills.

const VALLEY := SiegeIds.ROAD_VALLEY

var _rig: SiegeRig


## Wave 1 of `short`, 10 s in, riders on the generator (no Autopilot) and the starting towers on pads 3 and 4.
func _wave(humans: int = 2, patch: Callable = Callable()) -> SiegeRig:
	_rig = SiegeRig.new("short", humans, 0, 7, Wl.FAIR_FTP, patch).manual()
	_rig.enter(2, 10.0)
	return _rig


func _powered(peer: int, pad: int, p_eff: float, raw: float = 100.0) -> void:
	_rig.put(peer, pad)
	_rig.p_eff[peer] = p_eff
	_rig.power_w[peer] = raw


func _pad_m(pad: int) -> float:
	return _rig.state.pad(pad).m


## A far enemy that soaks fire: a ram at the gate with huge HP, and a gate nothing can breach.
func _soak() -> SiegeEnemyState:
	_rig.state.gate_hp = 1.0e9
	_rig.state.gate_max = 1.0e9
	var ram := _rig.spawn(SiegeIds.ENEMY_RAM, VALLEY, _rig.road_end(VALLEY), 0.0, 1.0e9)
	ram.st = SiegeIds.EN_BATTER
	return ram


func _prog_at(road: int, pad: int, dist: float) -> float:
	var map := _rig.content.map
	var at := map.pad_pos(pad)
	var best := 0.0
	var gap := INF
	var p := 0.0
	while p <= map.road_length(road):
		var g := absf(map.point_at(road, p).distance_to(at) - dist)
		if g < gap:
			gap = g
			best = p
		p += 0.05
	return best


func test_output_is_linear_in_p_eff() -> void:
	_wave()
	_powered(1, 3, 125.0)
	_rig.step()
	assert_almost_eq(_pad_m(3), 0.5, 1e-6, "0.5 at 125 W")
	_rig.p_eff[1] = 250.0
	_rig.step()
	assert_almost_eq(_pad_m(3), 1.0, 1e-6)
	_rig.p_eff[1] = 500.0
	_rig.step()
	assert_almost_eq(_pad_m(3), 2.0, 1e-6)


func test_two_riders_add() -> void:
	_wave()
	_powered(1, 3, 250.0)
	_powered(2, 3, 250.0)
	_rig.step()
	assert_almost_eq(_pad_m(3), 2.0, 1e-6, "2.0 for two riders at 250 W each")


func test_output_caps_at_4() -> void:
	_wave(3)
	for peer in [1, 2, 3]:
		_powered(peer, 3, 400.0)
	_rig.step()
	assert_almost_eq(_pad_m(3), 4.0, 1e-6, "1200 W / 250 = 4.8, capped")


func test_upgrade_one_adds_40_percent_before_the_cap() -> void:
	_wave(3)
	_rig.state.pad(3).level = 1
	_powered(1, 3, 250.0)
	_rig.step()
	assert_almost_eq(_pad_m(3), 1.4, 1e-6)
	for peer in [2, 3]:
		_powered(peer, 3, 400.0)
	_rig.p_eff[1] = 400.0
	_rig.step()
	assert_almost_eq(_pad_m(3), 4.0, 1e-6, "1200 / 250 x 1.4 = 6.72, capped at 4.0")


func test_overdrive_doubles_only_while_raw_power_reaches_cp() -> void:
	_wave()
	_powered(1, 3, 250.0, 200.0)
	var r := _rig.rider(1)
	r.od_state = SiegeIds.OD_ACTIVE
	r.od_s = 20.0
	_rig.step()
	assert_almost_eq(_pad_m(3), 2.0, 1e-6, "raw 200 W = slot FTP (CP): od = 2")
	_rig.power_w[1] = 199.0
	_rig.step()
	assert_almost_eq(_pad_m(3), 1.0, 1e-6, "below CP: od = 1")
	r.od_state = SiegeIds.OD_READY
	_rig.power_w[1] = 300.0
	_rig.step()
	assert_almost_eq(_pad_m(3), 1.0, 1e-6, "no Overdrive running: od = 1")


func test_a_reconnecting_afk_or_disconnected_rider_gives_no_output() -> void:
	_wave()
	_powered(1, 3, 250.0)
	_rig.rider(1).reconnect_s = 1.0
	_rig.step()
	assert_eq(_pad_m(3), 0.0, "reconnecting")
	_rig.rider(1).reconnect_s = 0.0
	_rig.afk[1] = true
	_rig.step()
	assert_eq(_pad_m(3), 0.0, "AFK stops the wheel")
	_rig.afk[1] = false
	_rig.rescue[1] = true
	_rig.step()
	assert_almost_eq(_pad_m(3), 1.0, 1e-6, "rescue counts at actual P_eff")


func test_an_unpowered_tower_idles() -> void:
	_wave()
	_soak()
	var tw := _rig.state.pad(3)
	tw.cd_s = 0.5
	_rig.run(2.0)
	assert_eq(tw.m, 0.0)
	assert_almost_eq(tw.cd_s, 0.5, 1e-6, "the cooldown does not run")
	assert_eq(tw.damage, 0.0)
	assert_true(_rig.state.shots.is_empty())


func test_reserve_flywheel_holds_the_last_m_for_10_s() -> void:
	_wave()
	_rig.state.perks = [SiegeIds.PERK_RESERVE]
	_powered(1, 3, 250.0)
	_rig.run(1.0)
	assert_almost_eq(_pad_m(3), 1.0, 1e-6)
	_rig.put(1, SiegeIds.TARGET_GEN)
	_rig.run(9.5)
	assert_almost_eq(_pad_m(3), 1.0, 1e-6, "still held after 9.5 s")
	_rig.run(1.0)
	assert_eq(_pad_m(3), 0.0, "gone after 10 s")


func test_without_the_perk_a_tower_stops_at_once() -> void:
	_wave()
	_powered(1, 3, 250.0)
	_rig.run(1.0)
	_rig.put(1, SiegeIds.TARGET_GEN)
	_rig.step()
	assert_eq(_pad_m(3), 0.0)


func test_aqueduct_drive_gives_an_unpowered_tower_a_quarter() -> void:
	_wave()
	_rig.state.perks = [SiegeIds.PERK_AQUEDUCT]
	_rig.step()
	assert_almost_eq(_pad_m(3), 0.25, 1e-6)
	assert_almost_eq(_pad_m(4), 0.25, 1e-6)
	assert_eq(_pad_m(5), 0.0, "an empty pad stays empty")
	_powered(1, 3, 500.0)
	_rig.step()
	assert_almost_eq(_pad_m(3), 2.0, 1e-6, "a powered tower uses its riders")


func test_towers_are_silent_outside_waves() -> void:
	_rig = SiegeRig.new("short", 1)
	_rig.state.perks = [SiegeIds.PERK_AQUEDUCT]
	_rig.enter(1, 10.0)
	assert_eq(_rig.state.role, SiegeIds.ROLE_BUILD_BREAK)
	assert_eq(_pad_m(3), 0.0)


func test_fire_interval_is_the_base_interval_over_m() -> void:
	for m in [1.0, 2.0]:
		_wave()
		_soak()
		var tw := _rig.state.pad(3)
		tw.cd_s = 0.0
		_powered(1, 3, 250.0 * m)
		_rig.run(20.0)
		var shots := roundi(tw.damage / 26.0)
		assert_between(shots, int(10 * m), int(10 * m) + 1, "ballista at m = %s: 2 s / m" % m)


func test_ballista_hits_the_enemy_nearest_the_gate() -> void:
	_wave()
	_powered(1, 3, 250.0)
	var far := _rig.spawn(SiegeIds.ENEMY_SHIELD_WALL, VALLEY, _rig.road_end(VALLEY) - 25.0)
	var near := _rig.spawn(SiegeIds.ENEMY_SHIELD_WALL, VALLEY, _rig.road_end(VALLEY) - 10.0)
	_rig.state.pad(3).cd_s = 0.0
	_rig.run(0.2)
	assert_almost_eq(near.hp, 160.0 - 22.0, 1e-3, "30 damage - 8 armor")
	assert_eq(far.hp, 160.0)


func test_a_shot_is_recorded_for_two_ticks() -> void:
	_wave()
	_powered(1, 3, 250.0)
	var e := _rig.spawn(SiegeIds.ENEMY_SHIELD_WALL, VALLEY, _rig.road_end(VALLEY) - 10.0)
	_rig.state.pad(3).cd_s = 0.0
	var seen := 0
	for _i in 6:
		_rig.step()
		for s in _rig.state.shots:
			if s.pad == 3:
				assert_eq(s.targets, [e.id] as Array[int])
				seen += 1
				break
	assert_eq(seen, 2, "each 10 Hz snapshot carries a shot once: it lives 0.1 s")


func test_damage_is_at_least_one() -> void:
	var patch := func(files: Dictionary) -> void: files["enemies"]["raiders"]["armor"] = 15
	_wave(2, patch)
	_powered(1, 4, 250.0)
	var e := _rig.spawn(SiegeIds.ENEMY_RAIDERS, VALLEY, _rig.road_end(VALLEY) - 5.0)
	_rig.state.pad(4).cd_s = 0.0
	_rig.step()
	assert_almost_eq(e.hp, 19.0, 1e-3, "max(1, 10 - 15)")


func test_pierce_takes_up_to_four_in_a_one_metre_corridor() -> void:
	_wave()
	var at := Vector2.ZERO
	var def := _rig.content.tower_def(SiegeIds.TOWER_BALLISTA)
	var line: Array[SiegeEnemyState] = []
	for d: Array in [[0.0, 10.0], [0.3, 20.0], [-0.4, 30.0], [0.0, 40.0], [0.0, 50.0]]:
		var e := SiegeEnemyState.new()
		e.hp = 10.0
		e.pos = Vector2(d[0], d[1])
		line.append(e)
	var off := SiegeEnemyState.new()
	off.hp = 10.0
	off.pos = Vector2(0.6, 25.0)
	var behind := SiegeEnemyState.new()
	behind.hp = 10.0
	behind.pos = Vector2(0.0, -10.0)
	_rig.state.enemies.clear()
	_rig.state.enemies.append_array(line)
	_rig.state.enemies.append(off)
	_rig.state.enemies.append(behind)
	var hit := SiegeTowers.pierce(_rig.state, line[4], at, 100.0, 4, def)
	assert_eq(hit.size(), 4, "up to 4")
	assert_eq(hit[0], line[4], "the primary target first")
	assert_false(hit.has(off), "0.6 m off the line: outside a 1 m wide corridor")
	assert_false(hit.has(behind), "behind the tower")
	assert_true(hit.has(line[0]) and hit.has(line[1]) and hit.has(line[2]))
	var short := SiegeTowers.pierce(_rig.state, line[4], at, 100.0, 1, def)
	assert_eq(short.size(), 1)


func test_ballista_upgrade_three_ignores_armor() -> void:
	_wave()
	_powered(1, 3, 250.0)
	_rig.state.pad(3).level = 3
	var e := _rig.spawn(SiegeIds.ENEMY_SHIELD_WALL, VALLEY, _rig.road_end(VALLEY) - 10.0)
	_rig.state.pad(3).cd_s = 0.0
	_rig.step()
	assert_almost_eq(e.hp, 130.0, 1e-3, "full 30 damage against armor 8")


func test_range_upgrade_adds_a_quarter() -> void:
	_wave()
	_powered(1, 3, 250.0)
	var prog := _prog_at(VALLEY, 3, 45.0)
	var e := _rig.spawn(SiegeIds.ENEMY_SHIELD_WALL, VALLEY, prog)
	_rig.state.pad(3).cd_s = 0.0
	_rig.run(0.3)
	assert_eq(e.hp, 160.0, "45 m is out of the Ballista's 40 m")
	_rig.state.pad(3).level = 2
	_rig.state.pad(3).cd_s = 0.0
	_rig.run(0.3)
	assert_lt(e.hp, 160.0, "50 m with upgrade 2")


func test_scorpion_hits_the_three_nearest_the_gate_and_five_with_upgrade_three() -> void:
	_wave()
	_powered(1, 4, 250.0)
	var list: Array[SiegeEnemyState] = []
	for i in 7:
		list.append(
			_rig.spawn(SiegeIds.ENEMY_SHIELD_WALL, VALLEY, _rig.road_end(VALLEY) - 1.0 - float(i))
		)
	_rig.state.pad(4).cd_s = 0.0
	_rig.step()
	for i in 7:
		var want := 160.0 - 2.0 if i < 3 else 160.0
		assert_almost_eq(list[i].hp, want, 1e-3, "enemy %d: 10 - 8 armor = 2 on the 3 nearest" % i)
	_rig.state.pad(4).level = 3
	_rig.state.pad(4).cd_s = 0.0
	_rig.step()
	for i in 7:
		var want := 160.0 - (4.0 if i < 3 else (2.0 if i < 5 else 0.0))
		assert_almost_eq(list[i].hp, want, 1e-3, "enemy %d: 5 nearest with upgrade 3" % i)


func test_scorpion_range_is_18_m() -> void:
	_wave()
	_powered(1, 4, 250.0)
	var e := _rig.spawn(SiegeIds.ENEMY_SHIELD_WALL, VALLEY, _prog_at(VALLEY, 4, 19.0))
	_rig.state.pad(4).cd_s = 0.0
	_rig.run(0.3)
	assert_eq(e.hp, 160.0, "19 m is out of range")
	var near := _rig.spawn(SiegeIds.ENEMY_SHIELD_WALL, VALLEY, _prog_at(VALLEY, 4, 17.0))
	_rig.state.pad(4).cd_s = 0.0
	_rig.run(0.3)
	assert_lt(near.hp, 160.0)


func _caltrop_rig() -> SiegeEnemyState:
	_wave()
	var tw := _rig.state.pad(3)
	tw.type = SiegeIds.TOWER_CALTROP
	tw.cd_s = 0.0
	_powered(1, 3, 250.0)
	return _rig.spawn(SiegeIds.ENEMY_RAIDERS, VALLEY, _prog_at(VALLEY, 3, 20.0), 0.0, 1000.0)


func test_caltrop_throws_a_zone_that_lands_after_one_second_for_four() -> void:
	var e := _caltrop_rig()
	var before := e.prog_m
	_rig.step()
	assert_eq(_rig.state.zones.size(), 1)
	var z := _rig.state.zones[0]
	assert_eq(z.pad, 3)
	assert_eq(z.road, VALLEY)
	assert_almost_eq(z.radius_m, 6.0, 1e-6)
	assert_almost_eq(z.slow, 0.6, 1e-6, "40% slower")
	assert_almost_eq(z.amp, 1.0, 1e-6)
	assert_false(z.landed(), "in flight")
	assert_almost_eq(
		z.prog_m, before + 2.2 + 2.2 * 0.05, 0.2, "the lead's predicted spot after 1.0 s"
	)
	assert_eq(e.hp, 1000.0, "no damage")
	_rig.run(0.9)
	assert_false(_rig.state.zones[0].landed())
	_rig.run(0.2)
	assert_true(_rig.state.zones[0].landed(), "landed after 1.0 s")
	assert_almost_eq(_rig.state.zones[0].ttl_s, 4.0, 0.15)


func test_a_zone_slows_by_40_percent_and_does_not_stack() -> void:
	var e := _caltrop_rig()
	_rig.state.pad(3).cd_s = 99.0
	var z1 := SiegeZoneState.new()
	z1.road = VALLEY
	z1.prog_m = e.prog_m
	z1.ttl_s = 4.0
	z1.slow = 0.6
	var z2 := SiegeZoneState.new()
	z2.road = VALLEY
	z2.prog_m = e.prog_m + 1.0
	z2.ttl_s = 4.0
	z2.slow = 0.6
	_rig.state.zones.append(z1)
	var p0 := e.prog_m
	_rig.step()
	assert_almost_eq(e.prog_m - p0, 2.2 * 0.6 * 0.05, 1e-4)
	_rig.state.zones.append(z2)
	var p1 := e.prog_m
	_rig.step()
	assert_almost_eq(e.prog_m - p1, 2.2 * 0.6 * 0.05, 1e-4, "two zones: still 0.6")
	assert_almost_eq(e.slow, 0.6, 1e-6)
	_rig.state.zones.clear()
	var p2 := e.prog_m
	_rig.step()
	assert_almost_eq(e.prog_m - p2, 2.2 * 0.05, 1e-4, "out of the zones: full speed")


func test_a_zone_ends_four_seconds_after_it_lands() -> void:
	_caltrop_rig()
	_rig.state.pad(3).cd_s = 99.0
	var z := SiegeZoneState.new()
	z.road = VALLEY
	z.delay_s = 1.0
	z.ttl_s = 4.0
	_rig.state.zones.append(z)
	_rig.run(4.9)
	assert_eq(_rig.state.zones.size(), 1)
	_rig.run(0.2)
	assert_eq(_rig.state.zones.size(), 0)


func test_caltrop_upgrade_three_makes_enemies_take_25_percent_more() -> void:
	_wave()
	_powered(1, 3, 250.0)
	_powered(2, 4, 250.0)
	var tw := _rig.state.pad(3)
	tw.type = SiegeIds.TOWER_CALTROP
	tw.level = 3
	tw.cd_s = 0.0
	_rig.state.pad(4).cd_s = 99.0
	var e := _rig.spawn(SiegeIds.ENEMY_RAIDERS, VALLEY, _prog_at(VALLEY, 3, 13.0), 0.0, 1000.0)
	_rig.step()
	assert_almost_eq(_rig.state.zones[0].amp, 1.25, 1e-6)
	_rig.run(1.2)
	assert_eq(e.amp, 1.25, "inside the landed zone")
	e.hp = 1000.0
	_rig.state.pad(4).cd_s = 0.0
	_rig.step()
	assert_almost_eq(e.hp, 1000.0 - 10.0 * 1.25, 1e-3, "the Scorpion's 10 becomes 12.5")


func test_a_kill_pays_the_bounty_split_by_p_eff_share() -> void:
	_wave()
	_powered(1, 3, 100.0)
	_powered(2, 3, 300.0)
	var a := _rig.rider(1)
	var b := _rig.rider(2)
	var d1 := a.denarii
	var d2 := b.denarii
	var team := _rig.state.team_earned
	_rig.spawn(SiegeIds.ENEMY_SHIELD_WALL, VALLEY, _rig.road_end(VALLEY) - 10.0, 0.0, 10.0)
	_rig.state.pad(3).cd_s = 0.0
	_rig.step()
	var kills := _rig.of_type(SiegeIds.EV_KILL)
	assert_eq(kills.size(), 1)
	assert_eq([kills[0]["et"], kills[0]["pad"], kills[0]["x2"]], [2, 3, 0])
	assert_almost_eq(a.denarii - d1, 6.0 * 0.25, 1e-6, "6 x 100/400")
	assert_almost_eq(b.denarii - d2, 6.0 * 0.75, 1e-6, "6 x 300/400")
	assert_almost_eq(a.bounty_denarii + b.bounty_denarii, 6.0, 1e-6)
	assert_almost_eq(_rig.state.team_earned - team, 6.0, 1e-6, "bounties count as earned")
	assert_eq(b.kills, 1, "the kill goes to the biggest share")
	assert_eq(a.kills, 0)
	assert_eq(_rig.state.pad(3).kills, 1)
	assert_eq(_rig.state.enemies.size(), 0, "the dead are removed")


func test_bounty_scale_applies() -> void:
	var patch := func(files: Dictionary) -> void: files["balance"]["bounty_scale"] = 2.0
	_wave(1, patch)
	_powered(1, 3, 250.0)
	var d := _rig.rider(1).denarii
	_rig.spawn(SiegeIds.ENEMY_HORSEMEN, VALLEY, _rig.road_end(VALLEY) - 10.0, 0.0, 5.0)
	_rig.state.pad(3).cd_s = 0.0
	_rig.step()
	assert_almost_eq(_rig.rider(1).denarii - d, 2.0 * 2.0, 1e-6)


func test_a_riderless_tower_earns_nothing() -> void:
	_wave()
	_rig.state.perks = [SiegeIds.PERK_AQUEDUCT]
	var before := _rig.rider(1).denarii + _rig.rider(2).denarii
	_rig.spawn(SiegeIds.ENEMY_RAIDERS, VALLEY, _rig.road_end(VALLEY) - 10.0, 0.0, 5.0)
	_rig.state.pad(3).cd_s = 0.0
	_rig.run(0.5)
	assert_eq(_rig.of_type(SiegeIds.EV_KILL).size(), 1, "the Aqueduct drive kills it")
	assert_almost_eq(_rig.rider(1).denarii + _rig.rider(2).denarii, before, 0.5, "no bounty")
	assert_eq(_rig.rider(1).bounty_denarii + _rig.rider(2).bounty_denarii, 0.0)


func test_rush_kills_pay_double_to_riders_in_overdrive_only() -> void:
	_wave()
	_powered(1, 3, 200.0, 250.0)
	_powered(2, 3, 200.0, 100.0)
	_rig.rider(1).od_state = SiegeIds.OD_ACTIVE
	_rig.rider(1).od_s = 20.0
	var d1 := _rig.rider(1).denarii
	var d2 := _rig.rider(2).denarii
	var e := _rig.spawn(SiegeIds.ENEMY_HORSEMEN, VALLEY, _rig.road_end(VALLEY) - 10.0, 0.0, 5.0)
	e.rush = true
	_rig.state.pad(3).cd_s = 0.0
	_rig.step()
	assert_almost_eq(_rig.rider(1).denarii - d1, 2.0 * 0.5 * 2.0, 1e-6, "double for Overdrive")
	assert_almost_eq(_rig.rider(2).denarii - d2, 2.0 * 0.5, 1e-6)
	assert_eq(_rig.of_type(SiegeIds.EV_KILL)[0]["x2"], 1)
	var plain := _rig.spawn(SiegeIds.ENEMY_HORSEMEN, VALLEY, _rig.road_end(VALLEY) - 10.0, 0.0, 5.0)
	var d1b := _rig.rider(1).denarii
	_rig.state.pad(3).cd_s = 0.0
	_rig.step()
	assert_eq(plain.hp, 0.0)
	assert_almost_eq(_rig.rider(1).denarii - d1b, 2.0 * 0.5, 1e-6, "no rush: no double")


func test_killing_a_ram_scatters_six_raiders_and_counts_it_stopped() -> void:
	_wave()
	_powered(1, 3, 250.0)
	var ram := _rig.spawn(SiegeIds.ENEMY_RAM, VALLEY, _rig.road_end(VALLEY) - 20.0, 0.0, 10.0)
	_rig.state.pad(3).cd_s = 0.0
	_rig.step()
	assert_eq(ram.hp, 0.0)
	assert_eq(_rig.state.rams_stopped, 1)
	var crew := _rig.state.enemies.filter(func(x: SiegeEnemyState) -> bool: return x.crew)
	assert_eq(crew.size(), 6)
	for c: SiegeEnemyState in crew:
		assert_eq(c.type, SiegeIds.ENEMY_RAIDERS)
		assert_eq(c.road, VALLEY)
		assert_lt(c.prog_m, ram.prog_m, "scattered just behind the ram")
	assert_eq(_rig.of_type(SiegeIds.EV_KILL)[0]["et"], SiegeIds.ENEMY_RAM)


func test_a_ram_killed_at_the_gate_is_not_stopped() -> void:
	_wave()
	_powered(1, 3, 250.0)
	var ram := _rig.spawn(SiegeIds.ENEMY_RAM, VALLEY, _rig.road_end(VALLEY), 0.0, 10.0)
	ram.st = SiegeIds.EN_BATTER
	_rig.state.pad(3).cd_s = 0.0
	_rig.step()
	assert_eq(ram.hp, 0.0)
	assert_eq(_rig.state.rams_stopped, 0)


func test_an_armed_tower_with_nothing_in_range_fires_the_moment_one_arrives() -> void:
	_wave()
	_powered(1, 3, 250.0)
	_rig.state.pad(3).cd_s = 0.0
	_rig.run(3.0)
	assert_eq(_rig.state.pad(3).cd_s, 0.0, "waiting, not winding up")
	assert_eq(_rig.state.pad(3).damage, 0.0)
	var e := _rig.spawn(SiegeIds.ENEMY_SHIELD_WALL, VALLEY, _rig.road_end(VALLEY) - 10.0)
	_rig.run(0.2)
	assert_lt(e.hp, 160.0)
