extends GutTest
## Brief 2.3's 4.6.3 check: "the band is always >= 65 rpm, above the 45 rpm trigger", for every
## band the rules publish (ride out practice, lure, tension, idle) and every preferred cadence a
## profile allows (30-160 rpm, core/settings.gd). Each band keeps its width: the low edge is
## max(65, centre - half) and the high edge low + width, like the Fight's tension band.

const H := preload("res://tests/games/fishing/rules/fishing_rules_harness.gd")
const PREFERRED_MIN := 30
const PREFERRED_MAX := 160


## One mackerel (T_nom 60 s) on `trip`, the lane following its band at `preferred` rpm.
func _mackerel(preferred: float, trip: String = "free_30") -> H:
	var probe := H.new()
	probe.content = H.load_content(trip)
	var ls: Array[FishingPlanSlot] = [H.make_slot(probe.content, "mackerel", 0, 60.0)]
	var h := H.new()
	h.setup(trip, 1, 3, [ls])
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


## The lane states of `seen` (lane state -> true), sorted.
func _states(seen: Dictionary) -> Array:
	var out: Array = []
	for s: int in seen:
		out.append(s)
	out.sort()
	return out


## Property over every preferred cadence a profile allows: each lane state that publishes a band
## (ride out, the Reel's lure band, the Fight's tension band down to S = 0 and through a run, idle)
## publishes one with its low edge >= 65 rpm and its width. The harness jumps phase to phase.
func test_every_band_keeps_65_rpm_for_every_preferred_cadence_30_to_160() -> void:
	var bad: Array = []
	var want := [
		FishingConst.ST_RIDE_OUT, FishingConst.ST_CAST, FishingConst.ST_FIGHT, FishingConst.ST_IDLE
	]
	for pref in range(PREFERRED_MIN, PREFERRED_MAX + 1):
		var h := _mackerel(float(pref))
		var l := h.lane()
		var seen := {}
		h.step()
		seen[l.state] = true
		for index in [1, 2]:
			h._goto(0, index)
			h.step()
			h.step()
			seen[l.state] = true
		# The Fight's lowest centre: S = 0 (10 rpm under), then a run's band shift on top.
		l.fish.s = 0.0
		h.run(6.0)
		l.fish.run_active = true
		l.fish.run_end_t = h.state.t + 30.0
		h.run(6.0)
		h._goto(0, 4)
		h.step()
		h.step()
		seen[l.state] = true
		for st: int in want:
			if not seen.has(st):
				bad.append([pref, "no band in state %d" % st])
		for b: Array in _bad_bands(h, [16, 22]):
			bad.append([pref, b])
	assert_eq(bad.size(), 0, "[preferred, band or problem]: %s" % [bad.slice(0, 8)])


func test_every_band_a_free_trip_publishes_keeps_65_rpm_and_its_width() -> void:
	for pref: float in [30.0, 45.0, 50.0, 60.0, 72.0, 73.0, 90.0, 125.0, 160.0]:
		var h := _mackerel(pref)
		var seen := {}
		for _k in roundi(1200.0 / H.DT):
			h.step()
			var l := h.lane()
			if l.pub_lo != 0 or l.pub_hi != 0:
				seen[l.state] = true
			if h.lane().state == FishingConst.ST_IDLE:
				h.run(5.0)
				break
		var bad := _bad_bands(h, [16, 22])
		assert_eq(bad.size(), 0, "preferred %d: bands [t, lo, hi] %s" % [pref, bad.slice(0, 6)])
		var lane_states := _states(seen)
		for st: int in [FishingConst.ST_RIDE_OUT, FishingConst.ST_FIGHT, FishingConst.ST_IDLE]:
			assert_has(lane_states, st, "preferred %d: a band in force in state %d" % [pref, st])
		assert_true(
			seen.has(FishingConst.ST_CAST) or seen.has(FishingConst.ST_REEL),
			"preferred %d had the lure band in force" % pref
		)


func test_threshold_bands_keep_65_rpm_at_a_low_preferred_cadence() -> void:
	var h := H.new()
	h.setup("threshold", 1, 3)
	h.players[0].preferred_cadence_rpm = 30.0
	h.rebuild()
	h.follow_band[0] = true
	assert_true(h.run_to_state(0, FishingConst.ST_FIGHT, 700.0), "the first tuna")
	h.run(60.0)
	assert_eq(_bad_bands(h, [16, 22]).size(), 0, "%s" % [_bad_bands(h, [16, 22]).slice(0, 6)])


func test_a_low_preferred_cadence_lifts_each_band_to_65_with_its_width() -> void:
	var h := _mackerel(50.0)
	h.run(1.0)
	assert_eq([h.lane().pub_lo, h.lane().pub_hi], [65, 81], "ride out: max(65, 42) + 16")
	h.follow_band[0] = false
	h.cadence[0] = 66.0
	h.lane().cadence_ema = 66.0
	h.step()
	assert_true(h.lane().in_band, "66 rpm is inside the published band")
	h.follow_band[0] = true
	assert_true(h.run_to_state(0, FishingConst.ST_CAST, 400.0), "the cast")
	assert_eq([h.lane().pub_lo, h.lane().pub_hi], [65, 81], "lure: max(65, 50 + 10 - 8) + 16")
	var at90 := _mackerel(90.0)
	at90.run(1.0)
	assert_eq([at90.lane().pub_lo, at90.lane().pub_hi], [82, 98], "unchanged at 90 rpm")
