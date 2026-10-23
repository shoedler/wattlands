extends GutTest
## Siege as a package: game.json exactly per brief 2.2, the option entry, strings (prefix, every
## used key present, unlock names), the first run never picking Siege, and the static scans
## (brief 4: no wall clock or global RNG in rules/ and combat/ and what they call; no trainer
## path in src/games/siege/ but ctx.directives; GAME_SDK 21's names).

const F := preload("res://tests/games/siege/siege_fakes.gd")
const MANIFEST := {
	"id": "siege",
	"title": "Castellum Rotae",
	"summary":
	"Co-op tower defense on a Roman hill fort. Your watts turn a treadwheel; send them to the towers or the generator.",
	"version": "0.1.0",
	"min_players": 1.0,
	"max_players": 4.0,
	"bots": true,
	"presentation": "3d",
	"entry": "res://src/games/siege/siege_game.gd",
	"contents": ["short", "vo2", "sweetspot", "endurance", "drill"],
	"default_content": "short",
	"e2e_content": "drill",
	"zero_input_content": "short",
	"first_run_priority": -1.0,
	"player_options":
	[
		{
			"id": "wave_offset",
			"type": "int",
			"min": -10.0,
			"max": 5.0,
			"step": 1.0,
			"default": 0.0,
			"label": "SIEGE_OPT_WAVE_OFFSET"
		}
	]
}
## Brief 4 static test: nothing in src/games/siege/ names these (plus GAME_SDK 21's stack).
const TRAINER_NAMES: Array[String] = [
	"TrainerController",
	"SafetyGovernor",
	"FtmsClient",
	"write_control",
	"set_target_power",
	"set_simulation",
	"set_resistance",
	"write_characteristic",
	"LocalRider",
	"GameHost",
	"TrainerService",
	"governor_profile",
	"local_rider",
	"game_host",
]
## Folders whose code runs inside SiegeRules.step (brief 4: rules/ and combat/; contracts/ and
## autopilot/ are called from them).
const PURE_DIRS: Array[String] = ["rules", "combat", "autopilot", "contracts"]


func _files(dir: String, exts: Array) -> Array[String]:
	var out: Array[String] = []
	var da := DirAccess.open(dir)
	for f in da.get_files() if da != null else PackedStringArray():
		if exts.has(f.get_extension()):
			out.append(dir.path_join(f))
	for sub in da.get_directories() if da != null else PackedStringArray():
		out.append_array(_files(dir.path_join(sub), exts))
	return out


func _csv_keys() -> Dictionary:
	var keys := {}
	var f := FileAccess.open(F.CONTENT_DIR.path_join("strings.csv"), FileAccess.READ)
	assert_eq(f.get_csv_line(), PackedStringArray(["keys", "en"]), "strings.csv header")
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 2 and row[0] != "":
			assert_false(keys.has(row[0]), "%s listed once" % row[0])
			keys[row[0]] = row[1]
	return keys


## GDScript without its comments.
func _code_only(text: String) -> String:
	var out := PackedStringArray()
	for line in text.split("\n"):
		var at := line.find("#")
		out.append(line.substr(0, at) if at >= 0 else line)
	return "\n".join(out)


func test_manifest_is_exactly_the_brief_s() -> void:
	var m := F.manifest()
	assert_eq(JSON.stringify(m), JSON.stringify(MANIFEST))
	var reg := WlGameRegistry.new()
	reg.scan_on_ready = false
	add_child_autofree(reg)
	reg.scan()
	assert_eq(reg.validate_manifest(m, F.GAME_DIR.path_join("game.json")), "")
	assert_true(reg.has_game("siege"))


func test_the_first_run_never_picks_siege() -> void:
	var reg := WlGameRegistry.new()
	reg.scan_on_ready = false
	add_child_autofree(reg)
	reg.scan()
	assert_ne(reg.first_run_game(), "siege")
	var workout := {"id": "workout", "first_run_priority": 0}
	assert_eq(WlGameRegistry.pick_first_run([F.manifest(), workout]), "workout")


func test_entry_is_an_instantiable_game_module() -> void:
	var script: Script = load(F.manifest()["entry"])
	assert_not_null(script)
	var game: Object = autofree(script.new())
	assert_is(game, GameModule)


func test_every_string_key_has_the_prefix_and_every_used_key_exists() -> void:
	var keys := _csv_keys()
	assert_gt(keys.size(), 100)
	for k: String in keys:
		assert_true(k.begins_with("SIEGE_"), k)
		assert_ne(str(keys[k]).strip_edges(), "", "%s has text" % k)
	var used := {}
	var re := RegEx.create_from_string("SIEGE_[A-Z0-9_]+")
	var sources := _files(F.GAME_DIR, ["gd", "json"]) + _files(F.CONTENT_DIR, ["json"])
	for path in sources:
		for mt in re.search_all(FileAccess.get_file_as_string(path)):
			var k := mt.get_string()
			if not k.ends_with("_"):
				used[k] = path
	var m := F.manifest()
	for e: Dictionary in m.get("player_options", []):
		used[str(e["label"])] = "game.json option label"
	for c: String in m["contents"]:
		used["SIEGE_CONTENT_%s" % c.to_upper()] = "game.json content"
	for name: String in SiegeIds.TOWER_NAMES.slice(1):
		used["SIEGE_TOWER_%s" % name.to_upper()] = "tower name"
	for name: String in SiegeIds.ENEMY_NAMES.slice(1):
		used["SIEGE_ENEMY_%s" % name.to_upper()] = "enemy name"
	for name: String in SiegeIds.ROAD_NAMES:
		used["SIEGE_ROAD_%s" % name.to_upper()] = "road name"
	for name: String in SiegeIds.PERK_NAMES.slice(1):
		used["SIEGE_PERK_%s" % name.to_upper()] = "perk name"
	for item: String in SiegeIds.ITEMS + [SiegeIds.ITEM_SAVE]:
		used["SIEGE_ITEM_%s" % item.to_upper()] = "shop item"
	for why: String in SiegeIds.BUY_REASONS:
		used["SIEGE_SHOP_REFUSED_%s" % why.to_upper()] = "buy refusal"
	for n in range(1, 4):
		used["SIEGE_ITEM_UPGRADE_%d" % n] = "upgrade level"
		used["SIEGE_ITEM_GENERATOR_%d" % n] = "generator level"
	var c := F.content("short")
	for id: String in m["contents"]:
		var plan := SiegePlanBuilder.build(c.shifts[id], F.make_slots(1)[0], id)
		for i in plan.size():
			used[plan.phase(i).label] = "%s phase %d" % [id, i]
	for u: Variant in c.cosmetics["unlocks"]:
		used["SIEGE_UNLOCK_%s" % str(u["id"]).to_upper()] = "unlock"
	assert_gt(used.size(), 60)
	for k: String in used:
		assert_true(keys.has(k), "%s (from %s) is in strings.csv" % [k, used[k]])


func test_the_four_unlocks_have_results_screen_names() -> void:
	var keys := _csv_keys()
	for id: String in ["swallowtail_pennant", "walnut_wheel", "bronze_chain_trim", "long_banner"]:
		assert_true(keys.has("SIEGE_UNLOCK_" + id.to_upper()), id)


func test_rules_and_combat_use_no_wall_clock_or_global_randomness() -> void:
	var clocks := "\\bTime\\.|OS\\.get_ticks|OS\\.get_unix_time|OS\\.get_system_time"
	clocks += "|RandomNumberGenerator\\.new\\("
	var globals := "(?<![\\w.])(randi|randf|randi_range|randf_range|randfn|randomize|rand_from_seed)\\("
	var re := RegEx.create_from_string(clocks + "|" + globals)
	var scanned := 0
	for dir in PURE_DIRS:
		for path in _files(F.GAME_DIR.path_join(dir), ["gd"]):
			scanned += 1
			var hit := re.search(_code_only(FileAccess.get_file_as_string(path)))
			assert_null(hit, "%s: %s" % [path, hit.get_string() if hit != null else ""])
	assert_gte(scanned, 10, "rules, combat, autopilot and contracts are scanned")


func test_nothing_reaches_the_trainer_except_ctx_directives() -> void:
	var scanned := 0
	for path in _files(F.GAME_DIR, ["gd", "tscn", "tres"]):
		scanned += 1
		var text := FileAccess.get_file_as_string(path)
		for name: String in TRAINER_NAMES:
			assert_false(text.contains(name), "%s mentions %s" % [path, name])
		var code := _code_only(text)
		for call: String in [".set_plan(", ".start_phase(", ".resume_phase(", ".governor"]:
			assert_false(code.contains(call), "%s calls %s" % [path, call])
	assert_gte(scanned, 15)


func test_the_only_directive_siege_sends_is_a_request() -> void:
	var re := RegEx.create_from_string("directives\\.(\\w+)\\(")
	var calls := {}
	for path in _files(F.GAME_DIR, ["gd"]):
		for mt in re.search_all(_code_only(FileAccess.get_file_as_string(path))):
			calls[mt.get_string(1)] = path
	assert_eq(calls.keys(), ["request"], "only request (Overdrive's SIM block): %s" % [calls])
