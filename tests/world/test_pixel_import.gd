extends GutTest
## PixelImportPreset (BRIEF 3.9 "filter off, mipmaps off"; OWNERSHIP W2D7, C36): the project
## defaults, writing and validating .import files, runtime texture checks and nearest
## filtering on CanvasItems.

var _dir: String = ""
## Every temp dir an earlier test in this file used (test_temp_dirs_are_removed checks them).
var _used_dirs: Array[String] = []


func before_each() -> void:
	_dir = Paths.make_temp_dir("wattlands_pixel_import")
	_used_dirs.append(_dir)
	Paths.set_override(_dir)


## The temp dir goes with each test (W4r2 R41, W3 QT-4): PNGs and .import files included.
func after_each() -> void:
	Paths.set_override("")
	_remove_tree(_dir)


static func _remove_tree(dir: String) -> void:
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.include_hidden = true
	for f in da.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in da.get_directories():
		_remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


func _png(name: String) -> String:
	var path := _dir.path_join(name)
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	img.save_png(path)
	return path


func test_params_hold_the_required_values() -> void:
	var p := PixelImportPreset.params()
	assert_eq(p["compress/mode"], 0, "lossless")
	assert_eq(p["mipmaps/generate"], false)
	assert_eq(p["detect_3d/compress_to"], 0, "never VRAM-compressed when seen in 3D")


func test_project_defaults_give_new_pngs_the_preset() -> void:
	assert_eq(PixelImportPreset.check_project_defaults(), PackedStringArray())


func test_write_creates_a_valid_import_file() -> void:
	var png := _png("sprite.png")
	assert_eq(PixelImportPreset.write_import_file(png), OK)
	assert_true(FileAccess.file_exists(PixelImportPreset.import_path(png)))
	assert_eq(PixelImportPreset.validate_import_file(png), PackedStringArray())
	assert_true(PixelImportPreset.is_import_ok(png))
	var cf := ConfigFile.new()
	assert_eq(cf.load(png + ".import"), OK)
	assert_eq(cf.get_value("remap", "importer"), "texture")
	assert_eq(cf.get_value("remap", "type"), "CompressedTexture2D")


func test_write_patches_and_keeps_remap() -> void:
	var png := _png("old.png")
	var cf := ConfigFile.new()
	cf.set_value("remap", "importer", "texture")
	cf.set_value("remap", "type", "CompressedTexture2D")
	cf.set_value("remap", "uid", "uid://abc123")
	cf.set_value("params", "compress/mode", 2)
	cf.set_value("params", "mipmaps/generate", true)
	cf.set_value("params", "svg/scale", 1.0)
	assert_eq(cf.save(png + ".import"), OK)
	assert_false(PixelImportPreset.is_import_ok(png))
	assert_eq(PixelImportPreset.write_import_file(png), OK)
	var back := ConfigFile.new()
	assert_eq(back.load(png + ".import"), OK)
	assert_eq(back.get_value("remap", "uid"), "uid://abc123", "uid kept")
	assert_eq(back.get_value("params", "compress/mode"), 0)
	assert_eq(back.get_value("params", "mipmaps/generate"), false)
	assert_eq(back.get_value("params", "svg/scale"), 1.0, "other params kept")
	assert_true(PixelImportPreset.is_import_ok(png))


func test_validate_reports_problems() -> void:
	var png := _png("bad.png")
	var problems := PixelImportPreset.validate_import_file(png)
	assert_eq(problems.size(), 1)
	assert_string_contains(problems[0], "no .import file")
	var cf := ConfigFile.new()
	cf.set_value("remap", "importer", "image")
	cf.set_value("params", "compress/mode", 2)
	cf.set_value("params", "detect_3d/compress_to", 1)
	cf.save(png + ".import")
	problems = PixelImportPreset.validate_import_file(png)
	var text := "\n".join(problems)
	assert_string_contains(text, "importer is 'image'")
	assert_string_contains(text, "compress/mode is 2")
	assert_string_contains(text, "missing mipmaps/generate")
	assert_string_contains(text, "recommended:")
	assert_false(PixelImportPreset.is_import_ok(png))


func test_recommended_differences_do_not_fail() -> void:
	var png := _png("rec.png")
	var cf := ConfigFile.new()
	cf.set_value("remap", "importer", "texture")
	cf.set_value("params", "compress/mode", 0)
	cf.set_value("params", "mipmaps/generate", false)
	cf.set_value("params", "detect_3d/compress_to", 1)
	cf.save(png + ".import")
	assert_eq(PixelImportPreset.validate_import_file(png).size(), 1)
	assert_true(PixelImportPreset.is_import_ok(png))


func test_an_imported_repo_png_meets_the_required_preset() -> void:
	# GUT's icon was imported with the project's texture defaults.
	assert_true(PixelImportPreset.is_import_ok("res://addons/gut/icon.png"))
	var tex: Texture2D = load("res://addons/gut/icon.png")
	assert_eq(PixelImportPreset.validate_texture(tex), PackedStringArray())


func test_validate_texture() -> void:
	var img := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	assert_eq(
		PixelImportPreset.validate_texture(ImageTexture.create_from_image(img)), PackedStringArray()
	)
	var mip := Image.create_empty(8, 8, true, Image.FORMAT_RGBA8)
	var problems := PixelImportPreset.validate_texture(ImageTexture.create_from_image(mip))
	assert_eq(problems.size(), 1)
	assert_string_contains(problems[0], "mipmaps")
	assert_eq(PixelImportPreset.validate_texture(null), PackedStringArray(["no texture"]))


func test_apply_to_sets_nearest() -> void:
	var s: Sprite2D = autofree(Sprite2D.new())
	PixelImportPreset.apply_to(s)
	assert_eq(s.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(s.texture_repeat, CanvasItem.TEXTURE_REPEAT_DISABLED)
	PixelImportPreset.apply_to(null)
	pass_test("null is ignored")


## Runs last (GUT keeps file order): no earlier test left its temp dir behind.
func test_zz_temp_dirs_are_removed() -> void:
	assert_gt(_used_dirs.size(), 1, "earlier tests used temp dirs")
	for d in _used_dirs:
		if d != _dir:
			assert_false(DirAccess.dir_exists_absolute(d), "%s was removed" % d)
