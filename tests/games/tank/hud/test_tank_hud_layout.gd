extends GutTest
## The HudSpec and its layout (brief 3.6; GAME_SDK 10.1): only the game's own Controls, no kit
## widget; shows_power; the palette themes the platform's toasts, banners and help; 3-6 help
## entries whose keys are in strings.csv; every rect on the canvas after the HUD's anchoring from
## 852 x 480 up to 1146 x 480; nothing in the bottom-right 200 x 60; no plate over the tank's
## band (y 150-360) but the world tags; the seat panel's cards clear of my numbers and the corner.

const X := preload("res://tests/games/tank/hud/tank_hud_fixtures.gd")
const STRINGS := "res://content/tank/strings.csv"
const CANVASES: Array[Vector2i] = [
	Vector2i(852, 480), Vector2i(853, 480), Vector2i(960, 540), Vector2i(1146, 480)
]
## The plates of the mission HUD and of free roam (each set shares one canvas).
const MISSION_KEYS: Array[String] = [
	"mission", "toasts", "hull", "boss", "banners", "mine", "seats"
]
const ROAM_KEYS: Array[String] = [
	"roam_strip", "roam_toasts", "roam_board", "roam_hull", "mine", "seats"
]


static func keys() -> Dictionary:
	var out := {}
	var f := FileAccess.open(STRINGS, FileAccess.READ)
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 2:
			out[row[0]] = row[1]
	return out


func _spec(crew: int = 3) -> HudSpec:
	var g: TankGame = autofree(X.game(X.state(crew)))
	var hs := TankHud.spec(g)
	for c: Dictionary in hs.controls:
		autofree(c["control"])
	return hs


func test_the_spec_has_only_the_games_own_controls() -> void:
	var hs := _spec()
	assert_eq(hs.widgets.size(), 0, "no kit widgets")
	for w: String in HudSpec.KIT_WIDGETS:
		assert_false(hs.has_widget(w), w)
	var kinds: Array[String] = []
	for c: Dictionary in hs.controls:
		assert_true(c["control"] is TankHudCtl)
		assert_true(c["at"] is Rect2i)
		kinds.append((c["control"] as Object).get_script().get_global_name())
	for k: String in [
		"TankHudMission", "TankHudHull", "TankHudBoss", "TankHudMine", "TankHudSeats"
	]:
		assert_has(kinds, k)
	assert_eq(kinds[-1], "TankHudTags", "the tags last: help points in a plate move with it")
	var rects := {}
	for c: Dictionary in hs.controls:
		assert_false(rects.has(c["at"]), "one Control per rect (a shared rect would stack)")
		rects[c["at"]] = true


func test_shows_power_and_the_palette_themes_toasts_banners_and_help() -> void:
	var hs := _spec()
	assert_true(hs.shows_power, "my numbers show raw W and %FTP")
	assert_eq(hs.toast_area, TankHud.LAYOUT["toasts"])
	assert_eq(hs.banner_area, TankHud.LAYOUT["banners"])
	var toasts: Rect2i = hs.toast_area
	var mission: Rect2i = TankHud.LAYOUT["mission"]
	assert_gt(toasts.position.y, mission.end.y - 1, "toasts under the mission plate")
	var banners: Rect2i = hs.banner_area
	assert_almost_eq(float(banners.get_center().x), 480.0, 1.0, "banners in the centre")
	for k: String in ["panel", "panel_border", "text", "text_dim", "accent", "banner_bg"]:
		assert_true(hs.palette.get(k) is Color, k)
	assert_eq(hs.palette["panel"], Color("#17140f"))
	assert_eq(hs.palette["panel_border"], Color("#8a6a3a"))
	assert_eq(hs.palette["text"], Color("#e8dcc0"))
	assert_eq(hs.palette["accent"], Color("#e3a24a"))
	assert_true(hs.palette["font"] is Font, "the game's stencil face")


func test_help_has_three_to_six_entries_with_keys_in_the_strings() -> void:
	var hs := _spec()
	var k := keys()
	assert_between(hs.help.size(), 3, 6)
	for e: Dictionary in hs.help:
		var key := str(e["text"])
		assert_true(key.begins_with("TANK_HELP_"), key)
		assert_true(k.has(key), key + " in strings.csv")
		var at: Vector2 = e["at"]
		var to: Vector2 = e["arrow_to"]
		assert_true(Rect2(Vector2.ZERO, Vector2(TankHud.BASE)).has_point(at), key)
		var inside := false
		for c: Dictionary in hs.controls:
			if c["control"] is TankHudTags:
				continue
			inside = inside or Rect2(c["at"] as Rect2i).has_point(to)
		assert_true(inside, key + " points at a plate")


func test_help_points_stay_on_the_smallest_canvas() -> void:
	var hs := _spec()
	var art := TankHud.FLEX_MIN
	var placed: Array[Rect2i] = []
	for c: Dictionary in hs.controls:
		placed.append(c["at"])
	for e: Dictionary in hs.help:
		for key: String in ["at", "arrow_to"]:
			var p: Vector2 = e[key]
			var r := Rect2i(Vector2i(p.floor()), Vector2i.ONE)
			for pr in placed:
				if Rect2(pr).has_point(p):
					r = pr
					break
			var moved := p + Vector2(TankHud.anchored(r, art).position - r.position)
			var on := Rect2(Vector2.ZERO, Vector2(art)).has_point(moved)
			assert_true(on, "%s %s on 852 x 480" % [e["text"], key])


func test_every_rect_stays_on_the_canvas_after_anchoring() -> void:
	for art in CANVASES:
		var canvas := Rect2i(Vector2i.ZERO, art)
		for key: String in TankHud.LAYOUT:
			var r := TankHud.anchored(TankHud.LAYOUT[key], art)
			assert_true(canvas.encloses(r), "%s inside %s: %s" % [key, art, r])


func test_nothing_reaches_the_bottom_right_corner() -> void:
	for art in CANVASES:
		var clear := TankHud.anchored(TankHud.CLEAR, art)
		assert_eq(clear.end, art, "the corner")
		for key: String in TankHud.LAYOUT:
			if key == "tags":
				continue
			var r := TankHud.anchored(TankHud.LAYOUT[key], art)
			assert_false(r.intersects(clear), "%s clear of the corner on %s" % [key, art])


func test_no_plate_covers_the_tank_band_and_none_overlap() -> void:
	for art in CANVASES:
		for set_keys: Array[String] in [MISSION_KEYS, ROAM_KEYS]:
			var placed: Array[Rect2i] = []
			for key in set_keys:
				var r := TankHud.anchored(TankHud.LAYOUT[key], art)
				var off_band := (
					r.end.y <= TankHud.TANK_BAND_Y.x or r.position.y >= TankHud.TANK_BAND_Y.y
				)
				assert_true(off_band, "%s off the tank band on %s" % [key, art])
				for p in placed:
					assert_false(r.intersects(p), "%s overlaps a plate on %s" % [key, art])
				placed.append(r)
	var tags: Rect2i = TankHud.LAYOUT["tags"]
	assert_eq(TankHud.anchored(tags, TankHud.FLEX_MIN), Rect2i(Vector2i.ZERO, TankHud.FLEX_MIN))


func test_the_seat_cards_stay_clear_of_my_numbers_and_the_corner() -> void:
	for art in CANVASES:
		var own := TankHud.anchored(TankHud.LAYOUT["seats"], art)
		var mine := TankHud.anchored(TankHud.LAYOUT["mine"], art)
		var clear := TankHud.anchored(TankHud.CLEAR, art)
		var cards := TankHudSeats.card_rects(art)
		assert_eq(cards.size(), TankIds.SEATS.size())
		for i in cards.size():
			var c := cards[i].abs()
			var on_canvas := Rect2i(Vector2i(c.position) + own.position, Vector2i(c.size))
			assert_false(on_canvas.intersects(mine), "card %d by my numbers on %s" % [i, art])
			assert_false(on_canvas.intersects(clear), "card %d in the corner on %s" % [i, art])
			assert_true(Rect2i(Vector2i.ZERO, art).encloses(on_canvas))
			assert_gte(c.size.x, 64.0, "a readable card (v4: six cards at 852 x 480)")
			if i > 0:
				assert_gt(c.position.x, cards[i - 1].end.x, "left to right, no overlap")
		if art.x >= 1100:
			assert_eq(cards[0].size.x, float(TankHudSeats.CARD_W), "full cards on %s" % art)
		elif art.x == 960:
			assert_eq(cards[0].size.x, 82.0, "six cards on the base canvas")
	var narrow := TankHudSeats.card_rects(TankHud.FLEX_MIN)
	assert_lt(narrow[0].size.x, float(TankHudSeats.CARD_W), "six narrow cards on 852 x 480")


func test_the_hud_code_names_no_kit_widget() -> void:
	var kit := RegEx.create_from_string(
		"HudSpec\\.(POWER_GAUGE|CADENCE|WBAL|TIMELINE|TEAMMATES|READOUT|GEAR)\\b|\\.add\\("
	)
	var dir := "res://src/games/tank/hud"
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string(dir.path_join(f))
		assert_null(kit.search(text), f)
