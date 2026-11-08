extends GutTest
## The big game trip: its own map (the dock, then one mixed biome where tuna and grouper both bite
## directly and nothing else lives), the trip's `map` field and its validation, the zone's
## index-coupled tables, and a cast in the biome that ends in a tuna or a grouper.

const H := preload("res://tests/games/fishing/rules/fishing_rules_harness.gd")
const F := preload("res://tests/games/fishing/fishing_fakes.gd")
const ZONE := "bluewater"
const TRIP := "big_game_30"


func test_the_trip_is_a_roam_trip_with_its_own_map() -> void:
	var c := H.load_content(TRIP)
	assert_true(c.ok, str(c.errors))
	assert_true(c.trip.is_roam())
	assert_eq(c.trip.minutes, 30.0)
	assert_eq(c.trip.map, "map_big_game.json")
	assert_eq(c.map["id"], "big_game")
	var roam := H.load_content("roam_30")
	assert_eq(roam.trip.map, "map.json", "no map field: map.json")
	assert_eq(roam.map["id"], "roam")


func test_the_map_is_the_dock_then_the_one_biome() -> void:
	var w := FishingWorld.from_map(H.load_content(TRIP).map, 1)
	var ids: Array = w.zones().map(func(z: Dictionary) -> String: return z["id"])
	assert_eq(ids, ["dock", ZONE])
	assert_eq(w.zone_at(100.0), "dock")
	assert_eq(w.zone_at(w.edge_x_m() - 10.0), ZONE)
	assert_eq(w.zone_index_at(3000.0), FishingWorld.ZONES.find(ZONE))
	for x in range(700, int(w.edge_x_m()), 500):
		assert_true(w.has_floor(float(x)), "a floor all the way (x %d)" % x)
	assert_gt(w.floor_depth_m(w.edge_x_m() - 100.0), 80.0, "deep enough for a grouper's ledge")
	assert_gte(w.landmarks().size(), 2, "the harbour light and something to sail past")


func test_every_zone_table_has_an_entry_for_the_new_zone() -> void:
	var n := FishingWorld.ZONES.size()
	assert_eq(FishingWorld.ZONES[n - 1], ZONE, "appended: no index moved")
	assert_eq(FishingWorld.ZONE_DEPTH_M.size(), n)
	assert_eq(FishingWorld.ZONE_COLOURS.size(), n)
	assert_eq(FishingWorld.LANDMARK_FOR_ZONE.size(), n)
	assert_eq(FishingFloor.MERGE_ROWS.size(), n)
	assert_eq(FishingFloor.RELIEF.size(), n)
	assert_eq(FishingProps.BIG.size(), n)
	assert_eq(FishingProps.SMALL.size(), n)
	assert_eq(
		FishingWorld.ZONES.slice(0, 6), ["dock", "shallows", "reef", "shelf", "deep", "abyss"]
	)
	var keys := FileAccess.get_file_as_string("res://content/fishing/strings.csv")
	assert_string_contains(keys, "FISHING_ZONE_%s," % ZONE.to_upper())
	assert_string_contains(keys, "FISHING_MAP_BIG_GAME,")
	assert_string_contains(keys, "FISHING_CONTENT_BIG_GAME_30,")
	assert_string_contains(keys, "FISHING_CARD_BIG_GAME,")


func test_only_tuna_and_grouper_live_in_the_biome() -> void:
	var c := H.load_content(TRIP)
	var here: Array[String] = []
	for id: String in FishingConst.SPECIES:
		if (c.species[id] as FishingSpeciesDef).zones.has(ZONE):
			here.append(id)
	assert_eq(here, ["tuna", "grouper"] as Array[String])
	assert_true((c.species["tuna"] as FishingSpeciesDef).zones.has("shelf"), "still on the shelf")
	assert_true((c.species["grouper"] as FishingSpeciesDef).zones.has("deep"), "still in the deep")


func test_hints_in_the_biome_are_tuna_and_grouper_with_the_groupers_on_the_floor() -> void:
	var h := H.new()
	h.setup(TRIP, 1, 5)
	var r := h.rider()
	var seen := {}
	for k in 60:
		r.x_m = 1500.0 + 50.0 * float(k)
		FishingRules.new_hints(h.state, r)
		var floor_d := h.state.world.floor_depth_m(r.x_m)
		assert_eq(r.hint_count(), FishingConst.HINTS_PER_STOP)
		for i in r.hint_count():
			var sp := int(r.hints[4 * i])
			seen[FishingConst.SPECIES[sp]] = true
			var depth := r.hints[4 * i + 2]
			if FishingConst.SPECIES[sp] == "grouper":
				assert_between(depth, floor_d - 10.0 - 1e-6, floor_d - 3.0 + 1e-6, "on the floor")
			else:
				assert_between(
					depth, 15.0 - 1e-6, minf(60.0, floor_d - 3.0) + 1e-6, "a tuna's depth"
				)
	assert_eq(seen.keys().size(), 2, "both bite directly: %s" % [seen.keys()])
	assert_true(seen.has("tuna") and seen.has("grouper"))


func test_a_cast_in_the_biome_ends_in_a_bite_and_a_fight_with_one_of_them() -> void:
	var h := H.new()
	h.setup(TRIP, 1, 3)
	h.follow_band[0] = true
	h.drive_w[0] = 220.0
	assert_true(h.run_until(func() -> bool: return h.rider().x_m >= 1500.0, 600.0))
	h.drive_w[0] = 20.0
	assert_true(h.run_to_action(0, FishingConst.A_MENU, 60.0))
	assert_eq(h.state.world.zone_at(h.rider().x_m), ZONE)
	assert_eq(h.rider().hint_count(), FishingConst.HINTS_PER_STOP, "fish on offer right here")
	h.drive_w[0] = 100.0
	h.send(0, FishingIntents.confirm(FishingIntents.VIA_ACTION))
	h.step()
	assert_true(h.run_to_action(0, FishingConst.A_FIGHT, 400.0), "it bites")
	var sp: String = FishingConst.SPECIES[h.rider().fish.sp]
	assert_has(["tuna", "grouper"], sp)
	assert_eq(h.violations, [] as Array[String])


func test_the_trip_map_field_is_validated() -> void:
	var good := {"id": "x", "kind": "roam", "minutes": 30, "map": "map_big_game.json"}
	assert_eq(FishingTripDef.errors(good, []), [] as Array[String])
	assert_eq(FishingTripDef.from_dict(good).map, "map_big_game.json")
	var no_map := {"id": "x", "kind": "roam", "minutes": 30}
	assert_eq(FishingTripDef.errors(no_map, []), [] as Array[String], "missing: map.json")
	assert_eq(FishingTripDef.from_dict(no_map).map, "map.json")
	for bad: Variant in [
		5, "", "../map.json", "sub/map.json", "map.txt", "Map.json", "species.json"
	]:
		var d := good.duplicate()
		d["map"] = bad
		var errs := FishingTripDef.errors(d, [])
		assert_eq(errs.size(), 1, "%s is refused" % [bad])
		if errs.size() == 1:
			assert_string_contains(errs[0], "map")


func test_an_unknown_map_file_is_a_load_error() -> void:
	var c := FishingContent.new().parse(
		H.json("species.json"),
		{"id": "x", "kind": "roam", "minutes": 30, "map": "nope.json"},
		null,
		H.json("cosmetics.json")
	)
	assert_false(c.ok)
	assert_eq(c.errors.size(), 1)
	assert_string_contains(c.errors[0], "nope.json")


func test_load_for_reads_the_trips_own_map_and_refuses_a_missing_one() -> void:
	var ctx := F.make_ctx(1, 0, TRIP, Wl.SOLO, 1)
	var c := FishingContent.load_for(ctx)
	assert_true(c.ok, str(c.errors))
	assert_eq(c.map["id"], "big_game")
	var bad := F.make_ctx(1, 0, TRIP, Wl.SOLO, 1)
	bad.content_overrides = {"trips/%s.json" % TRIP: {"map": "nope.json"}}
	var b := FishingContent.load_for(bad, true)
	assert_false(b.ok)
	assert_push_error("missing content")


func test_a_map_error_names_its_own_file() -> void:
	var m: Dictionary = H.json("map_big_game.json").duplicate(true)
	m["length_m"] = -1
	var c := FishingContent.new().parse(
		H.json("species.json"), H.json("trips/%s.json" % TRIP), m, H.json("cosmetics.json")
	)
	assert_false(c.ok)
	assert_string_contains("; ".join(c.errors), "map_big_game.json:")
	assert_false("; ".join(c.errors).contains("map.json:"))


func test_the_ride_tag_names_the_trip() -> void:
	var c := H.load_content(TRIP)
	var st := FishingRules.new_state(c, [], 1, [])
	var tx := GameStrings.new()
	assert_string_contains(FishingResults.ride_tag(st, c, tx), "Big game")
	var roam := H.load_content("roam_30")
	var st2 := FishingRules.new_state(roam, [], 1, [])
	assert_string_contains(FishingResults.ride_tag(st2, roam, tx), "Free Roam 30")


func test_the_trip_is_in_the_manifest_with_a_card() -> void:
	var m := F.manifest()
	assert_has(m["contents"], TRIP)
	assert_true((m["content_cards"] as Dictionary).has(TRIP))
	assert_true(ResourceLoader.exists(str((m["content_cards"][TRIP] as Dictionary)["image"])))


func test_bots_fish_the_biome() -> void:
	var h := H.new()
	h.setup(TRIP, 3, 4, [], 2)
	for i in 2:
		var r := h.rider(1 + i)
		r.strategy = [0, 3][i]
		r.stop_x = NAN
		FishingAutopilot.plan_stop(h.state, r)
		assert_eq(
			h.state.world.zone_at(r.stop_x), ZONE, "strategy %d stops in the biome" % r.strategy
		)
