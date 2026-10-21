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
## Not call sites: definitions (`func set_target_power(`, so the BleTransport implementations'
## `func write_characteristic(` are definitions), comments and doc comments, and strings that
## merely mention a name ("never call set_target_power here").
## ALLOW admits a name anywhere in a file; ALLOW_SITES admits at most n call sites of a name in
## a file (W2: GdbleTransport's single hand-off of the bytes to the GDBLE device, the
## &"write_characteristic" in _device_write); a second call site there is flagged.
## Names built at run time from pieces cannot be seen by any static scan; code review covers them.
## Besides the five names BRIEF 4.6.11 lists, the scan guards TrainerDevice.request_stop (Stop,
## 0x08 0x01): the TrainerDevice contract gives it to TrainerController alone, and the exit path
## (4.6.9) reaches it only through SafetyGovernor.shutdown().
##
## W4 (SAF-4): games (any file under src/games/) change trainer load only through ctx.directives
## (BRIEF 3.6, CLAUDE.md). A game must not reach the trainer stack at all, since the governor and
## LocalRider APIs can lift 4.6 rules (configure({profile: "ramp_test", skip_warmup}), a plan the
## PlanValidator never saw, resume() after a panic). So under src/games/ the scan also fails on
##   - references to the stack's classes and autoload: GAME_CLASS_NAMES (TrainerService,
##     LocalRider, SafetyGovernor, TrainerController, the devices, FtmsClient, the connection
##     manager and transports, and DirectiveRouter / HudRouter, whose rider maps sit behind
##     ctx.directives and ctx.hud), also inside strings ("/root/TrainerService");
##   - member access to GAME_MEMBER_NAMES (.governor, .configure_governor, .emergency_safe,
##     .resume, .local_rider, .trainer_service, ._riders) and the routers' rider maps
##     (directives.riders, hud.riders), calls of configure_governor(, emergency_safe( and
##     resume( (definitions excepted), and those names as exact string literals (dynamic calls).
## Workout's own WorkoutState.riders is a game field, so a bare ".riders" is not flagged; the
## routers' maps are private (the sdk's _riders) and reached only through the patterns above.
## Scene and resource files (.tscn, .tres) are scanned as text too: a signal connection or an
## AnimationPlayer method track naming a guarded setter is a call site anywhere, and under
## src/games/ so is any name above or a script path into the trainer stack.

const GUARDED: Array[String] = [
	"write_characteristic", "write_control", "set_target_power", "set_simulation", "set_resistance",
	"request_stop",
]
const ROOTS: Array[String] = ["res://addons/wattlands", "res://src"]
## W4 (SAF-4): what a file under src/games/ may not name (see the header).
const GAME_CLASS_NAMES: Array[String] = [
	"TrainerService", "WlTrainerService", "LocalRider", "SafetyGovernor", "TrainerController",
	"TrainerDevice", "MockTrainer", "FtmsTrainer", "FtmsClient", "FtmsConnectionManager",
	"GdbleTransport", "BridgeTransport", "BleTransport", "DirectiveRouter", "HudRouter",
]
const GAME_MEMBER_NAMES: Array[String] = [
	"governor", "configure_governor", "emergency_safe", "resume", "local_rider", "trainer_service",
	"_riders",
]
## Calls of these by bare name are flagged in games too (definitions excepted).
const GAME_CALL_NAMES: Array[String] = ["configure_governor", "emergency_safe", "resume"]
## Script paths a game scene may not reference.
const GAME_SCRIPT_PATHS: Array[String] = [
	"addons/wattlands/trainer/", "addons/wattlands/core/local_rider.gd",
	"addons/wattlands/core/trainer_service.gd", "addons/wattlands/sdk/directive_router.gd",
	"addons/wattlands/sdk/hud_router.gd",
]
const GAMES_DIR := "/src/games/"
## Path -> the guarded names that file may call.
const ALLOW := {
	"res://addons/wattlands/trainer/control/trainer_controller.gd": ["set_target_power", "set_simulation", "set_resistance", "request_stop"],
	"res://addons/wattlands/trainer/ftms_trainer.gd": ["write_control"],
	"res://addons/wattlands/trainer/ftms_client.gd": ["write_characteristic"],
}
## Path -> {guarded name: the most call sites that file may have}. BridgeTransport only
## defines write_characteristic (it sends a JSON request), so it needs no entry.
const ALLOW_SITES := {
	"res://addons/wattlands/trainer/ble/gdble_transport.gd": {"write_characteristic": 1},
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
## `sites` (ALLOW_SITES by default) admits the first n call sites of a name in that file, in
## source order; any further one is a violation.
static func scan_source(src: String, path: String, allow: Dictionary = ALLOW, sites: Dictionary = ALLOW_SITES) -> Array[Dictionary]:
	var found := _call_sites(src, path, allow)
	var budget: Dictionary = (sites.get(path, {}) as Dictionary).duplicate()
	var out: Array[Dictionary] = []
	for v in found:
		var name := str(v["name"])
		if int(budget.get(name, 0)) > 0:
			budget[name] = int(budget[name]) - 1
			continue
		out.append(v)
	return out


## Every call site of a guarded name the file's ALLOW entry doesn't admit, in source order.
static func _call_sites(src: String, path: String, allow: Dictionary) -> Array[Dictionary]:
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
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["line"]) < int(b["line"]))
	return out


## W4 (SAF-4): a game file's reaches into the trainer stack: [{path, line, name, how}] with how
## "class", "member", "call", "dynamic" or "router".
static func scan_game_source(src: String, path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lexed := lex(src)
	var code: String = lexed["code"]
	var classes := RegEx.create_from_string("(?<![A-Za-z0-9_])(" + "|".join(GAME_CLASS_NAMES) + ")(?![A-Za-z0-9_])")
	var members := RegEx.create_from_string("\\.\\s*(" + "|".join(GAME_MEMBER_NAMES) + ")(?![A-Za-z0-9_])")
	var calls := RegEx.create_from_string("(?<![A-Za-z0-9_.])(" + "|".join(GAME_CALL_NAMES) + ")\\s*\\(")
	var routers := RegEx.create_from_string("(?<![A-Za-z0-9_])(directives|hud)\\s*\\)?\\s*\\.\\s*(riders)(?![A-Za-z0-9_])")
	var defn := RegEx.create_from_string("(^|[^A-Za-z0-9_])func\\s+$")
	for m in classes.search_all(code):
		out.append(_hit(code, m.get_start(1), path, m.get_string(1), "class"))
	for m in members.search_all(code):
		out.append(_hit(code, m.get_start(1), path, m.get_string(1), "member"))
	for m in calls.search_all(code):
		var start := m.get_start(1)
		var line_start := code.rfind("\n", start - 1) + 1 if start > 0 else 0
		if defn.search(code.substr(line_start, start - line_start)) != null:
			continue
		out.append(_hit(code, start, path, m.get_string(1), "call"))
	for m in routers.search_all(code):
		out.append(_hit(code, m.get_start(2), path, m.get_string(1) + ".riders", "router"))
	for st: Dictionary in lexed["strings"]:
		var text := str(st["text"])
		if GAME_MEMBER_NAMES.has(text):
			out.append({"path": path, "line": int(st["line"]), "name": text, "how": "dynamic"})
			continue
		var cm := classes.search(text)
		if cm != null:
			out.append({"path": path, "line": int(st["line"]), "name": cm.get_string(1), "how": "dynamic"})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["line"]) < int(b["line"]))
	return out


static func _hit(code: String, start: int, path: String, name: String, how: String) -> Dictionary:
	return {"path": path, "line": code.substr(0, start).count("\n") + 1, "name": name, "how": how}


static func is_game_path(path: String) -> bool:
	return path.replace("\\", "/").contains(GAMES_DIR)


## W4 (SAF-4): a scene or resource file as text: whole-word guarded setters anywhere, and under
## src/games/ every game-guarded name and trainer-stack script path. how is "scene".
static func scan_scene_text(text: String, path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var names: Array[String] = GUARDED.duplicate()
	if is_game_path(path):
		names.append_array(GAME_CLASS_NAMES)
		names.append_array(GAME_MEMBER_NAMES)
	var re := RegEx.create_from_string("(?<![A-Za-z0-9_])(" + "|".join(names) + ")(?![A-Za-z0-9_])")
	for m in re.search_all(text):
		out.append(_hit(text, m.get_start(1), path, m.get_string(1), "scene"))
	if is_game_path(path):
		for sp: String in GAME_SCRIPT_PATHS:
			var at := text.find(sp)
			while at >= 0:
				out.append(_hit(text, at, path, sp, "scene"))
				at = text.find(sp, at + sp.length())
	return out


## Every .tscn and .tres under `root` (recursively).
static func scene_files(root: String) -> Array[String]:
	var out: Array[String] = []
	if DirAccess.open(root) == null:
		return out
	for f in DirAccess.get_files_at(root):
		if f.ends_with(".tscn") or f.ends_with(".tres"):
			out.append(root.path_join(f))
	for d in DirAccess.get_directories_at(root):
		if d.begins_with("."):
			continue
		out.append_array(scene_files(root.path_join(d)))
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


static func scan_roots(roots: Array, allow: Dictionary = ALLOW, sites: Dictionary = ALLOW_SITES) -> Dictionary:
	var files: Array[String] = []
	var violations: Array[Dictionary] = []
	for root: String in roots:
		for path in gd_files(root):
			files.append(path)
			var src := FileAccess.get_file_as_string(path)
			violations.append_array(scan_source(src, path, allow, sites))
			if is_game_path(path):
				violations.append_array(scan_game_source(src, path))
		for path in scene_files(root):
			files.append(path)
			violations.append_array(scan_scene_text(FileAccess.get_file_as_string(path), path))
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
	assert_true(names.has("request_stop"))
	assert_eq(scan_source(FileAccess.get_file_as_string(path), path).size(), 0, "and the allowlist admits them")


## Code references to the TrainerController class outside its own file and the governor.
static func controller_holders(roots: Array) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.create_from_string("(?<![A-Za-z0-9_])TrainerController(?![A-Za-z0-9_])")
	var own := ["res://addons/wattlands/trainer/control/trainer_controller.gd",
		"res://addons/wattlands/trainer/control/safety_governor.gd"]
	for root: String in roots:
		for path in gd_files(root):
			if own.has(path):
				continue
			var code: String = lex(FileAccess.get_file_as_string(path))["code"]
			if re.search(code) != null:
				out.append(path)
	return out


func test_only_the_governor_holds_a_trainer_controller() -> void:
	var holders := controller_holders(ROOTS)
	assert_eq(holders.size(), 0, "TrainerController referenced outside SafetyGovernor:\n" + "\n".join(holders))


func test_the_governor_has_no_call_sites() -> void:
	var path := "res://addons/wattlands/trainer/control/safety_governor.gd"
	assert_eq(scan_source(FileAccess.get_file_as_string(path), path, {}).size(), 0,
		"the governor only talks to its controller")


## ble (W2): the BleTransport implementations define write_characteristic; the definitions are
## no call sites. GdbleTransport hands the bytes to the GDBLE device exactly once (a dynamic
## &"write_characteristic" in _device_write); BridgeTransport sends a JSON request instead.
func test_ble_transports_define_and_hand_off_once() -> void:
	var gdble := "res://addons/wattlands/trainer/ble/gdble_transport.gd"
	var bridge := "res://addons/wattlands/trainer/ble/bridge_transport.gd"
	var contract := "res://addons/wattlands/contracts/ble_transport.gd"
	assert_eq(scan_source(FileAccess.get_file_as_string(bridge), bridge, {}, {}).size(), 0,
		"BridgeTransport only defines write_characteristic")
	assert_eq(scan_source(FileAccess.get_file_as_string(contract), contract, {}, {}).size(), 0,
		"the BleTransport contract only defines it")
	var raw := scan_source(FileAccess.get_file_as_string(gdble), gdble, {}, {})
	assert_eq(raw.size(), 1, "GdbleTransport has exactly one call site, its hand-off:
" + describe(raw))
	if raw.size() == 1:
		assert_eq(raw[0]["name"], "write_characteristic")
		assert_eq(raw[0]["how"], "dynamic")
	assert_eq(scan_source(FileAccess.get_file_as_string(gdble), gdble).size(), 0, "and ALLOW_SITES admits it")


func test_a_second_hand_off_in_gdble_transport_is_flagged() -> void:
	var gdble := "res://addons/wattlands/trainer/ble/gdble_transport.gd"
	var src := FileAccess.get_file_as_string(gdble)
	src += "

func _sneaky(dev: Object) -> void:
	dev.write_characteristic(\"a\", \"b\", PackedByteArray(), true)
"
	var v := scan_source(src, gdble)
	assert_eq(v.size(), 1, "the extra call site shows:
" + describe(v))
	if v.size() == 1:
		assert_eq(v[0]["how"], "reference")
	var twice := "func _w(d: Object) -> void:
	d.call(&\"write_characteristic\")
	d.call(&\"write_characteristic\")
"
	assert_eq(scan_source(twice, gdble).size(), 1, "only one hand-off is admitted")
	assert_eq(scan_source(twice, "res://addons/wattlands/trainer/ble/bridge_transport.gd").size(), 2,
		"BridgeTransport has no hand-off allowance")


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
	dev.request_stop()
	dev.call_deferred(&"request_stop")
	var ok := dev.has_method("request_stop_soon") # not exactly a guarded name
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
	var all: Array[Dictionary] = result["violations"]
	# W4: under src/games/ the game rules (SAF-4) flag the TrainerDevice reference too; this
	# test checks the setter scan, so it compares the guarded setters' call sites only.
	var v: Array[Dictionary] = []
	var game_hits := 0
	for x in all:
		if GUARDED.has(str(x["name"])) and str(x["how"]) in ["reference", "dynamic"]:
			v.append(x)
		else:
			game_hits += 1
	assert_gt(game_hits, 0, "the game rules flag `var dev: TrainerDevice` as well")
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
		"20:request_stop:reference",
		"21:request_stop:dynamic",
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
	var stop := "func shutdown(d) -> void:\n\td.request_stop()\n"
	assert_eq(scan_source(stop, ctl).size(), 0, "the controller sends Stop")
	var rider_stop := scan_source(stop, "res://addons/wattlands/core/local_rider.gd")
	assert_eq(rider_stop.size(), 1, "anyone else must go through SafetyGovernor.shutdown()")
	assert_eq(scan_source(stop, "res://addons/wattlands/trainer/ftms_trainer.gd").size(), 1,
		"FtmsTrainer implements request_stop, it never calls it")


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


# --- W4 (SAF-4): games reach the trainer only through ctx.directives ------------------------------


## The W3 fixture (build/w3/safety_fixture/src/games/rogue/rogue_game.gd): a game that changes
## trainer load without ctx.directives, naming none of the guarded setters. W3: 0 violations.
const ROGUE := """extends GameModule
## W3 safety fixture: a game that changes trainer load without ctx.directives.


func sim_step(_dt: float, _frame: InputFrame) -> void:
	# Lift the 150% cap, the duration limits, the long-phase cap and the unverified factor.
	var rider: LocalRider = TrainerService.local_rider()
	rider.governor.configure({"profile": "ramp_test", "ftp_verified": true, "skip_warmup": true})
	# Hand a rider a plan the PlanValidator never saw (ctx.directives exposes the LocalRiders).
	var router := ctx.directives as DirectiveRouter
	var other: LocalRider = router.riders[ctx.local_peer]
	other.set_plan(EffortPlan.of([PlanPhase.erg(Wl.WORK, 200.0, 600.0, "no validator")]))
	other.start_phase(0)
	# Leave a panic the rider did not leave.
	other.resume()
"""

## More ways in: the autoload by path, dynamic calls, the routers' maps, a bare resume().
const SNEAKY := """extends GameModule


func resume() -> void: # a game's own definition is fine
	pass


func sim_step(_dt: float, _frame: InputFrame) -> void:
	var ts := get_node("/root/TrainerService")
	ts.call("emergency_safe")
	var r: Variant = ctx.directives.riders
	var p: Variant = ctx.hud._riders
	var g: Variant = some_rider.get("governor")
	resume()
	some_rider.configure_governor({"skip_warmup": true})
	var gov := AutoloadLookup.trainer_service()
"""


func _write(root: String, rel: String, text: String) -> String:
	var path := root.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return path


func test_the_games_reach_the_trainer_only_through_ctx_directives() -> void:
	var result := scan_roots(["res://src/games"])
	var files: Array[String] = result["files"]
	assert_gt(files.size(), 5, "the scan walked the games (%d files)" % files.size())
	assert_has(files, "res://src/games/workout/workout_game.gd")
	var violations: Array[Dictionary] = result["violations"]
	assert_eq(violations.size(), 0, "a game reaches the trainer stack:\n" + describe(violations))


func test_the_w3_rogue_game_is_flagged() -> void:
	var root := _fixture_dir()
	_write(root, "src/games/rogue/rogue_game.gd", ROGUE)
	var v: Array[Dictionary] = scan_roots([root])["violations"]
	var got := {}
	for x in v:
		got["%d:%s:%s" % [x["line"], x["name"], x["how"]]] = true
	for e: String in [
		"7:LocalRider:class", "7:TrainerService:class", "7:local_rider:member",
		"8:governor:member", "10:DirectiveRouter:class", "11:LocalRider:class",
		"15:resume:member",
	]:
		assert_true(got.has(e), "flagged %s\n%s" % [e, describe(v)])
	assert_gt(v.size(), 0, "W3: a game that reconfigures the governor gave 0 violations")


func test_more_ways_into_the_stack_are_flagged() -> void:
	var root := _fixture_dir()
	_write(root, "src/games/sneaky/sneaky_game.gd", SNEAKY)
	var v: Array[Dictionary] = scan_roots([root])["violations"]
	var got := {}
	for x in v:
		got["%d:%s:%s" % [x["line"], x["name"], x["how"]]] = true
	for e: String in [
		"9:TrainerService:dynamic", "10:emergency_safe:dynamic", "11:directives.riders:router",
		"12:_riders:member", "13:governor:dynamic", "14:resume:call", "15:configure_governor:member",
		"16:trainer_service:member",
	]:
		assert_true(got.has(e), "flagged %s\n%s" % [e, describe(v)])
	for x in v:
		assert_ne(int(x["line"]), 4, "the game's own func resume() is a definition: %s" % str(x))


func test_the_same_code_outside_src_games_is_the_platforms_business() -> void:
	var root := _fixture_dir()
	_write(root, "src/app/screens/some_screen.gd", ROGUE)
	assert_eq(scan_roots([root])["violations"].size(), 0, "only games are held to ctx.directives")


func test_scene_files_are_scanned() -> void:
	var root := _fixture_dir()
	_write(root, "src/app/panel.tscn", """[gd_scene format=3]

[node name="Panel" type="Control"]

[connection signal="pressed" from="Button" to="." method="set_target_power"]
""")
	_write(root, "src/games/rogue/rogue.tscn", """[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://addons/wattlands/core/local_rider.gd" id="1"]

[node name="Rogue" type="Node"]
script = ExtResource("1")
""")
	_write(root, "src/games/rogue/anim.tres", """[gd_resource type="Animation" format=3]

[resource]
tracks/0/type = "method"
tracks/0/keys = {"values": [{"args": [], "method": &"emergency_safe"}]}
""")
	var result := scan_roots([root])
	var v: Array[Dictionary] = result["violations"]
	var got := {}
	for x in v:
		got["%s:%s" % [str(x["path"]).get_file(), x["name"]]] = true
	assert_true(got.has("panel.tscn:set_target_power"), "a signal connection naming a setter\n" + describe(v))
	assert_true(got.has("rogue.tscn:addons/wattlands/core/local_rider.gd"), "a game scene scripting a LocalRider\n" + describe(v))
	assert_true(got.has("anim.tres:emergency_safe"), "a method track in a game resource\n" + describe(v))
	assert_eq((result["files"] as Array).filter(func(f: String) -> bool: return not f.ends_with(".gd")).size(), 3)
