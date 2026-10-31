extends GutTest
## IntentValue: how a game's normalize() reads the loosely typed values of an intent.


func test_truthy_reads_bools_and_numbers() -> void:
	assert_true(IntentValue.truthy(true))
	assert_false(IntentValue.truthy(false))
	assert_true(IntentValue.truthy(1))
	assert_true(IntentValue.truthy(-1))
	assert_false(IntentValue.truthy(0))
	assert_true(IntentValue.truthy(0.5))
	assert_false(IntentValue.truthy(0.0))


func test_truthy_is_false_for_anything_else() -> void:
	for junk: Variant in ["1", "true", null, [1], {"a": 1}, Vector2.ONE]:
		assert_false(IntentValue.truthy(junk), "%s is not a flag" % str(junk))


func test_whole_takes_ints_and_whole_floats() -> void:
	for v: Variant in [0, -3, 7, 0.0, 3.0, -2.0]:
		assert_true(IntentValue.whole(v), "%s is whole" % str(v))


func test_whole_refuses_fractions_non_finite_floats_and_other_types() -> void:
	for v: Variant in [0.5, -1.25, INF, -INF, NAN, "3", null, true, [1], Vector2.ONE]:
		assert_false(IntentValue.whole(v), "%s is not whole" % str(v))
