extends GutTest
## Free roam's rules (brief 2.10, 4): the roam contents and their expansion, the seeded valley, the
## drive along it, the turn (ownership, the 8 s stop, the flip, the cooldown, the Autopilot at the
## ends), patrols and their caps, strongpoints and the engagement halt, time up and the overtime
## bound, and the crew's points. v4: nothing is ever behind the tank.

const ROAMS: Array[String] = ["roam_10", "roam_20", "roam_30", "roam_45", "roam_60"]


func _rig(crew: int = 3, mission: String = "roam_30", rng_seed: int = 7) -> TankRulesRig:
	var rig := TankRulesRig.new(crew, mission, rng_seed)
	assert_true(rig.content.ok(), "content: %s" % "; ".join(rig.content.errors))
	return rig


func _valley() -> Dictionary:
	return TankFixtures.content("roam_30").valley()


## Steps into the roam phase `into_s` seconds in (the drive-out done).
func _enter_roam(rig: TankRulesRig, into_s: float = 0.0) -> void:
	rig.enter(1, into_s)


## Events of `type` in `list` (the rig's of_type falls back to every event on an empty list).
func _count(list: Array[Dictionary], type: String) -> int:
	var n := 0
	for e in list:
		if str(e.get("type", "")) == type:
			n += 1
	return n


func _driver_peer(rig: TankRulesRig) -> int:
	var p := rig.peer_of(TankIds.ENGINE_DIESEL)
	return p if p != 0 else rig.peer_of(TankIds.ENGINE_BULWARK)


# --- Contents ------------------------------------------------------------------------------------


func test_every_roam_content_expands_into_the_drive_out_and_the_roam() -> void:
	for id in ROAMS:
		var c := TankContent.from_dicts(TankContent.read_files(id), id)
		assert_true(c.ok(), "%s: %s" % [id, "; ".join(c.errors)])
		assert_true(c.is_roam(), id)
		var minutes := int(id.trim_prefix("roam_"))
		assert_eq(c.roam_minutes(), minutes, id)
		assert_false(c.mission().has("rotation"), "no rotation in v3: " + id)
		assert_eq(c.plan_table(), "roam_plans", id)
		var segs := c.segments()
		assert_eq(segs.size(), 2, id)
		assert_eq(str(segs[0]["type"]), TankIds.SEG_DEPOT, id)
		assert_eq(str(segs[0]["kind"]), Wl.WARMUP, id)
		assert_eq(float(segs[0]["duration_s"]), 300.0, id)
		assert_false((segs[0] as Dictionary).has("drills"), "no drills, no enemies: " + id)
		assert_eq(str(segs[1]["type"]), TankIds.SEG_ROAM, id)
		assert_eq(str(segs[1]["kind"]), Wl.WORK, id)
		assert_eq(float(segs[1]["min_s"]), minutes * 60.0 - 300.0, id)
		assert_eq(float(segs[1]["plan_min_s"]), TankConst.SWITCH_GAP_S, "the plan phase min_s")
		assert_eq(float(segs[1]["max_s"]), minutes * 60.0, id)
		assert_gt(float(segs[1]["max_s"]), 300.0, "every roam phase is longer than 300 s: " + id)


func test_a_bad_roam_file_or_valley_is_a_load_error() -> void:
	var files := TankContent.read_files("roam_30")
	files["mission"]["minutes"] = 5
	assert_false(TankContent.from_dicts(files, "roam_30").ok(), "minutes below 10")
	files = TankContent.read_files("roam_30")
	files["valley"]["terrain_pct"] = [-3, 7]
	assert_false(TankContent.from_dicts(files, "roam_30").ok(), "terrain past +6%")
	files = TankContent.read_files("roam_30")
	files["valley"]["drive_out_s"] = 200
	assert_false(TankContent.from_dicts(files, "roam_30").ok(), "a drive-out under 300 s")
	files = TankContent.read_files("roam_30")
	(files["valley"]["zones"] as Dictionary).erase("quarry")
	assert_false(TankContent.from_dicts(files, "roam_30").ok(), "a zone missing")
	files = TankContent.read_files("roam_30")
	files["valley"]["grades"]["C"] = 99
	assert_false(TankContent.from_dicts(files, "roam_30").ok(), "grade cut-offs out of order")
	files = TankContent.read_files("ashfall_road")
	files["valley"] = null
	assert_true(TankContent.from_dicts(files, "ashfall_road").ok(), "missions ignore the valley")


# --- The map -------------------------------------------------------------------------------------


func test_the_valley_is_seeded_and_deterministic() -> void:
	var v := _valley()
	var a := TankRoamMap.build(v, 12345)
	var b := TankRoamMap.build(v, 12345)
	assert_eq(a.length_m, b.length_m)
	assert_eq(a.zones, b.zones)
	assert_eq(a.terrain, b.terrain)
	assert_eq(a.strongpoints, b.strongpoints)
	var differ := false
	for s in [1, 2, 3, 99, 4242]:
		var c := TankRoamMap.build(v, s)
		if c.zones != a.zones or c.terrain != a.terrain:
			differ = true
	assert_true(differ, "other seeds give other valleys")


func test_every_valley_is_about_6_km_of_contiguous_zones() -> void:
	var v := _valley()
	for s in range(1, 41):
		var m := TankRoamMap.build(v, s * 7919)
		assert_between(m.length_m, 5800.0, 6200.0, "length, seed %d" % s)
		assert_eq(str(m.zones[0]["id"]), TankIds.ZONE_FOREST, "the west end is forest")
		assert_eq(str(m.zones[m.zones.size() - 1]["id"]), TankIds.ZONE_FOREST, "the east end too")
		var at := 0.0
		var seen := {}
		for z: Dictionary in m.zones:
			assert_eq(float(z["from_m"]), at, "contiguous")
			assert_gt(float(z["to_m"]), float(z["from_m"]))
			at = float(z["to_m"])
			seen[str(z["id"])] = int(seen.get(str(z["id"]), 0)) + 1
		assert_eq(at, m.length_m, "the zones fill the road")
		for z2: String in [
			TankIds.ZONE_LAKE, TankIds.ZONE_VILLAGE, TankIds.ZONE_QUARRY, TankIds.ZONE_MEADOW
		]:
			assert_eq(int(seen.get(z2, 0)), 1, "%s once, seed %d" % [z2, s])
		var last := -1.0
		for pt: Array in m.terrain:
			assert_gte(float(pt[0]), last, "terrain ascending")
			last = float(pt[0])
			assert_between(float(pt[1]), -3.0, 5.0, "terrain -3..+5%")
		assert_eq(float(m.terrain[0][1]), 0.0, "flat at the west turning place")
		assert_eq(float(m.terrain[m.terrain.size() - 1][1]), 0.0, "flat at the east one")
		assert_gte(m.strongpoints.size(), 2, "strongpoints, seed %d" % s)
		for i in m.strongpoints.size():
			assert_between(m.strongpoints[i], 700.0, m.length_m - 700.0, "clear of the ends")
			if i > 0:
				assert_gte(m.strongpoints[i] - m.strongpoints[i - 1], 900.0, "spaced")
		var prof := m.profile(64)
		assert_eq(prof.size(), 64)


func test_the_grade_flips_westward_and_stays_in_bounds() -> void:
	var c := TankFixtures.content("roam_30")
	var m := TankRoamMap.build(c.valley(), 777)
	var x := 0.0
	while x < m.length_m:
		assert_almost_eq(m.grade_at(x, -1), -m.grade_at(x, 1), 1e-6)
		for d in [1, -1]:
			var g := TankTerrain.for_roam(c, m, x, d, false)
			assert_between(g, -3.0, 5.0, "WORK grade at %d m" % x)
			var w := TankTerrain.for_roam(c, m, x, d, true)
			assert_between(w, 0.0, 2.0, "warm-up grade at %d m" % x)
		x += 37.0


func test_the_map_seed_comes_from_the_session_rng() -> void:
	var a := _rig(3, "roam_30", 11)
	var b := _rig(3, "roam_30", 11)
	var c := _rig(3, "roam_30", 12)
	assert_true(a.state.roam.active)
	assert_ne(a.state.roam.map_seed, 0)
	assert_eq(a.state.roam.map_seed, b.state.roam.map_seed, "the same seed, the same valley")
	assert_ne(a.state.roam.map_seed, c.state.roam.map_seed)
	assert_not_null(a.state.roam_map)
	assert_eq(a.state.hull.dir, TankIds.DIR_RIGHT)
	assert_eq(a.state.roam.map_m, float(_valley()["start_m"]))
	var mission := _rig(3, "ashfall_road")
	assert_false(mission.state.roam.active, "missions leave free roam off")
	assert_null(mission.state.roam_map)


# --- The drive -----------------------------------------------------------------------------------


func test_the_drive_out_drives_east_with_no_enemies() -> void:
	var rig := _rig(3)
	rig.enter(0)
	var start := rig.state.roam.map_m
	rig.run(299.0)
	assert_gt(rig.state.roam.map_m, start + 500.0, "the tank drives the valley in the drive-out")
	assert_eq(rig.state.enemies.size(), 0, "no enemies in the drive-out")
	assert_eq(rig.of_type(TankEvents.SHOT).size(), 0)
	assert_almost_eq(rig.state.roam.odo_m, rig.state.roam.map_m - start, 0.01)
	assert_eq(rig.state.roam.work_m, 0.0, "the km points count the roam phase only")
	assert_between(rig.state.hull.grade_pct, 0.0, 2.0, "the warm-up terrain range")


func test_the_road_stops_at_the_turning_place() -> void:
	var rig := _rig(3)
	_enter_roam(rig)
	rig.state.roam.map_m = rig.state.roam_map.hi_m - 30.0
	rig.run(11.0)
	assert_almost_eq(rig.state.roam.map_m, rig.state.roam_map.hi_m, 0.01, "stopped at the end")
	assert_eq(rig.state.roam.at_end, 1)
	assert_eq(rig.state.hull.speed_mps, 0.0)
	assert_gt(rig.state.roam.end_s, 3.0, "the end clock runs while it stands there")


# --- The turn ------------------------------------------------------------------------------------


func test_only_the_driver_owns_the_turn() -> void:
	assert_true(TankIntents.owned(TankIds.INTENT_TURN, TankIds.ENGINE_DIESEL))
	for e: String in [
		TankIds.ENGINE_DYNAMO, TankIds.ENGINE_STEAM, TankIds.ENGINE_ARC, TankIds.ENGINE_FEED
	]:
		assert_false(TankIntents.owned(TankIds.INTENT_TURN, e), e)
	assert_true(TankIntents.is_deliberate(TankIntents.normalize({"k": "turn"})))
	assert_false(TankIntents.is_deliberate(TankIntents.normalize(TankIntents.auto("turn"))))


func test_a_turn_stops_8_s_flips_at_its_midpoint_and_cools_down_30_s() -> void:
	var rig := _rig(3)
	_enter_roam(rig, 10.0)
	rig.run(5.0)
	var driver := _driver_peer(rig)
	var slot := rig.rider(driver).slot
	var at := rig.state.roam.map_m
	rig.send(driver, {"k": "turn"})
	var ev := rig.step()
	var turns := rig.of_type(TankEvents.TURN, ev)
	assert_eq(turns.size(), 1)
	assert_eq(int(turns[0]["s"]), slot)
	assert_eq(int(turns[0]["dir"]), TankIds.DIR_LEFT)
	assert_eq(rig.state.hull.dir, TankIds.DIR_RIGHT, "not flipped before the midpoint")
	rig.run(3.5)
	assert_eq(rig.state.hull.dir, TankIds.DIR_RIGHT)
	assert_eq(rig.state.hull.speed_mps, 0.0, "stopped")
	rig.run(1.0)
	assert_eq(rig.state.hull.dir, TankIds.DIR_LEFT, "flipped at 4 s")
	assert_almost_eq(rig.state.roam.map_m, at, 0.05, "a turn on the spot")
	rig.run(3.0)
	assert_gt(rig.state.roam.turn_s, 0.0, "still turning before 8 s")
	rig.run(1.0)
	assert_eq(rig.state.roam.turn_s, 0.0)
	rig.run(5.0)
	assert_lt(rig.state.roam.map_m, at - 5.0, "drives west after the turn")
	rig.send(driver, {"k": "turn"})
	assert_eq(_count(rig.step(), TankEvents.TURN), 0, "the 30 s cooldown")
	rig.run(17.0)
	rig.send(driver, {"k": "turn"})
	assert_eq(_count(rig.step(), TankEvents.TURN), 1, "turns again after 30 s")


func test_a_turn_clears_the_field_with_no_credit_and_mirrors_the_obstacles() -> void:
	var rig := _rig(3)
	_enter_roam(rig, 10.0)
	rig.no_fire = true
	rig.no_bow = true
	rig.state.roam.patrol_s = 1.0e9
	rig.far(TankIds.ENEMY_MEDIUM)
	rig.near(TankIds.ENEMY_RECON)
	rig.state.roam.strong_id[0] = rig.far(TankIds.ENEMY_HEAVY).id
	var aux := TankAux.of(rig.state)
	TankEnemies.launch_far(rig.state, aux, 900.0, TankIds.SHELL_ENEMY, 1.0, 0.0, false, 0, 1, [])
	var o := TankEncounters.add_obstacle(rig.state, TankIds.OBST_WIRE, rig.state.hull.x_px + 1000.0)
	var at := TankRoam.map_of(rig.state, o.x_px + float(o.w) * 0.5)
	var kills := rig.state.score.crew_kills
	rig.send(_driver_peer(rig), {"k": "turn"})
	rig.step()
	rig.run(4.1)
	assert_eq(rig.state.hull.dir, TankIds.DIR_LEFT)
	assert_eq(
		rig.state.hull.facing, TankIds.FACE_RIGHT, "the turret keeps its facing: v4 has no rear"
	)
	assert_eq(rig.state.enemies.size(), 0, "every enemy gone")
	assert_eq(rig.state.shells.size(), 0, "every shell gone")
	assert_eq(rig.state.score.crew_kills, kills, "no credit")
	assert_eq(rig.of_type(TankEvents.KILL).size(), 0)
	assert_eq(rig.state.roam.strong_id[0], 0)
	assert_between(rig.state.roam.patrol_s, 40.0, 110.1, "the next patrol's wait rolled anew")
	var after := TankRoam.map_of(rig.state, o.x_px + float(o.w) * 0.5)
	assert_almost_eq(after, at, 0.5, "the obstacle stays where it was on the road")


func test_a_turn_with_a_running_telegraph_leaves_no_evade_behind() -> void:
	var rig := _rig(3)
	_enter_roam(rig, 10.0)
	rig.no_fire = true
	var e := rig.far(TankIds.ENEMY_DESTROYER)
	e.gun_s = 1.0
	rig.run(0.2)
	assert_eq(e.mode, TankIds.EM_TELEGRAPH)
	rig.send(_driver_peer(rig), {"k": "turn"})
	rig.step()
	rig.run(4.1)
	assert_eq(TankAux.of(rig.state).evade.size(), 0)


func test_the_autopilot_turns_3_s_after_the_end() -> void:
	var rig := _rig(1)
	_enter_roam(rig)
	rig.state.roam.map_m = rig.state.roam_map.hi_m - 5.0
	rig.run_until(func() -> bool: return rig.state.roam.at_end != 0, 20.0)
	assert_eq(rig.state.roam.at_end, 1)
	var peer := _driver_peer(rig)
	var asked := 0.0
	for i in 200:
		var auto := TankAutopilot.intents(rig.state, peer)
		var has_turn := false
		for n: Variant in auto:
			if str((n as Dictionary).get("k", "")) == TankIds.INTENT_TURN:
				has_turn = true
		if has_turn:
			asked = rig.state.roam.end_s
			for n2: Variant in auto:
				rig.send(peer, n2)
			break
		rig.step()
	assert_between(asked, 3.0, 3.6, "asked 3 s after reaching the end")
	var ev := rig.step()
	var turns := rig.of_type(TankEvents.TURN, ev)
	assert_eq(turns.size(), 1)
	assert_eq(int(turns[0]["s"]), -1, "the Autopilot's turn")
	rig.run(9.0)
	assert_eq(rig.state.hull.dir, TankIds.DIR_LEFT)
	assert_eq(rig.state.roam.at_end, 0)


func test_the_crew_turns_on_its_own_12_s_after_the_end_when_the_driver_does_not() -> void:
	var rig := _rig(3)
	_enter_roam(rig)
	rig.state.roam.map_m = rig.state.roam_map.hi_m
	rig.run_until(func() -> bool: return rig.state.roam.end_s >= 11.9, 20.0)
	assert_eq(rig.state.roam.turn_s, 0.0, "no turn before 12 s at the end")
	var turns := 0
	for i in 10:
		turns += _count(rig.step(), TankEvents.TURN)
	assert_eq(turns, 1, "the forced turn")
	assert_gt(rig.state.roam.turn_s, 0.0, "turning")
	rig.run(9.0)
	assert_eq(rig.state.hull.dir, TankIds.DIR_LEFT)


func test_nobody_but_the_driver_gets_the_autopilot_turn() -> void:
	var rig := _rig(3)
	_enter_roam(rig)
	rig.state.roam.map_m = rig.state.roam_map.hi_m
	rig.run(5.0)
	for e: String in [TankIds.ENGINE_DYNAMO, TankIds.ENGINE_STEAM]:
		for n: Variant in TankAutopilot.intents(rig.state, rig.peer_of(e)):
			assert_ne(str((n as Dictionary).get("k", "")), TankIds.INTENT_TURN, e)


# --- Patrols and strongpoints --------------------------------------------------------------------


## Plays the roam phase `seconds` with the gun silent, clearing the field whenever 4 or more stand
## on it (the crew's kills, without points); returns the spawn times (WORK seconds).
func _patrol_times(rig: TankRulesRig, seconds: float) -> Array[float]:
	var out: Array[float] = []
	var last := rig.state.roam.patrols
	for i in roundi(seconds / Wl.SIM_DT):
		rig.step()
		var n := TankRoam.alive(rig.state, TankAux.of(rig.state))
		assert_lte(n, 6, "at most 6 alive")
		if n >= 4:
			rig.state.enemies.clear()
		var heavies := 0
		for e in rig.state.enemies:
			if e.code == TankIds.enemy_code(TankIds.ENEMY_HEAVY):
				heavies += 1
		assert_lte(heavies, 1, "one heavy at a time")
		if heavies > 0:
			assert_gte(rig.state.roam.work_s, 600.0, "no heavy before 10 min of WORK time")
		if rig.state.roam.patrols != last:
			last = rig.state.roam.patrols
			out.append(rig.state.roam.work_s)
	return out


func test_patrols_come_every_50_to_110_s_of_work_time_capped_at_6() -> void:
	var rig := _rig(3, "roam_60", 3)
	_enter_roam(rig)
	rig.no_fire = true
	rig.no_bow = true
	# The tank stands in mid road, so no strongpoint or road end comes into it.
	rig.p_eff[_driver_peer(rig)] = 0.0
	rig.hull().hp_max = 1.0e7
	rig.hull().hp = 1.0e7
	var times := _patrol_times(rig, 1500.0)
	assert_gt(times.size(), 8, "patrols keep coming")
	assert_between(times[0], 50.0, 110.0 + 0.1, "the first one")
	var retried := 0
	for i in range(1, times.size()):
		var gap := times[i] - times[i - 1]
		if gap < 49.9:
			retried += 1
		assert_lte(gap, 110.0 + 0.1, "at most 110 s apart")
	assert_eq(retried, 0, "never sooner than 50 s")


func test_patrols_always_come_ahead_far_in_the_far_panel_and_near_from_the_bushes() -> void:
	var far := 0
	var near := 0
	for s in range(1, 9):
		var rig := _rig(3, "roam_30", s)
		_enter_roam(rig)
		rig.no_fire = true
		rig.no_bow = true
		rig.hull().hp_max = 1.0e7
		rig.hull().hp = 1.0e7
		var seen := {}
		for i in roundi(700.0 / Wl.SIM_DT):
			rig.step()
			for e in rig.state.enemies:
				assert_eq(e.side, 1, "nothing behind")
				if seen.has(e.id):
					continue
				seen[e.id] = true
				if e.is_near():
					near += 1
					assert_gt(TankEnemies.distance(rig.state, e), 0.0, "ahead of the front")
					assert_eq(e.range_m, 0.0)
				else:
					far += 1
					assert_between(e.range_m, 700.0, TankConst.FAR_SPAWN_M, "in the far panel")
	assert_gt(far, 10, "far patrols")
	assert_gt(near, 2, "near threats from the bushes")


func test_with_too_little_road_ahead_a_patrol_waits() -> void:
	var rig := _rig(3)
	_enter_roam(rig)
	rig.no_fire = true
	rig.no_bow = true
	rig.state.roam.map_m = rig.state.roam_map.hi_m - 100.0
	rig.state.roam.patrol_s = 0.04
	rig.step()
	assert_eq(rig.state.enemies.size(), 0, "no road ahead: none")
	assert_eq(rig.state.roam.patrols, 0)
	assert_almost_eq(rig.state.roam.patrol_s, 10.0, 0.01, "valley.json patrols.retry_s")


func test_patrol_counts_scale_with_difficulty() -> void:
	var c := TankFixtures.content("roam_30")
	assert_eq(c.crew_count(4, TankIds.TANK_LANDSHIP, 4, 1.3), 5, "Hard")
	assert_eq(c.crew_count(4, TankIds.TANK_LANDSHIP, 4, 0.85), 3, "Easy")


func test_no_heavy_patrol_before_10_min_and_the_weights_hold() -> void:
	var rig := _rig(3)
	_enter_roam(rig)
	var counts := {}
	for i in 4000:
		var k := TankRoam.roll_kind(rig.state)
		counts[str(k["id"])] = int(counts.get(str(k["id"]), 0)) + 1
	assert_false(counts.has("heavy"), "no heavy before 600 s of WORK time")
	rig.state.roam.work_s = 700.0
	counts = {}
	for i in 8000:
		var k2 := TankRoam.roll_kind(rig.state)
		counts[str(k2["id"])] = int(counts.get(str(k2["id"]), 0)) + 1
	assert_between(counts["lights"] / 8000.0, 0.32, 0.40, "lights 45 of 125")
	assert_between(counts["medium"] / 8000.0, 0.20, 0.28, "medium 30 of 125")
	assert_between(counts["destroyer"] / 8000.0, 0.09, 0.15, "destroyer 15 of 125")
	assert_between(counts["heavy"] / 8000.0, 0.05, 0.11, "heavy 10 of 125")
	assert_between(counts["ambush"] / 8000.0, 0.16, 0.24, "ambush 25 of 125")
	rig.spawn(TankIds.ENEMY_HEAVY, 1, 200.0)
	for i in 500:
		assert_ne(str(TankRoam.roll_kind(rig.state)["id"]), "heavy", "one heavy at a time")


func test_a_strongpoint_halts_the_tank_and_returns_10_min_after_it_falls() -> void:
	var rig := _rig(3)
	_enter_roam(rig)
	rig.no_fire = true
	rig.no_bow = true
	rig.hull().hp_max = 1.0e7
	rig.hull().hp = 1.0e7
	rig.state.roam.patrol_s = 1.0e9
	var spot := rig.state.roam_map.strongpoints[0]
	rig.state.roam.map_m = spot - 560.0
	rig.step()
	assert_eq(rig.state.roam.strong_id[0], 0, "past spawn_m ahead: not yet")
	rig.run_until(func() -> bool: return rig.state.roam.engaging, 60.0)
	assert_true(rig.state.roam.engaging, "the tank engages")
	assert_between(spot - rig.state.roam.map_m, 480.0, 500.0, "spawn_m ahead of it")
	var id := rig.state.roam.strong_id[0]
	var e := rig.state.enemy(id)
	assert_not_null(e, "the strongpoint stands on the field")
	assert_eq(e.code, TankIds.enemy_code(TankIds.ENEMY_HEAVY), "a holding force of one heavy")
	assert_false(e.gun_line)
	assert_between(e.range_m, 1300.0, 2300.0, "in the far panel")
	rig.run(5.0)
	assert_eq(rig.state.hull.speed_mps, 0.0, "holds while it stands")
	var before := rig.state.roam.points
	TankShells.kill_enemy(rig.state, TankAux.of(rig.state), e, TankEvents.BY_SHELL, 0, rig.events)
	TankRoam.post(rig.state, TankAux.of(rig.state), [TankEvents.kill(id, e.code, 0, 0)])
	assert_eq(rig.state.roam.points - before, 60, "a heavy's points")
	assert_true(rig.state.roam.strong_down(0))
	rig.run(5.0)
	assert_false(rig.state.roam.engaging)
	assert_gt(rig.state.hull.speed_mps, 0.0, "drives on")
	rig.state.roam.map_m = spot - 120.0
	rig.state.hull.dir = TankIds.DIR_RIGHT
	rig.run(10.0)
	assert_eq(rig.state.roam.strong_id[0], 0, "down: not back yet")
	rig.state.roam.strong_back_s[0] = 0.05
	rig.state.roam.map_m = spot - 40.0
	rig.run(2.0)
	assert_ne(rig.state.roam.strong_id[0], 0, "back after its 10 min")


func test_a_strongpoint_behind_the_tank_never_spawns() -> void:
	var rig := _rig(3)
	_enter_roam(rig)
	rig.no_fire = true
	rig.no_bow = true
	rig.state.roam.patrol_s = 1.0e9
	var spot := rig.state.roam_map.strongpoints[0]
	rig.state.roam.map_m = spot + 5.0
	rig.run(3.0)
	assert_eq(rig.state.roam.strong_id[0], 0, "just passed: behind")
	assert_eq(rig.state.enemies.size(), 0)


func test_no_strongpoint_after_time_up() -> void:
	var rig := _rig(3, "roam_10")
	_enter_roam(rig, 301.0)
	rig.state.roam.patrol_s = 1.0e9
	assert_true(rig.state.roam.time_up)
	rig.state.roam.map_m = rig.state.roam_map.strongpoints[0] - 100.0
	rig.run(1.0)
	assert_eq(rig.state.roam.strong_id[0], 0)


func test_a_heavy_in_range_halts_the_tank() -> void:
	var rig := _rig(3)
	_enter_roam(rig, 700.0)
	rig.no_fire = true
	rig.no_bow = true
	rig.state.roam.patrol_s = 1.0e9
	var heavy := rig.spawn(TankIds.ENEMY_HEAVY, 1, 150.0)
	rig.run(1.0)
	assert_true(rig.state.roam.engaging)
	assert_eq(rig.state.hull.speed_mps, 0.0)
	rig.state.enemies.erase(heavy)
	rig.run(3.0)
	assert_false(rig.state.roam.engaging)
	assert_gt(rig.state.hull.speed_mps, 0.0)
	var far_off := rig.far(TankIds.ENEMY_HEAVY, 2100.0)
	rig.run(1.0)
	assert_false(rig.state.roam.engaging, "past engage_heavy_m it rolls on")
	far_off.hold_m = 1900.0
	far_off.range_m = 1900.0
	rig.run(1.0)
	assert_true(rig.state.roam.engaging)


# --- Time up -------------------------------------------------------------------------------------


func test_time_up_at_min_s_stops_patrols_and_ends_the_phase_with_no_fight() -> void:
	var rig := _rig(3, "roam_10")
	_enter_roam(rig, 290.0)
	rig.state.roam.patrol_s = 1.0e9
	rig.state.enemies.clear()
	rig.run(9.0)
	assert_false(rig.state.roam.time_up)
	var ev := rig.run(2.0)
	assert_eq(_count(ev, TankEvents.TIME_UP), 1)
	assert_true(rig.state.roam.time_up)
	assert_true(rig.state.seg.objective_done, "no fight: the phase ends")
	rig.state.roam.patrol_s = 0.0
	rig.run(5.0)
	assert_eq(rig.state.roam.patrols, 0, "no patrol after time up")


func test_a_fight_runs_into_overtime_but_never_past_max_s() -> void:
	var rig := _rig(3, "roam_10")
	_enter_roam(rig, 295.0)
	rig.no_fire = true
	rig.no_bow = true
	rig.hull().hp_max = 1.0e7
	rig.hull().hp = 1.0e7
	rig.state.roam.patrol_s = 1.0e9
	rig.spawn(TankIds.ENEMY_MEDIUM, 1, 200.0)
	rig.run(10.0)
	assert_true(rig.state.roam.time_up)
	assert_true(rig.state.roam.overtime, "a fight in progress: overtime")
	assert_false(rig.state.seg.objective_done)
	rig.run(280.0)
	assert_false(rig.state.seg.objective_done)
	rig.run(15.0)
	assert_true(rig.state.seg.objective_done, "cut 1 s before max_s")
	assert_false(rig.state.roam.overtime)


func test_a_fight_is_a_far_enemy_in_fight_m_not_retiring_or_a_near_threat() -> void:
	var rig := _rig(3)
	_enter_roam(rig, 10.0)
	var aux := TankAux.of(rig.state)
	rig.state.enemies.clear()
	assert_false(TankRoam.fighting(rig.state, aux))
	var e := rig.far(TankIds.ENEMY_MEDIUM, 1500.0)
	assert_true(TankRoam.fighting(rig.state, aux))
	e.range_m = 2300.0
	assert_false(TankRoam.fighting(rig.state, aux), "beyond fight_m")
	e.range_m = 1500.0
	aux.enemy_leaving[e.id] = true
	assert_false(TankRoam.fighting(rig.state, aux), "retiring")
	rig.state.enemies.clear()
	var n := rig.near(TankIds.ENEMY_TANKETTE)
	assert_true(TankRoam.fighting(rig.state, aux))
	aux.enemy_leaving[n.id] = true
	assert_false(TankRoam.fighting(rig.state, aux), "fleeing")


func test_a_whole_roam_plays_to_the_cool_down_and_finishes_time_up() -> void:
	var rig := _rig(3, "roam_10")
	rig.enter(0)
	rig.play(2.0, 1400.0)
	assert_true(rig.in_cooldown())
	assert_eq(rig.state.outcome, TankIds.OUTCOME_TIME_UP)
	assert_eq(rig.of_type(TankEvents.TIME_UP).size(), 1)
	assert_lte(float(rig.seg_len[1]), 600.0, "the overtime bound")
	assert_ne(str(rig.ended_by[1]), Wl.ENDED_MAX_S, "ended by the director, not max_s")


# --- Points --------------------------------------------------------------------------------------


func test_points_per_kill_evade_breakdown_and_kilometre() -> void:
	var rig := _rig(3)
	_enter_roam(rig, 10.0)
	var r := rig.state.roam
	var aux := TankAux.of(rig.state)
	var cases := {
		TankIds.ENEMY_LIGHT: 10,
		TankIds.ENEMY_MEDIUM: 25,
		TankIds.ENEMY_DESTROYER: 30,
		TankIds.ENEMY_HEAVY: 60,
		TankIds.ENEMY_RECON: 8,
		TankIds.ENEMY_TANKETTE: 6,
	}
	for type: String in cases:
		var before := r.points
		TankRoam.post(rig.state, aux, [TankEvents.kill(999, TankIds.enemy_code(type), 0, 0)])
		assert_eq(r.points - before, int(cases[type]), type)
	var b2 := r.points
	TankRoam.post(rig.state, aux, [TankEvents.kill(998, 1, TankEvents.BY_BARRAGE, -1)])
	assert_eq(r.points, b2, "no points without crew fire")
	TankRoam.post(rig.state, aux, [TankEvents.evade(5, 3, true, 0)])
	assert_eq(r.points - b2, 5, "an evaded shot")
	TankRoam.post(rig.state, aux, [TankEvents.evade(5, 3, false)])
	assert_eq(r.points - b2, 5, "a shot not evaded scores nothing")
	TankRoam.post(rig.state, aux, [TankEvents.breakdown()])
	assert_eq(r.points - b2, -35, "a breakdown")
	TankRoam.post(rig.state, aux, [TankEvents.tank_lost(1, TankIds.SEG_ROAM, 1)])
	assert_eq(r.points - b2, -75, "a lost tank costs the same")
	var b3 := r.points
	r.work_m = 2999.0
	TankRoam.post(rig.state, aux, [])
	assert_eq(r.points - b3, 4, "two full kilometres")
	r.work_m = 3000.5
	TankRoam.post(rig.state, aux, [])
	assert_eq(r.points - b3, 6, "the third")


## The cut-offs are valley.json's: the brief's S 9, A 7, B 5, C 3 x 2.5 (P5 tuning, the README).
func test_the_grade_is_points_per_work_minute() -> void:
	var c := TankFixtures.content("roam_30")
	assert_eq(TankRoam.grade_of(c, 22.5), "S")
	assert_eq(TankRoam.grade_of(c, 22.49), "A")
	assert_eq(TankRoam.grade_of(c, 17.5), "A")
	assert_eq(TankRoam.grade_of(c, 12.5), "B")
	assert_eq(TankRoam.grade_of(c, 7.5), "C")
	assert_eq(TankRoam.grade_of(c, 7.49), "D")
	assert_eq(TankRoam.grade_of(c, 0.0), "D")
	var g: Dictionary = c.valley()["grades"]
	for k: String in ["S", "A", "B", "C"]:
		var brief := {"S": 9.0, "A": 7.0, "B": 5.0, "C": 3.0}
		assert_almost_eq(float(g[k]) / float(brief[k]), 2.5, 1e-6, "the brief's ratios kept: " + k)
	var rig := _rig(3)
	rig.state.roam.points = 150
	rig.state.roam.work_s = 1500.0
	assert_almost_eq(TankRoam.points_per_min(rig.state), 6.0, 1e-6)
	rig.state.roam.work_s = 0.0
	assert_eq(TankRoam.points_per_min(rig.state), 0.0)


func test_roam_rules_are_deterministic() -> void:
	var a := _rig(4, "roam_20", 5)
	var b := _rig(4, "roam_20", 5)
	a.enter(1, 0.0)
	b.enter(1, 0.0)
	a.run(400.0)
	b.run(400.0)
	assert_eq(a.state.roam.to_dict(), b.state.roam.to_dict())
	assert_eq(a.events.size(), b.events.size())
	assert_eq(JSON.stringify(a.events), JSON.stringify(b.events))
