extends GutTest
## Waves (brief 2.4 "Waves"): the budget B, groups, the threat mix by thirds, active roads and
## their rotation, the ram push, the warm-up wave, endurance rushes and the drill.

const F := preload("res://tests/games/siege/siege_fakes.gd")

var _rig: SiegeRig
var _seen: Dictionary = {}
## [time, SiegeEnemyState-copy fields] for every enemy first seen.
var _log: Array[Dictionary] = []


func _track() -> void:
	for e in _rig.state.enemies:
		if not _seen.has(e.id):
			_seen[e.id] = true
			_log.append(
				{
					"t": _rig.state.t,
					"type": e.type,
					"road": e.road,
					"prog": e.prog_m,
					"hp": e.hp,
					"escort": e.escort,
					"crew": e.crew,
					"rush": e.rush
				}
			)


## Steps `seconds`, logging every spawn.
func _run(seconds: float) -> void:
	for _i in roundi(seconds / Wl.SIM_DT):
		_rig.step()
		_track()


func _threat(type: int) -> float:
	return float(_rig.content.enemy_def(type)["threat"])


func _start(shift: String, phase: int, humans: int, into_s: float = 0.0) -> SiegeRig:
	_rig = SiegeRig.new(shift, humans, 0, 11).manual()
	_rig.enter(phase, into_s)
	_seen = {}
	_log = []
	return _rig


# --- the budget B ------------------------------------------------------------------------------


## balance.json c_budget (brief 2.4 "start 10"; G2 tuned it, docs/decisions/siege.md).
func _c() -> float:
	return _rig.content.num("c_budget")


func test_b_follows_planned_p_eff_in_fair_ftp() -> void:
	_start("vo2", 2, 4)
	# c_budget x sum(112 % x 250 / 250) x (120 - 60) / 60, four verified riders
	assert_almost_eq(_rig.state.wave.budget, _c() * 4.0 * 1.12, 1e-6)
	assert_eq(
		_rig.of_type(SiegeIds.EV_WAVE_START)[0]["b"],
		roundi(_c() * 4.0 * 1.12),
		"the event carries it rounded"
	)


func test_b_with_unverified_ftp_uses_085() -> void:
	_rig = SiegeRig.new("vo2", 4)
	for r in _rig.state.riders:
		r.ftp_verified = false
	_rig.enter(2, 0.0)
	assert_almost_eq(_rig.state.wave.budget, _c() * 4.0 * 1.12 * 0.85, 1e-6)


func test_b_in_raw_uses_the_ftp_itself() -> void:
	_rig = SiegeRig.new("vo2", 4, 0, 11, Wl.RAW)
	_rig.enter(2, 0.0)
	var ftps := 200.0 + 220.0 + 240.0 + 260.0
	assert_almost_eq(_rig.state.wave.budget, _c() * 1.12 * ftps / 250.0, 1e-6)
	_rig = SiegeRig.new("vo2", 4, 0, 11, Wl.RAW)
	for r in _rig.state.riders:
		r.ftp_verified = false
	_rig.enter(2, 0.0)
	assert_almost_eq(_rig.state.wave.budget, _c() * 1.12 * ftps / 250.0 * 0.85, 1e-6)


func test_b_in_wkg_uses_the_latest_p_eff_over_power() -> void:
	for verified in [true, false]:
		_rig = SiegeRig.new("vo2", 4, 0, 11, Wl.WKG)
		for r in _rig.state.riders:
			r.ftp_verified = verified
		for peer in [1, 2, 3, 4]:
			_rig.power_w[peer] = 100.0
			_rig.p_eff[peer] = 80.0
		_rig.enter(2, 0.0)
		var ftps := 200.0 + 220.0 + 240.0 + 260.0
		var u := 1.0 if verified else 0.85
		assert_almost_eq(_rig.state.wave.budget, _c() * 1.12 * ftps * 0.8 * u / 250.0, 1e-6)
		assert_almost_eq(_rig.rider(1).r_wkg, 0.8, 1e-9)


func test_wkg_r_is_one_before_telemetry_with_power_of_50_w() -> void:
	_rig = SiegeRig.new("vo2", 1, 0, 11, Wl.WKG)
	_rig.power_w[1] = 49.0
	_rig.p_eff[1] = 30.0
	_rig.enter(2, 0.0)
	assert_eq(_rig.rider(1).r_wkg, 1.0, "below 50 W: no r yet")
	assert_almost_eq(_rig.state.wave.budget, _c() * 1.12 * 200.0 / 250.0, 1e-6)


func test_b_scales_with_wave_length_and_team_size() -> void:
	_start("sweetspot", 2, 2)
	# 900 s wave at 90 %: c_budget x 2 x 0.9 x (900 - 60) / 60
	assert_almost_eq(_rig.state.wave.budget, _c() * 2.0 * 0.9 * 14.0, 1e-6)
	_start("vo2", 2, 1)
	assert_almost_eq(_rig.state.wave.budget, _c() * 1.12, 1e-6)


func test_b_follows_the_waves_offset_through_the_plan() -> void:
	_rig = SiegeRig.new("vo2", 1)
	_rig.slots[0].options["wave_offset"] = 5
	_rig.plans[1] = F.with_cooldown(
		SiegePlanBuilder.build(_rig.content.shift, _rig.slots[0], "vo2")
	)
	_rig.enter(2, 0.0)
	assert_almost_eq(_rig.state.wave.budget, _c() * 1.17, 1e-6, "112 + 5 = 117 % in a 120 s wave")


func test_the_warm_up_wave_is_04_of_b_at_its_mean_target() -> void:
	_start("short", 0, 4)
	assert_eq(_rig.state.role, SiegeIds.ROLE_WARMUP_WAVE)
	# mean of the 50 -> 65 % ramp = 57.5 %; 0.4 x c_budget x 4 x 0.575 x (300 - 60) / 60
	assert_almost_eq(_rig.state.wave.budget, 0.4 * _c() * 4.0 * 0.575 * 4.0, 1e-6)


func test_the_drill_budget_comes_from_its_60_percent_target() -> void:
	_start("drill", 1, 4)
	assert_eq(_rig.state.role, SiegeIds.ROLE_WAVE)
	assert_almost_eq(_rig.state.wave.budget, _c() * 4.0 * 0.6 * 40.0 / 60.0, 1e-6)


func test_par_follows_planned_p_eff_in_every_scaling_mode() -> void:
	for mode: String in Wl.SCALING_MODES:
		for verified in [true, false]:
			_rig = SiegeRig.new("short", 2, 0, 11, mode)
			for r in _rig.state.riders:
				r.ftp_verified = verified
				r.r_wkg = 0.9
			_rig.power_w = {1: 100.0, 2: 110.0}
			_rig.p_eff = {1: 90.0, 2: 99.0}
			_rig.enter(1, 0.0)
			_rig.run(10.0)
			var u := 1.0 if verified else 0.85
			var r_of := func(ftp: float) -> float:
				match mode:
					Wl.FAIR_FTP:
						return 250.0 / ftp
					Wl.WKG:
						return 0.9
				return 1.0
			# the break plans 50 % for 10 s + the first tick
			var kj := 0.0
			for ftp in [200.0, 220.0]:
				kj += 0.5 * ftp * u * float(r_of.call(ftp)) * 10.05 / 1000.0
			assert_almost_eq(
				_rig.state.planned_kj, kj, kj * 0.01, "%s verified %s" % [mode, verified]
			)
			assert_almost_eq(
				SiegeScore.compute(_rig.state)["par"], 0.75 * _rig.state.planned_kj, 1e-9
			)


func test_rules_never_read_a_weight() -> void:
	for dir in ["res://src/games/siege/rules", "res://src/games/siege/combat"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				var src := FileAccess.get_file_as_string(dir.path_join(f))
				for banned in [
					"rider_mass_kg", "weight_kg", "mass_kg", "p_eff_per_w", "Time.", "OS.get_ticks"
				]:
					assert_false(src.contains(banned), "%s mentions %s" % [f, banned])
				assert_false(src.contains("RandomNumberGenerator.new()"), f)


# --- groups and mix ----------------------------------------------------------------------------


func test_groups_come_every_6_to_12_seconds_until_60_s_before_the_end() -> void:
	_start("short", 2, 4)
	var times: Array[float] = []
	var last := _rig.state.next_enemy_id
	for _i in 6000:
		_rig.step()
		if _rig.state.phase_remaining_s <= 60.0:
			break
		if _rig.state.next_enemy_id != last:
			last = _rig.state.next_enemy_id
			if times.is_empty() or _rig.state.t - times[-1] > 0.001:
				times.append(_rig.state.t)
	var start := _rig.phase_start(2)
	assert_gt(times.size(), 15)
	for i in range(1, times.size()):
		var gap := times[i] - times[i - 1]
		assert_between(gap, 6.0 - 0.06, 12.0 + 0.06, "group %d" % i)
	assert_gt(times[0] - start, 0.0)
	assert_lt(times[-1] - start, 240.0 + 0.1, "none in the last 60 s")


func test_the_whole_budget_is_spent_on_groups() -> void:
	_start("short", 2, 4)
	var b := _rig.state.wave.budget
	_run(239.9)
	var spent := 0.0
	for e in _log:
		if not e["escort"] and not e["crew"] and not e["rush"]:
			spent += _threat(int(e["type"]))
	assert_between(spent, b - 1.0, b + 1e-6, "B = %.1f, spawned %.1f" % [b, spent])
	assert_lt(_rig.state.wave.budget_left, 1.0, "the last group takes the rest")


func test_mix_rows_by_thirds_of_the_shift() -> void:
	_start("short", 2, 1)
	var ph := SiegePhaseInfo.new()
	ph.mix = SiegeIds.MIX_STANDARD
	var want := {
		0.0: [0.7, 0.1, 0.2],
		500.0: [0.7, 0.1, 0.2],
		600.0: [0.5, 0.25, 0.25],
		1000.0: [0.5, 0.25, 0.25],
		1200.0: [0.4, 0.3, 0.3],
		1679.0: [0.4, 0.3, 0.3],
	}
	for t: float in want:
		ph.plan_elapsed_s = t
		assert_eq(SiegeSpawner.mix_row(_rig.state, ph), want[t] as Array[float], "t = %s" % t)
	ph.mix = SiegeIds.MIX_RAIDERS_HORSEMEN
	ph.plan_elapsed_s = 0.0
	assert_eq(SiegeSpawner.mix_row(_rig.state, ph)[1], 0.0, "the drill mix has no shield walls")


func test_composed_groups_follow_the_threat_split() -> void:
	_start("short", 2, 4)
	var tb := SiegeCombatTable.of(_rig.content, _rig.state)
	for src: Array in [[0.7, 0.1, 0.2], [0.5, 0.25, 0.25], [0.4, 0.3, 0.3]]:
		var row: Array[float] = []
		row.assign(src)
		var spent: Array[float] = [0.0]
		var types := SiegeSpawner.compose(_rig.state, tb, row, 3000.0, [], spent)
		var by := [0.0, 0.0, 0.0]
		for t in types:
			by[SiegeIds.MIX_ORDER.find(t)] += tb.threat[t]
		assert_almost_eq(spent[0], by[0] + by[1] + by[2], 1e-6)
		assert_between(spent[0], 3000.0 - 6.0, 3000.0)
		for i in 3:
			assert_almost_eq(by[i] / spent[0], row[i], 0.04, "row %s type %d" % [row, i])


func test_a_small_group_never_overspends() -> void:
	_start("short", 2, 4)
	var tb := SiegeCombatTable.of(_rig.content, _rig.state)
	for threat in [0.5, 1.0, 2.0, 5.5, 13.0]:
		var spent: Array[float] = [0.0]
		var types := SiegeSpawner.compose(_rig.state, tb, [0.4, 0.3, 0.3], threat, [], spent)
		assert_lte(spent[0], threat + 1e-6)
		assert_gt(threat - spent[0], -1e-6)
		var sum := 0.0
		for t in types:
			sum += tb.threat[t]
		assert_almost_eq(sum, spent[0], 1e-6)
		assert_lt(threat - spent[0], 1.0 + 1e-6, "less than the cheapest enemy is left")


# --- roads ------------------------------------------------------------------------------------


func test_active_roads_are_min_3_slots() -> void:
	for n in [1, 2, 3, 4]:
		_start("short", 2, n)
		assert_eq(_rig.state.wave.active_roads.size(), mini(3, n), "%d riders" % n)
		var starts := _rig.of_type(SiegeIds.EV_WAVE_START)
		assert_eq(starts[0]["roads"].size(), mini(3, n))


func test_three_or_more_riders_use_all_three_roads_without_rotating() -> void:
	_start("short", 2, 4)
	_run(120.0)
	assert_eq(_rig.of_type(SiegeIds.EV_ROADS).size(), 0)
	assert_eq(_rig.state.wave.active_roads, [0, 1, 2] as Array[int])
	var roads := {}
	for e in _log:
		roads[e["road"]] = true
	assert_eq(roads.size(), 3, "enemies come on every road")


func test_fewer_roads_rotate_every_30_to_60_s_with_a_5_s_horn() -> void:
	_start("sweetspot", 2, 1)
	var changes: Array[float] = []
	var announced := 0.0
	var current: Array[int] = _rig.state.wave.active_roads.duplicate()
	assert_eq(current.size(), 1)
	for _i in 20 * 330:
		_rig.step()
		var ev := _rig.of_type(SiegeIds.EV_ROADS)
		if ev.size() > 0 and announced != float(ev.size()):
			announced = float(ev.size())
			var e := ev[-1]
			assert_eq(e["in_ms"], 5000)
			assert_eq(e["roads"].size(), 1)
			assert_ne(e["roads"], current as Array, "a different road")
			assert_eq(_rig.state.wave.active_roads, current, "not switched yet")
		if _rig.state.wave.active_roads != current:
			changes.append(_rig.state.t)
			current = _rig.state.wave.active_roads.duplicate()
	assert_gte(changes.size(), 5)
	assert_eq(
		_rig.of_type(SiegeIds.EV_ROADS).size(),
		changes.size() + (1 if _rig.state.wave.horn_s > 0.0 else 0)
	)
	for i in range(1, changes.size()):
		assert_between(changes[i] - changes[i - 1], 30.0 - 0.1, 60.0 + 0.1, "switch %d" % i)


func test_the_horn_precedes_the_switch_by_five_seconds() -> void:
	_start("sweetspot", 2, 2)
	var t_horn := -1.0
	for _i in 20 * 90:
		var out := _rig.step()
		for e in out:
			if e["type"] == SiegeIds.EV_ROADS and t_horn < 0.0:
				t_horn = _rig.state.t
				assert_eq(e["roads"].size(), 2)
		if t_horn >= 0.0 and _rig.state.wave.horn_s == 0.0:
			assert_almost_eq(_rig.state.t - t_horn, 5.0, 0.06)
			return
	fail_test("no rotation within 90 s")


func test_spawns_use_only_the_active_roads() -> void:
	_start("sweetspot", 2, 1)
	var roads: Array[int] = _rig.state.wave.active_roads.duplicate()
	_run(20.0)
	for e in _log:
		assert_eq([e["road"]], roads)


# --- the ram push ------------------------------------------------------------------------------


func test_the_ram_push_sends_one_ram_per_active_road_with_an_escort() -> void:
	_start("short", 2, 4)
	_rig.state.wave.budget_left = 0.0
	_rig.goto(_rig.phase_start(2) + 239.0)
	_run(1.5)
	assert_eq(_rig.of_type(SiegeIds.EV_PUSH).size(), 1)
	assert_eq(_rig.of_type(SiegeIds.EV_PUSH)[0]["roads"], [0, 1, 2])
	var rams := _log.filter(func(e: Dictionary) -> bool: return e["type"] == SiegeIds.ENEMY_RAM)
	assert_eq(rams.size(), 3)
	for road in 3:
		var r: Dictionary = rams.filter(func(e: Dictionary) -> bool: return e["road"] == road)[0]
		assert_almost_eq(r["prog"], _rig.road_end(road) - 40.0, 1e-3, "enters 40 m from the gate")
		assert_eq(r["hp"], 600.0)
	var escort := _log.filter(func(e: Dictionary) -> bool: return e["escort"] and e["type"] == 1)
	assert_eq(escort.size(), 40, "raiders worth 10 threat per slot")
	assert_eq(_rig.state.rams_total, 3)
	assert_eq(_rig.state.wave.rams, 3)
	_run(3.0)
	assert_eq(_rig.of_type(SiegeIds.EV_PUSH).size(), 1, "once")


## Brief 2.4: "an unopposed ram batters the gate for about 20 s (60 HP)" at 1.0 m/s; G2 slowed it to
## 0.75 m/s (docs/decisions/siege.md, "G2 tuning"), so it now walks 40 m / 0.75 m/s = 53.3 s and
## batters the wave's last ~6.7 s (~20 HP). The rule tested: it walks at its speed, then batters
## 3 HP/s until the wave ends.
func test_an_unopposed_ram_walks_in_then_batters_until_the_wave_ends() -> void:
	_start("short", 2, 1)
	_rig.state.wave.budget_left = 0.0
	_rig.goto(_rig.phase_start(2) + 239.0)
	_run(1.5)
	_rig.state.enemies = _rig.state.enemies.filter(
		func(e: SiegeEnemyState) -> bool: return e.type == SiegeIds.ENEMY_RAM
	)
	assert_eq(_rig.state.enemies.size(), 1)
	_rig.run(58.4)
	assert_eq(_rig.state.enemies[0].st, SiegeIds.EN_BATTER, "the ram reached the gate")
	var walk := 40.0 / float(_rig.content.enemy_def(SiegeIds.ENEMY_RAM)["speed_mps"])
	var batter := (239.0 + 1.5 + 58.4) - (240.0 + walk)
	var hp := _rig.content.num("gate.hp")
	assert_between(
		_rig.state.gate_hp, hp - 3.0 * batter - 2.0, hp - 3.0 * batter + 2.0, "3 HP/s at the gate"
	)


func test_the_warm_up_push_is_one_half_hp_ram_without_escort() -> void:
	_start("short", 0, 4)
	_rig.state.wave.budget_left = 0.0
	_rig.goto(_rig.phase_start(0) + 239.0)
	_run(2.0)
	assert_eq(_rig.of_type(SiegeIds.EV_PUSH).size(), 1)
	assert_eq(_log.size(), 1)
	assert_eq(_log[0]["type"], SiegeIds.ENEMY_RAM)
	assert_eq(_log[0]["hp"], 300.0)
	assert_eq(_rig.state.rams_total, 1)


# --- the warm-up wave ---------------------------------------------------------------------------


func test_the_warm_up_sends_raiders_only_for_180_s_then_horsemen() -> void:
	_start("short", 0, 4)
	_run(179.0)
	assert_gt(_log.size(), 10)
	for e in _log:
		assert_eq(e["type"], SiegeIds.ENEMY_RAIDERS)
	_run(2.0)
	_log.clear()
	_rig.state.wave.spawn_in_s = 0.0
	_run(55.0)
	var types := {}
	for e in _log:
		if e["type"] != SiegeIds.ENEMY_RAM:
			types[e["type"]] = true
	assert_eq(types.keys(), [SiegeIds.ENEMY_HORSEMEN])


func test_one_teaching_toast_per_minute_in_the_warm_up() -> void:
	_start("short", 0, 1)
	var seen: Array[int] = []
	for s in 300:
		_rig.goto(_rig.phase_start(0) + float(s) + 0.5)
		_rig.step()
		if seen.is_empty() or seen[-1] != _rig.state.wave.toast_min:
			seen.append(_rig.state.wave.toast_min)
	assert_eq(seen, [1, 2, 3, 4, 5] as Array[int])


func test_no_toast_counter_outside_the_warm_up() -> void:
	_start("short", 2, 1)
	_run(70.0)
	assert_eq(_rig.state.wave.toast_min, 0)


# --- endurance rushes --------------------------------------------------------------------------


func test_endurance_rushes_at_8_16_24_32_and_40_minutes() -> void:
	_start("endurance", 2, 4)
	assert_eq(_rig.state.wave.budget_left, _rig.state.wave.budget)
	var b := _rig.state.wave.budget
	var starts: Array[float] = []
	var ends: Array[float] = []
	var base := _rig.phase_start(2)
	for at in [480.0, 960.0, 1440.0, 1920.0, 2400.0]:
		_rig.goto(base + at - 1.0)
		_rig.state.wave.spawn_in_s = 1.0e9
		for _i in 20 * 40:
			for ev in _rig.step():
				if ev["type"] == SiegeIds.EV_RUSH:
					(starts if ev["on"] == 1 else ends).append(_rig.state.t - base)
			_track()
			_rig.state.enemies.clear()
	assert_eq(starts.size(), 5)
	assert_eq(ends.size(), 5)
	for i in 5:
		assert_between(starts[i], 480.0 * (i + 1) - 0.01, 480.0 * (i + 1) + 0.1)
		assert_almost_eq(ends[i] - starts[i], 30.0, 0.1, "30 s")
	var rush := _log.filter(func(e: Dictionary) -> bool: return e["rush"])
	var threat := 0.0
	for e in rush:
		assert_true([SiegeIds.ENEMY_RAIDERS, SiegeIds.ENEMY_HORSEMEN].has(e["type"]))
		threat += _threat(int(e["type"]))
	assert_between(threat, 5.0 * 0.08 * b - 5.0, 5.0 * 0.08 * b + 1e-6, "8 % of B per rush")
	assert_almost_eq(_rig.state.wave.budget_left, b - 5.0 * 0.08 * b, 1e-6, "taken from B")


func test_rush_enemies_are_flagged_and_a_rush_is_on_for_30_s() -> void:
	_start("endurance", 2, 2)
	_rig.state.wave.spawn_in_s = 1.0e9
	_rig.goto(_rig.phase_start(2) + 480.0)
	_rig.step()
	assert_true(_rig.state.rush_on())
	_run(5.0)
	assert_gt(_log.size(), 0)
	for e in _log:
		assert_true(e["rush"])
	_rig.run(26.0)
	assert_false(_rig.state.rush_on())


func test_other_shifts_have_no_rush() -> void:
	_start("vo2", 2, 4)
	_run(60.0)
	assert_eq(_rig.of_type(SiegeIds.EV_RUSH).size(), 0)
	assert_false(_rig.state.rush_on())


# --- the drill ---------------------------------------------------------------------------------


func test_the_drill_plays_as_wave_1_with_raiders_and_horsemen_only() -> void:
	_start("drill", 0, 2)
	assert_eq(_rig.state.role, SiegeIds.ROLE_BUILD_BREAK, "the role comes from the meta")
	_rig.enter(1, 0.0)
	assert_eq(_rig.state.role, SiegeIds.ROLE_WAVE)
	assert_eq(_rig.state.wave_no, 1)
	assert_eq(_rig.state.waves_total, 1)
	_seen = {}
	_log = []
	_run(99.0)
	var types := {}
	for e in _log:
		types[e["type"]] = true
	assert_false(types.has(SiegeIds.ENEMY_SHIELD_WALL))
	assert_true(types.has(SiegeIds.ENEMY_RAIDERS))
	assert_eq(_rig.of_type(SiegeIds.EV_WAVE_START).size(), 1)
	assert_eq(_rig.of_type(SiegeIds.EV_PUSH).size(), 1, "the push, with its escort")
	var escort := _log.filter(func(e: Dictionary) -> bool: return e["escort"] and e["type"] == 1)
	assert_eq(escort.size(), 20, "10 per slot")
	_rig.enter(2, 0.0)
	assert_true(_rig.state.done, "the drill's wave counts as the last wave")
	assert_eq(_rig.of_type(SiegeIds.EV_WAVE_END).size(), 1)
	assert_eq(_rig.state.wave_gate_hp.size(), 1)
