extends WlSettings
## Test double of the Settings autoload: values in memory, saves counted.

var values: Dictionary = {}
var profile_saves: int = 0
var settings_saves: int = 0
var loads: int = 0


func load_all() -> void:
	loads += 1


func save_profile() -> bool:
	profile_saves += 1
	return true


func save_settings() -> bool:
	settings_saves += 1
	return true


func get_value(key: String, default: Variant = null) -> Variant:
	return values.get(key, default)


func set_value(key: String, value: Variant) -> void:
	values[key] = value
	changed.emit(key)


func relay_url() -> String:
	return str(values.get("relay_url", "ws://localhost:8787/v1"))
