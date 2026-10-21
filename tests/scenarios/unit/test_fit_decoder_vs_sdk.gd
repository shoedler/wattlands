extends GutTest
## QaFitDecoder against Garmin's FIT SDK on real rides-encoder output (BRIEF 3.8, 7.5): two FIT
## files written by the GDScript FitEncoder and RideRecorder (rides, W1) and what @garmin/fitsdk
## decoded from them in the fallback contract's shape (tools/fit_check/README.md, "Fallback
## decoder contract"). The decoder's rides_contract() output must equal the SDK's, field by
## field, so tools/fit_check/check.mjs judges a file the same way with either decoder.
##
## Fixtures (tests/scenarios/unit/fixtures/, provenance in docs/decisions/qa.md):
## - rides_ten_minute.fit: rides' tools/fit_check/testdata/gdscript_ten_minute_ride.fit, five named
##   laps, 601 records;
## - rides_paused_dropout.fit: rides' test_paused_ride_with_a_dropout_for_fit_check output, a
##   jittered ~1 Hz feed, a timer pause (two starts and two stops), a trainer dropout and a
##   cool-down without cadence;
## - rides_fit_sdk.json: @garmin/fitsdk 21.218.0's view of both, via rides' fake_decode.mjs.

const FIXTURES := "res://tests/scenarios/unit/fixtures"
const SDK_JSON := FIXTURES + "/rides_fit_sdk.json"
const TOL := 1e-6


func _sdk_files() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SDK_JSON))
	assert_true(parsed is Dictionary, "%s holds a JSON object" % SDK_JSON)
	if not parsed is Dictionary:
		return []
	return (parsed as Dictionary).get("files", [])


func _decode(name: String) -> Dictionary:
	return QaFitDecoder.decode_file(ProjectSettings.globalize_path(FIXTURES.path_join(name)))


## Differences between the SDK's value and ours as "path: sdk vs ours" (numbers within TOL,
## relative to their size; int vs float never matters).
static func diff(sdk: Variant, ours: Variant, path: String, out: Array[String]) -> void:
	if (sdk is int or sdk is float) and (ours is int or ours is float):
		var a := float(sdk)
		var b := float(ours)
		if absf(a - b) > TOL * maxf(1.0, maxf(absf(a), absf(b))):
			out.append("%s: SDK %s vs ours %s" % [path, str(sdk), str(ours)])
		return
	if sdk is Dictionary and ours is Dictionary:
		for k: Variant in (sdk as Dictionary).keys():
			if k == "path":
				continue
			if not (ours as Dictionary).has(k):
				out.append("%s.%s: missing in ours" % [path, str(k)])
				continue
			diff((sdk as Dictionary)[k], (ours as Dictionary)[k], "%s.%s" % [path, str(k)], out)
		return
	if sdk is Array and ours is Array:
		if (sdk as Array).size() != (ours as Array).size():
			out.append(
				(
					"%s: %d entries in the SDK's, %d in ours"
					% [path, (sdk as Array).size(), (ours as Array).size()]
				)
			)
			return
		for i in (sdk as Array).size():
			diff((sdk as Array)[i], (ours as Array)[i], "%s[%d]" % [path, i], out)
		return
	if typeof(sdk) != typeof(ours) or sdk != ours:
		out.append("%s: SDK %s vs ours %s" % [path, JSON.stringify(sdk), JSON.stringify(ours)])


func test_the_comparison_reports_every_kind_of_difference() -> void:
	var out: Array[String] = []
	diff(
		{"a": 1, "b": [1, 2], "c": "x", "d": {"e": 1.0}, "path": "ignored"},
		{"a": 1.0000000001, "b": [1, 2], "c": "x", "d": {"e": 1.0}, "path": "other"},
		"f",
		out
	)
	assert_eq(out, [] as Array[String], "equal within tolerance; path is not compared")
	diff(
		{"a": 1, "b": [1, 2], "c": "x", "d": {"e": 1.0}, "n": null, "m": 1},
		{"a": 1.01, "b": [1], "c": "y", "d": {"e": 2.0}, "n": 0},
		"f",
		out
	)
	assert_eq(out.size(), 6, "\n".join(PackedStringArray(out)))


func test_both_fixtures_are_listed() -> void:
	var names: Array = _sdk_files().map(
		func(f: Variant) -> String: return str((f as Dictionary).get("path", ""))
	)
	assert_eq(names, ["rides_ten_minute.fit", "rides_paused_dropout.fit"])


func test_the_fallback_contract_equals_the_fit_sdk() -> void:
	for f: Variant in _sdk_files():
		var sdk: Dictionary = f
		var name := str(sdk["path"])
		var ours := QaFitDecoder.rides_contract(_decode(name))
		var problems: Array[String] = []
		diff(sdk, ours, name, problems)
		assert_eq(
			problems,
			[] as Array[String],
			"%s:\n%s" % [name, "\n".join(PackedStringArray(problems))]
		)


func test_real_rides_pass_every_wattlands_check() -> void:
	for name: String in ["rides_ten_minute.fit", "rides_paused_dropout.fit"]:
		var s := _decode(name)
		assert_eq(s["errors"], [], name)
		assert_eq(s["warnings"], [], name)
		assert_true(bool(s["crc_ok"]), "%s: header and file CRCs" % name)
		assert_eq((s["laps"] as Array).size(), 5, "%s: five laps" % name)
		assert_eq(int((s["session"] as Dictionary)["num_laps"]), 5)
		assert_eq(
			int((s["messages"] as Dictionary).get("field_description", 0)),
			1,
			"%s: the lap_name description" % name
		)


func test_lap_names_and_starts_of_the_ten_minute_ride() -> void:
	var s := _decode("rides_ten_minute.fit")
	var laps: Array = s["laps"]
	var names: Array = laps.map(func(l: Variant) -> String: return str((l as Dictionary)["name"]))
	assert_eq(names, ["Warm-up", "Work 1", "Recovery", "Work 2", "Cool-down"])
	var starts: Array = laps.map(
		func(l: Variant) -> float: return float((l as Dictionary)["start_s"])
	)
	assert_eq(starts, [0.0, 120.0, 240.0, 300.0, 420.0])
	assert_eq(int(s["records"]), 601)
	assert_eq(int(s["record_gaps"]), 0)


func test_the_paused_ride_keeps_its_pause_and_dropout() -> void:
	var s := _decode("rides_paused_dropout.fit")
	assert_eq(int(s["timer_starts"]), 2)
	assert_eq(int(s["timer_stops"]), 2)
	var ses: Dictionary = s["session"]
	assert_almost_eq(float(ses["elapsed_s"]), 300.0, TOL)
	assert_almost_eq(float(ses["timer_s"]), 290.0, TOL, "the 10 s pause is not timer time")
	assert_true(bool(s["record_timestamps_monotonic"]))
