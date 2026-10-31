extends GutTest
## SnapHistory: the rows every game's view interpolates between (BRIEF 5.1). The cases come from
## test_tank_snap_history.gd and test_workout_client_view.gd, which still run against the subclasses.


func _row(v: Variant) -> Dictionary:
	return {"v": v}


func _keyed(key: int, v: float) -> Dictionary:
	return {"k": {key: v}}


func _subbed(key: int, sub: String, v: float) -> Dictionary:
	return {"r": {key: {sub: v}}}


func test_an_empty_history_reads_zero_and_the_fallback() -> void:
	var h := SnapHistory.new()
	assert_true(h.is_empty())
	assert_eq(h.newest_t(), 0.0)
	assert_eq(h.mean_spacing(), 0.0)
	assert_eq(h.sample(1.0, "v", null, 7.0), 7.0)
	assert_eq(h.sample_sub(1.0, "r", 1, "x", 7.0), 7.0)


func test_add_stamps_the_row_with_its_time() -> void:
	var h := SnapHistory.new()
	h.add(2.5, _row(1.0))
	assert_eq(h.entries[0]["t"], 2.5)
	assert_eq(h.newest_t(), 2.5)


func test_sample_is_linear_and_never_extrapolates() -> void:
	var h := SnapHistory.new()
	h.add(5.0, _row(1000.0))
	h.add(5.1, _row(1010.0))
	assert_almost_eq(float(h.sample(5.0, "v", null, -1.0)), 1000.0, 1e-4)
	assert_almost_eq(float(h.sample(5.05, "v", null, -1.0)), 1005.0, 1e-3)
	assert_almost_eq(float(h.sample(5.1, "v", null, -1.0)), 1010.0, 1e-4)
	assert_almost_eq(float(h.sample(9.0, "v", null, -1.0)), 1010.0, 1e-4, "after: the newest")
	assert_almost_eq(float(h.sample(1.0, "v", null, -1.0)), 1000.0, 1e-4, "before: the oldest")


func test_sample_lerps_vectors() -> void:
	var h := SnapHistory.new()
	h.add(1.0, _row(Vector2(100, 200)))
	h.add(1.1, _row(Vector2(140, 180)))
	var mid := h.sample(1.05, "v", null, Vector2.ZERO) as Vector2
	assert_almost_eq(mid.x, 120.0, 1e-3)
	assert_almost_eq(mid.y, 190.0, 1e-3)


func test_sample_by_key_skips_entries_without_it() -> void:
	var h := SnapHistory.new()
	h.add(1.0, {"k": {}})
	h.add(1.1, _keyed(5, 500.0))
	assert_almost_eq(float(h.sample(1.0, "k", 5, 0.0)), 500.0, 1e-3, "holds at its first value")
	assert_eq(h.sample(1.05, "k", 77, 123.0), 123.0, "an unknown key gets the fallback")
	h.add(1.2, _keyed(5, 520.0))
	assert_almost_eq(float(h.sample(1.15, "k", 5, 0.0)), 510.0, 1e-3)
	assert_almost_eq(float(h.sample(5.0, "k", 5, 0.0)), 520.0, 1e-3, "after: the newest")


func test_sample_treats_key_zero_as_a_key() -> void:
	var h := SnapHistory.new()
	h.add(1.0, _keyed(0, 10.0))
	assert_eq(h.sample(1.0, "k", 0, -1.0), 10.0)


func test_sample_sub_is_linear_and_never_extrapolates() -> void:
	var h := SnapHistory.new()
	h.add(1.0, _subbed(2, "x", 10.0))
	h.add(1.1, _subbed(2, "x", 20.0))
	assert_almost_eq(h.sample_sub(1.05, "r", 2, "x", -1.0), 15.0, 1e-3)
	assert_almost_eq(h.sample_sub(0.5, "r", 2, "x", -1.0), 10.0, 1e-3, "before: the oldest")
	assert_almost_eq(h.sample_sub(5.0, "r", 2, "x", -1.0), 20.0, 1e-3, "after: the newest")
	assert_eq(h.sample_sub(1.05, "r", 9, "x", -1.0), -1.0, "an unknown key gets the fallback")


func test_sample_sub_reads_a_missing_sub_as_the_fallback_or_the_later_value() -> void:
	var h := SnapHistory.new()
	h.add(1.0, _subbed(2, "y", 1.0))
	h.add(1.1, _subbed(2, "x", 20.0))
	assert_almost_eq(h.sample_sub(1.05, "r", 2, "x", -1.0), 20.0, 1e-3, "the earlier lacks it")
	assert_eq(h.sample_sub(1.05, "r", 2, "z", -1.0), -1.0, "neither has it")
	assert_eq(h.sample_sub(5.0, "r", 2, "y", -1.0), -1.0, "the newest lacks it")


func test_the_same_time_replaces_the_newest() -> void:
	var h := SnapHistory.new()
	h.add(0.5, _row(1.0))
	h.add(0.5, _row(2.0))
	assert_eq(h.entries.size(), 1)
	assert_eq(h.sample(0.5, "v", null, 0.0), 2.0)
	h.add(0.5 + SnapHistory.SAME_T_S / 2.0, _row(3.0))
	assert_eq(h.entries.size(), 1, "within SAME_T_S after")
	h.add(0.5 - SnapHistory.SAME_T_S / 4.0, _row(4.0))
	assert_eq(h.entries.size(), 1, "within SAME_T_S before: replaced, not started over")
	assert_eq(h.sample(0.5, "v", null, 0.0), 4.0)


func test_an_earlier_time_or_a_long_gap_starts_over() -> void:
	var h := SnapHistory.new()
	h.add(0.5, _row(1.0))
	h.add(0.6, _row(2.0))
	h.add(0.25, _row(3.0))
	assert_eq(h.entries.size(), 1, "the host's clock went back: a new session")
	h.add(0.25 + SnapHistory.MAX_GAP_S - 0.05, _row(4.0))
	assert_eq(h.entries.size(), 2, "a gap just under MAX_GAP_S still interpolates")
	h.add(0.25 + 3.0 * SnapHistory.MAX_GAP_S, _row(5.0))
	assert_eq(h.entries.size(), 1, "a longer gap starts over")


func test_capacity_and_mean_spacing() -> void:
	var h := SnapHistory.new()
	h.add(0.0, _row(0.0))
	assert_eq(h.mean_spacing(), 0.0, "one entry: no spacing")
	for i in range(1, 20):
		h.add(0.1 * float(i), _row(float(i)))
	assert_eq(h.entries.size(), SnapHistory.CAPACITY)
	assert_almost_eq(h.mean_spacing(), 0.1, 1e-6)
	assert_almost_eq(h.newest_t(), 1.9, 1e-6)
	h.clear()
	assert_true(h.is_empty())


## At this time is_equal_approx(t, t + 0.05) is true (1e-5 x t is wider than a tick): the histories
## once replaced the newest entry on every new tick from about 5000 s on.
func test_ticks_late_in_a_long_session_still_append() -> void:
	var h := SnapHistory.new()
	for i in 6:
		h.add(6000.0 + 0.05 * float(i), _row(float(i)))
	assert_eq(h.entries.size(), 6, "each tick is its own entry")
	assert_almost_eq(h.mean_spacing(), 0.05, 1e-6)
	assert_almost_eq(float(h.sample(6000.125, "v", null, -1.0)), 2.5, 1e-3)
