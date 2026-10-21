extends "res://tests/app/app_test_base.gd"
## The lobby with the real Workout game (W3 WO-1, ZIH-7):
## - BRIEF 3.7 Workout Director (P0): a rider's own .zwo, put in Paths.user_dir()/workouts/, is
##   offered in the lobby's content picker (pedal-scan selectable) as "zwo:<absolute path>", the
##   page names the folder, and the session preview lists the importer's clamps.
## - BRIEF 3.5 / APP_JOIN_HINT: a code typed on a physical keyboard reaches the code field with
##   no click first.

const FIXTURE_ZWO := "res://tests/fixtures/zwo/caps.zwo"


func _real_registry() -> void:
	fx.services.registry = get_tree().root.get_node("GameRegistry") as WlGameRegistry


## Copies the fixture .zwo into the rider's workouts folder; returns its content id.
func _install_zwo(file_name: String = "My caps.zwo") -> String:
	var dir := AppLobbyModel.workouts_dir()
	var dest := dir.path_join(file_name)
	var f := FileAccess.open(dest, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(FIXTURE_ZWO))
	f.close()
	return "zwo:" + dest


func _labels(root: Node) -> Array[String]:
	var out: Array[String] = []
	for n in root.find_children("*", "Label", true, false):
		out.append((n as Label).text)
	return out


func test_workouts_folder_is_created_under_the_user_dir() -> void:
	var dir := AppLobbyModel.workouts_dir()
	assert_eq(dir, Paths.user_dir().path_join("workouts"))
	assert_true(DirAccess.dir_exists_absolute(dir))


func test_own_zwo_is_listed_picked_by_pedal_and_previewed_with_its_clamps() -> void:
	fx.give_profile(200.0)
	_real_registry()
	var cid := _install_zwo()
	var s := open_screen(AppLobbyScreen.new(), {"mode": "solo", "game_id": "workout"}) as AppLobbyScreen
	assert_true(s.zwo_hint_label.visible, "the page says where .zwo files go")
	assert_true(s.zwo_hint_label.text.contains(AppLobbyModel.workouts_dir()), s.zwo_hint_label.text)
	assert_true(menu(s).ids().has("content"))
	surge_pick(s, "content")
	assert_true(menu(s).ids().has(cid), "the rider's .zwo is in the picker: %s" % str(menu(s).ids()))
	assert_eq(menu(s).text_of(cid), AppScreen.t("APP_CONTENT_ZWO").format(["My caps"]))
	assert_true(scan_to(s, cid), "pedal-scan reaches it")
	s.feed_gesture(Wl.G_SURGE)
	assert_eq(s.content_id, cid)
	var sent: Array = fx.fake_net().last_call("set_game")
	assert_eq(sent[3], cid, "the lobby announces the .zwo content")
	var want: Dictionary = WorkoutSession.load_id(cid, true).preview()
	var clamp_lines: Array = []
	for line: Variant in want.get("lines", []):
		if str(line).contains(GameStrings.new().t("WORKOUT_PREVIEW_CLAMP", {"text": ""}).strip_edges()):
			clamp_lines.append(line)
	assert_false(clamp_lines.is_empty(), "caps.zwo is clamped (160% FTP for 30 s, 110% for 10 min)")
	var shown := _labels(s.preview_box)
	for line: Variant in clamp_lines:
		assert_true(shown.has(str(line)), "the preview shows the clamp \"%s\" (shown: %s)" % [str(line), str(shown)])
	assert_true(shown.has(str(want.get("title", ""))) or shown[0].begins_with(str(want.get("title", ""))), "the .zwo's own name heads the preview")


func test_built_in_contents_still_come_first() -> void:
	fx.give_profile()
	_real_registry()
	var cid := _install_zwo()
	var s := open_screen(AppLobbyScreen.new(), {"mode": "solo", "game_id": "workout"}) as AppLobbyScreen
	var choices := s.content_choices()
	var m := fx.services.registry.manifest("workout")
	assert_eq(choices.slice(0, (m["contents"] as Array).size()), Array(m["contents"]))
	assert_eq(choices.back(), cid)


func test_content_flag_picks_a_zwo_in_the_app() -> void:
	fx.give_profile()
	_real_registry()
	var cid := _install_zwo()
	CmdLine.set_args(PackedStringArray(["--content=" + cid]), true)
	var s := open_screen(AppLobbyScreen.new(), {"mode": "solo", "game_id": "workout"}) as AppLobbyScreen
	assert_eq(s.content_id, cid, "--content=zwo:<path> (HARDWARE_TEST.md 6) preselects it")


func test_a_missing_zwo_falls_back_to_the_default() -> void:
	fx.give_profile()
	_real_registry()
	fx.settings.set_value("last_game", "workout")
	fx.settings.set_value("last_content", "zwo:" + AppLobbyModel.workouts_dir().path_join("gone.zwo"))
	var s := open_screen(AppLobbyScreen.new(), {"mode": "solo", "game_id": "workout"}) as AppLobbyScreen
	assert_eq(s.content_id, str(fx.services.registry.manifest("workout")["default_content"]))


func test_games_without_the_zwo_scheme_list_no_files() -> void:
	fx.give_profile()
	_install_zwo()
	var s := open_screen(AppLobbyScreen.new(), {"mode": "solo", "game_id": "siege"}) as AppLobbyScreen
	assert_false(s.zwo_hint_label.visible)
	for c in s.content_choices():
		assert_false(c.begins_with("zwo:"))


func test_content_available_rule() -> void:
	var m := {"contents": ["a"], "content_schemes": ["zwo"]}
	var cid := _install_zwo("x.zwo")
	assert_true(AppLobbyModel.content_available(m, "a"))
	assert_true(AppLobbyModel.content_available(m, cid))
	assert_false(AppLobbyModel.content_available(m, "zwo:C:/nowhere/none.zwo"))
	assert_false(AppLobbyModel.content_available({"contents": ["a"]}, cid), "no scheme, no file content")
	assert_false(AppLobbyModel.content_available(m, ""))


# --- typing a room code (ZIH-7) -------------------------------------------------------------------

func _key(ch: String) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = OS.find_keycode_from_string(ch)
	ev.physical_keycode = ev.keycode
	ev.unicode = ch.unicode_at(0)
	ev.pressed = true
	return ev


func test_typing_a_code_on_the_join_page_reaches_the_field() -> void:
	fx.give_profile()
	var s := open_screen(AppLobbyScreen.new(), {"mode": "join"}) as AppLobbyScreen
	await wait_process_frames(2)
	for ch in "K7QX2M":
		var ev := _key(ch)
		get_viewport().push_input(ev)
		var up := ev.duplicate() as InputEventKey
		up.pressed = false
		get_viewport().push_input(up)
	await wait_process_frames(1)
	assert_eq(s.code_field.value(), "K7QX2M", "focus owner: %s" % str(get_viewport().gui_get_focus_owner()))
	assert_true(s.text_focus, "the field owns the keyboard from the first character on")


func test_only_code_characters_start_typing() -> void:
	fx.give_profile()
	var s := open_screen(AppLobbyScreen.new(), {"mode": "join"}) as AppLobbyScreen
	await wait_process_frames(1)
	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.physical_keycode = KEY_DOWN
	down.pressed = true
	assert_false(s.take_typed_key(down), "arrows keep moving the on-screen keyboard")
	var dash := _key("-")
	assert_false(s.take_typed_key(dash), "a dash is ignored in codes and starts nothing")
	assert_eq(s.code_field.value(), "")
	assert_true(s.take_typed_key(_key("k")), "a code letter starts typing")
	assert_eq(s.code_field.value(), "K")
