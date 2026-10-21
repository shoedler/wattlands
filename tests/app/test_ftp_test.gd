extends "res://tests/app/app_test_base.gd"
## The FTP test page (BRIEF 3.2, P1) on the platform's FtpTest: the page starts FtpTest on the
## app's rider, which follows the rider's telemetry (a FakeRider with settable telemetry, or a
## real LocalRider on a MockTrainer). The protocol itself is tested in
## tests/core/test_ftp_test.gd; the BRIEF 7.4 accuracy gate in tests/core/integration/.

const DT := Wl.SIM_DT
const FakeSettings := preload("res://tests/app/fakes/fake_settings.gd")


func _start(ftp: float = 200.0) -> AppFtpTestScreen:
	fx.give_profile(ftp)
	var s := open_screen(AppFtpTestScreen.new()) as AppFtpTestScreen
	surge_pick(s, "start")
	return s


func _rider() -> FakeRider:
	return fx.trainer.local_rider() as FakeRider


## Ride `seconds` of fixed steps with the FakeRider's current telemetry.
func _ride(s: AppFtpTestScreen, seconds: float) -> void:
	for _i in roundi(seconds / DT):
		s.step_fixed()


func _fit_rider_tm(r: FakeRider, power: float, cadence: float = 90.0) -> void:
	r.tm.power_w = power
	r.tm.cadence_rpm = cadence
	r.tm.cadence_age_s = 0.5


func test_the_page_runs_the_platform_ftp_test() -> void:
	var s := _start(200.0)
	assert_eq(s.stage, "running")
	assert_true(s.test is FtpTest, "one implementation: the platform's FtpTest")
	var r := _rider()
	assert_same(r.plan_set, s.plan, "FtpTest gave the rider its plan")
	assert_eq(r.governor_params().get("profile"), "ramp_test", "the governor's ramp_test profile")
	assert_true(fx.trainer.is_rider_held(), "TrainerService holds the rider while the test runs")
	assert_true(fx.trainer.is_external_tick(), "the page ticks the rider, TrainerService does not")
	var ramp := s.plan.phase(0)
	assert_eq(ramp.kind, Wl.WARMUP)
	assert_eq([ramp.target_pct, ramp.ramp_to_pct, ramp.duration_s], [50.0, 65.0, 300.0])
	assert_eq([s.plan.phase(1).target_pct, s.plan.phase(2).target_pct, s.plan.phase(1).duration_s], [65.0, 71.0, 60.0])
	assert_eq(s.plan.phase(s.plan.size() - 1).kind, Wl.COOLDOWN)
	assert_true(r.setup_calls[0]["options"]["record"], "the test is a recorded ride")
	assert_eq(r.setup_calls[0]["options"]["game_id"], "ftp_test")
	assert_eq(r.phases_started, [0] as Array[int])
	assert_eq(s.big_label.text, "100 W", "the ramp-in starts at 50% of 200 W")
	assert_gte(font_size(s.big_label), AppStyle.KEY_NUMBER_MIN)


func test_trainer_max_limits_the_steps() -> void:
	var t := fx.fake_trainer()
	t.remove_child(t.dev)
	t.dev.free()
	t.dev = MockTrainer.from_spec("erg", 300.0, {"max_power_w": 600})
	t.add_child(t.dev)
	var s := _start(300.0)
	var steps := s.plan.size() - 2
	assert_eq(steps, FtpTest.step_count(300.0, 600.0))
	assert_lte(s.plan.phase(steps).target_pct * 3.0, 600.0, "the last step fits the trainer")
	assert_gt(FtpTest.step_pct(steps + 1) * 3.0, 600.0, "the next one would not")


func test_power_rule_ends_the_test_and_the_result_saves_after_10_s() -> void:
	var s := _start(200.0)
	var r := _rider()
	_fit_rider_tm(r, 210.0)
	r.tm.mode = Wl.ERG
	r.tm.applied_target_w = 200
	_ride(s, 400.0)
	assert_eq(s.stage, "running")
	r.tm.power_w = 170.0
	_ride(s, 9.9)
	assert_eq(s.stage, "running", "below 90% for less than 10 s")
	_ride(s, 0.2)
	assert_eq(s.stage, "cooldown")
	assert_eq(s.result["end_reason"], FtpTest.END_POWER)
	assert_true(s.result["valid"])
	assert_eq(s.big_label.text, "FTP 158 W", "0.75 x 210 W")
	assert_eq(menu(s).ids(), ["save", "keep", "panic"])
	r.tm.power_w = 100.0
	_ride(s, 9.5)
	assert_eq(fx.settings.profile.ftp_w, 200.0, "not before the countdown ends")
	_ride(s, 0.6)
	assert_eq(fx.settings.profile.ftp_w, 158.0)
	assert_eq(fx.settings.profile.cp_w, 158.0, "CP = FTP")
	assert_true(fx.settings.profile.ftp_verified)
	assert_gte((fx.settings as FakeSettings).profile_saves, 1)
	assert_eq(menu(s).ids(), ["end_cooldown", "panic"])


func test_cadence_rule_uses_a_fresh_cadence_and_waits_without_one() -> void:
	var s := _start(200.0)
	var r := _rider()
	_fit_rider_tm(r, 200.0, 0.0)
	r.tm.cadence_age_s = 30.0
	_ride(s, 400.0)
	assert_eq(s.stage, "running", "a trainer that reports no cadence never trips the cadence rule")
	r.tm.cadence_rpm = 40.0
	r.tm.cadence_age_s = 0.4
	_ride(s, 4.9)
	assert_eq(s.stage, "running")
	_ride(s, 0.2)
	assert_eq(s.stage, "cooldown", "a fresh (measured or estimated) cadence below 50 rpm for 5 s")
	assert_eq(s.result["end_reason"], FtpTest.END_CADENCE)


func test_rescue_ends_the_test_at_once_and_the_cooldown_follows() -> void:
	var s := _start(200.0)
	var r := _rider()
	_fit_rider_tm(r, 200.0)
	_ride(s, 300.0 + 2.0 * 60.0 + 10.0)
	r.tm.rescue = true
	s.step_fixed()
	assert_eq(s.stage, "cooldown", "rescue ends the test in the same tick")
	assert_eq(s.result["end_reason"], FtpTest.END_RESCUE)
	assert_eq(r.phases_started[r.phases_started.size() - 1], s.plan.cooldown_index(), "straight to the cool-down")
	assert_true(s.result["valid"], "two completed steps: the best minute so far counts")
	var before := r.phases_started.size()
	_ride(s, 60.0)
	assert_eq(r.phases_started.size(), before, "nothing ramps back into a step")


func test_a_stop_in_the_ramp_in_gives_no_ftp() -> void:
	var s := _start(200.0)
	var r := _rider()
	_fit_rider_tm(r, 300.0)
	_ride(s, 120.0)
	r.tm.coasting = true
	s.step_fixed()
	r.tm.coasting = false
	assert_eq(s.stage, "cooldown")
	assert_eq(s.result["end_reason"], FtpTest.END_COASTING)
	assert_false(s.result["valid"], "no completed one-minute step: no FTP to save")
	assert_eq(menu(s).ids(), ["end_cooldown", "panic"], "no countdown")
	assert_string_contains(s.detail_label.text, AppScreen.t("APP_FTP_NO_RESULT"))
	_ride(s, 181.0)
	assert_eq(s.stage, "done")
	assert_eq(fx.settings.profile.ftp_w, 200.0)
	assert_eq(r.finished_rides, 1, "the ride is saved")
	assert_false(fx.trainer.is_external_tick(), "the rider is handed back")
	assert_false(fx.trainer.is_rider_held())


func test_a_stop_in_the_first_step_gives_no_ftp_either() -> void:
	var s := _start(200.0)
	var r := _rider()
	_fit_rider_tm(r, 250.0)
	_ride(s, 300.0 + 40.0)
	r.tm.coasting = true
	s.step_fixed()
	assert_eq(s.result["steps_completed"], 0)
	assert_false(s.result["valid"])


func test_save_item_saves_at_once() -> void:
	var s := _start(200.0)
	var r := _rider()
	_fit_rider_tm(r, 240.0)
	_ride(s, 400.0)
	r.tm.coasting = true
	s.step_fixed()
	r.tm.coasting = false
	assert_eq(s.stage, "cooldown")
	confirm_pick(s, "save")
	assert_eq(fx.settings.profile.ftp_w, 180.0, "0.75 x 240 W, saved at once")
	assert_eq(menu(s).ids(), ["end_cooldown", "panic"])
	assert_string_contains(s.detail_label.text, AppScreen.t("CORE_FTP_SAVED"))


func test_cancel_gives_no_ftp() -> void:
	var s := _start(200.0)
	var r := _rider()
	_fit_rider_tm(r, 300.0)
	_ride(s, 450.0)
	confirm_pick(s, "stop")
	assert_eq(s.stage, "cooldown")
	assert_eq(s.result["end_reason"], FtpTest.END_BACK)
	assert_false(s.result["valid"])
	_ride(s, 15.0)
	assert_eq(fx.settings.profile.ftp_w, 200.0)


func test_pedal_gestures_pick_nothing_while_the_test_runs() -> void:
	var s := _start(200.0)
	var r := _rider()
	_fit_rider_tm(r, 200.0)
	_ride(s, 330.0)
	assert_false(menu(s).scanning, "the running test's menu does not scan")
	s.feed_gesture(Wl.G_SURGE)
	s.feed_gesture(Wl.G_COAST)
	assert_eq(s.stage, "running")
	assert_eq(menu(s).picks.size(), 0)
	assert_eq(r.panics, 0)


func test_end_cooldown_saves_the_ride_and_returns_to_settings() -> void:
	var s := _start(200.0)
	var r := _rider()
	_fit_rider_tm(r, 220.0)
	_ride(s, 400.0)
	r.tm.coasting = true
	s.step_fixed()
	r.tm.coasting = false
	_ride(s, 11.0)
	assert_eq(menu(s).ids(), ["end_cooldown", "panic"])
	s.feed_action(&"back")
	assert_eq(s.stage, "done", "back after the countdown ends the cool-down")
	assert_eq(r.finished_rides, 1)
	assert_eq(fx.settings.profile.ftp_w, 165.0)
	assert_false(fx.trainer.is_external_tick())
	s.feed_action(&"back")
	assert_eq(fx.app.state, "settings")


func test_leaving_mid_test_saves_the_ride_and_hands_the_rider_back() -> void:
	var s := _start(200.0)
	var r := _rider()
	_fit_rider_tm(r, 200.0)
	_ride(s, 30.0)
	s.leave()
	assert_eq(s.test.state, FtpTest.DONE)
	assert_eq(r.finished_rides, 1)
	assert_false(fx.trainer.is_external_tick())
	assert_false(fx.trainer.is_rider_held())
	assert_eq(r.governor_params().get("profile"), "normal", "the governor is back on its normal profile")
	s.leave()
	assert_eq(r.finished_rides, 1, "saved once")


## A real LocalRider on a MockTrainer whose samples carry no cadence and no speed (nothing to
## estimate from): the test runs on past the ramp-in into the steps instead of ending on the
## cadence rule after 5 s.
func test_a_trainer_without_cadence_runs_the_real_rider_through_the_steps() -> void:
	fx.give_profile(200.0)
	var t := fx.fake_trainer()
	var old: LocalRider = t.rider
	t.remove_child(old)
	old.free()
	var real := LocalRider.new()
	real.name = "LocalRider"
	t.add_child(real)
	t.rider = real
	t.dev.sample_received.connect(_strip_cadence_and_speed)
	var s := open_screen(AppFtpTestScreen.new()) as AppFtpTestScreen
	surge_pick(s, "start")
	assert_eq(s.stage, "running")
	_ride(s, 300.0 + 60.0 + 30.0)
	assert_eq(s.stage, "running", "ended early: %s" % str(s.result))
	assert_eq(s.test.state, FtpTest.STEPS)
	assert_gte(s.test.steps_completed, 1)
	var tel := real.telemetry()
	assert_eq(tel.cadence_rpm, 0.0, "no cadence reached the rider")
	assert_gt(tel.cadence_age_s, FtpTest.CADENCE_FRESH_S)
	s.leave()
	assert_ne(s.fit_path, "", "the ride was saved")


func _strip_cadence_and_speed(sample: TrainerSample) -> void:
	sample.flags &= ~(TrainerSample.HAS_CADENCE | TrainerSample.HAS_SPEED)
	sample.cadence_rpm = -1.0
	sample.speed_kmh = -1.0


func test_screen_needs_a_trainer() -> void:
	var s := AppFtpTestScreen.new()
	var services := AppServices.new()
	s.services = services
	s.auto_process = false
	add_child_autofree(s)
	s.enter({})
	s.start_test()
	assert_eq(s.stage, "error")
