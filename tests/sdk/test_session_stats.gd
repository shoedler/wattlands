extends GutTest
## SessionStatsTracker, ctx.stats (BRIEF 3.6, 3.7; docs/OWNERSHIP.md CTX15, RES1, C32).

const DT := Wl.SIM_DT

var _s: SessionStatsTracker = null


func before_each() -> void:
	_s = SessionStatsTracker.new()
	_s.add_rider(1, 200.0)


func _ride(
	seconds: float,
	power: float,
	mode: String = Wl.ERG,
	target: float = 0.0,
	lo: float = 0.0,
	hi: float = 0.0,
	peer: int = 1
) -> void:
	for i in PhaseTracker.ticks(seconds):
		_s.add_sample(peer, DT, power, mode, target, lo, hi)


func test_kj_average_and_ftp_pct() -> void:
	_ride(100, 200)
	assert_almost_eq(_s.kj(1), 20.0, 1e-6)
	var row := _s.base_row(1)
	assert_almost_eq(float(row["avg_power_w"]), 200.0, 1e-6)
	assert_almost_eq(float(row["avg_ftp_pct"]), 100.0, 1e-6)
	assert_almost_eq(float(row["ride_s"]), 100.0, 1e-6)
	for k: String in [
		"kj",
		"avg_power_w",
		"avg_ftp_pct",
		"np_w",
		"best_1m_w",
		"best_5m_w",
		"best_20m_w",
		"ride_s",
		"time_in_band_s",
		"time_in_band_pct"
	]:
		assert_true(row.has(k), k)


func test_best_power_windows() -> void:
	_ride(60, 100)
	_ride(60, 300)
	_ride(240, 150)
	assert_almost_eq(_s.best_power(1, 60.0), 300.0, 1e-6)
	assert_almost_eq(_s.best_power(1, 300.0), (60 * 300 + 240 * 150) / 300.0, 1e-6)
	assert_eq(_s.best_power(1, 1200.0), 0.0, "shorter than 20 minutes")
	var row := _s.base_row(1)
	assert_almost_eq(float(row["best_1m_w"]), 300.0, 1e-6)
	assert_eq(float(row["best_20m_w"]), 0.0)


func test_normalized_power() -> void:
	_ride(600, 200)
	assert_almost_eq(_s.np_w(1), 200.0, 1e-6, "steady power: NP = average")
	var s2 := SessionStatsTracker.new()
	s2.add_rider(1, 200.0)
	for k in 10:
		for i in PhaseTracker.ticks(60):
			s2.add_sample(1, DT, 300.0 if k % 2 == 0 else 100.0, Wl.ERG, 0.0)
	assert_gt(s2.np_w(1), 200.0, "variable power: NP above the 200 W average")
	var short := SessionStatsTracker.new()
	short.add_rider(1, 200.0)
	for i in PhaseTracker.ticks(10):
		short.add_sample(1, DT, 180.0, Wl.ERG, 0.0)
	assert_almost_eq(short.np_w(1), 180.0, 1e-6, "under 30 s: the average")


func test_time_in_band_erg_and_sim() -> void:
	_ride(60, 200, Wl.ERG, 200)
	_ride(60, 211, Wl.ERG, 200)
	_ride(60, 209, Wl.ERG, 200)
	assert_almost_eq(_s.time_in_band_s(1), 120.0, 1e-6, "within +-5% of the applied target")
	_ride(60, 250, Wl.SIM, 0, 200, 260)
	_ride(60, 150, Wl.SIM, 0, 200, 260)
	_ride(60, 250, Wl.SIM, 0, 0, 0)
	var row := _s.base_row(1)
	assert_almost_eq(float(row["time_in_band_s"]), 180.0, 1e-6)
	assert_almost_eq(
		float(row["time_in_band_pct"]),
		180.0 / 300.0 * 100.0,
		1e-6,
		"SIM without a band is not counted"
	)
	assert_almost_eq(float(row["ride_s"]), 360.0, 1e-6)


func test_unknown_peer_rows_are_zero() -> void:
	var row := _s.base_row(99)
	assert_eq(float(row["kj"]), 0.0)
	assert_eq(_s.kj(99), 0.0)
	assert_eq(_s.best_power(99, 60.0), 0.0)


func test_game_results_from_stats_prefills_rows() -> void:
	_ride(120, 200, Wl.ERG, 200)
	var slot := PlayerSlot.new()
	slot.peer_id = 1
	slot.name = "Ann"
	var players: Array[PlayerSlot] = [slot]
	var r := GameResults.from_stats(_s, players)
	assert_eq(r.rows.size(), 1)
	assert_almost_eq(float(r.rows[0]["kj"]), 24.0, 1e-6)
	assert_eq(r.rows[0]["name"], "Ann")
	assert_almost_eq(float(r.rows[0]["time_in_band_pct"]), 100.0, 1e-6)
