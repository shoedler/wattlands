class_name TestGameSessionSuite
extends GutTest
## What a game's integration suite shares: a fresh user dir per test, the installed games, and one
## session run through the real GameSimRunner, every runner cleaned up afterwards. A session that
## several tests only read is played once per script with shared_session().

var _dirs: Array[String] = []
## Runners made by a test: cleanup() deletes each one's temp root (W3 QT-4).
var _runners: Array[GameSimRunner] = []
## shared_session()'s plays, by game and flags, each played once per script: {report, failed}, where
## failed says what went wrong in the play ("" when nothing did).
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
	_drop_shared()


## A suite that overrides after_all() without super() would leave the shared dir behind: GUT frees
## the script when it is done, so the dir goes then at the latest.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_drop_shared()


func _drop_shared() -> void:
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
## FIT files are read-only too and stay until after_all (or until GUT frees the script, for a suite
## whose after_all() skips super()). A test that changes what it plays plays its own (run_session).
## A play that failed (an assert or an unhandled error while it ran) fails every test that asks for
## it, not only the one that played it.
func shared_session(game_id: String, flags: Array[String]) -> Dictionary:
	var key := "%s %s" % [game_id, " ".join(flags)]
	if not _shared.has(key):
		if _shared_dir == "":
			_shared_dir = Paths.make_temp_dir("game_session_shared")
		var report := _shared_dir.path_join("report_%d.json" % _shared.size())
		var fails: int = get_fail_count()
		var errors: int = get_errors().size()
		var played := _play(game_id, flags, report)
		_shared[key] = {"report": played, "failed": _what_failed(fails, errors)}
	var entry: Dictionary = _shared[key]
	if str(entry["failed"]) != "":
		_shared_play_failed(key, str(entry["failed"]))
	return (entry["report"] as Dictionary).duplicate(true)


## What went wrong since the script had `fails` failed asserts and the test `errors` tracked errors:
## "" when nothing did.
func _what_failed(fails: int, errors: int) -> String:
	var why: Array[String] = []
	var now: int = get_fail_count()
	if now > fails:
		why.append("%d assert(s) failed" % (now - fails))
	var tracked := get_errors()
	for i in range(errors, tracked.size()):
		var e: GutTrackedError = tracked[i]
		if not e.handled and (e.is_push_error() or e.is_engine_error()):
			why.append("%s %s" % [e.code, e.rationale])
	return "; ".join(why)


## Fails the asking test for a shared play that went wrong. test_game_session_suite.gd overrides it to
## check who is told.
func _shared_play_failed(key: String, why: String) -> void:
	fail_test('the shared session "%s" failed when it was played: %s' % [key, why])


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
