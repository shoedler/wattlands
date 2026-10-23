extends GutTest
## The stress scene's synthetic state and statistics, and its headless run (one log line, then it
## quits): the windowed 60 s frame-time run is a P1 check done by hand, see stress_scene.gd.


func test_the_synthetic_state_has_150_enemies_8_towers_and_4_wheels_in_a_small_snapshot() -> void:
	var st := SiegeStressScene.build_state()
	assert_eq(st.enemies.size(), 150)
	assert_eq(st.built_pads().size(), 8)
	assert_eq(st.riders.size(), 4)
	var types := {}
	for e in st.enemies:
		types[e.type] = true
		assert_gt(e.pos.length(), 1.0, "placed on a road")
	assert_eq(types.keys().size(), 4, "every enemy type is in the crowd")
	var snap := SiegeSnapshot.encode(st)
	assert_eq(SiegeSnapshotSchema.check(snap), "")
	assert_lte(SiegeSnapshotSchema.byte_size(snap), SiegeSnapshotSchema.MAX_BYTES)


func test_advance_moves_the_crowd_and_keeps_it_at_the_cap() -> void:
	var st := SiegeStressScene.build_state()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var before: Array[float] = []
	for e in st.enemies:
		before.append(e.prog_m)
	for _i in 600:
		SiegeStressScene.advance(st, 0.1, rng)
	assert_eq(st.enemies.size(), 150)
	var moved := 0
	for i in st.enemies.size():
		if not is_equal_approx(st.enemies[i].prog_m, before[i]):
			moved += 1
		assert_lt(st.enemies[i].prog_m, st.content.map.road_length(st.enemies[i].road))
	assert_gt(moved, 140)
	SiegeStressScene.add_shot(st, rng)
	assert_eq(st.shots.size(), 1)
	SiegeStressScene.advance(st, 0.2, rng)
	assert_eq(st.shots.size(), 0, "shots age out after 0.1 s")


func test_refill_tops_up_to_the_count_with_new_ids() -> void:
	var st := SiegeStressScene.build_state(150)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	st.enemies.resize(120)
	SiegeStressScene.refill(st, 150, rng)
	assert_eq(st.enemies.size(), 150)
	var ids := {}
	for e in st.enemies:
		ids[e.id] = true
	assert_eq(ids.size(), 150, "ids stay unique")


func test_frame_stats_and_the_one_percent_low() -> void:
	var ms := PackedFloat32Array()
	for i in 99:
		ms.append(10.0)
	ms.append(40.0)
	var fs := SiegeStressScene.frame_stats(ms)
	assert_almost_eq(float(fs["mean_ms"]), 10.3, 0.001)
	assert_almost_eq(float(fs["low1_ms"]), 40.0, 0.001, "the slowest 1 of 100 frames")
	assert_almost_eq(float(fs["max_ms"]), 40.0, 0.001)
	assert_eq(fs["frames"], 100)
	assert_eq(SiegeStressScene.frame_stats(PackedFloat32Array())["frames"], 0)
	assert_almost_eq(SiegeStressScene.low_mean(ms, 0.05), (40.0 + 4 * 10.0) / 5.0, 0.001)


func test_the_scene_runs_and_finishes_with_a_log_line() -> void:
	var scene: PackedScene = load("res://tests/games/siege/perf/stress_scene.tscn")
	assert_not_null(scene)
	var node: Node = scene.instantiate()
	assert_is(node, SiegeStressScene)
	var stress := node as SiegeStressScene
	stress.auto_quit = false
	stress.seconds = 0.3
	add_child_autofree(stress)
	assert_not_null(stress.view)
	assert_eq(stress.state.enemies.size(), 150)
	await wait_until(func() -> bool: return not stress.verdict.is_empty(), 20.0)
	assert_false(stress.verdict.is_empty(), "the run ended")
	if stress.verdict["headless"]:
		assert_eq(stress.verdict["enemies"], 150)
		assert_eq(stress.verdict["towers"], 8)
	else:
		assert_gt(stress.verdict["frames"], 0)
