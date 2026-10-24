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


func test_cadence_turns_the_crank_frames() -> void:
	var b := _boat()
	b.cadence = 90.0
	var seen := {}
	for i in 20:
		b.advance(0.05)
		seen[b.crew_frame()] = true
	assert_eq(seen.size(), FishingArtGrids.CREW_FRAMES, "the pedals go round")


func test_a_still_rider_leaves_the_drivetrain_still() -> void:
	var b := _boat()
	b.cadence = 0.0
	b.prop_drive = 0.0
	b.advance(0.05)
	var tex := b.prop.texture
	var crew := b.crew.texture
	for i in 20:
		b.advance(0.05)
	assert_eq(b.prop.texture, tex)
	assert_eq(b.crew.texture, crew)


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
	assert_eq(FishingSprites.size_of("boat_hull"), FishingRig.HULL_SIZE)
	assert_eq(FishingSprites.anchor("fish_tuna").x, 0)
	assert_has(FishingSprites.ids(), "fish_oarfish")


func test_species_map_to_their_fish_sprites() -> void:
	for sp in FishingConst.SPECIES.size():
		assert_eq(FishingSprites.fish_id(sp), "fish_" + str(FishingConst.SPECIES[sp]))
		assert_gt(FishingSprites.count(FishingSprites.fish_id(sp)), 1)
	assert_eq(FishingSprites.fish_id(-1), "fish_mackerel")


func test_the_line_under_water_reads_against_every_band_it_crosses() -> void:
	for band in FishingPalette.SEA.size():
		var line := FishingView.line_under(band)
		assert_gt(absf(line.v - FishingPalette.SEA[band].v), 0.15, "band %d" % band)
		assert_has(FishingPalette.ALL, line)
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
