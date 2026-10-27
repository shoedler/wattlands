extends GutTest
## The v2 contract additions (docs/games/tank.md 2.2, 2.4, 2.6, 2.10): the arc generator and the
## Bastion's ids, SHELL_BOW, the turn intent, the evade / turn / time_up events, TankArcState, the
## rider's target_pct, the hull's travel direction, their snapshot columns and the 4 KB budget with
## 4 riders, and the content skeleton for four tanks (the Citadel's room order, crew 4's rotation).

const ORDER_4: Array[String] = ["diesel", "dynamo", "steam", "arc"]


func _files(mission: String = "ashfall_road") -> Dictionary:
	return TankContent.read_files(mission)


func _errors(files: Dictionary) -> String:
	return "\n".join(TankContent.from_dicts(files, "ashfall_road").errors)


# --- Ids ------------------------------------------------------------------------------------------


func test_the_arc_engine_and_the_bastion_have_ids_codes_labels_and_an_icon() -> void:
	assert_eq(TankIds.ENGINE_ARC, "arc")
	assert_has(TankIds.ENGINES, TankIds.ENGINE_ARC)
	assert_eq(TankIds.engine_code(TankIds.ENGINE_ARC), 5)
	assert_eq(TankIds.engine_of(5), TankIds.ENGINE_ARC)
	assert_eq(TankIds.ENGINE_LABELS[TankIds.ENGINE_ARC], "TANK_ENGINE_ARC")
	assert_eq(TankIds.ENGINE_ICONS[TankIds.ENGINE_ARC], "res://assets/tank/icons/engine_arc.png")
	assert_eq(TankIds.TANK_BASTION, "bastion")
	assert_eq(TankIds.TANKS, ["bulwark", "rampart", "citadel", "bastion"] as Array[String])
	assert_eq(TankIds.TANK_CODES[TankIds.TANK_BASTION], 4)
	assert_eq(TankIds.tank_for_crew(4), TankIds.TANK_BASTION, "crew 4 picks the Bastion")
	assert_eq(TankIds.tank_for_crew(9), TankIds.TANK_BASTION)
	assert_eq(TankRiderState.ENGINE_INDEX[TankIds.ENGINE_ARC], 4)
	assert_eq(TankRiderState.new().engine_s.size(), TankIds.ENGINES.size())


func test_the_bow_round_keeps_code_4_and_the_dir_and_outcome_ids_exist() -> void:
	assert_eq(TankIds.SHELL_BOW, 4)
	assert_eq(TankIds.SHELL_NAMES[TankIds.SHELL_BOW], "bow")
	assert_eq(TankRiderState.SHELL_INDEX[TankIds.SHELL_BOW], 3)
	assert_eq(TankIds.DIR_RIGHT, 1)
	assert_eq(TankIds.DIR_LEFT, -1)
	assert_eq(TankIds.OUTCOME_TIME_UP, "time_up")


func test_turn_is_a_deliberate_intent_no_engine_owns_yet() -> void:
	assert_eq(TankIds.INTENT_KINDS.back(), TankIds.INTENT_TURN, "appended")
	assert_eq(TankIds.DELIBERATE_KINDS.back(), TankIds.INTENT_TURN)
	var n := TankIntents.normalize({"k": "turn"})
	assert_eq(n, {"k": "turn", "to": -1, "d": 0, "auto": false, "via": "action"})
	assert_true(TankIntents.is_deliberate(n))
	assert_false(TankIntents.is_deliberate(TankIntents.normalize({"k": "turn", "auto": 1})))
	for engine: String in TankIds.ENGINES:
		assert_false(TankIntents.owned(TankIds.INTENT_TURN, engine), "no handling yet: " + engine)


func test_evade_turn_and_time_up_events_are_appended_with_int_fields() -> void:
	var n := TankEvents.TYPES.size()
	assert_eq(TankEvents.TYPES.slice(n - 3), ["evade", "turn", "time_up"] as Array[String])
	assert_eq(
		TankEvents.evade(13, 3, true, 2), {"type": "evade", "id": 13, "e": 3, "ok": 1, "s": 2}
	)
	assert_eq(TankEvents.evade(13, 3, false, 2)["s"], -1, "no slot for a shot that was not evaded")
	assert_eq(TankEvents.evade(-4, TankIds.BOSS_CODE, false)["ok"], 0)
	assert_eq(TankEvents.turn(-1, TankIds.DIR_LEFT), {"type": "turn", "s": -1, "dir": -1})
	assert_eq(TankEvents.time_up(), {"type": "time_up"})
	assert_eq(TankEvents.INT_FIELDS[TankEvents.EVADE], ["id", "e", "ok", "s"])
	assert_eq(TankEvents.INT_FIELDS[TankEvents.TURN], ["s", "dir"])
	assert_eq(TankEvents.INT_FIELDS[TankEvents.TIME_UP], [])
	var cast := TankEventCast.cast(JSON.parse_string(JSON.stringify(TankEvents.evade(7, 1, true))))
	assert_eq(typeof(cast["ok"]), TYPE_INT, "the wire cast knows the new fields")


# --- TankArcState -----------------------------------------------------------------------------------


func test_make_arc_returns_the_arc_state_and_it_round_trips() -> void:
	var s := TankStationState.make(TankIds.ENGINE_ARC)
	assert_is(s, TankArcState)
	assert_eq(s.engine, TankIds.ENGINE_ARC)
	var arc := s as TankArcState
	arc.duty = 0.35
	arc.lit = true
	arc.stalled = true
	arc.slot = 3
	arc.note_fire(1, true)
	var d := arc.to_dict()
	for k: String in ["duty", "lit", "stalled", "engine", "slot"]:
		assert_has(d, k)
	assert_false(d.has("_ring"), "the fire history is host-only")
	var copy := TankStationState.make("arc").load_dict(JSON.parse_string(JSON.stringify(d)))
	assert_is(copy, TankArcState)
	assert_eq(JSON.stringify(copy.to_dict()), JSON.stringify(d))


func test_the_duty_is_the_share_of_the_last_10_s_the_bow_guns_fired() -> void:
	var arc := TankArcState.new()
	var n := TankArcState.window_ticks()
	assert_eq(n, 200, "10 s at 0.05 s")
	for t in n:
		arc.note_fire(t, true)
	assert_eq(arc.duty, 1.0, "firing the whole window")
	for t in range(n, n + n / 2):
		arc.note_fire(t, false)
	assert_almost_eq(arc.duty, 0.5, 1e-9, "half the window since")
	arc.note_fire(n + n / 2 - 1, true)
	assert_almost_eq(arc.duty, 0.5, 1e-9, "a tick counts once")
	arc.note_fire(2 * n + n / 2 - 1, false)
	assert_almost_eq(arc.duty, 0.0, 1e-9, "skipped ticks count as not firing")
	arc.note_fire(2 * n + n / 2, true)
	arc.note_fire(5 * n, true)
	assert_almost_eq(arc.duty, 1.0 / n, 1e-9, "a gap over the window clears it")
	arc.reset_fire()
	assert_eq(arc.duty, 0.0)
	arc.note_fire(3, true)
	assert_almost_eq(arc.duty, 1.0 / n, 1e-9)


# --- Rider target and hull direction ----------------------------------------------------------------


func _ri(mode: String, phase_mode: String, kind: String = Wl.WORK) -> TankRiderInput:
	var ri := TankRiderInput.new()
	ri.ftp = 200.0
	ri.mode = mode
	ri.phase_mode = phase_mode
	ri.phase_kind = kind
	ri.cadence_rpm = 90.0
	return ri


func test_target_pct_prefers_the_applied_then_the_planned_erg_target() -> void:
	var s := TankFixtures.state(3)
	var dyn := s.station(TankIds.ENGINE_DYNAMO)
	var ri := _ri(Wl.ERG, Wl.ERG)
	ri.applied_target_w = 150.0
	ri.planned_pct = 65.0
	assert_almost_eq(TankRules.target_pct(s, ri, dyn), 75.0, 1e-9, "the applied target")
	ri.applied_target_w = 100.0
	assert_almost_eq(TankRules.target_pct(s, ri, dyn), 50.0, 1e-9, "rescue's 50% applies")
	ri.applied_target_w = 0.0
	assert_eq(TankRules.target_pct(s, ri, dyn), 65.0, "no telemetry target: the plan's")
	ri.mode = Wl.OFF
	assert_eq(TankRules.target_pct(s, ri, dyn), 65.0)
	assert_eq(TankRules.target_pct(s, _ri(Wl.OFF, ""), null), 0.0, "no phase, no target")


func test_target_pct_in_sim_is_the_engines_band_centre() -> void:
	var s := TankFixtures.state(3)
	var diesel := s.station(TankIds.ENGINE_DIESEL)
	var steam := s.station(TankIds.ENGINE_STEAM) as TankSteamState
	var ri := _ri(Wl.SIM, Wl.SIM)
	assert_eq(TankRules.target_pct(s, ri, diesel), 90.5, "diesel: the middle of 76..105")
	var bul := TankFixtures.state(1)
	assert_eq(TankRules.target_pct(bul, ri, bul.station(TankIds.ENGINE_BULWARK)), 90.5)
	steam.loaded = false
	steam.cycling = false
	assert_eq(TankRules.target_pct(s, ri, steam), 90.0, "steam building")
	steam.loaded = true
	assert_eq(TankRules.target_pct(s, ri, steam), 60.0, "steam loaded")
	steam.loaded = false
	steam.cycling = true
	assert_eq(TankRules.target_pct(s, ri, steam), 60.0, "steam cycling")
	var warm := _ri(Wl.SIM, Wl.SIM, Wl.WARMUP)
	assert_eq(TankRules.target_pct(s, warm, diesel), 60.0, "the depot's SIM")
	assert_eq(TankRules.target_pct(s, warm, steam), 60.0)
	var checkpoint := _ri(Wl.ERG, Wl.ERG, Wl.RECOVERY)
	checkpoint.applied_target_w = 100.0
	assert_eq(TankRules.target_pct(s, checkpoint, diesel), 50.0, "checkpoint ERG 50%")


func test_the_input_digest_carries_the_planned_target() -> void:
	var c := TankFixtures.content()
	var players := TankFixtures.slots(3)
	var plans := TankPlanBuilder.build_all(c, players, true)
	var f := TankFixtures.frame(3)
	var inp := TankInputs.from_frame(f, players, plans, {}, {}, {})
	for ri in inp.riders:
		assert_eq(ri.planned_pct, f.phase_of(ri.peer).planned_pct, "peer %d" % ri.peer)
	assert_gt(inp.rider(1).planned_pct, 0.0, "stage 2: slot 0 is on the dynamo (ERG)")


func test_the_rules_fill_target_pct_every_tick() -> void:
	var rig := TankRulesRig.new(4)
	rig.enter(1, 30.0)
	rig.step()
	var want := {
		TankIds.ENGINE_DIESEL: 90.5,
		TankIds.ENGINE_STEAM: 90.0,
		TankIds.ENGINE_DYNAMO: 55.0,
		TankIds.ENGINE_ARC: 65.0,
	}
	for r in rig.state.riders:
		assert_almost_eq(r.target_pct, float(want[r.engine]), 0.5, "%s (stage 1)" % r.engine)
	rig.enter(0, 30.0)
	rig.step()
	for r in rig.state.riders:
		var depot := 60.0 if r.engine in ["diesel", "steam"] else 51.5
		assert_almost_eq(r.target_pct, depot, 0.5, "%s in the depot" % r.engine)


func test_the_hull_travels_right_by_default() -> void:
	var h := TankHullState.new()
	assert_eq(h.dir, TankIds.DIR_RIGHT)
	assert_eq(TankFixtures.state(4).hull.dir, 1, "missions always +1")
	assert_has(h.to_dict(), "dir")


# --- Snapshot ---------------------------------------------------------------------------------------


func _fresh(crew: int) -> TankState:
	return TankState.create(
		TankFixtures.content(), TankFixtures.slots(crew), "ashfall_road", true, null
	)


func test_the_new_fields_ride_the_snapshot_as_ints_and_round_trip() -> void:
	var host := TankFixtures.state(4)
	host.hull.dir = TankIds.DIR_LEFT
	var arc := host.station(TankIds.ENGINE_ARC) as TankArcState
	arc.stalled = true
	host.rider_at(2).target_pct = 87.65
	var snap := TankSnapshot.encode(host)
	assert_eq(TankSnapshotSchema.check(snap), "")
	assert_eq(snap["v"], 2)
	assert_eq(snap["tk"][TankSnapshotSchema.TK_DIR], -1)
	var row: Array = (snap["r"] as Array)[2]
	assert_eq(row[TankSnapshotSchema.R_TARGET_X10], 877, "x10, rounded")
	var arc_row: Array = []
	for st: Array in snap["st"]:
		if st[TankSnapshotSchema.ST_ENGINE] == TankIds.engine_code("arc"):
			arc_row = st
	assert_eq(arc_row[TankSnapshotSchema.ST_A], 350, "duty in thousandths")
	var flags: int = arc_row[TankSnapshotSchema.ST_FLAGS]
	assert_ne(flags & TankSnapshotSchema.STF_LIT, 0)
	assert_ne(flags & TankSnapshotSchema.STF_ARC_STALLED, 0)
	var client := _fresh(4)
	TankSnapshot.apply(client, JSON.parse_string(JSON.stringify(snap)))
	assert_eq(client.hull.dir, -1)
	assert_almost_eq(client.rider_at(2).target_pct, 87.7, 1e-9)
	var carc := client.station(TankIds.ENGINE_ARC) as TankArcState
	assert_almost_eq(carc.duty, 0.35, 1e-9)
	assert_true(carc.lit)
	assert_true(carc.stalled)
	assert_eq(JSON.stringify(TankSnapshot.encode(client)), JSON.stringify(snap), "round trip")


func test_every_crew_round_trips_through_json() -> void:
	for crew in [1, 2, 3, 4]:
		for f: Callable in [TankFixtures.state, TankFixtures.gun_line, TankFixtures.boss]:
			var snap := TankSnapshot.encode(f.call(crew))
			var client := _fresh(crew)
			TankSnapshot.apply(client, JSON.parse_string(JSON.stringify(snap)))
			assert_eq(
				JSON.stringify(TankSnapshot.encode(client)), JSON.stringify(snap), "crew %d" % crew
			)


func test_a_bastion_snapshot_at_the_caps_fits_4_kb() -> void:
	var s := TankFixtures.cap4()
	assert_eq(s.riders.size(), 4)
	assert_eq(s.stations.size(), 4)
	assert_eq(s.hull.tank, TankIds.TANK_BASTION)
	var snap := TankSnapshot.encode(s)
	assert_eq((snap["e"] as Array).size(), TankConst.MAX_ENEMIES)
	assert_eq((snap["s"] as Array).size(), TankConst.MAX_SHELLS)
	assert_eq((snap["r"] as Array).size(), 4)
	assert_eq((snap["st"] as Array).size(), 4)
	assert_eq(TankSnapshotSchema.check(snap), "")
	var size := TankSnapshotSchema.byte_size(snap)
	gut.p("Bastion snapshot at the caps: %d bytes" % size)
	assert_lte(size, TankConst.SNAPSHOT_MAX_BYTES)


func _canon(v: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v)))


func test_the_bastion_fixture_snapshot_matches_the_encoder() -> void:
	var snap := TankSnapshot.encode(TankFixtures.state(4))
	assert_eq(_canon(snap), JSON.stringify(TankFixtures.snapshot(4)), "snapshot_bastion.json")


# --- Content ----------------------------------------------------------------------------------------


func test_four_tanks_validate_and_the_bastion_has_the_kit_hull_size() -> void:
	for m: String in ["ashfall_road", "drill"]:
		var c := TankContent.from_dicts(_files(m), m)
		assert_eq(c.errors, [] as Array[String], m)
	var c := TankFixtures.content()
	var want := {
		"bulwark": [220, 71], "rampart": [251, 71], "citadel": [296, 71], "bastion": [327, 71]
	}
	for t: String in TankIds.TANKS:
		var def := c.tank_def(t)
		assert_eq(int(def["code"]), int(TankIds.TANK_CODES[t]), t)
		assert_eq(int(def["crew"]), TankIds.TANKS.find(t) + 1, t)
		var hull: Array = def["hull_px"]
		assert_eq([int(hull[0]), int(hull[1])], want[t], "%s hull_px" % t)
	var bastion := c.tank_def(TankIds.TANK_BASTION)
	assert_eq(c.engines_of("bastion"), ["diesel", "steam", "dynamo", "arc"] as Array[String])
	assert_eq(bastion["turrets"], ["main"])
	assert_eq(float(bastion["enemy_scale"]), 1.2)
	assert_eq(bastion["label"], "TANK_TANK_BASTION")
	assert_eq(c.engines_of("citadel"), ["diesel", "steam", "dynamo"] as Array[String], "rooms")
	assert_eq(c.tank_def("citadel")["turrets"], ["main"])
	assert_eq(c.start_engines("citadel"), ["diesel", "dynamo", "steam"] as Array[String], "slots")
	assert_eq(c.start_engines("bastion"), ORDER_4, "slot 3 starts on the arc")


func test_the_schema_rejects_a_broken_bastion() -> void:
	var f := _files()
	f["tanks"]["tanks"].erase("bastion")
	assert_string_contains(_errors(f), "tanks: missing bastion")
	f = _files()
	f["tanks"]["tanks"]["bastion"]["code"] = 3
	f["tanks"]["tanks"]["bastion"]["crew"] = 3
	var all := _errors(f)
	assert_string_contains(all, "tanks.bastion.code: must be 4")
	assert_string_contains(all, "tanks.bastion.crew: must be 4")
	f = _files()
	f["stations"]["start_engines"]["bastion"] = ["diesel", "dynamo", "steam"]
	assert_string_contains(_errors(f), "start_engines.bastion: one engine per slot")
	f = _files()
	f["tanks"]["tanks"]["bastion"]["engines"] = ["diesel", "steam", "dynamo", "bulwark"]
	assert_string_contains(_errors(f), "start_engines.bastion: must be tanks.json")
	f = _files()
	f["stations"]["plans"].erase("arc")
	assert_string_contains(_errors(f), "plans.arc: missing")
	f = _files()
	f["stations"]["plans"]["arc"]["advance"]["range_pct"] = [65, 105]
	assert_string_contains(_errors(f), "plans.arc.advance: every ERG value")
	f = _files()
	f["stations"]["rotation"]["bastion"][1] = ["dynamo", "dynamo", "arc", "diesel"]
	assert_string_contains(_errors(f), "rotation.bastion column 2")
	f = _files()
	f["tanks"]["power_ratio"]["steam_loaded_pct"] = 0
	assert_string_contains(_errors(f), "power_ratio.steam_loaded_pct")


func test_crew_4_rotates_through_every_engine_in_slot_order() -> void:
	var c := TankFixtures.content()
	for s in 4:
		var row := c.rotation_row(TankIds.TANK_BASTION, s)
		for k in 4:
			assert_eq(row[k], ORDER_4[(s + k) % 4], "slot %d stage %d" % [s, k + 1])
	var stages := [1, 4, 7, 10]
	for s in 4:
		var seen := {}
		for k in 4:
			var e := TankPlanBuilder.engine_for(c, TankIds.TANK_BASTION, s, stages[k], true)
			assert_eq(e, ORDER_4[(s + k) % 4], "the plan builder, slot %d" % s)
			seen[e] = true
		assert_eq(seen.size(), 4, "slot %d works every engine once" % s)


func test_the_arc_plans_follow_the_brief() -> void:
	var c := TankFixtures.content()
	assert_eq(
		c.plan_entry("arc", "depot"), {"mode": "ERG", "target_pct": 50.0, "ramp_to_pct": 65.0}
	)
	for seg: String in ["advance", "gun_line", "boss"]:
		var e := c.plan_entry("arc", seg)
		assert_eq(e["mode"], Wl.ERG, seg)
		assert_eq(float(e["target_pct"]), 65.0, seg)
		assert_eq(e["range_pct"], [65.0, 80.0], seg)
	var drill := TankContent.from_dicts(_files("drill"), "drill")
	assert_eq(float(drill.plan_entry("arc", "depot")["target_pct"]), 50.0)
	assert_eq(drill.plan_entry("arc", "skirmish")["range_pct"], [55.0, 65.0])
	var plans := TankPlanBuilder.build_all(c, TankFixtures.slots(4), true)
	assert_eq(plans.size(), 4, "a plan per Bastion rider")


func test_crew_4_starts_on_the_bastion_with_its_rooms() -> void:
	var s := _fresh(4)
	assert_eq(s.crew, 4)
	assert_eq(s.hull.tank, TankIds.TANK_BASTION)
	assert_eq(s.hull.code, 4)
	assert_eq([s.hull.hull_w, s.hull.hull_h], [327, 71])
	var rooms: Array = s.stations.map(func(st: TankStationState) -> String: return st.engine)
	assert_eq(rooms, ["diesel", "steam", "dynamo", "arc"], "rear to front")
	assert_is(s.station("arc"), TankArcState)
	assert_eq(s.station("arc").slot, 3)
	assert_eq(s.rider_at(3).engine, "arc")
	assert_eq(s.station("steam").slot, 2)
	assert_eq(s.station("dynamo").slot, 1)


func test_the_geometry_falls_back_to_the_citadel_for_the_bastion_until_its_rig_lands() -> void:
	var g := TankGeometry.load_default()
	assert_eq(g.validate(), [] as Array[String])
	if not g.has_rig(TankIds.TANK_BASTION):
		assert_eq(g.rig_of(TankIds.TANK_BASTION), TankIds.TANK_CITADEL)
		assert_eq(g.muzzle("bastion", 10.0, 1), g.muzzle("citadel", 10.0, 1))
	assert_eq(g.rig_of(TankIds.TANK_CITADEL), TankIds.TANK_CITADEL)
	var own := TankGeometry.from_dict({"tanks": {"bastion": {"muzzle": [1, 2]}}})
	assert_eq(own.rig_of("bastion"), "bastion", "its own rig wins once it exists")
