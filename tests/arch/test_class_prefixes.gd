extends GutTest
## W4 (QT-6; BRIEF 6, CLAUDE.md "Unique class_names. Game classes carry their game's prefix ...
## Platform classes never use a game prefix."): no class_name in platform code (addons/wattlands,
## the app shell src/app and tools) starts with a game's prefix, so the game sessions that come
## later can't collide with the platform. W3 found the platform's .zwo importer named
## WorkoutImport, inside the Workout game's namespace; it is ZwoImport now.

const PLATFORM_ROOTS: Array[String] = ["res://addons/wattlands", "res://src/app", "res://tools"]
## The registered games' class prefixes (Workout ships with the platform; Siege, Tank and Fishing
## come later; Template is the scaffold tools/new_game copies). Upper-case forms too.
const GAME_PREFIXES: Array[String] = [
	"Workout",
	"WORKOUT",
	"Siege",
	"SIEGE",
	"Tank",
	"TANK",
	"Fishing",
	"FISHING",
	"Template",
]


static func class_names_under(root: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if DirAccess.open(root) == null:
		return out
	var re := RegEx.create_from_string("(?m)^class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
	for f in DirAccess.get_files_at(root):
		if not f.ends_with(".gd"):
			continue
		var path := root.path_join(f)
		var m := re.search(FileAccess.get_file_as_string(path))
		if m != null:
			out.append({"path": path, "name": m.get_string(1)})
	for d in DirAccess.get_directories_at(root):
		if d.begins_with("."):
			continue
		out.append_array(class_names_under(root.path_join(d)))
	return out


static func prefixed(entries: Array[Dictionary]) -> Array[String]:
	var bad: Array[String] = []
	for e in entries:
		for p: String in GAME_PREFIXES:
			if str(e["name"]).begins_with(p):
				bad.append("%s: class_name %s" % [e["path"], e["name"]])
				break
	return bad


func test_no_platform_class_carries_a_game_prefix() -> void:
	var all: Array[Dictionary] = []
	for root in PLATFORM_ROOTS:
		all.append_array(class_names_under(root))
	assert_gt(all.size(), 100, "the scan saw the platform's classes (%d)" % all.size())
	var bad := prefixed(all)
	assert_eq(bad.size(), 0, "platform classes with a game prefix:\n" + "\n".join(bad))


func test_the_zwo_importer_is_zwo_import() -> void:
	var names: Array[String] = []
	for e in class_names_under("res://addons/wattlands/sim"):
		names.append(str(e["name"]))
	assert_has(names, "ZwoImport")
	assert_does_not_have(names, "WorkoutImport")


func test_the_check_flags_a_prefixed_platform_class() -> void:
	var entries: Array[Dictionary] = [
		{"path": "res://addons/wattlands/sim/x.gd", "name": "WorkoutImport"},
		{"path": "res://addons/wattlands/sim/y.gd", "name": "SiegeWave"},
		{"path": "res://tools/z.gd", "name": "TANK_TOOL"},
		{"path": "res://addons/wattlands/sim/ok.gd", "name": "ZwoImport"},
		{"path": "res://addons/wattlands/sim/ok2.gd", "name": "Bots"},
	]
	assert_eq(prefixed(entries).size(), 3)
