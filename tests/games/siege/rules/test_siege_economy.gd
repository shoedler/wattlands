extends GutTest
## The generator's economy (brief 2.4 "Economy"), the wave-time stats and AFK / rescue.

var _rig: SiegeRig


func _wave(humans: int = 2) -> SiegeRig:
	_rig = SiegeRig.new("short", humans)
	for p in _rig.slots:
		_rig.power_w[p.peer_id] = 0.0
		_rig.p_eff[p.peer_id] = 0.0
	_rig.enter(2, 10.0)
	for r in _rig.state.riders:
		r.route_fallback = false
		r.shop_fallback = false
	return _rig


func test_the_generator_pays_one_denarius_per_kj_of_p_eff() -> void:
	_wave()
	_rig.p_eff[1] = 250.0
	_rig.power_w[1] = 200.0
	var before := _rig.rider(1).denarii
	_rig.run(100.0)
	var gained := _rig.rider(1).denarii - before
	assert_almost_eq(gained, 25.0, 25.0 * 0.001, "250 W x 100 s = 25 kJ = 25 denarii, +-0.1 %")
	assert_almost_eq(_rig.rider(1).gen_denarii, gained, 1e-9)
	assert_almost_eq(_rig.state.team_earned, gained, 1e-9)
	assert_eq(_rig.rider(2).denarii, 40.0, "a silent rider earns nothing")


func test_p_eff_not_raw_power_is_what_pays() -> void:
	_wave()
	_rig.power_w[1] = 100.0
	_rig.p_eff[1] = 200.0
	var before := _rig.rider(1).denarii
	_rig.run(50.0)
	assert_almost_eq(_rig.rider(1).denarii - before, 10.0, 0.01)


func test_each_generator_level_adds_20_percent() -> void:
	for lvl in 4:
		_wave()
		_rig.state.gen_level = lvl
		_rig.p_eff[1] = 250.0
		var before := _rig.rider(1).denarii
		_rig.run(40.0)
		assert_almost_eq(
			_rig.rider(1).denarii - before, 10.0 * (1.0 + 0.2 * lvl), 0.01, "level %d" % lvl
		)


func test_breaks_pay_whatever_the_target() -> void:
	_wave()
	_rig.put(1, 3)
	_rig.enter(3, 0.0)
	_rig.p_eff[1] = 250.0
	var before := _rig.rider(1).denarii
	_rig.run(40.0)
	assert_almost_eq(_rig.rider(1).denarii - before, 10.0, 0.01)


func test_a_rider_on_a_tower_earns_nothing_from_the_generator() -> void:
	_wave()
	_rig.put(1, 3)
	_rig.p_eff[1] = 250.0
	_rig.run(20.0)
	assert_eq(_rig.rider(1).gen_denarii, 0.0)
	assert_eq(_rig.rider(1).denarii, 40.0)


func test_afk_stops_the_wheel_but_keeps_the_rest() -> void:
	_wave()
	_rig.put(1, 3)
	_rig.rider(1).denarii = 77.0
	_rig.p_eff[1] = 250.0
	_rig.afk[1] = true
	_rig.run(5.0)
	assert_true(_rig.rider(1).afk)
	assert_eq(_rig.rider(1).target, 3, "routing is kept")
	assert_eq(_rig.rider(1).denarii, 77.0, "denarii are kept")
	assert_eq(_rig.state.pad(3).m, 0.0, "the wheel is stopped")
	_rig.put(1, SiegeIds.TARGET_GEN)
	_rig.run(5.0)
	assert_eq(_rig.rider(1).denarii, 77.0, "and it earns nothing")


func test_an_afk_rider_keeps_their_share_of_b() -> void:
	var budgets: Array[float] = []
	for afk in [false, true]:
		_rig = SiegeRig.new("vo2", 3)
		_rig.afk[2] = afk
		_rig.enter(2, 0.0)
		budgets.append(_rig.state.wave.budget)
	assert_gt(budgets[0], 0.0)
	assert_eq(budgets[0], budgets[1])


func test_a_disconnected_rider_is_afk() -> void:
	_wave()
	_rig.connected[1] = false
	_rig.p_eff[1] = 250.0
	_rig.run(2.0)
	assert_true(_rig.rider(1).afk)
	assert_false(_rig.rider(1).connected)
	assert_eq(_rig.rider(1).denarii, 40.0)


func test_rescue_counts_at_actual_p_eff() -> void:
	_wave()
	_rig.rescue[1] = true
	_rig.p_eff[1] = 125.0
	var before := _rig.rider(1).denarii
	_rig.run(40.0)
	assert_true(_rig.rider(1).rescue)
	assert_almost_eq(_rig.rider(1).denarii - before, 5.0, 0.01)


func test_wave_time_is_counted_per_target() -> void:
	_wave()
	_rig.p_eff[1] = 100.0
	_rig.run(10.0)
	var r := _rig.rider(1)
	assert_almost_eq(r.wave_gen_s, 10.0, 0.06)
	assert_eq(r.wave_tower_s, 0.0)
	_rig.put(1, 3)
	_rig.run(6.0)
	assert_almost_eq(r.wave_tower_s, 6.0, 0.06)
	_rig.rider(1).reconnect_s = 2.0
	_rig.run(1.0)
	assert_almost_eq(r.wave_tower_s, 6.0, 0.06, "reconnecting time counts for neither")
	assert_almost_eq(r.wave_gen_s, 10.0, 0.06)
	_rig.enter(3, 0.0)
	_rig.run(5.0)
	assert_almost_eq(r.wave_gen_s, 10.0, 0.06, "breaks are not wave time")
	assert_almost_eq(r.wave_tower_s, 6.0, 0.06)


func test_the_teams_watts_are_a_one_second_mean_of_raw_power() -> void:
	_wave(2)
	_rig.power_w = {1: 200.0, 2: 100.0}
	_rig.run(2.0)
	assert_almost_eq(_rig.state.team_w, 300.0, 1e-6)
	_rig.power_w = {1: 0.0, 2: 0.0}
	_rig.run(0.5)
	assert_almost_eq(_rig.state.team_w, 150.0, 20.0, "half a second later: about half")
	_rig.run(1.0)
	assert_almost_eq(_rig.state.team_w, 0.0, 1e-6)
	_rig.power_w = {1: 200.0, 2: 100.0}
	_rig.afk[2] = true
	_rig.run(1.0)
	assert_almost_eq(_rig.state.team_w, 200.0, 1e-6, "an AFK wheel does not count")


func test_nothing_is_earned_in_the_cooldown_or_after_the_last_wave() -> void:
	_wave()
	_rig.enter(7, 1.0)
	_rig.p_eff[1] = 500.0
	var before := _rig.rider(1).denarii
	var kj := _rig.state.planned_kj
	_rig.run(20.0)
	assert_eq(_rig.rider(1).denarii, before)
	assert_eq(_rig.state.planned_kj, kj, "the cool-down is not part of par")


func test_planned_kj_covers_warm_up_to_the_last_wave() -> void:
	_rig = SiegeRig.new("drill", 1)
	_rig.run(120.0)
	# 20 s at 50 % + 100 s at 60 % of a 250 W P_eff reference, one verified rider
	assert_almost_eq(_rig.state.planned_kj, 0.5 * 250.0 * 0.020 + 0.6 * 250.0 * 0.100, 0.1)
