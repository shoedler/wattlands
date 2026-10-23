extends "res://tests/app/app_test_base.gd"
## The session screen (BRIEF 3.6, 4.6.5): the GameHost gets players = NetSession.lobby_slots(),
## local riders = TrainerService.local_rider() plus a LocalRider per bot (MockTrainer
## Bots.RIDER_SPEC at the bot FTP), net (HOST/CLIENT only), options and the view/HUD parents;
## the pause overlay; the on-screen panic; results with the FIT path and summary.


func _lobby_with_bots() -> void:
	fx.give_profile(250.0)
	var net := fx.fake_net()
	net.local_peer = 1
	net.add_human(1, "Ada", 250.0)
	net.settings_sent["bot_ftp"] = 230.0
	net.add_bot()
	net.add_bot()
	net.lobby = {
		"game_id": "workout",
		"game_version": "1.0.0",
		"content_id": "sweet_spot",
		"scaling": Wl.WKG,
		"settings": {"options": {"laps": 3}, "bot_ftp": 230.0},
		"player_options": {1: {"offset": 2}}
	}


## PlayerSlot.pedal_nav of this machine's rider is the profile's setting, whatever the lobby listed.
func test_the_local_slot_takes_pedal_navigation_from_the_profile() -> void:
	_lobby_with_bots()
	for on: bool in [true, false]:
		fx.settings.profile.pedal_nav = on
		var s := (
			open_screen(
				AppSessionScreen.new(),
				{"role": Wl.SOLO, "game_id": "workout", "content_id": "sweet_spot"}
			)
			as AppSessionScreen
		)
		var players: Array[PlayerSlot] = (s.host as FakeHost).config_seen["players"]
		assert_eq(players[0].pedal_nav, on)
		assert_false(players[1].pedal_nav, "bots never use pedal navigation")


func test_solo_config_from_the_lobby() -> void:
	_lobby_with_bots()
	var s := (
		open_screen(
			AppSessionScreen.new(),
			{"role": Wl.SOLO, "game_id": "workout", "content_id": "sweet_spot"}
		)
		as AppSessionScreen
	)
	var h := s.host as FakeHost
	assert_not_null(h)
	assert_true(h.started)
	var c := h.config_seen
	assert_eq(c["role"], Wl.SOLO)
	assert_eq(c["game_id"], "workout")
	assert_eq(c["content_id"], "sweet_spot")
	assert_eq(c["scaling_mode"], Wl.WKG)
	assert_null(c["net"], "SOLO has no net")
	assert_eq(c["bus"], fx.bus)
	assert_eq(c["local_peer"], 1)
	assert_true(c["headless"], "headless test run")
	assert_eq(c["view_parent"], s.view_layer)
	assert_eq(c["hud_parent"], s.hud_layer)
	assert_eq(
		c["options"],
		{"music": true, "laps": 3, "theme": "day"},
		"lobby values with defaults filled"
	)
	var players: Array[PlayerSlot] = c["players"]
	assert_eq(players.size(), 3)
	assert_eq(players[0].options, {"offset": 2}, "the rider's player_options from the lobby")
	assert_eq(players[1].options, {"offset": 0}, "bots get the defaults")
	assert_eq(
		c["seed"], SeededRng.derive(1800000000, "workout|sweet_spot") & AppSessionLauncher.SEED_MASK
	)


func test_local_riders_are_the_trainer_rider_and_bot_mocks() -> void:
	_lobby_with_bots()
	var s := (
		open_screen(
			AppSessionScreen.new(),
			{"role": Wl.SOLO, "game_id": "workout", "content_id": "sweet_spot"}
		)
		as AppSessionScreen
	)
	var riders: Dictionary = s.config["local_riders"]
	assert_eq(riders.keys().size(), 3)
	var me := riders[1] as FakeRider
	assert_eq(me, fx.trainer.local_rider(), "TrainerService.local_rider()")
	var call: Dictionary = me.setup_calls[0]
	assert_eq(call["peer"], 1)
	assert_eq(call["device"], fx.trainer.device())
	assert_false(call["options"]["multiplayer"])
	assert_true(call["options"]["record"])
	assert_eq(call["options"]["utc_start_unix"], 1800000000)
	for peer: int in [-1, -2]:
		var bot := riders[peer] as FakeRider
		assert_not_null(bot, "bot %d has a rider" % peer)
		assert_true(bot.is_bot)
		var bc: Dictionary = bot.setup_calls[0]
		assert_false(bc["options"]["record"], "bots record no ride")
		var dev := bc["device"] as MockTrainer
		assert_not_null(dev)
		assert_eq(dev.spec, Bots.RIDER_SPEC)
		assert_eq((bc["slot"] as PlayerSlot).ftp, 230.0, "the bot FTP")
	assert_eq(fx.settings.get_value("last_game", ""), "workout", "last-played game remembered")
	assert_eq(fx.settings.get_value("last_content", ""), "sweet_spot")


func test_host_config_has_the_net_and_marks_started() -> void:
	_lobby_with_bots()
	var s := (
		open_screen(
			AppSessionScreen.new(),
			{"role": Wl.HOST, "game_id": "workout", "content_id": "sweet_spot"}
		)
		as AppSessionScreen
	)
	var c := (s.host as FakeHost).config_seen
	assert_eq(c["net"], fx.net)
	assert_eq(fx.fake_net().calls_named("mark_started").size(), 1)
	var me := c["local_riders"][1] as FakeRider
	assert_true(me.setup_calls[0]["options"]["multiplayer"])


func test_client_config_from_session_start() -> void:
	fx.give_profile(220.0, "Bea")
	var net := fx.fake_net()
	net.local_peer = 2
	var a := PlayerSlot.new()
	a.peer_id = 1
	a.name = "Ada"
	a.apply_look(0)
	var b := PlayerSlot.new()
	b.peer_id = 2
	b.name = "Bea"
	b.apply_look(1)
	var start := {
		"type": "session_start",
		"v": 1,
		"game_id": "workout",
		"game_version": "1.0.0",
		"content_id": "e2e",
		"seed": 77,
		"players": [a.to_dict(), b.to_dict(), Bots.make_slot(1, 2, 200.0).to_dict()],
		"options": {"music": false},
		"scaling": Wl.FAIR_FTP,
		"start_tick": 0
	}
	var s := (
		open_screen(AppSessionScreen.new(), {"role": Wl.CLIENT, "session_start": start})
		as AppSessionScreen
	)
	var c := (s.host as FakeHost).config_seen
	assert_eq(c["role"], Wl.CLIENT)
	assert_eq(c["seed"], 77)
	assert_eq(c["content_id"], "e2e")
	assert_eq(c["local_peer"], 2)
	assert_eq(c["net"], fx.net)
	assert_eq(c["options"], {"music": false})
	assert_eq((c["players"] as Array).size(), 3)
	assert_eq((c["local_riders"] as Dictionary).keys(), [2], "clients never simulate bots")
	assert_eq(c["session_start"], start)


func test_players_are_sorted_by_slot_index() -> void:
	# OWNERSHIP CTX1: ctx.players is sorted by slot_index, identical on every peer.
	fx.give_profile(220.0, "Bea")
	fx.fake_net().local_peer = 2
	var a := PlayerSlot.new()
	a.peer_id = 1
	a.apply_look(0)
	var b := PlayerSlot.new()
	b.peer_id = 2
	b.apply_look(1)
	var start := {
		"type": "session_start",
		"v": 1,
		"game_id": "workout",
		"game_version": "1.0.0",
		"content_id": "e2e",
		"seed": 1,
		"players": [Bots.make_slot(1, 2, 200.0).to_dict(), b.to_dict(), a.to_dict()],
		"options": {},
		"scaling": Wl.FAIR_FTP,
		"start_tick": 0
	}
	var s := (
		open_screen(AppSessionScreen.new(), {"role": Wl.CLIENT, "session_start": start})
		as AppSessionScreen
	)
	var players: Array[PlayerSlot] = (s.host as FakeHost).config_seen["players"]
	var order: Array[int] = []
	for p in players:
		order.append(p.slot_index)
	assert_eq(order, [0, 1, 2] as Array[int])
	assert_eq(players[2].peer_id, -1, "the bot after the humans")


func test_rejoin_replays_the_message_to_the_game_host() -> void:
	fx.give_profile()
	var net := fx.fake_net()
	net.local_peer = 2
	net.add_human(1, "Ada")
	net.add_human(2, "Ada2")
	net.lobby = {"game_id": "workout", "game_version": "1.0.0", "content_id": "e2e", "settings": {}}
	var seen: Array = []
	net.game_message.connect(func(from: int, data: Dictionary) -> void: seen.append([from, data]))
	var msg := {"type": "phase", "v": 1, "index": 2, "start_tick": 100, "ended_by": "duration"}
	open_screen(
		AppSessionScreen.new(),
		{"role": Wl.CLIENT, "rejoin": true, "replay": [{"from": 1, "data": msg}]}
	)
	assert_eq(
		seen,
		[[1, msg]],
		"the GameHost (connected in setup) gets the message that opened the session"
	)


func test_no_trainer_shows_an_error() -> void:
	fx.give_profile()
	fx.fake_trainer().dev = null
	var s := (
		open_screen(
			AppSessionScreen.new(),
			{"role": Wl.SOLO, "game_id": "workout", "content_id": "easy_30", "quick": true}
		)
		as AppSessionScreen
	)
	assert_null(s.host)
	assert_eq(s.error, "APP_ERR_NO_TRAINER")
	assert_true(s.overlay.visible)
	assert_eq(s.error_label.text, AppScreen.t("APP_ERR_NO_TRAINER"))
	confirm_pick(s, "leave")
	assert_eq(fx.app.state, "title")


func test_setup_error_is_reported() -> void:
	fx.give_profile()
	fx.services.game_host_factory = func() -> GameHost:
		var h := FakeHost.new()
		h.setup_error = "plan rejected: warmup"
		return h
	var s := (
		open_screen(
			AppSessionScreen.new(),
			{"role": Wl.SOLO, "game_id": "workout", "content_id": "easy_30", "quick": true}
		)
		as AppSessionScreen
	)
	assert_eq(s.error, "plan rejected: warmup")
	assert_true(s.error_label.text.contains("plan rejected"))


func test_pause_overlay_and_resume() -> void:
	fx.give_profile()
	var s := (
		open_screen(
			AppSessionScreen.new(),
			{"role": Wl.SOLO, "game_id": "workout", "content_id": "easy_30", "quick": true}
		)
		as AppSessionScreen
	)
	var h := s.host as FakeHost
	assert_false(s.overlay.visible)
	s.feed_action(&"pause")
	assert_eq(h.pause_reasons, ["user"] as Array[String])
	assert_true(s.overlay.visible)
	assert_eq(s.overlay_title.text, AppScreen.t("APP_SESSION_PAUSED"))
	assert_eq(
		s.overlay_detail.text,
		AppScreen.t("APP_SESSION_PAUSED_USER"),
		"a rider's pause resumes from the menu"
	)
	s.feed_action(&"pause")
	assert_eq(h.pause_reasons.size(), 1, "pause never toggles")
	confirm_pick(s, "resume")
	assert_eq(h.resumes, 1)
	assert_false(s.overlay.visible)


## The GameHost ends a pause on not pedaling (1 s at >= 30 rpm, BRIEF 3.5); the screen follows
## its state and never resumes on a gesture itself.
func test_a_pause_on_not_pedaling_ends_with_the_game_host() -> void:
	fx.give_profile()
	var s := (
		open_screen(
			AppSessionScreen.new(),
			{"role": Wl.SOLO, "game_id": "workout", "content_id": "easy_30", "quick": true}
		)
		as AppSessionScreen
	)
	var h := s.host as FakeHost
	h.pause("stop_5s")
	fx.bus.paused_changed.emit(true, "stop_5s")
	assert_true(s.overlay.visible)
	s.feed_gesture(Wl.G_PEDAL_START)
	assert_eq(h.resumes, 0, "no resume from the screen")
	h.resume()
	fx.bus.paused_changed.emit(false, "resume")
	assert_false(s.overlay.visible, "the overlay follows the GameHost")


func test_coasting_pause_holds_resume_so_a_surge_resumes() -> void:
	# A surge from rest must resume, never pick End ride or Panic.
	fx.give_profile()
	var s := (
		open_screen(
			AppSessionScreen.new(),
			{"role": Wl.SOLO, "game_id": "workout", "content_id": "easy_30", "quick": true}
		)
		as AppSessionScreen
	)
	var h := s.host as FakeHost
	h.pause("coasting")
	fx.bus.paused_changed.emit(true, "coasting")
	assert_true(s.auto_paused())
	assert_eq(
		s.overlay_detail.text, AppScreen.t("APP_SESSION_PAUSED_DETAIL"), "pedal again to ride on"
	)
	assert_false(menu(s).scanning, "the auto-pause overlay does not scan")
	assert_eq(menu(s).highlighted(), menu(s).index_of_id("resume"))
	for _i in 10:
		s.tick(1.6)
	assert_eq(menu(s).highlighted(), menu(s).index_of_id("resume"), "Resume stays highlighted")
	s.feed_gesture(Wl.G_SURGE)
	assert_eq(h.resumes, 1, "the surge resumed the ride")
	assert_eq(h.ended_reasons.size(), 0)
	assert_eq((fx.trainer.local_rider() as FakeRider).panics, 0)


func test_a_user_pause_menu_scans() -> void:
	fx.give_profile()
	var s := (
		open_screen(
			AppSessionScreen.new(),
			{"role": Wl.SOLO, "game_id": "workout", "content_id": "easy_30", "quick": true}
		)
		as AppSessionScreen
	)
	s.feed_action(&"pause")
	assert_false(s.auto_paused())
	assert_true(menu(s).scanning, "a pause the rider asked for scans like any menu")


## A solo session from a lobby whose own slot has `autopilot`, with a router that would not scan
## (the fake's pedal_nav = false: pedal UI off and a device used).
func _autopilot_session(autopilot: bool) -> AppSessionScreen:
	fx.give_profile(250.0)
	fx.input.set("pedal_nav", false)
	var net := fx.fake_net()
	net.local_peer = 1
	net.add_human(1, "Ada", 250.0).autopilot = autopilot
	net.lobby = {
		"game_id": "workout",
		"game_version": "1.0.0",
		"content_id": "easy_30",
		"scaling": Wl.FAIR_FTP,
		"settings": {}
	}
	return (
		open_screen(
			AppSessionScreen.new(), {"role": Wl.SOLO, "game_id": "workout", "content_id": "easy_30"}
		)
		as AppSessionScreen
	)


## BRIEF 3.5 "with Autopilot or pedal UI on": the Autopilot the rider chose in the lobby (their
## slot's flag) makes the pause menu and the results scan.
func test_session_autopilot_scans_the_pause_menu_and_results() -> void:
	var s := _autopilot_session(true)
	assert_true(s.session_autopilot(), "the rider's own slot rides on Autopilot")
	assert_true(s.scanning_enabled())
	s.feed_action(&"pause")
	assert_true(s.overlay.visible)
	assert_true(menu(s).scanning, "the pause menu scans")
	(s.host as FakeHost).finish_with(GameResults.new())
	assert_eq(fx.app.state, "results")
	assert_true(fx.app.params["autopilot"], "results learn the session's Autopilot")
	var r := open_screen(AppResultsScreen.new(), fx.app.params) as AppResultsScreen
	assert_true(menu(r).scanning, "the results menu scans")


func test_without_autopilot_the_session_follows_the_router() -> void:
	var s := _autopilot_session(false)
	assert_false(s.session_autopilot())
	s.feed_action(&"pause")
	assert_true(s.overlay.visible)
	assert_false(menu(s).scanning, "the router says no and Autopilot is off")
	(s.host as FakeHost).finish_with(GameResults.new())
	assert_false(fx.app.params["autopilot"])
	var r := open_screen(AppResultsScreen.new(), fx.app.params) as AppResultsScreen
	assert_false(menu(r).scanning)


func test_an_autopilot_session_still_holds_resume_on_a_coasting_pause() -> void:
	var s := _autopilot_session(true)
	(s.host as FakeHost).pause("coasting")
	fx.bus.paused_changed.emit(true, "coasting")
	assert_true(s.auto_paused())
	assert_false(menu(s).scanning, "the auto-pause overlay holds Resume, Autopilot or not")
	assert_eq(menu(s).highlighted(), menu(s).index_of_id("resume"))


## A client (peer 2) from a session_start whose players are the host (peer 1, a human), the
## client's own slot and a bot (which always rides on Autopilot), with a router that would not
## scan (the fake's pedal_nav = false).
func _client_session(my_autopilot: bool, host_autopilot: bool) -> AppSessionScreen:
	fx.give_profile()
	fx.input.set("pedal_nav", false)
	var net := fx.fake_net()
	net.local_peer = 2
	var host := PlayerSlot.new()
	host.peer_id = 1
	host.name = "Host"
	host.apply_look(0)
	host.autopilot = host_autopilot
	var me := PlayerSlot.new()
	me.peer_id = 2
	me.name = "Me"
	me.apply_look(1)
	me.autopilot = my_autopilot
	var bot := Bots.make_slot(1, 2, 200.0)
	assert_true(bot.autopilot and bot.is_bot, "precondition: the bot rides on Autopilot")
	var start := {
		"type": "session_start",
		"game_id": "workout",
		"content_id": "e2e",
		"seed": 1,
		"players": [host.to_dict(), me.to_dict(), bot.to_dict()],
		"options": {},
		"scaling": Wl.FAIR_FTP
	}
	var s := (
		open_screen(AppSessionScreen.new(), {"role": Wl.CLIENT, "session_start": start})
		as AppSessionScreen
	)
	assert_eq(s.local_peer(), 2, "precondition: the client is peer 2")
	assert_eq(
		(s.config.get("players", []) as Array).size(), 3, "precondition: host, client and bot"
	)
	return s


func test_a_client_reads_its_autopilot_from_session_start() -> void:
	var s := _client_session(true, false)
	assert_true(s.session_autopilot(), "the client's own slot from session_start")
	assert_true(s.scanning_enabled())
	s.feed_action(&"pause")
	assert_true(s.overlay.visible)
	assert_true(menu(s).scanning, "the client's pause menu scans")


## Only the client's own slot counts: the host's and the bot's Autopilot leave it off while the
## router says no.
func test_a_client_without_autopilot_ignores_the_other_slots() -> void:
	var s := _client_session(false, true)
	assert_false(s.session_autopilot(), "the host's and the bot's Autopilot are not the client's")
	assert_false(s.scanning_enabled(), "and the router says no")
	s.feed_action(&"pause")
	assert_true(s.overlay.visible)
	assert_false(menu(s).scanning, "the client's pause menu does not scan")


func test_metronome_runs_during_the_session_when_on() -> void:
	var p := fx.give_profile()
	p.metronome = true
	p.preferred_cadence_rpm = 85.0
	var s := (
		open_screen(
			AppSessionScreen.new(),
			{"role": Wl.SOLO, "game_id": "workout", "content_id": "easy_30", "quick": true}
		)
		as AppSessionScreen
	)
	assert_eq(fx.fake_sfx().metronome_calls, [[85.0, true]])
	s.leave()
	assert_eq(
		fx.fake_sfx().metronome_calls,
		[[85.0, true], [0.0, false]],
		"stopped when the session screen goes"
	)


func test_no_metronome_when_off() -> void:
	fx.give_profile()
	var s := (
		open_screen(
			AppSessionScreen.new(),
			{"role": Wl.SOLO, "game_id": "workout", "content_id": "easy_30", "quick": true}
		)
		as AppSessionScreen
	)
	s.leave()
	assert_eq(fx.fake_sfx().metronome_calls, [])


func test_on_screen_panic() -> void:
	fx.give_profile()
	var s := (
		open_screen(
			AppSessionScreen.new(),
			{"role": Wl.SOLO, "game_id": "workout", "content_id": "easy_30", "quick": true}
		)
		as AppSessionScreen
	)
	watch_signals(fx.bus)
	s.panic_button.pressed.emit()
	assert_signal_emitted(fx.bus, "panic_requested")
	assert_eq((fx.trainer.local_rider() as FakeRider).panics, 1)
	assert_true(s.panicked)
	assert_true(s.overlay.visible)
	assert_eq(menu(s).ids(), ["resume_trainer", "end"])
	confirm_pick(s, "resume_trainer")
	assert_false(s.panicked)


func test_panic_action_goes_safe_at_once() -> void:
	fx.give_profile()
	var s := (
		open_screen(
			AppSessionScreen.new(),
			{"role": Wl.SOLO, "game_id": "workout", "content_id": "easy_30", "quick": true}
		)
		as AppSessionScreen
	)
	fx.input.inject_action(&"panic")
	assert_eq((fx.trainer.local_rider() as FakeRider).panics, 1)
	assert_true(s.panicked)


func test_finish_opens_results_with_fit_and_summary() -> void:
	fx.give_profile()
	var s := (
		open_screen(
			AppSessionScreen.new(),
			{"role": Wl.SOLO, "game_id": "workout", "content_id": "easy_30", "quick": true}
		)
		as AppSessionScreen
	)
	var h := s.host as FakeHost
	fx.bus.unlocks_ready.emit(["WORKOUT_BADGE"])
	fx.bus.ride_saved.emit("C:/rides/a.fit", {"ride_id": "r-1"})
	h.fits = {1: "C:/rides/a.fit"}
	var r := GameResults.new()
	r.grade = "B"
	h.finish_with(r)
	assert_eq(fx.app.state, "results")
	var p := fx.app.params
	assert_eq(p["results"], r)
	assert_eq(p["fit_path"], "C:/rides/a.fit")
	assert_eq(p["summary"], {"ride_id": "r-1"})
	assert_eq(p["unlocks"], ["WORKOUT_BADGE"])
	assert_eq(p["game_id"], "workout")


func test_end_ride_from_the_menu() -> void:
	fx.give_profile()
	var s := (
		open_screen(
			AppSessionScreen.new(),
			{"role": Wl.SOLO, "game_id": "workout", "content_id": "easy_30", "quick": true}
		)
		as AppSessionScreen
	)
	s.feed_action(&"back")
	assert_true(s.overlay.visible)
	confirm_pick(s, "end")
	assert_eq((s.host as FakeHost).ended_reasons, ["ended_by_rider"] as Array[String])
	assert_eq(fx.app.state, "results")


func test_client_host_left_ends_with_results() -> void:
	fx.give_profile()
	var net := fx.fake_net()
	net.local_peer = 2
	var start := {
		"type": "session_start",
		"game_id": "workout",
		"content_id": "e2e",
		"seed": 1,
		"players": [Bots.make_slot(1, 0, 200.0).to_dict()],
		"options": {},
		"scaling": Wl.FAIR_FTP
	}
	var b := PlayerSlot.new()
	b.peer_id = 2
	(start["players"] as Array).append(b.to_dict())
	open_screen(AppSessionScreen.new(), {"role": Wl.CLIENT, "session_start": start})
	net.refuse("host_left")
	assert_eq(fx.app.state, "results")
	assert_true(fx.app.params["host_left"])


func test_read_summary_falls_back_to_the_json_next_to_the_fit() -> void:
	var dir := Paths.user_dir().path_join("rides")
	DirAccess.make_dir_recursive_absolute(dir)
	var fit := dir.path_join("x.fit")
	var f := FileAccess.open(dir.path_join("x.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"ride_id": "x1"}))
	f.close()
	assert_eq(AppSessionScreen.read_summary(null, fit), {"ride_id": "x1"})
	assert_eq(
		AppSessionScreen.read_summary(null, dir.path_join("none.fit")),
		{"fit_path": dir.path_join("none.fit")}
	)
	assert_eq(AppSessionScreen.read_summary(null, ""), {})
