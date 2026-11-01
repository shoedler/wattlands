extends GutTest
## v4: the near threats (TankNear; SPEC_TANK 3.1): the burst from the bushes, pause, dash, the shots,
## the flight at flee_px and at flee_after_s, `escaped`, no reward and no penalty.

const CHECKPOINT := 3


static func _quiet(index: int) -> Callable:
	return func(files: Dictionary) -> void:
		(files["mission"]["segments"][index] as Dictionary).merge(
			{"encounters": [], "obstacles": []}, true
		)


func _rig(crew: int = 2) -> TankRulesRig:
	var rig := TankRulesRig.new(crew, "ashfall_road", 7, _quiet(CHECKPOINT))
	rig.no_fire = true
	rig.no_bow = true
	rig.enter(CHECKPOINT, 1.0)
	return rig


func _spawn(rig: TankRulesRig, type: String) -> TankEnemyState:
	return TankNear.spawn(rig.state, TankAux.of(rig.state), type, 0, rig.events)


func _dist(rig: TankRulesRig, e: TankEnemyState) -> float:
	return TankEnemies.distance(rig.state, e)


func test_it_bursts_from_the_bushes_and_raises_ambush() -> void:
	for type in TankIds.NEAR_KINDS:
		var rig := _rig()
		var def := rig.content.enemy_def(type)
		var e := _spawn(rig, type)
		assert_eq(e.mode, TankIds.EM_ENTER)
		assert_true(e.is_near())
		assert_eq(e.range_m, 0.0, "no metres in the near frame")
		assert_eq(e.side, 1)
		assert_between(_dist(rig, e), float(def["spawn_px"][0]), float(def["spawn_px"][1]), type)
		assert_eq([e.w, e.h], [int(def["size_px"][0]), int(def["size_px"][1])])
		var amb := rig.of_type("ambush")
		assert_eq(amb.size(), 1)
		assert_eq([amb[0]["id"], amb[0]["e"]], [e.id, TankIds.enemy_code(type)])


func test_lanes_alternate() -> void:
	var rig := _rig()
	var lanes: Array[int] = []
	for _i in 4:
		lanes.append(_spawn(rig, TankIds.ENEMY_RECON).lane)
	assert_eq(lanes, [0, 1, 0, 1] as Array[int])


func test_burst_then_pause_then_dash_then_pause() -> void:
	var rig := _rig()
	var def := rig.content.enemy_def(TankIds.ENEMY_RECON)
	var e := _spawn(rig, TankIds.ENEMY_RECON)
	var d0 := _dist(rig, e)
	rig.run(float(def["burst_s"]) + 0.05)
	assert_eq(e.mode, TankIds.EM_PAUSE, "after burst_s")
	var d1 := _dist(rig, e)
	assert_almost_eq(d1 - d0, float(def["burst_px_s"]) * float(def["burst_s"]), 4.0)
	rig.run(0.5)
	assert_eq(_dist(rig, e), d1, "still, keeping pace with the hull")
	rig.run_until(func() -> bool: return e.mode == TankIds.EM_MOVE, 3.0)
	assert_eq(e.mode, TankIds.EM_MOVE, "the dash")
	rig.run_until(func() -> bool: return e.mode == TankIds.EM_PAUSE, 3.0)
	assert_eq(e.mode, TankIds.EM_PAUSE)
	assert_almost_eq(_dist(rig, e) - d1, float(def["dash_px"]), 2.5, "one dash_px")


func test_it_keeps_pace_with_a_moving_hull() -> void:
	var rig := _rig()
	var e := rig.near(TankIds.ENEMY_TANKETTE, 60.0)
	rig.hull().x_px += 500.0
	rig.run(0.1)
	assert_almost_eq(_dist(rig, e), 60.0, 0.001)


func test_it_flees_at_flee_px_gets_away_and_it_costs_and_pays_nothing() -> void:
	var rig := _rig()
	var def := rig.content.enemy_def(TankIds.ENEMY_RECON)
	var e := rig.near(TankIds.ENEMY_RECON, float(def["flee_px"]) - 1.0)
	e.mode = TankIds.EM_MOVE
	TankAux.of(rig.state).near_left[e.id] = 100.0
	rig.hull().hp = 100.0
	var hp := rig.hull().hp
	rig.run(0.2)
	assert_eq(e.mode, TankIds.EM_LEAVE, "at flee_px")
	var shots := rig.of_type("shot").size()
	var t := rig.run_until(func() -> bool: return not rig.state.enemies.has(e), 5.0)
	assert_lt(t, 5.0, "gone")
	assert_eq(rig.of_type("shot").size(), shots, "no fire while fleeing")
	var esc := rig.of_type("escaped")
	assert_eq(esc.size(), 1)
	assert_eq([esc[0]["id"], esc[0]["e"]], [e.id, TankIds.enemy_code(TankIds.ENEMY_RECON)])
	assert_eq(rig.state.score.near_escaped, 1)
	assert_eq(rig.state.score.kills[7], 0, "no reward")
	assert_eq(rig.state.score.crew_kills, 0)
	assert_eq(rig.of_type("kill").size(), 0)
	assert_eq(rig.hull().hp, hp, "no penalty")
	assert_true(TankAux.of(rig.state).enemy_dist.is_empty(), "forgotten")


func test_it_flees_past_flee_after_s_wherever_it_got_to() -> void:
	for type in TankIds.NEAR_KINDS:
		var rig := _rig()
		var def := rig.content.enemy_def(type)
		var e := rig.near(type, 20.0)
		e.gun_s = 1.0e6
		rig.run(float(def["flee_after_s"]) - 0.5)
		assert_eq(e.mode, TankIds.EM_PAUSE, type)
		rig.run(0.6)
		assert_eq(e.mode, TankIds.EM_LEAVE, "%s at flee_after_s" % type)
		assert_lt(_dist(rig, e), float(def["flee_px"]))
		rig.run((TankConst.NEAR_SPAN_PX + 25.0) / float(def["flee_px_s"]))
		assert_false(rig.state.enemies.has(e), "%s gone past the panel" % type)
		assert_eq(rig.state.score.near_escaped, 1)


func test_it_fires_near_shells_only_while_paused_with_no_telegraph() -> void:
	var rig := _rig()
	rig.hull().hp = 1.0e6
	rig.hull().hp_max = 1.0e6
	var def := rig.content.enemy_def(TankIds.ENEMY_RECON)
	var e := rig.near(TankIds.ENEMY_RECON, 80.0)
	e.gun_s = 0.1
	rig.run(0.2)
	var shots := rig.of_type("shot")
	assert_eq(shots.size(), 1)
	assert_eq([shots[0]["src"], shots[0]["e"], shots[0]["s"]], [e.id, 7, -1])
	assert_eq(shots[0]["rng_m"], 0, "a near shell has no range")
	assert_false(shots[0].has("flight_s"), "and no flight_s")
	assert_eq(e.telegraph_s, 0.0)
	assert_eq(rig.of_type("evade").size(), 0, "not evadable")
	var s: TankShellState = rig.state.shells.back()
	assert_false(s.far)
	assert_false(s.evadable)
	assert_eq(s.damage, float(def["gun"]["damage"]))
	assert_almost_eq(e.gun_s, float(def["gun"]["every_s"]) - 0.1, 0.11)
	e.mode = TankIds.EM_MOVE
	TankAux.of(rig.state).near_left[e.id] = 1000.0
	e.gun_s = 0.05
	rig.run(0.5)
	assert_eq(rig.of_type("shot").size(), 1, "the dash holds its fire")


func test_the_muzzle_is_a_quarter_along_and_the_shell_lands_on_or_near_the_hull() -> void:
	var rig := _rig()
	rig.hull().hp = 1.0e6
	rig.hull().hp_max = 1.0e6
	rig.hull().evasive = false
	var e := rig.near(TankIds.ENEMY_RECON, 80.0)
	var m := TankNear.muzzle(e)
	assert_almost_eq(m.x, e.x_px + float(e.w) * 0.25, 0.001)
	assert_almost_eq(m.y, float(TankConst.GROUND_Y) - float(e.h) * 0.8, 0.001)
	e.gun_s = 0.05
	rig.run(1.2)
	assert_true(rig.of_type("hit").size() <= 1)
	assert_eq(rig.state.shells.size(), 0, "it arrived")


func test_it_is_not_a_main_gun_target_but_the_bow_hits_it() -> void:
	var rig := _rig()
	var aux := TankAux.of(rig.state)
	var e := rig.near(TankIds.ENEMY_TANKETTE, 60.0)
	TankTargets.build(rig.state, aux)
	var t := TankTargets.by_id(aux, e.id)
	assert_true(t.near)
	assert_false(TankTargets.engageable(t, rig.state.camera_x()))
	assert_false(aux.enemy_in_range, "a near threat is not a far target in range")
	assert_eq(TankTargets.near_threats(aux).size(), 1)
	assert_eq(TankBow.target(rig.state, aux).id, e.id)


func test_difficulty_scales_its_hp() -> void:
	for level: String in TankIds.DIFFICULTIES:
		var rig := _rig()
		rig.state.difficulty = level
		var e := _spawn(rig, TankIds.ENEMY_RECON)
		var row: Dictionary = rig.content.value("enemies", "difficulty.%s" % level, {})
		assert_almost_eq(e.hp_max, 22.5 * float(row["hp"]), 0.001, level)


func test_fractional_hp_crosses_the_wire_rounded_up_on_every_difficulty() -> void:
	# 22.5 and 13.5 x 0.6, 1, 1.25. The wire carries whole HP: a host's 0.125 must never read dead.
	for level: String in TankIds.DIFFICULTIES:
		for type: String in TankIds.NEAR_KINDS:
			var rig := _rig()
			rig.state.difficulty = level
			var e := _spawn(rig, type)
			var client := _rig()
			client.state.difficulty = level
			var label := "%s %s" % [level, type]
			TankSnapshot.apply(client.state, TankSnapshot.encode(rig.state))
			var c := client.state.enemy(e.id)
			assert_eq(c.hp_max, ceilf(e.hp_max), label)
			assert_eq(c.hp, c.hp_max, "%s: a full bar stays hidden" % label)
			e.hp = e.hp_max * 0.5
			TankSnapshot.apply(client.state, TankSnapshot.encode(rig.state))
			assert_almost_eq(c.hp / c.hp_max, 0.5, 1.0 / c.hp_max, "%s: half a bar" % label)
			e.hp = 0.125
			TankSnapshot.apply(client.state, TankSnapshot.encode(rig.state))
			assert_eq(client.state.enemy(e.id).hp, 1.0, "%s: alive, never 0" % label)


func test_a_bow_kill_is_scored_at_the_near_kinds_index() -> void:
	var rig := _rig()
	var aux := TankAux.of(rig.state)
	var r := rig.near(TankIds.ENEMY_RECON, 40.0)
	var k := rig.near(TankIds.ENEMY_TANKETTE, 50.0)
	TankShells.kill_enemy(rig.state, aux, r, TankEvents.BY_BOW, 1, rig.events)
	TankShells.kill_enemy(rig.state, aux, k, TankEvents.BY_BOW, 1, rig.events)
	assert_eq([rig.state.score.kills[7], rig.state.score.kills[8]], [1, 1])


func test_near_threats_clear_at_a_segment_change() -> void:
	var rig := _rig()
	rig.near(TankIds.ENEMY_RECON, 40.0)
	rig.enter(4, 1.0)
	assert_eq(
		rig.state.enemies.filter(func(e: TankEnemyState) -> bool: return e.is_near()).size(), 0
	)
	assert_eq(rig.of_type("escaped").size(), 0)
