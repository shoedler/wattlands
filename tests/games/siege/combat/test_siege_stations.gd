extends GutTest
## Station output and the weapons (brief 2.4 "Output", "Stations", 4 "Stations"): linear output
## (0.5 at 125 W, 2.0 for two riders at 250 W), the 4.0 cap, upgrade 1, Overdrive's od, the
## perks; winding and slew times; aligned firing; the arrow racks; target choice.

var _s: SiegeState


func before_each() -> void:
	_s = SiegeKit.state("short", 4)


func _out(id: int, dt: float = 0.05) -> float:
	return SiegeStations.output(_s, SiegeKit.table(_s), _s.station(id), dt, SiegeIds.is_weapon(id))


## Aims station `id` straight at enemy `e` (yaw only) so it may fire once wound.
func _face(id: int, e: SiegeEnemyState) -> void:
	_s.station(id).yaw_deg = SiegePath.yaw_to(_s.path.station_pos[id], e.pos)
	_s.station(id).target_id = e.id
	_s.station(id).retarget_s = 10.0


func _shots(events: Array[Dictionary]) -> Array[Dictionary]:
	return SiegeKit.of_type(events, SiegeIds.EV_SHOT)


func test_output_is_linear_in_p_eff() -> void:
	SiegeKit.put(_s, 1, SiegeIds.STATION_ONAGER, 125.0)
	assert_almost_eq(_out(SiegeIds.STATION_ONAGER), 0.5, 1e-6, "0.5 at 125 W")
	SiegeKit.put(_s, 1, SiegeIds.STATION_ONAGER, 250.0)
	SiegeKit.put(_s, 2, SiegeIds.STATION_ONAGER, 250.0)
	assert_almost_eq(_out(SiegeIds.STATION_ONAGER), 2.0, 1e-6, "2.0 for two riders at 250 W")


func test_output_caps_at_4() -> void:
	SiegeKit.put(_s, 1, SiegeIds.STATION_ARROWS, 600.0)
	SiegeKit.put(_s, 2, SiegeIds.STATION_ARROWS, 600.0)
	assert_eq(_out(SiegeIds.STATION_ARROWS), 4.0)


func test_upgrade_1_adds_40_percent() -> void:
	SiegeKit.put(_s, 1, SiegeIds.STATION_BALLISTA, 250.0)
	_s.station(SiegeIds.STATION_BALLISTA).level = 1
	assert_almost_eq(_out(SiegeIds.STATION_BALLISTA), 1.4, 1e-6)


func test_the_mine_takes_no_upgrade_factor() -> void:
	SiegeKit.put(_s, 1, SiegeIds.STATION_MINE, 250.0)
	_s.station(SiegeIds.STATION_MINE).level = 3
	assert_almost_eq(_out(SiegeIds.STATION_MINE), 1.0, 1e-6)


func test_overdrive_doubles_a_rider_at_or_above_cp() -> void:
	var r := SiegeKit.put(_s, 1, SiegeIds.STATION_ONAGER, 250.0)
	r.od_state = SiegeIds.OD_ACTIVE
	r.raw_w = r.ftp
	assert_almost_eq(_out(SiegeIds.STATION_ONAGER), 2.0, 1e-6)
	r.raw_w = r.ftp - 1.0
	assert_almost_eq(_out(SiegeIds.STATION_ONAGER), 1.0, 1e-6, "below CP: od 1")


func test_riders_reconnecting_afk_or_elsewhere_deliver_nothing() -> void:
	var r := SiegeKit.put(_s, 1, SiegeIds.STATION_ONAGER, 250.0)
	r.reconnect_s = 1.0
	assert_eq(_out(SiegeIds.STATION_ONAGER), 0.0)
	r.reconnect_s = 0.0
	r.afk = true
	assert_eq(_out(SiegeIds.STATION_ONAGER), 0.0)
	r.afk = false
	r.target = SiegeIds.STATION_ARROWS
	assert_eq(_out(SiegeIds.STATION_ONAGER), 0.0)


func test_the_reserve_flywheel_holds_the_last_m_for_10_s() -> void:
	_s.perks.append(SiegeIds.PERK_RESERVE)
	var r := SiegeKit.put(_s, 1, SiegeIds.STATION_ONAGER, 375.0)
	assert_almost_eq(_out(SiegeIds.STATION_ONAGER), 1.5, 1e-6)
	r.target = SiegeIds.STATION_MINE
	assert_almost_eq(_out(SiegeIds.STATION_ONAGER, 9.95), 1.5, 1e-6, "held")
	assert_almost_eq(_out(SiegeIds.STATION_ONAGER, 0.05), 1.5, 1e-6, "10 s in")
	assert_eq(_out(SiegeIds.STATION_ONAGER, 0.05), 0.0, "then gone")


func test_without_the_flywheel_an_unpowered_station_stops_at_once() -> void:
	var r := SiegeKit.put(_s, 1, SiegeIds.STATION_ONAGER, 375.0)
	_out(SiegeIds.STATION_ONAGER)
	r.target = SiegeIds.STATION_MINE
	assert_eq(_out(SiegeIds.STATION_ONAGER), 0.0)


func test_the_aqueduct_gives_idle_weapons_a_quarter() -> void:
	_s.perks.append(SiegeIds.PERK_AQUEDUCT)
	for id in SiegeIds.WEAPONS:
		assert_eq(_out(id), 0.25, "weapon %d" % id)
	assert_eq(
		SiegeStations.output(_s, SiegeKit.table(_s), _s.station(SiegeIds.STATION_TAR), 0.05, false),
		0.0,
		"not the tar works"
	)
	assert_eq(_out(SiegeIds.STATION_MINE), 0.0, "not the mine")


func test_the_ballista_winds_in_5_s_at_m_1() -> void:
	SiegeKit.put(_s, 1, SiegeIds.STATION_BALLISTA, 250.0)
	var st := _s.station(SiegeIds.STATION_BALLISTA)
	st.wind = 0.0
	SiegeKit.run_stations(_s, 2.5)
	assert_almost_eq(st.wind, 0.5, 0.011)
	SiegeKit.run_stations(_s, 2.5)
	assert_almost_eq(st.wind, 1.0, 1e-6)


func test_the_onager_winds_in_7_s_at_m_1_and_twice_as_fast_at_m_2() -> void:
	SiegeKit.put(_s, 1, SiegeIds.STATION_ONAGER, 250.0)
	var st := _s.station(SiegeIds.STATION_ONAGER)
	SiegeKit.run_stations(_s, 3.5)
	assert_almost_eq(st.wind, 0.5, 0.01)
	st.wind = 0.0
	SiegeKit.put(_s, 2, SiegeIds.STATION_ONAGER, 250.0)
	SiegeKit.run_stations(_s, 1.75)
	assert_almost_eq(st.wind, 0.5, 0.01, "m 2")


func test_an_unpowered_weapon_keeps_its_winding() -> void:
	var r := SiegeKit.put(_s, 1, SiegeIds.STATION_ONAGER, 250.0)
	SiegeKit.run_stations(_s, 2.0)
	var w := _s.station(SiegeIds.STATION_ONAGER).wind
	r.target = SiegeIds.STATION_MINE
	SiegeKit.run_stations(_s, 5.0)
	assert_almost_eq(_s.station(SiegeIds.STATION_ONAGER).wind, w, 1e-6, "kept, not wound further")
	assert_eq(_s.station(SiegeIds.STATION_ONAGER).m, 0.0)


func test_arm_follows_the_winding() -> void:
	SiegeKit.put(_s, 1, SiegeIds.STATION_BALLISTA, 250.0)
	SiegeKit.run_stations(_s, 1.0)
	var st := _s.station(SiegeIds.STATION_BALLISTA)
	assert_eq(st.arm, st.wind)


func test_the_arrow_organ_reloads_a_rack_in_1_5_s() -> void:
	SiegeKit.put(_s, 1, SiegeIds.STATION_ARROWS, 250.0)
	assert_almost_eq(SiegeStations.wind_time(_s, _s.station(SiegeIds.STATION_ARROWS)), 1.5, 1e-6)
	assert_eq(SiegeStations.racks(_s, _s.station(SiegeIds.STATION_ARROWS)), 3)


func test_a_fourth_rack_makes_a_volley_every_1_125_s() -> void:
	_s.station(SiegeIds.STATION_ARROWS).level = 3
	assert_eq(SiegeStations.racks(_s, _s.station(SiegeIds.STATION_ARROWS)), 4)
	assert_almost_eq(SiegeStations.wind_time(_s, _s.station(SiegeIds.STATION_ARROWS)), 1.125, 1e-6)


func test_the_onager_slews_4_degrees_a_second() -> void:
	var st := _s.station(SiegeIds.STATION_ONAGER)
	var e := SiegeKit.enemy(
		_s, SiegeIds.ENEMY_RAM, SiegeKit.prog_in_band(_s, SiegeIds.STATION_ONAGER)
	)
	e.speed_mps = 0.0
	SiegeKit.put(_s, 1, SiegeIds.STATION_ONAGER, 250.0)
	var want := SiegePath.yaw_to(_s.path.station_pos[SiegeIds.STATION_ONAGER], e.pos)
	st.yaw_deg = want - 40.0
	SiegeKit.run_stations(_s, 5.0)
	assert_almost_eq(st.yaw_deg, want - 20.0, 0.3, "20 degrees in 5 s")
	SiegeKit.run_stations(_s, 5.0)
	assert_almost_eq(wrapf(st.yaw_deg - want, -180.0, 180.0), 0.0, 0.5, "40 in 10 s")


func test_the_ballista_slews_25_degrees_a_second() -> void:
	var st := _s.station(SiegeIds.STATION_BALLISTA)
	var e := SiegeKit.enemy(
		_s, SiegeIds.ENEMY_RAM, SiegeKit.prog_in_band(_s, SiegeIds.STATION_BALLISTA)
	)
	e.speed_mps = 0.0
	SiegeKit.put(_s, 1, SiegeIds.STATION_BALLISTA, 250.0)
	var want := SiegePath.yaw_to(_s.path.station_pos[SiegeIds.STATION_BALLISTA], e.pos)
	st.yaw_deg = want + 50.0
	SiegeKit.run_stations(_s, 1.0)
	assert_almost_eq(st.yaw_deg, want + 25.0, 0.3)


func test_an_unpowered_weapon_does_not_turn() -> void:
	var st := _s.station(SiegeIds.STATION_ONAGER)
	SiegeKit.enemy(_s, SiegeIds.ENEMY_RAM, SiegeKit.prog_in_band(_s, SiegeIds.STATION_ONAGER))
	var y := st.yaw_deg
	SiegeKit.run_stations(_s, 2.0)
	assert_eq(st.yaw_deg, y)


func test_a_wound_aligned_weapon_fires_one_shot() -> void:
	var id := SiegeIds.STATION_BALLISTA
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_RAM, SiegeKit.prog_in_band(_s, id))
	e.speed_mps = 0.0
	SiegeKit.put(_s, 1, id, 250.0)
	_s.station(id).wind = 1.0
	_face(id, e)
	var shots := _shots(SiegeKit.run_stations(_s, 0.05))
	assert_eq(shots.size(), 1)
	assert_eq(int(shots[0]["src"]), id)
	assert_eq(int(shots[0]["kind"]), SiegeIds.SHOT_BOLT)
	assert_eq(int(shots[0]["n"]), 1)
	assert_eq(_s.station(id).wind, 0.0, "the winding starts over")
	assert_eq(_s.station(id).shots, 1)


func test_a_misaligned_weapon_waits_until_it_has_turned() -> void:
	var id := SiegeIds.STATION_ONAGER
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_RAM, SiegeKit.prog_in_band(_s, id))
	e.speed_mps = 0.0
	SiegeKit.put(_s, 1, id, 250.0)
	_s.station(id).wind = 1.0
	_face(id, e)
	_s.station(id).yaw_deg -= 6.0
	assert_eq(_shots(SiegeKit.run_stations(_s, 0.5)).size(), 0, "4 deg/s: still 4 degrees off")
	assert_eq(_shots(SiegeKit.run_stations(_s, 1.0)).size(), 1, "within 2 degrees: fires")


func test_an_unwound_weapon_does_not_fire() -> void:
	var id := SiegeIds.STATION_BALLISTA
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_RAM, SiegeKit.prog_in_band(_s, id))
	e.speed_mps = 0.0
	SiegeKit.put(_s, 1, id, 250.0)
	_s.station(id).wind = 0.0
	_face(id, e)
	assert_eq(_shots(SiegeKit.run_stations(_s, 4.9)).size(), 0)
	assert_eq(_shots(SiegeKit.run_stations(_s, 0.2)).size(), 1, "wound after 5 s")


func test_the_arrow_organ_fires_a_rack_of_12_and_cycles_its_racks() -> void:
	var id := SiegeIds.STATION_ARROWS
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, SiegeKit.prog_in_band(_s, id), 0.0, 1000.0)
	e.speed_mps = 0.0
	SiegeKit.put(_s, 1, id, 250.0)
	_s.station(id).wind = 1.0
	_face(id, e)
	var shots := _shots(SiegeKit.run_stations(_s, 3.2))
	assert_eq(shots.size(), 3, "1 at once, then every 1.5 s")
	assert_eq(int(shots[0]["n"]), 12)
	assert_eq(int(shots[0]["kind"]), SiegeIds.SHOT_ARROW)
	assert_eq(_s.station(id).rack, 0, "three racks cycled 0 -> 1 -> 2 -> 0")
	assert_eq(_s.station(id).shots, 36)


func test_nothing_fires_outside_a_wave_or_in_a_breach() -> void:
	var id := SiegeIds.STATION_BALLISTA
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_RAM, SiegeKit.prog_in_band(_s, id))
	SiegeKit.put(_s, 1, id, 250.0)
	_s.station(id).wind = 1.0
	_face(id, e)
	_s.breach_s = 5.0
	assert_eq(_shots(SiegeKit.run_stations(_s, 1.0)).size(), 0, "a Breach stops every station")
	assert_eq(_s.station(id).m, 0.0)
	_s.breach_s = 0.0
	_s.role = SiegeIds.ROLE_BREAK
	assert_eq(_shots(SiegeKit.run_stations(_s, 1.0)).size(), 0, "breaks are still")


func test_a_breach_stops_perks_too() -> void:
	_s.perks.append(SiegeIds.PERK_AQUEDUCT)
	_s.breach_s = 5.0
	SiegeKit.run_stations(_s, 0.05)
	for id in SiegeIds.WEAPONS:
		assert_eq(_s.station(id).m, 0.0)


func test_the_ballista_prefers_engines() -> void:
	var id := SiegeIds.STATION_BALLISTA
	var p := SiegeKit.prog_in_band(_s, id)
	var spear := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, p + 2.0)
	var ram := SiegeKit.enemy(_s, SiegeIds.ENEMY_RAM, p)
	var def := _s.content.station_def(id)
	assert_eq(SiegeStations.pick(_s, SiegeKit.table(_s), id, def), ram)
	ram.hp = 0.0
	assert_eq(SiegeStations.pick(_s, SiegeKit.table(_s), id, def), spear)


func test_the_arrow_organ_prefers_spearmen_to_shields() -> void:
	var id := SiegeIds.STATION_ARROWS
	var p := SiegeKit.prog_in_band(_s, id)
	SiegeKit.enemy(_s, SiegeIds.ENEMY_SHIELD, p + 1.0)
	var spear := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, p)
	assert_eq(SiegeStations.pick(_s, SiegeKit.table(_s), id, _s.content.station_def(id)), spear)


func test_ties_go_to_the_enemy_nearest_the_gate() -> void:
	var id := SiegeIds.STATION_ARROWS
	var progs := SiegeKit.band_progs(_s, id)
	SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, progs[2])
	var front := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, progs[progs.size() - 3])
	assert_eq(SiegeStations.pick(_s, SiegeKit.table(_s), id, _s.content.station_def(id)), front)


func test_the_onager_picks_the_densest_block() -> void:
	var id := SiegeIds.STATION_ONAGER
	var progs := SiegeKit.band_progs(_s, id)
	var lone := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, progs[progs.size() - 3])
	var mid := progs[progs.size() / 3]
	var block: Array[SiegeEnemyState] = []
	for i in 6:
		block.append(
			SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, mid + float(i % 3) * 1.2, float(i / 3) * 1.2)
		)
	var pick := SiegeStations.pick(_s, SiegeKit.table(_s), id, _s.content.station_def(id))
	assert_ne(pick, lone)
	assert_true(block.has(pick))


func test_nothing_in_the_band_means_no_target() -> void:
	var out := SiegeKit.prog_out_of_reach(_s)
	if out >= 0.0:
		SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, out)
	for id in SiegeIds.WEAPONS:
		assert_null(SiegeStations.pick(_s, SiegeKit.table(_s), id, _s.content.station_def(id)))


func test_the_onager_ignores_what_is_inside_30_m() -> void:
	var id := SiegeIds.STATION_ONAGER
	var p := SiegeKit.prog_at_dist(_s, id, 20.0)
	if p < 0.0:
		pass_test("no road within 20 m of the onager")
		return
	SiegeKit.enemy(_s, SiegeIds.ENEMY_RAM, p)
	assert_null(SiegeStations.pick(_s, SiegeKit.table(_s), id, _s.content.station_def(id)))


func test_a_weapon_keeps_its_target_unless_a_better_type_appears() -> void:
	var id := SiegeIds.STATION_BALLISTA
	var progs := SiegeKit.band_progs(_s, id)
	var first := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, progs[5])
	first.speed_mps = 0.0
	SiegeKit.put(_s, 1, id, 250.0)
	SiegeKit.run_stations(_s, 0.05)
	assert_eq(_s.station(id).target_id, first.id)
	var nearer := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, progs[progs.size() - 5])
	nearer.speed_mps = 0.0
	SiegeKit.run_stations(_s, 1.1)
	assert_eq(_s.station(id).target_id, first.id, "same type: no switch")
	var ram := SiegeKit.enemy(_s, SiegeIds.ENEMY_RAM, progs[10])
	ram.speed_mps = 0.0
	SiegeKit.run_stations(_s, 1.1)
	assert_eq(_s.station(id).target_id, ram.id, "an engine outranks spearmen")


func test_a_dead_target_is_replaced_at_once() -> void:
	var id := SiegeIds.STATION_ARROWS
	var progs := SiegeKit.band_progs(_s, id)
	var a := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, progs[3])
	var b := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, progs[1])
	a.speed_mps = 0.0
	b.speed_mps = 0.0
	SiegeKit.put(_s, 1, id, 250.0)
	SiegeKit.run_stations(_s, 0.05)
	assert_eq(_s.station(id).target_id, a.id)
	a.hp = 0.0
	SiegeKit.run_stations(_s, 0.05)
	assert_eq(_s.station(id).target_id, b.id)


func test_aim_spec_lifts_the_top_speed_after_upgrade_2() -> void:
	assert_eq(float(SiegeStations.aim_spec(_s, SiegeIds.STATION_ONAGER)["v_max"]), 34.0)
	_s.station(SiegeIds.STATION_ONAGER).level = 2
	assert_eq(float(SiegeStations.aim_spec(_s, SiegeIds.STATION_ONAGER)["v_max"]), 39.0)
	assert_true(bool(SiegeStations.aim_spec(_s, SiegeIds.STATION_ARROWS)["fallback"]))


func test_the_mine_shows_its_m_and_level() -> void:
	SiegeKit.put(_s, 1, SiegeIds.STATION_MINE, 250.0)
	_s.mine_level = 2
	SiegeKit.run_stations(_s, 0.05)
	assert_almost_eq(_s.station(SiegeIds.STATION_MINE).m, 1.0, 1e-6)
	assert_eq(_s.station(SiegeIds.STATION_MINE).level, 2)
