extends GutTest
## A peer sends what it likes (cleanup/mp-every-game): a client applies a snapshot whose lists are
## numbers (`for x in 99999999` would loop for ever), whose cells are lists, and refuses an event
## with a list where a number goes, all without a script error.

const F := preload("res://tests/games/siege/siege_fakes.gd")


func _client() -> SiegeGame:
	return autofree(F.make_game(F.make_ctx(2, 0, "drill", Wl.CLIENT, 2)))


func test_a_snapshot_whose_lists_are_numbers_is_applied_as_empty() -> void:
	var c := _client()
	var snap := {"tick": 5, "pk": 99999999, "gate": 7, "r": 3, "st": "x", "pd": 9, "e": null}
	c.apply_snapshot(snap)
	assert_eq(c.state.perks, [] as Array[int], "no perks, and no loop")
	assert_eq(c.state.enemies.size(), 0)
	assert_eq(c.state.tick, 5)


func test_a_snapshot_with_lists_in_number_cells_applies_defaults() -> void:
	var c := _client()
	c.apply_snapshot(
		{
			"tick": [1],
			"ph": {"a": 1},
			"gate": [[1], 2, "x"],
			"pk": [[1], "a", 3],
			"r": [[[1], 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]],
			"e": [[1, 2, [3], 4, 5, 6]]
		}
	)
	assert_eq(c.state.perks, [0, 0, 3] as Array[int])


func test_an_event_with_a_list_where_a_number_goes_is_refused() -> void:
	assert_eq(SiegeEvents.check(SiegeEvents.rush(true, 1)), "")
	assert_ne(SiegeEvents.check({"type": SiegeIds.EV_RUSH, "on": [1], "i": 2}), "")
	assert_ne(SiegeEvents.check({"type": SiegeIds.EV_SHOT, "o": 5, "v": [1, 2, 3]}), "")
	var c := _client()
	c.apply_event({"type": SiegeIds.EV_WAVE_START, "n": [1]})
	assert_push_warning("event ignored")
