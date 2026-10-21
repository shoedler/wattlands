extends GutTest
## MockTrainer's rider model (BRIEF 4.2, 4.5): W' fatigue that fails targets far above CP
## while sub-CP targets hold, cadence that lags after sprints, SIM speed from the SpeedModel,
## ERG flywheel speed from cadence, seeded dropouts, keyboard offsets, seeded determinism and
## simulated control loss.

const FTP := 250.0
const DT := 0.05

var _samples: Array[TrainerSample] = []
var _responses: Array[Vector2i] = []


func before_each() -> void:
	_samples = []
	_responses = []


func _mock(spec: String, ftp: float = FTP, options: Dictionary = {}) -> MockTrainer:
	var m: MockTrainer = autofree(MockTrainer.from_spec(spec, ftp, options))
	m.sample_received.connect(func(s: TrainerSample) -> void: _samples.append(s))
	m.control_response.connect(func(op: int, res: int) -> void: _responses.append(Vector2i(op, res)))
	return m


func _run(m: MockTrainer, seconds: float) -> void:
	for i in roundi(seconds / DT):
		m.tick(DT)


func _run_to(m: MockTrainer, t: float) -> void:
	while m.platform_time_s() < t - 1e-6:
		m.tick(DT)


# --- fatigue --------------------------------------------------------------------------

func test_fatigue_fails_150_pct_within_a_few_minutes() -> void:
	var m := _mock("erg")
	m.set_target_power(roundi(1.5 * FTP))
	var exhausted_at := -1.0
	while m.platform_time_s() < 300.0:
		m.tick(DT)
		if exhausted_at < 0.0 and m.is_exhausted():
			exhausted_at = m.platform_time_s()
	# W' / (P - CP) = 20000 / 125 = 160 s, plus the follower's settling.
	assert_between(exhausted_at, 155.0, 170.0, "W' runs out after about 160 s")
	assert_lt(m.instantaneous_power_w(), 0.75 * 1.5 * FTP, "below the governor's 75% rescue line")
	assert_almost_eq(m.instantaneous_power_w(), MockTrainer.EXHAUSTED_CP_FRACTION * FTP, 2.0)
	for s in _samples:
		if s.t > 10.0 and s.t < exhausted_at - 1.0:
			assert_almost_eq(s.power_w, 375.0, 2.0, "holds the target until W' is gone (t %.1f)" % s.t)


func test_sub_cp_targets_hold_for_twenty_minutes() -> void:
	var m := _mock("erg")
	m.set_target_power(roundi(0.9 * FTP))
	_run(m, 1200.0)
	assert_false(m.is_exhausted())
	assert_almost_eq(m.instantaneous_power_w(), 225.0, 0.5)
	assert_almost_eq(m.wbal_j(), MockTrainer.DEFAULT_WPRIME_J, 1e-6, "below CP W' stays full")


func test_exhaustion_recovers_after_easier_riding() -> void:
	var m := _mock("erg")
	m.set_target_power(375)
	_run(m, 200.0)
	assert_true(m.is_exhausted())
	m.set_target_power(100)
	var recovered_at := -1.0
	while m.platform_time_s() < 400.0:
		m.tick(DT)
		if recovered_at < 0.0 and not m.is_exhausted():
			recovered_at = m.platform_time_s()
	assert_gt(recovered_at, 200.0)
	assert_lt(recovered_at - 200.0, 60.0, "10% of W' comes back within a minute at 40% FTP")
	assert_gt(m.wbal_j(), 0.1 * MockTrainer.DEFAULT_WPRIME_J)
	m.set_target_power(375)
	_run(m, 10.0)
	assert_almost_eq(m.instantaneous_power_w(), 375.0, 4.0, "can hold a hard target again for a while")


func test_cp_and_wprime_options() -> void:
	var m := _mock("erg", FTP, {"cp_w": 300.0, "wprime_j": 10000.0})
	m.set_target_power(375)
	var exhausted_at := -1.0
	while m.platform_time_s() < 250.0 and exhausted_at < 0.0:
		m.tick(DT)
		if m.is_exhausted():
			exhausted_at = m.platform_time_s()
	assert_between(exhausted_at, 128.0, 142.0, "10000 / (375 - 300) = 133 s")
	_run(m, 20.0)
	assert_almost_eq(m.instantaneous_power_w(), MockTrainer.EXHAUSTED_CP_FRACTION * 300.0, 2.0)


func test_vo2_intervals_never_exhaust_a_compliant_rider() -> void:
	# Workout's VO2 session (BRIEF 3.7): 5 x 3 min at 110% with 3 min at 50% between.
	var m := _mock("erg:compliance=1.0", 200.0)
	for i in 5:
		m.set_target_power(220)
		_run(m, 180.0)
		assert_false(m.is_exhausted(), "interval %d" % (i + 1))
		assert_almost_eq(m.instantaneous_power_w(), 220.0, 1.0)
		m.set_target_power(100)
		_run(m, 180.0)


# --- sprints, cadence lag and speed ---------------------------------------------------

func test_cadence_lags_after_a_sprint() -> void:
	var m := _mock("erg", 200.0)
	m.set_simulation(0.0, 0.0, 0.004, 0.51)
	m.set_power_band(250.0, 270.0)
	_run(m, 20.0)
	assert_almost_eq(m.instantaneous_power_w(), 260.0, 1.0, "a SIM sprint at 130% FTP")
	assert_almost_eq(m.cadence_rpm(), 99.0, 1e-6, "sprint cadence +10%")
	m.set_target_power(150)
	_run(m, 1.0)
	assert_almost_eq(m.cadence_rpm(), 90.0, 1e-6, "the rider's cadence is back")
	var lagged := m.reported_cadence_rpm()
	assert_between(lagged, 92.0, 97.0, "the trainer's estimate lags (tau 1.5 s)")
	_run(m, 5.0)
	assert_eq(m.reported_cadence_rpm(), 90.0, "the lag ends 5 s after the sprint")


func test_band_riders_keep_the_band_in_a_sprint() -> void:
	var m := _mock("erg+band", 200.0, {"seed": 2})
	m.set_cadence_band(84.0, 96.0)
	m.set_simulation(0.0, 0.0, 0.004, 0.51)
	m.set_power_band(250.0, 270.0)
	_run(m, 20.0)
	assert_almost_eq(m.cadence_rpm(), 90.0, 1.6, "band cadence, no sprint lift")


func test_no_sprint_lift_in_erg_or_for_scripts() -> void:
	var e := _mock("erg", 200.0)
	e.set_target_power(300)
	_run(e, 20.0)
	assert_eq(e.cadence_rpm(), 90.0, "ERG holds power; the rider keeps their cadence")
	var c := _mock("const:w=300,rpm=85", 200.0)
	c.set_simulation(0.0, 0.0, 0.004, 0.51)
	_run(c, 5.0)
	assert_eq(c.cadence_rpm(), 85.0)


func test_erg_flywheel_speed_follows_cadence() -> void:
	var m := _mock("erg+band", 200.0, {"seed": 3})
	m.set_cadence_band(70.0, 80.0)
	m.set_target_power(150)
	_run(m, 30.0)
	assert_almost_eq(m.speed_kmh(), m.cadence_rpm() * MockTrainer.KMH_PER_RPM, 1e-9)
	assert_almost_eq(m.last_sample().speed_kmh, 75.0 * MockTrainer.KMH_PER_RPM, 0.7)


func test_sim_speed_comes_from_the_speed_model() -> void:
	var m := _mock("erg")
	m.set_simulation(0.0, 0.0, 0.004, 0.51)
	_run(m, 180.0)
	var flat := SpeedModel.steady_state_speed(225.0, 0.0, 75.0 + 8.0) * 3.6
	assert_almost_eq(m.speed_kmh(), flat, 0.01 * flat, "steady state on the flat")
	m.set_simulation(0.0, 5.0, 0.004, 0.51)
	_run(m, 180.0)
	var climb := SpeedModel.steady_state_speed(225.0, 5.0, 83.0) * 3.6
	assert_almost_eq(m.speed_kmh(), climb, 0.02 * climb, "slower on 5%")
	m.set_simulation(3.0, 5.0, 0.004, 0.51)
	_run(m, 120.0)
	var windy := SpeedModel.steady_state_speed(225.0, 5.0, 83.0, SpeedModel.DEFAULT_CDA, SpeedModel.DEFAULT_CRR, 3.0) * 3.6
	assert_almost_eq(m.speed_kmh(), windy, 0.02 * windy, "a headwind slows the rider")
	assert_lt(windy, climb)


func test_rider_weight_changes_climbing_speed() -> void:
	var light := _mock("erg", FTP, {"weight_kg": 60.0})
	var heavy := _mock("erg", FTP, {"weight_kg": 100.0})
	for m: MockTrainer in [light, heavy]:
		m.set_simulation(0.0, 6.0, 0.004, 0.51)
		_run(m, 240.0)
	assert_gt(light.speed_kmh(), heavy.speed_kmh() + 2.0)
	assert_almost_eq(heavy.speed_kmh(), SpeedModel.steady_state_speed(225.0, 6.0, 108.0) * 3.6, 0.3)


func test_switching_to_sim_starts_from_the_flywheel_speed() -> void:
	var m := _mock("erg")
	m.set_target_power(200)
	_run(m, 20.0)
	assert_almost_eq(m.speed_kmh(), 36.0, 1e-6)
	m.set_simulation(0.0, 0.0, 0.004, 0.51)
	m.tick(DT)
	assert_almost_eq(m.speed_kmh(), 36.0, 0.5, "no jump to 0 when SIM starts")


# --- notifications --------------------------------------------------------------------

func test_dropouts_skip_notifications_on_the_same_schedule() -> void:
	var plain := _times("erg", {"seed": 13})
	var gappy := _times("erg", {"seed": 13, "dropouts": true})
	assert_lt(gappy.size(), plain.size(), "some notifications are lost")
	for t in gappy:
		assert_has(plain, t, "every delivered notification keeps its time")
	var biggest := 0.0
	for i in range(1, gappy.size()):
		biggest = maxf(biggest, gappy[i] - gappy[i - 1])
	assert_gt(biggest, MockTrainer.DROPOUT_MIN_S)
	assert_lt(biggest, MockTrainer.DROPOUT_MAX_S + 2.0 * MockTrainer.SAMPLE_MAX_S + 2.0 * DT, "gaps never chain")
	var m := _mock("erg", FTP, {"seed": 13, "dropouts": true})
	_run(m, 600.0)
	assert_gt(m.dropout_count(), 3)
	assert_eq(m.samples_emitted(), gappy.size())
	assert_eq(_times("erg", {"seed": 13, "dropouts": true}), gappy, "seeded")
	var heavy := _times("erg", {"seed": 13, "dropouts": 0.3})
	assert_lt(heavy.size(), gappy.size(), "a number sets the per-notification chance")


func test_no_dropouts_by_default() -> void:
	var m := _mock("erg", FTP, {"seed": 13})
	_run(m, 600.0)
	assert_eq(m.dropout_count(), 0)
	for i in range(1, _samples.size()):
		assert_lt(_samples[i].t - _samples[i - 1].t, MockTrainer.SAMPLE_MAX_S + DT + 1e-6)


func _times(spec: String, options: Dictionary) -> Array[float]:
	_samples = []
	var m := _mock(spec, FTP, options)
	m.set_target_power(200)
	_run(m, 600.0)
	var out: Array[float] = []
	for s in _samples:
		out.append(s.t)
	_samples = []
	return out


# --- keyboard, determinism, control ---------------------------------------------------

func test_keyboard_offsets() -> void:
	var m := _mock("erg")
	assert_eq(m.keyboard_offsets(), {"power_w": 0.0, "cadence_rpm": 0.0}, "keyboard off by default")
	m.set_target_power(200)
	m.nudge_power(MockTrainer.KEY_POWER_STEP_W)
	m.nudge_power(MockTrainer.KEY_POWER_STEP_W)
	m.nudge_cadence(-MockTrainer.KEY_CADENCE_STEP_RPM)
	_run(m, 20.0)
	assert_almost_eq(m.instantaneous_power_w(), 220.0, 0.5, "W twice: +20 W")
	assert_eq(m.cadence_rpm(), 85.0, "A once: -5 rpm")
	m.nudge_power(-30.0)
	_run(m, 20.0)
	assert_almost_eq(m.instantaneous_power_w(), 190.0, 0.5)
	assert_eq(m.keyboard_offsets(), {"power_w": -10.0, "cadence_rpm": -5.0})


func test_seeded_determinism_with_every_component() -> void:
	var spec := "erg:compliance=0.9+band:offset_rpm=5+noise+surge:every_s=30+cadence_drop:rpm=40,at_s=100,for_s=10"
	var opts := {"seed": 42, "dropouts": true}
	var a := _dicts(spec, opts, 1.0)
	var b := _dicts(spec, opts, 1.0)
	assert_gt(a.size(), 150)
	assert_eq(a, b, "same seed, same samples")
	var coarse := _dicts(spec, opts, 0.5)
	assert_eq(coarse.size(), a.size(), "tick size does not matter (fixed internal steps)")
	for i in mini(coarse.size(), a.size()):
		for key: String in ["t", "power_w", "cadence_rpm", "speed_kmh"]:
			assert_almost_eq(float(coarse[i][key]), float(a[i][key]), 1e-6, "sample %d %s" % [i, key])
	opts["seed"] = 43
	assert_ne(_dicts(spec, opts, 1.0), a, "another seed, another run")


func _dicts(spec: String, options: Dictionary, tick_s: float) -> Array:
	_samples = []
	var m := _mock(spec, FTP, options)
	m.set_cadence_band(80.0, 90.0)
	m.set_target_power(200)
	for i in roundi(200.0 / tick_s):
		m.tick(tick_s)
	var out: Array = []
	for s in _samples:
		out.append(s.to_dict())
	_samples = []
	return out


func test_simulated_control_loss_and_refusals() -> void:
	var m := _mock("erg")
	watch_signals(m)
	m.response_result = 0x04
	m.set_target_power(150)
	m.tick(DT)
	assert_eq(_responses, [Vector2i(MockTrainer.OP_SET_TARGET_POWER, 0x04)] as Array[Vector2i])
	m.response_result = MockTrainer.RESULT_SUCCESS
	m.simulate_control_lost()
	assert_signal_emitted_with_parameters(m, "status_changed", [TrainerDevice.STATUS_CONTROL_LOST, FtmsClient.DETAIL_ANOTHER_APP])
	assert_signal_emitted_with_parameters(m, "machine_status", [0xFF, PackedByteArray()])
	assert_false(m.is_ready())
	assert_eq(m.status(), TrainerDevice.STATUS_CONTROL_LOST)
	m.set_target_power(160)
	m.tick(DT)
	assert_eq(_responses.back(), Vector2i(MockTrainer.OP_SET_TARGET_POWER, MockTrainer.RESULT_CONTROL_NOT_PERMITTED))
	m.restore_control()
	assert_true(m.is_ready())
	m.set_target_power(170)
	m.tick(DT)
	assert_eq(_responses.back(), Vector2i(MockTrainer.OP_SET_TARGET_POWER, MockTrainer.RESULT_SUCCESS))
