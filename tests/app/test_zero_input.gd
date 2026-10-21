extends "res://tests/app/app_test_base.gd"
## Zero-touch start with a saved profile (BRIEF 3.5; OWNERSHIP REG8): holding pedal_start for
## 5 s on the title starts the last-played game solo with its zero_input_content. Timings come
## from a synthetic rider stream (sample times), never the wall clock.


func test_tracker_five_second_hold() -> void:
	var z := AppZeroTouch.new()
	z.configure(250.0, false)
	assert_eq(z.hold_s, 5.0)
	for t in 5:
		assert_false(z.feed_values(float(t), 200.0, 85.0), "not at %d s" % t)
	assert_true(z.feed_values(5.0, 200.0, 85.0), "fires at 5 s")
	assert_false(z.feed_values(6.0, 200.0, 85.0), "fires once")


func test_tracker_with_jittery_samples() -> void:
	var z := AppZeroTouch.new()
	z.configure(250.0, false)
	var times: Array[float] = [10.0, 10.95, 12.1, 13.05, 14.0, 14.98, 16.02]
	var fired_at := -1.0
	for t in times:
		if z.feed_values(t, 0.0, 60.0):
			fired_at = t
	assert_eq(fired_at, 16.02, "the first sample at least 5 s after the stretch began")


func test_tracker_conditions() -> void:
	var z := AppZeroTouch.new()
	z.configure(200.0, false)
	assert_true(z.is_pedaling(0.0, 40.0), "cadence >= 40 rpm")
	assert_false(z.is_pedaling(0.0, 39.9))
	assert_true(z.is_pedaling(60.0, 0.0), "power >= 30% FTP")
	assert_false(z.is_pedaling(59.9, 10.0))


func test_tracker_interruption_and_cancel() -> void:
	var z := AppZeroTouch.new()
	z.configure(200.0, false)
	z.feed_values(0.0, 100.0, 80.0)
	z.feed_values(4.0, 100.0, 80.0)
	z.feed_values(4.5, 0.0, 0.0)
	assert_eq(z.held_s, 0.0)
	assert_false(z.feed_values(9.0, 100.0, 80.0), "the stretch restarted at 9 s")
	assert_true(z.feed_values(14.0, 100.0, 80.0))
	var z2 := AppZeroTouch.new()
	z2.configure(200.0, true)
	assert_eq(z2.hold_s, 20.0)
	z2.feed_values(0.0, 100.0, 80.0)
	z2.cancel()
	assert_false(z2.feed_values(30.0, 100.0, 80.0), "a cancelled countdown never fires")


func test_five_second_hold_starts_the_last_played_game() -> void:
	fx.give_profile()
	fx.settings.set_value("last_game", "tank")
	var m := open_main()
	var title := current_screen(m) as AppTitleScreen
	assert_eq(title.quick_game, "tank")
	assert_eq(title.quick_content, "ashfall_road")
	for t in 5:
		title.feed_sample(sample(100.0 + t, 180.0, 85.0))
	assert_eq(fx.app.state, "title", "not before 5 s")
	assert_eq(title.zero.seconds_left(), 1)
	title.feed_sample(sample(105.0, 180.0, 85.0))
	assert_eq(fx.app.state, "session")
	assert_eq(fx.app.params.get("game_id"), "tank")
	assert_eq(fx.app.params.get("content_id"), "ashfall_road")
	assert_eq(fx.app.params.get("role"), Wl.SOLO)
	assert_eq(fx.settings.profile.display_name, "Ada", "the saved profile is kept")


func test_nothing_played_yet_uses_the_first_run_game() -> void:
	fx.give_profile()
	fx.fake_registry().add_game(FakeRegistry.fishing())
	var title := open_screen(AppTitleScreen.new()) as AppTitleScreen
	assert_eq(title.quick_game, "fishing")


func test_an_uninstalled_last_game_falls_back() -> void:
	fx.give_profile()
	fx.settings.set_value("last_game", "kart")
	var title := open_screen(AppTitleScreen.new()) as AppTitleScreen
	assert_eq(title.quick_game, fx.registry.first_run_game())


func test_samples_arrive_from_the_trainer_device() -> void:
	fx.give_profile()
	var title := open_screen(AppTitleScreen.new()) as AppTitleScreen
	var dev := fx.trainer.device()
	for t in 6:
		dev.sample_received.emit(sample(float(t), 180.0, 85.0))
	assert_eq(fx.app.state, "session", "the title follows the trainer's samples")


func test_menu_surge_on_the_quick_ride_while_armed() -> void:
	fx.give_profile()
	var title := open_screen(AppTitleScreen.new()) as AppTitleScreen
	title.feed_sample(sample(0.0, 180.0, 85.0))
	title.feed_gesture(Wl.G_SURGE)
	assert_eq(fx.app.state, "session", "a surge picks the held quick ride")


func test_solo_lobby_starts_with_pedal_start_only() -> void:
	fx.give_profile()
	fx.fake_net().add_human(1, "Ada")
	var s := open_screen(AppLobbyScreen.new(), {"mode": "solo", "game_id": "workout"}) as AppLobbyScreen
	s.feed_gesture(Wl.G_PEDAL_START)
	assert_eq(fx.app.state, "session", "solo: pedal_start readies and starts")
	assert_eq(fx.app.params.get("content_id"), "easy_30")


func test_host_and_client_ready_by_pedal_start_only() -> void:
	fx.give_profile()
	fx.fake_net().add_human(1, "Ada")
	var host := open_screen(AppLobbyScreen.new(), {"mode": "host", "game_id": "workout"}) as AppLobbyScreen
	fx.fake_net().simulate_hosting("K7QX2M")
	host.feed_gesture(Wl.G_PEDAL_START)
	assert_true(host.local_ready)
	assert_ne(fx.app.state, "session", "a host starts only on Start ride (friends may still join)")
