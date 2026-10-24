extends GutTest
## FishingWorld: the roam map from map.json (zones, floor, abyss, edge), its validation, and the
## endless workout map from the seed.

const H := preload("res://tests/games/fishing/rules/fishing_rules_harness.gd")


func _map() -> Dictionary:
	return H.json("map.json")


func _roam() -> FishingWorld:
	return FishingWorld.from_map(_map(), 1)


func test_the_roam_map_runs_from_the_dock_to_the_edge() -> void:
	var w := _roam()
	assert_eq(w.length_m(), 18000.0)
	assert_eq(w.edge_x_m(), 17900.0)
	assert_false(w.endless)
	var ids: Array = w.zones().map(func(z: Dictionary) -> String: return z["id"])
	assert_eq(ids, ["dock", "shallows", "reef", "shelf", "deep", "abyss"])


func test_zone_at_follows_the_zone_ranges() -> void:
	var w := _roam()
	assert_eq(w.zone_at(-5.0), "dock")
	assert_eq(w.zone_at(100.0), "dock")
	assert_eq(w.zone_at(600.0), "shallows")
	assert_eq(w.zone_at(5000.0), "reef")
	assert_eq(w.zone_at(10000.0), "shelf")
	assert_eq(w.zone_at(14000.0), "deep")
	assert_eq(w.zone_at(17800.0), "abyss")
	assert_eq(w.zone_index_at(14000.0), FishingWorld.ZONES.find("deep"))


func test_the_floor_deepens_out_to_sea_and_drops_away_in_the_abyss() -> void:
	var w := _roam()
	assert_between(w.floor_depth_m(100.0), 3.0, 7.0)
	assert_lt(w.floor_depth_m(2000.0), w.floor_depth_m(9000.0))
	assert_gt(w.floor_depth_m(15200.0), 400.0, "the deep")
	assert_true(w.has_floor(16400.0))
	assert_true(is_inf(w.floor_depth_m(17000.0)), "the abyss has no floor")
	assert_true(is_inf(w.floor_depth_m(19000.0)), "nor past the edge")


func test_the_relief_stays_within_6_percent_of_the_profile() -> void:
	var w := _roam()
	for x in [1000.0, 3000.0, 6666.0, 10200.0, 13600.0]:
		var profile := FishingWorld.from_map(_map())._base_depth(x)
		assert_between(w.floor_depth_m(x), profile * 0.94 - 1e-6, profile * 1.06 + 1e-6, "x %s" % x)


func test_sample_floor_and_minimap_are_batch_samplers() -> void:
	var w := _roam()
	var s := w.sample_floor(0.0, 18000.0, 91)
	assert_eq(s.size(), 91)
	assert_almost_eq(s[10], w.floor_depth_m(2000.0), 1e-3)
	assert_true(is_inf(s[90]))
	var m := w.minimap(64)
	assert_eq([m["x0"], m["x1"]], [0.0, 18000.0])
	assert_eq((m["floor"] as PackedFloat32Array).size(), 64)
	assert_eq((m["zones"] as Array).size(), 6)
	assert_true((m["zones"][0] as Dictionary).has("colour"))


func test_map_json_validation_names_every_problem() -> void:
	assert_eq(FishingWorld.errors(_map()), [] as Array[String])
	var bad := _map().duplicate(true)
	bad["edge_x_m"] = 99999
	bad["zones"][1]["x_m"] = [700, 4000]
	bad["zones"][2]["id"] = "lagoon"
	bad["floor_m"][2] = [0, 5]
	bad["landmarks"][1]["kind"] = "castle"
	bad["landmarks"][2]["id"] = "harbour_light"
	bad["landmarks"][3]["x_m"] = 99999
	var errs := FishingWorld.errors(bad)
	assert_eq(errs.size(), 8, str(errs))
	assert_null(FishingWorld.from_map(bad))
	assert_eq(FishingWorld.errors(null).size(), 1)


func test_the_endless_map_never_ends_and_cycles_its_zones() -> void:
	var w := FishingWorld.endless_for(42)
	assert_true(w.endless)
	assert_true(is_inf(w.length_m()))
	assert_true(is_inf(w.edge_x_m()))
	assert_eq(w.zone_at(100.0), "dock")
	var seen := {}
	for x in range(700, 120000, 1000):
		seen[w.zone_at(float(x))] = true
		assert_true(w.has_floor(float(x)), "always a floor (x %d)" % x)
	assert_false(seen.has("abyss"))
	assert_true(
		seen.has("shallows") and seen.has("reef") and seen.has("shelf") and seen.has("deep")
	)


func test_the_endless_map_is_the_same_for_the_same_seed_and_differs_otherwise() -> void:
	var a := FishingWorld.endless_for(5)
	var b := FishingWorld.endless_for(5)
	var c := FishingWorld.endless_for(6)
	assert_eq(a.sample_floor(0.0, 60000.0, 60), b.sample_floor(0.0, 60000.0, 60))
	assert_ne(a.sample_floor(0.0, 60000.0, 60), c.sample_floor(0.0, 60000.0, 60))
	# Querying far ahead first gives the same zones as walking there.
	var d := FishingWorld.endless_for(5)
	assert_eq(d.zone_at(50000.0), a.zone_at(50000.0))


func test_endless_segments_keep_their_lengths_and_ease_their_floors() -> void:
	var w := FishingWorld.endless_for(9)
	var zs := w.zones(0.0, 40000.0)
	for i in range(1, zs.size() - 1):
		var length := float(zs[i]["x1"]) - float(zs[i]["x0"])
		assert_between(length, FishingWorld.SEG_MIN_M, FishingWorld.SEG_MAX_M)
	var x0 := float(zs[2]["x0"])
	var jump := absf(w.floor_depth_m(x0 + 1.0) - w.floor_depth_m(x0 - 1.0))
	assert_lt(jump, 5.0, "no cliff at a segment border")


func test_the_roam_landmarks_sit_in_their_zones() -> void:
	var w := _roam()
	var lms := w.landmarks()
	var kinds: Array = lms.map(func(l: Dictionary) -> String: return l["kind"])
	assert_eq(kinds, ["lighthouse", "reef_arch", "whale_bones", "wreck"])
	var zones_at: Array = lms.map(func(l: Dictionary) -> String: return w.zone_at(l["x_m"]))
	assert_eq(zones_at, ["dock", "reef", "shelf", "deep"])
	assert_eq(w.landmarks(5000.0, 12000.0).size(), 2, "a window lists only its landmarks")
	lms[0]["x_m"] = -1.0
	assert_eq(float(w.landmarks()[0]["x_m"]), 240.0, "copies")


func test_a_map_without_landmarks_is_valid() -> void:
	var m := _map().duplicate(true)
	m.erase("landmarks")
	assert_eq(FishingWorld.errors(m), [] as Array[String])
	assert_eq(FishingWorld.from_map(m).landmarks(), [] as Array[Dictionary])


func test_endless_landmarks_follow_the_segments_from_the_seed() -> void:
	var w := FishingWorld.endless_for(9)
	var lms := w.landmarks(0.0, 60000.0)
	assert_eq(str(lms[0]["kind"]), "lighthouse")
	assert_gt(lms.size(), 8)
	var px := -1.0
	for lm in lms.slice(1):
		var x := float(lm["x_m"])
		assert_gt(x, px, "in x order")
		px = x
		var zi := w.zone_index_at(x)
		assert_eq(str(lm["kind"]), FishingWorld.LANDMARK_FOR_ZONE[zi], "the zone's own kind")
	assert_eq(FishingWorld.endless_for(9).landmarks(0.0, 60000.0), lms, "deterministic")
	assert_ne(FishingWorld.endless_for(10).landmarks(0.0, 60000.0), lms, "seeded")
	var win := w.landmarks(20000.0, 30000.0)
	for lm in win:
		assert_between(float(lm["x_m"]), 20000.0, 30000.0)
