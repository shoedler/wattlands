extends GutTest
## Brief 4 static tests for Diesel Domestiques, lexer-based (comments are cut out and string
## contents reduced to quotes first, so a doc comment that mentions "Time." or a toast key never
## trips them). They extend the lead's test_tank_package.gd scans instead of repeating them:
##   - nothing under src/games/tank names the trainer stack, in code or as an exact string, in any
##     .gd, .tscn or .tres (TrainerController, SafetyGovernor, FtmsClient, write_control,
##     set_target_power, set_simulation, set_resistance and the rest of GAME_SDK 21's list);
##   - rules/, effort/ and combat/ (and the other host-side folders) use no clock, no global RNG,
##     no RandomNumberGenerator.new() and draw only from an rng object;
##   - ctx.directives is used only by the effort director, and only for the five calls Tank makes
##     (request, course_grade, cadence_band, end_phase and, v3, replan for a seat switch);
##   - the scanner itself is proven on bad snippets, so a green run cannot be a dead regex.

const GAME_DIR := "res://src/games/tank"
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
## Folders the brief names for the determinism rule, and the rest of what runs on the host.
const BRIEF_DIRS: Array[String] = ["rules", "effort", "combat"]
const HOST_DIRS: Array[String] = [
	"rules", "effort", "combat", "autopilot", "contracts", "net", "content"
]
## Folders that must stay free of the scene tree, input and presentation.
const PURE_DIRS: Array[String] = ["rules", "combat"]
## The ctx.directives calls Tank makes (brief 2.3: requests, course grade, cadence band, end_phase;
## v3: replan, each seat switch; 0.3.1: split, the trainer following a seat at once).
const DIRECTIVE_CALLS: Array[String] = [
	"request", "course_grade", "cadence_band", "end_phase", "replan", "split"
]
## v4: what no effort code may name (SPEC_TANK 3.5, lead's ruling 2).
const DIFFICULTY := (
	"TankDifficulty|DIFF_(AUTO|EASY|NORMAL|HARD)|\\.difficulty\\b"
	+ "|[\"']difficulty\\b|\\boptions\\s*(\\[|\\.\\s*get\\s*\\()"
)
## The folders whose choices become plans, directives or seat moves. effort/ holds TankSeatPlan too.
const NO_DIFFICULTY_DIRS: Array[String] = ["effort", "autopilot"]
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
	+ "|\\bTankView\\b|\\bTankHud\\b|\\bTankGame\\b|\\bTankAudio\\b"
)


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
	var lexed := TestGdLex.lex(src)
	var code: String = lexed["code"]
	assert_false(code.contains("Time"), "comment cut")
	assert_false(code.contains("set_target_power"), "string content cut")
	assert_true(code.contains("randi()"), "code kept")
	assert_eq(lexed["strings"], ["set_target_power #x"])
	var triple := TestGdLex.lex('var d := """Time.now\n# still text"""\nvar e := 2')
	assert_false((triple["code"] as String).contains("Time"))
	assert_true((triple["code"] as String).contains("var e := 2"))
	var esc := TestGdLex.lex('var q := "a \\" Time. b"\nrandf()')
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
		var code: String = TestGdLex.lex(line)["code"]
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
		var code: String = TestGdLex.lex(line)["code"]
		assert_eq(hit(code, CLOCKS) + hit(code, GLOBAL_RNG), "", line)


func test_the_trainer_scan_catches_names_in_code_and_as_exact_strings() -> void:
	var lexed := TestGdLex.lex(
		'governor.set_target_power(100)\ncall("write_control", 1)\n# FtmsClient\n"x"'
	)
	assert_eq(first_name(lexed["code"], TRAINER_NAMES), "set_target_power")
	assert_true((lexed["strings"] as Array).has("write_control"))
	var clean := TestGdLex.lex('# TrainerController is not allowed here\nvar s := "SafetyGovernor"')
	assert_eq(first_name(clean["code"], TRAINER_NAMES), "")
	assert_eq(first_name("var set_target_power_w := 1", TRAINER_NAMES), "", "whole identifiers")
	for n: String in [
		"TrainerController", "SafetyGovernor", "FtmsClient", "set_simulation", "set_resistance"
	]:
		assert_ne(first_name("x.%s(1)" % n, TRAINER_NAMES), "", n)


func test_the_world_scan_catches_tree_input_and_view_references() -> void:
	for line: String in [
		"var n := get_tree()",
		"var n := get_node(p)",
		"Input.is_action_pressed(a)",
		"var f := FileAccess.open(p, 1)",
		"var v: TankView = null",
		"Engine.time_scale = 2.0",
	]:
		assert_ne(hit(line, WORLD), "", line)
	assert_eq(hit("var e := TankEnemyState.new()", WORLD), "")


func test_the_directives_scan_finds_member_calls() -> void:
	var re := RegEx.create_from_string("directives\\s*\\.\\s*(\\w+)")
	var src := TestGdLex.lex(
		"ctx.directives.request(p, d)\nctx.directives . end_phase(p)\n# directives.replan()\n"
	)
	var seen: Array[String] = []
	for m in re.search_all(src["code"]):
		seen.append(m.get_string(1))
	assert_eq(seen, ["request", "end_phase"])


# --- the scans ---------------------------------------------------------------------------------------


func test_tank_never_names_the_trainer_stack_in_code_or_strings() -> void:
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
	assert_gte(scanned, 30, "every Tank script is scanned")


func test_tank_scenes_and_resources_never_name_the_trainer_stack() -> void:
	for path in files(GAME_DIR, ["tscn", "tres"]):
		var text := read(path)
		for name in TRAINER_NAMES:
			assert_false(text.contains(name), "%s mentions %s" % [path, name])
		assert_false(text.contains("addons/wattlands/trainer/"), path)
	assert_true(true)


func test_only_the_effort_director_uses_ctx_directives_and_only_the_four_calls() -> void:
	var re := RegEx.create_from_string("directives\\s*\\.\\s*(\\w+)")
	var any := RegEx.create_from_string("(?<![A-Za-z0-9_])directives(?![A-Za-z0-9_])")
	var seen := {}
	for path in files(GAME_DIR, ["gd"]):
		var code: String = TestGdLex.lex(read(path))["code"]
		var in_effort := path.begins_with(GAME_DIR + "/effort/")
		if not in_effort:
			assert_null(any.search(code), "%s uses `directives` outside effort/" % path)
		for m in re.search_all(code):
			seen[m.get_string(1)] = path
	for call: String in seen:
		assert_has(DIRECTIVE_CALLS, call, "Tank calls directives.%s (%s)" % [call, seen[call]])
	assert_eq(
		str(seen.get("replan", "")),
		GAME_DIR + "/effort/tank_director.gd",
		"v3: only the director replans (a seat switch)"
	)


func test_effort_rules_and_combat_use_no_wall_clock_and_no_global_randomness() -> void:
	var scanned := 0
	for dir in BRIEF_DIRS:
		for path in files(GAME_DIR.path_join(dir), ["gd"]):
			scanned += 1
			var code: String = TestGdLex.lex(read(path))["code"]
			assert_eq(hit(code, CLOCKS), "", "%s reads a clock" % path)
			assert_eq(hit(code, GLOBAL_RNG), "", "%s uses global randomness" % path)
	assert_gte(scanned, 2, "effort/ and rules/ (and combat/) are scanned")


func test_every_host_side_folder_is_deterministic_too() -> void:
	var scanned := 0
	for dir in HOST_DIRS:
		for path in files(GAME_DIR.path_join(dir), ["gd"]):
			scanned += 1
			var code: String = TestGdLex.lex(read(path))["code"]
			assert_eq(hit(code, CLOCKS), "", "%s reads a clock" % path)
			assert_eq(hit(code, GLOBAL_RNG), "", "%s uses global randomness" % path)
	assert_gte(scanned, 25, "contracts, rules, effort, combat, net, autopilot and content")
	var module := TestGdLex.lex(read(GAME_DIR.path_join("tank_game.gd")))["code"] as String
	assert_eq(hit(module, GLOBAL_RNG), "", "the module uses no global randomness")
	assert_eq(hit(module, CLOCKS), "", "the module reads no clock")


func test_every_random_draw_in_the_rules_goes_through_an_rng_object() -> void:
	var draw := RegEx.create_from_string(
		"([\\w.]+)\\s*\\.\\s*(randi|randf|randi_range|randf_range|randfn)\\s*\\("
	)
	for dir in ["rules", "combat", "effort", "autopilot"]:
		for path in files(GAME_DIR.path_join(dir), ["gd"]):
			for m in draw.search_all(TestGdLex.lex(read(path))["code"]):
				var recv := m.get_string(1)
				assert_true(recv.ends_with("rng"), "%s: %s.%s" % [path, recv, m.get_string(2)])
	assert_true(true)


func test_rules_and_combat_touch_no_scene_tree_input_engine_files_or_presentation() -> void:
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
	assert_gte(scanned, 2)


func test_class_names_are_unique_and_carry_the_tank_prefix() -> void:
	var re := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")
	var seen := {}
	for path in files(GAME_DIR, ["gd"]):
		var m := re.search(TestGdLex.lex(read(path))["code"])
		if m == null:
			continue
		var name := m.get_string(1)
		assert_true(name.begins_with("Tank"), "%s: %s starts with Tank" % [path, name])
		assert_false(
			seen.has(name), "%s is declared twice (%s, %s)" % [name, seen.get(name, ""), path]
		)
		seen[name] = path


func test_no_todo_implement_marker_is_left_in_the_game() -> void:
	for path in files(GAME_DIR, ["gd", "json", "md"]):
		assert_false(read(path).to_lower().contains("todo: implement"), path)


# --- v4: no effort code reads the difficulty (SPEC_TANK 3.5, lead's ruling 2) ------------------------


## On the raw text, comments and strings included, so nothing can hide; "before difficulty" in the
## director's boiler comment is the platform's SIM difficulty and is not matched.
func test_effort_code_never_reads_the_difficulty() -> void:
	var scanned := 0
	for dir in NO_DIFFICULTY_DIRS:
		for path in files(GAME_DIR.path_join(dir), ["gd"]):
			scanned += 1
			assert_eq(hit(read(path), DIFFICULTY), "", path)
	assert_gte(
		scanned, 5, "tank_director, tank_plan_builder, tank_seat_plan, tank_autopilot, tank_bots"
	)
	var seat_plan := read(GAME_DIR.path_join("effort/tank_seat_plan.gd"))
	assert_true(seat_plan.contains("class_name TankSeatPlan"), "the seat plan lives in effort/")


## v4: nothing comes from behind. `TankEnemyState.side` is only carried on the wire (E_SIDE, snapshot v5),
## always +1; no code may branch on it, and the rear and dug-in ids are gone.
func test_nothing_reads_an_enemys_side() -> void:
	for path in files(GAME_DIR, ["gd"]):
		if path.ends_with("net/tank_snapshot.gd"):
			continue
		assert_eq(hit(read(path), "\\.side\\b"), "", path)
	var ids: Dictionary = (TankIds as GDScript).get_script_constant_map()
	for gone: String in ["FROM_REAR", "ENEMY_DUGIN", "INTENT_TRAVERSE"]:
		assert_false(ids.has(gone), gone)


func test_the_difficulty_scan_catches_every_form() -> void:
	var bad := [
		'var m := TankDifficulty.mult(state, "damage")',
		"if state.difficulty == x:",
		"if s == TankIds.DIFF_HARD:",
		"if s == TankIds.DIFF_AUTO:",
		"if s == TankIds.DIFF_EASY:",
		"if s == TankIds.DIFF_NORMAL:",
		'var o: String = ctx.options["difficulty"]',
		'var o: String = ctx.options.get("mode", "")',
		'var row: Variant = content.value("enemies", "difficulty.hard", {})',
	]
	for line: String in bad:
		assert_ne(hit(line, DIFFICULTY), "", line)
	var fine := ["## the boiler's mode grade before difficulty: grade x pressure", "var d := 1"]
	for line: String in fine:
		assert_eq(hit(line, DIFFICULTY), "", line)
