extends GutTest
## Turbo Reel's sprites: every PNG in assets/fishing/sprites/ is what FishingArtGrids draws (the
## grids are the source), uses only the palette colours or full transparency, matches
## sprites.json and art.json, keeps the style rules (one cool hue family, nothing darker than
## the abyss, no outlines round the fish) and the shapes the view and HUD rely on.

const DIR := "res://assets/fishing/sprites"
const ART_JSON := "res://assets/fishing/art.json"

var _built: Dictionary = {}
var _index: Dictionary = {}
var _palette: Dictionary = {}


func before_all() -> void:
	_built = FishingArtGrids.build()
	var idx: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(DIR.path_join("sprites.json"))
	)
	_index = (idx as Dictionary).get("sprites", {}) if idx is Dictionary else {}
	for c in FishingPalette.ALL:
		_palette[_key(c)] = true


func _key(c: Color) -> int:
	return (c.r8 << 16) | (c.g8 << 8) | c.b8


## The PNG of `id` as RGBA8 (read as bytes, so no import is needed), or null.
func _png(id: String) -> Image:
	var path := DIR.path_join(id + ".png")
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


func _frame(id: String, k: int) -> Image:
	var frames: Array = _built[id]["frames"]
	return frames[k]


func test_the_palette_is_one_cool_family_with_one_accent_and_no_near_black() -> void:
	assert_lte(FishingPalette.ALL.size(), 16)
	assert_eq(_palette.size(), FishingPalette.ALL.size(), "no duplicates")
	for c in FishingPalette.ALL:
		assert_gte(c.v, FishingPalette.ABYSS.v, "%s is no darker than the abyss" % c.to_html(false))
		if FishingPalette.PLAYERS.has(c):
			assert_lte(c.s, 0.55, "player colours are desaturated")
			continue
		var hue := c.h * 360.0
		var cool := c.s < 0.1 or (hue >= 140.0 and hue <= 215.0)
		assert_true(
			cool or c == FishingPalette.ACCENT, "%s is in the cool family" % c.to_html(false)
		)
		assert_lte(c.s, 0.75)
	var prev := 2.0
	for c in FishingPalette.LADDER:
		assert_lt(c.v, prev, "the ladder steps darker")
		prev = c.v


func test_art_json_lists_the_palette_and_every_sprite() -> void:
	var art: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ART_JSON))
	var pal: Array = art["palette"]
	assert_eq(pal.size(), FishingPalette.ALL.size())
	for i in pal.size():
		assert_eq(Color(str(pal[i])), FishingPalette.ALL[i])
	var ids := {}
	for e: Dictionary in art["sprites"]:
		ids[str(e["id"])] = true
		assert_true(str(e.get("prompt", "")) != "", "%s has a description" % e["id"])
	assert_eq(ids.size(), _built.size())
	for id: String in _built:
		assert_true(ids.has(id), "art.json lists %s" % id)


func test_sprites_json_indexes_every_sprite_and_nothing_else() -> void:
	assert_eq(_index.size(), _built.size())
	for id: String in _built:
		assert_true(_index.has(id), id)
	var d := DirAccess.open(DIR)
	for f in d.get_files():
		if f.ends_with(".png"):
			assert_true(_built.has(f.get_basename()), "%s is a known sprite" % f)


func test_every_png_is_up_to_date_with_the_grids() -> void:
	for id: String in _built:
		var png := _png(id)
		assert_not_null(png, id)
		if png == null:
			continue
		var frames: Array = _built[id]["frames"]
		var f0: Image = frames[0]
		assert_eq(png.get_width(), f0.get_width() * frames.size(), "%s strip width" % id)
		assert_eq(png.get_height(), f0.get_height(), "%s height" % id)
		var same := true
		for k in frames.size():
			var f: Image = frames[k]
			for y in f.get_height():
				for x in f.get_width():
					var a := f.get_pixel(x, y)
					var b := png.get_pixel(k * f.get_width() + x, y)
					if (a.a > 0.5) != (b.a > 0.5) or (a.a > 0.5 and _key(a) != _key(b)):
						same = false
		assert_true(same, "%s matches FishingArtGrids (run fishing_write_sprites.gd)" % id)


func test_every_pixel_is_a_palette_colour_or_fully_clear() -> void:
	for id: String in _built:
		var png := _png(id)
		if png == null:
			continue
		var bad := 0
		var data := png.get_data()
		for i in range(0, data.size(), 4):
			var a := data[i + 3]
			var rgb := (data[i] << 16) | (data[i + 1] << 8) | data[i + 2]
			if a == 0:
				continue
			if a != 255 or not _palette.has(rgb):
				bad += 1
		assert_eq(bad, 0, "%s uses only palette colours at alpha 255" % id)


func test_sprites_json_sizes_frames_and_anchors_match() -> void:
	for id: String in _built:
		var e: Dictionary = _index.get(id, {})
		var frames: Array = _built[id]["frames"]
		var f0: Image = frames[0]
		assert_eq(int(e.get("frames", 0)), frames.size(), id)
		assert_eq(Vector2i(int(e["size"][0]), int(e["size"][1])), f0.get_size(), id)
		var a := Vector2i(int(e["anchor"][0]), int(e["anchor"][1]))
		assert_true(Rect2i(Vector2i.ZERO, f0.get_size() + Vector2i.ONE).has_point(a), id)


func test_every_species_has_an_animated_fish_facing_left() -> void:
	for sp in FishingConst.SPECIES.size():
		var id := FishingSprites.fish_id(sp)
		assert_true(_built.has(id), id)
		var frames: Array = _built[id]["frames"]
		assert_eq(frames.size(), FishingArtGrids.SWIM_FRAMES, id)
		var f: Image = frames[0]
		var left := 0
		for y in f.get_height():
			left += 1 if f.get_pixel(0, y).a > 0.5 or f.get_pixel(1, y).a > 0.5 else 0
		assert_gt(left, 0, "%s: the mouth is at the left edge" % id)
		var a: Vector2i = _built[id]["anchor"]
		assert_eq(a.x, 0, "%s: the anchor is the mouth" % id)


func test_swim_frames_differ_so_the_fish_moves() -> void:
	for id: String in FishingArtGrids.FISH:
		var a := _frame(id, 0)
		var b := _frame(id, 1)
		assert_ne(a.get_data(), b.get_data(), "%s frame 1 moves" % id)


func test_the_big_fish_are_bigger_than_the_shallow_ones() -> void:
	var small := _frame("fish_mackerel", 0).get_size()
	for id: String in ["fish_marlin", "fish_grouper", "fish_oarfish", "fish_swordfish"]:
		var big := _frame(id, 0).get_size()
		assert_gt(big.x * big.y, small.x * small.y * 4, id)


func test_the_hull_is_a_slate_mass_under_a_straight_foam_rail() -> void:
	var f := _frame("boat_hull", 0)
	var slate := 0
	for y in f.get_height():
		for x in f.get_width():
			slate += 1 if _key(f.get_pixel(x, y)) == _key(FishingPalette.SLATE) else 0
	assert_gt(slate, 400, "a dark mass that reads against the pale sky")
	for y in [21, 22]:
		for x in range(FishingRig.STERN_X, 76):
			assert_eq(_key(f.get_pixel(x, y)), _key(FishingPalette.FOAM), "rail (%d, %d)" % [x, y])


func test_no_sprite_uses_a_player_colour_and_the_crew_frames_all_differ() -> void:
	var players := {}
	for c in FishingPalette.PLAYERS.slice(1):
		players[_key(c)] = true
	for id: String in _built:
		if id.begins_with("card") or id.begins_with("picker") or id.begins_with("icon"):
			continue
		for f: Image in _built[id]["frames"]:
			for y in f.get_height():
				for x in f.get_width():
					var c := f.get_pixel(x, y)
					if c.a > 0.5 and players.has(_key(c)):
						fail_test("%s uses a player colour" % id)
						return
	var seen := {}
	for f: Image in _built["boat_crew"]["frames"]:
		seen[f.get_data()] = true
	assert_eq(seen.size(), 2 * FishingArtGrids.CREW_FRAMES)


func test_fish_have_no_outline_and_no_isolated_specks() -> void:
	for id: String in FishingArtGrids.FISH:
		var f := _frame(id, 0)
		var edge_dark := 0
		var edge := 0
		var specks := 0
		for y in f.get_height():
			for x in f.get_width():
				var c := f.get_pixel(x, y)
				if c.a < 0.5:
					continue
				var same := 0
				var border := false
				for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var p := Vector2i(x, y) + d
					var inside := Rect2i(Vector2i.ZERO, f.get_size()).has_point(p)
					var n := f.get_pixel(p.x, p.y) if inside else Color(0, 0, 0, 0)
					border = border or n.a < 0.5
					same += 1 if n.a > 0.5 and _key(n) == _key(c) else 0
				if border:
					edge += 1
					edge_dark += 1 if _key(c) == _key(FishingPalette.ABYSS) else 0
				if same == 0 and _key(c) != _key(FishingPalette.ABYSS):
					specks += 1
		assert_lt(float(edge_dark), float(edge) * 0.1, "%s has no dark contour" % id)
		assert_eq(specks, 0, "%s has no lone pixels but its eye" % id)


func test_boat_parts_sit_inside_the_hull_canvas() -> void:
	var hull := Rect2(Vector2.ZERO, Vector2(FishingRig.HULL_SIZE))
	var parts := {
		"boat_crew": FishingRig.CREW_AT,
		"boat_winch": FishingRig.WINCH_AT,
		"boat_prop": FishingRig.PROP_AT,
	}
	assert_eq(_frame("boat_hull", 0).get_size(), FishingRig.HULL_SIZE)
	for id: String in parts:
		var r := Rect2(parts[id], Vector2(_frame(id, 0).get_size()))
		assert_true(hull.encloses(r), "%s fits the hull canvas" % id)
	assert_gt(FishingRig.PROP_HUB.y, float(FishingRig.WATERLINE), "the screw is under water")


func test_the_hull_floats_on_its_waterline() -> void:
	var f := _frame("boat_hull", 0)
	var above := 0
	var below := 0
	for x in range(FishingRig.STERN_X + 2, FishingRig.BOW_X - 4):
		above += 1 if f.get_pixel(x, FishingRig.WATERLINE - 1).a > 0.5 else 0
		below += 1 if f.get_pixel(x, FishingRig.WATERLINE + 2).a > 0.5 else 0
	assert_gt(above, 50, "the hull reaches the waterline")
	assert_gt(below, 40, "and sits a little below it")


func test_every_action_icon_is_11_by_9_with_slot_colour_pixels() -> void:
	for id: String in FishingArtGrids.ICONS:
		var f := _frame(id, 0)
		assert_eq(f.get_size(), Vector2i(11, 9), id)
		var fill := 0
		for y in 9:
			for x in 11:
				if _key(f.get_pixel(x, y)) == _key(FishingPalette.FOAM):
					fill += 1
		assert_gt(fill, 3, "%s has pixels the slot colour tints" % id)


func test_cards_are_opaque_160_by_90_and_the_picker_image_exists() -> void:
	for id: String in ["picker_card", "card_roam", "card_workout"]:
		var f := _frame(id, 0)
		assert_eq(f.get_size(), FishingArtGrids.CARD, id)
		var clear := 0
		for y in f.get_height():
			for x in f.get_width():
				clear += 1 if f.get_pixel(x, y).a < 0.5 else 0
		assert_eq(clear, 0, "%s is opaque" % id)
	var m: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://src/games/fishing/game.json")
	)
	assert_true(ResourceLoader.exists(str(m["picker_image"])), "picker_image loads")


func test_the_pixel_font_png_is_the_glyph_grid_and_imports_as_a_font() -> void:
	var path := "res://assets/fishing/font/turbo_reel_5x7.png"
	var png := Image.new()
	assert_eq(png.load_png_from_buffer(FileAccess.get_file_as_bytes(path)), OK)
	var want := FishingFontGrids.font_image()
	png.convert(Image.FORMAT_RGBA8)
	assert_eq(png.get_size(), want.get_size())
	assert_eq(png.get_data(), want.get_data(), "run fishing_write_sprites.gd")
	var cells := FishingFontGrids.COLUMNS * FishingFontGrids.ROWS
	assert_eq(FishingFontGrids.FONT_GLYPHS.size(), cells, "one glyph per cell")
	var font := load(path) as Font
	assert_not_null(font)
	var px := FishingHudDraw.FONT_PX * 3
	var w := font.get_string_size("20:00 Rider 1 85%", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	assert_eq(w, float(17 * FishingFontGrids.CELL.x * 3), "fixed width, whole-pixel scale")
