extends GutTest
## FIT laps (BRIEF 3.8; OWNERSHIP GM18, PL10, FIT1, C3): a lap at every lap() call (the
## game's lap_marker, each lap-true plan phase start, the cool-down start), a lap-false phase
## continues the current lap, the cool-down is always its own lap, and a lap() at the
## instant the current lap started renames it instead of leaving a zero-length lap.
## Expected laps = lap-true phases that started + lap_markers + 1 for the cool-down, when the
## first phase is lap-true (Workout, Siege, Tank and Fishing all start with one).

const Reader := preload("res://tests/rides/fit_reader.gd")
const START := 1_800_000_000


func _feed(rec: RideRecorder, from: float, to: float, power: float) -> void:
	var t := from
	while t < to - 0.0001:
		rec.record(t, power, 90.0, 30.0)
		t += 0.05


func _labels(rec: RideRecorder) -> Array:
	var out: Array = []
	for l: Dictionary in rec.summary()["laps"]:
		out.append(l["label"])
	return out


func test_laps_at_phases_markers_and_cooldown() -> void:
	var rec := RideRecorder.new()
	rec.start("siege", "c", START, 0.0)
	# Phase 0 (lap-true) starts with the ride: renames the opening lap.
	rec.lap("Wave 1", 0.0)
	_feed(rec, 0.0, 30.0, 200.0)
	rec.lap("Wave 2", 30.0)  # lap-true phase
	_feed(rec, 30.0, 45.0, 250.0)
	rec.lap("Marker", 45.0)  # the game's lap_marker
	_feed(rec, 45.0, 60.0, 260.0)
	# A lap-false phase at 50 s calls nothing: the lap continues.
	rec.lap("Cool-down", 60.0)  # always its own lap
	_feed(rec, 60.0, 90.0, 100.0)
	rec.stop(90.0)
	assert_eq(_labels(rec), ["Wave 1", "Wave 2", "Marker", "Cool-down"])
	var lap_true_phases := 2
	var markers := 1
	assert_eq(rec.lap_count(), lap_true_phases + markers + 1, "FIT1 expected-lap formula")
	var laps: Array = rec.summary()["laps"]
	assert_almost_eq(float(laps[0]["start_s"]), 0.0, 0.001)
	assert_almost_eq(float(laps[1]["start_s"]), 30.0, 0.001)
	assert_almost_eq(float(laps[2]["duration_s"]), 15.0, 0.001)
	assert_almost_eq(float(laps[3]["duration_s"]), 30.0, 0.001)
	assert_almost_eq(float(laps[1]["avg_power_w"]), 250.0, 0.1)
	var d := Reader.read(rec.fit_bytes())
	assert_eq(d["errors"], [])
	var fit_laps := Reader.of(d, 19)
	assert_eq(fit_laps.size(), 4)
	var names: Array = []
	for l: Dictionary in fit_laps:
		names.append(Reader.dev_string(l["dev"][0]))
	assert_eq(names, ["Wave 1", "Wave 2", "Marker", "Cool-down"], "lap names in the FIT")
	assert_eq(fit_laps[3]["fields"][24], 7, "last lap trigger session_end")
	assert_eq(fit_laps[0]["fields"][24], 0, "other laps manual")
	assert_eq(fit_laps[1]["fields"][2] - (START - 631065600), 30, "lap 1 start_time")


func test_first_phase_without_lap_keeps_the_opening_lap() -> void:
	var rec := RideRecorder.new()
	rec.start("workout", "c", START, 0.0)
	_feed(rec, 0.0, 20.0, 150.0)
	rec.lap("Main", 20.0)
	_feed(rec, 20.0, 40.0, 200.0)
	rec.stop(40.0)
	assert_eq(_labels(rec), ["", "Main"], "the opening segment is its own lap")


func test_a_lap_at_the_same_instant_renames() -> void:
	var rec := RideRecorder.new()
	rec.start("g", "c", START, 0.0)
	_feed(rec, 0.0, 10.0, 150.0)
	rec.lap("A", 10.0)
	rec.lap("B", 10.0)
	_feed(rec, 10.0, 20.0, 150.0)
	rec.stop(20.0)
	assert_eq(_labels(rec), ["", "B"], "no zero-length lap")


func test_fractional_lap_times_keep_millisecond_durations() -> void:
	var rec := RideRecorder.new()
	rec.start("g", "c", START, 100.0)
	_feed(rec, 100.0, 160.05, 200.0)
	rec.lap("Second", 160.05)
	_feed(rec, 160.05, 200.0, 200.0)
	rec.stop(200.0)
	var d := Reader.read(rec.fit_bytes())
	var laps := Reader.of(d, 19)
	assert_eq(laps[0]["fields"][7], 60050, "first lap elapsed ms")
	assert_eq(laps[1]["fields"][7], 39950, "second lap elapsed ms")
	assert_eq(
		int(laps[0]["fields"][7]) + int(laps[1]["fields"][7]),
		Reader.of(d, 18)[0]["fields"][7],
		"laps cover the session"
	)


func test_a_ride_ending_before_the_cooldown_has_no_cooldown_lap() -> void:
	var rec := RideRecorder.new()
	rec.start("tank", "c", START, 0.0)
	rec.lap("Segment 1", 0.0)
	_feed(rec, 0.0, 30.0, 200.0)
	rec.lap("Segment 2", 30.0)
	_feed(rec, 30.0, 50.0, 200.0)
	rec.stop(50.0)  # timeout or paused ending
	assert_eq(_labels(rec), ["Segment 1", "Segment 2"])


func test_laps_after_stop_or_before_start_are_ignored() -> void:
	var rec := RideRecorder.new()
	rec.lap("Nope", 0.0)
	rec.start("g", "c", START, 0.0)
	_feed(rec, 0.0, 5.0, 100.0)
	rec.stop(5.0)
	rec.lap("Late", 6.0)
	assert_eq(rec.lap_count(), 1)


func test_lap_totals_add_up() -> void:
	var rec := RideRecorder.new()
	rec.start("g", "c", START, 0.0)
	for i in 6:
		rec.lap("L%d" % i, float(i) * 20.0)
		_feed(rec, float(i) * 20.0, float(i + 1) * 20.0, 100.0 + float(i) * 30.0)
	rec.stop(120.0)
	var s := rec.summary()
	var kj := 0.0
	var dur := 0.0
	var dist := 0.0
	for l: Dictionary in s["laps"]:
		kj += float(l["kj"])
		dur += float(l["duration_s"])
		dist += float(l["distance_m"])
	assert_almost_eq(kj, float(s["kj"]), 0.003)
	assert_almost_eq(dur, float(s["duration_s"]), 0.003)
	assert_almost_eq(dist, float(s["distance_m"]), 0.03)
