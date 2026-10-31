extends TestGameStaticSuite
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
## Folders that run inside SiegeRules.step or feed it on the host.
const HOST_DIRS: Array[String] = ["rules", "combat", "autopilot", "contracts", "net"]
## Folders that must stay free of the scene tree and the outside world.
const PURE_DIRS: Array[String] = ["rules", "combat", "autopilot", "net"]
const WORLD := (
	"\\bget_tree\\s*\\(|\\bget_node\\s*\\(|\\bget_node_or_null\\s*\\(|\\bEngine\\s*\\.|\\bInput\\s*\\."
	+ "|\\bDisplayServer\\b|\\bFileAccess\\b|\\bDirAccess\\b|\\bOS\\s*\\.|\\bResourceLoader\\b"
	+ "|\\bSiegeView\\b|\\bSiegeHud\\b|\\bSiegeGame\\b"
)

# --- the scanner itself ------------------------------------------------------------------------------


func test_lexer_drops_comments_and_string_contents_but_keeps_code() -> void:
	check_lexer()


func test_the_determinism_scan_catches_every_forbidden_form() -> void:
	check_determinism_scan()


func test_the_trainer_scan_catches_names_in_code_and_as_exact_strings() -> void:
	var lexed := TestGdLex.lex(
		'governor.set_target_power(100)\ncall("write_control", 1)\n# FtmsClient\n"x"'
	)
	assert_eq(first_name(lexed["code"], TRAINER_NAMES), "set_target_power")
	assert_true((lexed["strings"] as Array).has("write_control"))
	var clean := TestGdLex.lex('# TrainerController is not allowed here\nvar s := "SafetyGovernor"')
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
		var lexed := TestGdLex.lex(read(path))
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


func test_the_only_ctx_directives_calls_are_request_and_the_cadence_band() -> void:
	var re := RegEx.create_from_string("directives\\s*\\.\\s*(\\w+)")
	var seen := {}
	for path in files(GAME_DIR, ["gd"]):
		for m in re.search_all(TestGdLex.lex(read(path))["code"]):
			seen[m.get_string(1)] = path
	var calls: Array = seen.keys()
	calls.sort()
	assert_eq(calls, ["cadence_band", "request"], str(seen))


func test_host_code_uses_no_wall_clock_and_no_global_randomness() -> void:
	var scanned := 0
	for dir in HOST_DIRS:
		for path in files(GAME_DIR.path_join(dir), ["gd"]):
			scanned += 1
			var code: String = TestGdLex.lex(read(path))["code"]
			assert_eq(hit(code, CLOCKS), "", "%s reads a clock" % path)
			assert_eq(hit(code, GLOBAL_RNG), "", "%s uses global randomness" % path)
	assert_gte(scanned, 25, "rules, combat, autopilot, contracts and net are all scanned")


func test_the_module_uses_no_global_randomness() -> void:
	var path := GAME_DIR.path_join("siege_game.gd")
	assert_eq(hit(TestGdLex.lex(read(path))["code"], GLOBAL_RNG), "", path)


func test_every_random_draw_in_the_rules_goes_through_an_rng_object() -> void:
	var draw := RegEx.create_from_string(
		"([\\w.]+)\\s*\\.\\s*(randi|randf|randi_range|randf_range|randfn)\\s*\\("
	)
	var seen := 0
	for dir in ["rules", "combat", "autopilot"]:
		for path in files(GAME_DIR.path_join(dir), ["gd"]):
			for m in draw.search_all(TestGdLex.lex(read(path))["code"]):
				seen += 1
				var recv := m.get_string(1)
				assert_true(recv.ends_with("rng"), "%s: %s.%s" % [path, recv, m.get_string(2)])
	assert_true(seen >= 0, "%d draws checked" % seen)


func test_pure_folders_touch_no_scene_tree_input_engine_files_or_presentation() -> void:
	for dir in PURE_DIRS:
		for path in files(GAME_DIR.path_join(dir), ["gd"]):
			var found := hit(TestGdLex.lex(read(path))["code"], WORLD)
			assert_eq(found, "", "%s: %s" % [path, found])


func test_rules_and_combat_scripts_are_plain_data_classes() -> void:
	var ext := RegEx.create_from_string("(?m)^extends\\s+(\\w+)")
	var scanned := 0
	for dir in ["rules", "combat"]:
		for path in files(GAME_DIR.path_join(dir), ["gd"]):
			scanned += 1
			var m := ext.search(TestGdLex.lex(read(path))["code"])
			assert_not_null(m, "%s has no extends line" % path)
			if m != null:
				assert_true(
					["RefCounted", "Resource"].has(m.get_string(1)),
					"%s extends %s" % [path, m.get_string(1)]
				)
	assert_gte(scanned, 4)
