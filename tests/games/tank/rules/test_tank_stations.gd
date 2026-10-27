extends GutTest
## The engine rooms (brief 2.4 Dynamo, Steam, Bulwark gearbox): the capacitor bank, the boiler and
## the three-way gearbox with its auto-lever.

const DEPOT := 0
const ADVANCE := 1
const GUN_LINE := 2
const CHECKPOINT := 3
const STAGE2_ADVANCE := 4


## A mission patch: segment `index` gets `props` merged in.
static func _patch(index: int, props: Dictionary) -> Callable:
	return func(files: Dictionary) -> void:
		(files["mission"]["segments"][index] as Dictionary).merge(props, true)


func _quiet(crew: int, index: int = ADVANCE, into_s: float = 5.0) -> TankRulesRig:
	var rig := TankRulesRig.new(
		crew, "ashfall_road", true, 7, _patch(index, {"encounters": [], "obstacles": []})
	)
	rig.enter(index, into_s)
	return rig


# --- Dynamo --------------------------------------------------------------------------------------


func test_the_bank_gains_one_unit_per_150_joules_of_p_eff_in_band() -> void:
	var rig := _quiet(2)
	var dy := rig.dynamo()
	assert_eq(dy.peer, 2)
	dy.bank = 40.0
	rig.run(10.0)
	assert_true(dy.in_band)
	# Slot 1's FTP is 220 W: 55% = 121 W, P_eff 137.5 W.
	assert_almost_eq(dy.bank, 40.0 + 137.5 * 10.0 / 150.0, 0.1)


func test_the_bank_does_not_charge_out_of_band_or_on_reserve() -> void:
	var rig := _quiet(2)
	var dy := rig.dynamo()
	dy.bank = 40.0
	rig.power_w[2] = 50.0
	rig.run(5.0)
	assert_false(dy.in_band)
	assert_eq(dy.bank, 40.0)
	rig.power_w.erase(2)
	rig.afk[2] = true
	rig.run(5.0)
	assert_eq(dy.bank, 40.0, "reserve is never in band")


func test_the_stabilizer_drains_1_5_units_a_second_while_an_enemy_is_in_range() -> void:
	var rig := _quiet(2)
	rig.no_fire = true
	var dy := rig.dynamo()
	dy.bank = 60.0
	rig.power_w[2] = 50.0
	rig.run(2.0)
	assert_eq(dy.bank, 60.0, "no enemy, no drain")
	rig.spawn(TankIds.ENEMY_MEDIUM, 1, 300.0)
	rig.run(10.0)
	assert_true(dy.stabilizing)
	var drain := TankStations.stabilizer_per_s(rig.state)
	assert_between(
		drain, 0.75, 2.25, "1.5 in the brief, +-50% (a long fight must not empty the bank)"
	)
	assert_almost_eq(dy.bank, 60.0 - drain * 10.0, 0.1)


func test_elevation_costs_half_a_unit_per_degree_and_runs_at_8_degrees_a_second() -> void:
	var rig := _quiet(2)
	var dy := rig.dynamo()
	dy.bank = 100.0
	rig.power_w[2] = 50.0
	rig.hull().elev_target_deg = 20.0
	rig.run(1.0)
	assert_almost_eq(rig.hull().elev_deg, 8.0, 0.25, "8 degrees/s at 50 units or more")
	rig.run(2.0)
	assert_almost_eq(rig.hull().elev_deg, 20.0, 0.01)
	assert_almost_eq(dy.bank, 100.0 - 0.5 * 20.0, 0.05)


func test_elevation_slows_linearly_to_2_degrees_a_second_at_an_empty_bank() -> void:
	var rows := {100.0: 8.0, 50.0: 8.0, 25.0: 5.0, 0.0: 2.0}
	for bank: float in rows:
		var rig := _quiet(2)
		rig.dynamo().bank = bank
		rig.power_w[2] = 50.0
		rig.hull().elev_target_deg = 30.0
		rig.run(1.0)
		# The bank pays while it moves, so allow for the speed dropping a little during the second.
		assert_almost_eq(rig.hull().elev_deg, rows[bank], 0.7, "bank %.0f" % bank)


func test_a_traverse_costs_15_units_and_takes_2_5_s_at_a_full_bank_8_s_at_empty() -> void:
	var rig := _quiet(2)
	var dy := rig.dynamo()
	dy.bank = 100.0
	rig.power_w[2] = 50.0
	assert_eq(rig.hull().facing, TankIds.FACE_RIGHT)
	rig.send(2, {"k": "traverse"})
	rig.run(0.1)
	assert_almost_eq(dy.bank, 85.0, 0.01)
	assert_almost_eq(rig.hull().traverse_s, 2.5 - 0.05, 0.06)
	rig.run(2.6)
	assert_eq(rig.hull().facing, TankIds.FACE_LEFT, "the facing flips when the traverse completes")
	assert_eq(rig.hull().traverse_s, 0.0)
	var empty := _quiet(2)
	empty.dynamo().bank = 0.0
	empty.power_w[2] = 50.0
	empty.send(2, {"k": "traverse"})
	empty.run(0.1)
	assert_almost_eq(empty.hull().traverse_s, 8.0 - 0.05, 0.06)
	var mid := _quiet(2)
	mid.dynamo().bank = 25.0
	mid.power_w[2] = 50.0
	mid.send(2, {"k": "traverse"})
	mid.run(0.1)
	assert_almost_eq(mid.hull().traverse_s, 5.25 - 0.05, 0.06, "linear between 0 and 50 units")


func test_the_rampart_hoist_time_follows_the_bank_and_it_costs_25() -> void:
	var hs: Array = _quiet(2).content.value("tanks", "dynamo.hoist_s", [20, 10])
	assert_between(float(hs[1]), 5.0, 15.0, "10 s in the brief, +-50%")
	assert_between(float(hs[0]), 10.0, 30.0, "20 s in the brief, +-50%")
	var mid := (float(hs[0]) + float(hs[1])) / 2.0
	for row: Array in [[100.0, hs[1]], [50.0, hs[1]], [0.0, hs[0]], [25.0, mid]]:
		var rig := _quiet(2)
		rig.power_w[2] = 50.0
		rig.spawn(TankIds.ENEMY_MEDIUM, 1, 300.0)
		rig.dynamo().bank = float(row[0])
		rig.no_fire = false
		rig.state.hull.loaded = TankIds.SHELL_NONE
		rig.run(0.2)
		assert_almost_eq(rig.dynamo().hoist_s, float(row[1]) - 0.2, 0.1, "bank %.0f" % row[0])
		assert_almost_eq(
			rig.dynamo().bank,
			maxf(float(row[0]) - 25.0 - 1.5 * 0.2, 0.0),
			0.5,
			"25 units for the hoist"
		)


func test_the_hoist_lifts_a_heavy_shell_and_never_starts_without_a_target() -> void:
	var rig := _quiet(2)
	rig.power_w[2] = 50.0
	rig.no_fire = false
	rig.run(3.0)
	assert_eq(rig.dynamo().hoist_s, 0.0, "no target, no hoist")
	rig.spawn(TankIds.ENEMY_MEDIUM, 1, 300.0)
	rig.dynamo().bank = 100.0
	var fast := float(rig.content.value("tanks", "dynamo.hoist_s", [20, 10])[1])
	rig.run(fast + 0.5)
	assert_ne(rig.hull().loaded, TankIds.SHELL_NONE, "a shell is up after the fast hoist time")
	assert_eq(rig.of_type("latch").size() + rig.of_type("shot").size() > 0, true)


func test_the_hoist_waits_for_the_breech_cycle() -> void:
	var rig := _quiet(2)
	rig.power_w[2] = 50.0
	rig.no_fire = false
	rig.spawn(TankIds.ENEMY_MEDIUM, 1, 300.0)
	rig.hull().breech_s = 6.0
	rig.run(3.0)
	assert_eq(rig.dynamo().hoist_s, 0.0)
	rig.run(3.5)
	assert_gt(rig.dynamo().hoist_s, 0.0, "after the 6 s cycle")


func test_the_depot_fills_the_bank_on_a_script() -> void:
	var rig := TankRulesRig.new(2)
	rig.enter(DEPOT, 5.0)
	rig.dynamo().bank = 10.0
	rig.run(0.2)
	assert_eq(rig.dynamo().bank, 100.0)


func test_rescue_stalls_the_dynamo_the_turret_freezes_and_the_bank_holds() -> void:
	var rig := _quiet(2)
	var dy := rig.dynamo()
	dy.bank = 50.0
	rig.rescue[2] = true
	rig.hull().elev_target_deg = 10.0
	rig.spawn(TankIds.ENEMY_MEDIUM, 1, 300.0)
	rig.run(5.0)
	assert_true(dy.stalled)
	assert_eq(dy.bank, 50.0, "not charging, not draining")
	assert_eq(rig.hull().elev_deg, 0.0, "turret frozen")
	rig.send(2, {"k": "traverse"})
	rig.run(1.0)
	assert_eq(rig.hull().traverse_s, 0.0)
	rig.rescue[2] = false
	rig.run(1.0)
	assert_false(dy.stalled)


func test_the_citadel_secondaries_cost_2_units_and_stop_below_10() -> void:
	var rig := _quiet(3)
	rig.no_fire = false
	rig.power_w[2] = 50.0
	var dy := rig.dynamo()
	dy.bank = 12.0
	var e := rig.spawn(TankIds.ENEMY_MEDIUM, 1, 120.0)
	e.hp = 1000.0
	e.hp_max = 1000.0
	rig.run(0.1)
	var shots := rig.of_type("shot").filter(
		func(x: Dictionary) -> bool: return x["sh"] == TankIds.SHELL_BOW
	)
	assert_eq(shots.size(), 1, "the fore secondary fires at once")
	assert_almost_eq(dy.bank, 10.0 - 1.5 * 0.1 + 0.0, 0.3)
	rig.run(9.0)
	shots = rig.of_type("shot").filter(
		func(x: Dictionary) -> bool: return x["sh"] == TankIds.SHELL_BOW
	)
	assert_eq(shots.size(), 1, "below 10 units they stop")


# --- Steam ---------------------------------------------------------------------------------------


func test_pressure_is_the_boilers_energy_in_joules_of_p_eff_per_100_percent() -> void:
	var rig := _quiet(3)
	var st := rig.steam()
	assert_eq(st.peer, 3)
	var full_j := rig.content.num("tanks", "steam.full_j")
	assert_eq(full_j, 4000.0, "6 kJ in the brief, tuned to 4 kJ (P4 rules ADR)")
	st.pressure_pct = 0.0
	rig.run(full_j / 225.0 / 2.0)
	# Slot 2: FTP 240 W, 90% = 216 W raw, P_eff 225 W: half the energy in half the time.
	assert_almost_eq(st.pressure_pct, 50.0, 1.5)


func test_at_100_percent_the_boiler_holds_for_a_5_second_window_then_latches_a_heavy_shell(
) -> void:
	var rig := _quiet(3)
	var st := rig.steam()
	st.pressure_pct = 99.9
	rig.run(0.3)
	assert_eq(st.pressure_pct, 100.0)
	assert_almost_eq(st.window_s, 4.75, 0.06, "5 s from the first tick at 100%")
	assert_eq(rig.hull().loaded, TankIds.SHELL_NONE)
	rig.run(4.5)
	assert_eq(rig.hull().loaded, TankIds.SHELL_NONE, "still inside the window")
	assert_eq(st.pressure_pct, 100.0, "the boiler holds")
	rig.run(0.8)
	assert_eq(rig.hull().loaded, TankIds.SHELL_HEAVY)
	assert_eq(st.pressure_pct, 0.0)
	assert_true(st.loaded)
	var latch := rig.of_type("latch")
	assert_eq([latch[0]["s"], latch[0]["sh"]], [2, TankIds.SHELL_HEAVY])


func test_pressure_cannot_build_while_a_shell_is_loaded_or_the_breech_cycles() -> void:
	var rig := _quiet(3)
	var st := rig.steam()
	rig.load_shell(TankIds.SHELL_HEAVY)
	st.pressure_pct = 0.0
	rig.run(5.0)
	assert_eq(st.pressure_pct, 0.0, "loaded")
	rig.hull().loaded = TankIds.SHELL_NONE
	rig.hull().breech_s = 6.0
	rig.run(5.5)
	assert_eq(st.pressure_pct, 0.0, "the 6 s breech cycle")
	rig.run(1.0)
	rig.run(2.0)
	assert_gt(st.pressure_pct, 5.0, "building again")


func test_warmup_phases_and_the_first_300_seconds_have_no_window() -> void:
	var depot := _quiet(3, DEPOT, 100.0)
	depot.steam().pressure_pct = 99.9
	depot.run(0.3)
	assert_eq(depot.hull().loaded, TankIds.SHELL_HEAVY, "the shell latches at 100% at once")
	assert_eq(depot.steam().window_s, 0.0)
	var early := _quiet(3)
	early.plan_t = 250.0
	early.steam().pressure_pct = 99.9
	early.run(0.3)
	assert_eq(early.hull().loaded, TankIds.SHELL_HEAVY, "plan_elapsed_s < 300")
	var late := _quiet(3)
	late.plan_t = 301.0
	late.steam().pressure_pct = 99.9
	late.run(0.3)
	assert_eq(late.hull().loaded, TankIds.SHELL_NONE)
	assert_gt(late.steam().window_s, 0.0)


func test_confirm_at_40_percent_latches_a_light_shell() -> void:
	var rig := _quiet(3)
	var st := rig.steam()
	st.pressure_pct = 39.0
	rig.send(3, {"k": "latch"})
	rig.run(0.1)
	assert_eq(rig.hull().loaded, TankIds.SHELL_NONE, "39% is too low")
	st.pressure_pct = 45.0
	rig.send(3, {"k": "latch"})
	rig.run(0.1)
	assert_eq(rig.hull().loaded, TankIds.SHELL_LIGHT)
	assert_eq(st.pressure_pct, 0.0)


func test_a_latch_inside_the_window_is_a_heavy_shell_now() -> void:
	var rig := _quiet(3)
	var st := rig.steam()
	st.pressure_pct = 99.9
	rig.run(1.0)
	assert_gt(st.window_s, 0.0)
	rig.send(3, {"k": "latch"})
	rig.run(0.1)
	assert_eq(rig.hull().loaded, TankIds.SHELL_HEAVY)


func test_checkpoints_hold_pressure_it_neither_builds_nor_bleeds() -> void:
	var rig := TankRulesRig.new(3)
	rig.enter(CHECKPOINT, 2.0)
	var st := rig.steam()
	st.pressure_pct = 50.0
	rig.run(20.0)
	assert_eq(st.pressure_pct, 50.0)


func test_the_cooldown_holds_pressure_too_no_shell_is_built_with_nothing_to_shoot() -> void:
	var rig := TankRulesRig.new(3)
	rig.enter(rig.segs().size(), 2.0)
	assert_true(rig.in_cooldown())
	var st := rig.steam()
	st.pressure_pct = 50.0
	rig.run(60.0)
	assert_eq(st.pressure_pct, 50.0)
	assert_eq(rig.hull().loaded, TankIds.SHELL_NONE)


func _over_rig() -> TankRulesRig:
	var rig := _quiet(3)
	rig.plan_t = 400.0
	rig.steam().pressure_pct = 99.9
	rig.run(0.5)
	assert_gt(rig.steam().window_s, 0.0, "the window is open")
	return rig


func test_overpressure_builds_100_to_150_percent_on_3_kj_while_the_sprint_holds() -> void:
	var rig := _over_rig()
	var st := rig.steam()
	# Slot 2: 1.5 x FTP = 360 W, P_eff 375 W; the sprint rule needs a 3 s window first.
	rig.power_w[3] = 360.0
	rig.run(3.5)
	assert_true(st.sprinting)
	rig.send(3, {"k": "over", "via": "surge"})
	rig.run(0.1)
	assert_true(st.over)
	assert_eq(st.window_s, 0.0)
	var start := st.pressure_pct
	rig.run(3.9)
	# 4 s x 375 W = 1.5 kJ of 3 kJ: halfway to 150%.
	assert_almost_eq(st.pressure_pct, 125.0, 3.0, "start %.0f" % start)
	rig.run(5.0)
	assert_eq(rig.hull().loaded, TankIds.SHELL_OVER, "latched at 150% as an Overpressure shell")
	assert_eq(st.pressure_pct, 0.0)


func test_overpressure_bleeds_2_percent_a_second_without_the_sprint() -> void:
	var rig := _over_rig()
	var st := rig.steam()
	rig.power_w[3] = 360.0
	rig.run(3.5)
	rig.send(3, {"k": "over"})
	rig.run(2.0)
	var high := st.pressure_pct
	assert_gt(high, 100.0)
	rig.power_w[3] = 150.0
	rig.run(8.0)
	assert_false(st.sprinting)
	assert_almost_eq(st.pressure_pct, maxf(high - 0.1 * 0.0 - 2.0 * 8.0 - 2.0 * 0.0, 100.0), 6.0)
	rig.run(30.0)
	assert_eq(
		rig.hull().loaded,
		TankIds.SHELL_HEAVY,
		"30 s in the build latches what it has as a heavy shell"
	)


func test_below_150_percent_after_30_seconds_the_shell_is_heavy() -> void:
	var rig := _over_rig()
	var st := rig.steam()
	rig.power_w[3] = 360.0
	rig.run(3.5)
	rig.send(3, {"k": "over"})
	rig.run(0.1)
	st.over_s = 29.9
	st.pressure_pct = 120.0
	rig.power_w[3] = 100.0
	rig.run(0.3)
	assert_eq(rig.hull().loaded, TankIds.SHELL_HEAVY)


func test_overpressure_needs_the_window_and_does_nothing_outside_it() -> void:
	var rig := _quiet(3)
	rig.plan_t = 400.0
	rig.power_w[3] = 360.0
	rig.run(3.5)
	rig.send(3, {"k": "over"})
	rig.run(0.2)
	assert_false(rig.steam().over, "no window")


func test_overpressure_does_nothing_in_the_warmup_or_the_first_300_seconds() -> void:
	var rig := _quiet(3)
	rig.plan_t = 250.0
	rig.steam().window_s = 4.0
	rig.steam().pressure_pct = 100.0
	rig.power_w[3] = 360.0
	rig.run(3.5)
	rig.send(3, {"k": "over"})
	rig.run(0.2)
	assert_false(rig.steam().over)
	var depot := _quiet(3, DEPOT, 100.0)
	depot.steam().window_s = 4.0
	depot.steam().pressure_pct = 100.0
	depot.power_w[3] = 360.0
	depot.run(3.5)
	depot.send(3, {"k": "over"})
	depot.run(0.2)
	assert_false(depot.steam().over)


func test_steam_on_reserve_builds_at_60_watts_and_all_afk_freezes_it() -> void:
	var rig := _quiet(3)
	var st := rig.steam()
	rig.afk[3] = true
	rig.run(10.0)
	var want := 600.0 / rig.content.num("tanks", "steam.full_j") * 100.0
	assert_almost_eq(st.pressure_pct, want, 0.6, "60 W x 10 s = 600 J")
	assert_false(st.in_band)
	rig.afk[1] = true
	rig.afk[2] = true
	var p := st.pressure_pct
	rig.run(5.0)
	assert_eq(st.pressure_pct, p, "every rider AFK: the pressure freezes")


# --- Bulwark gearbox -------------------------------------------------------------------------------


func _bulwark(index: int = ADVANCE, into_s: float = 5.0) -> TankRulesRig:
	var rig := _quiet(1, index, into_s)
	var g := rig.gearbox()
	g.auto = false
	g.suspend_s = 1.0e9
	return rig


## Moves the lever by hand to `to` ("hoist", "turret", "drive") and keeps the auto-lever off.
func _lever(rig: TankRulesRig, to: String) -> void:
	rig.send(1, {"k": "lever", "to": to})
	rig.run(1.2)
	rig.gearbox().auto = false
	rig.gearbox().suspend_s = 1.0e9


func test_a_lever_move_takes_1_s_with_no_power_anywhere() -> void:
	var rig := _bulwark()
	var g := rig.gearbox()
	rig.send(1, {"k": "lever", "to": "hoist"})
	rig.run(0.1)
	assert_eq(g.lever, TankIds.LEVER_DRIVE, "still on Drive while it moves")
	assert_eq(g.lever_to, TankIds.LEVER_HOIST)
	assert_almost_eq(g.move_s, 0.95, 0.06)
	assert_eq(g.p_eff_w, 0.0, "no power during a move")
	var hoist := g.hoist_j
	rig.run(0.8)
	assert_eq(g.hoist_j, hoist)
	rig.run(0.3)
	assert_eq(g.lever, TankIds.LEVER_HOIST)
	assert_eq(g.move_s, 0.0)
	assert_eq(rig.of_type("lever")[0]["lv"], TankIds.LEVER_HOIST)
	rig.run(1.0)
	assert_gt(g.hoist_j, 100.0, "now the hoist gets the power")


func test_the_tank_coasts_while_the_lever_is_off_drive() -> void:
	var rig := _bulwark()
	rig.run(40.0)
	var v := rig.hull().speed_mps
	assert_gt(v, 6.0)
	rig.send(1, {"k": "lever", "to": "turret"})
	rig.run(1.2)
	var coast := rig.hull().speed_mps
	assert_lt(coast, v, "no drive power: it slows")
	assert_gt(coast, v - 1.0, "but coasts")


func test_swap_cycles_and_left_right_step_the_lever() -> void:
	var rig := _bulwark()
	var g := rig.gearbox()
	var seen: Array[int] = []
	for _i in 4:
		rig.send(1, {"k": "lever", "to": "next", "via": "action"})
		rig.run(1.2)
		seen.append(g.lever)
	assert_eq(
		seen, [TankIds.LEVER_TURRET, TankIds.LEVER_HOIST, TankIds.LEVER_DRIVE, TankIds.LEVER_TURRET]
	)
	rig.send(1, {"k": "lever", "to": "left"})
	rig.run(1.2)
	assert_eq(g.lever, TankIds.LEVER_DRIVE)
	rig.send(1, {"k": "lever", "to": "right"})
	rig.run(1.2)
	assert_eq(g.lever, TankIds.LEVER_TURRET)
	rig.send(1, {"k": "lever", "to": "right"})
	rig.run(1.2)
	rig.send(1, {"k": "lever", "to": "right"})
	rig.run(1.2)
	assert_eq(g.lever, TankIds.LEVER_DRIVE, "right wraps")


func test_hoist_lifts_a_heavy_shell_on_the_hoist_energy() -> void:
	var rig := _bulwark()
	var g := rig.gearbox()
	var full := rig.content.num("tanks", "gearbox.hoist_j")
	assert_between(full, 2000.0, 6000.0, "4 kJ in the brief, +-50%")
	_lever(rig, "hoist")
	g.hoist_j = 0.0
	var secs := full / 225.0
	rig.run(secs - 0.5)
	assert_eq(rig.hull().loaded, TankIds.SHELL_NONE, "225 W for a little under the time")
	rig.run(1.0)
	assert_eq(rig.hull().loaded, TankIds.SHELL_HEAVY)
	assert_eq(g.hoist_j, 0.0)


func test_confirm_at_40_percent_of_the_hoist_latches_a_light_shell() -> void:
	var rig := _bulwark()
	var g := rig.gearbox()
	var full := rig.content.num("tanks", "gearbox.hoist_j")
	g.hoist_j = 0.39 * full
	rig.send(1, {"k": "latch"})
	rig.run(0.1)
	assert_eq(rig.hull().loaded, TankIds.SHELL_NONE, "under 40%")
	g.hoist_j = 0.42 * full
	rig.send(1, {"k": "latch"})
	rig.run(0.1)
	assert_eq(rig.hull().loaded, TankIds.SHELL_LIGHT)
	assert_eq(g.hoist_j, 0.0)


func test_the_turret_slews_at_full_speed_from_200_w_and_linearly_below() -> void:
	for row: Array in [[300.0, 8.0], [200.0, 8.0], [100.0, 4.0], [0.0, 0.0]]:
		var rig := _bulwark()
		rig.send(1, {"k": "lever", "to": "turret"})
		rig.run(1.2)
		rig.p_eff[1] = float(row[0])
		rig.hull().elev_target_deg = 30.0
		rig.hull().aim_pause_s = 10.0
		rig.run(1.0)
		assert_almost_eq(rig.hull().elev_deg, float(row[1]), 0.3, "P_eff %.0f W" % row[0])


func test_a_traverse_takes_the_bulwark_2_5_s_at_full_turret_speed() -> void:
	var rig := _bulwark()
	_lever(rig, "turret")
	rig.send(1, {"k": "traverse"})
	rig.run(0.1)
	assert_almost_eq(rig.hull().traverse_s, 2.45, 0.06)
	rig.run(2.6)
	assert_eq(rig.hull().facing, TankIds.FACE_LEFT)


func test_a_traverse_needs_the_lever_on_turret() -> void:
	var rig := _bulwark()
	rig.send(1, {"k": "traverse"})
	rig.run(0.5)
	assert_eq(rig.hull().traverse_s, 0.0)


func test_a_manual_move_suspends_the_auto_lever_for_15_seconds() -> void:
	var rig := _quiet(1)
	var g := rig.gearbox()
	g.auto = true
	rig.send(1, {"k": "lever", "to": "turret"})
	rig.run(0.1)
	assert_false(g.auto)
	assert_almost_eq(g.suspend_s, 15.0, 0.1)
	rig.run(14.0)
	assert_false(g.auto)
	rig.run(1.2)
	assert_true(g.auto, "back after 15 s")


func test_the_auto_lever_drives_in_an_advance_when_nothing_is_near() -> void:
	var rig := _quiet(1)
	var g := rig.gearbox()
	g.lever = TankIds.LEVER_HOIST
	g.lever_to = TankIds.LEVER_HOIST
	g.auto = true
	g.dwell_s = 0.0
	rig.run(2.5)
	assert_eq(g.lever, TankIds.LEVER_HOIST, "dwell of 3 s")
	rig.run(1.0)
	assert_eq(g.lever_to, TankIds.LEVER_DRIVE)
	rig.run(1.2)
	assert_eq(g.lever, TankIds.LEVER_DRIVE)


func test_the_auto_lever_hoists_when_unloaded_with_a_target_in_range() -> void:
	var rig := _quiet(1)
	var g := rig.gearbox()
	g.auto = true
	g.dwell_s = 5.0
	rig.spawn(TankIds.ENEMY_MEDIUM, 1, 280.0)
	rig.run(1.3)
	assert_eq(g.lever_to, TankIds.LEVER_HOIST)


func test_the_auto_lever_turns_the_turret_when_loaded_and_off_target() -> void:
	var rig := _quiet(1)
	var g := rig.gearbox()
	g.auto = true
	g.dwell_s = 5.0
	rig.spawn(TankIds.ENEMY_MEDIUM, 1, 280.0)
	rig.load_shell(TankIds.SHELL_HEAVY)
	rig.run(1.3)
	assert_eq(g.lever_to, TankIds.LEVER_TURRET)


func test_the_auto_lever_stays_put_inside_its_dwell() -> void:
	var rig := _quiet(1)
	var g := rig.gearbox()
	g.auto = true
	g.dwell_s = 0.0
	rig.spawn(TankIds.ENEMY_MEDIUM, 1, 280.0)
	rig.run(2.0)
	assert_eq(g.lever_to, TankIds.LEVER_DRIVE, "dwell >= 3 s before the first auto move")


func test_a_breakdown_forces_drive() -> void:
	var rig := _bulwark()
	var g := rig.gearbox()
	rig.send(1, {"k": "lever", "to": "hoist"})
	rig.run(1.2)
	assert_eq(g.lever, TankIds.LEVER_HOIST)
	rig.hull().hp = 1.0
	TankHullRules.hit(rig.state, 5.0, TankIds.SHELL_ENEMY, 0.0, [])
	rig.run(0.1)
	assert_eq(g.lever, TankIds.LEVER_DRIVE)
	assert_eq(g.move_s, 0.0)
	rig.send(1, {"k": "lever", "to": "turret"})
	rig.run(0.5)
	assert_eq(g.lever, TankIds.LEVER_DRIVE, "no manual move while broken down")


func test_in_a_gun_line_drive_is_dig_and_only_it_raises_the_berm() -> void:
	var rig := _bulwark(GUN_LINE, 1.0)
	rig.state.enemies.clear()
	rig.run(10.0)
	assert_gt(rig.hull().berm_hp, 6.0)
	var berm := rig.hull().berm_hp
	rig.send(1, {"k": "lever", "to": "turret"})
	rig.run(5.0)
	assert_lte(rig.hull().berm_hp, berm + 1.0, "the dozer waits while the lever is elsewhere")


func test_in_a_gun_line_the_hoist_lifts_on_the_riders_erg_work() -> void:
	var rig := _bulwark(GUN_LINE, 1.0)
	rig.state.enemies.clear()
	_lever(rig, "hoist")
	rig.gearbox().hoist_j = 0.0
	var need := rig.content.num("tanks", "gearbox.hoist_j")
	assert_between(need, 2000.0, 6000.0, "4 kJ in the brief, tuned to 5.25 kJ (P4 rules ADR)")
	# ERG 90% of 200 W = 180 W raw, P_eff 225 W.
	rig.run(need / 225.0 - 1.0)
	assert_eq(rig.hull().loaded, TankIds.SHELL_NONE, "not before the hoist energy is in")
	rig.run(2.0)
	assert_eq(rig.hull().loaded, TankIds.SHELL_HEAVY)


func test_rescue_in_a_gun_line_powers_nothing_for_the_bulwark() -> void:
	var rig := _bulwark(GUN_LINE, 1.0)
	rig.state.enemies.clear()
	rig.rescue[1] = true
	rig.run(10.0)
	assert_eq(rig.hull().berm_hp, 0.0)
	assert_eq(rig.gearbox().p_eff_w, 0.0)
	rig.send(1, {"k": "lever", "to": "hoist"})
	rig.run(4.0)
	assert_eq(rig.gearbox().hoist_j, 0.0, "nothing gets power")


func test_a_solo_bulwark_that_goes_afk_has_no_power_at_all() -> void:
	var rig := _bulwark()
	_lever(rig, "hoist")
	rig.gearbox().hoist_j = 0.0
	rig.afk[1] = true
	rig.run(10.0)
	assert_true(rig.state.all_afk, "the only rider is the whole crew")
	assert_eq(rig.gearbox().hoist_j, 0.0)
	assert_eq(rig.gearbox().p_eff_w, 0.0)
