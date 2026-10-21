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

	func setup(args: Dictionary) -> String:
		calls.append("setup")
		seen["setup_args"] = args
		seen["user_dir"] = Paths.user_dir()
		return setup_error

	func run_to_end() -> String:
		calls.append("run")
		return end_reason

	func write_report() -> String:
		calls.append("write")
		return report_path

	func sim_seconds() -> float:
		return 660.0


const BASE: Array[String] = ["--mock-trainer", "--caller-cwd=C:/work", "--game=_template", "--report=build/r.json"]

var env: Dictionary = {}
var parse_calls: Array = []
var parse_result: Dictionary = {}
var made_runner: bool = false
## What the next fake runner does, and what the fakes recorded.
var setup_error: String = ""
var end_reason: String = "complete"
var report_path: String = "C:/reports/r.json"
var calls: Array[String] = []
var seen: Dictionary = {}


func before_each() -> void:
	env = {"WATTLANDS_NO_HW_CONTROL": "1", "WATTLANDS_NO_NETWORK_INTEGRATIONS": "1"}
	parse_calls = []
	parse_result = {"game": "_template", "content": "default", "seed": 1}
	made_runner = false
	setup_error = ""
	end_reason = "complete"
	report_path = "C:/reports/r.json"
	calls = []
	seen = {}


func _cli() -> GameSimCli:
	var cli := GameSimCli.new()
	cli.isolate_user_dir = false
	cli.env_fn = func(n: String) -> String: return str(env.get(n, ""))
	cli.parse_fn = func(a: PackedStringArray) -> Dictionary:
		parse_calls.append(Array(a))
		return parse_result.duplicate()
	cli.make_runner = func() -> GameSimRunner:
		made_runner = true
		var r := FakeRunner.new()
		r.calls = calls
		r.seen = seen
		r.setup_error = setup_error
		r.end_reason = end_reason
		r.report_path = report_path
		return r
	return cli


func _run(extra: Array = [], base: Array[String] = BASE) -> Array:
	var cli := _cli()
	var code := cli.run(PackedStringArray(base + extra), self)
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
	assert_eq(_run(["--mock-trainer=false"], no_mock)[0], GameSimCli.EXIT_USAGE)
	assert_eq(_run(["--mock-trainer=erg"], no_mock)[0], GameSimCli.EXIT_OK)


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
	var dir := Paths.make_temp_dir("cli_override")
	var f := FileAccess.open(dir.path_join("over.json"), FileAccess.WRITE)
	f.store_string("{\"default.json\": {\"nudge_pct\": 4}}")
	f.close()
	var base: Array[String] = ["--mock-trainer", "--caller-cwd=" + dir.replace("/", "\\"), "--game=_template",
		"--report=out\\r.json", "--override=over.json"]
	var r := _run([], base)
	assert_eq(r[0], GameSimCli.EXIT_OK, _errors(r[1]))
	assert_has(parse_calls[0], "--report=" + dir.path_join("out/r.json"))
	assert_has(parse_calls[0], "--override=" + dir.path_join("over.json"))
	GameSimCli.remove_tree(dir)
	var missing := _run(["--override=nope.json"])
	assert_eq(missing[0], GameSimCli.EXIT_USAGE)
	assert_string_contains(_errors(missing[1]), "--override=C:/work/nope.json")


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


func test_help_prints_usage() -> void:
	var r := _run(["--help"], [])
	assert_eq(r[0], GameSimCli.EXIT_OK)
	assert_string_contains("\n".join(r[1].out), "--player-options")


func test_the_run_uses_a_temp_user_dir_and_removes_it() -> void:
	var outer := Paths.make_temp_dir("cli_outer")
	Paths.set_override(outer)
	var cli := _cli()
	cli.isolate_user_dir = true
	assert_eq(cli.run(PackedStringArray(BASE), self), GameSimCli.EXIT_OK)
	assert_ne(seen.get("user_dir", outer), outer, "the run saw its own temp user dir")
	assert_false(DirAccess.dir_exists_absolute(str(seen.get("user_dir", ""))), "and removed it afterwards")
	assert_eq(Paths.user_dir(), outer, "the previous override is restored")
	Paths.set_override("")
	GameSimCli.remove_tree(outer)


func test_the_main_script_is_a_scene_tree_entry() -> void:
	var s: GDScript = load("res://tools/sdk/run_game_sim_main.gd")
	assert_not_null(s)
	assert_eq(s.get_instance_base_type(), &"SceneTree")
	assert_string_contains(s.source_code, "GameSimCli.new().run(OS.get_cmdline_user_args()")
