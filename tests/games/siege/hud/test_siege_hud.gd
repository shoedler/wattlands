extends GutTest
## Siege's HUD (docs/games/siege.md 3 "HUD"): the spec's widgets and controls, the help entries,
## the route card, the Overdrive button, the wave info, the curtain card, the teammate strip and
## the break shop, from the mid-wave fixture; and every string key the HUD and view use exists.

const F := preload("res://tests/games/siege/siege_fakes.gd")
const FIX := preload("res://tests/games/siege/fixtures/siege_fixtures.gd")
const STRINGS := "res://content/siege/strings.csv"


func _game(state: SiegeState = null) -> SiegeGame:
	var g := F.make_game(F.make_ctx(3, 1, "vo2", Wl.SOLO, 1))
	if state == null:
		state = FIX.mid_wave()
	g.state = state
	g.content = state.content
	return g


func _controls(spec: HudSpec) -> Array:
	var out: Array = []
	for c: Dictionary in spec.controls:
		out.append(c["control"])
	return out


func _find(spec: HudSpec, type: Variant) -> Variant:
	for c: Variant in _controls(spec):
		if is_instance_of(c, type):
			return c
	return null


func test_spec_holds_the_kit_widgets_and_sieges_controls() -> void:
	var g := _game()
	var spec := SiegeHud.spec(g)
	for w in [
		HudSpec.TIMELINE,
		HudSpec.POWER_GAUGE,
		HudSpec.CADENCE,
		HudSpec.WBAL,
		HudSpec.READOUT,
		HudSpec.GEAR
	]:
		assert_true(spec.has_widget(w), w)
	assert_false(spec.has_widget(HudSpec.TEAMMATES), "Siege's own strip replaces the kit's")
	for type in [
		SiegeRushStrip,
		SiegeWaveInfo,
		SiegeCurtainCard,
		SiegeStripOverlay,
		SiegeOverdriveButton,
		SiegeRouteCard,
		SiegeShopPanel
	]:
		assert_not_null(_find(spec, type), str(type))
	var ids := []
	for wd: Dictionary in spec.widgets:
		if str(wd.get("widget", "")) == HudSpec.READOUT:
			ids.append(str((wd.get("options", {}) as Dictionary).get("id", "")))
	assert_true(ids.has(SiegeHud.READOUT_GATE))
	assert_true(ids.has(SiegeHud.READOUT_GOLD))
	for c: Variant in _controls(spec):
		(c as Node).free()
	F.free_game(g)


func test_help_covers_the_seven_entries_with_arrows_on_the_art() -> void:
	var g := _game()
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
	var spec := SiegeHud.spec(g)
	assert_eq(spec.help.size(), 7)
	for c: Variant in _controls(spec):
		(c as Node).free()
	F.free_game(g)


func test_route_card_shows_the_five_stations_caps_and_coupling() -> void:
	var g := _game()
	var card := SiegeRouteCard.new()
	card.game = g
	add_child_autofree(card)
	card.refresh()
	assert_true(card.visible)
	assert_eq(card.rows.size(), 5)
	var me := g.state.rider(1)
	for row: Dictionary in card.rows:
		var id := int(row["id"])
		assert_eq(int(row["cap"]), g.state.station_cap(id))
		assert_eq(bool(row["mine"]), id == me.target)
		var on := 0
		for r in g.state.riders:
			if r.target == id:
				on += 1
		assert_eq(int(row["count"]), on, "riders on %d" % id)
	assert_eq(card.coupling, -1.0, "not coupling")
	# slot 2 reconnects in the fixture
	g.ctx.local_peer = 3
	card.refresh()
	assert_gte(card.coupling, 0.0, "the 2 s coupling bar")
	g.state.role = SiegeIds.ROLE_BREAK
	card.refresh()
	assert_false(card.visible, "the shop takes the directions in breaks")
	F.free_game(g)


func test_overdrive_button_faces() -> void:
	var g := _game()
	var r := g.state.rider(1)
	var face := SiegeHudModel.overdrive_face(g)
	assert_eq(face["mode"], SiegeHudModel.OD_ACTIVE, "slot 0 runs Overdrive in the fixture")
	r.od_state = SiegeIds.OD_COOLDOWN
	r.od_cd_s = 45.0
	assert_eq(SiegeHudModel.overdrive_face(g)["mode"], SiegeHudModel.OD_COOLDOWN)
	r.od_state = SiegeIds.OD_READY
	r.od_prompt = true
	face = SiegeHudModel.overdrive_face(g)
	assert_eq(face["mode"], SiegeHudModel.OD_PROMPT)
	assert_true(bool(face["enabled"]))
	var b := SiegeOverdriveButton.new()
	b.game = g
	add_child_autofree(b)
	b.refresh()
	b.pressed.emit()
	assert_eq(str((g.ctx.intents as F.Intents).sent[0]["k"]), SiegeIds.INTENT_OVERDRIVE)
	F.free_game(g)


func test_wave_info_lists_enemies_and_the_engine_warnings() -> void:
	var g := _game()
	var tx := GameStrings.new()
	var lines := SiegeHudModel.enemy_lines(g.state, tx)
	assert_gt(lines.size(), 0)
	var w := SiegeHudModel.warning(g.state)
	assert_false(w.is_empty(), "a ram at the gate and a tower on the road")
	assert_true(
		str(w["key"]) in ["SIEGE_HUD_TOWER_ON_ROAD", "SIEGE_HUD_RAM_ON_ROAD", "SIEGE_WARN_BOARDED"]
	)
	g.state.breach_s = 6.0
	assert_eq(SiegeHudModel.warning(g.state)["key"], "SIEGE_HUD_BREACH")
	g.state.breach_s = 0.0
	g.state.enemies.clear()
	g.state.queue.clear()
	g.state.queue_len = 0
	g.state.gate_hp = 10.0
	assert_eq(SiegeHudModel.warning(g.state)["key"], "SIEGE_WARN_GATE_LOW")
	var info := SiegeWaveInfo.new()
	info.game = g
	add_child_autofree(info)
	info.refresh()
	assert_true(info.visible)
	F.free_game(g)


func test_curtain_card_and_teammate_strip() -> void:
	var g := _game()
	var card := SiegeCurtainCard.new()
	card.game = g
	add_child_autofree(card)
	card.refresh()
	assert_eq(card.value_label.text, "80 / %d" % roundi(g.state.curtain_max()))
	assert_gte(card.value_label.label_settings.font_size, WlTheme.KEY_NUMBER_MIN_PX)
	var strip := SiegeStripOverlay.new()
	strip.game = g
	add_child_autofree(strip)
	strip.refresh()
	assert_eq(strip.cells.size(), 4)
	for slot in 4:
		assert_true(strip.cells[slot].visible)
	assert_true(strip.cells[0].is_local)
	var r1 := g.state.rider_at(1)
	assert_eq(
		strip.cells[1].watts_label.text,
		"%d W  %d%%" % [roundi(r1.raw_w), SiegeHudModel.pct_ftp(r1)]
	)
	F.free_game(g)


func _break_state() -> SiegeState:
	var st := FIX.mid_wave()
	st.role = SiegeIds.ROLE_BREAK
	st.phase_kind = Wl.RECOVERY
	st.phase_elapsed_s = 2.0
	st.enemies.clear()
	st.rider_at(0).gold = 500.0
	return st


func test_shop_rows_put_autopilots_pick_first_and_save_second() -> void:
	var st := _break_state()
	var g := _game(st)
	var r := st.rider_at(0)
	var picks := SiegeAutopilot.shop_picks(st, r, 1)
	var rows := SiegeShopModel.entries(st, r, GameStrings.new(), picks)
	assert_gt(rows.size(), 3)
	if not picks.is_empty():
		assert_true(bool(rows[0]["recommended"]))
		assert_eq(str(rows[0]["id"]["item"]), str(picks[0]["item"]))
		assert_eq(str(rows[1]["id"]["item"]), SiegeIds.ITEM_SAVE)
	else:
		assert_eq(str(rows[0]["id"]["item"]), SiegeIds.ITEM_SAVE)
	for row: Dictionary in rows:
		var id: Dictionary = row["id"]
		if str(id["item"]) == SiegeIds.ITEM_SAVE:
			continue
		var price := SiegeShop.price(st, str(id["item"]), int(id["at"]), int(id["at"]))
		assert_eq(int(row["cost"]), price, str(id))
		assert_false(bool(row["disabled"]), "500 gold buys anything")
	r.gold = 0.0
	for row: Dictionary in SiegeShopModel.entries(st, r, GameStrings.new(), []):
		if str(row["id"]["item"]) != SiegeIds.ITEM_SAVE:
			assert_true(bool(row["disabled"]), "nothing is affordable at 0 gold")
	F.free_game(g)


func test_shop_panel_lists_at_32_px_and_sends_buys() -> void:
	var st := _break_state()
	var g := _game(st)
	var panel := SiegeShopPanel.new()
	panel.game = g
	panel.picks_override = [
		SiegeIntents.normalize(SiegeIntents.buy(SiegeIds.ITEM_UPGRADE, 2, true))
	]
	add_child_autofree(panel)
	panel.refresh()
	assert_true(panel.visible)
	assert_gte(panel.list.item_font_px, 32)
	assert_eq(panel.list.item_count(), mini(panel.entries.size(), SiegeShopModel.ROWS))
	assert_eq(str(panel.entries[0]["id"]["item"]), SiegeIds.ITEM_UPGRADE)
	assert_eq(int(panel.entries[0]["id"]["at"]), 2)
	assert_eq(str(panel.entries[1]["id"]["item"]), SiegeIds.ITEM_SAVE)
	panel.list.item_picked.emit(0, panel.entries[0]["id"], "action")
	var sent: Array = (g.ctx.intents as F.Intents).sent
	assert_eq(sent.size(), 1)
	assert_eq(str(sent[0]["item"]), SiegeIds.ITEM_UPGRADE)
	assert_eq(int(sent[0]["station"]), 2)
	assert_false(sent[0].has("auto"))
	panel.list.item_picked.emit(1, panel.entries[1]["id"], "action")
	assert_eq(sent.size(), 1, "Save gold sends nothing")
	panel.list.item_picked.emit(0, panel.entries[0]["id"], "auto")
	assert_eq(int(sent[1]["auto"]), 1, "an auto-confirmed pick is tagged")
	st.role = SiegeIds.ROLE_WAVE
	panel.refresh()
	assert_false(panel.visible, "closed in waves")
	F.free_game(g)


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


func test_hud_stays_off_the_road_the_bridge_and_the_fort() -> void:
	var g := _game()
	var spec := SiegeHud.spec(g)
	var path := g.state.path
	var rects: Array[Rect2i] = []
	for wd: Dictionary in spec.widgets:
		assert_true(wd["at"] is Rect2i, "%s sits in a rect" % wd["widget"])
		rects.append(wd["at"])
	for c: Dictionary in spec.controls:
		assert_true(c["at"] is Rect2i)
		if not (c["control"] is SiegeShopPanel):
			rects.append(c["at"])
	rects.append(spec.toast_area)
	rects.append(spec.banner_area)
	var art := Rect2i(0, 0, 960, 540)
	# the shop shows in breaks only: it keeps off the road and the bridge
	var shop_rect: Rect2i = SiegeHud.SHOP_RECT
	for r in rects:
		assert_true(art.encloses(r), "%s inside the art" % r)
	# the road and the bridge, every metre
	var hits := []
	var prog := 0.0
	while prog <= path.length_m:
		var p := path.to_art(path.point_at(prog))
		for r in rects + [shop_rect]:
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
	for c: Dictionary in spec.controls:
		(c["control"] as Node).free()
	F.free_game(g)
