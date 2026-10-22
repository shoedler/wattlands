extends GutTest
## Enemies (brief 2.4 "Enemies (P0)"): road polylines, speeds, the seeded lateral offset, no
## collision, damage at the gate, the ram's battering, wave end retreat, the cap and its queue.

const VALLEY := SiegeIds.ROAD_VALLEY

var _rig: SiegeRig


func _wave(humans: int = 2, rng_seed: int = 7) -> SiegeRig:
	_rig = SiegeRig.new("short", humans, 0, rng_seed)
	_rig.enter(2, 10.0)
	# nothing spawns by itself during these tests
	_rig.state.wave.budget_left = 0.0
	_rig.state.wave.push_done = true
	return _rig


func test_enemies_walk_their_road_at_their_speed() -> void:
	_wave()
	var speeds := {
		SiegeIds.ENEMY_RAIDERS: 2.2,
		SiegeIds.ENEMY_SHIELD_WALL: 0.9,
		SiegeIds.ENEMY_HORSEMEN: 4.5,
		SiegeIds.ENEMY_RAM: 1.0,
	}
	var list := {}
	for t: int in speeds:
		list[t] = _rig.spawn(t, VALLEY, 10.0)
	_rig.run(2.0)
	for t: int in speeds:
		var e: SiegeEnemyState = list[t]
		assert_almost_eq(e.prog_m, 10.0 + float(speeds[t]) * 2.0, 1e-3, "type %d" % t)
		assert_eq(e.pos, _rig.content.map.point_at(VALLEY, e.prog_m, e.lat_m), "pos is current")


func test_enemy_numbers_are_the_briefs() -> void:
	var c := SiegeFakes.content()
	var want := {
		SiegeIds.ENEMY_RAIDERS: [20, 0, 2.2, 2, 1, 1],
		SiegeIds.ENEMY_SHIELD_WALL: [160, 8, 0.9, 8, 6, 6],
		SiegeIds.ENEMY_HORSEMEN: [35, 0, 4.5, 3, 2, 2.5],
		SiegeIds.ENEMY_RAM: [600, 4, 1.0, 0, 15, 20],
	}
	for t: int in want:
		var d := c.enemy_def(t)
		var w: Array = want[t]
		var got: Array = [
			d["hp"], d["armor"], d["speed_mps"], d.get("gate_hp", 0), d["bounty"], d["threat"]
		]
		for i in w.size():
			assert_eq(float(got[i]), float(w[i]), "type %d field %d" % [t, i])
	assert_eq(float(c.enemy_def(SiegeIds.ENEMY_RAM)["gate_hp_per_s"]), 3.0)
	assert_eq(int(c.enemy_def(SiegeIds.ENEMY_RAM)["crew"]), 6)
	assert_eq(int(c.enemies["cap"]), 150)
	assert_eq(float(c.enemies["retreat_s"]), 3.0)
	assert_eq(float(c.enemies["lateral_m"]), 1.5)


func test_the_lateral_offset_is_seeded_and_within_one_and_a_half_metres() -> void:
	var offsets: Array = []
	for rng_seed in [3, 3, 4]:
		_wave(2, rng_seed)
		for i in 40:
			SiegeSpawner.enqueue(_rig.state, SiegeIds.ENEMY_RAIDERS, i % 3, 0.0)
		_rig.step()
		var lat: Array = _rig.state.enemies.map(func(e: SiegeEnemyState) -> float: return e.lat_m)
		for x: float in lat:
			assert_lte(absf(x), 1.5 + 1e-9)
		offsets.append(lat)
	assert_eq(offsets[0].size(), 40)
	assert_eq(offsets[0], offsets[1], "same seed, same offsets")
	assert_ne(offsets[0], offsets[2], "another seed, other offsets")
	var spread := 0.0
	for x: float in offsets[0]:
		spread = maxf(spread, absf(x))
	assert_gt(spread, 1.0, "the offsets spread across the road")


func test_enemies_do_not_collide() -> void:
	_wave()
	var a := _rig.spawn(SiegeIds.ENEMY_RAIDERS, VALLEY, 30.0)
	var b := _rig.spawn(SiegeIds.ENEMY_RAIDERS, VALLEY, 30.0)
	_rig.run(3.0)
	assert_eq(a.prog_m, b.prog_m, "two enemies on one spot keep walking together")
	assert_eq(a.pos, b.pos)


func test_a_walker_that_reaches_the_gate_damages_it_and_is_gone() -> void:
	var want := {
		SiegeIds.ENEMY_RAIDERS: 2,
		SiegeIds.ENEMY_SHIELD_WALL: 8,
		SiegeIds.ENEMY_HORSEMEN: 3,
	}
	for t: int in want:
		_wave()
		var e := _rig.spawn(t, VALLEY, _rig.road_end(VALLEY) - 0.01)
		_rig.step()
		assert_eq(_rig.state.gate_hp, 100.0 - float(want[t]), "type %d" % t)
		assert_false(_rig.state.enemies.has(e), "gone")
		var leaks := _rig.of_type(SiegeIds.EV_LEAK)
		assert_eq(leaks.size(), 1)
		assert_eq([leaks[0]["et"], leaks[0]["road"], leaks[0]["dmg"]], [t, VALLEY, want[t]])
		assert_eq(_rig.rider(1).bounty_denarii, 0.0, "no bounty for a leak")
		assert_eq(_rig.of_type(SiegeIds.EV_KILL).size(), 0)
		assert_eq(_rig.state.wave.leaks, 1)
		assert_eq(_rig.state.leaks_by_road, [0, 1, 0] as Array[int])
		assert_almost_eq(_rig.state.gate_damage_by_road[VALLEY], float(want[t]), 1e-6)


func test_a_ram_batters_three_hp_a_second_until_destroyed() -> void:
	_wave()
	var ram := _rig.spawn(SiegeIds.ENEMY_RAM, VALLEY, _rig.road_end(VALLEY) - 0.02)
	_rig.step()
	assert_eq(ram.st, SiegeIds.EN_BATTER)
	assert_eq(_rig.state.wave.leaks, 1, "a ram counts once when it reaches the gate")
	var hp := _rig.state.gate_hp
	_rig.run(20.0)
	assert_almost_eq(hp - _rig.state.gate_hp, 60.0, 0.4, "about 60 HP in 20 s")
	var leaks := _rig.of_type(SiegeIds.EV_LEAK)
	assert_between(leaks.size(), 58, 61, "one leak event per whole HP")
	assert_eq(leaks[0]["dmg"], 1)
	assert_eq(ram.hp, 600.0, "nobody shoots it")


func test_a_ram_stops_battering_when_destroyed() -> void:
	_wave()
	var ram := _rig.spawn(SiegeIds.ENEMY_RAM, VALLEY, _rig.road_end(VALLEY), 0.0, 5.0)
	ram.st = SiegeIds.EN_BATTER
	_rig.run(2.0)
	var hp := _rig.state.gate_hp
	assert_lt(hp, 100.0, "battering")
	_rig.put(1, 3)
	_rig.p_eff[1] = 250.0
	_rig.state.pad(3).cd_s = 0.0
	_rig.run(0.3)
	assert_eq(ram.hp, 0.0, "destroyed")
	_rig.state.enemies.clear()
	var after := _rig.state.gate_hp
	_rig.run(2.0)
	assert_eq(_rig.state.gate_hp, after, "the gate is not hit any more")


func test_wave_end_retreats_enemies_for_three_seconds_then_they_vanish() -> void:
	_wave()
	var a := _rig.spawn(SiegeIds.ENEMY_RAIDERS, VALLEY, 40.0)
	var ram := _rig.spawn(SiegeIds.ENEMY_RAM, VALLEY, _rig.road_end(VALLEY))
	ram.st = SiegeIds.EN_BATTER
	SiegeSpawner.enqueue(_rig.state, SiegeIds.ENEMY_RAIDERS, 0, 0.0)
	var gate := _rig.state.gate_hp
	var den := _rig.rider(1).denarii
	_rig.enter(3, 0.0)
	assert_eq(a.st, SiegeIds.EN_RETREAT)
	assert_eq(ram.st, SiegeIds.EN_RETREAT)
	assert_almost_eq(a.retreat_s, 3.0 - 0.05, 1e-6, "3 s, minus the tick that started it")
	assert_true(_rig.state.queue.is_empty(), "the queue is dropped")
	var prog := a.prog_m
	_rig.run(1.0)
	assert_lt(a.prog_m, prog, "walking back")
	assert_true(_rig.state.enemies.has(a))
	_rig.run(2.2)
	assert_true(_rig.state.enemies.is_empty(), "gone after 3 s")
	assert_eq(_rig.of_type(SiegeIds.EV_KILL).size(), 0, "no bounty")
	assert_almost_eq(_rig.state.gate_hp, gate, 1e-6, "no damage while retreating")
	assert_gte(_rig.rider(1).denarii, den, "denarii only grew from the generator")
	assert_eq(_rig.of_type(SiegeIds.EV_LEAK).size(), 0)


func test_retreating_enemies_are_not_targets() -> void:
	_wave()
	_rig.put(1, 3)
	_rig.p_eff[1] = 250.0
	var e := _rig.spawn(SiegeIds.ENEMY_SHIELD_WALL, VALLEY, _rig.road_end(VALLEY) - 10.0)
	e.st = SiegeIds.EN_RETREAT
	e.retreat_s = 3.0
	_rig.state.pad(3).cd_s = 0.0
	_rig.run(0.5)
	assert_eq(e.hp, 160.0)


func test_the_cap_holds_150_alive_and_the_rest_queue() -> void:
	_wave()
	for i in 200:
		SiegeSpawner.enqueue(_rig.state, SiegeIds.ENEMY_RAIDERS, i % 3, 0.0)
	_rig.step()
	assert_eq(_rig.state.enemies.size(), 150)
	assert_eq(_rig.state.queue.size(), 50)
	assert_eq(_rig.state.queued(), 50)
	var snap_q: int = SiegeSnapshot.encode(_rig.state)["q"]
	assert_eq(snap_q, 50, "the snapshot's q is the queue")
	for i in 10:
		_rig.state.enemies[i].hp = 0.0
	_rig.state.enemies = _rig.state.enemies.filter(
		func(e: SiegeEnemyState) -> bool: return e.hp > 0.0
	)
	_rig.step()
	assert_eq(_rig.state.enemies.size(), 150, "refilled from the queue")
	assert_eq(_rig.state.queue.size(), 40)
	var ids: Array = _rig.state.enemies.map(func(e: SiegeEnemyState) -> int: return e.id)
	var sorted := ids.duplicate()
	sorted.sort()
	assert_eq(ids, sorted, "ids ascend in spawn order, the queue is FIFO")


func test_the_queue_is_dropped_at_wave_end() -> void:
	_wave()
	for i in 200:
		SiegeSpawner.enqueue(_rig.state, SiegeIds.ENEMY_RAIDERS, 0, 0.0)
	_rig.step()
	_rig.enter(3, 0.0)
	assert_eq(_rig.state.queue.size(), 0)
	assert_eq(_rig.state.queued(), 0)
	_rig.run(3.5)
	assert_eq(_rig.state.enemies.size(), 0, "no spawn follows the dropped queue")


func test_nothing_spawns_in_breaks_or_the_cooldown() -> void:
	_rig = SiegeRig.new("short", 2)
	_rig.state.rng.seed = 3
	_rig.enter(3, 0.0)
	_rig.run(60.0)
	assert_true(_rig.state.enemies.is_empty() and _rig.state.queue.is_empty(), "break")
	_rig.enter(7, 0.0)
	assert_eq(_rig.state.role, SiegeIds.ROLE_COOLDOWN)
	_rig.run(30.0)
	assert_true(_rig.state.enemies.is_empty() and _rig.state.queue.is_empty(), "cool-down")
	assert_true(_rig.of_type(SiegeIds.EV_WAVE_START).is_empty())
