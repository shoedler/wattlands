extends GutTest
## The Behemoth (brief 2.4 Enemies and Foundry Gate): creep, push-back, the two phases, the main
## gun with its telegraph and "Surge to evade", the secondary, death and withdrawal.

const BOSS := 10


## A rig in the boss segment; `quiet`: the crew's gun stays out of it (nothing loads or fires).
func _rig(crew: int = 2, quiet: bool = false) -> TankRulesRig:
	var rig := TankRulesRig.new(crew)
	rig.no_fire = quiet
	rig.enter(BOSS, 1.0)
	return rig


func _gap(rig: TankRulesRig) -> float:
	return rig.state.boss.x_px - (rig.hull().x_px + rig.hull().hull_w)


func _driver(rig: TankRulesRig) -> int:
	return rig.peer_of(TankIds.ENGINE_DIESEL)


func test_the_boss_starts_in_phase_1_at_full_health_scaled_by_the_tank() -> void:
	for crew in [1, 2, 3]:
		var rig := _rig(crew)
		var b := rig.state.boss
		assert_eq(b.phase, TankIds.BOSS_PHASE_1)
		var def := rig.content.boss_def()
		var scale := rig.content.enemy_scale(TankIds.tank_for_crew(crew))
		assert_almost_eq(b.bogie_max, float(def["bogie_hp"]) * scale, 0.001)
		assert_almost_eq(b.turret_max, float(def["turret_hp"]) * scale, 0.001)
		for hp in b.bogie_hp:
			assert_almost_eq(
				hp, b.bogie_max, 2.0, "full health (a Citadel secondary may have touched a bogie)"
			)
		assert_eq(b.turret_hp, b.turret_max)
		assert_eq(b.bogies_left(), 3)
		assert_eq(rig.of_type("boss_phase")[0]["p"], TankIds.BOSS_PHASE_1)


func test_the_boss_stands_partly_past_the_right_edge() -> void:
	var rig := _rig(1)
	var left_screen := rig.state.boss.x_px - rig.state.camera_x()
	assert_almost_eq(left_screen, float(rig.content.segment(BOSS)["boss"]["start_left_px"]), 0.5)
	assert_gt(left_screen + 320.0, 640.0, "its 320 px hull runs off the right edge")


func test_in_phase_1_it_creeps_2_px_a_second_until_it_is_stop_px_away() -> void:
	var rig := _rig(1, true)
	var gap := _gap(rig)
	var start := float(rig.content.segment(BOSS)["boss"]["start_left_px"])
	assert_almost_eq(gap, start - float(TankConst.REAR_SCREEN_X) - rig.hull().hull_w, 1.0)
	rig.run(10.0)
	assert_almost_eq(gap - _gap(rig), 20.0, 0.2, "2 px/s")
	var stop := float(rig.content.boss_def()["stop_px"])
	rig.run(ceilf((_gap(rig) - stop) / 2.0) + 1.0)
	assert_almost_eq(
		_gap(rig), stop, 0.01, "it stops stop_px from the hull's front (120 in the brief)"
	)
	rig.run(5.0)
	assert_almost_eq(_gap(rig), stop, 0.01)
	var cit := _rig(3, true)
	cit.run(ceilf((_gap(cit) - stop) / 2.0) + 1.0)
	assert_almost_eq(_gap(cit), stop, 0.01)


func test_each_broken_bogie_pushes_it_back_24_px_and_the_third_starts_phase_2() -> void:
	var rig := _rig(1, true)
	rig.run(80.0)
	var aux := TankAux.of(rig.state)
	var b := rig.state.boss
	var x := b.x_px
	TankShells.damage_boss(rig.state, aux, 0, 1000.0, 0, rig.events)
	assert_eq(b.bogie_hp[0], 0.0)
	assert_almost_eq(b.x_px, x + 24.0, 0.001)
	assert_eq(b.phase, TankIds.BOSS_PHASE_1)
	TankShells.damage_boss(rig.state, aux, 1, 1000.0, 0, rig.events)
	TankShells.damage_boss(rig.state, aux, 2, 1000.0, 0, rig.events)
	assert_almost_eq(b.x_px, x + 72.0, 0.001)
	assert_eq(b.phase, TankIds.BOSS_PHASE_2)
	assert_eq(rig.of_type("boss_phase").back()["p"], TankIds.BOSS_PHASE_2)
	var x2 := b.x_px
	rig.run(20.0)
	assert_eq(b.x_px, x2, "phase 2: immobile")


func test_a_broken_bogie_cannot_break_twice() -> void:
	var rig := _rig(1, true)
	var aux := TankAux.of(rig.state)
	TankShells.damage_boss(rig.state, aux, 0, 1000.0, 0, rig.events)
	var x := rig.state.boss.x_px
	TankShells.damage_boss(rig.state, aux, 0, 1000.0, 0, rig.events)
	assert_eq(rig.state.boss.x_px, x)


func test_the_turret_only_takes_damage_in_phase_2() -> void:
	var rig := _rig(1, true)
	var aux := TankAux.of(rig.state)
	var b := rig.state.boss
	TankShells.damage_boss(rig.state, aux, TankBossState.TURRET_PART, 100.0, 0, rig.events)
	assert_eq(b.turret_hp, b.turret_max, "armoured while a bogie stands")
	for i in 3:
		TankShells.damage_boss(rig.state, aux, i, 1000.0, 0, rig.events)
	TankShells.damage_boss(rig.state, aux, TankBossState.TURRET_PART, 30.0, 0, rig.events)
	assert_almost_eq(b.turret_hp, b.turret_max - 30.0, 0.001)


func test_killing_the_turret_kills_the_behemoth() -> void:
	var rig := _rig(2)
	var aux := TankAux.of(rig.state)
	for i in 3:
		TankShells.damage_boss(rig.state, aux, i, 1000.0, 0, rig.events)
	TankShells.damage_boss(rig.state, aux, TankBossState.TURRET_PART, 10000.0, 1, rig.events)
	var b := rig.state.boss
	assert_eq(b.phase, TankIds.BOSS_DEAD)
	assert_true(rig.state.score.behemoth_killed)
	assert_eq(rig.state.score.kills[TankIds.BOSS_CODE], 1)
	var kill := rig.of_type("kill")[0]
	assert_eq([kill["e"], kill["by"], kill["s"]], [TankIds.BOSS_CODE, TankEvents.BY_SHELL, 1])
	assert_eq(rig.of_type("boss_phase").back()["p"], TankIds.BOSS_DEAD)
	rig.run(0.1)
	assert_true(rig.state.seg.objective_done, "the objective is the Behemoth's death")
	assert_true(rig.state.seg.regroup, "min_s (120 s) has not passed")


func test_auto_aim_takes_the_nearest_standing_bogie_then_the_turret() -> void:
	var rig := _rig(1, true)
	rig.run(100.0)
	var aux := TankAux.of(rig.state)
	var order: Array[int] = []
	for step in 4:
		aux.aim_valid = false
		TankTargets.build(rig.state, aux)
		var t := TankAim.current(rig.state, aux)
		assert_not_null(t, "step %d" % step)
		order.append(t.id)
		TankShells.damage_boss(rig.state, aux, t.part, 10000.0, 0, rig.events)
		rig.state.boss.x_px = (
			rig.hull().x_px + rig.hull().hull_w + float(rig.content.boss_def()["stop_px"])
		)
	assert_eq(
		order,
		[
			TankBossState.part_id(0),
			TankBossState.part_id(1),
			TankBossState.part_id(2),
			TankBossState.part_id(3)
		],
		"bogies nearest the tank first, the turret last"
	)


func test_the_main_gun_fires_every_35_to_45_seconds_after_a_6_second_telegraph() -> void:
	var rig := _rig(2)
	rig.hull().hp = 100000.0
	rig.hull().hp_max = 100000.0
	var b := rig.state.boss
	assert_between(b.main_s, 35.0, 45.0)
	var shots: Array[float] = []
	var telegraphs: Array[float] = []
	for _i in 2200:
		rig.step()
		if b.telegraph_s > 0.0:
			telegraphs.append(b.telegraph_s)
		for e in rig.events:
			if e["type"] == "shot" and e["sh"] == TankIds.SHELL_BOSS_MAIN:
				shots.append(rig.seg_t)
		rig.events.clear()
	assert_gte(shots.size(), 2, "two shots in 110 s")
	assert_between(shots[0], 35.0, 46.0)
	assert_between(shots[1] - shots[0], 35.0, 45.5)
	assert_almost_eq(telegraphs.max(), 6.0, 0.1, "the telegraph shows for 6 s")
	assert_lte(telegraphs[0], 6.0)


func test_in_phase_2_the_main_gun_comes_every_25_to_35_seconds() -> void:
	var rig := _rig(2)
	rig.hull().hp = 100000.0
	rig.hull().hp_max = 100000.0
	var aux := TankAux.of(rig.state)
	for i in 3:
		TankShells.damage_boss(rig.state, aux, i, 1000.0, 0, rig.events)
	var b := rig.state.boss
	b.main_s = 1.0
	var gaps: Array[float] = []
	var last := -1.0
	for _i in 2400:
		rig.step()
		for e in rig.events:
			if e["type"] == "shot" and e["sh"] == TankIds.SHELL_BOSS_MAIN:
				if last >= 0.0:
					gaps.append(rig.seg_t - last)
				last = rig.seg_t
		rig.events.clear()
	assert_gte(gaps.size(), 2)
	for g in gaps:
		assert_between(g, 24.9, 35.2)


func test_the_main_gun_hits_for_20_and_raises_the_boss_hit_event() -> void:
	var rig := _rig(2)
	rig.hull().evasive = false
	var b := rig.state.boss
	b.main_s = 0.06
	var hp := rig.hull().hp
	var hit_seen := false
	for _i in 600:
		rig.hull().evasive = false
		rig.step()
		for e in rig.events:
			if e["type"] == "hit" and TankEvents.is_boss_main_hit(e):
				hit_seen = true
				assert_eq(e["dmg"], int(rig.content.boss_def()["main"]["damage"]))
				assert_eq(e["sh"], TankIds.SHELL_BOSS_MAIN)
		rig.events.clear()
		if hit_seen:
			break
	# With 0.85 the roll can miss; try more rolls on other seeds before giving up.
	var tries := 0
	while not hit_seen and tries < 12:
		tries += 1
		var r2 := TankRulesRig.new(2, "ashfall_road", true, 100 + tries)
		r2.enter(BOSS, 1.0)
		r2.state.boss.main_s = 0.06
		for _i in 400:
			r2.hull().evasive = false
			r2.step()
			for e in r2.events:
				if e["type"] == "hit" and TankEvents.is_boss_main_hit(e):
					hit_seen = true
			r2.events.clear()
			if hit_seen:
				hp = r2.hull().hp
				break
	assert_true(hit_seen, "a Behemoth main-gun hit")
	assert_false(
		TankEvents.is_tank_hit(
			{"type": "hit", "on": 0, "sh": TankIds.SHELL_BOSS_MAIN, "dmg": 20}, 8.0
		),
		"it is not a plain tank hit"
	)


func _sprint(rig: TankRulesRig, peer: int, seconds: float) -> void:
	rig.power_w[peer] = 1.5 * rig.slots[peer - 1].ftp
	rig.run(seconds)


func test_a_sprint_held_3_seconds_inside_the_telegraph_makes_the_shot_miss() -> void:
	var rig := _rig(2)
	var b := rig.state.boss
	var d := _driver(rig)
	rig.hull().hp = 100000.0
	rig.hull().hp_max = 100000.0
	b.main_s = 7.0
	b.secondary_s = 1000.0
	rig.run(1.2)
	assert_gt(b.telegraph_s, 0.0, "telegraph")
	assert_true(rig.rider(d).can_evade, "the driver rides SIM in the boss: Surge to evade")
	rig.power_w[d] = 1.5 * rig.slots[d - 1].ftp
	rig.run(3.0)
	assert_false(b.evaded, "the trailing 3 s average needs about 1.5 s to reach 1.2 x FTP")
	rig.run(2.0)
	assert_true(
		b.evaded, "held 3 s inside the telegraph: about 1.75 s for the rule to hold, then 3 s"
	)
	assert_eq(rig.of_type("evade").size(), 0, "the event comes when the shot resolves")
	var hp := rig.hull().hp
	rig.run(3.0)
	assert_eq(b.telegraph_s, 0.0, "the gun fired")
	var ev := rig.of_type("evade")
	assert_eq(ev.size(), 1)
	assert_eq(
		[ev[0]["id"], ev[0]["e"], ev[0]["ok"], ev[0]["s"]],
		[TankEvade.boss_shooter(), TankIds.BOSS_CODE, 1, rig.slots[d - 1].slot_index]
	)
	assert_eq([rig.rider(d).evades_ok, rig.rider(d).evades_tried], [1, 1])
	assert_eq([rig.state.score.evades_ok, rig.state.score.evades_tried], [1, 1])
	rig.run(4.0)
	assert_eq(rig.hull().hp, hp, "and missed")
	assert_false(b.evaded, "armed again for the next shot")


func test_without_the_sprint_the_telegraphed_shot_is_a_normal_roll() -> void:
	var hits := 0
	for s in 30:
		var rig := TankRulesRig.new(2, "ashfall_road", true, 200 + s)
		rig.enter(BOSS, 1.0)
		rig.hull().hp = 100000.0
		rig.hull().hp_max = 100000.0
		rig.state.boss.main_s = 6.5
		rig.state.boss.secondary_s = 1000.0
		rig.power_w[_driver(rig)] = 100.0
		rig.hull().evasive = false
		rig.run(8.0)
		for e in rig.events:
			if e["type"] == "hit" and TankEvents.is_boss_main_hit(e):
				hits += 1
	var content := TankContent.from_dicts(TankContent.read_files("ashfall_road"), "ashfall_road")
	var chance := float(content.boss_def()["main"]["hit"])
	assert_between(
		float(hits) / 30.0,
		chance - 0.2,
		minf(chance + 0.2, 1.0),
		"about the main gun's hit chance of the shots land"
	)


func test_the_evade_does_nothing_in_the_first_300_seconds() -> void:
	var rig := _rig(2)
	rig.plan_t = 200.0
	var b := rig.state.boss
	var d := _driver(rig)
	b.main_s = 7.0
	rig.run(1.2)
	_sprint(rig, d, 5.0)
	assert_false(b.evaded)
	assert_false(rig.rider(d).can_evade)
	rig.run(1.0)
	var ev := rig.of_type("evade")
	assert_eq(ev.size(), 1, "the telegraphed shot resolves")
	assert_eq(ev[0]["ok"], 0, "not evaded")
	assert_eq(rig.state.score.evades_tried, 0, "nobody could evade: not an evade tried")


func test_the_secondary_fires_3_damage_every_5_seconds() -> void:
	var rig := _rig(2)
	rig.hull().hp = 100000.0
	rig.hull().hp_max = 100000.0
	rig.state.boss.main_s = 1000.0
	var n := 0
	for _i in 1200:
		rig.step()
		for e in rig.events:
			if (
				e["type"] == "shot"
				and e["sh"] == TankIds.SHELL_ENEMY
				and e["e"] == TankIds.BOSS_CODE
			):
				n += 1
		rig.events.clear()
	assert_between(n, 11, 13, "one every 5 s over 60 s")
	var s: TankShellState = null
	rig.state.boss.secondary_s = 0.01
	rig.run(0.1)
	for sh in rig.state.shells:
		if not sh.friendly:
			s = sh
	assert_not_null(s)
	assert_eq(s.damage, float(rig.content.boss_def()["secondary"]["damage"]))


func test_a_boss_alive_when_the_segment_ends_withdraws() -> void:
	var rig := _rig(2)
	rig.enter(11, 0.0, Wl.ENDED_MAX_S)
	assert_eq(rig.state.boss.phase, TankIds.BOSS_WITHDRAWN)
	assert_eq(rig.of_type("boss_phase").back()["p"], TankIds.BOSS_WITHDRAWN)
	assert_eq(rig.state.outcome, TankIds.OUTCOME_WITHDRAWN)
	assert_eq(rig.of_type("overrun").back()["sg"], TankIds.seg_code(TankIds.SEG_BOSS))
	rig.run(5.0)
	assert_eq(rig.state.shells.size(), 0, "no more shots")


func test_a_dead_boss_stays_dead_through_the_cooldown_and_the_outcome_is_victory() -> void:
	var rig := _rig(2)
	var aux := TankAux.of(rig.state)
	for i in 3:
		TankShells.damage_boss(rig.state, aux, i, 1000.0, 0, rig.events)
	TankShells.damage_boss(rig.state, aux, TankBossState.TURRET_PART, 10000.0, 0, rig.events)
	rig.enter(11, 0.0, Wl.ENDED_END_PHASE)
	assert_eq(rig.state.boss.phase, TankIds.BOSS_DEAD)
	assert_eq(rig.state.outcome, TankIds.OUTCOME_VICTORY)
	assert_eq(rig.of_type("overrun").size(), 0)
