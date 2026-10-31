extends GutTest
## TankAutopilot (brief 2.5, SPEC_TANK 3.7): obstacle shots for the gunner, nothing else, every intent
## tagged auto; near threats and the hull in the seat needs. Built on the fixture states (stage 2
## Advance), moved around by hand; the gunner is peer 2 (slot 1 sits on the Gun; v3: the solo rider
## is on Drive, with no gunner). v4: nothing stands behind the tank, so no traverse is ever asked for.


func _gunner(state: TankState) -> TankRiderState:
	for r in state.riders:
		if TankAutopilot.is_gunner(r.engine):
			return r
	return null


## A state with no enemies, no shells and no obstacles, the gunner's gun loaded and level.
func _quiet(crew: int) -> TankState:
	var s := TankFixtures.state(crew)
	s.enemies.clear()
	s.shells.clear()
	s.obstacles.clear()
	s.hull.facing = TankIds.FACE_RIGHT
	s.hull.traverse_s = 0.0
	s.hull.target_id = 0
	s.hull.loaded = TankIds.SHELL_LIGHT
	s.hull.breech_s = 0.0
	s.hull.elev_deg = 4.0
	s.hull.elev_target_deg = 4.0
	return s


func _far(
	s: TankState, id: int = 91, range_m: float = 1200.0, type: String = TankIds.ENEMY_MEDIUM
) -> TankEnemyState:
	return TankFixturesV4._far(s, id, type, range_m, 0)


func _near(s: TankState, id: int = 92, type: String = TankIds.ENEMY_RECON) -> TankEnemyState:
	return TankFixturesV4._near(s, id, type, 60.0, 0)


func _wreck(s: TankState, id: int = 80, cleared: bool = false) -> TankObstacleState:
	var ob := TankObstacleState.new()
	ob.id = id
	ob.code = TankIds.obstacle_code(TankIds.OBST_WRECK)
	ob.x_px = s.hull.x_px + s.hull.hull_w + 150.0
	ob.w = 72
	ob.cleared = cleared
	s.obstacles.append(ob)
	return ob


func _kinds(list: Array) -> Array:
	return list.map(func(i: Dictionary) -> String: return str(i["k"]))


func test_only_the_gunner_gets_anything() -> void:
	for crew in [2, 3]:
		var s := _quiet(crew)
		s.hull.target_id = _wreck(s).id
		for r in s.riders:
			var got := TankAutopilot.intents(s, r.peer)
			if TankAutopilot.is_gunner(r.engine):
				assert_eq(_kinds(got), ["fire"], "crew %d %s" % [crew, r.engine])
			else:
				assert_eq(got, [], "crew %d %s works no gun" % [crew, r.engine])
	assert_eq(TankAutopilot.intents(null, 1), [])
	assert_eq(TankAutopilot.intents(_quiet(2), 99), [], "an unknown peer")


func test_the_intent_is_tagged_auto_so_it_never_ends_a_fallback() -> void:
	var s := _quiet(2)
	s.hull.target_id = _wreck(s).id
	var got := TankAutopilot.intents(s, 2)
	assert_eq(got, [{"k": "fire", "auto": 1}])
	var n := TankIntents.normalize(got[0])
	assert_true(bool(n["auto"]), "tagged auto")
	assert_false(TankIntents.is_deliberate(n), "so it never ends a fallback")


func test_enemies_in_range_counts_far_kinds_and_the_behemoth_never_a_near_threat() -> void:
	var s := _quiet(2)
	assert_eq(TankAutopilot.enemies_in_range(s), 0)
	_near(s)
	assert_eq(TankAutopilot.enemies_in_range(s), 0, "the main gun does not lay on a near threat")
	var e := _far(s)
	assert_eq(TankAutopilot.enemies_in_range(s), 1)
	e.range_m = 2600.0
	assert_eq(TankAutopilot.enemies_in_range(s), 0, "past gun.far.max_range_m")
	e.range_m = 1200.0
	e.mode = TankIds.EM_DEAD
	assert_eq(TankAutopilot.enemies_in_range(s), 0, "a dead enemy is no target")
	var b := TankFixtures.boss(2)
	b.enemies.clear()
	b.boss.range_m = 1100.0
	assert_eq(TankAutopilot.enemies_in_range(b), 1, "the Behemoth stands")


func test_an_aligned_loaded_gun_shoots_the_obstacle_when_no_enemy_is_in_range() -> void:
	var s := _quiet(2)
	var ob := _wreck(s)
	s.hull.target_id = ob.id
	assert_eq(TankAutopilot.intents(s, 2), [{"k": "fire", "auto": 1}])
	s.hull.elev_target_deg = 9.0
	assert_eq(TankAutopilot.intents(s, 2), [], "not within the aim tolerance yet")
	s.hull.elev_target_deg = 4.4
	assert_eq(_kinds(TankAutopilot.intents(s, 2)), ["fire"], "within 0.5 degrees")
	s.hull.loaded = TankIds.SHELL_NONE
	assert_eq(TankAutopilot.intents(s, 2), [], "an empty breech")
	s.hull.loaded = TankIds.SHELL_HEAVY
	s.hull.breech_s = 2.0
	assert_eq(TankAutopilot.intents(s, 2), [], "the breech cycle is running")


func test_no_obstacle_shot_with_an_enemy_in_range_or_a_cleared_or_ignored_obstacle() -> void:
	var s := _quiet(2)
	var ob := _wreck(s)
	s.hull.target_id = ob.id
	_far(s)
	assert_eq(TankAutopilot.intents(s, 2), [], "an enemy in range: auto-aim's business")
	s.enemies.clear()
	_near(s)
	assert_eq(_kinds(TankAutopilot.intents(s, 2)), ["fire"], "a near threat does not stop the shot")
	s.enemies.clear()
	ob.cleared = true
	assert_eq(TankAutopilot.intents(s, 2), [], "a cleared obstacle")
	ob.cleared = false
	ob.code = TankIds.obstacle_code(TankIds.OBST_TANK_TRAPS)
	assert_eq(TankAutopilot.intents(s, 2), [], "tank traps are shoved aside, not shot")
	ob.code = TankIds.obstacle_code(TankIds.OBST_DRILL_WRECK)
	assert_eq(TankAutopilot.intents(s, 2), [], "the drill wrecks belong to the scripted drills")
	ob.code = TankIds.obstacle_code(TankIds.OBST_WIRE)
	assert_eq(_kinds(TankAutopilot.intents(s, 2)), ["fire"], "wire is shot")


func test_it_cycles_the_target_toward_a_blocking_obstacle_once_a_second() -> void:
	var s := _quiet(2)
	_wreck(s)
	s.hull.target_id = 0
	var cycles := 0
	for tick in 100:
		s.tick = 5000 + tick
		var got := TankAutopilot.intents(s, 2)
		if not got.is_empty():
			assert_eq(got, [{"k": "target", "d": 1, "auto": 1}])
			cycles += 1
	assert_eq(cycles, 5, "20 ticks apart")


func test_nothing_while_out_of_action_all_afk_or_in_the_cooldown() -> void:
	var s := _quiet(2)
	s.hull.target_id = _wreck(s).id
	assert_eq(_kinds(TankAutopilot.intents(s, 2)), ["fire"])
	s.hull.breakdown = true
	assert_eq(TankAutopilot.intents(s, 2), [], "no fire in a breakdown")
	s.hull.breakdown = false
	s.hull.tow_s = 4.0
	assert_eq(TankAutopilot.intents(s, 2), [], "no fire under a tow")
	s.hull.tow_s = 0.0
	s.all_afk = true
	assert_eq(TankAutopilot.intents(s, 2), [], "nothing has power")
	s.all_afk = false
	s.seg.seg = TankIds.SEG_COOLDOWN
	assert_eq(TankAutopilot.intents(s, 2), [])
	s.seg.seg = TankIds.SEG_NONE
	assert_eq(TankAutopilot.intents(s, 2), [], "before the first segment")


## Over every fixture state and a mix of positions: the Autopilot only ever fires or cycles a target,
## never traverses, latches, levers, overpressures, turns or nudges the aim (and never sprints, so it
## never evades), always tagged auto and always owned by the rider's engine, so the module's ownership
## filter drops none of it.
func test_it_never_traverses_latches_levers_overpressures_or_aims() -> void:
	var allowed := ["fire", "target"]
	var builds: Array[Callable] = [
		TankFixtures.state, TankFixtures.gun_line, TankFixtures.boss, _quiet
	]
	var seen := {}
	for crew in [1, 2, 3, 4]:
		for build in builds:
			var s: TankState = build.call(crew)
			for with_far in [false, true]:
				s.hull.traverse_s = 0.0
				s.enemies = s.enemies.filter(func(e: TankEnemyState) -> bool: return e.id < 90)
				if with_far:
					_far(s, 90)
				else:
					s.enemies.clear()
					s.obstacles.clear()
					s.hull.target_id = _wreck(s).id
					s.hull.loaded = TankIds.SHELL_HEAVY
					s.hull.breech_s = 0.0
					s.hull.elev_deg = s.hull.elev_target_deg
				for tick in [0, 20, 7]:
					s.tick = tick
					for r in s.riders:
						for raw: Dictionary in TankAutopilot.intents(s, r.peer):
							var n := TankIntents.normalize(raw)
							assert_false(n.is_empty(), "valid: %s" % JSON.stringify(raw))
							assert_has(allowed, n["k"])
							assert_true(bool(n["auto"]), "tagged auto")
							assert_true(TankIntents.owned(n["k"], r.engine), "owned")
							seen[n["k"]] = true
	assert_true(seen.has("fire"), "the sweep did exercise a shot")


func test_the_same_state_gives_the_same_intents() -> void:
	var a := _quiet(3)
	a.hull.target_id = _wreck(a).id
	var b := _quiet(3)
	b.hull.target_id = _wreck(b).id
	for r in a.riders:
		assert_eq(TankAutopilot.intents(a, r.peer), TankAutopilot.intents(b, r.peer))


func test_a_shot_is_asked_for_twice_a_second_at_most() -> void:
	var t := _quiet(2)
	t.hull.target_id = _wreck(t).id
	var asked := 0
	for tick in 40:
		t.tick = 6000 + tick
		asked += TankAutopilot.intents(t, 2).size()
	assert_eq(asked, 4, "every tenth tick of 40")


# --- v4: what the seating reads ---------------------------------------------------------------------


func test_the_situation_reads_far_targets_and_near_threats_apart() -> void:
	var s := _quiet(3)
	TankTargets.build(s, TankAux.of(s))
	var sit := TankAutopilot.situation(s)
	assert_false(sit["targets"])
	assert_false(sit["far_target"])
	assert_false(sit["near_threat"])
	var rc := _near(s)
	TankTargets.build(s, TankAux.of(s))
	sit = TankAutopilot.situation(s)
	assert_false(sit["targets"], "the main gun does not lay on a near threat")
	assert_true(sit["near_threat"])
	assert_true(sit["bow"], "60 px off the front: in the bow guns' range")
	assert_true(sit["only_light"])
	assert_false(sit["far_target"])
	rc.hp = 0.0
	TankTargets.build(s, TankAux.of(s))
	assert_false(TankAutopilot.situation(s)["near_threat"], "a dead one is gone")
	s.enemies.clear()
	var e := _far(s)
	TankTargets.build(s, TankAux.of(s))
	sit = TankAutopilot.situation(s)
	assert_true(sit["targets"])
	assert_true(sit["far_target"])
	assert_false(sit["bow"], "a far enemy is never the bow guns'")
	assert_false(sit["far"], "1200 m: inside arc.dark_range_m")
	e.range_m = 2400.0
	TankTargets.build(s, TankAux.of(s))
	assert_true(TankAutopilot.situation(s)["far"], "2400 m: past arc.dark_range_m")


func test_the_secondaries_need_47_while_a_near_threat_is_alive() -> void:
	var s := _quiet(3)
	TankTargets.build(s, TankAux.of(s))
	assert_almost_eq(float(TankAutopilot.seat_needs(s)[TankIds.ENGINE_FEED]), 0.1, 1e-9)
	_near(s)
	TankTargets.build(s, TankAux.of(s))
	var needs := TankAutopilot.seat_needs(s)
	assert_almost_eq(float(needs[TankIds.ENGINE_FEED]), 4.7, 1e-9)
	assert_gt(
		float(needs[TankIds.ENGINE_FEED]), float(needs[TankIds.ENGINE_STEAM]), "before the Loader"
	)
	assert_lt(float(needs[TankIds.ENGINE_FEED]), float(needs[TankIds.ENGINE_DIESEL]), "not Drive")


func test_repairs_need_follows_the_hull() -> void:
	var s := _quiet(3)
	s.hull.hp_max = 100.0
	var cases := [[100.0, 0.05], [60.0, 0.05], [59.0, 4.2], [35.0, 4.2], [34.0, 5.6], [1.0, 5.6]]
	for c: Array in cases:
		s.hull.hp = float(c[0])
		assert_almost_eq(TankAutopilot.repair_need(s), float(c[1]), 1e-9, "%s HP" % c[0])
	s.hull.hp = 0.0
	s.hull.tow_s = 5.0
	assert_almost_eq(TankAutopilot.repair_need(s), 0.05, 1e-9, "under a tow: the restart lifts it")
	s.hull.tow_s = 0.0
	s.hull.breakdown = true
	assert_almost_eq(TankAutopilot.repair_need(s), 0.05, 1e-9, "in a breakdown: its own repair")


## _crew_may_move: otherwise every crew move is blocked before 60 s and before the segment's min_s, and
## stage 1's recon comes at about 40 s, so no Autopilot crew could ever man the Secondaries.
func test_a_crew_may_move_inside_the_opening_while_a_near_threat_is_alive() -> void:
	var s := _quiet(3)
	s.seg.elapsed_s = 40.0
	assert_false(TankAutopilot._crew_may_move(s, false), "the opening holds")
	var rc := _near(s)
	assert_true(TankAutopilot._crew_may_move(s, false), "a near threat opens it")
	rc.hp = 0.0
	assert_false(TankAutopilot._crew_may_move(s, false), "and only while it lives")
	rc.hp = 10.0
	s.seg.seg = TankIds.SEG_CHECKPOINT
	assert_false(TankAutopilot._crew_may_move(s, false), "never in a checkpoint")


## A rider who left Drive in the hold is not stuck off it: an Advance with nobody on Drive opens the crew's
## moves at once, or the tank stands until min_s and the Advance overruns.
func test_an_advance_with_nobody_on_drive_opens_the_crews_moves() -> void:
	var s := TankFixturesV4.make("advance_far", 3)
	s.seg.elapsed_s = 1.0
	s.seg.objective_done = false
	assert_false(TankAutopilot._crew_may_move(s, false), "Drive manned: the opening stay holds")
	s.station(TankIds.ENGINE_DIESEL).slot = -1
	assert_true(TankAutopilot._crew_may_move(s, false), "nobody on Drive")
	s.seg.seg = TankIds.SEG_CHECKPOINT
	assert_false(TankAutopilot._crew_may_move(s, false), "never in a checkpoint")
