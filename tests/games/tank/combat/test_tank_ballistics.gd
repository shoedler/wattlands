extends GutTest
## Shell flight and the aim solver (brief 2.4 Gun): the analytic arc, the lower-arc solver within
## 0.5 degrees with lead, the range rule for every tank, dispersion by bank.

const V0 := 360.0
const G := 300.0


func test_a_shell_flies_the_analytic_arc() -> void:
	var vel := TankBallistics.velocity(V0, 30.0, TankIds.FACE_RIGHT)
	assert_almost_eq(vel.x, V0 * cos(deg_to_rad(30.0)), 1e-3)
	assert_almost_eq(
		vel.y, -V0 * sin(deg_to_rad(30.0)), 1e-3, "y grows downward: rising is negative"
	)
	var m := Vector2(200.0, 196.0)
	var p := TankBallistics.position(m, vel, G, 1.0)
	assert_almost_eq(p.x, 200.0 + vel.x, 1e-3)
	assert_almost_eq(p.y, 196.0 + vel.y + 150.0, 1e-3, "gravity 300 px/s^2 pulls down")
	var left := TankBallistics.velocity(V0, 10.0, TankIds.FACE_LEFT)
	assert_lt(left.x, 0.0, "facing left shoots left")


func test_the_per_tick_stepping_reproduces_the_analytic_arc() -> void:
	var rig := TankRulesRig.new(1)
	rig.enter(4)
	rig.state.enemies.clear()
	var vel := TankBallistics.velocity(V0, 12.0, TankIds.FACE_RIGHT)
	var s := TankShellState.new()
	s.id = rig.state.take_id()
	s.type = TankIds.SHELL_HEAVY
	s.x = 100.0
	s.y = 150.0
	s.vx = vel.x
	s.vy = vel.y
	rig.state.shells.append(s)
	var aux := TankAux.of(rig.state)
	var events: Array[Dictionary] = []
	for i in 20:
		TankShells.step(rig.state, aux, Wl.SIM_DT, events)
		var want := TankBallistics.position(Vector2(100.0, 150.0), vel, G, (i + 1) * Wl.SIM_DT)
		assert_almost_eq(s.x, want.x, 1e-3, "x at tick %d" % i)
		assert_almost_eq(s.y, want.y, 1e-3, "y at tick %d" % i)


func test_solver_hits_points_at_several_ranges_and_heights() -> void:
	for dx: float in [150.0, 250.0, 350.0, 450.0]:
		for rise: float in [-80.0, -20.0, 0.0, 40.0]:
			var e := TankBallistics.solve_elevation(dx, rise, V0, G)
			if is_nan(e):
				continue
			var h := TankBallistics.height_at(dx, V0, e, G)
			assert_almost_eq(h, rise, 0.01, "dx %.0f rise %.0f at %.2f deg" % [dx, rise, e])


func test_solver_picks_the_lower_arc_and_reports_out_of_range() -> void:
	var e := TankBallistics.solve_elevation(300.0, 0.0, V0, G)
	assert_lt(e, 45.0, "the lower of the two arcs")
	assert_true(is_nan(TankBallistics.solve_elevation(900.0, 0.0, V0, G)), "beyond the range")
	assert_true(is_nan(TankBallistics.solve_elevation(-10.0, 0.0, V0, G)), "behind the muzzle")
	assert_true(is_nan(TankBallistics.solve_elevation(10.0, 0.0, 0.0, G)))


func test_the_lead_solver_meets_a_moving_target_within_half_a_degree() -> void:
	var dx := 320.0
	var rise := -40.0
	for vel: float in [-40.0, -20.0, 0.0, 25.0, 60.0]:
		var e := TankBallistics.solve_lead(dx, rise, vel, 0.0, V0, G)
		assert_false(is_nan(e), "vel %.0f" % vel)
		var vx := V0 * cos(deg_to_rad(e))
		# The shell and the target meet where their horizontal positions agree.
		var t := dx / (vx - vel)
		var h := V0 * sin(deg_to_rad(e)) * t - 0.5 * G * t * t
		assert_almost_eq(h, rise, 2.0, "vel %.0f: the shell is at the target's height" % vel)
		var exact := TankBallistics.solve_elevation(dx + vel * t, rise, V0, G)
		assert_lte(absf(e - exact), 0.5, "vel %.0f: within 0.5 degrees of the true intercept" % vel)


func test_lead_differs_from_the_unled_solution_for_a_moving_target() -> void:
	var still := TankBallistics.solve_lead(320.0, -40.0, 0.0, 0.0, V0, G)
	var away := TankBallistics.solve_lead(320.0, -40.0, 50.0, 0.0, V0, G)
	var toward := TankBallistics.solve_lead(320.0, -40.0, -50.0, 0.0, V0, G)
	assert_gt(away, still, "a receding target needs more elevation")
	assert_lt(toward, still, "an approaching one needs less")


func test_the_aim_aux_solution_puts_a_real_shell_in_the_box() -> void:
	for crew in [1, 2, 3]:
		var rig := TankRulesRig.new(crew)
		rig.enter(4)
		var aux := TankAux.of(rig.state)
		var e := TankEncounters.add_obstacle(
			rig.state, TankIds.OBST_WIRE, rig.hull().x_px + rig.hull().hull_w + 130.0
		)
		TankTargets.build(rig.state, aux)
		var t := TankTargets.by_id(aux, e.id)
		var aim: Array[Vector2] = [Vector2.ZERO]
		var elev := TankAim.solve_target(rig.state, aux, t, TankIds.FACE_RIGHT, aim)
		assert_false(is_nan(elev), "crew %d" % crew)
		var m := TankAim.muzzle_world(rig.state, aux, elev, TankIds.FACE_RIGHT)
		var vel := TankBallistics.velocity(V0, elev, TankIds.FACE_RIGHT)
		var best := INF
		for i in 400:
			var p := TankBallistics.position(m, vel, G, i * 0.01)
			if t.rect.has_point(p):
				best = 0.0
				break
		assert_eq(best, 0.0, "crew %d: the analytic arc enters the box" % crew)


func test_range_rule_30_degree_range_is_at_least_1_1_x_muzzle_to_edge() -> void:
	var geo := TankGeometry.load_default()
	var c := TankContent.from_dicts(TankContent.read_files("ashfall_road"), "ashfall_road")
	var v0 := c.num("tanks", "gun.shell_speed_px_s")
	var g := c.num("tanks", "gun.gravity_px_s2")
	for tank in TankIds.TANKS:
		var hull_h := float(c.tank_def(tank)["hull_px"][1])
		var top := float(TankConst.GROUND_Y - TankTargets.SKIRT_GAP) - hull_h
		var m30 := (
			Vector2(float(TankConst.REAR_SCREEN_X), top)
			+ geo.muzzle(tank, 30.0, TankIds.FACE_RIGHT)
		)
		var edge := float(TankConst.SCREEN_W) - m30.x
		var drop := float(TankConst.GROUND_Y) - m30.y
		var reach := TankBallistics.range_px(v0, 30.0, g, drop)
		assert_gte(reach, 1.1 * edge, "%s: range %.0f vs 1.1 x %.0f" % [tank, reach, edge])


func test_dispersion_is_half_a_degree_and_widens_below_a_bank_of_20() -> void:
	var c := TankContent.from_dicts(TankContent.read_files("ashfall_road"), "ashfall_road")
	assert_eq(TankBallistics.dispersion_deg(c, 100.0), 0.5)
	assert_eq(TankBallistics.dispersion_deg(c, 20.0), 0.5)
	assert_eq(TankBallistics.dispersion_deg(c, 19.9), 1.5)
	assert_eq(TankBallistics.dispersion_deg(c, 0.0), 1.5)


# --- v4: the far frame -----------------------------------------------------------------------------

const FAR_V0 := 560.0
const FAR_G := 70.0


## SPEC_TANK section 2's table: range, elevation, flight, metres per degree.
func test_the_far_frames_table() -> void:
	var rows := [[800.0, 5.1, 1.43, 153.0], [1500.0, 9.8, 2.72, 147.0], [2200.0, 14.7, 4.06, 136.0]]
	for row: Array in rows:
		var e := TankBallistics.far_elevation(float(row[0]), FAR_V0, FAR_G)
		assert_almost_eq(e, float(row[1]), 0.05, "%.0f m" % row[0])
		assert_almost_eq(TankBallistics.far_flight(e, FAR_V0, FAR_G), float(row[2]), 0.01)
		var per_deg := (
			TankBallistics.far_range(e + 0.5, FAR_V0, FAR_G)
			- TankBallistics.far_range(e - 0.5, FAR_V0, FAR_G)
		)
		assert_almost_eq(per_deg, float(row[3]), 2.0, "m per degree at %.0f m" % row[0])


func test_far_range_inverts_far_elevation() -> void:
	for r: float in [700.0, 800.0, 1234.0, 1900.0, 2500.0, 4000.0]:
		var e := TankBallistics.far_elevation(r, FAR_V0, FAR_G)
		assert_almost_eq(TankBallistics.far_range(e, FAR_V0, FAR_G), r, 1e-3, "%.0f m" % r)
	assert_true(is_nan(TankBallistics.far_elevation(5000.0, FAR_V0, FAR_G)), "out of range")
	assert_true(is_nan(TankBallistics.far_elevation(0.0, FAR_V0, FAR_G)))


func test_far_lead_lands_on_a_moving_target() -> void:
	for rate: float in [-30.0, -10.0, 0.0, 8.0, 20.0, 37.7]:
		for r: float in [900.0, 1500.0, 2200.0]:
			var e := TankBallistics.far_lead(r, rate, FAR_V0, FAR_G)
			var t := TankBallistics.far_flight(e, FAR_V0, FAR_G)
			var land := TankBallistics.far_range(e, FAR_V0, FAR_G)
			assert_almost_eq(land, r + rate * t, 0.5, "%.0f m at %.0f m/s" % [r, rate])


func test_the_per_tick_far_flight_lands_where_the_arc_says() -> void:
	var rig := TankRulesRig.new(1)
	rig.enter(3)
	var aux := TankAux.of(rig.state)
	var e := TankBallistics.far_elevation(1500.0, FAR_V0, FAR_G)
	var s := TankShellState.new()
	s.id = rig.state.take_id()
	s.type = TankIds.SHELL_HEAVY
	s.far = true
	s.friendly = true
	s.impact_r = 1500.0
	s.left_s = TankBallistics.far_flight(e, FAR_V0, FAR_G)
	s.vx = FAR_V0 * cos(deg_to_rad(e))
	s.vy = FAR_V0 * sin(deg_to_rad(e))
	var flight := s.left_s
	rig.state.shells.append(s)
	var events: Array[Dictionary] = []
	var peak := 0.0
	for i in 20:
		TankShells.step(rig.state, aux, Wl.SIM_DT, events)
		var t := (i + 1) * Wl.SIM_DT
		assert_almost_eq(
			s.y, TankBallistics.far_height(t, e, FAR_V0, FAR_G), 1e-2, "y at tick %d" % i
		)
		assert_almost_eq(s.x, s.vx * t, 1e-2)
		peak = maxf(peak, s.y)
	assert_gt(peak, 0.0, "it rises")
	TankShells.step(rig.state, aux, flight, events)
	assert_eq(rig.state.shells.size(), 0, "it lands when left_s runs out")


## The evade floor (v3's ADR, BRIEF 4.6's spirit): telegraph + the shortest flight is at least 6 s at
## Hard, for every telegraphing kind, at the nearest it can hold (a shift never goes nearer).
func test_hard_telegraph_plus_flight_is_at_least_6_s() -> void:
	var c := TankFixtures.content()
	var hard := float(c.value("enemies", "difficulty.hard", {})["telegraph"])
	var rows := {
		TankIds.ENEMY_HEAVY: [float(c.enemy_def(TankIds.ENEMY_HEAVY)["telegraph_s"]), 1300.0],
		TankIds.ENEMY_DESTROYER:
		[float(c.enemy_def(TankIds.ENEMY_DESTROYER)["telegraph_s"]), 1700.0],
		TankIds.ENEMY_LIGHT:
		[float(c.enemy_def(TankIds.ENEMY_LIGHT)["flank"]["telegraph_s"]), 800.0 - 60.0],
	}
	for kind: String in rows:
		var row: Array = rows[kind]
		var def := c.enemy_def(kind)
		var nearest := float(def["hold_m"][0]) - float(def.get("weave_m", 0.0))
		assert_eq(nearest, float(row[1]), kind)
		var e := TankBallistics.far_elevation(nearest, FAR_V0, FAR_G)
		var total := float(row[0]) * hard + TankBallistics.far_flight(e, FAR_V0, FAR_G)
		assert_gte(total, 6.0, "%s: %.2f s" % [kind, total])
	var boss := c.boss_def()
	var stop := float(boss["far"]["stop_m"])
	var be := TankBallistics.far_elevation(stop, FAR_V0, FAR_G)
	var bt := (
		float(boss["main"]["telegraph_s"]) * hard + TankBallistics.far_flight(be, FAR_V0, FAR_G)
	)
	assert_gte(bt, 6.0, "the Behemoth at its stop line: %.2f s" % bt)
