extends GutTest
## Base class of the BRIEF 7.4 scenario tests (owned by qa; not collected itself: GUT only runs
## test_*.gd). Each test gets a fresh temp dir as Paths.user_dir() and for its reports and FIT
## files, removed afterwards. BRIEF 3.8: before that, every FIT the test wrote there (and the
## summary JSON next to it) is copied to build/scenarios/<test script>/<test name>/, where the fit
## step of tools/run_tests decodes it with @garmin/fitsdk. The first scenario script of a GUT run
## clears build/scenarios/ (stale FITs of earlier runs); later scripts of the run keep the copies.

const S := preload("res://tests/scenarios/lib/scenario_lib.gd")

## This GUT run's id for S.prepare_fit_dir(): the Godot process id and its start time (shared by
## every scenario script of the run, so build/scenarios/ is cleared once per run, not per test).
static var _fit_run_id: String = ""

var tmp: String = ""
## Runners start_runner() made: after_each calls cleanup() on each, which deletes the runner's
## temp root (wattlands_sim_* under OS temp; W3 QT-4).
var runners: Array[GameSimRunner] = []


## build/scenarios/ as an absolute path (S.FIT_COPY_DIR).
static func fit_copy_dir() -> String:
	return ProjectSettings.globalize_path(S.FIT_COPY_DIR)


func before_all() -> void:
	if _fit_run_id == "":
		var started_s := int(Time.get_unix_time_from_system() - Time.get_ticks_msec() / 1000.0)
		_fit_run_id = "%d@%d" % [OS.get_process_id(), started_s]
	S.prepare_fit_dir(fit_copy_dir(), _fit_run_id)


func before_each() -> void:
	tmp = Paths.make_temp_dir("wattlands_scenarios")
	Paths.set_override(tmp)


func after_each() -> void:
	for r in runners:
		if is_instance_valid(r):
			r.cleanup()
	runners.clear()
	Paths.set_override("")
	copy_fits_for_fit_check()
	S.remove_tree(tmp)
	tmp = ""


## Copies every FIT this test wrote under `tmp` (and its summary JSON) to
## build/scenarios/<test script>/<test name>/ for the fit step (BRIEF 3.8); a failed copy fails
## the test. Returns the copied FIT paths.
func copy_fits_for_fit_check() -> Array[String]:
	if tmp == "":
		return [] as Array[String]
	var test_name := "test"
	var current: Variant = gut.get_current_test_object() if gut != null else null
	if current is Object and str((current as Object).get("name")) != "":
		test_name = str((current as Object).get("name"))
	var script_name := (get_script() as Script).resource_path.get_file().get_basename()
	var dest := fit_copy_dir().path_join(script_name).path_join(test_name.validate_filename())
	var res := S.copy_fits(tmp, dest)
	for e: Variant in res["errors"]:
		fail_test("FIT copy for tools/fit_check: %s" % str(e))
	var copied: Array[String] = res["copied"]
	return copied


func report_path(stem: String) -> String:
	return tmp.path_join("%s.json" % stem)


## A GameSimRunner set up from run_game_sim flags and added to the tree (freed after the test),
## or null after a failed assertion.
func start_runner(f: PackedStringArray) -> GameSimRunner:
	var made := S.new_runner(f)
	assert_eq(made["error"], "", "GameSimRunner.parse_args(%s)" % " ".join(f))
	if made["runner"] == null:
		return null
	var runner: GameSimRunner = made["runner"]
	add_child_autofree(runner)
	runners.append(runner)
	var err := runner.setup(made["args"])
	assert_eq(err, "", "GameSimRunner.setup(%s)" % " ".join(f))
	if err != "":
		return null
	return runner


## The host's own rider after setup (asserts it exists and rides a MockTrainer).
func human_rider(runner: GameSimRunner) -> LocalRider:
	var rider := S.rider_of(runner, S.human_peer(runner))
	assert_not_null(rider, "the host's own rider is GameHost.local_rider(peer)")
	if rider != null:
		assert_not_null(S.mock_of(rider), "the rider rides a MockTrainer")
	return rider


## Up to `limit` problems, then a count of the rest.
static func first(problems: Array, limit: int = 8) -> String:
	if problems.size() <= limit:
		return "\n".join(PackedStringArray(problems))
	return (
		"%s\n... and %d more"
		% ["\n".join(PackedStringArray(problems.slice(0, limit))), problems.size() - limit]
	)
