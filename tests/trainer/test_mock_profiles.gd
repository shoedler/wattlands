extends GutTest
## MockTrainer profiles added in W1 (BRIEF 4.2; docs/OWNERSHIP.md 2.20 MR1-MR8, C30, C31):
## the grammar for intervals, noise, band, cadence_drop and surge, every parameter with
## timing assertions, precedence between components, and the surge profile firing the ERG
## surge rule (flywheel speed >= 1.12 x its 10 s average for two consecutive samples).

const FTP := 200.0
const DT := 0.05

var _samples: Array[TrainerSample] = []
var _recognizer: GestureRecognizer = null
var _recognized_surges: int = 0


func before_each() -> void:
	_samples = []


func _mock(spec: String, ftp: float = FTP, options: Dictionary = {}) -> MockTrainer:
	var m: MockTrainer = autofree(MockTrainer.from_spec(spec, ftp, options))
	m.sample_received.connect(func(s: TrainerSample) -> void: _samples.append(s))
	return m


func _run(m: MockTrainer, seconds: float) -> void:
	for i in roundi(seconds / DT):
		m.tick(DT)


## Tick until the mock's platform time reaches t.
func _run_to(m: MockTrainer, t: float) -> void:
	while m.platform_time_s() < t - 1e-6:
		m.tick(DT)


func _samples_in(t0: float, t1: float) -> Array[TrainerSample]:
	var out: Array[TrainerSample] = []
	for s in _samples:
		if s.t >= t0 and s.t <= t1:
			out.append(s)
	return out


# --- grammar --------------------------------------------------------------------------

func test_brief_and_game_brief_specs_parse() -> void:
	var specs: Array[String] = [
		"intervals:on_w=300,off_w=100,on_s=30,off_s=60,rpm=95",
		"noise:sd_w=3,sd_rpm=1",
		"band:offset_rpm=-18",
		"erg:compliance=0.85+band",
		"erg+cadence_drop:rpm=30,at_phase=4,after_s=20,for_s=30",
		"erg+cadence_drop:rpm=30,at_phase=1,at_target_pct=60,for_s=30",
		"erg+surge:every_s=60,for_s=2,lift=0.2,sim_pct=130",
		"erg+cadence_drop:rpm=40,at_s=1200",
		"erg+band:offset_rpm=-18",
		"erg+band:offset_rpm=18",
		"erg+band+cadence_drop:rpm=40,at_s=600,for_s=20",
		"erg:compliance=0.7",
		"erg+cadence_drop:rpm=30,at_phase=2,at_target_pct=60,for_s=20+cadence_drop:rpm=30,at_phase=5,at_target_pct=60,for_s=20",
		"erg+cadence_drop:rpm=30,at_target_pct=60",
		"surge",
		"erg+noise+band+surge+cadence_drop:rpm=0,at_s=0",
	]
	for spec in specs:
		assert_gt(MockTrainer.parse_spec(spec).size(), 0, spec)
	var two := MockTrainer.parse_spec(specs[12])
	assert_eq(two.size(), 3, "cadence_drop may repeat")
	assert_eq(two[1]["params"]["at_phase"], 2.0)
	assert_eq(two[2]["params"]["at_phase"], 5.0)


func test_new_profiles_reject_bad_specs() -> void:
	var bad: Array[String] = [
		"intervals:on_w=300", "intervals:off_w=100", "intervals:on_w=1,off_w=1,on_s=0",
		"cadence_drop:rpm=30", "cadence_drop:at_s=10", "cadence_drop:rpm=30,at_s=10,at_phase=2",
		"cadence_drop:rpm=30,at_s=10,after_s=5", "cadence_drop:rpm=30,at_s=10,at_target_pct=50",
		"cadence_drop:rpm=30,at_phase=1.5", "cadence_drop:rpm=-5,at_s=1", "cadence_drop:rpm=30,at_s=1,for_s=0",
		"cadence_drop:rpm=30,at_target_pct=0", "cadence_drop:rpm=30,at_target_pct=400",
		"surge:for_s=60", "surge:every_s=10,for_s=12", "surge:every_s=0", "surge:lift=3", "surge:lift=-0.1",
		"surge:sim_pct=0", "surge:sim_pct=400", "noise:sd_w=-1", "band:rpm=80", "band:offset_rpm=abc",
	]
	for spec in bad:
		assert_eq(MockTrainer.parse_spec(spec), [], "\"%s\" is invalid" % spec)
		assert_push_error("invalid profile spec", spec)


func test_describe_profiles_covers_every_profile() -> void:
	var d := MockTrainer.describe_profiles()
	assert_eq(d.keys(), MockTrainer.PROFILE_KEYS.keys())
	for pname: String in d.keys():
		var e: Dictionary = d[pname]
		assert_ne(str(e["summary"]), "", pname)
		assert_eq(e["keys"], MockTrainer.PROFILE_KEYS[pname])
		for key: String in (e["defaults"] as Dictionary).keys():
			assert_has(e["keys"], key, "%s default %s is a key" % [pname, key])
	assert_eq(d["cadence_drop"]["required"], ["rpm"])
	assert_eq(d["surge"]["defaults"], {"every_s": 60.0, "for_s": 2.0, "lift": 0.2})


func test_negative_band_offset_is_allowed() -> void:
	var comps := MockTrainer.parse_spec("band:offset_rpm=-18")
	assert_eq(comps, [{"name": "band", "params": {"offset_rpm": -18.0}}])


# --- intervals ------------------------------------------------------------------------

func test_intervals_alternate_on_and_off() -> void:
	var m := _mock("intervals:on_w=300,off_w=100,on_s=30,off_s=60,rpm=95")
	_run_to(m, 10.0)
	assert_eq(m.instantaneous_power_w(), 300.0)
	_run_to(m, 29.9)
	assert_eq(m.instantaneous_power_w(), 300.0)
	_run_to(m, 30.1)
	assert_eq(m.instantaneous_power_w(), 100.0)
	_run_to(m, 89.9)
	assert_eq(m.instantaneous_power_w(), 100.0)
	_run_to(m, 90.1)
	assert_eq(m.instantaneous_power_w(), 300.0, "the second interval starts at on_s + off_s")
	for s in _samples:
		assert_eq(s.cadence_rpm, 95.0)


func test_intervals_defaults_and_precedence() -> void:
	var m := _mock("erg+intervals:on_w=250,off_w=120")
	m.set_target_power(180)
	_run_to(m, 59.9)
	assert_eq(m.instantaneous_power_w(), 250.0, "scripted power wins over erg; on_s defaults to 60")
	_run_to(m, 60.1)
	assert_eq(m.instantaneous_power_w(), 120.0)
	_run_to(m, 120.1)
	assert_eq(m.instantaneous_power_w(), 250.0, "off_s defaults to 60")
	assert_eq(m.last_sample().cadence_rpm, 90.0, "no rpm: the preferred cadence")


func test_scripted_profiles_ignore_fatigue() -> void:
	var m := _mock("intervals:on_w=400,off_w=100,on_s=300,off_s=60")
	_run_to(m, 290.0)
	assert_true(m.is_exhausted(), "W' is still tracked")
	assert_eq(m.instantaneous_power_w(), 400.0, "but a script is a script")


# --- noise ----------------------------------------------------------------------------

func test_noise_on_power_and_cadence() -> void:
	var m := _mock("const:w=200,rpm=90+noise:sd_w=5,sd_rpm=2", FTP, {"seed": 4})
	_run(m, 600.0)
	var pw: Array[float] = []
	var cd: Array[float] = []
	for s in _samples:
		pw.append(s.power_w)
		cd.append(s.cadence_rpm)
	assert_almost_eq(_mean(pw), 200.0, 1.0)
	assert_between(_sd(pw), 4.0, 6.0)
	assert_almost_eq(_mean(cd), 90.0, 0.5)
	assert_between(_sd(cd), 1.6, 2.4)
	assert_eq(m.instantaneous_power_w(), 200.0, "the rider's true power has no noise")


func test_noise_defaults_and_not_when_stopped() -> void:
	var m := _mock("const:w=150+noise", FTP, {"seed": 9})
	_run(m, 300.0)
	var pw: Array[float] = []
	for s in _samples:
		pw.append(s.power_w)
	assert_between(_sd(pw), 4.0, 6.0, "sd_w defaults to 5")
	_samples = []
	var z := _mock("const:w=0+noise", FTP, {"seed": 9})
	_run(z, 30.0)
	for s in _samples:
		assert_eq(s.power_w, 0.0)
		assert_eq(s.cadence_rpm, 0.0)


func test_noise_is_seeded() -> void:
	var a := _sample_dicts("erg+noise", {"seed": 21}, 120.0, 200)
	var b := _sample_dicts("erg+noise", {"seed": 21}, 120.0, 200)
	var c := _sample_dicts("erg+noise", {"seed": 22}, 120.0, 200)
	assert_eq(a, b)
	assert_ne(a, c)


# --- band -----------------------------------------------------------------------------

func _band_run(offset: float, lo: float, hi: float, seed: int = 1) -> MockTrainer:
	var m := _mock("erg+band:offset_rpm=%s" % offset, FTP, {"seed": seed})
	m.set_cadence_band(lo, hi)
	m.set_target_power(150)
	_run(m, 300.0)
	return m


func test_band_offset_below_holds_outside_within_2_rpm() -> void:
	_band_run(-18.0, 80.0, 96.0)
	var after := _samples_in(10.0, 1e9)
	assert_gt(after.size(), 250)
	for s in after:
		assert_almost_eq(s.cadence_rpm, 70.0, 2.0, "t %.1f" % s.t)
		assert_lt(s.cadence_rpm, 80.0, "below the band's low edge")


func test_band_offset_above_holds_outside_within_2_rpm() -> void:
	_band_run(18.0, 80.0, 96.0, 2)
	for s in _samples_in(10.0, 1e9):
		assert_almost_eq(s.cadence_rpm, 106.0, 2.0, "t %.1f" % s.t)
		assert_gt(s.cadence_rpm, 96.0, "above the band's high edge")


func test_band_centre_with_bounded_noise() -> void:
	_band_run(0.0, 60.0, 120.0, 3)
	var distinct := {}
	for s in _samples_in(10.0, 1e9):
		assert_almost_eq(s.cadence_rpm, 90.0, 2.0)
		distinct[s.cadence_rpm] = true
	assert_gt(distinct.size(), 3, "the cadence carries noise")


func test_band_follows_changes_with_a_2_s_lag() -> void:
	var m := _mock("erg+band", FTP, {"seed": 5})
	m.set_target_power(150)
	m.set_cadence_band(80.0, 96.0)
	_run(m, 30.0)
	assert_almost_eq(m.cadence_rpm(), 88.0, 1.6)
	m.set_cadence_band(100.0, 116.0)
	_run(m, 0.5)
	assert_lt(m.cadence_rpm(), 96.0, "no jump")
	_run(m, 1.5)
	assert_almost_eq(m.cadence_rpm(), 88.0 + 20.0 * (1.0 - exp(-1.0)), 2.0, "63% after 2 s")
	_run(m, 10.0)
	assert_almost_eq(m.cadence_rpm(), 108.0, 1.6)


func test_band_without_a_published_band_uses_the_preferred_cadence() -> void:
	var m := _mock("erg+band:offset_rpm=-18", FTP, {"seed": 6, "preferred_cadence_rpm": 84.0})
	m.set_target_power(150)
	_run(m, 30.0)
	assert_almost_eq(m.cadence_rpm(), 84.0, 1.6, "offset only applies to a published band")
	m.set_cadence_band(80.0, 96.0)
	_run(m, 20.0)
	assert_almost_eq(m.cadence_rpm(), 70.0, 1.6)
	m.set_cadence_band(0.0, 0.0)
	_run(m, 20.0)
	assert_almost_eq(m.cadence_rpm(), 84.0, 1.6, "a cleared band falls back")


func test_band_is_ignored_without_the_band_profile() -> void:
	var m := _mock("erg")
	m.set_target_power(150)
	m.set_cadence_band(60.0, 70.0)
	_run(m, 20.0)
	assert_eq(m.last_sample().cadence_rpm, 90.0)


# --- cadence_drop ---------------------------------------------------------------------

func test_cadence_drop_at_s_for_s() -> void:
	var m := _mock("erg+cadence_drop:rpm=40,at_s=30,for_s=20")
	m.set_target_power(150)
	_run_to(m, 29.9)
	assert_eq(m.cadence_rpm(), 90.0)
	assert_false(m.cadence_drop_active())
	_run_to(m, 30.05)
	assert_eq(m.cadence_rpm(), 40.0)
	assert_true(m.cadence_drop_active())
	_run_to(m, 49.9)
	assert_eq(m.cadence_rpm(), 40.0)
	assert_almost_eq(m.instantaneous_power_w(), 150.0, 1.0, "power holds through the drop (ERG)")
	_run_to(m, 50.05)
	assert_eq(m.cadence_rpm(), 90.0)
	for s in _samples_in(30.1, 49.9):
		assert_eq(s.cadence_rpm, 40.0)


func test_cadence_drop_lasts_the_rest_of_the_run_by_default() -> void:
	var m := _mock("erg+cadence_drop:rpm=40,at_s=10")
	m.set_target_power(150)
	_run_to(m, 600.0)
	assert_eq(m.cadence_rpm(), 40.0)


func test_cadence_drop_at_phase_after_s() -> void:
	var m := _mock("erg+cadence_drop:rpm=30,at_phase=4,after_s=20,for_s=30")
	m.set_target_power(150)
	m.set_phase(3)
	_run_to(m, 50.0)
	m.set_phase(4)
	_run_to(m, 69.9)
	assert_eq(m.cadence_rpm(), 90.0, "after_s counts from entering the phase")
	_run_to(m, 70.05)
	assert_eq(m.cadence_rpm(), 30.0)
	_run_to(m, 99.9)
	assert_eq(m.cadence_rpm(), 30.0)
	_run_to(m, 100.05)
	assert_eq(m.cadence_rpm(), 90.0)
	m.set_phase(5)
	m.set_phase(4)
	_run_to(m, 200.0)
	assert_eq(m.cadence_rpm(), 90.0, "each drop fires once")


func test_cadence_drop_at_phase_rearms_when_the_phase_ends_early() -> void:
	var m := _mock("erg+cadence_drop:rpm=30,at_phase=2,after_s=20,for_s=10")
	m.set_target_power(150)
	m.set_phase(2)
	_run_to(m, 10.0)
	m.set_phase(3)
	_run_to(m, 30.0)
	assert_eq(m.cadence_rpm(), 90.0, "never in another phase")
	m.set_phase(2)
	_run_to(m, 49.9)
	assert_eq(m.cadence_rpm(), 90.0)
	_run_to(m, 50.05)
	assert_eq(m.cadence_rpm(), 30.0, "20 s after re-entering phase 2")
	m.set_phase(2)
	_run_to(m, 55.0)
	assert_eq(m.cadence_rpm(), 30.0, "re-sending the same phase changes nothing")


func test_cadence_drop_waits_for_at_target_pct() -> void:
	var m := _mock("erg+cadence_drop:rpm=30,at_phase=1,at_target_pct=60,for_s=30")
	m.set_phase(1)
	m.set_target_power(100)
	_run_to(m, 40.0)
	assert_eq(m.cadence_rpm(), 90.0, "50% FTP: still waiting")
	m.set_target_power(110)
	_run_to(m, 41.0)
	m.set_target_power(119)
	_run_to(m, 42.0)
	assert_eq(m.cadence_rpm(), 90.0, "119 W is below 60% of 200 W")
	m.set_target_power(120)
	_run_to(m, 42.05)
	assert_eq(m.cadence_rpm(), 30.0, "starts once the applied target reaches 60%")
	_run_to(m, 71.95)
	assert_eq(m.cadence_rpm(), 30.0)
	_run_to(m, 72.1)
	assert_eq(m.cadence_rpm(), 90.0, "for_s 30")


func test_at_target_pct_counts_after_s_and_respects_the_phase() -> void:
	var m := _mock("erg+cadence_drop:rpm=30,at_phase=1,at_target_pct=60,after_s=10,for_s=5")
	m.set_phase(0)
	m.set_target_power(150)
	_run_to(m, 20.0)
	assert_eq(m.cadence_rpm(), 90.0, "the target is high, but in phase 0")
	m.set_phase(1)
	_run_to(m, 29.9)
	assert_eq(m.cadence_rpm(), 90.0, "after_s counts from the moment the target qualified")
	_run_to(m, 30.05)
	assert_eq(m.cadence_rpm(), 30.0)
	_run_to(m, 35.1)
	assert_eq(m.cadence_rpm(), 90.0)


func test_at_target_pct_ignores_sim_and_uses_the_applied_target() -> void:
	var m := _mock("erg+cadence_drop:rpm=30,at_target_pct=60,for_s=5")
	m.set_target_power(150)
	m.set_simulation(0.0, 0.0, 0.004, 0.51)
	_run_to(m, 20.0)
	assert_eq(m.cadence_rpm(), 90.0, "a SIM block is not an ERG target")
	m.set_target_power(102)
	_run_to(m, 30.0)
	assert_eq(m.cadence_rpm(), 90.0, "an unverified 60% (x0.85 = 102 W) never reaches 60% of FTP")
	m.set_target_power(130)
	_run_to(m, 30.1)
	assert_eq(m.cadence_rpm(), 30.0)


func test_two_drops_are_independent_and_the_lowest_wins() -> void:
	var m := _mock("erg+cadence_drop:rpm=30,at_s=10,for_s=5+cadence_drop:rpm=50,at_s=30,for_s=10+cadence_drop:rpm=60,at_s=32,for_s=2")
	m.set_target_power(150)
	_run_to(m, 12.0)
	assert_eq(m.cadence_rpm(), 30.0)
	_run_to(m, 20.0)
	assert_eq(m.cadence_rpm(), 90.0)
	_run_to(m, 31.0)
	assert_eq(m.cadence_rpm(), 50.0)
	_run_to(m, 33.0)
	assert_eq(m.cadence_rpm(), 50.0, "overlapping drops: the lowest rpm")
	_run_to(m, 41.0)
	assert_eq(m.cadence_rpm(), 90.0)


func test_cadence_drop_to_zero_stops_the_rider() -> void:
	var m := _mock("erg+cadence_drop:rpm=0,at_s=10,for_s=10")
	m.set_target_power(150)
	_run_to(m, 15.0)
	assert_eq(m.instantaneous_power_w(), 0.0)
	assert_eq(m.last_sample().cadence_rpm, 0.0)
	assert_eq(m.last_sample().power_w, 0.0)
	_run_to(m, 35.0)
	assert_almost_eq(m.instantaneous_power_w(), 150.0, 2.0, "rides again after for_s")
	assert_eq(m.cadence_rpm(), 90.0)


func test_cadence_drop_wins_over_surge_and_band() -> void:
	var m := _mock("erg+band+surge:every_s=20,for_s=2+cadence_drop:rpm=40,at_s=15", FTP, {"seed": 2})
	m.set_target_power(150)
	_run_to(m, 20.5)
	assert_true(m.surging())
	assert_eq(m.cadence_rpm(), 40.0)


# --- surge ----------------------------------------------------------------------------

func test_surge_for_s_sets_how_long_the_lift_lasts() -> void:
	var m := _mock("erg+surge:every_s=30,for_s=5,lift=0.25", FTP, {"seed": 5})
	m.set_target_power(160)
	for k in range(1, 5):
		var start := 30.0 * k
		_run_to(m, start - 0.1)
		assert_false(m.surging(), "surge %d not yet" % k)
		_run_to(m, start + 4.9)
		assert_true(m.surging(), "surge %d still on just before for_s" % k)
		assert_almost_eq(m.cadence_rpm(), 112.5, 1e-6, "lift 0.25")
		_run_to(m, start + 5.0 + MockTrainer.SAMPLE_MAX_S + 0.1)
		assert_false(m.surging(), "surge %d over after for_s (it had its two notifications)" % k)
	var lifted := 0
	for s in _samples:
		if s.cadence_rpm > 100.0:
			lifted += 1
			assert_between(fmod(s.t, 30.0), 0.0, 5.0 + MockTrainer.SAMPLE_MAX_S, "only inside a surge (t %.2f)" % s.t)
	assert_between(lifted, 4 * 4, 4 * 6, "about five notifications per 5 s surge")


func test_surge_lifts_cadence_and_speed_every_every_s() -> void:
	var m := _mock("erg+surge:every_s=60,for_s=2,lift=0.2", FTP, {"seed": 7})
	m.set_target_power(200)
	_run_to(m, 59.9)
	assert_false(m.surging())
	_run_to(m, 60.05)
	assert_true(m.surging(), "the first surge starts at every_s")
	assert_almost_eq(m.cadence_rpm(), 108.0, 1e-6)
	assert_almost_eq(m.speed_kmh(), 43.2, 1e-6, "flywheel speed x 1.2")
	assert_almost_eq(m.instantaneous_power_w(), 200.0, 0.5, "ERG holds power")
	_run_to(m, 650.0)
	var lifted := {}
	for s in _samples:
		var k := floori((s.t + 0.001) / 60.0)
		if s.speed_kmh > 40.0:
			lifted[k] = int(lifted.get(k, 0)) + 1
			assert_eq(s.cadence_rpm, 108.0)
			assert_almost_eq(s.speed_kmh, 43.2, 0.011)
		else:
			assert_almost_eq(s.speed_kmh, 36.0, 0.011)
	assert_eq(lifted.size(), 10, "ten surges in 650 s")
	for k: int in lifted.keys():
		assert_between(int(lifted[k]), 2, 3, "surge %d carried by 2-3 notifications" % k)


func test_every_surge_spans_two_notifications_even_when_short() -> void:
	for seed in [1, 2, 3, 4, 5, 6]:
		_samples = []
		var m := _mock("erg+surge:every_s=20,for_s=0.5,lift=0.3", FTP, {"seed": seed})
		m.set_target_power(180)
		_run(m, 205.0)
		var per := {}
		for s in _samples:
			if s.cadence_rpm > 100.0:
				var k := floori((s.t + 0.001) / 20.0)
				per[k] = int(per.get(k, 0)) + 1
		assert_eq(per.size(), 10, "seed %d" % seed)
		for k: int in per.keys():
			assert_eq(int(per[k]), MockTrainer.SURGE_MIN_SAMPLES, "seed %d surge %d" % [seed, k])


## Reference for the ERG surge rule (BRIEF 3.5): flywheel speed >= 1.12 x the mean of the
## previous 10 s of samples on two consecutive samples; fires once per stretch.
func _speed_rule_fires(samples: Array[TrainerSample]) -> Array[float]:
	var fires: Array[float] = []
	var prev := false
	var fired := false
	for i in samples.size():
		var s := samples[i]
		var sum := 0.0
		var n := 0
		for j in range(i - 1, -1, -1):
			if samples[j].t < s.t - 10.0:
				break
			sum += samples[j].speed_kmh
			n += 1
		var cond := n >= 5 and s.speed_kmh >= 1.12 * sum / n
		if cond and prev and not fired:
			fires.append(s.t)
			fired = true
		if not cond:
			fired = false
		prev = cond
	return fires


func test_ten_surges_fire_the_speed_rule_ten_times() -> void:
	for seed in [1, 2, 3, 11, 12]:
		for dropouts: bool in [false, true]:
			_samples = []
			var m := _mock("erg+surge:every_s=60,for_s=2,lift=0.2", FTP, {"seed": seed, "dropouts": dropouts})
			m.set_target_power(200)
			_run(m, 650.0)
			var fires := _speed_rule_fires(_samples)
			assert_eq(fires.size(), 10, "seed %d dropouts %s" % [seed, dropouts])
			for t in fires:
				var into := fmod(t, 60.0)
				assert_lt(into, 4.0, "fires right after a surge starts (t %.2f)" % t)


func test_surge_fires_the_real_gesture_recognizer() -> void:
	for seed in [3, 11]:
		for dropouts: bool in [false, true]:
			var m := _mock("erg+surge:every_s=60,for_s=2,lift=0.2", FTP, {"seed": seed, "dropouts": dropouts})
			m.set_target_power(200)
			_recognizer = GestureRecognizer.new()
			_recognizer.configure(FTP, true)
			_recognizer.set_erg(true)
			_recognized_surges = 0
			m.sample_received.connect(_feed_recognizer)
			_run(m, 650.0)
			assert_eq(_recognized_surges, 10,
				"the test fires 10 surges and expects 10 gestures (C30; seed %d, dropouts %s)" % [seed, dropouts])


func _feed_recognizer(s: TrainerSample) -> void:
	if _recognizer.on_sample(s).has(Wl.G_SURGE):
		_recognized_surges += 1




func test_surge_sim_pct_rides_n_pct_ftp_in_sim() -> void:
	var m := _mock("erg+surge:every_s=60,for_s=2,lift=0.2,sim_pct=130")
	m.set_target_power(150)
	_run(m, 20.0)
	assert_almost_eq(m.instantaneous_power_w(), 150.0, 1.0, "ERG: the target")
	m.set_simulation(0.0, 0.0, 0.004, 0.51)
	m.set_power_band(150.0, 170.0)
	_run(m, 15.0)
	assert_almost_eq(m.instantaneous_power_w(), 260.0, 2.0, "SIM: 130% FTP, overriding erg's band rule")
	assert_almost_eq(m.last_sample().power_w, 260.0, 2.0)
	m.set_target_power(150)
	_run(m, 15.0)
	assert_almost_eq(m.instantaneous_power_w(), 150.0, 1.0, "back in ERG")


func test_surge_lifts_reported_speed_in_sim() -> void:
	var m := _mock("erg+surge:every_s=60,for_s=2,lift=0.2,sim_pct=100", FTP, {"seed": 4})
	m.set_simulation(0.0, 0.0, 0.004, 0.51)
	_run_to(m, 59.9)
	var base := m.speed_kmh()
	_run_to(m, 60.05)
	assert_true(m.surging())
	assert_almost_eq(m.speed_kmh(), base * 1.2, 0.2)
	assert_almost_eq(m.cadence_rpm(), 108.0, 1e-6)


func test_power_precedence_scripted_over_sim_pct() -> void:
	var c := _mock("const:w=150+surge:sim_pct=130")
	c.set_simulation(0.0, 0.0, 0.004, 0.51)
	_run(c, 10.0)
	assert_eq(c.instantaneous_power_w(), 150.0, "const > surge sim_pct")
	var z := _mock("zero+surge:sim_pct=130")
	z.set_simulation(0.0, 0.0, 0.004, 0.51)
	_run(z, 10.0)
	assert_eq(z.instantaneous_power_w(), 0.0, "zero > surge sim_pct")
	var e := _mock("surge:sim_pct=120+erg:compliance=0.5")
	e.set_simulation(0.0, 0.0, 0.004, 0.51)
	_run(e, 20.0)
	assert_almost_eq(e.instantaneous_power_w(), 240.0, 2.0, "sim_pct > erg, without compliance")


func test_independent_surges() -> void:
	var m := _mock("erg+surge:every_s=60+surge:every_s=45,lift=0.3", FTP, {"seed": 8})
	m.set_target_power(150)
	_run_to(m, 45.05)
	assert_almost_eq(m.cadence_rpm(), 117.0, 1e-6, "the 45 s surge, lift 0.3")
	_run_to(m, 60.05)
	assert_almost_eq(m.cadence_rpm(), 108.0, 1e-6, "the 60 s surge, lift 0.2")


# --- zero and erg ---------------------------------------------------------------------

func test_zero_is_zero_from_the_start() -> void:
	var m := _mock("zero+surge:every_s=10+band")
	m.set_cadence_band(80.0, 90.0)
	m.set_target_power(150)
	_run(m, 60.0)
	assert_gt(_samples.size(), 50)
	for s in _samples:
		assert_eq(s.power_w, 0.0)
		assert_eq(s.cadence_rpm, 0.0)


func test_erg_compliance_in_sim_and_erg() -> void:
	var m := _mock("erg:compliance=0.7")
	m.set_target_power(200)
	_run(m, 20.0)
	assert_almost_eq(m.instantaneous_power_w(), 140.0, 1.0)
	m.set_simulation(0.0, 1.0, 0.004, 0.51)
	_run(m, 20.0)
	assert_almost_eq(m.instantaneous_power_w(), 180.0, 1.0, "SIM without a band: 90% FTP")
	m.set_power_band(152.0, 210.0)
	_run(m, 20.0)
	assert_almost_eq(m.instantaneous_power_w(), 0.7 * 181.0, 1.0, "compliance x the band centre")


# --- profile time ---------------------------------------------------------------------

func test_restart_profile_restarts_at_s_surges_and_scripts() -> void:
	var m := _mock("erg+surge:every_s=60,for_s=2+cadence_drop:rpm=40,at_s=30,for_s=10", FTP, {"seed": 3})
	m.set_target_power(150)
	_run_to(m, 35.0)
	assert_true(m.cadence_drop_active(), "menu time: the drop already fired")
	_run_to(m, 100.0)
	m.restart_profile()
	assert_almost_eq(m.profile_time_s(), 0.0, 1e-9)
	assert_almost_eq(m.platform_time_s(), 100.0, 1e-6, "platform time carries on")
	assert_false(m.surging())
	_run_to(m, 129.9)
	assert_false(m.cadence_drop_active(), "the drop re-armed: at_s counts from the restart")
	assert_false(m.surging(), "the 120 s surge of the old schedule is gone")
	_run_to(m, 130.05)
	assert_true(m.cadence_drop_active(), "at_s = 30 after the restart")
	_run_to(m, 159.9)
	assert_false(m.surging())
	_run_to(m, 160.05)
	assert_true(m.surging(), "the first surge is every_s after the restart")
	assert_almost_eq(m.instantaneous_power_w(), 150.0, 1.0, "the rider carried on")
	for i in range(1, _samples.size()):
		assert_lt(_samples[i].t - _samples[i - 1].t, MockTrainer.SAMPLE_MAX_S + DT + 1e-6, "no gap in notifications")
	var r := _mock("ramp:from_w=100,to_w=200,over_s=100")
	_run_to(r, 150.0)
	assert_eq(r.instantaneous_power_w(), 200.0)
	r.restart_profile()
	_run_to(r, 200.0)
	assert_almost_eq(r.instantaneous_power_w(), 150.0, 1e-6, "the ramp starts again")


# --- helpers --------------------------------------------------------------------------

func _sample_dicts(spec: String, options: Dictionary, seconds: float, target: int) -> Array:
	_samples = []
	var m := _mock(spec, FTP, options)
	m.set_target_power(target)
	_run(m, seconds)
	var out: Array = []
	for s in _samples:
		out.append(s.to_dict())
	return out


func _mean(xs: Array[float]) -> float:
	var t := 0.0
	for x in xs:
		t += x
	return t / maxf(xs.size(), 1)


func _sd(xs: Array[float]) -> float:
	var m := _mean(xs)
	var t := 0.0
	for x in xs:
		t += (x - m) * (x - m)
	return sqrt(t / maxf(xs.size() - 1, 1))
