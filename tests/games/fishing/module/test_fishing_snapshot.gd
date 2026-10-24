extends GutTest
## FishingSnapshot v2 (GAME_SDK 12): the 4-rider worst case under 2 KB through JSON.stringify,
## the JSON round trip host -> client restoring every carried field, the Protocol int paths,
## snapshot_applied for the view's interpolation, and a rejoining client restored by one snapshot.

const F := preload("res://tests/games/fishing/fishing_fakes.gd")
const S = preload("res://src/games/fishing/contracts/fishing_snapshot_schema.gd")

var _applied: Array = []


func before_each() -> void:
	_applied.clear()


func _host(humans: int = 4, content: String = "roam_30") -> FishingGame:
	return autofree(F.make_game(F.make_ctx(humans, 0, content, Wl.HOST, 1)))


func _client(humans: int = 4, peer: int = 2, content: String = "roam_30") -> FishingGame:
	return autofree(F.make_game(F.make_ctx(humans, 0, content, Wl.CLIENT, peer)))


func _round_trip(host: FishingGame, client: FishingGame) -> String:
	var text := JSON.stringify(host.snapshot())
	client.apply_snapshot(JSON.parse_string(text))
	return text


## Every rider at its widest: in the menu with three far, deep hints and five entries, big
## numbers, almost every flag; a full catch board. Values sit on whole decimetres.
func _worst_case(g: FishingGame) -> void:
	var st := g.state
	st.tick = 1234567
	st.t = st.tick * Wl.SIM_DT
	st.play_end_t = st.t + 1234.0
	st.team_points = 9999999
	st.team_fish = 999
	st.hookup_level = 4
	st.catches.assign([3, 9, 4999, 1, 2, 8, 2995, 0, 1, 7, 3999, 1, 0, 6, 2499, 0, 3, 0, 20, 1])
	for r in st.riders:
		r.action = FishingConst.A_MENU
		r.phase_kind = Wl.FREE
		r.x_m = 8949.9
		r.heading = -1
		r.v_mps = -0.29
		r.pitch_deg = 13.9
		r.wake = 0.999
		r.p_eff_w = 400.0
		r.hints.assign([9.0, -39.9, 399.9, 0.999, 8.0, 12.3, 612.4, 0.5, 7.0, 39.9, 55.5, 0.123])
		r.menu.assign([0, 1, 2, FishingConst.M_DRIVE_ON, FishingConst.M_TURN])
		r.selected = 4
		r.target_sp = 8
		r.lure_dx = -39.9
		r.lure_depth = 399.9
		r.strain = 0.999
		r.slack = 0.25
		r.gaff = 1.0 if r.slot == 1 else 0.731
		r.pub_lo = 105
		r.pub_hi = 127
		r.power_w = 1234.4
		r.cadence_ema = 118.6
		r.rescue = r.slot == 0
		r.afk = r.slot == 1
		r.paused = r.slot == 2
		r.cadence_stale = r.slot == 3
		r.pedal_nav = true
		r.cosmetics.assign([4, 3, 3, 1])
		r.state_t = 9999.94
		r.points = 999999
		r.fish_landed = 99
		r.furthest_x_m = 8949.9


func test_the_worst_case_fits_2_kb_of_json() -> void:
	var g := _host()
	_worst_case(g)
	var snap := g.snapshot()
	assert_eq(S.check(snap), "")
	var size := FishingSnapshot.byte_size(snap)
	gut.p("fishing worst-case 4-rider snapshot: %d bytes" % size)
	assert_gt(size, 600, "it carries everything")
	assert_lte(size, FishingConst.SNAPSHOT_MAX_BYTES)
	assert_eq((snap["C"] as Array).size(), FishingConst.CATCH_BOARD)
	assert_eq((snap["R"] as Array).size(), 4)
	for row: Array in snap["R"]:
		assert_eq(row.size(), S.R_COLUMNS)
		assert_eq((row[S.R_HINTS] as Array).size(), 3)
		assert_eq((row[S.R_MENU] as Array).size(), 5)


func test_a_json_round_trip_restores_every_carried_field() -> void:
	var host := _host()
	_worst_case(host)
	var client := _client()
	var text := _round_trip(host, client)
	assert_eq(
		JSON.stringify(client.snapshot()), text, "re-encoding the client gives the same bytes"
	)
	var b := client.state.riders[0]
	assert_eq(b.action, FishingConst.A_MENU)
	assert_almost_eq(b.x_m, 8949.9, 0.051)
	assert_eq(b.heading, -1)
	assert_almost_eq(b.v_mps, -0.29, 0.0051)
	assert_almost_eq(b.pitch_deg, 13.9, 0.051)
	assert_eq(b.menu, [0, 1, 2, FishingConst.M_DRIVE_ON, FishingConst.M_TURN] as Array[int])
	assert_eq(b.selected, 4)
	assert_eq(b.hint_count(), 3)
	assert_almost_eq(b.hints[4 * 1 + 2], 612.4, 0.051, "hint depth in dm")
	assert_eq(b.target_sp, 8)
	assert_almost_eq(b.lure_depth, 399.9, 0.051)
	assert_eq(b.pub_lo, 105)
	assert_eq(b.pub_hi, 127)
	assert_eq(b.power_w, 1234.0)
	assert_eq(b.cadence_ema, 119.0)
	assert_true(b.rescue)
	assert_true(b.pedal_nav)
	assert_true(client.state.riders[1].afk)
	assert_true(client.state.riders[2].paused)
	assert_true(client.state.riders[3].cadence_stale)
	assert_eq(b.cosmetics, [4, 3, 3, 1] as Array[int])
	assert_almost_eq(b.state_t, 9999.9, 0.001)
	assert_eq(b.points, 999999)
	assert_eq(b.fish_landed, 99)
	assert_almost_eq(b.furthest_x_m, 8949.9, 0.051)
	assert_true(client.state.roam)
	assert_eq(client.state.team_points, 9999999)
	assert_eq(client.state.team_fish, 999)
	assert_eq(client.state.hookup_level, 4)
	assert_eq(client.state.catches, host.state.catches)
	assert_eq(client.state.tick, 1234567)
	assert_almost_eq(client.state.time_left_s(), 1234.0, 1e-6)


func test_a_fight_round_trips_the_fish_and_the_meters() -> void:
	var host := _host(2)
	var r := host.state.riders[1]
	r.action = FishingConst.A_FIGHT
	r.heading = 1
	r.fish.sp = FishingConst.species_index("grouper")
	r.fish.d = 30.0
	r.fish.hook_depth_m = 400.0
	r.fish.z = 0.1
	r.fish.s = 0.5
	r.fish.run_active = true
	r.fish.replacement = true
	r.strain = 0.4
	var client := _client(2)
	var text := _round_trip(host, client)
	assert_eq(JSON.stringify(client.snapshot()), text)
	var row: Array = JSON.parse_string(text)["R"][1]
	assert_eq(int(row[S.R_FISH_DX_DM]), -300, "behind the stern of a seaward boat")
	assert_eq(int(row[S.R_FISH_DEPTH_DM]), 400)
	assert_eq(int(row[S.R_LINE_DM]), 500, "line to the fish: 30 m out, 40 m down")
	var b := client.state.riders[1]
	assert_eq(b.fish.sp, FishingConst.species_index("grouper"))
	assert_almost_eq(b.fish_dx(), -30.0, 0.051)
	assert_almost_eq(b.fish.depth_m(), 40.0, 0.051)
	assert_almost_eq(b.fish.s, 0.5, 0.5 / 255.0)
	assert_true(b.fish.run_active)
	assert_true(b.fish.replacement)
	assert_eq(int(row[S.R_SPECIES]), FishingConst.species_index("grouper"))


func test_the_declared_int_paths_cover_every_number() -> void:
	var host := _host()
	_worst_case(host)
	var parsed: Variant = JSON.parse_string(JSON.stringify(host.snapshot()))
	var fields := host.int_fields()
	assert_eq(fields["snapshot"], S.INT_PATHS)
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


func test_apply_snapshot_emits_snapshot_applied_for_the_view() -> void:
	var host := _host(2)
	var client := _client(2)
	client.snapshot_applied.connect(func(tick: int) -> void: _applied.append(tick))
	host.state.tick = 100
	_round_trip(host, client)
	host.state.tick = 102
	_round_trip(host, client)
	assert_eq(_applied, [100, 102])
	assert_eq(client.state.tick, 102)


func test_a_rejoining_client_is_restored_by_one_snapshot() -> void:
	var host := _host(3)
	var c := F.clock_for(host)
	c.run(20.0)
	var h := host.state
	h.riders[1].action = FishingConst.A_FIGHT
	h.riders[1].fish.sp = FishingConst.species_index("tuna")
	h.riders[1].fish.d = 64.3
	h.riders[1].fish.hook_depth_m = 30.0
	h.riders[1].fish.z = 0.5
	h.riders[1].strain = 0.4
	h.riders[2].action = FishingConst.A_MENU
	h.riders[2].hints.assign([0.0, 15.5, 3.0, 0.8, 1.0, 22.0, 6.0, 0.4])
	h.riders[2].menu.assign([0, 1, FishingConst.M_DRIVE_ON, FishingConst.M_TURN])
	h.riders[2].selected = 1
	h.team_points = 412
	h.catches.assign([0, 1, 25, 0])
	var text := JSON.stringify(host.snapshot())
	var late := _client(3, 3)
	assert_ne(JSON.stringify(late.snapshot()), text, "a fresh client starts elsewhere")
	late.apply_snapshot(JSON.parse_string(text))
	assert_eq(late.state.tick, h.tick)
	assert_eq(late.own_rider().action, FishingConst.A_MENU)
	assert_eq(late.own_rider().selected, 1)
	assert_eq(late.own_rider().hint_count(), 2)
	assert_eq(late.state.riders[1].fish.sp, FishingConst.species_index("tuna"))
	assert_almost_eq(late.state.riders[0].x_m, h.riders[0].x_m, 0.051, "the boats moved")
	assert_gt(late.state.riders[0].x_m, FishingRules.start_x(0))


func test_a_bad_snapshot_is_ignored_with_a_warning() -> void:
	var client := _client(2)
	var before := JSON.stringify(client.snapshot())
	client.apply_snapshot({"v": 1, "k": 5, "L": [], "T": [0, 0, 0, 0, 0], "C": []})
	client.apply_snapshot({"v": 2, "k": 5, "R": [[1, 2]], "T": [0, 0, 0, 0, 0, 0], "C": []})
	client.apply_snapshot({"v": 2, "k": 5, "R": [], "T": [0, 0, 0], "C": []})
	assert_eq(JSON.stringify(client.snapshot()), before)


func test_the_time_row_tells_mode_time_left_and_overtime() -> void:
	var host := _host(1)
	host.state.tick = 2000
	host.state.t = 100.0
	var t: Array = host.snapshot()["T"]
	assert_eq(t[S.T_MODE], S.MODE_ROAM)
	assert_eq(t[S.T_TIME_LEFT_S], 30 * 60 - 100)
	assert_eq(t[S.T_OVER], 0)
	host.state.time_up = true
	t = host.snapshot()["T"]
	assert_eq(t[S.T_TIME_LEFT_S], 0, "overtime shows no time left")
	assert_eq(t[S.T_OVER], 1)
	var client := _client(1, 1)
	_round_trip(host, client)
	assert_true(client.state.time_up)
	var w := _host(1, "e2e_2min")
	assert_eq(w.snapshot()["T"][S.T_MODE], S.MODE_WORKOUT)


func test_display_action_shows_away_and_paused_over_the_action() -> void:
	var host := _host(3)
	for r in host.state.riders:
		r.action = FishingConst.A_FIGHT
	host.state.riders[1].paused = true
	host.state.riders[2].afk = true
	host.state.riders[2].paused = true
	var rows: Array = host.snapshot()["R"]
	assert_eq(S.display_action(rows[0]), FishingConst.A_FIGHT)
	assert_eq(S.display_action(rows[1]), FishingConst.A_PAUSED)
	assert_eq(S.display_action(rows[2]), FishingConst.A_AFK, "away wins over paused")
	host.state.riders[0].p_eff_w = 300.0
	host.state.riders[0].is_bot = false
	var flags := int(host.snapshot()["R"][0][S.R_FLAGS])
	assert_ne(flags & S.F_SPRINT, 0, "120 % FTP-equivalent sprints")
