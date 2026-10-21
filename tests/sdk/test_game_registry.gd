extends GutTest
## WlGameRegistry (BRIEF 3.6, 3.5 first run, 7.1 "GameRegistry validation"; docs/OWNERSHIP.md
## REG1-REG7, GM1, CTX13; 3.1 C18). Fixture games live under tests/fixtures/games/.

const FIXTURES := "res://tests/fixtures/games"
const ENTRY := "res://tests/fixtures/games/fx_game.gd"

var _reg: WlGameRegistry = null


func before_each() -> void:
	_reg = WlGameRegistry.new()
	_reg.scan_on_ready = false
	_reg.content_root = FIXTURES.path_join("_content")


func after_each() -> void:
	if _reg != null:
		_reg.clear()
		_reg.free()
		_reg = null


func _valid() -> Dictionary:
	return {
		"id": "fx_valid", "title": "Valid", "summary": "s", "version": "1.0.0",
		"min_players": 1, "max_players": 4, "bots": true, "presentation": "2d",
		"pixel_base": [640, 360], "entry": ENTRY, "contents": ["a", "b"],
		"default_content": "a", "e2e_content": "b", "zero_input_content": "a",
	}


func _with(changes: Dictionary, erase: Array = []) -> Dictionary:
	var m := _valid()
	for k: String in changes.keys():
		m[k] = changes[k]
	for k: String in erase:
		m.erase(k)
	return m


func test_scan_lists_valid_games_sorted_by_title() -> void:
	_reg.scan(FIXTURES.path_join("runtime"))
	assert_eq(_reg.ids(), ["fx_crew", "fx_solo"] as Array[String])
	var list := _reg.games()
	assert_eq(list.size(), 2)
	assert_eq(str(list[0]["title"]), "Fixture Crew")
	assert_true(_reg.has_game("fx_solo"))
	assert_false(_reg.has_game("nope"))
	var m := _reg.manifest("fx_solo")
	assert_typeof(m["min_players"], TYPE_INT, "whole numbers are normalized to int")
	assert_eq(m["first_run_priority"], 0)
	assert_eq(_reg.manifest("fx_crew")["first_run_priority"], -1, "negative priorities are valid (C18)")
	assert_eq(_reg.game_dir("fx_solo"), FIXTURES.path_join("runtime/fx_solo"))
	assert_eq(_reg.content_dir("fx_solo"), FIXTURES.path_join("_content/fx_solo"))


func test_scan_hides_invalid_games_naming_the_field() -> void:
	_reg.scan(FIXTURES.path_join("scan"))
	assert_eq(_reg.ids(), ["fx_no_picker", "fx_valid"] as Array[String])
	var invalid := _reg.invalid_games()
	var by_folder := {}
	for path: String in invalid.keys():
		by_folder[path.get_base_dir().get_file()] = str(invalid[path])
	assert_string_starts_with(str(by_folder.get("fx_bad_presentation", "")), "presentation:")
	assert_string_starts_with(str(by_folder.get("fx_folder_mismatch", "")), "id:")
	assert_string_starts_with(str(by_folder.get("fx_bad_entry", "")), "entry:")
	assert_string_starts_with(str(by_folder.get("fx_bad_option", "")), "options[0].default:")
	assert_string_starts_with(str(by_folder.get("fx_broken_json", "")), "game.json:")
	assert_false(by_folder.has("_template"), "_template is skipped, not rejected")
	assert_false(by_folder.has("fx_no_manifest"), "folders without game.json are ignored")
	assert_push_warning("hiding")


func test_template_is_never_listed() -> void:
	_reg.scan(FIXTURES.path_join("scan"))
	assert_false(_reg.ids().has("_template"))
	assert_false(_reg.has_game("_template"))
	var tm := _with({"id": "_template", "title": "Template"})
	assert_string_starts_with(_reg.add_game(tm, ""), "id:")
	assert_eq(_reg.add_game(tm, "", true), "")
	assert_true(_reg.has_game("_template"), "loaded explicitly for conformance")
	assert_false(_reg.ids().has("_template"), "still never listed")
	var gm := _reg.instantiate("_template")
	assert_not_null(gm)
	gm.free()


func test_missing_picker_image_only_warns() -> void:
	_reg.scan(FIXTURES.path_join("scan"))
	assert_true(_reg.has_game("fx_no_picker"))
	var w := _reg.warnings("fx_no_picker")
	assert_eq(w.size(), 1)
	assert_string_contains(w[0], "missing")
	assert_eq(_reg.warnings("fx_valid"), [] as Array[String], "an existing texture is fine")
	assert_push_warning("generated title card")
	assert_string_contains(WlGameRegistry.picker_image_warning({"picker_image": ENTRY}), "unreadable")


func test_validate_manifest_accepts_the_reference() -> void:
	assert_eq(_reg.validate_manifest(_valid()), "")
	assert_eq(_reg.validate_manifest(_with({"presentation": "3d"}, ["pixel_base"])), "", "3d needs no pixel_base")
	assert_eq(_reg.validate_manifest(_with({"first_run_priority": -1})), "")
	assert_eq(_reg.validate_manifest(_with({"min_players": 2.0, "max_players": 4.0})), "", "JSON floats with whole values")


func test_validate_manifest_names_each_failing_field() -> void:
	var cases := [
		[_with({}, ["id"]), "id:"],
		[_with({"id": "Bad-Id"}), "id:"],
		[_with({"title": ""}), "title:"],
		[_with({}, ["version"]), "version:"],
		[_with({"summary": 5}), "summary:"],
		[_with({"min_players": 0}), "min_players:"],
		[_with({"min_players": 1.5}), "min_players:"],
		[_with({"max_players": 9}), "max_players:"],
		[_with({"min_players": 3, "max_players": 2}), "max_players:"],
		[_with({"bots": "yes"}), "bots:"],
		[_with({"presentation": "4d"}), "presentation:"],
		[_with({}, ["pixel_base"]), "pixel_base:"],
		[_with({"pixel_base": [640]}), "pixel_base:"],
		[_with({}, ["entry"]), "entry:"],
		[_with({"entry": "src/games/x/x.gd"}), "entry:"],
		[_with({"entry": "res://tests/fixtures/games/does_not_exist.gd"}), "entry:"],
		[_with({"entry": "res://tests/fixtures/games/not_a_game.gd"}), "entry:"],
		[_with({"contents": []}), "contents:"],
		[_with({"contents": "a"}), "contents:"],
		[_with({"contents": ["a", "a"]}), "contents:"],
		[_with({"default_content": "zzz"}), "default_content:"],
		[_with({}, ["e2e_content"]), "e2e_content:"],
		[_with({"zero_input_content": 3}), "zero_input_content:"],
		[_with({"first_run_priority": 1.5}), "first_run_priority:"],
		[_with({"picker_image": 5}), "picker_image:"],
		[_with({"options": {}}), "options:"],
		[_with({"player_options": [{"id": "x", "type": "slider", "default": 1}]}), "player_options[0].type:"],
	]
	for c: Array in cases:
		var err := _reg.validate_manifest(c[0])
		assert_true(err.begins_with(str(c[1])), "%s -> %s" % [JSON.stringify(c[0]), err])


func test_folder_must_match_id() -> void:
	assert_eq(_reg.validate_manifest(_valid(), "res://x/fx_valid/game.json"), "")
	assert_string_starts_with(_reg.validate_manifest(_valid(), "res://x/other/game.json"), "id:")


func test_every_option_type_validates() -> void:
	var good := [
		{"id": "t", "type": "toggle", "default": true},
		{"id": "i", "type": "int", "min": -10, "max": 5, "default": 0},
		{"id": "s", "type": "int", "min": 50, "max": 70, "step": 5, "default": 60},
		{"id": "c", "type": "choice", "choices": [{"value": 1, "label": "ONE"}, {"value": 2}], "default": 2},
		{"id": "w", "type": "choice", "choices": [{"value": "x"}], "default": "x", "label": "FX_OPT"},
	]
	assert_eq(WlGameRegistry.validate_option_entries(good, "options"), "")
	var bad := [
		[[{"type": "toggle", "default": true}], "options[0].id:"],
		[[{"id": "a", "type": "toggle", "default": true}, {"id": "a", "type": "toggle", "default": false}], "options[1].id:"],
		[[{"id": "a", "type": "toggle"}], "options[0].default:"],
		[[{"id": "a", "type": "toggle", "default": "yes"}], "options[0].default:"],
		[[{"id": "a", "type": "int", "max": 3, "default": 1}], "options[0].min:"],
		[[{"id": "a", "type": "int", "min": 4, "max": 3, "default": 4}], "options[0].max:"],
		[[{"id": "a", "type": "int", "min": 1, "max": 3, "step": 0, "default": 1}], "options[0].step:"],
		[[{"id": "a", "type": "int", "min": 1, "max": 5, "default": 7}], "options[0].default:"],
		[[{"id": "a", "type": "int", "min": 50, "max": 70, "step": 5, "default": 62}], "options[0].default:"],
		[[{"id": "a", "type": "choice", "choices": [], "default": 1}], "options[0].choices:"],
		[[{"id": "a", "type": "choice", "choices": [{"value": 1}, {"value": 1.0}], "default": 1}], "options[0].choices:"],
		[[{"id": "a", "type": "choice", "choices": [{"value": 1}], "default": 3}], "options[0].default:"],
		[[{"id": "a", "type": "radio", "default": 1}], "options[0].type:"],
		[[{"id": "a", "type": "toggle", "default": true, "label": 3}], "options[0].label:"],
	]
	for c: Array in bad:
		var err := WlGameRegistry.validate_option_entries(c[0], "options")
		assert_true(err.begins_with(str(c[1])), "%s -> %s" % [JSON.stringify(c[0]), err])


func test_instantiate() -> void:
	_reg.scan(FIXTURES.path_join("runtime"))
	var gm := _reg.instantiate("fx_solo")
	assert_not_null(gm)
	assert_true(gm is GameModule)
	gm.free()
	assert_null(_reg.instantiate("nope"))


func test_first_run_from_a_fixture_registry() -> void:
	_reg.scan(FIXTURES.path_join("first_run"))
	assert_eq(_reg.ids().size(), 3)
	assert_eq(_reg.first_run_game(), "workout", "ties at 0 go to workout")


func test_first_run_rule() -> void:
	var m := func(id: String, prio: Variant) -> Dictionary:
		var d := {"id": id}
		if prio != null:
			d["first_run_priority"] = prio
		return d
	assert_eq(WlGameRegistry.pick_first_run([m.call("alpha", 0), m.call("fishing", 10), m.call("workout", null)]), "fishing")
	assert_eq(WlGameRegistry.pick_first_run([m.call("zeta", 0), m.call("alpha", null)]), "alpha", "ties without workout: lowest id")
	assert_eq(WlGameRegistry.pick_first_run([m.call("alpha", 0), m.call("workout", 0), m.call("siege", -1)]), "workout")
	assert_eq(WlGameRegistry.pick_first_run([m.call("siege", -1), m.call("tank", -1)]), "siege")
	assert_eq(WlGameRegistry.pick_first_run([m.call("_template", 99), m.call("tank", -1)]), "tank")
	assert_eq(WlGameRegistry.pick_first_run([]), "")


func test_resolve_options_fills_defaults_and_drops_unknown_keys() -> void:
	_reg.scan(FIXTURES.path_join("runtime"))
	assert_eq(_reg.resolve_options("fx_solo", {}), {"speed": 2, "mirror": false, "mode": "a"})
	var got := _reg.resolve_options("fx_solo", {"speed": 4.0, "mode": "b", "mirror": true})
	assert_eq(got, {"speed": 4, "mirror": true, "mode": "b"})
	assert_typeof(got["speed"], TYPE_INT)
	got = _reg.resolve_options("fx_solo", {"speed": 9, "nope": 1})
	assert_eq(got, {"speed": 2, "mirror": false, "mode": "a"})
	assert_push_warning("using the default")
	assert_push_warning("unknown option")
	assert_eq(_reg.resolve_options("fx_solo", {"offset": -10}, true), {"offset": -10, "reel_pct": 60, "relaxed": false})


func test_check_option_values_for_tools() -> void:
	_reg.scan(FIXTURES.path_join("runtime"))
	assert_eq(_reg.check_option_values("fx_solo", {"speed": 3}), "")
	assert_eq(_reg.check_option_values("fx_solo", {"nope": 1}), "options.nope: unknown option")
	assert_string_starts_with(_reg.check_option_values("fx_solo", {"speed": 9}), "options.speed:")
	assert_string_starts_with(_reg.check_option_values("fx_solo", {"reel_pct": 62}, true), "player_options.reel_pct:")
	assert_string_starts_with(_reg.check_option_values("fx_solo", {"mode": "z"}), "options.mode:")


func test_label_keys() -> void:
	assert_eq(_reg.option_label_key("siege", {"id": "wave_offset"}), "SIEGE_OPT_WAVE_OFFSET")
	assert_eq(_reg.option_label_key("siege", {"id": "x", "label": "SIEGE_X"}), "SIEGE_X")
	assert_eq(_reg.content_label_key("fishing", "free_30"), "FISHING_CONTENT_FREE_30")


func test_game_translations_reach_the_translation_server() -> void:
	assert_eq(String(TranslationServer.translate("FX_SOLO_TITLE")), "FX_SOLO_TITLE", "not registered before the scan")
	_reg.scan(FIXTURES.path_join("runtime"))
	assert_eq(String(TranslationServer.translate("FX_SOLO_TITLE")), "Fixture solo")
	var strings := GameStrings.new()
	assert_eq(strings.t("FX_SOLO_HELLO", ["Ann"]), "Hello Ann")
	assert_eq(strings.t("FX_SOLO_MISSING"), "FX_SOLO_MISSING", "a missing key returns the key")
	_reg.clear()
	assert_eq(String(TranslationServer.translate("FX_SOLO_TITLE")), "FX_SOLO_TITLE", "clear() removes them")


func test_a_cleared_private_registry_keeps_another_registrys_strings() -> void:
	# The conformance test and other tests scan with private registries while the GameRegistry
	# autoload holds the same (cached) Translation objects: clearing one must not unregister
	# strings another still uses.
	_reg.scan(FIXTURES.path_join("runtime"))
	var other := WlGameRegistry.new()
	other.scan_on_ready = false
	other.content_root = FIXTURES.path_join("_content")
	other.scan(FIXTURES.path_join("runtime"))
	assert_eq(String(TranslationServer.translate("FX_SOLO_TITLE")), "Fixture solo")
	other.clear()
	other.free()
	assert_eq(String(TranslationServer.translate("FX_SOLO_TITLE")), "Fixture solo", "still registered for _reg")
	_reg.scan(FIXTURES.path_join("runtime"))
	assert_eq(String(TranslationServer.translate("FX_SOLO_TITLE")), "Fixture solo", "a rescan keeps them")
	_reg.clear()
	assert_eq(String(TranslationServer.translate("FX_SOLO_TITLE")), "FX_SOLO_TITLE", "the last owner removes them")


func test_json_equal_and_is_whole() -> void:
	assert_true(WlGameRegistry.json_equal(1, 1.0))
	assert_true(WlGameRegistry.json_equal({"a": [1, "x"]}, {"a": [1.0, "x"]}))
	assert_false(WlGameRegistry.json_equal(1, "1"))
	assert_false(WlGameRegistry.json_equal(true, 1))
	assert_true(WlGameRegistry.is_whole(3.0))
	assert_false(WlGameRegistry.is_whole(3.5))
	assert_false(WlGameRegistry.is_whole("3"))


func test_autoload_is_a_registry_without_template() -> void:
	var auto := get_tree().root.get_node_or_null("GameRegistry")
	assert_not_null(auto)
	assert_true(auto is WlGameRegistry)
	assert_false((auto as WlGameRegistry).ids().has("_template"))
	for id: String in (auto as WlGameRegistry).ids():
		assert_eq((auto as WlGameRegistry).validate_manifest((auto as WlGameRegistry).manifest(id)), "", id)
