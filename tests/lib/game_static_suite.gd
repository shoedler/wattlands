class_name TestGameStaticSuite
extends TestGameSuite
## What a game's static suite shares: the names and patterns its scans look for, and the proof that
## the lexer and the determinism patterns catch what they should, so a green run cannot be a dead
## regex. Each game's suite calls the proofs from its own tests and runs its own scans on its own
## folders: these scans are the games' no-trainer-bypass check.

## Brief 4: nothing under a game's folder references these (GAME_SDK 21 adds the rest of the stack).
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
const CLOCKS := (
	"\\bTime\\b|\\bOS\\s*\\.\\s*(get_ticks|get_unix_time|get_system_time|delay_)"
	+ "|\\bEngine\\s*\\.\\s*get_(frames|process_frames|physics_frames)"
)
const GLOBAL_RNG := (
	"(?<![\\w.])(randi|randf|randi_range|randf_range|randfn|randomize|rand_from_seed|seed)\\s*\\("
	+ "|RandomNumberGenerator\\s*\\.\\s*new\\s*\\(|\\.\\s*(shuffle|pick_random)\\s*\\("
)


## TestGdLex cuts comments and string contents and keeps the code.
func check_lexer() -> void:
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


## CLOCKS and GLOBAL_RNG catch every forbidden form and leave an rng object, comments and strings be.
func check_determinism_scan() -> void:
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
