extends GutTest
## Siege's own HUD Controls: wave info, the routing card with its connect bar and buttons, the
## Overdrive button, the strip overlay (raw W and %FTP from the snapshot on a client), the rush
## strip.

var _game: SiegeGame = null
var _state: SiegeState = null


func before_each() -> void:
	_state = SiegeFixtures.mid_wave()
	_game = SiegeHudUtil.make_game(_state)


func after_each() -> void:
	SiegeHudUtil.free_game(_game)


func _add(c: Node) -> Node:
	add_child_autofree(c)
	return c


# --- wave info -----------------------------------------------------------------------------------


func test_wave_info_shows_the_wave_the_enemies_and_the_warning() -> void:
	var w := _add(SiegeWaveInfo.new()) as SiegeWaveInfo
	w.game = _game
	w.refresh()
	assert_true(w.visible)
	assert_eq(w.title_label.text, "Wave 2/6")
	assert_string_contains(w.enemy_labels[0].text, "Raiders")
	assert_string_contains(w.enemy_labels[1].text, "Battering ram 1")
	assert_true(w.warn_label.visible, "the ram is at the gate")
	assert_eq(w.warn_label.text, "Battering ram on the road!")


func test_wave_info_in_a_break_shows_only_the_title() -> void:
	var w := _add(SiegeWaveInfo.new()) as SiegeWaveInfo
	w.game = _game
	_state.role = SiegeIds.ROLE_BREAK
	_state.wave_no = 2
	w.refresh()
	assert_eq(w.title_label.text, "Break 2")
	assert_false(w.enemy_labels[0].visible)
	assert_false(w.warn_label.visible)


func test_wave_info_hides_without_a_state() -> void:
	var w := _add(SiegeWaveInfo.new()) as SiegeWaveInfo
	w.refresh()
	assert_false(w.visible)


func test_the_hud_text_sizes_are_readable() -> void:
	var w := _add(SiegeWaveInfo.new()) as SiegeWaveInfo
	assert_gte(w.title_label.label_settings.font_size, 32)
	assert_gte(w.warn_label.label_settings.font_size, 32)
	for l in w.enemy_labels:
		assert_gte(l.label_settings.font_size, WlTheme.LABEL_PX)
	var od := _add(SiegeOverdriveButton.new()) as SiegeOverdriveButton
	assert_gte(od.get_theme_font_size("font_size"), 32)


# --- routing card ---------------------------------------------------------------------------------


func test_route_card_names_the_target_and_hides_the_bar_when_connected() -> void:
	var c := _add(SiegeRouteCard.new()) as SiegeRouteCard
	c.game = _game
	c.refresh()
	assert_true(c.visible)
	assert_eq(c.target_label.text, "Tower 3 (Ballista)")
	assert_false(c.connect_bar.visible)


func test_route_card_connect_bar_fills_over_the_2_s_reconnect() -> void:
	var r := _state.rider_at(0)
	var c := _add(SiegeRouteCard.new()) as SiegeRouteCard
	c.game = _game
	r.reconnect_s = 2.0
	c.refresh()
	assert_true(c.connect_bar.visible)
	assert_eq(c.connect_label.text, "Connecting...")
	assert_almost_eq(c.connect_bar.value, 0.0, 1e-6)
	r.reconnect_s = 0.5
	c.refresh()
	assert_almost_eq(c.connect_bar.value, 0.75, 1e-6)
	r.reconnect_s = 0.0
	c.refresh()
	assert_false(c.connect_bar.visible)


func test_route_buttons_send_route_intents_tagged_button() -> void:
	var c := _add(SiegeRouteCard.new()) as SiegeRouteCard
	c.game = _game
	c.refresh()
	(c.buttons["next"] as Button).pressed.emit()
	(c.buttons["prev"] as Button).pressed.emit()
	(c.buttons["gen"] as Button).pressed.emit()
	(c.buttons["hot"] as Button).pressed.emit()
	var sent := SiegeHudUtil.intents_sent(_game)
	assert_eq(sent.size(), 4)
	var tos: Array[String] = []
	for i: Dictionary in sent:
		assert_eq(i["k"], "route")
		assert_eq(i["via"], "button")
		tos.append(str(i["to"]))
		var n := SiegeIntents.normalize(i)
		assert_false(n.is_empty(), "the host accepts it: %s" % JSON.stringify(i))
	assert_eq(tos, ["next", "prev", "gen", "hot"] as Array[String])


func test_route_buttons_are_off_while_the_shop_is_open() -> void:
	var c := _add(SiegeRouteCard.new()) as SiegeRouteCard
	c.game = _game
	_state.role = SiegeIds.ROLE_BREAK
	c.refresh()
	for b: Button in c.buttons.values():
		assert_true(b.disabled)
	_state.role = SiegeIds.ROLE_WAVE
	c.refresh()
	for b: Button in c.buttons.values():
		assert_false(b.disabled)


# --- Overdrive button -----------------------------------------------------------------------------


func test_overdrive_button_shows_the_seconds_while_it_runs() -> void:
	var b := _add(SiegeOverdriveButton.new()) as SiegeOverdriveButton
	b.game = _game
	b.refresh()
	assert_eq(b.mode, SiegeHudModel.OD_ACTIVE)
	assert_eq(b.text, "12 s")
	assert_true(b.disabled)


func test_overdrive_button_prompt_and_press() -> void:
	var r := _state.rider_at(0)
	r.od_state = SiegeIds.OD_READY
	r.od_prompt = true
	var b := _add(SiegeOverdriveButton.new()) as SiegeOverdriveButton
	b.game = _game
	b.refresh()
	assert_eq(b.mode, SiegeHudModel.OD_PROMPT)
	assert_eq(b.text, "Surge for Overdrive!")
	assert_false(b.disabled)
	b.pressed.emit()
	var sent := SiegeHudUtil.intents_sent(_game)
	assert_eq(sent.size(), 1)
	assert_eq(sent[0], {"k": "overdrive", "via": "button"})
	assert_eq(SiegeIntents.normalize(sent[0])["via"], "button")


func test_overdrive_button_cooldown() -> void:
	var r := _state.rider_at(0)
	r.od_state = SiegeIds.OD_COOLDOWN
	r.od_cd_s = 45.0
	var b := _add(SiegeOverdriveButton.new()) as SiegeOverdriveButton
	b.game = _game
	b.refresh()
	assert_eq(b.mode, SiegeHudModel.OD_COOLDOWN)
	assert_eq(b.text, "Recharging 45 s")
	assert_almost_eq(b.fill, 0.5, 1e-4)
	assert_true(b.disabled)


func test_overdrive_button_hides_without_a_own_rider() -> void:
	_game.ctx.local_peer = 99
	var b := _add(SiegeOverdriveButton.new()) as SiegeOverdriveButton
	b.game = _game
	b.refresh()
	assert_false(b.visible)


# --- strip overlay --------------------------------------------------------------------------------


func test_the_strip_has_a_cell_per_rider_with_target_and_markers() -> void:
	var s := _add(SiegeStripOverlay.new()) as SiegeStripOverlay
	s.game = _game
	s.refresh()
	assert_eq(s.cells.size(), 4)
	for c in s.cells:
		assert_true(c.visible)
	assert_eq(s.cells[0].target_label.text, "T3")
	assert_eq(s.cells[1].target_label.text, "GEN")
	assert_eq(s.cells[2].target_label.text, "T4")
	assert_eq(s.cells[3].target_label.text, "T2")
	assert_string_contains(s.cells[0].marker_label.text, "OD 12")
	assert_string_contains(s.cells[1].marker_label.text, "Rescue")
	assert_string_contains(s.cells[1].marker_label.text, "OD ...", "recharging")
	assert_eq(s.cells[2].marker_label.text, "", "reconnecting shows no marker")
	assert_true(s.cells[2].icon.dim, "no output while reconnecting")
	assert_false(s.cells[0].icon.dim)


func test_the_strip_shows_raw_w_and_percent_ftp() -> void:
	var s := _add(SiegeStripOverlay.new()) as SiegeStripOverlay
	s.game = _game
	s.refresh()
	assert_eq(s.cells[0].watts_label.text, "240 W  120%")
	assert_eq(s.cells[3].watts_label.text, "250 W  96%")


func test_a_clients_strip_reads_raw_w_and_ftp_from_the_snapshot() -> void:
	# A client: a fresh state, only the snapshot applied.
	var client := SiegeState.create(
		SiegeFixtures.content("vo2"), SiegeFixtures.slots(), Wl.FAIR_FTP, null
	)
	SiegeSnapshot.apply(client, SiegeFixtures.snapshot())
	var g := SiegeHudUtil.make_game(client)
	var s := _add(SiegeStripOverlay.new()) as SiegeStripOverlay
	s.game = g
	s.refresh()
	var snap_rows: Array = SiegeFixtures.snapshot()["r"]
	for row: Array in snap_rows:
		var slot := int(row[SiegeSnapshotSchema.R_SLOT])
		var raw := int(row[SiegeSnapshotSchema.R_RAW_W])
		var ftp := 200.0 + 20.0 * slot
		var expect := "%d W  %d%%" % [raw, roundi(float(raw) / ftp * 100.0)]
		assert_eq(s.cells[slot].watts_label.text, expect, "slot %d from the snapshot" % slot)
	SiegeHudUtil.free_game(g)


func test_afk_and_rescue_markers() -> void:
	_state.rider_at(2).afk = true
	var s := _add(SiegeStripOverlay.new()) as SiegeStripOverlay
	s.game = _game
	s.refresh()
	assert_string_contains(s.cells[2].marker_label.text, "AFK")
	assert_lt(s.cells[2].modulate.a, 1.0)


func test_cells_match_the_kit_strip_spacing() -> void:
	var s := _add(SiegeStripOverlay.new()) as SiegeStripOverlay
	assert_eq(s.get_theme_constant("separation"), 10)
	assert_eq(SiegeStripCell.SIZE.x, 260.0)


func test_an_empty_wheel_has_no_cell() -> void:
	var one := SiegeState.create(
		SiegeFixtures.content("short"), SiegeFakes.make_slots(1, 0), Wl.FAIR_FTP, null
	)
	var g := SiegeHudUtil.make_game(one)
	var s := _add(SiegeStripOverlay.new()) as SiegeStripOverlay
	s.game = g
	s.refresh()
	assert_true(s.cells[0].visible)
	for i in range(1, 4):
		assert_false(s.cells[i].visible)
	SiegeHudUtil.free_game(g)


# --- rush strip -----------------------------------------------------------------------------------


func test_the_rush_strip_shows_only_in_a_wave_with_rushes() -> void:
	var r := _add(SiegeRushStrip.new()) as SiegeRushStrip
	r.game = _game
	r.refresh()
	assert_false(r.visible, "vo2 has no rushes")
	var g := SiegeHudUtil.make_game(SiegeFixtures.mid_wave(SiegeFixtures.content("endurance")))
	g.metas = SiegePlanBuilder.phase_metas(g.state.content.shift, "endurance")
	g.state.phase_index = 2
	g.state.role = SiegeIds.ROLE_WAVE
	g.state.phase_duration_s = 2700.0
	g.state.phase_elapsed_s = 700.0
	r.game = g
	r.refresh()
	assert_true(r.visible)
	assert_eq(r.fractions.size(), 5)
	assert_almost_eq(r.progress, 700.0 / 2700.0, 1e-4)
	assert_eq(r.next_index, 1, "the 480 s rush is past, 960 s is next")
	assert_false(r.rush_on)
	g.state.wave.rush_s = 20.0
	r.refresh()
	assert_true(r.rush_on)
	g.state.role = SiegeIds.ROLE_BREAK
	r.refresh()
	assert_false(r.visible)
	SiegeHudUtil.free_game(g)
