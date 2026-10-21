extends GutTest
## WorkoutPowerStats: kJ, average and normalized power, best 1/5/20-minute power from
## per-step telemetry (1 Hz samples).

const DT := 0.05


func _feed(stats: WorkoutPowerStats, power: float, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		stats.add(power, DT)


func test_constant_power() -> void:
	var s := WorkoutPowerStats.new()
	_feed(s, 200.0, 1500.0)
	assert_almost_eq(s.kj, 300.0, 0.001, "200 W for 1500 s = 300 kJ")
	assert_almost_eq(s.avg_power_w(), 200.0, 0.001)
	assert_almost_eq(s.np_w(), 200.0, 0.001)
	assert_eq(s.samples.size(), 1500)
	assert_almost_eq(s.best_w(60), 200.0, 0.001)
	assert_almost_eq(s.best_w(300), 200.0, 0.001)
	assert_almost_eq(s.best_w(1200), 200.0, 0.001)


func test_short_rides_report_no_long_bests() -> void:
	var s := WorkoutPowerStats.new()
	_feed(s, 150.0, 120.0)
	assert_almost_eq(s.best_w(60), 150.0, 0.001)
	assert_eq(s.best_w(300), 0.0)
	assert_eq(s.best_w(1200), 0.0)
	var tiny := WorkoutPowerStats.new()
	_feed(tiny, 100.0, 10.0)
	assert_almost_eq(tiny.np_w(), 100.0, 0.001, "rides under 30 s report average power")


func test_bests_find_the_hardest_window() -> void:
	var s := WorkoutPowerStats.new()
	_feed(s, 100.0, 600.0)
	_feed(s, 300.0, 60.0)
	_feed(s, 100.0, 600.0)
	assert_almost_eq(s.best_w(60), 300.0, 0.001)
	assert_almost_eq(s.best_w(300), (300.0 * 60.0 + 100.0 * 240.0) / 300.0, 0.001)


func test_normalized_power_weights_surges() -> void:
	var s := WorkoutPowerStats.new()
	for i in 20:
		_feed(s, 300.0, 30.0)
		_feed(s, 100.0, 30.0)
	assert_almost_eq(s.avg_power_w(), 200.0, 0.01)
	assert_gt(s.np_w(), s.avg_power_w(), "NP above average for a surging ride")
	assert_lt(s.np_w(), 300.0)


func test_negative_power_counts_as_zero() -> void:
	var s := WorkoutPowerStats.new()
	_feed(s, -50.0, 10.0)
	assert_eq(s.kj, 0.0)


func test_row_values() -> void:
	var s := WorkoutPowerStats.new()
	_feed(s, 150.0, 400.0)
	var row := s.row_values(200.0)
	assert_almost_eq(float(row["avg_ftp_pct"]), 75.0, 0.001)
	assert_almost_eq(float(row["kj"]), 60.0, 0.001)
	assert_almost_eq(float(row["ride_s"]), 400.0, 0.001)
	assert_almost_eq(float(row["best_5m_w"]), 150.0, 0.001)
	assert_eq(float(row["best_20m_w"]), 0.0)
