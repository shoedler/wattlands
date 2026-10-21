extends GutTest
## CmdLine (BRIEF 6): "--key=value" flags after "--", bare flags as true, repeated flags,
## typed getters with defaults, and the test override.


func after_each() -> void:
	CmdLine.set_args(PackedStringArray(), false)


func _use(list: Array) -> void:
	CmdLine.set_args(PackedStringArray(list))


func test_key_value_flags() -> void:
	_use(["--game=siege", "--seed=42", "--relay=ws://localhost:8787/v1?a=b"])
	assert_true(CmdLine.has("game"))
	assert_eq(CmdLine.get_str("game"), "siege")
	assert_eq(CmdLine.get_str("relay"), "ws://localhost:8787/v1?a=b", "only the first = splits")
	assert_eq(CmdLine.get_int("seed"), 42)


func test_bare_flags_are_true() -> void:
	_use(["--autopilot", "--host"])
	assert_true(CmdLine.has("autopilot"))
	assert_eq(CmdLine.get_str("autopilot"), "true")
	assert_true(CmdLine.get_bool("autopilot"))
	assert_true(CmdLine.get_bool("host"))


func test_missing_flags_use_defaults() -> void:
	_use(["--seed=1"])
	assert_false(CmdLine.has("game"))
	assert_eq(CmdLine.get_str("game"), "")
	assert_eq(CmdLine.get_str("game", "workout"), "workout")
	assert_eq(CmdLine.get_int("players", 3), 3)
	assert_eq(CmdLine.get_float("sim-speed", 1.5), 1.5)
	assert_false(CmdLine.get_bool("autopilot"))
	assert_true(CmdLine.get_bool("autopilot", true))
	assert_eq(CmdLine.get_all("tag").size(), 0)


func test_repeated_flags_keep_every_value() -> void:
	_use(["--override=a.json", "--seed=1", "--override=b.json", "--override=c.json"])
	assert_eq(CmdLine.get_all("override"), ["a.json", "b.json", "c.json"])
	assert_eq(CmdLine.get_str("override"), "c.json", "get_str returns the last value")
	_use(["--seed=1", "--seed=2"])
	assert_eq(CmdLine.get_int("seed"), 2)


func test_get_int() -> void:
	_use(["--seed=42", "--neg=-7", "--bad=4x", "--float=2.5", "--empty="])
	assert_eq(CmdLine.get_int("seed"), 42)
	assert_eq(CmdLine.get_int("neg"), -7)
	assert_eq(CmdLine.get_int("bad", 9), 9, "not an int: default")
	assert_eq(CmdLine.get_int("float", 9), 9, "not an int: default")
	assert_eq(CmdLine.get_int("empty", 9), 9)
	assert_eq(CmdLine.get_int("missing"), 0)


func test_get_float() -> void:
	_use(["--sim-speed=2.5", "--seed=10", "--bad=fast"])
	assert_eq(CmdLine.get_float("sim-speed"), 2.5)
	assert_eq(CmdLine.get_float("seed"), 10.0)
	assert_eq(CmdLine.get_float("bad", 1.0), 1.0)
	assert_eq(CmdLine.get_float("missing"), 0.0)


func test_get_bool() -> void:
	_use(["--a=true", "--b=false", "--c=0", "--d=no", "--e=off", "--f=1", "--g=yes", "--h=FALSE"])
	assert_true(CmdLine.get_bool("a"))
	assert_false(CmdLine.get_bool("b"))
	assert_false(CmdLine.get_bool("c"))
	assert_false(CmdLine.get_bool("d"))
	assert_false(CmdLine.get_bool("e"))
	assert_true(CmdLine.get_bool("f"))
	assert_true(CmdLine.get_bool("g"))
	assert_false(CmdLine.get_bool("h"), "case-insensitive")
	assert_false(CmdLine.get_bool("b", true), "a present flag ignores the default")


func test_non_flag_arguments_are_ignored() -> void:
	_use(["positional", "-x", "--seed=3", "+plus"])
	assert_false(CmdLine.has("positional"))
	assert_false(CmdLine.has("x"))
	assert_false(CmdLine.has("-x"))
	assert_eq(CmdLine.get_int("seed"), 3)


func test_parse_is_pure() -> void:
	var parsed := CmdLine.parse(PackedStringArray(["--a=1", "--b", "--a=2", "c"]))
	assert_eq(parsed, {"a": ["1", "2"], "b": ["true"]})


func test_set_args_reparses() -> void:
	_use(["--game=siege"])
	assert_eq(CmdLine.get_str("game"), "siege")
	_use(["--game=tank"])
	assert_eq(CmdLine.get_str("game"), "tank")


func test_reset_returns_to_the_process_arguments() -> void:
	_use(["--game=siege"])
	CmdLine.set_args(PackedStringArray(), false)
	assert_eq(CmdLine.args(), OS.get_cmdline_user_args())
	assert_eq(CmdLine.has("game"), OS.get_cmdline_user_args().has("--game=siege"))


func test_override_with_empty_list_hides_process_arguments() -> void:
	CmdLine.set_args(PackedStringArray(), true)
	assert_eq(CmdLine.args().size(), 0)
	assert_false(CmdLine.has("profile-dir"))
