extends GutTest
## WireRead: how a client's apply_snapshot and apply_event read values a peer may have mistyped.


func test_int_of_reads_numbers_bools_and_numeric_strings() -> void:
	assert_eq(WireRead.int_of(7), 7)
	assert_eq(WireRead.int_of(-3.9), -3, "truncated like int()")
	assert_eq(WireRead.int_of(true), 1)
	assert_eq(WireRead.int_of(false), 0)
	assert_eq(WireRead.int_of("12"), 12)
	assert_eq(WireRead.int_of("x", 5), 5)


func test_int_of_falls_back_for_everything_else() -> void:
	for junk: Variant in [null, [1], {"a": 1}, Vector2.ONE, NAN, INF, -INF, "", "1e999"]:
		assert_eq(WireRead.int_of(junk, 9), 9, "%s is not a number" % str(junk))


func test_int_of_clamps_huge_values() -> void:
	assert_eq(WireRead.int_of(1.5e300), int(WireRead.MAX_ABS))
	assert_eq(WireRead.int_of(-1.5e300), -int(WireRead.MAX_ABS))
	assert_eq(WireRead.int_of(9223372036854775807), int(WireRead.MAX_ABS))


func test_float_of_reads_numbers_and_falls_back() -> void:
	assert_eq(WireRead.float_of(2), 2.0)
	assert_eq(WireRead.float_of("2.5"), 2.5)
	assert_eq(WireRead.float_of(true), 1.0)
	assert_eq(WireRead.float_of(1.0e300), WireRead.MAX_ABS)
	for junk: Variant in [null, [], {}, NAN, INF, "x"]:
		assert_eq(WireRead.float_of(junk, -1.0), -1.0, "%s is not a number" % str(junk))


func test_array_and_dict_of_never_return_another_type() -> void:
	assert_eq(WireRead.array_of([1, 2]), [1, 2])
	assert_eq(WireRead.dict_of({"a": 1}), {"a": 1})
	for junk: Variant in [null, 5, 99999999, "x", {}, true]:
		assert_eq(WireRead.array_of(junk), [], "%s is not a list" % str(junk))
	for junk: Variant in [null, 5, "x", [], true]:
		assert_eq(WireRead.dict_of(junk), {}, "%s is not a map" % str(junk))


func test_row_of_needs_enough_columns() -> void:
	assert_eq(WireRead.row_of([1, 2, 3], 3), [1, 2, 3])
	assert_eq(WireRead.row_of([1, 2], 3), [])
	assert_eq(WireRead.row_of("abc", 1), [])


func test_flat_numbers_are_a_list_of_numbers_only() -> void:
	assert_true(WireRead.is_flat_numbers([1, 2.5, 3]))
	assert_true(WireRead.is_flat_numbers([]))
	for bad: Variant in [[1, "2"], [1, [2]], [true], [null], [{}], 5, "x", null, {}]:
		assert_false(WireRead.is_flat_numbers(bad), "%s is not a flat row" % str(bad))


func test_within_depth_refuses_deep_nesting() -> void:
	assert_true(WireRead.within_depth({"k": "route", "to": [1, 2]}, 2))
	assert_false(WireRead.within_depth({"k": {"to": {"x": 1}}}, 2))
	var deep: Variant = 1
	for i in 200:
		deep = [deep]
	assert_false(WireRead.within_depth(deep, 8))
	assert_true(WireRead.within_depth("x", 0))


func test_bad_int_path_names_the_first_path_that_is_not_numbers() -> void:
	var e := {"type": "x", "l": 1, "lanes": [1, 2], "r": [[1, 2], [3]]}
	assert_eq(WireRead.bad_int_path(e, ["l", "lanes[]", "r[][]"]), "")
	assert_eq(WireRead.bad_int_path(e, ["l", "missing"]), "missing")
	assert_eq(WireRead.bad_int_path({"l": "1"}, ["l"]), "l")
	assert_eq(WireRead.bad_int_path({"lanes": 5}, ["lanes[]"]), "lanes[]", "a number is no list")
	assert_eq(WireRead.bad_int_path({"lanes": [1, "a"]}, ["lanes[]"]), "lanes[]")
	assert_eq(WireRead.bad_int_path({"r": [1, 2]}, ["r[][]"]), "r[][]", "rows must be lists")
	assert_eq(WireRead.bad_int_path({"l": [1]}, ["l"]), "l", "a list is no number")


func test_strings_with_an_exponent_or_a_long_digit_run_are_no_numbers() -> void:
	assert_eq(WireRead.int_of("1e999", 4), 4)
	assert_eq(WireRead.int_of("9".repeat(40), 4), 4)
	assert_eq(WireRead.float_of("1E5", 2.0), 2.0)


func test_int_path_problem_says_missing_or_not_numbers() -> void:
	assert_eq(WireRead.int_path_problem({"l": 1}, ["l"]), "")
	assert_eq(WireRead.int_path_problem({}, ["l"]), "missing l")
	assert_eq(WireRead.int_path_problem({"l": [1]}, ["l"]), "l is not numbers")
	assert_eq(WireRead.int_path_problem({}, ["lanes[]"]), "missing lanes")
