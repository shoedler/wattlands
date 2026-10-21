extends GutTest
## WBalance (BRIEF 3.4): Skiba's differential model, stepped every sim tick.
##   P >= CP: wbal -= (P - CP) * dt
##   P <  CP: wbal = Wp - (Wp - wbal) * exp(-dt * (CP - P) / Wp)
##   clamp to [0, Wp]

const DT := 0.05


func _run(w: WBalance, power_w: float, seconds: float) -> float:
	var n := roundi(seconds / DT)
	for i in n:
		w.step(power_w, DT)
	return w.wbal_j


func test_create_starts_full() -> void:
	var w := WBalance.create(250.0, 20000.0)
	assert_eq(w.cp_w, 250.0)
	assert_eq(w.wprime_j, 20000.0)
	assert_eq(w.wbal_j, 20000.0)
	assert_eq(w.fraction(), 1.0)


func test_above_cp_drains_linearly() -> void:
	var w := WBalance.create(250.0, 20000.0)
	assert_almost_eq(_run(w, 350.0, 10.0), 19000.0, 1e-6, "100 W over CP for 10 s")
	assert_almost_eq(_run(w, 450.0, 30.0), 13000.0, 1e-6, "200 W over CP for 30 s more")
	assert_almost_eq(w.fraction(), 0.65, 1e-9)


func test_exactly_cp_holds() -> void:
	var w := WBalance.create(250.0, 20000.0)
	w.wbal_j = 12345.0
	assert_almost_eq(_run(w, 250.0, 60.0), 12345.0, 1e-9)


func test_drain_clamps_at_zero() -> void:
	var w := WBalance.create(250.0, 20000.0)
	assert_eq(w.step(1250.0, 30.0), 0.0, "30 kJ above CP empties a 20 kJ tank")
	assert_eq(_run(w, 1000.0, 5.0), 0.0, "stays at 0 while above CP")


func test_below_cp_recovers_per_the_exponential() -> void:
	var w := WBalance.create(250.0, 20000.0)
	w.wbal_j = 10000.0
	var got := _run(w, 150.0, 60.0)
	# Wp - (Wp - w0) * exp(-t * (CP - P) / Wp) = 20000 - 10000 * exp(-60 * 100 / 20000)
	var expected := 20000.0 - 10000.0 * exp(-0.3)
	assert_almost_eq(got, expected, expected * 1e-9)


func test_closed_form_steps() -> void:
	var w := WBalance.create(200.0, 15000.0)
	var wb := 15000.0
	var powers: Array[float] = [400.0, 400.0, 100.0, 0.0, 250.0, 199.0, 600.0]
	for p in powers:
		var dt := 1.5
		if p >= 200.0:
			wb -= (p - 200.0) * dt
		else:
			wb = 15000.0 - (15000.0 - wb) * exp(-dt * (200.0 - p) / 15000.0)
		wb = clampf(wb, 0.0, 15000.0)
		assert_almost_eq(w.step(p, dt), wb, 1e-9, "P = %s" % p)


func test_recovery_never_exceeds_wprime() -> void:
	var w := WBalance.create(250.0, 20000.0)
	w.wbal_j = 19999.9
	assert_true(_run(w, 0.0, 1000.0) <= 20000.0)
	w.wbal_j = 25000.0
	assert_eq(w.step(100.0, DT), 20000.0, "an out-of-range balance is clamped to W'")


func test_full_recovery_from_empty_approaches_wprime() -> void:
	var w := WBalance.create(250.0, 20000.0)
	w.wbal_j = 0.0
	var after := _run(w, 0.0, 600.0)
	var expected := 20000.0 * (1.0 - exp(-600.0 * 250.0 / 20000.0))
	assert_almost_eq(after, expected, 1e-6)
	assert_true(after > 19980.0 and after < 20000.0)


func test_reset_and_fraction() -> void:
	var w := WBalance.create(300.0, 24000.0)
	_run(w, 400.0, 60.0)
	assert_almost_eq(w.fraction(), 0.75, 1e-9)
	w.reset()
	assert_eq(w.wbal_j, 24000.0)
	assert_eq(w.fraction(), 1.0)
