extends GutTest
## SpeedModel (BRIEF 3.11) beyond W0's tests: the integrator against the bisection oracle
## across powers, grades, winds, masses, CdA and mass offsets; the game-feel parameters (a
## game's own CdA, mass offset and visual multiplier, Diesel Domestiques's CdA 0.5 m^2 at m + 8 kg);
## a hand-computed first step; and effort scaling (BRIEF 3.3) feeding P_eff.

const DT := 0.05
const POWERS: Array[float] = [100.0, 250.0, 400.0]
const GRADES: Array[float] = [-6.0, -2.0, 0.0, 4.0, 10.0]
const WINDS: Array[float] = [-4.0, 0.0, 5.0]
const MASSES: Array[float] = [55.0, 75.0, 110.0]
const CDAS: Array[float] = [0.25, 0.32, 0.5]
const OFFSETS: Array[float] = [0.0, 8.0, 20.0]


func _settle(m: SpeedModel, p_w: float, grade: float, wind: float, seconds: float = 400.0) -> float:
	for i in roundi(seconds / DT):
		m.step(DT, p_w, grade, wind)
	return m.v_mps


## The BRIEF 3.11 oracle squares (v + v_wind), so it holds while the air still pushes back
## (v + v_wind >= 0). Where a tailwind outruns a slow climber the integrator's
## (v + v_wind) * |v + v_wind| pushes instead; this is the same bisection with that sign.
func _signed_oracle(p_w: float, grade: float, mass_total: float, cda: float, wind: float) -> float:
	var th := atan(grade / 100.0)
	var target := p_w * SpeedModel.DEFAULT_ETA
	var lo := 0.0
	var hi := 30.0
	for i in 200:
		var mid := 0.5 * (lo + hi)
		var rel := mid + wind
		var need := (
			mid
			* (
				mass_total * SpeedModel.G * (SpeedModel.DEFAULT_CRR * cos(th) + sin(th))
				+ 0.5 * SpeedModel.DEFAULT_RHO * cda * rel * absf(rel)
			)
		)
		if need < target:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


func test_integrator_matches_the_oracle_everywhere() -> void:
	var worst := 0.0
	var brief_cases := 0
	var signed_cases := 0
	for p in POWERS:
		for grade in GRADES:
			for wind in WINDS:
				for cda in CDAS:
					var m := SpeedModel.create(75.0, cda)
					var v := _settle(m, p, grade, wind)
					var oracle := SpeedModel.steady_state_speed(
						p, grade, m.mass_kg(), cda, m.crr, wind
					)
					if oracle + wind < 0.0:
						oracle = _signed_oracle(p, grade, m.mass_kg(), cda, wind)
						assert_lt(oracle + wind, 0.0, "the tailwind really outruns the rider")
						signed_cases += 1
					else:
						brief_cases += 1
					var err := absf(v - oracle) / oracle
					worst = maxf(worst, err)
					assert_lt(
						err,
						0.005,
						(
							"P %s grade %s wind %s cda %s: v %.4f oracle %.4f"
							% [p, grade, wind, cda, v, oracle]
						)
					)
	assert_gt(brief_cases, 100, "most cases use the BRIEF oracle as written")
	gut.p(
		(
			"worst relative error %.6f (%d BRIEF-oracle cases, %d signed-oracle cases)"
			% [worst, brief_cases, signed_cases]
		)
	)


func test_integrator_matches_the_oracle_across_masses_and_offsets() -> void:
	for mass in MASSES:
		for offset in OFFSETS:
			for grade: float in [0.0, 6.0]:
				var m := SpeedModel.create(mass, SpeedModel.DEFAULT_CDA, offset)
				assert_eq(m.mass_kg(), mass + offset)
				var v := _settle(m, 250.0, grade, 0.0)
				var oracle := SpeedModel.steady_state_speed(250.0, grade, mass + offset)
				assert_lt(
					absf(v - oracle) / oracle,
					0.005,
					"mass %s offset %s grade %s" % [mass, offset, grade]
				)


func test_first_steps_by_hand() -> void:
	# v0 = 0, 250 W, flat, still air, m = 83 kg:
	# a = (0.97 * 250 / max(0, 1) - 83 * 9.80665 * 0.004) / 83 = 2.882460147 m/s^2
	var m := SpeedModel.create()
	assert_almost_eq(m.step(DT, 250.0), 0.1441230073493976, 1e-12)
	assert_almost_eq(m.distance_m, 0.1441230073493976 * DT, 1e-12)
	# Second step: drive still divides by max(v, 1) = 1; aero 0.5 * 1.225 * 0.32 * v * |v|.
	assert_almost_eq(m.step(DT, 250.0), 0.288243562167178, 1e-12)


func test_own_cda_for_game_feel() -> void:
	# Diesel Domestiques: CdA 0.5 m^2, m = mass + 8 kg (the default offset).
	var tank := SpeedModel.create(75.0, 0.5)
	assert_eq(tank.cda, 0.5)
	assert_eq(tank.mass_kg(), 83.0)
	var v_tank := _settle(tank, 250.0, 0.0, 0.0)
	var v_bike := _settle(SpeedModel.create(), 250.0, 0.0, 0.0)
	assert_lt(v_tank, v_bike, "more drag, slower")
	assert_almost_eq(v_tank, SpeedModel.steady_state_speed(250.0, 0.0, 83.0, 0.5), 0.02)


func test_mass_offset_for_game_feel() -> void:
	var light := SpeedModel.create(75.0, SpeedModel.DEFAULT_CDA, 0.0)
	var heavy := SpeedModel.create(75.0, SpeedModel.DEFAULT_CDA, 40.0)
	assert_lt(
		_settle(heavy, 250.0, 6.0, 0.0),
		_settle(light, 250.0, 6.0, 0.0),
		"a heavier vehicle climbs slower"
	)
	# On the flat the steady state barely depends on mass, but acceleration does.
	var a := SpeedModel.create(75.0, SpeedModel.DEFAULT_CDA, 0.0)
	var b := SpeedModel.create(75.0, SpeedModel.DEFAULT_CDA, 40.0)
	for i in 20:
		a.step(DT, 250.0)
		b.step(DT, 250.0)
	assert_gt(a.v_mps, b.v_mps, "the lighter one accelerates faster")


func test_visual_multiplier_never_changes_physics() -> void:
	var plain := SpeedModel.create()
	var fast_look := SpeedModel.create()
	fast_look.visual_multiplier = 2.5
	for i in 2000:
		plain.step(DT, 220.0, 2.0, 1.0)
		fast_look.step(DT, 220.0, 2.0, 1.0)
	assert_eq(fast_look.v_mps, plain.v_mps, "same physical speed")
	assert_eq(fast_look.distance_m, plain.distance_m, "same physical distance")
	assert_eq(fast_look.speed_kmh(), plain.speed_kmh(), "speed_kmh is physical")
	assert_almost_eq(fast_look.visual_speed_mps(), plain.v_mps * 2.5, 1e-12)
	assert_eq(plain.visual_speed_mps(), plain.v_mps, "default multiplier 1")


func test_headwind_and_tailwind() -> void:
	var still := SpeedModel.steady_state_speed(250.0, 0.0, 83.0)
	var head := _settle(SpeedModel.create(), 250.0, 0.0, 5.0)
	var tail := _settle(SpeedModel.create(), 250.0, 0.0, -4.0)
	assert_lt(head, still)
	assert_gt(tail, still)


func test_tailwind_faster_than_the_rider_pushes() -> void:
	# With no power and a 12 m/s tailwind, air pushes the rider until v + v_wind ~ 0
	# (minus rolling resistance), never beyond the wind speed.
	var m := SpeedModel.create()
	var v := _settle(m, 0.0, 0.0, -12.0, 600.0)
	assert_gt(v, 5.0, "the wind pushes")
	assert_lt(v, 12.0, "never faster than the wind")


func test_fair_ftp_scaling_equalizes_speed() -> void:
	# FAIR_FTP: P_eff = P / FTP * 250, so riders at the same %FTP ride equally fast.
	var a := SpeedModel.create(EffortScaling.rider_mass_kg(Wl.FAIR_FTP, 60.0, true))
	var b := SpeedModel.create(EffortScaling.rider_mass_kg(Wl.FAIR_FTP, 95.0, true))
	assert_eq(a.mass_kg(), 83.0, "FAIR_FTP always uses the 75 kg reference")
	var pa := EffortScaling.p_eff_w(Wl.FAIR_FTP, 0.75 * 150.0, 150.0, 60.0)
	var pb := EffortScaling.p_eff_w(Wl.FAIR_FTP, 0.75 * 320.0, 320.0, 95.0)
	assert_almost_eq(pa, pb, 1e-9)
	assert_almost_eq(pa, 187.5, 1e-9)
	assert_almost_eq(_settle(a, pa, 3.0, 0.0), _settle(b, pb, 3.0, 0.0), 1e-9)


func test_wkg_scaling_equalizes_by_watts_per_kilo() -> void:
	var pa := EffortScaling.p_eff_w(Wl.WKG, 3.0 * 60.0, 200.0, 60.0)
	var pb := EffortScaling.p_eff_w(Wl.WKG, 3.0 * 90.0, 300.0, 90.0)
	assert_almost_eq(pa, 225.0, 1e-9, "3 W/kg x 75 kg")
	assert_almost_eq(pa, pb, 1e-9)
	var a := SpeedModel.create(EffortScaling.rider_mass_kg(Wl.WKG, 60.0, true))
	var b := SpeedModel.create(EffortScaling.rider_mass_kg(Wl.WKG, 90.0, true))
	assert_almost_eq(_settle(a, pa, 5.0, 0.0), _settle(b, pb, 5.0, 0.0), 1e-9)


func test_raw_scaling_uses_real_watts_and_shared_weight() -> void:
	var light := SpeedModel.create(EffortScaling.rider_mass_kg(Wl.RAW, 60.0, true))
	var heavy := SpeedModel.create(EffortScaling.rider_mass_kg(Wl.RAW, 95.0, true))
	var hidden := SpeedModel.create(EffortScaling.rider_mass_kg(Wl.RAW, 95.0, false))
	assert_eq(light.mass_kg(), 68.0)
	assert_eq(heavy.mass_kg(), 103.0)
	assert_eq(hidden.mass_kg(), 83.0, "75 kg unless the weight is shared")
	var p := EffortScaling.p_eff_w(Wl.RAW, 250.0, 200.0, 95.0)
	assert_eq(p, 250.0)
	assert_gt(
		_settle(light, p, 6.0, 0.0),
		_settle(heavy, p, 6.0, 0.0),
		"same watts, lighter climbs faster"
	)
