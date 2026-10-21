extends RefCounted
## Helpers shared by the rides tests.


## Deletes `dir` and everything below it (temp dirs from Paths.make_temp_dir only).
static func remove_tree(dir: String) -> void:
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		remove_tree(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


## Captures every log line (print, push_warning, push_error, engine errors) while added
## with OS.add_logger(), so tests can assert that secrets never reach a log.
class LogCapture:
	extends Logger

	var lines: PackedStringArray = PackedStringArray()
	var _mutex: Mutex = Mutex.new()

	func _log_message(message: String, _error: bool) -> void:
		_mutex.lock()
		lines.append(message)
		_mutex.unlock()

	func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		_error_type: int,
		_script_backtraces: Array
	) -> void:
		_mutex.lock()
		lines.append("%s %s %s:%d %s" % [code, rationale, file, line, function])
		_mutex.unlock()

	func text() -> String:
		_mutex.lock()
		var t := "\n".join(lines)
		_mutex.unlock()
		return t
