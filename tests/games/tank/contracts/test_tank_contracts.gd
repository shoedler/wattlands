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
	f["tanks"]["tanks"].erase("landship")
	f["stations"]["plans"]["dynamo"]["advance"]["range_pct"] = [55, 110]
	f["enemies"]["types"]["light"]["gun"]["hit"] = 1.5
	f["mission"]["segments"][1].erase("max_s")
	f["cosmetics"]["unlocks"][0]["rule"] = "never"
	var c := TankContent.from_dicts(f, "ashfall_road")
	var all := "\n".join(c.errors)
	for needle: String in [
		"tanks: missing landship",
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
	for crew in [1, 2, 3, 4]:
		var snap := TankSnapshot.encode(TankFixtures.state(crew))
		assert_eq(TankSnapshotSchema.check(snap), "", "crew %d" % crew)
		assert_eq(_canon(snap), JSON.stringify(TankFixtures.snapshot(crew)), "snapshot_%d" % crew)
	for f: Callable in [_gun_line, _boss]:
		for crew in [1, 3, 4]:
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
		TankIntents.normalize({"k": "seat", "to": "steam"}),
		{"k": "seat", "to": 3, "d": 0, "auto": false, "via": "action"}
	)
	assert_eq(TankIntents.normalize({"k": "seat", "to": "prev", "via": "button"})["d"], -1)
	assert_eq(TankIntents.normalize({"k": "aim", "d": -1.0})["d"], -1)
	assert_true(TankIntents.normalize({"k": "fire", "auto": 1})["auto"])
	assert_eq(TankIntents.normalize({"k": "over", "via": "surge"})["via"], "surge")
	for junk: Variant in [
		null,
		[],
		{"k": "boost"},
		{"k": "ram", "via": "surge"},
		{"k": "aim", "d": 2},
		{"k": "lever", "to": "hoist"},
		{"k": "seat", "to": 1},
		{"k": "seat", "to": "bulwark"},
		{"k": "fire", "via": "x"}
	]:
		assert_eq(TankIntents.normalize(junk), {}, str(junk))


func test_intents_belong_to_their_engine() -> void:
	var expect := {
		"diesel": ["turn", "seat"],
		"dynamo": ["aim", "target", "traverse", "fire", "seat"],
		"steam": ["latch", "over", "seat"],
		"arc": ["seat"],
		"feed": ["seat"],
		"bulwark": [],
	}
	for engine: String in expect:
		for k: String in TankIds.INTENT_KINDS:
			assert_eq(
				TankIntents.owned(k, engine),
				(expect[engine] as Array).has(k),
				"%s %s" % [engine, k]
			)
	assert_false(TankIds.INTENT_KINDS.has("ram"), "v2: no Ram intent")
	assert_false(TankIds.INTENT_KINDS.has("lever"), "v3: no gearbox lever")
	assert_true(TankIntents.is_deliberate(TankIntents.normalize({"k": "seat", "to": "next"})))
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
		# Reserved (v3 retired rotation).
		{"type": TankEvents.ROTATION, "r": [[0, 2], [1, 1]]},
		TankEvents.shot(0, TankIds.SHELL_HEAVY, 5, 0, 0),
		TankEvents.hit(TankEvents.ON_TANK, 0, 12.4, TankIds.SHELL_ENEMY, 4.0, 300.0),
		TankEvents.kill(7, 1, TankEvents.BY_BOW, 0),
		# Reserved v1 types (never emitted in v2): their wire form stays declared.
		{"type": TankEvents.RAM, "s": 0, "ok": 1, "id": 7},
		{"type": TankEvents.DODGE, "s": 0},
		TankEvents.breakdown(),
		TankEvents.repaired(40.0),
		TankEvents.overrun("gun_line", 2),
		TankEvents.boss_phase(TankIds.BOSS_PHASE_2),
		TankEvents.latch(2, TankIds.SHELL_LIGHT),
		# Reserved (v3 retired the Bulwark's gearbox lever).
		{"type": TankEvents.LEVER, "s": 0, "lv": 2},
		TankEvents.evade(13, TankIds.enemy_code(TankIds.ENEMY_DESTROYER), true, 2),
		TankEvents.turn(0, TankIds.DIR_LEFT),
		TankEvents.time_up(),
		TankEvents.seat(1, TankIds.ENGINE_ARC, TankIds.ENGINE_FEED),
		TankEvents.tank_lost(1, TankIds.SEG_ADVANCE, 1),
		TankEvents.stage_restart(TankIds.SEG_ADVANCE, 1, 84.0),
		TankEvents.ambush(7, TankIds.enemy_code(TankIds.ENEMY_RECON)),
		TankEvents.escaped(7, TankIds.enemy_code(TankIds.ENEMY_RECON)),
		TankEvents.splash(1500.0, TankIds.SHELL_HEAVY, true),
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
	var plans := TankPlanBuilder.build_all(c, players)
	var f := TankFixtures.frame(3)
	f.players[2].intents = [{"k": "fire"}]
	var inp := TankInputs.from_frame(
		f, players, plans, {2: TankIntents.filter_owned([{"k": "fire"}], "steam")}, {3: true}, {}
	)
	assert_eq(inp.phase.index, 4)
	assert_eq(inp.phase.seg, TankIds.SEG_ADVANCE)
	assert_eq(inp.phase.stage, 2)
	var engines: Array = inp.riders.map(func(r: TankRiderInput) -> String: return r.engine)
	assert_eq(engines, ["diesel", "dynamo", "steam"], "v3: the start seats (no rotation)")
	assert_true(inp.rider(3).rescue)
	assert_eq(inp.rider(2).intents.size(), 0, "already ownership-filtered")
	for ri in inp.riders:
		var ph := (plans[ri.peer] as EffortPlan).phase(4)
		assert_eq(ri.phase_kind, Wl.WORK, "each rider's own phase kind")
		assert_eq(ri.phase_mode, ph.mode)
		assert_eq(ri.grade_source, ph.grade_source if ph.mode == Wl.SIM else "")
		assert_eq(ri.plan_elapsed_s, 300.0 + 180.0 + 120.0 + 60.0 + 60.0)
		assert_false(ri.in_first_window())
		assert_false(ri.in_warmup())
	assert_eq(inp.rider(1).grade_source, Wl.GRADE_GAME, "the diesel's terrain")
	players[2].rider_mass_kg = 91.0
	var heavy := TankInputs.from_frame(f, players, plans, {}, {}, {})
	assert_eq(heavy.rider(3).rider_mass_kg, 91.0, "the drive's mass comes from the slot")


func test_boss_part_ids_never_collide_with_entity_ids() -> void:
	var s := TankFixtures.state(3)
	for i in TankBossState.PART_COUNT:
		var id := TankBossState.part_id(i)
		assert_lt(id, 0)
		assert_eq(TankBossState.part_of(id), i)
		assert_true(TankBossState.is_part_id(id))
	for _i in 5000:
		var id := s.take_id()
		assert_gt(id, 0)
		assert_false(TankBossState.is_part_id(id))
	assert_eq(TankBossState.part_of(0), -1, "0 is no target")
	assert_eq(TankBossState.part_of(-5), -1)


func test_the_geometry_contract_holds() -> void:
	var g := TankGeometry.load_default()
	assert_eq(g.validate(), [] as Array[String])
	for t: String in TankIds.TANKS:
		var m0 := g.muzzle(t, 0.0, TankIds.FACE_RIGHT)
		assert_almost_eq(m0, g.trunnion(t) + Vector2(g.barrel_px(t), 0.0), Vector2(0.01, 0.01), t)
		assert_eq(g.bow_muzzles(t).size(), 2, "%s: two bow guns (v2)" % t)
		var up := g.muzzle(t, 30.0, TankIds.FACE_RIGHT)
		assert_lt(up.y, m0.y, "%s: elevation raises the muzzle" % t)
		assert_almost_eq(up.distance_to(g.trunnion(t)), g.barrel_px(t), 0.001)
		var left := g.muzzle(t, 0.0, TankIds.FACE_LEFT)
		assert_almost_eq(left.x, 2.0 * g.ring(t).x - m0.x, 0.001, "%s: mirrored" % t)
	for i in TankBossState.PART_COUNT:
		assert_true(g.boss_part_rect(i).has_area(), "boss part %d" % i)
	assert_true(g.enemy_hitbox("enemy_dugin").has_area(), "the dug-in's turret")
	var broken := TankGeometry.from_dict({"tanks": {}})
	var problems := " | ".join(broken.validate())
	assert_string_contains(problems, "tanks.landship.turret.trunnion: missing")


## Thresholds that live in two files must agree (one meaning, two owners).
func test_shared_thresholds_agree() -> void:
	var c := TankFixtures.content()
	var loader: Array = c.value("stations", "cadence_band.loader", [])
	var band: Array = c.value("stations", "cadence_band.default", [])
	assert_eq(c.num("tanks", "in_band.steam_cycle_cadence_rpm"), float(loader[0]))
	assert_eq(c.num("tanks", "in_band.recovery_cadence_rpm"), float(band[0]))
	assert_eq(c.num("tanks", "in_band.erg_cadence_rpm"), float(band[0]))
	assert_null(c.value("stations", "power_band_pct"), "one source: tanks.json in_band")
	assert_null(c.value("stations", "haptics.none_before_s"), "one source: TankConst.FIRST_S")
	assert_null(c.value("tanks", "evade.no_ability_first_s"), "one source: TankConst.FIRST_S")
	assert_null(c.value("tanks", "ram"), "v2: no Ram block")
	assert_null(c.value("tanks", "in_band.steam_build_tol_pct"), "one source: TankConst")


## The in-band rule follows the rider's own phase kind: WARMUP and RECOVERY kinds (the drill's
## skirmish included) are cadence >= 60 only, never the WORK power rules.
func test_in_band_follows_the_phase_kind() -> void:
	var s := TankFixtures.state(3)
	var steam := s.station(TankIds.ENGINE_STEAM) as TankSteamState
	steam.loaded = false
	steam.cycling = false
	var ri := TankRiderInput.new()
	ri.ftp = 200.0
	ri.mode = Wl.SIM
	ri.power_w = 0.0
	ri.cadence_rpm = 80.0
	ri.phase_kind = Wl.WORK
	assert_false(TankRules.in_band(s, ri, steam), "WORK: steam must build")
	for kind: String in [Wl.WARMUP, Wl.RECOVERY]:
		ri.phase_kind = kind
		assert_true(TankRules.in_band(s, ri, steam), kind)
		ri.cadence_rpm = 55.0
		assert_false(TankRules.in_band(s, ri, steam), "%s below 60 rpm" % kind)
		ri.cadence_rpm = 80.0
