extends GutTest
## Plan properties (brief 2.3, 4.1): every trip x 25 seeds x 4 riders x every reel_pct passes the
## PlanValidator with no warnings and every pre-roll rule and 4.6 check of brief 2.3. The opt-in
## sweep (tests/games/fishing/plan/sweep/fishing_plan_sweep.gd) runs the same checks at 200 seeds.

const H := preload("res://tests/games/fishing/plan/fishing_plan_harness.gd")
const SEEDS := 25
const RIDERS := 4


func _check_trip(trip_id: String) -> void:
	var c := H.content(trip_id)
	assert_true(c.ok, "%s content valid: %s" % [trip_id, c.errors])
	if not c.ok:
		return
	var fails: Array[String] = []
	var slots_total := 0
	for seed in range(1, SEEDS + 1):
		for rider in RIDERS:
			fails.append_array(H.plan_failures(c, seed, rider))
			slots_total += FishingPreroll.roll(c.trip, c.species, seed, rider).size()
	assert_eq(fails.size(), 0, "%s: %s" % [trip_id, "\n".join(fails.slice(0, 8))])
	assert_gt(slots_total, 0, "%s rolls fights" % trip_id)


func test_free_20() -> void:
	_check_trip("free_20")


func test_free_30() -> void:
	_check_trip("free_30")


func test_free_45() -> void:
	_check_trip("free_45")


func test_free_60() -> void:
	_check_trip("free_60")


func test_free_90() -> void:
	_check_trip("free_90")


func test_free_120() -> void:
	_check_trip("free_120")


func test_base_60() -> void:
	_check_trip("base_60")


func test_threshold() -> void:
	_check_trip("threshold")


func test_e2e_2min() -> void:
	_check_trip("e2e_2min")


func test_slots_stop_only_when_no_species_fits_the_budget_left() -> void:
	for trip_id: String in ["free_20", "free_45", "free_120", "base_60"]:
		var c := H.content(trip_id)
		var cap := c.trip.fight_cap_frac * c.trip.fishing_s
		for seed in range(1, SEEDS + 1):
			for rider in RIDERS:
				var used := 0.0
				for s in FishingPreroll.roll(c.trip, c.species, seed, rider):
					used += s.budget_s()
				for id: String in c.trip.species_weights:
					var def: FishingSpeciesDef = c.species[id]
					if FishingPreroll.fits(def, cap - used):
						fail_test("%s seed %d rider %d: %s still fits" % [trip_id, seed, rider, id])
						return
	pass_test("every pre-roll ran its budget down")


func test_marlin_is_the_second_slot_at_about_p_0_3() -> void:
	for trip_id: String in ["free_90", "free_120"]:
		var c := H.content(trip_id)
		var marlins := 0
		var riders := 0
		for seed in range(1, SEEDS + 1):
			for rider in RIDERS:
				var slots := FishingPreroll.roll(c.trip, c.species, seed, rider)
				riders += 1
				for s in slots:
					if s.species == "marlin":
						assert_eq(s.index, 1, "%s: a marlin only in the 2nd slot" % trip_id)
						marlins += 1
		var p := float(marlins) / float(riders)
		assert_between(p, 0.15, 0.45, "%s marlin share %.2f (p 0.3)" % [trip_id, p])
	for trip_id: String in ["free_20", "free_30", "free_45", "free_60", "base_60"]:
		var c := H.content(trip_id)
		for seed in range(1, SEEDS + 1):
			for s in FishingPreroll.roll(c.trip, c.species, seed, 0):
				assert_ne(s.species, "marlin", "%s rolls no marlin" % trip_id)


func test_species_follow_the_trip_weights() -> void:
	var c := H.content("free_60")
	var counts := {"mackerel": 0, "mahi": 0, "tuna": 0}
	for seed in range(1, 101):
		for s in FishingPreroll.roll(c.trip, c.species, seed, seed % 4):
			counts[s.species] = int(counts[s.species]) + 1
	var total := float(counts["mackerel"] + counts["mahi"] + counts["tuna"])
	# Short species fit more often late in the budget, so mackerel run a little above 45 %.
	assert_between(counts["mackerel"] / total, 0.35, 0.65, "mackerel share %s" % [counts])
	assert_between(counts["mahi"] / total, 0.2, 0.4, "mahi share %s" % [counts])
	assert_between(counts["tuna"] / total, 0.1, 0.35, "tuna share %s" % [counts])
	var base := H.content("base_60")
	for seed in range(1, SEEDS + 1):
		for s in FishingPreroll.roll(base.trip, base.species, seed, 0):
			assert_true(s.species in ["mackerel", "mahi"], "base_60: %s" % s.species)


func test_free_20_tuna_is_capped_to_fit_and_bites_before_last_call() -> void:
	var c := H.content("free_20")
	var tunas := 0
	for seed in range(1, 401):
		var slots := FishingPreroll.roll(c.trip, c.species, seed, seed % 4)
		if slots[0].species == "tuna":
			tunas += 1
			assert_lte(slots[0].t_nom_s + 30.0, 288.0 + 1e-6, "T_nom + 30 fits 40 % of 720 s")
			assert_lte(360.0 + slots[0].max_s + 30.0, 720.0 + 300.0, "passes last call")
	assert_gt(tunas, 0, "free_20 still rolls some tuna first")


func test_preroll_is_deterministic_per_seed_and_slot() -> void:
	var c := H.content("free_45")
	var differ := 0
	for seed in range(1, 11):
		var a := _dicts(FishingPreroll.roll(c.trip, c.species, seed, 0))
		assert_eq(a, _dicts(FishingPreroll.roll(c.trip, c.species, seed, 0)), "same seed, same")
		if a != _dicts(FishingPreroll.roll(c.trip, c.species, seed, 1)):
			differ += 1
	assert_gt(differ, 7, "riders roll their own slots")


func test_scheduled_trips_share_one_schedule() -> void:
	var th := H.content("threshold")
	var slots := FishingPreroll.roll(th.trip, th.species, 5, 0)
	assert_eq(_dicts(slots), _dicts(FishingPreroll.roll(th.trip, th.species, 5, 3)), "shared")
	assert_eq(slots.size(), 4)
	for s in slots:
		assert_eq(s.species, "tuna")
		assert_almost_eq(s.base_pct, 95.0, 1e-6)
		assert_almost_eq(s.t_nom_s, 345.0, 1e-6)
		assert_almost_eq(s.max_s, 420.0, 1e-6)
		assert_almost_eq(s.min_s, 276.0, 1e-6)
		assert_eq(s.run_count(), 3)
		for k in 3:
			assert_almost_eq(s.run_peak_pct(k), 102.6, 1e-6, "95 x 1.08")
		assert_almost_eq(s.range_hi, 102.6, 1e-6)
		assert_almost_eq(s.range_lo, 87.4, 1e-6)
		assert_true(s.scheduled)
		assert_almost_eq(s.reel_s, 240.0 if s.index == 0 else 360.0, 1e-6)
	var e2e := H.content("e2e_2min")
	var m := FishingPreroll.roll(e2e.trip, e2e.species, 9, 2)
	assert_eq(m.size(), 1)
	assert_eq(m[0].species, "mackerel")
	assert_almost_eq(m[0].base_pct, 62.0, 1e-6)
	assert_almost_eq(m[0].band_offset, 3.0, 1e-6, "lead decision: e2e band offset +3")
	assert_almost_eq(m[0].range_lo, 59.52, 1e-6)
	assert_almost_eq(m[0].range_hi, 64.48, 1e-6)
	assert_eq(m[0].run_count(), 0)
	assert_almost_eq(m[0].reel_s, 20.0, 1e-6)


func test_species_json_matches_the_brief_table() -> void:
	var c := H.content("free_30")
	var want := {
		"mackerel": [60, 120, 150, 70, 80, 4, 0, 0, 10, 40],
		"mahi": [120, 240, 270, 88, 95, 8, 2, 3, 8, 80],
		"tuna": [240, 480, 540, 93, 97, 8, 2, 4, 5, 120],
		"marlin": [600, 1200, 1320, 85, 90, 8, 4, 8, -2, 200],
	}
	for id: String in want:
		var d: FishingSpeciesDef = c.species[id]
		var got := [
			d.t_nom_lo,
			d.t_nom_hi,
			d.max_s,
			d.pull_lo,
			d.pull_hi,
			d.change_pct,
			d.runs_lo,
			d.runs_hi,
			d.band_offset,
			d.d_max
		]
		for i in got.size():
			assert_almost_eq(float(got[i]), float(want[id][i]), 1e-6, "%s field %d" % [id, i])
	assert_almost_eq(c.species["mahi"].run_peak_hi, 110.0, 1e-6)
	assert_almost_eq(c.species["tuna"].run_peak_factor, 1.08, 1e-6)
	assert_almost_eq(c.species["marlin"].run_peak_lo, 104.0, 1e-6)
	assert_almost_eq(c.species["marlin"].run_min_gap_s, 90.0, 1e-6)


func test_trip_files_match_the_brief() -> void:
	var fishing_min := {
		"free_20": 12, "free_30": 22, "free_45": 37, "free_60": 52, "free_90": 82, "free_120": 112
	}
	for id: String in fishing_min:
		var c := H.content(id)
		assert_true(c.ok, id)
		assert_almost_eq(c.trip.fishing_s, fishing_min[id] * 60.0, 1e-6, "%s: (N - 8) min" % id)
		assert_almost_eq(c.trip.fight_cap_frac, 0.4, 1e-6)
		assert_eq(c.trip.marlin_slot, 2 if id in ["free_90", "free_120"] else 0)
	var b := H.content("base_60")
	assert_almost_eq(b.trip.fishing_s, 52.0 * 60.0, 1e-6)
	assert_almost_eq(b.trip.fight_cap_frac, 0.25, 1e-6)
	assert_almost_eq(b.trip.top_pct, 100.0, 1e-6)


func test_plan_builder_labels_and_shape() -> void:
	var c := H.content("free_30")
	var slots := FishingPreroll.roll(c.trip, c.species, 3, 0)
	var plan := FishingPlanBuilder.build(c.trip, slots, 65)
	assert_eq(plan.phases[0].label, "FISHING_PHASE_RIDE_OUT")
	assert_almost_eq(plan.phases[0].ramp_to_pct, 65.0, 1e-6)
	assert_eq(plan.phases[1].label, "FISHING_PHASE_REEL_1")
	assert_almost_eq(plan.phases[1].target_pct, 65.0, 1e-6, "the rider's reel_pct")
	assert_eq(plan.phases[2].label, "FISHING_PHASE_%s_1" % slots[0].species.to_upper())
	assert_eq(plan.phases[2].meta, {"slot": 0, "species": slots[0].species})
	assert_eq(plan.phases[3].label, "FISHING_PHASE_LANDING")
	var tail := plan.phases[plan.phases.size() - 1]
	assert_eq(tail.label, "FISHING_PHASE_REEL_%d" % (slots.size() + 1), "trailing Reel")
	assert_eq(FishingPlanBuilder.reel_label(41), "Reel 41")
	assert_eq(FishingPlanBuilder.fight_label("marlin", 5), "Blue marlin 5")
	var e2e := H.content("e2e_2min")
	var ep := FishingPlanBuilder.build(
		e2e.trip, FishingPreroll.roll(e2e.trip, e2e.species, 1, 0), 70
	)
	assert_almost_eq(ep.phases[1].target_pct, 55.0, 1e-6, "e2e ignores reel_pct")
	assert_lte(ep.max_length_s(), 135.0, "e2e within 135 s")
	assert_not_null(PlanValidator.finalize(plan), "finalizes")


func _dicts(slots: Array[FishingPlanSlot]) -> Array:
	var out := []
	for s in slots:
		out.append(s.to_dict())
	return out
