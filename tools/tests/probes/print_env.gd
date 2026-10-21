extends SceneTree
## Probe for tools/tests/wrappers.test.mjs: prints the lock variables, a pass-through variable,
## the user data dir and the user args as Godot sees them, then quits.

const VARS: Array[String] = [
	"WATTLANDS_NO_HW_CONTROL",
	"WATTLANDS_NO_NETWORK_INTEGRATIONS",
	"WATTLANDS_PROBE_PASSTHROUGH",
]


func _initialize() -> void:
	for var_name: String in VARS:
		var value: String = (
			OS.get_environment(var_name) if OS.has_environment(var_name) else "<unset>"
		)
		print("PROBE %s=%s" % [var_name, value])
	print("PROBE USER_DATA_DIR=%s" % OS.get_user_data_dir())
	print("PROBE USER_ARGS=%s" % JSON.stringify(OS.get_cmdline_user_args()))
	print("PROBE DONE")
	quit(0)
