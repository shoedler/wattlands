extends GutTest
## MockTrainer W0 (BRIEF 4.2): the spec grammar, the const, ramp and zero profiles, the
## `erg` follower (tau ~ 2 s, slight overshoot, compliance, SIM power band), ~1 Hz seeded
## samples and the recorded commands. Profiles added in W1 get their own tests
## (tests/trainer/test_mock_profiles.gd).

const FTP := 250.0
const DT := 0.05

var _samples: Array[TrainerSample] = []
var _responses: Array[Vector2i] = []


func before_each() -> void:
	_samples = []
	_responses = []


func _mock(spec: String, ftp: float = FTP, options: Dictionary = {}) -> MockTrainer:
	var m: MockTrainer = autofree(MockTrainer.from_spec(spec, ftp, options))
	m.sample_received.connect(_on_sample)
	m.control_response.connect(_on_response)
	return m


func _on_sample(s: TrainerSample) -> void:
	_samples.append(s)


func _on_response(opcode: int, result: int) -> void:
	_responses.append(Vector2i(opcode, result))


func _run(m: MockTrainer, seconds: float) -> void:
	for i in roundi(seconds / DT):
		m.tick(DT)


# --- spec grammar ---------------------------------------------------------------------

func test_parse_spec_single_profile() -> void:
	var comps := MockTrainer.parse_spec("erg")
	assert_eq(comps.size(), 1)
	assert_eq(comps[0]["name"], "erg")
	assert_eq((comps[0]["params"] as Dictionary).size(), 0)


func test_parse_spec_params_and_combination() -> void:
	var comps := MockTrainer.parse_spec("erg:compliance=0.85+const:w=150,rpm=80")
	assert_eq(comps.size(), 2)
	assert_eq(comps[0]["name"], "erg")
	assert_almost_eq(float(comps[0]["params"]["compliance"]), 0.85, 1e-12)
	assert_eq(comps[1]["name"], "const")
	assert_eq(comps[1]["params"], {"w": 150.0, "rpm": 80.0})


func test_parse_spec_whitespace_case_and_repeats() -> void:
	var comps := MockTrainer.parse_spec(" ERG : Compliance = 1 + zero ")
	assert_eq(comps.size(), 2)
	assert_eq(comps[0]["name"], "erg")
	assert_eq(comps[0]["params"], {"compliance": 1.0})
	assert_eq(comps[1]["name"], "zero")
	comps = MockTrainer.parse_spec("ramp:from_w=100,to_w=200,over_s=60+ramp:from_w=1,to_w=2,over_s=0")
	assert_eq(comps.size(), 2, "a profile may appear more than once")
	assert_eq(comps[1]["params"]["over_s"], 0.0)
	assert_push_error_count(0)


func test_parse_spec_invalid() -> void:
	var bad: Array[String] = [
		"", "   ", "bogus", "erg+", "+erg", "erg++zero", "erg:", ":w=1", "erg:compliance",
		"erg:compliance=", "erg:compliance=abc", "erg:compliance=1.5", "erg:compliance=-0.1",
		"erg:foo=1", "erg:=1", "const", "const:rpm=80", "const:w=1,w=2", "const:w=-5",
		"ramp:from_w=1,to_w=2", "ramp:from_w=1,to_w=2,over_s=-1", "zero:w=3",
	]
	for spec in bad:
		assert_eq(MockTrainer.parse_spec(spec), [], "\"%s\" is invalid" % spec)
		assert_push_error("invalid profile spec", spec)


func test_from_spec_invalid_falls_back_to_erg() -> void:
	var m := _mock("erg:complience=0.9")
	assert_push_error("invalid profile spec")
	assert_eq(m.spec, MockTrainer.DEFAULT_SPEC)
	assert_eq(m.components(), [{"name": "erg", "params": {}}])
	_run(m, 20.0)
	assert_almost_eq(m.instantaneous_power_w(), 0.9 * FTP, 1.0, "rides like erg (90% FTP before any command)")


func test_from_spec_keeps_the_spec_and_options() -> void:
	var m := _mock("const:w=150", 230.0, {"max_power_w": 1500, "seed": 3})
	assert_eq(m.spec, "const:w=150")
	assert_eq(m.power_range(), {"min_w": 0, "max_w": 1500, "step_w": 1})
	assert_eq(_mock("erg").power_range()["max_w"], 1800, "KICKR CORE default")
	assert_string_contains(m.device_name(), "const:w=150")


func test_bot_spec_is_valid() -> void:
	var m := _mock(Bots.RIDER_SPEC)
	assert_eq(m.spec, Bots.RIDER_SPEC)
	assert_push_error_count(0)


# --- device surface -------------------------------------------------------------------

func test_ready_from_the_start() -> void:
	var m := _mock("erg")
	assert_true(m.is_ready())
	assert_eq(m.status(), TrainerDevice.STATUS_READY)
	assert_eq(m.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_null(m.last_sample())
	assert_eq(m.commanded_mode, Wl.OFF)
	assert_eq(m.command_count, 0)
	var f := m.features()
	assert_true((int(f["target"]) & (1 << 3)) != 0, "power target (ERG)")
	assert_true((int(f["target"]) & (1 << 13)) != 0, "indoor bike simulation")
	assert_true((int(f["machine"]) & (1 << 14)) != 0, "power measurement")


func test_commands_are_recorded() -> void:
	var m := _mock("erg")
	m.set_target_power(180)
	assert_eq(m.commanded_mode, Wl.ERG)
	assert_eq(m.commanded_target_w, 180)
	assert_eq(m.command_count, 1)
	m.set_simulation(1.5, 3.25, 0.005, 0.45)
	assert_eq(m.commanded_mode, Wl.SIM)
	assert_eq(m.commanded_wind_mps, 1.5)
	assert_eq(m.commanded_grade_pct, 3.25)
	assert_eq(m.commanded_crr, 0.005)
	assert_eq(m.commanded_cw, 0.45)
	assert_eq(m.commanded_target_w, 180, "SIM keeps the last ERG target for reports")
	assert_eq(m.command_count, 2)
	m.set_resistance(12.5)
	assert_eq(m.commanded_mode, Wl.RESISTANCE)
	assert_eq(m.commanded_resistance, 12.5)
	assert_eq(m.command_count, 3)
	m.request_stop()
	assert_eq(m.commanded_mode, Wl.OFF)
	assert_eq(m.command_count, 4)


func test_control_responses_arrive_on_the_next_tick() -> void:
	var m := _mock("erg")
	m.set_target_power(150)
	m.set_simulation(0.0, 0.0, 0.004, 0.51)
	assert_eq(_responses.size(), 0, "not synchronous")
	m.tick(DT)
	assert_eq(_responses, [
		Vector2i(MockTrainer.OP_SET_TARGET_POWER, MockTrainer.RESULT_SUCCESS),
		Vector2i(MockTrainer.OP_SET_SIMULATION, MockTrainer.RESULT_SUCCESS),
	])
	m.tick(DT)
	assert_eq(_responses.size(), 2, "each response once")
	m.set_resistance(5.0)
	m.request_stop()
	m.tick(DT)
	assert_eq(_responses[2], Vector2i(MockTrainer.OP_SET_RESISTANCE, MockTrainer.RESULT_SUCCESS))
	assert_eq(_responses[3], Vector2i(MockTrainer.OP_STOP_PAUSE, MockTrainer.RESULT_SUCCESS))


# --- scripted profiles ----------------------------------------------------------------

func test_const_power_and_cadence() -> void:
	var m := _mock("const:w=150,rpm=85")
	m.set_target_power(300) # scripted profiles ignore the trainer
	_run(m, 30.0)
	assert_between(_samples.size(), 27, 34)
	for s in _samples:
		assert_eq(s.power_w, 150.0)
		assert_eq(s.cadence_rpm, 85.0)
		assert_almost_eq(s.speed_kmh, 85.0 * MockTrainer.KMH_PER_RPM, 1e-9)
		assert_true(s.has_cadence() and s.has_speed())
		assert_true((s.flags & TrainerSample.HAS_POWER) != 0)


func test_const_without_rpm_uses_the_preferred_cadence() -> void:
	var m := _mock("const:w=120", FTP, {"preferred_cadence_rpm": 82.0})
	_run(m, 3.0)
	assert_eq(m.last_sample().cadence_rpm, 82.0)
	var d := _mock("const:w=120")
	_run(d, 3.0)
	assert_eq(d.last_sample().cadence_rpm, 90.0, "preferred cadence defaults to 90")
	assert_almost_eq(d.last_sample().speed_kmh, 36.0, 1e-9, "fixed virtual gear: 90 rpm is 36 km/h")


func test_const_zero_watts_means_zero_cadence() -> void:
	var m := _mock("const:w=0,rpm=80")
	_run(m, 5.0)
	assert_eq(m.last_sample().power_w, 0.0)
	assert_eq(m.last_sample().cadence_rpm, 0.0)
	assert_eq(m.last_sample().speed_kmh, 0.0)


func test_ramp_power_over_time() -> void:
	var m := _mock("ramp:from_w=100,to_w=200,over_s=100,rpm=80")
	_run(m, 50.0)
	assert_almost_eq(m.instantaneous_power_w(), 150.0, 1e-6)
	_run(m, 50.0)
	assert_almost_eq(m.instantaneous_power_w(), 200.0, 1e-6)
	_run(m, 30.0)
	assert_almost_eq(m.instantaneous_power_w(), 200.0, 1e-6, "holds to_w after over_s")
	for s in _samples:
		var expected := 100.0 + minf(s.t, 100.0)
		assert_almost_eq(s.power_w, expected, 0.51, "t %.2f" % s.t)
		assert_eq(s.cadence_rpm, 80.0)


func test_ramp_down_to_zero_stops_pedalling() -> void:
	var m := _mock("ramp:from_w=200,to_w=0,over_s=10")
	_run(m, 5.0)
	assert_almost_eq(m.instantaneous_power_w(), 100.0, 1e-6)
	assert_eq(m.last_sample().cadence_rpm, 90.0)
	_run(m, 8.0)
	assert_eq(m.instantaneous_power_w(), 0.0)
	assert_eq(m.last_sample().cadence_rpm, 0.0)


func test_scripted_power_wins_over_erg() -> void:
	var m := _mock("erg:compliance=0.5+const:w=140")
	m.set_target_power(300)
	_run(m, 10.0)
	assert_eq(m.last_sample().power_w, 140.0)


func test_zero_profile_emits_zero() -> void:
	var m := _mock("zero")
	m.set_target_power(200)
	_run(m, 20.0)
	assert_gt(_samples.size(), 15)
	for s in _samples:
		assert_eq(s.power_w, 0.0)
		assert_eq(s.cadence_rpm, 0.0)
		assert_eq(s.speed_kmh, 0.0)
		assert_true(s.has_cadence(), "0 rpm is a reported value, not a missing one")


# --- erg follower ---------------------------------------------------------------------

## Instantaneous power every tick for `seconds` after the current state.
func _trace(m: MockTrainer, seconds: float) -> Array[float]:
	var out: Array[float] = []
	for i in roundi(seconds / DT):
		m.tick(DT)
		out.append(m.instantaneous_power_w())
	return out


func test_erg_step_response() -> void:
	var m := _mock("erg")
	m.set_target_power(200)
	var tr := _trace(m, 30.0)
	var t63 := -1.0
	var peak := 0.0
	for i in tr.size():
		if t63 < 0.0 and tr[i] >= 0.632 * 200.0:
			t63 = (i + 1) * DT
		peak = maxf(peak, tr[i])
	assert_between(t63, 1.6, 2.4, "63% of the step after about tau = 2 s")
	assert_gt(peak, 200.0, "a slight overshoot")
	assert_lt(peak, 220.0, "overshoot below 10%")
	for i in range(roundi(10.0 / DT) - 1, tr.size()):
		assert_almost_eq(tr[i], 200.0, 4.0, "within 2%% after 10 s (t %.2f)" % ((i + 1) * DT))
		if absf(tr[i] - 200.0) > 4.0:
			break


func test_erg_step_between_targets() -> void:
	var m := _mock("erg")
	m.set_target_power(100)
	_run(m, 30.0)
	assert_almost_eq(m.instantaneous_power_w(), 100.0, 0.5)
	m.set_target_power(300)
	var tr := _trace(m, 20.0)
	var crossed := -1.0
	for i in tr.size():
		if tr[i] >= 100.0 + 0.632 * 200.0:
			crossed = (i + 1) * DT
			break
	assert_between(crossed, 1.6, 2.4)
	assert_almost_eq(tr[tr.size() - 1], 300.0, 3.0)
	m.set_target_power(150)
	tr = _trace(m, 20.0)
	assert_lt(tr.min(), 150.0, "undershoot on the way down")
	assert_gt(tr.min(), 150.0 - 15.0, "less than 10% of the step")
	assert_almost_eq(tr[tr.size() - 1], 150.0, 1.5)


func test_erg_compliance_scales_the_target() -> void:
	var m := _mock("erg:compliance=0.85")
	m.set_target_power(200)
	_run(m, 30.0)
	assert_almost_eq(m.instantaneous_power_w(), 170.0, 0.5)
	assert_almost_eq(m.last_sample().power_w, 170.0, 1.0)
	assert_eq(m.last_sample().cadence_rpm, 90.0)


func test_erg_target_zero_stops_the_rider() -> void:
	var m := _mock("erg")
	m.set_target_power(200)
	_run(m, 10.0)
	m.set_target_power(0)
	_run(m, 3.0)
	assert_eq(m.instantaneous_power_w(), 0.0)
	assert_eq(m.last_sample().cadence_rpm, 0.0)
	assert_eq(m.last_sample().speed_kmh, 0.0)


func test_erg_in_sim_without_band_rides_90_pct_ftp() -> void:
	var m := _mock("erg")
	m.set_simulation(0.0, 2.0, 0.004, 0.51)
	_run(m, 30.0)
	assert_almost_eq(m.instantaneous_power_w(), 0.9 * FTP, 0.5)
	assert_almost_eq(m.last_sample().power_w, 225.0, 1.0)


func test_erg_in_sim_with_band_rides_its_centre() -> void:
	var m := _mock("erg")
	m.set_simulation(0.0, 0.0, 0.004, 0.51)
	m.set_power_band(200.0, 260.0)
	_run(m, 30.0)
	assert_almost_eq(m.instantaneous_power_w(), 230.0, 0.5)
	var c := _mock("erg:compliance=0.85")
	c.set_simulation(0.0, 0.0, 0.004, 0.51)
	c.set_power_band(200.0, 260.0)
	_run(c, 30.0)
	assert_almost_eq(c.instantaneous_power_w(), 0.85 * 230.0, 0.5, "compliance x the band centre")
	m.set_power_band(0.0, 0.0)
	_run(m, 30.0)
	assert_almost_eq(m.instantaneous_power_w(), 225.0, 0.5, "a cleared band falls back to 90% FTP")


func test_erg_band_is_ignored_in_erg() -> void:
	var m := _mock("erg")
	m.set_power_band(300.0, 340.0)
	m.set_target_power(180)
	_run(m, 30.0)
	assert_almost_eq(m.instantaneous_power_w(), 180.0, 0.5)


func test_erg_target_above_the_power_range_is_limited() -> void:
	var m := _mock("erg", FTP, {"max_power_w": 400})
	m.set_target_power(900)
	_run(m, 30.0)
	assert_almost_eq(m.instantaneous_power_w(), 400.0, 1.0)


# --- notifications --------------------------------------------------------------------

func test_samples_about_1_hz_with_jitter() -> void:
	var m := _mock("const:w=100", FTP, {"seed": 5})
	_run(m, 120.0)
	assert_between(_samples.size(), 108, 134)
	assert_between(_samples[0].t, 0.9 - 1e-6, 1.1 + DT)
	var gaps: Array[float] = []
	for i in range(1, _samples.size()):
		var gap := _samples[i].t - _samples[i - 1].t
		gaps.append(snappedf(gap, 0.001))
		assert_between(gap, 0.9 - DT - 1e-6, 1.1 + DT + 1e-6, "gap %d" % i)
	var distinct := {}
	for g in gaps:
		distinct[g] = true
	assert_gt(distinct.size(), 2, "intervals jitter")
	assert_same(m.last_sample(), _samples[_samples.size() - 1])


func test_samples_deterministic_by_seed() -> void:
	var a := _mock("erg", FTP, {"seed": 11})
	a.set_target_power(200)
	_run(a, 60.0)
	var first: Array = []
	for s in _samples:
		first.append(s.to_dict())
	_samples = []
	var b := _mock("erg", FTP, {"seed": 11})
	b.set_target_power(200)
	_run(b, 60.0)
	var second: Array = []
	for s in _samples:
		second.append(s.to_dict())
	assert_eq(second, first, "same seed, same samples")
	_samples = []
	var c := _mock("erg", FTP, {"seed": 12})
	c.set_target_power(200)
	_run(c, 60.0)
	var times_c: Array = []
	for s in _samples:
		times_c.append(s.t)
	var times_a: Array = []
	for d: Dictionary in first:
		times_a.append(d["t"])
	assert_ne(times_c, times_a, "another seed, other notification times")


func test_tick_granularity_does_not_change_the_run() -> void:
	var a := _mock("ramp:from_w=100,to_w=300,over_s=60", FTP, {"seed": 2})
	_run(a, 30.0)
	var fine: Array = []
	for s in _samples:
		fine.append(s.to_dict())
	_samples = []
	var b := _mock("ramp:from_w=100,to_w=300,over_s=60", FTP, {"seed": 2})
	for i in 30:
		b.tick(1.0)
	var coarse: Array = []
	for s in _samples:
		coarse.append(s.to_dict())
	assert_eq(coarse.size(), fine.size())
	for i in mini(coarse.size(), fine.size()):
		assert_almost_eq(float(coarse[i]["t"]), float(fine[i]["t"]), 1e-6)
		assert_almost_eq(float(coarse[i]["power_w"]), float(fine[i]["power_w"]), 1.0)


func test_platform_time_advances_only_in_tick() -> void:
	var m := _mock("erg")
	assert_eq(m.platform_time_s(), 0.0)
	_run(m, 2.5)
	assert_almost_eq(m.platform_time_s(), 2.5, 1e-9)
	m.tick(0.0)
	m.tick(-1.0)
	assert_almost_eq(m.platform_time_s(), 2.5, 1e-9)


func test_feed_setters_are_stored_without_side_effects() -> void:
	var m := _mock("erg")
	m.set_cadence_band(80.0, 95.0)
	m.set_phase(3)
	m.set_keyboard_enabled(true)
	assert_eq(m.command_count, 0, "feeds are not trainer commands")
	assert_eq(m.commanded_mode, Wl.OFF)
