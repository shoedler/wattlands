class_name TestGameSessionSuite
extends GutTest
## What a game's integration suite shares: a fresh user dir per test, the installed games, and one
## session run through the real GameSimRunner, every runner cleaned up afterwards.

var _dirs: Array[String] = []
## Runners made by a test: cleanup() deletes each one's temp root (W3 QT-4).
var _runners: Array[GameSimRunner] = []


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


## The installed games. A suite overrides it to add a game that is not listed.
func _registry() -> WlGameRegistry:
	var reg := WlGameRegistry.new()
	reg.scan_on_ready = false
	add_child_autofree(reg)
	reg.scan()
	return reg


## Runs one session of `game_id` to its end; the report, with "_end" (why it ended) and "_path".
func run_session(game_id: String, flags: Array[String]) -> Dictionary:
	var report := _dirs[0].path_join("report.json")
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
