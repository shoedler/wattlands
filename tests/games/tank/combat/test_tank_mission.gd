extends GutTest
## Ashfall Road and the drill (brief 2.4 mission P0, 2.9, T6): validated at load, the encounter
## lists the plan builder relies on, the terrain, and what each tank meets.


func _load(id: String) -> TankContent:
	return TankContent.from_dicts(TankContent.read_files(id), id)


func _segments(c: TankContent, type: String) -> Array:
	return c.segments().filter(func(s: Dictionary) -> bool: return s["type"] == type)


func _count(list: Array, enemy: String, key: String = "enemy") -> int:
	var n := 0
	for e: Dictionary in list:
		if str(e.get(key, "")) == enemy:
			n += int(e.get("count", 1))
	return n


func test_both_missions_load_and_validate() -> void:
	for id in ["ashfall_road", "drill"]:
		var c := _load(id)
		assert_true(c.ok(), "%s: %s" % [id, "; ".join(c.errors)])


func test_a_broken_mission_is_rejected_at_load() -> void:
	var files := TankContent.read_files("ashfall_road")
	files["mission"]["segments"][1]["encounters"][0]["enemy"] = "dragon"
	var c := TankContent.from_dicts(files, "ashfall_road")
	assert_false(c.ok())
	files = TankContent.read_files("ashfall_road")
	files["mission"]["segments"][1]["terrain"] = [[0, 0], [100, 9]]
	assert_false(TankContent.from_dicts(files, "ashfall_road").ok(), "a grade past +6%")


func test_the_segment_order_and_lengths_are_the_briefs() -> void:
	var c := _load("ashfall_road")
	var types: Array = c.segments().map(func(s: Dictionary) -> String: return s["type"])
	assert_eq(
		types,
		[
			"depot",
			"advance",
			"gun_line",
			"checkpoint",
			"advance",
			"gun_line",
			"checkpoint",
			"advance",
			"gun_line",
			"checkpoint",
			"boss"
		]
	)
	var total := 0.0
	var longest := 0.0
	for s: Dictionary in c.segments():
		total += float(s["duration_s"])
		longest += float(s.get("max_s", s["duration_s"]))
	assert_eq(total, 1800.0 - 180.0, "30 min with the 180 s cool-down the validator appends")
	assert_eq(longest + 180.0, 2460.0, "at most 41 min")
	# The brief: 1300 / 1300 / 1400 m. Tuned inside +-50% (the Bulwark stops to hoist, so its
	# Advance runs longest); the brief's own values stay the reference.
	var brief := [1300.0, 1300.0, 1400.0]
	var lengths: Array = _segments(c, "advance").map(
		func(s: Dictionary) -> float: return float(s["length_m"])
	)
	for i in 3:
		assert_between(
			float(lengths[i]), float(brief[i]) * 0.5, float(brief[i]) * 1.5, "stage %d" % (i + 1)
		)


func test_every_stage_has_a_light_sprint_prompt_and_a_medium_in_its_advance() -> void:
	var c := _load("ashfall_road")
	for s: Dictionary in _segments(c, "advance"):
		var enc: Array = s["encounters"]
		assert_gte(
			_count(enc, "light"), 1, "stage %d: a light tank's telegraphed flank shot" % s["stage"]
		)
		assert_gte(_count(enc, "medium"), 1, "stage %d: a medium to hold the band for" % s["stage"])


func _table(list: Array, key: String) -> Array:
	var out: Array = []
	for e: Dictionary in list:
		out.append([int(e[key]), str(e["enemy"]), int(e.get("min_crew", 1))])
	return out


func _force(list: Array) -> Array:
	var out: Array = []
	for e: Dictionary in list:
		var hold: Array = e["hold_m"].map(func(m: float) -> int: return int(m))
		out.append([str(e["enemy"]), int(e["count"]), hold, int(e.get("min_crew", 1))])
	return out


## SPEC_TANK 3.2, the Advances.
func test_the_advance_tables() -> void:
	var adv := _segments(_load("ashfall_road"), "advance")
	assert_eq(
		_table(adv[0]["encounters"], "at_m"),
		[
			[130, "light", 1],
			[250, "recon", 2],
			[360, "medium", 1],
			[600, "destroyer", 1],
			[700, "tankette", 2],
			[830, "light", 1]
		]
	)
	assert_eq(
		_table(adv[1]["encounters"], "at_m"),
		[[109, "medium", 1], [349, "recon", 2], [589, "destroyer", 1], [800, "light", 1]]
	)
	assert_eq(
		_table(adv[2]["encounters"], "at_m"),
		[
			[95, "medium", 1],
			[266, "tankette", 2],
			[475, "light", 1],
			[608, "destroyer", 1],
			[760, "recon", 2]
		]
	)
	assert_eq(adv[0]["obstacles"].map(func(o: Dictionary) -> String: return o["type"]), ["wire"])
	assert_eq(adv[1]["obstacles"].map(func(o: Dictionary) -> String: return o["type"]), ["wreck"])
	assert_eq(adv[2]["obstacles"].size(), 0)


## SPEC_TANK 3.2, the holding actions and the boss's near list: heavies and destroyers on the move at
## long range; no dug-in, no stationary gun.
func test_the_holding_action_tables() -> void:
	var c := _load("ashfall_road")
	var lines := _segments(c, "gun_line")
	assert_eq(
		_force(lines[0]["enemies"]),
		[
			["medium", 2, [1200, 1500], 1],
			["medium", 1, [1350], 2],
			["light", 1, [900], 2],
			["light", 1, [1050], 4]
		]
	)
	assert_eq(_table(lines[0]["near"], "at_s"), [[15, "tankette", 3], [40, "recon", 3]])
	assert_eq(
		_force(lines[1]["enemies"]),
		[
			["heavy", 1, [1500], 1],
			["medium", 2, [1150, 1450], 2],
			["medium", 1, [1300], 3],
			["medium", 1, [1550], 3]
		]
	)
	assert_eq(_table(lines[1]["near"], "at_s"), [[20, "recon", 3], [55, "tankette", 3]])
	assert_eq(
		_force(lines[2]["enemies"]),
		[
			["heavy", 1, [1600], 1],
			["medium", 1, [1200], 2],
			["destroyer", 1, [1900], 2],
			["medium", 1, [1400], 3]
		]
	)
	assert_eq(_table(lines[2]["near"], "at_s"), [[25, "recon", 3], [60, "recon", 3]])
	assert_eq(
		_table(c.segment(10)["near"], "at_s"),
		[[30, "tankette", 3], [90, "recon", 3], [150, "tankette", 3]]
	)
	for i in 3:
		var g: Dictionary = lines[i]
		assert_eq(g["label"], "TANK_PHASE_HOLD_%d" % (i + 1), "the UI says Holding action")
		assert_lte(float(g["max_s"]), 180.0, "a 90% gun line lasts at most 180 s")
		assert_eq(float(g["duration_s"]), 120.0)
		assert_eq(float(g["min_s"]), 60.0)
	assert_eq(c.mission()["difficulty_default"], TankIds.DIFF_NORMAL)
	assert_eq(_load("drill").mission()["difficulty_default"], TankIds.DIFF_EASY)


func test_the_schema_refuses_a_rear_spawn_and_a_hold_nearer_than_the_kind() -> void:
	var files := TankContent.read_files("ashfall_road")
	files["mission"]["segments"][1]["encounters"][0]["from"] = "rear"
	var errors := TankContentSchema.validate_mission(files["mission"], "ashfall_road")
	assert_true(", ".join(errors).contains("from"), ", ".join(errors))
	files = TankContent.read_files("ashfall_road")
	files["mission"]["segments"][5]["enemies"][0]["hold_m"] = [1000]
	assert_false(TankContent.from_dicts(files, "ashfall_road").ok(), "a heavy nearer than 1300 m")


func test_nothing_in_the_shipped_lists_is_a_dug_in_or_comes_from_behind() -> void:
	for id in ["ashfall_road", "drill"]:
		for s: Dictionary in _load(id).segments():
			for key in ["encounters", "enemies", "near"]:
				for e: Dictionary in s.get(key, []):
					assert_has(TankIds.ENEMY_TYPES, str(e["enemy"]))
					assert_false(e.has("from"), "%s %s" % [id, s["id"]])
					assert_false(e.has("at_px"), "%s %s" % [id, s["id"]])


## Hard's count above a list's own total goes to the last entries, the lightest and latest first.
func test_hard_counts_spill_to_the_last_entries() -> void:
	var rig := TankRulesRig.new(4)
	var total := func(l: Array[int]) -> int:
		var n := 0
		for v in l:
			n += v
		return n
	var seg1: Array = rig.content.segment(1)["encounters"]
	assert_eq(total.call(TankEncounters.crew_counts(rig.state, seg1)), 6, "Normal crew 4")
	rig.state.difficulty = TankIds.DIFF_HARD
	assert_eq(total.call(TankEncounters.crew_counts(rig.state, seg1)), 6, "Hard's count is 1.0")
	# The rule itself, at a count above 1 (the shared content is restored below).
	var row: Dictionary = rig.content.data["enemies"]["difficulty"][TankIds.DIFF_HARD]
	var tuned: float = row["count"]
	row["count"] = 1.3
	var hard := TankEncounters.crew_counts(rig.state, seg1)
	assert_eq(total.call(hard), 8, "crew 4: 6 x 1.3 rounded")
	assert_eq(hard, [1, 1, 1, 1, 2, 2] as Array[int], "the last two get the extra")
	var hold1 := TankEncounters.crew_counts(rig.state, rig.content.segment(2)["enemies"])
	assert_eq(hold1, [2, 1, 2, 2] as Array[int], "5 x 1.3 rounded: from the last entry back")
	rig.enter(2, 0.0)
	var spawned := rig.state.enemies.size()
	row["count"] = tuned
	assert_eq(spawned, 7)
	var easy := TankRulesRig.new(4)
	easy.state.difficulty = TankIds.DIFF_EASY
	assert_eq(
		total.call(TankEncounters.crew_counts(easy.state, seg1)), 4, "Easy crew 4: 6 x 0.6 rounded"
	)


func test_near_threats_of_a_holding_action_come_by_seconds() -> void:
	var rig := TankRulesRig.new(4)
	rig.no_fire = true
	rig.no_bow = true
	rig.enter(2, 1.0)
	assert_eq(rig.of_type("ambush").size(), 0)
	rig.run(14.5)
	assert_eq(rig.of_type("ambush").size(), 1, "at_s 15: a tankette")
	assert_eq(rig.of_type("ambush")[0]["e"], TankIds.enemy_code(TankIds.ENEMY_TANKETTE))
	rig.run(25.0)
	assert_eq(rig.of_type("ambush").size(), 2, "at_s 40: a recon car")
	assert_eq(rig.of_type("ambush")[1]["e"], TankIds.enemy_code(TankIds.ENEMY_RECON))
	var solo := TankRulesRig.new(1)
	solo.no_fire = true
	solo.enter(2, 1.0)
	solo.run(45.0)
	assert_eq(solo.of_type("ambush").size(), 0, "min_crew 2: a solo rider meets none")


func test_an_advance_spawns_each_frame_through_its_own_class() -> void:
	var rig := TankRulesRig.new(4)
	rig.no_fire = true
	rig.no_bow = true
	rig.enter(1, 1.0)
	rig.hull().distance_m = 251.0
	rig.run(0.1)
	var near := rig.state.enemies.filter(func(e: TankEnemyState) -> bool: return e.is_near())
	var far := rig.state.enemies.filter(func(e: TankEnemyState) -> bool: return not e.is_near())
	assert_eq(near.size(), 1, "the recon car")
	assert_eq(far.size(), 1, "the light")
	assert_gt(far[0].range_m, 0.0)
	assert_eq(rig.of_type("ambush").size(), 1)


func test_encounters_are_ordered_and_inside_the_advance() -> void:
	var c := _load("ashfall_road")
	for s: Dictionary in _segments(c, "advance"):
		var last := -1.0
		for e: Dictionary in s["encounters"]:
			assert_gt(float(e["at_m"]), last, "ascending at_m")
			assert_lt(float(e["at_m"]), float(s["length_m"]) - 100.0, "well before the halt line")
			last = float(e["at_m"])
		for o: Dictionary in s["obstacles"]:
			assert_between(float(o["at_m"]), 300.0, float(s["length_m"]) - 100.0)


func test_the_terrain_profiles_match_the_briefs_ranges() -> void:
	var c := _load("ashfall_road")
	var ranges := [[-2.0, 3.0], [-3.0, 5.0], [-3.0, 6.0]]
	var adv := _segments(c, "advance")
	for i in 3:
		var lo := INF
		var hi := -INF
		var last := -1.0
		for pt: Array in adv[i]["terrain"]:
			lo = minf(lo, float(pt[1]))
			hi = maxf(hi, float(pt[1]))
			assert_gt(float(pt[0]), last - 0.001)
			last = float(pt[0])
		assert_gte(lo, float(ranges[i][0]), "stage %d low" % (i + 1))
		assert_lte(hi, float(ranges[i][1]), "stage %d high" % (i + 1))
		assert_gte(hi - 1.0, float(ranges[i][1]) - 1.5, "and it uses the range")
		assert_lte(last, float(adv[i]["length_m"]) + 0.001)
	for pt: Array in c.segment(0)["terrain"]:
		assert_between(float(pt[1]), 0.0, 2.0, "depot terrain 0 to +2%")


func test_the_depot_script_is_drive_then_aim_then_fire() -> void:
	var c := _load("ashfall_road")
	var depot := c.segment(0)
	assert_eq(int(depot["duration_s"]), 300)
	var drills: Array = depot["drills"]
	assert_eq(
		drills.map(func(d: Dictionary) -> String: return d["drill"]), ["drive", "aim", "fire"]
	)
	assert_eq([int(drills[0]["from_s"]), int(drills[0]["to_s"])], [0, 120])
	assert_eq(
		[int(drills[1]["from_s"]), int(drills[1]["to_s"]), int(drills[1]["targets"])], [120, 240, 2]
	)
	assert_eq([int(drills[2]["from_s"]), int(drills[2]["to_s"])], [240, 300])
	assert_false(depot.has("encounters"), "no enemies in the depot")


func test_the_boss_segment_and_the_cooldown_backdrops() -> void:
	var c := _load("ashfall_road")
	var boss := c.segment(10)
	assert_eq(boss["type"], "boss")
	assert_eq([int(boss["duration_s"]), int(boss["min_s"]), int(boss["max_s"])], [240, 120, 360])
	assert_gt(float(boss.get("end_hold_s", 0.0)), 0.0, "a death beat before the boss phase ends")
	assert_eq(boss["backdrop"], TankIds.BACKDROP_BASE, "v3: the Behemoth's gate at a little base")
	assert_eq(c.mission()["cooldown"]["backdrop_victory"], TankIds.BACKDROP_BASE)
	for s: Dictionary in c.segments():
		assert_has(TankIds.BACKDROPS, str(s["backdrop"]), "v3: the forest, or a little base")
	assert_true(c.mission()["cooldown"].has("backdrop_withdrawn"))


func test_the_drill_is_130_seconds_inside_warmup_limits() -> void:
	var c := _load("drill")
	assert_eq(
		c.segments().map(func(s: Dictionary) -> float: return float(s["duration_s"])),
		[30.0, 70.0, 30.0]
	)
	assert_eq(
		c.segments().map(func(s: Dictionary) -> String: return s["kind"]),
		["WARMUP", "WARMUP", "RECOVERY"]
	)
	var skirmish := c.segment(1)
	assert_eq(_count(skirmish["encounters"], "light"), 2)
	assert_eq(_count(skirmish["encounters"], "medium"), 1)
	assert_false(skirmish.has("min_s"), "fixed length: no objective")
	assert_false(c.mission().has("rotation"), "v3 retired rotation")
	for pt: Array in skirmish["terrain"]:
		assert_between(float(pt[1]), 0.0, 2.0)


func test_no_crew_meets_more_than_16_enemies_at_once_even_if_none_dies() -> void:
	var c := _load("ashfall_road")
	for s: Dictionary in _segments(c, "advance"):
		var total := 0
		for e: Dictionary in s["encounters"]:
			total += c.scaled_count(int(e["count"]), TankIds.TANK_LANDSHIP)
		assert_lte(total, TankConst.MAX_ENEMIES)
	for s: Dictionary in _segments(c, "gun_line"):
		var total := 0
		for e: Dictionary in s["enemies"]:
			total += c.scaled_count(int(e["count"]), TankIds.TANK_LANDSHIP)
		assert_lte(total, TankConst.MAX_ENEMIES)


## v3: enemy counts by crew size (0.5 / 0.7 / 0.85 / 1.0 per segment, at least 1).
func test_each_crew_meets_its_scaled_holding_force() -> void:
	for crew in [1, 2, 3, 4]:
		var rig := TankRulesRig.new(crew)
		for i in 3:
			var index: int = [2, 5, 8][i]
			var want := 0
			for n in TankEncounters.crew_counts(rig.state, rig.content.segment(index)["enemies"]):
				want += n
			rig.enter(index, 0.0)
			assert_eq(rig.state.gun_line.guns_total, want, "crew %d hold %d" % [crew, i + 1])
			assert_eq(rig.state.enemies.size(), want)
			# A solo rider meets holds 2 and 3's heavy alone (min_crew 2 on the rest).
			assert_gte(want, 1 if crew == 1 else 2, "a holding action is never a walkover")


func test_the_holding_force_stands_where_the_mission_put_it() -> void:
	var rig := TankRulesRig.new(4)
	rig.enter(8, 0.0)
	var holds: Array = rig.state.enemies.map(func(e: TankEnemyState) -> float: return e.hold_m)
	assert_eq(holds, [1600.0, 1200.0, 1900.0, 1400.0])


## The segment's total x the crew's scale (rounded, at least 1), taken from the list in order.
func test_enemy_counts_scale_by_crew_size_per_segment() -> void:
	var c := TankFixtures.content()
	assert_eq(c.value("enemies", "crew_count_scale", []), [0.5, 0.7, 0.85, 1.0])
	var adv_want := {1: 2, 2: 4, 3: 5, 4: 6}
	var hold2 := {1: [1, 0, 0, 0], 2: [1, 1, 0, 0], 3: [1, 2, 1, 0], 4: [1, 2, 1, 1]}
	for crew: int in adv_want:
		var rig := TankRulesRig.new(crew)
		assert_eq(
			TankEncounters.crew_counts(rig.state, rig.content.segment(5)["enemies"]),
			hold2[crew] as Array[int],
			"hold 2, crew %d" % crew
		)
		var adv := TankEncounters.crew_counts(rig.state, rig.content.segment(1)["encounters"])
		var n := 0
		for k in adv:
			n += k
		assert_eq(n, adv_want[crew], "Advance 1, crew %d" % crew)
	var hp := TankRulesRig.new(1)
	hp.enter(5, 0.0)
	for e in hp.state.enemies:
		assert_eq(e.hp_max, float(c.enemy_def(TankIds.enemy_of(e.code))["hp"]), "HP the same")


## v3 solo balance: an entry with min_crew (an enemy, a holding force's unit or a barricade) is not
## there for smaller crews, and does not count in their total; crews from min_crew on meet it as before.
func test_min_crew_entries_skip_the_smaller_crews() -> void:
	var solo := TankRulesRig.new(1)
	solo.enter(1, 0.0)
	assert_eq(solo.state.obstacles.size(), 0, "no wire for a solo rider")
	var crew := TankRulesRig.new(2)
	crew.enter(1, 0.0)
	assert_eq(crew.state.obstacles.size(), 1, "the wire for a crew")
	solo.enter(8, 0.0)
	assert_eq(solo.state.enemies.size(), 1)
	assert_eq(solo.state.enemies[0].code, TankIds.enemy_code(TankIds.ENEMY_HEAVY))
	var bad := TankContent.read_files("ashfall_road")
	(bad["mission"]["segments"][2]["enemies"][0] as Dictionary)["min_crew"] = 5
	var errors := TankContentSchema.validate_mission(bad["mission"], "ashfall_road")
	assert_true(", ".join(errors).contains("min_crew"), ", ".join(errors))


# --- Ambush (SPEC_TANK 3.8) -----------------------------------------------------------------------


func test_ambush_15_defaults_to_hard_and_lists_its_enemies() -> void:
	var c := TankFixtures.content("ambush_15")
	assert_true(c.ok(), "; ".join(c.errors))
	assert_eq(TankDifficulty.resolve("auto", c), TankIds.DIFF_HARD)
	assert_eq(TankDifficulty.resolve("easy", c), TankIds.DIFF_EASY, "the host's choice wins")
	var adv := c.segment(1)
	assert_eq(float(adv["length_m"]), 700.0)
	var enemies: Array = (adv["encounters"] as Array).map(
		func(e: Dictionary) -> Array: return [float(e["at_m"]), str(e["enemy"])]
	)
	assert_eq(
		enemies,
		[
			[35.0, "medium"],
			[105.0, "recon"],
			[210.0, "light"],
			[315.0, "destroyer"],
			[420.0, "tankette"],
			[470.0, "light"],
			[525.0, "medium"]
		]
	)
	var hold := c.segment(2)
	assert_eq(str(hold["enemies"][0]["enemy"]), "heavy")
	assert_eq(hold["enemies"][1]["hold_m"], [1100.0, 1350.0])
	assert_eq((hold["near"] as Array).size(), 2)
	assert_eq((c.segment(4)["near"] as Array).size(), 2)
	assert_eq(float(c.segment(4)["end_hold_s"]), 7.5)
	var stages: Array = c.segments().map(func(s: Dictionary) -> int: return int(s["stage"]))
	assert_eq(stages, [0, 1, 1, 1, 4])


func test_ambush_15_plays_to_the_cool_down_on_every_difficulty() -> void:
	for d: String in TankIds.DIFFICULTIES:
		var rig := TankRulesRig.new(3, "ambush_15", 2)
		rig.state.difficulty = d
		rig.auto_seat = true
		rig.bank_director = true
		var t := rig.play(1.0, 1100.0)
		assert_true(rig.in_cooldown(), d)
		assert_lt(t, 835.0, "%s: 830 s at the max_s before the 180 s cool-down" % d)
		assert_has([TankIds.OUTCOME_VICTORY, TankIds.OUTCOME_WITHDRAWN], rig.state.outcome, d)
