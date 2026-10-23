extends GutTest
## The fishing sprites (brief 3.3, 3.4, 4.1 "sprite PNGs that use only palette colors and
## transparency"): every art.json sprite has a PNG in assets/fishing/sprites/ at its size, using
## only art.json palette colours at alpha 255 or full transparency (0, 0, 0, 0), at most 32
## colours, with every part cut from it; sprites.json indexes them; the red key ramp appears only
## where PaletteSwap recolours it; fish face left; the placeholder art matches
## FishingFallbackSprites and keeps its own rules (reefs flat at the right end).

const ART_JSON := "res://assets/fishing/art.json"
const SPRITE_DIR := "res://assets/fishing/sprites"
const Writer := preload("res://src/games/fishing/tools/fishing_fallback_writer.gd")

var _art: Dictionary = {}
var _palette: Dictionary = {}


func before_all() -> void:
	_art = JSON.parse_string(FileAccess.get_file_as_string(ART_JSON))
	for hex: String in _art["palette"]:
		_palette[_key(Color(hex))] = hex


func _key(c: Color) -> int:
	return (c.r8 << 16) | (c.g8 << 8) | c.b8


## The PNG at `path` as RGBA8 (read as bytes, so no import warning), or null.
func _load(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


## {"bad": [problems], "colors": {rgb key: count}, "opaque": n, "clear": n} for one image.
func _scan(img: Image) -> Dictionary:
	var data := img.get_data()
	var colors := {}
	var bad: Array[String] = []
	var opaque := 0
	var clear := 0
	for i in range(0, data.size(), 4):
		var a := data[i + 3]
		var rgb := (data[i] << 16) | (data[i + 1] << 8) | data[i + 2]
		if a == 0:
			clear += 1
			if rgb != 0 and bad.size() < 3:
				bad.append("transparent pixel %d carries colour %06x" % [i >> 2, rgb])
			continue
		if a != 255 and bad.size() < 3:
			bad.append("pixel %d has alpha %d" % [i >> 2, a])
		if not _palette.has(rgb) and bad.size() < 3:
			bad.append("pixel %d is %06x, not a palette colour" % [i >> 2, rgb])
		colors[rgb] = int(colors.get(rgb, 0)) + 1
		opaque += 1
	return {"bad": bad, "colors": colors, "opaque": opaque, "clear": clear}


func _sprites() -> Array:
	return _art["sprites"]


func _index() -> Dictionary:
	var v: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(SPRITE_DIR.path_join("sprites.json"))
	)
	return v if v is Dictionary else {}


func _placeholder(id: String) -> bool:
	var entry: Dictionary = (_index().get("sprites", {}) as Dictionary).get(id, {})
	return not entry.has("source") and id != "picker_card"


func test_the_palette_has_at_most_32_distinct_colours() -> void:
	var pal: Array = _art["palette"]
	assert_between(pal.size(), 1, 32)
	assert_eq(_palette.size(), pal.size(), "no duplicates")
	assert_eq(
		Array(FishingFallbackSprites.PALETTE),
		pal,
		"FishingFallbackSprites uses the art.json palette"
	)
	for hex: String in FishingFallbackSprites.KEY_COLORS:
		assert_has(pal, hex, "the key ramp %s is in the palette" % hex)


func test_every_sprite_has_a_png_at_its_size_in_palette_colours_only() -> void:
	assert_gt(_sprites().size(), 20)
	for s: Dictionary in _sprites():
		var id: String = s["id"]
		var img := _load(SPRITE_DIR.path_join(id + ".png"))
		assert_not_null(img, "%s.png exists and is a PNG" % id)
		if img == null:
			continue
		var size := Vector2i(int(s["size"][0]), int(s["size"][1]))
		assert_eq(img.get_size(), size, "%s size" % id)
		var sc := _scan(img)
		assert_eq(sc["bad"], [], "%s pixels" % id)
		assert_lte((sc["colors"] as Dictionary).size(), 32, "%s uses at most 32 colours" % id)
		assert_gt(sc["opaque"], 0, "%s draws something" % id)
		if str(s.get("background", "transparent")) == "opaque":
			assert_eq(sc["clear"], 0, "%s is opaque" % id)
		elif not bool(s.get("tile", false)):
			# A tiled strip (sand) may cover its whole rect; a single subject never does.
			assert_gt(sc["clear"], 0, "%s has a transparent background" % id)


func test_every_part_exists_and_is_cut_from_its_sprite() -> void:
	var checked := 0
	for s: Dictionary in _sprites():
		var parts: Dictionary = s.get("parts", {})
		var whole := _load(SPRITE_DIR.path_join(str(s["id"]) + ".png"))
		for part_name: String in parts:
			var r: Array = parts[part_name]
			var rect := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
			var path := SPRITE_DIR.path_join("%s__%s.png" % [s["id"], part_name])
			var img := _load(path)
			assert_not_null(img, "%s exists" % path)
			if img == null or whole == null:
				continue
			assert_eq(img.get_size(), rect.size, "%s size" % path)
			assert_eq(img.get_data(), whole.get_region(rect).get_data(), "%s is its rect" % path)
			assert_eq(_scan(img)["bad"], [], "%s pixels" % path)
			checked += 1
	assert_eq(checked, 8, "the four fish have a body and a tail")


func test_sprites_json_indexes_every_sprite_in_the_pipeline_format() -> void:
	var index := _index()
	assert_eq(index.get("game"), "fishing")
	assert_eq(index.get("palette"), _art["palette"])
	var sprites: Dictionary = index.get("sprites", {})
	for s: Dictionary in _sprites():
		var id: String = s["id"]
		assert_true(sprites.has(id), "sprites.json lists %s" % id)
		if not sprites.has(id):
			continue
		var e: Dictionary = sprites[id]
		assert_eq(e["file"], id + ".png")
		assert_eq(e["size"], s["size"], "%s size" % id)
		for k: String in ["anchor", "align", "background", "tile", "mirror", "parts"]:
			assert_true(e.has(k), "%s has %s" % [id, k])
		assert_eq(
			(e["parts"] as Dictionary).keys().size(), (s.get("parts", {}) as Dictionary).size()
		)


## Only the boat's trim and canopy and the angler's cap and shirt carry the PaletteSwap key ramp
## (brief 3.3); picker_card is a whole scene and may show it.
func test_the_red_key_ramp_appears_only_on_the_boat_and_the_angler() -> void:
	var keys := {}
	for hex: String in FishingFallbackSprites.KEY_COLORS:
		keys[_key(Color(hex))] = hex
	for s: Dictionary in _sprites():
		var id: String = s["id"]
		var img := _load(SPRITE_DIR.path_join(id + ".png"))
		if img == null:
			continue
		var used := false
		for rgb: int in _scan(img)["colors"]:
			used = used or keys.has(rgb)
		if FishingFallbackSprites.KEY_SPRITES.has(id):
			assert_true(used, "%s carries the key ramp for PaletteSwap" % id)
		elif id != "picker_card":
			assert_false(used, "%s uses no key colour" % id)


## Fish face left (brief 3.3): the tail touches the right edge, and the head end (the left fifth)
## holds pixels near the vertical middle where the mouth is.
func test_fish_face_left_with_the_tail_at_the_right_edge() -> void:
	for id: String in ["fish_mackerel", "fish_mahi", "fish_tuna", "fish_marlin"]:
		var img := _load(SPRITE_DIR.path_join(id + ".png"))
		assert_not_null(img, id)
		if img == null:
			continue
		var w := img.get_width()
		var h := img.get_height()
		var right := 0
		for y in h:
			right += int(img.get_pixel(w - 1, y).a > 0.5)
		assert_gt(right, 1, "%s: the tail reaches the right edge" % id)
		var mouth := false
		for x in maxi(1, int(w / 5.0)):
			for y in range(int(h / 3.0), h - int(h / 3.0)):
				mouth = mouth or img.get_pixel(x, y).a > 0.5
		assert_true(mouth, "%s: the head is at the left" % id)


func test_fallback_drawings_cover_every_sprite_but_the_picker_card() -> void:
	for s: Dictionary in _sprites():
		var id: String = s["id"]
		if id == "picker_card":
			assert_false(FishingFallbackSprites.has(id), "picker_card keeps its G0 placeholder")
			continue
		assert_true(FishingFallbackSprites.has(id), "a fallback for %s" % id)
		var img := FishingFallbackSprites.image(id)
		assert_eq(img.get_size(), Vector2i(int(s["size"][0]), int(s["size"][1])), "%s size" % id)
		assert_eq(_scan(img)["bad"], [], "%s pixels" % id)
		assert_eq(img.get_data(), FishingFallbackSprites.image(id).get_data(), "%s is pure" % id)
		var parts: Dictionary = s.get("parts", {})
		for part_name: String in parts:
			var r: Array = parts[part_name]
			assert_eq(
				FishingFallbackSprites.part(id, part_name).get_size(),
				Vector2i(int(r[2]), int(r[3])),
				"%s part %s" % [id, part_name]
			)


func test_unknown_fallback_ids_are_rejected() -> void:
	assert_null(FishingFallbackSprites.image("picker_card"))
	assert_push_error("no fallback drawing for picker_card")
	assert_null(FishingFallbackSprites.part("fish_tuna", "fin"))
	assert_push_error("has no part fin")


## In placeholder mode the committed PNGs are exactly what the fallback draws.
func test_placeholder_pngs_match_the_fallback_drawings() -> void:
	var compared := 0
	for id: String in FishingFallbackSprites.ids():
		if not _placeholder(id):
			continue
		var img := _load(SPRITE_DIR.path_join(id + ".png"))
		assert_not_null(img, id)
		if img != null:
			assert_eq(img.get_data(), FishingFallbackSprites.image(id).get_data(), id)
			compared += 1
	if compared == 0:
		pass_test("every sprite comes from the art pipeline (sprites.json carries a source)")


## Brief 3.4: the reefs end flat at the right (the HUD zone holds only open water and flat sand).
## Generated reefs get a code-drawn cap in the view instead, so this checks placeholder art only.
func test_placeholder_reefs_are_flat_at_the_right_end() -> void:
	for id: String in ["reef_back", "reef_front"]:
		var img := FishingFallbackSprites.image(id)
		var h := img.get_height()
		for x in range(img.get_width() - 16, img.get_width()):
			var top := h
			for y in h:
				if img.get_pixel(x, y).a > 0.5:
					top = y
					break
			assert_gte(top, h - 2, "%s column %d is at most 2 px tall" % [id, x])


func test_the_writer_reproduces_the_committed_folder() -> void:
	var dir := "user://fishing_fallback_%d" % get_instance_id()
	var report: Dictionary = Writer.write(dir)
	assert_true(report["ok"], str(report["errors"]))
	assert_does_not_have(report["written"], "picker_card.png", "picker_card is never written")
	var written: Array = report["written"]
	assert_eq(written.size(), FishingFallbackSprites.ids().size() + 8 + 1, "sprites, parts, index")
	var index: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(dir.path_join("sprites.json"))
	)
	assert_eq(index.get("art_mode"), "placeholder")
	for f: String in written:
		if f == "sprites.json":
			continue
		var id := f.get_basename().get_slice("__", 0)
		if _placeholder(id):
			assert_eq(
				FileAccess.get_file_as_bytes(dir.path_join(f)),
				FileAccess.get_file_as_bytes(SPRITE_DIR.path_join(f)),
				"%s matches the committed file" % f
			)
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir.path_join("sprites.json"))
	DirAccess.remove_absolute(dir)
