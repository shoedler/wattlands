extends GutTest
## TankHudModel's pure parts the plates read, from the fixtures: the halt distance, the dynamo's
## bank target, the objective line and the boss bars.


func test_the_halt_distance_comes_from_the_mission_and_clamps_at_zero() -> void:
	var s := TankFixtures.state(1)
	var length_m := float(s.content.segment(s.seg.phase_index)["length_m"])
	s.hull.x_px = TankConst.m_to_px(length_m + 50.0)
	assert_eq(TankHudModel.halt_distance_m(s), 0.0)
	s.hull.x_px = 0.0
	assert_almost_eq(TankHudModel.halt_distance_m(s), length_m, 1e-6)
	s.seg.seg = TankIds.SEG_GUN_LINE
	assert_eq(TankHudModel.halt_distance_m(s), -1.0, "only an Advance has a halt line")


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
	var scale := TankFixtures.content().enemy_scale(TankIds.TANK_LANDSHIP)
	var bogie_max := float(def["bogie_hp"]) * scale
	var turret_max := float(def["turret_hp"]) * scale
	small.boss.bogie_hp = [bogie_max, bogie_max * 0.5, 0.0]
	small.boss.turret_hp = turret_max * 0.5
	var bb := TankHudModel.boss_bars(small)
	assert_almost_eq(bb["bogies"][0], 1.0, 1e-6, "the boss HP x the tank's scale")
	assert_almost_eq(bb["bogies"][1], 0.5, 1e-6)
	assert_almost_eq(bb["turret"], 0.5, 1e-6, "the turret HP x the tank's scale")


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
