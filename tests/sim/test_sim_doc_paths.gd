extends GutTest
## W4r2 (QT, sdk-completeness): every repo path the sim module's doc comments and its decisions
## (docs/decisions/sim.md) name must exist. W4r2 found ZwoImport's class comment and the sim ADR
## still pointing at src/games/workout/rules/workout_import.gd, the WorkoutImport alias that
## 1835250 deleted.

const SIM_DIR := "res://addons/wattlands/sim"
const DECISIONS := "res://docs/decisions/sim.md"
const PATH_RE := (
	"(?:(?<=res://)|(?<![A-Za-z0-9_./-]))"
	+ "((?:addons|src|tests|tools|content|server|docs)/"
	+ "[A-Za-z0-9_/.-]+\\.(?:gd|json|csv|md|tscn|tres|mjs))"
)


## Repo-relative paths named in `text`.
static func named_paths(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for m in RegEx.create_from_string(PATH_RE).search_all(text):
		var p := m.get_string(1)
		if not out.has(p):
			out.append(p)
	return out


func _sources() -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at(SIM_DIR):
		if f.ends_with(".gd"):
			out[SIM_DIR.path_join(f)] = FileAccess.get_file_as_string(SIM_DIR.path_join(f))
	out[DECISIONS] = FileAccess.get_file_as_string(DECISIONS)
	return out


func test_every_path_the_sim_docs_name_exists() -> void:
	var sources := _sources()
	assert_gt(sources.size(), 5, "the sim sources and the decisions were read")
	assert_ne(str(sources[DECISIONS]), "", "docs/decisions/sim.md was read")
	var missing := PackedStringArray()
	var seen := 0
	for src: String in sources.keys():
		for p in named_paths(str(sources[src])):
			seen += 1
			if not FileAccess.file_exists("res://" + p):
				missing.append("%s names %s" % [src, p])
	assert_gt(seen, 0, "some paths were checked")
	assert_eq(missing.size(), 0, "paths that don't exist:\n" + "\n".join(missing))


func test_zwo_import_names_no_alias() -> void:
	var src := FileAccess.get_file_as_string(SIM_DIR.path_join("workout_import.gd"))
	assert_false(src.contains("rules/workout_import"), "the deleted alias's path")
	assert_false(
		FileAccess.file_exists("res://src/games/workout/rules/workout_import.gd"),
		"the alias is gone"
	)


func test_the_path_pattern() -> void:
	assert_eq(
		named_paths("see src/games/workout/rules/workout_import.gd and `content/strings/sim.csv`."),
		PackedStringArray(["src/games/workout/rules/workout_import.gd", "content/strings/sim.csv"])
	)
	assert_eq(
		named_paths("sim/workout_import.gd and res://addons/x.gd"),
		PackedStringArray(["addons/x.gd"]),
		"a path relative to a module is not checked"
	)
