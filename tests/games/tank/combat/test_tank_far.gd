extends GutTest
## v4: the far frame's enemies (TankFar; SPEC_TANK 3.1): entry, the mode table, the weave and its rate,
## shifts and their bounds, the light's retirement, the heavy's back-off, lanes, difficulty, and that
## nothing ever stands behind the hull or holds a stationary gun.

const CHECKPOINT := 4


static func _quiet(index: int) -> Callable:
	return func(files: Dictionary) -> void:
		(files["mission"]["segments"][index] as Dictionary).merge(
			{"encounters": [], "obstacles": []}, true
		)


func _rig(crew: int = 2, seed_v: int = 7) -> TankRulesRig:
	var rig := TankRulesRig.new(crew, "ashfall_road", seed_v, _quiet(CHECKPOINT))
	rig.no_fire = true
	rig.no_bow = true
	rig.enter(CHECKPOINT, 1.0)
	return rig


func _spawn(rig: TankRulesRig, type: String, hold: float = -1.0) -> TankEnemyState:
	return TankFar.spawn(rig.state, TankAux.of(rig.state), type, hold, false, 0)


func test_a_far_enemy_enters_from_hold_plus_enter_m_and_takes_10_s() -> void:
	for type in TankIds.FAR_KINDS:
		var rig := _rig()
		var e := _spawn(rig, type)
		var def := rig.content.enemy_def(type)
		var span: Array = def["hold_m"]
		assert_between(e.hold_m, float(span[0]), float(span[1]), "%s rolled from hold_m" % type)
		assert_almost_eq(e.range_m, e.hold_m + float(def["enter_m"]), 0.001, type)
		assert_eq(e.mode, TankIds.EM_ENTER)
		assert_eq(e.side, 1, "always ahead")
		assert_eq(e.x_px, 0.0, "no px in the far frame")
		assert_false(e.fixed, "no stationary gun")
		e.gun_s = 1000.0
		rig.run(0.5)
		assert_almost_eq(e.rate_mps, -float(def["enter_mps"]), 0.001, "%s closing" % type)
		rig.run(9.0)
		assert_eq(e.mode, TankIds.EM_ENTER, "%s still rolling in at 9.5 s" % type)
		rig.run(0.6)
		assert_eq(e.mode, TankIds.EM_HOLD, "%s holds after 10 s" % type)
		assert_almost_eq(e.rate_mps, 0.0 if type != TankIds.ENEMY_LIGHT else e.rate_mps, 0.001)


func test_the_spawn_is_capped_by_the_far_field() -> void:
	var rig := _rig()
	var e := _spawn(rig, TankIds.ENEMY_HEAVY, 2500.0)
	assert_eq(e.range_m, TankConst.FAR_SPAWN_M, "nothing spawns beyond the field's end")


func test_the_caps_refuse_a_17th_enemy() -> void:
	var rig := _rig()
	for _i in 30:
		_spawn(rig, TankIds.ENEMY_LIGHT)
	assert_eq(rig.state.enemies.size(), TankConst.MAX_ENEMIES)
	assert_null(_spawn(rig, TankIds.ENEMY_MEDIUM))


func test_lanes_spread_least_used_first_ties_lowest() -> void:
	var rig := _rig()
	var lanes: Array[int] = []
	for _i in 6:
		lanes.append(_spawn(rig, TankIds.ENEMY_MEDIUM).lane)
	assert_eq(lanes, [0, 1, 2, 3, 0, 1] as Array[int])


func test_a_light_weaves_around_its_hold_and_the_rate_is_analytic() -> void:
	var rig := _rig()
	var e := rig.far(TankIds.ENEMY_LIGHT, 1000.0)
	e.gun_s = 1000.0
	var def := rig.content.enemy_def(TankIds.ENEMY_LIGHT)
	var amp := float(def["weave_m"])
	var period := float(def["weave_s"])
	var lo := INF
	var hi := -INF
	for _i in roundi(period / Wl.SIM_DT):
		var was := e.range_m
		rig.step()
		lo = minf(lo, e.range_m)
		hi = maxf(hi, e.range_m)
		var slope := (e.range_m - was) / Wl.SIM_DT
		assert_almost_eq(e.rate_mps, slope, 0.8, "the rate is d(range)/dt, half a tick apart")
	assert_almost_eq(hi - lo, 2.0 * amp, 1.0, "+-%.0f m" % amp)
	assert_almost_eq((hi + lo) * 0.5, 1000.0, 1.0)
	assert_eq(e.hold_m, 1000.0)


func test_the_weave_starts_at_the_hold_so_arriving_never_jumps() -> void:
	for s in 6:
		var rig := _rig(2, 40 + s)
		var e := _spawn(rig, TankIds.ENEMY_LIGHT)
		e.gun_s = 1000.0
		rig.run_until(func() -> bool: return e.mode == TankIds.EM_HOLD, 12.0)
		var was := e.range_m
		rig.step()
		assert_lte(absf(e.range_m - was), 60.0 * TAU / 9.0 * Wl.SIM_DT + 1e-3)


func test_a_medium_shifts_on_its_timer_inside_the_bounds_and_never_nearer_than_its_hold() -> void:
	var rig := _rig()
	var aux := TankAux.of(rig.state)
	var e := _spawn(rig, TankIds.ENEMY_MEDIUM, 1200.0)
	e.gun_s = 1.0e6
	var def := rig.content.enemy_def(TankIds.ENEMY_MEDIUM)
	var lo := float(def["hold_m"][0])
	var hi := float(def["hold_m"][1]) + float(def["shift_m"])
	var every: Array = def["shift_every_s"]
	assert_between(float(aux.enemy_shift[e.id]), float(every[0]), float(every[1]))
	rig.hull().hp = 1.0e9
	rig.hull().hp_max = 1.0e9
	var seen := {}
	var moved := 0
	for _i in roundi(600.0 / Wl.SIM_DT):
		var mode := e.mode
		rig.step()
		if e.mode == TankIds.EM_MOVE and mode != TankIds.EM_MOVE:
			moved += 1
		seen[e.hold_m] = true
		assert_gte(e.hold_m, lo - 1e-6)
		assert_lte(e.hold_m, hi + 1e-6)
	assert_gt(moved, 8, "it keeps manoeuvring")
	assert_gt(seen.size(), 2, "both ways")


func test_a_shift_moves_at_move_mps_with_a_signed_rate_then_holds() -> void:
	var rig := _rig()
	var e := rig.far(TankIds.ENEMY_MEDIUM, 1300.0)
	e.gun_s = 1.0e6
	e.hold_m = 1480.0
	e.mode = TankIds.EM_MOVE
	rig.run(1.0)
	assert_almost_eq(e.rate_mps, 8.0, 0.01, "move_mps, away")
	assert_almost_eq(e.range_m, 1308.0, 0.5)
	e.hold_m = 1300.0
	rig.run(0.1)
	assert_almost_eq(e.rate_mps, -8.0, 0.01, "and back")
	rig.run(5.0)
	assert_eq(e.mode, TankIds.EM_HOLD)
	assert_eq(e.rate_mps, 0.0)
	assert_eq(e.range_m, 1300.0)


func test_a_destroyer_shifts_after_each_shot_within_its_bounds() -> void:
	var rig := _rig()
	var e := rig.far(TankIds.ENEMY_DESTROYER, 1800.0)
	e.mode = TankIds.EM_TELEGRAPH
	e.gun_s = 0.1
	rig.hull().hp = 1.0e9
	rig.hull().hp_max = 1.0e9
	var def := rig.content.enemy_def(TankIds.ENEMY_DESTROYER)
	rig.run(0.2)
	assert_eq(e.mode, TankIds.EM_MOVE, "it fired and shifts")
	assert_almost_eq(absf(e.hold_m - 1800.0), float(def["shift_m"]), 0.001)
	for _i in 12:
		e.gun_s = 0.05
		e.mode = TankIds.EM_TELEGRAPH
		e.range_m = e.hold_m
		rig.run(0.2)
		assert_gte(e.hold_m, float(def["hold_m"][0]) - 1e-6)
		assert_lte(e.hold_m, float(def["hold_m"][1]) + float(def["shift_m"]) + 1e-6)


func test_a_light_retires_past_linger_s_with_no_credit() -> void:
	var rig := _rig()
	var def := rig.content.enemy_def(TankIds.ENEMY_LIGHT)
	var e := rig.far(TankIds.ENEMY_LIGHT, 1000.0)
	TankAux.of(rig.state).enemy_flank_done[e.id] = true
	e.gun_s = 1.0
	rig.hull().hp = 1.0e9
	rig.hull().hp_max = 1.0e9
	rig.run(float(def["linger_s"]) - 2.0)
	assert_ne(e.mode, TankIds.EM_RETIRE, "still at its hold")
	rig.run(3.0)
	assert_eq(e.mode, TankIds.EM_RETIRE, "past linger_s")
	assert_almost_eq(e.rate_mps, 2.0 * float(def["move_mps"]), 0.001, "away, in reverse")
	assert_eq(e.side, 1, "hull still toward us")
	var shots := rig.of_type("shot").size()
	var gone := rig.run_until(func() -> bool: return not rig.state.enemies.has(e), 200.0)
	assert_lt(gone, 200.0, "gone at the field's end")
	assert_eq(rig.of_type("kill").size(), 0)
	assert_eq(rig.state.score.crew_kills, 0)
	assert_eq(rig.of_type("shot").size() - shots, 0, "no fire while retiring")


func test_a_holding_forces_light_never_retires_and_other_kinds_never_leave() -> void:
	var rig := _rig(3)
	rig.hull().hp = 1.0e9
	rig.hull().hp_max = 1.0e9
	var aux := TankAux.of(rig.state)
	var l := TankFar.spawn(rig.state, aux, TankIds.ENEMY_LIGHT, 900.0, true, -1)
	var m := _spawn(rig, TankIds.ENEMY_MEDIUM)
	var d := _spawn(rig, TankIds.ENEMY_DESTROYER)
	var h := _spawn(rig, TankIds.ENEMY_HEAVY)
	rig.run(120.0)
	for e: TankEnemyState in [l, m, d, h]:
		assert_true(rig.state.enemies.has(e))
		assert_ne(e.mode, TankIds.EM_RETIRE)


func test_a_heavy_backs_off_after_taking_its_damage_up_to_retire_to_m() -> void:
	var rig := _rig()
	var aux := TankAux.of(rig.state)
	var h := rig.far(TankIds.ENEMY_HEAVY, 1500.0)
	h.gun_s = 1.0e6
	h.hp = 5000.0
	h.hp_max = 5000.0
	var def := rig.content.enemy_def(TankIds.ENEMY_HEAVY)
	TankShells.damage_enemy(rig.state, aux, h, 30.0, TankEvents.BY_SHELL, 0, rig.events)
	assert_eq(h.mode, TankIds.EM_HOLD, "30 damage: not yet")
	TankShells.damage_enemy(rig.state, aux, h, 20.0, TankEvents.BY_SHELL, 0, rig.events)
	assert_eq(h.mode, TankIds.EM_BACKOFF, "50 damage taken")
	assert_eq(h.hold_m, 1500.0 + float(def["backoff_m"]))
	rig.run(1.0)
	assert_almost_eq(h.rate_mps, float(def["move_mps"]), 0.001, "in reverse")
	rig.run(25.0)
	assert_eq(h.mode, TankIds.EM_HOLD)
	assert_eq(h.range_m, h.hold_m)
	for _i in 20:
		TankShells.damage_enemy(rig.state, aux, h, 50.0, TankEvents.BY_SHELL, 0, rig.events)
	assert_eq(h.hold_m, float(def["retire_to_m"]), "it retires in steps, no farther")


func test_nothing_counts_while_entering_or_backing_off_and_a_telegraph_restarts_in_full() -> void:
	var rig := _rig()
	var e := _spawn(rig, TankIds.ENEMY_HEAVY)
	e.gun_s = 3.0
	rig.run(5.0)
	assert_eq(e.gun_s, 3.0, "rolling in: the gun waits")
	rig.run(5.5)
	var tele := float(rig.content.enemy_def(TankIds.ENEMY_HEAVY)["telegraph_s"])
	assert_eq(e.mode, TankIds.EM_TELEGRAPH)
	assert_almost_eq(e.telegraph_s, tele, 0.6, "a full telegraph at its hold")
	e.mode = TankIds.EM_BACKOFF
	e.hold_m += 100.0
	rig.run(0.1)
	assert_eq(e.telegraph_s, 0.0, "backing off calls it off")
	assert_true(TankAux.of(rig.state).evade.is_empty())


func test_difficulty_scales_hp_and_telegraph_and_never_the_rest() -> void:
	var tele := {}
	for level: String in TankIds.DIFFICULTIES:
		var rig := _rig()
		rig.state.difficulty = level
		var e := _spawn(rig, TankIds.ENEMY_DESTROYER)
		var row: Dictionary = rig.content.value("enemies", "difficulty.%s" % level, {})
		var def := rig.content.enemy_def(TankIds.ENEMY_DESTROYER)
		assert_almost_eq(e.hp_max, float(def["hp"]) * float(row["hp"]), 0.001, level)
		var e2 := rig.far(TankIds.ENEMY_DESTROYER, 1800.0)
		e2.gun_s = 0.5
		var longest := 0.0
		for _i in 40:
			rig.step()
			longest = maxf(longest, e2.telegraph_s)
		tele[level] = longest
		var want := float(def["telegraph_s"]) * float(row["telegraph"])
		assert_almost_eq(longest, want, 0.06, "%s telegraph" % level)
	assert_gt(tele[TankIds.DIFF_EASY], tele[TankIds.DIFF_NORMAL])
	assert_gt(tele[TankIds.DIFF_NORMAL], tele[TankIds.DIFF_HARD])


func test_accuracy_is_scaled_and_capped_at_095() -> void:
	var rig := _rig()
	assert_eq(TankEnemies.chance(rig.state, 0.6), 0.6, "normal")
	rig.state.difficulty = TankIds.DIFF_HARD
	assert_almost_eq(TankEnemies.chance(rig.state, 0.6), 0.72, 1e-6)
	assert_eq(TankEnemies.chance(rig.state, 0.9), 0.95, "capped")
	rig.state.difficulty = TankIds.DIFF_EASY
	assert_almost_eq(TankEnemies.chance(rig.state, 0.6), 0.45, 1e-6)


## Every 100 ticks of a live Advance: every far enemy ahead at a positive range, none behind, none
## fixed; no rear spawn anywhere in the shipped encounter lists.
func test_no_enemy_stands_behind_and_no_gun_is_stationary_in_play() -> void:
	var rig := TankRulesRig.new(4)
	rig.no_fire = true
	rig.enter(2, 1.0)
	rig.hull().hp = 1.0e9
	rig.hull().hp_max = 1.0e9
	for i in 3000:
		rig.step()
		if i % 100 != 0:
			continue
		for e in rig.state.enemies:
			assert_eq(e.side, 1)
			assert_false(e.fixed)
			if e.is_near():
				assert_gt(e.x_px, rig.hull().x_px + rig.hull().hull_w, "near: ahead of the front")
			else:
				assert_gt(e.range_m, 0.0, "far: a real range")
	for index in [3, 6, 9]:
		rig.enter(index, 1.0)
		assert_gt(rig.state.enemies.size(), 0)
		for e in rig.state.enemies:
			assert_true(e.gun_line)
			assert_false(e.fixed, "a holding force, not a gun line")
			assert_eq(e.side, 1)
