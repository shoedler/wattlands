extends GutTest
## Tank v4's contract commit (SPEC_TANK section 1): ids, the split screen's geometry, the far frame's
## ballistics, the difficulty table, the v5 snapshot, the new events and the additive helpers.

const F := preload("res://tests/games/tank/tank_fakes.gd")


func _files(mission: String = "ashfall_road") -> Dictionary:
	return TankContent.read_files(mission)


func _content_errors(files: Dictionary, mission: String = "ashfall_road") -> Array[String]:
	return TankContent.from_dicts(files, mission).errors


func _has_error(errors: Array[String], needle: String) -> bool:
	for e in errors:
		if e.contains(needle):
			return true
	return false


# --- Ids --------------------------------------------------------------------------------------------


func test_the_repair_seat_has_its_ids() -> void:
	assert_eq(TankIds.ENGINE_REPAIR, "repair")
	assert_eq(TankIds.engine_code(TankIds.ENGINE_REPAIR), 7)
	assert_eq(TankIds.engine_of(7), TankIds.ENGINE_REPAIR)
	assert_eq(TankIds.ENGINE_LABELS[TankIds.ENGINE_REPAIR], "TANK_ENGINE_REPAIR")
	assert_eq(TankIds.SEAT_LABELS[TankIds.ENGINE_REPAIR], "TANK_SEAT_REPAIRS")
	assert_eq(TankIds.SEATS.back(), TankIds.ENGINE_REPAIR, "the sixth card")
	assert_eq(TankIds.SEATS.size(), 6)
	assert_eq(TankIds.ENGINES.size(), 6)
	assert_eq(TankRiderState.ENGINE_INDEX[TankIds.ENGINE_REPAIR], 6)
	assert_eq(TankRiderState.new().engine_s.size(), 7)
	assert_is(TankStationState.make(TankIds.ENGINE_REPAIR), TankRepairState)
	assert_true(TankRig.SEATS.has("repair"))


func test_codes_stay_unique_and_never_take_the_boss_code() -> void:
	var seen := {}
	for k: String in TankIds.ENEMY_CODES:
		var code := int(TankIds.ENEMY_CODES[k])
		assert_false(seen.has(code), "%s reuses %d" % [k, code])
		seen[code] = true
	assert_false(seen.has(TankIds.BOSS_CODE), "6 is the Behemoth's")
	assert_eq(TankIds.enemy_code(TankIds.ENEMY_RECON), 7)
	assert_eq(TankIds.enemy_code(TankIds.ENEMY_TANKETTE), 8)
	var engines := {}
	for k: String in TankIds.ENGINE_CODES:
		assert_false(engines.has(TankIds.ENGINE_CODES[k]), k)
		engines[TankIds.ENGINE_CODES[k]] = true
	assert_ne(TankIds.EM_RETIRE, TankIds.EM_PAUSE)
	assert_gt(TankIds.EM_RETIRE, TankIds.EM_LEAVE, "appended, none reused")


func test_every_kind_is_far_or_near_and_the_score_counts_them() -> void:
	for t: String in TankIds.ENEMY_TYPES:
		var far := TankIds.FAR_KINDS.has(t)
		var near := TankIds.NEAR_KINDS.has(t)
		assert_true(far != near, t)
		assert_eq(TankIds.is_near_code(TankIds.enemy_code(t)), near, t)
	var score := TankScoreState.new()
	assert_eq(score.kills.size(), 9)
	assert_eq([score.losses, score.near_escaped], [0, 0])
	var near_e := TankEnemyState.new()
	near_e.code = TankIds.enemy_code(TankIds.ENEMY_TANKETTE)
	assert_true(near_e.is_near())
	near_e.code = TankIds.enemy_code(TankIds.ENEMY_HEAVY)
	assert_false(near_e.is_near())


func test_a_repairs_rider_can_ask_for_another_seat() -> void:
	var kept := TankIntents.filter_owned(
		[TankIntents.seat(TankIds.ENGINE_DIESEL), TankIntents.make(TankIds.INTENT_FIRE)],
		TankIds.ENGINE_REPAIR
	)
	assert_eq(kept.size(), 1, "the seat intent survives, fire does not")
	assert_eq(str(kept[0]["k"]), TankIds.INTENT_SEAT)
	assert_eq(TankIntents.seat_wanted(kept[0], TankIds.ENGINE_REPAIR), TankIds.ENGINE_DIESEL)
	var to_repair := TankIntents.normalize(TankIntents.seat(TankIds.ENGINE_REPAIR))
	assert_eq(int(to_repair["to"]), 7, "a named move to Repairs")


func test_the_hull_is_out_of_action_in_a_breakdown_or_a_tow() -> void:
	var h := TankHullState.new()
	assert_false(h.out_of_action())
	h.tow_s = 0.05
	assert_true(h.out_of_action())
	h.tow_s = 0.0
	h.breakdown = true
	assert_true(h.out_of_action())


func test_the_repair_duty_is_the_share_of_the_last_10_s() -> void:
	var r := TankRepairState.new()
	assert_eq(r.engine, "")
	for t in TankRepairState.FIRE_RING:
		r.note_work(t, t % 2 == 0)
	assert_almost_eq(r.duty, 0.5, 0.001)
	for t in range(TankRepairState.FIRE_RING, 2 * TankRepairState.FIRE_RING):
		r.note_work(t, true)
	assert_almost_eq(r.duty, 1.0, 0.001, "the old half rolled out of the ring")


# --- The split screen -------------------------------------------------------------------------------


func _rects(canvas: Vector2, mirrored: bool) -> Array:
	var p := TankFarMap.panels(canvas, mirrored)
	return [p["near"], p["seam"], p["far"], p["pip"]]


## SPEC_TANK 4.1's table.
func test_the_panels_match_the_layout_table() -> void:
	assert_eq(
		_rects(Vector2(960, 540), false),
		[
			Rect2(0, 0, 622, 540),
			Rect2(622, 0, 8, 540),
			Rect2(630, 0, 330, 540),
			Rect2(636, 150, 318, 60)
		]
	)
	assert_eq(
		_rects(Vector2(852, 480), false),
		[
			Rect2(0, 0, 558, 480),
			Rect2(558, 0, 8, 480),
			Rect2(566, 0, 286, 480),
			Rect2(572, 150, 274, 60)
		]
	)
	assert_eq(
		_rects(Vector2(1280, 680), false),
		[
			Rect2(0, 0, 852, 680),
			Rect2(852, 0, 8, 680),
			Rect2(860, 0, 420, 680),
			Rect2(866, 150, 408, 60)
		]
	)
	assert_eq(
		_rects(Vector2(960, 540), true),
		[
			Rect2(338, 0, 622, 540),
			Rect2(330, 0, 8, 540),
			Rect2(0, 0, 330, 540),
			Rect2(6, 150, 318, 60)
		]
	)


func test_the_range_mapping() -> void:
	assert_eq(TankFarMap.near_end_x(960.0), 622.0)
	assert_eq(TankFarMap.near_end_x(852.0), 558.0)
	assert_almost_eq(TankFarMap.range_x(700.0, 330.0), 30.0, 0.001)
	assert_almost_eq(TankFarMap.range_x(2600.0, 330.0), 300.0, 0.001)
	assert_almost_eq(TankFarMap.range_x(100.0, 330.0), 30.0, 0.001, "clamped")
	assert_eq(TankFarMap.foot_y(700.0, 0), 392.0)
	assert_eq(TankFarMap.foot_y(2600.0, 3), 392.0 - 36.0 - 18.0)
	assert_eq(TankFarMap.foot_y(700.0, 9), 392.0 - 36.0, "lanes 0..3")


func test_the_near_span_and_the_far_field_constants() -> void:
	assert_eq(TankConst.NEAR_SPAN_PX, 200.0)
	assert_eq(TankConst.FAR_SPAWN_M, TankFarMap.RANGE_FAR_M)


# --- The far frame's ballistics ---------------------------------------------------------------------


## SPEC_TANK section 2's table: v0 560 m/s, g 70 m/s^2.
func test_the_far_numbers() -> void:
	var v0 := 560.0
	var g := 70.0
	for row: Array in [[800.0, 5.1, 1.43], [1500.0, 9.8, 2.72], [2200.0, 14.7, 4.06]]:
		var e := TankBallistics.far_elevation(float(row[0]), v0, g)
		assert_almost_eq(e, float(row[1]), 0.05, "elevation at %s m" % row[0])
		assert_almost_eq(TankBallistics.far_flight(e, v0, g), float(row[2]), 0.01, "flight")
		assert_almost_eq(TankBallistics.far_range(e, v0, g), float(row[0]), 0.01, "round trip")
		var t := TankBallistics.far_flight(e, v0, g)
		assert_almost_eq(TankBallistics.far_height(t, e, v0, g), 0.0, 0.01, "lands at height 0")
	assert_true(is_nan(TankBallistics.far_elevation(0.0, v0, g)), "no range, no elevation")
	assert_true(is_nan(TankBallistics.far_elevation(5000.0, v0, g)), "out of range")


func test_far_lead_lands_where_the_target_will_be() -> void:
	var v0 := 560.0
	var g := 70.0
	var e := TankBallistics.far_lead(1500.0, 20.0, v0, g)
	var t := TankBallistics.far_flight(e, v0, g)
	assert_almost_eq(TankBallistics.far_range(e, v0, g), 1500.0 + 20.0 * t, 0.5)
	assert_gt(e, TankBallistics.far_elevation(1500.0, v0, g), "a retiring target needs more")
	assert_true(is_nan(TankBallistics.far_lead(4400.0, 50.0, v0, g)), "out of range stays NAN")


# --- The far and near targets -----------------------------------------------------------------------


func _targets_state() -> TankState:
	var s := TankFixturesV4.make("far_duel")
	TankFixturesV4._near(s, 41, TankIds.ENEMY_RECON, 60.0, 0)
	return s


func test_targets_read_the_far_frame() -> void:
	var s := _targets_state()
	var aux := TankAux.of(s)
	TankTargets.build(s, aux)
	var far := TankTargets.far_targets(aux)
	assert_eq(far.size(), 3)
	assert_eq(far[0].range_m, 1640.0)
	assert_eq(far[0].hit_half_m, 42.0)
	assert_eq(far[0].rect, Rect2(), "a far target has no box")
	assert_eq(far[0].sort_key(), 1640.0, "not center().x, which is 0")
	var near := TankTargets.near_threats(aux)
	assert_eq(near.size(), 1)
	assert_true(near[0].near)
	assert_false(near[0].far)
	assert_gt(near[0].rect.size.x, 0.0, "a near threat keeps its box")
	assert_almost_eq(near[0].sort_key(), near[0].center().x, 0.001)
	assert_true(aux.enemy_in_range)
	assert_true(aux.any_target)


func test_engageable_and_collidable_for_the_new_frames() -> void:
	var s := _targets_state()
	var aux := TankAux.of(s)
	TankTargets.build(s, aux)
	var cam := s.camera_x()
	var far := TankTargets.far_targets(aux)[0]
	assert_true(TankTargets.engageable(far, cam), "reach is TankAim.in_reach")
	assert_false(TankShells.collidable(far), "near shells fly past far targets")
	var near := TankTargets.near_threats(aux)[0]
	assert_false(TankTargets.engageable(near, cam), "the main gun does not lay on it")
	assert_true(TankShells.collidable(near), "bow rounds and near arcs still hit it")


func test_a_far_kind_at_range_zero_stays_in_the_old_frame() -> void:
	var s := TankFixtures.state(3)
	var aux := TankAux.of(s)
	TankTargets.build(s, aux)
	assert_eq(TankTargets.far_targets(aux).size(), 0, "old rules run untouched")
	assert_eq(TankTargets.near_threats(aux).size(), 0)
	assert_gt(TankTargets.by_id(aux, 11).rect.size.x, 0.0)


func test_a_far_target_past_the_guns_range_does_not_count() -> void:
	var s := TankFixtures._base(TankFixtures.content(), 2, TankFixturesV4.SEG_ADVANCE_2, 10.0)
	TankFixturesV4._far(s, 11, TankIds.ENEMY_MEDIUM, 2590.0, 0)
	var aux := TankAux.of(s)
	TankTargets.build(s, aux)
	assert_eq(TankTargets.far_targets(aux).size(), 1)
	assert_false(aux.enemy_in_range, "past gun.far.max_range_m")
	s.enemies[0].range_m = 2400.0
	TankTargets.build(s, aux)
	assert_true(aux.enemy_in_range)


func test_boss_parts_stand_in_the_far_frame_by_metres() -> void:
	var s := TankFixturesV4.make("boss_far")
	var aux := TankAux.of(s)
	TankTargets.build(s, aux)
	var far := TankTargets.far_targets(aux)
	assert_eq(far.size(), 2, "bogies 0 and 1; bogie 2 broken, the turret waits for phase 2")
	assert_eq(far[0].range_m, 1100.0)
	assert_eq(far[1].range_m, 1122.0)
	assert_eq(far[0].hit_half_m, 16.0)
	assert_eq(far[0].rect, Rect2())
	assert_true(TankTargets.engageable(far[0], s.camera_x()))


# --- Difficulty -------------------------------------------------------------------------------------


func test_resolve_takes_the_mission_default_on_auto() -> void:
	var c := TankContent.from_dicts(_files(), "ashfall_road")
	assert_eq(
		TankDifficulty.resolve(TankIds.DIFF_AUTO, c), TankIds.DIFF_NORMAL, "no default: normal"
	)
	assert_eq(TankDifficulty.resolve("", c), TankIds.DIFF_NORMAL)
	assert_eq(TankDifficulty.resolve(TankIds.DIFF_EASY, c), TankIds.DIFF_EASY)
	assert_eq(TankDifficulty.resolve(TankIds.DIFF_HARD, c), TankIds.DIFF_HARD)
	assert_eq(TankDifficulty.resolve("nightmare", c), TankIds.DIFF_NORMAL, "junk: normal")
	var files := _files()
	(files["mission"] as Dictionary)["difficulty_default"] = TankIds.DIFF_HARD
	var hard := TankContent.from_dicts(files, "ashfall_road")
	assert_eq(hard.errors, [] as Array[String])
	assert_eq(TankDifficulty.resolve(TankIds.DIFF_AUTO, hard), TankIds.DIFF_HARD)
	assert_eq(TankDifficulty.resolve(TankIds.DIFF_EASY, hard), TankIds.DIFF_EASY, "the host's pick")


func test_the_table_and_who_can_lose() -> void:
	var s := TankFixturesV4.make("advance_far")
	assert_eq(s.difficulty, TankIds.DIFF_NORMAL)
	assert_eq(TankDifficulty.mult(s, "hp"), 1.0)
	assert_true(TankDifficulty.tank_loss(s))
	s.difficulty = TankIds.DIFF_HARD
	assert_eq(TankDifficulty.mult(s, "damage"), 1.6)
	assert_eq(TankDifficulty.mult(s, "nothing"), 1.0, "default 1")
	assert_true(TankDifficulty.tank_loss(s))
	s.difficulty = TankIds.DIFF_EASY
	assert_eq(TankDifficulty.mult(s, "repair"), 1.5)
	assert_false(TankDifficulty.tank_loss(s), "Easy breaks down")
	s.difficulty = TankIds.DIFF_HARD
	s.seg.kind = Wl.WARMUP
	assert_false(TankDifficulty.tank_loss(s), "never in a warm-up kind")
	assert_eq(TankDifficulty.mult(null, "hp"), 1.0)


func test_the_module_sets_difficulty_on_every_peer_from_the_option() -> void:
	for role: String in [Wl.SOLO, Wl.HOST, Wl.CLIENT]:
		var ctx := F.make_ctx(2, 0, "ashfall_road", role, 1)
		ctx.options["difficulty"] = TankIds.DIFF_HARD
		var g: TankGame = autofree(F.make_game(ctx))
		assert_eq(g.state.difficulty, TankIds.DIFF_HARD, role)
	var plain: TankGame = autofree(F.make_game(F.make_ctx(1, 0, "drill")))
	assert_eq(plain.state.difficulty, TankIds.DIFF_EASY, "auto: the mission's default")
	var files := TankContent.read_files("drill")
	(files["mission"] as Dictionary).erase("difficulty_default")
	var bare := TankContent.from_dicts(files, "drill")
	assert_eq(TankDifficulty.resolve(TankIds.DIFF_AUTO, bare), TankIds.DIFF_NORMAL, "no default")


func test_the_manifest_offers_the_option() -> void:
	var man := F.manifest()
	var opt: Dictionary = (man["options"] as Array)[0]
	assert_eq(str(opt["id"]), "difficulty")
	assert_eq(str(opt["default"]), TankIds.DIFF_AUTO)
	var values: Array = []
	for c: Dictionary in opt["choices"]:
		values.append(str(c["value"]))
	assert_eq(values, ["auto", "easy", "normal", "hard"])


func test_the_schema_refuses_an_unknown_key_in_a_difficulty_row() -> void:
	var files := _files()
	files["enemies"]["difficulty"]["hard"]["erg_pct"] = 1.1
	assert_true(_has_error(_content_errors(files), "difficulty.hard: unknown key erg_pct"))


func test_the_schema_holds_the_difficulty_table() -> void:
	var cases: Array = [
		[["hard", "damage"], 3.5, "difficulty.hard.damage"],
		[["easy", "hp"], 0.1, "difficulty.easy.hp"],
		[["normal", "tank_loss"], 1, "difficulty.normal.tank_loss"],
	]
	for c: Array in cases:
		var files := _files()
		files["enemies"]["difficulty"][c[0][0]][c[0][1]] = c[1]
		assert_true(_has_error(_content_errors(files), str(c[2])), str(c[2]))
	var gone := _files()
	(gone["enemies"]["difficulty"] as Dictionary).erase("easy")
	assert_true(_has_error(_content_errors(gone), "difficulty.easy: missing"))
	var extra := _files()
	extra["enemies"]["difficulty"]["brutal"] = extra["enemies"]["difficulty"]["hard"]
	assert_true(_has_error(_content_errors(extra), "unknown level brutal"))


func test_the_repair_pattern_sits_inside_the_bank_envelope() -> void:
	var fast := _files()
	fast["stations"]["repair"]["max_step_pts"] = 12
	assert_true(_has_error(_content_errors(fast), "repair.max_step_pts"))
	var wide := _files()
	wide["stations"]["repair"]["span_pct"] = 50
	assert_true(_has_error(_content_errors(wide), "repair: base_pct + span_pct"))
	var low := _files()
	low["stations"]["repair"]["base_pct"] = 45
	assert_true(_has_error(_content_errors(low), "repair.base_pct"))
	var c := TankContent.from_dicts(_files(), "ashfall_road")
	assert_eq(
		c.plan_entry(TankIds.ENGINE_REPAIR, TankIds.SEG_GUN_LINE),
		{"mode": "ERG", "target_pct": 55.0, "range_pct": [55.0, 70.0]}
	)


func test_the_schema_holds_the_mission_extras() -> void:
	var bad_default := _files()
	bad_default["mission"]["difficulty_default"] = "brutal"
	assert_true(_has_error(_content_errors(bad_default), "difficulty_default"))
	var stages := _files()
	stages["mission"]["score_stages"] = 0
	assert_true(_has_error(_content_errors(stages), "score_stages"))
	var near := _files()
	near["mission"]["segments"][5]["near"] = [{"at_s": 10, "enemy": "heavy"}]
	assert_true(_has_error(_content_errors(near), "near:"))
	var ok := _files()
	ok["mission"]["segments"][5]["near"] = [{"at_s": 10, "enemy": "recon", "min_crew": 2}]
	assert_eq(_content_errors(ok), [] as Array[String])
	var close := _files()
	close["mission"]["segments"][5]["enemies"] = [{"enemy": "heavy", "count": 1, "hold_m": [1200]}]
	assert_true(_has_error(_content_errors(close), "below the kind's hold_m[0]"), "the 6 s floor")


func test_every_content_still_loads() -> void:
	var missions: Array[String] = ["ashfall_road", "drill", "roam_10", "roam_30", "roam_60"]
	for m in missions:
		assert_eq(_content_errors(_files(m), m), [] as Array[String], m)


# --- Snapshot v5 ------------------------------------------------------------------------------------


func test_a_crew_4_snapshot_at_the_v4_caps_fits_4_kb() -> void:
	var s := TankFixturesV4.make("cap_v4")
	var snap := TankSnapshot.encode(s)
	assert_eq(int(snap["v"]), 5)
	assert_eq((snap["r"] as Array).size(), 4)
	assert_eq((snap["st"] as Array).size(), 6)
	assert_eq((snap["e"] as Array).size(), TankConst.MAX_ENEMIES)
	assert_eq((snap["s"] as Array).size(), TankConst.MAX_SHELLS)
	assert_eq(TankSnapshotSchema.check(snap), "")
	var size := TankSnapshotSchema.byte_size(snap)
	gut.p("v5 crew-4 snapshot at the v4 caps: %d bytes" % size)
	assert_lte(size, TankConst.SNAPSHOT_MAX_BYTES)
	var old_caps := TankSnapshotSchema.byte_size(TankSnapshot.encode(TankFixtures.cap4()))
	gut.p("v5 crew-4 snapshot at the old caps: %d bytes" % old_caps)
	assert_lte(old_caps, TankConst.SNAPSHOT_MAX_BYTES)


func _client_of(host: TankState) -> TankState:
	var c := TankState.create(
		host.content, TankFixtures.slots(host.riders.size()), host.mission, null
	)
	c.difficulty = host.difficulty
	return c


func test_the_v5_columns_round_trip() -> void:
	var s := TankFixturesV4.make("cap_v4")
	s.hull.tow_s = 3.25
	s.score.losses = 2
	s.boss.phase = TankIds.BOSS_PHASE_1
	s.boss.range_m = 1234.4
	var fs := s.shells[1]
	assert_true(fs.far)
	fs.evadable = true
	var snap: Dictionary = JSON.parse_string(JSON.stringify(TankSnapshot.encode(s)))
	var c := _client_of(s)
	TankSnapshot.apply(c, snap)
	assert_eq(c.hull.tow_s, 3.25)
	assert_true(c.hull.out_of_action())
	assert_eq(c.score.losses, 2)
	assert_eq(c.boss.range_m, 1234.0)
	assert_eq(c.enemies[0].range_m, 2599.0)
	assert_eq(c.enemies[8].range_m, 0.0, "a near kind has no metres")
	assert_true(c.enemies[8].is_near())
	assert_true(c.shells[1].far)
	assert_true(c.shells[1].evadable)
	assert_almost_eq(c.shells[1].left_s, fs.left_s, 0.001)
	assert_false(c.shells[20].far, "the bow rounds stay near")
	var rp := c.station(TankIds.ENGINE_REPAIR) as TankRepairState
	assert_eq(rp.patches, 999)
	assert_almost_eq(rp.press_t, 0.999, 0.001)
	assert_almost_eq(rp.duty, 0.999, 0.001)
	assert_false(rp.working)
	assert_eq(rp.slot, 3, "Repairs is manned")


func test_the_repair_room_flag_round_trips() -> void:
	var s := TankFixturesV4.make("repair")
	var c := _client_of(s)
	TankSnapshot.apply(c, TankSnapshot.encode(s))
	var rp := c.station(TankIds.ENGINE_REPAIR) as TankRepairState
	assert_true(rp.working)
	assert_true(rp.in_band)
	assert_almost_eq(rp.press_t, 0.6, 0.001)
	assert_eq(rp.patches, 7)


func test_a_clients_maxima_follow_the_difficulty() -> void:
	var s := TankFixturesV4.make("advance_far")
	s.difficulty = TankIds.DIFF_HARD
	var c := _client_of(s)
	TankSnapshot.apply(c, TankSnapshot.encode(s))
	assert_eq(c.enemies[0].hp_max, ceilf(70.0 * 1.25), "enemy HP x difficulty")
	var def := s.content.boss_def()
	assert_eq(c.boss.bogie_max, float(def["bogie_hp"]) * 1.25)
	assert_eq(c.boss.turret_max, float(def["turret_hp"]) * 1.25)


# --- Events -----------------------------------------------------------------------------------------


func _v4_events() -> Array[Dictionary]:
	return [
		TankEvents.tank_lost(2, TankIds.SEG_GUN_LINE, 2),
		TankEvents.stage_restart(TankIds.SEG_GUN_LINE, 2, 84.4),
		TankEvents.ambush(41, TankIds.enemy_code(TankIds.ENEMY_RECON)),
		TankEvents.escaped(41, TankIds.enemy_code(TankIds.ENEMY_RECON)),
		TankEvents.splash(1499.6, TankIds.SHELL_HEAVY, true),
	]


func test_every_v4_event_declares_its_fields() -> void:
	var events := _v4_events()
	assert_eq(events.size(), 5)
	for e in events:
		var type := str(e["type"])
		assert_has(TankEvents.TYPES, type)
		var declared: Array = TankEvents.INT_FIELDS[type]
		for k: String in e:
			if k != "type":
				assert_has(declared, k, "%s.%s" % [type, k])
				assert_typeof(e[k], TYPE_INT, "%s.%s" % [type, k])
		for k: String in declared:
			assert_true(e.has(k), "%s has %s" % [type, k])


func test_the_v4_events_carry_what_they_say() -> void:
	var events := _v4_events()
	assert_eq(events[0]["n"], 2)
	assert_eq(events[0]["sg"], TankIds.seg_code(TankIds.SEG_GUN_LINE))
	assert_eq(events[1]["hp"], 84)
	assert_eq(events[2]["e"], 7)
	assert_eq(events[4]["r"], 1500)
	assert_eq(events[4]["f"], 1)
	assert_eq(TankEvents.splash(900.0, TankIds.SHELL_ENEMY, false)["f"], 0)


## SPEC_AUDIO's incoming whistle and far boom read these.
func test_a_far_shot_carries_its_flight_and_range() -> void:
	var far := TankEvents.shot(-1, TankIds.SHELL_ENEMY, 42, 12, 2, 2.7349, 1500.4)
	assert_eq(far["flight_s"], 2.73)
	assert_eq(far["rng_m"], 1500)
	assert_typeof(far["rng_m"], TYPE_INT)
	assert_has(TankEvents.INT_FIELDS[TankEvents.SHOT], "rng_m")
	assert_has(TankEvents.FLOAT_FIELDS[TankEvents.SHOT], "flight_s")
	var cast := TankEventCast.cast(JSON.parse_string(JSON.stringify(far)))
	assert_eq(cast["flight_s"], 2.73, "the float survives the wire")
	assert_typeof(cast["rng_m"], TYPE_INT)
	var near := TankEvents.shot(1, TankIds.SHELL_HEAVY, 41)
	assert_false(near.has("flight_s"), "only a far shot has a flight time")
	assert_eq(near["rng_m"], 0)


# --- Stubs and seats --------------------------------------------------------------------------------


func test_is_free_for_lets_a_human_take_a_bots_seat() -> void:
	var s := TankFixturesV4.make("bots")
	var human := s.riders[0]
	var bot := s.riders[1]
	assert_true(bot.is_bot)
	assert_true(TankSeats.is_free_for(s, human, bot.engine), "a human's move always wins")
	assert_false(TankSeats.is_free_for(s, bot, human.engine), "a bot never takes a human's seat")
	assert_false(TankSeats.is_free_for(s, bot, s.riders[2].engine), "nor another bot's")
	assert_true(TankSeats.is_free_for(s, bot, TankIds.ENGINE_REPAIR), "an empty seat")
	assert_true(TankSeats.is_free_for(s, human, TankIds.ENGINE_REPAIR))
	assert_false(TankSeats.is_free_for(s, null, bot.engine))
	assert_false(TankSeats.is_free_for(s, human, "nowhere"))


func test_the_bot_stubs_keep_everything_where_it_is() -> void:
	var s := TankFixturesV4.make("bots")
	var bot := s.riders[1]
	assert_eq(TankBots.seat_wanted(s, bot), bot.engine)
	assert_eq(TankBots.intent(s, bot), {})
	assert_eq(TankBots.next_seat(s, bot), TankSeats.empty_seats(s)[0])
	assert_true(TankSeats.empty_seats(s).size() >= 2, "always at least two empty seats")


func test_the_autopilot_ranks_every_seat() -> void:
	var s := TankFixturesV4.make("repair")
	TankTargets.build(s, TankAux.of(s))
	var needs := TankAutopilot.seat_needs(s)
	assert_almost_eq(
		float(needs[TankIds.ENGINE_REPAIR]), TankAutopilot.repair_need(s), 0.0001, "hull at 55 %"
	)
	assert_gt(float(needs[TankIds.ENGINE_REPAIR]), 0.05, "more than the idle seat's rank")
	for seat: String in TankIds.SEATS:
		assert_true(needs.has(seat), seat)


func test_the_aux_has_the_cover_map() -> void:
	assert_eq(TankAux.new().cover, {})
