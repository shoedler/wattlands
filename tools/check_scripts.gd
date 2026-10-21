extends SceneTree
## Static gate (BRIEF 7.2): loads every .gd under addons/wattlands/, src/, tests/ and tools/
## and fails when a load returns null or logs an error, or when a script that is not abstract
## cannot be instantiated.
##
##   tools/godot.sh --headless --path . -s tools/check_scripts.gd
##
## Skips dot-folders and folders with a .gdignore (Godot never imports those). Prints one line
## per failure and a summary "check_scripts: <n> scripts, <f> failures"; exits 1 on any failure.

const ROOTS: Array[String] = [
	"res://addons/wattlands/",
	"res://src/",
	"res://tests/",
	"res://tools/",
]


## Records errors logged while one script loads. Godot 4.7 returns a script with a parse error
## instead of null, so the errors are the reliable signal, also for abstract scripts.
class ErrorCatcher:
	extends Logger

	var _mutex: Mutex = Mutex.new()
	var _errors: PackedStringArray = PackedStringArray()

	func _log_error(
		_function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array
	) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var text: String = rationale if not rationale.is_empty() else code
		_mutex.lock()
		_errors.append("%s (%s:%d)" % [text, file, line])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> PackedStringArray:
		_mutex.lock()
		var out: PackedStringArray = _errors
		_errors = PackedStringArray()
		_mutex.unlock()
		return out


var _catcher: ErrorCatcher = ErrorCatcher.new()


func _initialize() -> void:
	var files: Array[String] = []
	var skipped: Array[String] = []
	for root: String in ROOTS:
		_collect(root, files, skipped)
	files.sort()
	for dir_path: String in skipped:
		print("check_scripts: skipped %s (.gdignore)" % dir_path)
	OS.add_logger(_catcher)
	var failures: int = 0
	for path: String in files:
		var reason: String = _check(path)
		if not reason.is_empty():
			failures += 1
			print("check_scripts: FAIL %s: %s" % [path, reason])
	OS.remove_logger(_catcher)
	print("check_scripts: %d scripts, %d failures" % [files.size(), failures])
	quit(1 if failures > 0 else 0)


func _collect(dir_path: String, files: Array[String], skipped: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	if dir.file_exists(".gdignore"):
		skipped.append(dir_path)
		return
	dir.include_hidden = false
	dir.include_navigational = false
	for file_name: String in dir.get_files():
		if file_name.begins_with("."):
			continue
		if file_name.get_extension() == "gd":
			files.append(dir_path.path_join(file_name))
	for sub: String in dir.get_directories():
		if sub.begins_with("."):
			continue
		_collect(dir_path.path_join(sub) + "/", files, skipped)


func _check(path: String) -> String:
	_catcher.take()
	var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	var errors: PackedStringArray = _catcher.take()
	if res == null:
		return "load returned null" + _describe(errors)
	if not errors.is_empty():
		return "load logged errors" + _describe(errors)
	var script: Script = res as Script
	if script == null:
		return "not a Script (%s)" % res.get_class()
	var abstract: bool = false
	if script.has_method("is_abstract"):
		abstract = bool(script.call("is_abstract"))
	if not abstract and not script.can_instantiate():
		return "can_instantiate() is false and the script is not abstract"
	return ""


func _describe(errors: PackedStringArray) -> String:
	if errors.is_empty():
		return ""
	return ": " + errors[0] + (" (+%d more)" % (errors.size() - 1) if errors.size() > 1 else "")
