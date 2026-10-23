extends GutTest
## FishingSnapshot (brief 2.6, GAME_SDK 12): the 4-lane worst case under 2 KB through
## JSON.stringify, the JSON round trip host -> client restoring every carried field, the
## Protocol int paths, history, and a rejoining client restored by one snapshot.

const F := preload("res://tests/games/fishing/fishing_fakes.gd")


func _host(humans: int = 4) -> FishingGame:
	return autofree(F.make_game(F.make_ctx(humans, 0, "free_30", Wl.HOST, 1)))


func _client(humans: int = 4, peer: int = 2) -> FishingGame:
	return autofree(F.make_game(F.make_ctx(humans, 0, "free_30", Wl.CLIENT, peer)))


func _jump_slot() -> FishingPlanSlot:
	var s := FishingPlanSlot.new()
	s.index = 0
	s.species = "marlin"
	s.sp = FishingConst.species_index("marlin")
	s.run_kind = FishingSpeciesDef.RUN_JUMP
	return s


## Every lane at its widest: picking with three far hints, big numbers, every flag; a full
## catch board. Lane 0's marlin is jumping.
func _worst_case(g: FishingGame) -> void:
	var st := g.state
	st.tick = 1234567
	st.t = st.tick * Wl.SIM_DT
	st.team_points = 9999999
	st.team_fish = 999
	st.hookup_level = 4
	st.trip_over = false
	st.catches.assign([3, 3, 1, 2, 2, 0, 1, 1, 1, 0, 0, 0, 3, 3, 1])
	for l in st.lanes:
		l.state = FishingConst.ST_PICK
		l.phase_index = 123
		l.hints.assign([1.0, 79.9, 0.999, 3.0, 80.0, 0.5, 2.0, 40.1, 0.123])
		l.selected = 2
		l.fish.sp = FishingConst.species_index("marlin")
		l.fish.d = 199.9
		l.fish.z = 0.999
		l.fish.s = 0.501
		l.fish.run_active = true
		l.fish.replacement = true
		l.fish.off_line = l.slot == 3
		l.strain = 0.999
		l.slack = 0.25
		l.gaff = 1.0 if l.slot == 1 else 0.731
		l.pub_lo = 105
		l.pub_hi = 127
		l.power_w = 1234.4
		l.cadence_ema = 118.6
		l.lure_d = 79.95
		l.rescue = l.slot == 0
		l.afk = l.slot == 1
		l.stale = l.slot == 2
		l.cadence_stale = l.slot == 3
		l.frenzy_until_t = st.t + 30.0
		l.fallback = l.slot != 2
		l.cosmetics.assign([4, 3, 3, 1])
		l.state_t = 9999.94
		l.points = 999999
		l.fish_landed = 99
	st.lanes[0].slots.assign([_jump_slot()])
	st.lanes[0].fight_slot = 0


func test_the_worst_case_fits_2_kb_of_json() -> void:
	var g := _host()
	_worst_case(g)
	var snap := g.snapshot()
	assert_eq(FishingSnapshotSchema.check(snap), "")
	var size := FishingSnapshot.byte_size(snap)
	gut.p("fishing worst-case 4-lane snapshot: %d bytes" % size)
	assert_gt(size, 400, "it carries everything")
	assert_lte(size, FishingConst.SNAPSHOT_MAX_BYTES)
	assert_eq((snap["C"] as Array).size(), FishingConst.CATCH_BOARD)
	for row: Array in snap["L"]:
		assert_eq((row[FishingSnapshotSchema.L_HINTS] as Array).size(), 3)


func test_a_json_round_trip_restores_every_carried_field() -> void:
	var host := _host()
	_worst_case(host)
	var text := JSON.stringify(host.snapshot())
	var client := _client()
	client.state.lanes[0].slots.assign([_jump_slot()])
	client.apply_snapshot(JSON.parse_string(text))
	assert_eq(
		JSON.stringify(client.snapshot()), text, "re-encoding the client gives the same bytes"
	)
	var a := host.state.lanes[0]
	var b := client.state.lanes[0]
	assert_eq(b.state, FishingConst.ST_PICK)
	assert_eq(b.phase_index, 123)
	assert_almost_eq(b.fish.d, 199.9, 0.051)
	assert_almost_eq(b.fish.z, 0.999, 0.0006)
	assert_almost_eq(b.fish.s, a.fish.s, 0.5 / 255.0)
	assert_almost_eq(b.strain, a.strain, 0.5 / 255.0)
	assert_eq(b.pub_lo, 105)
	assert_eq(b.pub_hi, 127)
	assert_eq(b.power_w, 1234.0)
	assert_eq(b.cadence_ema, 119.0)
	assert_eq(b.selected, 2)
	assert_eq(b.hint_count(), 3)
	assert_almost_eq(b.hints[4], 80.0, 0.001)
	assert_true(b.rescue)
	assert_true(b.fish.run_active)
	assert_true(b.fish.replacement)
	assert_eq(b.fight_slot, 0, "the jump flag finds the jumping slot")
	assert_gt(b.frenzy_until_t, client.state.t, "frenzy restored")
	assert_true(client.state.lanes[1].afk)
	assert_true(client.state.lanes[2].afk, "a stale rider shows as AFK")
	assert_true(client.state.lanes[3].cadence_stale)
	assert_true(client.state.lanes[3].fish.off_line)
	assert_false(client.state.lanes[2].fallback)
	assert_eq(b.cosmetics, [4, 3, 3, 1] as Array[int])
	assert_almost_eq(b.state_t, 9999.9, 0.001)
	assert_eq(b.points, 999999)
	assert_eq(b.fish_landed, 99)
	assert_eq(client.state.team_points, 9999999)
	assert_eq(client.state.team_fish, 999)
	assert_eq(client.state.hookup_level, 4)
	assert_eq(client.state.catches, host.state.catches)
	assert_eq(client.state.tick, 1234567)


func test_the_declared_int_paths_cover_every_number() -> void:
	var host := _host()
	_worst_case(host)
	var parsed: Variant = JSON.parse_string(JSON.stringify(host.snapshot()))
	var fields := host.int_fields()
	assert_eq(fields["snapshot"], FishingSnapshotSchema.INT_PATHS)
	for k: String in FishingEvents.INT_FIELDS:
		assert_true(fields.has(k), "int_fields declares %s" % k)
	var decoded: Variant = Protocol.apply_int_fields(parsed, fields["snapshot"])
	var floats: Array = []
	_collect_floats(decoded, "", floats)
	assert_eq(floats, [], "every number is an int after Protocol's int paths")


func _collect_floats(v: Variant, path: String, out: Array) -> void:
	if v is float:
		out.append(path)
	elif v is Array:
		for i in (v as Array).size():
			_collect_floats(v[i], "%s[%d]" % [path, i], out)
	elif v is Dictionary:
		for k: Variant in v:
			_collect_floats(v[k], "%s.%s" % [path, k], out)


func test_apply_snapshot_pushes_the_interpolation_history() -> void:
	var host := _host(2)
	var client := _client(2)
	host.state.tick = 100
	host.state.lanes[0].fish.d = 30.0
	client.apply_snapshot(JSON.parse_string(JSON.stringify(host.snapshot())))
	host.state.tick = 102
	host.state.lanes[0].fish.d = 31.0
	client.apply_snapshot(JSON.parse_string(JSON.stringify(host.snapshot())))
	assert_eq(client.history.entries.size(), 2)
	assert_almost_eq(client.history.newest_t(), 102 * Wl.SIM_DT, 1e-6)
	assert_almost_eq(float(client.history.entries[0]["lanes"][0]["d"]), 30.0, 1e-6)
	assert_almost_eq(client.history.mean_spacing(), 0.1, 1e-6)


func test_a_rejoining_client_is_restored_by_one_snapshot() -> void:
	var host := _host(3)
	var plans := F.plans_of(host)
	var tick := F.run(host, plans, 0, 20.0)
	var h := host.state
	h.lanes[1].state = FishingConst.ST_FIGHT
	h.lanes[1].fish.sp = FishingConst.species_index("tuna")
	h.lanes[1].fish.d = 64.3
	h.lanes[1].strain = 0.4
	h.lanes[2].state = FishingConst.ST_PICK
	h.lanes[2].hints.assign([0.0, 55.5, 0.8, 1.0, 62.0, 0.4, 3.0, 71.2, 0.6])
	h.lanes[2].selected = 1
	h.team_points = 412
	h.catches.assign([0, 1, 0])
	var text := JSON.stringify(host.snapshot())
	var late := _client(3, 3)
	assert_ne(JSON.stringify(late.snapshot()), text, "a fresh client starts elsewhere")
	late.apply_snapshot(JSON.parse_string(text))
	assert_eq(JSON.stringify(late.snapshot()), text)
	assert_eq(late.state.tick, tick)
	assert_eq(late.local_lane().state, FishingConst.ST_PICK)
	assert_eq(late.local_lane().selected, 1)
	assert_eq(late.state.lanes[1].fish.sp, FishingConst.species_index("tuna"))


func test_a_bad_snapshot_is_ignored_with_a_warning() -> void:
	var client := _client(2)
	var before := JSON.stringify(client.snapshot())
	client.apply_snapshot({"v": 99, "k": 5, "L": [], "T": [0, 0, 0, 0, 0], "C": []})
	client.apply_snapshot({"v": 1, "k": 5, "L": [[1, 2]], "T": [0, 0, 0, 0, 0], "C": []})
	assert_eq(JSON.stringify(client.snapshot()), before)


func test_a_cleared_frenzy_flag_clears_the_client_frenzy() -> void:
	var host := _host(2)
	var client := _client(2)
	host.state.lanes[1].frenzy_until_t = 40.0
	host.state.tick = 400
	host.state.t = 20.0
	client.apply_snapshot(JSON.parse_string(JSON.stringify(host.snapshot())))
	var until := client.state.lanes[1].frenzy_until_t
	assert_almost_eq(until, 20.0 + FishingConst.FRENZY_S, 1e-6)
	host.state.tick = 402
	host.state.t = 20.1
	client.apply_snapshot(JSON.parse_string(JSON.stringify(host.snapshot())))
	assert_eq(client.state.lanes[1].frenzy_until_t, until, "an on-going frenzy keeps its end")
	host.state.lanes[1].frenzy_until_t = 0.0
	host.state.tick = 404
	client.apply_snapshot(JSON.parse_string(JSON.stringify(host.snapshot())))
	assert_eq(client.state.lanes[1].frenzy_until_t, 0.0)
