extends GutTest
## The damage table (brief 2.4 Gun): shell damage, armour classes, splash, and HP and counts scaled
## by the tank.

const ADVANCE := 2


func _rig(crew: int = 3) -> TankRulesRig:
	var rig := TankRulesRig.new(crew)
	rig.no_fire = true
	rig.enter(ADVANCE, 5.0)
	return rig


## Lands a friendly far shell of `type` at range `r` this tick.
func _land(rig: TankRulesRig, r: float, type: int, source: int = 0) -> void:
	var aux := TankAux.of(rig.state)
	TankTargets.build(rig.state, aux)
	var s := TankShellState.new()
	s.id = rig.state.take_id()
	s.type = type
	s.far = true
	s.left_s = Wl.SIM_DT
	s.impact_r = r
	s.friendly = true
	s.source = source
	rig.state.shells.append(s)
	TankShells.step(rig.state, aux, Wl.SIM_DT, rig.events)


func _hit(rig: TankRulesRig, e: TankEnemyState, type: int) -> void:
	_land(rig, e.range_m, type)


func test_the_shell_damage_table() -> void:
	var c := TankContent.from_dicts(TankContent.read_files("ashfall_road"), "ashfall_road")
	# v3: v2's 20 / 50 / 100 x 0.7 (the rack's shells come about 2.3x faster).
	assert_eq(TankDamage.shell_damage(c, TankIds.SHELL_LIGHT), 14.0)
	assert_eq(TankDamage.shell_damage(c, TankIds.SHELL_HEAVY), 35.0)
	assert_eq(TankDamage.shell_damage(c, TankIds.SHELL_OVER), 70.0)
	assert_eq(TankDamage.shell_damage(c, TankIds.SHELL_BOW), 0.375, "a machine-gun round")
	assert_eq(
		TankDamage.shell_damage(c, TankIds.SHELL_ENEMY), 0.0, "enemy rounds have their gun's damage"
	)


func test_light_shells_and_secondaries_are_armoured_heavy_and_overpressure_are_not() -> void:
	var c := TankContent.from_dicts(TankContent.read_files("ashfall_road"), "ashfall_road")
	var armour := {
		TankIds.ENEMY_LIGHT: 1.0,
		TankIds.ENEMY_MEDIUM: 0.5,
		TankIds.ENEMY_DESTROYER: 0.25,
		TankIds.ENEMY_HEAVY: 0.25,
		TankIds.ENEMY_RECON: 1.0,
		TankIds.ENEMY_TANKETTE: 1.0,
	}
	for type: String in armour:
		assert_eq(TankDamage.enemy_mult(c, type, TankIds.SHELL_LIGHT), armour[type], type)
		assert_eq(TankDamage.enemy_mult(c, type, TankIds.SHELL_BOW), armour[type], type)
		assert_eq(TankDamage.enemy_mult(c, type, TankIds.SHELL_HEAVY), 1.0, type)
		assert_eq(TankDamage.enemy_mult(c, type, TankIds.SHELL_OVER), 1.0, type)
	assert_eq(TankDamage.boss_mult(c, TankIds.SHELL_LIGHT), 0.25, "the Behemoth takes a quarter")
	assert_eq(TankDamage.boss_mult(c, TankIds.SHELL_BOW), 0.25)
	assert_eq(TankDamage.boss_mult(c, TankIds.SHELL_HEAVY), 1.0)


func test_a_shell_hit_applies_the_table_to_a_real_enemy() -> void:
	var rows := [
		[TankIds.ENEMY_MEDIUM, TankIds.SHELL_LIGHT, 7.0],
		[TankIds.ENEMY_MEDIUM, TankIds.SHELL_HEAVY, 35.0],
		[TankIds.ENEMY_HEAVY, TankIds.SHELL_LIGHT, 3.5],
		[TankIds.ENEMY_HEAVY, TankIds.SHELL_OVER, 70.0],
		[TankIds.ENEMY_DESTROYER, TankIds.SHELL_LIGHT, 3.5],
		[TankIds.ENEMY_LIGHT, TankIds.SHELL_LIGHT, 14.0],
	]
	for row: Array in rows:
		var rig := _rig(3)
		var e := rig.spawn(str(row[0]), 1, 250.0)
		var hp := e.hp
		_hit(rig, e, int(row[1]))
		assert_almost_eq(hp - e.hp, float(row[2]), 0.001, "%s takes %d" % [row[0], row[1]])
		var hits := rig.of_type("hit")
		assert_eq(hits.size(), 1)
		assert_eq(
			[hits[0]["on"], hits[0]["id"], hits[0]["sh"]], [TankEvents.ON_ENEMY, e.id, row[1]]
		)
		assert_eq(hits[0]["dmg"], roundi(float(row[2])))
		assert_eq(hits[0]["x"], roundi(e.range_m), "a far hit's x is the range in metres")


func test_enemy_hp_and_counts_scale_with_the_tank() -> void:
	var c := TankContent.from_dicts(TankContent.read_files("ashfall_road"), "ashfall_road")
	# v3: one tank, and enemy HP is the same for every crew size (tanks.json enemy_scale 1.0; the
	# rules builder scales the counts by crew size).
	var scale := {TankIds.TANK_LANDSHIP: c.enemy_scale(TankIds.TANK_LANDSHIP)}
	assert_eq(scale[TankIds.TANK_LANDSHIP], 1.0, "v3: the same HP for every crew")
	for tank: String in scale:
		assert_eq(c.scaled_count(1, tank), 1, "at least one")
		assert_eq(c.scaled_count(3, tank), maxi(1, roundi(3.0 * scale[tank])))
		assert_eq(c.scaled_count(4, tank), maxi(1, roundi(4.0 * scale[tank])))
	for crew in [1, 2, 3]:
		var rig := _rig(crew)
		var tank := TankIds.tank_for_crew(crew)
		for type in TankIds.ENEMY_TYPES:
			var e := rig.spawn(type, 1, 250.0)
			assert_almost_eq(
				e.hp,
				float(c.enemy_def(type)["hp"]) * float(scale[tank]),
				0.001,
				"%s %s" % [tank, type]
			)
			assert_eq(e.hp, e.hp_max)


func test_splash_is_half_damage_within_60_m_of_the_impact() -> void:
	var rig := _rig(3)
	var hit := rig.far(TankIds.ENEMY_MEDIUM, 1200.0)
	var other := rig.far(TankIds.ENEMY_LIGHT, 1100.0)
	other.range_m = 1250.0
	other.hold_m = 1250.0
	other.hp = 100.0
	var hp := other.hp
	_hit(rig, hit, TankIds.SHELL_HEAVY)
	# Heavy 35 x 50% = 17.5 on a light tank (armour does not apply to heavy shells).
	assert_almost_eq(hp - other.hp, 17.5, 0.001)
	var far := _rig(3)
	var a := far.far(TankIds.ENEMY_MEDIUM, 1200.0)
	var b := far.far(TankIds.ENEMY_LIGHT, 1100.0)
	b.range_m = 1270.0
	var b_hp := b.hp
	_hit(far, a, TankIds.SHELL_HEAVY)
	assert_eq(b.hp, b_hp, "70 m away: no splash")


func test_splash_follows_the_armour_of_the_victim_and_hurts_on_a_miss_too() -> void:
	var rig := _rig(3)
	var m := rig.far(TankIds.ENEMY_MEDIUM, 1200.0)
	var hp := m.hp
	# A light shell lands 50 m past the medium's 35 m hit window's centre: no direct hit.
	_land(rig, 1250.0, TankIds.SHELL_LIGHT)
	assert_eq(rig.state.shells.size(), 0, "landed")
	assert_eq(rig.of_type("hit").size(), 0)
	assert_eq(rig.of_type("splash").size(), 1, "it hit nothing directly")
	# Light 14 x 50% splash x 50% armour = 3.5.
	assert_almost_eq(hp - m.hp, 3.5, 0.001)


func test_a_kill_is_credited_to_the_shooter_and_removes_the_enemy() -> void:
	var rig := _rig(3)
	var e := rig.spawn(TankIds.ENEMY_LIGHT, 1, 250.0)
	e.hp = 10.0
	_land(rig, e.range_m, TankIds.SHELL_LIGHT, 1)
	assert_false(rig.state.enemies.has(e))
	var kill := rig.of_type("kill")[0]
	assert_eq([kill["id"], kill["e"], kill["by"], kill["s"]], [e.id, 1, TankEvents.BY_SHELL, 1])
	assert_eq(rig.state.score.kills[1], 1)
	assert_eq(rig.state.score.crew_kills, 1)
