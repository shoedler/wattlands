extends GutTest
## RideRecorder (BRIEF 3.8, 7.5): one record per second of platform time, totals, timer
## pauses, the summary, saving (file names, JSON), and the FIT's totals equal the summary's.
## Also writes a 10-minute synthetic ride to build/rides_test/ for tools/fit_check.

const Reader := preload("res://tests/rides/fit_reader.gd")
const Util := preload("res://tests/rides/rides_test_util.gd")
const START := 1_800_000_000 # 2027-01-15T08:00:00Z
const DT := 0.05

var _dir: String = ""


func before_each() -> void:
	_dir = Paths.make_temp_dir("wattlands_rides")
	Paths.set_override(_dir)


func after_each() -> void:
	Paths.set_override("")
	Util.remove_tree(_dir)


## Feeds constant values at 20 Hz from t0 for `seconds` and stops.
func _ride_20hz(rec: RideRecorder, t0: float, seconds: float, power: float, cad: float, kmh: float) -> float:
	var steps := roundi(seconds / DT)
	var t := t0
	for i in steps + 1:
		t = t0 + float(i) * DT
		rec.record(t, power, cad, kmh)
	return t


func test_one_record_per_second_at_20hz() -> void:
	var rec := RideRecorder.new()
	rec.start("workout", "easy30", START, 12.5)
	var t_end := _ride_20hz(rec, 12.5, 60.0, 200.0, 90.0, 36.0)
	rec.stop(t_end)
	assert_eq(rec.record_count(), 61, "seconds 0..60")
	var recs := rec.records()
	for i in recs.size():
		assert_eq(int(recs[i]["t_rel"]), i)
	var s := rec.summary()
	assert_almost_eq(float(s["duration_s"]), 60.0, 0.001)
	assert_almost_eq(float(s["distance_m"]), 600.0, 0.05, "10 m/s for 60 s")
	assert_almost_eq(float(s["kj"]), 12.0, 0.001, "200 W x 60 s")
	assert_almost_eq(float(s["avg_power_w"]), 200.0, 0.05)
	assert_eq(float(s["max_power_w"]), 200.0)
	assert_almost_eq(float(s["avg_cadence_rpm"]), 90.0, 0.05)
	assert_almost_eq(float(s["avg_speed_kmh"]), 36.0, 0.01)
	assert_eq(int(s["records"]), 61)


func test_one_record_per_second_with_a_jittered_1hz_feed() -> void:
	var rec := RideRecorder.new()
	rec.start("workout", "x", START, 0.0)
	var rng := SeededRng.make(7)
	var last := 0.0
	for k in 300:
		last = float(k) + SeededRng.range_f(rng, -0.2, 0.2) if k > 0 else 0.0
		rec.record(last, 150.0 + float(k % 10), 85.0, 30.0)
	rec.stop(300.0)
	assert_eq(rec.record_count(), 301, "one record per second, 0..300")
	var recs := rec.records()
	for i in recs.size():
		assert_eq(int(recs[i]["t_rel"]), i, "record %d stamped at its second" % i)


func test_records_hold_the_latest_value() -> void:
	var rec := RideRecorder.new()
	rec.start("g", "c", START, 0.0)
	rec.record(0.0, 100.0, 80.0, 20.0)
	rec.record(0.5, 300.0, 95.0, 40.0)
	rec.record(2.5, 50.0, 60.0, 10.0)
	rec.stop(3.0)
	var recs := rec.records()
	assert_eq(recs.size(), 4)
	assert_eq(float(recs[0]["power_w"]), 100.0, "t=0: the sample at 0")
	assert_eq(float(recs[1]["power_w"]), 300.0, "t=1: held from 0.5")
	assert_eq(float(recs[2]["power_w"]), 300.0, "t=2: still held")
	assert_eq(float(recs[3]["power_w"]), 50.0, "t=3: held from 2.5")
	# Work integrates the held values: 100*0.5 + 300*2.0 + 50*0.5 = 675 J.
	assert_almost_eq(float(rec.summary()["kj"]), 0.675, 0.0005)
	assert_eq(float(rec.summary()["max_power_w"]), 300.0)


func test_absent_cadence_and_speed() -> void:
	var rec := RideRecorder.new()
	rec.start("g", "c", START, 0.0)
	rec.record(0.0, 100.0, -1.0, -1.0)
	rec.record(1.0, 100.0, -1.0, -1.0)
	rec.stop(1.0)
	var s := rec.summary()
	assert_eq(float(s["avg_cadence_rpm"]), -1.0, "no cadence: absent")
	assert_eq(float(s["distance_m"]), 0.0, "no speed: no distance")
	var d := Reader.read(rec.fit_bytes())
	assert_eq(d["errors"], [])
	assert_eq(Reader.of(d, 20)[0]["fields"][4], 0xFF)
	assert_eq(Reader.of(d, 18)[0]["fields"][18], 0xFF, "session avg cadence invalid")


func test_samples_before_start_after_stop_and_backwards_are_ignored() -> void:
	var rec := RideRecorder.new()
	rec.record(0.0, 999.0, 90.0, 30.0)
	assert_false(rec.is_recording())
	rec.start("g", "c", START, 10.0)
	assert_true(rec.is_recording())
	rec.record(10.0, 100.0, 90.0, 30.0)
	rec.record(11.0, 100.0, 90.0, 30.0)
	rec.record(10.5, 500.0, 90.0, 30.0)
	assert_push_warning("time went backwards")
	rec.stop(12.0)
	assert_false(rec.is_recording())
	rec.record(13.0, 999.0, 90.0, 30.0)
	assert_eq(rec.record_count(), 3)
	assert_eq(float(rec.summary()["max_power_w"]), 100.0)


func test_timer_pause_counts_in_elapsed_not_timer() -> void:
	var rec := RideRecorder.new()
	rec.start("g", "c", START, 0.0)
	rec.record(0.0, 100.0, 80.0, 20.0)
	rec.set_timer_running(false, 10.0)
	rec.set_timer_running(false, 11.0)
	rec.set_timer_running(true, 25.0)
	rec.record(30.0, 100.0, 80.0, 20.0)
	rec.stop(40.0)
	var s := rec.summary()
	assert_almost_eq(float(s["duration_s"]), 40.0, 0.001)
	assert_almost_eq(float(s["timer_s"]), 25.0, 0.001, "15 s paused")
	assert_eq(rec.record_count(), 41, "records continue while paused")
	var d := Reader.read(rec.fit_bytes())
	var evs := Reader.of(d, 21)
	var types: Array = []
	for e: Dictionary in evs:
		types.append([int(e["fields"][253]) - (START - 631065600), int(e["fields"][1])])
	assert_eq(types, [[0, 0], [10, 4], [25, 0], [40, 4]], "start, stop, start, stop")
	assert_eq(Reader.of(d, 18)[0]["fields"][8], 25000, "session timer time")
	assert_eq(Reader.of(d, 18)[0]["fields"][7], 40000, "session elapsed time")


func test_summary_keys() -> void:
	var rec := RideRecorder.new()
	rec.ride_id = "11111111-2222-4333-8444-555555555555"
	rec.start("workout", "e2e", START, 0.0)
	rec.record(0.0, 100.0, 80.0, 20.0)
	rec.stop(5.0)
	var s := rec.summary()
	for k in ["ride_id", "game_id", "content_id", "utc_start", "duration_s", "distance_m",
			"records", "laps", "kj", "avg_power_w", "max_power_w", "avg_cadence_rpm",
			"max_cadence_rpm", "fit_path"]:
		assert_true(s.has(k), "summary has %s" % k)
	assert_eq(s["ride_id"], "11111111-2222-4333-8444-555555555555", "a preset ride id is kept")
	assert_eq(s["utc_start"], "2027-01-15T08:00:00Z")
	assert_eq(int(s["utc_start_unix"]), START)
	assert_eq(s["game_id"], "workout")
	assert_eq(s["content_id"], "e2e")
	var lap0: Dictionary = (s["laps"] as Array)[0]
	for k in ["label", "start_s", "duration_s", "avg_power_w", "max_power_w", "kj", "distance_m"]:
		assert_true(lap0.has(k), "lap has %s" % k)


func test_ride_ids_are_uuid_v4_and_new_per_ride() -> void:
	var re := RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
	var a := RideRecorder.new()
	a.start("g", "c", START, 0.0)
	var b := RideRecorder.new()
	b.start("g", "c", START, 0.0)
	assert_not_null(re.search(a.ride_id), a.ride_id)
	assert_ne(a.ride_id, b.ride_id)


func test_save_names_and_json() -> void:
	var rec := RideRecorder.new()
	rec.start("workout", "easy30", START, 0.0)
	_ride_20hz(rec, 0.0, 10.0, 180.0, 88.0, 30.0)
	assert_eq(rec.file_stem(), "20270115T080000Z_workout")
	var path := rec.save()
	assert_eq(path, Paths.rides_dir().path_join("20270115T080000Z_workout.fit"))
	assert_false(rec.is_recording(), "save stops the ride")
	assert_true(FileAccess.file_exists(path))
	var json_path := path.get_basename() + ".json"
	assert_true(FileAccess.file_exists(json_path))
	var s: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	assert_eq(s["fit_path"], path)
	assert_eq(s["ride_id"], rec.ride_id)
	assert_eq(int(s["records"]), rec.record_count())
	assert_true(FitCrc.file_is_valid(FileAccess.get_file_as_bytes(path)))
	var rec2 := RideRecorder.new()
	rec2.start("workout", "easy30", START, 0.0)
	rec2.stop(1.0)
	assert_eq(rec2.save(), Paths.rides_dir().path_join("20270115T080000Z_workout_2.fit"), "no overwrite")
	var rec3 := RideRecorder.new()
	rec3.start("My Game!", "c", START, 0.0)
	rec3.stop(1.0)
	assert_eq(rec3.file_stem(), "20270115T080000Z_mygame", "safe file name")


func test_save_into_a_directory_and_save_as() -> void:
	var rec := RideRecorder.new()
	rec.start("workout", "c", START, 0.0)
	rec.stop(3.0)
	var sub := _dir.path_join("elsewhere/deeper")
	var p := rec.save(sub)
	assert_eq(p.get_base_dir(), sub)
	var exact := _dir.path_join("fit/report_slot0.fit")
	assert_eq(rec.save_as(exact), exact)
	assert_true(FileAccess.file_exists(_dir.path_join("fit/report_slot0.json")))


func test_save_before_start_fails_softly() -> void:
	var rec := RideRecorder.new()
	assert_eq(rec.save(), "")
	assert_push_warning("before start")


func test_fit_totals_equal_the_summary() -> void:
	var rec := RideRecorder.new()
	rec.start("workout", "c", START, 3.0)
	var t := 3.0
	var rng := SeededRng.make(3)
	for i in 2400:
		t = 3.0 + float(i) * DT
		if i == 600:
			rec.lap("Work", t)
		if i == 1800:
			rec.lap("Cool-down", t)
		rec.record(t, 150.0 + SeededRng.range_f(rng, 0.0, 100.0), 85.0 + SeededRng.range_f(rng, 0.0, 10.0), 28.0 + SeededRng.range_f(rng, 0.0, 8.0))
	rec.stop(t)
	var s := rec.summary()
	var d := Reader.read(rec.fit_bytes())
	assert_eq(d["errors"], [])
	assert_eq(Reader.of(d, 20).size(), int(s["records"]), "record count")
	var sess: Dictionary = Reader.of(d, 18)[0]["fields"]
	assert_eq(sess[48], roundi(float(s["kj"]) * 1000.0), "total_work")
	assert_eq(sess[7], roundi(float(s["duration_s"]) * 1000.0), "elapsed")
	assert_eq(sess[8], roundi(float(s["timer_s"]) * 1000.0), "timer")
	assert_eq(sess[9], roundi(float(s["distance_m"]) * 100.0), "distance")
	assert_eq(sess[20], roundi(float(s["avg_power_w"])), "avg power")
	assert_eq(sess[21], roundi(float(s["max_power_w"])), "max power")
	assert_eq(sess[18], roundi(float(s["avg_cadence_rpm"])), "avg cadence")
	assert_eq(sess[19], roundi(float(s["max_cadence_rpm"])), "max cadence")
	assert_eq(sess[26], (s["laps"] as Array).size(), "num_laps")
	var laps := Reader.of(d, 19)
	assert_eq(laps.size(), 3)
	var work_sum := 0
	for i in laps.size():
		var lf: Dictionary = laps[i]["fields"]
		var ls: Dictionary = (s["laps"] as Array)[i]
		assert_eq(lf[41], roundi(float(ls["kj"]) * 1000.0), "lap %d work" % i)
		assert_eq(lf[7], roundi(float(ls["duration_s"]) * 1000.0), "lap %d elapsed" % i)
		assert_eq(lf[19], roundi(float(ls["avg_power_w"])), "lap %d avg power" % i)
		assert_eq(Reader.dev_string(laps[i]["dev"][0]), str(ls["label"]))
		work_sum += int(lf[41])
	assert_almost_eq(work_sum, int(sess[48]), 2, "lap work adds up to the session's")
	assert_eq(Reader.of(d, 0).size(), 1, "file_id")
	assert_eq(Reader.of(d, 34).size(), 1, "activity")


func test_ten_minute_synthetic_ride() -> void:
	# Warm-up ramp 120 s, work 120 s, recovery 60 s, work 120 s, cool-down 180 s, each a lap,
	# fed at 20 Hz like LocalRider's ticks. Written to build/rides_test/ for tools/fit_check.
	var rec := RideRecorder.new()
	rec.utc_offset_s = 7200
	rec.start("workout", "synthetic10", START, 0.0)
	var plan := [["Warm-up", 120.0, 110.0, 160.0], ["Work 1", 120.0, 250.0, 250.0],
		["Recovery", 60.0, 120.0, 120.0], ["Work 2", 120.0, 260.0, 260.0], ["Cool-down", 180.0, 100.0, 100.0]]
	var t := 0.0
	var phase_start := 0.0
	for ph: Array in plan:
		rec.lap(str(ph[0]), phase_start)
		var steps := roundi(float(ph[1]) / DT)
		for i in steps:
			t = phase_start + float(i) * DT
			var f := float(i) / float(steps)
			var p := lerpf(float(ph[2]), float(ph[3]), f)
			rec.record(t, p, 85.0 + 10.0 * f, 25.0 + p / 20.0)
		phase_start += float(ph[1])
	rec.record(600.0, 100.0, 85.0, 30.0)
	rec.stop(600.0)
	assert_eq(rec.record_count(), 601, "0..600 s")
	assert_eq(rec.lap_count(), 5, "five phases, the first renames the opening lap")
	var s := rec.summary()
	assert_almost_eq(float(s["duration_s"]), 600.0, 0.001)
	var labels: Array = []
	for l: Dictionary in s["laps"]:
		labels.append(l["label"])
	assert_eq(labels, ["Warm-up", "Work 1", "Recovery", "Work 2", "Cool-down"])
	var out_dir := ProjectSettings.globalize_path("res://build/rides_test")
	var path := rec.save_as(out_dir.path_join("ten_minute_ride.fit"))
	assert_ne(path, "")
	var bytes := FileAccess.get_file_as_bytes(path)
	assert_true(FitCrc.file_is_valid(bytes))
	var d := Reader.read(bytes)
	assert_eq(d["errors"], [])
	assert_eq(Reader.of(d, 20).size(), 601)
	assert_eq(Reader.of(d, 19).size(), 5)
	var sess: Dictionary = Reader.of(d, 18)[0]["fields"]
	assert_eq(sess[5], 2)
	assert_eq(sess[6], 58)
	assert_eq(sess[7], 600000)
	assert_eq(Reader.of(d, 34)[0]["fields"][5], START + 600 - 631065600 + 7200, "local timestamp")
