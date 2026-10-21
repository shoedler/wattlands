extends GutTest
## BRIEF 4.6.11: only SafetyGovernor holds TrainerController; only TrainerController calls the
## TrainerDevice setters; only FtmsTrainer calls FtmsClient.write_control(); only FtmsClient
## (and the BLE transports, on their backends) write characteristics. This scan reads every
## .gd file under res://addons/wattlands and res://src (recursively, so every game under
## src/games/ is covered automatically) and fails on any other CALL SITE of the guarded names.
##
## What counts as a call site (comments and string contents are lexed out first):
##   - any code reference to a guarded name: obj.set_target_power(...), super.write_control(),
##     a method reference like `var f := dev.set_simulation`;
##   - a string or StringName literal that is exactly a guarded name, which is how dynamic
##     calls name a method: call("set_target_power", ...), callv(&"write_control", ...),
##     Callable(dev, "set_resistance"), call_deferred(...), has_method(...).
## Not call sites: definitions (`func set_target_power(`), comments and doc comments, and
## strings that merely mention a name ("never call set_target_power here").
## Names built at run time from pieces cannot be seen by any static scan; code review covers them.

const GUARDED: Array[String] = [
	"write_characteristic", "write_control", "set_target_power", "set_simulation", "set_resistance",
]
const ROOTS: Array[String] = ["res://addons/wattlands", "res://src"]
## Path -> the guarded names that file may call.
const ALLOW := {
	"res://addons/wattlands/trainer/control/trainer_controller.gd": ["set_target_power", "set_simulation", "set_resistance"],
	"res://addons/wattlands/trainer/ftms_trainer.gd": ["write_control"],
	"res://addons/wattlands/trainer/ftms_client.gd": ["write_characteristic"],
	"res://addons/wattlands/trainer/ble/gdble_transport.gd": ["write_characteristic"],
	"res://addons/wattlands/trainer/ble/bridge_transport.gd": ["write_characteristic"],
}

const _QUOTE := 34
const _APOS := 39
const _HASH := 35
const _BACKSLASH := 92
const _NEWLINE := 10

var _tmp_dirs: Array[String] = []


func after_each() -> void:
	for d in _tmp_dirs:
		_remove_tree(d)
	_tmp_dirs.clear()


# --- the scanner -----------------------------------------------------------------------

## Split GDScript source into code (comments removed, every string literal replaced by "",
## line breaks kept) and its string literals [{line, text}].
static func lex(src: String) -> Dictionary:
	var parts := PackedStringArray()
	var strings: Array[Dictionary] = []
	var n := src.length()
	var i := 0
	var line := 1
	var seg := 0
	while i < n:
		var c := src.unicode_at(i)
		if c == _NEWLINE:
			line += 1
			i += 1
		elif c == _HASH:
			parts.append(src.substr(seg, i - seg))
			while i < n and src.unicode_at(i) != _NEWLINE:
				i += 1
			seg = i
		elif c == _QUOTE or c == _APOS:
			parts.append(src.substr(seg, i - seg))
			var raw := i > 0 and src.unicode_at(i - 1) == 114 and (i < 2 or not _is_ident(src.unicode_at(i - 2)))
			var triple := i + 2 < n and src.unicode_at(i + 1) == c and src.unicode_at(i + 2) == c
			var open_len := 3 if triple else 1
			var start_line := line
			var j := i + open_len
			var text := ""
			var newlines := 0
			while j < n:
				var d := src.unicode_at(j)
				if d == _BACKSLASH and not raw and j + 1 < n:
					text += src.substr(j, 2)
					if src.unicode_at(j + 1) == _NEWLINE:
						newlines += 1
					j += 2
					continue
				if d == c and (not triple or (j + 2 < n and src.unicode_at(j + 1) == c and src.unicode_at(j + 2) == c)):
					break
				if d == _NEWLINE:
					if not triple:
						break
					newlines += 1
				text += String.chr(d)
				j += 1
			strings.append({"line": start_line, "text": text})
			parts.append("\"\"" + "\n".repeat(newlines))
			line += newlines
			i = mini(n, j + (open_len if j < n and src.unicode_at(j) == c else 0))
			seg = i
		else:
			i += 1
	parts.append(src.substr(seg, n - seg))
	return {"code": "".join(parts), "strings": strings}


static func _is_ident(c: int) -> bool:
	return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95


## Violations in one file's source: [{path, line, name, how}] with how "reference" or "dynamic".
static func scan_source(src: String, path: String, allow: Dictionary = ALLOW) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lexed := lex(src)
	var code: String = lexed["code"]
	var allowed: Array = allow.get(path, [])
	var re := RegEx.create_from_string("(?<![A-Za-z0-9_])(" + "|".join(GUARDED) + ")(?![A-Za-z0-9_])")
	var defn := RegEx.create_from_string("(^|[^A-Za-z0-9_])func\\s+$")
	for m in re.search_all(code):
		var name := m.get_string(1)
		if allowed.has(name):
			continue
		var start := m.get_start(1)
		var line_start := code.rfind("\n", start - 1) + 1 if start > 0 else 0
		var prefix := code.substr(line_start, start - line_start)
		if defn.search(prefix) != null:
			continue
		out.append({"path": path, "line": code.substr(0, start).count("\n") + 1, "name": name, "how": "reference"})
	for s: Dictionary in lexed["strings"]:
		var text := str(s["text"])
		if GUARDED.has(text) and not allowed.has(text):
			out.append({"path": path, "line": int(s["line"]), "name": text, "how": "dynamic"})
	return out


## Every .gd under `root` (recursively).
static func gd_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for f in DirAccess.get_files_at(root):
		if f.ends_with(".gd"):
			out.append(root.path_join(f))
	for d in DirAccess.get_directories_at(root):
		if d.begins_with("."):
			continue
		out.append_array(gd_files(root.path_join(d)))
	return out


static func scan_roots(roots: Array, allow: Dictionary = ALLOW) -> Dictionary:
	var files: Array[String] = []
	var violations: Array[Dictionary] = []
	for root: String in roots:
		for path in gd_files(root):
			files.append(path)
			violations.append_array(scan_source(FileAccess.get_file_as_string(path), path, allow))
	return {"files": files, "violations": violations}


static func describe(violations: Array) -> String:
	var lines := PackedStringArray()
	for v: Dictionary in violations:
		lines.append("%s:%d %s (%s)" % [v["path"], v["line"], v["name"], v["how"]])
	return "\n".join(lines)


# --- the gate ----------------------------------------------------------------------------

func test_no_call_site_outside_the_allowlist() -> void:
	var result := scan_roots(ROOTS)
	var files: Array[String] = result["files"]
	var violations: Array[Dictionary] = result["violations"]
	assert_gt(files.size(), 40, "the scan walked the platform (%d files)" % files.size())
	assert_has(files, "res://addons/wattlands/trainer/control/trainer_controller.gd")
	assert_has(files, "res://addons/wattlands/trainer/control/safety_governor.gd")
	assert_has(files, "res://addons/wattlands/contracts/trainer_device.gd")
	assert_eq(violations.size(), 0, "bypassing call sites:\n" + describe(violations))


func test_the_scan_sees_the_controllers_real_calls() -> void:
	var path := "res://addons/wattlands/trainer/control/trainer_controller.gd"
	var found := scan_source(FileAccess.get_file_as_string(path), path, {})
	var names := {}
	for v in found:
		names[v["name"]] = true
	assert_true(names.has("set_target_power"), "without the allowlist the controller's calls show")
	assert_true(names.has("set_simulation"))
	assert_true(names.has("set_resistance"))
	assert_eq(scan_source(FileAccess.get_file_as_string(path), path).size(), 0, "and the allowlist admits them")


func test_the_governor_has_no_call_sites() -> void:
	var path := "res://addons/wattlands/trainer/control/safety_governor.gd"
	assert_eq(scan_source(FileAccess.get_file_as_string(path), path, {}).size(), 0,
		"the governor only talks to its controller")


# --- fixtures: the scanner flags a bypass ------------------------------------------------------

const BYPASS := """extends Node
## Calls set_target_power directly. A doc comment mention is fine.
var dev: TrainerDevice


func set_target_power(w: int) -> void: # a definition is fine
	pass


func bad() -> void:
	dev.set_target_power(300)
	dev.call("set_simulation", 0.0, 5.0, 0.004, 0.51)
	var c := Callable(dev, 'set_resistance')
	dev.callv(&"write_control", [PackedByteArray()])
	print("never call set_target_power here") # set_simulation in a comment
	var s := \"\"\"multi
line set_simulation(1) string\"\"\"
	var m := dev.write_characteristic
	super.set_resistance(2.0)
"""


func _fixture_dir() -> String:
	var d := Paths.make_temp_dir("wattlands_no_bypass")
	_tmp_dirs.append(d)
	return d


func test_fixture_file_is_flagged() -> void:
	var root := _fixture_dir()
	DirAccess.make_dir_recursive_absolute(root.path_join("src/games/rogue"))
	var path := root.path_join("src/games/rogue/rogue_game.gd")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(BYPASS)
	f.close()
	var result := scan_roots([root])
	var v: Array[Dictionary] = result["violations"]
	var got := {}
	for x in v:
		got["%d:%s:%s" % [x["line"], x["name"], x["how"]]] = true
	var expected := [
		"11:set_target_power:reference",
		"12:set_simulation:dynamic",
		"13:set_resistance:dynamic",
		"14:write_control:dynamic",
		"18:write_characteristic:reference",
		"19:set_resistance:reference",
	]
	for e: String in expected:
		assert_true(got.has(e), "flagged %s\n%s" % [e, describe(v)])
	assert_eq(v.size(), expected.size(), "nothing else (comments, the definition, messages):\n" + describe(v))


func test_allowlist_is_per_file_and_per_name() -> void:
	var ctl := "res://addons/wattlands/trainer/control/trainer_controller.gd"
	var src := "func f(d, c) -> void:\n\td.set_target_power(1)\n\tc.write_control(PackedByteArray())\n"
	var v := scan_source(src, ctl)
	assert_eq(v.size(), 1)
	assert_eq(v[0]["name"], "write_control", "the controller may not write the control point")
	var other := scan_source(src, "res://addons/wattlands/core/local_rider.gd")
	assert_eq(other.size(), 2, "the same lines anywhere else are both violations")


func test_lexer_strings_comments_and_lines() -> void:
	var src := "var a := \"x # not a comment\" # set_simulation\nvar b := 'it\\'s'\nvar c := \"\"\"\n\n\"\"\"\nset_resistance(1)\n"
	var lexed := lex(src)
	var code: String = lexed["code"]
	assert_eq(code.count("\n"), src.count("\n"), "line breaks kept")
	assert_false(code.contains("set_simulation"), "comment removed")
	assert_false(code.contains("not a comment"), "string blanked")
	var v := scan_source(src, "res://x.gd")
	assert_eq(v.size(), 1)
	assert_eq(int(v[0]["line"]), 6, "line numbers survive triple-quoted strings")
	var strings: Array = lexed["strings"]
	assert_eq(strings[1]["text"], "it\\'s", "escaped quotes stay inside the string")


func _remove_tree(path: String) -> void:
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(d))
	DirAccess.remove_absolute(path)
