extends GutTest
## Determinism (BRIEF 6: seeded RNG, fixed steps) and the cost of one step at the caps.


func _fingerprint(rig: TankRig) -> String:
	return JSON.stringify([rig.state.to_dict(), rig.events])


func _play(crew: int, rng_seed: int, seconds: float) -> TankRig:
	var rig := TankRig.new(crew, "ashfall_road", true, rng_seed)
	rig.auto_phase = true
	rig.enter(1, 0.0)
	rig.run(seconds)
	return rig


func test_the_same_seed_and_inputs_give_the_same_state_and_events() -> void:
	for crew in [1, 2, 3]:
		var a := _play(crew, 21, 150.0)
		var b := _play(crew, 21, 150.0)
		assert_gt(a.events.size(), 8, "something happened")
		assert_eq(_fingerprint(a), _fingerprint(b), "crew %d" % crew)


func test_another_seed_changes_the_fight() -> void:
	var a := _play(3, 21, 150.0)
	var b := _play(3, 22, 150.0)
	assert_ne(_fingerprint(a), _fingerprint(b))


func test_the_same_seed_gives_the_same_whole_mission() -> void:
	var a := TankRig.new(2, "ashfall_road", true, 5)
	var b := TankRig.new(2, "ashfall_road", true, 5)
	a.play()
	b.play()
	assert_eq(a.seg_len, b.seg_len)
	assert_eq(a.state.outcome, b.state.outcome)
	assert_eq(JSON.stringify(a.state.to_dict()), JSON.stringify(b.state.to_dict()))


func test_the_rules_never_read_a_clock_or_a_global_random_source() -> void:
	var banned := ["Time.", "OS.get_ticks", "randi(", "randf(", "RandomNumberGenerator.new("]
	var bad: Array[String] = []
	var files := 0
	for dir in ["res://src/games/tank/rules", "res://src/games/tank/combat"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			files += 1
			var text := FileAccess.get_file_as_string(dir.path_join(f))
			for line in text.split("\n"):
				var code := line.split("#")[0]
				for word in banned:
					if code.contains(word) and not code.contains("rng."):
						bad.append("%s: %s" % [f, line.strip_edges()])
	assert_gt(files, 10, "the rules and combat folders were scanned")
	assert_eq(bad, [] as Array[String])


## A crew-3 stage-3 advance with 16 enemies and 24 shells in flight.
func _capped() -> TankRig:
	var rig := TankRig.new(3)
	rig.enter(7, 50.0)
	rig.state.enemies.clear()
	return rig


func _top_up(rig: TankRig) -> void:
	var aux := TankAux.of(rig.state)
	var i := 0
	while rig.state.enemies.size() < TankConst.MAX_ENEMIES:
		var type: String = TankIds.ENEMY_TYPES[i % 5]
		var e := TankEnemies.spawn(
			rig.state, aux, type, -1 if i % 4 == 0 else 1, -1.0, false, false, 0
		)
		e.hp = 100000.0
		e.hp_max = 100000.0
		e.mode = TankIds.EM_HOLD
		i += 1
	while rig.state.shells.size() < TankConst.MAX_SHELLS:
		var s := TankShellState.new()
		s.id = rig.state.take_id()
		s.type = TankIds.SHELL_ENEMY
		s.friendly = i % 2 == 0
		s.x = rig.hull().x_px + 400.0
		s.y = 200.0
		s.vx = -50.0
		s.vy = 0.0
		rig.state.shells.append(s)
		TankAux.of(rig.state).shell_left[s.id] = 2.0
		i += 1
	rig.hull().hp = 100000.0
	rig.hull().hp_max = 100000.0
	rig.hull().loaded = TankIds.SHELL_HEAVY


func test_a_step_at_the_caps_stays_far_below_a_frame() -> void:
	var rig := _capped()
	_top_up(rig)
	rig.run(1.0)
	var total := 0
	var worst := 0
	var n := 200
	for _i in n:
		_top_up(rig)
		var inp := rig.inputs()
		var t0 := Time.get_ticks_usec()
		TankRules.step(rig.state, inp, Wl.SIM_DT)
		var dt := Time.get_ticks_usec() - t0
		rig.tick += 1
		rig.seg_t += Wl.SIM_DT
		rig.plan_t += Wl.SIM_DT
		total += dt
		worst = maxi(worst, dt)
	var mean_ms := float(total) / n / 1000.0
	print("TankRules.step at the caps: mean %.3f ms, worst %.3f ms" % [mean_ms, worst / 1000.0])
	assert_lt(
		mean_ms,
		3.0,
		"brief: <= 1 ms in a release build; the bound here is generous (debug build, shared CI)"
	)


func test_a_live_state_at_the_caps_encodes_into_a_valid_snapshot_under_4_kb() -> void:
	var rig := _capped()
	_top_up(rig)
	rig.run(2.0)
	_top_up(rig)
	var snap := TankSnapshot.encode(rig.state)
	assert_eq(TankSnapshotSchema.check(snap), "")
	assert_lt(TankSnapshotSchema.byte_size(snap), TankConst.SNAPSHOT_MAX_BYTES)
	assert_eq(rig.state.enemies.size(), TankConst.MAX_ENEMIES)
	assert_eq(rig.state.shells.size(), TankConst.MAX_SHELLS)
