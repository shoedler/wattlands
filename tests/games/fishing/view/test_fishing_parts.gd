extends GutTest
## The boat view's parts, the sprite loader, the line colours and the audio cue map.

const FX := preload("res://tests/games/fishing/view/fishing_view_fixtures.gd")


func _boat() -> FishingBoatView:
	var b := FishingBoatView.new()
	add_child_autofree(b)
	b.set_slot(2, FishingPalette.LINE)
	return b


func test_the_cap_and_pennant_take_the_player_colour_and_every_part_a_palette_map() -> void:
	var b := _boat()
	assert_eq(b.player_color(), FishingPalette.player(2))
	for s: Sprite2D in [b.hull, b.crew, b.winch, b.prop]:
		var m := s.material as ShaderMaterial
		assert_not_null(m, s.name)
		assert_eq(m.shader, FishingPaletteMap.shader())


func test_every_part_has_its_sprite_at_its_rig_point() -> void:
	var b := _boat()
	assert_eq(b.crew.position, FishingRig.CREW_AT)
	assert_eq(b.prop.position, FishingRig.PROP_AT)
	assert_eq(b.winch.position, FishingRig.WINCH_AT)
	for s: Sprite2D in [b.hull, b.crew, b.winch, b.prop]:
		assert_not_null(s.texture, s.name)


func test_the_crank_turns_at_exactly_the_cadence_every_frame() -> void:
	var b := _boat()
	b.cadence = 90.0
	b.advance(0.0)
	var a0 := b.crank()
	for i in 10:
		b.advance(1.0 / 60.0)
	var turned := fposmod(b.crank() - a0, TAU)
	assert_almost_eq(turned, 90.0 / 60.0 * TAU * 10.0 / 60.0, 1e-4, "1.5 turns a second")
	var p0 := FishingRig.drivetrain(0.0)
	var p1 := FishingRig.drivetrain(0.3)
	assert_ne(p0, p1, "every angle draws its own crank and leg, no quarter-turn frames")


func test_the_drivetrain_is_a_ring_a_brass_hub_and_a_two_pixel_crank_and_leg() -> void:
	var colours := {}
	for a in [0.0, PI * 0.5, PI, PI * 1.5]:
		var ring := 0
		var hub := 0
		for p in FishingRig.drivetrain(a):
			colours[p.z] = true
			ring += 1 if p.z == 0 else 0
			hub += 1 if p.z == 2 else 0
		assert_eq(ring, 48, "the ring is fixed")
		assert_eq(hub, 4, "a 2 x 2 hub")
	assert_eq(colours.size(), 3, "three colours: slate ring, abyss crank and leg, brass hub")
	for p in FishingRig.drivetrain(1.0):
		assert_true(Rect2i(Vector2i.ZERO, FishingRig.CREW_SIZE).has_point(Vector2i(p.x, p.y)))


func test_a_still_rider_leaves_the_drivetrain_still() -> void:
	var b := _boat()
	b.cadence = 0.0
	b.prop_drive = 0.0
	b.advance(0.05)
	var tex := b.prop.texture
	var crank := b.crank()
	for i in 20:
		b.advance(0.05)
	assert_eq(b.prop.texture, tex)
	assert_eq(b.crank(), crank)


func test_fishing_switches_the_crew_to_the_fishing_pose() -> void:
	var b := _boat()
	b.advance(0.05)
	assert_lt(b.crew_frame(), FishingArtGrids.CREW_FRAMES, "driving pose")
	b.fishing_target = 1.0
	for i in 20:
		b.advance(0.05)
	assert_gte(b.crew_frame(), FishingArtGrids.CREW_FRAMES, "fishing pose")


func test_the_rod_bends_toward_the_line_under_tension() -> void:
	var b := _boat()
	b.fishing_target = 1.0
	for i in 20:
		b.advance(0.05)
	var straight := b.rod_points()[-1]
	b.tension = 0.5
	assert_gt(b.rod_points()[-1].y, straight.y, "the tip bends down")
	assert_lt(b.rod_points()[-1].x, straight.x, "and back toward the line")


func test_the_rod_tip_follows_the_boat() -> void:
	var b := _boat()
	b.position = Vector2(300, FishingScenery.SURF_Y)
	b.advance(0.0)
	var tip := b.rod_tip()
	b.position.x += 10.0
	assert_almost_eq(b.rod_tip().x - tip.x, 10.0, 0.01)
	b.heading = -1
	b.advance(0.0)
	assert_gt(b.rod_tip().x, b.position.x, "heading home the rod points the other way")


func test_sprites_load_with_their_frames_and_wrap() -> void:
	var n := FishingArtGrids.CREW_POSES * FishingArtGrids.CREW_FRAMES
	assert_eq(FishingSprites.count("boat_crew"), n)
	assert_eq(FishingSprites.frame("boat_crew", n + 1), FishingSprites.frame("boat_crew", 1))
	assert_eq(FishingSprites.count("fish_tuna"), FishingArtGrids.FISH_POSES.size())
	assert_eq(FishingSprites.size_of("boat_hull"), FishingRig.HULL_SIZE)
	assert_eq(FishingSprites.anchor("fish_tuna").x, 0)
	assert_has(FishingSprites.ids(), "fish_oarfish")


func test_species_map_to_their_fish_sprites() -> void:
	for sp in FishingConst.SPECIES.size():
		assert_eq(FishingSprites.fish_id(sp), "fish_" + str(FishingConst.SPECIES[sp]))
		assert_gt(FishingSprites.count(FishingSprites.fish_id(sp)), 1)
	assert_eq(FishingSprites.fish_id(-1), "fish_mackerel")


func test_the_line_under_water_reads_against_every_band_it_crosses() -> void:
	var line := FishingView.line_under()
	assert_eq(line, FishingPalette.DEEP, "one deep teal under the water")
	for band in FishingPalette.SEA.size():
		assert_gt(absf(line.v - FishingPalette.SEA[band].v), 0.08, "band %d" % band)
	assert_eq(FishingPalette.LINE, FishingPalette.SLATE, "the rod's slate above the water")


func test_the_default_line_cosmetic_is_the_bright_line() -> void:
	var g := FX.make_game(1)
	add_child_autofree(g)
	var v := FishingView.new()
	v.game = g
	add_child_autofree(v)
	v.advance(0.05)
	assert_eq(v.boat_view(0).line_color, FishingPalette.LINE)


func test_cues_play_their_sounds_and_other_riders_are_quieter() -> void:
	var a := FishingAudio.new()
	add_child_autofree(a)
	a.cue({"k": FishingCues.CUE_CAST, "l": 0}, true)
	assert_eq(a.played.slice(-2), ["fishing_clunk", "fishing_plop"])
	a.cue({"k": FishingCues.CUE_SNAP, "l": 1}, false)
	assert_eq(a.played[-1], "fishing_twang")
	a.cue({"k": FishingCues.CUE_TRIP_OVER, "l": -1}, false)
	assert_eq(a.played[-1], "fishing_horn")
	assert_lt(FishingAudio.OTHER_DB, 0.0)


func test_gulls_call_only_near_the_harbour() -> void:
	var a := FishingAudio.new()
	add_child_autofree(a)
	var r := FishingRiderState.new()
	r.x_m = 50.0
	a.update(0.05, r, 0.0)
	assert_has(a.played, "fishing_gull")


func test_the_decoration_hash_is_deterministic() -> void:
	assert_eq(FishingScenery.hash2(3, 7), FishingScenery.hash2(3, 7))
	assert_ne(FishingScenery.hash2(3, 7), FishingScenery.hash2(7, 3))
	assert_gte(FishingScenery.hash2(-5, 2), 0)


func test_the_sprite_writer_lays_frames_side_by_side() -> void:
	var writer: Script = load("res://src/games/fishing/tools/fishing_write_sprites.gd")
	var frames: Array[Image] = []
	frames.assign(FishingArtGrids.build()["boat_prop"]["frames"])
	var strip: Image = writer.call("strip_of", frames)
	assert_eq(strip.get_width(), frames[0].get_width() * frames.size())
	var art: Dictionary = writer.call("art_json", FishingArtGrids.build())
	var cards := 0
	for e: Dictionary in art["sprites"]:
		cards += 1 if str(e.get("background", "")) == "opaque" else 0
	assert_eq(cards, 3)


func test_minimap_icons_never_overlap() -> void:
	var m := FishingMinimap.new()
	m.icons.assign([{"x": 0.5}, {"x": 0.5}, {"x": 0.51}, {"x": 0.99}])
	var spots := m.icon_spots(400.0)
	var sorted := spots.duplicate()
	sorted.sort()
	for i in range(1, sorted.size()):
		assert_gte(sorted[i] - sorted[i - 1], FishingMinimap.ICON_GAP)
	assert_lte(sorted[-1], 400.0 - FishingMinimap.ICON_GAP * 0.5)
	m.free()


func test_the_minimap_draws_in_a_frame() -> void:
	var g := FX.make_game(2)
	add_child_autofree(g)
	var m := FishingMinimap.make(g)
	add_child_autofree(m)
	m.size = Vector2(FishingMinimap.ART.size) * 3.0
	await wait_process_frames(2)
	assert_eq(m.icons.size(), 2)
	assert_almost_eq(m.ap(), 3.0, 0.001)
