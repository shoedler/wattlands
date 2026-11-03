extends GutTest
## A peer sends what it likes (cleanup/mp-every-game): a client refuses a snapshot or an event
## whose number cells hold lists, strings or nothing, instead of raising a script error.

const U := preload("res://tests/games/workout/workout_test_util.gd")


func _client() -> WorkoutGame:
	return autofree(U.game("e2e", U.players(2), Wl.CLIENT, 2))


func _snap() -> Dictionary:
	var host := U.game("e2e", U.players(2), Wl.HOST, 1)
	var snap: Dictionary = JSON.parse_string(JSON.stringify(host.snapshot()))
	host.free()
	return snap


func test_the_real_snapshot_passes_and_mistyped_cells_do_not() -> void:
	assert_eq(WorkoutSnapshot.check(_snap()), "")
	for key: String in ["t", "p", "pt"]:
		var s := _snap()
		s[key] = [1]
		assert_ne(WorkoutSnapshot.check(s), "", key)
	var rows := _snap()
	(rows["r"] as Array)[0][1] = [1]
	assert_ne(WorkoutSnapshot.check(rows), "", "a row cell that is a list")
	var many := _snap()
	for i in WorkoutSnapshot.MAX_ROWS + 1:
		(many["r"] as Array).append([0, 0, 0, 0, 0, 0, 0, 0, 0])
	assert_ne(WorkoutSnapshot.check(many), "")
	assert_ne(WorkoutSnapshot.check({"tl": [5]}), "", "a timeline entry is a list")
	assert_ne(WorkoutSnapshot.check({"tl": [[1, 2, "x", 4, 5, 6]]}), "")
	assert_ne(WorkoutSnapshot.check({"tll": 5}), "")
	assert_eq(WorkoutSnapshot.check({"tl": [[0, 0, 600, 0, 600, 0]], "tll": ["a"]}), "")


func test_the_client_refuses_a_bad_snapshot_and_event_whole() -> void:
	var c := _client()
	var tick_before := c.state.tick
	c.apply_snapshot({"t": 999, "r": [[2, [1], 0, 0, 0, 0, 0, 0, 0]]})
	assert_push_warning("snapshot ignored")
	assert_eq(c.state.tick, tick_before, "nothing of it was applied")
	c.apply_event({"type": WorkoutRules.EV_INTERVAL_END, "i": [1], "r": []})
	assert_push_warning("event ignored")
	c.apply_event({"type": "no_such_event"})
	assert_push_warning("event ignored")
