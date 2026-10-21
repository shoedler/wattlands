extends "res://tests/app/app_test_base.gd"
## The results screen (BRIEF 3.6, 3.8; OWNERSHIP RES1-RES3): grade, rows, custom and team stats,
## XP and new unlocks; where the ride was saved; Upload to Strava on pedal-scan; the auto-upload
## status from EventBus.upload_state_changed; Continue.


func _results() -> GameResults:
	var r := GameResults.new()
	r.grade = "S"
	r.rows = [
		{"peer_id": 1, "slot_index": 0, "name": "Ada", "is_bot": false, "kj": 412.4, "avg_power_w": 205.0,
			"avg_ftp_pct": 82.0, "np_w": 214.0, "time_in_band_pct": 96.0, "xp": 41, "unlocks": ["SIEGE_BANNER_RED"],
			"stats": {"walls_held": 3}},
		{"peer_id": -1, "slot_index": 1, "name": "Bot 1", "is_bot": true, "kj": 380.0, "avg_power_w": 190.0,
			"avg_ftp_pct": 95.0, "np_w": 191.0, "time_in_band_pct": 100.0, "xp": 0, "unlocks": [], "stats": {}},
	]
	r.team = {"gate_hp": 75}
	return r


func _open(extra: Dictionary = {}) -> AppResultsScreen:
	fx.give_profile()
	var p := {"results": _results(), "fit_path": "C:/rides/2026-10-21_workout.fit", "summary": {"ride_id": "abc"},
		"unlocks": ["SIEGE_BANNER_RED"], "game_id": "workout", "local_peer": 1}
	for k: Variant in extra.keys():
		p[k] = extra[k]
	return open_screen(AppResultsScreen.new(), p) as AppResultsScreen


func test_grade_rows_xp_and_unlocks() -> void:
	var s := _open()
	assert_eq(s.grade_label.text, "S")
	assert_eq(s.xp_label.text, "+41 XP")
	assert_true(s.unlocks_label.text.contains("SIEGE_BANNER_RED"))
	var texts: Array[String] = []
	for c in s.rows_grid.get_children():
		if c is Label:
			texts.append((c as Label).text)
	assert_true(texts.has("Ada  ★1"), "a row with unlocks is marked")
	assert_true(texts.has("Bot 1"))
	assert_true(texts.has("412"), "kJ")
	assert_true(texts.has("96%"), "time in band")
	# Custom stats sit in a wrapped line per rider under the grid (W3 ZIH-1), not in the grid.
	var stats := s.find_child("Stats1", true, false) as Label
	assert_not_null(stats, "custom stats")
	if stats != null:
		assert_true(stats.text.contains("walls_held: 3"), "custom stats: %s" % stats.text)
		assert_true(stats.text.begins_with("Ada"), "named for its rider")
	assert_true(s.ride_label.text.contains("2026-10-21_workout.fit"))


func test_upload_offered_only_when_strava_is_connected() -> void:
	var s := _open()
	assert_eq(menu(s).ids(), ["continue"])
	assert_eq(s.upload_label.text, AppScreen.t("APP_RESULTS_STRAVA_OFF"))


func test_upload_by_pedal_and_status_from_the_bus() -> void:
	fx.fake_rides().connected = true
	var s := _open()
	assert_eq(menu(s).ids(), ["upload", "continue"])
	surge_pick(s, "upload")
	var up: Dictionary = fx.fake_rides().uploads[0]
	assert_eq(up["fit_path"], "C:/rides/2026-10-21_workout.fit")
	assert_eq(up["summary"]["ride_id"], "abc")
	assert_true(menu(s).is_disabled_id("upload"), "one upload at a time")
	fx.bus.upload_state_changed.emit("other", "failed", "x")
	assert_eq(s.upload_state, "", "another ride's state is ignored")
	fx.bus.upload_state_changed.emit("abc", "processing", "")
	assert_eq(s.upload_label.text, AppScreen.t("APP_UPLOAD_PROCESSING").format([""]))
	fx.bus.upload_state_changed.emit("abc", "uploaded", "12345")
	assert_eq(s.upload_label.text, AppScreen.t("APP_UPLOAD_UPLOADED").format(["12345"]))
	assert_true(menu(s).is_disabled_id("upload"))
	assert_eq(fx.fake_rides().uploads.size(), 1)


func test_failed_upload_can_be_retried() -> void:
	fx.fake_rides().connected = true
	var s := _open()
	s.upload()
	fx.bus.upload_state_changed.emit("abc", "failed", "500")
	assert_false(menu(s).is_disabled_id("upload"))
	s.upload()
	assert_eq(fx.fake_rides().uploads.size(), 2)


func test_auto_upload_once_without_a_prompt() -> void:
	fx.fake_rides().connected = true
	fx.fake_rides().auto = true
	var s := _open()
	assert_eq(fx.fake_rides().uploads.size(), 1, "auto-upload started at once")
	s.upload()
	assert_eq(fx.fake_rides().uploads.size(), 1, "never twice")


func test_auto_upload_from_the_profile_setting() -> void:
	fx.fake_rides().connected = true
	fx.give_profile().strava_auto_upload = true
	var p := {"results": _results(), "fit_path": "C:/r.fit", "summary": {}, "local_peer": 1}
	open_screen(AppResultsScreen.new(), p)
	assert_eq(fx.fake_rides().uploads.size(), 1)


func test_a_ride_saved_later_is_picked_up() -> void:
	fx.fake_rides().connected = true
	var s := _open({"fit_path": "", "summary": {}})
	assert_eq(menu(s).ids(), ["continue"])
	fx.bus.ride_saved.emit("C:/late.fit", {"ride_id": "late"})
	assert_eq(s.fit_path, "C:/late.fit")
	assert_eq(menu(s).ids(), ["upload", "continue"])


func test_continue_leaves_the_room() -> void:
	var s := _open()
	surge_pick(s, "continue")
	assert_eq(fx.fake_net().calls_named("leave").size(), 1)
	assert_eq(fx.app.state, "title")


func test_grade_colors_and_host_left_note() -> void:
	assert_eq(AppResultsScreen.grade_color("S"), AppStyle.GOOD)
	assert_eq(AppResultsScreen.grade_color("D"), AppStyle.BAD)
	var s := _open({"host_left": true})
	var found := false
	for c in s.find_children("*", "Label", true, false):
		if (c as Label).text == AppScreen.t("APP_REFUSED_HOST_LEFT"):
			found = true
	assert_true(found)


func test_a_session_without_results_shows_no_grade() -> void:
	# A client whose host left before the results: the ride is saved, but there is no grade.
	var s := _open({"results": null, "host_left": true})
	assert_false(s.has_results)
	assert_eq(s.grade_label.text, "—", "never a D for a session that had no results")
	assert_eq(s.rows_grid.get_child_count(), 7, "only the column headers")
	assert_eq(s.ride_label.text, AppScreen.t("APP_RESULTS_SAVED").format(["C:/rides/2026-10-21_workout.fit"]))
	assert_true(menu(s).ids().has("continue"))
