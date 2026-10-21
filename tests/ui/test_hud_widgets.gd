extends GutTest
## The HUD kit widgets on their own (BRIEF 3.9; docs/OWNERSHIP.md HUD3-HUD6, HUD10): each
## builds headless and reacts to data: the power gauge's band glows in band (ERG: applied
## target +-5%; SIM: the published band), cadence with its band, W' bar, the timeline with
## its next-phase preview and open-ended phases, teammate chips per slot look, toasts and
## banners, readouts per source, the gear only in SIM, and key numbers >= 48 px at 1080p.


func _tele(mode: String, power: float, target: int = 0) -> Telemetry:
	var t := Telemetry.new()
	t.mode = mode
	t.power_w = power
	t.applied_target_w = target
	t.ftp_pct = power / 2.0
	return t


func _add(w: Control) -> Control:
	add_child_autofree(w)
	return w


# --- every widget builds headless ---------------------------------------------------------


func test_every_kit_widget_builds_headless() -> void:
	var made: Array[HudWidget] = [
		HudPowerGauge.new(),
		HudCadence.new(),
		HudWbal.new(),
		HudTimeline.new(),
		HudTeammates.new(),
		HudReadout.new(),
		HudGear.new(),
	]
	var ids: Array[String] = []
	for w in made:
		_add(w)
		ids.append(w.widget_id)
		assert_gt(w.base_size().x, 0.0)
		assert_true(
			w.min_rect().x <= w.base_size().x and w.min_rect().y <= w.base_size().y, w.widget_id
		)
		w.set_telemetry(_tele(Wl.SIM, 180.0))
		w.set_phase(PhaseState.new(), null)
	ids.sort()
	var expect: Array[String] = HudSpec.KIT_WIDGETS.duplicate()
	expect.sort()
	assert_eq(ids, expect, "one class per HudSpec kit widget")


# --- power gauge --------------------------------------------------------------------------


func test_power_gauge_erg_band_is_target_plus_minus_5_pct() -> void:
	var g: HudPowerGauge = _add(HudPowerGauge.new())
	g.set_telemetry(_tele(Wl.ERG, 205.0, 200))
	assert_eq(g.band(), Vector2(190, 210))
	assert_true(g.in_band())
	assert_true(g.bar().glow, "glows in band")
	assert_eq(g.bar().marker, 200.0, "target marker")
	assert_eq(g.watts_label().text, "205")
	assert_string_contains(g.pct_label().text, "103")
	g.set_telemetry(_tele(Wl.ERG, 230.0, 200))
	assert_false(g.in_band())
	assert_false(g.bar().glow)
	g.set_telemetry(_tele(Wl.ERG, 189.0, 200))
	assert_false(g.in_band(), "below the band")


func test_power_gauge_erg_ignores_the_published_band() -> void:
	var g: HudPowerGauge = _add(HudPowerGauge.new())
	g.set_power_band(300.0, 400.0)
	g.set_telemetry(_tele(Wl.ERG, 350.0, 200))
	assert_eq(g.band(), Vector2(190, 210), "ERG shows the applied target")
	assert_false(g.in_band())


func test_power_gauge_sim_uses_the_published_band() -> void:
	var g: HudPowerGauge = _add(HudPowerGauge.new())
	g.set_telemetry(_tele(Wl.SIM, 260.0))
	assert_eq(g.band(), Vector2.ZERO, "no band until one is published")
	assert_false(g.in_band())
	g.set_power_band(240.0, 280.0)
	assert_eq(g.band(), Vector2(240, 280))
	assert_true(g.in_band())
	assert_true(g.bar().glow)
	assert_eq(g.bar().marker, -1.0, "no target marker in SIM")
	g.set_power_band(0.0, 0.0)
	assert_eq(g.band(), Vector2.ZERO, "0, 0 clears it")
	assert_false(g.bar().glow)


func test_power_gauge_shows_raw_w_pct_and_wkg_only_opted_in() -> void:
	var g: HudPowerGauge = _add(HudPowerGauge.new())
	g.ftp_w = 250.0
	var t := _tele(Wl.SIM, 250.0)
	t.ftp_pct = 0.0
	g.set_telemetry(t)
	assert_string_contains(
		g.pct_label().text, "100", "%FTP computed from the FTP when telemetry has none"
	)
	assert_false(g.wkg_label().visible, "no W/kg without the opt-in")
	g.weight_kg = 80.0
	g.set_telemetry(t)
	assert_true(g.wkg_label().visible)
	assert_string_contains(g.wkg_label().text, "3.1")


# --- cadence ------------------------------------------------------------------------------


func test_cadence_band_glow_and_clear() -> void:
	var c: HudCadence = _add(HudCadence.new())
	var t := Telemetry.new()
	t.cadence_rpm = 88.0
	c.set_telemetry(t)
	assert_eq(c.rpm_label().text, "88")
	assert_false(c.in_band(), "no band")
	c.set_cadence_band(80.0, 95.0)
	assert_true(c.in_band())
	assert_true(c.bar().glow)
	t.cadence_rpm = 100.0
	c.set_telemetry(t)
	assert_false(c.in_band())
	c.set_cadence_band(0.0, 0.0)
	assert_eq(c.band(), Vector2.ZERO)


func test_cadence_stale_dims_and_never_glows() -> void:
	var c: HudCadence = _add(HudCadence.new())
	c.set_cadence_band(80.0, 95.0)
	var t := Telemetry.new()
	t.cadence_rpm = 88.0
	t.cadence_age_s = 3.5
	c.set_telemetry(t)
	assert_true(c.is_stale())
	assert_false(c.in_band())
	assert_true(c.bar().dim)


# --- W' ---------------------------------------------------------------------------------------


func test_wbal_fraction_and_low_state() -> void:
	var w: HudWbal = _add(HudWbal.new())
	w.wprime_j = 20000.0
	w.set_wbal(15000.0)
	assert_almost_eq(w.fraction(), 0.75, 1e-6)
	assert_eq(w.pct_label().text, "75%")
	assert_false(w.is_low())
	w.set_wbal(3000.0)
	assert_true(w.is_low())
	assert_string_contains(w.pct_label().text, "15")
	assert_eq(w.bar().fill_color, WlTheme.WARN)
	w.set_wbal(-50.0)
	assert_eq(w.fraction(), 0.0)


func test_wbal_option() -> void:
	var w: HudWbal = HudWbal.new()
	w.configure({"wprime_j": 10000.0})
	_add(w)
	w.set_wbal(5000.0)
	assert_almost_eq(w.fraction(), 0.5, 1e-6)


# --- timeline ---------------------------------------------------------------------------------


func _plan() -> EffortPlan:
	return (
		EffortPlan
		. of(
			[
				PlanPhase.erg(Wl.WARMUP, 50, 300, "Ride out").with_ramp(65),
				PlanPhase.erg(Wl.WORK, 90, 180, "Wave 1"),
				PlanPhase.erg(Wl.WORK, 60, 0, "Reel 1").with_open(120, 540),
				PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, 30, "Landing"),
			]
		)
	)


func _phase(plan: EffortPlan, index: int, elapsed: float) -> PhaseState:
	var p := plan.phase(index)
	var s := PhaseState.new()
	s.index = index
	s.kind = p.kind
	s.mode = p.mode
	s.label = p.label
	s.duration_s = p.duration_s
	s.open_ended = p.open_ended
	s.min_s = p.min_s
	s.max_s = p.max_s
	s.elapsed_s = elapsed
	s.remaining_s = maxf(0.0, (p.max_s if p.open_ended else p.duration_s) - elapsed)
	s.count = plan.size()
	return s


func test_timeline_fixed_phase_and_next_preview() -> void:
	var tl: HudTimeline = _add(HudTimeline.new())
	var plan := _plan()
	tl.set_phase(_phase(plan, 1, 60.0), plan)
	assert_eq(tl.phase_text(), "Wave 1")
	assert_eq(tl.time_text(), "2:00", "time left")
	assert_eq(tl.range_text(), "")
	assert_string_contains(tl.next_text(), "Reel 1")
	assert_string_contains(tl.next_text(), "2:00")
	assert_string_contains(tl.next_text(), "9:00", "an open-ended next phase shows min_s-max_s")
	assert_eq(tl.strip().blocks.size(), 4)
	assert_eq(tl.strip().current, 1)
	assert_almost_eq(tl.strip().progress, 60.0 / 180.0, 1e-6)


func test_timeline_ramp_preview() -> void:
	var tl: HudTimeline = _add(HudTimeline.new())
	var plan := EffortPlan.of(
		[
			PlanPhase.erg(Wl.FREE, 50, 10, "Intro"),
			PlanPhase.erg(Wl.WARMUP, 50, 300, "Ride out").with_ramp(65)
		]
	)
	tl.set_phase(_phase(plan, 0, 1.0), plan)
	assert_string_contains(tl.next_text(), "50")
	assert_string_contains(tl.next_text(), "65")
	assert_string_contains(tl.next_text(), "5:00")


func test_timeline_open_ended_phase() -> void:
	var tl: HudTimeline = _add(HudTimeline.new())
	var plan := _plan()
	tl.set_phase(_phase(plan, 2, 75.0), plan)
	assert_eq(tl.time_text(), "1:15", "elapsed")
	assert_string_contains(tl.range_text(), "2:00")
	assert_string_contains(tl.range_text(), "9:00")
	assert_eq(
		float(tl.strip().blocks[2]["len"]), 330.0, "no nominal length: the middle of min_s-max_s"
	)
	assert_string_contains(tl.next_text(), "Landing")


func test_timeline_last_phase_and_no_plan() -> void:
	var tl: HudTimeline = _add(HudTimeline.new())
	var plan := _plan()
	tl.set_phase(_phase(plan, 3, 5.0), plan)
	assert_eq(tl.next_text(), tr("UI_HUD_LAST_PHASE"))
	var s := PhaseState.new()
	s.index = 0
	s.kind = Wl.WORK
	s.duration_s = 60.0
	s.remaining_s = 30.0
	tl.set_phase(s, null)
	assert_eq(tl.next_text(), "")
	assert_eq(tl.time_text(), "0:30")
	assert_eq(tl.phase_text(), tr("UI_KIND_WORK"), "an empty label falls back to the kind")


func test_clock_text() -> void:
	assert_eq(HudWidget.clock_text(0.0), "0:00")
	assert_eq(HudWidget.clock_text(59.2), "1:00")
	assert_eq(HudWidget.clock_text(125.0), "2:05")
	assert_eq(HudWidget.clock_text(3725.0), "1:02:05")


# --- teammates --------------------------------------------------------------------------------


func _roster() -> Dictionary:
	return {
		1: {"name": "Ada", "slot_index": 0, "raw_w": 212.4, "ftp_pct": 85.0, "connected": true},
		3: {"name": "Bo", "slot_index": 5, "raw_w": 150.0, "ftp_pct": 75.0, "rescue": true},
		-1:
		{
			"name": "Bot 1",
			"slot_index": 1,
			"raw_w": 180.0,
			"ftp_pct": 90.0,
			"status": {"in_band": true, "icon": "", "text": ""}
		},
	}


func test_teammate_cards_follow_slot_order_and_looks() -> void:
	var tm: HudTeammates = _add(HudTeammates.new())
	tm.local_peer = 1
	tm.set_roster(_roster())
	assert_eq(tm.peers(), [1, -1, 3], "slot order")
	for p: int in [1, -1, 3]:
		var card := tm.card(p)
		var look := Wl.slot_look(int(_roster()[p]["slot_index"]))
		assert_eq(card.chip().color, look["color"], "color for %d" % p)
		assert_eq(card.chip().shape, look["shape"], "shape for %d" % p)
		assert_eq(card.chip().pattern, look["pattern"], "pattern for %d" % p)
		assert_eq(card.chip().hollow, look["hollow"], "hollow for %d" % p)
	assert_true(tm.card(3).chip().hollow, "slot 5 is hollow")
	assert_eq(tm.card(3).chip().shape, "triangle")
	assert_eq(tm.card(3).chip().pattern, "dashed")
	assert_string_contains(tm.card(1).watts_label().text, "212")
	assert_true(tm.card(1).is_local)


func test_teammate_status_lines() -> void:
	var tm: HudTeammates = _add(HudTeammates.new())
	tm.set_roster(_roster())
	assert_eq(tm.card(3).status_text(), tr("UI_HUD_RESCUE"))
	assert_true(tm.card(-1).in_band())
	assert_eq(tm.card(-1).status_text(), tr("UI_HUD_IN_BAND"))
	tm.set_status(1, {"in_band": false, "icon": "res://does/not/exist.png", "text": "Diesel"})
	assert_eq(tm.card(1).status_text(), "Diesel")
	assert_false(tm.card(1).icon().visible, "a missing icon is skipped")
	var r := _roster()
	r[1]["afk"] = true
	r[3]["connected"] = false
	tm.set_roster(r)
	assert_eq(tm.card(1).status_text(), tr("UI_HUD_AFK"))
	assert_eq(tm.card(3).status_text(), tr("UI_HUD_OFFLINE"), "offline wins over rescue")


func test_teammate_icon_from_res_path() -> void:
	var tm: HudTeammates = _add(HudTeammates.new())
	tm.set_roster(
		{
			2:
			{
				"name": "Cy",
				"slot_index": 2,
				"status": {"icon": "res://src/app/icon.svg", "text": ""}
			}
		}
	)
	if ResourceLoader.exists("res://src/app/icon.svg"):
		assert_true(tm.card(2).icon().visible)
	else:
		pass_test("no icon resource in this checkout")


func test_teammates_add_update_remove() -> void:
	var tm: HudTeammates = _add(HudTeammates.new())
	tm.set_roster(_roster())
	var first := tm.card(1)
	var r := _roster()
	r.erase(3)
	r[1]["raw_w"] = 300.0
	tm.set_roster(r)
	assert_same(tm.card(1), first, "cards are reused")
	assert_null(tm.card(3))
	assert_string_contains(tm.card(1).watts_label().text, "300")


## HUD8: a client's teammate_status draws only on that client, so the next 2 Hz roster
## (which carries the host's statuses) must not wipe it; a newer status in the roster wins.
func test_local_teammate_status_survives_roster_updates() -> void:
	var tm: HudTeammates = _add(HudTeammates.new())
	tm.set_roster(_roster())
	tm.set_status(1, {"in_band": true, "icon": "", "text": "Diesel"})
	assert_eq(tm.card(1).status_text(), "Diesel")
	tm.set_roster(_roster())
	tm.set_roster(_roster())
	assert_eq(tm.card(1).status_text(), "Diesel", "kept across roster updates")
	assert_true(tm.card(1).in_band())
	assert_eq(tm.local_status(1)["text"], "Diesel")
	var r := _roster()
	r[1]["status"] = {"in_band": false, "icon": "", "text": "Steam"}
	tm.set_roster(r)
	assert_eq(tm.card(1).status_text(), "Steam", "the roster's newer status wins")
	assert_eq(tm.local_status(1), {}, "the local one is dropped")
	tm.set_roster(r)
	assert_eq(tm.card(1).status_text(), "Steam")
	tm.set_status(1, {"text": "Dynamo"})
	tm.configure({"include_local": true})
	assert_eq(tm.card(1).status_text(), "Dynamo", "configure keeps local statuses")
	assert_eq(tm.local_statuses().keys(), [1])


func test_local_teammate_status_before_the_rider_is_in_the_roster() -> void:
	var tm: HudTeammates = _add(HudTeammates.new())
	tm.set_status(5, {"text": "Bank"})
	assert_eq(tm.card(5).status_text(), "Bank")
	tm.set_roster({5: {"name": "Eve", "slot_index": 1, "status": {}}})
	assert_eq(tm.card(5).status_text(), "Bank", "the first roster with the rider adopts it")
	assert_eq(tm.card(5).entry()["name"], "Eve")
	tm.set_roster({5: {"name": "Eve", "slot_index": 1, "status": {}}})
	assert_eq(tm.card(5).status_text(), "Bank")
	tm.set_roster({5: {"name": "Eve", "slot_index": 1, "status": {"text": "Host says"}}})
	assert_eq(tm.card(5).status_text(), "Host says")


func test_teammates_can_hide_the_local_rider() -> void:
	var tm := HudTeammates.new()
	tm.local_peer = 1
	tm.configure({"include_local": false, "vertical": true})
	_add(tm)
	tm.set_roster(_roster())
	assert_eq(tm.peers(), [-1, 3])


func test_slot_chip_takes_the_slot_look() -> void:
	var chip: SlotChip = _add(SlotChip.new())
	for i in 8:
		chip.set_slot(i)
		var look := Wl.slot_look(i)
		assert_eq(
			chip.look(),
			{
				"color": look["color"],
				"shape": look["shape"],
				"pattern": look["pattern"],
				"hollow": look["hollow"]
			}
		)
	for s: String in Wl.SLOT_SHAPES:
		assert_gt(SlotChip.shape_points(s, Rect2(0, 0, 40, 40)).size(), 2, s)


# --- readout and gear -------------------------------------------------------------------------


func test_readout_sources() -> void:
	var t := _tele(Wl.ERG, 251.6, 250)
	t.cadence_rpm = 91.0
	t.ftp_pct = 125.8
	var cases := {"power_w": "252", "cadence_rpm": "91", "ftp_pct": "126%", "wkg": "--"}
	for src: String in cases.keys():
		var r := HudReadout.new()
		r.configure({"source": src})
		_add(r)
		r.set_telemetry(t)
		assert_eq(r.value_text(), cases[src], src)
	var wkg := HudReadout.new()
	wkg.weight_kg = 70.0
	wkg.configure({"source": "wkg"})
	_add(wkg)
	wkg.set_telemetry(t)
	assert_eq(wkg.value_text(), "3.6")


func test_readout_custom_and_bad_source() -> void:
	var r := HudReadout.new()
	r.configure({"source": "custom", "id": "gate_hp", "label": "Gate"})
	_add(r)
	r.set_telemetry(_tele(Wl.ERG, 200.0))
	assert_eq(r.value_text(), "", "telemetry never writes a custom readout")
	r.set_text("1250")
	assert_eq(r.value_text(), "1250")
	var bad := HudReadout.new()
	bad.configure({"source": "heart_rate"})
	assert_push_error("unknown source")
	assert_eq(bad.source, "power_w")
	bad.free()


func test_gear_only_in_sim() -> void:
	var g: HudGear = _add(HudGear.new())
	assert_false(g.visible, "hidden until SIM")
	var t := _tele(Wl.SIM, 200.0)
	t.gear = 17
	g.set_telemetry(t)
	assert_true(g.visible)
	assert_eq(g.gear_label().text, "17")
	g.set_telemetry(_tele(Wl.ERG, 200.0, 200))
	assert_false(g.visible, "hidden in ERG")
	g.set_gear(99)
	assert_eq(g.gear(), 24)


# --- readability --------------------------------------------------------------------------------


func test_key_numbers_are_at_least_48_px_at_any_scale() -> void:
	var g: HudPowerGauge = _add(HudPowerGauge.new())
	var c: HudCadence = _add(HudCadence.new())
	var r: HudReadout = _add(HudReadout.new())
	var gear: HudGear = _add(HudGear.new())
	var keys: Array[Label] = [g.watts_label(), c.rpm_label(), r.value_label()]
	for l in keys:
		assert_gte(HudWidget.font_px(l), 48, "%s at full size" % l.name)
	assert_eq(HudWidget.font_px(gear.gear_label()), 48, "the gear is 48 px at full size")
	var tl: HudTimeline = _add(HudTimeline.new())
	assert_eq(HudWidget.font_px(tl.time_label()), 48, "the phase clock is 48 px at full size")
	assert_gte(HudWidget.font_px(g.watts_label()), WlTheme.KEY_NUMBER_PX)
	assert_gte(HudWidget.font_px(r.value_label()), WlTheme.BIG_READOUT_PX)
	for w: HudWidget in [g, c, r, gear]:
		w.fit_to(Vector2(120, 40))
		assert_lt(w.ui_scale, 0.55, "shrunk")
	for l in keys:
		assert_gte(HudWidget.font_px(l), 48, "%s shrunk" % l.name)


## The documented base_size and min_rect hold for real content (4-digit watts, a band
## label, long phase names): nothing overflows them once Labels have re-measured.
func test_documented_sizes_hold() -> void:
	var t := _tele(Wl.SIM, 1000.0)
	t.ftp_pct = 150.0
	t.cadence_rpm = 120.0
	t.gear = 24
	var plan := EffortPlan.of(
		[
			PlanPhase.erg(Wl.WARMUP, 50, 300, "Ride out to the reef").with_ramp(65),
			PlanPhase.erg(Wl.WORK, 90, 180, "Wave 12 of the long siege")
		]
	)
	var ph := _phase(plan, 0, 1.0)
	var ws: Array[HudWidget] = [
		HudPowerGauge.new(),
		HudCadence.new(),
		HudWbal.new(),
		HudTimeline.new(),
		HudReadout.new(),
		HudGear.new()
	]
	for w in ws:
		w.weight_kg = 75.0
		_add(w)
		w.set_telemetry(t)
		w.set_phase(ph, plan)
		if w is HudPowerGauge:
			(w as HudPowerGauge).set_power_band(980.0, 1020.0)
		if w is HudCadence:
			(w as HudCadence).set_cadence_band(100.0, 120.0)
	for w in ws:
		w.set_ui_scale(1.0)
	await wait_process_frames(2)
	for w in ws:
		var got := w.get_combined_minimum_size()
		assert_true(
			got.x <= w.base_size().x + 1.0 and got.y <= w.base_size().y + 1.0,
			"%s at scale 1: %s fits %s" % [w.widget_id, got, w.base_size()]
		)
	for w in ws:
		w.fit_to(w.min_rect())
		w.custom_minimum_size = Vector2.ZERO
	await wait_process_frames(2)
	for w in ws:
		var got := w.get_combined_minimum_size()
		assert_true(
			got.x <= w.min_rect().x + 1.0 and got.y <= w.min_rect().y + 1.0,
			"%s in min_rect: %s fits %s" % [w.widget_id, got, w.min_rect()]
		)
	var card: HudTeammateCard = _add(HudTeammateCard.new())
	card.set_entry(
		2,
		{
			"name": "Long Name Rider",
			"slot_index": 1,
			"raw_w": 1000,
			"ftp_pct": 150,
			"status": {"text": "Diesel"}
		}
	)
	await wait_process_frames(2)
	var tm := HudTeammates.new()
	var got_card := card.get_combined_minimum_size()
	assert_true(
		got_card.x <= tm.base_size().x + 1.0 and got_card.y <= tm.base_size().y + 1.0,
		"a card fits %s: %s" % [tm.base_size(), got_card]
	)
	tm.free()


func test_fit_to_never_grows() -> void:
	var g: HudPowerGauge = _add(HudPowerGauge.new())
	g.fit_to(Vector2(4000, 4000))
	assert_eq(g.ui_scale, 1.0)
	g.fit_to(Vector2(210, 68))
	assert_almost_eq(g.ui_scale, 0.5, 1e-6)
	assert_eq(g.custom_minimum_size, g.base_size() * 0.5)


func test_panel_option() -> void:
	var g := HudPowerGauge.new()
	g.configure({"panel": false})
	_add(g)
	assert_true(g.get_theme_stylebox("panel") is StyleBoxEmpty)


# --- toasts and banners -------------------------------------------------------------------------


func test_toasts_stack_expire_and_cap() -> void:
	var t: HudToasts = _add(HudToasts.new())
	t.push("one")
	t.push("two", 1.0)
	assert_eq(t.texts(), ["one", "two"])
	t.tick(1.0)
	assert_eq(t.texts(), ["one"])
	t.push("a")
	t.push("b")
	t.push("c")
	assert_eq(t.texts(), ["a", "b", "c"], "at most 3; the oldest goes first")
	t.tick(3.0)
	assert_eq(t.texts().size(), 0)
	assert_eq(t.get_child_count(), 0, "panels freed")
	t.push("")
	assert_eq(t.texts().size(), 0, "empty text ignored")


## A toast area in a small art-pixel rect keeps its text readable (>= MIN_FONT_PX) and shows
## fewer toasts at once instead of shrinking them.
func test_toasts_in_a_small_rect_stay_readable() -> void:
	var t: HudToasts = _add(HudToasts.new())
	t.fit_to(Vector2(1280, 90))
	assert_gte(t.font_px, HudToasts.MIN_FONT_PX)
	assert_gte(HudToasts.MIN_FONT_PX, 24)
	assert_eq(t.max_visible, 1, "one toast fits 90 px")
	t.push("one")
	t.push("two")
	assert_eq(t.texts(), ["two"], "the newest shows")
	t.fit_to(Vector2(1280, 400))
	assert_eq(t.font_px, WlTheme.TOAST_PX, "full size in a tall rect")
	assert_eq(t.max_visible, HudToasts.MAX_VISIBLE)
	t.push("three")
	t.push("four")
	assert_eq(t.texts(), ["two", "three", "four"])
	t.fit_to(Vector2(1280, 30))
	assert_eq(t.font_px, HudToasts.MIN_FONT_PX, "never below the floor")
	assert_eq(t.texts(), ["four"], "trimmed to what fits")


func test_banner_safety_priority() -> void:
	var b: HudBanner = _add(HudBanner.new())
	assert_eq(b.safety_state(), HudBanner.SAFETY_NONE)
	assert_eq(b.safety_text(), "")
	b.set_safety(true, false, false)
	assert_eq(b.safety_state(), HudBanner.SAFETY_WARMUP)
	assert_eq(b.safety_text(), tr("UI_BANNER_WARMUP"))
	b.set_safety(true, true, false)
	assert_eq(b.safety_state(), HudBanner.SAFETY_RESCUE, "rescue over warm-up")
	assert_eq(b.safety_text(), tr("UI_BANNER_RESCUE"))
	b.set_safety(true, true, true)
	assert_eq(b.safety_state(), HudBanner.SAFETY_PAUSED)
	b.show_safety = false
	assert_eq(b.safety_text(), "", "hidden at once when turned off")
	b.set_safety(true, true, true)
	assert_eq(b.safety_state(), HudBanner.SAFETY_NONE, "show_safety_banners off")
	b.show_safety = true
	assert_eq(b.safety_text(), tr("UI_BANNER_PAUSED"), "and back when turned on")
	b.set_safety(false, false, false)
	assert_eq(b.safety_text(), "")


## In a small art-pixel rect the safety banners stay readable from 3 m (they wrap or
## overflow the rect rather than shrink below the floor).
func test_banners_in_a_small_rect_stay_readable() -> void:
	var b: HudBanner = _add(HudBanner.new())
	b.fit_to(Vector2(640, 60))
	b.set_safety(false, true, false)
	assert_gte(HudWidget.font_px(b.safety_label()), HudBanner.MIN_FONT_PX, "rescue")
	assert_gte(HudBanner.MIN_FONT_PX, 32)
	b.set_safety(true, false, false)
	assert_gte(HudWidget.font_px(b.safety_label()), HudBanner.MIN_WARMUP_PX, "warm-up")
	b.show_game_banner("Strike!", 2.0)
	assert_gte(HudWidget.font_px(b.game_label()), HudBanner.MIN_FONT_PX, "game banner")
	b.fit_to(Vector2(1280, 400))
	b.set_safety(false, true, false)
	assert_eq(HudWidget.font_px(b.safety_label()), WlTheme.BANNER_PX, "full size in a tall rect")


func test_banner_game_text_expires() -> void:
	var b: HudBanner = _add(HudBanner.new())
	b.show_game_banner("Wave 2", 2.0)
	assert_eq(b.game_text(), "Wave 2")
	b.tick(1.9)
	assert_eq(b.game_text(), "Wave 2")
	b.tick(0.2)
	assert_eq(b.game_text(), "")
	assert_gte(HudWidget.font_px(b.game_label()), 48, "banners are big")


func test_theme_resource_loads() -> void:
	var th := WlTheme.get_theme()
	assert_not_null(th)
	assert_eq(th.default_font_size, WlTheme.BODY_PX)
	assert_true(th.has_stylebox("panel", "PanelContainer"))
	assert_gte(th.get_font_size("font_size", "Button"), 32)
	assert_not_null(WlTheme.font())
	assert_true(ResourceLoader.exists(WlTheme.THEME_PATH))


func test_teammates_max_width_wraps_then_scales() -> void:
	var tm: HudTeammates = _add(HudTeammates.new())
	var r := {}
	for i in 8:
		r[i + 1] = {"name": "R%d" % i, "slot_index": i}
	tm.set_roster(r)
	tm.set_max_width(3000.0)
	assert_eq(tm.columns(), 8)
	assert_eq(tm.ui_scale, 1.0)
	tm.set_max_width(1200.0)
	assert_eq(tm.columns(), 4, "two rows")
	assert_eq(tm.ui_scale, 1.0)
	tm.set_max_width(800.0)
	assert_eq(tm.columns(), 4)
	assert_almost_eq(tm.ui_scale, 800.0 / (4.0 * 260.0 + 30.0), 1e-4)
	tm.set_max_width(100.0)
	assert_eq(tm.ui_scale, HudTeammates.MIN_SCALE, "never below MIN_SCALE")
	var v := HudTeammates.new()
	v.configure({"vertical": true})
	_add(v)
	v.set_roster(r)
	assert_eq(v.columns(), 1)


func test_wrap_label() -> void:
	var l := Label.new()
	l.label_settings = WlTheme.label_settings(32)
	l.text = "Short"
	HudWidget.wrap_label(l, 400.0)
	assert_eq(l.autowrap_mode, TextServer.AUTOWRAP_OFF)
	l.text = "A much longer line of text that cannot fit in four hundred pixels at all"
	HudWidget.wrap_label(l, 400.0)
	assert_eq(l.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
	assert_eq(l.custom_minimum_size.x, 400.0)
	HudWidget.wrap_label(l, INF)
	assert_eq(l.autowrap_mode, TextServer.AUTOWRAP_OFF)
	l.free()
