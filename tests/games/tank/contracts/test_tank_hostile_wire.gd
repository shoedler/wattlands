extends GutTest
## A peer sends what it likes (cleanup/mp-every-game): the snapshot schema and the event check
## refuse a number cell that holds a list, a string or nothing, before a client reads a row.


func _snap() -> Dictionary:
	return JSON.parse_string(JSON.stringify(TankSnapshot.encode(TankFixtures.state(2))))


func test_the_real_snapshot_passes_and_a_mistyped_cell_does_not() -> void:
	assert_eq(TankSnapshotSchema.check(_snap()), "")
	for key: String in ["sg", "tk", "gl", "b", "sc"]:
		for bad: Variant in [[1], "x", null, {}]:
			var s := _snap()
			(s[key] as Array)[0] = bad
			assert_ne(TankSnapshotSchema.check(s), "", "%s[0] = %s" % [key, str(bad)])
	for key: String in ["r", "st", "e", "s", "o"]:
		var rows: Array = _snap()[key]
		if rows.is_empty():
			continue
		for bad: Variant in [[1], "x", null, {}]:
			var s := _snap()
			(s[key] as Array)[0][0] = bad
			assert_ne(TankSnapshotSchema.check(s), "", "%s[0][0] = %s" % [key, str(bad)])


func test_a_snapshot_whose_scalars_or_lists_are_the_wrong_type_is_refused() -> void:
	for key: String in ["v", "tick"]:
		var s := _snap()
		s[key] = [1]
		assert_ne(TankSnapshotSchema.check(s), "", key)
	for key: String in ["sg", "tk", "r", "st", "e", "s", "o", "gl", "b", "sc"]:
		var s := _snap()
		s[key] = 99999999
		assert_ne(TankSnapshotSchema.check(s), "", "%s as a number" % key)
	var many := _snap()
	for i in TankSnapshotSchema.MAX_ROWS + 1:
		(many["o"] as Array).append([1, 1, 1, 1, 1])
	assert_string_contains(TankSnapshotSchema.check(many), "too many rows")


func test_an_event_with_a_missing_or_mistyped_number_is_refused() -> void:
	assert_eq(TankEvents.check(TankEvents.segment(1, TankIds.SEG_COOLDOWN, 0)), "")
	assert_string_contains(TankEvents.check({"type": "no_such_event"}), "unknown type")
	assert_ne(TankEvents.check({"type": TankEvents.HIT, "on": [1]}), "", "a list for a number")
	assert_ne(TankEvents.check({"type": TankEvents.HIT}), "", "missing numbers")
	assert_ne(TankEvents.check({"type": TankEvents.ROTATION, "r": [1, 2]}), "", "rows are lists")
	assert_eq(TankEvents.check({"type": TankEvents.ROTATION, "r": [[1, 2], [3]]}), "")
	var shot := TankEvents.shot(1, 2, 3, 0, 0, 1.5, 40.0)
	assert_eq(TankEvents.check(shot), "")
	shot["flight_s"] = "x"
	assert_ne(TankEvents.check(shot), "", "flight_s is a number")
