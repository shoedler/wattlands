extends GutTest
## SiegeState (STATE_V2.md): the starting state, lookups, range bands, the tar capacities, the
## Overdrive prompt's "hot" station, serialization.

const F := preload("res://tests/games/siege/siege_fakes.gd")


func test_a_fresh_state() -> void:
	var s := SiegeKit.state("short", 3, 1)
	assert_eq(s.riders.size(), 4)
	assert_eq(s.stations.size(), 5)
	assert_eq(s.pads.size(), 4)
	assert_eq(s.path, s.content.path)
	for r in s.riders:
		assert_eq(r.target, SiegeIds.STATION_MINE, "everyone starts on the mine")
		assert_eq(r.gold, 40.0, "with 40 gold")
	assert_eq(s.gate_hp, 130.0)
	assert_eq(s.gate_max, 130.0)
	assert_eq(s.waves_total, 3)
	assert_eq(s.mine_level, 0)


func test_pad_1_starts_with_a_scorpion() -> void:
	var s := SiegeKit.state()
	assert_eq(s.pad(1).type, SiegeIds.PAD_SCORPION)
	for n in [2, 3, 4]:
		assert_false(s.pad(n).built(), "pad %d" % n)
	assert_eq(s.built_pads(), [1])


func test_the_cauldrons_start_full() -> void:
	var s := SiegeKit.state()
	assert_eq(s.tar.cauldron_l, 300.0)
	assert_eq(s.tar.cauldron_max_l, 300.0)
	assert_eq(s.tar.curtain_hp, 0.0)
	assert_eq(s.tar.curtain_max, 200.0)
	assert_false(s.tar.boarded)


func test_stations_start_at_their_yaw() -> void:
	var s := SiegeKit.state()
	for id in 5:
		assert_eq(s.station(id).id, id)
		assert_eq(s.station(id).yaw_deg, s.path.station_yaw0_deg[id])


func test_lookups() -> void:
	var s := SiegeKit.state("short", 2, 1)
	assert_eq(s.rider(2).slot, 1)
	assert_eq(s.rider(-1).slot, 2)
	assert_null(s.rider(77))
	assert_eq(s.rider_at(0).peer, 1)
	assert_null(s.rider_at(9))
	var e := SiegeKit.enemy(s, SiegeIds.ENEMY_SPEAR, 10.0)
	assert_eq(s.enemy(e.id), e)
	assert_null(s.enemy(0))
	assert_null(s.enemy(999))


func test_routed_count_and_riders_on() -> void:
	var s := SiegeKit.state("short", 3)
	SiegeKit.put(s, 1, SiegeIds.STATION_ONAGER)
	SiegeKit.put(s, 2, SiegeIds.STATION_ONAGER)
	s.rider(2).reconnect_s = 1.0
	assert_eq(s.routed_count(SiegeIds.STATION_ONAGER), 2, "reconnecting riders count")
	assert_eq(s.riders_on(SiegeIds.STATION_ONAGER).size(), 1, "only delivering ones deliver")
	assert_eq(s.routed_count(SiegeIds.STATION_MINE), 1)


func test_station_caps() -> void:
	var s := SiegeKit.state()
	assert_eq(s.station_cap(SiegeIds.STATION_BALLISTA), 1)
	assert_eq(s.station_cap(SiegeIds.STATION_TAR), 1)
	assert_eq(s.station_cap(SiegeIds.STATION_ONAGER), 2)


func test_range_bands_and_upgrade_2() -> void:
	var s := SiegeKit.state()
	assert_eq(s.range_band(SiegeIds.STATION_ONAGER), Vector2(30, 100))
	s.station(SiegeIds.STATION_ONAGER).level = 2
	assert_eq(s.range_band(SiegeIds.STATION_ONAGER), Vector2(30, 125), "+25% range")
	assert_eq(s.range_band(SiegeIds.STATION_MINE), Vector2.ZERO)
	assert_eq(s.range_band(SiegeIds.STATION_TAR), Vector2.ZERO)


func test_in_band_uses_the_ground_distance_from_the_pivot() -> void:
	var s := SiegeKit.state()
	var at := s.path.station_pos[SiegeIds.STATION_ONAGER]
	assert_false(s.in_band(SiegeIds.STATION_ONAGER, at + Vector3(10, 0, 0)), "inside 30 m")
	assert_true(
		s.in_band(SiegeIds.STATION_ONAGER, at + Vector3(50, 0, -17)), "50 m, height ignored"
	)
	assert_false(s.in_band(SiegeIds.STATION_ONAGER, at + Vector3(0, 101, 0)))
	assert_false(s.in_band(SiegeIds.STATION_MINE, at))


func test_pad_bands() -> void:
	var s := SiegeKit.state()
	assert_eq(s.pad_band(1), Vector2(0, 60))
	s.pad(1).level = 2
	assert_eq(s.pad_band(1), Vector2(0, 75))
	assert_eq(s.pad_band(2), Vector2.ZERO, "empty")


func test_cauldron_and_curtain_capacity() -> void:
	var s := SiegeKit.state()
	s.perks.append(SiegeIds.PERK_CAULDRON)
	assert_eq(s.cauldron_max(), 400.0, "+100 L with the Spare cauldron")
	s.station(SiegeIds.STATION_TAR).level = 2
	assert_eq(s.curtain_max(), 250.0, "curtain max +25% after upgrade 2")


func test_target_hot_for_weapons() -> void:
	var s := SiegeKit.state()
	assert_false(s.target_hot(SiegeIds.STATION_BALLISTA))
	SiegeKit.enemy(s, SiegeIds.ENEMY_SPEAR, SiegeKit.prog_in_band(s, SiegeIds.STATION_BALLISTA))
	assert_true(s.target_hot(SiegeIds.STATION_BALLISTA))
	assert_false(s.target_hot(SiegeIds.STATION_MINE), "the mine is never hot")


func test_target_hot_for_the_tar_works_needs_an_engine_near_the_gate() -> void:
	var s := SiegeKit.state()
	SiegeKit.enemy(s, SiegeIds.ENEMY_SPEAR, s.path.length_m - 10.0)
	assert_false(s.target_hot(SiegeIds.STATION_TAR), "infantry don't count")
	var ram := SiegeKit.enemy(s, SiegeIds.ENEMY_RAM, s.path.length_m - 61.0)
	assert_false(s.target_hot(SiegeIds.STATION_TAR), "61 m out")
	ram.prog_m = s.path.length_m - 59.0
	assert_true(s.target_hot(SiegeIds.STATION_TAR), "within 60 m")


func test_retreating_enemies_are_never_hot() -> void:
	var s := SiegeKit.state()
	var e := SiegeKit.enemy(
		s, SiegeIds.ENEMY_SPEAR, SiegeKit.prog_in_band(s, SiegeIds.STATION_ARROWS)
	)
	e.st = SiegeIds.EN_RETREAT
	assert_false(s.target_hot(SiegeIds.STATION_ARROWS))


func test_alive_by_type_and_the_docked_tower() -> void:
	var s := SiegeKit.state()
	SiegeKit.enemy(s, SiegeIds.ENEMY_SPEAR, 1.0)
	SiegeKit.enemy(s, SiegeIds.ENEMY_SPEAR, 2.0)
	var t := SiegeKit.enemy(s, SiegeIds.ENEMY_TOWER, 3.0)
	assert_eq(s.alive_by_type(), [0, 2, 0, 0, 0, 1])
	assert_null(s.docked_tower())
	t.st = SiegeIds.EN_DOCKED
	assert_eq(s.docked_tower(), t)


func test_phase_predicates() -> void:
	var s := SiegeKit.state()
	assert_true(s.in_wave())
	assert_false(s.shop_open())
	s.role = SiegeIds.ROLE_BUILD_BREAK
	assert_true(s.shop_open())
	s.role = SiegeIds.ROLE_COOLDOWN
	assert_true(s.in_cooldown())
	assert_false(s.rush_on())
	s.wave.rush_s = 3.0
	assert_true(s.rush_on())


func test_queued_on_host_and_client() -> void:
	var s := SiegeKit.state()
	SiegeSpawner.enqueue(s, SiegeIds.ENEMY_SPEAR, 0.0)
	assert_eq(s.queued(), 1)
	s.queue.clear()
	s.queue_len = 7
	assert_eq(s.queued(), 7)


func test_take_od_requests_empties_the_list() -> void:
	var s := SiegeKit.state()
	s.od_requests = [1, 2]
	assert_eq(s.take_od_requests(), [1, 2])
	assert_eq(s.od_requests, [])


func test_to_dict_and_back_keeps_the_state() -> void:
	var s := SiegeFixtures.mid_wave()
	var d := s.to_dict()
	var back := SiegeState.from_dict(JSON.parse_string(JSON.stringify(d)), s.content)
	assert_eq(back.riders.size(), 4)
	assert_eq(back.enemies.size(), s.enemies.size())
	assert_eq(back.station(SiegeIds.STATION_ONAGER).level, 2)
	assert_eq(back.pad(2).level, 2)
	assert_eq(back.tar.curtain_hp, 80.0)
	assert_eq(back.queue.size(), 3)
	assert_true(back.enemies[5].pos.distance_to(s.enemies[5].pos) < 0.01, "positions re-placed")
	assert_eq(back.rider_at(0).station_s.size(), 5)


func test_records_round_trip_vector3() -> void:
	var e := SiegeEnemyState.new()
	e.pos = Vector3(1.5, -2.5, 3.25)
	e.id = 4
	var back := SiegeEnemyState.new().load_dict(JSON.parse_string(JSON.stringify(e.to_dict())))
	assert_eq((back as SiegeEnemyState).pos, Vector3(1.5, -2.5, 3.25))
	assert_eq((back as SiegeEnemyState).id, 4)


func test_rider_top_station() -> void:
	var r := SiegeRiderState.new()
	assert_eq(r.top_station(), SiegeIds.STATION_MINE)
	r.station_s[SiegeIds.STATION_ARROWS] = 30.0
	r.station_s[SiegeIds.STATION_MINE] = 10.0
	assert_eq(r.top_station(), SiegeIds.STATION_ARROWS)


func test_delivering() -> void:
	var r := SiegeRiderState.new()
	assert_true(r.delivering())
	r.reconnect_s = 0.5
	assert_false(r.delivering())
	r.reconnect_s = 0.0
	r.afk = true
	assert_false(r.delivering())
	r.afk = false
	r.connected = false
	assert_false(r.delivering())


func test_the_state_v2_names_exist() -> void:
	# contracts/STATE_V2.md: the view builder codes against these names.
	var s := SiegeFixtures.mid_wave()
	for f: String in [
		"path",
		"tick",
		"t",
		"phase_index",
		"role",
		"wave_no",
		"waves_total",
		"phase_elapsed_s",
		"phase_duration_s",
		"phase_remaining_s",
		"done",
		"gate_hp",
		"gate_max",
		"breach_s",
		"breaches",
		"iron_bands",
		"mine_level",
		"perks",
		"team_w",
		"riders",
		"stations",
		"pads",
		"enemies",
		"tar"
	]:
		assert_true(f in s, f)
	for f: String in [
		"slot",
		"peer",
		"is_bot",
		"target",
		"reconnect_s",
		"p_eff_w",
		"raw_w",
		"cadence_rpm",
		"rescue",
		"afk",
		"gold",
		"od_state",
		"od_s",
		"od_cd_s",
		"od_prompt",
		"wave_mine_s",
		"wave_weapon_s"
	]:
		assert_true(f in s.riders[0], f)
	for f: String in [
		"id", "level", "m", "wind", "yaw_deg", "arm", "rack", "damage_wave", "shots", "hits"
	]:
		assert_true(f in s.stations[0], f)
	for f: String in ["pad", "type", "level", "cd_s", "yaw_deg"]:
		assert_true(f in s.pads[0], f)
	for f: String in ["id", "type", "hp", "max_hp", "st", "prog_m", "lat_m", "speed_mps", "pos"]:
		assert_true(f in s.enemies[0], f)
	for f: String in [
		"cauldron_l", "cauldron_max_l", "curtain_hp", "curtain_max", "coat", "boarded"
	]:
		assert_true(f in s.tar, f)
	assert_true(s.has_method("in_wave") and s.has_method("shop_open"))
	assert_true(s.has_method("in_cooldown") and s.has_method("rush_on") and s.has_method("queued"))
