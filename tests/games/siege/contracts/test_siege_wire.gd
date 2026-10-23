extends GutTest
## Events, int_fields and the snapshot (brief 2.6): every event type, ints after a JSON round
## trip, the exact snapshot layout, <= 8 KB at the 150-enemy cap, and a client's apply.

const FIX := preload("res://tests/games/siege/fixtures/siege_fixtures.gd")


func _round_trip(d: Dictionary, paths: Array) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(d))
	return Protocol.apply_int_fields(parsed, paths)


func _samples() -> Array[Dictionary]:
	var roads: Array[int] = [0, 2]
	return [
		SiegeEvents.wave_start(4, SiegeIds.ROLE_WAVE, 2, 6, 180.4, roads),
		SiegeEvents.wave_end(4, 2, 71.2, 125.0, 3),
		SiegeEvents.roads(roads, 5000),
		SiegeEvents.push(roads),
		SiegeEvents.rush(true, 1),
		SiegeEvents.kill(1234, SiegeIds.ENEMY_RAM, 3, 1, true),
		SiegeEvents.leak(77, SiegeIds.ENEMY_RAIDERS, 2, 2),
		SiegeEvents.breach(1),
		SiegeEvents.gate_restored(30.0),
		SiegeEvents.buy(2, SiegeIds.ITEM_UPGRADE, 4, false, SiegeIds.BUY_FUNDS, 2),
		SiegeEvents.route(1, 6),
		SiegeEvents.overdrive(0, SiegeIds.OD_EV_REFUSED, false, Wl.REFUSE_SWITCH_SPACING),
	]


func test_every_event_type_has_a_constructor_and_survives_json_as_ints() -> void:
	var fields := SiegeEvents.int_fields()
	var types := {}
	for e in _samples():
		assert_eq(SiegeEvents.check(e), "", str(e))
		types[e["type"]] = true
		var back := _round_trip(e, fields[e["type"]])
		assert_eq(back, e, "%s comes back equal (ints included)" % e["type"])
		assert_eq(
			SiegeEvents.cast(JSON.parse_string(JSON.stringify(e))),
			e,
			"cast() alone also restores the ints"
		)
	assert_eq(types.size(), SiegeIds.EVENT_TYPES.size(), "every event type sampled")
	for t: String in SiegeIds.EVENT_TYPES:
		assert_true(fields.has(t), t)
	assert_false(fields.has("wl.phase_started"))
	assert_true(fields.has("snapshot"))
	assert_has(fields["snapshot"], "f[][]")
	assert_has(fields["snapshot"], "f[][][]")


func test_buy_refusals_carry_the_slot_and_a_zero_level() -> void:
	var e := SiegeEvents.buy(3, SiegeIds.ITEM_GENERATOR, 0, false, SiegeIds.BUY_FUNDS, 2)
	assert_eq([e["slot"], e["ok"], e["why"], e["lvl"]], [3, 0, "funds", 0])
	assert_ne(SiegeEvents.check({"type": "buy", "slot": 1}), "")
	assert_ne(SiegeEvents.check({"type": "nope"}), "")


func test_the_snapshot_layout_is_exactly_the_brief_s() -> void:
	var snap := SiegeSnapshot.encode(FIX.mid_wave())
	var keys := snap.keys()
	keys.sort()
	var want := SiegeSnapshotSchema.KEYS.duplicate()
	# The fixture has one Iron band bought; the other optional keys stay off their defaults.
	want.append("ib")
	want.sort()
	assert_eq(keys, want)
	assert_eq(snap["ib"], 1)
	assert_eq(SiegeSnapshotSchema.check(snap), "")
	assert_eq(snap["v"], 1)
	assert_eq(snap["ph"], 4)
	assert_eq(snap["pt_ms"], 50000)
	assert_eq(snap["gate"], [72, 125, 0])
	assert_eq(snap["gl"], 1)
	assert_eq(snap["pk"], [SiegeIds.PERK_RESERVE])
	assert_eq(snap["q"], 3)
	assert_eq((snap["r"] as Array).size(), 4)
	assert_eq(
		snap["r"][0], [0, 3, 0, 12000, 0, 57, 300, 240, 96, 0, 0], "slot 0 in Overdrive on pad 3"
	)
	assert_eq(
		snap["r"][1], [1, 0, 0, 0, 61500, 133, 125, 110, 41, 1, 0], "slot 1 rescued, cooling down"
	)
	assert_eq(snap["r"][2][2], 1200, "slot 2 reconnecting")
	assert_eq((snap["tw"] as Array).size(), 4, "built pads only")
	assert_eq(snap["tw"][0], [2, SiegeIds.TOWER_CALTROP, 2, 85, 1200])
	assert_eq((snap["e"] as Array).size(), 43)
	assert_eq((snap["z"] as Array).size(), 1)
	assert_eq((snap["f"] as Array).size(), 3)


func test_the_snapshot_survives_json_as_ints_and_matches_the_fixture_file() -> void:
	var snap := SiegeSnapshot.encode(FIX.mid_wave())
	var back := _round_trip(snap, SiegeSnapshotSchema.INT_PATHS)
	assert_eq(JSON.stringify(back), JSON.stringify(snap))
	assert_eq(typeof(back["f"][1][1][0]), TYPE_INT, "shot target ids are ints (f[][][])")
	assert_eq(typeof(back["r"][0][5]), TYPE_INT)
	var file := FIX.snapshot()
	assert_eq(
		JSON.stringify(_round_trip(file, SiegeSnapshotSchema.INT_PATHS)),
		JSON.stringify(snap),
		"the fixture file is current"
	)


func test_at_the_cap_a_snapshot_stays_under_8_kb() -> void:
	var s := FIX.cap()
	assert_eq(s.enemies.size(), 150)
	var bytes := SiegeSnapshotSchema.byte_size(SiegeSnapshot.encode(s))
	assert_lte(bytes, SiegeSnapshotSchema.MAX_BYTES, "%d bytes" % bytes)


func test_the_shop_and_gate_keys_ride_only_when_they_are_off_their_defaults() -> void:
	var s := FIX.mid_wave()
	s.iron_bands = 0
	var plain := SiegeSnapshot.encode(s)
	for k in ["ib", "gd", "gt", "ro", "ru"]:
		assert_false(plain.has(k), "%s is absent at its default" % k)
	assert_eq(SiegeSnapshotSchema.check(plain), "")
	s.iron_bands = 2
	s.note_gate_damage(SiegeIds.ROAD_VALLEY, SiegeIds.ENEMY_RAIDERS, 3.04)
	s.note_gate_damage(SiegeIds.ROAD_VALLEY, SiegeIds.ENEMY_RAM, 0.46)
	s.note_gate_damage(SiegeIds.ROAD_EAST, SiegeIds.ENEMY_HORSEMEN, 12.0)
	var snap := SiegeSnapshot.encode(s)
	assert_eq(snap["ib"], 2)
	assert_eq(snap["gd"], [0, 35, 120], "gate damage by road in 0.1 HP")
	var raiders := 1 << SiegeIds.ENEMY_RAIDERS
	var ram := 1 << SiegeIds.ENEMY_RAM
	assert_eq(snap["gt"], [0, raiders | ram, 1 << SiegeIds.ENEMY_HORSEMEN])
	for k in ["ib", "gd", "gt"]:
		assert_true(SiegeSnapshotSchema.OPTIONAL_KEYS.has(k))
	var back := _round_trip(snap, SiegeSnapshotSchema.INT_PATHS)
	assert_eq(JSON.stringify(back), JSON.stringify(snap), "ints stay ints through the wire")
	assert_eq(typeof(back["ib"]), TYPE_INT)
	assert_eq(typeof(back["gd"][1]), TYPE_INT)
	assert_eq(typeof(back["gt"][2]), TYPE_INT)
	var client := SiegeState.create(FIX.content("vo2"), FIX.slots(), Wl.FAIR_FTP, null)
	SiegeSnapshot.apply(client, JSON.parse_string(JSON.stringify(snap)))
	assert_eq(client.iron_bands, 2)
	assert_almost_eq(client.gate_damage_by_road[SiegeIds.ROAD_VALLEY], 3.5, 1e-6)
	assert_eq(client.gate_damage_types_by_road, s.gate_damage_types_by_road)
	assert_true(client.gate_damaged_by(SiegeIds.ROAD_VALLEY, SiegeIds.ENEMY_RAM))
	assert_false(client.gate_damaged_by(SiegeIds.ROAD_WEST, SiegeIds.ENEMY_RAM))
	# A snapshot without the keys (an older host, or nothing yet) clears them.
	SiegeSnapshot.apply(client, JSON.parse_string(JSON.stringify(plain)))
	assert_eq(client.iron_bands, 0)
	assert_eq(client.gate_damage_by_road, [0.0, 0.0, 0.0] as Array[float])
	assert_eq(client.gate_damage_types_by_road, [0, 0, 0] as Array[int])


func test_a_client_applies_the_snapshot_without_int_fields() -> void:
	var c := FIX.content("vo2")
	var client := SiegeState.create(c, FIX.slots(), Wl.FAIR_FTP, null)
	SiegeSnapshot.apply(client, JSON.parse_string(JSON.stringify(FIX.snapshot())))
	var host := FIX.mid_wave(c)
	assert_eq(client.tick, host.tick)
	assert_eq(client.phase_index, 4)
	assert_eq(client.gate_hp, 72.0)
	assert_eq(client.enemies.size(), host.enemies.size())
	assert_eq(
		client.enemies[5].pos.distance_to(host.enemies[5].pos) < 0.2, true, "positions from the map"
	)
	assert_eq(client.rider_at(0).od_state, SiegeIds.OD_ACTIVE)
	assert_eq(client.rider_at(1).od_state, SiegeIds.OD_COOLDOWN)
	assert_eq(client.rider_at(2).od_state, SiegeIds.OD_READY)
	assert_eq(client.rider_at(1).raw_w, 110.0, "a teammate's raw W from the snapshot")
	assert_true(client.rider_at(1).rescue)
	assert_eq(client.pad(3).type, SiegeIds.TOWER_BALLISTA)
	assert_eq(client.pad(1).type, SiegeIds.TOWER_NONE)
	assert_eq(client.queued(), 3)
	assert_eq(client.zones[0].landed(), true)
	assert_eq(client.shots[1].targets.size(), 3)
	assert_eq(JSON.stringify(SiegeSnapshot.encode(client)).length() > 0, true)
	var again := SiegeSnapshot.encode(client)
	again["tick"] = host.tick
	assert_eq(
		again["e"], SiegeSnapshot.encode(host)["e"], "re-encoding the client gives the same rows"
	)
