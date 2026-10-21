extends "res://tests/app/app_test_base.gd"
## The lobby (BRIEF 3.6, 5.5; OWNERSHIP REG4, PS14, NET7): option widgets for every option type
## (host only, sent in lobby_state.settings.options), per-rider player_options on the rider's
## own card (sent in player_info), content labels, the session preview, bots and the bot FTP,
## trainer status per rider, ready-up, the start, and clear messages for a missing game, a
## version mismatch, session_in_progress and host_left.

var _translation: Translation = null


func after_each() -> void:
	if _translation != null:
		TranslationServer.remove_translation(_translation)
		_translation = null
	super.after_each()


func _host_lobby(game: String = "workout") -> AppLobbyScreen:
	fx.give_profile(250.0)
	fx.fake_net().add_human(1, "Ada", 250.0)
	var s := open_screen(AppLobbyScreen.new(), {"mode": "host", "game_id": game}) as AppLobbyScreen
	fx.fake_net().simulate_hosting("K7QX2M")
	return s


func _client_lobby(lobby: Dictionary) -> AppLobbyScreen:
	fx.give_profile(220.0, "Bea")
	var net := fx.fake_net()
	net.add_human(1, "Ada", 250.0)
	net.add_human(2, "Bea", 220.0)
	var s := open_screen(AppLobbyScreen.new(), {"mode": "join"}) as AppLobbyScreen
	s.join_code("K7QX2M")
	net.simulate_joined(2, "K7QX2M", lobby)
	return s


static func workout_lobby() -> Dictionary:
	return {
		"players": [],
		"game_id": "workout",
		"game_version": "1.0.0",
		"content_id": "sweet_spot",
		"scaling": Wl.FAIR_FTP,
		"settings": {"options": {"music": false, "laps": 3, "theme": "night"}, "bot_ftp": 230.0},
		"ready_flags": {1: true, 2: false},
		"trainers": {1: "ready"},
		"player_options": {1: {"offset": -2}}
	}


func test_option_entries_for_every_type() -> void:
	var s := _host_lobby()
	var ids := menu(s).ids()
	for id: String in ["opt:music", "opt:laps", "opt:theme", "popt:offset"]:
		assert_true(ids.has(id), "menu has %s" % id)
	assert_eq(menu(s).text_of("opt:music"), "music: On", "a missing label key shows the option id")
	assert_eq(menu(s).text_of("opt:laps"), "laps: 2")
	assert_eq(menu(s).text_of("opt:theme"), "theme: day")
	var sent: Dictionary = fx.fake_net().settings_sent["options"]
	assert_eq(sent, {"music": true, "laps": 2, "theme": "day"}, "defaults sent at once")


func test_toggle_option() -> void:
	var s := _host_lobby()
	confirm_pick(s, "opt:music")
	assert_eq(menu(s).ids(), [0, 1])
	assert_eq(menu(s).text_of(1), AppScreen.t("APP_OFF"))
	confirm_pick(s, 1)
	assert_eq(fx.fake_net().settings_sent["options"]["music"], false)
	assert_eq(menu(s).text_of("opt:music"), "music: " + AppScreen.t("APP_OFF"))


func test_int_option_lists_values_on_its_step_grid() -> void:
	var s := _host_lobby()
	confirm_pick(s, "opt:laps")
	assert_eq(menu(s).item_count(), 4, "1..4")
	assert_eq(menu(s).highlighted(), 1, "the current value (2) is highlighted")
	confirm_pick(s, 3)
	assert_eq(fx.fake_net().settings_sent["options"]["laps"], 4)
	assert_typeof(fx.fake_net().settings_sent["options"]["laps"], TYPE_INT)


func test_choice_option_with_labels() -> void:
	_translation = Translation.new()
	_translation.locale = TranslationServer.get_locale()
	_translation.add_message("WORKOUT_THEME_NIGHT", "Night ride")
	_translation.add_message("WORKOUT_OPT_THEME", "Theme")
	_translation.add_message("WORKOUT_CONTENT_SWEET_SPOT", "Sweet spot")
	TranslationServer.add_translation(_translation)
	# A content id with no label key anywhere (the real Workout strings label its own contents).
	(fx.fake_registry().manifests["workout"]["contents"] as Array).append("no_label")
	var s := _host_lobby()
	assert_eq(menu(s).text_of("opt:theme"), "Theme: day", "the label key <ID>_OPT_<OPTION ID>")
	confirm_pick(s, "opt:theme")
	assert_eq(menu(s).text_of(0), "day", "a missing choice label shows the value")
	assert_eq(menu(s).text_of(1), "Night ride")
	confirm_pick(s, 1)
	assert_eq(fx.fake_net().settings_sent["options"]["theme"], "night")
	assert_eq(menu(s).text_of("opt:theme"), "Theme: Night ride")
	confirm_pick(s, "content")
	assert_eq(menu(s).text_of("sweet_spot"), "Sweet spot", "<ID>_CONTENT_<CID> label")
	assert_eq(menu(s).text_of("no_label"), "no_label", "bare id when the key is missing")


func test_long_int_player_option_uses_a_stepper() -> void:
	var s := _host_lobby("siege")
	assert_true(menu(s).ids().has("popt:wave_offset"))
	confirm_pick(s, "popt:wave_offset")
	assert_eq(menu(s).ids(), ["value", "dec", "inc", "dec5", "inc5", "done"], "16 values: stepper")
	confirm_pick(s, "dec5")
	confirm_pick(s, "dec5")
	confirm_pick(s, "dec5")
	assert_eq(s.my_player_options["wave_offset"], -10, "clamped to min")
	confirm_pick(s, "inc")
	confirm_pick(s, "done")
	var info: Dictionary = fx.fake_net().info
	assert_eq(info["player_options"]["wave_offset"], -9, "player_options travel in player_info")
	assert_eq(
		menu(s).text_of("popt:wave_offset"),
		AppScreen.t("APP_LOBBY_MY_OPTION").format(["wave_offset", "-9"])
	)


func test_autopilot_is_toggled_in_the_lobby() -> void:
	# BRIEF 3.5: Autopilot is per player, toggled in the profile or the lobby.
	var s := _host_lobby()
	assert_false(fx.fake_net().info["autopilot"], "the profile default (off)")
	assert_eq(
		menu(s).text_of("autopilot"),
		AppScreen.t("APP_LOBBY_AUTOPILOT").format([AppScreen.t("APP_OFF")])
	)
	surge_pick(s, "autopilot")
	assert_true(s.my_autopilot)
	assert_true(fx.fake_net().info["autopilot"], "sent in player_info")
	assert_eq(
		menu(s).text_of("autopilot"),
		AppScreen.t("APP_LOBBY_AUTOPILOT").format([AppScreen.t("APP_ON")])
	)
	var card := s.cards_box.get_child(0) as AppLobbyCard
	assert_true(
		card.options_label.text.begins_with(AppScreen.t("APP_LOBBY_AUTOPILOT_TAG")),
		"shown on the rider's card"
	)
	assert_false(fx.settings.profile.autopilot_default, "the profile default is unchanged")


func test_autopilot_starts_from_the_profile_and_clients_toggle_it_too() -> void:
	fx.give_profile(220.0, "Bea")
	fx.settings.profile.autopilot_default = true
	var net := fx.fake_net()
	net.add_human(1, "Ada", 250.0)
	net.add_human(2, "Bea", 220.0)
	var s := open_screen(AppLobbyScreen.new(), {"mode": "join"}) as AppLobbyScreen
	s.join_code("K7QX2M")
	net.simulate_joined(2, "K7QX2M", workout_lobby())
	assert_true(net.info["autopilot"])
	confirm_pick(s, "autopilot")
	assert_false(net.info["autopilot"])


func test_own_card_shows_player_options() -> void:
	var s := _host_lobby()
	confirm_pick(s, "popt:offset")
	confirm_pick(s, "inc")
	confirm_pick(s, "done")
	var card := s.cards_box.get_child(0) as AppLobbyCard
	assert_true(card.is_local)
	assert_eq(card.options_label.text, "offset: 1")


func test_client_sees_options_read_only_and_edits_own_options() -> void:
	var s := _client_lobby(workout_lobby())
	var ids := menu(s).ids()
	assert_false(ids.has("opt:music"), "only the host sets game options")
	assert_false(ids.has("content"))
	assert_false(ids.has("add_bot"))
	assert_true(ids.has("ready"))
	assert_true(ids.has("popt:offset"), "a client edits its own player options")
	assert_true(s.info_label.text.contains("laps: 3"), "the host's values are shown")
	assert_true(s.info_label.text.contains("theme: night"))
	confirm_pick(s, "popt:offset")
	confirm_pick(s, "inc")
	confirm_pick(s, "done")
	assert_eq(fx.fake_net().info["player_options"]["offset"], 1)


func test_session_preview_from_the_game_module() -> void:
	var s := _host_lobby()
	var labels: Array[String] = []
	for c in s.preview_box.get_children():
		labels.append((c as Label).text)
	assert_true(labels[0].begins_with("Preview easy_30"), "title from session_preview()")
	assert_true(labels[0].contains("28:00"), "total time")
	assert_true(labels.has("line for easy_30"))
	confirm_pick(s, "content")
	confirm_pick(s, "sweet_spot")
	assert_eq(fx.fake_net().last_call("set_game"), ["set_game", "workout", "1.0.0", "sweet_spot"])
	assert_true((s.preview_box.get_child(0) as Label).text.begins_with("Preview sweet_spot"))


func test_bots_up_to_max_players_and_bot_ftp() -> void:
	var s := _host_lobby("siege")
	assert_eq(fx.fake_net().settings_sent["bot_ftp"], 250.0, "bot FTP defaults to the host's")
	for _i in 3:
		confirm_pick(s, "add_bot")
	assert_eq(fx.fake_net().slots.size(), 4)
	assert_true(menu(s).is_disabled_id("add_bot"), "siege has 4 slots")
	assert_eq(s.cards_box.get_child_count(), 4)
	var bot_card := s.cards_box.get_child(3) as AppLobbyCard
	assert_eq(bot_card.name_label.text, "Bot 3")
	confirm_pick(s, "remove_bot")
	assert_eq(fx.fake_net().slots.size(), 3)
	assert_false(menu(s).is_disabled_id("add_bot"))
	confirm_pick(s, "bot_ftp")
	confirm_pick(s, "dec")
	assert_eq(fx.fake_net().settings_sent["bot_ftp"], 240.0)
	confirm_pick(s, "inc5")
	assert_eq(fx.fake_net().settings_sent["bot_ftp"], 290.0)
	confirm_pick(s, "done")
	assert_eq(menu(s).text_of("bot_ftp"), AppScreen.t("APP_LOBBY_BOT_FTP").format([290]))


func test_no_bot_entries_when_the_game_has_no_bots() -> void:
	var s := _host_lobby("tank")
	assert_false(menu(s).ids().has("add_bot"))
	assert_false(menu(s).ids().has("bot_ftp"))
	assert_false(fx.fake_net().settings_sent.has("bot_ftp"))


func test_trainer_status_per_rider() -> void:
	var s := _client_lobby(workout_lobby())
	var host_card := s.cards_box.get_child(0) as AppLobbyCard
	var my_card := s.cards_box.get_child(1) as AppLobbyCard
	assert_eq(
		host_card.trainer_label.text,
		AppScreen.t("APP_TITLE_TRAINER").format([AppScreen.t("APP_TRAINER_OK")])
	)
	assert_eq(host_card.ready_label.text, AppScreen.t("APP_LOBBY_READY"))
	assert_true(my_card.is_local)
	assert_eq(
		my_card.trainer_label.text,
		AppScreen.t("APP_TITLE_TRAINER").format([AppScreen.t("APP_TRAINER_OK")]),
		"own trainer from TrainerService"
	)
	assert_eq(my_card.ready_label.text, AppScreen.t("APP_LOBBY_NOT_READY"))
	assert_eq(fx.fake_net().info.get("trainer"), TrainerDevice.STATUS_READY)


func test_client_ready_with_pedal_start_or_confirm() -> void:
	var s := _client_lobby(workout_lobby())
	s.feed_gesture(Wl.G_PEDAL_START)
	assert_eq(fx.fake_net().last_call("set_ready"), ["set_ready", true])
	assert_eq(menu(s).text_of("ready"), AppScreen.t("APP_LOBBY_UNREADY"))
	confirm_pick(s, "ready")
	assert_eq(fx.fake_net().last_call("set_ready"), ["set_ready", false])


func test_client_player_info_has_the_profile() -> void:
	_client_lobby(workout_lobby())
	var info: Dictionary = fx.fake_net().info
	assert_eq(info["name"], "Bea")
	assert_eq(info["ftp"], 220.0)
	assert_true(info["ftp_verified"])
	assert_almost_eq(float(info["p_eff_per_w"]), 250.0 / 220.0, 1e-6)
	assert_false(info.has("weight_kg"), "weight stays local unless shared")
	assert_eq(info["games"], {"siege": "0.3.0", "tank": "0.2.0", "workout": "1.0.0"})
	assert_eq(info["player_options"], {"offset": 0})


func test_missing_game_blocks_ready_with_a_message() -> void:
	var lobby := workout_lobby()
	lobby["game_id"] = "kart"
	var s := _client_lobby(lobby)
	assert_true(menu(s).is_disabled_id("ready"))
	assert_eq(s.message_label.text, AppScreen.t("APP_LOBBY_MISSING_GAME").format(["kart"]))
	s.feed_gesture(Wl.G_PEDAL_START)
	assert_eq(fx.fake_net().calls_named("set_ready").size(), 0, "no ready-up without the game")


func test_version_mismatch_blocks_ready_with_a_message() -> void:
	var lobby := workout_lobby()
	lobby["game_version"] = "2.0.0"
	var s := _client_lobby(lobby)
	assert_true(menu(s).is_disabled_id("ready"))
	assert_eq(
		s.message_label.text, AppScreen.t("APP_LOBBY_VERSION_MISMATCH").format(["2.0.0", "1.0.0"])
	)


func test_host_left_message() -> void:
	var s := _client_lobby(workout_lobby())
	fx.fake_net().refuse("host_left")
	assert_eq(
		s.message_label.text, AppScreen.t("APP_LOBBY_HOST_LEFT"), "no ride to save in the lobby"
	)
	assert_eq(menu(s).ids(), ["leave"])
	confirm_pick(s, "leave")
	assert_eq(fx.fake_net().calls_named("leave").size(), 1)
	assert_eq(fx.app.state, "title")


func test_client_answers_no_lobby_echo_with_player_info() -> void:
	# A host answers each player_info with a lobby_state broadcast. The client must not answer
	# that echo with another player_info, even for a game without player_options (Tank).
	var lobby := workout_lobby()
	lobby["game_id"] = "tank"
	lobby["game_version"] = "0.2.0"
	lobby["content_id"] = "ashfall_road"
	var net := fx.fake_net()
	net.echo_player_info = true
	var s := _client_lobby(lobby)
	var sends := net.calls_named("set_local_player_info").size()
	assert_lt(sends, 4, "a bounded number of sends while joining (got %d)" % sends)
	for _i in 5:
		net.lobby_changed.emit(net.lobby)
	assert_eq(
		net.calls_named("set_local_player_info").size(), sends, "lobby_state echoes send nothing"
	)
	assert_eq(s.my_player_options, {}, "tank has no player options")


func test_client_player_options_survive_lobby_echoes() -> void:
	var net := fx.fake_net()
	net.echo_player_info = true
	var s := _client_lobby(workout_lobby())
	confirm_pick(s, "popt:offset")
	confirm_pick(s, "inc")
	confirm_pick(s, "done")
	net.lobby_changed.emit(net.lobby)
	assert_eq(s.my_player_options, {"offset": 1}, "an echo never resets an edited value")
	assert_eq(net.info["player_options"], {"offset": 1})


func test_client_resends_player_info_when_the_host_changes_scaling() -> void:
	var s := _client_lobby(workout_lobby())
	var net := fx.fake_net()
	var before := net.calls_named("set_local_player_info").size()
	assert_almost_eq(float(net.info["p_eff_per_w"]), 250.0 / 220.0, 1e-6)
	net.lobby["scaling"] = Wl.WKG
	net.lobby_changed.emit(net.lobby)
	assert_eq(
		net.calls_named("set_local_player_info").size(),
		before + 1,
		"one resend for the new scaling"
	)
	assert_almost_eq(float(net.info["p_eff_per_w"]), 75.0 / 75.0, 1e-6, "WKG: 75 / weight")
	net.lobby_changed.emit(net.lobby)
	assert_eq(net.calls_named("set_local_player_info").size(), before + 1)
	assert_not_null(s)


func test_refusal_texts() -> void:
	for reason: String in [
		"session_in_progress",
		"version_mismatch",
		"room_not_found",
		"room_full",
		"rate_limited",
		"host_left"
	]:
		var text := AppLobbyScreen.refusal_text(reason)
		assert_ne(text, "", reason)
		assert_false(text.begins_with("APP_"), "%s has a string" % reason)


func test_host_never_starts_before_the_room_exists() -> void:
	fx.give_profile(250.0)
	fx.fake_net().add_human(1, "Ada", 250.0)
	var s := (
		open_screen(AppLobbyScreen.new(), {"mode": "host", "game_id": "workout"}) as AppLobbyScreen
	)
	confirm_pick(s, "start")
	s.tick(0.1)
	assert_ne(fx.app.state, "session", "no room code yet")
	assert_eq(s.message_label.text, AppScreen.t("APP_LOBBY_CREATING"))
	fx.fake_net().simulate_hosting("K7QX2M")
	s.tick(0.1)
	assert_eq(
		fx.app.state, "session", "the room exists and the host is ready: the start goes ahead"
	)


func test_host_starts_once_everyone_is_ready() -> void:
	var s := _host_lobby()
	var net := fx.fake_net()
	net.add_human(2, "Bea")
	confirm_pick(s, "start")
	assert_ne(fx.app.state, "session", "Bea is not ready")
	assert_eq(s.message_label.text, AppScreen.t("APP_LOBBY_WAITING_READY"))
	net.ready_flags[2] = true
	net.lobby_changed.emit(net.lobby)
	assert_eq(fx.app.state, "session")
	assert_eq(fx.app.params, {"role": Wl.HOST, "game_id": "workout", "content_id": "easy_30"})


func test_min_players_needs_bots() -> void:
	fx.give_profile()
	var m := FakeRegistry.siege()
	m["min_players"] = 2
	fx.fake_registry().add_fixture(m)
	fx.fake_net().add_human(1, "Ada")
	var s := (
		open_screen(AppLobbyScreen.new(), {"mode": "solo", "game_id": "siege"}) as AppLobbyScreen
	)
	confirm_pick(s, "start")
	assert_ne(fx.app.state, "session")
	assert_eq(s.message_label.text, AppScreen.t("APP_LOBBY_NEED_PLAYERS").format([2]))
	confirm_pick(s, "add_bot")
	assert_eq(fx.app.state, "session", "a bot fills the second slot and the start goes ahead")


func test_no_trainer_blocks_the_start() -> void:
	var s := _host_lobby()
	fx.fake_trainer().dev = null
	confirm_pick(s, "start")
	assert_ne(fx.app.state, "session")
	assert_eq(s.message_label.text, AppScreen.t("APP_ERR_NO_TRAINER"))


func test_client_follows_session_start() -> void:
	var s := _client_lobby(workout_lobby())
	var start := {
		"type": "session_start",
		"v": 1,
		"game_id": "workout",
		"content_id": "sweet_spot",
		"seed": 42
	}
	fx.fake_net().receive(1, start)
	assert_eq(fx.app.state, "session")
	assert_eq(fx.app.params.get("role"), Wl.CLIENT)
	assert_eq(fx.app.params.get("session_start"), start)
	assert_true(s.launched)


func test_rejoin_opens_the_running_session() -> void:
	_client_lobby(workout_lobby())
	var plan_msg := {"type": "plan", "v": 1, "plan": {}}
	fx.fake_net().receive(1, plan_msg)
	assert_eq(fx.app.state, "session")
	assert_true(fx.app.params.get("rejoin"))
	assert_eq(fx.app.params.get("replay"), [{"from": 1, "data": plan_msg}])


func test_hosting_remembers_the_room_and_reclaims_it() -> void:
	_host_lobby()
	var recent: Array = fx.settings.get_value("recent_rooms", [])
	assert_eq(recent.size(), 1)
	assert_eq(recent[0]["code"], "K7QX2M")
	assert_eq(recent[0]["role"], Wl.HOST)


func test_leave_from_back_needs_a_confirm() -> void:
	var s := _host_lobby()
	s.feed_gesture(Wl.G_COAST)
	assert_eq(fx.app.state, "boot", "a coast only highlights Leave")
	assert_eq(menu(s).highlighted(), menu(s).index_of_id("leave"))
	s.feed_gesture(Wl.G_SURGE)
	assert_eq(fx.app.state, "title")
	assert_eq(fx.fake_net().calls_named("leave").size(), 1)
