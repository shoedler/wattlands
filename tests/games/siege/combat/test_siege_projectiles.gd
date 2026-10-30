extends GutTest
## Projectiles (brief 2.4 "Projectiles", "Stations"; 4): the ballista's pierce falloff and its
## iron head, the onager's splash falloff and the engine multiplier, arrows and the testudo, the
## Scorpion's single hit, damage at impact, bounties by share, kills, engines stopped.

var _s: SiegeState
var _events: Array[Dictionary] = []


func before_each() -> void:
	_s = SiegeKit.state("short", 2)
	_events = []


## An enemy of `type` standing at world point `p` (its pos set directly; nothing moves here).
func _at(type: int, p: Vector3, hp: float = 1000.0) -> SiegeEnemyState:
	var e := SiegeKit.enemy(_s, type, 100.0, 0.0, hp)
	e.pos = p
	return e


func _proj(kind: int, src: int, pos: Vector3, vel: Vector3, damage: float) -> SiegeProjectile:
	var p := SiegeProjectile.new()
	p.kind = kind
	p.src = src
	p.pos = pos
	p.vel = vel
	p.damage = damage
	p.floor_z = 0.0
	p.ticks = 1 if kind == SiegeIds.SHOT_STONE or kind == SiegeIds.SHOT_ARROW else 200
	p.pierce = kind == SiegeIds.SHOT_BOLT
	_s.projectiles.append(p)
	return p


func _step(n: int = 1) -> void:
	for _i in n:
		SiegeProjectiles.step(_s, SiegeKit.table(_s), _events)


func _lost(e: SiegeEnemyState) -> float:
	return 1000.0 - e.hp


# --- stones ------------------------------------------------------------------------------------


func test_a_stone_splashes_with_linear_falloff() -> void:
	var c := Vector3(50, 120, 0)
	var a := _at(SiegeIds.ENEMY_SPEAR, c)
	var b := _at(SiegeIds.ENEMY_SPEAR, c + Vector3(2.5, 0, 0))
	var edge := _at(SiegeIds.ENEMY_SPEAR, c + Vector3(0, 4.9, 0))
	var out := _at(SiegeIds.ENEMY_SPEAR, c + Vector3(5.2, 0, 0))
	_proj(SiegeIds.SHOT_STONE, SiegeIds.STATION_ONAGER, c, Vector3.ZERO, 160.0)
	_step()
	assert_almost_eq(_lost(a), 160.0, 1e-3, "160 at the centre")
	assert_almost_eq(_lost(b), 160.0 * (1.0 - 0.6 * 2.5 / 5.0), 1e-3)
	assert_almost_eq(_lost(edge), 160.0 * (1.0 - 0.6 * 4.9 / 5.0), 1e-3, "40% at the edge")
	assert_eq(_lost(out), 0.0, "outside 5 m")
	assert_true(_s.projectiles.is_empty())


func test_an_engine_within_2_m_takes_2_5_times() -> void:
	var c := Vector3(60, 130, 0)
	var ram := _at(SiegeIds.ENEMY_RAM, c + Vector3(1.0, 0, 0))
	var far := _at(SiegeIds.ENEMY_RAM, c + Vector3(0, 3.0, 0))
	_proj(SiegeIds.SHOT_STONE, SiegeIds.STATION_ONAGER, c, Vector3.ZERO, 160.0)
	_step()
	assert_almost_eq(_lost(ram), 160.0 * (1.0 - 0.6 / 5.0) * 2.5 - 6.0, 1e-3, "x2.5, then armour")
	assert_almost_eq(_lost(far), 160.0 * (1.0 - 0.6 * 3.0 / 5.0) - 6.0, 1e-3, "3 m: no bonus")


func test_a_docked_tower_takes_1_5_times_from_the_onager() -> void:
	var c := Vector3(44, 100, 0)
	var t := _at(SiegeIds.ENEMY_TOWER, c, 1800.0)
	t.st = SiegeIds.EN_DOCKED
	_proj(SiegeIds.SHOT_STONE, SiegeIds.STATION_ONAGER, c, Vector3.ZERO, 160.0)
	_step()
	assert_almost_eq(1800.0 - t.hp, 160.0 * 2.5 * 1.5 - 6.0, 1e-3)


func test_upgrade_3_grows_the_splash_to_6_5_m() -> void:
	_s.station(SiegeIds.STATION_ONAGER).level = 3
	var c := Vector3(50, 120, 0)
	var e := _at(SiegeIds.ENEMY_SPEAR, c + Vector3(6.0, 0, 0))
	_proj(SiegeIds.SHOT_STONE, SiegeIds.STATION_ONAGER, c, Vector3.ZERO, 160.0)
	_step()
	assert_almost_eq(_lost(e), 160.0 * (1.0 - 0.6 * 6.0 / 6.5), 1e-3)


func test_armour_never_drops_damage_below_1() -> void:
	var c := Vector3(50, 120, 0)
	var e := _at(SiegeIds.ENEMY_SHIELD, c)
	_proj(SiegeIds.SHOT_STONE, SiegeIds.STATION_ONAGER, c, Vector3.ZERO, 3.0)
	_step()
	assert_eq(_lost(e), 1.0, "max(1, 3 - 6)")


func test_a_stone_lands_only_after_its_flight() -> void:
	var c := Vector3(50, 120, 0)
	var e := _at(SiegeIds.ENEMY_SPEAR, c)
	var p := _proj(SiegeIds.SHOT_STONE, SiegeIds.STATION_ONAGER, c, Vector3.ZERO, 160.0)
	p.ticks = 70
	_step(69)
	assert_eq(_lost(e), 0.0, "in flight: no damage yet")
	_step()
	assert_eq(_lost(e), 160.0, "at impact")


func test_a_target_that_moved_away_is_missed() -> void:
	var c := Vector3(50, 120, 0)
	var e := _at(SiegeIds.ENEMY_CHARIOT, c)
	var p := _proj(SiegeIds.SHOT_STONE, SiegeIds.STATION_ONAGER, c, Vector3.ZERO, 160.0)
	p.ticks = 60
	_step(30)
	e.pos += Vector3(8, 0, 0)
	_step(30)
	assert_eq(_lost(e), 0.0)


# --- arrows ------------------------------------------------------------------------------------


func test_an_arrow_hits_the_nearest_enemy_within_0_6_m() -> void:
	var c := Vector3(70, 150, 0)
	var near := _at(SiegeIds.ENEMY_SPEAR, c + Vector3(0.3, 0, 0))
	var nearer := _at(SiegeIds.ENEMY_SPEAR, c + Vector3(0, 0.2, 0))
	_proj(SiegeIds.SHOT_ARROW, SiegeIds.STATION_ARROWS, c, Vector3.ZERO, 8.0)
	_step()
	assert_eq(_lost(nearer), 8.0)
	assert_eq(_lost(near), 0.0, "one body per arrow")


func test_an_arrow_farther_than_0_6_m_misses() -> void:
	var c := Vector3(70, 150, 0)
	var e := _at(SiegeIds.ENEMY_SPEAR, c + Vector3(0.65, 0, 0))
	_proj(SiegeIds.SHOT_ARROW, SiegeIds.STATION_ARROWS, c, Vector3.ZERO, 8.0)
	_step()
	assert_eq(_lost(e), 0.0)


func test_big_bodies_catch_arrows_within_their_radius() -> void:
	var c := Vector3(70, 150, 0)
	var ch := _at(SiegeIds.ENEMY_CHARIOT, c + Vector3(1.4, 0, 0))
	_proj(SiegeIds.SHOT_ARROW, SiegeIds.STATION_ARROWS, c, Vector3.ZERO, 8.0)
	_step()
	assert_eq(_lost(ch), 6.0, "a chariot's 1 m body: 8 - 2 armour")


func test_the_testudo_blocks_an_arrow_marked_for_it() -> void:
	var c := Vector3(70, 150, 0)
	var sh := _at(SiegeIds.ENEMY_SHIELD, c)
	var p := _proj(SiegeIds.SHOT_ARROW, SiegeIds.STATION_ARROWS, c, Vector3.ZERO, 8.0)
	p.testudo = true
	_step()
	assert_eq(_lost(sh), 0.0, "blocked")
	var p2 := _proj(SiegeIds.SHOT_ARROW, SiegeIds.STATION_ARROWS, c, Vector3.ZERO, 8.0)
	p2.testudo = false
	_step()
	assert_eq(_lost(sh), 2.0, "through the shields: 8 - 6")


func test_the_testudo_mark_means_nothing_to_spearmen() -> void:
	var c := Vector3(70, 150, 0)
	var sp := _at(SiegeIds.ENEMY_SPEAR, c)
	var p := _proj(SiegeIds.SHOT_ARROW, SiegeIds.STATION_ARROWS, c, Vector3.ZERO, 8.0)
	p.testudo = true
	_step()
	assert_eq(_lost(sp), 8.0)


func test_about_70_percent_of_a_volley_is_marked_for_the_testudo() -> void:
	var id := SiegeIds.STATION_ARROWS
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_SHIELD, SiegeKit.prog_in_band(_s, id), 0.0, 9999.0)
	e.speed_mps = 0.0
	var marked := 0
	var total := 0
	for i in 40:
		_s.projectiles.clear()
		var sol := SiegeAim.lead(
			_s.path,
			_s.path.station_pos[id],
			_s.path.station_muzzle_m[id],
			e,
			SiegeStations.aim_spec(_s, id),
			2.0
		)
		SiegeProjectiles.fire(_s, SiegeKit.table(_s), id, sol, 12, e.id, _events)
		for p in _s.projectiles:
			total += 1
			marked += int(p.testudo)
	assert_eq(total, 480)
	assert_between(float(marked) / total, 0.64, 0.76)


# --- bolts -------------------------------------------------------------------------------------


func test_a_bolt_pierces_with_75_percent_after_infantry() -> void:
	var a := _at(SiegeIds.ENEMY_SPEAR, Vector3(10, 0, 0))
	var b := _at(SiegeIds.ENEMY_SPEAR, Vector3(12, 0, 0))
	var c := _at(SiegeIds.ENEMY_SPEAR, Vector3(14, 0.4, 0))
	_proj(
		SiegeIds.SHOT_BOLT, SiegeIds.STATION_BALLISTA, Vector3(0, 0, 0.9), Vector3(70, 0, 0), 120.0
	)
	_step(5)
	assert_almost_eq(_lost(a), 120.0, 1e-3)
	assert_almost_eq(_lost(b), 90.0, 1e-3)
	assert_almost_eq(_lost(c), 67.5, 1e-3)


func test_a_bolt_keeps_30_percent_after_an_engine() -> void:
	var ram := _at(SiegeIds.ENEMY_RAM, Vector3(10, 0, 0))
	var b := _at(SiegeIds.ENEMY_SPEAR, Vector3(15, 0, 0))
	_proj(
		SiegeIds.SHOT_BOLT, SiegeIds.STATION_BALLISTA, Vector3(0, 0, 0.9), Vector3(70, 0, 0), 120.0
	)
	_step(5)
	assert_almost_eq(_lost(ram), 114.0, 1e-3, "120 - 6 armour")
	assert_almost_eq(_lost(b), 36.0, 1e-3, "30% of 120")


func test_a_bolt_stops_below_10() -> void:
	_at(SiegeIds.ENEMY_RAM, Vector3(10, 0, 0))
	var ram2 := _at(SiegeIds.ENEMY_RAM, Vector3(16, 0, 0))
	var ram3 := _at(SiegeIds.ENEMY_RAM, Vector3(22, 0, 0))
	var b := _at(SiegeIds.ENEMY_SPEAR, Vector3(27, 0, 0))
	_proj(
		SiegeIds.SHOT_BOLT, SiegeIds.STATION_BALLISTA, Vector3(0, 0, 0.9), Vector3(70, 0, 0), 120.0
	)
	_step(10)
	assert_almost_eq(_lost(ram2), 30.0, 1e-3, "36 left for the second engine")
	assert_almost_eq(_lost(ram3), 4.8, 1e-3, "10.8 for the third")
	assert_eq(_lost(b), 0.0, "10.8 x 0.3 is below 10: spent")
	assert_true(_s.projectiles.is_empty())


func test_a_bolt_misses_bodies_more_than_0_6_m_off_its_path() -> void:
	var off := _at(SiegeIds.ENEMY_SPEAR, Vector3(10, 0.7, 0))
	_proj(
		SiegeIds.SHOT_BOLT, SiegeIds.STATION_BALLISTA, Vector3(0, 0, 0.9), Vector3(70, 0, 0), 120.0
	)
	_step(5)
	assert_eq(_lost(off), 0.0)


func test_a_bolt_flies_over_heads() -> void:
	var e := _at(SiegeIds.ENEMY_SPEAR, Vector3(10, 0, 0))
	_proj(
		SiegeIds.SHOT_BOLT, SiegeIds.STATION_BALLISTA, Vector3(0, 0, 3.0), Vector3(70, 0, 0), 120.0
	)
	_step(4)
	assert_eq(_lost(e), 0.0, "3 m up passes over a 1.8 m body")


func test_a_bolt_stops_at_the_ground() -> void:
	_proj(
		SiegeIds.SHOT_BOLT,
		SiegeIds.STATION_BALLISTA,
		Vector3(0, 0, 0.5),
		Vector3(10, 0, -20),
		120.0
	)
	_step(2)
	assert_true(_s.projectiles.is_empty())


func test_the_iron_head_ignores_armour() -> void:
	var sh := _at(SiegeIds.ENEMY_SHIELD, Vector3(10, 0, 0))
	var p := _proj(
		SiegeIds.SHOT_BOLT, SiegeIds.STATION_BALLISTA, Vector3(0, 0, 0.9), Vector3(70, 0, 0), 120.0
	)
	p.ignore_armour = true
	_step(3)
	assert_eq(_lost(sh), 120.0)


func test_a_scorpion_bolt_stops_at_the_first_body() -> void:
	_s.pad(1).type = SiegeIds.PAD_SCORPION
	var a := _at(SiegeIds.ENEMY_SPEAR, Vector3(10, 0, 0))
	var b := _at(SiegeIds.ENEMY_SPEAR, Vector3(12, 0, 0))
	var p := _proj(
		SiegeIds.SHOT_SCORPION, SiegeIds.SRC_PAD + 1, Vector3(0, 0, 0.9), Vector3(50, 0, 0), 10.0
	)
	p.pierce = false
	_step(5)
	assert_eq(_lost(a), 10.0)
	assert_eq(_lost(b), 0.0)
	assert_eq(_s.pad(1).hits, 1)
	assert_eq(_s.pad(1).damage, 10.0)


func test_each_body_is_hit_once_per_bolt() -> void:
	var a := _at(SiegeIds.ENEMY_RAM, Vector3(10, 0, 0))
	_proj(
		SiegeIds.SHOT_BOLT, SiegeIds.STATION_BALLISTA, Vector3(0, 0, 0.9), Vector3(20, 0, 0), 120.0
	)
	_step(12)
	assert_almost_eq(_lost(a), 114.0, 1e-3, "a 2 m body spans several ticks, one hit")


# --- kills, bounties, credit ---------------------------------------------------------------------


func test_a_kill_pays_the_bounty_by_fire_time_shares() -> void:
	var r1 := _s.rider(1)
	var r2 := _s.rider(2)
	var g1 := r1.gold
	var g2 := r2.gold
	var e := _at(SiegeIds.ENEMY_SHIELD, Vector3(50, 120, 0), 10.0)
	var p := _proj(SiegeIds.SHOT_STONE, SiegeIds.STATION_ONAGER, e.pos, Vector3.ZERO, 160.0)
	p.peers = [1, 2]
	p.shares = [0.75, 0.25]
	_step()
	var bounty := 3.0 * _s.bounty_scale
	assert_almost_eq(r1.gold - g1, bounty * 0.75, 1e-6)
	assert_almost_eq(r2.gold - g2, bounty * 0.25, 1e-6)
	assert_eq(r1.kills, 1, "the top share gets the kill")
	assert_eq(r2.kills, 0)
	assert_almost_eq(r1.bounty_gold, bounty * 0.75, 1e-6)
	assert_almost_eq(_s.team_earned, bounty, 1e-6)


func test_a_kill_raises_the_kill_event_with_its_source() -> void:
	var e := _at(SiegeIds.ENEMY_SPEAR, Vector3(50, 120, 0), 5.0)
	_proj(SiegeIds.SHOT_ARROW, SiegeIds.STATION_ARROWS, e.pos, Vector3.ZERO, 8.0)
	_step()
	var kills := SiegeKit.of_type(_events, SiegeIds.EV_KILL)
	assert_eq(kills.size(), 1)
	assert_eq(
		kills[0], SiegeEvents.kill(e.id, SiegeIds.ENEMY_SPEAR, SiegeIds.STATION_ARROWS, false)
	)
	assert_eq(e.hp, 0.0)
	assert_eq(_s.station(SiegeIds.STATION_ARROWS).kills, 1)


func test_a_rush_kill_pays_double_to_a_rider_in_overdrive() -> void:
	var r1 := _s.rider(1)
	r1.od_state = SiegeIds.OD_ACTIVE
	var g := r1.gold
	var e := _at(SiegeIds.ENEMY_SPEAR, Vector3(50, 120, 0), 5.0)
	e.rush = true
	var p := _proj(SiegeIds.SHOT_ARROW, SiegeIds.STATION_ARROWS, e.pos, Vector3.ZERO, 8.0)
	p.peers = [1]
	p.shares = [1.0]
	_step()
	assert_almost_eq(r1.gold - g, 2.0 * 1.0 * _s.bounty_scale, 1e-6)
	assert_eq(int(SiegeKit.of_type(_events, SiegeIds.EV_KILL)[0]["x2"]), 1)


func test_pad_kills_pay_nothing() -> void:
	_s.pad(1).type = SiegeIds.PAD_SCORPION
	var before := _s.rider(1).gold
	var e := _at(SiegeIds.ENEMY_SPEAR, Vector3(10, 0, 0), 5.0)
	var p := _proj(
		SiegeIds.SHOT_SCORPION, SiegeIds.SRC_PAD + 1, Vector3(0, 0, 0.9), Vector3(50, 0, 0), 10.0
	)
	p.pierce = false
	_step(6)
	assert_eq(e.hp, 0.0)
	assert_eq(_s.rider(1).gold, before)
	assert_eq(_s.pad(1).kills, 1)
	assert_eq(int(SiegeKit.of_type(_events, SiegeIds.EV_KILL)[0]["src"]), 11)


func test_damage_is_credited_to_the_station_and_its_riders() -> void:
	var e := _at(SiegeIds.ENEMY_SPEAR, Vector3(50, 120, 0), 1000.0)
	var p := _proj(SiegeIds.SHOT_STONE, SiegeIds.STATION_ONAGER, e.pos, Vector3.ZERO, 160.0)
	p.peers = [2]
	p.shares = [1.0]
	_step()
	assert_eq(_s.station(SiegeIds.STATION_ONAGER).damage_wave, 160.0)
	assert_eq(_s.station(SiegeIds.STATION_ONAGER).damage_total, 160.0)
	assert_eq(_s.rider(2).damage, 160.0)
	assert_eq(_s.station(SiegeIds.STATION_ONAGER).hits, 1)


func test_overkill_credits_only_the_hp_there_was() -> void:
	var e := _at(SiegeIds.ENEMY_SPEAR, Vector3(50, 120, 0), 12.0)
	_proj(SiegeIds.SHOT_STONE, SiegeIds.STATION_ONAGER, e.pos, Vector3.ZERO, 160.0)
	_step()
	assert_eq(_s.station(SiegeIds.STATION_ONAGER).damage_wave, 12.0)


func test_a_destroyed_ram_scatters_six_spearmen_and_counts_as_stopped() -> void:
	var ram := _at(SiegeIds.ENEMY_RAM, Vector3(50, 120, 0), 10.0)
	ram.prog_m = 200.0
	_proj(SiegeIds.SHOT_STONE, SiegeIds.STATION_ONAGER, ram.pos, Vector3.ZERO, 160.0)
	_step()
	assert_eq(_s.queue.size(), 6)
	for sp in _s.queue:
		assert_eq(sp.type, SiegeIds.ENEMY_SPEAR)
		assert_true(sp.crew)
		assert_between(sp.prog_m, 194.0, 198.0)
	assert_eq(_s.engines_stopped, 1)


func test_an_engine_that_reached_the_gate_is_not_stopped() -> void:
	var ram := _at(SiegeIds.ENEMY_RAM, Vector3(50, 120, 0), 10.0)
	ram.reached = true
	_proj(SiegeIds.SHOT_STONE, SiegeIds.STATION_ONAGER, ram.pos, Vector3.ZERO, 160.0)
	_step()
	assert_eq(_s.engines_stopped, 0)


func test_a_tower_destroyed_before_docking_is_stopped_and_has_no_crew() -> void:
	var t := _at(SiegeIds.ENEMY_TOWER, Vector3(50, 120, 0), 10.0)
	_proj(SiegeIds.SHOT_STONE, SiegeIds.STATION_ONAGER, t.pos, Vector3.ZERO, 160.0)
	_step()
	assert_eq(_s.engines_stopped, 1)
	assert_eq(_s.queue.size(), 0)


func test_hits_count_once_per_projectile() -> void:
	var c := Vector3(50, 120, 0)
	for i in 4:
		_at(SiegeIds.ENEMY_SPEAR, c + Vector3(i, 0, 0))
	_proj(SiegeIds.SHOT_STONE, SiegeIds.STATION_ONAGER, c, Vector3.ZERO, 160.0)
	_step()
	assert_eq(_s.station(SiegeIds.STATION_ONAGER).hits, 1)


# --- fire ----------------------------------------------------------------------------------------


func _fire(id: int, e: SiegeEnemyState, n: int = 1) -> Dictionary:
	var sol := SiegeAim.lead(
		_s.path,
		_s.path.station_pos[id],
		_s.path.station_muzzle_m[id],
		e,
		SiegeStations.aim_spec(_s, id),
		2.0
	)
	SiegeProjectiles.fire(_s, SiegeKit.table(_s), id, sol, n, e.id, _events)
	return sol


func test_fire_raises_one_shot_event_with_the_quantized_launch() -> void:
	var e := SiegeKit.enemy(
		_s, SiegeIds.ENEMY_RAM, SiegeKit.prog_in_band(_s, SiegeIds.STATION_ONAGER)
	)
	var sol := _fire(SiegeIds.STATION_ONAGER, e)
	var shots := SiegeKit.of_type(_events, SiegeIds.EV_SHOT)
	assert_eq(shots.size(), 1)
	var ev := shots[0]
	assert_eq(SiegeEvents.check(ev), "")
	assert_eq(ev["o"], SiegeEvents.quantize_o(sol["o"]))
	assert_eq(ev["v"], SiegeEvents.quantize_v(sol["v"]))
	assert_eq(int(ev["kind"]), SiegeIds.SHOT_STONE)
	assert_eq(int(ev["tk"]), _s.tick)
	assert_eq(_s.projectiles.size(), 1)


func test_the_host_flies_what_a_client_replays() -> void:
	var e := SiegeKit.enemy(
		_s, SiegeIds.ENEMY_SPEAR, SiegeKit.prog_in_band(_s, SiegeIds.STATION_ARROWS)
	)
	_fire(SiegeIds.STATION_ARROWS, e, 12)
	var ev := SiegeKit.of_type(_events, SiegeIds.EV_SHOT)[0]
	var def := _s.content.station_def(SiegeIds.STATION_ARROWS)
	var replay := SiegeBallistics.shot_velocities(
		SiegeEvents.shot_velocity(ev),
		12,
		int(ev["sd"]),
		float(def["spread_deg"]),
		float(def["speed_spread"])
	)
	assert_eq(_s.projectiles.size(), 12)
	for j in 12:
		var l := SiegeBallistics.land(
			SiegeEvents.shot_origin(ev), replay[j], float(def["k"]), _s.projectiles[j].floor_z
		)
		assert_true(
			(l["p"] as Vector3).is_equal_approx(_s.projectiles[j].pos), "arrow %d lands alike" % j
		)
		assert_eq(int(l["steps"]), _s.projectiles[j].ticks)


func test_fire_records_the_shares_of_the_riders_delivering_now() -> void:
	SiegeKit.put(_s, 1, SiegeIds.STATION_ONAGER, 300.0)
	SiegeKit.put(_s, 2, SiegeIds.STATION_ONAGER, 100.0)
	var e := SiegeKit.enemy(
		_s, SiegeIds.ENEMY_RAM, SiegeKit.prog_in_band(_s, SiegeIds.STATION_ONAGER)
	)
	_fire(SiegeIds.STATION_ONAGER, e)
	var p := _s.projectiles[0]
	assert_eq(p.peers, [1, 2])
	assert_almost_eq(p.shares[0], 0.75, 1e-6)
	assert_almost_eq(p.shares[1], 0.25, 1e-6)


func test_an_aqueduct_shot_has_no_riders_to_pay() -> void:
	var e := SiegeKit.enemy(
		_s, SiegeIds.ENEMY_RAM, SiegeKit.prog_in_band(_s, SiegeIds.STATION_ONAGER)
	)
	_fire(SiegeIds.STATION_ONAGER, e)
	assert_eq(_s.projectiles[0].peers, [])


func test_seeds_come_from_the_session_rng() -> void:
	var e := SiegeKit.enemy(
		_s, SiegeIds.ENEMY_RAM, SiegeKit.prog_in_band(_s, SiegeIds.STATION_ONAGER)
	)
	_fire(SiegeIds.STATION_ONAGER, e)
	_fire(SiegeIds.STATION_ONAGER, e)
	var shots := SiegeKit.of_type(_events, SiegeIds.EV_SHOT)
	assert_ne(int(shots[0]["sd"]), int(shots[1]["sd"]))
	var again := SiegeKit.state("short", 2)
	var e2 := SiegeKit.enemy(
		again, SiegeIds.ENEMY_RAM, SiegeKit.prog_in_band(again, SiegeIds.STATION_ONAGER)
	)
	var ev2: Array[Dictionary] = []
	var sol := SiegeAim.lead(
		again.path,
		again.path.station_pos[2],
		again.path.station_muzzle_m[2],
		e2,
		SiegeStations.aim_spec(again, 2),
		2.0
	)
	SiegeProjectiles.fire(again, SiegeKit.table(again), 2, sol, 1, e2.id, ev2)
	assert_eq(int(ev2[0]["sd"]), int(shots[0]["sd"]), "same session seed, same shot seed")


func test_the_ballista_iron_head_is_set_at_level_3() -> void:
	_s.station(SiegeIds.STATION_BALLISTA).level = 3
	var e := SiegeKit.enemy(
		_s, SiegeIds.ENEMY_SHIELD, SiegeKit.prog_in_band(_s, SiegeIds.STATION_BALLISTA)
	)
	_fire(SiegeIds.STATION_BALLISTA, e)
	assert_true(_s.projectiles[0].ignore_armour)
	assert_true(_s.projectiles[0].pierce)


func test_clear_drops_everything_in_flight() -> void:
	_proj(SiegeIds.SHOT_STONE, SiegeIds.STATION_ONAGER, Vector3.ZERO, Vector3.ZERO, 1.0)
	SiegeProjectiles.clear(_s)
	assert_true(_s.projectiles.is_empty())
