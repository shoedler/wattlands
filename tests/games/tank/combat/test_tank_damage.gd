extends GutTest
## The damage table (brief 2.4 Gun): shell damage, armour classes, splash, and HP and counts scaled
## by the tank.

const ADVANCE := 1


func _rig(crew: int = 3) -> TankRulesRig:
	var rig := TankRulesRig.new(crew)
	rig.no_fire = true
	rig.enter(ADVANCE, 5.0)
	return rig


## Fires a friendly shell of `type` straight into the middle of `e` from its left side.
func _hit(rig: TankRulesRig, e: TankEnemyState, type: int) -> void:
	var aux := TankAux.of(rig.state)
	TankTargets.build(rig.state, aux)
	var t := TankTargets.by_id(aux, e.id)
	var c := t.rect.get_center()
	var s := TankShellState.new()
	s.id = rig.state.take_id()
	s.type = type
	s.x = t.rect.position.x - 6.0
	s.y = c.y
	s.vx = 360.0
	s.vy = 0.0
	s.friendly = true
	s.source = 0
	rig.state.shells.append(s)
	TankShells.step(rig.state, aux, Wl.SIM_DT, rig.events)


func test_the_shell_damage_table() -> void:
	var c := TankContent.from_dicts(TankContent.read_files("ashfall_road"), "ashfall_road")
	assert_eq(TankDamage.shell_damage(c, TankIds.SHELL_LIGHT), 20.0)
	assert_eq(TankDamage.shell_damage(c, TankIds.SHELL_HEAVY), 50.0)
	assert_eq(TankDamage.shell_damage(c, TankIds.SHELL_OVER), 100.0)
	assert_eq(TankDamage.shell_damage(c, TankIds.SHELL_SECONDARY), 5.0)
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
		TankIds.ENEMY_DUGIN: 1.0,
	}
	for type: String in armour:
		assert_eq(TankDamage.enemy_mult(c, type, TankIds.SHELL_LIGHT), armour[type], type)
		assert_eq(TankDamage.enemy_mult(c, type, TankIds.SHELL_SECONDARY), armour[type], type)
		assert_eq(TankDamage.enemy_mult(c, type, TankIds.SHELL_HEAVY), 1.0, type)
		assert_eq(TankDamage.enemy_mult(c, type, TankIds.SHELL_OVER), 1.0, type)
	assert_eq(TankDamage.boss_mult(c, TankIds.SHELL_LIGHT), 0.25, "the Behemoth takes a quarter")
	assert_eq(TankDamage.boss_mult(c, TankIds.SHELL_SECONDARY), 0.25)
	assert_eq(TankDamage.boss_mult(c, TankIds.SHELL_HEAVY), 1.0)


func test_a_shell_hit_applies_the_table_to_a_real_enemy() -> void:
	var rows := [
		[TankIds.ENEMY_MEDIUM, TankIds.SHELL_LIGHT, 10.0],
		[TankIds.ENEMY_MEDIUM, TankIds.SHELL_HEAVY, 50.0],
		[TankIds.ENEMY_HEAVY, TankIds.SHELL_LIGHT, 5.0],
		[TankIds.ENEMY_HEAVY, TankIds.SHELL_OVER, 100.0],
		[TankIds.ENEMY_DESTROYER, TankIds.SHELL_LIGHT, 5.0],
		[TankIds.ENEMY_LIGHT, TankIds.SHELL_LIGHT, 20.0],
		[TankIds.ENEMY_DUGIN, TankIds.SHELL_LIGHT, 20.0],
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


func test_enemy_hp_and_counts_scale_with_the_tank() -> void:
	var c := TankContent.from_dicts(TankContent.read_files("ashfall_road"), "ashfall_road")
	# The scales are content (tanks.json): the brief's 0.6 / 0.8 / 1.0, each within +-50%.
	var scale := {}
	for tank: String in [TankIds.TANK_BULWARK, TankIds.TANK_RAMPART, TankIds.TANK_CITADEL]:
		scale[tank] = c.enemy_scale(tank)
	assert_between(scale[TankIds.TANK_BULWARK], 0.3, 0.9, "Bulwark: 0.6 +-50%")
	assert_between(scale[TankIds.TANK_RAMPART], 0.4, 1.2, "Rampart: 0.8 +-50%")
	assert_between(scale[TankIds.TANK_CITADEL], 0.5, 1.5, "Citadel: 1.0 +-50%")
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


func test_splash_is_half_damage_within_16_px_of_the_impact() -> void:
	var rig := _rig(3)
	var near := rig.spawn(TankIds.ENEMY_MEDIUM, 1, 250.0)
	var other := rig.spawn(TankIds.ENEMY_LIGHT, 1, 250.0)
	# Two enemies overlap (the view draws them on two depth rows): the first one in the list takes
	# the direct hit, the other stands inside the splash radius.
	other.x_px = near.x_px
	other.hp = 100.0
	var hp := other.hp
	_hit(rig, near, TankIds.SHELL_HEAVY)
	# Heavy 50 x 50% = 25 on a light tank (armour does not apply to heavy shells).
	assert_almost_eq(hp - other.hp, 25.0, 0.001)
	var far := _rig(3)
	var a := far.spawn(TankIds.ENEMY_MEDIUM, 1, 250.0)
	var b := far.spawn(TankIds.ENEMY_LIGHT, 1, 250.0)
	b.x_px = a.x_px + a.w + 40.0
	var b_hp := b.hp
	_hit(far, a, TankIds.SHELL_HEAVY)
	assert_eq(b.hp, b_hp, "40 px away: no splash")


func test_splash_follows_the_armour_of_the_victim_and_hurts_on_a_ground_impact_too() -> void:
	var rig := _rig(3)
	var aux := TankAux.of(rig.state)
	var m := rig.spawn(TankIds.ENEMY_MEDIUM, 1, 250.0)
	var hp := m.hp
	# A light shell comes down on the ground 10 px in front of the medium tank's box.
	TankTargets.build(rig.state, aux)
	var s := TankShellState.new()
	s.id = rig.state.take_id()
	s.type = TankIds.SHELL_LIGHT
	s.x = m.x_px - 10.0
	s.y = float(TankConst.GROUND_Y) - 8.0
	s.vx = 0.0
	s.vy = 200.0
	s.friendly = true
	rig.state.shells.append(s)
	TankShells.step(rig.state, aux, Wl.SIM_DT, rig.events)
	assert_eq(rig.state.shells.size(), 0, "landed")
	# Light 20 x 50% splash x 50% armour = 5.
	assert_almost_eq(hp - m.hp, 5.0, 0.001)


func test_a_kill_is_credited_to_the_shooter_and_removes_the_enemy() -> void:
	var rig := _rig(3)
	var e := rig.spawn(TankIds.ENEMY_LIGHT, 1, 250.0)
	e.hp = 10.0
	var aux := TankAux.of(rig.state)
	TankTargets.build(rig.state, aux)
	var t := TankTargets.by_id(aux, e.id)
	var s := TankShellState.new()
	s.id = rig.state.take_id()
	s.type = TankIds.SHELL_LIGHT
	s.x = t.rect.position.x - 6.0
	s.y = t.rect.get_center().y
	s.vx = 360.0
	s.friendly = true
	s.source = 1
	rig.state.shells.append(s)
	TankShells.step(rig.state, aux, Wl.SIM_DT, rig.events)
	assert_false(rig.state.enemies.has(e))
	var kill := rig.of_type("kill")[0]
	assert_eq([kill["id"], kill["e"], kill["by"], kill["s"]], [e.id, 1, TankEvents.BY_SHELL, 1])
	assert_eq(rig.state.score.kills[1], 1)
	assert_eq(rig.state.score.crew_kills, 1)
