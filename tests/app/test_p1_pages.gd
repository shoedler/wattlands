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
	lan.rooms = [
		{"code": "Q2W3E4", "name": "Ada's PC", "game_id": "workout", "address": "192.168.1.20"}
	]
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
		{
			"fit_path": "C:/rides/b.fit",
			"summary":
			{
				"ride_id": "b",
				"utc_start": "2026-10-21T08:00:00Z",
				"game_id": "workout",
				"duration_s": 1680.0
			},
			"uploaded": true,
			"activity_id": 5
		},
		{
			"fit_path": "C:/rides/a.fit",
			"summary":
			{
				"ride_id": "a",
				"utc_start": "2026-10-20T08:00:00Z",
				"game_id": "siege",
				"duration_s": 3300.0
			},
			"uploaded": false
		},
	]
	var s := open_screen(AppRidesScreen.new()) as AppRidesScreen
	assert_eq(menu(s).ids(), [0, 1, "copy_folder", "back"])
	assert_true(menu(s).text_of(0).contains("28:00"))
	assert_true(menu(s).text_of(0).contains(AppScreen.t("APP_RIDES_UPLOADED")))
	assert_true(scan_to(s, 0))
	s.feed_gesture(Wl.G_SURGE)
	assert_eq(menu(s).ids(), ["upload", "copy_title", "copy_description", "back"], "its actions")
	assert_eq(menu(s).text_of("upload"), AppScreen.t("APP_RIDES_REUPLOAD"))
	surge_pick(s, "upload")
	assert_eq(menu(s).ids(), [0, 1, "copy_folder", "back"], "back on the list")
	# W3 RS-3: Rides.upload() would only report the stored state of a ride marked uploaded;
	# the history re-uploads it (Rides.reupload) so a ride deleted on Strava goes up again.
	assert_eq(fx.fake_rides().reuploads, ["b"] as Array[String], "re-upload of an uploaded ride")
	assert_eq(fx.fake_rides().uploads.size(), 0, "not the plain upload, which skips uploaded rides")
	fx.bus.upload_state_changed.emit("b", "duplicate", "")
	assert_true(
		menu(s).text_of(0).contains(AppScreen.t("APP_UPLOAD_DUPLICATE").format([""]).strip_edges())
	)
	assert_true(scan_to(s, 1))
	s.feed_gesture(Wl.G_SURGE)
	assert_eq(menu(s).text_of("upload"), AppScreen.t("APP_RIDES_UPLOAD"))
	surge_pick(s, "upload")
	assert_eq(fx.fake_rides().uploads.size(), 1, "a ride never uploaded goes through upload()")
	assert_eq(fx.fake_rides().uploads[0]["fit_path"], "C:/rides/a.fit")
	assert_eq(fx.fake_rides().reuploads.size(), 1)
	surge_pick(s, "back")
	assert_eq(fx.app.state, "settings")


func _detail_of(s: AppScreen, id: Variant) -> String:
	for it: Variant in menu(s).items():
		if AppScreen.same_id((it as Dictionary).get("id"), id):
			return str((it as Dictionary).get("detail", ""))
	return ""


func test_rides_history_shows_why_an_upload_failed() -> void:
	fx.give_profile()
	fx.fake_rides().connected = true
	fx.fake_rides().ride_list = [
		{
			"fit_path": "C:/rides/f.fit",
			"summary":
			{
				"ride_id": "f",
				"utc_start": "2026-10-23T20:04:28Z",
				"game_id": "fishing",
				"duration_s": 1208.0,
				"upload": {"state": "failed", "error": "Forbidden (403)"}
			},
			"uploaded": false,
			"state": "failed"
		},
		{"fit_path": "C:/rides/g.fit", "summary": {"ride_id": "g"}, "uploaded": false},
	]
	var s := open_screen(AppRidesScreen.new()) as AppRidesScreen
	var failed := AppScreen.t("APP_UPLOAD_FAILED")
	assert_eq(_detail_of(s, 0), failed.format(["Forbidden (403)"]), "the saved reason")
	assert_false(menu(s).text_of(0).contains(failed.format([""]).strip_edges()), "not twice")
	assert_eq(_detail_of(s, 1), "", "no second line for a ride that never failed")
	fx.bus.upload_state_changed.emit("g", "failed", "Forbidden (403)")
	assert_eq(_detail_of(s, 1), failed.format(["Forbidden (403)"]), "this visit's reason")
	fx.bus.upload_state_changed.emit("f", "uploaded", "123")
	assert_eq(_detail_of(s, 0), "", "gone once it uploads")


func test_rides_need_strava() -> void:
	fx.give_profile()
	fx.fake_rides().ride_list = [{"fit_path": "C:/r.fit", "summary": {"ride_id": "r"}}]
	var s := open_screen(AppRidesScreen.new()) as AppRidesScreen
	assert_false(menu(s).is_disabled_id(0), "the ride opens: copying needs no Strava")
	assert_eq(s.status_label.text, AppScreen.t("APP_RESULTS_STRAVA_OFF"))
	surge_pick(s, 0)
	assert_true(menu(s).is_disabled_id("upload"))
	assert_false(menu(s).is_disabled_id("copy_title"))
	assert_false(menu(s).is_disabled_id("copy_description"))


func _copy_summary() -> Dictionary:
	return {
		"ride_id": "c",
		"utc_start": "2026-10-25T18:00:00Z",
		"game_id": "fishing",
		"game_title": "Fishing",
		"ride_tag": "Marlin Bay",
		"duration_s": 1500.0,
		"timer_s": 1440.0,
		"distance_m": 12345.0,
		"avg_power_w": 181.0,
		"np_w": 190.0,
		"avg_cadence_rpm": 88.0,
		"ride_lines": ["Landed 3 fish"],
	}


func test_rides_copy_the_strava_title_and_description() -> void:
	fx.give_profile()
	fx.fake_rides().ride_list = [{"fit_path": "C:/rides/c.fit", "summary": _copy_summary()}]
	var s := open_screen(AppRidesScreen.new()) as AppRidesScreen
	var copied: Array[String] = []
	s.clipboard_set = func(text: String) -> void: copied.append(text)
	surge_pick(s, 0)
	surge_pick(s, "copy_title")
	assert_eq(
		copied, [WlRides.activity_name(_copy_summary())] as Array[String], "exactly Strava's name"
	)
	assert_true(copied[0].contains("Fishing") and copied[0].contains("Marlin Bay"), copied[0])
	assert_eq(s.copied_label.text, AppScreen.t("APP_RIDES_COPIED_TITLE"), "a confirmation")
	surge_pick(s, "copy_description")
	assert_eq(copied.size(), 2)
	assert_eq(
		copied[1], WlRides.activity_description(_copy_summary()), "exactly Strava's description"
	)
	assert_true(copied[1].contains("Landed 3 fish"))
	assert_eq(s.copied_label.text, AppScreen.t("APP_RIDES_COPIED_DESCRIPTION"))
	assert_eq(menu(s).ids()[0], "upload", "the actions stay open for the next copy")
	s.tick(AppRidesScreen.COPIED_S + 0.1)
	assert_eq(s.copied_label.text, "", "the confirmation goes away")
	surge_pick(s, "back")
	assert_eq(menu(s).ids(), [0, "copy_folder", "back"])
	assert_eq(menu(s).highlighted(), 0, "the ride stays highlighted")


func test_rides_page_shows_and_copies_the_folder() -> void:
	fx.give_profile()
	var s := open_screen(AppRidesScreen.new()) as AppRidesScreen
	var folder := ProjectSettings.globalize_path(Paths.rides_dir())
	assert_true(folder.is_absolute_path())
	assert_eq(AppRidesScreen.rides_folder(), folder)
	assert_eq(s.folder_label.text, AppScreen.t("APP_RIDES_FOLDER").format([folder]))
	assert_true(s.folder_label.visible)
	var copied: Array[String] = []
	s.clipboard_set = func(text: String) -> void: copied.append(text)
	surge_pick(s, "copy_folder")
	assert_eq(copied, [folder] as Array[String])
	assert_eq(s.copied_label.text, AppScreen.t("APP_RIDES_COPIED_FOLDER"))


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
	assert_eq(
		rider.phases_started.slice(0, 3),
		[0, 1, 2] as Array[int],
		"the first step after the 300 s ramp-in, then the second"
	)
	assert_eq(s.stage, "running")
	rider.tm.cadence_rpm = 30.0
	for _i in int(6.0 / Wl.SIM_DT):
		s.step_fixed()
	assert_eq(s.stage, "cooldown", "cadence < 50 rpm for 5 s ends the test")
	assert_eq(s.test.end_reason, FtpTest.END_CADENCE)
	assert_eq(
		rider.phases_started[rider.phases_started.size() - 1], rider.plan_set.cooldown_index()
	)
	assert_eq(
		menu(s).ids(),
		["save", "keep", "panic"],
		"the 10 s save countdown runs as the cool-down starts"
	)
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
