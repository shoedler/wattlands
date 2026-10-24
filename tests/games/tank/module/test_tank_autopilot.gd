extends GutTest
## TankAutopilot (brief 2.5): rear traverses and obstacle shots for the gunner, nothing else, every
## intent tagged auto. Built on the fixture states (stage 2 Advance), moved around by hand.


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


func _enemy(
	s: TankState, id: int, side: int, x: float, type: String = TankIds.ENEMY_LIGHT
) -> TankEnemyState:
	var e := TankFixtures._enemy(id, type, x, 30.0, side)
	s.enemies.append(e)
	return e


func _rear(s: TankState, id: int = 90) -> TankEnemyState:
	return _enemy(s, id, -1, s.camera_x() + 10.0, TankIds.ENEMY_MEDIUM)


func _front(s: TankState, id: int = 91) -> TankEnemyState:
	return _enemy(s, id, 1, s.hull.x_px + s.hull.hull_w + 120.0)


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
		_rear(s)
		for r in s.riders:
			var got := TankAutopilot.intents(s, r.peer)
			if TankAutopilot.is_gunner(r.engine):
				assert_eq(_kinds(got), ["traverse"], "crew %d %s" % [crew, r.engine])
			else:
				assert_eq(got, [], "crew %d %s works no gun" % [crew, r.engine])
	assert_eq(TankAutopilot.intents(null, 1), [])
	assert_eq(TankAutopilot.intents(_quiet(1), 99), [], "an unknown peer")


func test_a_rear_enemy_alone_flips_the_turret_and_the_intent_is_tagged_auto() -> void:
	for crew in [1, 2, 3]:
		var s := _quiet(crew)
		_rear(s)
		var peer := _gunner(s).peer
		var got := TankAutopilot.intents(s, peer)
		assert_eq(got, [{"k": "traverse", "auto": 1}], "crew %d" % crew)
		var n := TankIntents.normalize(got[0])
		assert_true(bool(n["auto"]), "tagged auto")
		assert_false(TankIntents.is_deliberate(n), "so it never ends a fallback")


func test_no_flip_while_the_facing_side_still_has_a_target() -> void:
	var s := _quiet(1)
	_rear(s)
	_front(s)
	assert_eq(TankAutopilot.intents(s, 1), [], "front and rear: stay on the front")
	s.hull.facing = TankIds.FACE_LEFT
	assert_eq(TankAutopilot.intents(s, 1), [], "facing the rear while it still has one")


func test_the_turret_returns_to_the_front_once_the_rear_is_clear() -> void:
	var s := _quiet(1)
	s.hull.facing = TankIds.FACE_LEFT
	assert_eq(_kinds(TankAutopilot.intents(s, 1)), ["traverse"], "nothing anywhere")
	_front(s)
	assert_eq(_kinds(TankAutopilot.intents(s, 1)), ["traverse"], "only ahead")
	var rear := _rear(s)
	assert_eq(TankAutopilot.intents(s, 1), [], "a rear target keeps it facing back")
	rear.mode = TankIds.EM_DEAD
	assert_eq(_kinds(TankAutopilot.intents(s, 1)), ["traverse"], "a dead enemy is no target")


func test_no_second_traverse_while_one_runs() -> void:
	var s := _quiet(1)
	_rear(s)
	s.hull.traverse_s = 1.5
	assert_eq(TankAutopilot.intents(s, 1), [])


func test_enemies_off_screen_are_out_of_range() -> void:
	var s := _quiet(1)
	_enemy(s, 90, -1, s.camera_x() - 200.0)
	assert_eq(TankAutopilot.intents(s, 1), [], "behind the left edge")
	var far := _enemy(s, 91, 1, s.camera_x() + 1000.0)
	far.hp = 30.0
	assert_eq(TankAutopilot.intents(s, 1), [], "past the right edge")


func test_the_behemoth_counts_as_a_target_ahead() -> void:
	var s := TankFixtures.boss(1)
	s.hull.facing = TankIds.FACE_LEFT
	s.hull.traverse_s = 0.0
	assert_eq(_kinds(TankAutopilot.intents(s, 1)), ["traverse"], "face the Behemoth")
	s.hull.facing = TankIds.FACE_RIGHT
	assert_eq(TankAutopilot.intents(s, 1), [], "already facing it")


func test_an_aligned_loaded_gun_shoots_the_obstacle_when_no_enemy_is_in_range() -> void:
	var s := _quiet(1)
	var ob := _wreck(s)
	s.hull.target_id = ob.id
	assert_eq(TankAutopilot.intents(s, 1), [{"k": "fire", "auto": 1}])
	s.hull.elev_target_deg = 9.0
	assert_eq(TankAutopilot.intents(s, 1), [], "not within the aim tolerance yet")
	s.hull.elev_target_deg = 4.4
	assert_eq(_kinds(TankAutopilot.intents(s, 1)), ["fire"], "within 0.5 degrees")
	s.hull.loaded = TankIds.SHELL_NONE
	assert_eq(TankAutopilot.intents(s, 1), [], "an empty breech")
	s.hull.loaded = TankIds.SHELL_HEAVY
	s.hull.breech_s = 2.0
	assert_eq(TankAutopilot.intents(s, 1), [], "the breech cycle is running")


func test_no_obstacle_shot_with_an_enemy_in_range_or_a_cleared_or_ignored_obstacle() -> void:
	var s := _quiet(1)
	var ob := _wreck(s)
	s.hull.target_id = ob.id
	_front(s)
	assert_eq(TankAutopilot.intents(s, 1), [], "an enemy in range: auto-aim's business")
	s.enemies.clear()
	ob.cleared = true
	assert_eq(TankAutopilot.intents(s, 1), [], "a cleared obstacle")
	ob.cleared = false
	ob.code = TankIds.obstacle_code(TankIds.OBST_TANK_TRAPS)
	assert_eq(TankAutopilot.intents(s, 1), [], "tank traps are shoved aside, not shot")
	ob.code = TankIds.obstacle_code(TankIds.OBST_DRILL_WRECK)
	assert_eq(TankAutopilot.intents(s, 1), [], "the drill wrecks belong to the scripted drills")
	ob.code = TankIds.obstacle_code(TankIds.OBST_WIRE)
	assert_eq(_kinds(TankAutopilot.intents(s, 1)), ["fire"], "wire is shot")
	s.hull.facing = TankIds.FACE_LEFT
	assert_eq(_kinds(TankAutopilot.intents(s, 1)), ["traverse"], "turn to the front first")


func test_it_cycles_the_target_toward_a_blocking_obstacle_once_a_second() -> void:
	var s := _quiet(1)
	_wreck(s)
	s.hull.target_id = 0
	var cycles := 0
	for tick in 100:
		s.tick = 5000 + tick
		var got := TankAutopilot.intents(s, 1)
		if not got.is_empty():
			assert_eq(got, [{"k": "target", "d": 1, "auto": 1}])
			cycles += 1
	assert_eq(cycles, 5, "20 ticks apart")


func test_nothing_while_broken_down_all_afk_or_in_the_cooldown() -> void:
	var s := _quiet(1)
	_rear(s)
	assert_eq(_kinds(TankAutopilot.intents(s, 1)), ["traverse"])
	s.hull.breakdown = true
	assert_eq(TankAutopilot.intents(s, 1), [], "no fire in a breakdown")
	s.hull.breakdown = false
	s.all_afk = true
	assert_eq(TankAutopilot.intents(s, 1), [], "nothing has power")
	s.all_afk = false
	s.seg.seg = TankIds.SEG_COOLDOWN
	assert_eq(TankAutopilot.intents(s, 1), [])
	s.seg.seg = TankIds.SEG_NONE
	assert_eq(TankAutopilot.intents(s, 1), [], "before the first segment")


## Over every fixture state and a mix of positions: the Autopilot only ever traverses, fires or
## cycles a target, never latches, levers, rams, overpressures or nudges the aim, always tagged auto
## and always owned by the rider's engine, so the module's ownership filter drops none of it.
func test_it_never_latches_levers_rams_overpressures_or_aims() -> void:
	var allowed := ["traverse", "fire", "target"]
	var builds: Array[Callable] = [
		TankFixtures.state, TankFixtures.gun_line, TankFixtures.boss, _quiet
	]
	var seen := {}
	for crew in [1, 2, 3]:
		for build in builds:
			var s: TankState = build.call(crew)
			for facing in [TankIds.FACE_RIGHT, TankIds.FACE_LEFT]:
				for with_rear in [false, true]:
					s.hull.facing = facing
					s.hull.traverse_s = 0.0
					s.enemies = s.enemies.filter(func(e: TankEnemyState) -> bool: return e.id < 90)
					if with_rear:
						_rear(s)
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
	assert_true(seen.has("traverse"), "the sweep did exercise a traverse")


func test_the_same_state_gives_the_same_intents() -> void:
	var a := _quiet(3)
	_rear(a)
	var b := _quiet(3)
	_rear(b)
	for r in a.riders:
		assert_eq(TankAutopilot.intents(a, r.peer), TankAutopilot.intents(b, r.peer))


func test_a_traverse_or_a_shot_is_asked_for_twice_a_second_at_most() -> void:
	var s := _quiet(1)
	_rear(s)
	var asked := 0
	for tick in 40:
		s.tick = 6000 + tick
		asked += TankAutopilot.intents(s, 1).size()
	assert_eq(asked, 4, "every tenth tick of 40")
	var t := _quiet(1)
	t.hull.target_id = _wreck(t).id
	asked = 0
	for tick in 40:
		t.tick = 6000 + tick
		asked += TankAutopilot.intents(t, 1).size()
	assert_eq(asked, 4, "the same for the shot")


func test_a_rear_light_is_left_to_the_secondary_and_the_ram() -> void:
	var s := _quiet(1)
	_enemy(s, 90, -1, s.camera_x() + 10.0)
	assert_eq(TankAutopilot.enemies_in_range(s)["behind"], 0, "the main gun cannot reach it")
	assert_eq(TankAutopilot.intents(s, 1), [], "no traverse, no bank spent, no aim pause")
	s.hull.facing = TankIds.FACE_LEFT
	assert_eq(_kinds(TankAutopilot.intents(s, 1)), ["traverse"], "back to the front")


func test_a_rear_enemy_the_main_gun_can_reach_still_flips_the_turret() -> void:
	var s := _quiet(1)
	_rear(s)
	assert_eq(TankAutopilot.enemies_in_range(s)["behind"], 1)
	assert_eq(_kinds(TankAutopilot.intents(s, 1)), ["traverse"])
