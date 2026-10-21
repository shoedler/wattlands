class_name CmdLine
extends RefCounted
## Command-line flags after `--`, read with OS.get_cmdline_user_args() (BRIEF 6):
## --mock-trainer=<profile>, --autopilot, --host, --join=<code>, --relay=<url>,
## --game=<id>, --content=<id>, --seed=<n>, --sim-speed=<x>, --run-seconds=<n>,
## --report=<path>, --screenshot-dir=<dir>, --profile-dir=<abs path>, --strava-base=<url>.
## Tools add their own flags (run_game_sim, screenshot, pixelate); all parse the same way:
## "--key=value", "--key value" is NOT supported, a bare "--flag" means true. A repeated
## flag keeps every value (see get_all).

static var _parsed: Dictionary = {}
static var _ready: bool = false
static var _override_args: PackedStringArray = PackedStringArray()
static var _use_override: bool = false


## Parse `args` instead of the process arguments (tests and tools). Pass an empty array
## with use = false to go back to the real arguments.
static func set_args(args: PackedStringArray, use: bool = true) -> void:
	_override_args = args
	_use_override = use
	_ready = false


static func args() -> PackedStringArray:
	return _override_args if _use_override else OS.get_cmdline_user_args()


static func has(key: String) -> bool:
	_parse()
	return _parsed.has(key)


## Last value of --key=value, or `default`.
static func get_str(key: String, default: String = "") -> String:
	_parse()
	if not _parsed.has(key):
		return default
	var vals: Array = _parsed[key]
	return str(vals[vals.size() - 1])


static func get_int(key: String, default: int = 0) -> int:
	var s := get_str(key, "")
	return int(s) if s.is_valid_int() else default


static func get_float(key: String, default: float = 0.0) -> float:
	var s := get_str(key, "")
	return float(s) if s.is_valid_float() else default


static func get_bool(key: String, default: bool = false) -> bool:
	if not has(key):
		return default
	var s := get_str(key, "true").to_lower()
	return not (s == "false" or s == "0" or s == "no" or s == "off")


## Every value given for a repeated flag, in order.
static func get_all(key: String) -> Array[String]:
	_parse()
	var out: Array[String] = []
	for v: Variant in _parsed.get(key, []):
		out.append(str(v))
	return out


## Parses a list of "--key=value" strings into {key: [values]} (bare flags -> "true").
static func parse(list: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for a in list:
		if not a.begins_with("--"):
			continue
		var body := a.substr(2)
		var key := body
		var val := "true"
		var eq := body.find("=")
		if eq >= 0:
			key = body.substr(0, eq)
			val = body.substr(eq + 1)
		if not out.has(key):
			out[key] = []
		(out[key] as Array).append(val)
	return out


static func _parse() -> void:
	if _ready:
		return
	_parsed = parse(args())
	_ready = true
