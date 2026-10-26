extends GutTest
## Turbo Reel's HUD: the spec's rects at every art size, the help overlay, the minimap and its
## action icons, the leaderboard, the clock, the stopped menu's chips next to the boat, the
## cruise box (with and without heart rate), the speed behind the stern, the fight panel under
## the boat, and that every string the HUD uses exists.

const FX := preload("res://tests/games/fishing/view/fishing_view_fixtures.gd")
const STRINGS := "res://content/fishing/strings.csv"


func _keys() -> Dictionary:
	var out := {}
	for line in FileAccess.get_file_as_string(STRINGS).split("\n"):
		out[line.get_slice(",", 0)] = true
	return out


const SIZES: Array[Vector2i] = [
	Vector2i(640, 360), Vector2i(860, 360), Vector2i(640, 340), Vector2i(568, 320)
]


func _panic(art: Vector2i) -> Rect2i:
	var w := FishingConst.PIXEL_W - FishingConst.PANIC_X
	var h := FishingConst.PIXEL_H - FishingConst.PANIC_Y
	return Rect2i(art.x - w, art.y - h, w, h)


func _ctl(c: FishingHudControl) -> FishingHudControl:
	add_child_autofree(c)
	c.size = Vector2(c.art_rect.size) * 3.0
	return c


func test_no_rect_reaches_the_panic_corner_or_leaves_the_view_at_any_art_size() -> void:
	for art in SIZES:
		var view := Rect2i(Vector2i.ZERO, art)
		for r in FishingHud.rects(art):
			assert_false(r.intersects(_panic(art)), "%s clear of PANIC at %s" % [r, art])
			assert_true(view.encloses(r), "%s inside the view at %s" % [r, art])


func test_the_layout_follows_the_art_size() -> void:
	var a := FishingHud.layout(Vector2i(640, 360))
	var b := FishingHud.layout(Vector2i(860, 340))
	assert_eq((a["board"] as Rect2i).end.x, 636, "the board keeps to the right edge")
	assert_eq((b["board"] as Rect2i).end.x, 856)
	assert_eq((a["minimap"] as Rect2i).size.x, 412)
	assert_eq((b["minimap"] as Rect2i).size.x, 412 + 220, "the minimap takes the extra width")
	assert_eq((a["cruise"] as Rect2i).end.y, 356, "the cruise box sits on the bottom edge")
	assert_eq((b["cruise"] as Rect2i).end.y, 336)
	assert_eq((b["fight"] as Rect2i).size, Vector2i(860, 340), "the fight panel can go anywhere")


func test_the_spec_has_its_own_power_box_the_gear_and_a_help_overlay() -> void:
	var g := FX.make_game(2)
	add_child_autofree(g)
	var spec := FishingHud.spec(g)
	assert_false(spec.has_widget(HudSpec.POWER_GAUGE), "the cruise box and the fight panel")
	assert_false(spec.has_widget(HudSpec.CADENCE))
	assert_true(spec.shows_power, "the game draws raw W and %FTP itself")
	assert_true(spec.has_widget(HudSpec.GEAR), "BRIEF 4.5: the gear stays on the HUD")
	assert_false(spec.has_widget(HudSpec.TIMELINE), "Free Roam has no plan timeline")
	var w := FX.make_game(1, 0, Wl.SOLO, "base_60")
	add_child_autofree(w)
	var ws := FishingHud.spec(w)
	assert_true(ws.has_widget(HudSpec.TIMELINE), "workouts keep the timeline")
	_free_controls(ws)
	var keys := _keys()
	assert_between(spec.help.size(), 5, 8)
	var view := Rect2(Vector2.ZERO, Vector2(FishingConst.PIXEL_W, FishingConst.PIXEL_H))
	for e in spec.help:
		assert_true(keys.has(str(e["text"])), "%s is in strings.csv" % e["text"])
		assert_true(view.has_point(e["at"] as Vector2), "%s inside the view" % e["text"])
		assert_true(view.has_point(e["arrow_to"] as Vector2), "%s points inside" % e["text"])
	_free_controls(spec)


func _free_controls(spec: HudSpec) -> void:
	for e in spec.controls:
		(e["control"] as Control).free()


func test_shown_actions_pick_afk_and_pause_first_then_sprint() -> void:
	var r := FishingRiderState.new()
	r.action = FishingConst.A_DRIVE
	r.p_eff_w = 200.0
	assert_eq(FishingHudModel.shown_action(r), FishingConst.A_DRIVE)
	r.p_eff_w = 300.0
	assert_eq(FishingHudModel.shown_action(r), FishingHudModel.SPRINT)
	r.paused = true
	assert_eq(FishingHudModel.shown_action(r), FishingConst.A_PAUSED)
	r.afk = true
	assert_eq(FishingHudModel.shown_action(r), FishingConst.A_AFK)


func test_every_action_has_an_icon_sprite() -> void:
	var want := {
		FishingConst.A_DRIVE: "icon_drive",
		FishingHudModel.SPRINT: "icon_sprint",
		FishingConst.A_WAIT: "icon_wait",
		FishingConst.A_FIGHT: "icon_fight",
		FishingConst.A_LAND: "icon_landed",
		FishingConst.A_PAUSED: "icon_paused",
		FishingConst.A_AFK: "icon_afk",
	}
	for a: int in want:
		assert_eq(FishingHudModel.icon_of(a), str(want[a]))
	for a in FishingConst.ACTION_NAMES.size():
		assert_not_null(FishingSprites.frame(FishingHudModel.icon_of(a)))


func test_the_leaderboard_sorts_by_points_and_marks_the_local_rider() -> void:
	var g := FX.make_game(3, 1)
	add_child_autofree(g)
	g.state.rider(0).points = 50
	g.state.rider(1).points = 120
	g.state.rider(2).points = 50
	var rows := FishingHudModel.board(g)
	assert_eq(int(rows[0]["slot"]), 1)
	assert_true(bool(rows[0]["local"]))
	assert_eq(int(rows[1]["slot"]), 0, "ties keep slot order")
	assert_eq(int(rows[2]["slot"]), 2)


func test_the_clock_counts_down_then_reads_time_up_or_overtime() -> void:
	var g := FX.make_game(1)
	add_child_autofree(g)
	g.state.t = 0.0
	g.state.play_end_t = 125.0
	assert_eq(FishingHudModel.time_text(g), "2:05")
	g.state.time_up = true
	assert_eq(FishingHudModel.time_text(g), FishingHudModel.tr_key(g, FishingHudModel.KEY_TIME_UP))
	FX.set_fight(g.state.rider(0), 3000.0)
	assert_eq(FishingHudModel.time_text(g), FishingHudModel.tr_key(g, FishingHudModel.KEY_OVERTIME))
	assert_eq(FishingHudModel.clock(3725.0), "1:02:05")


func test_menu_chips_name_the_fish_and_the_two_moves() -> void:
	var g := FX.make_game(1)
	add_child_autofree(g)
	var r := g.state.rider(0)
	FX.set_menu(r, 500.0, 3)
	var chips := FishingHudModel.chips(g, r)
	assert_eq(chips.size(), 5)
	assert_string_contains(str(chips[0]["text"]), FishingHudModel.species_name(g, 0))
	assert_eq(int(chips[0]["hint"]), 0)
	assert_eq(str(chips[3]["text"]), FishingHudModel.tr_key(g, FishingHudModel.KEY_DRIVE_ON))
	assert_true(bool(chips[3]["selected"]))
	assert_eq(str(chips[4]["text"]), FishingHudModel.tr_key(g, FishingHudModel.KEY_TURN))
	FX.set_drive(r, 500.0)
	assert_eq(FishingHudModel.chips(g, r).size(), 0, "no chips while driving")


func test_chips_sit_by_their_hint_and_either_side_of_the_boat() -> void:
	var g := FX.make_game(1)
	add_child_autofree(g)
	FX.set_menu(g.state.rider(0), 3000.0)
	var v := FishingView.new()
	v.game = g
	add_child_autofree(v)
	for i in 10:
		v.advance(0.05)
	var c := _ctl(FishingChips.make(g)) as FishingChips
	c.refresh()
	assert_eq(c.chips.size(), 5)
	var boat: Vector2 = v.model["boats"][0]
	var hint0: Vector2 = v.model["hints"][0]["pos"]
	assert_almost_eq((c.chips[0]["at"] as Vector2).x, hint0.x, 0.01)
	assert_lt((c.chips[0]["at"] as Vector2).y, hint0.y, "above its fish")
	assert_gt((c.chips[3]["at"] as Vector2).x, boat.x, "drive on ahead of the bow")
	assert_lt((c.chips[4]["at"] as Vector2).x, boat.x, "turn around behind the stern")


func test_the_minimap_places_every_rider_with_its_action_icon() -> void:
	var g := FX.make_game(2)
	add_child_autofree(g)
	FX.set_drive(g.state.rider(0), 900.0)
	FX.set_fight(g.state.rider(1), 4500.0)
	var m := _ctl(FishingMinimap.make(g)) as FishingMinimap
	m.refresh()
	assert_true(m.edge, "the roam map ends at the edge")
	assert_eq(m.x0, 0.0)
	assert_eq(m.x1, g.state.world.length_m())
	assert_eq(m.icons.size(), 2)
	assert_almost_eq(float(m.icons[0]["x"]), 900.0 / g.state.world.length_m(), 0.001)
	assert_eq(str(m.icons[1]["icon"]), "icon_fight")
	assert_true(bool(m.icons[0]["local"]))
	assert_eq(m.floor_m.size(), FishingMinimap.SAMPLES)
	assert_gt(m.zones.size(), 4)
	assert_eq(m.marks.size(), g.state.world.landmarks().size(), "every landmark on the strip")
	for mk in m.marks:
		assert_true(FishingMinimap.MARKS.has(str(mk["kind"])), "a mark for %s" % mk["kind"])


func test_the_workout_minimap_is_a_moving_window_round_the_boats() -> void:
	var g := FX.make_game(1, 0, Wl.SOLO, "base_60")
	add_child_autofree(g)
	g.state.rider(0).x_m = 12000.0
	var m := _ctl(FishingMinimap.make(g)) as FishingMinimap
	m.refresh()
	assert_false(m.edge)
	assert_lt(m.x0, 12000.0)
	assert_gt(m.x1, 12000.0)
	assert_almost_eq(float(m.icons[0]["x"]), 0.5, 0.01)


func _view(g: FishingGame, frames: int = 6) -> FishingView:
	var v := FishingView.new()
	v.game = g
	add_child_autofree(v)
	for i in frames:
		v.advance(0.05)
	return v


func _tm(power: float, cadence: float, hr: int, target: int = 0) -> Telemetry:
	var t := Telemetry.new()
	t.t = 10.0
	t.power_w = power
	t.cadence_rpm = cadence
	t.heart_rate_bpm = hr
	t.applied_target_w = target
	return t


func test_the_fight_panel_shows_the_fish_reel_in_target_now_and_the_cues() -> void:
	var g := FX.make_game(1)
	add_child_autofree(g)
	var r := g.state.rider(0)
	var l := FishingHud.layout(Vector2i(640, 360))
	var p := _ctl(FishingFightPanel.make(g, l["fight"])) as FishingFightPanel
	FX.set_drive(r, 2600.0)
	p.refresh()
	assert_false(bool(p.fish["visible"]))
	FX.set_fight(r, 7000.0, 8, 30.0, 400.0, 0.6, 0.2)
	r.reel = 0.35
	r.band_lo = 84.0
	r.band_hi = 100.0
	_view(g)
	p.set_telemetry(_tm(231.0, 91.0, 0, 236))
	p.refresh()
	assert_true(bool(p.fish["visible"]))
	assert_eq(int(p.fish["sp"]), 8)
	assert_almost_eq(float(p.fish["reel"]), 0.35, 1e-6, "the bar is the reel-in progress")
	assert_eq(float(p.numbers["target"]), 236.0)
	assert_eq(float(p.numbers["power"]), 231.0)
	assert_eq(p.strain, 0.6)
	assert_eq(p.slack, 0.2)
	assert_eq(p.band, Vector2(84, 100))
	p.queue_redraw()
	await wait_physics_frames(2)
	var boat: Vector2 = (g.get_meta(FishingView.META) as FishingView).model["boats"][0]
	assert_gt(p.panel_rect.position.y, FishingScenery.SURF_Y, "under the surface")
	assert_lt(p.panel_rect.position.y, FishingScenery.SURF_Y + 20, "just under the boat")
	assert_true(p.panel_rect.position.x <= int(boat.x), "it reaches under the boat")
	assert_true(Rect2i(0, 0, 640, 360).encloses(p.panel_rect))
	FX.set_land(r, 500.0)
	p.refresh()
	assert_true(bool(p.gaff["visible"]))
	assert_eq(str(p.gaff["phase"]), FishingHudModel.KEY_SPRINT)
	r.state_t = FishingConst.GAFF_S + 1.0
	assert_eq(str(FishingHudModel.gaff(r)["phase"]), FishingHudModel.KEY_SPIN)
	r.gaff = 1.0
	assert_eq(str(FishingHudModel.gaff(r)["phase"]), FishingHudModel.KEY_TROPHY)


func test_the_cruise_box_grows_by_half_without_heart_rate_and_hides_in_a_fight() -> void:
	var g := FX.make_game(1)
	add_child_autofree(g)
	var r := g.state.rider(0)
	FX.set_drive(r, 2600.0, 12.0)
	var l := FishingHud.layout(Vector2i(640, 360))
	var c := _ctl(FishingCruisePanel.make(g, l["cruise"])) as FishingCruisePanel
	c.set_telemetry(_tm(250.0, 88.0, 141))
	c.refresh()
	assert_true(c.shown)
	assert_string_contains(c.place, "m")
	c.queue_redraw()
	await wait_physics_frames(2)
	assert_eq(c.panel_rect.size.x, 2 * FishingCruisePanel.BOX_W, "watts and heart rate")
	assert_eq(c.panel_rect.end.y, (l["cruise"] as Rect2i).size.y, "on the rect's bottom")
	c.set_telemetry(_tm(250.0, 88.0, 0))
	c.refresh()
	c.queue_redraw()
	await wait_physics_frames(2)
	assert_eq(c.panel_rect.size.x, FishingCruisePanel.BOX_W * 3 / 2, "1.5 boxes without HR")
	assert_gt(c.tag_rect.position.x, c.panel_rect.end.x, "the zone tag right of the box")
	FX.set_fight(r, 7000.0)
	c.refresh()
	assert_false(c.shown, "the fight panel takes over")
	r.fish.off_line = true
	c.refresh()
	assert_true(c.shown, "a lost fish: raw W and %FTP stay on screen")
	FX.set_land(r, 7000.0)
	c.refresh()
	assert_true(c.shown, "the Landing keeps the cruise box beside the gaff meter")


func test_the_speed_shows_knots_behind_the_stern_and_the_flat_road_speed() -> void:
	var g := FX.make_game(1)
	add_child_autofree(g)
	var r := g.state.rider(0)
	FX.set_drive(r, 2600.0, 10.0)
	_view(g)
	var l := FishingHud.layout(Vector2i(640, 360))
	var s := _ctl(FishingSpeedTag.make(g, l["speed"])) as FishingSpeedTag
	s.set_telemetry(_tm(250.0, 90.0, 0))
	s.refresh()
	assert_true(s.shown)
	assert_string_contains(s.knots, "19.4")
	var kmh := SpeedModel.steady_state_speed(250.0, 0.0, 75.0 + SpeedModel.DEFAULT_MASS_OFFSET_KG)
	assert_string_contains(s.kmh, str(roundi(kmh * 3.6)))
	s.queue_redraw()
	await wait_physics_frames(2)
	var boat: Vector2 = (g.get_meta(FishingView.META) as FishingView).model["boats"][0]
	assert_lt(s.text_rect.end.x, int(boat.x), "behind the stern, heading out")
	FX.set_menu(r, 2600.0)
	s.refresh()
	assert_false(s.shown, "not while stopped")


func test_the_board_refreshes_its_rows_and_clock() -> void:
	var g := FX.make_game(2)
	add_child_autofree(g)
	var b := _ctl(FishingBoard.make(g)) as FishingBoard
	b.refresh()
	assert_eq(b.rows.size(), 2)
	assert_ne(b.time_text, "")


func test_every_hud_string_is_in_the_strings_csv() -> void:
	var keys := _keys()
	for k in FishingHudModel.KEYS:
		assert_true(keys.has(k), k)
		assert_true(FishingHudModel.FALLBACK.has(k), "%s has an English stand-in" % k)


func test_every_action_species_and_zone_has_a_string() -> void:
	var keys := _keys()
	for n: String in FishingConst.ACTION_NAMES:
		assert_true(keys.has(FishingHudModel.ACTION_PREFIX + n.to_upper()), n)
	for sp: String in FishingConst.SPECIES:
		assert_true(keys.has("FISHING_SPECIES_" + sp.to_upper()), sp)
	for z: String in FishingWorld.ZONES:
		assert_true(keys.has("FISHING_ZONE_" + z.to_upper()), z)


func test_untranslated_keys_fall_back_to_english_with_args() -> void:
	assert_eq(FishingHudModel.tr_key(null, FishingHudModel.KEY_POINTS, [12]), "12 pts")
	var cast := FishingHudModel.tr_key(null, FishingHudModel.KEY_CAST, {"species": "Tuna"})
	assert_eq(cast, "Cast: Tuna")
	assert_eq(FishingHudModel.name_of(null, 2), "P3")


func test_chips_stay_under_the_minimap_and_clear_of_each_other() -> void:
	var top := FishingChips.TOP_ROW * 3.0
	var placed: Array[Rect2] = [Rect2(0, top, 300, 40)]
	var r := FishingChips._free_spot(Rect2(10, top + 2.0, 100, 51), placed, top)
	assert_gte(r.position.y, top, "never above the minimap's strip")
	assert_false(r.grow(-1.0).intersects(placed[0]))
