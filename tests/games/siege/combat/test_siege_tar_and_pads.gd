extends GutTest
## The tar works and the pads (brief 2.4 "Tar works", "Pads"; 4): the tar flow, the curtain
## absorbing gate damage, the coat slowing the bridge, cauldron refill, boarders; the Scorpion.

var _s: SiegeState


func before_each() -> void:
	_s = SiegeKit.state("short", 2)


func _tar_step(seconds: float) -> void:
	for _i in roundi(seconds / Wl.SIM_DT):
		SiegeTarWorks.step(_s, SiegeKit.table(_s), Wl.SIM_DT)


func test_the_pump_moves_6_litres_a_second_at_m_1() -> void:
	SiegeKit.put(_s, 1, SiegeIds.STATION_TAR, 250.0)
	_tar_step(10.0)
	# 60 L pumped, ~10 L reheated, 10 HP drained.
	assert_almost_eq(_s.tar.cauldron_l, 300.0 - 60.0 + 10.0, 0.5)
	assert_almost_eq(_s.tar.curtain_hp, 60.0 - 10.0, 0.5)


func test_the_pump_scales_with_m() -> void:
	SiegeKit.put(_s, 1, SiegeIds.STATION_TAR, 500.0)
	_tar_step(5.0)
	assert_almost_eq(_s.tar.curtain_hp, 2.0 * 6.0 * 5.0 - 5.0, 0.5)
	assert_almost_eq(_s.station(SiegeIds.STATION_TAR).m, 2.0, 1e-6)


func test_the_curtain_drains_1_hp_a_second() -> void:
	_s.tar.curtain_hp = 50.0
	_tar_step(10.0)
	assert_almost_eq(_s.tar.curtain_hp, 40.0, 0.01)


func test_the_curtain_holds_at_most_200() -> void:
	SiegeKit.put(_s, 1, SiegeIds.STATION_TAR, 1000.0)
	_s.tar.curtain_hp = 195.0
	_tar_step(3.0)
	assert_lte(_s.tar.curtain_hp, 200.0)
	assert_gt(_s.tar.cauldron_l, 200.0, "no tar is wasted past the top")


func test_upgrade_2_raises_the_curtain_to_250() -> void:
	_s.station(SiegeIds.STATION_TAR).level = 2
	SiegeKit.put(_s, 1, SiegeIds.STATION_TAR, 1000.0)
	_s.tar.curtain_hp = 240.0
	_tar_step(3.0)
	assert_gt(_s.tar.curtain_hp, 240.0)
	assert_lte(_s.tar.curtain_hp, 250.0)
	assert_eq(_s.tar.curtain_max, 250.0)


func test_no_tar_no_curtain() -> void:
	SiegeKit.put(_s, 1, SiegeIds.STATION_TAR, 250.0)
	_s.tar.cauldron_l = 0.0
	_tar_step(1.0)
	assert_almost_eq(_s.tar.curtain_hp, 1.0 - 1.0, 0.06, "only the reheated litre flows")


func test_the_cauldrons_reheat_1_litre_a_second_with_or_without_a_rider() -> void:
	_s.tar.cauldron_l = 100.0
	_tar_step(20.0)
	assert_almost_eq(_s.tar.cauldron_l, 120.0, 0.01)
	_s.role = SiegeIds.ROLE_BREAK
	_tar_step(10.0)
	assert_almost_eq(_s.tar.cauldron_l, 130.0, 0.01, "in breaks too")


func test_a_rider_empties_full_cauldrons_in_about_60_s() -> void:
	SiegeKit.put(_s, 1, SiegeIds.STATION_TAR, 250.0)
	var t := 0.0
	while _s.tar.cauldron_l > 1.0 and t < 120.0:
		_tar_step(1.0)
		_s.tar.curtain_hp = 0.0
		t += 1.0
	assert_between(t, 55.0, 65.0, "300 L at 6 L/s less the 1 L/s reheat")


func test_the_spare_cauldron_holds_400() -> void:
	_s.perks.append(SiegeIds.PERK_CAULDRON)
	_tar_step(0.05)
	assert_eq(_s.tar.cauldron_max_l, 400.0)
	_tar_step(5.0)
	assert_almost_eq(_s.tar.cauldron_l, 305.0, 0.1, "the new cauldron fills at 1 L/s")


func test_the_coat_is_the_curtain_over_100() -> void:
	_s.tar.curtain_hp = 51.0
	_tar_step(1.0)
	assert_almost_eq(_s.tar.coat, 0.5, 0.001)
	_s.tar.curtain_hp = 181.0
	_tar_step(1.0)
	assert_eq(_s.tar.coat, 1.0)


func test_the_pump_stops_outside_waves_and_in_a_breach() -> void:
	SiegeKit.put(_s, 1, SiegeIds.STATION_TAR, 250.0)
	_s.role = SiegeIds.ROLE_BREAK
	_tar_step(2.0)
	assert_eq(_s.tar.curtain_hp, 0.0)
	_s.role = SiegeIds.ROLE_WAVE
	_s.breach_s = 9.0
	_tar_step(2.0)
	assert_eq(_s.tar.curtain_hp, 0.0)


func test_boarders_stop_the_pump() -> void:
	SiegeKit.put(_s, 1, SiegeIds.STATION_TAR, 250.0)
	var t := SiegeKit.enemy(_s, SiegeIds.ENEMY_TOWER, _s.path.moat_edge_m)
	t.st = SiegeIds.EN_DOCKED
	_tar_step(2.0)
	assert_true(_s.tar.boarded)
	assert_eq(_s.tar.curtain_hp, 0.0)
	assert_eq(_s.station(SiegeIds.STATION_TAR).m, 0.0)
	t.hp = 0.0
	_tar_step(1.0)
	assert_false(_s.tar.boarded, "the tower destroyed: the wall is clear")
	assert_gt(_s.tar.curtain_hp, 0.0)


func test_the_tar_station_shows_the_cauldron_fill() -> void:
	_s.tar.cauldron_l = 150.0
	_tar_step(0.05)
	assert_almost_eq(_s.station(SiegeIds.STATION_TAR).wind, 150.05 / 300.0, 1e-4)


func test_the_curtain_absorbs_gate_damage_first() -> void:
	var ev: Array[Dictionary] = []
	_s.tar.curtain_hp = 5.0
	var applied := SiegeCombat.damage_gate(_s, 8.0, ev)
	assert_eq(applied, 8.0)
	assert_eq(_s.tar.curtain_hp, 0.0)
	assert_eq(_s.gate_hp, 130.0 - 3.0)


func test_a_full_curtain_takes_all_of_it() -> void:
	var ev: Array[Dictionary] = []
	_s.tar.curtain_hp = 100.0
	SiegeCombat.damage_gate(_s, 30.0, ev)
	assert_eq(_s.gate_hp, 130.0)
	assert_eq(_s.tar.curtain_hp, 70.0)


func test_the_coat_slows_the_bridge_by_half() -> void:
	_s.tar.coat = 1.0
	assert_almost_eq(SiegeKit.table(_s).bridge_f, 0.5, 1e-6)
	_s.tar.coat = 0.4
	assert_almost_eq(SiegeKit.table(_s).bridge_f, 0.8, 1e-6)


func test_upgrade_3_coat_slows_65_percent() -> void:
	_s.station(SiegeIds.STATION_TAR).level = 3
	_s.tar.coat = 1.0
	assert_almost_eq(SiegeKit.table(_s).bridge_f, 0.35, 1e-6)


# --- pads ---------------------------------------------------------------------------------------


func _pad_shots(seconds: float) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	for _i in roundi(seconds / Wl.SIM_DT):
		SiegePads.step(_s, SiegeKit.table(_s), Wl.SIM_DT, ev)
	return SiegeKit.of_type(ev, SiegeIds.EV_SHOT)


func _near_pad(n: int) -> SiegeEnemyState:
	var at := _s.path.pads[n - 1]
	var best := -1.0
	var p := 0.0
	while p <= _s.path.length_m:
		var d := _s.path.ground_dist(at, p)
		if d > 15.0 and d < 55.0:
			best = p
		p += 0.5
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, best, 0.0, 999.0)
	e.speed_mps = 0.0
	return e


func test_the_scorpion_fires_every_2_4_s_at_the_enemy_nearest_the_gate() -> void:
	var e := _near_pad(1)
	var shots := _pad_shots(5.0)
	assert_eq(shots.size(), 3, "at once, at 2.4 and 4.8 s")
	assert_eq(int(shots[0]["src"]), 11)
	assert_eq(int(shots[0]["kind"]), SiegeIds.SHOT_SCORPION)
	assert_eq(int(shots[0]["n"]), 1)
	assert_eq(SiegePads.target(_s, 1), e)


func test_scorpion_upgrades_rate_range_and_a_second_bolt() -> void:
	_near_pad(1)
	_s.pad(1).level = 1
	assert_eq(_pad_shots(4.0).size(), 3, "+40% rate: every 1.71 s")
	_s.pad(1).level = 3
	_s.pad(1).cd_s = 0.0
	var shots := _pad_shots(0.05)
	assert_eq(int(shots[0]["n"]), 2, "upgrade 3: two bolts")
	assert_eq(_s.pad_band(1).y, 75.0, "upgrade 2: +25% range")


func test_an_empty_pad_does_nothing() -> void:
	_s.pad(1).type = SiegeIds.PAD_NONE
	_near_pad(1)
	assert_eq(_pad_shots(3.0).size(), 0)


func test_a_pad_with_nothing_in_range_waits_armed() -> void:
	assert_eq(_pad_shots(3.0).size(), 0)
	assert_eq(_s.pad(1).cd_s, 0.0)
	_near_pad(1)
	assert_eq(_pad_shots(0.05).size(), 1, "fires the tick something comes into range")


func test_boarders_stop_pads_1_and_2_only() -> void:
	_s.pad(3).type = SiegeIds.PAD_SCORPION
	_near_pad(1)
	_near_pad(3)
	_s.tar.boarded = true
	var shots := _pad_shots(1.0)
	assert_eq(shots.size(), 1)
	assert_eq(int(shots[0]["src"]), 13)


func test_pads_stop_in_a_breach_and_in_breaks() -> void:
	_near_pad(1)
	_s.breach_s = 5.0
	assert_eq(_pad_shots(1.0).size(), 0)
	_s.breach_s = 0.0
	_s.role = SiegeIds.ROLE_BREAK
	assert_eq(_pad_shots(1.0).size(), 0)


func test_the_pad_turns_to_its_target() -> void:
	var e := _near_pad(1)
	_pad_shots(0.05)
	var want := SiegePath.yaw_to(_s.path.pads[0], e.pos)
	assert_almost_eq(wrapf(_s.pad(1).yaw_deg - want, -180.0, 180.0), 0.0, 2.0)


func test_a_scorpion_bolt_flies_and_hits() -> void:
	var e := _near_pad(1)
	var kinds: Array[int] = []
	for _i in 60:
		for ev in SiegeCombat.step(_s, _inputs(), Wl.SIM_DT):
			if ev["type"] == SiegeIds.EV_SHOT:
				kinds.append(int(ev["kind"]))
	assert_lt(e.hp, 999.0, "a 50 m/s bolt reached it")
	assert_true(kinds.has(SiegeIds.SHOT_SCORPION))


func _inputs() -> SiegeInputs:
	var inp := SiegeInputs.new()
	inp.phase.kind = Wl.WORK
	inp.phase.role = SiegeIds.ROLE_WAVE
	inp.phase.duration_s = 10000.0
	inp.phase.remaining_s = 10000.0
	return inp
