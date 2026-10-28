extends GutTest
## The tracks (brief 2.4 Drive): the speed model on the driver's P_eff, the world scroll, obstacles,
## the sprint rule, evasive, the berm, breakdown and repair (v2: no Ram, brief 2.4).

const ADVANCE := 1
const GUN_LINE := 2


## A mission patch: segment `index` gets `props` merged in (for example an empty encounter list).
static func _patch(index: int, props: Dictionary) -> Callable:
	return func(files: Dictionary) -> void:
		(files["mission"]["segments"][index] as Dictionary).merge(props, true)


## An Advance with nothing in it on a constant grade.
static func _empty_advance(grade: float) -> Callable:
	return _patch(ADVANCE, {"encounters": [], "obstacles": [], "terrain": [[0, grade]]})


func _driver_v(rig: TankRulesRig) -> float:
	return rig.hull().speed_mps


func test_speed_follows_the_speed_model_oracle_on_the_drivers_p_eff() -> void:
	for grade: float in [0.0, 3.0, -2.0, 5.0]:
		var rig := TankRulesRig.new(1, "ashfall_road", 7, _empty_advance(grade))
		rig.enter(ADVANCE, 1.0)
		rig.run(60.0)
		var want := SpeedModel.steady_state_speed(225.0, grade, 75.0 + 8.0, 0.5)
		assert_almost_eq(_driver_v(rig), want, want * 0.02, "grade %.0f%%" % grade)
		assert_eq(rig.hull().grade_pct, grade, "the terrain grade under the tank")


func test_80_percent_ftp_on_the_flat_is_8_2_m_s_and_66_px_s() -> void:
	var rig := TankRulesRig.new(1, "ashfall_road", 7, _empty_advance(0.0))
	rig.sim_pct = 80.0
	rig.enter(ADVANCE, 1.0)
	rig.run(80.0)
	assert_almost_eq(_driver_v(rig), 8.2, 0.15)
	var before := rig.hull().x_px
	rig.run(10.0)
	var px_per_s := (rig.hull().x_px - before) / 10.0
	assert_almost_eq(px_per_s, 66.0, 1.5, "the world scrolls 0.4 x speed at 20 px per visual metre")


func test_the_world_scrolls_eight_px_per_game_metre() -> void:
	assert_eq(TankConst.PX_PER_M, 8.0)
	var rig := TankRulesRig.new(1, "ashfall_road", 7, _empty_advance(0.0))
	rig.enter(ADVANCE, 1.0)
	rig.run(20.0)
	assert_almost_eq(rig.hull().x_px, rig.hull().distance_m * 8.0, 1e-6)


func test_the_drive_uses_the_mass_of_the_rider_on_the_diesel() -> void:
	var slow := TankRulesRig.new(1, "ashfall_road", 7, _empty_advance(4.0))
	slow.mass_kg = 110.0
	slow.enter(ADVANCE, 1.0)
	slow.run(60.0)
	var fast := TankRulesRig.new(1, "ashfall_road", 7, _empty_advance(4.0))
	fast.mass_kg = 55.0
	fast.enter(ADVANCE, 1.0)
	fast.run(60.0)
	assert_lt(_driver_v(slow), _driver_v(fast), "a heavier rider climbs slower")
	assert_almost_eq(_driver_v(slow), SpeedModel.steady_state_speed(225.0, 4.0, 118.0, 0.5), 0.15)


func test_the_tank_holds_in_gun_lines_checkpoints_and_the_boss_and_in_a_breakdown() -> void:
	var rig := TankRulesRig.new(1)
	for index in [2, 3, 10]:
		rig.enter(index, 3.0)
		rig.run(5.0)
		assert_eq(rig.hull().speed_mps, 0.0, "segment %d" % index)
		assert_true(rig.hull().holding, "segment %d" % index)
		assert_eq(rig.hull().x_px, 0.0)


func test_a_wire_stops_the_tank_at_its_standoff_until_a_heavy_shell_clears_it() -> void:
	var rig := TankRulesRig.new(
		1,
		"ashfall_road",
		7,
		_patch(
			ADVANCE,
			{"encounters": [], "obstacles": [{"at_m": 300, "type": "wire"}], "terrain": [[0, 0]]}
		)
	)
	rig.no_fire = true
	rig.no_bow = true
	rig.enter(ADVANCE, 1.0)
	var o := rig.state.obstacles[0]
	var standoff := rig.content.num("tanks", "props.standoff_px")
	rig.run(70.0)
	assert_eq(rig.hull().speed_mps, 0.0, "stopped")
	assert_eq(rig.hull().blocked_by, o.id)
	var front := rig.hull().x_px + rig.hull().hull_w
	assert_almost_eq(
		o.x_px - front, standoff, 0.5, "it stops its standoff short, where the gun reaches"
	)
	assert_false(o.cleared)
	var d := rig.hull().distance_m
	rig.run(5.0)
	assert_eq(rig.hull().distance_m, d, "it stays")
	# A heavy shell clears it and the tank rolls again.
	TankShells.damage_obstacle(o, TankIds.SHELL_HEAVY, rig.content)
	assert_true(o.cleared)
	rig.run(10.0)
	assert_gt(rig.hull().distance_m, d + 20.0, "rolling again")
	assert_eq(rig.hull().blocked_by, 0)


func test_three_light_shells_clear_an_obstacle_and_two_do_not() -> void:
	var rig := TankRulesRig.new(1)
	var o := TankObstacleState.new()
	TankShells.damage_obstacle(o, TankIds.SHELL_LIGHT, rig.content)
	TankShells.damage_obstacle(o, TankIds.SHELL_LIGHT, rig.content)
	assert_false(o.cleared)
	TankShells.damage_obstacle(o, TankIds.SHELL_BOW, rig.content)
	assert_false(o.cleared, "a bow-gun round clears a barricade by time, not by hits (TankBow)")
	TankShells.damage_obstacle(o, TankIds.SHELL_LIGHT, rig.content)
	assert_true(o.cleared)
	var o2 := TankObstacleState.new()
	TankShells.damage_obstacle(o2, TankIds.SHELL_OVER, rig.content)
	assert_true(o2.cleared, "an Overpressure shell is heavy")


func test_the_advance_stops_at_the_halt_line_and_the_objective_is_met() -> void:
	var rig := TankRulesRig.new(
		1,
		"ashfall_road",
		7,
		_patch(ADVANCE, {"encounters": [], "obstacles": [], "terrain": [[0, -3]], "length_m": 200})
	)
	rig.enter(ADVANCE, 1.0)
	rig.run(60.0)
	assert_true(rig.state.seg.objective_done)
	assert_almost_eq(rig.hull().distance_m, 200.0, 0.01)
	assert_eq(rig.hull().speed_mps, 0.0)
	assert_true(rig.state.seg.regroup, "min_s (90 s) has not passed: Regroup")
	rig.run(40.0)
	assert_false(rig.state.seg.regroup, "after min_s the tank is free to be moved on")


# --- Evasive -------------------------------------------------------------------------------------


func _hits_of_shots(rig: TankRulesRig, n: int) -> int:
	var aux := TankAux.of(rig.state)
	var hits := 0
	var events: Array[Dictionary] = []
	for _i in n:
		rig.state.shells.clear()
		TankEnemies.launch(
			rig.state,
			aux,
			Vector2(600.0, 250.0),
			TankIds.SHELL_ENEMY,
			4.0,
			0.6,
			false,
			1,
			1,
			events
		)
		if rig.state.shells[0].will_hit:
			hits += 1
	return hits


func test_evasive_cuts_enemy_hit_chances_by_the_content_factor_while_the_driver_is_in_band(
) -> void:
	var rig := TankRulesRig.new(1)
	rig.enter(ADVANCE, 1.0)
	rig.run(1.0)
	assert_true(rig.hull().evasive, "in band at 90% FTP")
	var n := 4000
	var evasive := _hits_of_shots(rig, n)
	var mult := rig.content.num("tanks", "drive.evasive_hit_mult", 0.7)
	assert_almost_eq(float(evasive) / n, 0.6 * mult, 0.03)
	rig.hull().evasive = false
	var plain := _hits_of_shots(rig, n)
	assert_almost_eq(float(plain) / n, 0.6, 0.03)
	rig.power_w[1] = 100.0
	rig.run(1.0)
	assert_false(rig.hull().evasive, "out of band (50% FTP)")


# --- The sprint rule ---------------------------------------------------------------------------


func _sprint_rig(crew: int = 1) -> TankRulesRig:
	var rig := TankRulesRig.new(
		crew,
		"ashfall_road",
		7,
		_patch(ADVANCE, {"encounters": [], "obstacles": [], "terrain": [[0, 0]]})
	)
	rig.no_fire = true
	rig.enter(ADVANCE, 5.0)
	return rig


func _sprint(rig: TankRulesRig, seconds: float, mult: float = 1.5) -> void:
	for p in rig.slots:
		rig.power_w[p.peer_id] = mult * p.ftp
	rig.run(seconds)


func test_the_sprint_rule_is_the_trailing_3_second_average_at_1_2_ftp() -> void:
	var rig := _sprint_rig()
	_sprint(rig, 2.0, 1.5)
	assert_false(rig.diesel().sprinting, "not yet: the average over 3 s")
	rig.run(1.6)
	assert_true(rig.diesel().sprinting)
	_sprint(rig, 3.5, 1.15)
	assert_false(rig.diesel().sprinting, "1.15 x FTP is below 1.2 x")
	assert_false(rig.rider().sprinting)


# --- Dig in -------------------------------------------------------------------------------------


func _gun_line_rig(crew: int = 1) -> TankRulesRig:
	var rig := TankRulesRig.new(crew)
	rig.enter(GUN_LINE, 1.0)
	# No guns shoot: only the berm is under test.
	rig.state.enemies.clear()
	return rig


func test_dig_in_grows_the_berm_one_hp_per_250_joules_in_band() -> void:
	var rig := _gun_line_rig(2)
	# The diesel's ERG target is 90% of 200 W = 180 W; P_eff 250 W at FTP gives 225 W.
	rig.run(20.0)
	var want := 225.0 * 20.0 / 250.0
	assert_almost_eq(rig.hull().berm_hp, floorf(want), 1.01, "18 HP from 4.5 kJ")
	assert_true(rig.diesel().in_band)


func test_the_berm_stops_at_40_hp() -> void:
	var rig := _gun_line_rig(2)
	rig.run(80.0)
	assert_eq(rig.hull().berm_hp, 40.0)
	rig.run(10.0)
	assert_eq(rig.hull().berm_hp, 40.0)


func test_the_berm_only_grows_while_in_band_and_not_in_rescue() -> void:
	var rig := _gun_line_rig(2)
	rig.power_w[1] = 100.0
	rig.run(10.0)
	assert_eq(rig.hull().berm_hp, 0.0, "below 95% of the target: out of band")
	rig.power_w.erase(1)
	rig.rescue[1] = true
	rig.run(10.0)
	assert_eq(rig.hull().berm_hp, 0.0, "rescue: the berm stops growing")
	rig.rescue.erase(1)
	rig.run(5.0)
	assert_gt(rig.hull().berm_hp, 3.0)


func test_the_berm_absorbs_hits_before_the_hull() -> void:
	var rig := _gun_line_rig(2)
	rig.hull().berm_hp = 10.0
	var events: Array[Dictionary] = []
	var lost := TankHullRules.hit(rig.state, 4.0, TankIds.SHELL_ENEMY, 300.0, events)
	assert_eq(lost, 0.0)
	assert_eq(rig.hull().berm_hp, 6.0)
	assert_eq(rig.hull().hp, rig.hull().hp_max)
	lost = TankHullRules.hit(rig.state, 10.0, TankIds.SHELL_ENEMY, 300.0, events)
	assert_eq(lost, 4.0, "6 absorbed, 4 through")
	assert_eq(rig.hull().berm_hp, 0.0)
	assert_eq(rig.hull().hp, rig.hull().hp_max - 4.0)
	assert_eq(
		[events[1]["dmg"], events[1]["b"]],
		[10, 6],
		"the event keeps the round's damage and what the berm took"
	)
	assert_eq(rig.state.score.berm_absorbed, 10.0)
	assert_eq(rig.rider().berm_absorbed, 10.0, "credited to the digging rider")


func test_the_berm_clears_when_the_segment_ends() -> void:
	var rig := _gun_line_rig(2)
	rig.run(10.0)
	assert_gt(rig.hull().berm_hp, 0.0)
	rig.enter(3, 0.0)
	assert_eq(rig.hull().berm_hp, 0.0)


# --- Breakdown ---------------------------------------------------------------------------------


func test_zero_hp_is_a_breakdown_that_ignores_damage_until_5_kj_repair_it() -> void:
	var rig := _sprint_rig()
	rig.hull().hp = 5.0
	var events: Array[Dictionary] = []
	TankHullRules.hit(rig.state, 12.0, TankIds.SHELL_ENEMY, 300.0, events)
	assert_true(rig.hull().breakdown)
	assert_eq(rig.hull().hp, 0.0)
	assert_eq(rig.state.score.breakdowns, 1)
	assert_eq(events.back()["type"], "breakdown")
	rig.run(1.0)
	assert_eq(rig.hull().speed_mps, 0.0, "no movement")
	events.clear()
	TankHullRules.hit(rig.state, 12.0, TankIds.SHELL_ENEMY, 300.0, events)
	assert_eq(rig.hull().hp, 0.0, "damage ignored")
	assert_eq(events[0]["dmg"], 0, "a round that lands still raises a hit event with 0 damage")
	# 225 W P_eff: 5000 J take 22.2 s.
	rig.run(20.0)
	assert_true(rig.hull().breakdown)
	rig.run(3.0)
	assert_false(rig.hull().breakdown)
	assert_eq(rig.hull().hp, 40.0, "back with 40 HP")
	assert_eq(rig.of_type("repaired")[0]["hp"], 40)
	assert_eq(rig.state.score.breakdowns, 1)


func test_repair_time_is_12_to_30_seconds_across_the_p_eff_range() -> void:
	for w: float in [417.0, 250.0, 167.0]:
		var rig := _sprint_rig()
		rig.p_eff[1] = w
		rig.hull().hp = 1.0
		var events: Array[Dictionary] = []
		TankHullRules.hit(rig.state, 5.0, TankIds.SHELL_ENEMY, 0.0, events)
		var t := rig.run_until(func() -> bool: return not rig.hull().breakdown, 120.0)
		assert_almost_eq(t, 5000.0 / w, 0.2, "%d W" % w)


func test_the_repair_is_paid_by_the_reserve_when_the_driver_is_afk() -> void:
	var rig := _sprint_rig(2)
	rig.hull().hp = 1.0
	TankHullRules.hit(rig.state, 5.0, TankIds.SHELL_ENEMY, 0.0, [])
	rig.afk[1] = true
	rig.p_eff[2] = 60.0
	var t := rig.run_until(func() -> bool: return not rig.hull().breakdown, 200.0)
	assert_almost_eq(t, 5000.0 / 60.0, 0.5, "reserve P_eff is 60 W")


## v3: the crew works the repair: the mean P_eff of the manned seats, whatever seats they are.
func test_the_crew_pays_the_repair_with_its_mean_p_eff() -> void:
	var rig := _sprint_rig(2)
	rig.p_eff[1] = 300.0
	rig.p_eff[2] = 100.0
	rig.hull().hp = 1.0
	TankHullRules.hit(rig.state, 5.0, TankIds.SHELL_ENEMY, 0.0, [])
	var t := rig.run_until(func() -> bool: return not rig.hull().breakdown, 200.0)
	assert_almost_eq(t, 5000.0 / 200.0, 0.2, "(300 + 100) / 2 W")


# --- Reserve and all-AFK ------------------------------------------------------------------------


func test_an_afk_driver_runs_on_the_60_w_reserve_and_is_never_in_band() -> void:
	var rig := TankRulesRig.new(2, "ashfall_road", 7, _empty_advance(0.0))
	rig.enter(ADVANCE, 1.0)
	rig.afk[1] = true
	rig.run(80.0)
	assert_true(rig.diesel().reserve)
	assert_false(rig.diesel().in_band)
	assert_false(rig.rider(1).in_band)
	assert_eq(rig.diesel().p_eff_w, 60.0)
	assert_almost_eq(_driver_v(rig), SpeedModel.steady_state_speed(60.0, 0.0, 83.0, 0.5), 0.15)
	assert_false(rig.hull().evasive)


func test_a_dropped_rider_counts_as_afk() -> void:
	var rig := TankRulesRig.new(2, "ashfall_road", 7, _empty_advance(0.0))
	rig.enter(ADVANCE, 1.0)
	rig.connected[1] = false
	rig.run(1.0)
	assert_true(rig.rider(1).afk)
	assert_true(rig.diesel().reserve)
	assert_eq(rig.diesel().p_eff_w, 60.0)


func test_when_every_rider_is_afk_nothing_has_power() -> void:
	var rig := TankRulesRig.new(2)
	rig.enter(ADVANCE, 20.0)
	rig.load_shell(TankIds.SHELL_HEAVY)
	rig.spawn(TankIds.ENEMY_MEDIUM, 1, 250.0)
	rig.afk[1] = true
	rig.afk[2] = true
	rig.run(3.0)
	assert_true(rig.state.all_afk)
	assert_eq(rig.hull().speed_mps, 0.0, "no drive")
	for st in rig.state.stations:
		assert_eq(st.p_eff_w, 0.0)
		if not st.is_empty():
			assert_true(st.unpowered, "%s: a manned seat loses its power" % st.engine)
	var bank := rig.dynamo().bank
	rig.run(20.0)
	assert_eq(rig.dynamo().bank, bank, "the bank is frozen: no charge, no drain")
	assert_eq(
		rig.of_type("shot").filter(func(e: Dictionary) -> bool: return e["s"] >= 0).size(),
		0,
		"no gun fires"
	)
	assert_eq(rig.hull().loaded, TankIds.SHELL_HEAVY, "the loaded shell stays in the breech")


func test_when_every_rider_is_afk_the_bow_guns_stay_quiet_too() -> void:
	var rig := TankRulesRig.new(3)
	rig.enter(ADVANCE, 20.0)
	var e := rig.spawn(TankIds.ENEMY_LIGHT, 1, 130.0)
	e.hp = 500.0
	e.hp_max = 500.0
	for p in rig.slots:
		rig.afk[p.peer_id] = true
	rig.run(10.0)
	assert_true(rig.state.all_afk)
	assert_eq(e.hp, 500.0)
	var quiet := rig.of_type("shot").filter(func(s: Dictionary) -> bool: return s["s"] >= 0)
	assert_eq(quiet.size(), 0)
