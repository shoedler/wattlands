extends GutTest
## What the Tank Controls show, from the fixtures: the station card per engine (diesel speed,
## distance to the halt line and berm; dynamo bank, target and elevation; steam dial marks and the
## loaded shell; Bulwark lever, auto marker and hoist progress), the objective line and boss bars.


func _card(state: TankState, peer: int) -> Dictionary:
	return TankHudModel.card(state, peer)


func test_the_diesel_card_shows_speed_halt_distance_and_the_ram() -> void:
	var s := TankFixtures.state(2)
	var peer := s.rider_at(s.station(TankIds.ENGINE_DIESEL).slot).peer
	var c := _card(s, peer)
	assert_eq(c["kind"], TankIds.ENGINE_DIESEL)
	assert_almost_eq(float(c["speed_kmh"]), 7.4 * 3.6, 1e-3)
	var length_m := float(s.content.segment(s.seg.phase_index)["length_m"])
	assert_almost_eq(float(c["halt_m"]), length_m - s.hull.x_px / TankConst.PX_PER_M, 1e-3)
	assert_false(c["show_berm"], "the berm shows at a gun line")
	var d := s.station(TankIds.ENGINE_DIESEL) as TankDieselState
	d.ram_s = 4.0
	d.ram_cd_s = 0.0
	var ram := _card(s, peer)
	assert_almost_eq(float(ram["ram_frac"]), 0.4, 1e-6, "a 10 s window")
	d.ram_s = 0.0
	d.ram_cd_s = 15.0
	assert_almost_eq(float(_card(s, peer)["ram_cd_frac"]), 0.5, 1e-6, "a 30 s cooldown")


func test_the_halt_distance_comes_from_the_mission_and_clamps_at_zero() -> void:
	var s := TankFixtures.state(1)
	var length_m := float(s.content.segment(s.seg.phase_index)["length_m"])
	s.hull.x_px = TankConst.m_to_px(length_m + 50.0)
	assert_eq(TankHudModel.halt_distance_m(s), 0.0)
	s.hull.x_px = 0.0
	assert_almost_eq(TankHudModel.halt_distance_m(s), length_m, 1e-6)
	s.seg.seg = TankIds.SEG_GUN_LINE
	assert_eq(TankHudModel.halt_distance_m(s), -1.0, "only an Advance has a halt line")


func test_the_berm_shows_at_a_gun_line() -> void:
	var s := TankFixtures.gun_line(2)
	var peer := s.rider_at(s.station(TankIds.ENGINE_DIESEL).slot).peer
	var c := _card(s, peer)
	assert_true(c["show_berm"])
	assert_eq(c["berm"], 18.0)
	assert_eq(c["berm_max"], 40.0)


func test_the_dynamo_card_shows_the_bank_its_target_and_the_elevation() -> void:
	var s := TankFixtures.state(2)
	var peer := s.rider_at(s.station(TankIds.ENGINE_DYNAMO).slot).peer
	var c := _card(s, peer)
	assert_eq(c["kind"], TankIds.ENGINE_DYNAMO)
	assert_eq(c["bank"], 64.0)
	assert_almost_eq(float(c["bank_frac"]), 0.64, 1e-6)
	assert_almost_eq(
		float(c["target_pct"]),
		55.0 + 45.0 * 0.36,
		1e-3,
		"the ERG target 55 + 45 x (1 - bank / 100)"
	)
	assert_eq(c["elev_deg"], 6.5)
	assert_eq(c["facing"], TankIds.FACE_RIGHT)
	(s.station(TankIds.ENGINE_DYNAMO) as TankDynamoState).bank = 0.0
	assert_almost_eq(float(_card(s, peer)["target_pct"]), 100.0, 1e-3)
	(s.station(TankIds.ENGINE_DYNAMO) as TankDynamoState).bank = 100.0
	assert_almost_eq(float(_card(s, peer)["target_pct"]), 55.0, 1e-3)


func test_the_bank_target_follows_the_phases_range() -> void:
	var s := TankFixtures.state(2)
	s.seg.seg = TankIds.SEG_ADVANCE
	var entry := s.content.plan_entry(TankIds.ENGINE_DYNAMO, TankIds.SEG_ADVANCE)
	var rng: Array = entry.get("range_pct", [55, 100])
	var lo := float(rng[0])
	var hi := float(rng[1])
	var t := TankHudModel.bank_target_pct(s, 0.0)
	assert_gte(t, lo)
	assert_lte(t, hi)


func test_the_steam_card_shows_the_dial_marks_and_the_loaded_shell() -> void:
	var s := TankFixtures.state(3)
	var peer := s.rider_at(s.station(TankIds.ENGINE_STEAM).slot).peer
	var c := _card(s, peer)
	assert_eq(c["kind"], TankIds.ENGINE_STEAM)
	assert_eq(c["pressure"], 72.0)
	assert_almost_eq(float(c["dial_frac"]), 0.48, 1e-6, "72% on a 0..150 dial")
	assert_eq(c["marks"], [40.0, 100.0, 150.0] as Array[float])
	assert_eq(c["shell"], "")
	var st := s.station(TankIds.ENGINE_STEAM) as TankSteamState
	st.loaded = true
	s.hull.loaded = TankIds.SHELL_HEAVY
	assert_eq(_card(s, peer)["shell"], "TANK_SHELL_HEAVY")
	s.hull.loaded = TankIds.SHELL_OVER
	assert_eq(_card(s, peer)["shell"], "TANK_SHELL_OVER")
	s.hull.loaded = TankIds.SHELL_LIGHT
	assert_eq(_card(s, peer)["shell"], "TANK_SHELL_LIGHT")
	st.window_s = 2.5
	assert_almost_eq(float(_card(s, peer)["window_frac"]), 0.5, 1e-6, "a 5 s window")
	st.pressure_pct = 125.0
	assert_almost_eq(
		float(_card(s, peer)["over_frac"]), 0.5, 1e-6, "100 to 150 is the Overpressure build"
	)


func test_the_bulwark_card_shows_the_lever_the_auto_marker_and_the_hoist() -> void:
	var s := TankFixtures.state(1)
	var c := _card(s, 1)
	assert_eq(c["kind"], TankIds.ENGINE_BULWARK)
	assert_eq(c["lever"], TankIds.LEVER_TURRET)
	assert_true(c["auto"], "the auto-lever is on by default")
	assert_almost_eq(
		float(c["hoist_frac"]),
		1500.0 / TankFixtures.content().num("tanks", "gearbox.hoist_j", 4000.0),
		1e-6
	)
	assert_almost_eq(float(c["speed_kmh"]), 7.4 * 3.6, 1e-3, "the Bulwark drives too")
	var g := s.station(TankIds.ENGINE_BULWARK) as TankGearboxState
	g.auto = false
	g.lever = TankIds.LEVER_DRIVE
	g.lever_to = TankIds.LEVER_HOIST
	g.move_s = 0.4
	var moving := _card(s, 1)
	assert_false(moving["auto"])
	assert_eq(moving["lever_to"], TankIds.LEVER_HOIST)
	assert_almost_eq(float(moving["move_s"]), 0.4, 1e-6)
	var gl := TankFixtures.gun_line(1)
	assert_true(_card(gl, 1)["dig"], "Drive is Dig at a gun line")


func test_an_unknown_peer_has_no_card() -> void:
	assert_eq(_card(TankFixtures.state(3), 99), {"kind": "none"})


func test_a_reserve_or_unpowered_station_is_flagged() -> void:
	var s := TankFixtures.state(2)
	var peer := s.rider_at(s.station(TankIds.ENGINE_DYNAMO).slot).peer
	s.station(TankIds.ENGINE_DYNAMO).reserve = true
	assert_true(_card(s, peer)["reserve"])
	s.all_afk = true
	assert_true(_card(s, peer)["unpowered"])
	(s.station(TankIds.ENGINE_DYNAMO) as TankDynamoState).stalled = true
	assert_true(_card(s, peer)["stalled"])


func test_the_objective_line_per_segment() -> void:
	var s := TankFixtures.state(1)
	var adv := TankHudModel.objective(s)
	assert_eq(adv["key"], "TANK_OBJ_ADVANCE")
	assert_eq(adv["args"][0], int(ceilf(TankHudModel.halt_distance_m(s))))
	var g := TankFixtures.gun_line(1)
	g.gun_line.guns_total = 4
	g.gun_line.guns_left = 2
	var gl := TankHudModel.objective(g)
	assert_eq(gl["key"], "TANK_OBJ_GUN_LINE")
	assert_eq(gl["args"], [2, 4], "Gun line 2/4")
	g.gun_line.guns_left = 4
	assert_eq(TankHudModel.objective(g)["args"], [0, 4])
	g.gun_line.guns_left = 0
	assert_eq(TankHudModel.objective(g)["args"], [4, 4])
	var b := TankFixtures.boss(1)
	assert_eq(TankHudModel.objective(b)["key"], "TANK_OBJ_BOSS")
	for pair: Array in [
		[TankIds.SEG_DEPOT, "TANK_OBJ_DEPOT"],
		[TankIds.SEG_CHECKPOINT, "TANK_OBJ_CHECKPOINT"],
		[TankIds.SEG_SKIRMISH, "TANK_OBJ_SKIRMISH"]
	]:
		s.seg.seg = pair[0]
		assert_eq(TankHudModel.objective(s)["key"], pair[1])


func test_regroup_overrides_the_objective_and_the_cooldown_has_none() -> void:
	var s := TankFixtures.state(1)
	s.seg.regroup = true
	var o := TankHudModel.objective(s)
	assert_eq(o["key"], "TANK_OBJ_REGROUP")
	assert_true(o["warn"])
	s.seg.regroup = false
	s.seg.seg = TankIds.SEG_COOLDOWN
	assert_eq(TankHudModel.objective(s), {})
	s.seg.seg = ""
	assert_eq(TankHudModel.objective(s), {})


func test_boss_bars_show_the_fractions_scaled_by_the_tank() -> void:
	var s := TankFixtures.boss(3)
	var b := TankHudModel.boss_bars(s)
	assert_true(b["show"])
	assert_eq(b["bogies"], [1.0, 0.4, 0.0] as Array[float])
	assert_eq(b["turret"], 1.0)
	assert_true(b["telegraph"])
	var small := TankFixtures.boss(1)
	var def := TankFixtures.content().boss_def()
	var scale := TankFixtures.content().enemy_scale(TankIds.TANK_BULWARK)
	var bogie_max := float(def["bogie_hp"]) * scale
	var turret_max := float(def["turret_hp"]) * scale
	small.boss.bogie_hp = [bogie_max, bogie_max * 0.5, 0.0]
	small.boss.turret_hp = turret_max * 0.5
	var bb := TankHudModel.boss_bars(small)
	assert_almost_eq(bb["bogies"][0], 1.0, 1e-6, "the boss HP x the Bulwark's scale")
	assert_almost_eq(bb["bogies"][1], 0.5, 1e-6)
	assert_almost_eq(bb["turret"], 0.5, 1e-6, "the turret HP x the Bulwark's scale")


func test_no_boss_bars_before_the_behemoth() -> void:
	assert_eq(TankHudModel.boss_bars(TankFixtures.state(3)), {"show": false})
	var s := TankFixtures.boss(3)
	s.boss.phase = TankIds.BOSS_DEAD
	assert_true(TankHudModel.boss_bars(s)["dead"])


func test_the_telegraph_blink_is_on_game_time() -> void:
	var s := TankFixtures.boss(3)
	s.t = 1.0
	var a: bool = TankHudModel.boss_bars(s)["blink"]
	s.t = 1.25
	var b: bool = TankHudModel.boss_bars(s)["blink"]
	assert_ne(a, b, "four blinks a second")
	s.boss.telegraph_s = 0.0
	assert_false(TankHudModel.boss_bars(s)["blink"])
