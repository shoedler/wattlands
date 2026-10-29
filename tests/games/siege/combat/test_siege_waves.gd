extends GutTest
## The wave director (brief 2.4 "Waves", "Siege engines"; 4): ranks and lateral offsets, the
## staging-ground choice, groups and their cadence, engine entry so they reach the moat 60 s
## before the wave ends, one or two rams by slot count, the siege tower in the last long wave,
## escorts, the cap and the queue, retreat, rushes, the warm-up wave and the drill.

const F := preload("res://tests/games/siege/siege_fakes.gd")

var _s: SiegeState


func before_each() -> void:
	_s = SiegeKit.state("short", 2)


func _ph(
	elapsed: float, duration: float = 300.0, role: String = SiegeIds.ROLE_WAVE
) -> SiegePhaseInfo:
	var p := SiegePhaseInfo.new()
	p.index = 2
	p.kind = Wl.WORK
	p.role = role
	p.elapsed_s = elapsed
	p.duration_s = duration
	p.remaining_s = duration - elapsed
	p.plan_elapsed_s = 420.0 + elapsed
	return p


func _drain() -> void:
	SiegeSpawner.drain(_s, SiegeKit.table(_s), [])


# --- formations ----------------------------------------------------------------------------------


func test_a_spear_block_is_4_wide_and_3_deep_1_2_m_apart() -> void:
	assert_true(
		SiegeSpawner.place_formation(
			_s, SiegeKit.table(_s), _ph(0.0), SiegeIds.ENEMY_SPEAR, 0, false
		)
	)
	assert_eq(_s.queue.size(), 12)
	var lats := {}
	var progs := {}
	for sp in _s.queue:
		lats[snappedf(sp.lat_m, 0.01)] = true
		progs[snappedf(sp.prog_m, 0.01)] = true
	var l: Array = lats.keys()
	l.sort()
	assert_eq(l, [-1.8, -0.6, 0.6, 1.8], "four files within +-1.8 m")
	var p: Array = progs.keys()
	p.sort()
	assert_eq(p.size(), 3)
	assert_almost_eq(float(p[1]) - float(p[0]), 1.2, 1e-4)
	assert_almost_eq(float(p[2]) - float(p[1]), 1.2, 1e-4)


func test_a_shield_group_is_3_by_2() -> void:
	SiegeSpawner.place_formation(_s, SiegeKit.table(_s), _ph(0.0), SiegeIds.ENEMY_SHIELD, 0, false)
	assert_eq(_s.queue.size(), 6)
	var lats := {}
	for sp in _s.queue:
		lats[snappedf(sp.lat_m, 0.01)] = true
	var l: Array = lats.keys()
	l.sort()
	assert_eq(l, [-1.2, 0.0, 1.2])


func test_chariots_come_in_pairs_6_m_apart() -> void:
	SiegeSpawner.place_formation(_s, SiegeKit.table(_s), _ph(0.0), SiegeIds.ENEMY_CHARIOT, 0, false)
	assert_eq(_s.queue.size(), 2)
	assert_almost_eq(absf(_s.queue[0].prog_m - _s.queue[1].prog_m), 6.0, 1e-4)
	for sp in _s.queue:
		assert_between(sp.lat_m, -1.8, 1.8, "a seeded lateral offset")


func test_a_formation_s_rear_rank_stands_on_the_staging_ground() -> void:
	SiegeSpawner.place_formation(_s, SiegeKit.table(_s), _ph(0.0), SiegeIds.ENEMY_SPEAR, 0, false)
	var lo := INF
	for sp in _s.queue:
		lo = minf(lo, sp.prog_m)
	assert_almost_eq(lo, 0.0, 1e-4, "the camp")


func test_a_second_formation_of_a_group_follows_the_first() -> void:
	var tb := SiegeKit.table(_s)
	SiegeSpawner.place_formation(_s, tb, _ph(0.0), SiegeIds.ENEMY_SPEAR, 0, false)
	var first: Array[float] = []
	for sp in _s.queue:
		first.append(sp.prog_m)
	_s.queue.clear()
	SiegeSpawner.place_formation(_s, tb, _ph(0.0), SiegeIds.ENEMY_SPEAR, 1, false)
	for sp in _s.queue:
		assert_gt(sp.prog_m, first.max() as float, "no overlap")


func test_formation_threats() -> void:
	var tb := SiegeKit.table(_s)
	assert_eq(SiegeSpawner.formation_threat(_s, tb, SiegeIds.ENEMY_SPEAR), 12.0)
	assert_eq(SiegeSpawner.formation_threat(_s, tb, SiegeIds.ENEMY_SHIELD), 18.0)
	assert_eq(SiegeSpawner.formation_threat(_s, tb, SiegeIds.ENEMY_CHARIOT), 6.0)


func test_draws_follow_the_mix_by_threat() -> void:
	var tb := SiegeKit.table(_s)
	var row: Array[float] = [0.5, 0.25, 0.25]
	var threat := {1: 0.0, 2: 0.0, 3: 0.0}
	for _i in 3000:
		var t := SiegeSpawner.draw_type(_s, tb, row)
		threat[t] += SiegeSpawner.formation_threat(_s, tb, t)
	var total := float(threat[1] + threat[2] + threat[3])
	assert_almost_eq(float(threat[1]) / total, 0.5, 0.04)
	assert_almost_eq(float(threat[2]) / total, 0.25, 0.04)
	assert_almost_eq(float(threat[3]) / total, 0.25, 0.04)


func test_an_empty_row_draws_nothing() -> void:
	var row: Array[float] = [0.0, 0.0, 0.0]
	assert_eq(SiegeSpawner.draw_type(_s, SiegeKit.table(_s), row), 0)


# --- staging -------------------------------------------------------------------------------------


func test_spearmen_enter_at_the_furthest_staging_ground_that_still_reaches() -> void:
	var tb := SiegeKit.table(_s)
	var st := _s.path.staging
	# 1.8 m/s; the gate 30 s before the end of a 300 s wave: by 270 s.
	assert_eq(SiegeSpawner.staging_for(_s, tb, SiegeIds.ENEMY_SPEAR, 0.0, 300.0), st[0], "the camp")
	assert_eq(
		SiegeSpawner.staging_for(_s, tb, SiegeIds.ENEMY_SPEAR, 60.0, 300.0), st[1], "the grove"
	)
	assert_eq(
		SiegeSpawner.staging_for(_s, tb, SiegeIds.ENEMY_SPEAR, 140.0, 300.0), st[2], "the wadi"
	)
	assert_eq(SiegeSpawner.staging_for(_s, tb, SiegeIds.ENEMY_SPEAR, 200.0, 300.0), -1.0, "none")


func test_the_camp_works_exactly_until_its_last_moment() -> void:
	var tb := SiegeKit.table(_s)
	var last := 270.0 - _s.path.length_m / 1.8
	assert_eq(SiegeSpawner.staging_for(_s, tb, SiegeIds.ENEMY_SPEAR, last - 0.01, 300.0), 0.0)
	assert_ne(SiegeSpawner.staging_for(_s, tb, SiegeIds.ENEMY_SPEAR, last + 0.01, 300.0), 0.0)


func test_slow_shields_skip_the_camp() -> void:
	var tb := SiegeKit.table(_s)
	assert_eq(
		SiegeSpawner.staging_for(_s, tb, SiegeIds.ENEMY_SHIELD, 0.0, 300.0), _s.path.staging[1]
	)


func test_fast_chariots_start_from_the_camp_late() -> void:
	var tb := SiegeKit.table(_s)
	assert_eq(SiegeSpawner.staging_for(_s, tb, SiegeIds.ENEMY_CHARIOT, 200.0, 300.0), 0.0)


func test_a_formation_that_cannot_reach_is_not_placed() -> void:
	assert_false(
		SiegeSpawner.place_formation(
			_s, SiegeKit.table(_s), _ph(230.0), SiegeIds.ENEMY_SHIELD, 0, false
		)
	)
	assert_true(_s.queue.is_empty())


# --- the mix -------------------------------------------------------------------------------------


func test_the_mix_follows_the_third_of_the_shift() -> void:
	var total := SiegePlanBuilder.total_s(_s.content.shift)
	assert_eq(SiegeSpawner.third_row(_s, SiegeIds.MIX_STANDARD, 10.0), [0.7, 0.1, 0.2])
	assert_eq(SiegeSpawner.third_row(_s, SiegeIds.MIX_STANDARD, total * 0.5), [0.5, 0.25, 0.25])
	assert_eq(SiegeSpawner.third_row(_s, SiegeIds.MIX_STANDARD, total - 1.0), [0.4, 0.3, 0.3])


func test_the_warm_up_is_spearmen_only_for_180_s() -> void:
	_s.role = SiegeIds.ROLE_WARMUP_WAVE
	assert_eq(
		SiegeSpawner.mix_row(_s, _ph(179.0, 300.0, SiegeIds.ROLE_WARMUP_WAVE)), [1.0, 0.0, 0.0]
	)
	var after := SiegeSpawner.mix_row(_s, _ph(181.0, 300.0, SiegeIds.ROLE_WARMUP_WAVE))
	assert_eq(after[1], 0.0, "then chariots too, never shields")
	assert_gt(after[2], 0.0)


func test_the_drill_mix_has_no_shields() -> void:
	var ph := _ph(10.0, 100.0)
	ph.mix = SiegeIds.MIX_RAIDERS_HORSEMEN
	assert_eq(SiegeSpawner.mix_row(_s, ph)[1], 0.0)


# --- groups ----------------------------------------------------------------------------------------


func test_groups_spend_the_budget_and_stop_60_s_before_the_end() -> void:
	var rig := SiegeRig.new("short", 2)
	rig.manual()
	rig.enter(2)
	var w := rig.state.wave
	var b := w.budget
	assert_gt(b, 0.0)
	var last_queued := -1.0
	var spawned := 0
	while rig.tick * Wl.SIM_DT < rig.phase_start(3) - 0.05:
		var n := rig.state.next_enemy_id
		var q := rig.state.queue.size()
		rig.step()
		if rig.state.next_enemy_id > n or rig.state.queue.size() > q:
			last_queued = rig.tick * Wl.SIM_DT - rig.phase_start(2)
			spawned += 1
	assert_lte(last_queued, 300.0 - 60.0 + 0.1, "nothing new in the last 60 s but engines' escort")
	assert_lt(w.budget_left, 1.0, "the budget is spent or dropped")
	assert_gt(spawned, 5)


func test_group_gaps_are_6_to_12_s() -> void:
	var rig := SiegeRig.new("short", 2)
	rig.manual()
	rig.enter(2)
	var gaps: Array[float] = []
	var last := rig.state.wave.spawn_in_s
	for _i in 2000:
		rig.step()
		var now := rig.state.wave.spawn_in_s
		if now > last + 1.0:
			gaps.append(now)
		last = now
	assert_gt(gaps.size(), 5)
	for g in gaps:
		assert_between(g, 6.0, 12.0)


func test_dropped_threat_is_recorded() -> void:
	var rig := SiegeRig.new("vo2", 4)
	rig.manual()
	rig.enter(2)
	rig.run(70.0)
	assert_gt(rig.state.wave.dropped, 0.0, "120 s waves: the slow types can't make it")


# --- siege engines ---------------------------------------------------------------------------------


func test_one_ram_for_one_or_two_slots() -> void:
	for n in [1, 2]:
		var s := SiegeKit.state("short", n)
		var plan := SiegeSpawner.engine_plan(s, _ph(0.0))
		assert_eq(plan.size(), 1, "%d slots" % n)
		assert_eq(int(plan[0][0]), SiegeIds.ENEMY_RAM)


func test_two_rams_25_m_apart_for_three_or_four() -> void:
	for n in [3, 4]:
		var s := SiegeKit.state("short", n)
		var plan := SiegeSpawner.engine_plan(s, _ph(0.0))
		assert_eq(plan.size(), 2, "%d slots" % n)
		assert_almost_eq(absf(float(plan[0][2]) - float(plan[1][2])), 25.0, 1e-3)


func test_a_ram_enters_where_it_reaches_the_moat_60_s_before_the_end() -> void:
	var plan := SiegeSpawner.engine_plan(_s, _ph(0.0))
	assert_eq(float(plan[0][1]), 0.0, "at the wave start")
	assert_almost_eq(float(plan[0][2]), _s.path.moat_edge_m - 0.8 * 240.0, 1e-3, "192 m out")


func test_the_pair_is_centred_on_that_point() -> void:
	var s := SiegeKit.state("short", 4)
	var plan := SiegeSpawner.engine_plan(s, _ph(0.0))
	var mid := (float(plan[0][2]) + float(plan[1][2])) * 0.5
	assert_almost_eq(mid, s.path.moat_edge_m - 0.8 * 240.0, 1e-3)


func test_a_long_wave_s_ram_enters_at_the_camp_later() -> void:
	var plan := SiegeSpawner.engine_plan(_s, _ph(0.0, 900.0))
	assert_eq(float(plan[0][2]), 0.0, "the camp")
	assert_almost_eq(float(plan[0][1]), 900.0 - 60.0 - _s.path.moat_edge_m / 0.8, 1e-3)


func test_the_siege_tower_replaces_the_rams_in_the_last_long_wave() -> void:
	var ph := _ph(0.0)
	ph.last_wave = true
	var plan := SiegeSpawner.engine_plan(SiegeKit.state("short", 4), ph)
	assert_eq(plan.size(), 1)
	assert_eq(int(plan[0][0]), SiegeIds.ENEMY_TOWER)
	assert_almost_eq(float(plan[0][2]), _s.path.moat_edge_m - 0.5 * 240.0, 1e-3)


func test_no_tower_in_waves_shorter_than_300_s() -> void:
	var ph := _ph(0.0, 120.0)
	ph.last_wave = true
	var plan := SiegeSpawner.engine_plan(SiegeKit.state("vo2", 4), ph)
	assert_eq(int(plan[0][0]), SiegeIds.ENEMY_RAM)
	assert_eq(plan.size(), 2)


func test_the_endurance_tower_enters_at_the_camp_in_time_to_dock() -> void:
	var ph := _ph(0.0, 2700.0)
	ph.last_wave = true
	var plan := SiegeSpawner.engine_plan(SiegeKit.state("endurance", 4), ph)
	assert_eq(int(plan[0][0]), SiegeIds.ENEMY_TOWER)
	assert_almost_eq(float(plan[0][1]), 2700.0 - 60.0 - _s.path.moat_edge_m / 0.5, 1e-3)


func test_the_warm_up_ram_has_half_hp_and_no_escort() -> void:
	var plan := SiegeSpawner.engine_plan(
		SiegeKit.state("short", 4), _ph(0.0, 300.0, SiegeIds.ROLE_WARMUP_WAVE)
	)
	assert_eq(plan.size(), 1, "one ram whatever the slots")
	assert_eq(float(plan[0][3]), 0.5)
	assert_eq(float(plan[0][4]), 0.0)


func test_escorts_are_10_threat_per_slot() -> void:
	var s := SiegeKit.state("short", 3)
	var plan := SiegeSpawner.engine_plan(s, _ph(0.0))
	var total := 0.0
	for en: Array in plan:
		total += float(en[4])
	assert_eq(total, 30.0)


func test_an_engine_spawns_with_a_push_event_and_its_escort() -> void:
	var rig := SiegeRig.new("short", 2)
	rig.manual()
	var ev := rig.run(0.1)
	var pushes := rig.of_type(SiegeIds.EV_PUSH, ev)
	assert_eq(pushes.size(), 1, "the warm-up ram")
	var ram := rig.state.enemy(int(pushes[0]["id"]))
	assert_not_null(ram)
	assert_eq(ram.type, SiegeIds.ENEMY_RAM)
	assert_eq(ram.hp, 300.0)
	assert_eq(rig.state.engines_total, 1)
	rig.enter(2)
	ev = rig.run(0.1)
	pushes = rig.of_type(SiegeIds.EV_PUSH, rig.events)
	assert_eq(pushes.size(), 2)
	var escorts := 0
	for e in rig.state.enemies:
		escorts += int(e.escort)
	assert_eq(escorts, 20, "2 slots x 10 threat of spearmen")


func test_a_ram_reaches_the_moat_60_s_before_the_wave_ends() -> void:
	var rig := SiegeRig.new("short", 2)
	rig.manual()
	rig.state.pad(1).type = SiegeIds.PAD_NONE
	rig.enter(2)
	rig.run(0.1)
	var ram: SiegeEnemyState = null
	for e in rig.state.enemies:
		if e.type == SiegeIds.ENEMY_RAM:
			ram = e
	assert_not_null(ram)
	var start := rig.phase_start(2)
	while ram.prog_m < rig.state.path.moat_edge_m and rig.tick * Wl.SIM_DT < start + 300.0:
		rig.step()
	assert_almost_eq(rig.tick * Wl.SIM_DT - start, 240.0, 0.2)


func test_the_siege_tower_comes_in_the_last_wave_of_short_and_docks() -> void:
	var rig := SiegeRig.new("short", 2)
	rig.manual()
	for pd in rig.state.pads:
		pd.type = SiegeIds.PAD_NONE
	rig.enter(6)
	rig.run(0.1)
	var tower: SiegeEnemyState = null
	for e in rig.state.enemies:
		if e.type == SiegeIds.ENEMY_TOWER:
			tower = e
	assert_not_null(tower, "the boss")
	rig.goto(rig.phase_start(6) + 239.0)
	tower.prog_m = rig.state.path.moat_edge_m - 0.3
	var ev := rig.run(1.0)
	assert_eq(rig.of_type(SiegeIds.EV_DOCK, ev).size(), 1)
	assert_true(rig.state.tar.boarded)


# --- the cap, the queue, retreat ---------------------------------------------------------------


func test_at_most_150_alive_and_the_rest_wait() -> void:
	for i in 200:
		SiegeSpawner.enqueue(_s, SiegeIds.ENEMY_SPEAR, float(i % 50))
	_drain()
	assert_eq(_s.enemies.size(), 150)
	assert_eq(_s.queue.size(), 50)
	assert_eq(_s.queued(), 50)


func test_the_queue_is_first_in_first_out() -> void:
	for i in 152:
		SiegeSpawner.enqueue(_s, SiegeIds.ENEMY_SPEAR, float(i))
	_drain()
	assert_eq(_s.queue[0].prog_m, 150.0)
	_s.enemies.pop_back()
	_drain()
	assert_eq(_s.enemies.back().prog_m, 150.0)


func test_ids_ascend_in_spawn_order() -> void:
	for i in 5:
		SiegeSpawner.enqueue(_s, SiegeIds.ENEMY_SHIELD, 1.0)
	_drain()
	for i in range(1, 5):
		assert_eq(_s.enemies[i].id, _s.enemies[i - 1].id + 1)


func test_at_wave_end_the_queue_is_dropped_and_enemies_retreat_then_vanish() -> void:
	var rig := SiegeRig.new("short", 2)
	rig.manual()
	rig.enter(2)
	rig.run(30.0)
	SiegeSpawner.enqueue(rig.state, SiegeIds.ENEMY_SPEAR, 0.0)
	rig.spawn(SiegeIds.ENEMY_SPEAR, 100.0)
	var gold := rig.rider().gold
	rig.enter(3)
	assert_true(rig.state.queue.is_empty())
	for e in rig.state.enemies:
		assert_eq(e.st, SiegeIds.EN_RETREAT)
	rig.run(3.1)
	assert_true(rig.state.enemies.is_empty())
	assert_gte(rig.rider().gold, gold, "no bounty lost, none paid by retreaters")


func test_nothing_spawns_in_breaks_or_the_cool_down() -> void:
	var rig := SiegeRig.new("drill", 1)
	rig.manual()
	rig.enter(2)
	rig.run(5.0)
	assert_true(rig.state.in_cooldown())
	assert_eq(rig.state.enemies.size(), 0)
	assert_eq(rig.state.queued(), 0)
	var rig2 := SiegeRig.new("short", 1)
	rig2.manual()
	rig2.enter(1)
	rig2.run(30.0)
	assert_eq(rig2.state.next_enemy_id, 1, "the build break spawns nobody")


# --- the warm-up wave, rushes, the drill ------------------------------------------------------


func test_the_warm_up_budget_is_40_percent_of_b() -> void:
	var rig := SiegeRig.new("short", 2)
	rig.manual()
	rig.enter(0)
	var mean_pct := (50.0 + 65.0) / 2.0
	var b := 0.0
	for r in rig.state.riders:
		b += SiegeRules.planned_p_eff_w(rig.state, r, mean_pct) / 250.0
	b *= rig.content.num("c_budget") * (300.0 - 60.0) / 60.0
	assert_almost_eq(rig.state.wave.budget, 0.4 * b, 1e-3)


func test_the_warm_up_spawns_only_spearmen_for_180_s() -> void:
	var rig := SiegeRig.new("short", 2)
	rig.manual()
	rig.run(179.0)
	for e in rig.state.enemies:
		assert_true(
			e.type == SiegeIds.ENEMY_SPEAR or e.type == SiegeIds.ENEMY_RAM,
			"type %d before 180 s" % e.type
		)


func test_endurance_rushes_start_at_8_minutes_with_8_percent_of_b() -> void:
	var rig := SiegeRig.new("endurance", 2)
	rig.manual()
	rig.enter(2)
	var b := rig.state.wave.budget
	rig.goto(rig.phase_start(2) + 479.9)
	var ev := rig.run(0.2)
	var rush := rig.of_type(SiegeIds.EV_RUSH, ev)
	assert_eq(rush.size(), 1)
	assert_eq(int(rush[0]["on"]), 1)
	assert_eq(int(rush[0]["i"]), 0)
	assert_true(rig.state.rush_on())
	assert_almost_eq(rig.state.wave.rush_budget_left + rig.state.wave.rush_acc, 0.08 * b, 0.08 * b)
	ev = rig.run(30.0)
	var ends := rig.of_type(SiegeIds.EV_RUSH, ev)
	assert_eq(int(ends.back()["on"]), 0, "the rush ends after 30 s")
	assert_false(rig.state.rush_on())


func test_rush_bodies_are_spearmen_and_chariots_marked_rush() -> void:
	var rig := SiegeRig.new("endurance", 4)
	rig.manual()
	rig.enter(2)
	rig.goto(rig.phase_start(2) + 479.9)
	rig.run(30.5)
	var any := false
	for e in rig.state.enemies:
		if e.rush:
			any = true
			assert_true(e.type == SiegeIds.ENEMY_SPEAR or e.type == SiegeIds.ENEMY_CHARIOT)
	for sp in rig.state.queue:
		if sp.rush:
			any = true
	assert_true(any, "the rush brought bodies")


func test_the_drill_is_wave_1_with_a_ram_push_and_escort() -> void:
	var rig := SiegeRig.new("drill", 1)
	rig.manual()
	rig.enter(1)
	assert_eq(rig.state.role, SiegeIds.ROLE_WAVE)
	assert_eq(rig.state.wave_no, 1)
	var starts := rig.of_type(SiegeIds.EV_WAVE_START)
	assert_eq(int(starts.back()["n"]), 1)
	rig.run(0.1)
	assert_eq(rig.of_type(SiegeIds.EV_PUSH).size(), 1)
	var escorts := 0
	for e in rig.state.enemies:
		escorts += int(e.escort)
	assert_eq(escorts, 10)
	assert_true(rig.state.wave.engines.is_empty(), "the one ram has entered")


func test_the_drill_ends_the_shift() -> void:
	var rig := SiegeRig.new("drill", 1)
	rig.manual()
	rig.enter(1)
	rig.goto(rig.phase_start(2))
	rig.step()
	assert_true(rig.state.done)
	assert_eq(rig.state.wave_gate_frac.size(), 1)
