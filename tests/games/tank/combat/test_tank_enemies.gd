extends GutTest
## The enemy tanks' guns (brief 2.4 Enemies; v4): shot cadence and damage, telegraphs, hit rolls with
## the session RNG, launch_far (flight_s and rng_m on every far shot), the near launch and where its
## shell lands, the caps. Far motion: test_tank_far.gd; near motion: test_tank_near.gd.

const ADVANCE := 1
const GUN_LINE := 2


## A quiet Advance: no encounters, no obstacles, the gun out of the picture.
static func _quiet(index: int, props: Dictionary = {"encounters": [], "obstacles": []}) -> Callable:
	return func(files: Dictionary) -> void:
		(files["mission"]["segments"][index] as Dictionary).merge(props, true)


func _rig(crew: int = 1, index: int = ADVANCE, seed_v: int = 7) -> TankRulesRig:
	var rig := TankRulesRig.new(crew, "ashfall_road", seed_v, _quiet(index))
	rig.no_fire = true
	rig.no_bow = true
	rig.enter(index, 5.0)
	return rig


func _shots_of(rig: TankRulesRig, e: TankEnemyState) -> Array:
	return rig.of_type("shot").filter(func(x: Dictionary) -> bool: return x["src"] == e.id)


func test_a_light_tank_fires_its_gun_every_every_s() -> void:
	var rig := _rig(1)
	var e := rig.far(TankIds.ENEMY_LIGHT, 900.0)
	rig.hull().hp = 1.0e9
	rig.hull().hp_max = 1.0e9
	TankAux.of(rig.state).enemy_flank_done[e.id] = true
	var every := float(rig.content.enemy_def(TankIds.ENEMY_LIGHT)["gun"]["every_s"])
	e.gun_s = every
	rig.run(40.0)
	var shots := _shots_of(rig, e)
	assert_between(shots.size(), 7, 9, "one every %.0f s" % every)
	assert_eq(shots[0]["s"], -1)
	assert_eq(shots[0]["sh"], TankIds.SHELL_ENEMY)
	assert_eq(shots[0]["e"], 1, "enemy code in the event")


func test_the_shot_cadence_and_damage_of_every_kind() -> void:
	var content := TankContent.from_dicts(TankContent.read_files("ashfall_road"), "ashfall_road")
	var table := {}
	for type in TankIds.ENEMY_TYPES:
		var gun: Dictionary = content.enemy_def(type)["gun"]
		table[type] = [float(gun["damage"]), float(gun["every_s"]), float(gun["hit"])]
	for type: String in table:
		var rig := _rig(3)
		rig.hull().hp = 100000.0
		rig.hull().hp_max = 100000.0
		var e := rig.spawn(type, 1, 60.0)
		# Telegraphed guns run their whole telegraph first (test_tank_evade.gd).
		var tele := float(rig.content.enemy_def(type).get("telegraph_s", 0.0))
		e.gun_s = 0.5 + tele
		# The light's first shot is its telegraphed flank shot (test_tank_evade.gd): its gun after.
		TankAux.of(rig.state).enemy_flank_done[e.id] = true
		var fired := func() -> bool:
			return rig.state.shells.any(func(s: TankShellState) -> bool: return not s.friendly)
		var t := rig.run_until(fired, 10.0)
		assert_almost_eq(t, 0.5 + tele, 0.06, "%s fires after its countdown" % type)
		var first: TankShellState = null
		for s in rig.state.shells:
			if not s.friendly:
				first = s
		assert_not_null(first, type)
		assert_eq(first.damage, table[type][0], "%s damage" % type)
		assert_between(table[type][2], 0.3, 0.95, "%s has a real hit chance" % type)
		assert_eq(first.source, e.id)
		assert_eq(first.far, not TankIds.NEAR_KINDS.has(type), "%s's frame" % type)
		assert_almost_eq(
			e.gun_s, table[type][1], 0.1, "%s reloads in %.1f s" % [type, table[type][1]]
		)


func test_a_destroyer_telegraphs_before_each_shot_and_moves_after() -> void:
	var rig := _rig(1)
	rig.hull().hp = 1.0e9
	rig.hull().hp_max = 1.0e9
	var e := rig.far(TankIds.ENEMY_DESTROYER, 1800.0)
	var tele := float(rig.content.enemy_def(TankIds.ENEMY_DESTROYER)["telegraph_s"])
	e.gun_s = tele + 2.0
	rig.run(2.2)
	assert_eq(e.mode, TankIds.EM_TELEGRAPH)
	assert_almost_eq(e.telegraph_s, tele - 0.2, 0.15, "the glint runs for the last seconds")
	assert_eq(rig.of_type("shot").size(), 0)
	rig.run(tele)
	assert_eq(e.telegraph_s, 0.0, "fired")
	assert_eq(rig.of_type("shot").size(), 1)
	assert_ne(e.hold_m, 1800.0, "it moves after the shot")


func test_a_destroyer_in_telegraph_is_the_autoaims_first_target() -> void:
	var rig := _rig(3)
	var aux := TankAux.of(rig.state)
	var d := rig.far(TankIds.ENEMY_DESTROYER, 1800.0)
	var h := rig.far(TankIds.ENEMY_HEAVY, 1300.0)
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
	assert_lt(TankTargets.by_id(aux, d.id).tier, TankTargets.by_id(aux, h.id).tier)


func test_a_holding_force_stands_where_the_mission_put_it_and_keeps_moving() -> void:
	var rig := TankRulesRig.new(1)
	rig.no_fire = true
	rig.enter(GUN_LINE, 1.0)
	var guns := rig.state.enemies
	var want := 0
	for n in TankEncounters.crew_counts(rig.state, rig.content.segment(GUN_LINE)["enemies"]):
		want += n
	assert_eq(guns.size(), want, "the mission's force x the crew's scale")
	assert_gt(want, 0)
	for e in guns:
		assert_false(e.fixed)
		assert_true(e.gun_line)
		assert_eq(e.mode, TankIds.EM_ENTER)
	assert_eq(rig.state.gun_line.guns_total, want)
	assert_eq(rig.state.gun_line.guns_left, want)
	assert_true(rig.state.gun_line.active)
	rig.run(12.0)
	assert_almost_eq(guns[0].range_m, guns[0].hold_m, 1.0, "at its mission hold")


# --- Far shots -----------------------------------------------------------------------------------


func _launch_far(
	rig: TankRulesRig, range_m: float, hit_chance: float, telegraphed: bool = false
) -> TankShellState:
	rig.state.shells.clear()
	TankEnemies.launch_far(
		rig.state,
		TankAux.of(rig.state),
		range_m,
		TankIds.SHELL_ENEMY,
		4.0,
		hit_chance,
		telegraphed,
		1,
		1,
		rig.events
	)
	return rig.state.shells[0]


## Far shots report where they come from and how long they fly (ruling 5: audio's whistle and far boom
## read these): theirs carry the shooter's range.
func test_every_enemy_far_shot_passes_flight_s_and_rng_m() -> void:
	var rig := _rig(1)
	rig.hull().hp = 1.0e9
	rig.hull().hp_max = 1.0e9
	for r: float in [800.0, 1500.0, 2200.0]:
		rig.events.clear()
		var s := _launch_far(rig, r, 0.5)
		var ev: Dictionary = rig.of_type("shot")[0]
		assert_eq(ev["rng_m"], roundi(r), "the shooter's range")
		assert_almost_eq(float(ev["flight_s"]), s.left_s, 0.006)
		var elev := TankBallistics.far_elevation(r, 560.0, 70.0)
		assert_almost_eq(s.left_s, TankBallistics.far_flight(elev, 560.0, 70.0), 1e-4)
		assert_true(s.far)
		assert_almost_eq(s.x, r, 1e-3, "x is the range from the hull")
		assert_lt(s.vx, 0.0, "coming at us")
		assert_gt(s.vy, 0.0, "up-positive")
		assert_false(s.friendly)
	# From each kind's own gun, in play.
	for type in TankIds.FAR_KINDS:
		var r2 := _rig(3)
		r2.hull().hp = 1.0e9
		r2.hull().hp_max = 1.0e9
		var e := r2.far(type)
		TankAux.of(r2.state).enemy_flank_done[e.id] = true
		e.gun_s = 0.05 + float(r2.content.enemy_def(type).get("telegraph_s", 0.0))
		r2.run(e.gun_s + 0.1)
		var shots := _shots_of(r2, e)
		assert_eq(shots.size(), 1, type)
		assert_almost_eq(float(shots[0]["rng_m"]), e.range_m, 15.0, "%s: its range" % type)
		assert_gt(float(shots[0]["flight_s"]), 1.0, "%s: a real flight" % type)


func test_hit_rolls_come_from_the_session_rng_at_fire_time() -> void:
	var a := _rig(1, ADVANCE, 11)
	var b := _rig(1, ADVANCE, 11)
	var c := _rig(1, ADVANCE, 12)
	var seq_a: Array[bool] = []
	var seq_b: Array[bool] = []
	var seq_c: Array[bool] = []
	for _i in 40:
		seq_a.append(_launch_far(a, 1000.0, 0.5).will_hit)
		seq_b.append(_launch_far(b, 1000.0, 0.5).will_hit)
		seq_c.append(_launch_far(c, 1000.0, 0.5).will_hit)
	assert_eq(seq_a, seq_b, "same seed, same rolls")
	assert_ne(seq_a, seq_c, "another seed rolls differently")


func test_hit_chance_zero_and_one_are_certain_and_the_driver_in_band_is_harder_to_hit() -> void:
	var rig := _rig(1)
	rig.hull().evasive = false
	for _i in 30:
		assert_true(_launch_far(rig, 1000.0, 1.0).will_hit)
		assert_false(_launch_far(rig, 1000.0, 0.0).will_hit)
	rig.hull().evasive = true
	var hits := 0
	for _i in 400:
		if _launch_far(rig, 1000.0, 1.0).will_hit:
			hits += 1
	var mult := rig.content.num("tanks", "drive.evasive_hit_mult")
	assert_almost_eq(float(hits) / 400.0, mult, 0.08, "x evasive_hit_mult")


func test_a_far_hit_lands_after_its_flight_and_costs_the_hull() -> void:
	var rig := _rig(4)
	rig.hull().evasive = false
	var full := rig.hull().hp
	var s := _launch_far(rig, 1500.0, 1.0)
	rig.run(s.left_s - 0.2)
	assert_eq(rig.hull().hp, full, "nothing before it lands")
	assert_eq(rig.of_type("hit").size(), 0)
	rig.run(0.3)
	assert_almost_eq(rig.hull().hp, full - 4.0 * rig.content.crew_damage_scale(4), 1e-6)
	var hits := rig.of_type("hit")
	assert_eq(hits.size(), 1)
	assert_eq(
		[hits[0]["on"], hits[0]["dmg"], hits[0]["sh"], hits[0]["b"]],
		[TankEvents.ON_TANK, 3, TankIds.SHELL_ENEMY, 0]
	)
	assert_eq(rig.state.shells.size(), 0)
	assert_eq(rig.of_type("splash").size(), 0)


func test_a_far_miss_raises_a_splash_40_to_90_m_off_the_hull_and_costs_nothing() -> void:
	var rig := _rig(2)
	rig.hull().evasive = false
	var full := rig.hull().hp
	for _i in 12:
		var s := _launch_far(rig, 900.0, 0.0)
		rig.run(s.left_s + 0.1)
	var sp := rig.of_type("splash")
	assert_eq(sp.size(), 12)
	for e in sp:
		assert_between(int(e["r"]), 40, 90)
		assert_eq([e["sh"], e["f"]], [TankIds.SHELL_ENEMY, 0])
	assert_eq(rig.hull().hp, full)


func test_at_the_shell_cap_a_far_shot_resolves_at_once_evade_first() -> void:
	var rig := _rig(4)
	rig.hull().evasive = false
	var full := rig.hull().hp
	var aux := TankAux.of(rig.state)
	for i in TankConst.MAX_SHELLS:
		var s := TankShellState.new()
		s.id = rig.state.take_id()
		s.far = true
		s.left_s = 99.0
		s.x = 1000.0
		rig.state.shells.append(s)
	rig.events.clear()
	TankEnemies.launch_far(
		rig.state, aux, 1500.0, TankIds.SHELL_ENEMY, 4.0, 1.0, true, 1, 1, rig.events
	)
	assert_eq(rig.state.shells.size(), TankConst.MAX_SHELLS, "no 25th shell")
	assert_almost_eq(rig.hull().hp, full - 4.0 * rig.content.crew_damage_scale(4), 1e-6, "at once")
	var kinds: Array = rig.events.map(func(e: Dictionary) -> String: return e["type"])
	assert_eq(kinds, ["shot", "evade", "hit"], "the evade before the hit")


# --- Near shots ----------------------------------------------------------------------------------


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


func test_a_near_hit_chance_zero_and_one_are_certain() -> void:
	var rig := _rig(1)
	rig.hull().evasive = false
	for _i in 30:
		assert_true(_fire_from(rig, 1.0).will_hit)
		assert_false(_fire_from(rig, 0.0).will_hit)


func test_a_missing_near_shell_lands_20_to_40_px_short_of_the_tank_and_a_hit_on_it() -> void:
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


func test_a_near_shell_that_hits_costs_the_hull_its_damage_when_it_arrives() -> void:
	var rig := _rig(4)
	rig.hull().evasive = false
	var s := _fire_from(rig, 1.0)
	var full := rig.hull().hp
	assert_eq(rig.hull().hp, full, "nothing before the shell arrives")
	rig.run(3.0)
	var lost := 4.0 * rig.content.crew_damage_scale(4)
	assert_almost_eq(rig.hull().hp, full - lost, 1e-6)
	assert_eq(rig.of_type("hit").size(), 1)
	assert_eq(rig.state.shells.size(), 0)
	assert_false(s in rig.state.shells)
	var miss := _fire_from(rig, 0.0)
	rig.run(3.0)
	assert_almost_eq(rig.hull().hp, full - lost, 1e-6, "a miss costs nothing")
	assert_false(miss in rig.state.shells)


func test_at_the_shell_cap_a_near_shot_resolves_at_once() -> void:
	var rig := _rig(4)
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
	assert_almost_eq(rig.hull().hp, full - 4.0 * rig.content.crew_damage_scale(4), 1e-6, "at once")


## v3 solo balance (enemies.json crew_damage_scale [0.5, 1, 1, 1]): an enemy shell costs a solo
## rider's hull half its damage; crews 2-4 take it in full. Enemy HP is the same for every crew.
func test_a_solo_hull_takes_the_crew_damage_scale_of_an_enemy_shell() -> void:
	for crew in [1, 2, 4]:
		var rig := _rig(crew)
		rig.hull().evasive = false
		var full := rig.hull().hp
		var lost := TankHullRules.hit(rig.state, 4.0, TankIds.SHELL_ENEMY, 0.0, rig.events)
		var want := 4.0 * rig.content.crew_damage_scale(crew)
		assert_almost_eq(lost, want, 1e-6, "crew %d" % crew)
		assert_almost_eq(rig.hull().hp, full - want, 1e-6)
	assert_eq(TankFixtures.content().crew_damage_scale(1), 0.62)
	assert_eq(TankFixtures.content().crew_damage_scale(2), 0.57)
	assert_eq(TankFixtures.content().crew_damage_scale(3), 0.74)
	assert_eq(TankFixtures.content().crew_damage_scale(4), 0.74)
