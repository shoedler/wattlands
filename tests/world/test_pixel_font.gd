extends GutTest
## PixelFont.hang: from a font of its own in a temp dir, so it never touches a game's shared face.

const CELL := 9
const GLYPH_A := 65
const SPACE := 32

var _dir: String = ""


func before_each() -> void:
	_dir = Paths.make_temp_dir("wl_pixel_font")


func after_each() -> void:
	for f in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))
	DirAccess.remove_absolute(_dir)


func _font_path(file: String) -> String:
	var ff := FontFile.new()
	ff.set_glyph_offset(0, Vector2i(CELL, 0), GLYPH_A, Vector2(0, -4))
	ff.set_glyph_advance(0, CELL, GLYPH_A, Vector2(6, 0))
	ff.set_glyph_offset(0, Vector2i(CELL, 0), SPACE, Vector2(0, -4))
	ff.set_glyph_advance(0, CELL, SPACE, Vector2(6, 0))
	var path := _dir.path_join(file)
	assert_eq(ResourceSaver.save(ff, path), OK, "the temp font saved")
	return path


func test_every_glyph_hangs_by_the_cap_and_the_space_narrows() -> void:
	var ff := PixelFont.hang(_font_path("hung.res"), 7, 3) as FontFile
	assert_not_null(ff)
	var sz := Vector2i(CELL, 0)
	assert_eq(ff.get_glyph_offset(0, sz, GLYPH_A), Vector2(0, -7))
	assert_eq(ff.get_glyph_offset(0, sz, SPACE), Vector2(0, -7))
	assert_eq(ff.get_glyph_advance(0, CELL, SPACE), Vector2(3, 0))
	assert_eq(ff.get_glyph_advance(0, CELL, GLYPH_A), Vector2(6, 0), "only the space narrows")


func test_a_path_hangs_once_so_the_first_numbers_stand() -> void:
	var path := _font_path("once.res")
	var first := PixelFont.hang(path, 7, 3) as FontFile
	var again := PixelFont.hang(path, 9, 4) as FontFile
	assert_same(again, first, "one Font per path")
	assert_eq(first.get_glyph_offset(0, Vector2i(CELL, 0), GLYPH_A), Vector2(0, -7))
	assert_eq(first.get_glyph_advance(0, CELL, SPACE), Vector2(3, 0))


func test_a_font_that_is_not_a_font_file_comes_back_as_loaded() -> void:
	var path := _dir.path_join("variation.res")
	assert_eq(ResourceSaver.save(FontVariation.new(), path), OK)
	assert_true(PixelFont.hang(path, 7, 3) is FontVariation)


func test_a_path_without_a_font_gives_null() -> void:
	var path := _dir.path_join("not_a_font.res")
	assert_eq(ResourceSaver.save(Gradient.new(), path), OK)
	assert_null(PixelFont.hang(path, 7, 3))
