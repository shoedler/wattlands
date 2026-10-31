extends GutTest
## v4's HUD (SPEC_TANK section 6): the Repairs card, bots on the seat row, the difficulty tag and the
## losses, TANK LOST, KEEP RIDING, the holding force's objective and the far-frame help.

const X := preload("res://tests/games/tank/hud/tank_hud_fixtures.gd")
const D := preload("res://src/games/tank/hud/tank_hud_draw.gd")
const CANVASES: Array[Vector2i] = [Vector2i(852, 480), Vector2i(960, 540), Vector2i(1280, 680)]


func _lost(s: TankState) -> TankHudLost:
	var g: TankGame = autofree(X.game(s))
	var c := TankHudLost.new().setup(g, TankHud.LAYOUT["lost"]) as TankHudLost
	add_child_autofree(c)
	return c


func _line(s: TankState, r: TankRiderState, mode: String, target: float = 0.0) -> Dictionary:
	var band := TankHudModel.band_w(s, r, mode, target, Vector2.ZERO)
	return TankHudModel.instruction(
		s, r, {"mode": mode, "cad": 90.0, "band": band, "cband": Vector2.ZERO}
	)


func _panel(s: TankState, local: int = 1) -> TankHudSeats:
	var c := TankHudSeats.new().setup(autofree(X.game(s, local)), TankHud.LAYOUT["seats"])
	add_child_autofree(c)
	return c as TankHudSeats


# --- the sixth card -------------------------------------------------------------------------------


func test_six_cards_at_the_widths_the_spec_names() -> void:
	assert_eq(TankHudSeats.card_rects(Vector2i(960, 540))[0].size.x, 82.0)
	assert_eq(TankHudSeats.card_rects(Vector2i(852, 480))[0].size.x, 64.0)
	assert_eq(TankHudSeats.card_rects(Vector2i(1280, 680))[0].size.x, 100.0)
	assert_eq(TankHudSeats.card_rects(Vector2i(960, 540)).size(), 6)


func test_every_tab_fits_its_card_at_the_narrowest_width_or_falls_to_its_short_name() -> void:
	var g: TankGame = autofree(X.game(X.state(4)))
	var w := TankHudSeats.card_rects(TankHud.FLEX_MIN)[0].size.x
	for e: String in TankIds.SEATS:
		var full := D.text_w(TankHud.tx(g, "TANK_HUD_TAB_" + e.to_upper())) + 16.0
		var short := D.text_w(TankHud.tx(g, "TANK_HUD_TAB_SHORT_" + e.to_upper())) + 16.0
		assert_true(full <= w - 8.0 or short <= w - 8.0, "%s on an empty or manned card" % e)
		var you := D.text_w("YOU") + 8.0
		var bare := short - TankHudSeats.TAB_PAD + TankHudSeats.TAB_PAD_BARE
		assert_lte(bare, w - 8.0 - you - 2.0, "%s beside the YOU tab, without its icon" % e)


func test_the_repairs_seat_has_its_icon_tab_and_machine_name() -> void:
	var g: TankGame = autofree(X.game(X.state(4)))
	assert_true(D.ICONS.has(TankIds.ENGINE_REPAIR), "its own icon")
	assert_ne(D.ICONS[TankIds.ENGINE_REPAIR], D.ICONS[TankIds.ENGINE_DIESEL])
	assert_eq(TankHud.tx(g, "TANK_HUD_TAB_REPAIR"), "REPAIRS")
	for e: String in TankIds.SEATS:
		var k := TankHudModel.machine_key(e)
		assert_ne(TankHud.tx(g, k), k, "%s has a machine name" % e)


func test_the_repairs_card_gives_the_hull_and_the_rate_only_while_it_works() -> void:
	var s := TankFixturesV4.make("repair")
	var rp := TankHudModel.repair(s, 130.0)
	assert_true(bool(rp["working"]))
	assert_almost_eq(float(rp["hull"]), 66.0 / 120.0, 0.001)
	assert_almost_eq(float(rp["rate"]), 0.39, 0.001, "130 W on Normal: 0.39 HP/s (SPEC_TANK 3.6)")
	assert_eq(TankHudSeats.rate_text(0.39), "+0.4/s")
	(s.station(TankIds.ENGINE_REPAIR) as TankRepairState).working = false
	assert_eq(float(TankHudModel.repair(s, 130.0)["rate"]), 0.0, "no rate while idle")


func test_the_repair_rate_follows_the_difficulty() -> void:
	var s := TankFixturesV4.make("repair")
	var normal := float(TankHudModel.repair(s, 200.0)["rate"])
	for level: String in [TankIds.DIFF_EASY, TankIds.DIFF_HARD]:
		s.difficulty = level
		var want := normal * TankDifficulty.mult(s, "repair")
		assert_almost_eq(float(TankHudModel.repair(s, 200.0)["rate"]), want, 0.001, level)


func test_the_rate_text_is_in_the_stencil_face_and_fits_the_card() -> void:
	var have := {}
	for ch in TankHudFont.chars():
		have[ch] = true
	var t := TankHudSeats.rate_text(0.4)
	for ch in t + TankHudSeats.BOT_TAG:
		assert_true(have.has(ch), "%s in the face" % ch)
	assert_lte(D.text_w(t) + 6.0, 60.0, "on a 64 px card")


func test_the_repairs_card_draws_at_both_narrow_widths_for_me_and_for_others() -> void:
	var s := TankFixturesV4.make("repair")
	for local in [1, 4]:
		var p := _panel(s, local)
		p.tick(0.1)
		p.refresh()
		p.queue_redraw()
		await wait_physics_frames(2)
		assert_gt(p.draws, 0, "local %d" % local)
		var c: Dictionary = p.cards[TankIds.SEATS.find(TankIds.ENGINE_REPAIR)]
		assert_false(bool(c["empty"]))
		assert_eq(str(c["mode"]), Wl.ERG, "Repairs is an ERG seat")


func test_a_repairs_rider_reads_hold_a_band_in_watts() -> void:
	var s := TankFixturesV4.make("repair")
	var r := s.rider_at(s.station(TankIds.ENGINE_REPAIR).slot)
	var line := _line(s, r, Wl.ERG, 0.6 * r.ftp)
	assert_eq(line["kind"], TankHudModel.DO_HOLD)
	assert_eq(line["key"], "TANK_HUD_DO_HOLD")
	assert_eq(TankHudModel.plan_mode(s, TankIds.ENGINE_REPAIR), Wl.ERG, "the plan's mode")


# --- bots -----------------------------------------------------------------------------------------


func test_a_bots_card_says_so_and_a_human_may_pick_its_seat() -> void:
	var s := TankFixturesV4.make("bots")
	var cards := TankHudModel.seat_cards(s, 1)
	var bots := 0
	for c: Dictionary in cards:
		if bool(c["bot"]):
			bots += 1
			assert_false(bool(c["empty"]))
			assert_false(bool(c["local"]))
	assert_eq(bots, 3, "three bots")
	var human := s.riders[0]
	human.autopilot = false
	var seats := TankHudSeatPicker.empty_seats(s, human)
	for r in s.riders:
		if r.is_bot:
			assert_has(seats, r.engine, "a human may take a bot's seat")
	assert_does_not_have(seats, human.engine, "not their own")
	assert_true(TankHudSeatPicker.usable(s, human))


func test_a_bot_may_not_pick_and_a_humans_seat_is_never_offered() -> void:
	var s := TankFixturesV4.make("bots")
	var bot := s.riders[1]
	assert_false(TankHudSeatPicker.usable(s, bot), "the automatic seating places bots")
	var crew := X.state(3)
	var r0 := crew.riders[0]
	for other in crew.riders:
		if other != r0:
			assert_does_not_have(
				TankHudSeatPicker.empty_seats(crew, r0), other.engine, "another human's seat"
			)


func test_the_picker_steps_onto_a_bots_seat_and_sits() -> void:
	var s := TankFixturesV4.make("bots")
	var human := s.riders[0]
	human.autopilot = false
	var bot_seat := s.riders[1].engine
	var pick := TankHudSeatPicker.new()
	var right: Array[StringName] = [&"right"]
	pick.feed(s, human, right)
	assert_true(pick.is_open())
	var guard := 0
	while pick.pick != bot_seat and guard < 8:
		pick.feed(s, human, right)
		guard += 1
	assert_eq(pick.pick, bot_seat, "the walk reaches the bot's seat")
	var ok: Array[StringName] = [&"confirm"]
	var out := pick.feed(s, human, ok)
	assert_eq((out["intents"] as Array).size(), 1, "the seat intent")
	assert_eq((out["intents"] as Array)[0], TankIntents.seat(bot_seat))


func test_the_bots_fixture_draws() -> void:
	var p := _panel(TankFixturesV4.make("bots"))
	p.tick(0.1)
	p.refresh()
	p.queue_redraw()
	await wait_physics_frames(2)
	assert_gt(p.draws, 0)


# --- difficulty and losses ------------------------------------------------------------------------


func test_the_mission_plate_gives_the_difficulty_and_the_losses() -> void:
	var s := TankFixturesV4.make("hard", 3)
	var m := TankHudModel.mission(s)
	assert_eq(m["diff_key"], "TANK_HUD_DIFF_HARD")
	assert_true(bool(m["hard"]))
	assert_eq(int(m["losses"]), 1)
	var e := TankHudModel.mission(TankFixturesV4.make("easy_breakdown", 3))
	assert_eq(e["diff_key"], "TANK_HUD_DIFF_EASY")
	assert_false(bool(e["hard"]))
	assert_eq(int(e["losses"]), 0)
	var n := TankHudModel.mission(TankFixturesV4.make("repair"))
	assert_eq(n["diff_key"], "TANK_HUD_DIFF_NORMAL", "a state's default")


## The cool-down is past the mission's last segment: a named plate and a real clock, not a blank 0:00.
func test_the_mission_plate_names_the_cool_down_and_counts_it_down() -> void:
	var s := TankFixturesV4.make("hard", 3)
	s.seg.seg = TankIds.SEG_COOLDOWN
	s.seg.phase_index = s.content.segments().size()
	s.seg.elapsed_s = 30.0
	var m := TankHudModel.mission(s)
	assert_eq(m["title"], "TANK_PHASE_COOLDOWN")
	assert_almost_eq(float(m["left_s"]), PlanValidator.COOLDOWN_S - 30.0, 0.001)
	s.seg.elapsed_s = PlanValidator.COOLDOWN_S + 5.0
	assert_eq(float(TankHudModel.mission(s)["left_s"]), 0.0, "never below zero")


func test_an_unknown_or_auto_difficulty_reads_normal_on_the_plate() -> void:
	var s := TankFixturesV4.make("hard", 3)
	for v: String in [TankIds.DIFF_AUTO, "", "nonsense"]:
		s.difficulty = v
		assert_eq(TankHudModel.difficulty(s)["key"], "TANK_HUD_DIFF_NORMAL", "'%s'" % v)


func test_every_difficulty_tag_fits_the_mission_plate_beside_its_losses() -> void:
	var g: TankGame = autofree(X.game(X.state(1)))
	for key: String in ["TANK_HUD_DIFF_EASY", "TANK_HUD_DIFF_NORMAL", "TANK_HUD_DIFF_HARD"]:
		var tag := TankHud.tx(g, key)
		assert_ne(tag, key, "%s has a string" % key)
		var lost := TankHud.tx(g, "TANK_HUD_LOSSES", [9])
		assert_lt(D.tall_w(tag) + 5.0 + D.tall_w(lost), 110.0, "room left for the title")


func test_the_mission_plate_draws_with_tag_and_losses() -> void:
	var s := TankFixturesV4.make("tank_lost", 3)
	var g: TankGame = autofree(X.game(s))
	var c := TankHudMission.new().setup(g, TankHud.LAYOUT["mission"]) as TankHudMission
	add_child_autofree(c)
	c.refresh()
	c.queue_redraw()
	await wait_physics_frames(2)
	assert_gt(c.draws, 0)


func test_the_roam_board_carries_the_tag() -> void:
	var s := TankFixturesV4.make("roam_west", 3)
	s.difficulty = TankIds.DIFF_HARD
	s.score.losses = 2
	var g: TankGame = autofree(X.game(s))
	var b := TankHudBoard.new().setup(g, TankHud.LAYOUT["roam_board"]) as TankHudBoard
	add_child_autofree(b)
	b.refresh()
	assert_eq(b.diff_key, "TANK_HUD_DIFF_HARD")
	assert_true(b.hard)
	assert_eq(b.losses, 2)
	b.queue_redraw()
	await wait_physics_frames(2)
	assert_gt(b.draws, 0)


func test_the_roam_strip_places_a_far_enemy_by_range() -> void:
	var s := TankFixturesV4.make("roam_west", 3)
	var g: TankGame = autofree(X.game(s))
	var strip := TankHudRoamStrip.new().setup(g, TankHud.LAYOUT["roam_strip"]) as TankHudRoamStrip
	add_child_autofree(strip)
	strip.refresh()
	var at_m := s.roam.map_m + float(s.hull.dir) * s.enemy(301).range_m
	var found := false
	for p: float in strip.patrols:
		if absf(p - at_m) < 0.5:
			found = true
	assert_true(found, "%f among %s" % [at_m, strip.patrols])


# --- holding force --------------------------------------------------------------------------------


func test_the_objective_says_holding_force() -> void:
	var g: TankGame = autofree(X.game(X.state(1)))
	var s := TankFixturesV4.make("far_duel", 3)
	var m := TankHudModel.mission(s)
	assert_eq(m["obj_key"], "TANK_OBJ_HOLD")
	assert_eq(m["obj_args"], [0, 3])
	assert_eq(TankHud.tx(g, "TANK_OBJ_HOLD", m["obj_args"]), "Holding force 0/3")
	assert_eq(TankHudModel.objective(s)["key"], "TANK_OBJ_HOLD")


# --- telegraphs on the far frame ------------------------------------------------------------------


func test_an_evadable_shell_keeps_the_surge_line_after_the_telegraph() -> void:
	var s := TankFixturesV4.make("far_duel", 3)
	for e in s.enemies:
		e.telegraph_s = 0.0
	var left := TankHudModel.telegraph_left(s)
	assert_almost_eq(left, s.shells[0].left_s, 0.001, "the shell's flight")
	var sh := TankHudModel.evadable_shell(s)
	assert_eq(int(sh["id"]), s.shells[0].id)
	assert_gte(float(sh["total"]), float(sh["left"]))
	s.shells[0].left_s = 0.0
	assert_true(TankHudModel.evadable_shell(s).is_empty(), "landed")
	assert_eq(TankHudModel.telegraph_left(s), 0.0)


func test_the_soonest_of_two_evadable_shells_counts() -> void:
	var s := TankFixturesV4.make("cap_v4")
	var soonest := INF
	for sh in s.shells:
		if sh.far and sh.evadable and not sh.friendly:
			soonest = minf(soonest, sh.left_s)
	assert_almost_eq(float(TankHudModel.evadable_shell(s)["left"]), soonest, 0.001)


func test_a_friendly_or_unevadable_shell_is_not_a_surge() -> void:
	var s := TankFixturesV4.make("incoming", 3)
	assert_true(TankHudModel.evadable_shell(s).is_empty(), "this enemy shot has no telegraph")
	var f := TankFixturesV4.make("advance_far", 3)
	assert_true(TankHudModel.evadable_shell(f).is_empty(), "our own")


func test_the_telegraph_length_follows_the_difficulty() -> void:
	var s := TankFixturesV4.make("far_duel", 3)
	var e := s.enemy(21)
	e.telegraph_s = 0.1
	var at_normal := 0.0
	for t: Dictionary in TankHudModel.telegraphs(s):
		if int(t["id"]) == 21:
			at_normal = float(t["total"])
	s.difficulty = TankIds.DIFF_HARD
	for t: Dictionary in TankHudModel.telegraphs(s):
		if int(t["id"]) == 21:
			var want := at_normal * TankDifficulty.mult(s, "telegraph")
			assert_almost_eq(float(t["total"]), want, 0.001, "Hard's shorter telegraph")


func test_the_boss_bars_read_the_difficultys_maxima() -> void:
	var s := TankFixturesV4.make("boss_far", 3)
	s.difficulty = TankIds.DIFF_HARD
	var def := s.content.boss_def()
	var k := s.content.enemy_scale(s.hull.tank) * TankDifficulty.mult(s, "hp")
	s.boss.bogie_hp = [float(def["bogie_hp"]) * k * 0.5, 0.0, 0.0]
	var bars := TankHudModel.boss_bars(s)
	assert_almost_eq(float((bars["bogies"] as Array)[0]), 0.5, 0.001, "half of Hard's maximum")


# --- TANK LOST ------------------------------------------------------------------------------------


func test_tank_lost_shows_through_the_tow_and_a_moment_after() -> void:
	var s := TankFixturesV4.make("tank_lost", 3)
	var c := _lost(s)
	c.tick(0.05)
	c.refresh()
	assert_true(c.showing(), "under the tow")
	assert_almost_eq(float(c.m["tow"]), 5.0, 0.001)
	assert_eq(int(c.m["losses"]), 1)
	s.hull.tow_s = 0.0
	c.tick(1.0)
	c.refresh()
	assert_true(c.showing(), "a moment after")
	assert_false(c.m.is_empty())
	c.tick(0.6)
	c.refresh()
	assert_false(c.showing(), "then gone")
	assert_true(c.m.is_empty())


func test_the_lost_hold_is_pure_wall_clock() -> void:
	assert_eq(TankHudLost.next_hold(0.0, 3.0, 0.1), TankHudLost.HOLD_S, "full while towed")
	assert_almost_eq(TankHudLost.next_hold(1.5, 0.0, 0.5), 1.0, 0.001)
	assert_eq(TankHudLost.next_hold(0.2, 0.0, 0.5), 0.0)


func test_tank_lost_is_silent_on_every_other_fixture() -> void:
	for n: String in ["far_duel", "easy_breakdown", "restart", "repair"]:
		var c := _lost(TankFixturesV4.make(n))
		c.tick(0.05)
		c.refresh()
		assert_false(c.showing(), n)


func test_tank_lost_draws_and_its_text_fits_the_plate() -> void:
	var s := TankFixturesV4.make("tank_lost", 3)
	s.score.losses = 30
	var c := _lost(s)
	c.tick(0.05)
	c.refresh()
	c.queue_redraw()
	await wait_physics_frames(2)
	assert_gt(c.draws, 0)
	var g: TankGame = c.game
	var w := float(TankHud.LAYOUT["lost"].size.x)
	assert_lt(D.tall_w(TankHud.tx(g, "TANK_HUD_LOST")), w - 40.0, "the title")
	var row := D.tall_w(TankHud.tx(g, "TANK_HUD_TOW", [8]))
	row += TankHudLost.PIPS_MAX * (TankHudLost.PIP_W + 2.0)
	assert_lt(row, w - 20.0, "the countdown beside a full row of pips")


func test_the_lost_plate_stays_clear_of_the_other_plates_on_every_canvas() -> void:
	for art: Vector2i in (
		[Vector2i(852, 480), Vector2i(853, 480), Vector2i(960, 540)]
		+ [Vector2i(1146, 480), Vector2i(1280, 680)]
	):
		var lost := TankHud.anchored(TankHud.LAYOUT["lost"], art)
		for key: String in ["mission", "toasts", "hull", "boss", "banners", "roam_strip"]:
			var r := TankHud.anchored(TankHud.LAYOUT[key], art)
			assert_false(lost.intersects(r), "%s on %s: %s %s" % [key, art, lost, r])
		for key2: String in ["roam_toasts", "roam_board", "roam_hull"]:
			var r2 := TankHud.anchored(TankHud.LAYOUT[key2], art)
			assert_false(lost.intersects(r2), "%s on %s" % [key2, art])


func test_my_numbers_say_keep_riding_under_a_tow() -> void:
	var s := TankFixturesV4.make("tank_lost", 3)
	for r in s.riders:
		var line := _line(s, r, Wl.SIM)
		assert_eq(line["kind"], TankHudModel.DO_TOW, r.engine)
		assert_eq(line["key"], "TANK_HUD_DO_TOW", r.engine)
		assert_false(bool(line["urgent"]))
	var r0 := s.riders[0]
	r0.afk = true
	assert_eq(_line(s, r0, Wl.SIM)["kind"], TankHudModel.DO_RESERVE, "AFK still reads RESERVE")
	r0.afk = false
	s.hull.tow_s = 0.0
	assert_ne(_line(s, r0, Wl.SIM)["kind"], TankHudModel.DO_TOW, "the tow is over")


func test_every_new_string_has_a_value_in_the_stencil_faces() -> void:
	var g: TankGame = autofree(X.game(X.state(2)))
	var have := {}
	for ch in TankHudFont.chars():
		have[ch] = true
	for k: String in [
		"TANK_HUD_LOST",
		"TANK_HUD_TOW",
		"TANK_HUD_LOSSES",
		"TANK_HUD_DO_TOW",
		"TANK_HUD_DIFF_EASY",
		"TANK_HUD_DIFF_NORMAL",
		"TANK_HUD_DIFF_HARD",
		"TANK_OBJ_HOLD",
		"TANK_ENGINE_REPAIR",
		"TANK_HELP_RANGE",
		"TANK_HELP_PIP",
		"TANK_HELP_NEAR",
		"TANK_HELP_REPAIR",
	]:
		var t := TankHud.tx(g, k, ["3", "9"])
		assert_ne(t, k, "%s has a string" % k)
		for ch in t.to_upper() + t.to_lower():
			assert_true(have.has(ch), "%s: %s" % [k, ch])


# --- help -----------------------------------------------------------------------------------------


func test_the_help_lists_the_specs_entries() -> void:
	var keys: Array[String] = []
	for e: Dictionary in TankHud.help(false):
		keys.append(str(e["text"]))
	assert_eq(keys.size(), 8, "eight entries")
	for k: String in [
		"TANK_HELP_NUMBERS",
		"TANK_HELP_SEATS",
		"TANK_HELP_HULL",
		"TANK_HELP_SURGE",
		"TANK_HELP_RANGE",
		"TANK_HELP_PIP",
		"TANK_HELP_NEAR",
		"TANK_HELP_REPAIR",
	]:
		assert_has(keys, k)
	assert_does_not_have(keys, "TANK_HELP_MISSION")
	assert_does_not_have(keys, "TANK_HELP_SEAT_LOCK", "no lock since 0.3.1")
	var roam: Array[String] = []
	for e: Dictionary in TankHud.help(true):
		roam.append(str(e["text"]))
	assert_does_not_have(roam, "TANK_HELP_SEAT_LOCK")
	for k: String in ["TANK_HELP_RANGE", "TANK_HELP_PIP", "TANK_HELP_NEAR", "TANK_HELP_REPAIR"]:
		assert_has(roam, k)


## Where the HUD moves a help point on `art`: with the plate that holds it (TankHud.LAYOUT, plates
## before the tags), else with its half of the canvas through the tags' rect.
func _moved(p: Vector2, art: Vector2i) -> Vector2:
	for key: String in ["mission", "hull", "boss", "mine", "seats", "lost", "tags"]:
		var r: Rect2i = TankHud.LAYOUT[key]
		if Rect2(r).has_point(p):
			return p + Vector2(TankHud.anchored(r, art).position - r.position)
	return p


func _target(key: String) -> Vector2:
	for e: Dictionary in TankHud.help(false):
		if str(e["text"]) == key:
			return e["arrow_to"]
	return Vector2(-1, -1)


func test_the_arrows_land_on_what_they_explain_on_every_canvas() -> void:
	for art in CANVASES:
		var panels := TankFarMap.panels(Vector2(art), false)
		var far: Rect2 = panels["far"]
		var pip: Rect2 = panels["pip"]
		var near: Rect2 = panels["near"]
		var range_to := _moved(_target("TANK_HELP_RANGE"), art)
		assert_true(far.has_point(range_to), "%s: range arrow on the far panel" % art)
		assert_false(pip.has_point(range_to), "%s: not on the PiP" % art)
		var pip_to := _moved(_target("TANK_HELP_PIP"), art)
		assert_between(pip_to.x, pip.position.x, pip.end.x, "%s: under the PiP's span" % art)
		if art.y <= TankHud.BASE.y:
			assert_true(pip.has_point(pip_to), "%s: on the PiP" % art)
		assert_true(near.has_point(_moved(_target("TANK_HELP_NEAR"), art)), "%s: near panel" % art)
		var own := TankHud.anchored(TankHud.LAYOUT["seats"], art)
		var last := TankHudSeats.card_rects(art)[TankIds.SEATS.find(TankIds.ENGINE_REPAIR)]
		var card := Rect2(last.position + Vector2(own.position), last.size)
		var to := _moved(_target("TANK_HELP_REPAIR"), art)
		assert_true(card.has_point(to), "%s: %s on the Repairs card %s" % [art, to, card])
