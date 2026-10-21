extends SceneTree
## Probe for the wrapper's --timeout: it never quits, so only the timeout can end the run.
## With "-- --pid-file=<path>" it writes its own process id there first, so a test can check
## that the timeout killed the real Godot process (on Windows, _console.exe starts it as a child).


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--pid-file="):
			var f: FileAccess = FileAccess.open(arg.trim_prefix("--pid-file="), FileAccess.WRITE)
			f.store_string(str(OS.get_process_id()))
			f.close()
	print("PROBE NEVER_QUIT started")
