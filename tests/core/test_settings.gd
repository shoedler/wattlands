extends GutTest
## WlSettings (BRIEF 3.2, 6): profile.json and settings.json under Paths.user_dir(),
## defaults for missing and corrupt files, run-only overrides, recent rooms and signals.

const Util := preload("res://tests/core/helpers/core_test_util.gd")

var _dirs: Array[String] = []
var _bus: WlEventBus = null


func before_each() -> void:
	CmdLine.set_args(PackedStringArray(), true)
	Paths.set_override(_temp())
	_bus = WlEventBus.new()
	autofree(_bus)


func after_each() -> void:
	Paths.set_override("")
	CmdLine.set_args(PackedStringArray(), false)
	for d in _dirs:
		Util.remove_tree(d)
	_dirs.clear()


func _temp() -> String:
	var d := Paths.make_temp_dir("wattlands_settings_test")
	_dirs.append(d)
	return d


func _make() -> WlSettings:
	var s := WlSettings.new()
	s.bus = _bus
	autofree(s)
	return s


func test_missing_files_give_defaults() -> void:
	var s := _make()
	s.load_all()
	assert_false(s.has_profile())
	assert_eq(s.profile.to_dict(), RiderProfile.new().to_dict())
	for key: String in WlSettings.DEFAULTS.keys():
		assert_eq(s.get_value(key), WlSettings.DEFAULTS[key], key)
	assert_eq(s.relay_url(), "ws://localhost:8787/v1")
	assert_eq(s.strava_api_base(), "https://www.strava.com/api/v3")
	assert_eq(s.strava_oauth_base(), "https://www.strava.com/oauth")
	assert_eq(s.scaling_mode(), Wl.FAIR_FTP)
	assert_eq(s.recent_rooms(), [])
	assert_push_warning_count(0, "a first run is not a warning")
	assert_false(FileAccess.file_exists(Paths.settings_path()), "loading writes nothing")


func test_profile_round_trip() -> void:
	var s := _make()
	s.load_all()
	s.profile.display_name = "Simon"
	s.profile.ftp_w = 265.0
	s.profile.ftp_verified = true
	s.profile.cp_w = 270.0
	s.profile.weight_kg = 68.5
	s.profile.haptics_on = false
	s.profile.grade_min_pct = -3.0
	s.profile.created = true
	assert_true(s.save_profile())
	assert_true(FileAccess.file_exists(Paths.profile_path()))
	var t := _make()
	t.load_all()
	assert_eq(t.profile.to_dict(), s.profile.to_dict())
	assert_true(t.has_profile())


func test_settings_round_trip() -> void:
	var s := _make()
	s.load_all()
	s.set_value("relay_url", "wss://relay.example.org/v1")
	s.set_value("scaling_mode", Wl.WKG)
	s.set_value("last_device", {"address": "AA:BB", "name": "KICKR CORE 1234"})
	s.set_value("master_volume_db", -6)
	s.set_value("fullscreen", true)
	s.set_value("locale", "de")
	s.set_value("ui_metronome_bpm", 92)
	var t := _make()
	t.load_all()
	assert_eq(t.relay_url(), "wss://relay.example.org/v1")
	assert_eq(t.scaling_mode(), Wl.WKG)
	assert_eq(t.get_value("last_device"), {"address": "AA:BB", "name": "KICKR CORE 1234"})
	assert_eq(t.get_value("master_volume_db"), -6.0)
	assert_typeof(t.get_value("master_volume_db"), TYPE_FLOAT)
	assert_eq(t.get_value("fullscreen"), true)
	assert_eq(t.get_value("locale"), "de")
	assert_eq(int(t.get_value("ui_metronome_bpm")), 92, "other modules' keys survive")
	assert_eq(t.get_value("no_such_key", "fallback"), "fallback")


func test_corrupt_profile_gives_defaults() -> void:
	Util.write_text(Paths.profile_path(), "{\"display_name\": \"Ann\", oops")
	var s := _make()
	s.load_all()
	assert_push_warning("corrupt")
	assert_eq(s.profile.to_dict(), RiderProfile.new().to_dict())
	assert_false(s.has_profile())


func test_profile_that_is_not_an_object_gives_defaults() -> void:
	Util.write_text(Paths.profile_path(), "[1, 2, 3]")
	var s := _make()
	s.load_all()
	assert_push_warning("corrupt")
	assert_eq(s.profile.ftp_w, 200.0)


func test_corrupt_settings_give_defaults() -> void:
	Util.write_text(Paths.settings_path(), "not json at all")
	var s := _make()
	s.load_all()
	assert_push_warning("corrupt")
	assert_eq(s.relay_url(), "ws://localhost:8787/v1")
	assert_eq(s.recent_rooms(), [])


func test_empty_settings_file_gives_defaults() -> void:
	Util.write_text(Paths.settings_path(), "")
	var s := _make()
	s.load_all()
	assert_push_warning("corrupt")
	assert_eq(s.get_value("fullscreen"), false)


func test_bad_profile_values_are_dropped_or_clamped() -> void:
	Util.write_text(Paths.profile_path(), JSON.stringify({
		"display_name": "Ann", "ftp_w": "lots", "weight_kg": 5000, "units": "furlongs",
		"preferred_cadence_rpm": 85, "created": true, "unknown_key": 1,
	}))
	var s := _make()
	s.load_all()
	assert_push_warning("ftp_w")
	assert_push_warning("weight_kg")
	assert_push_warning("units")
	assert_eq(s.profile.display_name, "Ann")
	assert_eq(s.profile.ftp_w, 200.0, "wrong type keeps the default")
	assert_eq(s.profile.weight_kg, 300.0, "clamped into range")
	assert_eq(s.profile.units, "metric")
	assert_eq(s.profile.preferred_cadence_rpm, 85.0)
	assert_true(s.has_profile())


func test_grade_range_edges_load_cleanly() -> void:
	Util.write_text(Paths.profile_path(), JSON.stringify({"grade_min_pct": -1, "grade_max_pct": 0, "created": true}))
	var s := _make()
	s.load_all()
	assert_eq(s.profile.grade_min_pct, -1.0)
	assert_eq(s.profile.grade_max_pct, 0.0)
	Util.write_text(Paths.profile_path(), JSON.stringify({"grade_min_pct": 0, "grade_max_pct": 0, "created": true}))
	s.load_all()
	assert_eq(s.profile.grade_min_pct, 0.0, "an empty range is still ordered")
	assert_push_warning_count(0)


func test_bad_settings_values_are_ignored() -> void:
	Util.write_text(Paths.settings_path(), JSON.stringify({
		"relay_url": 5, "fullscreen": "yes", "master_volume_db": -12, "scaling_mode": "FAST",
		"custom": {"a": 1},
	}))
	var s := _make()
	s.load_all()
	assert_push_warning("relay_url")
	assert_push_warning("fullscreen")
	assert_push_warning("scaling_mode")
	assert_eq(s.relay_url(), "ws://localhost:8787/v1")
	assert_eq(s.get_value("fullscreen"), false)
	assert_eq(s.get_value("master_volume_db"), -12.0)
	assert_eq(s.scaling_mode(), Wl.FAIR_FTP)
	assert_eq(s.get_value("custom"), {"a": 1.0})


func test_set_value_refuses_wrong_types() -> void:
	var s := _make()
	s.load_all()
	s.set_value("fullscreen", "yes")
	assert_push_error("fullscreen")
	assert_eq(s.get_value("fullscreen"), false)
	s.set_value("scaling_mode", "FAST")
	assert_push_error("scaling_mode")
	assert_eq(s.scaling_mode(), Wl.FAIR_FTP)
	s.set_value("recent_rooms", "K7QX2M")
	assert_push_error("recent_rooms")
	s.set_value("anything", Node)
	assert_push_error("JSON value")
	s.set_value("", 1)
	assert_push_error("empty key")
	assert_false(FileAccess.file_exists(Paths.settings_path()), "nothing was saved")


func test_set_value_refuses_values_json_cannot_hold() -> void:
	var s := _make()
	s.load_all()
	s.set_value("ui_offset", Vector2(1, 2))
	assert_push_error("JSON value")
	s.set_value("ui_list", [1, "a", Color.RED])
	assert_push_error("JSON value")
	s.set_value("ui_map", {1: "int key"})
	assert_push_error("JSON value")
	s.set_value("ui_nan", NAN)
	assert_push_error("JSON value")
	assert_eq(s.get_value("ui_offset", "none"), "none")
	s.set_value("ui_ok", {"a": [1, 2.5, "x", true, null, {"b": &"name"}]})
	assert_eq(s.get_value("ui_ok"), {"a": [1, 2.5, "x", true, null, {"b": &"name"}]})
	var t := _make()
	t.load_all()
	assert_eq(t.get_value("ui_ok"), {"a": [1.0, 2.5, "x", true, null, {"b": "name"}]}, "round-trips through JSON")


func test_set_last_device_stores_json_safe_values() -> void:
	var s := _make()
	s.load_all()
	s.set_last_device({"address": "AA:BB", "name": "KICKR CORE", "rssi": -60,
		"services": PackedStringArray(["1826", "1818"])})
	var t := _make()
	t.load_all()
	assert_eq(t.get_value("last_device"), {"address": "AA:BB", "name": "KICKR CORE", "rssi": -60.0,
		"services": ["1826", "1818"]})


func test_set_value_emits_changed_once_per_change() -> void:
	var s := _make()
	s.load_all()
	watch_signals(s)
	watch_signals(_bus)
	s.set_value("locale", "de")
	assert_signal_emitted_with_parameters(s, "changed", ["locale"])
	assert_signal_emitted_with_parameters(_bus, "settings_changed", ["locale"])
	s.set_value("locale", "de")
	assert_signal_emit_count(s, "changed", 1, "no signal when nothing changed")
	assert_signal_emit_count(_bus, "settings_changed", 1)


func test_autosave() -> void:
	var s := _make()
	s.load_all()
	s.set_value("locale", "fr")
	assert_eq((Util.read_json(Paths.settings_path()) as Dictionary).get("locale"), "fr")
	s.autosave = false
	s.set_value("locale", "it")
	assert_eq((Util.read_json(Paths.settings_path()) as Dictionary).get("locale"), "fr", "not saved yet")
	assert_true(s.save_settings())
	assert_eq((Util.read_json(Paths.settings_path()) as Dictionary).get("locale"), "it")
	assert_false(FileAccess.file_exists(Paths.settings_path() + ".tmp"), "no temp file left")


func test_save_profile_and_load_all_emit() -> void:
	var s := _make()
	watch_signals(s)
	watch_signals(_bus)
	s.load_all()
	assert_signal_emitted_with_parameters(s, "changed", [""])
	assert_signal_emitted(_bus, "profile_changed")
	assert_signal_emitted_with_parameters(_bus, "settings_changed", [""])
	s.profile.ftp_w = 250.0
	s.save_profile()
	assert_signal_emitted_with_parameters(s, "changed", ["profile"])
	assert_signal_emit_count(_bus, "profile_changed", 2)


func test_create_profile() -> void:
	var s := _make()
	s.load_all()
	assert_true(s.create_profile("Rider"))
	assert_true(s.has_profile())
	assert_eq(s.profile.display_name, "Rider")
	assert_eq(s.profile.ftp_w, 200.0)
	assert_false(s.profile.ftp_verified)
	var t := _make()
	t.load_all()
	assert_true(t.has_profile())
	assert_eq(t.profile.display_name, "Rider")
	s.create_profile("   ")
	assert_eq(s.profile.display_name, "Rider", "blank names fall back to Rider")


func test_relay_override_is_used_but_never_saved() -> void:
	var s := _make()
	s.load_all()
	s.set_value("relay_url", "wss://stored.example/v1")
	CmdLine.set_args(PackedStringArray(["--relay=ws://127.0.0.1:9999/v1"]))
	assert_eq(s.relay_url(), "ws://127.0.0.1:9999/v1")
	assert_eq(s.get_value("relay_url"), "ws://127.0.0.1:9999/v1")
	assert_true(s.is_overridden("relay_url"))
	assert_false(s.is_overridden("locale"))
	s.set_value("locale", "de")
	assert_true(s.save_settings())
	var saved: Dictionary = Util.read_json(Paths.settings_path())
	assert_eq(saved.get("relay_url"), "wss://stored.example/v1")
	assert_false(Util.read_text(Paths.settings_path()).contains("9999"))
	CmdLine.set_args(PackedStringArray(), true)
	assert_eq(s.relay_url(), "wss://stored.example/v1")
	assert_false(s.is_overridden("relay_url"))


func test_strava_base_override_sets_both_bases() -> void:
	var s := _make()
	s.load_all()
	CmdLine.set_args(PackedStringArray(["--strava-base=http://127.0.0.1:8899/"]))
	assert_eq(s.strava_api_base(), "http://127.0.0.1:8899/api/v3")
	assert_eq(s.strava_oauth_base(), "http://127.0.0.1:8899/oauth")
	assert_true(s.is_overridden("strava_api_base"))
	assert_true(s.is_overridden("strava_oauth_base"))
	s.save_settings()
	assert_false(Util.read_text(Paths.settings_path()).contains("8899"), "never saved")
	CmdLine.set_args(PackedStringArray(["--strava-base=http://localhost:1/api/v3"]))
	assert_eq(s.strava_api_base(), "http://localhost:1/api/v3")
	assert_eq(s.strava_oauth_base(), "http://localhost:1/oauth")
	CmdLine.set_args(PackedStringArray(["--strava-base"]))
	assert_eq(s.strava_api_base(), "https://www.strava.com/api/v3", "a bare flag is ignored")


func test_recent_rooms_newest_first_max_eight() -> void:
	var s := _make()
	s.load_all()
	var codes: Array[String] = []
	for i in 10:
		var code := "K7QX%02d" % i
		codes.append(code)
		s.add_recent_room(code, Wl.HOST if i % 2 == 0 else Wl.CLIENT, 1000 + i)
	var rooms := s.recent_rooms()
	assert_eq(rooms.size(), WlSettings.MAX_RECENT_ROOMS)
	assert_eq(rooms[0], {"code": "K7QX09", "at": 1009, "role": Wl.CLIENT})
	assert_eq(rooms[7]["code"], "K7QX02")
	s.add_recent_room("k7q-x05", "host", 2000)
	rooms = s.recent_rooms()
	assert_eq(rooms.size(), 8, "re-adding moves, never duplicates")
	assert_eq(rooms[0], {"code": "K7QX05", "at": 2000, "role": Wl.HOST})
	var n := 0
	for r: Dictionary in rooms:
		if r["code"] == "K7QX05":
			n += 1
	assert_eq(n, 1)
	var t := _make()
	t.load_all()
	assert_eq(t.recent_rooms(), rooms, "persisted")
	assert_typeof(t.recent_rooms()[0]["at"], TYPE_INT)


func test_recent_room_default_stamp_is_utc_now() -> void:
	var s := _make()
	s.load_all()
	var before := int(Time.get_unix_time_from_system())
	s.add_recent_room("K7QX2M", Wl.CLIENT)
	var at: int = s.recent_rooms()[0]["at"]
	assert_between(at, before, before + 5)


func test_recent_rooms_refuse_bad_input() -> void:
	var s := _make()
	s.load_all()
	s.add_recent_room("??", Wl.HOST)
	assert_push_error("room code")
	s.add_recent_room("K7QX2M", "spectator")
	assert_push_error("role")
	assert_eq(s.recent_rooms(), [])


func test_recent_rooms_are_cleaned_on_load() -> void:
	Util.write_text(Paths.settings_path(), JSON.stringify({"recent_rooms": [
		{"code": "k7q-x2m", "at": 5.0, "role": "host"},
		{"code": "K7QX2M", "at": 4, "role": "CLIENT"},
		{"code": "bad!", "at": 3, "role": "HOST"},
		{"code": "ABCDEF", "at": 2, "role": "nobody"},
		"junk",
		{"code": "Q1Q1Q1", "at": "x", "role": "CLIENT"},
	]}))
	var s := _make()
	s.load_all()
	assert_eq(s.recent_rooms(), [
		{"code": "K7QX2M", "at": 5, "role": Wl.HOST},
		{"code": "Q1Q1Q1", "at": 0, "role": Wl.CLIENT},
	])


func test_load_all_rereads_after_override_change() -> void:
	var a := _temp()
	var b := _temp()
	Util.write_text(a.path_join("profile.json"), JSON.stringify({"display_name": "A", "created": true}))
	Util.write_text(b.path_join("profile.json"), JSON.stringify({"display_name": "B", "created": true}))
	Util.write_text(b.path_join("settings.json"), JSON.stringify({"locale": "nl"}))
	var s := _make()
	Paths.set_override(a)
	s.load_all()
	assert_eq(s.profile.display_name, "A")
	assert_eq(s.get_value("locale"), "en")
	Paths.set_override(b)
	s.load_all()
	assert_eq(s.profile.display_name, "B")
	assert_eq(s.get_value("locale"), "nl")


func test_set_last_game_and_device() -> void:
	var s := _make()
	s.load_all()
	s.set_last_game("workout", "easy30")
	s.set_last_device({"address": "C0:FF:EE", "name": "KICKR CORE"})
	var t := _make()
	t.load_all()
	assert_eq(t.get_value("last_game"), "workout")
	assert_eq(t.get_value("last_content"), "easy30")
	assert_eq(t.get_value("last_device"), {"address": "C0:FF:EE", "name": "KICKR CORE"})


func test_get_value_returns_copies() -> void:
	var s := _make()
	s.load_all()
	s.add_recent_room("K7QX2M", Wl.HOST, 1)
	var rooms: Array = s.get_value("recent_rooms")
	rooms.clear()
	(s.get_value("last_device") as Dictionary)["x"] = 1
	assert_eq(s.recent_rooms().size(), 1)
	assert_eq(s.get_value("last_device"), {})
