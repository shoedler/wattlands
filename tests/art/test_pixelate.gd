extends GutTest
## ArtPixelate's pure functions (BRIEF 3.10, docs/OWNERSHIP.md ART6): trimming, fit with align, cover
## and centre-crop, tile and mirror, area averaging, alpha thresholding, Oklab quantization to the
## palette only, ordered dithering, parts, anchors, art.json checks and determinism.

const PALETTE: Array = ["#000000", "#ffffff", "#ff0000", "#00ff00", "#0000ff", "#808080"]
## A sprite pixelate wrote, committed with the .import pixelate writes (ArtPixelate.import_file_text());
## Godot's import added the uid and dest_files.
const IMPORTED_SPRITE: String = "res://tests/art/fixtures/import/pixel_sprite.png"


func _img(w: int, h: int, c: Color = Color(0, 0, 0, 0)) -> Image:
	var img: Image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img


func _spec(w: int, h: int, extra: Dictionary = {}) -> Dictionary:
	var spec: Dictionary = {
		"size": Vector2i(w, h),
		"background": "transparent",
		"align": "bottom_center",
		"tile": false,
		"mirror": false,
		"dither": "none",
	}
	spec.merge(extra, true)
	return spec


func _palette() -> ArtPixelate.Palette:
	return ArtPixelate.make_palette(PALETTE)


func _opaque_rect(img: Image) -> Rect2i:
	return ArtPixelate.trim_rect(img, 255)


func _assert_palette_only(img: Image, palette: Array) -> void:
	var allowed: Dictionary = {}
	for h: Variant in palette:
		allowed[Color(str(h)).to_rgba32()] = true
	var bad: int = 0
	for y: int in img.get_height():
		for x: int in img.get_width():
			var c: Color = img.get_pixel(x, y)
			var a: int = c.a8
			if a == 0:
				if c.r8 != 0 or c.g8 != 0 or c.b8 != 0:
					bad += 1
			elif a != 255 or not allowed.has(c.to_rgba32()):
				bad += 1
	assert_eq(bad, 0, "every pixel is a palette color at alpha 255 or fully transparent")


# ---------------------------------------------------------------- colour


func test_oklab_reference_values() -> void:
	var white: Vector3 = ArtPixelate.rgb8_to_oklab(255, 255, 255)
	assert_almost_eq(white.x, 1.0, 0.001)
	assert_almost_eq(white.y, 0.0, 0.001)
	assert_almost_eq(white.z, 0.0, 0.001)
	assert_almost_eq(ArtPixelate.rgb8_to_oklab(0, 0, 0).x, 0.0, 0.0001)
	var red: Vector3 = ArtPixelate.rgb8_to_oklab(255, 0, 0)
	assert_almost_eq(red.x, 0.62796, 0.001)
	assert_almost_eq(red.y, 0.22486, 0.001)
	assert_almost_eq(red.z, 0.12585, 0.001)
	var blue: Vector3 = ArtPixelate.rgb8_to_oklab(0, 0, 255)
	assert_almost_eq(blue.x, 0.45201, 0.001)
	assert_almost_eq(blue.z, -0.31153, 0.001)


func test_palette_nearest_is_the_oklab_nearest() -> void:
	var p: ArtPixelate.Palette = _palette()
	assert_eq(p.size(), 6)
	assert_eq(p.nearest(0xfafafa), 1)
	assert_eq(p.nearest(0xc81e1e), 2)
	assert_eq(p.nearest(0x7a7a7a), 5)
	assert_eq(p.nearest(0x101010), 0)
	# Brute force over a grid agrees with the cached lookup.
	for r: int in range(0, 256, 51):
		for g: int in range(0, 256, 51):
			for b: int in range(0, 256, 51):
				var lab: Vector3 = ArtPixelate.rgb8_to_oklab(r, g, b)
				var best: int = 0
				for i: int in p.lab.size():
					if lab.distance_squared_to(p.lab[i]) < lab.distance_squared_to(p.lab[best]):
						best = i
				assert_eq(p.nearest((r << 16) | (g << 8) | b), best)


func test_palette_ties_go_to_the_lower_index() -> void:
	var p: ArtPixelate.Palette = ArtPixelate.make_palette(["#123456", "#123456"])
	assert_eq(p.nearest(0x123456), 0)


func test_oklab_differs_from_rgb_distance() -> void:
	# A dark saturated blue: RGB distance picks black, Oklab (perceptual) picks blue.
	var p: ArtPixelate.Palette = ArtPixelate.make_palette(["#000000", "#0000ff"])
	assert_eq(p.nearest(0x00007f), 1)


# ---------------------------------------------------------------- trimming and geometry


func test_trim_rect_finds_the_content_and_ignores_faint_alpha() -> void:
	var img: Image = _img(20, 10)
	img.fill_rect(Rect2i(5, 2, 6, 4), Color.RED)
	img.set_pixel(0, 0, Color(1, 1, 1, 10.0 / 255.0))
	assert_eq(ArtPixelate.trim_rect(img), Rect2i(5, 2, 6, 4))
	assert_eq(ArtPixelate.trim_rect(_img(4, 4)), Rect2i())


func test_point_fractions_and_anchors() -> void:
	assert_eq(ArtPixelate.point_fraction("top_left"), Vector2(0, 0))
	assert_eq(ArtPixelate.point_fraction("bottom_center"), Vector2(0.5, 1))
	assert_eq(ArtPixelate.point_fraction("center"), Vector2(0.5, 0.5))
	assert_eq(ArtPixelate.point_fraction("center_right"), Vector2(1, 0.5))
	assert_eq(ArtPixelate.anchor_point("bottom_center", Vector2i(80, 32)), Vector2(40, 32))
	assert_eq(ArtPixelate.anchor_point("top_right", Vector2i(80, 32)), Vector2(80, 0))
	assert_eq(ArtPixelate.anchor_point([12, 7], Vector2i(80, 32)), Vector2(12, 7))


func test_fit_keeps_the_aspect_and_pads_toward_align() -> void:
	# A 4:1 block with margins, fitted into 40x40: 40x10 of content.
	var wide: Image = _img(600, 300)
	wide.fill_rect(Rect2i(100, 100, 400, 100), Color.RED)
	var expect: Dictionary = {
		"bottom_center": Rect2i(0, 30, 40, 10),
		"top_left": Rect2i(0, 0, 40, 10),
		"center": Rect2i(0, 15, 40, 10),
		"center_left": Rect2i(0, 15, 40, 10),
	}
	for align: String in expect.keys():
		var out: Image = ArtPixelate.process_sprite(
			wide, _spec(40, 40, {"align": align}), _palette()
		)
		assert_eq(_opaque_rect(out), expect[align], align)
	# A 1:4 block: 10x40 of content, placed by the horizontal part of align.
	var tall: Image = _img(300, 600)
	tall.fill_rect(Rect2i(100, 100, 100, 400), Color.BLUE)
	var expect_h: Dictionary = {
		"bottom_left": Rect2i(0, 0, 10, 40),
		"bottom_center": Rect2i(15, 0, 10, 40),
		"top_right": Rect2i(30, 0, 10, 40),
	}
	for align: String in expect_h.keys():
		var out: Image = ArtPixelate.process_sprite(
			tall, _spec(40, 40, {"align": align}), _palette()
		)
		assert_eq(_opaque_rect(out), expect_h[align], align)


func test_fit_never_stretches() -> void:
	# 3:1 content into a square: the content stays 3:1 (64 x 21.3), never 64 x 64.
	var img: Image = _img(500, 500)
	img.fill_rect(Rect2i(50, 200, 300, 100), Color.GREEN)
	var out: Image = ArtPixelate.process_sprite(img, _spec(64, 64), _palette())
	var r: Rect2i = _opaque_rect(out)
	assert_eq(r.size.x, 64)
	assert_between(r.size.y, 21, 22)
	assert_eq(r.end.y, 64, "bottom aligned")
	# A sprite already at the right aspect fills the whole size.
	var exact: Image = _img(320, 160)
	exact.fill_rect(Rect2i(10, 10, 300, 150), Color.GREEN)
	assert_eq(
		_opaque_rect(ArtPixelate.process_sprite(exact, _spec(32, 16), _palette())),
		Rect2i(0, 0, 32, 16)
	)


func test_fit_mapping_numbers() -> void:
	var m: Dictionary = ArtPixelate.fit_mapping(
		Rect2i(100, 50, 400, 100), Vector2i(40, 40), "bottom_center"
	)
	assert_almost_eq(float(m["scale"]), 0.1, 1e-9)
	assert_eq(m["content"], Rect2(0, 30, 40, 10))
	assert_eq(m["origin"], Vector2(100, 50 - 30 / 0.1))


func test_cover_scales_to_cover_and_crops_the_centre() -> void:
	# Three vertical stripes, 3:1, into a square: only the middle stripe remains.
	var img: Image = _img(300, 100, Color.RED)
	img.fill_rect(Rect2i(100, 0, 100, 100), Color.GREEN)
	img.fill_rect(Rect2i(200, 0, 100, 100), Color.BLUE)
	var out: Image = ArtPixelate.process_sprite(
		img, _spec(10, 10, {"background": "opaque"}), _palette()
	)
	assert_eq(out.get_size(), Vector2i(10, 10))
	for y: int in 10:
		for x: int in 10:
			assert_eq(out.get_pixel(x, y), Color.GREEN)
	# Bands stacked vertically, 1:3, into a square: the middle band.
	var tall: Image = _img(100, 300, Color.RED)
	tall.fill_rect(Rect2i(0, 100, 100, 100), Color.WHITE)
	var out2: Image = ArtPixelate.process_sprite(
		tall, _spec(8, 8, {"background": "opaque"}), _palette()
	)
	assert_eq(out2.get_pixel(4, 0), Color.WHITE)
	assert_eq(out2.get_pixel(4, 7), Color.WHITE)


func test_cover_keeps_the_aspect() -> void:
	var img: Image = _img(200, 100, Color.WHITE)
	img.fill_rect(Rect2i(50, 25, 100, 50), Color.BLACK)
	var out: Image = ArtPixelate.process_sprite(
		img, _spec(40, 20, {"background": "opaque"}), _palette()
	)
	var black: Rect2i = Rect2i()
	for y: int in 20:
		for x: int in 40:
			if out.get_pixel(x, y) == Color.BLACK:
				black = (
					Rect2i(x, y, 1, 1)
					if black.size == Vector2i.ZERO
					else black.merge(Rect2i(x, y, 1, 1))
				)
	assert_eq(black, Rect2i(10, 5, 20, 10))


func test_tile_repeats_across_the_width() -> void:
	var seg: Image = _img(30, 10, Color.RED)
	seg.fill_rect(Rect2i(15, 0, 15, 10), Color.GREEN)
	var out: Image = ArtPixelate.process_sprite(
		seg, _spec(30, 5, {"background": "opaque", "tile": true}), _palette()
	)
	assert_eq(out.get_size(), Vector2i(30, 5))
	# Scaled to height 5 the segment is 15 px wide: red 0-7, green 8-14, red 15-22, green 23-29.
	assert_eq(out.get_pixel(2, 2), Color.RED)
	assert_eq(out.get_pixel(11, 2), Color.GREEN)
	assert_eq(out.get_pixel(17, 2), Color.RED)
	assert_eq(out.get_pixel(26, 2), Color.GREEN)


func test_tile_mirror_alternates_flipped_copies() -> void:
	var seg: Image = _img(30, 10, Color.RED)
	seg.fill_rect(Rect2i(15, 0, 15, 10), Color.GREEN)
	var out: Image = ArtPixelate.process_sprite(
		seg, _spec(45, 5, {"background": "opaque", "tile": true, "mirror": true}), _palette()
	)
	# Copies: normal (red, green), flipped (green, red), normal (red, green): edges match.
	assert_eq(out.get_pixel(2, 2), Color.RED)
	assert_eq(out.get_pixel(11, 2), Color.GREEN)
	assert_eq(out.get_pixel(17, 2), Color.GREEN)
	assert_eq(out.get_pixel(26, 2), Color.RED)
	assert_eq(out.get_pixel(32, 2), Color.RED)
	assert_eq(out.get_pixel(41, 2), Color.GREEN)


func test_tile_trims_then_scales_to_the_sprite_height() -> void:
	# Content 20x10 inside transparent margins; the tile is scaled by the trimmed height.
	var img: Image = _img(40, 40)
	img.fill_rect(Rect2i(10, 15, 20, 10), Color.BLUE)
	var out: Image = ArtPixelate.process_sprite(img, _spec(50, 5, {"tile": true}), _palette())
	assert_eq(
		_opaque_rect(out), Rect2i(0, 0, 50, 5), "trimmed segments butt together across the width"
	)


func test_tile_strip_width() -> void:
	var img: Image = _img(30, 10, Color.RED)
	var strip: Image = ArtPixelate.build_tile_strip(
		img, Rect2i(0, 0, 30, 10), Vector2i(100, 5), false
	)
	assert_eq(strip.get_size(), Vector2i(200, 10))


# ---------------------------------------------------------------- area averaging and quantization


func test_area_averaging_by_exact_coverage() -> void:
	var checker: Image = _img(2, 2, Color.BLACK)
	checker.set_pixel(1, 0, Color.WHITE)
	checker.set_pixel(0, 1, Color.WHITE)
	var out: PackedFloat32Array = ArtPixelate.area_resample(
		checker, Vector2.ZERO, 0.5, Rect2(0, 0, 2, 2), Vector2i(1, 1)
	)
	assert_almost_eq(out[0], 127.5, 0.001)
	assert_almost_eq(out[3], 1.0, 0.0001)
	# Clipping: a 1-row source scaled by 2/3 covers only 2/3 of the output row's height.
	var thin: Image = _img(3, 1, Color.WHITE)
	var o3: PackedFloat32Array = ArtPixelate.area_resample(
		thin, Vector2.ZERO, 2.0 / 3.0, Rect2(0, 0, 3, 1), Vector2i(2, 1)
	)
	assert_almost_eq(o3[3], 2.0 / 3.0, 0.0001)
	# Three source columns into two: [0, 1.5) and [1.5, 3) (three rows into two likewise).
	var row: Image = _img(3, 3, Color(1, 0, 0))
	row.fill_rect(Rect2i(1, 0, 2, 3), Color(0, 0, 1))
	var o2: PackedFloat32Array = ArtPixelate.area_resample(
		row, Vector2.ZERO, 2.0 / 3.0, Rect2(0, 0, 3, 3), Vector2i(2, 2)
	)
	assert_almost_eq(o2[0], 255.0 * 2.0 / 3.0, 0.01, "red: 1 of 1.5")
	assert_almost_eq(o2[2], 255.0 / 3.0, 0.01, "blue: 0.5 of 1.5")
	assert_almost_eq(o2[4], 0.0, 0.01)
	assert_almost_eq(o2[6], 255.0, 0.01)


func test_area_averaging_is_premultiplied() -> void:
	# White next to fully transparent black averages to half-transparent white, not grey.
	var img: Image = _img(2, 2)
	img.fill_rect(Rect2i(0, 0, 1, 2), Color.WHITE)
	var out: PackedFloat32Array = ArtPixelate.area_resample(
		img, Vector2.ZERO, 0.5, Rect2(0, 0, 2, 2), Vector2i(1, 1)
	)
	assert_almost_eq(out[3], 0.5, 0.0001)
	assert_almost_eq(out[0] / out[3], 255.0, 0.01)
	var q: Image = ArtPixelate.quantize(out, Vector2i(1, 1), _palette())
	assert_eq(q.get_pixel(0, 0), Color.WHITE, "at the 0.5 threshold it becomes opaque white")


func test_alpha_is_thresholded_to_opaque_or_transparent() -> void:
	var pm: PackedFloat32Array = PackedFloat32Array(
		[0, 0, 0, 0.0, 120.0 * 0.49, 0, 0, 0.49, 255.0 * 0.5, 0, 0, 0.5, 200.0, 200.0, 200.0, 1.0]
	)
	var q: Image = ArtPixelate.quantize(pm, Vector2i(4, 1), _palette())
	assert_eq(q.get_pixel(0, 0).a8, 0)
	assert_eq(q.get_pixel(1, 0).a8, 0)
	assert_eq(q.get_pixel(1, 0).r8, 0, "transparent pixels are (0, 0, 0, 0)")
	assert_eq(q.get_pixel(2, 0), Color.RED)
	assert_eq(q.get_pixel(3, 0).a8, 255)


func test_every_output_pixel_is_a_palette_color_or_transparent() -> void:
	var rng: RandomNumberGenerator = SeededRng.make(1234)
	var img: Image = _img(300, 200)
	for y: int in 200:
		for x: int in 300:
			img.set_pixel(
				x,
				y,
				Color8(
					rng.randi_range(0, 255),
					rng.randi_range(0, 255),
					rng.randi_range(0, 255),
					rng.randi_range(0, 255)
				)
			)
	for spec: Dictionary in [
		_spec(37, 23),
		_spec(37, 23, {"background": "opaque"}),
		_spec(90, 7, {"tile": true, "mirror": true}),
		_spec(37, 23, {"dither": "ordered"})
	]:
		_assert_palette_only(ArtPixelate.process_sprite(img, spec, _palette()), PALETTE)


func test_ordered_dither_mixes_palette_colors_and_none_does_not() -> void:
	# Mid grey (L about 0.5) between black and white.
	var grey: Image = _img(64, 64, Color8(99, 99, 99))
	var bw: ArtPixelate.Palette = ArtPixelate.make_palette(["#000000", "#ffffff"])
	var flat: Image = ArtPixelate.process_sprite(grey, _spec(8, 8, {"background": "opaque"}), bw)
	var dithered: Image = ArtPixelate.process_sprite(
		grey, _spec(8, 8, {"background": "opaque", "dither": "ordered"}), bw
	)
	var flat_colors: Dictionary = {}
	var dith_colors: Dictionary = {}
	for y: int in 8:
		for x: int in 8:
			flat_colors[flat.get_pixel(x, y)] = true
			dith_colors[dithered.get_pixel(x, y)] = true
	assert_eq(flat_colors.size(), 1, "no dithering by default")
	assert_eq(dith_colors.size(), 2)
	_assert_palette_only(dithered, ["#000000", "#ffffff"])


func test_a_fully_transparent_result_gives_an_empty_sprite() -> void:
	var out: Image = ArtPixelate.process_sprite(_img(64, 64), _spec(16, 8), _palette())
	assert_eq(out.get_size(), Vector2i(16, 8))
	assert_eq(ArtPixelate.trim_rect(out, 1), Rect2i())


func test_parts_are_cut_from_the_finished_sprite() -> void:
	var img: Image = _img(160, 64)
	img.fill_rect(Rect2i(0, 0, 120, 64), Color.RED)
	img.fill_rect(Rect2i(120, 0, 40, 64), Color.BLUE)
	var out: Image = ArtPixelate.process_sprite(img, _spec(40, 16), _palette())
	var body: Image = ArtPixelate.cut_part(out, Rect2i(0, 0, 30, 16))
	var tail: Image = ArtPixelate.cut_part(out, Rect2i(30, 0, 10, 16))
	assert_eq(body.get_size(), Vector2i(30, 16))
	assert_eq(tail.get_size(), Vector2i(10, 16))
	assert_eq(body.get_pixel(5, 5), Color.RED)
	assert_eq(tail.get_pixel(5, 5), Color.BLUE)
	assert_eq(body.get_data(), out.get_region(Rect2i(0, 0, 30, 16)).get_data())


func test_processing_is_deterministic() -> void:
	var rng: RandomNumberGenerator = SeededRng.make(99)
	var img: Image = _img(257, 131)
	for y: int in 131:
		for x: int in 257:
			img.set_pixel(
				x,
				y,
				Color8(
					rng.randi_range(0, 255), (x * 3) % 256, (y * 7) % 256, 255 if (x + y) % 5 else 0
				)
			)
	for spec: Dictionary in [
		_spec(33, 17),
		_spec(33, 17, {"background": "opaque"}),
		_spec(70, 9, {"tile": true, "mirror": true})
	]:
		var a: PackedByteArray = (
			ArtPixelate.process_sprite(img, spec, _palette()).save_png_to_buffer()
		)
		var b: PackedByteArray = (
			ArtPixelate
			. process_sprite(img.duplicate() as Image, spec, _palette())
			. save_png_to_buffer()
		)
		assert_eq(a, b)


func test_non_rgba_input_is_converted() -> void:
	var rgb: Image = Image.create_empty(20, 10, false, Image.FORMAT_RGB8)
	rgb.fill(Color.RED)
	var out: Image = ArtPixelate.process_sprite(
		rgb, _spec(4, 2, {"background": "opaque"}), _palette()
	)
	assert_eq(out.get_format(), Image.FORMAT_RGBA8)
	assert_eq(out.get_pixel(1, 1), Color.RED)


# ---------------------------------------------------------------- art.json and the import preset


func _valid_art() -> Dictionary:
	return {
		"palette": PALETTE.duplicate(),
		"style": "pixel art",
		"sprites":
		[
			{
				"id": "fish_tuna",
				"prompt": "a tuna",
				"size": [44.0, 16.0],
				"parts": {"body": [0.0, 0.0, 33.0, 16.0], "tail": [33.0, 0.0, 11.0, 16.0]}
			},
			{
				"id": "reef",
				"prompt": "reef",
				"size": [416.0, 18.0],
				"tile": true,
				"mirror": true,
				"anchor": [0.0, 18.0]
			},
		],
	}


func test_validate_art_accepts_a_valid_file() -> void:
	assert_eq(ArtPixelate.validate_art(_valid_art()), PackedStringArray())


func test_validate_art_reports_problems() -> void:
	var cases: Array = [
		["palette", Array(range(33)).map(func(i: int) -> String: return "#%06x" % i), "at most 32"],
		["palette", ["#12345g"], 'not a "#rrggbb"'],
		["style", "", "style"],
		["dither", "floyd", "dither"],
	]
	for c: Array in cases:
		var art: Dictionary = _valid_art()
		art[c[0]] = c[1]
		var errs: PackedStringArray = ArtPixelate.validate_art(art)
		assert_true(" ".join(errs).contains(str(c[2])), "%s -> %s" % [c[0], errs])
	var bad_sprites: Array = [
		[{"id": "Bad"}, ".id"],
		[{"size": [0, 4]}, ".size"],
		[{"mirror": true}, "mirror: needs tile"],
		[{"parts": {"body": [0, 0, 45, 16]}}, "lies outside"],
		[{"align": "middle"}, ".align"],
		[{"anchor": [99, 0]}, ".anchor"],
		[{"background": "white"}, ".background"],
	]
	for c: Array in bad_sprites:
		var art: Dictionary = _valid_art()
		var s: Dictionary = (art["sprites"] as Array)[0]
		s.merge(c[0], true)
		var errs: PackedStringArray = ArtPixelate.validate_art(art)
		assert_true(" ".join(errs).contains(str(c[1])), "%s -> %s" % [c[0], errs])
	assert_false(ArtPixelate.validate_art([]).is_empty())


func test_normalize_sprite_fills_defaults() -> void:
	var art: Dictionary = _valid_art()
	var s: Dictionary = ArtPixelate.normalize_sprite((art["sprites"] as Array)[0], art)
	assert_eq(s["size"], Vector2i(44, 16))
	assert_eq(s["background"], "transparent")
	assert_eq(s["align"], "bottom_center")
	assert_eq(s["anchor"], "bottom_center")
	assert_eq(s["dither"], "none")
	assert_eq((s["parts"] as Dictionary)["tail"], Rect2i(33, 0, 11, 16))


func test_selected_entries_take_only_selected_ok_results() -> void:
	var m: Dictionary = {
		"requests":
		[
			{"sprite": "a", "request_id": "1", "status": "ok", "selected": false},
			{"sprite": "a", "request_id": "2", "status": "ok", "selected": true},
			{"sprite": "b", "request_id": "3", "status": "download_failed", "selected": true},
			{"sprite": "c", "request_id": "4", "status": "ok"},
		]
	}
	var sel: Dictionary = ArtPixelate.selected_entries(m)
	assert_eq(sel.keys(), ["a"])
	assert_eq((sel["a"] as Dictionary)["request_id"], "2")


func test_import_file_text_is_the_pixel_preset() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	assert_eq(cfg.parse(ArtPixelate.import_file_text()), OK)
	assert_eq(cfg.get_value("remap", "importer"), "texture")
	assert_eq(cfg.get_value("params", "mipmaps/generate"), false)
	assert_eq(cfg.get_value("params", "compress/mode"), 0, "lossless")


func test_an_imported_sprite_has_mipmaps_off() -> void:
	# docs/OWNERSHIP.md W2D7 and C36: the pixel import preset (mipmaps off, lossless).
	var tex: Texture2D = load(IMPORTED_SPRITE) as Texture2D
	assert_not_null(tex)
	assert_eq(tex.get_size(), Vector2(16, 8))
	var img: Image = tex.get_image()
	assert_false(img.has_mipmaps(), "mipmaps off")
	assert_false(img.is_compressed(), "lossless, not VRAM-compressed")


func test_the_imported_sprite_keeps_the_preset_in_its_import_file() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	assert_eq(cfg.load(ProjectSettings.globalize_path(IMPORTED_SPRITE + ".import")), OK)
	assert_eq(cfg.get_value("remap", "importer"), "texture")
	assert_eq(cfg.get_value("params", "mipmaps/generate"), false)
	assert_eq(cfg.get_value("params", "compress/mode"), 0)
	assert_true(
		str(cfg.get_value("remap", "uid", "")).begins_with("uid://"),
		"Godot completed the minimal file on import"
	)


func test_imported_sprite_pixels_are_exact() -> void:
	var img: Image = (load(IMPORTED_SPRITE) as Texture2D).get_image()
	img.convert(Image.FORMAT_RGBA8)
	assert_eq(img.get_pixel(0, 0).a8, 0)
	assert_eq(img.get_pixel(0, 2), Color("#d6d2cf"))
	assert_eq(img.get_pixel(1, 2), Color("#a33412"))
	assert_eq(img.get_pixel(3, 2), Color("#2a5aa8"))
