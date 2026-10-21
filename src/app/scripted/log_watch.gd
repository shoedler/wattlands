class_name AppLogWatch
extends Logger
## Counts what a scripted peer's report needs from the engine log: script errors (runtime
## "SCRIPT ERROR"s) and desync warnings (any push_warning or error whose text mentions
## "desync"; plain prints are not counted).
## Installed with OS.add_logger() only in scripted mode. Thread-safe.

var script_errors: int = 0
var errors: int = 0
var desync_warnings: int = 0
var _mutex: Mutex = Mutex.new()


func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
	var text := (rationale + " " + code).to_lower()
	_mutex.lock()
	if error_type == ERROR_TYPE_SCRIPT:
		script_errors += 1
	elif error_type == ERROR_TYPE_ERROR:
		errors += 1
	if text.contains("desync"):
		desync_warnings += 1
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass


func counts() -> Dictionary:
	_mutex.lock()
	var out := {"script_errors": script_errors, "errors": errors, "desync_warnings": desync_warnings}
	_mutex.unlock()
	return out
