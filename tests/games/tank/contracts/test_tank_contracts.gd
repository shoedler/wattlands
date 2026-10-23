extends GutTest
## The G0 contracts: content schemas, the snapshot layout and budget, records, intents and their
## ownership and rate limit, events, the steam tolerance and the input digest. Lead-owned.


func _files(mission: String = "ashfall_road") -> Dictionary:
	return TankContent.read_files(mission)


## JSON text as it reads back from a file (every number a float).
func _canon(v: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v)))


func _state(crew: int) -> TankState:
	return TankFixtures.state(crew)


func _gun_line(crew: int) -> TankState:
	return TankFixtures.gun_line(crew)


func _boss(crew: int) -> TankState:
	return TankFixtures.boss(crew)


func test_every_content_file_validates() -> void:
	for m: String in ["ashfall_road", "drill"]:
		var c := TankContent.from_dicts(_files(m), m)
		assert_eq(c.errors, [] as Array[String], m)
		assert_true(c.ok())


func test_the_schemas_name_what_is_wrong() -> void:
	var f := _files()
	f["tanks"]["tanks"].erase("citadel")
	f["stations"]["plans"]["dynamo"]["advance"]["range_pct"] = [55, 110]
	f["enemies"]["types"]["light"]["gun"]["hit"] = 1.5
	f["mission"]["segments"][1].erase("max_s")
	f["cosmetics"]["unlocks"][0]["rule"] = "never"
	var c := TankContent.from_dicts(f, "ashfall_road")
	var all := "\n".join(c.errors)
	for needle: String in [
		"tanks: missing citadel",
		"plans.dynamo.advance: every ERG value",
		"types.light gun.hit",
		"segments[1]: open-ended",
		"soot.rule"
	]:
		assert_string_contains(all, needle)


func test_ashfall_road_follows_the_segment_table() -> void:
	var c := TankContent.from_dicts(_files(), "ashfall_road")
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
	var nominal := 0.0
	var worst := 0.0
	for s: Dictionary in c.segments():
		nominal += float(s["duration_s"])
		worst += float(s.get("max_s", s["duration_s"]))
	assert_eq(nominal + 180.0, 1800.0, "30 min nominal with the cool-down")
	assert_eq(worst + 180.0, 2460.0, "41 min at most")


func test_fixture_snapshots_match_the_encoder_and_the_schema() -> void:
	for crew in [1, 2, 3]:
		var snap := TankSnapshot.encode(TankFixtures.state(crew))
		assert_eq(TankSnapshotSchema.check(snap), "", "crew %d" % crew)
		assert_eq(_canon(snap), JSON.stringify(TankFixtures.snapshot(crew)), "snapshot_%d" % crew)
	for f: Callable in [_gun_line, _boss]:
		for crew in [1, 3]:
			assert_eq(TankSnapshotSchema.check(TankSnapshot.encode(f.call(crew))), "")


func test_a_snapshot_at_the_caps_fits_4_kb() -> void:
	var snap := TankSnapshot.encode(TankFixtures.cap())
	assert_eq((snap["e"] as Array).size(), TankConst.MAX_ENEMIES)
	assert_eq((snap["s"] as Array).size(), TankConst.MAX_SHELLS)
	assert_eq(TankSnapshotSchema.check(snap), "")
	assert_lte(TankSnapshotSchema.byte_size(snap), TankConst.SNAPSHOT_MAX_BYTES)


func test_the_schema_catches_a_bad_row() -> void:
	var snap := TankSnapshot.encode(TankFixtures.state(2))
	(snap["e"] as Array).append([1, 2, 3])
	assert_string_contains(TankSnapshotSchema.check(snap), "e: a row needs")


func test_frames_json_matches_the_builder() -> void:
	var json: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(TankFixtures.FRAMES_PATH)
	)
	for crew in [1, 2, 3]:
		assert_eq(JSON.stringify(json[str(crew)]), _canon(TankFixtures.frame_dict(crew)))
		var f := TankFixtures.frame_from_json(crew)
		assert_eq(f.players.size(), crew)


func test_state_records_round_trip() -> void:
	for f: Callable in [_state, _gun_line, _boss]:
		var s: TankState = f.call(3)
		var copy := TankState.new()
		copy.load_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
		assert_eq(JSON.stringify(copy.to_dict()), JSON.stringify(s.to_dict()))
		assert_is(copy.station(TankIds.ENGINE_STEAM), TankSteamState)


func test_intents_normalize_and_reject_junk() -> void:
	assert_eq(
		TankIntents.normalize({"k": "lever", "to": "hoist"}),
		{"k": "lever", "to": 2, "d": 0, "auto": false, "via": "action"}
	)
	assert_eq(TankIntents.normalize({"k": "lever", "to": "left", "via": "button"})["d"], -1)
	assert_eq(TankIntents.normalize({"k": "aim", "d": -1.0})["d"], -1)
	assert_true(TankIntents.normalize({"k": "fire", "auto": 1})["auto"])
	assert_eq(TankIntents.normalize({"k": "ram", "via": "surge"})["via"], "surge")
	for junk: Variant in [
		null,
		[],
		{"k": "boost"},
		{"k": "aim", "d": 2},
		{"k": "lever", "to": 1},
		{"k": "fire", "via": "x"}
	]:
		assert_eq(TankIntents.normalize(junk), {}, str(junk))


func test_intents_belong_to_their_engine() -> void:
	var expect := {
		"diesel": ["ram"],
		"dynamo": ["aim", "target", "traverse", "fire"],
		"steam": ["latch", "over"],
		"bulwark": ["lever", "aim", "target", "traverse", "fire", "latch", "ram"],
	}
	for engine: String in expect:
		for k: String in TankIds.INTENT_KINDS:
			assert_eq(
				TankIntents.owned(k, engine),
				(expect[engine] as Array).has(k),
				"%s %s" % [engine, k]
			)
	assert_false(
		TankIntents.is_deliberate(TankIntents.normalize({"k": "ram"})), "ram never ends Autopilot"
	)
	assert_false(TankIntents.is_deliberate(TankIntents.normalize({"k": "over"})))
	assert_false(TankIntents.is_deliberate(TankIntents.normalize({"k": "fire", "auto": 1})))
	assert_true(TankIntents.is_deliberate(TankIntents.normalize({"k": "fire"})))


func test_the_limiter_allows_5_a_second_per_peer() -> void:
	var lim := TankIntentLimiter.new()
	var raw: Array = []
	for i in 7:
		raw.append({"k": "fire"})
	assert_eq(lim.filter(1, 0, raw, "dynamo").size(), 5)
	assert_eq(lim.filter(1, 19, raw, "dynamo").size(), 0, "still inside the second")
	assert_eq(lim.filter(1, 20, raw, "dynamo").size(), 5, "a new second")
	assert_eq(lim.filter(2, 0, raw, "diesel").size(), 0, "the diesel doesn't own fire")


func test_every_event_declares_its_int_fields() -> void:
	var samples: Array[Dictionary] = [
		TankEvents.segment(1, "advance", 1),
		TankEvents.rotation([[0, "dynamo"], [1, "diesel"]]),
		TankEvents.shot(0, TankIds.SHELL_HEAVY, 5, 0, 0),
		TankEvents.hit(TankEvents.ON_TANK, 0, 12.4, TankIds.SHELL_ENEMY, 4.0, 300.0),
		TankEvents.kill(7, 1, TankEvents.BY_RAM, 0),
		TankEvents.ram(0, true, 7),
		TankEvents.dodge(0),
		TankEvents.breakdown(),
		TankEvents.repaired(40.0),
		TankEvents.overrun("gun_line", 2),
		TankEvents.boss_phase(TankIds.BOSS_PHASE_2),
		TankEvents.latch(2, TankIds.SHELL_LIGHT),
		TankEvents.lever(0, TankIds.LEVER_HOIST),
	]
	assert_eq(samples.size(), TankEvents.TYPES.size())
	for e in samples:
		var t := str(e["type"])
		assert_has(TankEvents.TYPES, t)
		for k: String in e:
			if k != "type":
				var declared: Array = TankEvents.INT_FIELDS[t]
				assert_true(declared.has(k) or declared.has(k + "[][]"), "%s.%s declared" % [t, k])
	assert_true(TankEvents.is_tank_hit(samples[3], 8.0))
	var boss_hit := TankEvents.hit(TankEvents.ON_TANK, 0, 20.0, TankIds.SHELL_BOSS_MAIN, 0.0, 0.0)
	assert_true(TankEvents.is_boss_main_hit(boss_hit))


func test_steam_building_keeps_a_small_tolerance_at_90_percent() -> void:
	assert_true(TankConst.steam_building(180.0, 200.0), "exactly 90%")
	assert_true(TankConst.steam_building(179.0, 200.0), "one whole watt under (rounding)")
	assert_false(TankConst.steam_building(178.0, 200.0))
	assert_true(TankConst.steam_building(358.0, 400.0), "0.5% of FTP at 400 W")
	assert_false(TankConst.steam_building(0.85 * 180.0, 200.0), "compliance 0.85 never builds")


func test_the_input_digest_reads_the_group_phase_and_each_engine() -> void:
	var c := TankFixtures.content()
	var players := TankFixtures.slots(3)
	var plans := TankPlanBuilder.build_all(c, players, true)
	var f := TankFixtures.frame(3)
	f.players[2].intents = [{"k": "fire"}]
	var inp := TankInputs.from_frame(
		f, players, plans, {2: TankIntents.filter_owned([{"k": "fire"}], "steam")}, {3: true}, {}
	)
	assert_eq(inp.phase.index, 4)
	assert_eq(inp.phase.seg, TankIds.SEG_ADVANCE)
	assert_eq(inp.phase.stage, 2)
	var engines: Array = inp.riders.map(func(r: TankRiderInput) -> String: return r.engine)
	assert_eq(engines, ["dynamo", "steam", "diesel"], "stage 2 with rotation")
	assert_true(inp.rider(3).rescue)
	assert_eq(inp.rider(2).intents.size(), 0, "already ownership-filtered")
