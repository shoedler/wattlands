extends GutTest
## BRIEF 3.8 "decode every FIT file the tests write with @garmin/fitsdk": the scenario tests copy
## each FIT they write (and its summary JSON) into build/scenarios/, which the fit step of
## tools/run_tests decodes with tools/fit_check. These are the helpers behind that copy
## (scenario_lib.gd: fit_files, prepare_fit_dir, copy_fits; scenario_test.gd: fit_copy_dir).

const S := preload("res://tests/scenarios/lib/scenario_lib.gd")
const ScenarioTest := preload("res://tests/scenarios/lib/scenario_test.gd")

var _dirs: Array[String] = []


func after_each() -> void:
	for d in _dirs:
		S.remove_tree(d)
	_dirs.clear()


func _temp() -> String:
	var d := Paths.make_temp_dir("wattlands_fit_copy")
	_dirs.append(d)
	return d


static func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_the_copy_dir_is_build_scenarios_which_the_fit_step_decodes() -> void:
	assert_eq(S.FIT_COPY_DIR, "res://build/scenarios")
	assert_eq(ScenarioTest.fit_copy_dir(), ProjectSettings.globalize_path("res://build/scenarios"))
	assert_true(
		ScenarioTest.fit_copy_dir().ends_with("/build/scenarios"), "an absolute path in the project"
	)
	var steps := FileAccess.get_file_as_string(
		ProjectSettings.globalize_path("res://tools/lib/run_tests.mjs")
	)
	assert_string_contains(steps, "'build/scenarios'", false)


func test_fit_files_are_found_recursively_and_sorted() -> void:
	var d := _temp()
	_write(d.path_join("b.fit"), "b")
	_write(d.path_join("fit/a_slot0.fit"), "a")
	_write(d.path_join("fit/a_slot0.json"), "{}")
	_write(d.path_join("deep/x/C.FIT"), "c")
	_write(d.path_join("report.json"), "{}")
	_write(d.path_join("notes.fit.txt"), "n")
	assert_eq(
		S.fit_files(d),
		(
			[d.path_join("b.fit"), d.path_join("deep/x/C.FIT"), d.path_join("fit/a_slot0.fit")]
			as Array[String]
		)
	)
	assert_eq(S.fit_files(d.path_join("missing")), [] as Array[String])
	assert_eq(S.fit_files(""), [] as Array[String])


func test_the_copy_dir_is_cleared_once_per_run() -> void:
	var d := _temp().path_join("scenarios")
	_write(d.path_join("old_test/stale.fit"), "stale")
	_write(d.path_join("stale.json"), "{}")
	assert_true(S.prepare_fit_dir(d, "run-a"), "a new run clears the stale files")
	assert_true(DirAccess.dir_exists_absolute(d))
	assert_false(FileAccess.file_exists(d.path_join("old_test/stale.fit")))
	assert_false(DirAccess.dir_exists_absolute(d.path_join("old_test")))
	assert_false(FileAccess.file_exists(d.path_join("stale.json")))
	assert_eq(FileAccess.get_file_as_string(d.path_join(S.FIT_RUN_STAMP)), "run-a")
	assert_eq(S.fit_files(d), [] as Array[String], "the stamp isn't a FIT for fit_check")
	_write(d.path_join("first_script/t/x.fit"), "x")
	assert_false(S.prepare_fit_dir(d, "run-a"), "the same run's next script keeps the copies")
	assert_true(FileAccess.file_exists(d.path_join("first_script/t/x.fit")))
	assert_true(S.prepare_fit_dir(d, "run-b"), "the next run starts empty")
	assert_false(FileAccess.file_exists(d.path_join("first_script/t/x.fit")))
	assert_eq(FileAccess.get_file_as_string(d.path_join(S.FIT_RUN_STAMP)), "run-b")


func test_copy_fits_keeps_the_layout_and_the_summary_next_to_each_fit() -> void:
	var src := _temp()
	var dest := _temp().path_join("scenarios/test_x/test_y")
	_write(src.path_join("fit/e2e_slot0.fit"), "FIT0")
	_write(src.path_join("fit/e2e_slot0.json"), '{"records": 3}')
	_write(src.path_join("sub/plain.fit"), "FIT1")
	_write(src.path_join("e2e.json"), '{"report": true}')
	var res := S.copy_fits(src, dest)
	assert_eq(res["errors"], [] as Array[String])
	assert_eq(
		res["copied"],
		[dest.path_join("fit/e2e_slot0.fit"), dest.path_join("sub/plain.fit")] as Array[String]
	)
	assert_eq(FileAccess.get_file_as_string(dest.path_join("fit/e2e_slot0.fit")), "FIT0")
	assert_eq(
		FileAccess.get_file_as_string(dest.path_join("fit/e2e_slot0.json")),
		'{"records": 3}',
		"the recorder's summary goes along, so fit_check compares the totals"
	)
	assert_eq(FileAccess.get_file_as_string(dest.path_join("sub/plain.fit")), "FIT1")
	assert_false(FileAccess.file_exists(dest.path_join("sub/plain.json")))
	assert_false(FileAccess.file_exists(dest.path_join("e2e.json")), "only FITs and summaries")
	# The same names again (a parameterized test): nothing is overwritten.
	_write(src.path_join("fit/e2e_slot0.fit"), "FIT0b")
	var again := S.copy_fits(src, dest)
	assert_eq(again["errors"], [] as Array[String])
	assert_eq(
		again["copied"],
		[dest.path_join("fit/e2e_slot0_2.fit"), dest.path_join("sub/plain_2.fit")] as Array[String]
	)
	assert_eq(FileAccess.get_file_as_string(dest.path_join("fit/e2e_slot0.fit")), "FIT0")
	assert_eq(FileAccess.get_file_as_string(dest.path_join("fit/e2e_slot0_2.fit")), "FIT0b")
	assert_eq(
		FileAccess.get_file_as_string(dest.path_join("fit/e2e_slot0_2.json")), '{"records": 3}'
	)
	var none := S.copy_fits(src.path_join("missing"), dest)
	assert_eq((none["copied"] as Array).size(), 0, "a missing dir copies nothing")
	assert_eq((none["errors"] as Array).size(), 0)
