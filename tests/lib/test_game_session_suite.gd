extends TestGameSessionSuite
## shared_session(): a session the tests of one script only read is played once for the script,
## each call gets a copy of its own, the files stay until after_all, and a shared play that broke
## fails every test that asks for it. It plays the platform's own `_template` game (never listed,
## so it is added here the way the conformance test adds it), two seconds of its default content,
## so no game's change can break this platform test.

const TEMPLATE_DIR := "res://src/games/_template"
const TEMPLATE := "_template"
const SHORT: Array[String] = ["--players=1", "--seed=3", "--max-sim-seconds=2"]

## When set, _play() pushes an error instead of playing: a shared play that broke.
var _break_play: bool = false
## What _shared_play_failed() was told while _catch_failures is set, instead of failing the test.
var _told: Array[String] = []
var _catch_failures: bool = false


func _registry() -> WlGameRegistry:
	var reg := super()
	if not reg.has_game(TEMPLATE):
		var m: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(TEMPLATE_DIR.path_join("game.json"))
		)
		assert_eq(reg.add_game(m, TEMPLATE_DIR, true), "")
	return reg


func _play(game_id: String, flags: Array[String], report: String) -> Dictionary:
	if _break_play:
		push_error("the shared play broke")
		return {"_end": "error", "_path": ""}
	return super(game_id, flags, report)


func _shared_play_failed(key: String, why: String) -> void:
	if _catch_failures:
		_told.append("%s: %s" % [key, why])
	else:
		fail_test("%s: %s" % [key, why])


func test_the_same_flags_play_once() -> void:
	var a := shared_session(TEMPLATE, SHORT)
	var played := _runners.size()
	var b := shared_session(TEMPLATE, SHORT)
	assert_eq(a["_end"], "timeout", "it ran to --max-sim-seconds")
	assert_eq(_runners.size(), played, "the second call plays nothing")
	assert_eq(b["deterministic_hash"], a["deterministic_hash"])
	assert_eq(b["_path"], a["_path"])


func test_other_flags_play_another_session() -> void:
	var a := shared_session(TEMPLATE, SHORT)
	var other: Array[String] = ["--players=1", "--seed=4", "--max-sim-seconds=2"]
	var b := shared_session(TEMPLATE, other)
	assert_ne(b["_path"], a["_path"], "a report of its own")
	assert_eq(int(b["seed"]), 4)
	assert_eq(int(a["seed"]), 3)


func test_each_call_gets_a_copy_of_its_own() -> void:
	var a := shared_session(TEMPLATE, SHORT)
	a["_end"] = "changed"
	(a["slots"] as Array).clear()
	var b := shared_session(TEMPLATE, SHORT)
	assert_eq(b["_end"], "timeout", "a test's change stays in its copy")
	assert_eq((b["slots"] as Array).size(), 1, "nested too")


func test_the_report_outlives_the_test_that_played_it() -> void:
	var r := shared_session(TEMPLATE, ["--players=1", "--seed=5", "--max-sim-seconds=2"])
	var path := str(r["_path"])
	assert_true(FileAccess.file_exists(path), "written")
	assert_false(path.begins_with(_dirs[0]), "not in this test's own user dir")
	after_each()
	assert_true(FileAccess.file_exists(path), "after_each leaves it")
	before_each()


func test_after_all_deletes_the_shared_files() -> void:
	var r := shared_session(TEMPLATE, ["--players=1", "--seed=6", "--max-sim-seconds=2"])
	var path := str(r["_path"])
	assert_true(FileAccess.file_exists(path))
	after_all()
	assert_false(FileAccess.file_exists(path), "after_all removes the shared dir")
	assert_eq(_shared, {}, "and forgets the sessions")


## A push_error in the shared play fails the test that played it (GUT), and shared_session() tells
## every later caller too, in this test or a later one, so none passes on a broken run.
func test_a_shared_play_that_broke_fails_every_caller() -> void:
	var broken: Array[String] = ["--players=1", "--seed=7", "--max-sim-seconds=2"]
	_catch_failures = true
	_break_play = true
	shared_session(TEMPLATE, broken)
	assert_push_error("the shared play broke")
	_break_play = false
	assert_eq(_told.size(), 1, "the caller that played it: %s" % [_told])
	shared_session(TEMPLATE, broken)
	after_each()
	before_each()
	shared_session(TEMPLATE, broken)
	assert_eq(_told.size(), 3, "and every caller after it, a later test's too: %s" % [_told])
	for t in _told:
		assert_string_contains(t, "the shared play broke")
	var fine := shared_session(TEMPLATE, SHORT)
	assert_eq(fine["_end"], "timeout")
	assert_eq(_told.size(), 3, "another session is not touched")
	_catch_failures = false
	_told.clear()


## A suite that overrides after_all without calling super still leaves no shared dir behind: the
## suite deletes it when GUT frees the script.
func test_the_shared_dir_goes_with_the_suite_even_without_after_all() -> void:
	var suite := TestGameSessionSuite.new()
	var dir := Paths.make_temp_dir("game_session_shared")
	var f := FileAccess.open(dir.path_join("report_0.json"), FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	suite._shared_dir = dir
	suite.free()
	assert_false(DirAccess.dir_exists_absolute(dir), "freed with the suite")
	if DirAccess.dir_exists_absolute(dir):
		GameSimCli.remove_tree(dir)
