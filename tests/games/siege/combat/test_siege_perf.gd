extends GutTest
## A rules step stays cheap at the enemy cap (brief 4: <= 1 ms with 150 enemies, so a 55 minute
## shift simulates in about a minute). The clock is read here, in the test, never in the rules.

const BUDGET_US := 1000.0


func _loaded_rig() -> SiegeRig:
	var rig := SiegeRig.new("vo2", 4, 0, 5)
	rig.state = SiegeFixtures.cap(rig.content)
	rig.state.rng = RandomNumberGenerator.new()
	rig.state.rng.seed = 5
	rig.goto(730.0)
	rig.state.phase_index = 4
	for t in rig.state.pads:
		if not t.built():
			t.type = 1 + t.pad % 3
	for r in rig.state.riders:
		r.target = 2 + r.slot
		r.route_fallback = false
		r.shop_fallback = false
	rig.state.wave.budget_left = 0.0
	rig.state.wave.push_done = true
	return rig


func _mean_us(rig: SiegeRig, steps: int, refill: bool) -> float:
	rig.run(1.0)
	var total := 0
	for _i in steps:
		if refill:
			# keep the field full so every step is a worst-case one
			while rig.state.enemies.size() < 150:
				var e := SiegeEnemyState.new()
				e.id = rig.state.next_enemy_id
				rig.state.next_enemy_id += 1
				e.type = SiegeIds.ENEMY_SHIELD_WALL
				e.road = e.id % 3
				e.prog_m = 20.0 + float(e.id % 60)
				e.max_hp = 160.0
				e.hp = 160.0
				e.place(rig.content.map)
				rig.state.enemies.append(e)
		var t0 := Time.get_ticks_usec()
		rig.step()
		total += Time.get_ticks_usec() - t0
	return float(total) / steps


func test_a_step_with_150_enemies_and_8_towers_is_well_under_a_millisecond() -> void:
	var rig := _loaded_rig()
	assert_eq(rig.state.enemies.size(), 150)
	assert_eq(rig.state.built_pads().size(), 8)
	var mean := _mean_us(rig, 400, true)
	gut.p("mean rules step with 150 enemies and 8 towers: %.0f us" % mean)
	assert_lt(mean, BUDGET_US, "mean %.0f us" % mean)


func test_an_idle_field_with_armed_towers_is_cheap_too() -> void:
	var rig := _loaded_rig()
	for t in rig.state.pads:
		t.cd_s = 0.0
	for e in rig.state.enemies:
		e.prog_m = 1.0
	var total := 0
	rig.run(0.1)
	for _i in 100:
		for e in rig.state.enemies:
			e.prog_m = 1.0
		var t0 := Time.get_ticks_usec()
		rig.step()
		total += Time.get_ticks_usec() - t0
	var mean := float(total) / 100.0
	gut.p("mean rules step, armed towers with nothing in range: %.0f us" % mean)
	assert_lt(mean, BUDGET_US)


func test_a_cap_sized_burst_of_spawns_drains_within_the_cap() -> void:
	var rig := _loaded_rig()
	for i in 300:
		SiegeSpawner.enqueue(rig.state, SiegeIds.ENEMY_RAIDERS, i % 3, 0.0)
	rig.step()
	assert_lte(rig.state.enemies.size(), 150)
	assert_gt(rig.state.queue.size(), 0)
	assert_lte(
		SiegeSnapshotSchema.byte_size(SiegeSnapshot.encode(rig.state)),
		SiegeSnapshotSchema.MAX_BYTES
	)
