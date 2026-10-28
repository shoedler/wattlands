extends GutTest
## The game's own HUD Controls built and drawn headless from fixture states for crews 1-4 (v3: the
## landship's five seats, the fourth rider on Lights), the seat panel's cards (seat order, live
## machine windows, YOU, names cut with an ellipsis), my numbers from the local telemetry, the
## world tags,
## the free-roam strip and board from their setters, the fonts, and the elevation arc clear of the
## barrel's pixels.

const X := preload("res://tests/games/tank/hud/tank_hud_fixtures.gd")
const D := preload("res://src/games/tank/hud/tank_hud_draw.gd")


func _place(c: TankHudCtl) -> TankHudCtl:
	add_child_autofree(c)
	c.size = Vector2(c.art_rect.size * 2)
	return c


func _controls(g: TankGame) -> Array[TankHudCtl]:
	var out: Array[TankHudCtl] = []
	for e: Dictionary in TankHud.spec(g).controls:
		out.append(_place(e["control"]))
	return out


func test_every_control_builds_and_draws_for_crews_1_to_4() -> void:
	for crew in range(1, 5):
		for kind: String in ["advance", "gun_line", "boss"]:
			var g: TankGame = autofree(X.game(X.state(crew, kind)))
			var ctls := _controls(g)
			for c in ctls:
				c.set_telemetry(X.tm(185.0, 88.0))
				c.tick(0.1)
				c.refresh()
				c.queue_redraw()
			await wait_physics_frames(2)
			for c in ctls:
				assert_gt(c.draws, 0, "%s crew %d %s drew" % [c.name, crew, kind])


func test_the_seat_panel_has_five_cards_in_seat_order_for_crews_1_to_4() -> void:
	for crew in range(1, 5):
		var s := X.state(crew)
		var g: TankGame = autofree(X.game(s))
		var row := _place(TankHudSeats.new().setup(g, TankHud.LAYOUT["seats"])) as TankHudSeats
		row.refresh()
		assert_eq(row.cards.size(), TankIds.SEATS.size(), "crew %d: every seat" % crew)
		var shown: Array[String] = []
		var manned := 0
		for c: Dictionary in row.cards:
			var engine := str(c["engine"])
			shown.append(engine)
			assert_not_null(row.texture_of(engine), "a machine window")
			assert_eq(int(c["slot"]), s.station(engine).slot, engine)
			assert_eq(bool(c["empty"]), s.station(engine).is_empty(), engine)
			if not bool(c["empty"]):
				manned += 1
		assert_eq(shown, TankIds.SEATS, "Drive, Gun, Loader, Lights, Secondaries")
		assert_eq(manned, crew, "crew %d: one card per rider manned" % crew)
	var four := TankHudModel.seat_cards(X.state(4), 1)
	assert_eq(str(four[3]["engine"]), TankIds.ENGINE_ARC)
	assert_eq(str(four[3]["mech"]), "arc", "TankMech paints the arc generator")
	assert_eq(str(four[4]["mech"]), "feed", "and the belt feed")
	assert_true(bool(four[4]["empty"]))


func test_the_engine_windows_turn_with_cadence_and_stop_at_zero() -> void:
	var s := X.state(3)
	var g: TankGame = autofree(X.game(s))
	var row := _place(TankHudSeats.new().setup(g, TankHud.LAYOUT["seats"])) as TankHudSeats
	row.refresh()
	var diesel := s.rider_at(s.station(TankIds.ENGINE_DIESEL).slot)
	diesel.cadence_rpm = 0.0
	row.refresh()
	row.tick(1.0)
	assert_eq(row.phase_of(TankIds.ENGINE_DIESEL), 0.0, "at 0 rpm everything stands still")
	var dynamo := s.rider_at(s.station(TankIds.ENGINE_DYNAMO).slot)
	dynamo.cadence_rpm = 90.0
	row.refresh()
	var before := row.phase_of(TankIds.ENGINE_DYNAMO)
	row.tick(2.0)
	assert_almost_eq(row.phase_of(TankIds.ENGINE_DYNAMO) - before, 3.0, 1e-6, "90 rpm: 1.5 rev/s")


func test_the_local_card_says_you_and_uses_the_local_telemetry() -> void:
	var s := X.state(3)
	var g: TankGame = autofree(X.game(s, 2))
	var row := _place(TankHudSeats.new().setup(g, TankHud.LAYOUT["seats"])) as TankHudSeats
	row.set_telemetry(X.tm(321.0, 101.0))
	row.refresh()
	var locals := row.cards.filter(func(c: Dictionary) -> bool: return bool(c["local"]))
	assert_eq(locals.size(), 1)
	assert_eq(int(locals[0]["peer"]), 2)
	assert_eq(float(locals[0]["w"]), 321.0)
	assert_eq(float(locals[0]["cad"]), 101.0)
	assert_eq(str(locals[0]["name"]), "Rider 2")
	s.rider(3).afk = true
	row.refresh()
	var away := row.cards.filter(func(c: Dictionary) -> bool: return int(c["peer"]) == 3)
	assert_true(bool(away[0]["reserve"]))
	assert_eq(float(away[0]["cad"]), 0.0, "a reserve engine idles")


func test_names_are_cut_with_an_ellipsis_to_fit_their_card() -> void:
	var long := "Bartholomew Longname-Smythe"
	for w in [90.0, float(TankHudSeats.CARD_W)]:
		var fitted := TankHudSeats.fit_name(long, w, "180 W")
		assert_true(fitted.ends_with(D.ELLIPSIS), fitted)
		assert_lte(D.tall_w(fitted), w - 12.0 - D.tall_w("180 W") - 9.0)
		assert_gt(fitted.length(), 3, "still a name")
	assert_eq(TankHudSeats.fit_name("Ann", 90.0, "180 W"), "Ann")
	assert_eq(D.fit_tall("anything", 1.0), "")


func test_my_numbers_come_from_the_local_telemetry() -> void:
	var s := X.state(3)
	for e in s.enemies:
		e.telegraph_s = 0.0
	var dyn_slot := s.station(TankIds.ENGINE_DYNAMO).slot
	var peer := s.rider_at(dyn_slot).peer
	var g: TankGame = autofree(X.game(s, peer))
	var mine := _place(TankHudMine.new().setup(g, TankHud.LAYOUT["mine"])) as TankHudMine
	mine.set_telemetry(X.tm(150.0, 92.0, Wl.ERG, 150))
	mine.refresh()
	assert_eq(float(mine.m["w"]), 150.0)
	assert_eq(float(mine.m["cad"]), 92.0)
	assert_almost_eq((mine.m["band"] as Vector2).x, 142.5, 1e-3)
	assert_almost_eq((mine.m["band"] as Vector2).y, 157.5, 1e-3)
	assert_eq(str(mine.m["line"]), TankHud.tx(g, "TANK_HUD_DO_HOLD", ["143", "158"]))
	assert_false(bool(mine.m["sim"]), "the gear is dim in ERG")
	assert_almost_eq(float(mine.m["wbal"]), 0.75, 1e-6)
	s.rider(peer).in_band = false
	mine.set_telemetry(X.tm(190.0, 92.0, Wl.ERG, 150))
	mine.refresh()
	assert_eq(int(mine.m["state"]), 1, "over the band")
	mine.set_telemetry(X.tm(90.0, 92.0, Wl.ERG, 150))
	mine.refresh()
	assert_eq(int(mine.m["state"]), -1, "under the band")
	var drv := s.rider_at(s.station(TankIds.ENGINE_DIESEL).slot)
	var g2: TankGame = autofree(X.game(s, drv.peer))
	var m2 := _place(TankHudMine.new().setup(g2, TankHud.LAYOUT["mine"])) as TankHudMine
	s.enemy(13).telegraph_s = 3.4
	m2.set_telemetry(X.tm(250.0, 95.0, Wl.SIM))
	m2.refresh()
	var sprint := str(roundi(1.2 * drv.ftp))
	var want := TankHud.tx(g2, "TANK_HUD_DO_SURGE", [sprint]) + "  0:04"
	assert_eq(str(m2.m["line"]), want, "SURGE nnn+ W with the seconds left")
	assert_true(bool(m2.m["urgent"]))


func test_the_world_tags_find_the_shooters_the_halt_line_and_the_gun() -> void:
	var s := X.state(3)
	var g: TankGame = autofree(X.game(s))
	var tags := _place(TankHudTags.new().setup(g, TankHud.LAYOUT["tags"])) as TankHudTags
	tags.refresh()
	assert_eq((tags.m["warn"] as Array).size(), 1, "the destroyer's glint")
	assert_true(tags.m.has("halt_x"), "an Advance has a halt line")
	assert_true(bool(tags.m["aim"]), "the gunner lays the gun on a target")
	var b := TankHudTags.new().setup(autofree(X.game(X.state(3, "boss"))), TankHud.LAYOUT["tags"])
	_place(b)
	b.refresh()
	assert_eq(((b as TankHudTags).m["warn"] as Array).size(), 1, "the Behemoth's main gun")
	assert_false((b as TankHudTags).m.has("halt_x"))
	tags.set_turn_marker(s.hull.x_px + 400.0, -1)
	tags.refresh()
	assert_true(tags.m.has("turn_x"))
	tags.queue_redraw()
	await wait_physics_frames(2)
	assert_gt(tags.draws, 0)
	tags.clear_turn_marker()
	tags.refresh()
	assert_false(tags.m.has("turn_x"))


func test_the_roam_strip_and_board_draw_what_their_setters_give() -> void:
	var g: TankGame = autofree(X.game(X.state(3)))
	var strip := _place(TankHudRoamStrip.new().setup(g, TankHud.LAYOUT["roam_strip"]))
	var rs := strip as TankHudRoamStrip
	var zones := [
		{"id": "forest", "from_m": 0.0, "to_m": 1500.0},
		{"id": "lake", "from_m": 1500.0, "to_m": 2600.0, "label": "TANK_HUD_TURN"},
		{"id": "village", "from_m": 2600.0, "to_m": 6000.0},
	]
	rs.set_map(6000.0, zones, PackedFloat32Array([0.1, 0.5, 0.3, 0.9, 0.2]))
	rs.set_tank(2500.0, -1, 120.0)
	rs.set_contacts(PackedFloat32Array([3100.0, 900.0]), [{"at_m": 4000.0, "alive": false}])
	rs.set_title("ROAM", "30 min")
	var map := rs.map_rect()
	assert_eq(rs.mx(0.0), map.position.x + TankHudRoamStrip.END_W)
	assert_eq(rs.mx(6000.0), map.end.x - TankHudRoamStrip.END_W)
	assert_eq(rs.mx(99999.0), rs.mx(6000.0), "clamped to the map")
	assert_eq(rs.tank_dir, -1)
	var board := _place(TankHudBoard.new().setup(g, TankHud.LAYOUT["roam_board"])) as TankHudBoard
	board.set_time(125.0, false)
	board.set_score(1234, 7)
	assert_eq(TankHudBoard.thousands(12345), "12 345")
	assert_eq(TankHudBoard.thousands(999), "999")
	strip.queue_redraw()
	board.queue_redraw()
	await wait_physics_frames(2)
	assert_gt(strip.draws, 0)
	assert_gt(board.draws, 0)


func test_the_fonts_load_and_match_their_generator() -> void:
	var f := D.font()
	assert_true(f is FontFile, "the stencil 5 x 7 face")
	assert_true(D.font_tall() is FontFile, "the stencil 5 x 9 face")
	assert_eq(D.text_w("ABC"), 17.0, "6 px advance, the last gap is not ink")
	assert_eq(D.tall_w("ABC"), 17.0)
	assert_not_null(D.digits(), "the 14 x 24 key-number strip")
	for pair: Array in [
		[TankHudFont.TEXT_PNG, TankHudFont.text_image()],
		[TankHudFont.TALL_PNG, TankHudFont.tall_image()],
		[TankHudFont.DIGITS_PNG, TankHudFont.digits_image()],
	]:
		var png := Image.load_from_file(ProjectSettings.globalize_path(str(pair[0])))
		var gen: Image = pair[1]
		assert_eq(png.get_size(), gen.get_size(), str(pair[0]))
		var diff := 0
		for y in gen.get_height():
			for x in gen.get_width():
				if (png.get_pixel(x, y).a > 0.5) != (gen.get_pixel(x, y).a > 0.5):
					diff += 1
		assert_eq(diff, 0, "%s is TankHudFont's" % pair[0])
	assert_eq(TankHudFont.DIGIT_CELL.y, 24, "key numbers 24 art px tall")


## The v3 barrel sprite's opaque pixels (centres, relative to its trunnion: TankRig.barrel_origin).
func _opaque() -> Array[Vector2]:
	var rig := TankRig.shared()
	var img := rig.barrel_tex.get_image()
	var out: Array[Vector2] = []
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				out.append(Vector2(x, y) + Vector2(0.5, 0.5) - rig.barrel_origin)
	return out


## The barrel sprite on the canvas at elevation `deg` round `pivot` (as TankBody turns it: the bore
## along +x, rotated up by `deg`, mirrored when it faces left), each pixel with its 8 neighbours so
## rounding never hides a touch.
func _barrel_sprite(opaque: Array[Vector2], pivot: Vector2, deg: float, left: bool) -> Dictionary:
	var out := {}
	var t := Transform2D(-deg_to_rad(deg), Vector2.ZERO)
	for q in opaque:
		var rot := t * q
		if left:
			rot.x = -rot.x
		var p := Vector2i((pivot + rot).floor())
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				out[p + Vector2i(dx, dy)] = true
	return out


func test_the_elevation_arc_never_touches_the_barrel() -> void:
	var opaque := _opaque()
	assert_gt(opaque.size(), 200, "the barrel sprite")
	for crew in range(1, 5):
		var s := X.state(crew)
		for facing in [TankIds.FACE_RIGHT, TankIds.FACE_LEFT]:
			s.hull.facing = facing
			var left: bool = facing == TankIds.FACE_LEFT
			var deg := TankHudGeom.ELEV_MIN
			while deg <= TankHudGeom.ELEV_MAX:
				s.hull.elev_deg = deg
				var b := TankHudGeom.make(s, null).barrel()
				var piv: Vector2 = b["pivot"]
				var radius := TankHudGeom.arc_radius(float(b["length"]))
				var barrel := _barrel_sprite(opaque, piv, deg, left)
				var model := TankHudGeom.barrel_pixels(piv, float(b["length"]), deg, left)
				var drawn: Array[Vector2i] = TankHudGeom.arc_pixels(piv, radius, left)
				drawn.append_array(
					TankHudGeom.tick_pixels(piv, deg, left, radius - 2.0, radius + 3.0)
				)
				drawn.append_array(
					TankHudGeom.tick_pixels(piv, deg, left, radius + 3.0, radius + 6.0)
				)
				var lr := TankHudGeom.label_rect(piv, radius, left, Vector2(30, 9))
				for y in range(int(lr.position.y), int(lr.end.y)):
					for x in range(int(lr.position.x), int(lr.end.x)):
						drawn.append(Vector2i(x, y))
				var hits := 0
				for p in drawn:
					if barrel.has(p) or model.has(p):
						hits += 1
				assert_eq(hits, 0, "crew %d facing %d at %.0f deg" % [crew, facing, deg])
				deg += 3.0


func test_the_barrel_check_catches_an_arc_inside_the_barrels_reach() -> void:
	var s := X.state(3)
	s.hull.elev_deg = 10.0
	var b := TankHudGeom.make(s, null).barrel()
	var piv: Vector2 = b["pivot"]
	var barrel := _barrel_sprite(_opaque(), piv, 10.0, false)
	var hits := 0
	for p in TankHudGeom.arc_pixels(piv, 20.0, false):
		if barrel.has(p):
			hits += 1
	assert_gt(hits, 0, "an arc 20 px out runs under the barrel")
