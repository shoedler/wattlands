extends "res://tests/app/app_test_base.gd"
## P1 pages (BRIEF 3.2, 3.5, 3.8): the LAN room list and Recent rooms on the join page
## (pedal-scan selectable), rides history with re-upload, and the FTP test page run end to end
## with a fake rider (time from fixed steps).

const FakeLanNet := preload("res://tests/app/fakes/fake_lan_net.gd")


func _use_lan_net() -> FakeLanNet:
	var lan := FakeLanNet.new()
	fx.net.free()
	fx.net = lan
	fx.services.net = lan
	return lan


func test_lan_rooms_are_listed_and_joinable_by_pedal() -> void:
	fx.give_profile()
	var lan := _use_lan_net()
	lan.rooms = [{"code": "Q2W3E4", "name": "Ada's PC", "game_id": "workout", "address": "192.168.1.20"}]
	var s := open_screen(AppLobbyScreen.new(), {"mode": "join"}) as AppLobbyScreen
	assert_true(menu(s).ids().has("lan:Q2W3E4"))
	assert_true(menu(s).text_of("lan:Q2W3E4").contains("Q2W-3E4"))
	lan.announce([{"code": "Q2W3E4", "name": "Ada's PC"}, {"code": "ZZZ111", "name": "Bea's PC"}])
	assert_true(menu(s).ids().has("lan:ZZZ111"), "the list follows lan_rooms_changed")
	assert_true(scan_to(s, "lan:ZZZ111"))
	s.feed_gesture(Wl.G_SURGE)
	assert_eq(lan.lan_joins.size(), 1)
	assert_eq(lan.lan_joins[0]["code"], "ZZZ111")
	assert_eq(s.page, AppLobbyScreen.PAGE_CONNECTING)


func test_rides_history_reupload() -> void:
	fx.give_profile()
	fx.fake_rides().connected = true
	fx.fake_rides().ride_list = [
		{"fit_path": "C:/rides/b.fit", "summary": {"ride_id": "b", "utc_start": "2026-10-21T08:00:00Z", "game_id": "workout", "duration_s": 1680.0}, "uploaded": true, "activity_id": 5},
		{"fit_path": "C:/rides/a.fit", "summary": {"ride_id": "a", "utc_start": "2026-10-20T08:00:00Z", "game_id": "siege", "duration_s": 3300.0}, "uploaded": false},
	]
	var s := open_screen(AppRidesScreen.new()) as AppRidesScreen
	assert_eq(menu(s).ids(), [0, 1, "back"])
	assert_true(menu(s).text_of(0).contains("28:00"))
	assert_true(menu(s).text_of(0).contains(AppScreen.t("APP_RIDES_UPLOADED")))
	assert_true(scan_to(s, 0))
	s.feed_gesture(Wl.G_SURGE)
	assert_eq(fx.fake_rides().uploads.size(), 1, "re-upload of an uploaded ride")
	assert_eq(fx.fake_rides().uploads[0]["fit_path"], "C:/rides/b.fit")
	fx.bus.upload_state_changed.emit("b", "duplicate", "")
	assert_true(menu(s).text_of(0).contains(AppScreen.t("APP_UPLOAD_DUPLICATE").format([""]).strip_edges()))
	surge_pick(s, "back")
	assert_eq(fx.app.state, "settings")


func test_rides_need_strava() -> void:
	fx.give_profile()
	fx.fake_rides().ride_list = [{"fit_path": "C:/r.fit", "summary": {"ride_id": "r"}}]
	var s := open_screen(AppRidesScreen.new()) as AppRidesScreen
	assert_true(menu(s).is_disabled_id(0))
	assert_eq(s.status_label.text, AppScreen.t("APP_RESULTS_STRAVA_OFF"))


func _with_cooldown(plan: EffortPlan, _opts: Dictionary) -> EffortPlan:
	var p := plan.duplicate_plan()
	p.add(PlanValidator.cooldown_phase())
	p.cooldown_appended = true
	return p


func test_ftp_test_runs_to_a_saved_ftp() -> void:
	var prof := fx.give_profile(200.0)
	prof.ftp_verified = false
	var s := open_screen(AppFtpTestScreen.new()) as AppFtpTestScreen
	s.plan_finalizer = _with_cooldown
	surge_pick(s, "start")
	assert_eq(s.stage, "running")
	var rider := fx.trainer.local_rider() as FakeRider
	assert_eq(rider.setup_calls.size(), 1)
	assert_true(rider.setup_calls[0]["options"]["record"], "the test is a recorded ride")
	assert_not_null(rider.plan_set)
	assert_eq(rider.phases_started, [0] as Array[int])
	rider.tm.power_w = 250.0
	rider.tm.cadence_rpm = 90.0
	for _i in int(390.0 / Wl.SIM_DT):
		s.step_fixed()
	assert_eq(rider.phases_started.slice(0, 3), [0, 1, 2] as Array[int], "the first step after the 300 s ramp-in, then the second")
	assert_eq(s.stage, "running")
	rider.tm.cadence_rpm = 30.0
	for _i in int(6.0 / Wl.SIM_DT):
		s.step_fixed()
	assert_eq(s.stage, "cooldown", "cadence < 50 rpm for 5 s ends the test")
	assert_eq(s.test.end_reason, FtpTest.END_CADENCE)
	assert_eq(rider.phases_started[rider.phases_started.size() - 1], rider.plan_set.cooldown_index())
	assert_eq(menu(s).ids(), ["save", "keep", "panic"], "the 10 s save countdown runs as the cool-down starts")
	s.tick(10.5)
	assert_eq(prof.ftp_w, 188.0, "0.75 x 250 W, rounded")
	assert_true(prof.ftp_verified)
	for _i in int(171.0 / Wl.SIM_DT):
		s.step_fixed()
	assert_eq(s.stage, "done")
	assert_eq(rider.finished_rides, 1, "the ride is saved")
	assert_eq(menu(s).ids(), ["back"])
	s.feed_action(&"back")
	assert_eq(fx.app.state, "settings")


func test_ftp_test_back_keeps_the_old_ftp() -> void:
	var prof := fx.give_profile(200.0)
	var s := open_screen(AppFtpTestScreen.new()) as AppFtpTestScreen
	s.plan_finalizer = _with_cooldown
	surge_pick(s, "start")
	var rider := fx.trainer.local_rider() as FakeRider
	rider.tm.power_w = 300.0
	rider.tm.cadence_rpm = 90.0
	for _i in int(400.0 / Wl.SIM_DT):
		s.step_fixed()
	rider.tm.coasting = true
	s.step_fixed()
	assert_eq(s.test.end_reason, FtpTest.END_COASTING, "stopping pedaling ends the test")
	assert_true(s.result["valid"])
	rider.tm.coasting = false
	for _i in int(3.0 / Wl.SIM_DT):
		s.step_fixed()
	s.feed_action(&"back")
	for _i in int(181.0 / Wl.SIM_DT):
		s.step_fixed()
	assert_eq(s.stage, "done")
	assert_eq(prof.ftp_w, 200.0, "back keeps the old FTP")


func test_ftp_test_refused_plan() -> void:
	fx.give_profile()
	var s := open_screen(AppFtpTestScreen.new()) as AppFtpTestScreen
	s.plan_finalizer = func(_p: EffortPlan, _o: Dictionary) -> EffortPlan: return null
	surge_pick(s, "start")
	assert_eq(s.stage, "error")
	assert_eq(s.detail_label.text, AppScreen.t("APP_FTP_PLAN_REJECTED"))


func test_ftp_test_panic_action_goes_safe_at_once() -> void:
	fx.give_profile(200.0)
	var s := open_screen(AppFtpTestScreen.new()) as AppFtpTestScreen
	s.plan_finalizer = _with_cooldown
	surge_pick(s, "start")
	watch_signals(fx.bus)
	fx.input.inject_action(&"panic")
	assert_eq((fx.trainer.local_rider() as FakeRider).panics, 1, "the rider's governor goes safe")
	assert_signal_emitted(fx.bus, "panic_requested")
	assert_eq(s.stage, "running", "the menu did not take the action")
