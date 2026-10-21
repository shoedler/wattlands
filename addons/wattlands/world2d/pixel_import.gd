class_name PixelImportPreset
extends RefCounted
## The pixel import preset for pixel-art sprites (BRIEF 3.9 "filter off, mipmaps off",
## 3.10; OWNERSHIP C36). Static helpers; nothing here runs on its own.
##
## The preset has two halves:
## 1. Import (per PNG, in its `.import` file): lossless compression (`compress/mode` 0), no
##    mipmaps (`mipmaps/generate` false), no VRAM recompression when a texture shows up in
##    3D (`detect_3d/compress_to` 0) and no size limit. The project's importer defaults
##    (`[importer_defaults] texture` in project.godot) already give every new PNG the first
##    two, so `tools/art/pixelate.gd` writes plain PNGs and needs no hand-written `.import`
##    files; `check_project_defaults()` verifies that, `validate_import_file()` checks a
##    sprite's `.import` after Godot imported it, and `write_import_file()` writes or patches
##    one (for a sprite folder outside the defaults, or to pin the preset).
## 2. Runtime: Godot 4 filters per CanvasItem, not per texture. PixelViewport makes nearest
##    the default for everything in a game view; `apply_to(item)` sets nearest and no repeat
##    on a CanvasItem outside it (menus, picker cards, the HUD).
## [codeblock]
## var problems := PixelImportPreset.validate_import_file("res://assets/tank/sprites/hull_citadel.png")
## assert(problems.is_empty(), "\n".join(problems))
## PixelImportPreset.apply_to($PickerCard)
## [/codeblock]

## [params] values the preset requires in a sprite's .import file.
const REQUIRED_PARAMS: Dictionary = {
	"compress/mode": 0,
	"mipmaps/generate": false,
}
## Further [params] values write_import_file() sets; validate_import_file() reports a
## differing value as a problem prefixed "recommended:".
const RECOMMENDED_PARAMS: Dictionary = {
	"detect_3d/compress_to": 0,
	"process/size_limit": 0,
	"process/premult_alpha": false,
	"process/fix_alpha_border": true,
	"roughness/mode": 0,
}
const IMPORTER := "texture"
const RESOURCE_TYPE := "CompressedTexture2D"


## Every [params] value the preset writes (required and recommended).
static func params() -> Dictionary:
	var out := REQUIRED_PARAMS.duplicate()
	out.merge(RECOMMENDED_PARAMS)
	return out


## The .import path for an image path.
static func import_path(image_path: String) -> String:
	return image_path + ".import"


## Problems with the .import file of `image_path` (empty = the preset holds). Missing file,
## wrong importer, a required value that differs, or ("recommended: ...") a recommended one.
static func validate_import_file(image_path: String) -> PackedStringArray:
	var problems := PackedStringArray()
	var path := import_path(image_path)
	if not FileAccess.file_exists(path):
		problems.append("%s: no .import file (run tools/godot.sh --headless --path . --import)" % path)
		return problems
	var cf := ConfigFile.new()
	var err := cf.load(path)
	if err != OK:
		problems.append("%s: unreadable (%s)" % [path, error_string(err)])
		return problems
	var importer := str(cf.get_value("remap", "importer", ""))
	if importer != IMPORTER:
		problems.append("%s: importer is '%s', not '%s'" % [path, importer, IMPORTER])
	for key: String in REQUIRED_PARAMS:
		if not cf.has_section_key("params", key):
			problems.append("%s: missing %s (want %s)" % [path, key, REQUIRED_PARAMS[key]])
		elif not _same(cf.get_value("params", key), REQUIRED_PARAMS[key]):
			problems.append("%s: %s is %s (want %s)" % [path, key, cf.get_value("params", key), REQUIRED_PARAMS[key]])
	for key: String in RECOMMENDED_PARAMS:
		if cf.has_section_key("params", key) and not _same(cf.get_value("params", key), RECOMMENDED_PARAMS[key]):
			problems.append("recommended: %s: %s is %s (want %s)" % [path, key, cf.get_value("params", key), RECOMMENDED_PARAMS[key]])
	return problems


## True when the required half of the preset holds (recommended differences are ignored).
static func is_import_ok(image_path: String) -> bool:
	for p: String in validate_import_file(image_path):
		if not p.begins_with("recommended:"):
			return false
	return true


## Write the preset into the .import file of `image_path`: patch [params] of an existing
## file (keeping its uid and remap), or create a minimal one that Godot completes on the next
## import (it reads [params] from the file). Returns OK or the save error.
static func write_import_file(image_path: String) -> Error:
	var path := import_path(image_path)
	var cf := ConfigFile.new()
	if FileAccess.file_exists(path):
		var err := cf.load(path)
		if err != OK:
			push_error("PixelImportPreset: cannot read %s (%s)" % [path, error_string(err)])
			return err
	else:
		cf.set_value("remap", "importer", IMPORTER)
		cf.set_value("remap", "type", RESOURCE_TYPE)
	var all := params()
	for key: String in all:
		cf.set_value("params", key, all[key])
	return cf.save(path)


## Problems with a loaded texture (empty = fine): mipmaps present, or a lossy/VRAM-compressed
## format. Works headless.
static func validate_texture(texture: Texture2D) -> PackedStringArray:
	var problems := PackedStringArray()
	if texture == null:
		problems.append("no texture")
		return problems
	var img := texture.get_image()
	if img == null:
		problems.append("%s: no image data" % texture.resource_path)
		return problems
	if img.has_mipmaps():
		problems.append("%s: has mipmaps" % texture.resource_path)
	if img.is_compressed():
		problems.append("%s: compressed format %d" % [texture.resource_path, img.get_format()])
	return problems


## Runtime half of the preset: nearest filtering and no repeat on `item` (and, through
## the default inherit mode, on its children).
static func apply_to(item: CanvasItem) -> void:
	if item == null:
		return
	item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	item.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED


## Problems with the project's texture importer defaults (empty = new PNGs import with the
## required half of the preset).
static func check_project_defaults() -> PackedStringArray:
	var problems := PackedStringArray()
	var key := "importer_defaults/texture"
	if not ProjectSettings.has_setting(key):
		problems.append("project.godot has no [importer_defaults] texture entry")
		return problems
	var d: Variant = ProjectSettings.get_setting(key)
	if not (d is Dictionary):
		problems.append("importer_defaults/texture is not a Dictionary")
		return problems
	var defaults: Dictionary = d
	for k: String in REQUIRED_PARAMS:
		if not defaults.has(k):
			problems.append("importer_defaults/texture lacks %s" % k)
		elif not _same(defaults[k], REQUIRED_PARAMS[k]):
			problems.append("importer_defaults/texture %s is %s (want %s)" % [k, defaults[k], REQUIRED_PARAMS[k]])
	return problems


static func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	if a is bool and (b is int or b is float):
		return bool(a) == (float(b) != 0.0)
	if b is bool and (a is int or a is float):
		return bool(b) == (float(a) != 0.0)
	if typeof(a) != typeof(b):
		return false
	return a == b
