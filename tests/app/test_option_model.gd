extends GutTest
## game.json option entries in the lobby (BRIEF 3.6; OWNERSHIP REG4): toggle, int (min, max,
## step default 1) and choice; label keys <ID>_OPT_<OPTION ID>; values keep their JSON types.


func test_toggle() -> void:
	var m := AppOptionModel.make("tank", {"id": "rotation", "type": "toggle", "default": true})
	assert_eq(m.label_key(), "TANK_OPT_ROTATION")
	assert_eq(m.values(), [true, false])
	assert_true(m.default_value())
	assert_eq(m.step_value(true, 1), false)
	assert_eq(m.value_text(true), AppScreen.t("APP_ON"))
	assert_true(m.uses_list())


func test_int_with_step() -> void:
	var m := AppOptionModel.make(
		"fishing", {"id": "reel_pct", "type": "int", "default": 60, "min": 50, "max": 70, "step": 5}
	)
	assert_eq(m.label_key(), "FISHING_OPT_REEL_PCT")
	assert_eq(m.values(), [50, 55, 60, 65, 70])
	assert_eq(m.index_of(60), 2)
	assert_eq(m.step_value(60, 1), 65)
	assert_eq(m.step_value(70, 1), 70, "clamped at max")
	assert_eq(m.normalize(80.0), 70)
	assert_typeof(m.normalize(55.0), TYPE_INT, "JSON floats come back as ints")
	assert_true(m.uses_list())


func test_int_default_step_and_stepper_for_long_ranges() -> void:
	var m := AppOptionModel.make(
		"siege", {"id": "wave_offset", "type": "int", "default": 0, "min": -10, "max": 5}
	)
	assert_eq(m.int_step(), 1)
	assert_eq(m.values().size(), 16)
	assert_false(m.uses_list(), "more than 12 values: stepper")
	assert_eq(m.step_value(0, -5), -5)
	assert_eq(m.step_value(-8, -5), -10)


func test_int_stepper_stays_on_the_step_grid() -> void:
	# min 0, max 10, step 3: the grid is 0, 3, 6, 9 (10 is not on it).
	var m := AppOptionModel.make(
		"x", {"id": "n", "type": "int", "default": 3, "min": 0, "max": 10, "step": 3}
	)
	assert_eq(m.values(), [0, 3, 6, 9])
	assert_eq(m.step_value(9, 1), 9, "the last grid value, never the off-grid max")
	assert_eq(m.step_value(6, 5), 9)
	assert_eq(m.step_value(4, 1), 6, "an off-grid value snaps to 3, then steps")
	assert_eq(m.step_value(5, 0), 6, "snaps to the nearest grid value")
	assert_eq(m.step_value(3, -5), 0)
	var reel := AppOptionModel.make(
		"fishing", {"id": "reel_pct", "type": "int", "default": 60, "min": 50, "max": 70, "step": 5}
	)
	assert_eq(reel.step_value(63, 1), 70, "63 snaps to 65 and steps to 70")
	assert_eq(reel.step_value(60, -1), 55)


func test_choice() -> void:
	var m := AppOptionModel.make(
		"workout",
		{
			"id": "theme",
			"type": "choice",
			"default": "day",
			"choices":
			[{"value": "day", "label": "WORKOUT_THEME_DAY"}, {"value": "night", "label": "Night"}]
		}
	)
	assert_eq(m.values(), ["day", "night"])
	assert_eq(m.value_text("day"), "day", "a missing label key shows the value")
	assert_eq(m.value_text("night"), "Night", "a plain label is shown as is")
	assert_eq(m.step_value("night", 1), "day", "wraps")
	assert_eq(m.normalize("bogus"), "day")


func test_explicit_label_and_defaults() -> void:
	var m := AppOptionModel.make(
		"x", {"id": "a", "type": "toggle", "default": false, "label": "X_CUSTOM"}
	)
	assert_eq(m.label_key(), "X_CUSTOM")
	assert_eq(m.label_text(), "a", "missing key: the option id")
	var d := (
		AppOptionModel
		. defaults(
			"workout",
			[
				{"id": "music", "type": "toggle", "default": true},
				{"id": "laps", "type": "int", "default": 2.0, "min": 1, "max": 4},
			]
		)
	)
	assert_eq(d, {"music": true, "laps": 2})


func test_lobby_model_helpers() -> void:
	var lobby := {
		"ready_flags": {1: true, "2": true},
		"trainers": {3.0: "ready"},
		"player_options": {1: {"a": 1}},
		"settings": {"options": {"x": 1}, "bot_ftp": 240.0},
		"game_id": "g",
		"game_version": "1"
	}
	assert_true(AppLobbyModel.is_ready(lobby, 1))
	assert_true(AppLobbyModel.is_ready(lobby, 2), "string keys too")
	assert_false(AppLobbyModel.is_ready(lobby, 4))
	assert_eq(AppLobbyModel.trainer_status(lobby, 3), "ready", "float keys too")
	assert_eq(AppLobbyModel.player_options_of(lobby, 1), {"a": 1})
	assert_eq(AppLobbyModel.game_options(lobby), {"x": 1})
	assert_eq(AppLobbyModel.bot_ftp(lobby, 200.0), 240.0)
	assert_true(AppLobbyModel.can_add_bot({"bots": true, "max_players": 4}, 3))
	assert_false(AppLobbyModel.can_add_bot({"bots": true, "max_players": 4}, 4))
	assert_false(AppLobbyModel.can_add_bot({"bots": false, "max_players": 4}, 1))
	assert_eq(
		AppLobbyModel.content_label("nogame", "easy_30"),
		"easy_30",
		"bare id when the key is missing"
	)
	assert_eq(
		AppLobbyModel.content_label("workout", "easy_30"),
		AppScreen.t("WORKOUT_CONTENT_EASY_30"),
		"the game's <ID>_CONTENT_<CID> label when its strings are registered"
	)
	assert_eq(AppLobbyModel.zero_input_content({"default_content": "a"}), "a")
	var p := RiderProfile.new()
	p.share_weight = true
	p.weight_kg = 68.0
	var info := AppLobbyModel.player_info(p, Wl.WKG, {}, {}, "ready")
	assert_eq(info["weight_kg"], 68.0, "weight only when the rider opted in")
	assert_almost_eq(float(info["p_eff_per_w"]), 75.0 / 68.0, 1e-6)
	for key: String in NetMessages.GAME["player_info"]["req"]:
		assert_true(info.has(key), "player_info has %s" % key)
