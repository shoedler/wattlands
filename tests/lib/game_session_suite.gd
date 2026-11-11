class_name TestGameSessionSuite
extends GutTest
## What a game's integration suite shares: a fresh user dir per test, the installed games, and one
## session run through the real GameSimRunner, every runner cleaned up afterwards. A session that
## several tests only read is played once per script with shared_session().

var _dirs: Array[String] = []
## Runners made by a test: cleanup() deletes each one's temp root (W3 QT-4).
var _runners: Array[GameSimRunner] = []
## Reports of shared_session(), by game and flags; each played once per script.
var _shared: Dictionary = {}
## Where the shared sessions write their reports and FIT files, until after_all.
var _shared_dir: String = ""


func before_each() -> void:
	var d := Paths.make_temp_dir("game_session")
	_dirs.append(d)
	Paths.set_override(d)


func after_each() -> void:
	for r in _runners:
		if is_instance_valid(r):
			r.cleanup()
	_runners.clear()
	Paths.set_override("")
	for d in _dirs:
		GameSimCli.remove_tree(d)
	_dirs.clear()


func after_all() -> void:
	_shared.clear()
	if _shared_dir != "":
		GameSimCli.remove_tree(_shared_dir)
		_shared_dir = ""


## The installed games. A suite overrides it to add a game that is not listed.
func _registry() -> WlGameRegistry:
	var reg := WlGameRegistry.new()
	reg.scan_on_ready = false
	add_child_autofree(reg)
	reg.scan()
	return reg


## Runs one session of `game_id` to its end; the report, with "_end" (why it ended) and "_path".
func run_session(game_id: String, flags: Array[String]) -> Dictionary:
	return _play(game_id, flags, _dirs[0].path_join("report.json"))


## run_session() for a session that tests only read: the first call with these flags plays it, and
## every call returns a deep copy of that report, so no test sees another's changes. Its report and
## FIT files stay until after_all.
func shared_session(game_id: String, flags: Array[String]) -> Dictionary:
	var key := "%s %s" % [game_id, " ".join(flags)]
	if not _shared.has(key):
		if _shared_dir == "":
			_shared_dir = Paths.make_temp_dir("game_session_shared")
		var report := _shared_dir.path_join("report_%d.json" % _shared.size())
		_shared[key] = _play(game_id, flags, report)
	return (_shared[key] as Dictionary).duplicate(true)


func _play(game_id: String, flags: Array[String], report: String) -> Dictionary:
	var args := PackedStringArray(
		["--game=" + game_id, "--report=" + report, "--sim-speed=1000"] + flags
	)
	var parsed := GameSimRunner.parse_args(args)
	assert_false(parsed.has("error"), str(parsed.get("error", "")))
	parsed["headless"] = true
	parsed["registry"] = _registry()
	var runner := GameSimRunner.new()
	add_child_autofree(runner)
	_runners.append(runner)
	assert_eq(runner.setup(parsed), "")
	var reason := runner.run_to_end()
	var out := runner.build_report()
	out["_end"] = reason
	out["_path"] = runner.write_report()
	return out
