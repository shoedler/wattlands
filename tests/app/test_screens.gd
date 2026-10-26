extends "res://tests/app/app_test_base.gd"
## Every app-shell screen instantiates headless with test doubles (BRIEF 3.9), the main scene
## shows the screen for App.state, and key numbers are readable from 3 m (>= 48 px at 1080p).


func test_title_without_profile() -> void:
	var s := open_screen(AppTitleScreen.new()) as AppTitleScreen
	assert_false(s.has_profile)
	assert_eq(menu(s).ids(), ["quick", "first_run", "join", "settings", "quit"])
	assert_false(menu(s).scanning, "no pedal-scan before a profile exists")
	assert_true(s.zero.armed)
	assert_eq(s.zero.hold_s, AppZeroTouch.FIRST_RUN_S)
	assert_ne(s.hint_label.text, "")


func test_title_with_profile() -> void:
	fx.give_profile()
	var s := open_screen(AppTitleScreen.new()) as AppTitleScreen
	assert_true(s.has_profile)
	assert_eq(
		menu(s).ids(), ["quick", "picker", "host", "join", "profile", "settings", "rides", "quit"]
	)
	assert_eq(
		menu(s).highlighted(), 0, "the quick ride is highlighted while the countdown is armed"
	)
	assert_eq(s.zero.hold_s, AppZeroTouch.HOLD_START_S)


func test_first_run_screen() -> void:
	var s := open_screen(AppFirstRunScreen.new()) as AppFirstRunScreen
	assert_eq(menu(s).ids(), ["name", "ftp", "weight", "done", "back"])
	confirm_pick(s, "done")
	assert_true(fx.settings.profile.created)
	assert_false(fx.settings.profile.ftp_verified, "untouched FTP stays unverified")
	assert_eq(fx.settings.profile.ftp_w, 200.0)
	assert_eq(fx.app.state, "title")


func test_first_run_ftp_typed_is_verified() -> void:
	var s := open_screen(AppFirstRunScreen.new()) as AppFirstRunScreen
	confirm_pick(s, "ftp")
	confirm_pick(s, "inc5")
	confirm_pick(s, "done")
	confirm_pick(s, "done")
	assert_eq(fx.settings.profile.ftp_w, 225.0)
	assert_true(fx.settings.profile.ftp_verified)


func test_profile_screen_edits_and_saves() -> void:
	fx.give_profile(200.0)
	fx.settings.profile.ftp_verified = false
	var s := open_screen(AppProfileScreen.new()) as AppProfileScreen
	assert_true(menu(s).ids().has("ftp"))
	confirm_pick(s, "ftp")
	confirm_pick(s, "inc")
	assert_eq(fx.settings.profile.ftp_w, 205.0)
	assert_true(fx.settings.profile.ftp_verified, "typing the FTP verifies it")
	assert_eq(fx.settings.profile.cp_w, 205.0)
	confirm_pick(s, "done")
	confirm_pick(s, "autopilot")
	assert_true(fx.settings.profile.autopilot_default)
	confirm_pick(s, "units")
	confirm_pick(s, 1)
	assert_eq(fx.settings.profile.units, "imperial")
	assert_gt((fx.settings as Object).get("profile_saves"), 0)
	assert_gte(font_size(s.ftp_label), AppStyle.KEY_NUMBER_MIN)


## BRIEF 3.3: W/kg shows only if the rider opted in; the opt-in is a profile toggle that
## pedal-scan reaches like every other field.
func test_profile_show_wkg_toggle_by_pedal() -> void:
	fx.give_profile(200.0)
	var s := open_screen(AppProfileScreen.new()) as AppProfileScreen
	assert_false(fx.settings.profile.show_wkg, "off by default")
	assert_true(menu(s).ids().has("show_wkg"))
	assert_true(menu(s).text_of("show_wkg").begins_with(AppScreen.t("APP_FIELD_SHOW_WKG")))
	assert_ne(AppScreen.t("APP_FIELD_SHOW_WKG"), "APP_FIELD_SHOW_WKG", "the label is translated")
	assert_true(menu(s).text_of("show_wkg").ends_with(AppScreen.t("APP_OFF")))
	var saves: int = (fx.settings as Object).get("profile_saves")
	assert_true(scan_to(s, "show_wkg"), "pedal-scan reaches the W/kg toggle")
	s.feed_gesture(Wl.G_SURGE)
	assert_true(fx.settings.profile.show_wkg, "a surge turns it on")
	assert_false(fx.settings.profile.share_weight, "independent of sharing the weight")
	assert_gt((fx.settings as Object).get("profile_saves"), saves, "saved")
	assert_true(menu(s).text_of("show_wkg").ends_with(AppScreen.t("APP_ON")))
	confirm_pick(s, "show_wkg")
	assert_false(fx.settings.profile.show_wkg, "and off again")


func test_settings_screen_pages() -> void:
	fx.give_profile()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	for section: String in [
		"trainer", "strava", "haptics", "controls", "audio", "network", "pedal_nav"
	]:
		confirm_pick(s, section)
		assert_eq(s.menus.size(), 2, "%s page open" % section)
		confirm_pick(s, "back")
		assert_eq(s.menus.size(), 1, "%s page closed" % section)


func test_settings_haptics_and_pedal_nav() -> void:
	fx.give_profile()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	confirm_pick(s, "haptics")
	confirm_pick(s, "haptics_on")
	assert_false(fx.settings.profile.haptics_on)
	assert_true(menu(s).is_disabled_id("haptic_intensity"), "intensity needs haptics on")
	confirm_pick(s, "haptics_on")
	confirm_pick(s, "haptic_intensity")
	confirm_pick(s, "dec")
	assert_eq(fx.settings.profile.haptic_intensity_pct, 60.0)
	confirm_pick(s, "done")
	confirm_pick(s, "back")
	confirm_pick(s, "pedal_nav")
	assert_false(fx.settings.profile.pedal_nav, "pedal navigation is off until chosen")
	assert_true(menu(s).is_disabled_id("scan_interval"), "the interval needs pedal navigation")
	confirm_pick(s, "pedal_nav")
	assert_true(fx.settings.profile.pedal_nav)
	confirm_pick(s, "scan_interval")
	confirm_pick(s, "inc")
	assert_almost_eq(fx.settings.profile.scan_interval_s, 1.8, 1e-6)


func test_settings_strava_connect_never_keeps_the_secret() -> void:
	fx.give_profile()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	confirm_pick(s, "strava")
	assert_true(menu(s).is_disabled_id("connect"))
	s.strava_client_id = "12345"
	s.strava_client_secret = "abcdef0123"
	s.refresh_fields()
	confirm_pick(s, "connect")
	assert_eq(fx.fake_rides().connects, ["12345"] as Array[String])
	assert_true(fx.fake_rides().secret_passed)
	assert_eq(s.strava_client_secret, "", "the secret is not kept after connect")
	confirm_pick(s, "auto_upload")
	assert_true(fx.settings.profile.strava_auto_upload)


func test_settings_relay_text_entry() -> void:
	fx.give_profile()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	confirm_pick(s, "network")
	confirm_pick(s, "relay")
	assert_not_null(s.text_field)
	s.text_field.set_value("ws://10.0.0.2:8787/v1")
	confirm_pick(s, AppKeyboard.ID_DONE)
	assert_eq(fx.settings.get_value("relay_url", ""), "ws://10.0.0.2:8787/v1")
	assert_null(s.text_field)


func test_settings_rebind_captures_the_next_key() -> void:
	fx.give_profile()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	confirm_pick(s, "controls")
	confirm_pick(s, "bind:ability_1")
	assert_eq(s.capturing, &"ability_1")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_G
	ev.keycode = KEY_G
	ev.pressed = true
	assert_true(s.capture_event(ev))
	var rebinds: Array = (fx.input as Object).get("rebinds")
	assert_eq(rebinds.size(), 1)
	assert_eq(rebinds[0][0], &"ability_1")
	assert_eq(s.capturing, &"")


func test_picker_cards_and_generated_title_card() -> void:
	fx.give_profile()
	fx.fake_registry().add_fixture(FakeRegistry.fishing())
	var s := open_screen(AppPickerScreen.new(), {"mode": "host"}) as AppPickerScreen
	assert_eq(s.cards.size(), 4)
	var siege := s.cards["siege"] as AppGameCard
	assert_null(siege.image, "a missing picker_image draws a generated card")
	assert_not_null(siege.generated)
	var tank := s.cards["tank"] as AppGameCard
	assert_not_null(tank.image, "Tank's picker_image is shown")
	var fishing := s.cards["fishing"] as AppGameCard
	assert_not_null(fishing.image, "an existing picker_image is shown")
	var workout := s.cards["workout"] as AppGameCard
	assert_not_null(workout.generated, "no picker_image: generated card")
	assert_eq(workout.players_label.text, "1–8 riders")
	assert_eq(menu(s).ids(), ["siege", "tank", "fishing", "workout", "back"], "sorted by title")


func test_lobby_solo_host_join_open() -> void:
	fx.give_profile()
	var solo := (
		open_screen(AppLobbyScreen.new(), {"mode": "solo", "game_id": "workout"}) as AppLobbyScreen
	)
	assert_eq(solo.page, AppLobbyScreen.PAGE_LOBBY)
	assert_false(solo.code_label.visible)
	var host := (
		open_screen(AppLobbyScreen.new(), {"mode": "host", "game_id": "workout"}) as AppLobbyScreen
	)
	assert_eq(host.role, Wl.HOST)
	var join := open_screen(AppLobbyScreen.new(), {"mode": "join"}) as AppLobbyScreen
	assert_eq(join.page, AppLobbyScreen.PAGE_JOIN)
	assert_not_null(join.code_field)


func test_session_screen_opens_headless() -> void:
	fx.give_profile()
	var s := (
		open_screen(
			AppSessionScreen.new(),
			{"role": Wl.SOLO, "game_id": "workout", "content_id": "easy_30", "quick": true}
		)
		as AppSessionScreen
	)
	assert_eq(s.error, "")
	assert_not_null(s.host)
	assert_true((s.host as FakeHost).started)
	assert_not_null(s.panic_button)
	assert_gte(s.panic_button.get_theme_font_size("font_size"), AppStyle.KEY_NUMBER_MIN)


func test_results_screen_opens() -> void:
	fx.give_profile()
	var r := GameResults.new()
	r.grade = "A"
	var s := (
		open_screen(AppResultsScreen.new(), {"results": r, "game_id": "workout", "local_peer": 1})
		as AppResultsScreen
	)
	assert_eq(s.grade_label.text, "A")
	assert_gte(font_size(s.grade_label), AppStyle.KEY_NUMBER_MIN)
	assert_gte(font_size(s.xp_label), AppStyle.KEY_NUMBER_MIN)


func test_rides_and_ftp_test_pages_open() -> void:
	fx.give_profile()
	var rides := open_screen(AppRidesScreen.new()) as AppRidesScreen
	assert_eq(menu(rides).ids(), ["copy_folder", "back"])
	var ftp := open_screen(AppFtpTestScreen.new()) as AppFtpTestScreen
	assert_eq(menu(ftp).ids(), ["start", "back"])
	assert_gte(font_size(ftp.big_label), AppStyle.KEY_NUMBER_MIN)


func test_scripted_screen_opens() -> void:
	var s := open_screen(AppScriptedScreen.new()) as AppScriptedScreen
	assert_not_null(s.view_layer)
	assert_not_null(s.hud_layer)


func test_main_shows_the_screen_for_app_state() -> void:
	fx.give_profile()
	var m := open_main()
	assert_true(current_screen(m) is AppTitleScreen, "boot goes to the title")
	fx.app.goto("picker", {"mode": "solo"})
	assert_true(current_screen(m) is AppPickerScreen)
	fx.app.goto("settings", {"page": "rides"})
	assert_true(current_screen(m) is AppRidesScreen)
	fx.app.goto("settings", {"page": "ftp_test"})
	assert_true(current_screen(m) is AppFtpTestScreen)
	fx.app.goto("settings")
	assert_true(current_screen(m) is AppSettingsScreen)
	fx.app.goto("profile")
	assert_true(current_screen(m) is AppProfileScreen)
	fx.app.goto("first_run")
	assert_true(current_screen(m) is AppFirstRunScreen)
	fx.app.goto("quitting")
	assert_eq(fx.quits, [0] as Array[int])


func test_main_falls_back_when_the_app_stub_does_not_move() -> void:
	fx.give_profile()
	fx.services.app = null
	var m := open_main()
	assert_true(current_screen(m) is AppTitleScreen)
	fx.services.goto("picker", {"mode": "host"})
	assert_true(current_screen(m) is AppPickerScreen)


func test_main_boot_starts_trainer_and_upload_queue() -> void:
	fx.give_profile()
	fx.fake_trainer().dev = null
	fx.fake_trainer().st = TrainerDevice.STATUS_DISCONNECTED
	fx.settings.set_value("master_volume_db", -9.0)
	var before := AudioServer.get_bus_volume_db(0)
	var m: Control = MainScene.new()
	m.set("services", fx.services)
	m.set("screens_auto_process", false)
	m.set("scripted_config", AppScriptedConfig.new())
	add_child(m)
	_opened.append(m)
	assert_eq(fx.fake_trainer().starts, 1)
	assert_eq(fx.fake_rides().queue_runs, 1)
	assert_eq((fx.settings as Object).get("loads"), 1)
	assert_almost_eq(AudioServer.get_bus_volume_db(0), -9.0, 0.01, "the saved master volume")
	AudioServer.set_bus_volume_db(0, before)


func test_room_code_is_readable_from_3_m() -> void:
	fx.give_profile()
	var s := (
		open_screen(AppLobbyScreen.new(), {"mode": "host", "game_id": "workout"}) as AppLobbyScreen
	)
	fx.fake_net().simulate_hosting("K7QX2M")
	assert_eq(s.code_label.text, "K7Q-X2M")
	assert_true(s.code_label.visible)
	assert_gte(font_size(s.code_label), AppStyle.KEY_NUMBER_MIN)
	var f := AppTextField.make_code("Code")
	autofree(f)
	assert_gte(font_size(f.display), AppStyle.KEY_NUMBER_MIN)


func test_settings_trainer_scan_connect_and_mock() -> void:
	fx.give_profile()
	var conn: FtmsConnectionManager = preload("res://tests/app/fakes/fake_connection.gd").new()
	fx.trainer.add_child(conn)
	fx.fake_trainer().conn = conn
	fx.fake_trainer().dev = null
	fx.fake_trainer().st = TrainerDevice.STATUS_DISCONNECTED
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	confirm_pick(s, "trainer")
	assert_eq(
		menu(s).text_of("status"),
		AppScreen.t("APP_SET_TRAINER_STATUS") + ": " + AppScreen.t("APP_TRAINER_NONE")
	)
	confirm_pick(s, "scan")
	assert_eq(conn.get("scans"), [10.0] as Array[float])
	conn.device_found.emit({"address": "AA:BB", "name": "KICKR CORE 1234", "rssi": -60})
	conn.device_found.emit({"address": "AA:BB", "name": "KICKR CORE 1234", "rssi": -58})
	assert_true(menu(s).ids().has("dev:AA:BB"), "found trainers are listed once")
	assert_eq(menu(s).ids().count("dev:AA:BB"), 1)
	confirm_pick(s, "dev:AA:BB")
	assert_eq(conn.get("connects"), ["AA:BB"] as Array[String])
	confirm_pick(s, "mock")
	assert_eq(fx.fake_trainer().mock_specs, ["erg"] as Array[String])
	assert_eq(
		menu(s).text_of("status"),
		AppScreen.t("APP_SET_TRAINER_STATUS") + ": " + AppScreen.t("APP_TRAINER_OK")
	)
	confirm_pick(s, "disconnect")
	assert_eq(conn.get("disconnects"), 1)
