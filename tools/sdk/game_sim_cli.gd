class_name GameSimCli
extends RefCounted
## The logic behind tools/run_game_sim (BRIEF 3.6): tools/sdk/run_game_sim_main.gd calls main().
## It refuses to run without the hardware and network locks or without --mock-trainer (the
## wrappers add both), checks the flag names and syntax, resolves --report and --override against
## the caller's directory (--caller-cwd; Godot itself runs in the project folder), removes what an
## earlier run left at that report path, parses the flags with GameSimRunner.parse_args, runs the
## session headless with MockTrainer riders and writes the report and FIT files with
## GameSimRunner.write_report().
##
## Exit codes: 0 the run completed (any end_reason), 2 bad flags or missing locks, 3 setup failed
## (unknown game or content, a rejected plan, ...), 4 the report could not be written, 5 Godot
## logged a SCRIPT ERROR during the run (the report is written if the run got that far).
## Tests replace parse_fn, make_runner and env_fn with fakes.

const EXIT_OK := 0
const EXIT_USAGE := 2
const EXIT_SETUP := 3
const EXIT_REPORT := 4
const EXIT_SCRIPT_ERRORS := 5

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
## Counts Godot's script errors while main() runs (null outside main()).
var error_counter: ScriptErrorCounter = null
## Script errors logged during the last main() call, and the first one's description.
var script_errors: int = 0
var first_script_error: String = ""


## Counts SCRIPT ERRORs (GDScript runtime errors in this tool, the platform or the game) through
## Godot's Logger API. push_error and push_warning are not counted: they report bad input.
class ScriptErrorCounter:
	extends Logger
	var count: int = 0
	var first: String = ""
	var _mutex: Mutex = Mutex.new()

	## Godot calls this from any thread.
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mutex.lock()
		count += 1
		if first == "":
			first = "%s (%s:%d, %s)" % [rationale if rationale != "" else code, file, line, function]
		_mutex.unlock()

	func snapshot() -> Array:
		_mutex.lock()
		var out := [count, first]
		_mutex.unlock()
		return out


## The whole tool: run() with Godot's script errors counted. GDScript ends a function that hits a
## script error and returns its type's default (0 for run(), which would read as success), so a run
## that logged any SCRIPT ERROR exits EXIT_SCRIPT_ERRORS instead of 0 (BRIEF 7: no script errors).
func main(raw: PackedStringArray, parent: Node) -> int:
	error_counter = ScriptErrorCounter.new()
	OS.add_logger(error_counter)
	var code := run(raw, parent)
	OS.remove_logger(error_counter)
	var seen: Array = error_counter.snapshot()
	error_counter = null
	script_errors = int(seen[0])
	first_script_error = str(seen[1])
	if script_errors > 0 and code == EXIT_OK:
		_fail("run_game_sim: %d script error(s) during the run, the first: %s. Fix them (BRIEF 7); the report, if written, is kept" % [script_errors, first_script_error])
		return EXIT_SCRIPT_ERRORS
	return code


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
		if BOOL_FLAGS.has(f[0]):  # parse_args sees a bare flag or nothing: --unverified=false drops it
			if v != null and str(v).to_lower() in ["false", "0"]:
				continue
			v = null
		passthrough.append("--%s" % f[0] if v == null else "--%s=%s" % [f[0], v])
	if _has(flags, "override"):
		var op := resolve_path(str(_value(flags, "override")), cwd)
		var patch: Variant = parse_json(FileAccess.get_file_as_string(op)) if FileAccess.file_exists(op) else null
		if not (patch is Dictionary):
			return _usage("--override=%s is not a readable JSON object file (keys: files under content/<game>/, values: merge patches)" % op)
	if _has(flags, "echo-args"):
		_say("run_game_sim: args %s" % JSON.stringify(Array(passthrough)))
		_say("run_game_sim: locks %s=%s %s=%s mock-trainer=%s" % [LOCK_VARS[0], env_fn.call(LOCK_VARS[0]),
			LOCK_VARS[1], env_fn.call(LOCK_VARS[1]), "true" if mock == null else str(mock)])
		return EXIT_OK
	var report := resolve_path(str(_value(flags, "report")), cwd)
	var removed := clear_report(report)
	if not removed.is_empty():
		_say("run_game_sim: removed %d file(s) an earlier run left at %s (a failed run leaves no stale report)" % [removed.size(), report])
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
	var template_registry := _template_registry(parent)
	var runner: GameSimRunner = make_runner.call()
	runner.process_mode = Node.PROCESS_MODE_ALWAYS  # a system node (BRIEF 4.1)
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
	if template_registry != null:
		parent.remove_child(template_registry)
		template_registry.free()
	if isolate_user_dir:
		Paths.set_override(saved_override)
		remove_tree(temp_dir)
	return code


## `--game=_template`: the template is never listed, so the GameRegistry autoload can't run
## it; the run gets a private registry with the installed games plus the template (the way the
## conformance test loads it). Null for every other game (the autoload serves it).
func _template_registry(parent: Node) -> WlGameRegistry:
	if str(parsed.get("game", "")) != WlGameRegistry.TEMPLATE_ID or parsed.has("registry"):
		return null
	var reg := WlGameRegistry.new()
	reg.scan_on_ready = false
	parent.add_child(reg)
	reg.scan()
	var err := reg.add_game(reg.template_manifest(), WlGameRegistry.GAMES_ROOT.path_join(WlGameRegistry.TEMPLATE_ID), true)
	if err != "":
		_fail("run_game_sim: src/games/_template/game.json: %s" % err)
	parsed["registry"] = reg
	return reg


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
	problems.append_array(_check_slots(flags))
	return problems


## Slot counts across flags: --players plus --bots, and the --rider, --ftp, --autopilot,
## --haptics-off and --player-options lists against them (only for values that passed their own check).
func _check_slots(flags: Array) -> Array[String]:
	var problems: Array[String] = []
	var players := _int_flag(flags, "players", 1)
	var bots := _int_flag(flags, "bots", 0)
	if players + bots > Wl.MAX_SLOTS:
		problems.append("--players plus --bots is %d: a session has at most %d slots" % [players + bots, Wl.MAX_SLOTS])
	var riders := _count(flags, "rider")
	if riders > 1 and riders != players:
		problems.append("--rider given %d times for %d human slots: give it once, or once per slot" % [riders, players])
	for key: String in ["autopilot", "haptics-off"]:
		var v: Variant = _value(flags, key)
		if v == null or str(v) in ["all", "none"] or _check_value(key, str(v)) != "":
			continue
		for s in str(v).split(","):
			if int(s.strip_edges()) >= players:
				problems.append("--%s=%s: slot %d is not a human slot (0..%d)" % [key, v, int(s.strip_edges()), players - 1])
	var ftp: Variant = _value(flags, "ftp")
	if ftp != null and _check_value("ftp", str(ftp)) == "" and str(ftp).split(",").size() > players + bots:
		problems.append("--ftp=%s: %d values for %d slots (give one, or one per slot)" % [ftp, str(ftp).split(",").size(), players + bots])
	var po: Variant = _value(flags, "player-options")
	if po != null and _check_value("player-options", str(po)) == "" and (parse_json(str(po)) as Array).size() > players:
		problems.append("--player-options: %d objects for %d human slots" % [(parse_json(str(po)) as Array).size(), players])
	return problems


## The int value of `key`, or `default` when it is missing or not an int.
func _int_flag(flags: Array, key: String, default: int) -> int:
	var v := str(_value(flags, key))
	return int(v) if v.is_valid_int() else default


## Deletes what an earlier run left at `report`: the report file and its FIT files
## (<report dir>/fit/<report stem>_slot<n>.fit), so a run that fails can't leave stale results for
## a checker to read. Returns the removed paths.
static func clear_report(report: String) -> Array[String]:
	var removed: Array[String] = []
	if report == "":
		return removed
	if FileAccess.file_exists(report) and DirAccess.remove_absolute(report) == OK:
		removed.append(report)
	var fit_dir := report.get_base_dir().path_join("fit")
	var prefix := report.get_file().get_basename() + "_slot"
	if not DirAccess.dir_exists_absolute(fit_dir):
		return removed
	for f in DirAccess.get_files_at(fit_dir):
		var n := f.trim_prefix(prefix).trim_suffix(".fit")
		if f.begins_with(prefix) and f.ends_with(".fit") and n.is_valid_int() and DirAccess.remove_absolute(fit_dir.path_join(f)) == OK:
			removed.append(fit_dir.path_join(f))
	return removed


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
