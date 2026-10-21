extends GutTest
## SprintRule (BRIEF 3.5): power >= 1.2 x FTP, instantaneous or over a trailing window
## (Tank's Ram: over the last 3 s), with held_s() and best_s() (Siege: held >= 10 s).

const DT := 0.05


func test_threshold() -> void:
	var r := SprintRule.create(250.0)
	assert_eq(r.threshold_w(), 300.0)
	assert_eq(r.window_s, 0.0)
	assert_eq(SprintRule.create(200.0, 3.0).window_s, 3.0)
	assert_eq(SprintRule.FTP_FACTOR, 1.2)


func test_instantaneous_holds_at_the_threshold() -> void:
	var r := SprintRule.create(200.0)
	assert_false(r.holds(), "nothing fed")
	r.update(0.0, 239.0)
	assert_false(r.holds())
	r.update(1.0, 240.0)
	assert_true(r.holds(), ">= 1.2 x FTP, inclusive")
	assert_eq(r.current_w(), 240.0)
	r.update(2.0, 239.9)
	assert_false(r.holds())
	assert_eq(r.held_s(), 0.0, "0 when not holding")


func test_held_and_best_with_sim_steps() -> void:
	var r := SprintRule.create(200.0)
	# 300 W from t = 1.0 to t = 11.0 inclusive, fed every 0.05 s; 100 W otherwise.
	for k in 241:
		var t := k * DT
		var p := 300.0 if t >= 1.0 - 1e-9 and t <= 11.0 + 1e-9 else 100.0
		r.update(t, p)
		if is_equal_approx(t, 6.0):
			assert_true(r.holds())
			assert_almost_eq(r.held_s(), 5.05, 1e-6, "since the start of the first holding step (0.95)")
		if is_equal_approx(t, 11.0):
			assert_almost_eq(r.held_s(), 10.05, 1e-6, "Siege's >= 10 s")
	assert_false(r.holds())
	assert_eq(r.held_s(), 0.0)
	assert_almost_eq(r.best_s(), 10.05, 1e-6)


func test_held_with_1_hz_samples() -> void:
	var r := SprintRule.create(200.0)
	r.update(0.0, 100.0)
	for t in range(1, 12):
		r.update(float(t), 260.0)
	assert_eq(r.held_s(), 11.0, "each sample stands for the second before it")
	r.update(12.0, 100.0)
	assert_eq(r.held_s(), 0.0)
	assert_eq(r.best_s(), 11.0)


func test_best_keeps_the_longest_streak() -> void:
	var r := SprintRule.create(200.0)
	r.update(0.0, 100.0)
	r.update(1.0, 300.0)
	r.update(2.0, 300.0)
	r.update(3.0, 300.0)
	r.update(4.0, 100.0)
	assert_eq(r.best_s(), 3.0)
	r.update(5.0, 300.0)
	assert_eq(r.held_s(), 1.0)
	assert_eq(r.best_s(), 3.0, "a shorter streak doesn't lower it")
	for t in range(6, 11):
		r.update(float(t), 300.0)
	assert_eq(r.held_s(), 6.0)
	assert_eq(r.best_s(), 6.0)


func test_first_update_ever_covers_no_time() -> void:
	var r := SprintRule.create(200.0)
	r.update(5.0, 400.0)
	assert_true(r.holds())
	assert_eq(r.held_s(), 0.0)
	r.update(6.0, 400.0)
	assert_eq(r.held_s(), 1.0)


func test_window_needs_the_average_over_the_last_3_s() -> void:
	var r := SprintRule.create(200.0, 3.0)
	r.update(0.0, 100.0)
	r.update(1.0, 300.0)
	r.update(2.0, 300.0)
	assert_false(r.holds(), "the window isn't covered yet")
	assert_eq(r.current_w(), -1.0)
	r.update(3.0, 300.0)
	assert_true(r.holds(), "(1, 3]: 300 W")
	assert_almost_eq(r.current_w(), 300.0, 1e-9)
	r.update(4.0, 120.0)
	assert_almost_eq(r.current_w(), 240.0, 1e-9, "(300 + 300 + 120) / 3")
	assert_true(r.holds(), "exactly 1.2 x FTP")
	r.update(5.0, 100.0)
	assert_almost_eq(r.current_w(), 520.0 / 3.0, 1e-9)
	assert_false(r.holds())


func test_window_with_sim_steps() -> void:
	var r := SprintRule.create(250.0, 3.0)
	var first_hold := -1.0
	for k in 201:
		var t := k * DT
		var p := 400.0 if t >= 2.0 - 1e-9 else 150.0
		r.update(t, p)
		if first_hold < 0.0 and r.holds():
			first_hold = t
	# Average over (t - 3, t] reaches 300 W when 400 W covers 1.5 s of it ... plus 150 W x 1.5 s:
	# (400 x a + 150 x (3 - a)) / 3 >= 300 -> a >= 1.8 s; 400 W starts with the step ending at 2.0.
	assert_almost_eq(first_hold, 1.95 + 1.8, 1e-6)
	assert_true(r.holds())
	assert_almost_eq(r.current_w(), 400.0, 1e-9)


func test_window_rejects_a_short_spike() -> void:
	var r := SprintRule.create(200.0, 3.0)
	for t in 10:
		r.update(float(t), 200.0)
	r.update(10.0, 500.0)
	assert_almost_eq(r.current_w(), 300.0, 1e-9, "(200 + 200 + 500) / 3")
	assert_true(r.holds())
	var s := SprintRule.create(200.0, 3.0)
	for t in 10:
		s.update(float(t), 150.0)
	s.update(10.0, 400.0)
	assert_almost_eq(s.current_w(), 700.0 / 3.0, 1e-9)
	assert_false(s.holds(), "one 400 W second doesn't make a 3 s sprint")


func test_older_and_equal_times() -> void:
	var r := SprintRule.create(200.0)
	r.update(1.0, 300.0)
	r.update(0.5, 100.0)
	assert_true(r.holds(), "an older update is ignored")
	r.update(1.0, 100.0)
	assert_false(r.holds(), "the same t replaces the latest value")


func test_reset() -> void:
	var r := SprintRule.create(200.0, 3.0)
	for t in 10:
		r.update(float(t), 400.0)
	assert_true(r.holds())
	assert_gt(r.best_s(), 0.0)
	r.reset()
	assert_false(r.holds())
	assert_eq(r.held_s(), 0.0)
	assert_eq(r.best_s(), 0.0)
	assert_eq(r.current_w(), -1.0)
	assert_eq(r.window_s, 3.0, "configuration kept")
	assert_eq(r.ftp_w, 200.0)


func test_long_run_keeps_memory_bounded() -> void:
	var r := SprintRule.create(200.0, 3.0)
	for k in 20000:
		r.update(k * DT, 300.0)
	assert_true(r.holds())
	assert_almost_eq(r.held_s(), 19999 * DT - 3.0 + DT, 1e-6, "from the step that completed the window")
	assert_almost_eq(r.current_w(), 300.0, 1e-9)
