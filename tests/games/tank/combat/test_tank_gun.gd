extends GutTest
## The main turret (brief 2.4 Gun; v4): auto-aim priority and lead, the far lay and its tolerance,
## far hits by metres, near arcs to a barricade and a drill wreck, manual controls, dispersion,
## chambering from the rack, the dark gun's reach, the shell cap (the bow guns: test_tank_bow.gd;
## chambering in detail: test_tank_stations.gd).

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


func test_the_auto_aim_priority_is_telegraph_heavy_medium_light_obstacle() -> void:
	var rig := _rig(3)
	var aux := TankAux.of(rig.state)
	var d := rig.far(TankIds.ENEMY_DESTROYER, 1800.0)
	var heavy := rig.far(TankIds.ENEMY_HEAVY, 1500.0)
	var med := rig.far(TankIds.ENEMY_MEDIUM, 1200.0)
	var light := rig.far(TankIds.ENEMY_LIGHT, 900.0)
	var wire := TankEncounters.add_obstacle(
		rig.state, TankIds.OBST_WIRE, rig.hull().x_px + rig.hull().hull_w + 130.0
	)
	d.mode = TankIds.EM_TELEGRAPH
	d.telegraph_s = 2.0
	var order: Array[int] = []
	for i in 5:
		var t := _aim(rig)
		assert_not_null(t, "step %d" % i)
		order.append(t.id)
		match t.kind:
			TankTarget.KIND_ENEMY:
				rig.state.enemies.erase(t.enemy)
			TankTarget.KIND_OBSTACLE:
				rig.state.obstacles.erase(t.obstacle)
	assert_eq(order, [d.id, heavy.id, med.id, light.id, wire.id])
	assert_null(_aim(rig), "nothing left")
	assert_eq(aux.aim_target, null)


func test_nearer_first_inside_a_tier() -> void:
	var rig := _rig(2)
	var far := rig.far(TankIds.ENEMY_MEDIUM, 1500.0)
	var near := rig.far(TankIds.ENEMY_MEDIUM, 1150.0)
	assert_eq(_aim(rig).id, near.id)
	rig.state.enemies.erase(near)
	assert_eq(_aim(rig).id, far.id)


func test_a_target_the_gun_cannot_reach_is_skipped() -> void:
	# With the gun held to +6 degrees a medium at 1200 m (7.8 degrees) cannot be reached; a light at
	# 800 m (5.1 degrees) can.
	var patch := func(files: Dictionary) -> void:
		_quiet(CHECKPOINT).call(files)
		files["tanks"]["gun"]["elev_max_deg"] = 6
	var rig := TankRulesRig.new(2, "ashfall_road", 7, patch)
	rig.enter(CHECKPOINT, 5.0)
	rig.dynamo().bank = 100.0
	var med := rig.far(TankIds.ENEMY_MEDIUM, 1200.0)
	var light := rig.far(TankIds.ENEMY_LIGHT, 800.0)
	assert_eq(_aim(rig).id, light.id, "the medium outranks it but is out of reach")
	rig.state.enemies.erase(light)
	assert_null(_aim(rig))
	assert_true(rig.state.enemies.has(med))


func test_the_lay_leads_a_moving_target() -> void:
	var rig := _rig(2)
	var aux := TankAux.of(rig.state)
	var e := rig.far(TankIds.ENEMY_MEDIUM, 1300.0)
	var aim: Array[Vector2] = [Vector2.ZERO]
	TankTargets.build(rig.state, aux)
	var still := TankAim.solve_target(rig.state, aux, TankTargets.by_id(aux, e.id), 1, aim)
	assert_almost_eq(still, TankBallistics.far_elevation(1300.0, 560.0, 70.0), 1e-4)
	e.rate_mps = 8.0
	TankTargets.build(rig.state, aux)
	var away := TankAim.solve_target(rig.state, aux, TankTargets.by_id(aux, e.id), 1, aim)
	assert_almost_eq(away, TankBallistics.far_lead(1300.0, 8.0, 560.0, 70.0), 1e-4)
	assert_gt(away, still, "receding: more elevation")
	e.rate_mps = -8.0
	TankTargets.build(rig.state, aux)
	assert_lt(TankAim.solve_target(rig.state, aux, TankTargets.by_id(aux, e.id), 1, aim), still)


func test_every_holding_force_is_reachable_from_every_crew() -> void:
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
						"crew %d segment %d: %s at %.0f m"
						% [crew, index, TankIds.enemy_of(g.code), g.range_m]
					)
				)


func test_the_gun_lays_within_a_tenth_of_a_degree_and_hits_after_the_flight() -> void:
	var rig := _rig(4)
	assert_true(rig.arc().lit, "lit: +-0.2 degrees keeps a medium inside its 35 m window")
	var med := rig.far(TankIds.ENEMY_MEDIUM, 1300.0)
	med.gun_s = 1.0e6
	med.hp = 40.0
	rig.load_shell(TankIds.SHELL_HEAVY)
	var aux := TankAux.of(rig.state)
	var t := rig.run_until(func() -> bool: return _gun_shots(rig).size() > 0, 10.0)
	assert_lt(t, 5.0, "fired")
	var shot: Dictionary = _gun_shots(rig)[0]
	assert_eq([shot["s"], shot["sh"]], [_g(rig) - 1, TankIds.SHELL_HEAVY])
	assert_eq(rig.hull().loaded, TankIds.SHELL_NONE)
	var chamber := rig.content.num("tanks", "steam.chamber_s")
	assert_almost_eq(rig.steam().chamber_s, chamber, 0.06, "v3: the next round from the rack")
	assert_lte(absf(rig.hull().elev_deg - aux.aim_elev), 0.1 + 1e-6, "within gun.far.aim_tol_deg")
	var s := rig.state.shells[0]
	assert_true(s.friendly)
	assert_true(s.far)
	assert_eq(s.damage, 35.0)
	assert_eq(s.source, _g(rig) - 1)
	assert_eq(s.target_id, med.id)
	assert_almost_eq(s.impact_r, 1300.0, 35.0, "it lands around the target")
	assert_almost_eq(s.x, s.vx * Wl.SIM_DT, 0.01, "from the hull, one tick flown")
	assert_gt(s.vy, 0.0, "y is up in the far frame")
	assert_eq(med.hp, 40.0, "nothing before it lands")
	rig.run(s.left_s + 0.1)
	assert_almost_eq(med.hp, 5.0, 0.001, "35 at landing")
	var hits := rig.of_type("hit")
	assert_eq(hits.size(), 1)
	assert_eq(hits[0]["x"], roundi(med.range_m), "x: the range in metres")
	assert_eq(rig.of_type("splash").size(), 0)
	assert_eq(rig.state.score.shots, 1)
	assert_eq(rig.state.score.hits, 1)
	assert_eq(rig.rider(_g(rig)).shots, 1)
	assert_eq(rig.rider(_g(rig)).hits, 1)
	assert_eq(rig.rider(_g(rig)).shells_by_type[1], 1, "heavy")


## Ruling 5: every far shot passes flight_s and rng_m. Ours: where it lands.
func test_our_far_shot_passes_flight_s_and_where_it_lands() -> void:
	var rig := _rig(4)
	var med := rig.far(TankIds.ENEMY_MEDIUM, 1600.0)
	med.gun_s = 1.0e6
	rig.load_shell(TankIds.SHELL_LIGHT)
	rig.run_until(func() -> bool: return _gun_shots(rig).size() > 0, 10.0)
	var ev: Dictionary = _gun_shots(rig)[0]
	var s := rig.state.shells[0]
	assert_eq(ev["rng_m"], roundi(s.impact_r), "where it lands, not where the target is")
	assert_almost_eq(float(ev["flight_s"]), s.left_s + Wl.SIM_DT, 0.006)
	assert_between(float(ev["flight_s"]), 2.5, 3.5, "1600 m takes about 3 s")


func test_a_far_shell_that_misses_raises_splash_where_it_landed() -> void:
	var rig := _rig(4)
	var med := rig.far(TankIds.ENEMY_MEDIUM, 1300.0)
	med.gun_s = 1.0e6
	var hp := med.hp
	rig.load_shell(TankIds.SHELL_HEAVY)
	rig.hull().elev_deg = 15.0
	rig.hull().elev_target_deg = 15.0
	rig.hull().aim_pause_s = 99.0
	rig.send(_g(rig), {"k": "fire"})
	rig.run(5.0)
	var sp := rig.of_type("splash")
	assert_eq(sp.size(), 1)
	assert_eq(sp[0]["f"], 1, "ours")
	assert_gt(int(sp[0]["r"]), 2000, "15 degrees lands far past it")
	assert_eq(med.hp, hp)
	assert_eq(rig.state.score.hits, 0)
	assert_eq(rig.state.score.shots, 1)


func test_the_aimed_target_takes_the_hit_when_two_stand_in_the_window() -> void:
	var rig := _rig(4)
	var aux := TankAux.of(rig.state)
	var a := rig.far(TankIds.ENEMY_MEDIUM, 1300.0)
	var b := rig.far(TankIds.ENEMY_MEDIUM, 1320.0)
	for e: TankEnemyState in [a, b]:
		e.hp = 500.0
		e.gun_s = 1.0e6
	TankTargets.build(rig.state, aux)
	var s := TankShellState.new()
	s.id = rig.state.take_id()
	s.type = TankIds.SHELL_HEAVY
	s.far = true
	s.friendly = true
	s.left_s = 0.01
	s.impact_r = 1302.0
	s.target_id = b.id
	rig.state.shells.append(s)
	TankShells.step(rig.state, aux, Wl.SIM_DT, rig.events)
	assert_almost_eq(b.hp, 465.0, 0.001, "the aimed one, direct")
	assert_almost_eq(a.hp, 482.5, 0.001, "the other: splash")
	s = TankShellState.new()
	s.id = rig.state.take_id()
	s.type = TankIds.SHELL_HEAVY
	s.far = true
	s.friendly = true
	s.left_s = 0.01
	s.impact_r = 1301.0
	rig.state.shells.append(s)
	TankShells.step(rig.state, aux, Wl.SIM_DT, rig.events)
	assert_almost_eq(a.hp, 447.5, 0.001, "no aim: the nearest takes it")


## Near arcs stay: a barricade and a drill wreck in the near panel are inside the -12 degree arc's
## reach, the shell is a near one.
func test_the_gun_lays_a_near_arc_on_a_barricade_at_the_standoff_and_clears_it() -> void:
	var rig := _rig(2)
	var stand := rig.content.num("tanks", "props.standoff_px")
	assert_eq(stand, 130.0)
	var wire := TankEncounters.add_obstacle(
		rig.state, TankIds.OBST_WIRE, rig.hull().x_px + rig.hull().hull_w + stand
	)
	rig.load_shell(TankIds.SHELL_HEAVY)
	var t := rig.run_until(func() -> bool: return _gun_shots(rig).size() > 0, 10.0)
	assert_lt(t, 5.0, "fired")
	var shot: Dictionary = _gun_shots(rig)[0]
	assert_eq(shot["rng_m"], 0, "a near shell")
	assert_false(shot.has("flight_s"))
	assert_false(rig.state.shells[0].far)
	rig.run(3.0)
	assert_true(wire.cleared, "a heavy shell clears it")


func test_the_aim_drills_wrecks_are_solvable() -> void:
	var rig := _rig(2)
	var aux := TankAux.of(rig.state)
	var px: Array = rig.content.value("tanks", "drill.wreck_px", [])
	assert_eq(px, [135.0, 170.0] if px[0] is float else [135, 170])
	for d: Variant in px:
		rig.state.obstacles.clear()
		var o := TankEncounters.add_obstacle(
			rig.state, TankIds.OBST_DRILL_WRECK, rig.hull().x_px + rig.hull().hull_w + float(d)
		)
		TankTargets.build(rig.state, aux)
		var aim: Array[Vector2] = [Vector2.ZERO]
		var e := TankAim.solve_target(rig.state, aux, TankTargets.by_id(aux, o.id), 1, aim)
		assert_false(is_nan(e), "a wreck %.0f px off the bow" % float(d))


func test_a_near_shell_inherits_the_hulls_velocity() -> void:
	var rig := _rig(2, ADVANCE)
	rig.run(40.0)
	var speed := rig.hull().speed_mps
	assert_gt(speed, 5.0)
	rig.state.enemies.clear()
	rig.load_shell(TankIds.SHELL_HEAVY)
	rig.hull().elev_target_deg = 0.5
	rig.hull().elev_deg = 0.5
	rig.hull().aim_pause_s = 99.0
	rig.send(_g(rig), {"k": "fire"})
	rig.run(0.05)
	var s := rig.state.shells[0]
	assert_false(s.far, "under a degree with no target: a near shell")
	var hull_px := TankConst.m_to_px(rig.hull().speed_mps)
	var angle := rad_to_deg(atan2(-s.vy + 300.0 * Wl.SIM_DT, s.vx - hull_px))
	assert_almost_eq(angle, 0.5, 0.51, "the muzzle velocity, plus the tank's own")
	assert_almost_eq(s.vx - hull_px, V0 * cos(deg_to_rad(0.5)), 2.0)


func test_an_afk_gunner_in_rescue_does_not_stall_the_gun_which_runs_on_reserve() -> void:
	# Brief 2.2: an AFK station runs on reserve, so a rescue left over from before the rider
	# stopped pedaling must not freeze the dynamo for the whole absence (RN-1).
	var rig := _rig(2)
	rig.far(TankIds.ENEMY_MEDIUM)
	rig.load_shell(TankIds.SHELL_HEAVY)
	rig.rescue[_g(rig)] = true
	rig.afk[_g(rig)] = true
	rig.run(20.0)
	assert_false(rig.dynamo().stalled, "a rider on reserve is not in rescue")
	assert_gt(_gun_shots(rig).size(), 0, "the gun keeps firing on reserve")


func test_a_present_gunner_in_rescue_still_stalls_the_gun() -> void:
	var rig := _rig(2)
	rig.far(TankIds.ENEMY_MEDIUM)
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
	var m := rig.far(TankIds.ENEMY_MEDIUM)
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
	var m := rig.far(TankIds.ENEMY_MEDIUM)
	m.gun_s = 999.0
	rig.load_shell(TankIds.SHELL_HEAVY)
	rig.run(4.0)
	assert_eq(_gun_shots(rig).size(), 0, "paused: no auto fire")
	assert_almost_eq(rig.hull().elev_deg, -1.0, 0.05)
	rig.run(1.5)
	rig.run(3.0)
	assert_eq(_gun_shots(rig).size(), 1, "auto-aim resumed")


func test_a_nudge_on_a_far_target_moves_a_quarter_degree() -> void:
	var rig := _rig(2)
	rig.set_rack(0)
	var m := rig.far(TankIds.ENEMY_MEDIUM)
	m.gun_s = 999.0
	rig.run(1.5)
	assert_eq(rig.hull().target_id, m.id)
	var at := rig.hull().elev_deg
	rig.send(_g(rig), {"k": "aim", "d": 1})
	rig.run(0.05)
	assert_almost_eq(rig.hull().elev_target_deg, at + 0.25, 1e-3, "gun.far.nudge_deg")


func test_the_target_buttons_cycle_the_target_and_the_choice_stays_until_it_falls() -> void:
	var rig := _rig(2)
	var left := rig.far(TankIds.ENEMY_MEDIUM, 1200.0)
	var right := rig.far(TankIds.ENEMY_MEDIUM, 1500.0)
	rig.near(TankIds.ENEMY_RECON, 60.0)
	rig.run(0.2)
	var first := rig.hull().target_id
	assert_eq(first, left.id, "auto-aim: nearer first")
	rig.send(_g(rig), {"k": "target", "d": 1})
	rig.run(0.1)
	assert_eq(rig.hull().target_id, right.id, "cycled to the next one farther, past the recon car")
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
	var s := rig.state.shells[0]
	assert_eq(s.damage, 14.0)
	assert_true(s.far, "no target and the barrel raised: a far shell")
	assert_gt(s.vy, 50.0, "rising at 12 degrees, up-positive")


## Far: gun.far.dispersion_deg lit, x arc.dark_dispersion_mult dark; the wider one below a bank of 20.
func test_the_far_dispersion_by_bank_and_lights() -> void:
	for row: Array in [
		[100.0, true, 0.2], [10.0, true, 0.6], [100.0, false, 0.4], [10.0, false, 1.2]
	]:
		var rig := _rig(4)
		rig.hull().elev_deg = 10.0
		var widest := 0.0
		for _i in 300:
			rig.dynamo().bank = float(row[0])
			rig.arc().lit = bool(row[1])
			rig.load_shell(TankIds.SHELL_HEAVY)
			rig.state.shells.clear()
			TankGun.fire(rig.state, TankAux.of(rig.state), rig.dynamo(), false, rig.events)
			var s := rig.state.shells[0]
			assert_true(s.far)
			widest = maxf(widest, absf(rad_to_deg(atan2(s.vy, s.vx)) - 10.0))
		assert_lte(widest, float(row[2]) + 0.01, "bank %.0f lit %s" % [row[0], row[1]])
		assert_gt(widest, float(row[2]) * 0.8, "and it uses the range")


## A near arc. Lit (crew 4's Lights rider in band); dark it doubles (test_tank_bow.gd).
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


func test_the_turret_never_traverses() -> void:
	var rig := _rig(2)
	var m := rig.far(TankIds.ENEMY_MEDIUM)
	m.gun_s = 999.0
	rig.send(_g(rig), {"k": "traverse"})
	rig.run(1.0)
	assert_eq(rig.hull().traverse_s, 0.0, "a traverse intent is junk")
	assert_eq(rig.hull().facing, TankIds.FACE_RIGHT)
	assert_almost_eq(rig.hull().aim_pause_s, 0.0, 0.01, "and leaves the aim running")


func test_target_ids_are_the_entity_id_or_the_negative_boss_part() -> void:
	var rig := _rig(2)
	var m := rig.spawn(TankIds.ENEMY_MEDIUM, 1, 250.0)
	rig.run(0.2)
	assert_eq(rig.hull().target_id, m.id)
	assert_gt(m.id, 0)


## Dark (no Lights rider in band) the gun sees far targets to arc.dark_range_m; lit to gun.far.max_range_m.
func test_the_dark_gun_reaches_only_the_dark_range() -> void:
	var rig := _rig(2)
	assert_eq(rig.content.num("tanks", "arc.dark_range_m"), 2300.0)
	assert_false(TankGun.searchlights_lit(rig.state))
	var far := rig.far(TankIds.ENEMY_HEAVY, 2400.0)
	far.gun_s = 999.0
	assert_null(_aim(rig), "2400 m: in the dark")
	far.range_m = 2250.0
	assert_eq(_aim(rig).id, far.id, "2250 m: seen")
	var lit := _rig(4)
	var f2 := lit.far(TankIds.ENEMY_HEAVY, 2400.0)
	f2.gun_s = 999.0
	assert_true(TankGun.searchlights_lit(lit.state))
	assert_eq(_aim(lit).id, f2.id, "lit: the full range")
	f2.range_m = 2550.0
	assert_null(_aim(lit), "past gun.far.max_range_m even lit")


func test_near_arcs_are_always_within_reach_in_the_dark() -> void:
	var rig := _rig(2)
	assert_false(TankGun.searchlights_lit(rig.state))
	var wire := TankEncounters.add_obstacle(
		rig.state, TankIds.OBST_WIRE, rig.hull().x_px + rig.hull().hull_w + 130.0
	)
	assert_eq(_aim(rig).id, wire.id)


## Only the Secondaries hit a near threat: the main gun never lays on one, by hand either.
func test_the_main_gun_never_lays_on_a_near_threat() -> void:
	var rig := _rig(4)
	var aux := TankAux.of(rig.state)
	var e := rig.near(TankIds.ENEMY_RECON, 60.0)
	e.gun_s = 999.0
	assert_null(_aim(rig), "a recon car alone")
	var t := TankTargets.by_id(aux, e.id)
	assert_not_null(t, "it is a target (the view and the bow guns' list see it)")
	if t != null:
		assert_true(t.near)
	rig.state.hull.target_id = e.id
	aux.manual_target = true
	assert_null(_aim(rig), "not by hand")
	assert_false(aux.manual_target, "the manual choice falls")
	rig.send(_g(rig), {"k": "target", "d": 1})
	rig.run(0.1)
	assert_ne(rig.hull().target_id, e.id, "and cycling skips it")
