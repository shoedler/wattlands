extends GutTest
## ArtPixelate.run_game on temp project roots (BRIEF 3.10, docs/OWNERSHIP.md ART4, ART6, W2D7): only the
## selected result is used, sprites and parts are written with sprites.json and the pixel import
## preset, re-runs give the same bytes, and bad input is rejected with push_error.

const GAME: String = "fixture"
const PALETTE: Array = ["#0b0b0e", "#d6d2cf", "#a33412", "#2a5aa8", "#6fb4ff", "#f08a2c"]

var _roots: Array[String] = []


func after_each() -> void:
	ArtPixelate.import_preset_mode = ArtPixelate.IMPORT_WRITE_FILE
	for r: String in _roots:
		_remove_tree(r)
	_roots.clear()


static func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	var da: DirAccess = DirAccess.open(dir)
	if da == null:
		return
	da.include_hidden = true
	for f: String in da.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub: String in da.get_directories():
		_remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## A raw "result": a coloured block with transparent margins (or a full opaque frame).
func _raw(w: int, h: int, color: Color, opaque: bool = false) -> Image:
	var img: Image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	if opaque:
		img.fill(color)
		img.fill_rect(Rect2i(w / 4, h / 4, w / 2, h / 2), Color.BLACK)
	else:
		img.fill(Color(0, 0, 0, 0))
		img.fill_rect(Rect2i(w / 8, h / 6, w * 3 / 4, h * 2 / 3), color)
	return img


func _art() -> Dictionary:
	return {
		"palette": PALETTE,
		"style": "pixel art",
		"sprites": [
			{"id": "boat", "prompt": "boat", "size": [80, 32], "parts": {"hull": [0, 16, 80, 16], "cabin": [20, 0, 40, 16]}},
			{"id": "fish_tuna", "prompt": "tuna", "size": [44, 16], "anchor": "center"},
			{"id": "bg_sky", "prompt": "sky", "size": [120, 40], "background": "opaque"},
			{"id": "reef", "prompt": "reef", "size": [200, 10], "tile": true, "mirror": true},
		],
	}


func _entry(sprite: String, rid: String, selected: bool, status: String = "ok", background: String = "transparent") -> Dictionary:
	return {
		"sprite": sprite, "request_id": rid, "endpoint": "openai/gpt-image-2.5/sunburst/text-to-image",
		"input": {"background": background}, "status": status, "selected": selected,
		"cache": ".art_cache/%s/%s.png" % [GAME, rid],
	}


## A root with art.json, a manifest and raw results for every sprite; returns the root.
func _make_root(art: Dictionary = _art(), with_raw: bool = true) -> String:
	var root: String = Paths.make_temp_dir("wattlands_art_run")
	_roots.append(root)
	var game_dir: String = root.path_join("assets").path_join(GAME)
	_write_text(game_dir.path_join("art.json"), JSON.stringify(art, "  "))
	var reqs: Array = [
		_entry("boat", "r-boat", true),
		_entry("fish_tuna", "r-tuna", true),
		_entry("bg_sky", "r-sky", true, "ok", "opaque"),
		_entry("reef", "r-reef", true),
	]
	_write_text(game_dir.path_join("art_manifest.json"), JSON.stringify({"version": 1, "game": GAME, "requests": reqs}, "  "))
	if with_raw:
		var cache: String = root.path_join(".art_cache").path_join(GAME)
		DirAccess.make_dir_recursive_absolute(cache)
		_raw(1600, 640, Color("#a33412")).save_png(cache.path_join("r-boat.png"))
		_raw(1408, 512, Color("#2a5aa8")).save_png(cache.path_join("r-tuna.png"))
		_raw(1536, 512, Color("#6fb4ff"), true).save_png(cache.path_join("r-sky.png"))
		_raw(1776, 592, Color("#f08a2c")).save_png(cache.path_join("r-reef.png"))
	return root


func _sprites_dir(root: String) -> String:
	return root.path_join("assets").path_join(GAME).path_join("sprites")


func _load(path: String) -> Image:
	var img: Image = Image.new()
	assert_eq(img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)), OK, path)
	return img


func _assert_palette_only(img: Image) -> void:
	var allowed: Dictionary = {}
	for h: Variant in PALETTE:
		allowed[Color(str(h)).to_rgba32()] = true
	var bad: int = 0
	for y: int in img.get_height():
		for x: int in img.get_width():
			var c: Color = img.get_pixel(x, y)
			if c.a8 == 0:
				if c.to_rgba32() != 0:
					bad += 1
			elif c.a8 != 255 or not allowed.has(c.to_rgba32()):
				bad += 1
	assert_eq(bad, 0)


func test_writes_every_sprite_its_parts_and_the_index() -> void:
	var root: String = _make_root()
	var report: Dictionary = ArtPixelate.run_game(root, GAME)
	assert_true(report["ok"], str(report["errors"]))
	assert_eq(report["written"], [
		"assets/fixture/sprites/boat.png",
		"assets/fixture/sprites/boat__cabin.png",
		"assets/fixture/sprites/boat__hull.png",
		"assets/fixture/sprites/fish_tuna.png",
		"assets/fixture/sprites/bg_sky.png",
		"assets/fixture/sprites/reef.png",
	])
	var dir: String = _sprites_dir(root)
	var sizes: Dictionary = {"boat": Vector2i(80, 32), "fish_tuna": Vector2i(44, 16), "bg_sky": Vector2i(120, 40), "reef": Vector2i(200, 10)}
	for id: String in sizes.keys():
		var img: Image = _load(dir.path_join(id + ".png"))
		assert_eq(img.get_size(), sizes[id], id)
		_assert_palette_only(img)
	var boat: Image = _load(dir.path_join("boat.png"))
	assert_eq(_load(dir.path_join("boat__hull.png")).get_data(), boat.get_region(Rect2i(0, 16, 80, 16)).get_data())
	assert_eq(_load(dir.path_join("boat__cabin.png")).get_data(), boat.get_region(Rect2i(20, 0, 40, 16)).get_data())
	# The transparent boat is fitted bottom-centre: its content touches the bottom edge.
	assert_eq(ArtPixelate.trim_rect(boat, 255).end.y, 32)
	# The opaque sky covers every pixel.
	assert_eq(ArtPixelate.trim_rect(_load(dir.path_join("bg_sky.png")), 255), Rect2i(0, 0, 120, 40))
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("sprites.json")))
	assert_eq(index["game"], GAME)
	var sprites: Dictionary = index["sprites"]
	assert_eq(sprites.keys().size(), 4)
	var b: Dictionary = sprites["boat"]
	assert_eq(b["file"], "boat.png")
	assert_eq(b["size"], [80.0, 32.0])
	assert_eq(b["anchor"], [40.0, 32.0])
	assert_eq((b["parts"] as Dictionary)["hull"], {"file": "boat__hull.png", "rect": [0.0, 16.0, 80.0, 16.0]})
	assert_eq((b["source"] as Dictionary)["request_id"], "r-boat")
	assert_eq((sprites["fish_tuna"] as Dictionary)["anchor"], [22.0, 8.0])
	assert_eq((sprites["reef"] as Dictionary)["tile"], true)


func test_uses_only_the_selected_result() -> void:
	var root: String = _make_root()
	var cache: String = root.path_join(".art_cache").path_join(GAME)
	_raw(1408, 512, Color("#d6d2cf")).save_png(cache.path_join("r-tuna-2.png"))
	var mpath: String = root.path_join("assets").path_join(GAME).path_join("art_manifest.json")
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(mpath))
	var reqs: Array = m["requests"]
	reqs.append(_entry("fish_tuna", "r-tuna-2", false))
	_write_text(mpath, JSON.stringify(m))
	assert_true(ArtPixelate.run_game(root, GAME, PackedStringArray(["fish_tuna"]))["ok"])
	var tuna: Image = _load(_sprites_dir(root).path_join("fish_tuna.png"))
	assert_eq(tuna.get_pixel(22, 8), Color("#2a5aa8"), "the selected (blue) result, not the newer unselected one")
	# Select the other one: the sprite follows the selection.
	(reqs[1] as Dictionary)["selected"] = false
	(reqs[4] as Dictionary)["selected"] = true
	_write_text(mpath, JSON.stringify(m))
	assert_true(ArtPixelate.run_game(root, GAME, PackedStringArray(["fish_tuna"]))["ok"])
	tuna = _load(_sprites_dir(root).path_join("fish_tuna.png"))
	assert_eq(tuna.get_pixel(22, 8), Color("#d6d2cf"))


func test_reruns_are_byte_identical() -> void:
	var root: String = _make_root()
	assert_true(ArtPixelate.run_game(root, GAME)["ok"])
	var dir: String = _sprites_dir(root)
	var first: Dictionary = {}
	for f: String in DirAccess.get_files_at(dir):
		first[f] = FileAccess.get_file_as_bytes(dir.path_join(f))
	assert_true(ArtPixelate.run_game(root, GAME)["ok"])
	var files: PackedStringArray = DirAccess.get_files_at(dir)
	assert_eq(files.size(), first.size())
	for f: String in files:
		assert_eq(FileAccess.get_file_as_bytes(dir.path_join(f)), first[f], f)


func test_only_limits_the_sprites_and_keeps_the_index_whole() -> void:
	var root: String = _make_root()
	assert_true(ArtPixelate.run_game(root, GAME)["ok"])
	var report: Dictionary = ArtPixelate.run_game(root, GAME, PackedStringArray(["reef"]))
	assert_eq(report["written"], ["assets/fixture/sprites/reef.png"])
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_sprites_dir(root).path_join("sprites.json")))
	assert_eq((index["sprites"] as Dictionary).size(), 4)


func test_sprites_without_a_selected_result_are_skipped_with_a_warning() -> void:
	var root: String = _make_root()
	var mpath: String = root.path_join("assets").path_join(GAME).path_join("art_manifest.json")
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(mpath))
	((m["requests"] as Array)[3] as Dictionary)["selected"] = false
	((m["requests"] as Array)[2] as Dictionary)["status"] = "download_failed"
	_write_text(mpath, JSON.stringify(m))
	var report: Dictionary = ArtPixelate.run_game(root, GAME)
	assert_true(report["ok"])
	assert_eq(report["skipped"], ["bg_sky", "reef"])
	assert_push_warning("bg_sky: no selected result")
	assert_push_warning("reef: no selected result")
	assert_false(FileAccess.file_exists(_sprites_dir(root).path_join("reef.png")))


func test_import_preset_files() -> void:
	var root: String = _make_root()
	assert_true(ArtPixelate.run_game(root, GAME, PackedStringArray(["boat"]))["ok"])
	var imp: String = _sprites_dir(root).path_join("boat.png.import")
	assert_true(FileAccess.file_exists(imp))
	assert_true(FileAccess.file_exists(_sprites_dir(root).path_join("boat__hull.png.import")))
	var cfg: ConfigFile = ConfigFile.new()
	assert_eq(cfg.load(imp), OK)
	assert_eq(cfg.get_value("params", "mipmaps/generate"), false)
	assert_eq(cfg.get_value("params", "compress/mode"), 0)
	# An existing .import (as Godot rewrote it, with a uid) keeps its uid; wrong preset keys are fixed.
	cfg.set_value("remap", "uid", "uid://abc123")
	cfg.set_value("params", "mipmaps/generate", true)
	cfg.save(imp)
	assert_true(ArtPixelate.run_game(root, GAME, PackedStringArray(["boat"]))["ok"])
	var after: ConfigFile = ConfigFile.new()
	after.load(imp)
	assert_eq(after.get_value("remap", "uid"), "uid://abc123")
	assert_eq(after.get_value("params", "mipmaps/generate"), false)


func test_project_defaults_mode_writes_no_import_files() -> void:
	ArtPixelate.import_preset_mode = ArtPixelate.IMPORT_PROJECT_DEFAULTS
	var root: String = _make_root()
	assert_true(ArtPixelate.run_game(root, GAME, PackedStringArray(["boat"]))["ok"])
	assert_true(FileAccess.file_exists(_sprites_dir(root).path_join("boat.png")))
	assert_false(FileAccess.file_exists(_sprites_dir(root).path_join("boat.png.import")))


func test_a_missing_raw_result_is_an_error() -> void:
	var root: String = _make_root(_art(), false)
	var report: Dictionary = ArtPixelate.run_game(root, GAME, PackedStringArray(["boat"]))
	assert_false(report["ok"])
	assert_push_error("has no raw image")


func test_an_invalid_art_json_is_an_error() -> void:
	var art: Dictionary = _art()
	art["palette"] = ["#nothex"]
	var root: String = _make_root(art)
	var report: Dictionary = ArtPixelate.run_game(root, GAME)
	assert_false(report["ok"])
	assert_push_error("palette[0]")


func test_a_missing_manifest_or_art_json_is_an_error() -> void:
	var root: String = _make_root()
	DirAccess.remove_absolute(root.path_join("assets").path_join(GAME).path_join("art_manifest.json"))
	assert_false(ArtPixelate.run_game(root, GAME)["ok"])
	assert_push_error("run node tools/art/generate.mjs")
	assert_false(ArtPixelate.run_game(root, "nogame")["ok"])
	assert_push_error("art.json is missing")


func test_an_unknown_only_id_is_an_error() -> void:
	var root: String = _make_root()
	assert_false(ArtPixelate.run_game(root, GAME, PackedStringArray(["ghost"]))["ok"])
	assert_push_error("no sprite \"ghost\"")


func test_a_background_mismatch_is_a_warning() -> void:
	var art: Dictionary = _art()
	((art["sprites"] as Array)[1] as Dictionary)["background"] = "opaque"
	var root: String = _make_root(art)
	assert_true(ArtPixelate.run_game(root, GAME, PackedStringArray(["fish_tuna"]))["ok"])
	assert_push_warning("generated with background transparent")
