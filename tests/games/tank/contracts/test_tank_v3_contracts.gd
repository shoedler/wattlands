extends GutTest
## The v3 contract (docs/games/tank.md "v3 (2026-10-28)"): one tank for every crew size with its
## geometry from the r6 hitbox, five seats (the new feed), the seat model (empty seats, the seat
## lock, the seat target), the seat intent and event, the Loader's ready rack, the feed's state,
## their snapshot columns, the content schema for the tank and its seats, the strings, and
## TankTerrain.height_at. Behaviour (seat rules, the rack's cycle, the feed's fire) is the rules
## builder's; these are the names and shapes it builds on.

const HITBOX := "res://assets/tank/v3/r6_hitbox.json"
## r6 art px -> rules px: (art - ORIGIN) / SCALE (tanks.json tanks.landship.geometry).
const ORIGIN := Vector2(14.0, 111.5)
const SCALE := 1.5


func _files(mission: String = "ashfall_road") -> Dictionary:
	return TankContent.read_files(mission)


func _errors(files: Dictionary) -> String:
	return "\n".join(TankContent.from_dicts(files, "ashfall_road").errors)


func _fresh(crew: int) -> TankState:
	return TankState.create(TankFixtures.content(), TankFixtures.slots(crew), "ashfall_road", null)


func _row(snap: Dictionary, engine: String) -> Array:
	for st: Array in snap["st"]:
		if int(st[TankSnapshotSchema.ST_ENGINE]) == TankIds.engine_code(engine):
			return st
	return []


# --- Ids --------------------------------------------------------------------------------------------


func test_one_tank_for_every_crew_size_with_a_new_code() -> void:
	assert_eq(TankIds.TANKS, ["landship"] as Array[String])
	for crew in [0, 1, 2, 3, 4, 9]:
		assert_eq(TankIds.tank_for_crew(crew), TankIds.TANK_LANDSHIP, "crew %d" % crew)
	assert_eq(TankIds.TANK_CODES[TankIds.TANK_LANDSHIP], 5)
	assert_eq(TankIds.MAX_CREW, 4)
	for t: String in TankIds.RETIRED_TANK_CODES:
		var code := int(TankIds.RETIRED_TANK_CODES[t])
		assert_false(
			TankIds.TANK_CODES.values().has(code), "%s's code %d stays reserved" % [t, code]
		)


func test_the_feed_seat_and_the_seat_order() -> void:
	assert_eq(TankIds.ENGINE_FEED, "feed")
	assert_eq(TankIds.engine_code(TankIds.ENGINE_FEED), 6)
	assert_eq(TankIds.engine_of(6), TankIds.ENGINE_FEED)
	assert_eq(TankIds.engine_code(TankIds.ENGINE_BULWARK), 0, "v3: the gearbox's code 4 is retired")
	assert_eq(TankIds.engine_of(4), "")
	assert_eq(TankIds.ENGINE_LABELS[TankIds.ENGINE_FEED], "TANK_ENGINE_FEED")
	assert_eq(
		TankIds.SEATS, ["diesel", "dynamo", "steam", "arc", "feed"] as Array[String], "Drive first"
	)
	var labels: Array = []
	for e: String in TankIds.SEATS:
		labels.append(TankIds.SEAT_LABELS[e])
	assert_eq(
		labels,
		[
			"TANK_SEAT_DRIVE",
			"TANK_SEAT_GUN",
			"TANK_SEAT_LOADER",
			"TANK_SEAT_LIGHTS",
			"TANK_SEAT_SECONDARIES"
		]
	)
	assert_eq(TankIds.ENGINES.size(), TankIds.SEATS.size())
	for e: String in TankIds.SEATS:
		assert_has(TankIds.ENGINES, e)
	assert_eq(TankRiderState.ENGINE_INDEX[TankIds.ENGINE_FEED], 5)
	assert_eq(TankRiderState.new().engine_s.size(), 6, "index 3 stays the retired Bulwark's")
	assert_eq(TankIds.seat_step("feed", 1), "diesel", "next wraps")
	assert_eq(TankIds.seat_step("diesel", -1), "feed", "prev wraps")
	assert_eq(TankIds.seat_step("dynamo", 1), "steam")
	assert_eq(TankIds.seat_step("bulwark", 1), "diesel", "an unknown seat starts at Drive")


# --- Intents and events -----------------------------------------------------------------------------


func test_the_seat_intent_normalizes_and_every_seat_owns_it() -> void:
	assert_eq(
		TankIntents.normalize({"k": "seat", "to": "feed"}),
		{"k": "seat", "to": 6, "d": 0, "auto": false, "via": "action"}
	)
	assert_eq(TankIntents.normalize({"k": "seat", "to": "next"})["d"], 1)
	assert_eq(TankIntents.normalize({"k": "seat", "to": "prev"})["d"], -1)
	for junk: Variant in [
		{"k": "seat"},
		{"k": "seat", "to": 3},
		{"k": "seat", "to": "bulwark"},
		{"k": "seat", "to": "left"},
		{"k": "lever", "to": "drive"},
	]:
		assert_eq(TankIntents.normalize(junk), {}, str(junk))
	assert_eq(TankIntents.seat(TankIds.SEAT_TO_NEXT), {"k": "seat", "to": "next", "via": "action"})
	assert_true(TankIntents.is_deliberate(TankIntents.normalize(TankIntents.seat("arc"))))
	assert_false(
		TankIntents.is_deliberate(TankIntents.normalize({"k": "seat", "to": "arc", "auto": 1}))
	)
	for e: String in TankIds.SEATS:
		assert_true(TankIntents.owned(TankIds.INTENT_SEAT, e), e)
	assert_false(TankIntents.owned(TankIds.INTENT_SEAT, TankIds.ENGINE_BULWARK))
	var named := TankIntents.normalize({"k": "seat", "to": "steam"})
	assert_eq(TankIntents.seat_wanted(named, "diesel"), "steam")
	var nxt := TankIntents.normalize({"k": "seat", "to": "next"})
	assert_eq(TankIntents.seat_wanted(nxt, "arc"), "feed")
	var prv := TankIntents.normalize({"k": "seat", "to": "prev"})
	assert_eq(TankIntents.seat_wanted(prv, "diesel"), "feed")
	assert_eq(TankIntents.seat_wanted(TankIntents.normalize({"k": "fire"}), "dynamo"), "")


func test_the_seat_event_carries_slot_and_engine_codes() -> void:
	var e := TankEvents.seat(2, TankIds.ENGINE_ARC, TankIds.ENGINE_FEED)
	assert_eq(e, {"type": "seat", "s": 2, "from": 5, "to": 6})
	assert_eq(TankEvents.TYPES.back(), TankEvents.SEAT, "appended")
	assert_eq(TankEvents.INT_FIELDS[TankEvents.SEAT], ["s", "from", "to"])
	assert_has(TankEvents.TYPES, TankEvents.LEVER, "the lever's name stays taken on the wire")
	var cast := TankEventCast.cast(JSON.parse_string(JSON.stringify(e)))
	assert_eq(cast, e, "ints after the wire")


# --- State ------------------------------------------------------------------------------------------


func test_the_feed_state_round_trips_and_names_its_last_gun() -> void:
	var s := TankStationState.make(TankIds.ENGINE_FEED)
	assert_is(s, TankFeedState)
	var fd := s as TankFeedState
	assert_eq(TankFeedState.ROUNDS_PER_REV, 2)
	assert_eq([fd.rounds, fd.fire_tick, fd.last_gun()], [0, -1, -1])
	assert_true(fd.is_empty(), "a fresh seat is empty")
	fd.rounds = 7
	fd.rpm = 176.0
	fd.fire_tick = 1234
	fd.rev_acc = 0.25
	fd.slot = 2
	assert_eq(fd.last_gun(), 0, "round 7 is the upper gun's (rounds alternate 0, 1, 0, ...)")
	fd.rounds = 8
	assert_eq(fd.last_gun(), 1)
	var copy := TankStationState.make("feed").load_dict(
		JSON.parse_string(JSON.stringify(fd.to_dict()))
	)
	assert_is(copy, TankFeedState)
	assert_eq(JSON.stringify(copy.to_dict()), JSON.stringify(fd.to_dict()))
	assert_false(copy.is_empty())


func test_every_crew_starts_on_its_seats_and_the_rest_are_empty() -> void:
	var want := ["diesel", "dynamo", "steam", "arc"]
	for crew in [1, 2, 3, 4]:
		var s := _fresh(crew)
		assert_eq(s.crew, crew)
		assert_eq(s.hull.tank, TankIds.TANK_LANDSHIP)
		assert_eq(s.hull.code, 5)
		assert_eq([s.hull.hull_w, s.hull.hull_h], [296, 65], "the r6 hull in rules px")
		var rooms: Array = s.stations.map(func(st: TankStationState) -> String: return st.engine)
		assert_eq(rooms, ["diesel", "steam", "dynamo", "arc", "feed"], "rear to front")
		assert_is(s.station("feed"), TankFeedState)
		for r in s.riders:
			assert_eq(r.engine, want[r.slot], "crew %d slot %d" % [crew, r.slot])
			assert_eq(s.station(r.engine).slot, r.slot)
			assert_eq([r.seat_lock_s, r.seat_target], [0.0, ""], "the lock open, not moving")
		var empty: Array = []
		for st in s.stations:
			if st.is_empty():
				empty.append(st.engine)
				assert_eq(st.peer, 0)
		assert_eq(empty.size(), 5 - crew, "crew %d: at least one seat is always empty" % crew)
		assert_null(s.station_of(-1), "an empty seat is nobody's station")


func test_the_loader_rack_fields_round_trip() -> void:
	var sm := TankStationState.make(TankIds.ENGINE_STEAM) as TankSteamState
	assert_eq([sm.rack, sm.chamber, sm.chamber_s, sm.load_t], [0, false, 0.0, 0.0])
	assert_eq(TankConst.RACK_MAX, 3)
	assert_eq(TankConst.SEAT_LOCK_S, 60.0)
	sm.rack = 3
	sm.chamber = true
	sm.chamber_s = 0.6
	sm.load_t = 0.25
	var d := sm.to_dict()
	for k: String in ["rack", "chamber", "chamber_s", "load_t"]:
		assert_has(d, k)
	var copy := TankStationState.make("steam").load_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(JSON.stringify(copy.to_dict()), JSON.stringify(d))


# --- Snapshot ---------------------------------------------------------------------------------------


func test_the_v3_fields_ride_the_snapshot_as_ints_and_round_trip() -> void:
	var host := TankFixtures.state(4)
	host.rider_at(1).seat_lock_s = 42.345
	host.rider_at(3).seat_target = TankIds.ENGINE_FEED
	var sm := host.station(TankIds.ENGINE_STEAM) as TankSteamState
	sm.rack = 3
	sm.chamber = true
	sm.chamber_s = 0.75
	sm.load_t = 0.6
	var fd := host.station(TankIds.ENGINE_FEED) as TankFeedState
	fd.rounds = 1201
	fd.rpm = 183.4
	fd.fire_tick = 49199
	var snap := TankSnapshot.encode(host)
	assert_eq(TankSnapshotSchema.check(snap), "")
	assert_eq(snap["v"], 3)
	var r1: Array = (snap["r"] as Array)[1]
	assert_eq(r1.size(), TankSnapshotSchema.R_LEN)
	assert_eq(r1[TankSnapshotSchema.R_SEAT_LOCK_MS], 42345)
	assert_eq(r1[TankSnapshotSchema.R_SEAT_TARGET], 0, "not moving")
	assert_eq((snap["r"] as Array)[3][TankSnapshotSchema.R_SEAT_TARGET], 6, "moving to the feed")
	var st := _row(snap, "steam")
	assert_eq(st.size(), TankSnapshotSchema.ST_LEN)
	assert_eq(
		[st[TankSnapshotSchema.ST_D], st[TankSnapshotSchema.ST_E], st[TankSnapshotSchema.ST_F]],
		[3, 600, 750],
		"rack, load_pml, chamber_ms"
	)
	assert_ne(int(st[TankSnapshotSchema.ST_FLAGS]) & TankSnapshotSchema.STF_CHAMBER, 0)
	var fr := _row(snap, "feed")
	assert_eq([fr[TankSnapshotSchema.ST_A], fr[TankSnapshotSchema.ST_B]], [1201, 1834])
	assert_eq(fr[TankSnapshotSchema.ST_C], 49199)
	assert_eq(fr[TankSnapshotSchema.ST_SLOT], -1, "crew 4: the feed seat is empty")
	var client := _fresh(4)
	TankSnapshot.apply(client, JSON.parse_string(JSON.stringify(snap)))
	assert_almost_eq(client.rider_at(1).seat_lock_s, 42.345, 1e-9)
	assert_eq(client.rider_at(3).seat_target, TankIds.ENGINE_FEED)
	assert_eq(client.rider_at(0).seat_target, "")
	var csm := client.station(TankIds.ENGINE_STEAM) as TankSteamState
	assert_eq([csm.rack, csm.chamber], [3, true])
	assert_almost_eq(csm.chamber_s, 0.75, 1e-9)
	assert_almost_eq(csm.load_t, 0.6, 1e-9)
	var cfd := client.station(TankIds.ENGINE_FEED) as TankFeedState
	assert_eq([cfd.rounds, cfd.fire_tick], [1201, 49199])
	assert_almost_eq(cfd.rpm, 183.4, 1e-9)
	assert_true(cfd.is_empty())
	assert_eq(cfd.peer, 0, "derive(): nobody on an empty seat")
	assert_eq(JSON.stringify(TankSnapshot.encode(client)), JSON.stringify(snap), "round trip")


func test_an_empty_seat_and_a_seat_move_survive_the_wire() -> void:
	var host := TankFixtures.state(2)
	var client := _fresh(2)
	# The rider in slot 1 has left the Gun for the Loader: the Gun seat is empty now.
	host.station(TankIds.ENGINE_DYNAMO).slot = -1
	host.station(TankIds.ENGINE_STEAM).slot = 1
	host.rider_at(1).engine = TankIds.ENGINE_STEAM
	host.rider_at(1).seat_lock_s = 60.0
	TankSnapshot.apply(client, JSON.parse_string(JSON.stringify(TankSnapshot.encode(host))))
	assert_true(client.station(TankIds.ENGINE_DYNAMO).is_empty())
	assert_eq(client.station(TankIds.ENGINE_STEAM).slot, 1)
	assert_eq(client.station(TankIds.ENGINE_STEAM).peer, client.rider_at(1).peer)
	assert_eq(client.rider_at(1).engine, TankIds.ENGINE_STEAM)
	assert_eq(client.station_of(1), client.station(TankIds.ENGINE_STEAM))


func test_crew_4_at_the_caps_with_every_v3_field_busy_fits_4_kb() -> void:
	var s := TankFixtures.cap4()
	for r in s.riders:
		r.seat_lock_s = 59.999
		r.seat_target = TankIds.ENGINE_FEED
	var sm := s.station(TankIds.ENGINE_STEAM) as TankSteamState
	sm.rack = 3
	sm.chamber = true
	sm.chamber_s = 0.999
	sm.load_t = 0.999
	var fd := s.station(TankIds.ENGINE_FEED) as TankFeedState
	fd.rounds = 99999
	fd.rpm = 239.9
	fd.fire_tick = 99999
	var snap := TankSnapshot.encode(s)
	assert_eq((snap["r"] as Array).size(), 4)
	assert_eq((snap["st"] as Array).size(), 5)
	assert_eq((snap["e"] as Array).size(), TankConst.MAX_ENEMIES)
	assert_eq((snap["s"] as Array).size(), TankConst.MAX_SHELLS)
	assert_eq(TankSnapshotSchema.check(snap), "")
	var size := TankSnapshotSchema.byte_size(snap)
	gut.p("v3 crew-4 snapshot at the caps: %d bytes" % size)
	assert_lte(size, TankConst.SNAPSHOT_MAX_BYTES)


# --- Geometry ---------------------------------------------------------------------------------------


func _art(p: Variant) -> Vector2:
	return (Vector2(float(p[0]), float(p[1])) - ORIGIN) / SCALE


func _art_rect(r: Variant) -> Rect2:
	return Rect2(_art(r), Vector2(float(r[2]), float(r[3])) / SCALE)


func test_the_landship_geometry_is_the_r6_hitbox_in_rules_px() -> void:
	var hb: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HITBOX))
	var g := TankGeometry.load_default()
	assert_eq(g.validate(), [] as Array[String])
	var t := TankIds.TANK_LANDSHIP
	var eps := Vector2(0.01, 0.01)
	assert_almost_eq(g.trunnion(t), _art(hb["trunnion"]), eps, "trunnion")
	assert_almost_eq(g.muzzle(t, 0.0, TankIds.FACE_RIGHT), _art(hb["muzzle"]), eps, "muzzle")
	assert_almost_eq(
		g.muzzle(t, 0.0, TankIds.FACE_RIGHT), g.trunnion(t) + Vector2(g.barrel_px(t), 0.0), eps
	)
	var muzzles := g.bow_muzzles(t)
	var pivots := g.bow_pivots(t)
	assert_eq([muzzles.size(), pivots.size()], [2, 2], "two bow guns")
	for i in 2:
		assert_almost_eq(muzzles[i], _art(hb["bow_muzzles"][i]), eps, "bow muzzle %d" % i)
		assert_almost_eq(pivots[i], _art(hb["bow_pivots"][i]), eps, "bow pivot %d" % i)
	var rects := g.hit_rects(t)
	assert_eq(rects.size(), 3, "hull, track run, turret")
	var rr: Dictionary = hb["rects"]
	var want: Array = [rr["hull"], rr["track_run"], rr["turret"]]
	for i in 3:
		var w := _art_rect(want[i])
		assert_almost_eq(rects[i].position, w.position, eps, "rect %d" % i)
		assert_almost_eq(rects[i].size, w.size, eps, "rect %d" % i)
	var c := TankFixtures.content()
	var hull: Array = c.tank_def(t)["hull_px"]
	assert_almost_eq(rects[0].size.x, float(hull[0]), 0.01, "hull_px width: the hull rect")
	var ground := (float(hb["ground_contact"]["y"]) - ORIGIN.y) / SCALE
	assert_almost_eq(ground, float(hull[1]), 0.01, "the hull's bottom is the ground contact")
	assert_almost_eq(rects[1].end.y, float(hull[1]), 0.01, "the track run stands on the ground")
	assert_lt(rects[2].position.y, 0.0, "the turret above the hull rect")
	for e: String in c.engines_of(t):
		var room := g.seat_rect(t, e)
		assert_true(room.has_area(), "%s has a room" % e)
		assert_true(rects[0].encloses(room), "%s's room is inside the hull" % e)
	var xs: Array = []
	for e: String in c.engines_of(t):
		xs.append(g.seat_rect(t, e).position.x)
	var sorted := xs.duplicate()
	sorted.sort()
	assert_eq(xs, sorted, "the rooms run rear to front in tanks.json order")


# --- Content ----------------------------------------------------------------------------------------


func test_the_content_has_the_one_tank_and_five_seats() -> void:
	for m: String in ["ashfall_road", "drill", "roam_30"]:
		var c := TankContent.from_dicts(_files(m), m)
		assert_eq(c.errors, [] as Array[String], m)
	var c := TankFixtures.content()
	assert_eq((c.data["tanks"]["tanks"] as Dictionary).keys(), ["landship"])
	assert_null(c.value("tanks", "gearbox"), "the Bulwark's gearbox block is retired")
	assert_null(c.value("tanks", "bow.bulwark_rate"))
	assert_null(c.value("stations", "hoist"), "the Bulwark's hoist pattern is retired")
	assert_null(c.value("stations", "rotation"), "no rotation in v3")
	assert_eq(
		c.start_engines(TankIds.TANK_LANDSHIP),
		["diesel", "dynamo", "steam", "arc"] as Array[String]
	)
	for table: String in ["plans", "drill_plans", "roam_plans"]:
		for e: String in TankIds.ENGINES:
			assert_true((c.value("stations", table) as Dictionary).has(e), "%s.%s" % [table, e])
	for seg: String in ["depot", "advance", "gun_line", "boss"]:
		assert_eq(c.plan_entry("feed", seg), {"mode": "SIM", "grade_source": "flat"}, seg)


func test_the_schema_rejects_a_broken_landship_or_seats() -> void:
	var cases: Array = [
		[["tanks", "tanks", "landship", "code"], 4, "tanks.landship.code: must be 5"],
		[["tanks", "tanks", "landship", "crew"], [1, 3], "tanks.landship.crew: must be [1, 4]"],
		[
			["tanks", "tanks", "landship", "engines"],
			["diesel", "steam", "dynamo", "arc"],
			"needs the feed seat exactly once"
		],
		[
			["tanks", "tanks", "landship", "engines"],
			["diesel", "steam", "dynamo", "arc", "feed", "bulwark"],
			"unknown engine bulwark"
		],
		[["tanks", "tanks", "landship", "geometry", "muzzle"], [290, -5.6], "muzzle: must equal"],
		[
			["tanks", "tanks", "landship", "geometry", "ground_y"],
			70,
			"ground_y: must be hull_px[1]"
		],
		[["tanks", "tanks", "landship", "geometry", "hull_rect"], [0, 0, 0, 50], "hull_rect"],
		[["tanks", "tanks", "landship", "geometry", "bow_guns"], [], "bow_guns: at least one"],
		[["tanks", "tanks", "landship", "geometry", "seats"], {}, "seats.diesel"],
		[["tanks", "tanks", "landship", "geometry"], null, "landship geometry: expected obj"],
		[["stations", "start_engines", "landship"], ["diesel", "dynamo"], "one seat per slot"],
		[["stations", "start_engines", "landship"], ["diesel", "x", "steam", "arc"], "distinct"],
		[["stations", "rotation"], {}, "rotation: retired in v3"],
		[["stations", "plans", "feed"], null, "plans.feed: missing"],
	]
	for case: Array in cases:
		var f := _files()
		var path: Array = case[0]
		var node: Variant = f
		for i in path.size() - 1:
			node = node[path[i]]
		if case[1] == null:
			(node as Dictionary).erase(path[-1])
		else:
			node[path[-1]] = case[1]
		assert_string_contains(_errors(f), str(case[2]), str(path))


func test_the_v3_strings_exist_and_the_retired_ones_are_gone() -> void:
	var keys := {}
	for line: String in FileAccess.get_file_as_string("res://content/tank/strings.csv").split("\n"):
		keys[line.split(",")[0]] = true
	for k: String in [
		"TANK_TANK_LANDSHIP",
		"TANK_ENGINE_FEED",
		"TANK_SEAT_DRIVE",
		"TANK_SEAT_GUN",
		"TANK_SEAT_LOADER",
		"TANK_SEAT_LIGHTS",
		"TANK_SEAT_SECONDARIES",
		"TANK_STAT_FEED_S",
		"TANK_HUD_ENG_FEED",
		"TANK_HUD_JOB_FEED",
		"TANK_TOAST_SEAT",
	]:
		assert_true(keys.has(k), k)
	for e: String in TankIds.SEATS:
		assert_true(keys.has(TankIds.SEAT_LABELS[e]), e)
		assert_true(keys.has(TankIds.ENGINE_LABELS[e]), e)
	for k: String in [
		"TANK_TANK_BULWARK",
		"TANK_TANK_BASTION",
		"TANK_ENGINE_BULWARK",
		"TANK_LEVER_DRIVE",
		"TANK_TOAST_ROTATION",
		"TANK_CARD_HOIST"
	]:
		assert_false(keys.has(k), "retired: " + k)


# --- Terrain relief ---------------------------------------------------------------------------------


func test_the_height_is_the_integral_of_the_grade() -> void:
	assert_eq(TankTerrain.height_at([], 500.0), 0.0, "no terrain is flat")
	assert_eq(TankTerrain.height_at([[0, 5]], 0.0), 0.0, "0 at distance 0")
	assert_almost_eq(TankTerrain.height_at([[0, 5]], 100.0), 5.0, 1e-9, "5% for 100 m")
	assert_almost_eq(TankTerrain.height_at([[0, 5]], -100.0), -5.0, 1e-9, "back down behind 0")
	var pts := [[100, 0], [200, 4], [300, -2]]
	# Before 100 m the first grade (0) holds; 100..200 the trapezoid of 0 and 4 % = 2 m; 200..300
	# of 4 and -2 % = 1 m; past 300 m the last grade (-2 %) holds.
	assert_almost_eq(TankTerrain.height_at(pts, 100.0), 0.0, 1e-9)
	assert_almost_eq(TankTerrain.height_at(pts, 200.0), 2.0, 1e-9)
	assert_almost_eq(TankTerrain.height_at(pts, 150.0), 0.5, 1e-9, "half-way up the ramp")
	assert_almost_eq(TankTerrain.height_at(pts, 300.0), 3.0, 1e-9)
	assert_almost_eq(TankTerrain.height_at(pts, 400.0), 1.0, 1e-9, "-2% held for 100 m")


func test_the_height_agrees_with_the_grade_sampler_on_every_mission_segment() -> void:
	var c := TankFixtures.content()
	for i in c.segments().size():
		var pts: Variant = c.segment(i).get("terrain", [])
		if not (pts is Array) or (pts as Array).is_empty():
			continue
		var h := 0.0
		var step := 0.5
		var x := 0.0
		while x < 1200.0:
			h += (TankTerrain.grade_at(pts, x) + TankTerrain.grade_at(pts, x + step)) * 0.5 * step
			x += step
		assert_almost_eq(TankTerrain.height_at(pts, 1200.0), h / 100.0, 1e-6, "segment %d" % i)


# --- The rules on the one tank (interim, until the rules builder's seat logic) ----------------------


func test_a_solo_rider_drives_and_the_empty_gun_stays_silent() -> void:
	var rig := TankRulesRig.new(1)
	rig.enter(1, 5.0)
	var x0 := rig.hull().x_px
	rig.spawn(TankIds.ENEMY_MEDIUM, 1, 280.0)
	rig.run(20.0)
	assert_gt(rig.hull().x_px, x0, "Drive moves the tank")
	for engine: String in ["dynamo", "steam", "arc", "feed"]:
		var st := rig.state.station(engine)
		assert_true(st.is_empty(), engine)
		assert_eq(st.p_eff_w, 0.0, "%s: an empty seat gets no power" % engine)
	var main := rig.of_type("shot").filter(func(e: Dictionary) -> bool: return int(e["s"]) >= 0)
	assert_eq(main.size(), 0, "nobody on the Gun, nothing fires")
