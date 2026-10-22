extends GutTest
## SiegeState and its records: the starting state (brief 2.4), lookups, ranges, serialization.

const F := preload("res://tests/games/siege/siege_fakes.gd")
const FIX := preload("res://tests/games/siege/fixtures/siege_fixtures.gd")


func test_the_starting_state() -> void:
	var c := F.content("short")
	var s := SiegeState.create(c, F.make_slots(2, 2), Wl.FAIR_FTP, RandomNumberGenerator.new())
	assert_eq(s.riders.size(), 4)
	for r in s.riders:
		assert_eq(r.target, SiegeIds.TARGET_GEN, "everyone starts on the generator")
		assert_eq(r.denarii, 40.0)
		assert_true(r.route_fallback and r.shop_fallback)
	assert_eq([s.rider_at(2).is_bot, s.rider_at(2).autopilot], [true, true])
	assert_eq(s.pads.size(), 8)
	assert_eq(s.built_pads(), [3, 4] as Array[int])
	assert_eq(s.pad(3).type, SiegeIds.TOWER_BALLISTA)
	assert_eq(s.pad(4).type, SiegeIds.TOWER_SCORPION)
	assert_eq([s.gate_hp, s.gate_max, s.breaches, s.gen_level], [100.0, 100.0, 0, 0])
	assert_eq(s.waves_total, 3)
	assert_eq(s.phase_index, -1)


func test_ranges_and_lookups_on_the_fixture() -> void:
	var s := FIX.mid_wave()
	assert_eq(s.tower_range_m(3), 40.0, "Ballista L1")
	assert_eq(s.tower_range_m(6), 50.0, "Ballista L3: x1.25 from upgrade 2")
	assert_eq(s.tower_range_m(2), 31.25, "Caltrop L2")
	assert_eq(s.tower_range_m(1), 0.0, "empty")
	assert_gt(s.enemy_hp_in_range(3), 0.0, "the ram at the gate is in the Ballista's reach")
	assert_true(s.target_hot(3))
	assert_false(s.target_hot(SiegeIds.TARGET_GEN))
	assert_eq(s.routed_count(4), 1)
	assert_eq(s.riders_on(4).size(), 0, "slot 2 is still reconnecting")
	assert_eq(s.riders_on(3).size(), 1)
	assert_eq(s.enemy(100).road, 0)
	assert_null(s.enemy(5))
	var alive := s.alive_by_type()
	assert_eq(alive[SiegeIds.ENEMY_RAM], 1)
	assert_eq(alive[1] + alive[2] + alive[3] + alive[4], s.enemies.size())
	assert_true(s.in_wave())
	assert_false(s.shop_open())
	assert_false(s.rush_on())


func test_to_dict_and_back() -> void:
	var c := FIX.content("vo2")
	var s := FIX.mid_wave(c)
	var d := s.to_dict()
	var text := JSON.stringify(d)
	var back := SiegeState.from_dict(JSON.parse_string(text), c)
	assert_eq(JSON.stringify(back.to_dict()), text, "a JSON round trip is lossless")
	assert_eq(back.riders.size(), 4)
	assert_eq(back.rider_at(0).od_state, SiegeIds.OD_ACTIVE)
	assert_eq(typeof(back.rider_at(0).od_state), TYPE_INT)
	assert_eq(back.enemies.size(), s.enemies.size())
	assert_eq(back.enemies[0].pos, s.enemies[0].pos)
	assert_eq(back.wave.active_roads, [0, 1, 2] as Array[int])
	assert_eq(back.shots[1].targets, s.shots[1].targets)
	assert_eq(back.perks, [SiegeIds.PERK_RESERVE] as Array[int])
	assert_eq(back.content, c)


func test_od_requests_drain_once() -> void:
	var s := FIX.mid_wave()
	s.od_requests.append(2)
	assert_eq(s.take_od_requests(), [2] as Array[int])
	assert_eq(s.take_od_requests(), [] as Array[int])
