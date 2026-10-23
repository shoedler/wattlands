extends GutTest
## Brief 4 static tests, lexer-based (comments and string contents are cut out first, so a doc
## comment that mentions "Time." or a toast key never trips them). They extend the lead's
## test_siege_package.gd scans instead of repeating them:
##   - the trainer names are looked for in code AND as exact string literals (how a dynamic call
##     names a method), in every .gd, .tscn and .tres under src/games/siege/;
##   - the determinism scan covers everything that runs on the host inside the sim step: rules/,
##     combat/, autopilot/, contracts/ and net/ (clock, global RNG, `shuffle()` and
##     `pick_random()`, which draw from the global RNG), and the module file for global RNG;
##   - the pure folders touch no scene tree, Input, Engine, file API, view, HUD or module class;
##   - the scanner itself is proven on bad snippets, so a green run cannot be a dead regex.

const GAME_DIR := "res://src/games/siege"
## Brief 4: nothing in src/games/siege/ references these (GAME_SDK 21 adds the rest of the stack).
const TRAINER_NAMES: Array[String] = [
	"TrainerController",
	"SafetyGovernor",
	"FtmsClient",
	"write_control",
	"set_target_power",
	"set_simulation",
	"set_resistance",
	"write_characteristic",
	"request_stop",
	"TrainerService",
	"LocalRider",
	"GameHost",
	"MockTrainer",
	"TrainerDevice",
	"FtmsTrainer",
	"DirectiveRouter",
	"HudRouter",
	"governor_profile",
]
## Folders that run inside SiegeRules.step or feed it on the host.
const HOST_DIRS: Array[String] = ["rules", "combat", "autopilot", "contracts", "net"]
## Folders that must stay free of the scene tree and the outside world.
const PURE_DIRS: Array[String] = ["rules", "combat", "autopilot", "net"]
const CLOCKS := (
	"\\bTime\\b|\\bOS\\s*\\.\\s*(get_ticks|get_unix_time|get_system_time|delay_)"
	+ "|\\bEngine\\s*\\.\\s*get_(frames|process_frames|physics_frames)"
)
const GLOBAL_RNG := (
	"(?<![\\w.])(randi|randf|randi_range|randf_range|randfn|randomize|rand_from_seed|seed)\\s*\\("
	+ "|RandomNumberGenerator\\s*\\.\\s*new\\s*\\(|\\.\\s*(shuffle|pick_random)\\s*\\("
)
const WORLD := (
	"\\bget_tree\\s*\\(|\\bget_node\\s*\\(|\\bget_node_or_null\\s*\\(|\\bEngine\\s*\\.|\\bInput\\s*\\."
	+ "|\\bDisplayServer\\b|\\bFileAccess\\b|\\bDirAccess\\b|\\bOS\\s*\\.|\\bResourceLoader\\b"
	+ "|\\bSiegeView\\b|\\bSiegeHud\\b|\\bSiegeGame\\b"
)


## {"code": the text with comments removed and every string reduced to its quotes,
## "strings": the contents of every string literal}.
static func lex(text: String) -> Dictionary:
	var code := PackedStringArray()
	var strings: Array[String] = []
	var n := text.length()
	var i := 0
	while i < n:
		var c := text[i]
		if c == "#":
			while i < n and text[i] != "\n":
				i += 1
			continue
		if c == '"' or c == "'":
			var triple := text.substr(i, 3) == c.repeat(3)
			var close := c.repeat(3) if triple else c
			var raw := i > 0 and text[i - 1] == "r"
			i += 3 if triple else 1
			var start := i
			while i < n:
				if text[i] == "\\" and not raw:
					i += 2
					continue
				if text.substr(i, close.length()) == close:
					break
				if text[i] == "\n" and not triple:
					break
				i += 1
			strings.append(text.substr(start, i - start))
			code.append('""')
			i += close.length()
			continue
		code.append(c)
		i += 1
	return {"code": "".join(code), "strings": strings}


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


# --- the scanner itself ------------------------------------------------------------------------------


func test_lexer_drops_comments_and_string_contents_but_keeps_code() -> void:
	var src := 'var a := 1 # Time.get_ticks_msec()\nvar s := "set_target_power #x"\nrandi()\n'
	var lexed := lex(src)
	var code: String = lexed["code"]
	assert_false(code.contains("Time"), "comment cut")
	assert_false(code.contains("set_target_power"), "string content cut")
	assert_true(code.contains("randi()"), "code kept")
	assert_eq(lexed["strings"], ["set_target_power #x"])
	var triple := lex('var d := """Time.now\n# still text"""\nvar e := 2')
	assert_false((triple["code"] as String).contains("Time"))
	assert_true((triple["code"] as String).contains("var e := 2"))
	var esc := lex('var q := "a \\" Time. b"\nrandf()')
	assert_false((esc["code"] as String).contains("Time"), "an escaped quote does not end it")
	assert_true((esc["code"] as String).contains("randf()"))


func test_the_determinism_scan_catches_every_forbidden_form() -> void:
	var bad := [
		"var t := Time.get_ticks_msec()",
		"var t := OS.get_ticks_usec()",
		"var t := OS.get_unix_time()",
		"var r := RandomNumberGenerator.new()",
		"var r := randi() % 6",
		"var r := randf_range(0.0, 1.0)",
		"randomize()",
		"arr.shuffle()",
		"var x = arr.pick_random()",
		"var f := Engine.get_frames_drawn()",
	]
	for line: String in bad:
		var code: String = lex(line)["code"]
		assert_ne(hit(code, CLOCKS) + hit(code, GLOBAL_RNG), "", line)
	var fine := [
		"var r := state.rng.randf()",
		"var r := ctx.rng.randi_range(1, 3)",
		"var v := rng.randf_range(a, b)",
		"var t := state.t",
		"# Time.get_ticks_msec() in a comment",
		'var k := "Time.now"',
		"var d := runtime_randi_like(3)",
		"var s := state.seed_value",
	]
	for line: String in fine:
		var code: String = lex(line)["code"]
		assert_eq(hit(code, CLOCKS) + hit(code, GLOBAL_RNG), "", line)


func test_the_trainer_scan_catches_names_in_code_and_as_exact_strings() -> void:
	var lexed := lex('governor.set_target_power(100)\ncall("write_control", 1)\n# FtmsClient\n"x"')
	assert_eq(first_name(lexed["code"], TRAINER_NAMES), "set_target_power")
	assert_true((lexed["strings"] as Array).has("write_control"))
	var clean := lex('# TrainerController is not allowed here\nvar s := "SafetyGovernor"')
	assert_eq(first_name(clean["code"], TRAINER_NAMES), "")
	assert_eq(first_name("var set_target_power_w := 1", TRAINER_NAMES), "", "whole identifiers")


func test_the_world_scan_catches_tree_input_and_view_references() -> void:
	for line: String in [
		"var n := get_tree()",
		"var n := get_node(p)",
		"Input.is_action_pressed(a)",
		"var f := FileAccess.open(p, 1)",
		"var v: SiegeView = null",
		"Engine.time_scale = 2.0",
	]:
		assert_ne(hit(line, WORLD), "", line)
	assert_eq(hit("var e := SiegeEnemyState.new()", WORLD), "")


# --- the scans ---------------------------------------------------------------------------------------


func test_siege_never_names_the_trainer_stack_in_code_or_strings() -> void:
	var scanned := 0
	for path in files(GAME_DIR, ["gd"]):
		scanned += 1
		var lexed := lex(read(path))
		var found := first_name(lexed["code"], TRAINER_NAMES)
		assert_eq(found, "", "%s names %s" % [path, found])
		for s: String in lexed["strings"]:
			assert_false(TRAINER_NAMES.has(s.strip_edges()), "%s: string %s" % [path, s])
			for frag: String in [
				"local_rider", "safety_governor", "trainer_controller", "addons/wattlands/trainer/"
			]:
				assert_false(s.contains(frag), "%s: string %s" % [path, s])
	assert_gte(scanned, 25, "every Siege script is scanned")


func test_siege_scenes_and_resources_never_name_the_trainer_stack() -> void:
	var count := 0
	for path in files(GAME_DIR, ["tscn", "tres"]):
		count += 1
		var text := read(path)
		for name in TRAINER_NAMES:
			assert_false(text.contains(name), "%s mentions %s" % [path, name])
		assert_false(text.contains("addons/wattlands/trainer/"), path)
	assert_true(count >= 0, "%d scene/resource files scanned" % count)


func test_the_only_ctx_directives_call_is_request() -> void:
	var re := RegEx.create_from_string("directives\\s*\\.\\s*(\\w+)")
	var seen := {}
	for path in files(GAME_DIR, ["gd"]):
		for m in re.search_all(lex(read(path))["code"]):
			seen[m.get_string(1)] = path
	assert_eq(seen.keys(), ["request"], str(seen))


func test_host_code_uses_no_wall_clock_and_no_global_randomness() -> void:
	var scanned := 0
	for dir in HOST_DIRS:
		for path in files(GAME_DIR.path_join(dir), ["gd"]):
			scanned += 1
			var code: String = lex(read(path))["code"]
			assert_eq(hit(code, CLOCKS), "", "%s reads a clock" % path)
			assert_eq(hit(code, GLOBAL_RNG), "", "%s uses global randomness" % path)
	assert_gte(scanned, 25, "rules, combat, autopilot, contracts and net are all scanned")


func test_the_module_uses_no_global_randomness() -> void:
	var path := GAME_DIR.path_join("siege_game.gd")
	assert_eq(hit(lex(read(path))["code"], GLOBAL_RNG), "", path)


func test_every_random_draw_in_the_rules_goes_through_an_rng_object() -> void:
	var draw := RegEx.create_from_string(
		"([\\w.]+)\\s*\\.\\s*(randi|randf|randi_range|randf_range|randfn)\\s*\\("
	)
	var seen := 0
	for dir in ["rules", "combat", "autopilot"]:
		for path in files(GAME_DIR.path_join(dir), ["gd"]):
			for m in draw.search_all(lex(read(path))["code"]):
				seen += 1
				var recv := m.get_string(1)
				assert_true(recv.ends_with("rng"), "%s: %s.%s" % [path, recv, m.get_string(2)])
	assert_true(seen >= 0, "%d draws checked" % seen)


func test_pure_folders_touch_no_scene_tree_input_engine_files_or_presentation() -> void:
	for dir in PURE_DIRS:
		for path in files(GAME_DIR.path_join(dir), ["gd"]):
			var found := hit(lex(read(path))["code"], WORLD)
			assert_eq(found, "", "%s: %s" % [path, found])


func test_rules_and_combat_scripts_are_plain_data_classes() -> void:
	var ext := RegEx.create_from_string("(?m)^extends\\s+(\\w+)")
	var scanned := 0
	for dir in ["rules", "combat"]:
		for path in files(GAME_DIR.path_join(dir), ["gd"]):
			scanned += 1
			var m := ext.search(lex(read(path))["code"])
			assert_not_null(m, "%s has no extends line" % path)
			if m != null:
				assert_true(
					["RefCounted", "Resource"].has(m.get_string(1)),
					"%s extends %s" % [path, m.get_string(1)]
				)
	assert_gte(scanned, 4)
