extends GutTest
## The plates around the cockpit (docs/games/siege.md 3 "HUD"): the session plate, the teammate
## cards, the right column (gate, tar, gold, stations, Overdrive) and what is pinned to the world.

const K := preload("res://tests/games/siege/hud/siege_hud_kit.gd")
const F := preload("res://tests/games/siege/siege_fakes.gd")
const FIX := preload("res://tests/games/siege/fixtures/siege_fixtures.gd")

var _games: Array[SiegeGame] = []


func after_each() -> void:
	for g in _games:
		F.free_game(g)
	_games.clear()


func _g(index: int = 4, elapsed_s: float = 105.0) -> SiegeGame:
	var g := K.game(index, elapsed_s)
	_games.append(g)
	return g


# --- the session plate --------------------------------------------------------------------------


func test_session_title_and_ends_in_count_the_cool_down() -> void:
	var f := SiegeHudModel.session_face(_g(4, 105.0))
	assert_eq(f["title"].to_upper(), "WAVE 2 OF 3")
	assert_eq(f["ends"].to_upper(), "ENDS IN 14:15", "the mock's wave state")
	assert_eq(f["total_s"], 1860.0, "the shift's 1680 s and the 180 s cool-down")
	assert_eq(f["elapsed_s"], 1005.0)
	assert_eq(f["index"], 4)


func test_session_titles_by_phase() -> void:
	var cases := [
		[0, 150.0, "WARM-UP WAVE", "ENDS IN 28:30"],
		[1, 90.0, "BUILD BREAK", "ENDS IN 24:30"],
		[6, 20.0, "WAVE 3 OF 3", "ENDS IN 7:40"],
		[7, 80.0, "COOL-DOWN", "ENDS IN 1:40"],
	]
	var g := _g()
	for c: Array in cases:
		K.stand(g, int(c[0]), float(c[1]))
		var f := SiegeHudModel.session_face(g)
		assert_eq(f["title"].to_upper(), c[2])
		assert_eq(f["ends"].to_upper(), c[3])


func test_the_profile_strip_has_every_phase_with_its_effort() -> void:
	var f := SiegeHudModel.session_face(_g())
	var phases: Array = f["phases"]
	assert_eq(phases.size(), 8, "seven and the cool-down")
	assert_eq(phases[0]["p0"], 50.0)
	assert_eq(phases[0]["p1"], 65.0, "the warm-up ramps")
	assert_eq(phases[0]["kind"], Wl.WARMUP)
	assert_eq(phases[2]["kind"], Wl.WORK)
	assert_eq(phases[2]["p0"], 95.0)
	assert_eq(phases[7]["kind"], Wl.COOLDOWN)
	assert_eq(phases[7]["d"], 180.0)


func test_a_rider_with_an_offset_sees_their_own_targets() -> void:
	var g := _g()
	g.ctx.player(1).options["wave_offset"] = -10
	var f := SiegeHudModel.session_face(g)
	assert_eq(f["phases"][2]["p0"], 85.0)


func test_rush_marks_sit_on_the_endurance_wave() -> void:
	var g := K.game(2, 10.0, "endurance")
	_games.append(g)
	var f := SiegeHudModel.session_face(g)
	assert_gt((f["rush"] as Array).size(), 0)
	assert_gt(float(f["rush"][0]), float(f["phases"][2]["from_s"]))


func test_enemies_come_as_icons_engines_in_range_first() -> void:
	var g := _g()
	var icons := SiegeHudModel.enemy_icons(g.state)
	assert_gt(icons.size(), 2)
	assert_eq(icons[0]["icon"], "tower", "the fixture's tower is near")
	assert_true(icons[0]["warn"])
	var alive := g.state.alive_by_type()
	for e: Dictionary in icons:
		assert_eq(e["n"], alive[SiegeIds.ENEMY_NAMES.find(e["icon"])], str(e["icon"]))
	K.stand(g, 1, 10.0)
	assert_eq(SiegeHudModel.enemy_icons(g.state), [], "no enemies in a break")


func test_warnings_are_short_and_in_order() -> void:
	var g := _g()
	var st := g.state
	st.tar.boarded = false
	st.wave.rush_s = 0.0
	var w := SiegeHudModel.warning(st)
	assert_eq(w["key"], "SIEGE_HUD_TOWER_ON_ROAD")
	assert_eq(
		SiegeHudModel.session_face(g)["warning"].to_upper(), "TOWER %d M" % roundi(w["args"][0])
	)
	st.breach_s = 6.0
	assert_eq(SiegeHudModel.warning(st)["key"], "SIEGE_HUD_BREACH")
	st.breach_s = 0.0
	st.enemies.clear()
	st.queue.clear()
	st.queue_len = 0
	st.gate_hp = 10.0
	assert_eq(SiegeHudModel.warning(st)["key"], "SIEGE_HUD_GATE_FAILING_SHORT")
	st.gate_hp = st.gate_max
	assert_eq(SiegeHudModel.warning(st), {})
	st.tar.boarded = true
	assert_eq(SiegeHudModel.warning(st)["key"], "SIEGE_HUD_BOARDED")


func test_no_rush_warning_without_a_rush_ahead() -> void:
	var st := SiegeKit.state("endurance")
	var phases: Array = st.content.shift["phases"]
	for i in phases.size():
		if not (phases[i] as Dictionary).get("rushes_at_s", []).is_empty():
			st.phase_index = i
			st.phase_duration_s = float(phases[i]["duration_s"])
			st.role = SiegeIds.ROLE_WAVE
			st.phase_kind = Wl.WORK
			break
	st.enemies.clear()
	var rushes := SiegeHudModel.rush_times(st)
	assert_gt(rushes.size(), 1, "the endurance wave has rushes")
	# a restarted client: rush_next 0, the first rush long past, the next one far off
	st.wave.rush_next = 0
	st.phase_elapsed_s = rushes[0] + 40.0
	if rushes[1] - st.phase_elapsed_s <= 15.0:
		st.phase_elapsed_s = rushes[0] + 1.0
	var w := SiegeHudModel.warning(st)
	assert_false(not w.is_empty() and w["key"] == "SIEGE_WARN_RUSH", "no warning for a past rush")
	st.phase_elapsed_s = rushes[1] - 10.0
	assert_eq(SiegeHudModel.warning(st).get("key", ""), "SIEGE_WARN_RUSH")


# --- the teammate cards -------------------------------------------------------------------------


func test_cards_are_only_teammates_in_slot_order() -> void:
	var g := _g()
	var cards := SiegeHudModel.crew_cards(g, {})
	assert_eq(cards.size(), 3, "your own numbers are in the cockpit")
	assert_eq(cards[0]["slot"], 1)
	assert_eq(cards[2]["slot"], 3)
	assert_eq(cards[0]["name"], "Rider 2")
	assert_eq(cards[2]["name"], "Bot 1")
	for c: Dictionary in cards:
		assert_eq(c["shape"], Wl.SLOT_SHAPES[int(c["slot"])], "the rider's shape with their colour")
		assert_eq(c["color"], Wl.SLOT_COLORS[int(c["slot"])])


func test_solo_has_no_cards() -> void:
	var g := _g()
	g.ctx.local_peer = 1
	var one: Array[SiegeRiderState] = [g.state.rider(1)]
	g.state.riders = one
	assert_eq(SiegeHudModel.crew_cards(g, {}), [])


func test_a_card_has_watts_percent_and_the_station_from_the_state() -> void:
	var g := _g()
	var r := g.state.rider_at(3)
	r.raw_w = 188.0
	r.ftp = 200.0
	r.target = SiegeIds.STATION_TAR
	var c: Dictionary = SiegeHudModel.crew_cards(g, {})[2]
	assert_eq(c["w"], 188)
	assert_eq(c["pct"], 94)
	assert_eq(c["icon"], "tar")


func test_marks_rescue_chip_afk_and_overdrive() -> void:
	var g := _g()
	var cards := SiegeHudModel.crew_cards(g, {})
	assert_eq(cards[0]["mark"].to_upper(), "RESCUE", "the fixture's slot 1")
	assert_eq(cards[0]["mark_kind"], "alarm")
	var r := g.state.rider_at(2)
	r.afk = true
	var c: Dictionary = SiegeHudModel.crew_cards(g, {})[1]
	assert_eq(c["mark"].to_upper(), "AFK")
	assert_eq(c["mark_kind"], "dim")
	assert_true(c["afk"])
	r.afk = false
	r.od_state = SiegeIds.OD_ACTIVE
	r.od_s = 12.0
	c = SiegeHudModel.crew_cards(g, {})[1]
	assert_eq(c["mark"].to_upper(), "OD 0:12")
	assert_eq(c["mark_kind"], "od")


func test_a_dropped_teammate_shows_dashes() -> void:
	var g := _g()
	g.state.rider_at(2).connected = false
	var c: Dictionary = SiegeHudModel.crew_cards(g, {})[1]
	assert_eq(c["w"], -1)
	assert_true(c["afk"], "a dropped peer is AFK")


func test_the_lamp_holds_through_a_wobble() -> void:
	var g := _g(4, 105.0)
	var r := g.state.rider_at(3)  # the bot, FTP 260: target 247 W, band 234.65-259.35
	var tracks := {}
	var seen := {}
	for i in 40:
		g.state.t = 100.0 + float(i) * 0.5
		r.raw_w = 247.0 + (10.0 if i % 2 == 0 else -10.0)
		seen[SiegeHudModel.crew_cards(g, tracks)[2]["lamp"]] = true
	assert_eq(seen.keys(), [HudRiderNumbers.IN_BAND])
	for i in 10:
		g.state.t = 200.0 + float(i)
		r.raw_w = 150.0
		SiegeHudModel.crew_cards(g, tracks)
	assert_eq(SiegeHudModel.crew_cards(g, tracks)[2]["lamp"], HudRiderNumbers.UNDER)


func test_a_clients_cards_come_from_the_snapshot() -> void:
	var client := F.make_game(F.make_ctx(3, 1, "vo2", Wl.CLIENT, 2))
	_games.append(client)
	client.apply_snapshot(
		Protocol.apply_int_fields(FIX.snapshot(), client.int_fields()["snapshot"])
	)
	var cards := SiegeHudModel.crew_cards(client, {})
	assert_eq(cards.size(), 3)
	assert_eq(cards[0]["slot"], 0)
	assert_eq(cards[0]["w"], 240)
	assert_eq(cards[0]["mark_kind"], "od", "slot 0 is in Overdrive")
	assert_eq(cards[1]["w"], 252)
	assert_eq(cards[2]["name"], "Bot 1")
	assert_ne(cards[0]["color"], cards[1]["color"])


func test_a_card_draws_with_a_long_or_foreign_name() -> void:
	var g := _g()
	g.ctx.player(2).name = "Schoedler-von-Hohenzollern"
	g.ctx.player(3).name = "Zoë 日本 ☃"
	var ctl := K.ctl(SiegeHudCrew.new(), g, SiegeHudCrew.RECT) as SiegeHudCrew
	add_child_autofree(ctl)
	ctl.refresh()
	await wait_physics_frames(2)
	assert_gt(ctl.draws, 0)
	assert_eq((ctl.model["cards"] as Array).size(), 3)
	assert_lte(SiegeHudType.width(SiegeHudType.fit(g.ctx.player(2).name, "LABEL", 68), "LABEL"), 68)


# --- the right column ------------------------------------------------------------------------------


func _column(g: SiegeGame) -> SiegeHudColumn:
	var ctl := K.ctl(SiegeHudColumn.new(), g, SiegeHudColumn.RECT) as SiegeHudColumn
	add_child_autofree(ctl)
	ctl.refresh()
	return ctl


func test_the_gate_turns_to_alarm_when_low() -> void:
	var g := _g()
	g.state.gate_hp = 98.0
	g.state.gate_max = 130.0
	var f := SiegeHudModel.fort_face(g.state, g.state.rider(1))
	assert_eq(f["gate"], 98)
	assert_eq(f["gate_max"], 130)
	assert_false(f["low"])
	g.state.gate_hp = 24.0
	g.state.gate_max = 180.0
	assert_true(SiegeHudModel.fort_face(g.state, g.state.rider(1))["low"])


func test_the_tar_row_reads_the_curtain_and_the_cauldrons() -> void:
	var g := _g()
	g.state.tar.curtain_hp = 79.5
	g.state.tar.cauldron_l = 210.9
	var f := SiegeHudModel.fort_face(g.state, g.state.rider(1))
	assert_eq(f["curtain"], 80)
	assert_eq(f["curtain_max"], roundi(g.state.curtain_max()))
	assert_eq(f["litres"], 210)


func test_gold_is_small_in_waves_and_big_while_the_shop_is_open() -> void:
	var g := _g(4, 105.0)
	g.state.rider(1).gold = 53.7
	var wave := SiegeHudModel.fort_face(g.state, g.state.rider(1))
	assert_eq(wave["gold"], 53)
	assert_false(wave["gold_big"])
	K.stand(g, 1, 10.0)
	assert_true(SiegeHudModel.fort_face(g.state, g.state.rider(1))["gold_big"])


func test_a_bigger_gold_plate_moves_the_stations_and_overdrive_down() -> void:
	var g := _g(4, 105.0)
	var ctl := _column(g)
	var y := int(ctl.model["stations_y"])
	var od := ctl.od_rect.position.y
	K.stand(g, 1, 10.0)
	ctl.refresh()
	assert_eq(int(ctl.model["stations_y"]), y + 12)
	assert_eq(ctl.od_rect.position.y, od + 12)
	await wait_physics_frames(2)
	assert_gt(ctl.draws, 0)


func test_station_rows_show_mine_caps_and_riders() -> void:
	var g := _g()
	var rows := SiegeHudModel.station_rows(g.state, GameStrings.new(), g.state.rider(1))
	assert_eq(rows.size(), 5)
	var me := g.state.rider(1)
	for row: Dictionary in rows:
		var id := int(row["id"])
		assert_eq(int(row["cap"]), g.state.station_cap(id))
		assert_eq(bool(row["mine"]), id == me.target)
		assert_eq(str(row["icon"]), SiegeIds.STATION_NAMES[id])
		var on := 0
		for r in g.state.riders:
			if r.target == id:
				on += 1
		assert_eq(int(row["count"]), on, "riders on %d" % id)


func test_the_hot_station_is_autopilots_pick() -> void:
	var g := _g()
	var me := g.state.rider(1)
	var rows := SiegeHudModel.station_rows(g.state, GameStrings.new(), me)
	var hot := SiegeAutopilot.hot_target(g.state, me)
	for row: Dictionary in rows:
		assert_eq(bool(row["hot"]), int(row["id"]) == hot)


func test_coupling_keeps_your_row_until_it_is_done() -> void:
	var g := _g()
	var me := g.state.rider(1)
	me.target = SiegeIds.STATION_BALLISTA
	me.reconnect_s = 0.0
	var ctl := _column(g)
	assert_eq(float(ctl.model["coupling"]), -1.0)
	me.target = SiegeIds.STATION_TAR
	me.reconnect_s = 0.8
	ctl.refresh()
	assert_almost_eq(float(ctl.model["coupling"]), 0.6, 0.001)
	var rows: Array = ctl.model["rows"]
	assert_true(rows[SiegeIds.STATION_BALLISTA]["mine"], "still there")
	assert_true(rows[SiegeIds.STATION_TAR]["going"], "on its way")
	me.reconnect_s = 0.0
	ctl.refresh()
	rows = ctl.model["rows"]
	assert_true(rows[SiegeIds.STATION_TAR]["mine"])
	assert_false(rows[SiegeIds.STATION_TAR]["going"])
	assert_eq(float(ctl.model["coupling"]), -1.0)


func test_overdrive_faces() -> void:
	var g := _g()
	var r := g.state.rider(1)
	r.od_state = SiegeIds.OD_ACTIVE
	r.od_s = 22.0
	var face := SiegeHudModel.overdrive_face(g)
	assert_eq(face["mode"], SiegeHudModel.OD_ACTIVE)
	assert_eq(face["top"].to_upper(), "OVERDRIVE 0:22")
	assert_eq(face["sub"].to_upper(), "DOUBLE OUTPUT")
	assert_almost_eq(float(face["fill"]), 22.0 / 30.0, 0.001)
	r.od_state = SiegeIds.OD_COOLDOWN
	r.od_cd_s = 74.0
	face = SiegeHudModel.overdrive_face(g)
	assert_eq(face["mode"], SiegeHudModel.OD_COOLDOWN)
	assert_eq(face["top"].to_upper(), "RECHARGING")
	assert_eq(face["sub"], "1:14")
	r.od_state = SiegeIds.OD_READY
	r.od_prompt = true
	face = SiegeHudModel.overdrive_face(g)
	assert_eq(face["mode"], SiegeHudModel.OD_PROMPT)
	assert_eq(face["top"].to_upper(), "OVERDRIVE READY")
	assert_eq(face["sub"].to_upper(), "SURGE TO START")
	assert_true(face["enabled"])


func test_overdrive_closed_says_why() -> void:
	var g := _g(4, 105.0)
	var r := g.state.rider(1)
	r.od_state = SiegeIds.OD_READY
	r.od_prompt = false
	r.rescue = false
	r.raw_w = 220.0
	r.cadence_rpm = 90.0
	var face := SiegeHudModel.overdrive_face(g)
	assert_eq(face["mode"], SiegeHudModel.OD_READY)
	assert_true(face["enabled"], "ready in a WORK wave")
	assert_eq(face["sub"].to_upper(), "PRESS TO START")
	r.rescue = true
	face = SiegeHudModel.overdrive_face(g)
	assert_false(face["enabled"], "never in rescue")
	assert_eq(face["sub"].to_upper(), "NOT IN RESCUE")
	r.rescue = false
	r.afk = true
	assert_eq(SiegeHudModel.overdrive_face(g)["sub"].to_upper(), "NOT WHILE AFK")
	r.afk = false
	r.raw_w = 0.0
	r.cadence_rpm = 0.0
	assert_eq(SiegeHudModel.overdrive_face(g)["sub"].to_upper(), "PEDAL FIRST")
	r.raw_w = 220.0
	r.cadence_rpm = 90.0
	K.stand(g, 4, 280.0)
	face = SiegeHudModel.overdrive_face(g)
	assert_false(face["enabled"], "not with < 30 s left")
	assert_eq(face["sub"].to_upper(), "TOO LATE IN WAVE")
	K.stand(g, 3, 10.0)
	assert_eq(SiegeHudModel.overdrive_face(g)["sub"].to_upper(), "WAVES ONLY")
	K.stand(g, 0, 10.0)
	assert_eq(SiegeHudModel.overdrive_face(g)["sub"].to_upper(), "NOT IN WARM-UP")
	K.stand(g, 7, 10.0)
	assert_eq(SiegeHudModel.overdrive_face(g)["sub"].to_upper(), "WAVES ONLY")


func test_pressing_the_plate_sends_overdrive_only_when_enabled() -> void:
	var g := _g(4, 105.0)
	var r := g.state.rider(1)
	r.od_state = SiegeIds.OD_READY
	r.od_prompt = true
	r.rescue = false
	var ctl := _column(g)
	var inside := (Vector2(ctl.od_rect.position) + Vector2(10, 10)) * ctl.u()
	assert_true(ctl._has_point(inside), "the plate takes the mouse")
	assert_false(ctl._has_point(Vector2(10, 10)), "the gate plate doesn't")
	var press := InputEventMouseButton.new()
	press.pressed = true
	press.button_index = MOUSE_BUTTON_LEFT
	ctl._gui_input(press)
	var sent: Array = (g.ctx.intents as F.Intents).sent
	assert_eq(sent.size(), 1)
	assert_eq(str(sent[0]["k"]), SiegeIds.INTENT_OVERDRIVE)
	r.od_state = SiegeIds.OD_COOLDOWN
	r.od_cd_s = 40.0
	ctl.refresh()
	assert_false(ctl._has_point(inside), "a recharging plate lets the mouse through")


# --- the world --------------------------------------------------------------------------------------


func test_tags_anchor_to_the_live_engines() -> void:
	var g := _g()
	var st := g.state
	var tags := SiegeHudModel.world_tags(st, GameStrings.new())
	assert_gt(tags.size(), 0)
	var near := SiegeHudModel.nearest_engine(st, SiegeIds.ENEMY_TOWER)
	var e: SiegeEnemyState = near["e"]
	var art := st.path.to_art(st.path.point_at(e.prog_m, e.lat_m))
	assert_eq(tags[0]["at"].x, roundi(art.x), "on the tower with SiegePath.to_art")
	assert_eq(tags[0]["at"].y, roundi(art.y) - SiegeHudWorld.TOWER_HEAD_PX)


func test_a_far_or_dead_engine_has_no_tag() -> void:
	var g := _g()
	var st := g.state
	for e in st.enemies:
		if e.type == SiegeIds.ENEMY_TOWER or e.type == SiegeIds.ENEMY_RAM:
			e.hp = 0.0
	assert_eq(SiegeHudModel.world_tags(st, GameStrings.new()), [])
	K.stand(g, 3, 10.0)
	assert_eq(SiegeHudModel.world_tags(st, GameStrings.new()), [], "not in a break")


func test_the_gate_banner_shows_only_while_it_fails_in_a_wave() -> void:
	var g := _g()
	var ctl := K.ctl(SiegeHudWorld.new(), g, SiegeHudWorld.RECT) as SiegeHudWorld
	add_child_autofree(ctl)
	g.state.gate_hp = g.state.gate_max
	ctl.refresh()
	assert_eq(ctl.model["banner"], "")
	g.state.gate_hp = g.state.gate_max * 0.2
	ctl.refresh()
	assert_eq(ctl.model["banner"].to_upper(), "THE GATE IS FAILING")
	var want := g.state.path.to_art(g.state.path.gate_pos + SiegeHudWorld.GATE_LIFT)
	assert_eq(ctl.model["gate"], Vector2i(roundi(want.x), roundi(want.y)), "the leader's end")
	await wait_physics_frames(2)
	assert_gt(ctl.draws, 0)
	K.stand(g, 3, 10.0)
	ctl.refresh()
	assert_eq(ctl.model["banner"], "", "the shop has that corner in breaks")


func test_session_and_world_draw_in_every_phase() -> void:
	var g := _g()
	var session := K.ctl(SiegeHudSession.new(), g, SiegeHudSession.RECT) as SiegeHudSession
	var world := K.ctl(SiegeHudWorld.new(), g, SiegeHudWorld.RECT) as SiegeHudWorld
	add_child_autofree(session)
	add_child_autofree(world)
	for i in [0, 1, 4, 7]:
		K.stand(g, i, 20.0)
		session.refresh()
		world.refresh()
		await wait_physics_frames(1)
	assert_gt(session.draws, 0)
	assert_gt(world.draws, 0)
