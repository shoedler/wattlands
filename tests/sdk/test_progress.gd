extends GutTest
## ctx.progress isolation per game and per rider, and apply_progress then save (BRIEF 3.6,
## 7.1 "ctx.progress isolation per game and rider, apply_progress on host and clients";
## docs/OWNERSHIP.md CTX9, GM17, C33). The multi-peer cases are in test_game_host_net.gd.

const Kit := preload("res://tests/sdk/helpers/session_kit.gd")

var _root: Node = null
var _tmp: String = ""


func before_each() -> void:
	_root = Node.new()
	add_child_autofree(_root)
	_tmp = Paths.make_temp_dir("wattlands_progress_test")
	Paths.set_override(_tmp)


func after_each() -> void:
	Paths.set_override("")
	Kit.remove_tree(_tmp)


func _finish(b: Dictionary) -> void:
	var host: GameHost = b["host"]
	host.start()
	Kit.step(b, 10)
	host.end_session("timeout")


func test_default_store_is_per_game_under_the_user_dir() -> void:
	var a := Kit.solo(_root, "tiny", {"progress_path": ""})
	var c := Kit.solo(_root, "tiny", {"progress_path": ""}, 0, "fx_crew")
	assert_eq(a["err"], "")
	assert_eq(c["err"], "")
	var pa := (a["host"] as GameHost).ctx.progress.path
	var pc := (c["host"] as GameHost).ctx.progress.path
	assert_eq(pa, _tmp.path_join("games/fx_solo/progress.json"))
	assert_eq(pc, _tmp.path_join("games/fx_crew/progress.json"))
	_finish(a)
	_finish(c)
	assert_true(FileAccess.file_exists(pa))
	assert_true(FileAccess.file_exists(pc))
	Kit.remove_tree(str(a["tmp"]))
	Kit.remove_tree(str(c["tmp"]))


func test_apply_progress_runs_once_and_is_saved_per_rider() -> void:
	var a := Kit.solo(
		_root, "tiny", {"progress_path": _tmp.path_join("riderA/games/fx_solo/progress.json")}
	)
	var b := Kit.solo(
		_root, "tiny", {"progress_path": _tmp.path_join("riderB/games/fx_solo/progress.json")}
	)
	_finish(a)
	var ha: GameHost = a["host"]
	assert_eq(ha.game.get("progress_calls"), 1)
	assert_eq(ha.unlocks, ["fx_badge"])
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(ha.ctx.progress.path))
	assert_eq(float(saved["xp"]), 10.0)
	assert_true(bool(saved["badge"]))
	assert_false(
		FileAccess.file_exists((b["host"] as GameHost).ctx.progress.path),
		"the other rider's store is untouched"
	)
	# A second session for rider A keeps building on its own store.
	var a2 := Kit.solo(_root, "tiny", {"progress_path": ha.ctx.progress.path})
	_finish(a2)
	var saved2: Variant = JSON.parse_string(FileAccess.get_file_as_string(ha.ctx.progress.path))
	assert_eq(float(saved2["xp"]), 20.0)
	assert_eq((a2["host"] as GameHost).unlocks, [], "no repeated unlock")
	for d: Dictionary in [a, b, a2]:
		Kit.remove_tree(str(d["tmp"]))
