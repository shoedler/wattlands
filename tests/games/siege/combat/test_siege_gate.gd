extends GutTest
## The gate and the Breach (brief 2.4 "Gate and Breach", "Waves" warm-up wave).

const VALLEY := SiegeIds.ROAD_VALLEY

var _rig: SiegeRig


func _wave(shift: String = "short", phase: int = 2, humans: int = 2) -> SiegeRig:
	_rig = SiegeRig.new(shift, humans, 0, 7)
	_rig.enter(phase, 10.0)
	_rig.state.wave.budget_left = 0.0
	_rig.state.wave.push_done = true
	return _rig


## Drops the gate to `hp` and sends raiders at it until it is breached.
func _breach(hp: float = 3.0) -> void:
	_rig.state.gate_hp = hp
	for _i in 3:
		_rig.spawn(SiegeIds.ENEMY_RAIDERS, VALLEY, _rig.road_end(VALLEY) - 0.01)
	_rig.step()


## Brief 2.4 says 100 HP; G2 tuned it to 130 (docs/decisions/siege.md, "G2 tuning").
func test_the_gate_starts_at_130_hp() -> void:
	_wave()
	assert_eq(_rig.state.gate_hp, 130.0)
	assert_eq(_rig.state.gate_max, 130.0)


func test_a_breach_happens_at_zero_hp() -> void:
	_wave()
	_breach()
	assert_eq(_rig.state.gate_hp, 0.0)
	assert_eq(_rig.state.breaches, 1)
	assert_almost_eq(_rig.state.breach_s, 10.0, 1e-6)
	assert_eq(_rig.of_type(SiegeIds.EV_BREACH).size(), 1)
	assert_eq(_rig.of_type(SiegeIds.EV_BREACH)[0]["n"], 1)
	var leaks := _rig.of_type(SiegeIds.EV_LEAK)
	assert_eq(leaks.map(func(e: Dictionary) -> int: return e["dmg"]), [2, 1, 0])
	assert_eq(_rig.state.enemies.size(), 0)


func test_every_tower_stops_for_ten_seconds_perks_included() -> void:
	_wave()
	_rig.state.perks = [SiegeIds.PERK_RESERVE, SiegeIds.PERK_AQUEDUCT]
	_rig.put(1, 3)
	_rig.p_eff[1] = 250.0
	_rig.run(1.0)
	assert_almost_eq(_rig.state.pad(3).m, 1.0, 1e-6)
	_breach()
	for pad in [3, 4]:
		assert_eq(_rig.state.pad(pad).m, 0.0, "pad %d is silent" % pad)
	var e := _rig.spawn(SiegeIds.ENEMY_SHIELD_WALL, VALLEY, 80.0)
	_rig.state.pad(3).cd_s = 0.0
	var tw3 := _rig.state.pad(3).damage
	_rig.run(5.0)
	assert_eq(_rig.state.pad(3).damage, tw3, "no shot in a Breach")
	assert_eq(_rig.state.pad(3).m, 0.0)
	assert_eq(_rig.state.pad(4).m, 0.0, "the Aqueduct drive is off too")
	assert_true(_rig.state.shots.is_empty())
	assert_eq(e.hp, 160.0)
	_rig.run(5.1)
	assert_eq(_rig.state.breach_s, 0.0)
	_rig.run(0.2)
	assert_gt(_rig.state.pad(3).m, 0.0, "back after ten seconds")


func test_arrivals_during_a_breach_vanish_without_damage() -> void:
	_wave()
	_breach()
	_rig.run(1.0)
	_rig.spawn(SiegeIds.ENEMY_SHIELD_WALL, VALLEY, _rig.road_end(VALLEY) - 0.01)
	_rig.step()
	assert_eq(_rig.state.gate_hp, 0.0, "no damage")
	assert_eq(_rig.state.enemies.size(), 0, "the arrival is gone")
	assert_eq(_rig.state.breaches, 1, "no second Breach")


func test_rams_pause_during_a_breach() -> void:
	_wave()
	var ram := _rig.spawn(SiegeIds.ENEMY_RAM, VALLEY, _rig.road_end(VALLEY))
	ram.st = SiegeIds.EN_BATTER
	_rig.state.gate_hp = 2.0
	_rig.run(2.0)
	assert_eq(_rig.state.breaches, 1)
	var leaks := _rig.of_type(SiegeIds.EV_LEAK).size()
	_rig.run(5.0)
	assert_eq(_rig.of_type(SiegeIds.EV_LEAK).size(), leaks, "no battering meanwhile")
	assert_eq(_rig.state.gate_hp, 0.0)
	assert_true(_rig.state.enemies.has(ram), "the ram waits")
	for _i in 120:
		_rig.step()
		if not _rig.of_type(SiegeIds.EV_GATE_RESTORED).is_empty():
			break
	assert_eq(_rig.of_type(SiegeIds.EV_GATE_RESTORED)[0]["hp"], 30)
	assert_almost_eq(_rig.state.gate_hp, 30.0, 0.2, "restored first")
	_rig.run(2.0)
	assert_lt(_rig.state.gate_hp, 26.0, "battering resumes")


func test_afterwards_the_gate_is_back_at_30_hp_and_riders_lose_30_percent() -> void:
	_wave()
	_rig.rider(1).denarii = 100.0
	_rig.rider(2).denarii = 33.7
	_rig.power_w = {1: 0.0, 2: 0.0}
	_rig.p_eff = {1: 0.0, 2: 0.0}
	_breach()
	_rig.run(9.9)
	assert_eq(_rig.state.gate_hp, 0.0)
	assert_eq(_rig.of_type(SiegeIds.EV_GATE_RESTORED).size(), 0)
	_rig.run(0.2)
	assert_eq(_rig.state.gate_hp, 30.0)
	assert_eq(_rig.of_type(SiegeIds.EV_GATE_RESTORED)[0]["hp"], 30)
	assert_almost_eq(_rig.rider(1).denarii, 70.0, 1e-6, "100 - 30")
	assert_almost_eq(_rig.rider(2).denarii, 24.7, 1e-6, "33 unspent: 30% = 9.9, rounded down to 9")
	assert_eq(_rig.state.role, SiegeIds.ROLE_WAVE, "the wave runs on")
	assert_eq(_rig.state.breach_s, 0.0)


func test_the_loss_rounds_down_on_small_purses() -> void:
	_wave("short", 2, 1)
	_rig.rider(1).denarii = 3.9
	_rig.power_w = {1: 0.0}
	_rig.p_eff = {1: 0.0}
	_breach()
	_rig.run(10.1)
	assert_almost_eq(_rig.rider(1).denarii, 3.9, 1e-6, "30% of 3 is 0.9: nothing lost")


func test_a_breach_does_not_change_the_wave_or_the_plan() -> void:
	_wave()
	var idx := _rig.state.phase_index
	_breach()
	_rig.run(12.0)
	assert_eq(_rig.state.phase_index, idx)
	assert_eq(_rig.of_type(SiegeIds.EV_WAVE_END).size(), 0)


func test_the_warm_up_wave_never_lets_the_gate_fall_below_50() -> void:
	_wave("short", 0)
	assert_eq(_rig.state.role, SiegeIds.ROLE_WARMUP_WAVE)
	_rig.state.gate_hp = 52.0
	for _i in 5:
		_rig.spawn(SiegeIds.ENEMY_SHIELD_WALL, VALLEY, _rig.road_end(VALLEY) - 0.01)
	_rig.step()
	assert_eq(_rig.state.gate_hp, 50.0)
	assert_eq(_rig.state.breaches, 0)
	var ram := _rig.spawn(SiegeIds.ENEMY_RAM, VALLEY, _rig.road_end(VALLEY))
	ram.st = SiegeIds.EN_BATTER
	_rig.run(30.0)
	assert_eq(_rig.state.gate_hp, 50.0)
	assert_eq(_rig.state.breaches, 0)


func test_the_floor_applies_to_the_warm_up_wave_only() -> void:
	_wave("short", 2)
	_rig.state.gate_hp = 10.0
	_rig.spawn(SiegeIds.ENEMY_SHIELD_WALL, VALLEY, _rig.road_end(VALLEY) - 0.01)
	_rig.spawn(SiegeIds.ENEMY_SHIELD_WALL, VALLEY, _rig.road_end(VALLEY) - 0.01)
	_rig.step()
	assert_eq(_rig.state.gate_hp, 0.0)
	assert_eq(_rig.state.breaches, 1)


func test_the_drill_wave_has_no_floor() -> void:
	_rig = SiegeRig.new("drill", 1)
	_rig.enter(1, 5.0)
	assert_eq(_rig.state.role, SiegeIds.ROLE_WAVE)
	assert_eq(_rig.state.phase_kind, Wl.WARMUP, "a WARMUP-kind phase plays as wave 1")
	_rig.state.wave.budget_left = 0.0
	_rig.state.gate_hp = 4.0
	for _i in 3:
		_rig.spawn(SiegeIds.ENEMY_RAIDERS, VALLEY, _rig.road_end(VALLEY) - 0.01)
	_rig.step()
	assert_eq(_rig.state.gate_hp, 0.0)
	assert_eq(_rig.state.breaches, 1)


func test_iron_bands_raise_the_max() -> void:
	_wave()
	_rig.state.gate_hp = 100.0
	_rig.state.gate_max = 150.0
	_rig.state.iron_bands = 2
	_rig.spawn(SiegeIds.ENEMY_SHIELD_WALL, VALLEY, _rig.road_end(VALLEY) - 0.01)
	_rig.step()
	assert_eq(_rig.state.gate_hp, 92.0)
	_rig.state.gate_hp = 0.5
	_rig.spawn(SiegeIds.ENEMY_RAIDERS, VALLEY, _rig.road_end(VALLEY) - 0.01)
	_rig.step()
	_rig.power_w = {1: 0.0, 2: 0.0}
	_rig.run(10.1)
	assert_eq(_rig.state.gate_hp, 30.0)
