extends GutTest
## SDK conformance (BRIEF 3.6, 7.3; docs/OWNERSHIP.md TL8, REG6, REG7). Runs SdkConformance
## for `_template` (loaded explicitly) and every game the GameRegistry finds under
## res://src/games, with no per-game code: a new game passes it without any change here.
## Each game logs "conformance: <id> ok" (or FAILED) so a log shows which games ran.
## It also asserts that every res://src/games/*/game.json other than _template validates,
## naming the failing field, so an invalid game cannot pass by being hidden.
## The last tests check the harness itself on fixture games under tests/fixtures/games/.

const FIXTURES := "res://tests/fixtures/games"

var _reg: WlGameRegistry = null
var _template_err: String = ""
var _has_template: bool = false


func before_all() -> void:
	_reg = WlGameRegistry.new()
	_reg.scan_on_ready = false
	_reg.scan(WlGameRegistry.GAMES_ROOT)
	var tm := _reg.template_manifest()
	_has_template = not tm.is_empty()
	if _has_template:
		_template_err = _reg.add_game(
			tm, WlGameRegistry.GAMES_ROOT.path_join(WlGameRegistry.TEMPLATE_ID), true
		)


func after_all() -> void:
	_reg.clear()
	_reg.free()


func _game_folders() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(WlGameRegistry.GAMES_ROOT)
	if dir == null:
		return out
	for sub in dir.get_directories():
		if sub.begins_with(".") or sub == WlGameRegistry.TEMPLATE_ID:
			continue
		var path := WlGameRegistry.GAMES_ROOT.path_join(sub).path_join("game.json")
		if FileAccess.file_exists(path):
			out.append(path)
	out.sort()
	return out


func _check(registry: WlGameRegistry, id: String) -> void:
	var log: Array = []
	var errors := SdkConformance.check_game(registry, id, {}, log)
	for line: Variant in log:
		print(line)
	print("conformance: %s %s" % [id, "ok" if errors.is_empty() else "FAILED"])
	assert_eq(errors, [] as Array[String], "conformance: %s" % id)


func test_every_game_json_validates_naming_the_failing_field() -> void:
	var paths := _game_folders()
	for path in paths:
		var err := SdkConformance.manifest_error(_reg, path)
		assert_eq(err, "", "%s: %s" % [path, err])
	if paths.is_empty():
		pass_test("no game under src/games yet")


func test_template_conforms() -> void:
	if not _has_template:
		pass_test("no src/games/_template yet (sdk-tools writes it in W1)")
		return
	assert_eq(_template_err, "", "_template/game.json: %s" % _template_err)
	if _template_err == "":
		_check(_reg, WlGameRegistry.TEMPLATE_ID)


func test_every_registered_game_conforms() -> void:
	var ids := _reg.ids()
	if ids.is_empty():
		pass_test("no registered game yet")
		return
	for id in ids:
		_check(_reg, id)


func test_game_strings_keep_their_prefix() -> void:
	var ids := _reg.ids()
	if _has_template and _template_err == "":
		ids.append(WlGameRegistry.TEMPLATE_ID)
	for id in ids:
		assert_eq(
			SdkConformance.strings_errors(id, _reg.content_dir(id).path_join("strings.csv")),
			[] as Array[String],
			id
		)
	if ids.is_empty():
		pass_test("no game strings yet")


# --- the harness on fixtures -----------------------------------------------------------


func test_harness_passes_a_conforming_fixture() -> void:
	var reg := WlGameRegistry.new()
	reg.scan_on_ready = false
	reg.content_root = FIXTURES.path_join("_content")
	reg.scan(FIXTURES.path_join("conform"))
	assert_eq(reg.ids(), ["fx_conform"] as Array[String])
	_check(reg, "fx_conform")
	reg.clear()
	reg.free()


func test_harness_catches_a_plan_that_breaks_the_rules() -> void:
	var reg := WlGameRegistry.new()
	reg.scan_on_ready = false
	reg.content_root = FIXTURES.path_join("_content")
	reg.scan(FIXTURES.path_join("runtime"))
	var m := reg.manifest("fx_solo")
	var errors: Array[String] = []
	for content: Variant in m["contents"]:
		var r := GameSimRunner.new()
		var err := r.setup(
			{"game": "fx_solo", "content": str(content), "registry": reg, "max_sim_seconds": 1.0}
		)
		if err != "":
			errors.append(err)
		r.cleanup()
		r.free()
	assert_eq(errors.size(), 1, 'only the "bad" content is rejected')
	assert_string_contains(errors[0], "warm-up")
	reg.clear()
	reg.free()


func test_harness_catches_unprefixed_strings() -> void:
	var errs := SdkConformance.strings_errors(
		"fx_crew", FIXTURES.path_join("_content/fx_crew/strings.csv")
	)
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "CREW_WRONG_PREFIX")
	assert_eq(
		SdkConformance.strings_errors(
			"fx_solo", FIXTURES.path_join("_content/fx_solo/strings.csv")
		),
		[] as Array[String]
	)
	assert_eq(
		SdkConformance.strings_errors("fx_solo", "res://nope/strings.csv"),
		[] as Array[String],
		"no strings file is fine"
	)


func test_harness_catches_snapshots_that_do_not_survive_json() -> void:
	assert_eq(
		SdkConformance.snapshot_errors({"a": 1.5, "b": "x", "c": [true, null, {"d": 2.0}]}, []),
		[] as Array[String]
	)
	var errs := SdkConformance.snapshot_errors({"v": Vector2(1, 2), 3: "x", "n": 5}, [])
	var joined := " | ".join(errs)
	assert_string_contains(joined, "snapshot.v: Vector2 is not a JSON type")
	assert_string_contains(joined, "key 3 is a int")
	assert_string_contains(joined, "snapshot.n: int 5 comes back as a float")
	assert_eq(
		SdkConformance.snapshot_errors([], []).size(), 1, "snapshot() must return a Dictionary"
	)


func test_player_counts() -> void:
	assert_eq(
		SdkConformance.player_counts({"min_players": 1, "max_players": 4}), [1, 4] as Array[int]
	)
	assert_eq(SdkConformance.player_counts({"min_players": 2, "max_players": 2}), [2] as Array[int])
