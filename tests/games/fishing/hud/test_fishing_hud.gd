extends GutTest
## FishingHud.spec (G0 decision "HUD layout") for every lane count and local slot: every rect
## inside the view, inside its zone and clear of the PANIC corner (art x >= 503 and y >= 316);
## the strain meter left of cadence and the slack meter right of it; one FishingLaneHud per other
## lane. The game's own Controls refresh headless from hand-made states, and every string key
## the HUD and the view use is in strings.csv.

const FX := preload("res://tests/games/fishing/view/fishing_view_fixtures.gd")
const VIEW := Rect2i(0, 0, 640, 360)
## Keys the rules and the module raise (the view builder owns strings.csv).
const RAISED_KEYS: Array[String] = [
	"FISHING_TIP_1",
	"FISHING_TIP_2",
	"FISHING_TIP_3",
	"FISHING_TIP_4",
	"FISHING_TIP_5",
	"FISHING_TIP_6",
	"FISHING_TOAST_STRIKE",
	"FISHING_TOAST_LANDED",
	"FISHING_TOAST_TROPHY",
	"FISHING_TOAST_SNAP",
	"FISHING_TOAST_THROWN",
	"FISHING_TOAST_REPLACEMENT",
	"FISHING_TOAST_MISS",
	"FISHING_TOAST_DOUBLE_HOOKUP",
	"FISHING_TOAST_FRENZY",
	"FISHING_TOAST_RUN",
	"FISHING_TOAST_JUMP",
	"FISHING_TOAST_TRIP_OVER",
	"FISHING_BANNER_LANDING",
	"FISHING_STAT_KJ",
	"FISHING_STAT_FTP_PCT",
	"FISHING_STAT_BAND_PCT",
	"FISHING_STAT_LANDED",
	"FISHING_STAT_TROPHIES",
	"FISHING_STAT_LOST",
	"FISHING_STAT_BIGGEST",
	"FISHING_STAT_LONGEST",
	"FISHING_TEAM_POINTS",
	"FISHING_TEAM_FISH",
	"FISHING_TEAM_TROPHIES",
]

var _specs: Array[HudSpec] = []


func after_each() -> void:
	for s in _specs:
		for c in s.controls:
			var node: Control = c["control"]
			if is_instance_valid(node):
				node.free()
	_specs.clear()


func _spec(game: FishingGame) -> HudSpec:
	var s := FishingHud.spec(game)
	_specs.append(s)
	return s


func _game(n: int, local_slot: int) -> FishingGame:
	var g: FishingGame = autofree(FX.make_game(n, local_slot))
	return g


func _rects(s: HudSpec) -> Array:
	var out: Array = []
	for w in s.widgets:
		out.append([str(w["widget"]), w["at"]])
	for c in s.controls:
		out.append([str((c["control"] as Control).name), c["at"]])
	out.append(["toasts", s.toast_area])
	out.append(["banners", s.banner_area])
	return out


func _csv_keys() -> Dictionary:
	var keys := {}
	var f := FileAccess.open("res://content/fishing/strings.csv", FileAccess.READ)
	assert_eq(f.get_csv_line(), PackedStringArray(["keys", "en"]), "header keys,en")
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 2 and row[0] != "":
			keys[row[0]] = row[1]
	return keys


func test_every_rect_is_inside_the_view_and_clear_of_panic_for_every_n_and_local_slot() -> void:
	for n in range(1, 5):
		for local in n:
			var s := _spec(_game(n, local))
			for e: Array in _rects(s):
				assert_true(e[1] is Rect2i, "%s at a Rect2i (n %d, local %d)" % [e[0], n, local])
				var r: Rect2i = e[1]
				assert_true(
					VIEW.encloses(r),
					"%s inside the view (n %d, local %d): %s" % [e[0], n, local, r]
				)
				assert_true(
					FishingLayout.clear_of_panic(r),
					"%s clear of PANIC (n %d, local %d): %s" % [e[0], n, local, r]
				)


func test_local_zone_holds_power_strain_cadence_slack_in_order() -> void:
	for n in range(1, 5):
		for local in n:
			var s := _spec(_game(n, local))
			var zone := FishingLayout.hud_zone(local, n)
			var at := {}
			for w in s.widgets:
				at[str(w["widget"])] = w["at"]
			for c in s.controls:
				var ctl: Control = c["control"]
				if ctl is FishingMeter:
					at[(ctl as FishingMeter).kind] = c["at"]
			for k: String in [
				HudSpec.POWER_GAUGE, HudSpec.CADENCE, FishingMeter.STRAIN, FishingMeter.SLACK
			]:
				assert_true(
					zone.encloses(at[k]), "%s in the local zone (n %d local %d)" % [k, n, local]
				)
			assert_lt(
				(at[FishingMeter.STRAIN] as Rect2i).end.x,
				(at[HudSpec.CADENCE] as Rect2i).position.x + 1
			)
			assert_gt(
				(at[FishingMeter.SLACK] as Rect2i).position.x,
				(at[HudSpec.CADENCE] as Rect2i).end.x - 1
			)
			var has_timeline := at.has(HudSpec.TIMELINE)
			var row := Rect2i(zone.position.x, zone.position.y + 38, FishingConst.HUD_W, 36)
			assert_eq(
				has_timeline, FishingLayout.clear_of_panic(row), "timeline only where the row fits"
			)
			if has_timeline:
				assert_true(zone.encloses(at[HudSpec.TIMELINE]))


func test_deck_bar_holds_the_deck_controls_and_the_kit_gear_and_wbal() -> void:
	var s := _spec(_game(2, 0))
	var deck := FishingLayout.deck_rect()
	var deck_rects: Array[Rect2i] = []
	for w in s.widgets:
		if str(w["widget"]) in [HudSpec.GEAR, HudSpec.WBAL]:
			assert_true(deck.encloses(w["at"]), str(w["widget"]))
			deck_rects.append(w["at"])
	var found := 0
	for c in s.controls:
		if c["control"] is FishingDeckBar or c["control"] is FishingCatchBoard:
			assert_true(deck.encloses(c["at"]))
			deck_rects.append(c["at"])
			found += 1
	assert_eq(found, 2)
	for a in deck_rects.size():
		for b in range(a + 1, deck_rects.size()):
			assert_false(deck_rects[a].intersects(deck_rects[b]), "deck rects do not overlap")


func test_one_lane_hud_per_other_lane_at_the_top_of_its_zone() -> void:
	for n in range(1, 5):
		for local in n:
			var s := _spec(_game(n, local))
			var slots: Array[int] = []
			for c in s.controls:
				if c["control"] is FishingLaneHud:
					var h := c["control"] as FishingLaneHud
					slots.append(h.slot)
					var zone := FishingLayout.hud_zone(h.slot, n)
					var r: Rect2i = c["at"]
					assert_true(zone.encloses(r))
					assert_eq(r.position.y, zone.position.y)
					assert_lte(r.size.y, 36)
			assert_eq(slots.size(), n - 1, "n %d local %d" % [n, local])
			assert_false(slots.has(local))


func test_toasts_below_the_deck_and_banners_over_the_local_lanes_left_two_thirds() -> void:
	var s := _spec(_game(3, 2))
	var toast: Rect2i = s.toast_area
	assert_gte(toast.position.y, FishingConst.DECK_H)
	var banner: Rect2i = s.banner_area
	assert_eq(
		banner, Rect2i(0, FishingLayout.lane_y(2, 3), FishingConst.HUD_X, FishingLayout.lane_h(3))
	)


func test_lane_numbers_are_at_least_32_px_at_1080p() -> void:
	assert_gte(FishingHudModel.LANE_NUMBER_PX, 32)
	var h := FishingLaneHud.make(_game(2, 0), 1)
	h.size = Vector2(639, 108)
	assert_gte(h.px(FishingHudModel.LANE_NUMBER_PX), 32)
	h.free()


func test_meters_show_only_in_a_fight_with_the_hosts_values() -> void:
	var game := _game(1, 0)
	var strain := FishingMeter.make(game, FishingMeter.STRAIN)
	var slack := FishingMeter.make(game, FishingMeter.SLACK)
	strain.refresh()
	assert_false(strain.shown, "no meters on the ride out")
	FX.set_fight(game.state.lane(0), 1, 50.0, 0.5, 0.65, 0.2)
	strain.refresh()
	slack.refresh()
	assert_true(strain.shown)
	assert_almost_eq(strain.fill, 0.65, 0.0001)
	assert_almost_eq(slack.fill, 0.2, 0.0001)
	assert_ne(strain.color(), slack.color(), "red and yellow, with different icons")
	strain.free()
	slack.free()


func test_deck_bar_shows_clock_phase_chip_fish_row_and_gaff() -> void:
	var game := _game(2, 1)
	var bar := FishingDeckBar.make(game)
	game.state.t = 75.0
	bar.refresh()
	assert_eq(bar.clock_text, "1:15")
	assert_ne(str(bar.chip["label"]), "")
	assert_false(bool(bar.fish["visible"]))
	var l := game.state.lane(1)
	FX.set_fight(l, 2, 47.4)
	bar.refresh()
	assert_true(bool(bar.fish["visible"]))
	assert_eq(bar.fish["d_m"], 47)
	assert_almost_eq(float(bar.fish["stamina"]), 0.7, 0.0001)
	FX.set_landing(l, 4.0, 0.5)
	bar.refresh()
	assert_true(bool(bar.gaff["visible"]))
	assert_eq(bar.gaff["phase"], FishingHudModel.KEY_SPRINT)
	l.gaff = 1.0
	l.state_t = 16.0
	bar.refresh()
	assert_eq(bar.gaff["phase"], FishingHudModel.KEY_TROPHY)
	bar.free()


func test_phase_chip_uses_the_plan_or_falls_back_to_the_state() -> void:
	var game := _game(1, 0)
	var l := game.state.lane(0)
	l.phase_index = 0
	l.state = FishingConst.ST_RIDE_OUT
	game.state.t = 5.0
	var plan := EffortPlan.of(
		[PlanPhase.erg(Wl.WARMUP, 50.0, 15.0), PlanPhase.erg(Wl.RECOVERY, 55.0, 20.0)]
	)
	plan.phase(0).label = "Ride out"
	plan.phase(1).label = "Reel 1"
	var chip := FishingHudModel.phase_chip(game, l, plan, 0.0)
	assert_eq(chip["label"], "Ride out")
	assert_almost_eq(float(chip["left_s"]), 10.0, 0.001)
	assert_eq(chip["next"], "Reel 1")
	var fallback := FishingHudModel.phase_chip(game, l, null, 0.0)
	assert_ne(str(fallback["label"]), "")
	assert_ne(str(fallback["next"]), "")
	assert_eq(FishingHudModel.clock(3725.0), "1:02:05")


func test_catch_board_lists_the_last_five_catches_and_the_hookup_level() -> void:
	var game := _game(2, 0)
	var st := game.state
	st.team_points = 345
	st.team_fish = 6
	st.hookup_level = 2
	st.catches.assign([0, 0, 0, 1, 1, 0, 0, 2, 1, 1, 0, 0, 0, 3, 0])
	var board := FishingCatchBoard.make(game)
	board.refresh()
	assert_eq(board.catches.size(), 5)
	assert_eq(board.catches[2], [0, 2, 1])
	assert_eq(board.hookup_level, 2)
	assert_eq(FishingHudModel.hookup_text(2), "x1.5")
	assert_eq(FishingHudModel.hookup_text(3), "x2")
	board.free()


func test_lane_hud_shows_band_marker_meters_and_status() -> void:
	var game := _game(3, 0)
	var h := FishingLaneHud.make(game, 2)
	var l := game.state.lane(2)
	FX.set_fight(l, 0, 22.0, 0.5, 0.4, 0.1)
	h.refresh()
	assert_eq(h.watts, 210)
	assert_eq(h.rpm, 90)
	assert_eq([h.band_lo, h.band_hi], [82, 98])
	assert_true(h.in_fight)
	assert_almost_eq(h.strain, 0.4, 0.0001)
	assert_true(h.detail.contains("22"), h.detail)
	l.rescue = true
	l.state = FishingConst.ST_REEL
	h.refresh()
	assert_eq(h.detail, FishingHudModel.status_text(game, l))
	h.free()


func test_controls_build_in_a_tree_and_draw_without_errors() -> void:
	var game := _game(4, 1)
	FX.set_fight(game.state.lane(1), 3, 150.0)
	FX.set_landing(game.state.lane(2), 3.0, 0.3)
	FX.set_pick(game.state.lane(3))
	var s := _spec(game)
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	add_child_autofree(root)
	for c in s.controls:
		var ctl: Control = c["control"]
		var r: Rect2i = c["at"]
		ctl.position = Vector2(r.position * 3)
		ctl.size = Vector2(r.size * 3)
		root.add_child(ctl)
	await wait_process_frames(3)
	for c in s.controls:
		var ctl := c["control"] as FishingHudControl
		assert_almost_eq(ctl.k(), 1.0, 0.01, str(ctl.name))
	for c in s.controls:
		root.remove_child(c["control"])


func test_every_string_key_the_hud_and_rules_use_is_in_strings_csv() -> void:
	var keys := _csv_keys()
	var used: Array[String] = []
	used.append_array(FishingHudModel.KEYS)
	used.append_array(FishingHudModel.STATUS_KEYS)
	used.append_array(FishingHudModel.SPECIES_KEYS)
	used.append_array(RAISED_KEYS)
	for k in used:
		assert_true(keys.has(k), "%s is in strings.csv" % k)
		assert_true(k.begins_with("FISHING_"), k)
	assert_true(str(keys["FISHING_TOAST_LANDED"]).contains("{species}"))
	assert_true(str(keys["FISHING_TOAST_LANDED"]).contains("{kg}"))
	assert_true(str(keys["FISHING_TOAST_LANDED"]).contains("{points}"))
