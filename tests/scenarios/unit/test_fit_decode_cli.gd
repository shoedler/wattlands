extends GutTest
## tools/fit_decode/decode.gd's command line (QaFitDecoder.run_cli): arguments, directories,
## the text and JSON summaries, --expect-laps, --out and exit codes (0 ok, 1 errors, 2 usage).

var _dirs: Array[String] = []


func after_each() -> void:
	Paths.set_override("")
	for d in _dirs:
		_remove_tree(d)
	_dirs.clear()


func _temp() -> String:
	var d := Paths.make_temp_dir("wattlands_fit_decode_cli")
	_dirs.append(d)
	return d


func _write(path: String, bytes: PackedByteArray) -> String:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return path


func _json(result: Dictionary) -> Dictionary:
	var out: PackedStringArray = result["out"]
	assert_eq(out.size(), 1, "--json prints exactly one line")
	var parsed: Variant = JSON.parse_string(out[0])
	assert_true(parsed is Dictionary, "the line is a JSON object")
	return parsed if parsed is Dictionary else {}


func test_no_arguments_is_a_usage_error() -> void:
	var r := QaFitDecoder.run_cli(PackedStringArray())
	assert_eq(r["code"], 2)
	assert_string_contains("\n".join(r["err"]), "usage:")


func test_unknown_option_is_a_usage_error() -> void:
	var r := QaFitDecoder.run_cli(PackedStringArray(["--frobnicate", "x.fit"]))
	assert_eq(r["code"], 2)
	assert_string_contains("\n".join(r["err"]), "unknown option \"--frobnicate\"")


func test_bad_expect_laps_is_a_usage_error() -> void:
	var r := QaFitDecoder.run_cli(PackedStringArray(["--expect-laps=two", "x.fit"]))
	assert_eq(r["code"], 2)


func test_help() -> void:
	var r := QaFitDecoder.run_cli(PackedStringArray(["--help"]))
	assert_eq(r["code"], 0)
	assert_string_contains("\n".join(r["out"]), "decode.gd")


func test_one_good_file_text_output() -> void:
	var dir := _temp()
	var p := _write(dir.path_join("ride.fit"), QaFitWriter.activity({"records": 90, "laps": [30, 60]}))
	var r := QaFitDecoder.run_cli(PackedStringArray([p]))
	assert_eq(r["code"], 0)
	var text := "\n".join(r["out"])
	assert_string_contains(text, "%s: OK" % p)
	assert_string_contains(text, "errors: 0")
	assert_string_contains(text, "records: 90 (span 89 s)")
	assert_string_contains(text, "laps: 2")
	assert_string_contains(text, "1: start 0 s, duration 30 s")
	assert_string_contains(text, "2: start 30 s, duration 60 s")
	assert_string_contains(text, "session: sport 2, sub_sport 58, elapsed 90 s")
	assert_string_contains(text, "fit_decode: 1 file(s), 0 with errors")


func test_json_output_schema() -> void:
	var dir := _temp()
	var p := _write(dir.path_join("ride.fit"), QaFitWriter.activity())
	var r := QaFitDecoder.run_cli(PackedStringArray([p, "--json"]))
	assert_eq(r["code"], 0)
	var j := _json(r)
	assert_eq(j["decoder"], "wattlands-fit-decode-gd")
	assert_eq(j["ok"], true)
	assert_eq(int(j["failed"]), 0)
	var f: Dictionary = (j["files"] as Array)[0]
	assert_eq(f["path"], p)
	assert_eq(f["ok"], true)
	assert_eq(f["errors"], [])
	assert_eq(int(f["records"]), 120)
	assert_eq((f["laps"] as Array).size(), 2)
	for key: String in ["start_s", "duration_s", "work_kj", "avg_power_w"]:
		assert_true(((f["laps"] as Array)[0] as Dictionary).has(key), "lap key %s" % key)
	for key: String in ["sport", "sub_sport", "elapsed_s", "timer_s", "distance_m", "work_kj", "avg_power_w", "max_power_w", "avg_cadence_rpm", "max_cadence_rpm", "num_laps"]:
		assert_true((f["session"] as Dictionary).has(key), "session key %s" % key)


func test_directories_are_searched_recursively() -> void:
	var dir := _temp()
	_write(dir.path_join("a/one.fit"), QaFitWriter.activity())
	_write(dir.path_join("a/b/two.FIT"), QaFitWriter.activity({"records": 30, "laps": [30]}))
	_write(dir.path_join("a/notes.txt"), "not a fit file".to_utf8_buffer())
	var r := QaFitDecoder.run_cli(PackedStringArray([dir, "--json"]))
	assert_eq(r["code"], 0)
	var files: Array = _json(r)["files"]
	assert_eq(files.size(), 2)
	var paths: Array = files.map(func(f: Dictionary) -> String: return str(f["path"]).get_file())
	assert_has(paths, "one.fit")
	assert_has(paths, "two.FIT")


func test_any_bad_file_fails_the_run() -> void:
	var dir := _temp()
	_write(dir.path_join("good.fit"), QaFitWriter.activity())
	_write(dir.path_join("bad.fit"), QaFitWriter.activity_writer().to_bytes({"bad_file_crc": true}))
	var r := QaFitDecoder.run_cli(PackedStringArray([dir]))
	assert_eq(r["code"], 1)
	var text := "\n".join(r["out"])
	assert_string_contains(text, "bad.fit: FAIL")
	assert_string_contains(text, "good.fit: OK")
	assert_string_contains(text, "file CRC mismatch")
	assert_string_contains(text, "fit_decode: 2 file(s), 1 with errors")


func test_empty_directory_is_an_error() -> void:
	var dir := _temp()
	DirAccess.make_dir_recursive_absolute(dir.path_join("empty"))
	var r := QaFitDecoder.run_cli(PackedStringArray([dir.path_join("empty"), "--json"]))
	assert_eq(r["code"], 1)
	assert_string_contains(str(_json(r)["files"]), "no FIT files under")


func test_missing_file_is_an_error() -> void:
	var dir := _temp()
	var r := QaFitDecoder.run_cli(PackedStringArray([dir.path_join("nope.fit")]))
	assert_eq(r["code"], 1)
	assert_string_contains("\n".join(r["out"]), "no such file")


func test_expect_laps_flag() -> void:
	var dir := _temp()
	var p := _write(dir.path_join("ride.fit"), QaFitWriter.activity({"laps": [60, 60]}))
	assert_eq(QaFitDecoder.run_cli(PackedStringArray([p, "--expect-laps=2"]))["code"], 0)
	var r := QaFitDecoder.run_cli(PackedStringArray([p, "--expect-laps=3"]))
	assert_eq(r["code"], 1)
	assert_string_contains("\n".join(r["out"]), "expected 3 lap(s), found 2")


func test_out_writes_the_json_report() -> void:
	var dir := _temp()
	var p := _write(dir.path_join("ride.fit"), QaFitWriter.activity())
	var target := dir.path_join("reports/fit.json")
	var r := QaFitDecoder.run_cli(PackedStringArray([p, "--out=%s" % target]))
	assert_eq(r["code"], 0)
	assert_true(FileAccess.file_exists(target))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(target))
	assert_true(parsed is Dictionary)
	assert_eq((parsed as Dictionary)["ok"], true)


func test_relative_paths_resolve_against_the_project_root() -> void:
	var root := ProjectSettings.globalize_path("res://").replace("\\", "/")
	assert_eq(QaFitDecoder.resolve_path("build/x.fit"), root.path_join("build/x.fit").simplify_path())
	assert_eq(QaFitDecoder.resolve_path("res://build/x.fit"), root.path_join("build/x.fit").simplify_path())
	assert_eq(QaFitDecoder.resolve_path("C:\\rides\\a.fit"), "C:/rides/a.fit")


static func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in da.get_directories():
		_remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)
