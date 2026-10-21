extends "res://tests/app/app_test_base.gd"
## First run with no input (BRIEF 3.5, 3.6, 7.1; OWNERSHIP REG2): after 20 s of pedaling on the
## title, a profile "Rider" (FTP 200, unverified) is created and GameRegistry.first_run_game()
## starts solo with its zero_input_content. The game comes from the registry by
## first_run_priority (never a hard-coded "workout"): installing a game with a higher priority
## changes the choice.


func _pedal(title: AppTitleScreen, from_s: int, to_s: int) -> void:
	for t in range(from_s, to_s + 1):
		title.feed_sample(sample(float(t), 140.0, 82.0))


func test_first_run_game_comes_from_the_registry() -> void:
	assert_eq(fx.registry.first_run_game(), "workout", "fixture: workout 0, siege -1, tank -1")
	var title := open_screen(AppTitleScreen.new()) as AppTitleScreen
	assert_eq(title.quick_game, fx.registry.first_run_game())
	assert_eq(title.quick_content, "easy_30")


func test_a_higher_priority_game_takes_the_first_run() -> void:
	fx.fake_registry().add_game(FakeRegistry.fishing())
	assert_eq(fx.registry.first_run_game(), "fishing")
	var title := open_screen(AppTitleScreen.new()) as AppTitleScreen
	assert_eq(title.quick_game, "fishing")
	assert_eq(title.quick_content, "free_30")


func test_negative_priority_never_takes_the_first_run() -> void:
	fx.fake_registry().remove_game("workout")
	# Siege and Tank are both -1: the tie goes to the lowest id.
	var title := open_screen(AppTitleScreen.new()) as AppTitleScreen
	assert_eq(title.quick_game, fx.registry.first_run_game())
	assert_eq(title.quick_game, "siege")


func test_twenty_seconds_of_pedaling_creates_rider_and_starts() -> void:
	fx.fake_registry().add_game(FakeRegistry.fishing())
	var m := open_main()
	var title := current_screen(m) as AppTitleScreen
	assert_false(fx.settings.has_profile())
	_pedal(title, 0, 19)
	assert_eq(fx.app.state, "title", "19 s of pedaling is not enough")
	assert_false(fx.settings.profile.created)
	title.feed_sample(sample(20.0, 140.0, 82.0))
	assert_eq(fx.app.state, "session", "20 s of pedaling starts the first-run game")
	var p := fx.settings.profile
	assert_true(p.created)
	assert_eq(p.display_name, "Rider")
	assert_eq(p.ftp_w, 200.0)
	assert_false(p.ftp_verified)
	assert_gt((fx.settings as Object).get("profile_saves"), 0, "the profile was saved")
	assert_eq(fx.app.params.get("role"), Wl.SOLO)
	assert_eq(fx.app.params.get("game_id"), "fishing")
	assert_eq(fx.app.params.get("content_id"), "free_30")
	assert_true(current_screen(m) is AppSessionScreen)


func test_stopping_restarts_the_twenty_seconds() -> void:
	var title := open_screen(AppTitleScreen.new()) as AppTitleScreen
	_pedal(title, 0, 15)
	title.feed_sample(sample(16.0, 5.0, 0.0))
	_pedal(title, 17, 36)
	assert_eq(fx.app.state, "boot", "only 19 s since the restart")
	title.feed_sample(sample(37.0, 140.0, 82.0))
	assert_eq(fx.app.state, "session")


func test_a_coast_on_the_first_run_only_restarts_the_twenty_seconds() -> void:
	# A rider with no input who stops for a while (the coast gesture) must still get in: the
	# countdown stays armed and the stretch starts again when they pedal.
	var m := open_main()
	var title := current_screen(m) as AppTitleScreen
	_pedal(title, 0, 12)
	title.feed_sample(sample(13.0, 0.0, 0.0))
	fx.input.inject_gesture(Wl.G_COAST)
	assert_true(title.zero.armed, "a coast never disarms the first-run countdown")
	assert_true(current_screen(m) is AppTitleScreen, "and never backs out of the title")
	_pedal(title, 20, 39)
	assert_eq(fx.app.state, "title", "19 s since the restart")
	title.feed_sample(sample(40.0, 140.0, 82.0))
	assert_eq(fx.app.state, "session", "20 s of pedaling after the coast starts the first run")
	assert_eq(fx.settings.profile.display_name, "Rider")


func test_any_key_cancels_the_first_run_countdown() -> void:
	var title := open_screen(AppTitleScreen.new()) as AppTitleScreen
	_pedal(title, 0, 10)
	title.feed_action(&"down")
	_pedal(title, 11, 40)
	assert_ne(fx.app.state, "session")
	assert_false(fx.settings.profile.created)


func test_ride_now_item_does_the_same_at_once() -> void:
	var title := open_screen(AppTitleScreen.new()) as AppTitleScreen
	surge_pick(title, "quick")
	assert_eq(fx.app.state, "session")
	assert_eq(fx.settings.profile.display_name, "Rider")
	assert_eq(fx.app.params.get("game_id"), fx.registry.first_run_game())


func test_first_run_session_sets_up_the_offline_lobby() -> void:
	var title := open_screen(AppTitleScreen.new()) as AppTitleScreen
	_pedal(title, 0, 20)
	var s := open_screen(AppSessionScreen.new(), fx.app.params) as AppSessionScreen
	var net := fx.fake_net()
	assert_eq(net.calls_named("start_offline").size(), 1)
	assert_eq(net.last_call("set_game"), ["set_game", "workout", "1.0.0", "easy_30"])
	assert_eq(net.last_call("set_ready"), ["set_ready", true])
	assert_eq(s.config.get("role"), Wl.SOLO)
	assert_eq(s.config.get("content_id"), "easy_30")
	var players: Array[PlayerSlot] = s.config.get("players")
	assert_eq(players.size(), 1, "the profile's own slot when the offline lobby has none")
	assert_eq(players[0].name, "Rider")
	assert_eq(players[0].ftp, 200.0)
	assert_false(players[0].ftp_verified)
