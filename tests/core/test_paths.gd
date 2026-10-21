extends GutTest
## Paths (BRIEF 6): every persisted file under Paths.user_dir(), which honours the test
## override and --profile-dir; make_temp_dir() gives fresh directories.

var _made: Array[String] = []


func after_each() -> void:
	Paths.set_override("")
	CmdLine.set_args(PackedStringArray(), false)
	for d in _made:
		_remove_tree(d)
	_made.clear()


func _temp() -> String:
	var d := Paths.make_temp_dir("wattlands_paths_test")
	_made.append(d)
	return d


static func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in da.get_directories():
		_remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


func test_make_temp_dir_is_fresh() -> void:
	var a := _temp()
	var b := _temp()
	assert_ne(a, b)
	assert_true(DirAccess.dir_exists_absolute(a))
	assert_true(DirAccess.dir_exists_absolute(b))
	assert_eq(DirAccess.get_files_at(a).size(), 0)
	assert_eq(DirAccess.get_directories_at(a).size(), 0)
	assert_false(a.contains("\\"), "forward slashes only")
	assert_true(a.get_file().begins_with("wattlands_paths_test_"))


func test_override_is_the_user_dir() -> void:
	var tmp := _temp()
	Paths.set_override(tmp)
	assert_eq(Paths.user_dir(), tmp)


func test_override_is_normalised() -> void:
	var tmp := _temp()
	Paths.set_override(tmp.replace("/", "\\") + "\\")
	assert_eq(Paths.user_dir(), tmp)
	Paths.set_override(tmp + "/")
	assert_eq(Paths.user_dir(), tmp)


func test_user_dir_is_created() -> void:
	var tmp := _temp().path_join("not_yet/deeper")
	Paths.set_override(tmp)
	assert_false(DirAccess.dir_exists_absolute(tmp))
	assert_eq(Paths.user_dir(), tmp)
	assert_true(DirAccess.dir_exists_absolute(tmp))


func test_every_path_is_under_the_override() -> void:
	var tmp := _temp()
	Paths.set_override(tmp)
	var expected := {
		Paths.profile_path(): "profile.json",
		Paths.settings_path(): "settings.json",
		Paths.input_cfg_path(): "input.cfg",
		Paths.last_device_path(): "last_device.json",
		Paths.recent_rooms_path(): "recent_rooms.json",
		Paths.reconnect_token_path(): "reconnect_token.json",
		Paths.strava_path(): "strava.json",
		Paths.rides_dir(): "rides",
		Paths.upload_queue_path(): "rides/upload_queue.json",
		Paths.game_dir("siege"): "games/siege",
		Paths.progress_path("tank"): "games/tank/progress.json",
	}
	for path: String in expected.keys():
		assert_eq(path, tmp.path_join(expected[path]))


func test_dirs_are_created_on_demand() -> void:
	var tmp := _temp()
	Paths.set_override(tmp)
	assert_true(DirAccess.dir_exists_absolute(Paths.rides_dir()))
	assert_true(DirAccess.dir_exists_absolute(Paths.game_dir("fishing")))
	Paths.progress_path("workout")
	assert_true(DirAccess.dir_exists_absolute(tmp.path_join("games/workout")))
	Paths.upload_queue_path()
	assert_true(DirAccess.dir_exists_absolute(tmp.path_join("rides")))


func test_profile_dir_flag_is_used_without_override() -> void:
	var tmp := _temp()
	CmdLine.set_args(PackedStringArray(["--profile-dir=" + tmp]))
	assert_eq(Paths.user_dir(), tmp)
	assert_eq(Paths.profile_path(), tmp.path_join("profile.json"))


func test_override_wins_over_profile_dir() -> void:
	var flag_dir := _temp()
	var override_dir := _temp()
	CmdLine.set_args(PackedStringArray(["--profile-dir=" + flag_dir]))
	Paths.set_override(override_dir)
	assert_eq(Paths.user_dir(), override_dir)


func test_default_is_the_globalized_user_dir() -> void:
	Paths.set_override("")
	CmdLine.set_args(PackedStringArray(), true)
	var expected := ProjectSettings.globalize_path("user://").replace("\\", "/").trim_suffix("/")
	assert_eq(Paths.user_dir(), expected)
	assert_true(Paths.user_dir().is_absolute_path())
