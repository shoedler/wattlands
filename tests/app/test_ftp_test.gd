extends GutTest
## The FTP test protocol (BRIEF 3.2, P1): ramp-in, 60 s steps rising by 6% of FTP, the end rules
## (power < 90% of target for 10 s, cadence < 50 rpm for 5 s, coast, rescue) and FTP = 0.75 x
## the best 1-minute power. Time comes from the samples.


func test_plan_shape() -> void:
	var t := AppFtpTest.create(200.0, 1800.0)
	var plan := t.build_plan()
	var ramp := plan.phase(0)
	assert_eq(ramp.kind, Wl.WARMUP)
	assert_eq(ramp.target_pct, 50.0)
	assert_eq(ramp.ramp_to_pct, 65.0)
	assert_eq(ramp.duration_s, 300.0)
	assert_eq(plan.phase(1).target_pct, 65.0)
	assert_eq(plan.phase(2).target_pct, 71.0)
	assert_eq(plan.phase(1).duration_s, 60.0)
	assert_true(plan.phase(1).lap)
	for i in range(1, plan.size()):
		assert_eq(plan.phase(i).mode, Wl.ERG)
		assert_lte(t.ftp_w * plan.phase(i).target_pct / 100.0, 1000.0, "every step within 1000 W")
	assert_eq(t.step_count(), plan.size() - 1)


func test_trainer_max_limits_the_steps() -> void:
	var t := AppFtpTest.create(300.0, 600.0)
	assert_lte(t.step_target_w(t.step_count() - 1), 600.0)
	assert_gt(t.step_target_w(t.step_count()), 600.0)


func test_power_rule_and_result() -> void:
	var t := AppFtpTest.create(200.0)
	var time := 0.0
	# 2 minutes holding 300 W against a 280 W target.
	while time < 120.0:
		assert_eq(t.feed(time, 300.0, 90.0, 280.0, false), "")
		time += 1.0
	assert_almost_eq(t.best_1m_w, 300.0, 1e-6)
	# Then 240 W against 280 W (< 90%): ends after 10 s.
	var ended := ""
	var start := time
	while ended == "" and time < start + 20.0:
		ended = t.feed(time, 240.0, 90.0, 280.0, false)
		time += 1.0
	assert_eq(ended, AppFtpTest.END_POWER)
	assert_almost_eq(t.end_t, start + 10.0, 1e-6)
	assert_eq(t.result_ftp_w(), 225.0, "0.75 x 300")


func test_cadence_rule() -> void:
	var t := AppFtpTest.create(200.0)
	for s in 30:
		t.feed(float(s), 200.0, 85.0, 200.0, false)
	var ended := ""
	var s2 := 30
	while ended == "" and s2 < 50:
		ended = t.feed(float(s2), 200.0, 40.0, 200.0, false)
		s2 += 1
	assert_eq(ended, AppFtpTest.END_CADENCE)
	assert_eq(t.end_t, 35.0)


func test_rescue_and_coast_end_it_at_once() -> void:
	var t := AppFtpTest.create(200.0)
	t.feed(0.0, 200.0, 85.0, 200.0, false)
	assert_eq(t.feed(1.0, 100.0, 85.0, 100.0, true), AppFtpTest.END_RESCUE)
	assert_eq(t.feed(2.0, 300.0, 85.0, 200.0, false), "", "nothing after the end")
	var t2 := AppFtpTest.create(200.0)
	assert_eq(t2.on_coast(5.0), AppFtpTest.END_COAST)
	assert_eq(t2.on_coast(6.0), "")


func test_no_result_before_a_full_minute() -> void:
	var t := AppFtpTest.create(200.0)
	for s in 30:
		t.feed(float(s), 400.0, 90.0, 0.0, false)
	assert_eq(t.result_ftp_w(), 0.0)


func test_screen_needs_a_trainer() -> void:
	var s := AppFtpTestScreen.new()
	var services := AppServices.new()
	s.services = services
	s.auto_process = false
	add_child_autofree(s)
	s.enter({})
	s.start_test()
	assert_eq(s.stage, "error")
