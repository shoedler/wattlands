extends "res://tests/app/app_test_base.gd"
## Pedal-scan navigation (BRIEF 3.5, 3.9; OWNERSHIP PSL4): title -> picker -> lobby -> session
## -> results with nothing but gestures injected through the InputRouter (scan ticks move the
## focus, surge picks, coast backs out), plus keyboard/controller confirm and up/down.


func _pedal_then_coast(title: AppTitleScreen) -> void:
	# A pedal stroke, then a coast: disarms the zero-touch countdown so the menu scans.
	title.feed_sample(sample(0.0, 150.0, 85.0))
	fx.input.inject_gesture(Wl.G_COAST)


func test_title_to_picker_to_lobby_to_session_by_pedal() -> void:
	fx.give_profile()
	var m := open_main()
	var title := current_screen(m) as AppTitleScreen
	assert_not_null(title)
	assert_false(menu(title).scanning, "the countdown holds the quick ride first")
	_pedal_then_coast(title)
	assert_false(title.zero.armed, "coast after pedaling disarms the countdown")
	assert_true(menu(title).scanning, "the main menu now runs on pedal-scan")
	assert_true(scan_to(title, "host"), "the scan reaches Host a room")
	fx.input.inject_gesture(Wl.G_SURGE)
	var picker := current_screen(m) as AppPickerScreen
	assert_not_null(picker, "surge opened the picker")
	assert_eq(picker.mode, "host")
	assert_true(scan_to(picker, "workout"))
	fx.input.inject_gesture(Wl.G_SURGE)
	var lobby := current_screen(m) as AppLobbyScreen
	assert_not_null(lobby, "surge opened the lobby")
	assert_eq(lobby.role, Wl.HOST)
	assert_eq(fx.fake_net().last_call("host_room"), ["host_room", 8])
	fx.fake_net().add_human(1, "Ada", 250.0)
	fx.fake_net().simulate_hosting("K7QX2M")
	assert_eq(lobby.code_label.text, "K7Q-X2M")
	fx.input.inject_gesture(Wl.G_PEDAL_START)
	assert_true(lobby.local_ready, "pedal_start readies up")
	assert_true(scan_to(lobby, "start"))
	fx.input.inject_gesture(Wl.G_SURGE)
	var session := current_screen(m) as AppSessionScreen
	assert_not_null(session, "everyone ready: the host's start opened the session")
	assert_eq(session.role, Wl.HOST)
	var h := fx.last_host()
	assert_true(h.started)
	h.finish_with(GameResults.new())
	var results := current_screen(m) as AppResultsScreen
	assert_not_null(results, "the session's end opened results")
	assert_true(scan_to(results, "continue"))
	fx.input.inject_gesture(Wl.G_SURGE)
	assert_true(current_screen(m) is AppTitleScreen, "continue returns to the title")


func test_coast_backs_out_of_the_picker() -> void:
	fx.give_profile()
	var m := open_main()
	fx.app.goto("picker", {"mode": "solo"})
	var picker := current_screen(m) as AppPickerScreen
	fx.input.inject_gesture(Wl.G_COAST)
	assert_true(current_screen(m) is AppTitleScreen)


func test_keyboard_moves_and_confirms() -> void:
	fx.give_profile()
	var m := open_main()
	var title := current_screen(m) as AppTitleScreen
	fx.input.inject_action(&"down")
	assert_false(title.zero.armed, "a device action disarms the countdown")
	assert_eq(menu(title).highlighted(), 1)
	fx.input.inject_action(&"confirm")
	assert_true(current_screen(m) is AppPickerScreen)


func test_scan_interval_follows_the_profile() -> void:
	var p := fx.give_profile()
	p.scan_interval_s = 2.4
	var s := open_screen(AppPickerScreen.new(), {"mode": "solo"})
	assert_eq(menu(s).scan_interval_s, 2.4)
	assert_true(menu(s).scanning)
	var before := menu(s).highlighted()
	s.tick(2.3)
	assert_eq(menu(s).highlighted(), before, "no move before the interval")
	s.tick(0.1)
	assert_ne(menu(s).highlighted(), before, "focus moved after one interval")


func test_menus_follow_the_input_router_pedal_ui() -> void:
	fx.give_profile()
	fx.input.set("pedal_ui", false)
	var s := open_screen(AppPickerScreen.new(), {"mode": "solo"})
	assert_false(menu(s).scanning, "a controller rider with pedal UI off")
	fx.input.set("pedal_ui", true)
	var s2 := open_screen(AppPickerScreen.new(), {"mode": "solo"})
	assert_true(menu(s2).scanning)


func test_without_a_router_the_profile_decides() -> void:
	var p := fx.give_profile()
	fx.services.input = null
	p.pedal_ui = false
	p.autopilot_default = false
	var s := open_screen(AppPickerScreen.new(), {"mode": "solo"})
	assert_false(menu(s).scanning)
	p.autopilot_default = true
	var s2 := open_screen(AppPickerScreen.new(), {"mode": "solo"})
	assert_true(menu(s2).scanning, "Autopilot turns pedal-scan on")


func test_lobby_add_and_remove_bots_by_pedal() -> void:
	fx.give_profile()
	fx.fake_net().add_human(1, "Ada")
	var s := open_screen(AppLobbyScreen.new(), {"mode": "solo", "game_id": "workout"}) as AppLobbyScreen
	assert_true(scan_to(s, "add_bot"))
	s.feed_gesture(Wl.G_SURGE)
	assert_eq(fx.fake_net().calls_named("add_bot").size(), 1)
	assert_false(menu(s).is_disabled_id("remove_bot"))
	assert_true(scan_to(s, "remove_bot"))
	s.feed_gesture(Wl.G_SURGE)
	assert_eq(fx.fake_net().calls_named("remove_bot").size(), 1)


func test_results_upload_is_pedal_selectable() -> void:
	fx.give_profile()
	fx.fake_rides().connected = true
	var s := open_screen(AppResultsScreen.new(), {"results": GameResults.new(), "fit_path": "C:/x/ride.fit",
		"summary": {"ride_id": "r1"}, "local_peer": 1}) as AppResultsScreen
	assert_true(scan_to(s, "upload"))
	s.feed_gesture(Wl.G_SURGE)
	assert_eq(fx.fake_rides().uploads.size(), 1)
	assert_eq(fx.fake_rides().uploads[0]["fit_path"], "C:/x/ride.fit")
