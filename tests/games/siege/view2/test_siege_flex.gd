extends GutTest
## Castellum Rotae on a flex canvas (game.json pixel_flex): the manifest, the view's offset, what
## every canvas must show, the bake covering what the windows ask for, the depth test, the world's
## mirrored copies past the bake, the tilt-shift's rows, and the HUD's plates at every size.

const F := preload("res://tests/games/siege/siege_fakes.gd")
const FIX := preload("res://tests/games/siege/fixtures/siege_fixtures.gd")
const K := preload("res://tests/games/siege/hud/siege_hud_kit.gd")
const MANIFEST := "res://src/games/siege/game.json"
const MAP := "res://content/siege/maps/rotae.json"
const BASE := Vector2i(960, 540)
const MIN := Vector2i(852, 480)
## Windows the bake must cover whole.
const WINDOWS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1440, 900),
	Vector2i(1600, 900),
	Vector2i(1680, 1050),
	Vector2i(1703, 1079),
	Vector2i(1920, 1080),
	Vector2i(1920, 1200),
	Vector2i(2560, 1080),
	Vector2i(2560, 1440),
	Vector2i(2560, 1600),
	Vector2i(3440, 1440),
	Vector2i(3840, 1080),
	Vector2i(3840, 1600),
	Vector2i(3840, 2160),
	Vector2i(5120, 1440),
	Vector2i(5120, 2160),
	Vector2i(5120, 2880),
	Vector2i(7680, 4320),
]

var _games: Array[SiegeGame] = []


func after_each() -> void:
	for g in _games:
		F.free_game(g)
	_games.clear()
	SiegeBakeBank.shared().set_view_offset(Vector2i.ZERO)


func _art(window: Vector2i) -> Vector2i:
	return PixelViewport.fit_layout(Vector2(window), BASE, 1.0, MIN)["art_size"]


func _canvases() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for window in WINDOWS:
		out.append(_art(window))
	for w in range(MIN.x, 1921, 53):
		for h in range(MIN.y, 1085, 41):
			out.append(Vector2i(w, h))
	return out


func _game() -> SiegeGame:
	var g := K.game()
	_games.append(g)
	return g


func _path() -> SiegePath:
	return SiegePath.load_file(MAP)


# --- the manifest ------------------------------------------------------------------------------


func test_the_manifest_flexes_from_what_must_show() -> void:
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_eq(m["pixel_base"], [960.0, 540.0])
	assert_eq(m["pixel_flex"], {"min": [852.0, 480.0]})
	assert_eq(MIN, SiegeViewMath.MUST_SHOW.size, "the smallest canvas is what must show")
	assert_true(
		Rect2i(Vector2i.ZERO, BASE).encloses(SiegeViewMath.MUST_SHOW), "inside the design frame"
	)


func test_the_game_host_windows_give_the_canvases_the_decision_names() -> void:
	assert_eq(_art(Vector2i(1280, 720)), Vector2i(1280, 720))
	assert_eq(_art(Vector2i(1920, 1080)), BASE)
	assert_eq(_art(Vector2i(2560, 1440)), Vector2i(853, 480))
	assert_eq(_art(Vector2i(3440, 1440)), Vector2i(1146, 480))
	assert_eq(_art(Vector2i(3840, 2160)), BASE)


# --- the view's offset ---------------------------------------------------------------------------


func test_the_offset_centres_the_frame_and_stops_at_what_must_show() -> void:
	var cases := {
		BASE: Vector2i.ZERO,
		Vector2i(852, 480): Vector2i(-29, -36),
		Vector2i(853, 480): Vector2i(-29, -36),
		Vector2i(1146, 480): Vector2i(93, -36),
		Vector2i(1278, 540): Vector2i(159, 0),
		Vector2i(1280, 720): Vector2i(160, 90),
		Vector2i(1920, 540): Vector2i(480, 0),
		Vector2i(1703, 1079): Vector2i(371, 269),
		Vector2i(960, 533): Vector2i(0, -4),
	}
	for art: Vector2i in cases:
		assert_eq(SiegeViewMath.view_offset(art), cases[art], str(art))


func test_every_canvas_shows_the_fort_the_wheels_and_the_road() -> void:
	var path := _path()
	var marks: Array[Vector2] = []
	for slot in 4:
		marks.append(path.to_art(path.wheels[slot]))
		marks.append(path.to_art(path.wheels[slot] + Vector3(0, 0, path.wheel_radius_m)))
	for q: Vector3 in [
		Vector3(0, 2, 9), Vector3(84, 2, 9), Vector3(84, 60, 0), Vector3(0, 60, 0), path.gate_pos
	]:
		marks.append(path.to_art(q))
	# the road, every 2 m from where it leaves the camp's stretch
	var prog := 0.0
	while prog <= path.length_m:
		var p := path.to_art(path.point_at(prog))
		if p.y > 110.0:
			marks.append(p)
		prog += 2.0
	for art in _canvases():
		var on := Rect2(Vector2.ZERO, Vector2(art))
		var off := Vector2(SiegeViewMath.view_offset(art))
		for m in marks:
			if not on.has_point(m + off):
				fail_test("%s off the canvas %s" % [m, art])
				return
	pass_test("all on every canvas")


func test_the_design_frame_stays_centred_on_a_bigger_canvas() -> void:
	for art: Vector2i in [BASE, Vector2i(1146, 540), Vector2i(1280, 720), Vector2i(1920, 1084)]:
		var off := SiegeViewMath.view_offset(art)
		assert_almost_eq(off.x + BASE.x * 0.5, art.x * 0.5, 0.5, "x %s" % art)
		assert_almost_eq(off.y + BASE.y * 0.5, art.y * 0.5, 0.5, "y %s" % art)


# --- the bake ------------------------------------------------------------------------------------


func test_the_bake_covers_every_window_with_one_copy() -> void:
	var bank := SiegeBakeBank.shared()
	assert_eq(bank.world_size, Vector2i(1920, 1084))
	assert_eq(bank.world_origin, Vector2i(480, 272))
	assert_eq(bank.world_depth_image.get_size(), bank.world_size)
	assert_eq(Vector2i(bank.world_texture.get_size()), bank.world_size)
	for window in WINDOWS:
		var art := _art(window)
		var off := SiegeViewMath.view_offset(art)
		var cells := SiegeV2WorldLayer.tiles(art, off, bank.world_origin, bank.world_size)
		assert_eq(
			cells,
			[
				{
					"at": Vector2i.ZERO,
					"src": Rect2i(Vector2i.ZERO, bank.world_size),
					"flip": Vector2i.ZERO
				}
			],
			"window %s, canvas %s" % [window, art]
		)


func test_past_the_bake_its_margins_fill_the_canvas_and_the_fort_stays_single() -> void:
	var bank := SiegeBakeBank.shared()
	var frame := Rect2i(bank.world_origin, SiegeBakeBank.ART_SIZE)
	for window: Vector2i in [
		Vector2i(3440, 900), Vector2i(1703, 1500), Vector2i(6000, 959), Vector2i(1000, 3000)
	]:
		var art := _art(window)
		var off := SiegeViewMath.view_offset(art)
		var cells := SiegeV2WorldLayer.tiles(art, off, bank.world_origin, bank.world_size)
		assert_gt(cells.size(), 1, "window %s, canvas %s" % [window, art])
		assert_eq(cells[0]["src"], Rect2i(Vector2i.ZERO, bank.world_size), "the image first")
		for i in range(1, cells.size()):
			var src: Rect2i = cells[i]["src"]
			assert_false(src.intersects(frame), "a copy holds no design frame: %s" % src)
		# every canvas pixel on the sampled grid falls in a tile
		var from := bank.world_origin - off
		for y in range(0, art.y, 37):
			for x in range(0, art.x, 41):
				var p := from + Vector2i(x, y)
				var hit := false
				for c: Dictionary in cells:
					if Rect2i(c["at"], (c["src"] as Rect2i).size).has_point(p):
						hit = true
						break
				if not hit:
					fail_test("%s on %s has no tile" % [p, art])
					return


func test_a_margin_copy_continues_from_the_edge_mirrored() -> void:
	var size := Vector2i(1920, 1084)
	var origin := Vector2i(480, 272)
	var art := Vector2i(3440, 900)
	var cells := SiegeV2WorldLayer.tiles(art, SiegeViewMath.view_offset(art), origin, size)
	var sawn := {}
	for c: Dictionary in cells:
		sawn[[c["at"], c["flip"]]] = c["src"]
	# the first copy past each end mirrors that end's margin, the next one mirrors it back
	assert_eq(sawn[[Vector2i(1920, 0), Vector2i(1, 0)]], Rect2i(1440, 0, 480, 1084))
	assert_eq(sawn[[Vector2i(-480, 0), Vector2i(1, 0)]], Rect2i(0, 0, 480, 1084))
	assert_eq(sawn[[Vector2i(-960, 0), Vector2i(0, 0)]], Rect2i(0, 0, 480, 1084))


func test_the_bank_reads_the_world_by_the_frames_pixels_and_beyond() -> void:
	var bank := SiegeBakeBank.shared()
	var img := bank.world_depth_image
	for px: Vector2i in [
		Vector2i(0, 0), Vector2i(500, 300), Vector2i(-480, -272), Vector2i(1439, 811)
	]:
		var c := img.get_pixelv(px + bank.world_origin)
		assert_eq(bank.world_depth_at(px), bank.decode_world_depth(SiegeBakeBank.rg16(c)), str(px))
		assert_gt(bank.world_depth_at(px), -1.0e8, "%s is ground" % px)
	assert_lt(bank.world_depth_at(Vector2i(-481, 0)), -1.0e8, "off the image")
	assert_lt(bank.world_depth_at(Vector2i(1440, 0)), -1.0e8, "off the image")
	assert_eq(bank.sun_at(Vector2i(0, 812)), 1.0, "off the image")


func test_the_depth_test_follows_the_view() -> void:
	var bank := SiegeBakeBank.shared()
	var m := bank.material(0)
	assert_eq(m.get_shader_parameter("art_size"), Vector2(bank.world_size))
	bank.set_view_offset(Vector2i(93, -36))
	assert_eq(m.get_shader_parameter("art_origin"), Vector2(93 - 480, -36 - 272))
	bank.set_view_offset(Vector2i.ZERO)
	assert_eq(m.get_shader_parameter("art_origin"), Vector2(-480, -272))


# --- the screen pass -----------------------------------------------------------------------------


func test_the_focus_band_keeps_the_frames_band_and_no_more_blur_than_the_base() -> void:
	assert_eq(SiegeV2TiltShift.focus_rows(540, 0, 95.0, 500.0), Vector2(95, 500), "the base")
	assert_eq(SiegeV2TiltShift.focus_rows(480, -36, 95.0, 500.0), Vector2(59, 464), "the smallest")
	assert_eq(
		SiegeV2TiltShift.focus_rows(720, 90, 95.0, 500.0), Vector2(95, 680), "tall: the edges"
	)
	for art in _canvases():
		var rows := SiegeV2TiltShift.focus_rows(
			art.y, SiegeViewMath.view_offset(art).y, 95.0, 500.0
		)
		assert_lte(rows.x + (art.y - rows.y), 135.0, "blurred rows at %s" % art)


func test_the_screen_pass_covers_the_canvas() -> void:
	var t := SiegeV2TiltShift.new(BASE, {"top": 95, "bottom": 500})
	autofree(t)
	t.set_canvas(Vector2i(1146, 480), Vector2i(93, -36))
	assert_eq(t.position, Vector2(-93, 36), "the node's parent has the frame's origin")
	assert_eq(t.size, Vector2(1146, 480))
	var m := t.material as ShaderMaterial
	assert_eq(m.get_shader_parameter("focus_top"), 59.0)
	assert_eq(m.get_shader_parameter("focus_bottom"), 464.0)


# --- the view, in a PixelViewport ----------------------------------------------------------------


func test_the_view_follows_the_canvas() -> void:
	var g := F.make_game(F.make_ctx(3, 1, "vo2", Wl.SOLO, 1))
	_games.append(g)
	g.state = FIX.mid_wave()
	g.content = g.state.content
	var pv := PixelViewport.new()
	pv.pixel_base = BASE
	pv.flex_min = MIN
	pv.set_anchors_preset(Control.PRESET_TOP_LEFT)
	pv.size = Vector2(3440, 1440)
	add_child_autofree(pv)
	var v := g.make_view() as SiegeView
	pv.set_game_view(v)
	assert_eq(v.canvas, Vector2i(1146, 480))
	assert_eq(v.position, Vector2(93, -36))
	assert_eq(v.world.canvas, Vector2i(1146, 480))
	assert_eq(v.tilt.size, Vector2(1146, 480))
	assert_eq(v.bank.view_offset, Vector2i(93, -36))
	pv.size = Vector2(1280, 720)
	v.update(0.05)
	assert_eq(v.canvas, Vector2i(1280, 720))
	assert_eq(v.position, Vector2(160, 90))
	assert_eq(v.tilt.position, Vector2(-160, -90))
	assert_eq(v.world.view_offset, Vector2i(160, 90))
	assert_eq(v.bank.view_offset, Vector2i(160, 90))


func test_outside_a_pixel_viewport_the_view_is_the_design_frame() -> void:
	var g := F.make_game(F.make_ctx(3, 1, "vo2", Wl.SOLO, 1))
	_games.append(g)
	g.state = FIX.mid_wave()
	g.content = g.state.content
	var v := g.make_view() as SiegeView
	add_child_autofree(v)
	assert_eq(v.canvas, BASE)
	assert_eq(v.position, Vector2.ZERO)


func test_attackers_fade_in_over_the_roads_first_metres() -> void:
	var c := SiegeV2Crowd.new(SiegeBakeBank.shared())
	add_child_autofree(c)
	var p := Vector3(-80, 50, 0)
	c.set_enemies(
		PackedInt32Array([1, 1]),
		PackedVector3Array([p, p]),
		PackedFloat32Array([0, 0]),
		PackedFloat32Array([0, 0]),
		PackedFloat32Array([1, 1]),
		PackedInt32Array([0, 0]),
		PackedFloat32Array([0.5])
	)
	assert_eq(c.drawn, 2)
	# each body queues its shadow, then its frame
	assert_eq(c.entry_count(), 4)
	var a: PackedColorArray = c.get("_mods")
	assert_eq(a[0].a8, 128, "the shadow fades")
	assert_eq(a[1].a8, 128, "the body fades")
	assert_eq(a[3].a8, 255, "past the array's end: opaque")


# --- the HUD -------------------------------------------------------------------------------------


func _plates(spec: HudSpec) -> Dictionary:
	var rects := {}
	for c: Dictionary in spec.controls:
		if not (c["control"] is SiegeHudWorld):
			rects[(c["control"] as Node).get_script().get_global_name()] = c["at"]
		autofree(c["control"])
	rects["banners"] = spec.banner_area
	rects["toasts"] = spec.toast_area
	return rects


func test_no_two_plates_overlap_and_all_stay_on_every_canvas() -> void:
	var rects := _plates(SiegeHud.spec(_game()))
	var names: Array = rects.keys()
	for art in _canvases():
		var on := Rect2i(Vector2i.ZERO, art)
		for i in names.size():
			var a := PixelViewport.anchor_rect(rects[names[i]], BASE, art)
			if not on.encloses(a):
				fail_test("%s %s off the canvas %s" % [names[i], a, art])
				return
			for j in range(i + 1, names.size()):
				var b := PixelViewport.anchor_rect(rects[names[j]], BASE, art)
				if a.intersects(b):
					fail_test("%s and %s overlap on %s" % [names[i], names[j], art])
					return
	pass_test("clear on every canvas")


func test_the_column_keeps_to_the_top_right() -> void:
	for art: Vector2i in [MIN, Vector2i(1146, 480), Vector2i(1280, 720), Vector2i(1703, 1079)]:
		var r := PixelViewport.anchor_rect(SiegeHudColumn.RECT, BASE, art)
		assert_eq(r.position.y, SiegeHudColumn.RECT.position.y, "the top, %s" % art)
		assert_eq(art.x - r.end.x, BASE.x - SiegeHudColumn.RECT.end.x, "the right, %s" % art)


func test_the_cockpit_stays_off_the_road_at_every_canvas() -> void:
	var path := _path()
	for art in _canvases():
		var off := Vector2(SiegeViewMath.view_offset(art))
		var r := Rect2(PixelViewport.anchor_rect(SiegeHudCockpit.RECT, BASE, art)).grow(-2.0)
		var prog := 0.0
		while prog <= path.length_m:
			if r.has_point(path.to_art(path.point_at(prog)) + off):
				fail_test("the road at prog %d under the cockpit on %s" % [prog, art])
				return
			prog += 1.0
	pass_test("clear")


func test_tags_stay_on_the_canvas() -> void:
	assert_eq(SiegeHudWorld.tag_x(10, 60, -54, 852), 56, "the left edge, control px")
	assert_eq(SiegeHudWorld.tag_x(900, 60, -54, 852), 844, "the right edge, control px")
	assert_eq(SiegeHudWorld.tag_x(400, 60, 0, 960), 370, "over its engine")


func test_the_world_control_is_under_the_plates_and_the_last_control() -> void:
	var spec := SiegeHud.spec(_game())
	for c: Dictionary in spec.controls:
		autofree(c["control"])
	var last: Control = spec.controls[spec.controls.size() - 1]["control"]
	assert_is(last, SiegeHudWorld)
	assert_lt(last.z_index, 0)


func _hud_on(window: Vector2i, spec: HudSpec, g: SiegeGame) -> Array:
	var pv := PixelViewport.new()
	pv.pixel_base = BASE
	pv.flex_min = MIN
	pv.set_anchors_preset(Control.PRESET_TOP_LEFT)
	pv.size = Vector2(window)
	add_child_autofree(pv)
	var hud := HudLayer.new()
	add_child_autofree(hud)
	hud.build(spec, g.ctx, pv)
	return [hud, pv]


func test_help_points_follow_the_world_or_their_plate() -> void:
	var g := _game()
	var spec := SiegeHud.spec(g)
	var made := _hud_on(Vector2i(2560, 1440), spec, g)
	var h: HudHelp = (made[0] as HudLayer).help_overlay()
	var art := Vector2i(853, 480)
	var off := Vector2(SiegeViewMath.view_offset(art))
	var wheel := g.state.path.to_art(g.state.path.wheels[0])
	assert_eq(h.art_point(wheel), wheel + off, "a wheel: with the view")
	var card := SiegeHud.ROUTE_CARD_AT
	var column := PixelViewport.anchor_rect(SiegeHudColumn.RECT, BASE, art)
	assert_eq(
		h.art_point(card),
		card + Vector2(column.position - SiegeHudColumn.RECT.position),
		"the card"
	)
	var shop := PixelViewport.anchor_rect(SiegeShopPanel.RECT, BASE, art)
	assert_eq(
		h.art_point(SiegeHud.SHOP_AT),
		SiegeHud.SHOP_AT + Vector2(shop.position - SiegeShopPanel.RECT.position),
		"the shop"
	)


func test_the_world_control_draws_where_the_view_does() -> void:
	var g := _game()
	var spec := SiegeHud.spec(g)
	var made := _hud_on(Vector2i(2560, 1440), spec, g)
	var w: SiegeHudWorld = null
	for c: Dictionary in spec.controls:
		if c["control"] is SiegeHudWorld:
			w = c["control"]
	var art := Vector2i(853, 480)
	assert_not_null(made[1])
	assert_eq(w.canvas(), art)
	var here := PixelViewport.anchor_rect(SiegeHudWorld.RECT, BASE, art).position
	assert_eq(here + w.shift(), SiegeViewMath.view_offset(art))
	w.refresh()
	assert_eq(w.model["shift"], w.shift())
	assert_eq(w.model["art"], art)
