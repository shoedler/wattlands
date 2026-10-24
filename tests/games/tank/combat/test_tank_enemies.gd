extends GutTest
## The enemy tanks (brief 2.4 Enemies; ADR "P0 simplifications" 1 and 3): entering, held
## distances and their clamps, keeping station, weaving, telegraphs, shot cadence and damage, hit
## rolls with the session RNG, where shells land, the caps.

const ADVANCE := 1
const GUN_LINE := 2
const SKIRMISH := 1


## A quiet Advance: no encounters, no obstacles, the gun and the lever out of the picture.
static func _quiet(index: int, props: Dictionary = {"encounters": [], "obstacles": []}) -> Callable:
	return func(files: Dictionary) -> void:
		(files["mission"]["segments"][index] as Dictionary).merge(props, true)


func _rig(crew: int = 1, index: int = ADVANCE, seed_v: int = 7) -> TankRulesRig:
	var rig := TankRulesRig.new(crew, "ashfall_road", true, seed_v, _quiet(index))
	rig.no_fire = true
	rig.enter(index, 5.0)
	return rig


## Spawns `type` as the enemy list's only member the way an encounter does (rolled hold).
func _enter(rig: TankRulesRig, type: String, side: int = 1) -> TankEnemyState:
	return TankEnemies.spawn(rig.state, TankAux.of(rig.state), type, side, -1.0, false, false, 0)


func _dist(rig: TankRulesRig, e: TankEnemyState) -> float:
	return TankEnemies.distance(rig.state, e)


func test_enemies_enter_from_the_screen_edge_and_hold_a_distance_from_the_hulls_nearer_end(
) -> void:
	var rig := _rig(1)
	var cam := rig.state.camera_x()
	var light := _enter(rig, TankIds.ENEMY_LIGHT)
	assert_gte(light.x_px, cam + 640.0, "off the right edge")
	assert_eq(light.mode, TankIds.EM_ENTER)
	var rear := _enter(rig, TankIds.ENEMY_LIGHT, -1)
	assert_lte(rear.x_px + rear.w, cam, "off the left edge")
	rig.run(12.0)
	assert_eq(light.mode, TankIds.EM_HOLD)
	assert_between(_dist(rig, light), 120.0 - 8.5, 140.0 + 8.5, "120-140 px with the weave")


func test_a_light_tank_weaves_around_its_hold_with_an_8_px_amplitude() -> void:
	var rig := _rig(1)
	var e := _enter(rig, TankIds.ENEMY_LIGHT)
	rig.run(12.0)
	var lo := INF
	var hi := -INF
	for _i in 100:
		rig.run(0.1)
		lo = minf(lo, _dist(rig, e))
		hi = maxf(hi, _dist(rig, e))
	assert_almost_eq(hi - lo, 16.0, 0.8, "+-8 px")
	assert_almost_eq((hi + lo) * 0.5, e.hold_px, 0.8)


func test_enemies_in_an_advance_keep_station_with_the_moving_hull() -> void:
	var rig := _rig(1)
	var m := _enter(rig, TankIds.ENEMY_MEDIUM)
	rig.run(12.0)
	var d0 := _dist(rig, m)
	var x0 := rig.hull().x_px
	rig.run(5.0)
	assert_gt(rig.hull().x_px, x0 + 100.0, "the tank moved")
	assert_almost_eq(_dist(rig, m), d0, 0.01, "same distance")


func test_held_distances_are_rolled_per_type_and_clamped_to_the_screen() -> void:
	# Medium 260-340, light 120-140, clamp: an enemy ahead ends at screen x <= 632.
	for crew in [1, 2, 3]:
		var rig := _rig(crew)
		var front_screen := 16.0 + rig.hull().hull_w
		for type in [TankIds.ENEMY_MEDIUM, TankIds.ENEMY_LIGHT, TankIds.ENEMY_DESTROYER]:
			for _i in 12:
				var e := _enter(rig, type)
				var far_edge_screen := front_screen + e.hold_px + e.w
				assert_lte(far_edge_screen, 632.0 + 0.01, "%s crew %d" % [type, crew])
				rig.state.enemies.erase(e)
	var rig := _rig(1)
	var seen := {}
	for _i in 40:
		var e := _enter(rig, TankIds.ENEMY_MEDIUM)
		assert_between(e.hold_px, 260.0, 320.0, "Bulwark: 260-340 clamped to 320")
		seen[snappedf(e.hold_px, 10.0)] = true
		rig.state.enemies.erase(e)
	assert_gt(seen.size(), 3, "rolled, not fixed")
	var cit := _rig(3)
	var m := _enter(cit, TankIds.ENEMY_MEDIUM)
	assert_eq(
		m.hold_px,
		632.0 - 104.0 - (16.0 + 288.0),
		"the Citadel's long hull clamps a medium to 224 px"
	)


func test_a_tank_destroyer_stops_at_the_screen_edge() -> void:
	for crew in [1, 2, 3]:
		var rig := _rig(crew)
		var d := _enter(rig, TankIds.ENEMY_DESTROYER)
		d.gun_s = 100.0
		rig.run(8.0)
		assert_eq(d.mode, TankIds.EM_HOLD)
		assert_almost_eq(
			d.x_px + d.w - rig.state.camera_x(), 632.0, 1.0, "crew %d: far edge at 632" % crew
		)


func test_an_enemy_behind_shows_24_px_at_the_left_edge() -> void:
	var rig := _rig(1)
	var e := _enter(rig, TankIds.ENEMY_LIGHT, -1)
	rig.run(5.0)
	var right_screen := e.x_px + e.w - rig.state.camera_x()
	assert_gte(right_screen, 24.0 - 0.01)
	assert_almost_eq(right_screen, 24.0, 8.5, "within the weave")


func test_a_light_tank_fires_4_damage_every_4_seconds() -> void:
	var rig := _rig(1)
	var e := _enter(rig, TankIds.ENEMY_LIGHT)
	rig.run(12.0)
	rig.events.clear()
	rig.run(40.0)
	var shots := rig.of_type("shot").filter(func(x: Dictionary) -> bool: return x["src"] == e.id)
	assert_between(shots.size(), 9, 11, "one every 4 s")
	assert_eq(shots[0]["s"], -1)
	assert_eq(shots[0]["sh"], TankIds.SHELL_ENEMY)
	assert_eq(shots[0]["e"], 1, "enemy code in the event")


func test_the_shot_cadence_and_damage_of_every_type() -> void:
	# The brief: light 4 / 4 s, medium 8 / 6 s, destroyer 15 / 8 s, dug-in 10 / 7 s, heavy 12 / 7 s;
	# the shipped numbers are tuned (enemies.json), so the table comes from the content.
	var content := TankContent.from_dicts(TankContent.read_files("ashfall_road"), "ashfall_road")
	var table := {}
	for type in TankIds.ENEMY_TYPES:
		var gun: Dictionary = content.enemy_def(type)["gun"]
		table[type] = [float(gun["damage"]), float(gun["every_s"]), float(gun["hit"])]
	for type: String in table:
		var rig := _rig(3)
		rig.hull().hp = 100000.0
		rig.hull().hp_max = 100000.0
		var e := rig.spawn(type, 1, 220.0)
		e.gun_s = 0.5
		rig.run(1.0)
		var first: TankShellState = null
		for s in rig.state.shells:
			if not s.friendly:
				first = s
		assert_not_null(first, type)
		assert_eq(first.damage, table[type][0], "%s damage" % type)
		var chance := float(rig.content.enemy_def(type)["gun"]["hit"])
		assert_between(chance, 0.3, 0.95, "%s has a real hit chance" % type)
		assert_eq(first.source, e.id)
		assert_almost_eq(
			e.gun_s, table[type][1] - 0.5, 0.1, "%s reloads in %.0f s" % [type, table[type][1]]
		)


func test_a_destroyer_telegraphs_for_4_seconds_before_each_shot_and_shifts_40_px_after() -> void:
	var rig := _rig(1)
	var e := rig.spawn(TankIds.ENEMY_DESTROYER, 1, 312.0)
	e.gun_s = 6.0
	rig.run(2.2)
	assert_eq(e.mode, TankIds.EM_TELEGRAPH)
	assert_almost_eq(e.telegraph_s, 3.8, 0.15, "the glint runs for the last 4 s")
	assert_eq(rig.of_type("shot").size(), 0)
	rig.run(4.0)
	assert_eq(e.telegraph_s, 0.0, "fired")
	assert_eq(rig.of_type("shot").size(), 1)
	assert_almost_eq(e.hold_px, 272.0, 0.01, "moves 40 px closer after the shot")
	rig.run(3.0)
	assert_eq(e.mode, TankIds.EM_HOLD)
	assert_almost_eq(_dist(rig, e), 272.0, 4.0, "it holds 40 px closer")
	e.gun_s = 0.1
	rig.run(0.5)
	assert_almost_eq(e.hold_px, 312.0, 0.01, "and back to the edge after the next")


func test_a_destroyer_in_telegraph_is_the_autoaims_first_target() -> void:
	var rig := _rig(3)
	var aux := TankAux.of(rig.state)
	var d := rig.spawn(TankIds.ENEMY_DESTROYER, 1, 216.0)
	var dug := rig.spawn(TankIds.ENEMY_DUGIN, 1, 230.0)
	TankTargets.build(rig.state, aux)
	assert_eq(
		TankTargets.by_id(aux, d.id).tier,
		TankTarget.TIER_MEDIUM,
		"idle destroyer ranks as a medium"
	)
	d.mode = TankIds.EM_TELEGRAPH
	d.telegraph_s = 2.0
	TankTargets.build(rig.state, aux)
	assert_eq(TankTargets.by_id(aux, d.id).tier, TankTarget.TIER_TELEGRAPH)
	assert_lt(TankTargets.by_id(aux, d.id).tier, TankTargets.by_id(aux, dug.id).tier)


func test_a_dug_in_tank_can_only_be_hit_on_its_turret() -> void:
	var rig := _rig(3, GUN_LINE)
	var aux := TankAux.of(rig.state)
	var dug := rig.spawn(TankIds.ENEMY_DUGIN, 1, 230.0)
	TankTargets.build(rig.state, aux)
	var t := TankTargets.by_id(aux, dug.id)
	var hb := aux.geo.enemy_hitbox("enemy_dugin")
	assert_eq(t.rect.size, hb.size, "the hit box is the turret above the concrete")
	assert_lt(t.rect.size.y, float(dug.h) * 0.6)
	assert_almost_eq(t.rect.position.x, dug.x_px + hb.position.x, 0.001)
	assert_almost_eq(t.rect.position.y, float(TankConst.GROUND_Y - dug.h) + hb.position.y, 0.001)


func test_a_dug_in_tank_holds_where_the_mission_put_it_and_fires_from_the_start() -> void:
	var rig := TankRulesRig.new(1)
	rig.no_fire = true
	rig.enter(GUN_LINE, 1.0)
	var guns := rig.state.enemies
	var want := 0
	for spec: Dictionary in rig.content.segment(GUN_LINE)["enemies"]:
		want += rig.content.scaled_count(int(spec["count"]), TankIds.TANK_BULWARK)
	assert_eq(guns.size(), want, "the mission's gun line x the Bulwark's scale")
	assert_gt(want, 0)
	var holding := 0
	for e in guns:
		assert_true(e.fixed)
		assert_true(e.gun_line)
		if e.code == TankIds.enemy_code(TankIds.ENEMY_DUGIN):
			assert_eq(e.mode, TankIds.EM_HOLD)
			holding += 1
	assert_gt(holding, 0, "dug-in tanks stand there from the start")
	assert_eq(rig.state.gun_line.guns_total, want)
	assert_eq(rig.state.gun_line.guns_left, want)
	assert_true(rig.state.gun_line.active)
	var digs: Array = guns.filter(
		func(e: TankEnemyState) -> bool: return e.code == TankIds.enemy_code(TankIds.ENEMY_DUGIN)
	)
	var x0: Array = digs.map(func(e: TankEnemyState) -> float: return e.x_px)
	rig.hull().holding = true
	rig.run(10.0)
	assert_eq(digs.map(func(e: TankEnemyState) -> float: return e.x_px), x0, "fixed in world space")


func _heavy_rig(crew: int = 1) -> TankRulesRig:
	var rig := TankRulesRig.new(crew)
	rig.no_fire = true
	rig.enter(5, 1.0)
	return rig


func test_a_heavy_tank_rolls_in_to_its_hold_and_halts() -> void:
	var rig := _heavy_rig(3)
	var h: TankEnemyState = null
	for e in rig.state.enemies:
		if e.code == TankIds.enemy_code(TankIds.ENEMY_HEAVY):
			h = e
	assert_not_null(h)
	assert_eq(h.mode, TankIds.EM_ENTER)
	assert_gte(h.x_px, rig.state.camera_x() + 640.0)
	rig.run(15.0)
	assert_eq(h.mode, TankIds.EM_HOLD)
	var front := rig.hull().x_px + rig.hull().hull_w
	assert_almost_eq(h.x_px - front, h.hold_px, 0.01)
	assert_true(h.fixed)
	assert_eq(h.hp_max, float(rig.content.enemy_def("heavy")["hp"]), "Citadel: scale 1.0")


func test_a_heavy_tank_telegraphs_3_seconds_and_backs_off_30_px_after_taking_50() -> void:
	var rig := _heavy_rig(1)
	var h: TankEnemyState = null
	for e in rig.state.enemies:
		if e.code == TankIds.enemy_code(TankIds.ENEMY_HEAVY):
			h = e
	rig.run(15.0)
	h.hold_px = 250.0
	h.x_px = rig.hull().x_px + rig.hull().hull_w + 250.0
	h.gun_s = 100.0
	var aux := TankAux.of(rig.state)
	h.hp = 90.0
	var hold := h.hold_px
	TankShells.damage_enemy(rig.state, aux, h, 30.0, TankEvents.BY_SHELL, 0, rig.events)
	assert_eq(h.mode, TankIds.EM_HOLD, "30 damage: no back-off yet")
	TankShells.damage_enemy(rig.state, aux, h, 20.0, TankEvents.BY_SHELL, 0, rig.events)
	assert_eq(h.mode, TankIds.EM_BACKOFF, "50 damage taken")
	assert_almost_eq(h.hold_px - hold, 30.0, 0.01)
	rig.run(3.0)
	assert_eq(h.mode, TankIds.EM_HOLD)
	assert_almost_eq(h.x_px - (rig.hull().x_px + rig.hull().hull_w), hold + 30.0, 0.01)
	# The telegraph: 3 s before the shot.
	h.gun_s = 4.0
	rig.run(1.3)
	assert_eq(h.mode, TankIds.EM_TELEGRAPH)
	assert_almost_eq(h.telegraph_s, 2.7, 0.15)
	rig.run(3.0)
	assert_eq(h.telegraph_s, 0.0)


func test_no_enemy_moves_into_the_hull_or_off_the_cap() -> void:
	var rig := _rig(1)
	for _i in 30:
		_enter(rig, TankIds.ENEMY_LIGHT)
	assert_eq(rig.state.enemies.size(), TankConst.MAX_ENEMIES, "caps at 16 enemies")
	assert_null(_enter(rig, TankIds.ENEMY_MEDIUM))


# --- Hit rolls and where shells land ---------------------------------------------------------------


func _fire_from(rig: TankRulesRig, hit_chance: float) -> TankShellState:
	var aux := TankAux.of(rig.state)
	rig.state.shells.clear()
	TankEnemies.launch(
		rig.state,
		aux,
		Vector2(700.0, 250.0),
		TankIds.SHELL_ENEMY,
		4.0,
		hit_chance,
		false,
		1,
		1,
		rig.events
	)
	return rig.state.shells[0]


func test_hit_rolls_come_from_the_session_rng_at_fire_time() -> void:
	var a := _rig(1, ADVANCE, 11)
	var b := _rig(1, ADVANCE, 11)
	var c := _rig(1, ADVANCE, 12)
	var seq_a: Array[bool] = []
	var seq_b: Array[bool] = []
	var seq_c: Array[bool] = []
	for _i in 40:
		seq_a.append(_fire_from(a, 0.5).will_hit)
		seq_b.append(_fire_from(b, 0.5).will_hit)
		seq_c.append(_fire_from(c, 0.5).will_hit)
	assert_eq(seq_a, seq_b, "same seed, same rolls")
	assert_ne(seq_a, seq_c, "another seed rolls differently")


func test_hit_chance_zero_and_one_are_certain() -> void:
	var rig := _rig(1)
	rig.hull().evasive = false
	for _i in 30:
		assert_true(_fire_from(rig, 1.0).will_hit)
		assert_false(_fire_from(rig, 0.0).will_hit)


func test_a_missing_shell_lands_20_to_40_px_short_of_the_tank_and_a_hit_on_it() -> void:
	var rig := _rig(1)
	rig.hull().evasive = false
	rig.hull().speed_mps = 0.0
	var aux := TankAux.of(rig.state)
	var front := rig.hull().x_px + rig.hull().hull_w
	for _i in 30:
		var s := _fire_from(rig, 0.0)
		var left: float = aux.shell_left[s.id]
		var end := Vector2(s.x + s.vx * left, s.y + s.vy * left)
		assert_almost_eq(end.y, float(TankConst.GROUND_Y), 0.5)
		assert_between(end.x - front, 20.0, 40.0, "20-40 px off the near end")
		var h := _fire_from(rig, 1.0)
		var lh: float = aux.shell_left[h.id]
		var hend := Vector2(h.x + h.vx * lh, h.y + h.vy * lh)
		var origin := TankTargets.hull_origin(rig.state)
		assert_true(
			Rect2(origin, Vector2(rig.hull().hull_w, rig.hull().hull_h)).has_point(hend),
			"a hit lands on the hull"
		)


func test_a_shell_that_hits_costs_the_hull_its_damage_when_it_arrives() -> void:
	var rig := _rig(1)
	rig.hull().evasive = false
	var s := _fire_from(rig, 1.0)
	var full := rig.hull().hp
	assert_eq(rig.hull().hp, full, "nothing before the shell arrives")
	rig.run(3.0)
	assert_eq(rig.hull().hp, full - 4.0)
	var hits := rig.of_type("hit")
	assert_eq(hits.size(), 1)
	assert_eq(
		[hits[0]["on"], hits[0]["dmg"], hits[0]["sh"], hits[0]["b"]],
		[TankEvents.ON_TANK, 4, TankIds.SHELL_ENEMY, 0]
	)
	assert_eq(rig.state.shells.size(), 0)
	assert_false(s in rig.state.shells)
	var miss := _fire_from(rig, 0.0)
	rig.run(3.0)
	assert_eq(rig.hull().hp, full - 4.0, "a miss costs nothing")
	assert_false(miss in rig.state.shells)


func test_at_the_shell_cap_an_enemy_shot_resolves_at_once() -> void:
	var rig := _rig(1)
	rig.hull().evasive = false
	var full := rig.hull().hp
	var aux := TankAux.of(rig.state)
	for i in TankConst.MAX_SHELLS:
		var s := TankShellState.new()
		s.id = rig.state.take_id()
		s.friendly = false
		s.type = TankIds.SHELL_ENEMY
		s.x = 5000.0
		s.y = 200.0
		rig.state.shells.append(s)
		aux.shell_left[s.id] = 99.0
	TankEnemies.launch(
		rig.state,
		aux,
		Vector2(700.0, 250.0),
		TankIds.SHELL_ENEMY,
		4.0,
		1.0,
		false,
		1,
		1,
		rig.events
	)
	assert_eq(rig.state.shells.size(), TankConst.MAX_SHELLS, "no 25th shell")
	assert_eq(rig.hull().hp, full - 4.0, "applied at once")


# --- Raiders -------------------------------------------------------------------------------------


func test_a_light_tank_harasses_for_linger_s_and_then_breaks_off_with_no_kill() -> void:
	var rig := _rig(1)
	var linger := float(rig.content.enemy_def("light")["linger_s"])
	var e := _enter(rig, TankIds.ENEMY_LIGHT)
	rig.run(8.0)
	assert_eq(e.mode, TankIds.EM_HOLD)
	rig.run(linger - 6.0)
	assert_true(rig.state.enemies.has(e), "still on station")
	assert_ne(e.mode, TankIds.EM_LEAVE)
	rig.run(10.0)
	assert_eq(e.mode, TankIds.EM_LEAVE, "it breaks off")
	var shots := rig.of_type("shot").size()
	rig.run(15.0)
	assert_false(rig.state.enemies.has(e), "gone once off screen")
	assert_eq(rig.of_type("kill").size(), 0)
	assert_eq(rig.state.score.crew_kills, 0)
	assert_eq(rig.of_type("shot").size(), shots, "a light tank that left fires no more")


func test_a_light_tank_from_the_rear_breaks_off_to_the_left() -> void:
	var rig := _rig(1)
	var e := _enter(rig, TankIds.ENEMY_LIGHT, -1)
	rig.run(float(rig.content.enemy_def("light")["linger_s"]) + 25.0)
	assert_false(rig.state.enemies.has(e))
	assert_eq(rig.of_type("kill").size(), 0)


func test_other_enemies_never_leave() -> void:
	var rig := _rig(3)
	var m := _enter(rig, TankIds.ENEMY_MEDIUM)
	var d := _enter(rig, TankIds.ENEMY_DESTROYER)
	rig.hull().hp = 1.0e9
	rig.hull().hp_max = 1.0e9
	rig.run(120.0)
	assert_true(rig.state.enemies.has(m))
	assert_true(rig.state.enemies.has(d))
