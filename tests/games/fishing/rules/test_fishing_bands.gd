extends GutTest
## BRIEF 4.6.3: every band the rules publish (the lure band while waiting or trolling, the Fight's
## tension band) keeps its low edge >= 65 rpm, above the 45 rpm rescue trigger, for every
## preferred cadence a profile allows (30-160 rpm), and keeps its width.

const H := preload("res://tests/games/fishing/rules/fishing_rules_harness.gd")
const PREFERRED_MIN := 30
const PREFERRED_MAX := 160


## One mackerel (T_nom 60 s) on base_60, the rider following its band at `preferred` rpm.
func _mackerel(preferred: float) -> H:
	var probe := H.new()
	probe.content = H.load_content("base_60")
	var ls: Array[FishingPlanSlot] = [H.make_slot(probe.content, "mackerel", 0, 60.0)]
	var h := H.new()
	h.setup("base_60", 1, 3, [ls])
	h.players[0].preferred_cadence_rpm = preferred
	h.rebuild()
	h.follow_band[0] = true
	return h


## [t, lo, hi] of every published band (not the cleared 0..0) whose low edge is under 65 or
## whose width is not one of `widths`.
func _bad_bands(h: H, widths: Array) -> Array:
	var bad: Array = []
	for b: Array in h.bands:
		var lo := int(b[2])
		var hi := int(b[3])
		if lo == 0 and hi == 0:
			continue
		if lo < roundi(FishingConst.BAND_LOW_MIN) or not widths.has(hi - lo):
			bad.append([snappedf(float(b[0]), 0.05), lo, hi])
	return bad


func test_every_workout_band_keeps_65_rpm_for_every_preferred_cadence() -> void:
	for pref in range(PREFERRED_MIN, PREFERRED_MAX + 1, 5):
		var h := _mackerel(float(pref))
		var seen := {}
		for k in 20000:
			h.step()
			if h.rider().pub_hi > 0:
				seen[h.rider().action] = true
			if h.rider().action == FishingConst.A_LAND:
				break
		assert_true(seen.has(FishingConst.A_WAIT), "preferred %d: the lure band" % pref)
		assert_true(seen.has(FishingConst.A_FIGHT), "preferred %d: the tension band" % pref)
		assert_eq(_bad_bands(h, [16, 22]), [], "preferred %d" % pref)


func test_every_roam_lure_band_keeps_65_rpm() -> void:
	for pref in [30.0, 60.0, 90.0, 140.0]:
		var h := H.new()
		h.setup("roam_10", 1, 2, [], 1)
		h.players[0].preferred_cadence_rpm = pref
		h.rebuild([2])
		h.follow_band[0] = true
		assert_true(h.run_to_action(0, FishingConst.A_FIGHT, 600.0), "preferred %s: a fight" % pref)
		h.run(30.0)
		assert_eq(_bad_bands(h, [16]), [], "preferred %s" % pref)


func test_threshold_bands_keep_65_rpm_at_a_low_preferred_cadence() -> void:
	var h := H.new()
	h.setup("threshold", 1, 3)
	h.players[0].preferred_cadence_rpm = 30.0
	h.rebuild()
	h.follow_band[0] = true
	assert_true(h.run_to_action(0, FishingConst.A_FIGHT, 700.0), "the first tuna")
	h.run(60.0)
	assert_eq(_bad_bands(h, [16, 22]).size(), 0, "%s" % [_bad_bands(h, [16, 22]).slice(0, 6)])


func test_a_low_preferred_cadence_lifts_the_lure_band_to_65_with_its_width() -> void:
	var h := _mackerel(50.0)
	assert_true(h.run_to_action(0, FishingConst.A_WAIT, 400.0), "trolling")
	assert_eq([h.rider().pub_lo, h.rider().pub_hi], [65, 81], "max(65, 50 + 10 - 8) + 16")
	h.follow_band[0] = false
	h.cadence[0] = 66.0
	h.rider().cadence_ema = 66.0
	h.step()
	assert_true(h.rider().in_band, "66 rpm is inside the published band")
	var at90 := _mackerel(90.0)
	assert_true(at90.run_to_action(0, FishingConst.A_WAIT, 400.0))
	assert_eq([at90.rider().pub_lo, at90.rider().pub_hi], [92, 108], "90 + 10 - 8, width 16")
