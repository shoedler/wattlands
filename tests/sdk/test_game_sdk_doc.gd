extends GutTest
## docs/GAME_SDK.md documents the SDK calls the game briefs rely on (BRIEF 3.6 "docs for game
## sessions"; docs/OWNERSHIP.md SH2; W3 SDK-2): every public method and property of SpeedModel
## (BRIEF 3.11, Tank's drive) is named there, with its units.

const DOC := "res://docs/GAME_SDK.md"


func _doc() -> String:
	return FileAccess.get_file_as_string(DOC)


func test_every_public_speed_model_member_is_documented() -> void:
	var text := _doc()
	assert_ne(text, "", "GAME_SDK.md is readable")
	var script: Script = SpeedModel
	var names: Array[String] = []
	for m: Dictionary in script.get_script_method_list():
		var n := str(m["name"])
		if not n.begins_with("_"):
			names.append(n)
	for p: Dictionary in script.get_script_property_list():
		var n := str(p["name"])
		if not n.begins_with("_") and not n.ends_with(".gd") and (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			names.append(n)
	assert_gt(names.size(), 8, "SpeedModel's members were listed")
	for n in names:
		assert_true(text.contains("`%s" % n) or text.contains(" %s(" % n) or text.contains(".%s(" % n) or text.contains("`%s`" % n),
			"GAME_SDK.md names SpeedModel.%s" % n)
	for snippet: String in ["SpeedModel.create(rider_mass_kg = 75.0, cda = 0.32, mass_offset_kg = 8.0)",
			"step(dt, p_eff_w, grade_pct = 0.0, wind_mps = 0.0) -> float", "SpeedModel.steady_state_speed(",
			"`distance_m` (metres", "`v_mps` (m/s"]:
		assert_string_contains(text, snippet)


func test_the_zwo_importer_result_is_documented() -> void:
	var text := _doc()
	for key: String in ["phases", "blocks", "clamps", "clamp_records", "warnings", "prefix_inserted", "total_s", "error"]:
		assert_true(text.contains("`%s`" % key) or text.contains(", %s" % key) or text.contains("{ok, name, description, phases"),
			"GAME_SDK.md names the importer result key %s" % key)
	assert_string_contains(text, "`parse_zwo(xml_text)` and `parse_zwo_file(path)` return `{ok, name, description, phases, blocks, clamps, clamp_records, warnings, prefix_inserted, total_s, error}`")
