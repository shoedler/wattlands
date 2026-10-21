extends GutTest
## The pixel import preset on an imported sprite (docs/OWNERSHIP.md W2D7, C36): a sprite PNG that
## pixelate wrote, with the .import pixelate writes, imports with mipmaps off and lossless compression.
## tests/art/fixtures/import/pixel_sprite.png started with exactly ArtPixelate.import_file_text() as
## its .import; Godot's import added the uid and dest_files.

const SPRITE: String = "res://tests/art/fixtures/import/pixel_sprite.png"


func test_the_imported_sprite_has_mipmaps_off() -> void:
	var tex: Texture2D = load(SPRITE) as Texture2D
	assert_not_null(tex)
	assert_eq(tex.get_size(), Vector2(16, 8))
	var img: Image = tex.get_image()
	assert_false(img.has_mipmaps(), "mipmaps off")
	assert_false(img.is_compressed(), "lossless, not VRAM-compressed")


func test_the_import_file_keeps_the_preset() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	assert_eq(cfg.load(ProjectSettings.globalize_path(SPRITE + ".import")), OK)
	assert_eq(cfg.get_value("remap", "importer"), "texture")
	assert_eq(cfg.get_value("params", "mipmaps/generate"), false)
	assert_eq(cfg.get_value("params", "compress/mode"), 0)
	assert_true(str(cfg.get_value("remap", "uid", "")).begins_with("uid://"), "Godot completed the file on import")


func test_imported_pixels_are_exact() -> void:
	var img: Image = (load(SPRITE) as Texture2D).get_image()
	img.convert(Image.FORMAT_RGBA8)
	assert_eq(img.get_pixel(0, 0).a8, 0)
	assert_eq(img.get_pixel(0, 2), Color("#d6d2cf"))
	assert_eq(img.get_pixel(1, 2), Color("#a33412"))
	assert_eq(img.get_pixel(3, 2), Color("#2a5aa8"))
