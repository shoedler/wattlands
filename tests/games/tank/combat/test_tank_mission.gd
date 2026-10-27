extends GutTest
## Ashfall Road and the drill (brief 2.4 mission P0, 2.9, T6): validated at load, the encounter
## lists the plan builder relies on, the terrain, and what each tank meets.


func _load(id: String) -> TankContent:
	return TankContent.from_dicts(TankContent.read_files(id), id)


func _segments(c: TankContent, type: String) -> Array:
	return c.segments().filter(func(s: Dictionary) -> bool: return s["type"] == type)


static func _is_rear_light(e: Dictionary) -> bool:
	return e["enemy"] == "light" and e.get("from") == "rear"


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


func test_stages_2_and_3_end_in_a_heavy_tank_duel_at_the_gun_line() -> void:
	var c := _load("ashfall_road")
	var lines := _segments(c, "gun_line")
	assert_eq(_count(lines[0]["enemies"], "heavy"), 0)
	assert_gte(_count(lines[0]["enemies"], "dugin"), 3)
	for i in [1, 2]:
		assert_eq(_count(lines[i]["enemies"], "heavy"), 1, "stage %d" % (i + 1))
	# P4 rules ADR: gun line 3 keeps one dug-in beside its heavy and destroyer (2 -> 1, the -50%
	# bound) so a crew's duel stays inside T1's 160 s.
	assert_gte(_count(lines[1]["enemies"], "dugin"), 2)
	assert_eq(_count(lines[2]["enemies"], "dugin"), 1)
	assert_eq(_count(lines[2]["enemies"], "destroyer"), 1, "stage 3 adds a tank destroyer")
	for g: Dictionary in lines:
		assert_lte(float(g["max_s"]), 180.0, "a 90% gun line lasts at most 180 s")
		assert_eq(float(g["duration_s"]), 120.0)
		assert_eq(float(g["min_s"]), 60.0)


## The brief's lists, except one medium fewer in stages 2 and 3 (2 -> 1, the -50% bound; ADR "Balance
## iteration 1") and stage 1's rear light and destroyer (P4 rules ADR): every Advance still has a
## telegraphed shot and a medium (T6).
func test_the_brief_enemy_lists_per_stage() -> void:
	var c := _load("ashfall_road")
	var adv := _segments(c, "advance")
	var s1: Array = adv[0]["encounters"]
	assert_eq([_count(s1, "light"), _count(s1, "medium"), _count(s1, "destroyer")], [3, 1, 1])
	assert_eq(
		s1.filter(_is_rear_light).size(), 1, "stage 1's rear light: a flank shot no gun reaches"
	)
	assert_eq(adv[0]["obstacles"].map(func(o: Dictionary) -> String: return o["type"]), ["wire"])
	var s2: Array = adv[1]["encounters"]
	assert_eq([_count(s2, "medium"), _count(s2, "destroyer"), _count(s2, "light")], [1, 1, 1])
	assert_eq(
		s2.filter(func(e: Dictionary) -> bool: return e.get("from") == "rear").size(),
		1,
		"one light from the rear"
	)
	assert_eq(adv[1]["obstacles"].map(func(o: Dictionary) -> String: return o["type"]), ["wreck"])
	var s3: Array = adv[2]["encounters"]
	assert_eq([_count(s3, "medium"), _count(s3, "destroyer"), _count(s3, "light")], [1, 1, 2])
	assert_eq(s3.filter(_is_rear_light).size(), 1)
	assert_eq(adv[2]["obstacles"].size(), 0)


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


func test_the_depot_script_is_drive_then_aim_then_fire_with_one_teaching_toast_per_station(
) -> void:
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
	var engines := {}
	for t: Dictionary in depot["teach"]:
		engines[t["engine"]] = int(engines.get(t["engine"], 0)) + 1
		assert_lt(float(t["at_s"]), 300.0)
	for e in ["diesel", "dynamo", "steam", "bulwark"]:
		assert_eq(engines.get(e, 0), 1, "one teaching toast for the %s" % e)
	assert_false(depot.has("encounters"), "no enemies in the depot")


func test_the_boss_segment_and_the_cooldown_backdrops() -> void:
	var c := _load("ashfall_road")
	var boss := c.segment(10)
	assert_eq(boss["type"], "boss")
	assert_eq([int(boss["duration_s"]), int(boss["min_s"]), int(boss["max_s"])], [240, 120, 360])
	var citadel_stop := float(TankConst.REAR_SCREEN_X) + 288.0 + float(c.boss_def()["stop_px"])
	assert_gt(
		float(boss["boss"]["start_left_px"]),
		citadel_stop,
		"the Behemoth starts past the longest tank's stop line"
	)
	assert_gt(float(boss.get("end_hold_s", 0.0)), 0.0, "a death beat before the boss phase ends")
	assert_eq(boss["backdrop"], "bg_town_near", "the foundry town")
	assert_eq(c.mission()["cooldown"]["backdrop_victory"], "bg_town_near")
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
	assert_false(c.mission_rotates())
	for pt: Array in skirmish["terrain"]:
		assert_between(float(pt[1]), 0.0, 2.0)


func test_the_citadel_never_meets_more_than_16_enemies_at_once_even_if_none_dies() -> void:
	var c := _load("ashfall_road")
	for s: Dictionary in _segments(c, "advance"):
		var total := 0
		for e: Dictionary in s["encounters"]:
			total += c.scaled_count(int(e["count"]), "citadel")
		assert_lte(total, TankConst.MAX_ENEMIES)
	for s: Dictionary in _segments(c, "gun_line"):
		var total := 0
		for e: Dictionary in s["enemies"]:
			total += c.scaled_count(int(e["count"]), "citadel")
		assert_lte(total, TankConst.MAX_ENEMIES)


func test_each_tank_meets_the_scaled_gun_line() -> void:
	for crew in [1, 2, 3]:
		var rig := TankRulesRig.new(crew)
		var tank := TankIds.tank_for_crew(crew)
		for i in 3:
			var index: int = [2, 5, 8][i]
			var want := 0
			for spec: Dictionary in rig.content.segment(index)["enemies"]:
				want += rig.content.scaled_count(int(spec["count"]), tank)
			rig.enter(index, 0.0)
			assert_eq(rig.state.gun_line.guns_total, want, "crew %d gun line %d" % [crew, i + 1])
			assert_eq(rig.state.enemies.size(), want)
			assert_gte(want, 3, "a gun line is never a walkover")


func test_the_gun_line_enemies_stand_where_the_mission_put_them_clamped_to_the_screen() -> void:
	var rig := TankRulesRig.new(3)
	rig.enter(8, 0.0)
	var front_screen := 16.0 + rig.hull().hull_w
	for e in rig.state.enemies:
		var far_screen := front_screen + e.hold_px + e.w
		assert_lte(far_screen, 632.0 + 0.01)
		assert_gte(e.hold_px, rig.content.num("enemies", "lanes.min_hold_px", 60.0) - 0.01)
