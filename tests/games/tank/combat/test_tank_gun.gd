extends GutTest
## The main turret (brief 2.4 Gun; v3): auto-aim priority and lead, the 0.5 degree rule, manual
## controls, dispersion, chambering from the rack, the dark gun's reach, the shell cap (the bow
## guns: test_tank_bow.gd; chambering in detail: test_tank_stations.gd).

const ADVANCE := 1
const CHECKPOINT := 3
const V0 := 360.0


static func _quiet(index: int) -> Callable:
	return func(files: Dictionary) -> void:
		(files["mission"]["segments"][index] as Dictionary).merge(
			{"encounters": [], "obstacles": []}, true
		)


## A rig in a checkpoint: the tank stands still, nothing else is going on, only the gun is under
## test.
func _rig(crew: int = 2, index: int = CHECKPOINT) -> TankRulesRig:
	var rig := TankRulesRig.new(crew, "ashfall_road", 7, _quiet(index))
	rig.enter(index, 5.0)
	if rig.dynamo() != null:
		rig.dynamo().bank = 100.0
	return rig


## The gunner's peer: whoever works the dynamo (the checkpoint already carries the next stage's
## engines, so it is not always peer 2).
func _g(rig: TankRulesRig) -> int:
	return rig.peer_of(TankIds.ENGINE_DYNAMO)


func _gun_shots(rig: TankRulesRig) -> Array:
	return rig.of_type("shot").filter(
		func(e: Dictionary) -> bool: return e["s"] >= 0 and e["sh"] != TankIds.SHELL_BOW
	)


func _aim(rig: TankRulesRig) -> TankTarget:
	var aux := TankAux.of(rig.state)
	aux.aim_valid = false
	TankTargets.build(rig.state, aux)
	return TankAim.current(rig.state, aux)


func test_the_auto_aim_priority_is_telegraph_dugin_heavy_medium_light_obstacle() -> void:
	var rig := _rig(3)
	var aux := TankAux.of(rig.state)
	var d := rig.spawn(TankIds.ENEMY_DESTROYER, 1, 216.0)
	var dug := rig.spawn(TankIds.ENEMY_DUGIN, 1, 232.0)
	var heavy := rig.spawn(TankIds.ENEMY_HEAVY, 1, 192.0)
	var med := rig.spawn(TankIds.ENEMY_MEDIUM, 1, 224.0)
	var light := rig.spawn(TankIds.ENEMY_LIGHT, 1, 130.0)
	var wire := TankEncounters.add_obstacle(
		rig.state, TankIds.OBST_WIRE, rig.hull().x_px + rig.hull().hull_w + 260.0
	)
	d.mode = TankIds.EM_TELEGRAPH
	d.telegraph_s = 2.0
	var order: Array[int] = []
	for i in 6:
		var t := _aim(rig)
		assert_not_null(t, "step %d" % i)
		order.append(t.id)
		match t.kind:
			TankTarget.KIND_ENEMY:
				rig.state.enemies.erase(t.enemy)
			TankTarget.KIND_OBSTACLE:
				rig.state.obstacles.erase(t.obstacle)
	assert_eq(order, [d.id, dug.id, heavy.id, med.id, light.id, wire.id])
	assert_null(_aim(rig), "nothing left")
	assert_eq(aux.aim_target, null)


func test_nearer_first_inside_a_tier() -> void:
	var rig := _rig(2)
	# Inside the screen clamp of a medium's hold on the v3 hull (about 210 px).
	var far := rig.spawn(TankIds.ENEMY_MEDIUM, 1, 200.0)
	var near := rig.spawn(TankIds.ENEMY_MEDIUM, 1, 150.0)
	assert_eq(_aim(rig).id, near.id)
	rig.state.enemies.erase(near)
	assert_eq(_aim(rig).id, far.id)


func test_a_target_the_gun_cannot_reach_is_skipped() -> void:
	# With the gun held to -2 degrees a light tank right against the bow cannot be reached; a medium
	# can. (v3: the r6 gun sits lower on the hull and reaches it at -12 degrees.)
	var patch := func(files: Dictionary) -> void:
		_quiet(CHECKPOINT).call(files)
		files["tanks"]["gun"]["elev_min_deg"] = -2
	var rig := TankRulesRig.new(2, "ashfall_road", 7, patch)
	rig.enter(CHECKPOINT, 5.0)
	rig.dynamo().bank = 100.0
	var close := rig.spawn(TankIds.ENEMY_LIGHT, 1, 10.0)
	var med := rig.spawn(TankIds.ENEMY_MEDIUM, 1, 280.0)
	var t := _aim(rig)
	assert_eq(t.id, med.id)
	rig.state.enemies.erase(med)
	assert_null(_aim(rig), "the close light tank is out of reach")
	assert_true(rig.state.enemies.has(close))
	# Beyond the 30 degree range: unreachable too.
	rig.state.enemies.clear()
	var far := rig.spawn(TankIds.ENEMY_MEDIUM, 1, 270.0)
	far.x_px += 700.0
	assert_null(_aim(rig))


## Brief 2.4 Gun and section 4: at -12 degrees the solver hits a light tank anywhere on its hold
## distance (enemies.json hold_px, plus its weave), from every tank.
func test_the_solver_hits_a_light_tank_at_its_hold_distance_from_every_tank() -> void:
	for crew in [1, 2, 3, 4]:
		var rig := _rig(crew)
		var aux := TankAux.of(rig.state)
		var def := rig.content.enemy_def(TankIds.ENEMY_LIGHT)
		var span: Array = def["hold_px"]
		var weave := float(def["weave_px"])
		assert_eq(rig.content.num("tanks", "gun.elev_min_deg"), -12.0)
		for d: float in [
			float(span[0]) - weave, float(span[0]), float(span[1]), float(span[1]) + weave
		]:
			rig.state.enemies.clear()
			var e := rig.spawn(TankIds.ENEMY_LIGHT, 1, d)
			TankTargets.build(rig.state, aux)
			var out: Array[Vector2] = [Vector2.ZERO]
			var el := TankAim.solve_target(rig.state, aux, TankTargets.by_id(aux, e.id), 1, out)
			assert_false(is_nan(el), "crew %d: a light tank %.0f px off the bow" % [crew, d])
			assert_between(el, -12.0, 30.0)


func test_every_gun_line_enemy_is_reachable_from_every_tank() -> void:
	for crew in [1, 2, 3, 4]:
		var rig := TankRulesRig.new(crew)
		for index in [2, 5, 8]:
			rig.enter(index, 1.0)
			rig.hull().speed_mps = 0.0
			var aux := TankAux.of(rig.state)
			var guns: Array[TankEnemyState] = rig.state.enemies.duplicate()
			rig.run(15.0)
			for g in guns:
				var list: Array[TankEnemyState] = [g]
				rig.state.enemies.assign(list)
				aux.aim_valid = false
				TankTargets.build(rig.state, aux)
				var t := TankAim.current(rig.state, aux)
				assert_not_null(
					t,
					(
						"crew %d segment %d: %s at %.0f px"
						% [crew, index, TankIds.enemy_of(g.code), g.hold_px]
					)
				)


func test_the_gun_aims_and_fires_within_half_a_degree_and_hits() -> void:
	var rig := _rig(2)
	var med := rig.spawn(TankIds.ENEMY_MEDIUM, 1, 250.0)
	med.hp = 30.0
	rig.load_shell(TankIds.SHELL_HEAVY)
	var aux := TankAux.of(rig.state)
	var t := rig.run_until(func() -> bool: return _gun_shots(rig).size() > 0, 10.0)
	assert_lt(t, 5.0, "fired")
	var shot: Dictionary = _gun_shots(rig)[0]
	assert_eq([shot["s"], shot["sh"]], [_g(rig) - 1, TankIds.SHELL_HEAVY])
	assert_eq(rig.hull().loaded, TankIds.SHELL_NONE)
	var chamber := rig.content.num("tanks", "steam.chamber_s")
	assert_eq(chamber, 1.0, "v3: the next round chambers in 1 s")
	assert_almost_eq(rig.steam().chamber_s, chamber, 0.06, "from the rack")
	assert_eq(rig.hull().breech_s, 0.0, "no breech cycle in v3")
	assert_lte(
		absf(rig.hull().elev_deg - aux.aim_elev), 0.5 + 1e-6, "within 0.5 degrees of the solution"
	)
	var s := rig.state.shells[0]
	assert_true(s.friendly)
	assert_eq(s.damage, 35.0)
	assert_eq(s.source, _g(rig) - 1)
	var muzzle := TankAim.muzzle_world(rig.state, aux, rig.hull().elev_deg, rig.hull().facing)
	# The shell already flew the tick it was fired in.
	var g := 300.0
	assert_almost_eq(s.x - s.vx * Wl.SIM_DT, muzzle.x, 0.01, "from the muzzle anchor")
	assert_almost_eq(
		s.y - (s.vy - g * Wl.SIM_DT) * Wl.SIM_DT - 0.5 * g * Wl.SIM_DT * Wl.SIM_DT, muzzle.y, 0.01
	)
	rig.run(3.0)
	assert_lt(med.hp, med.hp_max, "the shell hit")
	assert_eq(rig.state.score.shots, 1)
	assert_eq(rig.state.score.hits, 1)
	assert_eq(rig.rider(_g(rig)).shots, 1)
	assert_eq(rig.rider(_g(rig)).hits, 1)
	assert_eq(rig.rider(_g(rig)).shells_by_type[1], 1, "heavy")


func test_a_shell_inherits_the_hulls_velocity() -> void:
	var rig := _rig(2, ADVANCE)
	rig.run(40.0)
	var speed := rig.hull().speed_mps
	assert_gt(speed, 5.0)
	rig.state.enemies.clear()
	rig.load_shell(TankIds.SHELL_HEAVY)
	rig.hull().elev_target_deg = 5.0
	rig.hull().elev_deg = 5.0
	rig.hull().aim_pause_s = 99.0
	rig.send(_g(rig), {"k": "fire"})
	rig.run(0.05)
	var s := rig.state.shells[0]
	var hull_px := TankConst.m_to_px(rig.hull().speed_mps)
	var angle := rad_to_deg(atan2(-s.vy + 300.0 * Wl.SIM_DT, s.vx - hull_px))
	assert_almost_eq(angle, 5.0, 0.51, "the muzzle velocity at 5 degrees, plus the tank's own")
	assert_almost_eq(s.vx - hull_px, V0 * cos(deg_to_rad(5.0)), 2.0)


func test_an_afk_gunner_in_rescue_does_not_stall_the_gun_which_runs_on_reserve() -> void:
	# Brief 2.2: an AFK station runs on reserve, so a rescue left over from before the rider
	# stopped pedaling must not freeze the dynamo for the whole absence (RN-1).
	var rig := _rig(2)
	rig.spawn(TankIds.ENEMY_MEDIUM, 1, 250.0)
	rig.load_shell(TankIds.SHELL_HEAVY)
	rig.rescue[_g(rig)] = true
	rig.afk[_g(rig)] = true
	rig.run(20.0)
	assert_false(rig.dynamo().stalled, "a rider on reserve is not in rescue")
	assert_gt(_gun_shots(rig).size(), 0, "the gun keeps firing on reserve")


func test_a_present_gunner_in_rescue_still_stalls_the_gun() -> void:
	var rig := _rig(2)
	rig.spawn(TankIds.ENEMY_MEDIUM, 1, 250.0)
	rig.load_shell(TankIds.SHELL_HEAVY)
	rig.rescue[_g(rig)] = true
	rig.run(20.0)
	assert_true(rig.dynamo().stalled)
	assert_eq(_gun_shots(rig).size(), 0)


func test_a_loaded_gun_fires_nothing_with_no_target() -> void:
	var rig := _rig(2)
	rig.load_shell(TankIds.SHELL_HEAVY)
	rig.run(5.0)
	assert_eq(rig.hull().loaded, TankIds.SHELL_HEAVY)
	assert_eq(rig.of_type("shot").size(), 0)


func test_no_second_shot_inside_the_breech_cycle() -> void:
	var rig := _rig(2)
	var m := rig.spawn(TankIds.ENEMY_MEDIUM, 1, 250.0)
	m.hp = 9999.0
	m.gun_s = 999.0
	rig.load_shell(TankIds.SHELL_HEAVY)
	rig.run_until(func() -> bool: return _gun_shots(rig).size() > 0, 10.0)
	rig.load_shell(TankIds.SHELL_HEAVY)
	rig.hull().breech_s = 6.0
	rig.run(5.5)
	assert_eq(_gun_shots(rig).size(), 1)
	rig.run(1.0)
	assert_eq(_gun_shots(rig).size(), 2)


func test_the_elevation_limits_are_minus_12_and_plus_30() -> void:
	var rig := _rig(2)
	rig.set_rack(0)
	rig.power_w[_g(rig)] = 50.0
	rig.hull().elev_target_deg = 80.0
	rig.run(6.0)
	assert_eq(rig.hull().elev_deg, 30.0)
	rig.hull().elev_target_deg = -80.0
	rig.run(12.0)
	assert_eq(rig.hull().elev_deg, -12.0)


func test_aim_nudges_move_one_degree_and_pause_auto_aim_for_5_seconds() -> void:
	var rig := _rig(2)
	rig.set_rack(0)
	rig.send(_g(rig), {"k": "aim", "d": 1})
	rig.run(0.05)
	assert_eq(rig.hull().elev_target_deg, 1.0)
	assert_almost_eq(rig.hull().aim_pause_s, 5.0, 0.1)
	rig.send(_g(rig), {"k": "aim", "d": -1})
	rig.run(0.05)
	rig.send(_g(rig), {"k": "aim", "d": -1})
	rig.run(0.05)
	assert_eq(rig.hull().elev_target_deg, -1.0)
	# While paused the auto-aim leaves the barrel alone, then it takes over again.
	var m := rig.spawn(TankIds.ENEMY_MEDIUM, 1, 250.0)
	m.gun_s = 999.0
	rig.load_shell(TankIds.SHELL_HEAVY)
	rig.run(4.0)
	assert_eq(_gun_shots(rig).size(), 0, "paused: no auto fire")
	assert_almost_eq(rig.hull().elev_deg, -1.0, 0.05)
	rig.run(1.5)
	rig.run(3.0)
	assert_eq(_gun_shots(rig).size(), 1, "auto-aim resumed")


func test_the_target_buttons_cycle_the_target_and_the_choice_stays_until_it_falls() -> void:
	var rig := _rig(2)
	var left := rig.spawn(TankIds.ENEMY_MEDIUM, 1, 250.0)
	var right := rig.spawn(TankIds.ENEMY_MEDIUM, 1, 275.0)
	rig.run(0.2)
	var first := rig.hull().target_id
	assert_eq(first, left.id, "auto-aim: nearer first")
	rig.send(_g(rig), {"k": "target", "d": 1})
	rig.run(0.1)
	assert_eq(rig.hull().target_id, right.id, "cycled to the next one to the right")
	rig.run(1.0)
	assert_eq(rig.hull().target_id, right.id, "the choice stays")
	rig.send(_g(rig), {"k": "target", "d": -1})
	rig.run(0.1)
	assert_eq(rig.hull().target_id, left.id)
	rig.send(_g(rig), {"k": "target", "d": 1})
	rig.run(0.1)
	rig.state.enemies.erase(right)
	rig.run(0.2)
	assert_eq(rig.hull().target_id, left.id, "back to auto-aim once it fell")


func test_fire_shoots_the_loaded_shell_at_the_current_elevation() -> void:
	var rig := _rig(2)
	rig.hull().elev_deg = 12.0
	rig.hull().elev_target_deg = 12.0
	rig.hull().aim_pause_s = 99.0
	rig.send(_g(rig), {"k": "fire"})
	rig.run(0.1)
	assert_eq(_gun_shots(rig).size(), 0, "nothing loaded")
	rig.load_shell(TankIds.SHELL_LIGHT)
	rig.send(_g(rig), {"k": "fire"})
	rig.run(0.05)
	assert_eq(_gun_shots(rig).size(), 1)
	assert_eq(_gun_shots(rig)[0]["sh"], TankIds.SHELL_LIGHT)
	assert_eq(rig.state.shells[0].damage, 14.0)
	assert_lt(rig.state.shells[0].vy, -50.0, "rising at 12 degrees")


## Lit (crew 4's Lights rider in band); dark it doubles (test_tank_bow.gd).
func test_the_dispersion_is_half_a_degree_and_widens_to_one_and_a_half_below_a_bank_of_20() -> void:
	for row: Array in [[100.0, 0.5], [10.0, 1.5]]:
		var rig := _rig(4)
		assert_true(rig.arc().lit)
		rig.hull().elev_deg = 0.0
		var widest := 0.0
		for _i in 300:
			rig.dynamo().bank = float(row[0])
			rig.load_shell(TankIds.SHELL_HEAVY)
			rig.state.shells.clear()
			TankGun.fire(rig.state, TankAux.of(rig.state), rig.dynamo(), false, rig.events)
			var s := rig.state.shells[0]
			widest = maxf(widest, absf(rad_to_deg(atan2(-s.vy, s.vx))))
		assert_lte(widest, float(row[1]) + 0.01, "bank %.0f" % row[0])
		assert_gt(widest, float(row[1]) * 0.8, "and it uses the range")


func test_the_gun_stops_at_24_shells_in_flight() -> void:
	var rig := _rig(2)
	for _i in 30:
		rig.load_shell(TankIds.SHELL_LIGHT)
		TankGun.fire(rig.state, TankAux.of(rig.state), rig.dynamo(), false, rig.events)
	assert_eq(rig.state.shells.size(), TankConst.MAX_SHELLS)
	assert_eq(rig.hull().loaded, TankIds.SHELL_LIGHT, "the 25th stays in the breech")


func test_a_shell_that_lands_on_the_ground_is_gone_at_y_296() -> void:
	var rig := _rig(2)
	rig.load_shell(TankIds.SHELL_HEAVY)
	rig.hull().elev_deg = -5.0
	rig.hull().elev_target_deg = -5.0
	rig.hull().aim_pause_s = 99.0
	rig.send(_g(rig), {"k": "fire"})
	rig.run(0.05)
	assert_eq(rig.state.shells.size(), 1)
	rig.run(2.0)
	assert_eq(rig.state.shells.size(), 0)


func test_a_traverse_turns_the_gun_to_a_target_on_the_other_side_before_it_fires() -> void:
	var rig := _rig(2)
	rig.hull().facing = TankIds.FACE_LEFT
	var m := rig.spawn(TankIds.ENEMY_MEDIUM, 1, 250.0)
	m.gun_s = 999.0
	rig.load_shell(TankIds.SHELL_HEAVY)
	rig.set_rack(0)
	rig.run(0.1)
	assert_gt(rig.hull().traverse_s, 2.0, "traversing")
	assert_eq(_gun_shots(rig).size(), 0)
	rig.run(3.0)
	assert_eq(rig.hull().facing, TankIds.FACE_RIGHT)
	rig.run(3.0)
	assert_eq(_gun_shots(rig).size(), 1)


func test_target_ids_are_the_entity_id_or_the_negative_boss_part() -> void:
	var rig := _rig(2)
	var m := rig.spawn(TankIds.ENEMY_MEDIUM, 1, 250.0)
	rig.run(0.2)
	assert_eq(rig.hull().target_id, m.id)
	assert_gt(m.id, 0)


func test_an_autopilot_traverse_does_not_pause_the_auto_aim() -> void:
	var rig := _rig(2)
	var m := rig.spawn(TankIds.ENEMY_MEDIUM, 1, 250.0)
	m.gun_s = 999.0
	rig.send(_g(rig), {"k": "traverse", "auto": 1})
	rig.run(0.1)
	assert_gt(rig.hull().traverse_s, 0.0, "the Autopilot's traverse still turns the turret")
	assert_almost_eq(rig.hull().aim_pause_s, 0.0, 0.01, "and leaves the aim running")


func test_a_traverse_by_hand_pauses_the_auto_aim_so_it_is_not_undone() -> void:
	var rig := _rig(2)
	var m := rig.spawn(TankIds.ENEMY_MEDIUM, 1, 250.0)
	m.gun_s = 999.0
	rig.send(_g(rig), {"k": "traverse"})
	rig.run(0.1)
	assert_almost_eq(rig.hull().aim_pause_s, 5.0, 0.2)
	rig.load_shell(TankIds.SHELL_HEAVY)
	rig.run(3.0)
	assert_eq(rig.hull().facing, TankIds.FACE_LEFT, "turned to the rear and left there")
	assert_eq(_gun_shots(rig).size(), 0)


## v3: dark (no Lights rider in band) the gun sees only the headlight's range, 260 rules px off the
## hull's front; lit it reaches as far as the solver does.
func test_the_dark_gun_reaches_only_the_headlights_range() -> void:
	var rig := _rig(2)
	var reach := rig.content.num("tanks", "arc.dark_range_px")
	assert_eq(reach, 260.0)
	# The screen clamps every held enemy ahead inside about 255 px of the hull's front, so the test
	# puts one past the headlight by hand (the Behemoth's far parts stand there in play).
	var far := rig.spawn(TankIds.ENEMY_LIGHT, 1, 200.0)
	far.gun_s = 999.0
	far.x_px = rig.hull().x_px + rig.hull().hull_w + 290.0
	assert_false(TankGun.searchlights_lit(rig.state))
	assert_null(_aim(rig), "290 px: in the dark")
	far.x_px = rig.hull().x_px + rig.hull().hull_w + 250.0
	assert_eq(_aim(rig).id, far.id, "250 px: in the headlight")
	var lit := _rig(4)
	var f2 := lit.spawn(TankIds.ENEMY_LIGHT, 1, 200.0)
	f2.gun_s = 999.0
	f2.x_px = lit.hull().x_px + lit.hull().hull_w + 290.0
	assert_true(TankGun.searchlights_lit(lit.state))
	assert_eq(_aim(lit).id, f2.id, "lit: the full range")


## A light tank behind the hull is never the main gun's target (v2's rule kept): its flank shot's
## sprint prompt always comes.
func test_the_main_gun_never_lays_on_a_rear_light() -> void:
	var rig := _rig(4)
	var e := rig.spawn(TankIds.ENEMY_LIGHT, -1, 130.0)
	e.gun_s = 999.0
	assert_null(_aim(rig), "a rear light")
	var t := TankTargets.by_id(TankAux.of(rig.state), e.id)
	assert_not_null(t, "it is a target (the view and the bow guns' list see it)")
	if t != null:
		assert_true(TankAim.rear_light(t))
