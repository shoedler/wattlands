extends "res://tests/app/app_test_base.gd"
## Room-code entry (BRIEF 3.5, 5.2): case-insensitive, dashes and spaces ignored, O -> 0 and
## I/L -> 1, at most 6 Crockford characters, shown as K7Q-X2M; an on-screen keyboard usable by
## controller and pedal-scan; joining needs only the code.


func test_filter_normalises() -> void:
	assert_eq(AppCodeInput.filter("k7q-x2m"), "K7QX2M")
	assert_eq(AppCodeInput.filter(" K7Q X2M "), "K7QX2M")
	assert_eq(AppCodeInput.filter("K7Q - X2M"), "K7QX2M")
	assert_eq(AppCodeInput.filter("o0-il"), "0011")
	assert_eq(AppCodeInput.filter("ABCDEFGH"), "ABCDEF", "at most 6 characters")
	assert_eq(AppCodeInput.filter("AU!B"), "AB", "U and symbols are not in the alphabet")


func test_append_and_backspace() -> void:
	var c := ""
	for ch in "k7q-x2m9":
		c = AppCodeInput.append(c, ch)
	assert_eq(c, "K7QX2M", "dash ignored, extra character ignored")
	assert_eq(AppCodeInput.backspace(c), "K7QX2")
	assert_eq(AppCodeInput.backspace(""), "")
	assert_eq(AppCodeInput.append("K7", "u"), "K7", "invalid characters are ignored")


func test_display_and_complete() -> void:
	assert_eq(AppCodeInput.display("K7QX"), "K7Q-X__")
	assert_eq(AppCodeInput.display("K7"), "K7_-___")
	assert_eq(AppCodeInput.display("K7QX2M"), "K7Q-X2M")
	assert_eq(AppCodeInput.display("K7QX", false), "K7Q-X")
	assert_true(AppCodeInput.is_complete("k7q-x2m"))
	assert_false(AppCodeInput.is_complete("K7QX2"))
	assert_eq(RoomCode.format(AppCodeInput.filter("k7qx2m")), "K7Q-X2M")


func test_keyboard_rows_cover_the_alphabet() -> void:
	var rows := AppCodeInput.keyboard_rows()
	assert_eq("".join(rows), NetMessages.CODE_ALPHABET)
	for r in rows:
		assert_lte(r.length(), 8)


func test_text_field_code_mode() -> void:
	var f := AppTextField.make_code("Code")
	add_child_autofree(f)
	f.set_value("k7q x2m")
	assert_eq(f.value(), "K7QX2M")
	assert_eq(f.display.text, "K7Q-X2M")
	assert_true(f.is_complete())
	f.append_char("Z")
	assert_eq(f.value(), "K7QX2M", "full code ignores more characters")
	f.line_edit.text_changed.emit("ab-c d")
	assert_eq(f.value(), "ABCD", "typing is filtered")
	assert_eq(f.line_edit.text, "ABCD")
	assert_eq(f.display.text, "ABC-D__")


func test_secret_text_field_never_shows_the_value() -> void:
	var f := AppTextField.make_text("Secret", AppTextField.ROWS_HEX, 64, true)
	add_child_autofree(f)
	f.set_value("abc123")
	assert_false(f.display.text.contains("abc"))
	assert_true(f.line_edit.secret)


func _type_code_by_pedal(s: AppLobbyScreen, code: String) -> void:
	var rows := AppCodeInput.keyboard_rows()
	for ch in code:
		var row := -1
		for i in rows.size():
			if rows[i].contains(ch):
				row = i
		assert_true(scan_to(s, "kb:row:%d" % row), "scan to the row of %s" % ch)
		s.feed_gesture(Wl.G_SURGE)
		assert_true(scan_to(s, "kb:ch:" + ch), "scan to %s" % ch)
		s.feed_gesture(Wl.G_SURGE)


func test_join_with_the_on_screen_keyboard_by_pedal() -> void:
	fx.give_profile()
	var s := open_screen(AppLobbyScreen.new(), {"mode": "join"}) as AppLobbyScreen
	assert_true(menu(s).is_disabled_id(AppKeyboard.ID_DONE), "Join waits for 6 characters")
	_type_code_by_pedal(s, "K7QX2M")
	assert_eq(s.code_field.value(), "K7QX2M")
	assert_eq(s.code_field.display.text, "K7Q-X2M")
	assert_false(menu(s).is_disabled_id(AppKeyboard.ID_DONE))
	assert_true(scan_to(s, AppKeyboard.ID_DONE))
	s.feed_gesture(Wl.G_SURGE)
	assert_eq(fx.fake_net().last_call("join_room"), ["join_room", "K7QX2M"])
	assert_eq(s.page, AppLobbyScreen.PAGE_CONNECTING)
	assert_eq(s.code_label.text, "K7Q-X2M")


func test_join_by_typing_with_dashes_and_spaces() -> void:
	fx.give_profile()
	var s := open_screen(AppLobbyScreen.new(), {"mode": "join"}) as AppLobbyScreen
	s.code_field.line_edit.text_changed.emit("k7q - x2m")
	s.code_field.line_edit.text_submitted.emit(s.code_field.line_edit.text)
	assert_eq(fx.fake_net().last_call("join_room"), ["join_room", "K7QX2M"])


func test_keyboard_delete_and_controller_navigation() -> void:
	fx.give_profile()
	var s := open_screen(AppLobbyScreen.new(), {"mode": "join"}) as AppLobbyScreen
	confirm_pick(s, "kb:row:0")
	confirm_pick(s, "kb:ch:7")
	confirm_pick(s, "kb:row:1")
	confirm_pick(s, "kb:ch:A")
	assert_eq(s.code_field.value(), "7A")
	confirm_pick(s, AppKeyboard.ID_DELETE)
	assert_eq(s.code_field.value(), "7")
	confirm_pick(s, "kb:row:2")
	s.feed_action(&"back")
	assert_eq(s.menus.size(), 1, "back closes the row")
	assert_eq(s.code_field.value(), "7")


func test_join_refused_shows_the_reason_and_returns_to_entry() -> void:
	fx.give_profile()
	var s := open_screen(AppLobbyScreen.new(), {"mode": "join"}) as AppLobbyScreen
	s.join_code("K7Q-X2M")
	fx.fake_net().refuse("session_in_progress")
	assert_eq(s.page, AppLobbyScreen.PAGE_JOIN)
	assert_eq(s.message_label.text, AppScreen.t("APP_REFUSED_IN_PROGRESS"))
	assert_true(s.message_label.visible)
	s.join_code("K7Q-X2")
	assert_eq(s.message_label.text, AppScreen.t("APP_JOIN_BAD_CODE"))


func test_recent_rooms_are_listed_and_joinable() -> void:
	fx.give_profile()
	fx.settings.set_value(
		"recent_rooms",
		[{"code": "ABC123", "role": Wl.CLIENT, "game_id": "workout", "game_title": "Workout"}]
	)
	var s := open_screen(AppLobbyScreen.new(), {"mode": "join"}) as AppLobbyScreen
	assert_true(menu(s).ids().has("recent:ABC123"))
	surge_pick(s, "recent:ABC123")
	assert_eq(fx.fake_net().last_call("join_room"), ["join_room", "ABC123"])


func test_a_coast_on_the_keyboard_keeps_the_half_typed_code() -> void:
	# A pedal-only rider who stops for a moment must not lose the code: the first back (or coast)
	# only highlights Back; a second back, or picking Back, leaves.
	fx.give_profile()
	var s := open_screen(AppLobbyScreen.new(), {"mode": "join"}) as AppLobbyScreen
	confirm_pick(s, "kb:row:0")
	confirm_pick(s, "kb:ch:7")
	s.feed_gesture(Wl.G_COAST)
	assert_eq(s.page, AppLobbyScreen.PAGE_JOIN)
	assert_eq(s.code_field.value(), "7", "the code is kept")
	assert_eq(
		menu(s).highlighted(), menu(s).index_of_id(AppKeyboard.ID_CANCEL), "Back is highlighted"
	)
	assert_ne(fx.app.state, "title")
	s.feed_action(&"back")
	assert_eq(fx.app.state, "title", "a second back leaves")
	assert_eq(fx.fake_net().calls_named("leave").size(), 1)


func test_text_entry_back_keeps_the_text_until_confirmed() -> void:
	fx.give_profile()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	confirm_pick(s, "network")
	confirm_pick(s, "relay")
	s.text_field.set_value("ws://10.0.0.9:8787/v1")
	s.feed_gesture(Wl.G_COAST)
	assert_not_null(s.text_field, "a coast keeps the editor open")
	surge_pick(s, AppKeyboard.ID_CANCEL)
	assert_null(s.text_field, "picking Back closes it")
	assert_ne(
		fx.settings.get_value("relay_url", ""), "ws://10.0.0.9:8787/v1", "cancelled: nothing saved"
	)
