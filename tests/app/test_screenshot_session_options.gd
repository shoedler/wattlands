extends GutTest
## tools/screenshot --app-screen=session (tools/qa/screenshot_options.gd, screenshot_session.gd):
## the flags of the app's session shots (BRIEF 7.8). The driver itself needs a window and runs
## in tools/screenshot; the session screen it shoots is tested in test_real_session.gd.

const Options := preload("res://tools/qa/screenshot_options.gd")


func _parse(args: Array) -> Dictionary:
	return Options.parse(PackedStringArray(args))


func test_session_defaults() -> void:
	var o := _parse(["--app-screen=session"])
	assert_eq(o["error"], "")
	assert_eq(o["mode"], "app")
	assert_eq(o["app_screen"], "session")
	assert_eq(o["app_role"], "client", "a client HUD built from session_start by default")
	assert_eq(o["app_overlay"], "menu")
	assert_eq(o["at"], [Options.DEFAULT_SESSION_AT], "one shot 30 s into the session")
	assert_eq(o["app_game"], "workout")


func test_session_flags() -> void:
	var o := _parse(
		[
			"--app-screen=session",
			"--app-role=host",
			"--app-overlay=panic",
			"--at=100,20",
			"--content=e2e",
			"--sim-speed=8"
		]
	)
	assert_eq(o["error"], "")
	assert_eq(o["app_role"], "host")
	assert_eq(o["app_overlay"], "panic")
	assert_eq(_parse(["--app-screen=session", "--app-overlay=discard"])["error"], "")
	assert_eq(o["at"], [20.0, 100.0])
	assert_eq(o["content"], "e2e")
	assert_true(
		(o["sim_args"] as PackedStringArray).has("--sim-speed=8"),
		"the app reads --sim-speed itself"
	)
	assert_false(
		(o["sim_args"] as PackedStringArray).has("--app-role=host"),
		"own flags stay out of the sim flags"
	)


func test_bad_role_and_overlay_are_refused() -> void:
	assert_string_contains(
		_parse(["--app-screen=session", "--app-role=bot"])["error"], "--app-role"
	)
	assert_string_contains(
		_parse(["--app-screen=session", "--app-overlay=shop"])["error"], "--app-overlay"
	)
	assert_string_contains(
		_parse(["--app-screen=settings"])["error"], "--app-screen", "other screens stay refused"
	)


func test_other_app_screens_keep_no_at() -> void:
	assert_eq(
		_parse(["--app-screen=title"])["at"], [], "title, picker and lobby shots take no --at"
	)


func test_session_file_names() -> void:
	assert_eq(Options.session_file_name("client", 20.0), "app_session_client_20s.png")
	assert_eq(Options.session_file_name("host", 100.5, "menu"), "app_session_host_100.5s_menu.png")


# --- --app-screen=results (W4r2 R26) -------------------------------------------------------------


func test_results_shots_take_a_rider_count() -> void:
	var o := _parse(["--app-screen=results"])
	assert_eq(o["error"], "")
	assert_eq(o["mode"], "app")
	assert_eq(o["app_riders"], 1, "solo by default")
	assert_eq(o["at"], [], "no --at")
	o = _parse(["--app-screen=results", "--app-riders=8"])
	assert_eq(o["error"], "")
	assert_eq(o["app_riders"], 8)
	assert_false((o["sim_args"] as PackedStringArray).has("--app-riders=8"), "an own flag")
	for bad: String in ["0", "9", "two", ""]:
		assert_string_contains(
			_parse(["--app-screen=results", "--app-riders=" + bad])["error"], "--app-riders", bad
		)
	assert_eq(Options.results_file_name(2), "app_results_2p.png")


func test_results_params_are_a_full_workout_page() -> void:
	for n in [1, 2, 8]:
		var p := QaScreenshotResults.params(n)
		var r := p["results"] as GameResults
		assert_eq(r.rows.size(), n)
		assert_eq(int(p["local_peer"]), 1)
		assert_eq(bool(p["host_left"]), n > 1)
		assert_eq(str(p["role"]), Wl.SOLO if n == 1 else Wl.HOST)
		assert_true(str(p["fit_path"]).ends_with("_workout.fit"))
		assert_false((r.rows[0]["stats"] as Dictionary).is_empty())
	assert_eq(
		(QaScreenshotResults.params(20)["results"] as GameResults).rows.size(),
		Options.MAX_RESULTS_RIDERS,
		"clamped"
	)
