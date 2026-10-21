extends GutTest
## BRIEF 7.10: export_presets.cfg has a Windows Desktop preset that ships the GDBLE DLL.
## Godot copies a GDExtension's library for the export platform next to the executable when
## the .gdextension resource is exported, so the preset must export it (not filter it out)
## and the .gdextension must name an existing Windows x86_64 library.

const PRESETS := "res://export_presets.cfg"
const GDEXT := "res://addons/gdble/gdble.gdextension"


func _windows_preset(cfg: ConfigFile) -> String:
	for section in cfg.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			if str(cfg.get_value(section, "platform", "")) == "Windows Desktop":
				return section
	return ""


func test_windows_desktop_preset_exists() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(PRESETS), OK, "export_presets.cfg parses")
	var sec := _windows_preset(cfg)
	assert_ne(sec, "", "a Windows Desktop preset exists")
	assert_eq(str(cfg.get_value(sec, "name", "")), "Windows Desktop")
	assert_eq(str(cfg.get_value(sec, "export_filter", "")), "all_resources")
	assert_true(str(cfg.get_value(sec, "export_path", "")).ends_with(".exe"))
	assert_eq(str(cfg.get_value(sec + ".options", "binary_format/architecture", "")), "x86_64")


func test_preset_does_not_filter_out_gdble() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(PRESETS), OK)
	var sec := _windows_preset(cfg)
	var exclude := str(cfg.get_value(sec, "exclude_filter", ""))
	for pattern in exclude.split(",", false):
		var p := pattern.strip_edges()
		assert_false(
			("addons/gdble/gdble.gdextension").match(p),
			"exclude_filter %s drops the GDBLE extension" % p
		)
		assert_false(
			("addons/gdble/libgdble.windows.x86_64.dll").match(p),
			"exclude_filter %s drops the GDBLE DLL" % p
		)


func test_gdextension_names_an_existing_windows_dll() -> void:
	var ext := ConfigFile.new()
	assert_eq(ext.load(GDEXT), OK, "gdble.gdextension parses")
	for key in ["windows.release.x86_64", "windows.debug.x86_64"]:
		var lib := str(ext.get_value("libraries", key, ""))
		assert_true(lib.ends_with(".dll"), "%s points at a DLL" % key)
		assert_true(FileAccess.file_exists(lib), "%s exists: %s" % [key, lib])
	assert_eq(
		ext.get_value("configuration", "reloadable", true), false, "reloadable = false (BRIEF 4.2)"
	)
