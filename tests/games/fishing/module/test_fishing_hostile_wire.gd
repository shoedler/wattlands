extends GutTest
## A peer sends what it likes (cleanup/mp-every-game): a client reads a snapshot, an event or an
## intent whose numbers are lists or whose lists are numbers without a script error (GUT and the
## log would fail the test), and refuses it whole.

const F := preload("res://tests/games/fishing/fishing_fakes.gd")


func _client() -> FishingGame:
	return autofree(F.make_game(F.make_ctx(2, 0, "roam_30", Wl.CLIENT, 2)))


func _snap() -> Dictionary:
	var host: FishingGame = autofree(F.make_game(F.make_ctx(2, 0, "roam_30", Wl.HOST, 1)))
	return JSON.parse_string(JSON.stringify(host.snapshot()))


func test_a_snapshot_with_a_list_in_a_number_cell_is_refused() -> void:
	assert_eq(FishingSnapshotSchema.check(_snap()), "", "the real one passes")
	for bad: Variant in [[1], "x", null, {}, true]:
		var s := _snap()
		(s["R"] as Array)[0][FishingSnapshotSchema.R_X_DM] = bad
		assert_ne(FishingSnapshotSchema.check(s), "", "%s in a rider column" % str(bad))
	var s2 := _snap()
	s2["k"] = [5]
	assert_ne(FishingSnapshotSchema.check(s2), "")
	var s3 := _snap()
	s3["v"] = [FishingSnapshotSchema.VERSION]
	assert_ne(FishingSnapshotSchema.check(s3), "", "a list is no version (this raised int())")
	var s4 := _snap()
	s4["C"] = [5]
	assert_ne(FishingSnapshotSchema.check(s4), "")
	var s5 := _snap()
	(s5["R"] as Array)[0][FishingSnapshotSchema.R_HINTS] = [[1, 2]]
	assert_ne(FishingSnapshotSchema.check(s5), "", "a hint with too few columns")


func test_the_client_survives_such_a_snapshot() -> void:
	var c := _client()
	var s := _snap()
	(s["R"] as Array)[0][FishingSnapshotSchema.R_STRAIN] = [1]
	c.apply_snapshot(s)
	assert_push_warning("snapshot ignored")


func test_an_event_with_a_list_where_a_number_goes_is_refused() -> void:
	assert_eq(FishingEvents.check(FishingEvents.cast(0, 1, 2.0, 3.0)), "")
	assert_ne(FishingEvents.check({"type": "cast", "l": [1], "sp": 1, "dx": 1, "z": 1}), "")
	assert_ne(FishingEvents.check({"type": "double_hookup", "lanes": 5, "lvl": 2}), "")
	assert_ne(FishingEvents.check({"type": "double_hookup", "lanes": [1, "a"], "lvl": 2}), "")
	var c := _client()
	c.apply_event({"type": "landed", "l": [1]})
	assert_push_warning("event ignored")


func test_cast_ints_reads_a_mistyped_list_without_raising() -> void:
	var e := FishingEvents.cast_ints({"type": "double_hookup", "lanes": [1, [2], "x"], "lvl": [3]})
	assert_eq(e["lanes"], [1, 0, 0])


func test_an_intent_with_a_list_for_a_number_is_junk() -> void:
	assert_eq(FishingIntents.normalize({"k": "spot", "dir": [1]}), {})
	assert_eq(FishingIntents.normalize({"k": "spot", "dir": {"a": 1}}), {})
	assert_eq(FishingIntents.normalize({"k": "spot", "dir": 1})["dir"], 1)
	var n := FishingIntents.normalize(
		{"k": "summary", "xp": [1], "rec": {"tuna": [2]}, "cos": [[1], {}, 3, 4, 5]}
	)
	assert_eq(n["xp"], 0)
	assert_eq(n["cos"], [0, 0, 3, 4])
