extends TestGameSessionSuite
## shared_session(): a session the tests of one script only read is played once for the script,
## each call gets a copy of its own, and the files stay until after_all. Two seconds of the first
## installed game's default content keep each run short.

const SHORT: Array[String] = ["--players=1", "--seed=3", "--max-sim-seconds=2"]


func _game_id() -> String:
	var ids := _registry().ids()
	assert_gt(ids.size(), 0, "an installed game")
	return ids[0] if not ids.is_empty() else ""


func test_the_same_flags_play_once() -> void:
	var id := _game_id()
	var a := shared_session(id, SHORT)
	var played := _runners.size()
	var b := shared_session(id, SHORT)
	assert_eq(a["_end"], "timeout", "it ran to --max-sim-seconds")
	assert_eq(_runners.size(), played, "the second call plays nothing")
	assert_eq(b["deterministic_hash"], a["deterministic_hash"])
	assert_eq(b["_path"], a["_path"])


func test_other_flags_play_another_session() -> void:
	var id := _game_id()
	var a := shared_session(id, SHORT)
	var other: Array[String] = ["--players=1", "--seed=4", "--max-sim-seconds=2"]
	var b := shared_session(id, other)
	assert_ne(b["_path"], a["_path"], "a report of its own")
	assert_eq(int(b["seed"]), 4)
	assert_eq(int(a["seed"]), 3)


func test_each_call_gets_a_copy_of_its_own() -> void:
	var id := _game_id()
	var a := shared_session(id, SHORT)
	a["_end"] = "changed"
	(a["slots"] as Array).clear()
	var b := shared_session(id, SHORT)
	assert_eq(b["_end"], "timeout", "a test's change stays in its copy")
	assert_eq((b["slots"] as Array).size(), 1, "nested too")


func test_the_report_outlives_the_test_that_played_it() -> void:
	var r := shared_session(_game_id(), ["--players=1", "--seed=5", "--max-sim-seconds=2"])
	var path := str(r["_path"])
	assert_true(FileAccess.file_exists(path), "written")
	assert_false(path.begins_with(_dirs[0]), "not in this test's own user dir")
	after_each()
	assert_true(FileAccess.file_exists(path), "after_each leaves it")
	before_each()


func test_after_all_deletes_the_shared_files() -> void:
	var r := shared_session(_game_id(), ["--players=1", "--seed=6", "--max-sim-seconds=2"])
	var path := str(r["_path"])
	assert_true(FileAccess.file_exists(path))
	after_all()
	assert_false(FileAccess.file_exists(path), "after_all removes the shared dir")
	assert_eq(_shared, {}, "and forgets the sessions")
