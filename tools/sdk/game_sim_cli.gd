class_name GameSimCli
extends RefCounted
## The logic behind tools/run_game_sim (BRIEF 3.6): tools/sdk/run_game_sim_main.gd calls run().
## It refuses to run without the hardware and network locks or without --mock-trainer (the
## wrappers add both), checks the flag names and syntax, resolves --report and --override against
## the caller's directory (--caller-cwd; Godot itself runs in the project folder), parses the
## flags with GameSimRunner.parse_args, runs the session headless with MockTrainer riders and
## writes the report and FIT files with GameSimRunner.write_report().
##
## Exit codes: 0 the run completed (any end_reason), 2 bad flags or missing locks, 3 setup failed
## (unknown game or content, a rejected plan, ...), 4 the report could not be written.
## Tests replace parse_fn, make_runner and env_fn with fakes.

const EXIT_OK := 0
const EXIT_USAGE := 2
const EXIT_SETUP := 3
const EXIT_REPORT := 4

## run_game_sim flags that take a value (BRIEF 3.6). Only `rider` may repeat.
const VALUE_FLAGS: Array[String] = [
	"game", "content", "players", "bots", "rider", "sim-speed", "seed", "report", "autopilot",
	"ftp", "haptics-off", "options", "player-options", "override", "max-sim-seconds",
]
## run_game_sim flags without a value.
const BOOL_FLAGS: Array[String] = ["unverified"]
## Flags for this entry script only, never passed to parse_args.
const CLI_FLAGS: Array[String] = ["mock-trainer", "caller-cwd", "echo-args", "help"]
const LOCK_VARS: Array[String] = ["WATTLANDS_NO_HW_CONTROL", "WATTLANDS_NO_NETWORK_INTEGRATIONS"]

const USAGE := """usage: tools/run_game_sim --game=<id> --report=<path> [--content=<id>] [--players=<n>]
    [--bots=<n>] [--rider=<profile>]... [--sim-speed=<x>] [--seed=<n>] [--autopilot=all|none|<slot,...>]
    [--ftp=<w>[,<w>...]] [--unverified] [--haptics-off=<slot,...>] [--options=<json object>]
    [--player-options=<json array>] [--override=<json file>] [--max-sim-seconds=<n>]
  (tools/run_game_sim.ps1 in PowerShell; docs/GAME_SDK.md explains every flag and the report)"""

## (args: PackedStringArray) -> Dictionary, the parsed args or {"error": String}.
var parse_fn: Callable = func(a: PackedStringArray) -> Dictionary: return GameSimRunner.parse_args(a)
## () -> GameSimRunner.
var make_runner: Callable = func() -> GameSimRunner: return GameSimRunner.new()
## (name: String) -> String.
var env_fn: Callable = func(n: String) -> String: return OS.get_environment(n)
## Point Paths.user_dir() at a fresh temp dir for the run, so nothing reaches the real profile.
var isolate_user_dir: bool = true
## Everything printed, for tests.
var out: PackedStringArray = PackedStringArray()
var err: PackedStringArray = PackedStringArray()
## The args handed to parse_fn (after path resolution) and what it returned.
var passthrough: PackedStringArray = PackedStringArray()
var parsed: Dictionary = {}


## Runs one simulation; `parent` holds the runner node while it runs. Returns the exit code.
func run(raw: PackedStringArray, parent: Node) -> int:
	var flags: Array = []  # [[key, value or null], ...] in order
	for a in raw:
		if not a.begins_with("--") or a == "--":
			return _usage("unexpected argument \"%s\" (flags look like --name=value)" % a)
		var eq := a.find("=")
		flags.append([a.substr(2, eq - 2), a.substr(eq + 1)] if eq >= 0 else [a.substr(2), null])
	if _has(flags, "help"):
		_say(USAGE)
		return EXIT_OK
	for v in LOCK_VARS:
		if env_fn.call(v) != "1":
			return _usage("refusing to run: %s is not 1. Start simulations with tools/run_game_sim, which sets the hardware and network locks" % v)
	var mock: Variant = _value(flags, "mock-trainer")
	if not _has(flags, "mock-trainer") or (mock != null and str(mock).to_lower() in ["false", "0", "no", "off"]):
		return _usage("refusing to run without --mock-trainer: every simulated rider is a MockTrainer (tools/run_game_sim adds it)")
	var problems := _check(flags)
	if not problems.is_empty():
		for p in problems:
			_fail("run_game_sim: " + p)
		return _usage("")
	var cwd := str(_value(flags, "caller-cwd")) if _value(flags, "caller-cwd") != null else ""
	passthrough = PackedStringArray()
	for f: Array in flags:
		if CLI_FLAGS.has(f[0]):
			continue
		var v: Variant = f[1]
		if f[0] in ["report", "override"]:
			v = resolve_path(str(v), cwd)
		passthrough.append("--%s" % f[0] if v == null else "--%s=%s" % [f[0], v])
	if _has(flags, "override"):
		var op := resolve_path(str(_value(flags, "override")), cwd)
		var patch: Variant = parse_json(FileAccess.get_file_as_string(op)) if FileAccess.file_exists(op) else null
		if not (patch is Dictionary):
			return _usage("--override=%s is not a readable JSON object file (keys: files under content/<game>/, values: merge patches)" % op)
	if _has(flags, "echo-args"):
		_say("run_game_sim: args %s" % JSON.stringify(Array(passthrough)))
		_say("run_game_sim: locks %s=%s %s=%s" % [LOCK_VARS[0], env_fn.call(LOCK_VARS[0]), LOCK_VARS[1], env_fn.call(LOCK_VARS[1])])
		return EXIT_OK
	parsed = parse_fn.call(passthrough)
	if parsed.has("error"):
		return _usage("bad flags: %s" % parsed["error"])
	parsed["headless"] = true
	return _run_session(parent)


func _run_session(parent: Node) -> int:
	var temp_dir := ""
	var saved_override: String = Paths._override
	if isolate_user_dir:
		temp_dir = Paths.make_temp_dir("run_game_sim")
		Paths.set_override(temp_dir)
	var runner: GameSimRunner = make_runner.call()
	parent.add_child(runner)
	var code := EXIT_OK
	_say("run_game_sim: %s/%s, seed %s" % [parsed.get("game", "?"), parsed.get("content", "default"), parsed.get("seed", "?")])
	var setup_error := runner.setup(parsed)
	if setup_error != "":
		_fail("run_game_sim: setup failed: %s" % setup_error)
		code = EXIT_SETUP
	else:
		var reason := runner.run_to_end()
		var path := runner.write_report()
		if path == "":
			_fail("run_game_sim: the report could not be written (end_reason %s)" % reason)
			code = EXIT_REPORT
		else:
			_say("run_game_sim: end_reason=%s sim_seconds=%.1f report=%s" % [reason, runner.sim_seconds(), path])
	parent.remove_child(runner)
	runner.free()
	if isolate_user_dir:
		Paths.set_override(saved_override)
		remove_tree(temp_dir)
	return code


## Problems with the flag names and syntax ([] when fine). Values that need the game's
## manifest (option ranges, content ids) are GameSimRunner.parse_args's and setup's job.
func _check(flags: Array) -> Array[String]:
	var problems: Array[String] = []
	var seen := {}
	for f: Array in flags:
		var key: String = f[0]
		if not (VALUE_FLAGS.has(key) or BOOL_FLAGS.has(key) or CLI_FLAGS.has(key)):
			problems.append("unknown flag --%s" % key)
			continue
		if VALUE_FLAGS.has(key) and (f[1] == null or str(f[1]) == ""):
			problems.append("--%s needs a value: --%s=<value>" % [key, key])
			continue
		if BOOL_FLAGS.has(key) and f[1] != null and not (str(f[1]).to_lower() in ["true", "false", "1", "0"]):
			problems.append("--%s takes no value" % key)
		if seen.has(key) and key != "rider":
			problems.append("--%s given more than once" % key)
		seen[key] = true
		if VALUE_FLAGS.has(key):
			var msg := _check_value(key, str(f[1]))
			if msg != "":
				problems.append("--%s=%s: %s" % [key, f[1], msg])
	for key in ["game", "report"]:
		if not seen.has(key):
			problems.append("--%s is required" % key)
	var riders := _count(flags, "rider")
	var players := int(_value(flags, "players")) if str(_value(flags, "players")).is_valid_int() else 1
	if riders > 1 and riders != players:
		problems.append("--rider given %d times for %d human slots: give it once, or once per slot" % [riders, players])
	return problems


func _check_value(key: String, v: String) -> String:
	match key:
		"players":
			return "" if v.is_valid_int() and int(v) >= 1 and int(v) <= Wl.MAX_SLOTS else "an integer 1..%d" % Wl.MAX_SLOTS
		"bots", "seed":
			return "" if v.is_valid_int() and int(v) >= 0 else "an integer >= 0"
		"sim-speed", "max-sim-seconds":
			return "" if v.is_valid_float() and float(v) > 0.0 else "a number > 0"
		"ftp":
			for w in v.split(","):
				if not w.strip_edges().is_valid_float() or float(w) <= 0.0:
					return "watts > 0, comma separated"
		"autopilot", "haptics-off":
			if key == "autopilot" and v in ["all", "none"]:
				return ""
			for s in v.split(","):
				if not s.strip_edges().is_valid_int() or int(s) < 0:
					return "slot numbers (0, 1, ...), comma separated" + (", or all or none" if key == "autopilot" else "")
		"options":
			return "" if parse_json(v) is Dictionary else "a JSON object"
		"player-options":
			var arr: Variant = parse_json(v)
			if not (arr is Array) or (arr as Array).any(func(o: Variant) -> bool: return not (o is Dictionary)):
				return "a JSON array of objects, one per human slot"
	return ""


## Parsed JSON, or null when `text` is not JSON (without logging an engine error).
static func parse_json(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null


## `p` made absolute against `cwd` (the caller's directory) unless it already is.
static func resolve_path(p: String, cwd: String) -> String:
	var path := p.replace("\\", "/")
	if path.is_absolute_path() or cwd == "":
		return path
	return cwd.replace("\\", "/").path_join(path).simplify_path()


static func remove_tree(dir: String) -> void:
	var da: DirAccess = DirAccess.open(dir) if dir != "" else null
	if da == null:
		return
	for f in da.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in da.get_directories():
		remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


func _has(flags: Array, key: String) -> bool:
	return flags.any(func(f: Array) -> bool: return f[0] == key)


func _count(flags: Array, key: String) -> int:
	return flags.filter(func(f: Array) -> bool: return f[0] == key).size()


## The last value given for `key` (null when absent or bare).
func _value(flags: Array, key: String) -> Variant:
	var v: Variant = null
	for f: Array in flags:
		if f[0] == key:
			v = f[1]
	return v


func _usage(msg: String) -> int:
	if msg != "":
		_fail("run_game_sim: " + msg)
	_fail(USAGE)
	return EXIT_USAGE


func _say(line: String) -> void:
	out.append(line)
	print(line)


func _fail(line: String) -> void:
	err.append(line)
	printerr(line)
