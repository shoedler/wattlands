extends GutTest
## The Free Roam menu: hints by zone (rarity, depth, the floor), left/right and confirm, pedal_nav
## scanning, surge and auto-confirm (and none of them without pedal_nav).

const H := preload("res://tests/games/fishing/rules/fishing_rules_harness.gd")


func _at_menu(x: float, pedal_nav: bool = false, seed: int = 3) -> H:
	var h := H.new()
	h.setup("roam_30", 1, seed)
	if pedal_nav:
		h.players[0].pedal_nav = true
		h.rebuild()
	h.drive_w[0] = 220.0
	assert_true(h.run_until(func() -> bool: return h.rider().x_m >= x, 2400.0), "out to %s" % x)
	h.drive_w[0] = 0.0
	assert_true(h.run_to_action(0, FishingConst.A_MENU, 60.0), "the menu opens")
	h.drive_w[0] = 60.0
	return h


func _species_of(h: H) -> Array:
	var out: Array = []
	for i in h.rider().hint_count():
		out.append(FishingConst.SPECIES[int(h.rider().hints[4 * i])])
	return out


func test_hints_come_from_the_zone_and_sit_in_order_of_dx() -> void:
	var h := _at_menu(5200.0)
	var r := h.rider()
	assert_eq(h.state.world.zone_at(r.x_m), "reef")
	for id: String in _species_of(h):
		assert_true(id in ["snapper", "mahi"], "%s lives on the reef" % id)
	for i in range(1, r.hint_count()):
		assert_lte(r.hints[4 * (i - 1) + 1], r.hints[4 * i + 1], "sorted by dx")
	for i in r.hint_count():
		var dx := absf(r.hints[4 * i + 1])
		assert_between(dx, FishingConst.HINT_DX_MIN, FishingConst.HINT_DX_MAX)
		assert_between(r.hints[4 * i + 3], 0.0, 1.0, "size w")
		assert_lt(r.hints[4 * i + 2], h.state.world.floor_depth_m(r.x_m), "above the floor")


func test_the_dock_offers_no_fish() -> void:
	var h := H.new()
	h.setup("roam_10", 1, 1)
	h.drive_w[0] = 0.0
	h.state.riders[0].x_m = 100.0
	FishingRules.new_hints(h.state, h.rider())
	assert_eq(h.rider().hint_count(), 0)


func test_grouper_hints_hold_just_above_the_floor_in_the_deep() -> void:
	var h := H.new()
	h.setup("roam_60", 1, 1)
	var r := h.rider()
	r.x_m = 14400.0
	var grouper := FishingConst.species_index("grouper")
	var found := 0
	for k in 60:
		FishingRules.new_hints(h.state, r)
		for i in r.hint_count():
			if int(r.hints[4 * i]) == grouper:
				found += 1
				var gap := h.state.world.floor_depth_m(r.x_m) - r.hints[4 * i + 2]
				assert_between(
					gap, FishingConst.FLOOR_GAP_LO - 1e-6, FishingConst.FLOOR_GAP_HI + 1e-6
				)
	assert_gt(found, 0, "groupers show up in the deep")


func test_the_abyss_offers_the_legendary_fish() -> void:
	var h := H.new()
	h.setup("roam_60", 1, 1)
	var r := h.rider()
	r.x_m = 17200.0
	FishingRules.new_hints(h.state, r)
	assert_eq(_species_of(h), ["oarfish", "oarfish", "oarfish"])


func test_hints_are_the_same_for_the_same_seed() -> void:
	var a := _at_menu(900.0, false, 5)
	var b := _at_menu(900.0, false, 5)
	assert_eq(a.rider().hints, b.rider().hints)


func test_left_and_right_move_the_highlight_and_wrap() -> void:
	var h := _at_menu(900.0)
	var r := h.rider()
	var n := r.menu.size()
	assert_eq(r.selected, 0)
	h.send(0, FishingIntents.spot(-1))
	h.step()
	assert_eq(r.selected, n - 1, "wraps to Turn around")
	h.send(0, FishingIntents.spot(1))
	h.step()
	assert_eq(r.selected, 0)


func test_without_pedal_nav_nothing_scans_surges_or_auto_confirms() -> void:
	var h := _at_menu(900.0)
	var r := h.rider()
	h.send(0, FishingIntents.confirm(FishingIntents.VIA_SURGE))
	h.run(FishingRules.auto_confirm_s(r.menu.size()) + 5.0)
	assert_eq(r.action, FishingConst.A_MENU, "a surge is no confirm and nothing auto-confirms")
	assert_eq(r.selected, 0, "no scan")


func test_with_pedal_nav_the_menu_scans_every_1_6_s() -> void:
	var h := _at_menu(900.0, true)
	var r := h.rider()
	h.run(FishingConst.SCAN_INTERVAL_S + 0.05)
	assert_eq(r.selected, 1)
	h.run(FishingConst.SCAN_INTERVAL_S)
	assert_eq(r.selected, 2)


func test_with_pedal_nav_a_surge_confirms() -> void:
	var h := _at_menu(900.0, true)
	h.send(0, FishingIntents.confirm(FishingIntents.VIA_SURGE))
	h.step()
	assert_eq(h.rider().action, FishingConst.A_CAST, "the highlighted hint")


func test_with_pedal_nav_the_menu_auto_confirms_after_two_scan_cycles() -> void:
	var h := _at_menu(900.0, true)
	var r := h.rider()
	var n := r.menu.size()
	h.run(FishingRules.auto_confirm_s(n) - 0.2)
	assert_eq(r.action, FishingConst.A_MENU)
	h.run(0.3)
	assert_ne(r.action, FishingConst.A_MENU, "auto-confirmed")
	assert_eq(FishingRules.auto_confirm_s(5), 2 * 5 * 1.6)


func test_a_key_pauses_the_scan_for_10_s() -> void:
	var h := _at_menu(900.0, true)
	var r := h.rider()
	h.send(0, FishingIntents.spot(1))
	h.step()
	h.run(9.0)
	assert_eq(r.selected, 1, "paused")
	h.run(1.0 + FishingConst.SCAN_INTERVAL_S)
	assert_eq(r.selected, 2, "scanning again")


func test_moving_on_more_than_60_m_draws_new_hints() -> void:
	var h := _at_menu(900.0)
	var r := h.rider()
	var first := r.hints.duplicate()
	r.x_m += 30.0
	h.send(0, FishingIntents.confirm(FishingIntents.VIA_ACTION))
	h.send(0, FishingIntents.spot(-1))
	# Back in the menu after a reel-in: within 60 m the same fish are there.
	FishingRules.new_hints(h.state, r)
	assert_ne(r.hints, first, "new_hints always draws")
	r.hints = first.duplicate()
	r.hints_x = r.x_m - 30.0
	h.rider().action = FishingConst.A_CAST
	h.send(0, FishingIntents.confirm(FishingIntents.VIA_ACTION))
	h.step()
	assert_eq(r.action, FishingConst.A_MENU)
	assert_eq(r.hints, first, "within 60 m the hints stay")
