extends GutTest
## tools/run_game_sim's entry logic (GameSimCli, tools/sdk/game_sim_cli.gd) with a fake runner and
## a fake flag parser: locks, --mock-trainer, flag names and syntax for every BRIEF 3.6 flag, path
## resolution against the caller's directory, the runner sequence and the exit codes.


## The CLI frees its runner after each run, so a fake records into containers the test owns.
class FakeRunner:
	extends GameSimRunner
	var calls: Array[String] = []
	var seen: Dictionary = {}
	var setup_error: String = ""
	var end_reason: String = "complete"
	var report_path: String = "C:/reports/r.json"
	## Feed these error types to the CLI's script error counter during run_to_end (stands in for
	## Godot logging errors, without a real SCRIPT ERROR in the test log).
	var log_error_types: Array[int] = []
	var cli: GameSimCli = null

	func setup(args: Dictionary) -> String:
		calls.append("setup")
		seen["setup_args"] = args
		seen["user_dir"] = Paths.user_dir()
		seen["process_mode"] = process_mode
		return setup_error

	func run_to_end() -> String:
		calls.append("run")
		var bt: Array[ScriptBacktrace] = []
		for t in log_error_types:
			if cli != null and cli.error_counter != null:
				cli.error_counter._log_error("run_to_end", "res://fake_game.gd", 7, "", "Invalid access to key 'x'", false, t, bt)
		return end_reason

	func write_report() -> String:
		calls.append("write")
		return report_path

	func sim_seconds() -> float:
		return 660.0


const BASE: Array[String] = ["--mock-trainer=erg", "--caller-cwd=C:/work", "--game=_template", "--report=build/r.json"]

var env: Dictionary = {}
var parse_calls: Array = []
var parse_result: Dictionary = {}
var made_runner: bool = false
## What the next fake runner does, and what the fakes recorded.
var setup_error: String = ""
var end_reason: String = "complete"
var report_path: String = "C:/reports/r.json"
var log_error_types: Array[int] = []
var calls: Array[String] = []
var seen: Dictionary = {}
## Temp dirs made by a test (removed in after_each).
var temp_dirs: Array[String] = []


func before_each() -> void:
	env = {"WATTLANDS_NO_HW_CONTROL": "1", "WATTLANDS_NO_NETWORK_INTEGRATIONS": "1"}
	parse_calls = []
	parse_result = {"game": "_template", "content": "default", "seed": 1}
	made_runner = false
	setup_error = ""
	end_reason = "complete"
	report_path = "C:/reports/r.json"
	log_error_types = []
	calls = []
	seen = {}
	Paths.set_override(_temp_dir("cli_user"))  # anything the code under test persists lands here


func after_each() -> void:
	Paths.set_override("")
	for d in temp_dirs:
		GameSimCli.remove_tree(d)
	temp_dirs.clear()


func _temp_dir(prefix: String) -> String:
	var d := Paths.make_temp_dir(prefix)
	temp_dirs.append(d)
	return d


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _cli() -> GameSimCli:
	var cli := GameSimCli.new()
	cli.isolate_user_dir = false
	cli.env_fn = func(n: String) -> String: return str(env.get(n, ""))
	cli.parse_fn = func(a: PackedStringArray) -> Dictionary:
		parse_calls.append(Array(a))
		return parse_result.duplicate()
	var cli_ref: WeakRef = weakref(cli)  # a strong capture would make cli -> make_runner -> cli a leaking cycle
	cli.make_runner = func() -> GameSimRunner:
		made_runner = true
		var r := FakeRunner.new()
		r.calls = calls
		r.seen = seen
		r.setup_error = setup_error
		r.end_reason = end_reason
		r.report_path = report_path
		r.log_error_types = log_error_types
		r.cli = cli_ref.get_ref()
		return r
	return cli


func _run(extra: Array = [], base: Array[String] = BASE) -> Array:
	var cli := _cli()
	var code := cli.run(PackedStringArray(base + extra), self)
	return [code, cli]


func _main(extra: Array = [], base: Array[String] = BASE) -> Array:
	var cli := _cli()
	var code := cli.main(PackedStringArray(base + extra), self)
	return [code, cli]


func _errors(cli: GameSimCli) -> String:
	return "\n".join(cli.err)


func test_a_good_run_calls_setup_run_and_write_and_exits_0() -> void:
	var r := _run(["--content=short", "--players=2", "--bots=1", "--rider=erg", "--rider=zero", "--sim-speed=200", "--seed=3"])
	assert_eq(r[0], GameSimCli.EXIT_OK, _errors(r[1]))
	assert_eq(calls, ["setup", "run", "write"])
	assert_true(seen["setup_args"]["headless"], "run_game_sim is always headless")
	assert_eq(parse_calls.size(), 1)
	assert_eq(parse_calls[0], ["--game=_template", "--report=C:/work/build/r.json", "--content=short", "--players=2",
		"--bots=1", "--rider=erg", "--rider=zero", "--sim-speed=200", "--seed=3"], "wrapper flags never reach parse_args")
	assert_true(r[1].out[r[1].out.size() - 1].contains("end_reason=complete"))
	assert_true(r[1].out[r[1].out.size() - 1].contains("report=C:/reports/r.json"))
	assert_eq(get_children().filter(func(n: Node) -> bool: return n is GameSimRunner), [], "the runner is freed")
	assert_eq(seen["process_mode"], Node.PROCESS_MODE_ALWAYS, "the runner is a system node (BRIEF 4.1)")


func test_main_is_run_plus_a_script_error_check() -> void:
	var r := _main(["--seed=3"])
	assert_eq(r[0], GameSimCli.EXIT_OK, _errors(r[1]))
	assert_eq(calls, ["setup", "run", "write"])
	assert_eq(r[1].script_errors, 0)
	assert_null(r[1].error_counter, "the logger is removed after the run")


func test_a_run_that_logged_a_script_error_exits_5_and_keeps_its_report() -> void:
	log_error_types = [Logger.ERROR_TYPE_SCRIPT, Logger.ERROR_TYPE_SCRIPT]
	var r := _main()
	assert_eq(r[0], GameSimCli.EXIT_SCRIPT_ERRORS)
	assert_eq(calls, ["setup", "run", "write"], "the report is still written")
	assert_eq(r[1].script_errors, 2)
	assert_string_contains(_errors(r[1]), "2 script error(s)")
	assert_string_contains(_errors(r[1]), "Invalid access to key 'x' (res://fake_game.gd:7, run_to_end)")


func test_push_errors_and_warnings_are_not_script_errors() -> void:
	log_error_types = [Logger.ERROR_TYPE_ERROR, Logger.ERROR_TYPE_WARNING]
	var r := _main()
	assert_eq(r[0], GameSimCli.EXIT_OK, "push_error reports bad input, it is not a broken run")
	assert_eq(r[1].script_errors, 0)


func test_a_failing_exit_code_wins_over_the_script_error_code() -> void:
	log_error_types = [Logger.ERROR_TYPE_SCRIPT]
	report_path = ""
	assert_eq(_main()[0], GameSimCli.EXIT_REPORT)
	setup_error = "unknown game"
	calls.clear()
	assert_eq(_main()[0], GameSimCli.EXIT_SETUP)


func test_the_script_error_counter_is_a_godot_logger() -> void:
	var c := GameSimCli.ScriptErrorCounter.new()
	assert_is(c, Logger)
	var bt: Array[ScriptBacktrace] = []
	c._log_error("f", "res://a.gd", 1, "", "", false, Logger.ERROR_TYPE_SHADER, bt)
	c._log_error("g", "res://b.gd", 2, "code_text", "", false, Logger.ERROR_TYPE_SCRIPT, bt)
	c._log_error("h", "res://c.gd", 3, "", "later", false, Logger.ERROR_TYPE_SCRIPT, bt)
	assert_eq(c.snapshot(), [2, "code_text (res://b.gd:2, g)"], "counts script errors and keeps the first")


func test_every_end_reason_is_a_completed_run() -> void:
	for reason: String in ["complete", "timeout", "paused"]:
		end_reason = reason
		var r := _run()
		assert_eq(r[0], GameSimCli.EXIT_OK, reason)
		assert_true("\n".join(r[1].out).contains("end_reason=" + reason))


func test_a_setup_error_exits_3_and_never_runs() -> void:
	setup_error = "plan rejected: warm-up target 70% above 65%"
	var r := _run()
	assert_eq(r[0], GameSimCli.EXIT_SETUP)
	assert_eq(calls, ["setup"])
	assert_string_contains(_errors(r[1]), "plan rejected")


func test_an_unwritten_report_exits_4() -> void:
	report_path = ""
	assert_eq(_run()[0], GameSimCli.EXIT_REPORT)


func test_a_parser_error_exits_2_before_any_runner_exists() -> void:
	parse_result = {"error": "--player-options[0].wave_offset: 9 is above max 5"}
	var r := _run()
	assert_eq(r[0], GameSimCli.EXIT_USAGE)
	assert_false(made_runner)
	assert_string_contains(_errors(r[1]), "wave_offset")


func test_it_refuses_to_run_without_both_locks() -> void:
	for v: String in ["WATTLANDS_NO_HW_CONTROL", "WATTLANDS_NO_NETWORK_INTEGRATIONS"]:
		env = {"WATTLANDS_NO_HW_CONTROL": "1", "WATTLANDS_NO_NETWORK_INTEGRATIONS": "1"}
		env.erase(v)
		var r := _run()
		assert_eq(r[0], GameSimCli.EXIT_USAGE, v)
		assert_string_contains(_errors(r[1]), v)
		assert_eq(parse_calls, [], "nothing parsed or run")
		assert_false(made_runner)
	env["WATTLANDS_NO_HW_CONTROL"] = "0"
	assert_eq(_run()[0], GameSimCli.EXIT_USAGE)


func test_it_refuses_to_run_without_mock_trainer() -> void:
	var no_mock: Array[String] = ["--caller-cwd=C:/work", "--game=_template", "--report=r.json"]
	var r := _run([], no_mock)
	assert_eq(r[0], GameSimCli.EXIT_USAGE)
	assert_string_contains(_errors(r[1]), "--mock-trainer")
	assert_eq(parse_calls, [])
	assert_eq(_run(["--mock-trainer=false"], no_mock)[0], GameSimCli.EXIT_USAGE)
	assert_eq(_run(["--mock-trainer=off"], no_mock)[0], GameSimCli.EXIT_USAGE)
	assert_eq(_run(["--mock-trainer=erg"], no_mock)[0], GameSimCli.EXIT_OK)
	assert_eq(_run(["--mock-trainer"], no_mock)[0], GameSimCli.EXIT_OK, "a bare flag counts too")


func test_every_brief_flag_is_accepted_and_passed_through_in_order() -> void:
	var flags := ["--content=default", "--players=3", "--bots=1", "--rider=erg:compliance=0.9",
		"--rider=erg+cadence_drop:rpm=40,at_s=1200", "--rider=zero", "--sim-speed=200", "--seed=7",
		"--autopilot=0,2", "--ftp=180,220,250,200", "--unverified", "--haptics-off=1",
		"--options={\"boosts\":false}", "--player-options=[{\"work_offset\":5},{},{\"work_offset\":-10}]",
		"--max-sim-seconds=900"]
	var r := _run(flags)
	assert_eq(r[0], GameSimCli.EXIT_OK, _errors(r[1]))
	assert_eq(parse_calls[0].slice(2), flags)


func test_unknown_flags_missing_values_and_repeats_exit_2_and_name_the_flag() -> void:
	var cases := {
		"--player=2": "unknown flag --player",
		"--players": "--players needs a value",
		"--seed=": "--seed needs a value",
		"--unverified=yes": "--unverified takes no value",
		"--content=a --content=b": "--content given more than once",
		"stray": "unexpected argument",
	}
	for c: String in cases:
		var r := _run(Array(c.split(" ")))
		assert_eq(r[0], GameSimCli.EXIT_USAGE, c)
		assert_string_contains(_errors(r[1]), cases[c])
		assert_eq(parse_calls, [], c)


func test_game_and_report_are_required() -> void:
	var r := _run([], ["--mock-trainer", "--players=1"])
	assert_eq(r[0], GameSimCli.EXIT_USAGE)
	assert_string_contains(_errors(r[1]), "--game is required")
	assert_string_contains(_errors(r[1]), "--report is required")


func test_unverified_reaches_the_parser_as_a_bare_flag() -> void:
	_run(["--unverified=true"])
	assert_has(parse_calls[0], "--unverified")
	parse_calls.clear()
	_run(["--unverified=1"])
	assert_has(parse_calls[0], "--unverified")
	parse_calls.clear()
	_run(["--unverified=false"])
	assert_false(parse_calls[0].any(func(a: String) -> bool: return a.begins_with("--unverified")), "false drops it")


func test_slot_lists_must_fit_the_slots() -> void:
	var cases := {
		"--players=6 --bots=3": "a session has at most 8 slots",
		"--players=2 --autopilot=0,2": "--autopilot=0,2: slot 2 is not a human slot (0..1)",
		"--players=2 --haptics-off=5": "--haptics-off=5: slot 5 is not a human slot (0..1)",
		"--players=1 --bots=1 --ftp=200,210,220": "3 values for 2 slots",
		"--players=1 --player-options=[{},{}]": "2 objects for 1 human slots",
	}
	for c: String in cases:
		var r := _run(Array(c.split(" ")))
		assert_eq(r[0], GameSimCli.EXIT_USAGE, c)
		assert_string_contains(_errors(r[1]), cases[c])
		assert_eq(parse_calls, [], c)
	for ok: String in ["--players=4 --bots=4", "--players=2 --autopilot=1 --haptics-off=0,1", "--players=1 --bots=2 --ftp=200,210,220",
			"--players=2 --bots=2 --ftp=180,220", "--players=3 --player-options=[{},{}]", "--autopilot=none"]:
		assert_eq(_run(Array(ok.split(" ")))[0], GameSimCli.EXIT_OK, ok)


func test_rider_is_given_once_or_once_per_human_slot() -> void:
	assert_eq(_run(["--players=3", "--rider=erg"])[0], GameSimCli.EXIT_OK)
	assert_eq(_run(["--players=2", "--rider=erg", "--rider=zero"])[0], GameSimCli.EXIT_OK)
	var r := _run(["--players=3", "--rider=erg", "--rider=zero"])
	assert_eq(r[0], GameSimCli.EXIT_USAGE)
	assert_string_contains(_errors(r[1]), "--rider given 2 times for 3 human slots")
	assert_eq(_run(["--rider=erg", "--rider=zero"])[0], GameSimCli.EXIT_USAGE, "--players defaults to 1")


func test_bad_values_are_refused_with_the_flag_named() -> void:
	for f: String in ["--players=0", "--players=x", "--players=9", "--bots=-1", "--seed=1.5", "--sim-speed=0",
			"--max-sim-seconds=-5", "--ftp=200,abc", "--ftp=0", "--autopilot=some", "--autopilot=0,-1",
			"--haptics-off=all", "--options=[1]", "--options=nope", "--player-options={\"a\":1}",
			"--player-options=[{},3]"]:
		var r := _run([f])
		assert_eq(r[0], GameSimCli.EXIT_USAGE, f)
		assert_string_contains(_errors(r[1]), f.get_slice("=", 0), false)


func test_good_values_pass() -> void:
	for f: String in ["--autopilot=all", "--autopilot=none", "--autopilot=0", "--ftp=150.5", "--sim-speed=0.5",
			"--options={}", "--player-options=[]", "--bots=0", "--seed=0"]:
		assert_eq(_run([f])[0], GameSimCli.EXIT_OK, f)


func test_report_and_override_resolve_against_the_callers_directory() -> void:
	var dir := _temp_dir("cli_override")
	_write(dir.path_join("over.json"), "{\"default.json\": {\"nudge_pct\": 4}}")
	var base: Array[String] = ["--mock-trainer=erg", "--caller-cwd=" + dir.replace("/", "\\"), "--game=_template",
		"--report=out\\r.json", "--override=over.json"]
	var r := _run([], base)
	assert_eq(r[0], GameSimCli.EXIT_OK, _errors(r[1]))
	assert_has(parse_calls[0], "--report=" + dir.path_join("out/r.json"))
	assert_has(parse_calls[0], "--override=" + dir.path_join("over.json"))
	var missing := _run(["--override=nope.json"])
	assert_eq(missing[0], GameSimCli.EXIT_USAGE)
	assert_string_contains(_errors(missing[1]), "--override=C:/work/nope.json")
	_write(dir.path_join("list.json"), "[1, 2]")
	var no_override: Array[String] = ["--mock-trainer=erg", "--caller-cwd=" + dir, "--game=_template", "--report=r.json"]
	assert_eq(_run(["--override=list.json"], no_override)[0], GameSimCli.EXIT_USAGE, "an override must be a JSON object")


func test_a_run_first_removes_what_an_earlier_run_left_at_the_report_path() -> void:
	var dir := _temp_dir("cli_stale")
	var old := ["r.json", "fit/r_slot0.fit", "fit/r_slot1.fit"]
	var other := ["r2.json", "fit/r2_slot0.fit", "fit/r_slotx.fit", "fit/r_slot0.fit.bak", "fit/rr_slot0.fit"]
	for f: String in old + other:
		_write(dir.path_join(f), "old")
	var base: Array[String] = ["--mock-trainer=erg", "--caller-cwd=" + dir, "--game=_template", "--report=r.json"]
	assert_eq(_run(["--echo-args"], base)[0], GameSimCli.EXIT_OK)
	assert_file_exists(dir.path_join("r.json"))
	setup_error = "plan rejected: warm-up target 70% above 65%"
	var r := _run([], base)
	assert_eq(r[0], GameSimCli.EXIT_SETUP)
	for f: String in old:
		assert_file_does_not_exist(dir.path_join(f))
	for f: String in other:
		assert_file_exists(dir.path_join(f))
	assert_string_contains("\n".join(r[1].out), "removed 3 file(s)")
	assert_eq(GameSimCli.clear_report(dir.path_join("r.json")), [], "nothing left to remove")
	assert_eq(GameSimCli.clear_report(""), [])


func test_a_parser_error_also_leaves_no_stale_report() -> void:
	var dir := _temp_dir("cli_stale_parse")
	_write(dir.path_join("r.json"), "old")
	parse_result = {"error": "--content=nope is not one of default, short"}
	var base: Array[String] = ["--mock-trainer=erg", "--caller-cwd=" + dir, "--game=_template", "--report=r.json"]
	assert_eq(_run([], base)[0], GameSimCli.EXIT_USAGE)
	assert_file_does_not_exist(dir.path_join("r.json"))


func test_resolve_path() -> void:
	assert_eq(GameSimCli.resolve_path("build/r.json", "C:/work"), "C:/work/build/r.json")
	assert_eq(GameSimCli.resolve_path("..\\r.json", "C:\\work\\sub"), "C:/work/r.json")
	assert_eq(GameSimCli.resolve_path("D:/x/r.json", "C:/work"), "D:/x/r.json")
	assert_eq(GameSimCli.resolve_path("/tmp/r.json", "/home/me"), "/tmp/r.json")
	assert_eq(GameSimCli.resolve_path("r.json", ""), "r.json", "no caller directory: left to Godot")


func test_echo_args_prints_the_resolved_flags_and_runs_nothing() -> void:
	var r := _run(["--echo-args", "--seed=4"])
	assert_eq(r[0], GameSimCli.EXIT_OK)
	assert_eq(parse_calls, [])
	assert_false(made_runner)
	var line: String = r[1].out[0]
	assert_true(line.begins_with("run_game_sim: args "))
	assert_eq(JSON.parse_string(line.trim_prefix("run_game_sim: args ")), ["--game=_template", "--report=C:/work/build/r.json", "--seed=4"])
	assert_string_contains(r[1].out[1], "WATTLANDS_NO_HW_CONTROL=1")
	assert_string_contains(r[1].out[1], "mock-trainer=erg")


func test_help_prints_usage() -> void:
	var r := _run(["--help"], [])
	assert_eq(r[0], GameSimCli.EXIT_OK)
	assert_string_contains("\n".join(r[1].out), "--player-options")


func test_the_run_uses_a_temp_user_dir_and_removes_it() -> void:
	var outer := _temp_dir("cli_outer")
	Paths.set_override(outer)
	var cli := _cli()
	cli.isolate_user_dir = true
	assert_eq(cli.run(PackedStringArray(BASE), self), GameSimCli.EXIT_OK)
	assert_ne(seen.get("user_dir", outer), outer, "the run saw its own temp user dir")
	assert_false(DirAccess.dir_exists_absolute(str(seen.get("user_dir", ""))), "and removed it afterwards")
	assert_eq(Paths.user_dir(), outer, "the previous override is restored")


func test_the_main_script_is_a_scene_tree_entry() -> void:
	var s: GDScript = load("res://tools/sdk/run_game_sim_main.gd")
	assert_not_null(s)
	assert_eq(s.get_instance_base_type(), &"SceneTree")
	assert_string_contains(s.source_code, "GameSimCli.new().main(OS.get_cmdline_user_args(), root)")
