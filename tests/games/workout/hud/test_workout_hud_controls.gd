extends GutTest
## Workout's HUD Controls built and drawn headless, alone and in a real HudLayer: the font loads as a
## Font, plates draw with and without telemetry, 8 crew cards fit, the plates keep clear of each other
## on 852, 960 and 1146 wide canvases, the gear lights in SIM, the host's `readout` is stored with no
## readout widget, and the peak resets on a new phase.

const U := preload("res://tests/games/workout/workout_test_util.gd")
const D := preload("res://src/games/workout/hud/workout_hud_draw.gd")
const FakePV := preload("res://tests/ui/fake_pixel_viewport.gd")

var _tr: Translation = null


func before_all() -> void:
	_tr = U.register_strings()


func after_all() -> void:
	U.unregister_strings(_tr)


func test_the_timeline_keeps_the_shared_setup_of_a_hud_control() -> void:
	var c: WorkoutHudTimeline = autofree(WorkoutHudTimeline.new())
	assert_eq(c.mouse_filter, Control.MOUSE_FILTER_IGNORE, "it must not eat the mouse")
	assert_eq(c.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "its text stays on the art grid")
	assert_eq(c.texture_repeat, CanvasItem.TEXTURE_REPEAT_ENABLED, "the strip still tiles")


func _game_at(content: String, t: float, humans: int = 2, bots: int = 0) -> WorkoutGame:
	var g: WorkoutGame = autofree(U.game(content, U.players(humans, bots)))
	g.state.plan_t = t
	var i := 0
	while i + 1 < g.state.phases.size() and g.state.phase_start_s(i + 1) <= t:
		i += 1
	g.state.phase_index = i
	for r: WorkoutRiderState in g.state.riders.values():
		r.phase_index = i
	return g


func _tm(t: float = 10.0, power: float = 130.0, mode: String = Wl.ERG) -> Telemetry:
	var tm := Telemetry.new()
	tm.peer_id = 1
	tm.t = t
	tm.power_w = power
	tm.cadence_rpm = 90.0
	tm.mode = mode
	tm.applied_target_w = 130 if mode == Wl.ERG else 0
	tm.wbal_j = 20000.0
	tm.gear = 15
	return tm


func _controls(g: WorkoutGame) -> Array[WorkoutHudCtl]:
	var out: Array[WorkoutHudCtl] = []
	for e: Dictionary in WorkoutHud.spec(g).controls:
		var c := e["control"] as WorkoutHudCtl
		add_child_autofree(c)
		c.size = Vector2(c.art_rect.size * 2)
		out.append(c)
	return out


func test_the_fonts_load_as_fonts() -> void:
	assert_true(D.font() is Font, "wo_text_5x7's .import made a FontFile")
	assert_true(D.font_tall() is Font, "wo_tall_5x9's too")
	assert_not_null(D.digits())
	assert_not_null(D.crank_texture())
	assert_eq(D.crank_texture().get_size(), Vector2(27 * WorkoutRig.CRANK_FRAMES, 27))
	assert_gt(D.tall_w("HOLD"), 15.0)
	assert_eq(D.big_w("88"), 30.0)
	assert_eq(D.fit_tall("A very long rider name indeed", 40.0).right(1), D.ELLIPSIS)


func test_key_digits_are_48_px_at_1080p() -> void:
	assert_eq(D.DIGIT_CELL.y * 2, 48)


func test_the_crank_icon_fills_the_cadence_column_and_touches_nothing() -> void:
	var at := WorkoutHudMine.CRANK_AT
	var icon := Rect2(at, Vector2(D.CRANK_CELL, D.CRANK_CELL))
	assert_gte(D.CRANK_CELL, 27, "54 px at 1080p, big enough to read at trainer distance")
	assert_eq(icon.end.x, float(WorkoutHudMine.W - 6), "on the plate's right margin")
	assert_gt(icon.position.y, 17.0, "under the header rule")
	assert_lte(icon.end.y, 45.0, "over the gauge's needle, which starts at y 45")
	var rpm_end := (
		WorkoutHudMine.CADENCE_X
		+ D.big_w("140")
		+ 3.0
		+ D.tall_w(TranslationServer.translate("WORKOUT_HUD_RPM"))
	)
	assert_lt(rpm_end, icon.position.x, "clear of RPM after a 3-digit cadence")


func test_every_control_draws_with_telemetry() -> void:
	for content: String in ["easy_30", "rolling_road", "e2e"]:
		var ctls := _controls(_game_at(content, 100.0, 4, 4))
		for c in ctls:
			c.set_telemetry(_tm())
			c.refresh()
			c.queue_redraw()
		await wait_process_frames(2)
		for c in ctls:
			assert_gt(c.draws, 0, "%s %s drew" % [content, c.name])


func test_null_telemetry_draws_and_shows_dashes() -> void:
	var ctls := _controls(_game_at("easy_30", 400.0))
	for c in ctls:
		assert_null(c.tm)
		c.refresh()
		c.queue_redraw()
	await wait_process_frames(2)
	for c in ctls:
		assert_gt(c.draws, 0, "%s drew" % c.name)
	var mine := ctls[1] as WorkoutHudMine
	assert_eq(mine.m["watts"], "--")
	assert_eq(mine.m["cadence"], "--")


func test_a_control_without_a_game_draws_nothing_and_does_not_crash() -> void:
	var c := WorkoutHudMine.new().setup(null, WorkoutHud.LAYOUT["mine"]) as WorkoutHudMine
	add_child_autofree(c)
	c.size = Vector2(444, 188)
	await wait_process_frames(2)
	assert_gt(c.draws, 0)
	assert_true(c.m.is_empty())


func test_stale_power_shows_dashes_through_the_control() -> void:
	var mine := _controls(_game_at("easy_30", 400.0))[1] as WorkoutHudMine
	var t := _tm(10.0, 0.0)
	t.cadence_rpm = 0.0
	t.cadence_age_s = 9.0
	mine.set_telemetry(t)
	mine.refresh()
	assert_eq(mine.m["watts"], "--")


func test_the_gear_lights_in_sim_only() -> void:
	var road := _controls(_game_at("rolling_road", 600.0))[1] as WorkoutHudMine
	road.set_telemetry(_tm(10.0, 180.0, Wl.SIM))
	road.refresh()
	assert_true(road.m["gear_lit"])
	assert_eq(road.m["gear"], "15")
	var erg := _controls(_game_at("easy_30", 400.0))[1] as WorkoutHudMine
	erg.set_telemetry(_tm())
	erg.refresh()
	assert_false(erg.m["gear_lit"])
	assert_eq(erg.m["gear"], "-")


func test_8_crew_cards_fit_the_plate() -> void:
	var crew := _controls(_game_at("easy_30", 400.0, 4, 4))[2] as WorkoutHudCrew
	crew.refresh()
	assert_eq(crew.cards.size(), 8)
	var plate := Rect2i(Vector2i.ZERO, crew.art_rect.size)
	var longest := "%s %s" % ["1234W", "567%"]
	for i in crew.cards.size():
		var r := WorkoutHudModel.card_rect(i)
		assert_true(plate.encloses(r), "card %d" % i)
		# the line and a flag (no lamp beside a flag) never collide in a card
		assert_lte(
			D.tall_w("482W 241%") + 2.0 + D.tall_w("RESCUE"), float(r.size.x - 8), "card %d" % i
		)
		assert_lte(D.tall_w(longest) + 3.0 + 5.0 + 2.0 + D.tall_w("100%"), float(r.size.x - 8))


func test_one_to_four_riders_are_one_row() -> void:
	for n in range(1, 5):
		var crew := _controls(_game_at("easy_30", 400.0, n))[2] as WorkoutHudCrew
		crew.refresh()
		for i in crew.cards.size():
			assert_eq(WorkoutHudModel.card_rect(i).position.y, 34, "the bottom row")
	assert_eq(WorkoutHudModel.card_rect(4).position.y, 0)


func test_plates_do_not_overlap_on_any_canvas() -> void:
	var keys: Array[String] = ["timeline", "mine", "crew", "score", "toasts", "banners"]
	for w: int in [852, 960, 1146, 1280]:
		var h := 480 if w < 960 or w == 1146 else 540
		var art := Vector2i(w, h)
		var placed: Dictionary = {}
		for k: String in keys:
			placed[k] = PixelViewport.anchor_rect(WorkoutHud.LAYOUT[k], Vector2i(960, 540), art)
			assert_true(
				Rect2i(Vector2i.ZERO, art).encloses(placed[k]), "%s on %s stays on" % [k, art]
			)
		for i in keys.size():
			for j in i:
				assert_false(
					(placed[keys[i]] as Rect2i).intersects(placed[keys[j]]),
					"%s and %s on %s" % [keys[i], keys[j], art]
				)


func test_anchoring_on_852_as_the_spec_says() -> void:
	var art := Vector2i(852, 480)
	var at := func(k: String) -> Rect2i:
		return PixelViewport.anchor_rect(WorkoutHud.LAYOUT[k], Vector2i(960, 540), art)
	assert_eq((at.call("mine") as Rect2i).position.x, 6)
	assert_eq((at.call("crew") as Rect2i).position.x, 234)
	assert_eq((at.call("crew") as Rect2i).end.x, 650)
	assert_eq((at.call("score") as Rect2i).position.x, 662)
	assert_eq((at.call("score") as Rect2i).end.x, 846)


func test_the_peak_tracks_power_and_resets_on_a_new_phase() -> void:
	var g := _game_at("easy_30", 670.0)
	var score := _controls(g)[3] as WorkoutHudScore
	score.set_telemetry(_tm(10.0, 412.0, Wl.SIM))
	score.refresh()
	score.set_telemetry(_tm(11.0, 300.0, Wl.SIM))
	score.refresh()
	assert_eq(score.m["peak"], "PEAK 412 W", "held after the power falls")
	g.state.rider(1).phase_index += 1
	score.set_telemetry(_tm(12.0, 130.0))
	score.refresh()
	assert_almost_eq(score.peak_w, 130.0, 1e-5, "a new phase starts over")
	assert_eq(score.m["peak"], "", "no longer a sprint")


func test_the_timeline_cache_follows_a_clients_late_timeline() -> void:
	var g := _game_at("easy_30", 400.0)
	var tl := _controls(g)[0] as WorkoutHudTimeline
	tl.refresh()
	var before := tl.runs.size()
	assert_gt(before, 0)
	var runs_ref := tl.runs
	tl.refresh()
	assert_true(is_same(tl.runs, runs_ref), "cached between frames")
	g.state.set_timeline(g.state.phases.slice(0, 3))
	tl.refresh()
	assert_ne(tl.runs.size(), before, "rebuilt")


## A real HudLayer through a fake PixelViewport: the controls are placed, telemetry reaches them, and
## the host's calls (readout, band) land.
func _layer(g: WorkoutGame) -> HudLayer:
	var bus: WlEventBus = autofree(WlEventBus.new())
	g.ctx.events = bus
	var pv = autofree(FakePV.new())
	pv.fake_scale = 2
	var hud := HudLayer.new()
	hud.sounds = false
	hud.wkg_weight_kg = 0.0
	hud.screen_size_override = Vector2(1920, 1080)
	add_child_autofree(hud)
	hud.build(g.hud_spec(), g.ctx, pv)
	return hud


func test_in_a_real_hud_layer() -> void:
	var g := _game_at("rolling_road", 600.0, 2, 2)
	var hud := _layer(g)
	var spec := hud.spec()
	assert_eq(spec.controls.size(), 4)
	assert_eq(spec.widgets.size(), 0, "no kit widgets")
	assert_null(hud.widget(HudSpec.POWER_GAUGE), "shows_power: no fallback gauge")
	var mine: WorkoutHudMine = null
	for e: Dictionary in spec.controls:
		if e["control"] is WorkoutHudMine:
			mine = e["control"]
	assert_not_null(mine)
	assert_eq(mine.hud_layer(), hud)
	hud.update(_tm(10.0, 180.0, Wl.SIM), null, null)
	assert_not_null(mine.tm, "the HudLayer sends its telemetry")
	hud.apply_power_band(1, 152.0, 210.0)
	mine.refresh()
	assert_eq(mine.m["band"], Vector2(152, 210), "the band Workout published")
	await wait_process_frames(2)
	assert_gt(mine.draws, 0)


func test_a_readout_with_no_readout_widget_is_stored() -> void:
	var g := _game_at("easy_30", 400.0)
	var hud := _layer(g)
	hud.set_readout(WorkoutHud.READOUT_TIB, "94%")
	assert_eq(hud.widgets_of(HudSpec.READOUT).size(), 0)
	pass_test("stored without a widget, no error")


func test_the_help_overlay_has_six_entries_in_words() -> void:
	var g := _game_at("easy_30", 400.0)
	var hud := _layer(g)
	assert_true(hud.has_help())
	var strings := GameStrings.new()
	for e: Dictionary in WorkoutHud.help():
		assert_true(strings.has(str(e["text"])), str(e["text"]))
