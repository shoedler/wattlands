extends GutTest
## Autopilot (brief 2.5): routing by enemy HP in range with the 2-rider limit, ties to the lower
## pad, the 8 s and 25% hysteresis, the shop order and its budget, and that it never asks for
## Overdrive or changes effort.

const K := preload("res://tests/games/siege/module/siege_module_kit.gd")
## Between the gate's two flank pads: in reach of pad 3 (Ballista, 40 m) and pad 4 (Scorpion, 18 m).
const GATE := Vector2(0, 30)
## In reach of pad 3 only (22 m from it, 38 m from pad 4).
const EAST_OF_GATE := Vector2(30, 26)

# --- routing ---------------------------------------------------------------------------------


func test_no_enemy_in_range_means_the_generator() -> void:
	var st := K.state()
	var r := st.rider_at(0)
	assert_eq(SiegeAutopilot.route_choice(st, r), -1, "already on the generator")
	r.target = 3
	assert_eq(SiegeAutopilot.route_choice(st, r), SiegeIds.TARGET_GEN)


func test_the_tower_with_the_most_enemy_hp_in_range_wins() -> void:
	var st := K.state()
	K.enemy(st, EAST_OF_GATE, 40.0)
	assert_eq(st.enemy_hp_in_range(3), 40.0)
	assert_eq(st.enemy_hp_in_range(4), 0.0)
	assert_eq(SiegeAutopilot.route_choice(st, st.rider_at(0)), 3)


func test_ties_go_to_the_lower_pad() -> void:
	var st := K.state()
	K.enemy(st, GATE, 60.0)
	assert_eq(st.enemy_hp_in_range(3), st.enemy_hp_in_range(4))
	assert_eq(SiegeAutopilot.route_choice(st, st.rider_at(0)), 3)
	assert_eq(SiegeAutopilot.hot_target(st, st.rider_at(0)), 3)


func test_a_tower_with_two_riders_is_skipped() -> void:
	var st := K.state(SiegeIds.ROLE_WAVE, 3)
	K.enemy(st, GATE, 60.0)
	st.rider_at(0).target = 3
	st.rider_at(1).target = 3
	assert_eq(SiegeAutopilot.route_choice(st, st.rider_at(2)), 4, "pad 3 is full")
	assert_eq(SiegeAutopilot.route_choice(st, st.rider_at(0)), -1, "a rider on it stays")


func test_a_caltrop_thrower_counts_by_its_throw_range() -> void:
	var st := K.state()
	K.tower(st, 6, SiegeIds.TOWER_CALTROP)
	# Pad 6 is at (-32, 0): 25 m reach.
	K.enemy(st, Vector2(-32, 20), 35.0, SiegeIds.ENEMY_HORSEMEN, 0)
	assert_eq(st.enemy_hp_in_range(6), 35.0)
	assert_eq(SiegeAutopilot.route_choice(st, st.rider_at(0)), 6)
	st.enemies[0].pos = Vector2(-32, 30)
	assert_eq(st.enemy_hp_in_range(6), 0.0, "30 m is past the throw range")


func test_it_switches_at_most_once_per_8_seconds() -> void:
	var st := K.state()
	K.enemy(st, EAST_OF_GATE, 100.0)
	var r := st.rider_at(0)
	r.target = 4
	r.routed_t = st.t - 5.0
	assert_eq(SiegeAutopilot.route_choice(st, r), -1, "5 s since the last change")
	r.routed_t = st.t - 8.0
	assert_eq(SiegeAutopilot.route_choice(st, r), 3, "8 s is enough")


func test_it_switches_only_for_25_percent_more_enemy_hp() -> void:
	var st := K.state()
	K.enemy(st, GATE, 100.0)
	var near_pad3 := K.enemy(st, Vector2(20, 26), 20.0)
	var r := st.rider_at(0)
	r.target = 4
	assert_eq(st.enemy_hp_in_range(3), 120.0)
	assert_eq(st.enemy_hp_in_range(4), 100.0)
	assert_eq(SiegeAutopilot.route_choice(st, r), -1, "20% more is not enough")
	near_pad3.hp = 25.0
	assert_eq(SiegeAutopilot.route_choice(st, r), 3, "exactly 25% more is")
	near_pad3.hp = 24.0
	assert_eq(SiegeAutopilot.route_choice(st, r), -1)


func test_a_rider_on_a_quiet_tower_moves_to_a_busy_one_at_once() -> void:
	var st := K.state()
	K.enemy(st, EAST_OF_GATE, 20.0)
	var r := st.rider_at(0)
	r.target = 4
	assert_eq(st.enemy_hp_in_range(4), 0.0)
	assert_eq(SiegeAutopilot.route_choice(st, r), 3)


func test_it_only_routes_in_a_wave_and_never_for_a_dropped_rider() -> void:
	var st := K.state()
	K.enemy(st, EAST_OF_GATE, 100.0)
	var r := st.rider_at(0)
	for role in [SiegeIds.ROLE_BREAK, SiegeIds.ROLE_BUILD_BREAK, SiegeIds.ROLE_COOLDOWN]:
		st.role = role
		assert_eq(SiegeAutopilot.route_choice(st, r), -1, role)
	st.role = SiegeIds.ROLE_WARMUP_WAVE
	assert_eq(SiegeAutopilot.route_choice(st, r), 3, "the warm-up wave counts")
	r.afk = true
	assert_eq(SiegeAutopilot.route_choice(st, r), -1, "an AFK rider keeps its routing")


func test_retreating_enemies_do_not_attract_riders() -> void:
	var st := K.state()
	var e := K.enemy(st, EAST_OF_GATE, 100.0)
	e.st = SiegeIds.EN_RETREAT
	assert_eq(SiegeAutopilot.route_choice(st, st.rider_at(0)), -1)


# --- shop ------------------------------------------------------------------------------------


func _shop(denarii: float, role: String = SiegeIds.ROLE_BREAK) -> SiegeState:
	var st := K.state(role)
	st.rider_at(0).denarii = denarii
	return st


func _items(picks: Array[Dictionary]) -> Array:
	var out: Array = []
	for p in picks:
		out.append(p["item"])
	return out


func test_a_failing_gate_is_repaired_first_then_the_shop_goes_on() -> void:
	var st := _shop(200.0)
	st.gate_hp = 40.0
	var picks := SiegeAutopilot.shop_picks(st, st.rider_at(0))
	assert_eq(picks.size(), 2)
	assert_eq(picks[0]["item"], SiegeIds.ITEM_REPAIR)
	assert_ne(picks[1]["item"], SiegeIds.ITEM_REPAIR, "40 + 20 is 60%: whole enough")
	st.gate_hp = 50.0
	assert_ne(SiegeAutopilot.shop_picks(st, st.rider_at(0), 1)[0]["item"], SiegeIds.ITEM_REPAIR)


func test_picks_are_auto_buy_intents_and_never_overdrive_or_effort() -> void:
	var st := _shop(500.0)
	var picks := SiegeAutopilot.shop_picks(st, st.rider_at(0), 8)
	assert_gt(picks.size(), 2)
	for p in picks:
		assert_eq(p["k"], SiegeIds.INTENT_BUY)
		assert_true(p["auto"], "tagged auto so it never ends the zero-input fallback")
		assert_eq(p["via"], SiegeIds.VIA_AUTO)
		assert_eq(SiegeIntents.normalize(p), p, "already normalized")
	var code := FileAccess.get_file_as_string("res://src/games/siege/autopilot/siege_autopilot.gd")
	for word in ["INTENT_OVERDRIVE", "overdrive(", "directives", "target_pct", "ERG"]:
		assert_false(code.contains(word), "autopilot never touches %s" % word)


func test_with_no_damage_yet_it_builds_ballista_scorpion_caltrop_in_turn() -> void:
	var st := _shop(500.0)
	# Pad 3 holds a Ballista and pad 4 a Scorpion: the Caltrop thrower is next, then a Ballista.
	var picks := SiegeAutopilot.shop_picks(st, st.rider_at(0), 2)
	assert_eq(_items(picks), [SiegeIds.ITEM_BUILD_CALTROP, SiegeIds.ITEM_BUILD_BALLISTA])
	assert_ne(picks[0]["pad"], picks[1]["pad"], "the second pick sees the first")
	for p in picks:
		assert_false([3, 4].has(int(p["pad"])), "pad %d is free" % int(p["pad"]))
	K.tower(st, 5, SiegeIds.TOWER_CALTROP)
	K.tower(st, 6, SiegeIds.TOWER_BALLISTA)
	assert_eq(
		SiegeAutopilot.build_type(st, 0),
		SiegeIds.TOWER_SCORPION,
		"2 Ballistas, 1 Scorpion and 1 Caltrop: the Scorpion comes first"
	)


func test_it_builds_on_the_road_with_the_most_gate_damage() -> void:
	var st := _shop(500.0)
	st.gate_damage_by_road = [3.0, 1.0, 12.0]
	assert_eq(SiegeAutopilot.target_road(st), SiegeIds.ROAD_EAST)
	var pick := SiegeAutopilot.shop_picks(st, st.rider_at(0), 1)[0]
	var map := st.content.map
	var d := map.distance_to_road(map.pad_pos(int(pick["pad"])), SiegeIds.ROAD_EAST)
	for n in range(1, SiegeIds.PAD_COUNT + 1):
		if st.pad(n).built():
			continue
		var other := map.distance_to_road(map.pad_pos(n), SiegeIds.ROAD_EAST)
		assert_lte(d, other + 1e-6, "pad %d is no closer to the east road" % n)


func test_the_tower_type_follows_what_was_on_the_damaged_road() -> void:
	var st := _shop(500.0)
	st.gate_damage_by_road = [0.0, 0.0, 12.0]
	var e := K.enemy(st, Vector2(40, 40), 160.0, SiegeIds.ENEMY_SHIELD_WALL, SiegeIds.ROAD_EAST)
	var rider := st.rider_at(0)
	assert_eq(
		SiegeAutopilot.shop_picks(st, rider, 1)[0]["item"],
		SiegeIds.ITEM_BUILD_BALLISTA,
		"a Shield wall"
	)
	e.type = SiegeIds.ENEMY_RAM
	assert_eq(
		SiegeAutopilot.shop_picks(st, rider, 1)[0]["item"], SiegeIds.ITEM_BUILD_BALLISTA, "a ram"
	)
	e.type = SiegeIds.ENEMY_HORSEMEN
	assert_eq(
		SiegeAutopilot.shop_picks(st, rider, 1)[0]["item"],
		SiegeIds.ITEM_BUILD_CALTROP,
		"Horsemen and nothing heavier"
	)
	e.type = SiegeIds.ENEMY_RAIDERS
	assert_eq(
		SiegeAutopilot.shop_picks(st, rider, 1)[0]["item"],
		SiegeIds.ITEM_BUILD_SCORPION,
		"otherwise a Scorpion"
	)
	st.enemies.clear()
	assert_eq(
		SiegeAutopilot.shop_picks(st, rider, 1)[0]["item"],
		SiegeIds.ITEM_BUILD_BALLISTA,
		"in a break the damage came from the heavies"
	)


func test_it_upgrades_the_lowest_tower_on_the_road_when_a_build_is_too_dear() -> void:
	var st := _shop(45.0)
	st.gate_damage_by_road = [0.0, 0.0, 12.0]
	st.pad(3).level = 1
	var picks := SiegeAutopilot.shop_picks(st, st.rider_at(0))
	assert_eq(_items(picks), [SiegeIds.ITEM_UPGRADE], "50 for a Ballista is out of reach; 40 isn't")
	assert_eq(picks[0]["pad"], 4, "the Scorpion is the lowest tower")


func test_the_budget_runs_down_across_picks() -> void:
	var st := _shop(80.0)
	var picks := SiegeAutopilot.shop_picks(st, st.rider_at(0), 8)
	var cost := 0.0
	for p in picks:
		match str(p["item"]):
			SiegeIds.ITEM_BUILD_CALTROP:
				cost += 35.0
			SiegeIds.ITEM_BUILD_BALLISTA:
				cost += 50.0
			SiegeIds.ITEM_BUILD_SCORPION:
				cost += 40.0
			SiegeIds.ITEM_UPGRADE:
				cost += 40.0
			_:
				cost += 20.0
	assert_lte(cost, 80.0)
	assert_gt(picks.size(), 0)


func test_with_everything_built_it_goes_generator_bands_perks_then_saves() -> void:
	var st := _shop(1000.0)
	for n in range(1, SiegeIds.PAD_COUNT + 1):
		K.tower(st, n, SiegeIds.TOWER_BALLISTA, SiegeIds.MAX_TOWER_LEVEL)
	var picks := SiegeAutopilot.shop_picks(st, st.rider_at(0), 8)
	assert_eq(
		_items(picks),
		[
			SiegeIds.ITEM_GENERATOR,
			SiegeIds.ITEM_GENERATOR,
			SiegeIds.ITEM_GENERATOR,
			SiegeIds.ITEM_IRON_BANDS,
			SiegeIds.ITEM_IRON_BANDS,
			SiegeIds.ITEM_RESERVE,
			SiegeIds.ITEM_AQUEDUCT,
		],
		"then nothing is left to buy: it saves"
	)
	var short := _shop(44.0)
	for n in range(1, SiegeIds.PAD_COUNT + 1):
		K.tower(short, n, SiegeIds.TOWER_BALLISTA, SiegeIds.MAX_TOWER_LEVEL)
	assert_eq(_items(SiegeAutopilot.shop_picks(short, short.rider_at(0))), [], "44 < 45: save")


func test_the_shop_only_opens_in_breaks_and_max_items_caps_it() -> void:
	var st := _shop(500.0, SiegeIds.ROLE_WAVE)
	assert_eq(SiegeAutopilot.shop_picks(st, st.rider_at(0)).size(), 0, "no shopping in a wave")
	st.role = SiegeIds.ROLE_BUILD_BREAK
	assert_eq(SiegeAutopilot.shop_picks(st, st.rider_at(0)).size(), 2, "the build break is a shop")
	assert_eq(SiegeAutopilot.shop_picks(st, st.rider_at(0), 1).size(), 1)
	assert_eq(SiegeAutopilot.shop_picks(st, st.rider_at(0), 0).size(), 0)
	assert_eq(SiegeAutopilot.shop_picks(null, null).size(), 0)
