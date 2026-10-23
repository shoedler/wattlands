extends GutTest
## The sprite planes: the near plane follows the segment (fields, village, quarry, town, depot), the
## cool-down's backdrop follows the outcome, and the scenery lights are a pure function of the scroll.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")


func _state_at(index: int) -> TankState:
	var s := TankFixtures.state(1)
	s.seg.phase_index = index
	return s


func test_every_mission_segment_names_a_known_near_plane() -> void:
	var c := TankFixtures.content()
	for i in c.segments().size():
		var id := TankBackdrop.backdrop_id(_state_at(i))
		assert_has(TankBackdrop.NEAR_IDS, id, "segment %d" % i)


func test_the_planes_of_ashfall_road_by_stage() -> void:
	var want := {
		0: "bg_depot_near",
		1: "bg_fields_near",
		4: "bg_village_near",
		7: "bg_quarry_near",
		10: "bg_town_near",
	}
	for i: int in want:
		assert_eq(TankBackdrop.backdrop_id(_state_at(i)), want[i], "segment %d" % i)


func test_the_cooldown_backdrop_follows_the_outcome() -> void:
	var s := _state_at(99)
	s.outcome = TankIds.OUTCOME_VICTORY
	assert_eq(TankBackdrop.backdrop_id(s), "bg_town_near")
	s.outcome = TankIds.OUTCOME_WITHDRAWN
	assert_eq(TankBackdrop.backdrop_id(s), "bg_fields_near")


func test_set_near_swaps_once_per_change() -> void:
	var b := TankBackdrop.new()
	add_child_autofree(b)
	autofree(b.front)
	var start := b.swaps
	b.set_near("bg_village_near")
	b.set_near("bg_village_near")
	assert_eq(b.swaps, start + 1)
	b.set_near("not_a_plane")
	assert_eq(b.near_id, "bg_fields_near", "an unknown id falls back to the fields")


func test_the_view_switches_planes_when_the_segment_changes() -> void:
	var s := TankFixtures.state(1)
	var v := U.view_of(self, s)
	assert_eq(v.backdrop.near_id, "bg_village_near")
	s.seg.phase_index = 7
	v.advance(0.02)
	assert_eq(v.backdrop.near_id, "bg_quarry_near")


func test_scenery_is_deterministic_and_scrolls_at_the_near_factor() -> void:
	for id in TankBackdrop.NEAR_IDS:
		var a := TankBackdrop.scenery(id, 1000.0)
		var b := TankBackdrop.scenery(id, 1000.0)
		assert_eq(a.size(), b.size(), id)
		for i in a.size():
			assert_eq(a[i]["pos"], b[i]["pos"], id)
	var base := TankBackdrop.scenery("bg_town_near", 1000.0)
	var moved := TankBackdrop.scenery("bg_town_near", 1100.0)
	assert_gt(base.size(), 0, "the town has lights in view")
	var dx := (base[0]["pos"] as Vector2).x - (moved[0]["pos"] as Vector2).x
	assert_almost_eq(dx, 50.0, 1.01, "100 px of camera is 50 px of the 0.5 plane")


func test_scenery_colours_are_the_palette_s_warm_and_cold_lights_only() -> void:
	var warm := [TankPalette.FIRE, TankPalette.AMBER, TankPalette.GLOW_WARM]
	var cold := [TankPalette.COLD_LIGHT, TankPalette.COLD, TankPalette.WHITE_COLD]
	var seen_cold := false
	for id in TankBackdrop.NEAR_IDS:
		for cam in range(0, 3000, 150):
			for l in TankBackdrop.scenery(id, float(cam)):
				var c: Color = l["color"]
				assert_true(c in warm or c in cold, id)
				seen_cold = seen_cold or c in cold
	assert_true(seen_cold, "cold work lamps and floodlights exist")


func test_the_fields_burn_somewhere_on_poplar_road() -> void:
	var fires := 0
	for cam in range(0, 3000, 150):
		for l in TankBackdrop.scenery("bg_fields_near", float(cam)):
			if bool(l["fire"]):
				fires += 1
	assert_gt(fires, 0, "a burning farmstead")
