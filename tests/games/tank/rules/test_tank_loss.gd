extends GutTest
## Tank loss and the stage restart (SPEC_TANK 3.4; BRIEF 4.6.3): hull at 0 on Normal and Hard is TANK
## LOST, an 8 s tow, then the current stage starts over with its enemies back; the plan's phase and
## clock run on and no directive moves. Easy keeps the breakdown. A rider in rescue, AFK or dropped, a
## won stage and every phase but WORK hold the hull at 1 HP.

const Harness := preload("res://tests/games/tank/effort/tank_effort_harness.gd")
const DEPOT := 0
const ADVANCE := 1
const HOLD := 2
const CHECKPOINT := 3
const BOSS := 10


func _rig(
	difficulty: String = TankIds.DIFF_NORMAL, index: int = ADVANCE, crew: int = 2
) -> TankRulesRig:
	var rig := TankRulesRig.new(crew, "ashfall_road", 7)
	rig.state.difficulty = difficulty
	rig.enter(index, 1.0)
	return rig


func _kill_the_tank(rig: TankRulesRig) -> Array[Dictionary]:
	rig.state.hull.hp = 1.0
	var events: Array[Dictionary] = []
	TankHullRules.hit(rig.state, 1000.0, TankIds.SHELL_ENEMY, 300.0, events)
	return events


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(e: Dictionary) -> String: return str(e["type"]))


# --- The level ------------------------------------------------------------------------------------


func test_normal_and_hard_lose_the_tank_at_zero() -> void:
	for d: String in [TankIds.DIFF_NORMAL, TankIds.DIFF_HARD]:
		var rig := _rig(d)
		var events := _kill_the_tank(rig)
		var hull := rig.state.hull
		assert_eq(hull.hp, 0.0, d)
		assert_false(hull.breakdown, d)
		assert_eq(hull.tow_s, 8.0, d)
		assert_true(hull.out_of_action(), d)
		assert_eq(rig.state.score.losses, 1, d)
		assert_eq(rig.state.score.breakdowns, 0, d)
		var lost: Array = events.filter(
			func(e: Dictionary) -> bool: return e["type"] == TankEvents.TANK_LOST
		)
		assert_eq(lost.size(), 1, d)
		assert_eq(lost[0]["n"], 1, d)
		assert_eq(lost[0]["sg"], TankIds.seg_code(TankIds.SEG_ADVANCE), d)
		assert_eq(lost[0]["st"], 1, d)
		assert_does_not_have(_types(events), TankEvents.BREAKDOWN, d)


func test_easy_keeps_the_breakdown_and_you_cannot_lose() -> void:
	var rig := _rig(TankIds.DIFF_EASY)
	var events := _kill_the_tank(rig)
	var hull := rig.state.hull
	assert_true(hull.breakdown)
	assert_eq(hull.tow_s, 0.0)
	assert_eq(rig.state.score.losses, 0)
	assert_eq(rig.state.score.breakdowns, 1)
	assert_has(_types(events), TankEvents.BREAKDOWN)
	assert_does_not_have(_types(events), TankEvents.TANK_LOST)


func test_the_drill_never_loses_or_breaks_down() -> void:
	for d: String in TankIds.DIFFICULTIES:
		var rig := TankRulesRig.new(1, "drill", 2)
		rig.state.difficulty = d
		rig.enter(1, 1.0)
		var events := _kill_the_tank(rig)
		assert_eq(rig.state.hull.hp, 1.0, "%s: a WARMUP kind holds the hull at 1 HP" % d)
		assert_eq(rig.state.hull.tow_s, 0.0, d)
		assert_false(rig.state.hull.breakdown, d)
		assert_does_not_have(_types(events), TankEvents.TANK_LOST, d)
		assert_false(TankDifficulty.tank_loss(rig.state), d)


func test_the_damage_counts_after_the_difficulty_and_the_hit_event_before_it() -> void:
	for row: Array in [
		[TankIds.DIFF_EASY, 0.55], [TankIds.DIFF_NORMAL, 1.0], [TankIds.DIFF_HARD, 1.5]
	]:
		var rig := _rig(str(row[0]), ADVANCE, 4)
		rig.state.hull.hp = 100.0
		var events: Array[Dictionary] = []
		var lost := TankHullRules.hit(rig.state, 10.0, TankIds.SHELL_ENEMY, 0.0, events)
		var crew_hit := 10.0 * rig.content.crew_damage_scale(4)
		assert_almost_eq(lost, crew_hit * float(row[1]), 1e-6, str(row[0]))
		assert_almost_eq(rig.state.hull.hp, 100.0 - crew_hit * float(row[1]), 1e-6, str(row[0]))
		assert_eq(
			events[0]["dmg"], roundi(crew_hit), "%s: the haptics read the same numbers" % row[0]
		)


func test_the_berm_absorbs_before_the_difficulty() -> void:
	var rig := _rig(TankIds.DIFF_HARD, ADVANCE, 4)
	rig.state.hull.hp = 100.0
	rig.state.hull.berm_hp = 4.0
	var lost := TankHullRules.hit(rig.state, 10.0, TankIds.SHELL_ENEMY, 0.0, [])
	assert_almost_eq(lost, (10.0 * rig.content.crew_damage_scale(4) - 4.0) * 1.5, 1e-6)
	assert_eq(rig.state.hull.berm_hp, 0.0)


# --- BRIEF 4.6.3 and the won stage ---------------------------------------------------------------


func _assert_holds_at_1(rig: TankRulesRig, why: String) -> void:
	rig.state.hull.hp = 5.0
	var events: Array[Dictionary] = []
	assert_true(TankHullRules.protected(rig.state), why)
	TankHullRules.hit(rig.state, 1000.0, TankIds.SHELL_ENEMY, 0.0, events)
	assert_eq(rig.state.hull.hp, 1.0, "%s: the hit leaves 1 HP" % why)
	assert_eq(rig.state.hull.tow_s, 0.0, why)
	assert_false(rig.state.hull.breakdown, why)
	assert_does_not_have(_types(events), TankEvents.TANK_LOST, why)
	# And again at 1 HP: never below it.
	TankHullRules.hit(rig.state, 1000.0, TankIds.SHELL_ENEMY, 0.0, events)
	assert_eq(rig.state.hull.hp, 1.0, why)


func test_a_rider_in_rescue_afk_or_dropped_holds_the_hull_at_one_hp_on_every_level() -> void:
	for d: String in TankIds.DIFFICULTIES:
		var rig := _rig(d)
		rig.rescue[2] = true
		rig.step()
		_assert_holds_at_1(rig, "%s rescue" % d)
		rig = _rig(d)
		rig.afk[2] = true
		rig.step()
		_assert_holds_at_1(rig, "%s AFK" % d)
		rig = _rig(d)
		rig.connected[2] = false
		rig.step()
		_assert_holds_at_1(rig, "%s dropped" % d)


func test_the_rider_recovering_ends_the_protection() -> void:
	var rig := _rig()
	rig.rescue[2] = true
	rig.step()
	assert_true(TankHullRules.protected(rig.state))
	rig.rescue[2] = false
	rig.step()
	assert_false(TankHullRules.protected(rig.state))
	_kill_the_tank(rig)
	assert_eq(rig.state.hull.tow_s, 8.0)


func test_a_won_stage_holds_the_hull_at_one_hp() -> void:
	var rig := _rig(TankIds.DIFF_HARD)
	rig.state.seg.objective_done = true
	_assert_holds_at_1(rig, "objective done")


func test_a_checkpoint_or_the_depot_holds_the_hull_at_one_hp() -> void:
	_assert_holds_at_1(_rig(TankIds.DIFF_HARD, CHECKPOINT), "checkpoint")
	_assert_holds_at_1(_rig(TankIds.DIFF_HARD, DEPOT), "depot")


# --- The tow -------------------------------------------------------------------------------------


func test_a_loss_clears_the_field_and_the_tow_blocks_fire_drive_and_spawns() -> void:
	var rig := _rig()
	rig.state.hull.distance_m = 400.0
	rig.state.hull.x_px = TankConst.m_to_px(400.0)
	rig.far(TankIds.ENEMY_MEDIUM)
	rig.near(TankIds.ENEMY_RECON)
	rig.load_shell()
	rig.events.clear()
	_kill_the_tank(rig)
	assert_eq(rig.state.enemies.size(), 0)
	assert_eq(rig.state.shells.size(), 0)
	assert_eq(rig.state.hull.speed_mps, 0.0)
	rig.send(rig.peer_of(TankIds.ENGINE_DYNAMO), {"k": "fire"})
	rig.run(7.0)
	assert_gt(rig.state.hull.tow_s, 0.0)
	assert_eq(rig.of_type(TankEvents.SHOT).size(), 0, "nothing fires under tow")
	assert_eq(rig.state.hull.speed_mps, 0.0, "nothing drives")
	assert_almost_eq(rig.state.hull.distance_m, 400.0, 1e-6)
	assert_eq(rig.state.enemies.size(), 0, "nothing spawns")
	assert_eq(rig.of_type(TankEvents.AMBUSH).size(), 0)
	assert_eq(rig.state.hull.grade_pct, 0.0, "the rider pedals flat")


func test_a_hit_during_the_tow_does_nothing() -> void:
	var rig := _rig()
	_kill_the_tank(rig)
	var events: Array[Dictionary] = []
	assert_eq(TankHullRules.hit(rig.state, 50.0, TankIds.SHELL_ENEMY, 0.0, events), 0.0)
	assert_eq(events[0]["dmg"], 0)
	assert_eq(rig.state.score.losses, 1, "one loss")


func test_a_shell_that_loses_the_tank_takes_the_others_with_it() -> void:
	var rig := _rig()
	rig.no_fire = true
	rig.no_bow = true
	rig.state.hull.hp = 1.0
	var aux := TankAux.of(rig.state)
	var events: Array[Dictionary] = []
	for _i in 3:
		TankEnemies.launch_far(
			rig.state, aux, 800.0, TankIds.SHELL_ENEMY, 50.0, 2.0, false, 0, 1, events
		)
	assert_eq(rig.state.shells.size(), 3)
	for s in rig.state.shells:
		s.will_hit = true
		s.left_s = 0.01
	var out: Array[Dictionary] = []
	TankShells.step(rig.state, aux, Wl.SIM_DT, out)
	assert_eq(rig.state.shells.size(), 0, "the field is clear")
	assert_eq(rig.state.score.losses, 1)
	assert_eq(_types(out).count(TankEvents.TANK_LOST), 1)


func test_a_loss_at_the_shell_cap_stops_the_other_enemies_guns() -> void:
	var rig := _rig()
	rig.no_fire = true
	rig.no_bow = true
	rig.state.hull.hp = 0.5
	rig.state.hull.evasive = false
	for type: String in [TankIds.ENEMY_MEDIUM, TankIds.ENEMY_MEDIUM, TankIds.ENEMY_MEDIUM]:
		rig.far(type).gun_s = 0.0
	var aux := TankAux.of(rig.state)
	for _i in int(rig.content.num("tanks", "caps.shells", 24.0)):
		var s := TankShellState.new()
		s.id = rig.state.take_id()
		s.far = true
		s.left_s = 99.0
		rig.state.shells.append(s)
	# One of three rolls at 60 % lands at once at the cap; the rest must not fire after the clear.
	var out: Array[Dictionary] = []
	for _i in 200:
		TankEnemies.fire(rig.state, aux, Wl.SIM_DT, out)
		if rig.state.hull.tow_s > 0.0:
			break
		for e in rig.state.enemies:
			e.gun_s = 0.0
	assert_gt(rig.state.hull.tow_s, 0.0)
	var at := _types(out).find(TankEvents.TANK_LOST)
	assert_eq(_types(out).slice(at).count(TankEvents.SHOT), 0, "no shot after the loss")
	assert_eq(rig.state.shells.size(), 0)


func test_a_loss_stops_the_behemoth() -> void:
	var rig := _rig(TankIds.DIFF_NORMAL, BOSS)
	assert_eq(rig.state.boss.phase, TankIds.BOSS_PHASE_1)
	rig.state.boss.telegraph_s = 3.0
	_kill_the_tank(rig)
	assert_eq(rig.state.boss.phase, TankIds.BOSS_NONE)
	assert_eq(rig.state.boss.telegraph_s, 0.0)
	rig.run(2.0)
	assert_eq(rig.of_type(TankEvents.SHOT).size(), 0)


# --- The restart ---------------------------------------------------------------------------------


func _tow_out(rig: TankRulesRig) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for _i in 400:
		out.append_array(rig.step())
		if rig.state.hull.tow_s <= 0.0:
			break
	return out


func test_the_restart_of_an_advance_sets_the_road_and_its_enemies_back() -> void:
	var rig := _rig()
	rig.no_fire = true
	rig.no_bow = true
	rig.state.hull.hp_max = 180.0
	rig.state.hull.distance_m = 660.0
	rig.state.hull.x_px = TankConst.m_to_px(660.0)
	rig.state.seg.next_encounter = 4
	rig.state.hull.berm_hp = 12.0
	for o in rig.state.obstacles:
		o.cleared = true
	rig.set_rack(0)
	_kill_the_tank(rig)
	var out := _tow_out(rig)
	var sg := rig.state.seg
	var hull := rig.state.hull
	assert_eq(hull.tow_s, 0.0)
	assert_lt(hull.distance_m, 5.0, "from the start of the road")
	assert_eq(sg.next_encounter, 0, "no encounter driven up to yet")
	assert_false(sg.objective_done)
	assert_almost_eq(hull.hp, 180.0 * 0.7, 1e-6, "tanks.json hull.restart_hp_frac")
	assert_eq(hull.berm_hp, 0.0)
	assert_eq(rig.steam().rack, int(rig.content.num("tanks", "steam.rack_start", 0.0)))
	assert_false(rig.state.obstacles.is_empty(), "the barricade stands again")
	for o in rig.state.obstacles:
		assert_false(o.cleared)
	var restarts: Array = out.filter(
		func(e: Dictionary) -> bool: return e["type"] == TankEvents.STAGE_RESTART
	)
	assert_eq(restarts.size(), 1)
	assert_eq(restarts[0]["sg"], TankIds.seg_code(TankIds.SEG_ADVANCE))
	assert_eq(restarts[0]["st"], 1)
	assert_eq(restarts[0]["hp"], roundi(180.0 * 0.7))
	rig.run_until(func() -> bool: return not rig.state.enemies.is_empty(), 60.0)
	assert_false(rig.state.enemies.is_empty(), "the road's first enemy comes back")


func test_the_restart_keeps_a_better_hull() -> void:
	var rig := _rig()
	_kill_the_tank(rig)
	rig.state.hull.hp = 140.0
	_tow_out(rig)
	assert_eq(rig.state.hull.hp, 140.0)


func test_the_restart_of_a_holding_action_brings_its_force_back_and_times_its_near_list_anew(
) -> void:
	var rig := _rig(TankIds.DIFF_NORMAL, HOLD, 3)
	rig.no_fire = true
	rig.no_bow = true
	rig.run(50.0)
	var aux := TankAux.of(rig.state)
	assert_eq(rig.of_type(TankEvents.AMBUSH).size(), 2, "both near entries came")
	var total := rig.state.gun_line.guns_total
	assert_gt(total, 0)
	for e in rig.state.enemies.duplicate():
		if e.gun_line:
			TankShells.kill_enemy(rig.state, aux, e, TankEvents.BY_SHELL, 0, rig.events)
			break
	assert_eq(rig.state.gun_line.guns_left, total - 1)
	_kill_the_tank(rig)
	assert_eq(rig.state.gun_line.guns_total, 0, "no force under tow")
	rig.run(1.0)
	assert_false(rig.state.seg.objective_done, "a cleared field under tow is no objective")
	rig.events.clear()
	_tow_out(rig)
	assert_eq(rig.state.gun_line.guns_total, total)
	assert_eq(rig.state.gun_line.guns_left, total)
	var far := 0
	for e in rig.state.enemies:
		if e.gun_line:
			far += 1
			assert_eq(e.mode, TankIds.EM_ENTER, "it enters again")
	assert_eq(far, total)
	assert_eq(rig.state.seg.next_near, 0)
	assert_eq(rig.of_type(TankEvents.AMBUSH).size(), 0, "not both at once on the restart")
	rig.run(16.0)
	assert_eq(rig.of_type(TankEvents.AMBUSH).size(), 1, "at_s 15 counts from the restart")
	assert_false(rig.state.obstacles.is_empty(), "the props stand")


func test_the_restart_of_the_boss_fight_brings_a_fresh_behemoth() -> void:
	var rig := _rig(TankIds.DIFF_NORMAL, BOSS)
	var b := rig.state.boss
	b.bogie_hp[0] = 0.0
	b.range_m = 1100.0
	_kill_the_tank(rig)
	rig.events.clear()
	var out := _tow_out(rig)
	assert_eq(b.phase, TankIds.BOSS_PHASE_1)
	assert_eq(b.bogie_hp[0], b.bogie_max)
	assert_almost_eq(b.range_m, 1450.0, 1.0)
	assert_has(_types(out), TankEvents.BOSS_PHASE, "the view hears it")


func test_the_plan_phase_and_its_clock_run_on_and_no_lap_or_segment_moves() -> void:
	var rig := _rig()
	rig.run(10.0)
	var phase := rig.state.seg.phase_index
	var t := rig.state.seg.elapsed_s
	rig.events.clear()
	_kill_the_tank(rig)
	_tow_out(rig)
	assert_eq(rig.state.seg.phase_index, phase, "the same phase")
	assert_almost_eq(rig.state.seg.elapsed_s, t + 8.0, 0.11, "its clock ran on")
	assert_eq(rig.of_type(TankEvents.SEGMENT).size(), 0, "no segment event")


func test_max_s_during_a_tow_ends_it_and_the_next_segment_starts_clean() -> void:
	var rig := _rig()
	rig.state.hull.hp_max = 150.0
	_kill_the_tank(rig)
	rig.run(1.0)
	assert_gt(rig.state.hull.tow_s, 0.0)
	rig.enter(HOLD, 0.0, Wl.ENDED_MAX_S)
	assert_eq(rig.state.hull.tow_s, 0.0, "begin clears the tow")
	assert_almost_eq(rig.state.hull.hp, 150.0 * 0.7, 1e-6)
	assert_false(rig.state.enemies.is_empty(), "the next stage's force is up")
	assert_eq(rig.of_type(TankEvents.STAGE_RESTART).size(), 0, "no restart on top of it")
	assert_eq(rig.state.score.overruns, 1, "it counts as an overrun, as any max_s")


func test_a_tow_into_the_cool_down_withdraws_with_no_error() -> void:
	var rig := _rig(TankIds.DIFF_NORMAL, BOSS)
	_kill_the_tank(rig)
	rig.enter(11, 0.0, Wl.ENDED_MAX_S)
	assert_eq(rig.state.hull.tow_s, 0.0)
	assert_eq(rig.state.outcome, TankIds.OUTCOME_WITHDRAWN)
	assert_eq(rig.of_type(TankEvents.BOSS_PHASE).size(), 1, "just its start: nothing to withdraw")


func test_losses_are_counted_across_restarts() -> void:
	var rig := _rig()
	for n in [1, 2, 3]:
		_kill_the_tank(rig)
		assert_eq(rig.state.score.losses, n)
		_tow_out(rig)


# --- The effort plan -----------------------------------------------------------------------------


## No call to ctx.directives from any of this: the rules hold no directives, and the director on a
## state with a loss in it requests nothing beyond what the same phase requests without one.
func test_the_rules_never_reach_the_directives_and_the_plans_do_not_move() -> void:
	var rig := _rig()
	var before := {}
	for peer: int in rig.plans:
		before[peer] = (rig.plans[peer] as EffortPlan).to_dict()
	_kill_the_tank(rig)
	_tow_out(rig)
	for peer: int in rig.plans:
		assert_eq((rig.plans[peer] as EffortPlan).to_dict(), before[peer], "the plan stands")
	var src := FileAccess.get_file_as_string("res://src/games/tank/combat/tank_encounters.gd")
	assert_false(src.contains("directives"), "TankEncounters reaches no directive")
	src = FileAccess.get_file_as_string("res://src/games/tank/rules/tank_hull_rules.gd")
	assert_false(src.contains("directives"), "TankHullRules reaches no directive")


## The director over a state whose tank is lost and restarts: no split, no replan, no end_phase.
func test_a_loss_records_no_split_replan_or_end_phase_on_the_directives() -> void:
	var h := Harness.new()
	h.build(2)
	h.step(ADVANCE)
	var events: Array[Dictionary] = []
	h.state.hull.hp = 1.0
	TankEncounters.lose(h.state, TankAux.of(h.state), events)
	assert_eq(h.state.score.losses, 1)
	for _i in roundi(4.0 / Wl.SIM_DT):
		h.step(ADVANCE)
	TankEncounters.restart(h.state, TankAux.of(h.state), events)
	for _i in roundi(4.0 / Wl.SIM_DT):
		h.step(ADVANCE)
	assert_eq(h.dirs().splits.size(), 0)
	assert_eq(h.dirs().replans.size(), 0)
	assert_eq(h.ended.size(), 0)


# --- Free roam -----------------------------------------------------------------------------------


func test_a_roam_loss_stays_on_the_road_and_costs_the_breakdown_points() -> void:
	var rig := TankRulesRig.new(3, "roam_30", 7)
	rig.enter(1, 10.0)
	rig.no_fire = true
	rig.no_bow = true
	var r := rig.state.roam
	var aux := TankAux.of(rig.state)
	rig.far(TankIds.ENEMY_MEDIUM)
	r.strong_id[0] = rig.far(TankIds.ENEMY_HEAVY).id
	var at := r.map_m
	var points := r.points
	var events := _kill_the_tank(rig)
	TankRoam.post(rig.state, aux, events)
	assert_eq(r.points - points, int(rig.content.num("valley", "points.breakdown", -40.0)))
	assert_eq(rig.state.enemies.size(), 0)
	assert_eq(r.strong_id[0], 0, "the strongpoint's enemy is gone")
	r.patrol_s = 0.0
	var patrols := r.patrols
	rig.run(7.0)
	assert_eq(r.patrols, patrols, "no patrol under tow")
	assert_eq(rig.state.enemies.size(), 0)
	assert_almost_eq(r.map_m, at, 0.01, "no movement")
	_tow_out(rig)
	assert_eq(rig.state.hull.tow_s, 0.0)
	assert_almost_eq(r.map_m, at, 2.0, "no distance reset: it goes on from where it stood")
	assert_gt(rig.state.hull.hp, 0.0)
	assert_eq(rig.state.enemies.size(), 0, "the field stays clear")


func test_roam_on_easy_breaks_down() -> void:
	var rig := TankRulesRig.new(3, "roam_30", 7)
	rig.state.difficulty = TankIds.DIFF_EASY
	rig.enter(1, 10.0)
	_kill_the_tank(rig)
	assert_true(rig.state.hull.breakdown)
	assert_eq(rig.state.score.losses, 0)


# --- The score -----------------------------------------------------------------------------------


func _scored() -> TankState:
	var s := TankFixtures.state(1)
	for r in s.riders:
		r.work_s = 100.0
		r.band_s = 100.0
	s.score.shots = 10
	s.score.hits = 10
	s.score.stages_clean = 3
	s.score.behemoth_killed = true
	s.score.breakdowns = 0
	s.score.losses = 0
	return s


func test_each_loss_costs_survival_and_caps_the_grade_at_a() -> void:
	var s := _scored()
	var clean := TankScore.summary(s)
	assert_eq(clean["grade"], "S", "S needs no loss")
	assert_eq(clean["survival"], 1.0)
	s.score.losses = 1
	var one := TankScore.summary(s)
	assert_almost_eq(float(one["survival"]), 0.75, 1e-6)
	assert_almost_eq(float(one["score"]), float(clean["score"]) - 1000.0 * 0.2 * 0.25, 1e-3)
	assert_eq(one["grade"], "A", "920 points, but a loss caps it")
	s.score.losses = 2
	assert_almost_eq(float(TankScore.summary(s)["survival"]), 0.5, 1e-6)
	s.score.losses = 4
	assert_eq(TankScore.summary(s)["survival"], 0.0, "floored at 0")
	s.score.breakdowns = 1
	s.score.losses = 1
	assert_almost_eq(float(TankScore.summary(s)["survival"]), 0.5, 1e-6, "both count")


func test_the_cap_never_lifts_a_lower_grade() -> void:
	var s := _scored()
	s.score.behemoth_killed = false
	s.score.stages_clean = 0
	s.score.losses = 1
	for r in s.riders:
		r.band_s = 0.0
	assert_eq(TankScore.summary(s)["grade"], "D")


func test_score_stages_is_per_mission() -> void:
	var c := TankFixtures.content("ambush_15")
	assert_eq(float(c.mission().get("score_stages", 0.0)), 1.0)
	var s := TankRulesRig.new(1, "ambush_15").state
	s.score.stages_clean = 1
	assert_almost_eq(float(TankScore.summary(s)["objectives"]), 0.6, 1e-6, "one stage is the lot")
	var road := _scored()
	road.score.stages_clean = 1
	road.score.behemoth_killed = false
	assert_almost_eq(float(TankScore.summary(road)["objectives"]), 0.2, 1e-6, "ashfall has three")


func test_the_brass_unlock_needs_no_loss_too() -> void:
	var s := _scored()
	assert_has(TankScore.unlocks(s, "S", true), "brass_machinery")
	s.score.losses = 1
	assert_does_not_have(TankScore.unlocks(s, "S", true), "brass_machinery")
