class_name Paths
extends RefCounted
## Every persisted file goes through here (BRIEF 6): profile.json, input.cfg, last device,
## recent rooms, reconnect token, rides and FIT files, the upload queue, strava.json and
## per-game progression. Honours --profile-dir=<abs path>; tests call set_override().

static var _override: String = ""


## The user data root: the override, else --profile-dir, else user://.
## Always returns an absolute OS path and creates it.
static func user_dir() -> String:
	var dir := _override
	if dir == "":
		dir = CmdLine.get_str("profile-dir", "")
	if dir == "":
		dir = ProjectSettings.globalize_path("user://")
	dir = dir.replace("\\", "/").trim_suffix("/")
	_ensure(dir)
	return dir


## Use `dir` as the user dir (tests: a fresh temp dir). "" restores the default.
static func set_override(dir: String) -> void:
	_override = dir.replace("\\", "/").trim_suffix("/")


## The current override set by set_override() ("" when none), so a caller can restore it
## after pointing user_dir() somewhere else for a while (run_game_sim). Added in W2.
static func get_override() -> String:
	return _override


static func profile_path() -> String:
	return user_dir().path_join("profile.json")


static func settings_path() -> String:
	return user_dir().path_join("settings.json")


static func input_cfg_path() -> String:
	return user_dir().path_join("input.cfg")


static func last_device_path() -> String:
	return user_dir().path_join("last_device.json")


static func recent_rooms_path() -> String:
	return user_dir().path_join("recent_rooms.json")


static func reconnect_token_path() -> String:
	return user_dir().path_join("reconnect_token.json")


static func strava_path() -> String:
	return user_dir().path_join("strava.json")


static func rides_dir() -> String:
	var d := user_dir().path_join("rides")
	_ensure(d)
	return d


static func upload_queue_path() -> String:
	return rides_dir().path_join("upload_queue.json")


## Paths.user_dir()/games/<id>/ (created on demand).
static func game_dir(game_id: String) -> String:
	var d := user_dir().path_join("games").path_join(game_id)
	_ensure(d)
	return d


static func progress_path(game_id: String) -> String:
	return game_dir(game_id).path_join("progress.json")


## A fresh, empty temp directory for tests (under the OS temp dir).
static func make_temp_dir(prefix: String = "wattlands_test") -> String:
	var base := OS.get_temp_dir().replace("\\", "/")
	var n := 0
	while true:
		var d := base.path_join("%s_%d_%d" % [prefix, OS.get_process_id(), n])
		if not DirAccess.dir_exists_absolute(d):
			_ensure(d)
			return d
		n += 1
	return base


static func _ensure(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
