extends GutTest
## Bots (BRIEF 3.6, 4.2): negative peer ids, "Bot n" names, verified lobby FTP, Autopilot,
## the slot's session look and MockTrainer's erg profile at compliance 1.0 with its `band`
## cadence policy: a bot follows a published cadence band's centre after a 2 s lag (seeded
## noise within +-1.5 rpm) and pedals its preferred 90 rpm without one (BRIEF 3.6
## cadence_band).

const DT := 0.05
## The bot slot's preferred cadence (Bots.make_slot) and MockTrainer's band noise bound.
const PREFERRED_RPM := 90.0
const NOISE_RPM := 1.5

var _samples: Array[TrainerSample] = []


func before_each() -> void:
	_samples = []


## A bot's MockTrainer as the app's SessionLauncher builds it (spec, bot FTP and a seed;
## the preferred cadence is MockTrainer's default) riding an ERG target of 150 W.
func _bot_mock(rng_seed: int) -> MockTrainer:
	var m: MockTrainer = autofree(MockTrainer.from_spec(Bots.RIDER_SPEC, 200.0, {"seed": rng_seed}))
	m.sample_received.connect(func(s: TrainerSample) -> void: _samples.append(s))
	m.set_target_power(150)
	return m


func _run(m: MockTrainer, seconds: float) -> void:
	for i in roundi(seconds / DT):
		m.tick(DT)


func _cadences_in(t0: float, t1: float) -> Array[float]:
	var out: Array[float] = []
	for s in _samples:
		if s.t >= t0 and s.t <= t1:
			out.append(s.cadence_rpm)
	return out


func test_peer_ids_are_negative() -> void:
	assert_eq(Bots.peer_id(1), -1)
	assert_eq(Bots.peer_id(3), -3)
	assert_eq(Bots.peer_id(-2), -2, "already negative stays negative")
	for n in range(1, 8):
		assert_lt(Bots.peer_id(n), 0)


func test_make_slot() -> void:
	var s := Bots.make_slot(2, 5, 230.0)
	assert_eq(s.peer_id, -2)
	assert_eq(s.name, "Bot 2")
	assert_eq(s.slot_index, 5)
	assert_true(s.is_bot)
	assert_true(s.autopilot)
	assert_eq(s.ftp, 230.0)
	assert_true(s.ftp_verified)
	assert_eq(s.scaling_mode, Wl.FAIR_FTP)
	assert_almost_eq(s.p_eff_per_w, 250.0 / 230.0, 1e-9)
	assert_eq(s.rider_mass_kg, 75.0)
	assert_eq(s.preferred_cadence_rpm, 90.0)
	assert_true(s.haptics_on)


func test_make_slot_look_matches_the_slot() -> void:
	for i in Wl.MAX_SLOTS:
		var s := Bots.make_slot(i + 1, i, 200.0)
		var look := Wl.slot_look(i)
		assert_eq(s.color, look["color"], "slot %d color" % i)
		assert_eq(s.shape, look["shape"], "slot %d shape" % i)
		assert_eq(s.pattern, look["pattern"], "slot %d pattern" % i)
		assert_eq(s.hollow, look["hollow"], "slot %d hollow" % i)
		assert_eq(s.hollow, i >= 4)


func test_make_slot_scaling_modes() -> void:
	assert_almost_eq(Bots.make_slot(1, 0, 200.0, Wl.WKG).p_eff_per_w, 1.0, 1e-9, "75 / 75 kg")
	assert_eq(Bots.make_slot(1, 0, 200.0, Wl.RAW).p_eff_per_w, 1.0)
	assert_eq(Bots.make_slot(1, 0, 200.0, Wl.RAW).scaling_mode, Wl.RAW)
	assert_eq(Bots.make_slot(1, 0, 200.0, Wl.RAW).rider_mass_kg, 75.0)


func test_make_profile() -> void:
	var p := Bots.make_profile(3, 180.0)
	assert_eq(p.display_name, "Bot 3")
	assert_eq(p.ftp_w, 180.0)
	assert_true(p.ftp_verified)
	assert_eq(p.cp_w, 180.0)
	assert_eq(p.wprime_j, 20000.0)
	assert_true(p.created)


func test_rider_spec_is_a_valid_mock_profile() -> void:
	assert_eq(Bots.RIDER_SPEC, "erg:compliance=1.0+band")
	var comps := MockTrainer.parse_spec(Bots.RIDER_SPEC)
	assert_eq(comps.size(), 2)
	assert_eq(comps[0]["name"], "erg")
	assert_eq(float(comps[0]["params"]["compliance"]), 1.0)
	assert_eq(comps[1], {"name": "band", "params": {}}, "band at offset 0: the band's centre")
	assert_eq(Bots.make_slot(1, 0, 200.0).preferred_cadence_rpm, PREFERRED_RPM)
	assert_eq(MockTrainer.DEFAULT_CADENCE_RPM, PREFERRED_RPM, "the mock's default matches")
	assert_eq(MockTrainer.BAND_LAG_S, 2.0)
	assert_eq(MockTrainer.BAND_NOISE_MAX_RPM, NOISE_RPM)
	assert_push_error_count(0)


func test_a_bot_pedals_its_preferred_cadence_without_a_band() -> void:
	var m := _bot_mock(11)
	_run(m, 60.0)
	var c := _cadences_in(0.0, 60.0)
	assert_gt(c.size(), 50)
	for v in c:
		assert_between(v, PREFERRED_RPM - NOISE_RPM, PREFERRED_RPM + NOISE_RPM)
	assert_almost_eq(m.instantaneous_power_w(), 150.0, 2.0, "still the erg follower at 1.0")


func test_a_bot_follows_a_published_100_120_band() -> void:
	var m := _bot_mock(12)
	_run(m, 20.0)
	var t_pub := m.platform_time_s()
	m.set_cadence_band(100.0, 120.0)
	_run(m, 0.5)
	assert_lt(m.cadence_rpm(), 100.0, "no jump: the band is reached through the 2 s lag")
	_run(m, 1.5)
	assert_almost_eq(
		m.cadence_rpm(),
		PREFERRED_RPM + 20.0 * (1.0 - exp(-1.0)),
		NOISE_RPM + 0.05,
		"63% of the 90 -> 110 rpm step after 2 s"
	)
	_run(m, 58.0)
	# 6 s after the band: at most 20 * e^-3 = 1.0 rpm of lag left, plus the noise bound.
	var inside := _cadences_in(t_pub + 6.0, t_pub + 60.0)
	assert_gt(inside.size(), 50)
	for v in inside:
		assert_between(v, 100.0, 120.0, "inside the published band")
		assert_almost_eq(v, 110.0, 1.0 + NOISE_RPM, "the band's centre")
	for v in _cadences_in(t_pub + 12.0, t_pub + 60.0):
		assert_almost_eq(v, 110.0, NOISE_RPM + 0.05, "settled on the centre, noise only")
	assert_almost_eq(m.instantaneous_power_w(), 150.0, 2.0, "a band never changes the load")


func test_a_cleared_band_returns_a_bot_to_its_preferred_cadence() -> void:
	var m := _bot_mock(13)
	m.set_cadence_band(100.0, 120.0)
	_run(m, 30.0)
	assert_almost_eq(m.cadence_rpm(), 110.0, NOISE_RPM + 0.05)
	var t_clear := m.platform_time_s()
	m.set_cadence_band(0.0, 0.0)
	_run(m, 40.0)
	# 12 s after clearing: 20 * e^-6 = 0.05 rpm of lag left.
	var back := _cadences_in(t_clear + 12.0, t_clear + 40.0)
	assert_gt(back.size(), 20)
	for v in back:
		assert_almost_eq(v, PREFERRED_RPM, NOISE_RPM + 0.05, "the preferred cadence again")


func test_a_bots_band_noise_is_seeded() -> void:
	var runs: Array = []
	for rng_seed: int in [21, 21, 22]:
		_samples = []
		var m := _bot_mock(rng_seed)
		m.set_cadence_band(100.0, 120.0)
		_run(m, 30.0)
		runs.append(_cadences_in(0.0, 30.0))
	assert_eq(runs[0], runs[1], "the same seed gives the same cadence")
	assert_ne(runs[0], runs[2], "another seed, other noise")
