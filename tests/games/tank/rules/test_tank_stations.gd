extends GutTest
## The seats' machines (brief 2.4 Dynamo, Steam; v3): the Gun's capacitor bank, the Loader's ready
## rack (a shell per steam.full_j of P_eff in band, the rack of 3, Overpressure, the light latch)
## and the Gun chambering from the rack. (v3 retired the gearbox and the gunner's hoist.)

const DEPOT := 0
const ADVANCE := 1
const GUN_LINE := 2
const CHECKPOINT := 3
const STAGE2_ADVANCE := 4


## A mission patch: segment `index` gets `props` merged in.
static func _patch(index: int, props: Dictionary) -> Callable:
	return func(files: Dictionary) -> void:
		(files["mission"]["segments"][index] as Dictionary).merge(props, true)


## A rig with nothing in the field and an empty rack (nothing to chamber, so the gun only moves
## when a test moves it).
func _quiet(crew: int, index: int = ADVANCE, into_s: float = 5.0) -> TankRulesRig:
	var rig := TankRulesRig.new(
		crew, "ashfall_road", 7, _patch(index, {"encounters": [], "obstacles": []})
	)
	rig.enter(index, into_s)
	rig.set_rack(0)
	return rig


# --- Dynamo --------------------------------------------------------------------------------------


func test_the_bank_gains_one_unit_per_j_per_unit_joules_of_p_eff_in_band() -> void:
	var rig := _quiet(2)
	var dy := rig.dynamo()
	assert_eq(dy.peer, 2)
	dy.bank = 40.0
	rig.run(10.0)
	assert_true(dy.in_band)
	# Slot 1's FTP is 220 W: 55% = 121 W, P_eff 137.5 W.
	var joules := rig.content.num("tanks", "dynamo.j_per_unit", 0.0)
	assert_between(joules, 100.0, 225.0, "150 at the start, tuned inside +-50%")
	assert_almost_eq(dy.bank, 40.0 + 137.5 * 10.0 / joules, 0.1)


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
	# The medium's hold is clamped to the screen, inside the bow guns' 220 px on the v3 hull.
	rig.no_bow = true
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
	rig.hull().elev_deg = 0.0
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
		rig.hull().elev_deg = 0.0
		rig.hull().elev_target_deg = 30.0
		rig.run(1.0)
		# The bank pays while it moves, so allow for the speed dropping a little during the second.
		assert_almost_eq(rig.hull().elev_deg, rows[bank], 0.7, "bank %.0f" % bank)


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
	rig.hull().elev_deg = 0.0
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


# --- Loader (steam): the ready rack ----------------------------------------------------------------


## Crew 3 in Stage 1's Advance with nothing in the field: the Loader is peer 3 (FTP 240: 216 W
## raw, P_eff 225 W), a round chambered (so the Gun takes nothing from the rack) and the rack at
## `rack`.
func _loader(rack: int = 0, index: int = ADVANCE, into_s: float = 5.0) -> TankRulesRig:
	var rig := _quiet(3, index, into_s)
	rig.load_shell(TankIds.SHELL_HEAVY)
	rig.set_rack(rack)
	rig.steam().pressure_pct = 0.0
	return rig


func test_a_shell_is_full_j_of_p_eff_in_band_about_7_s_at_250_w() -> void:
	var rig := _loader()
	var st := rig.steam()
	assert_eq(st.peer, 3)
	var full_j := rig.content.num("tanks", "steam.full_j")
	assert_between(full_j / 250.0, 6.5, 7.5, "about 7 s a shell at 250 W")
	rig.run(full_j / 225.0 / 2.0)
	assert_almost_eq(st.pressure_pct, 50.0, 1.5, "half the energy, half the shell")
	assert_almost_eq(st.load_t, 0.5, 0.015)
	rig.run(full_j / 225.0 / 2.0 + 0.1)
	assert_eq(st.rack, 1, "stowed in the rack")
	var latch := rig.of_type("latch")
	assert_eq([latch[0]["s"], latch[0]["sh"]], [2, TankIds.SHELL_HEAVY])
	assert_lt(st.pressure_pct, 10.0, "the next shell begins")


func test_the_rack_fills_to_three_and_then_the_loader_idles() -> void:
	var rig := _loader()
	var st := rig.steam()
	var full_j := rig.content.num("tanks", "steam.full_j")
	rig.run(4.0 * full_j / 225.0)
	assert_eq(st.rack, TankConst.RACK_MAX)
	assert_eq(rig.of_type("latch").size(), TankConst.RACK_MAX)
	assert_true(st.loaded, "idle: the rack is full")
	assert_eq(st.pressure_pct, 0.0, "nothing builds")
	assert_eq(st.load_t, 0.0)
	rig.set_rack(2)
	rig.run(0.1)
	assert_false(st.loaded, "room again: loading")
	assert_gt(st.pressure_pct, 0.0)


func test_only_p_eff_in_band_loads_and_the_reserve_loads_at_60_w() -> void:
	var rig := _loader()
	var st := rig.steam()
	rig.power_w[3] = 0.8 * 240.0
	rig.run(5.0)
	assert_false(st.in_band, "under 90% FTP")
	assert_eq(st.pressure_pct, 0.0, "nothing loads under band")
	rig.power_w.erase(3)
	rig.afk[3] = true
	rig.run(10.0)
	var want := 600.0 / rig.content.num("tanks", "steam.full_j") * 100.0
	assert_almost_eq(st.pressure_pct, want, 0.6, "on reserve: 60 W x 10 s = 600 J")
	rig.afk[1] = true
	rig.afk[2] = true
	var p := st.pressure_pct
	rig.run(5.0)
	assert_eq(st.pressure_pct, p, "every rider AFK: the boiler freezes")


func test_checkpoints_and_the_cooldown_hold_pressure() -> void:
	var rig := _loader(0, CHECKPOINT, 2.0)
	rig.steam().pressure_pct = 50.0
	rig.run(20.0)
	assert_eq(rig.steam().pressure_pct, 50.0, "a checkpoint")
	var cd := _loader(0, 4, 2.0)
	cd.enter(cd.segs().size(), 2.0)
	cd.set_rack(0)
	assert_true(cd.in_cooldown())
	cd.steam().pressure_pct = 50.0
	cd.run(30.0)
	assert_eq(cd.steam().pressure_pct, 50.0, "the cool-down")
	assert_eq(cd.steam().rack, 0)


func test_the_light_latch_stows_a_light_shell_from_40_percent() -> void:
	var rig := _loader(1)
	var st := rig.steam()
	st.pressure_pct = 30.0
	rig.send(3, {"k": "latch"})
	rig.run(0.1)
	assert_eq(st.rack, 1, "too low")
	st.pressure_pct = 45.0
	rig.send(3, {"k": "latch"})
	rig.run(0.1)
	assert_eq(st.rack, 2)
	assert_eq(TankAux.of(rig.state).rack_types, [TankIds.SHELL_HEAVY, TankIds.SHELL_LIGHT])
	assert_lt(st.pressure_pct, 2.0, "the next shell begins")


func test_the_window_opens_on_a_stowed_shell_past_300_s_only() -> void:
	var late := _loader(1)
	late.plan_t = 400.0
	late.steam().pressure_pct = 99.9
	late.run(0.3)
	assert_eq(late.steam().rack, 2, "stowed at once: the window holds nothing back")
	assert_almost_eq(late.steam().window_s, 4.75, 0.06)
	var early := _loader(1)
	early.plan_t = 250.0
	early.steam().pressure_pct = 99.9
	early.run(0.3)
	assert_eq(early.steam().window_s, 0.0, "plan_elapsed_s < 300")
	var depot := _loader(1, DEPOT, 100.0)
	depot.steam().pressure_pct = 99.9
	depot.run(0.3)
	assert_eq(depot.steam().rack, 2)
	assert_eq(depot.steam().window_s, 0.0, "the warm-up")


## A Loader 400 s into its plan with a shell just stowed (the window open) and the sprint held.
func _over_rig() -> TankRulesRig:
	var rig := _loader(1)
	rig.plan_t = 400.0
	rig.power_w[3] = 360.0
	rig.run(3.5)
	rig.steam().pressure_pct = 99.99
	rig.run(0.1)
	assert_eq(rig.steam().rack, 2)
	assert_gt(rig.steam().window_s, 0.0, "the window is open")
	return rig


func test_overpressure_takes_the_stowed_shell_back_and_builds_it_to_150() -> void:
	var rig := _over_rig()
	var st := rig.steam()
	var carry := st.pressure_pct
	rig.send(3, {"k": "over", "via": "surge"})
	rig.run(0.05)
	assert_true(st.over)
	assert_eq(st.rack, 1, "the shell is back at the boiler")
	assert_eq(st.window_s, 0.0)
	assert_almost_eq(st.pressure_pct, 100.0, 1.0)
	# 1.5 x FTP = 360 W raw, P_eff 375 W: over_j (75% of a shell's full_j, v2's ratio) in 3.5 s.
	var over_j := rig.content.num("tanks", "steam.over_j")
	assert_almost_eq(over_j, 0.75 * rig.content.num("tanks", "steam.full_j"), 20.0)
	rig.run(over_j / 375.0 / 2.0 - 0.05)
	assert_almost_eq(st.pressure_pct, 125.0, 3.0)
	rig.run(over_j / 375.0 / 2.0 + 1.0)
	assert_false(st.over)
	assert_eq(st.rack, 2)
	assert_eq(TankAux.of(rig.state).rack_types.back(), TankIds.SHELL_OVER)
	assert_eq(rig.of_type("latch").back()["sh"], TankIds.SHELL_OVER)
	assert_gte(st.pressure_pct, carry, "the next shell's progress came back and builds on")


func test_overpressure_bleeds_without_the_sprint_and_ends_heavy_after_30_s() -> void:
	var rig := _over_rig()
	var st := rig.steam()
	rig.send(3, {"k": "over"})
	rig.run(1.0)
	assert_gt(st.pressure_pct, 100.0)
	rig.power_w[3] = 230.0
	rig.run(4.0)
	assert_false(st.sprinting)
	var high := st.pressure_pct
	assert_lt(high, 150.0)
	rig.run(4.0)
	assert_lt(st.pressure_pct, high, "it bleeds")
	rig.run(25.0)
	assert_false(st.over)
	assert_eq(TankAux.of(rig.state).rack_types.back(), TankIds.SHELL_HEAVY, "30 s: a heavy shell")


func test_overpressure_needs_the_window() -> void:
	var rig := _loader(1)
	rig.plan_t = 400.0
	rig.power_w[3] = 360.0
	rig.run(3.5)
	rig.send(3, {"k": "over"})
	rig.run(0.2)
	assert_false(rig.steam().over, "no window")
	var early := _loader(1)
	early.plan_t = 250.0
	early.steam().window_s = 4.0
	early.power_w[3] = 360.0
	early.run(3.5)
	early.send(3, {"k": "over"})
	early.run(0.2)
	assert_false(early.steam().over, "the first 300 s")


## A surge just before the stow (up to window_s) counts: the shell goes straight back to the boiler.
func test_a_surge_just_before_the_stow_overpressures_that_shell() -> void:
	var rig := _loader(1)
	rig.plan_t = 400.0
	rig.power_w[3] = 360.0
	var st := rig.steam()
	var full_j := rig.content.num("tanks", "steam.full_j")
	st.pressure_pct = 100.0 - 375.0 * 2.0 / full_j * 100.0
	rig.send(3, {"k": "over"})
	rig.run(0.05)
	assert_false(st.over, "nothing stowed to take back yet")
	rig.run(2.5)
	assert_true(st.over, "stowed and straight back to the boiler")
	assert_eq(st.rack, 1)
	assert_eq(st.window_s, 0.0)
	var late := _loader(1)
	late.plan_t = 400.0
	late.power_w[3] = 360.0
	var window := late.content.num("tanks", "steam.window_s")
	late.steam().pressure_pct = 100.0 - 375.0 * (window + 1.0) / full_j * 100.0
	late.send(3, {"k": "over"})
	late.run(window + 1.5)
	assert_false(late.steam().over, "a surge more than window_s before the stow does not count")
	assert_eq(late.steam().rack, 2)


# --- The Gun chambers from the rack ----------------------------------------------------------------


func test_the_gun_chambers_the_oldest_shell_in_1_s_at_the_loading_elevation() -> void:
	var rig := _quiet(2)
	var st := rig.steam()
	rig.hull().loaded = TankIds.SHELL_NONE
	rig.set_rack(0)
	TankAux.of(rig.state).rack_types.append_array([TankIds.SHELL_LIGHT, TankIds.SHELL_HEAVY])
	st.rack = 2
	var load_elev := rig.content.num("tanks", "gun.load_elev_deg")
	rig.hull().elev_deg = load_elev + 8.0
	rig.hull().elev_target_deg = load_elev + 8.0
	rig.run(0.5)
	assert_lt(rig.hull().elev_deg, load_elev + 8.0, "back down to the loading elevation")
	assert_false(st.chamber)
	assert_almost_eq(st.chamber_s, 1.0, 1e-6, "the chambering waits for the elevation")
	rig.run(0.6)
	assert_almost_eq(rig.hull().elev_deg, load_elev, 1e-6, "at 8 degrees a second")
	rig.run(0.7)
	assert_eq(rig.hull().loaded, TankIds.SHELL_NONE, "1 s of chambering")
	rig.run(0.5)
	assert_eq(rig.hull().loaded, TankIds.SHELL_LIGHT, "the oldest shell")
	assert_true(st.chamber)
	assert_eq(st.rack, 1)
	assert_eq(st.chamber_s, 0.0)


func test_a_shot_starts_the_next_chambering_and_an_empty_rack_chambers_nothing() -> void:
	var rig := _quiet(2)
	rig.set_rack(1)
	rig.load_shell(TankIds.SHELL_HEAVY)
	var aux := TankAux.of(rig.state)
	TankGun.fire(rig.state, aux, rig.dynamo(), true, rig.events)
	assert_eq(rig.hull().loaded, TankIds.SHELL_NONE)
	assert_false(rig.steam().chamber)
	assert_eq(rig.steam().chamber_s, rig.content.num("tanks", "steam.chamber_s"), "from 1 s")
	rig.run(1.2)
	assert_eq(rig.hull().loaded, TankIds.SHELL_HEAVY)
	assert_eq(rig.steam().rack, 0)
	TankGun.fire(rig.state, aux, rig.dynamo(), true, rig.events)
	assert_eq(rig.steam().chamber_s, 0.0, "nothing left to chamber")
	rig.run(3.0)
	assert_eq(rig.hull().loaded, TankIds.SHELL_NONE)


## v3 solo balance (tanks.json steam.checkpoint_rack_by_crew [3, 0, 0, 0]): a solo rider's rack is
## restocked to 3 at each checkpoint; a crew loads its own.
func test_a_solo_riders_rack_is_restocked_at_each_checkpoint() -> void:
	var solo := _quiet(1, 2, 5.0)
	solo.set_rack(0)
	solo.enter(3, 0.0)
	solo.run(0.1)
	assert_eq(solo.steam().rack, TankConst.RACK_MAX)
	var crew := _quiet(2, 2, 5.0)
	crew.set_rack(1)
	crew.enter(3, 0.0)
	crew.run(0.1)
	assert_eq(crew.steam().rack, 1, "crews 2-4 load their own")
