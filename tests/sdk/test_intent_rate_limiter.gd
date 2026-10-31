extends GutTest
## IntentRateLimiter: BRIEF 2.6's per-peer limit on game ticks, and the flag reader games share.


func test_the_window_is_one_second_of_ticks() -> void:
	assert_eq(IntentRateLimiter.WINDOW_TICKS, Wl.SIM_HZ)


func test_a_new_limiter_allows_five() -> void:
	var lim := IntentRateLimiter.new()
	for i in 5:
		assert_true(lim.allow(1, 100), "intent %d" % i)
	assert_false(lim.allow(1, 100), "the sixth is dropped")


func test_max_per_s_sets_the_limit() -> void:
	var lim := IntentRateLimiter.new()
	lim.max_per_s = 2
	assert_true(lim.allow(1, 0))
	assert_true(lim.allow(1, 0))
	assert_false(lim.allow(1, 0))


func test_an_intent_leaves_the_window_exactly_one_second_later() -> void:
	var lim := IntentRateLimiter.new()
	lim.max_per_s = 1
	assert_true(lim.allow(1, 100))
	assert_false(lim.allow(1, 100 + IntentRateLimiter.WINDOW_TICKS - 1), "still inside")
	assert_true(lim.allow(1, 100 + IntentRateLimiter.WINDOW_TICKS), "just out")


func test_a_dropped_intent_does_not_count() -> void:
	var lim := IntentRateLimiter.new()
	lim.max_per_s = 1
	assert_true(lim.allow(1, 100))
	assert_false(lim.allow(1, 110))
	assert_true(
		lim.allow(1, 100 + IntentRateLimiter.WINDOW_TICKS),
		"the window still counts from tick 100, not the dropped 110"
	)


func test_peers_have_their_own_windows() -> void:
	var lim := IntentRateLimiter.new()
	lim.max_per_s = 1
	assert_true(lim.allow(1, 100))
	assert_true(lim.allow(2, 100))
	assert_false(lim.allow(1, 100))


func test_any_window_holds_at_most_the_limit() -> void:
	var lim := IntentRateLimiter.new()
	var accepted: Array[int] = []
	for tick in 200:
		if lim.allow(1, tick):
			accepted.append(tick)
	assert_gt(accepted.size(), 5)
	for i in range(lim.max_per_s, accepted.size()):
		assert_gte(
			accepted[i] - accepted[i - lim.max_per_s],
			IntentRateLimiter.WINDOW_TICKS,
			"six accepted intents never fit one window"
		)


func test_truthy_reads_bools_and_numbers() -> void:
	assert_true(IntentRateLimiter.truthy(true))
	assert_false(IntentRateLimiter.truthy(false))
	assert_true(IntentRateLimiter.truthy(1))
	assert_true(IntentRateLimiter.truthy(-1))
	assert_false(IntentRateLimiter.truthy(0))
	assert_true(IntentRateLimiter.truthy(0.5))
	assert_false(IntentRateLimiter.truthy(0.0))


func test_truthy_is_false_for_anything_else() -> void:
	for junk: Variant in ["1", "true", null, [1], {"a": 1}, Vector2.ONE]:
		assert_false(IntentRateLimiter.truthy(junk), "%s is not a flag" % str(junk))
