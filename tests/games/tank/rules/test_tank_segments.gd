extends GutTest
## The crew's place in the mission (brief 2.3, 2.4): segment events, objectives and the hold before
## min_s, overruns at max_s, checkpoints, the depot's drills, the cool-down and the outcome.

const DEPOT := 0
const ADVANCE := 1
const GUN_LINE := 2
const CHECKPOINT := 3
const STAGE2_ADVANCE := 4
const BOSS := 10


static func _patch(index: int, props: Dictionary) -> Callable:
	return func(files: Dictionary) -> void:
		(files["mission"]["segments"][index] as Dictionary).merge(props, true)


func test_each_new_segment_raises_a_segment_event_with_its_stage() -> void:
	var rig := TankRulesRig.new(1)
	rig.enter(DEPOT, 0.0)
	rig.enter(ADVANCE, 0.0)
	rig.enter(GUN_LINE, 0.0)
	rig.enter(CHECKPOINT, 0.0)
	rig.enter(BOSS, 0.0)
	rig.enter(11, 0.0)
	var seen := rig.of_type("segment")
	assert_eq(seen.size(), 6)
	var want := [
		[0, TankIds.SEG_DEPOT, 0],
		[1, TankIds.SEG_ADVANCE, 1],
		[2, TankIds.SEG_GUN_LINE, 1],
		[3, TankIds.SEG_CHECKPOINT, 1],
		[10, TankIds.SEG_BOSS, 4],
		[11, TankIds.SEG_COOLDOWN, 0],
	]
	for i in want.size():
		assert_eq(
			[seen[i]["i"], seen[i]["sg"], seen[i]["st"]],
			[want[i][0], TankIds.seg_code(want[i][1]), want[i][2]]
		)
	rig.run(1.0)
	assert_eq(rig.of_type("segment").size(), 6, "once per segment")
	assert_true(rig.state.in_cooldown())


func test_the_hull_hp_at_each_segment_end_is_recorded() -> void:
	var rig := TankRulesRig.new(1)
	rig.enter(ADVANCE, 0.0)
	rig.hull().hp = 77.0
	rig.enter(GUN_LINE, 0.0)
	rig.hull().hp = 55.0
	rig.enter(CHECKPOINT, 0.0)
	assert_eq(rig.state.score.hp_by_segment, [77, 55] as Array[int])


func test_a_checkpoint_adds_its_hp_to_the_maximum_and_heals_that_much() -> void:
	var rig := TankRulesRig.new(1)
	var base := rig.hull().hp_max
	var bonus := rig.content.num("tanks", "hull.checkpoint_hp", 20.0)
	assert_between(bonus, 10.0, 30.0, "20 HP in the brief, +-50%")
	rig.enter(GUN_LINE, 0.0)
	rig.hull().hp = 60.0
	rig.enter(CHECKPOINT, 0.0)
	assert_eq(rig.hull().hp_max, base + bonus)
	assert_eq(rig.hull().hp, 60.0 + bonus)
	rig.hull().hp = base + 15.0
	rig.enter(6, 0.0)
	assert_eq(rig.hull().hp_max, base + 2.0 * bonus)
	assert_eq(rig.hull().hp, minf(base + 15.0 + bonus, base + 2.0 * bonus))
	rig.enter(STAGE2_ADVANCE, 0.0)
	rig.enter(9, 0.0)
	assert_eq(rig.hull().hp_max, base + 3.0 * bonus, "the third checkpoint")


## v3: rotation is gone (seat choice replaces it): the checkpoint moves nobody and raises no
## rotation event; every rider keeps its seat.
func test_nobody_moves_at_the_checkpoint() -> void:
	var rig := TankRulesRig.new(3)
	rig.enter(GUN_LINE, 1.0)
	rig.events.clear()
	rig.enter(CHECKPOINT, 0.0)
	rig.enter(STAGE2_ADVANCE, 0.0)
	assert_eq(rig.of_type("rotation").size(), 0)
	assert_eq(rig.rider(1).engine, "diesel")
	assert_eq(rig.state.station("dynamo").slot, 1)
	assert_eq(rig.state.station("steam").peer, 3)
	assert_true(rig.state.station("feed").is_empty())


func test_rotation_off_never_moves_anyone() -> void:
	var rig := TankRulesRig.new(3, "ashfall_road", false)
	for index in [ADVANCE, CHECKPOINT, STAGE2_ADVANCE, BOSS]:
		rig.enter(index, 1.0)
	assert_eq(rig.of_type("rotation").size(), 0)
	assert_eq(rig.rider(1).engine, "diesel")


# --- Objectives ----------------------------------------------------------------------------------


func test_an_advance_is_done_at_the_halt_line_and_holds_until_min_s() -> void:
	var rig := TankRulesRig.new(
		1,
		"ashfall_road",
		true,
		7,
		_patch(ADVANCE, {"encounters": [], "obstacles": [], "terrain": [[0, -3]], "length_m": 150})
	)
	rig.no_fire = true
	rig.enter(ADVANCE, 1.0)
	assert_false(rig.state.seg.objective_done)
	rig.run_until(func() -> bool: return rig.state.seg.objective_done, 120.0)
	assert_true(rig.state.seg.objective_done)
	assert_true(rig.state.seg.regroup, "Regroup until min_s")
	rig.run(0.2)
	assert_true(rig.hull().holding)
	assert_eq(rig.hull().speed_mps, 0.0)
	rig.run_until(func() -> bool: return not rig.state.seg.regroup, 120.0)
	assert_gte(rig.state.seg.elapsed_s, 90.0, "never before min_s")
	assert_true(rig.state.seg.objective_done, "stays done")


func test_a_gun_line_is_done_when_every_gun_has_fallen() -> void:
	var rig := TankRulesRig.new(1)
	rig.enter(GUN_LINE, 1.0)
	var aux := TankAux.of(rig.state)
	assert_false(rig.state.seg.objective_done)
	var guns: Array = rig.state.enemies.duplicate()
	assert_gte(guns.size(), 2)
	TankShells.kill_enemy(rig.state, aux, guns[0], TankEvents.BY_SHELL, 0, rig.events)
	rig.run(0.1)
	assert_false(rig.state.seg.objective_done)
	assert_eq(rig.state.gun_line.guns_left, guns.size() - 1)
	assert_false(rig.hull().traps_cleared)
	for i in range(1, guns.size()):
		TankShells.kill_enemy(rig.state, aux, guns[i], TankEvents.BY_SHELL, 0, rig.events)
	rig.run(0.1)
	assert_true(rig.state.seg.objective_done)
	assert_true(rig.hull().traps_cleared, "the blade shoves the tank traps aside")
	for o in rig.state.obstacles:
		if o.code == TankIds.obstacle_code(TankIds.OBST_TANK_TRAPS):
			assert_true(o.cleared)
	assert_true(rig.state.seg.regroup)


func test_the_boss_objective_is_the_behemoth_dead() -> void:
	var rig := TankRulesRig.new(1)
	rig.enter(BOSS, 1.0)
	rig.run(1.0)
	assert_false(rig.state.seg.objective_done)
	rig.state.boss.phase = TankIds.BOSS_DEAD
	rig.run(0.1)
	assert_true(rig.state.seg.objective_done)


func test_fixed_phases_never_complete() -> void:
	for index in [DEPOT, CHECKPOINT]:
		var rig := TankRulesRig.new(1)
		rig.enter(index, 20.0)
		rig.run(30.0)
		assert_false(rig.state.seg.objective_done)
		assert_false(rig.state.seg.regroup)


# --- Overruns ------------------------------------------------------------------------------------


func test_an_overrun_counts_flags_the_stage_and_costs_the_clean_stage_credit() -> void:
	var rig := TankRulesRig.new(1)
	rig.enter(ADVANCE, 0.0)
	rig.enter(GUN_LINE, 0.0, Wl.ENDED_MAX_S)
	assert_eq(rig.state.score.overruns, 1)
	assert_true(rig.state.seg.overrun)
	assert_true(rig.state.score.stage_overrun[0])
	var ev := rig.of_type("overrun")
	assert_eq([ev[0]["sg"], ev[0]["st"]], [TankIds.seg_code(TankIds.SEG_ADVANCE), 1])
	rig.enter(CHECKPOINT, 0.0, Wl.ENDED_END_PHASE)
	assert_eq(rig.state.score.stages_clean, 0, "a stage with an overrun is not clean")
	var ok := TankRulesRig.new(1)
	ok.enter(ADVANCE, 0.0)
	ok.enter(GUN_LINE, 0.0, Wl.ENDED_END_PHASE)
	ok.enter(CHECKPOINT, 0.0, Wl.ENDED_END_PHASE)
	assert_eq(ok.state.score.stages_clean, 1)
	assert_false(ok.state.seg.overrun)


func test_an_advance_overrun_tows_the_tank_to_the_halt_line() -> void:
	var rig := TankRulesRig.new(1)
	rig.no_fire = true
	rig.enter(ADVANCE, 100.0)
	rig.run(20.0)
	assert_gt(rig.hull().distance_m, 50.0)
	rig.spawn(TankIds.ENEMY_MEDIUM, 1, 260.0)
	rig.enter(GUN_LINE, 0.0, Wl.ENDED_MAX_S)
	assert_eq(rig.hull().x_px, 0.0, "the next segment starts from its halt line")
	assert_eq(rig.hull().distance_m, 0.0)
	assert_true(rig.state.seg.overrun, "the view fades for the tow")
	for e in rig.state.enemies:
		assert_true(e.gun_line, "the Advance's enemies are gone")


func test_a_gun_line_overrun_falls_to_a_support_barrage_with_no_kill_credit() -> void:
	var rig := TankRulesRig.new(1)
	rig.enter(GUN_LINE, 10.0)
	var left := rig.state.enemies.size()
	assert_gt(left, 0)
	rig.events.clear()
	rig.enter(CHECKPOINT, 0.0, Wl.ENDED_MAX_S)
	var kills := rig.of_type("kill")
	assert_eq(kills.size(), left)
	for k in kills:
		assert_eq(k["by"], TankEvents.BY_BARRAGE)
		assert_eq(k["s"], -1)
	assert_eq(rig.state.score.crew_kills, 0, "a barrage kills nothing for the score")
	assert_eq(rig.state.score.kills, [0, 0, 0, 0, 0, 0, 0] as Array[int])
	assert_true(rig.state.gun_line.barrage)
	assert_eq(rig.state.enemies.size(), 0)
	assert_false(rig.state.gun_line.active)
	assert_eq(rig.state.score.overruns, 1)
	rig.enter(STAGE2_ADVANCE, 0.0)
	assert_false(rig.state.gun_line.barrage, "only for the segment after the overrun")


func test_a_boss_overrun_is_a_withdrawal_and_the_outcome_follows() -> void:
	var rig := TankRulesRig.new(1)
	rig.enter(BOSS, 10.0)
	rig.enter(11, 0.0, Wl.ENDED_MAX_S)
	assert_eq(rig.state.outcome, TankIds.OUTCOME_WITHDRAWN)
	assert_eq(rig.state.boss.phase, TankIds.BOSS_WITHDRAWN)
	assert_eq(rig.state.score.overruns, 1)
	assert_false(rig.state.score.behemoth_killed)


func test_the_outcome_is_set_once_in_the_cooldown() -> void:
	var rig := TankRulesRig.new(1)
	rig.enter(BOSS, 10.0)
	rig.state.boss.phase = TankIds.BOSS_DEAD
	rig.state.score.behemoth_killed = true
	rig.enter(11, 0.0, Wl.ENDED_END_PHASE)
	assert_eq(rig.state.outcome, TankIds.OUTCOME_VICTORY)
	rig.state.score.behemoth_killed = false
	rig.run(5.0)
	assert_eq(rig.state.outcome, TankIds.OUTCOME_VICTORY, "not recomputed")
	var drill := TankRulesRig.new(1, "drill")
	drill.enter(3, 0.0)
	assert_eq(drill.state.outcome, TankIds.OUTCOME_COMPLETE, "the drill has no boss")


func test_the_cooldown_has_no_enemies_and_the_tank_rolls_on_without_score() -> void:
	var rig := TankRulesRig.new(1)
	rig.enter(11, 0.0)
	assert_eq(rig.state.enemies.size(), 0)
	rig.run(10.0)
	assert_gt(rig.hull().speed_mps, 1.0, "the tank rolls through the gate")
	assert_eq(rig.rider().work_s, 0.0, "no WORK time, no score")
	assert_eq(rig.of_type("shot").size(), 0)


# --- Depot ---------------------------------------------------------------------------------------


func test_the_depot_drives_for_120_s_then_the_tank_halts_for_the_aim_and_fire_drills() -> void:
	var rig := TankRulesRig.new(1)
	rig.enter(DEPOT, 10.0)
	rig.run(20.0)
	assert_gt(rig.hull().speed_mps, 2.0, "drive drill")
	assert_eq(TankSegments.drill_at(rig.state), "drive")
	var grade := rig.hull().grade_pct
	assert_between(grade, 0.0, 2.0, "terrain 0 to +2% in the depot")
	rig.enter(DEPOT, 125.0)
	rig.run(3.0)
	assert_eq(rig.hull().speed_mps, 0.0)
	assert_true(rig.hull().holding)
	assert_eq(TankSegments.drill_at(rig.state), "aim")
	assert_true(TankSegments.drill_targets(rig.state))
	assert_false(TankSegments.fire_drill(rig.state))
	rig.enter(DEPOT, 250.0)
	assert_true(TankSegments.fire_drill(rig.state))


func test_the_aim_drill_stands_two_wrecks_and_the_gun_slews_to_them() -> void:
	var rig := TankRulesRig.new(2)
	rig.enter(DEPOT, 125.0)
	rig.run(1.0)
	var wrecks := rig.state.obstacles.filter(
		func(o: TankObstacleState) -> bool:
			return o.code == TankIds.obstacle_code(TankIds.OBST_DRILL_WRECK)
	)
	assert_eq(wrecks.size(), 2)
	rig.run(6.0)
	assert_ne(rig.hull().elev_deg, 0.0, "the barrel aimed at a drill wreck")
	assert_ne(rig.hull().target_id, 0)
	assert_eq(rig.state.shells.size(), 0, "no fire in the aim drill")
	assert_eq(rig.of_type("shot").filter(func(e: Dictionary) -> bool: return e["s"] >= 0).size(), 0)


func test_the_fire_drill_shoots_the_drill_wrecks_with_no_damage_and_no_score() -> void:
	var rig := TankRulesRig.new(2)
	rig.enter(DEPOT, 125.0)
	rig.run(1.0)
	rig.enter(DEPOT, 245.0)
	rig.load_shell(TankIds.SHELL_HEAVY)
	rig.run_until(
		func() -> bool:
			return (
				rig.of_type("shot").filter(func(e: Dictionary) -> bool: return e["s"] >= 0).size()
				> 0
			),
		20.0
	)
	var fired := rig.of_type("shot").filter(func(e: Dictionary) -> bool: return e["s"] >= 0)
	assert_gt(fired.size(), 0, "each loaded shell fires at a drill wreck")
	rig.run(4.0)
	assert_eq(rig.state.score.shots, 0, "the drill counts for nothing")
	assert_eq(rig.state.score.hits, 0)
	assert_eq(rig.rider(1).shots, 0)
	for o in rig.state.obstacles:
		if o.code == TankIds.obstacle_code(TankIds.OBST_DRILL_WRECK):
			assert_false(o.cleared, "a wreck takes no damage")
	assert_eq(rig.hull().hp, rig.hull().hp_max)


func test_the_aim_drill_does_not_fire_a_loaded_shell_before_the_fire_drill() -> void:
	var rig := TankRulesRig.new(2)
	rig.enter(DEPOT, 125.0)
	rig.load_shell(TankIds.SHELL_HEAVY)
	rig.run(20.0)
	assert_eq(rig.hull().loaded, TankIds.SHELL_HEAVY)


# --- The drill mission -----------------------------------------------------------------------------


func test_the_drill_skirmish_is_warmup_with_two_lights_and_a_medium() -> void:
	var rig := TankRulesRig.new(3, "drill")
	rig.enter(1, 0.0)
	rig.no_fire = true
	rig.run(2.0)
	assert_eq(rig.state.seg.seg, TankIds.SEG_SKIRMISH)
	assert_eq(rig.state.seg.kind, Wl.WARMUP)
	var seen: Array[int] = []
	for _i in 70 * 20:
		rig.step()
		for e in rig.state.enemies:
			if not seen.has(e.id):
				seen.append(e.id)
	assert_eq(seen.size(), 3, "2 light tanks and 1 medium at the Citadel's scale")
	assert_false(rig.state.seg.objective_done, "a fixed 70 s skirmish has no objective")
	assert_lte(rig.hull().distance_m, 500.0 + 0.01, "the tank holds at the end of the 500 m")


func test_an_advance_encounter_spawns_when_the_tank_has_driven_that_far() -> void:
	var rig := TankRulesRig.new(3)
	rig.no_fire = true
	rig.enter(ADVANCE, 0.0)
	assert_eq(rig.state.enemies.size(), 0)
	rig.run_until(func() -> bool: return rig.hull().distance_m >= 150.0, 60.0)
	rig.run(0.2)
	assert_eq(rig.state.enemies.size(), 1, "a light tank at 150 m")
	assert_eq(rig.state.enemies[0].code, TankIds.enemy_code(TankIds.ENEMY_LIGHT))
	assert_eq(rig.state.seg.next_encounter, 1)
