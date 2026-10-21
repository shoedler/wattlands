extends GutTest
## SpeedModel (BRIEF 3.11): the per-step integrator against the steady-state bisection
## oracle P*eta = v*(m*g*(Crr*cos + sin) + 0.5*rho*CdA*(v + v_wind)^2).

const DT := 0.05
const POWER_W := 250.0
const GRADES: Array[float] = [-5.0, 0.0, 3.0, 8.0]
const WINDS: Array[float] = [-3.0, 0.0, 4.0]
const MASSES: Array[float] = [60.0, 75.0, 100.0]
const CDAS: Array[float] = [0.25, 0.32, 0.5]


## Residual of the steady-state equation, relative to P*eta.
func _oracle_residual(
	p_w: float, grade_pct: float, mass_total: float, cda: float, wind: float, v: float
) -> float:
	var th := atan(grade_pct / 100.0)
	var rel := v + wind
	var force := (
		mass_total * SpeedModel.G * (SpeedModel.DEFAULT_CRR * cos(th) + sin(th))
		+ 0.5 * SpeedModel.DEFAULT_RHO * cda * rel * rel
	)
	var target := p_w * SpeedModel.DEFAULT_ETA
	return absf(v * force - target) / target


func test_defaults_match_the_brief() -> void:
	var m := SpeedModel.new()
	assert_eq(m.crr, 0.004)
	assert_eq(m.cda, 0.32)
	assert_eq(m.rho, 1.225)
	assert_eq(m.eta, 0.97)
	assert_eq(m.rider_mass_kg, 75.0)
	assert_eq(m.mass_offset_kg, 8.0)
	assert_eq(m.mass_kg(), 83.0)
	assert_eq(m.v_mps, 0.0)
	assert_eq(m.distance_m, 0.0)


func test_create_sets_mass_cda_and_offset() -> void:
	var m := SpeedModel.create(62.0, 0.28, 12.0)
	assert_eq(m.rider_mass_kg, 62.0)
	assert_eq(m.cda, 0.28)
	assert_eq(m.mass_offset_kg, 12.0)
	assert_eq(m.mass_kg(), 74.0)


func test_bisection_oracle_self_check() -> void:
	for grade in GRADES:
		for wind in WINDS:
			for mass in MASSES:
				for cda in CDAS:
					var total := mass + SpeedModel.DEFAULT_MASS_OFFSET_KG
					var v := SpeedModel.steady_state_speed(
						POWER_W, grade, total, cda, SpeedModel.DEFAULT_CRR, wind
					)
					assert_true(
						v > 0.0 and v < 30.0,
						(
							"v in (0, 30) for grade %s wind %s mass %s cda %s"
							% [grade, wind, mass, cda]
						)
					)
					assert_lt(
						_oracle_residual(POWER_W, grade, total, cda, wind, v),
						1e-6,
						"P*eta = v*F for grade %s wind %s mass %s cda %s" % [grade, wind, mass, cda]
					)


func test_oracle_known_value() -> void:
	# 250 W, flat, still air, 83 kg, CdA 0.32 is a little over 37 km/h.
	var v := SpeedModel.steady_state_speed(250.0, 0.0, 83.0)
	assert_between(v * 3.6, 36.0, 38.0)
	assert_lt(SpeedModel.steady_state_speed(250.0, 8.0, 83.0), v, "climbing is slower")
	assert_gt(SpeedModel.steady_state_speed(250.0, -5.0, 83.0), v, "descending is faster")
	assert_lt(
		SpeedModel.steady_state_speed(250.0, 0.0, 83.0, 0.32, 0.004, 4.0), v, "headwind is slower"
	)


func test_integrator_converges_to_the_oracle() -> void:
	for grade in GRADES:
		for wind in WINDS:
			for mass in MASSES:
				for cda in CDAS:
					var m := SpeedModel.create(mass, cda)
					for i in 6000:  # 300 s
						m.step(DT, POWER_W, grade, wind)
					var oracle := SpeedModel.steady_state_speed(
						POWER_W, grade, m.mass_kg(), cda, m.crr, wind
					)
					var err := absf(m.v_mps - oracle) / oracle
					assert_lt(
						err,
						0.005,
						(
							"grade %s wind %s mass %s cda %s: v %.4f oracle %.4f"
							% [grade, wind, mass, cda, m.v_mps, oracle]
						)
					)


func test_speed_never_negative() -> void:
	var m := SpeedModel.create()
	m.reset(0.5)
	for i in 400:
		assert_true(m.step(DT, 0.0, 10.0, 0.0) >= 0.0)
	assert_eq(m.v_mps, 0.0, "a stopped rider on a 10% climb stays at 0, never rolls back")
	m.reset(2.0)
	for i in 400:
		m.step(DT, 0.0, 0.0, 15.0)
	assert_eq(m.v_mps, 0.0, "a strong headwind with no power stops the rider at 0")
	m.reset(5.0)
	m.step(DT, -500.0, 0.0, 0.0)
	assert_true(m.v_mps >= 0.0, "negative power counts as 0")
	assert_true(m.v_mps < 5.0)


func test_distance_accumulates() -> void:
	var m := SpeedModel.create()
	for i in 4000:
		m.step(DT, 200.0)
	var v := m.v_mps
	var d0 := m.distance_m
	assert_gt(d0, 0.0)
	for i in 2000:  # 100 s at steady state
		m.step(DT, 200.0)
	assert_almost_eq(m.distance_m - d0, v * 100.0, v * 100.0 * 0.001)


func test_speed_kmh_visual_multiplier_and_reset() -> void:
	var m := SpeedModel.create()
	m.reset(10.0)
	assert_almost_eq(m.speed_kmh(), 36.0, 1e-9)
	m.visual_multiplier = 1.5
	assert_almost_eq(m.visual_speed_mps(), 15.0, 1e-9)
	var before := m.v_mps
	m.step(DT, 0.0)
	assert_lt(m.v_mps, before, "physics ignores the visual multiplier")
	m.reset()
	assert_eq(m.v_mps, 0.0)
	assert_eq(m.distance_m, 0.0)


func test_heavier_rider_climbs_slower() -> void:
	var light := SpeedModel.steady_state_speed(250.0, 8.0, 68.0)
	var heavy := SpeedModel.steady_state_speed(250.0, 8.0, 108.0)
	assert_lt(heavy, light)
