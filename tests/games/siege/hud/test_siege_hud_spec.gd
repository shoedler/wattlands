extends GutTest
## Siege's HudSpec (docs/games/siege.md 3 "HUD"): no kit widgets, its own Controls clear of the
## field and of each other, the palette, the help's seven entries, every string key; and the baked
## letter: its metrics, truncation and the fallback.

const K := preload("res://tests/games/siege/hud/siege_hud_kit.gd")
const F := preload("res://tests/games/siege/siege_fakes.gd")
const STRINGS := "res://content/siege/strings.csv"

var _games: Array[SiegeGame] = []


func after_each() -> void:
	for g in _games:
		F.free_game(g)
	_games.clear()


func _g() -> SiegeGame:
	var g := K.game()
	_games.append(g)
	return g


func _spec(g: SiegeGame) -> HudSpec:
	var spec := SiegeHud.spec(g)
	for c: Dictionary in spec.controls:
		autofree(c["control"])
	return spec


func _rect_of(spec: HudSpec, type: Variant) -> Rect2i:
	for c: Dictionary in spec.controls:
		if is_instance_of(c["control"], type):
			return c["at"]
	return Rect2i()


func test_the_spec_has_no_kit_widgets_and_all_its_own_controls() -> void:
	var spec := _spec(_g())
	assert_eq(spec.widgets, [], "the game draws its own HUD")
	assert_true(spec.shows_power, "the cockpit shows raw W and %FTP")
	for type in [
		SiegeHudWorld,
		SiegeHudSession,
		SiegeHudCrew,
		SiegeHudColumn,
		SiegeHudCockpit,
		SiegeShopPanel
	]:
		assert_ne(_rect_of(spec, type), Rect2i(), str(type))


func test_every_control_gets_telemetry_through_the_hud_contract() -> void:
	var spec := _spec(_g())
	for c: Dictionary in spec.controls:
		assert_true((c["control"] as Control).has_method("set_telemetry"), str(c["control"]))
	var x := K.tm(1.0, 150.0)
	var cockpit: SiegeHudCockpit = null
	for c: Dictionary in spec.controls:
		if c["control"] is SiegeHudCockpit:
			cockpit = c["control"]
	cockpit.set_telemetry(x)
	assert_eq(cockpit.tm, x)
	assert_eq(cockpit.cockpit.tm, x)


func test_the_placements_match_the_mock() -> void:
	var spec := _spec(_g())
	assert_eq(_rect_of(spec, SiegeHudSession).position, Vector2i(150, 8))
	assert_eq(_rect_of(spec, SiegeHudCrew).position, Vector2i(470, 8))
	assert_eq(_rect_of(spec, SiegeHudColumn).position, Vector2i(804, 8))
	var cockpit := _rect_of(spec, SiegeHudCockpit)
	# 23 px east of the mock: on the narrowest flex canvas it clears the road's east hairpin
	assert_eq(cockpit.position.x, 479)
	assert_eq(cockpit.position.y + SiegeHudCockpit.Y, 420)
	var shop := _rect_of(spec, SiegeShopPanel)
	assert_eq(shop.position.x, 8)
	assert_eq(shop.end.y - 2, 532)
	# narrower than the mock: on the narrowest flex canvas it fits between the session and the column
	assert_eq(spec.banner_area, Rect2i(464, 69, 286, 27))


func test_banners_and_toasts_sit_clear_of_the_plates() -> void:
	var spec := _spec(_g())
	for c: Dictionary in spec.controls:
		if c["control"] is SiegeHudWorld:
			continue
		var r: Rect2i = c["at"]
		assert_false(r.intersects(spec.banner_area), "%s and the banners" % c["control"])
		assert_false(r.intersects(spec.toast_area), "%s and the toasts" % c["control"])


func test_the_plates_do_not_overlap() -> void:
	var spec := _spec(_g())
	var rects := {}
	for c: Dictionary in spec.controls:
		if not (c["control"] is SiegeHudWorld):
			rects[c["control"]] = c["at"]
	for a: Variant in rects:
		for b: Variant in rects:
			if a != b:
				assert_false((rects[a] as Rect2i).intersects(rects[b]), "%s, %s" % [a, b])


func test_the_hud_stays_off_the_field() -> void:
	var g := _g()
	var spec := _spec(g)
	var path := g.state.path
	var rects: Array[Rect2i] = []
	for c: Dictionary in spec.controls:
		# the shop has the road's west loop in breaks, when nothing marches on it
		if not (c["control"] is SiegeHudWorld or c["control"] is SiegeShopPanel):
			rects.append(c["at"])
	rects.append(spec.toast_area)
	rects.append(spec.banner_area)
	var art := Rect2i(0, 0, 960, 540)
	for r in rects:
		assert_true(art.encloses(r), "%s inside the art" % r)
	# the road and the bridge, every metre
	var hits := []
	var prog := 0.0
	while prog <= path.length_m:
		var p := path.to_art(path.point_at(prog))
		for r in rects:
			if Rect2(r).grow(-2.0).has_point(p) and p.x > 0.0:
				hits.append("%s at prog %d" % [r, prog])
		prog += 1.0
	assert_eq(hits, [], "nothing on the road")
	# the fort's footprint (its four corners on the ground, with the walls' 9 m)
	var fort := PackedVector2Array()
	for q: Vector3 in [Vector3(0, 2, 0), Vector3(84, 2, 0), Vector3(84, 60, 0), Vector3(0, 60, 0)]:
		fort.append(path.to_art(q))
	for r in rects:
		for corner: Vector2 in [
			Vector2(r.position),
			Vector2(r.end),
			Vector2(r.position.x, r.end.y),
			Vector2(r.end.x, r.position.y)
		]:
			assert_false(Geometry2D.is_point_in_polygon(corner, fort), "%s clear of the fort" % r)


func test_the_palette_comes_from_the_mock() -> void:
	var spec := _spec(_g())
	var p := spec.palette
	assert_eq(p["panel"], Color("#1d1611"), "the wax")
	assert_eq(p["panel_border"], Color("#d3c19c"), "the limestone")
	assert_eq(p["text"], Color("#f2e6cb"))
	assert_eq(p["banner_bg"], Color("#1d1611"))
	assert_eq(p["corner_radius"], 0)
	assert_false(p["text_outline"])
	assert_eq(p["grid_px"], 2)


func test_help_covers_the_seven_entries_with_arrows_on_the_art() -> void:
	var g := _g()
	var help := SiegeHud.help(g)
	var keys := []
	for h: Dictionary in help:
		keys.append(h["text"])
		var at: Vector2 = h["at"]
		var to: Vector2 = h["arrow_to"]
		for p: Vector2 in [at, to]:
			assert_true(
				p.x >= 0.0 and p.x <= 960.0 and p.y >= 0.0 and p.y <= 540.0,
				"%s %s" % [h["text"], p]
			)
	assert_eq(
		keys,
		[
			"SIEGE_HELP_WHEEL",
			"SIEGE_HELP_PATH",
			"SIEGE_HELP_STATIONS",
			"SIEGE_HELP_ROAD",
			"SIEGE_HELP_GATE",
			"SIEGE_HELP_ROUTE_CARD",
			"SIEGE_HELP_SHOP",
		]
	)
	# the wheel arrow points at the local rider's own wheel
	var me := g.state.rider(1)
	assert_eq(help[0]["arrow_to"], g.state.path.to_art(g.state.path.wheels[me.slot]))
	assert_eq(_spec(g).help.size(), 7)


func test_the_help_arrows_point_into_the_new_plates() -> void:
	var g := _g()
	var spec := _spec(g)
	var help := SiegeHud.help(g)
	var column := _rect_of(spec, SiegeHudColumn)
	var shop := _rect_of(spec, SiegeShopPanel)
	assert_true(Rect2(column).has_point(help[5]["arrow_to"]), "the stations card")
	assert_true(Rect2(shop).has_point(help[6]["arrow_to"]), "the shop")


func test_the_help_panels_do_not_cover_each_other() -> void:
	var boxes: Array[Rect2] = []
	for h: Dictionary in SiegeHud.help(_g()):
		# the kit wraps a panel near this width; two lines take twice the height
		var w := SiegeHudType.width(tr(str(h["text"])), "BODY") + 6.0
		var lines := ceili(w / 286.0)
		var box := Vector2(minf(w, 286.0), 14.0 * lines + 6.0)
		boxes.append(Rect2((h["at"] as Vector2) - box * 0.5, box))
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			assert_false(boxes[i].intersects(boxes[j]), "help panels %d and %d" % [i, j])


func test_the_stations_leader_ends_at_the_plate_edge() -> void:
	var help := SiegeHud.help(_g())
	assert_eq((help[5]["arrow_to"] as Vector2).x, float(SiegeHudColumn.RECT.position.x))


## A help panel as the kit draws it, in 1080p px.
func _help_box(h: Dictionary) -> Rect2:
	var size := Vector2(SiegeHudType.width(tr(str(h["text"])), "BODY") * 2.0 + 12.0, 40.0)
	return Rect2((h["at"] as Vector2) * 2.0 - size * 0.5, size)


func test_the_two_long_panels_sit_on_the_sand_inside_the_road_loop() -> void:
	var help := SiegeHud.help(_g())
	var sand := Rect2(420, 860, 480, 100)
	for i in [1, 2]:
		var box := _help_box(help[i])
		assert_lte(box.size.x, 480.0, str(help[i]["text"]))
		assert_true(sand.encloses(box), "%s %s" % [help[i]["text"], box])


func test_the_route_panel_clears_the_blue_wheel_and_the_stations_card() -> void:
	var box := _help_box(SiegeHud.help(_g())[5])
	assert_almost_eq(box.position.x, 1070.0, 4.0)
	assert_lt(box.end.x, 1608.0)


func test_the_short_help_stays_one_line_in_the_kit() -> void:
	for h: Dictionary in SiegeHud.help(_g()):
		if str(h["text"]) in ["SIEGE_HELP_PATH", "SIEGE_HELP_STATIONS", "SIEGE_HELP_ROUTE_CARD"]:
			assert_lt(SiegeHudType.width(tr(str(h["text"])), "BODY") * 2.0, HudHelp.MAX_PANEL_W)


func test_a_comma_has_a_tail_in_every_face() -> void:
	for f: String in SiegeHudType.manifest()["faces"]:
		var face: Dictionary = SiegeHudType.face(f)
		var g: Array = face["glyphs"][","]
		var below := int(g[3]) - int(g[5]) - int(face["cap"])
		assert_gte(below, 2, f)


func _string_keys() -> Dictionary:
	var keys := {}
	var f := FileAccess.open(STRINGS, FileAccess.READ)
	while f != null and not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("#") or line.strip_edges() == "":
			continue
		keys[line.get_slice(",", 0)] = true
	return keys


func test_no_string_key_is_missing() -> void:
	var keys := _string_keys()
	var missing := []
	for k in SiegeHudModel.STRING_KEYS:
		if not keys.has(k):
			missing.append(k)
	for slot_key in ["SIEGE_OPT_TILT_SHIFT"]:
		if not keys.has(slot_key):
			missing.append(slot_key)
	for id in SiegeIds.STATION_COUNT:
		if not keys.has(SiegeGame.station_key(id)):
			missing.append(SiegeGame.station_key(id))
	for n in range(1, 11):
		for k in ["SIEGE_PHASE_BREAK_%d" % n]:
			if not keys.has(k):
				missing.append(k)
	assert_eq(missing, [])


# --- the letter ------------------------------------------------------------------------------------


func test_every_face_is_baked_with_its_cap() -> void:
	var caps := {"LABEL": 9, "BODY": 12, "LINE": 14, "NUM": 14, "KEY": 24, "KEY28": 28, "KEY36": 36}
	for f: String in caps:
		assert_eq(int(SiegeHudType.face(f)["cap"]), caps[f], f)
		for ch in "0123456789ABCXYZ:%-":
			assert_true(SiegeHudType.has_glyph(ch, f), "%s %s" % [f, ch])
	assert_not_null(SiegeHudType.atlas(), "the atlas imports")


func test_text_is_upper_cased_at_draw_time() -> void:
	assert_eq(SiegeHudType.width("rider", "LABEL"), SiegeHudType.width("RIDER", "LABEL"))
	assert_gt(SiegeHudType.width("RIDER", "BODY"), SiegeHudType.width("RIDER", "LABEL"))


func test_a_character_outside_the_atlas_falls_back() -> void:
	var fb := SiegeHudType.width(SiegeHudType.FALLBACK, "LABEL")
	assert_eq(SiegeHudType.width("日", "LABEL"), fb)
	assert_eq(SiegeHudType.width("☃", "KEY36"), SiegeHudType.width(SiegeHudType.FALLBACK, "KEY36"))
	assert_eq(SiegeHudType.width("ö", "LABEL"), SiegeHudType.width("O", "LABEL"), "folds to O")
	assert_eq(SiegeHudType.width("", "LABEL"), 0)
	assert_eq(SiegeHudType.width("ABC", "NO_SUCH_FACE"), 0)


func test_fit_cuts_a_long_name_and_leaves_a_short_one() -> void:
	assert_eq(SiegeHudType.fit("RIDER 2", "LABEL", 68), "RIDER 2")
	var cut := SiegeHudType.fit("MAXIMILIAN VON HOHENZOLLERN", "LABEL", 68)
	assert_lte(SiegeHudType.width(cut, "LABEL"), 68)
	assert_true(cut.ends_with("."), "the cut shows")
	assert_true(cut.begins_with("MAX"))
	assert_eq(SiegeHudType.fit("WWWW", "LABEL", 1), "")


func test_the_kit_font_draws_both_cases_at_twice_its_size() -> void:
	var font := SiegeHudType.kit_font()
	if font == null:
		pass_test("no atlas image under this renderer: the kit's font stands in")
		return
	var w := font.get_string_size("GATE", HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	assert_gt(w, 0.0)
	assert_eq(font.get_string_size("gate", HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x, w, "both cases")
	var small := font.get_string_size("GATE", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	assert_almost_eq(w, small * 2.0, 1.0, "it scales by whole steps")


func test_plates_are_textures_of_their_size_and_cached() -> void:
	var a := SiegeHudDraw.plate_texture(148, 68)
	assert_not_null(a)
	assert_eq(a.get_width(), 148)
	assert_eq(a.get_height(), 68)
	assert_eq(SiegeHudDraw.plate_texture(148, 68), a, "built once")
	assert_ne(SiegeHudDraw.plate_texture(148, 68, true), a, "the alarm's frame is its own")
	assert_ne(SiegeHudDraw.plate_texture(148, 68, false, SiegeHudDraw.LIT), a, "and the lit wax")
	var small := SiegeHudDraw.plate_texture(9, 9)
	assert_not_null(small, "even a tiny plate stays in bounds")
