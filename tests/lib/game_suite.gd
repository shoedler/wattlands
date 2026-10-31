class_name TestGameSuite
extends GutTest
## What a game's package and static suites share: walking and reading its files, and the manifest
## checks every game keeps. A suite extends this and keeps its own test functions, so each game's
## scans stay its own and name its own folders.

## The fields every game.json holds (BRIEF 3.6).
const REQUIRED_FIELDS := [
	"id",
	"title",
	"summary",
	"version",
	"min_players",
	"max_players",
	"bots",
	"presentation",
	"entry",
	"contents",
	"default_content",
	"e2e_content",
	"zero_input_content"
]
## Names only the platform's trainer stack may use (BRIEF 4.6.11, tests/arch/test_no_bypass.gd).
const CORE_TRAINER_NAMES := [
	"TrainerController",
	"SafetyGovernor",
	"FtmsClient",
	"write_control",
	"set_target_power",
	"set_simulation",
	"set_resistance",
	"write_characteristic"
]


## Every file under `dir` with one of the extensions `exts` (empty when `dir` does not exist).
static func files(dir: String, exts: Array) -> Array[String]:
	var out: Array[String] = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f in da.get_files():
		if exts.has(f.get_extension()):
			out.append(dir.path_join(f))
	for sub in da.get_directories():
		out.append_array(files(dir.path_join(sub), exts))
	return out


static func read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## The first name of `names` that `code` holds as a whole identifier, or "".
static func first_name(code: String, names: Array[String]) -> String:
	for name in names:
		var re := RegEx.create_from_string("(?<![A-Za-z0-9_])" + name + "(?![A-Za-z0-9_])")
		if re.search(code) != null:
			return name
	return ""


## What `pattern` finds in `code` ("" when nothing).
static func hit(code: String, pattern: String) -> String:
	var m := RegEx.create_from_string(pattern).search(code)
	return m.get_string() if m != null else ""


## The keys of the strings.csv in `content_dir`, checking its header.
func csv_keys(content_dir: String) -> Array[String]:
	var keys: Array[String] = []
	var f := FileAccess.open(content_dir.path_join("strings.csv"), FileAccess.READ)
	assert_eq(f.get_csv_line(), PackedStringArray(["keys", "en"]), "strings.csv header")
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 2 and row[0] != "":
			keys.append(row[0])
	return keys


## Every entry of the manifest's `options` and `player_options` uses the SDK's entry format.
func check_option_entries(manifest: Dictionary) -> void:
	var entries: Array = manifest.get("options", []) + manifest.get("player_options", [])
	assert_gt(entries.size(), 0)
	for e: Dictionary in entries:
		assert_has(["toggle", "int", "choice"], e["type"], str(e))
		match e["type"]:
			"toggle":
				assert_typeof(e["default"], TYPE_BOOL, str(e))
			"int":
				var step := float(e.get("step", 1))
				assert_between(float(e["default"]), float(e["min"]), float(e["max"]), str(e))
				assert_eq(
					fmod(float(e["default"]) - float(e["min"]), step),
					0.0,
					"default on the step grid: %s" % e
				)
			"choice":
				var values: Array = (e["choices"] as Array).map(
					func(c: Dictionary) -> Variant: return c["value"]
				)
				assert_has(values, e["default"], str(e))
