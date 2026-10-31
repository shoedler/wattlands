extends GutTest
## The ride's one morning: session progress to a LUT row, and the kit's rows.

const U := preload("res://tests/games/workout/workout_test_util.gd")


func test_the_row_runs_from_0_to_31_and_never_back() -> void:
	assert_eq(WorkoutTod.row(0.0), 0)
	assert_eq(WorkoutTod.row(1.0), 31)
	assert_eq(WorkoutTod.row(-1.0), 0, "clamped")
	assert_eq(WorkoutTod.row(2.0), 31, "clamped")
	var prev := 0
	for i in 1001:
		var row := WorkoutTod.row(float(i) / 1000.0)
		assert_true(row >= prev and row - prev <= 1, "monotonic at %d" % i)
		prev = row


func test_progress_follows_the_plan() -> void:
	var g := U.game("easy_30", U.players(1))
	autofree(g)
	g.state.plan_t = g.state.total_s() * 0.25
	assert_almost_eq(WorkoutTod.progress(g.state), 0.25, 1e-9)
	g.state.plan_t = g.state.total_s() + 100.0
	assert_eq(WorkoutTod.progress(g.state), 1.0, "the cool-down lands in full day and stays")


func test_an_empty_timeline_is_the_start_of_the_morning() -> void:
	var empty := WorkoutState.new()
	assert_eq(WorkoutTod.progress(empty), 0.0)
	assert_eq(WorkoutTod.row(WorkoutTod.progress(empty)), 0)


func test_the_kit_has_a_row_for_each_and_slot_colours_stay_readable() -> void:
	var kit := WorkoutKit.shared()
	assert_eq(kit.tod.size(), WorkoutTod.ROWS)
	for row in WorkoutTod.ROWS:
		var c := kit.tod_color(row, "rider_tint")
		assert_true(minf(minf(c.r, c.g), c.b) >= 0.72, "rider_tint of row %d: %s" % [row, c])


func test_the_view_follows_the_row() -> void:
	var g := U.game("easy_30", U.players(1))
	autofree(g)
	var view := g.make_view() as WorkoutRideView
	add_child_autofree(view)
	view.set_process(false)
	g.state.plan_t = g.state.total_s()
	view.refresh()
	assert_eq(int(view.model["row"]), 31)
	var kit := view.kit
	assert_eq(view.riders.modulate, kit.tod_color(31, "rider_tint"))
	assert_eq(view.sky_fill.color, kit.tod_color(31, "sky_top"))
	assert_eq(view.sun.position, Vector2(WorkoutKit.vec(kit.tod_row(31)["sun"])))
	assert_eq(view.bank.bank, kit.tod_color(31, "bank"))
