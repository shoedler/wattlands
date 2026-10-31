extends GutTest
## The Repairs seat (SPEC_TANK 3.6): rebuilds the hull per kJ of P_eff in band, only below the hull's
## maximum, at a difficulty-dependent rate; a rescue, an empty seat and a tow stop it.

const ADVANCE := 1


## Rider 1 on Repairs, 130 W P_eff, the plan's ERG in band, no enemies, the Drive seat empty.
func _rig(difficulty: String = TankIds.DIFF_NORMAL) -> TankRulesRig:
	var rig := TankRulesRig.new(1, "ashfall_road", 7)
	rig.state.difficulty = difficulty
	rig.no_fire = true
	rig.no_bow = true
	rig.enter(ADVANCE, 1.0)
	rig.seat(1, TankIds.ENGINE_REPAIR)
	rig.state.enemies.clear()
	rig.p_eff[1] = 130.0
	rig.state.hull.hp = 50.0
	return rig


func _bay(rig: TankRulesRig) -> TankRepairState:
	return rig.state.station(TankIds.ENGINE_REPAIR) as TankRepairState


func _run_quiet(rig: TankRulesRig, seconds: float) -> void:
	for _i in roundi(seconds / Wl.SIM_DT):
		rig.state.enemies.clear()
		rig.step()


func test_the_rate_is_hp_per_kj_times_the_difficulty_at_each_level() -> void:
	var per_kj := TankContent.read_files("ashfall_road")["tanks"]["repair"]["hp_per_kj"] as float
	assert_eq(per_kj, 3.0)
	var want := {TankIds.DIFF_EASY: 1.5, TankIds.DIFF_NORMAL: 1.0, TankIds.DIFF_HARD: 0.7}
	for d: String in want:
		var rig := _rig(d)
		_run_quiet(rig, 10.0)
		var hp := 0.13 * per_kj * float(want[d]) * 10.0
		assert_almost_eq(rig.state.hull.hp, 50.0 + hp, 0.05, "%s: 130 W for 10 s" % d)
		assert_almost_eq(rig.rider(1).repaired_hp, hp, 0.05, "%s: the rider's credit" % d)


func test_it_stops_at_the_hulls_maximum() -> void:
	var rig := _rig()
	rig.state.hull.hp = rig.state.hull.hp_max - 0.2
	_run_quiet(rig, 5.0)
	assert_eq(rig.state.hull.hp, rig.state.hull.hp_max, "never past the maximum")
	assert_false(_bay(rig).working, "at the maximum it stands idle")
	var credit := rig.rider(1).repaired_hp
	assert_almost_eq(credit, 0.2, 0.05, "only what it rebuilt")
	_run_quiet(rig, 2.0)
	assert_eq(rig.rider(1).repaired_hp, credit)


func test_out_of_band_it_rebuilds_nothing() -> void:
	var rig := _rig()
	rig.power_w[1] = 10.0
	_run_quiet(rig, 3.0)
	assert_false(_bay(rig).in_band)
	assert_false(_bay(rig).working)
	assert_eq(rig.state.hull.hp, 50.0)


func test_a_rescue_stops_it() -> void:
	var rig := _rig()
	rig.rescue[1] = true
	_run_quiet(rig, 3.0)
	assert_false(_bay(rig).working)
	assert_eq(rig.state.hull.hp, 50.0)


func test_a_rider_on_reserve_rebuilds_nothing() -> void:
	var rig := TankRulesRig.new(2, "ashfall_road", 7)
	rig.no_fire = true
	rig.no_bow = true
	rig.enter(ADVANCE, 1.0)
	rig.seat(2, TankIds.ENGINE_REPAIR)
	rig.afk[2] = true
	rig.state.hull.hp = 50.0
	_run_quiet(rig, 3.0)
	assert_true(_bay(rig).reserve)
	assert_false(_bay(rig).working)
	assert_eq(rig.state.hull.hp, 50.0)


func test_an_empty_seat_rebuilds_nothing() -> void:
	var rig := TankRulesRig.new(1, "ashfall_road", 7)
	rig.no_fire = true
	rig.no_bow = true
	rig.enter(ADVANCE, 1.0)
	rig.state.hull.hp = 50.0
	assert_true(_bay(rig).is_empty())
	_run_quiet(rig, 3.0)
	assert_eq(rig.state.hull.hp, 50.0)
	assert_false(_bay(rig).working)
	assert_eq(_bay(rig).duty, 0.0, "an empty seat has no load")


func test_no_repair_during_a_breakdown_or_a_tow() -> void:
	var rig := _rig(TankIds.DIFF_EASY)
	rig.state.hull.breakdown = true
	_run_quiet(rig, 1.0)
	assert_false(_bay(rig).working, "a breakdown")
	rig.state.hull.breakdown = false
	rig.state.hull.tow_s = 100.0
	rig.state.hull.hp = 50.0
	_run_quiet(rig, 1.0)
	assert_false(_bay(rig).working, "a tow")
	assert_eq(rig.state.hull.hp, 50.0)


func test_a_patch_comes_every_patch_hp_rebuilt_and_press_t_runs_toward_it() -> void:
	var rig := _rig()
	var bay := _bay(rig)
	rig.p_eff[1] = 1000.0
	# 3 HP a second: a patch of 4 HP every 1.33 s.
	_run_quiet(rig, 1.0)
	assert_eq(bay.patches, 0)
	assert_almost_eq(bay.press_t, 0.75, 0.02)
	_run_quiet(rig, 3.1)
	assert_eq(bay.patches, 3, "12.3 HP is 3 patches")
	assert_between(bay.press_t, 0.0, 1.0)


func test_duty_is_the_share_of_the_last_10_s_below_the_maximum() -> void:
	var rig := _rig()
	var bay := _bay(rig)
	rig.p_eff[1] = 0.0
	_run_quiet(rig, 5.0)
	assert_almost_eq(bay.duty, 0.5, 0.02, "5 of the last 10 s")
	_run_quiet(rig, 6.0)
	assert_almost_eq(bay.duty, 1.0, 0.01)
	rig.state.hull.hp = rig.state.hull.hp_max
	_run_quiet(rig, 5.0)
	assert_almost_eq(bay.duty, 0.5, 0.02, "the hull at its maximum is no load")


func test_a_rider_on_repairs_counts_seat_seconds() -> void:
	var rig := _rig()
	var r := rig.rider(1)
	var at: int = TankRiderState.ENGINE_INDEX[TankIds.ENGINE_REPAIR]
	var was := r.engine_s[at]
	_run_quiet(rig, 2.0)
	assert_almost_eq(r.engine_s[at] - was, 2.0, 0.01)
