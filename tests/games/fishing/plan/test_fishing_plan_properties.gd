extends GutTest
## Plan properties (BRIEF 4.6, 4.5): every workout x 25 seeds x 4 riders x every reel_pct passes
## the PlanValidator with no warnings and every pre-roll rule; every Free Roam content grows its
## plan bite by bite (random species and sizes) and each replan validates with no warnings, the
## giants staying inside 4.6.1. The opt-in sweep (tests/games/fishing/plan/sweep/) runs the same
## checks at more seeds.

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


func _check_roam(trip_id: String, species: Array = FishingConst.SPECIES) -> void:
	var c := H.content(trip_id)
	assert_true(c.ok, "%s content valid: %s" % [trip_id, c.errors])
	if not c.ok:
		return
	var fails: Array[String] = []
	for seed in range(1, SEEDS + 1):
		fails.append_array(H.roam_failures(c, seed, species))
	assert_eq(fails.size(), 0, "%s: %s" % [trip_id, "\n".join(fails.slice(0, 8))])


func test_base_60() -> void:
	_check_trip("base_60")


func test_threshold() -> void:
	_check_trip("threshold")


func test_e2e_2min() -> void:
	_check_trip("e2e_2min")


func test_roam_10() -> void:
	_check_roam("roam_10")


func test_roam_20() -> void:
	_check_roam("roam_20")


func test_roam_30() -> void:
	_check_roam("roam_30")


func test_roam_45() -> void:
	_check_roam("roam_45")


func test_roam_60() -> void:
	_check_roam("roam_60", ["grouper", "oarfish", "marlin", "swordfish", "mackerel"])


func test_back_to_back_giants_keep_the_plan_valid() -> void:
	var c := H.content("roam_60")
	var fails: Array[String] = []
	for seed in range(1, 101):
		fails.append_array(H.roam_failures(c, seed, ["grouper", "oarfish"], 6))
	assert_eq(fails.size(), 0, "\n".join(fails.slice(0, 8)))


func test_the_giant_grouper_holds_105_to_110_for_at_most_300_s() -> void:
	var c := H.content("roam_60")
	var def: FishingSpeciesDef = c.species["grouper"]
	for k in 20:
		var w := k / 19.0
		var slot := FishingPreroll.roam_slot(def, w, 0, FishingRandom.derive(k, 1, 2), 0.0)
		assert_between(slot.base_pct, 105.0, 110.0, "w %.2f" % w)
		assert_eq(slot.hold_above_105, slot.base_pct > 105.0, "holds whenever above 105")
		assert_lte(slot.max_s, PlanValidator.LONG_PHASE_S, "never longer than 300 s above 105 %")
		assert_between(slot.t_nom_s, 180.0, 270.0, "3-4.5 min")
		assert_lte(slot.range_hi, FishingConst.SELF_CAP_PCT)


func test_a_second_giant_caps_at_105_once_300_s_have_accrued() -> void:
	var c := H.content("roam_60")
	var def: FishingSpeciesDef = c.species["grouper"]
	var first := FishingPreroll.roam_slot(def, 1.0, 0, FishingRandom.derive(1, 1, 2), 0.0)
	var second := FishingPreroll.roam_slot(def, 1.0, 1, FishingRandom.derive(1, 1, 2), first.max_s)
	assert_gt(first.base_pct, 105.0)
	assert_eq(second.base_pct, 105.0, "capped")
	assert_eq(second.range_hi, 105.0)
	assert_false(second.hold_above_105)


func test_a_roam_hint_size_sets_kg_pull_and_t_nom() -> void:
	var c := H.content("roam_30")
	for id: String in FishingConst.SPECIES:
		var def: FishingSpeciesDef = c.species[id]
		var small := FishingPreroll.roam_slot(def, 0.0, 0, FishingRandom.derive(3, 1, 2), 0.0)
		var big := FishingPreroll.roam_slot(def, 1.0, 0, FishingRandom.derive(3, 1, 2), 0.0)
		assert_almost_eq(small.kg, def.kg_lo, 1e-6, id)
		assert_almost_eq(big.kg, def.kg_hi, 1e-6, id)
		assert_lte(small.t_nom_s, big.t_nom_s, id)
		assert_lte(small.base_pct, big.base_pct, id)
		assert_gte(small.min_s, FishingConst.FIGHT_MIN_S, "%s: >= 30 s between switches" % id)


func test_every_roam_slot_passes_the_slot_checks() -> void:
	var c := H.content("roam_30")
	var fails: Array[String] = []
	for id: String in FishingConst.SPECIES:
		for seed in range(1, SEEDS + 1):
			var slot := H.species_slot(c, id, seed)
			var at := "%s %d" % [id, seed]
			fails.append_array(H.slot_failures(c, slot, FishingConst.SELF_CAP_PCT, at))
	assert_eq(fails.size(), 0, "\n".join(fails.slice(0, 8)))


func test_base_slots_stop_only_when_no_species_fits_the_budget_left() -> void:
	var c := H.content("base_60")
	var cap := c.trip.fight_cap_frac * c.trip.fishing_s
	for seed in range(1, SEEDS + 1):
		for rider in RIDERS:
			var used := 0.0
			for s in FishingPreroll.roll(c.trip, c.species, seed, rider):
				used += s.budget_s()
			for id: String in c.trip.species_weights:
				if FishingPreroll.fits(c.species[id], cap - used):
					fail_test("seed %d rider %d: %s still fits" % [seed, rider, id])
					return
	pass_test("every pre-roll ran its budget down")


func test_base_species_follow_the_trip_weights() -> void:
	var c := H.content("base_60")
	var counts := {"mackerel": 0, "mahi": 0}
	for seed in range(1, 101):
		for s in FishingPreroll.roll(c.trip, c.species, seed, seed % 4):
			assert_has(counts, s.species, "base_60 rolls only its species")
			counts[s.species] = int(counts.get(s.species, 0)) + 1
	var total := float(counts["mackerel"] + counts["mahi"])
	assert_between(counts["mackerel"] / total, 0.5, 0.8, "mackerel share %s" % [counts])


func test_preroll_is_deterministic_per_seed_and_slot() -> void:
	var c := H.content("base_60")
	var differ := 0
	for seed in range(1, 11):
		var a := _dicts(FishingPreroll.roll(c.trip, c.species, seed, 0))
		assert_eq(a, _dicts(FishingPreroll.roll(c.trip, c.species, seed, 0)), "same seed, same")
		if a != _dicts(FishingPreroll.roll(c.trip, c.species, seed, 1)):
			differ += 1
	assert_gt(differ, 7, "riders roll their own slots")
	var roam := H.content("roam_30")
	assert_eq(FishingPreroll.roll(roam.trip, roam.species, 1, 0).size(), 0, "roam pre-rolls none")


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
		assert_true(s.scheduled)
		assert_almost_eq(s.reel_s, 240.0 if s.index == 0 else 360.0, 1e-6)
	var e2e := H.content("e2e_2min")
	var m := FishingPreroll.roll(e2e.trip, e2e.species, 9, 2)
	assert_eq(m.size(), 1)
	assert_eq(m[0].species, "mackerel")
	assert_almost_eq(m[0].base_pct, 62.0, 1e-6)
	assert_almost_eq(m[0].band_offset, 3.0, 1e-6)
	assert_almost_eq(m[0].min_s, 36.0, 1e-6)
	assert_almost_eq(m[0].reel_s, 20.0, 1e-6)


func test_the_species_table_covers_every_zone_and_grows_out_to_sea() -> void:
	var c := H.content("roam_30")
	assert_eq(c.species.size(), 10)
	var zone_kg := {}
	for id: String in FishingConst.SPECIES:
		var d: FishingSpeciesDef = c.species[id]
		assert_eq(d.sprite, "fish_" + id)
		assert_eq(d.label, "FISHING_SPECIES_" + id.to_upper())
		for z in d.zones:
			zone_kg[z] = maxf(float(zone_kg.get(z, 0.0)), d.kg_hi)
		if d.max_s > PlanValidator.LONG_PHASE_S:
			assert_lte(d.pull_hi, 105.0, "%s: a long phase stays <= 105 %%" % id)
	for z in ["shallows", "reef", "shelf", "deep", "abyss"]:
		assert_true(zone_kg.has(z), "%s has fish" % z)
	assert_lt(zone_kg["shallows"], zone_kg["reef"])
	assert_lt(zone_kg["reef"], zone_kg["shelf"])
	assert_lt(zone_kg["shelf"], zone_kg["deep"])
	assert_true(c.species["grouper"].near_floor)
	assert_eq(c.species["oarfish"].zones, ["abyss"] as Array[String])
	assert_lte(c.species["mahi"].max_run_peak(88.0), 100.0, "reef fish stay around 90 %")


func test_content_files() -> void:
	for m in [10, 20, 30, 45, 60]:
		var c := H.content("roam_%d" % m)
		assert_true(c.ok, str(c.errors))
		assert_true(c.trip.is_roam())
		assert_eq(c.trip.minutes, float(m))
		assert_false(c.map.is_empty(), "roam loads map.json")
	var b := H.content("base_60")
	assert_almost_eq(b.trip.fishing_s, 52.0 * 60.0, 1e-6)
	assert_almost_eq(b.trip.fight_cap_frac, 0.25, 1e-6)
	assert_almost_eq(b.trip.top_pct, 100.0, 1e-6)
	assert_true(b.map.is_empty(), "workouts need no map")


func test_workout_plan_labels_and_shape() -> void:
	var c := H.content("base_60")
	var slots := FishingPreroll.roll(c.trip, c.species, 3, 0)
	var plan := FishingPlanBuilder.build(c.trip, slots, 65)
	assert_eq(plan.phases[0].label, "FISHING_PHASE_RIDE_OUT")
	assert_almost_eq(plan.phases[0].ramp_to_pct, 65.0, 1e-6)
	assert_eq(plan.phases[1].label, "FISHING_PHASE_TROLL")
	assert_almost_eq(plan.phases[1].target_pct, 65.0, 1e-6, "the rider's reel_pct")
	assert_eq(plan.phases[2].label, "FISHING_SPECIES_%s" % slots[0].species.to_upper())
	assert_eq(plan.phases[2].meta, {"slot": 0, "species": slots[0].species})
	assert_eq(plan.phases[3].label, "FISHING_PHASE_LANDING")
	assert_eq(plan.phases[plan.phases.size() - 1].label, "FISHING_PHASE_TROLL", "trailing Troll")
	var e2e := H.content("e2e_2min")
	var e2e_slots := FishingPreroll.roll(e2e.trip, e2e.species, 1, 0)
	var ep := FishingPlanBuilder.build(e2e.trip, e2e_slots, 70)
	assert_almost_eq(ep.phases[1].target_pct, 55.0, 1e-6, "e2e ignores reel_pct")
	assert_lte(ep.max_length_s(), 135.0, "e2e within 135 s")
	assert_not_null(PlanValidator.finalize(plan), "finalizes")


func test_the_roam_plan_starts_with_a_fixed_drive_out_and_an_open_roam() -> void:
	var plan := FishingPlanBuilder.roam(1800.0)
	assert_eq(plan.phases.size(), 2)
	var out := plan.phases[0]
	assert_eq([out.kind, out.mode, out.grade_source], [Wl.WARMUP, Wl.SIM, Wl.GRADE_GAME])
	assert_eq(out.duration_s, FishingConst.WARMUP_S)
	assert_false(out.open_ended, "no fight can start in the first 300 s")
	var roam := plan.phases[1]
	assert_eq([roam.kind, roam.mode, roam.grade_source], [Wl.FREE, Wl.SIM, Wl.GRADE_GAME])
	assert_true(roam.open_ended)
	assert_eq(roam.min_s, FishingConst.ROAM_MIN_S)
	assert_eq(roam.max_s, 1800.0 - 300.0 + 300.0 + 60.0, "outlasts play time and overtime")
	var res := PlanValidator.validate(plan)
	assert_true(bool(res["ok"]))
	assert_eq(res["warnings"], [])


func _dicts(slots: Array[FishingPlanSlot]) -> Array:
	return slots.map(func(s: FishingPlanSlot) -> Dictionary: return s.to_dict())
