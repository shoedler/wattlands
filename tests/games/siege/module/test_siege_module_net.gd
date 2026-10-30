extends GutTest
## The module's network layer (brief 2.6; 4): snapshots as ints after a JSON round trip and under
## 8 KB at the cap, the optional rush and rack keys, a client's shop recommendation equal to the
## host's, a rejoining client, a host and client in lockstep, the teammate strip from the snapshot,
## and the interpolation history.

const K := preload("res://tests/games/siege/module/siege_module_kit.gd")
const F := preload("res://tests/games/siege/siege_fakes.gd")
const FIX := preload("res://tests/games/siege/fixtures/siege_fixtures.gd")


func _free(g: SiegeGame) -> void:
	F.free_game(g)


func _wire(d: Dictionary, paths: Array) -> Dictionary:
	return Protocol.apply_int_fields(JSON.parse_string(JSON.stringify(d)), paths)


# --- snapshots --------------------------------------------------------------------------------


func test_a_snapshot_comes_back_as_ints_after_a_json_round_trip() -> void:
	var host := K.game(3, 1, "vo2", Wl.HOST, 1)
	host.state = FIX.mid_wave(host.content)
	var snap := host.snapshot()
	var back := _wire(snap, host.int_fields()["snapshot"])
	assert_eq(JSON.stringify(back), JSON.stringify(snap), "ints stay ints through the wire")
	assert_eq(typeof(back["tick"]), TYPE_INT)
	assert_eq(typeof(back["gate"][0]), TYPE_INT)
	assert_eq(typeof(back["r"][0][5]), TYPE_INT)
	assert_eq(typeof(back["e"][0][2]), TYPE_INT)
	assert_eq(typeof(back["st"][2][3]), TYPE_INT)
	assert_eq(typeof(back["pd"][0][4]), TYPE_INT)
	assert_eq(typeof(back["tar"][1]), TYPE_INT)
	assert_eq(typeof(back["dw"][1][1]), TYPE_INT)
	var plain: Dictionary = JSON.parse_string(JSON.stringify(snap))
	var a := K.game(3, 1, "vo2", Wl.CLIENT, 2)
	var b := K.game(3, 1, "vo2", Wl.CLIENT, 2)
	a.apply_snapshot(back)
	b.apply_snapshot(plain)
	assert_eq(JSON.stringify(a.state.to_dict()), JSON.stringify(b.state.to_dict()))
	assert_eq(a.state.enemies.size(), 43)
	assert_eq(typeof(a.state.enemies[0].id), TYPE_INT)
	for g in [host, a, b]:
		_free(g)


func test_the_snapshot_has_the_brief_s_keys_and_rows() -> void:
	var snap := SiegeSnapshot.encode(FIX.mid_wave())
	assert_eq(SiegeSnapshotSchema.check(snap), "")
	assert_eq(int(snap["v"]), 2)
	for k in SiegeSnapshotSchema.KEYS:
		assert_true(snap.has(k), k)
	assert_eq((snap["st"] as Array).size(), 5)
	assert_eq((snap["pd"] as Array).size(), 2, "built pads only")
	assert_eq((snap["r"] as Array).size(), 4)
	assert_eq(snap["gate"], [72, 155, 0])
	assert_eq(int(snap["ml"]), 1)
	assert_eq(int(snap["ib"]), 1)
	assert_eq(snap["pk"], [SiegeIds.PERK_RESERVE])
	assert_eq(int(snap["q"]), 3)
	assert_eq(int(snap["gd"]), 580)
	assert_eq(snap["dw"], [[1, 360], [2, 512], [3, 96]])
	assert_eq(int(snap["rk"]), 1)


func test_station_rows_carry_wind_yaw_m_and_arm() -> void:
	var snap := SiegeSnapshot.encode(FIX.mid_wave())
	var onager: Array = snap["st"][SiegeIds.STATION_ONAGER]
	assert_eq(onager, [2, 2, 180, 14250, 96, 180])
	var ballista: Array = snap["st"][SiegeIds.STATION_BALLISTA]
	assert_eq(ballista[SiegeSnapshotSchema.ST_M_X100], 224)
	assert_eq(ballista[SiegeSnapshotSchema.ST_WIND_PM], 620)


func test_pad_tar_and_enemy_rows() -> void:
	var s := FIX.mid_wave()
	var snap := SiegeSnapshot.encode(s)
	assert_eq(snap["pd"][1], [2, SiegeIds.PAD_SCORPION, 2, 1600, 7750])
	assert_eq(snap["tar"], [2100, 800, 800, 0])
	var ram: Array = snap["e"][41]
	assert_eq(ram[SiegeSnapshotSchema.E_TYPE], SiegeIds.ENEMY_RAM)
	assert_eq(ram[SiegeSnapshotSchema.E_ST], SiegeIds.EN_BATTER)
	assert_eq(ram[SiegeSnapshotSchema.E_PROG_DM], roundi(s.path.length_m * 10.0))
	assert_eq(ram[SiegeSnapshotSchema.E_HP], 410)


func test_a_rush_rides_in_the_snapshot_and_comes_back() -> void:
	var host := K.game(2, 0, "endurance", Wl.HOST, 1)
	host.state.wave.rush_s = 12.3
	host.state.wave.rush_next = 3
	var snap := host.snapshot()
	assert_eq(snap["ru"], [1, 2, 12300])
	var client := K.game(2, 0, "endurance", Wl.CLIENT, 2)
	client.apply_snapshot(_wire(snap, client.int_fields()["snapshot"]))
	assert_true(client.state.rush_on())
	assert_eq(client.state.wave.rush_next, 3)
	host.state.wave.rush_s = 0.0
	assert_false(host.snapshot().has("ru"), "absent when off")
	client.apply_snapshot(_wire(host.snapshot(), client.int_fields()["snapshot"]))
	assert_false(client.state.rush_on())
	_free(host)
	_free(client)


func test_a_snapshot_stays_under_8_kb_at_the_enemy_cap() -> void:
	var host := K.game(3, 1, "vo2", Wl.HOST, 1)
	host.state = FIX.cap(host.content)
	assert_eq(host.state.enemies.size(), 150)
	host.state.wave.rush_s = 12.3
	var snap := host.snapshot()
	var bytes := SiegeSnapshotSchema.byte_size(snap)
	assert_lte(bytes, SiegeSnapshotSchema.MAX_BYTES, "%d bytes" % bytes)
	assert_eq(SiegeSnapshotSchema.check(snap), "")
	_free(host)


func test_check_catches_bad_snapshots() -> void:
	var snap := SiegeSnapshot.encode(FIX.mid_wave())
	var a := snap.duplicate(true)
	a.erase("tar")
	assert_eq(SiegeSnapshotSchema.check(a), "missing tar")
	var b := snap.duplicate(true)
	(b["st"] as Array).pop_back()
	assert_eq(SiegeSnapshotSchema.check(b), "st needs one row per station")
	var c := snap.duplicate(true)
	c["v"] = 1
	assert_ne(SiegeSnapshotSchema.check(c), "")
	var d := snap.duplicate(true)
	(d["e"][0] as Array).pop_back()
	assert_true(SiegeSnapshotSchema.check(d).begins_with("e:"))


func test_a_client_rebuilds_stations_pads_tar_and_enemies() -> void:
	var host := FIX.mid_wave()
	var client := SiegeState.create(host.content, FIX.slots(), Wl.FAIR_FTP, null)
	SiegeSnapshot.apply(client, JSON.parse_string(JSON.stringify(SiegeSnapshot.encode(host))))
	for id in 5:
		var h := host.station(id)
		var c := client.station(id)
		assert_eq(c.level, h.level, "station %d" % id)
		assert_almost_eq(c.wind, h.wind, 0.001)
		assert_almost_eq(c.yaw_deg, h.yaw_deg, 0.01)
		assert_almost_eq(c.m, h.m, 0.01)
		assert_almost_eq(c.arm, h.arm, 0.001)
	assert_eq(client.station(SiegeIds.STATION_ARROWS).rack, 1)
	assert_eq(client.station(SiegeIds.STATION_ONAGER).damage_wave, 512.0)
	assert_eq(client.pad(2).level, 2)
	assert_almost_eq(client.pad(2).yaw_deg, 77.5, 0.01)
	assert_false(client.pad(3).built())
	assert_almost_eq(client.tar.curtain_hp, 80.0, 0.1)
	assert_almost_eq(client.tar.cauldron_l, 210.0, 0.1)
	assert_almost_eq(client.tar.coat, 0.8, 0.001)
	assert_eq(client.tar.curtain_max, 200.0, "level 1: the curtain max follows the level")
	assert_eq(client.enemies.size(), host.enemies.size())
	for i in host.enemies.size():
		assert_lt(client.enemies[i].pos.distance_to(host.enemies[i].pos), 0.1)
		assert_eq(client.enemies[i].st, host.enemies[i].st)
	assert_eq(client.mine_level, 1)
	assert_eq(client.iron_bands, 1)
	assert_eq(client.queued(), 3)


func test_a_client_derives_od_state_from_the_clocks() -> void:
	var host := FIX.mid_wave()
	var client := SiegeState.create(host.content, FIX.slots(), Wl.FAIR_FTP, null)
	SiegeSnapshot.apply(client, SiegeSnapshot.encode(host))
	assert_eq(client.rider_at(0).od_state, SiegeIds.OD_ACTIVE)
	assert_almost_eq(client.rider_at(0).od_s, 12.0, 0.001)
	assert_eq(client.rider_at(1).od_state, SiegeIds.OD_COOLDOWN)
	assert_eq(client.rider_at(2).od_state, SiegeIds.OD_READY)
	assert_eq(client.rider_at(0).gold, 57.0, "floored")
	assert_almost_eq(client.rider_at(2).reconnect_s, 1.2, 0.001)


func _break_index(g: SiegeGame) -> int:
	for i in g.metas.size():
		if g.metas[i].get("role", "") == SiegeIds.ROLE_BREAK:
			return i
	return -1


func test_a_clients_shop_recommendation_equals_the_hosts_after_a_json_round_trip() -> void:
	var scenarios := [
		# [iron_bands, gate_hp, damage per weapon, gold, mine level]
		[0, 130.0, [0.0, 0.0, 0.0], 400.0, 0],
		[1, 64.9, [100.0, 900.0, 3.0], 400.0, 1],
		[2, 154.0, [9.0, 0.0, 2.0], 400.0, 3],
		[0, 130.0, [0.0, 12.0, 400.0], 90.0, 0],
		[1, 100.0, [0.0, 12.0, 20.0], 49.0, 2],
	]
	var seen := {}
	for sc: Array in scenarios:
		var host := K.game(2, 0, "short", Wl.HOST, 1)
		var client := K.game(2, 0, "short", Wl.CLIENT, 2)
		var brk := _break_index(host)
		var hs := host.state
		hs.phase_index = brk
		hs.role = SiegeIds.ROLE_BREAK
		hs.iron_bands = sc[0]
		hs.gate_max = 130.0 + 25.0 * int(sc[0])
		hs.gate_hp = sc[1]
		for i in 3:
			hs.station(SiegeIds.WEAPONS[i]).damage_wave = sc[2][i]
		hs.rider_at(0).gold = sc[3]
		hs.mine_level = sc[4]
		client.apply_snapshot(_wire(host.snapshot(), host.int_fields()["snapshot"]))
		var cs := client.state
		assert_true(cs.shop_open())
		var want := SiegeAutopilot.shop_picks(hs, hs.rider_at(0), 6)
		var got := SiegeAutopilot.shop_picks(cs, cs.rider_at(0), 6)
		assert_eq(got, want, "same picks for %s" % [sc])
		if not want.is_empty():
			seen[want[0]["item"]] = true
		for item: String in SiegeIds.ITEMS:
			for at in [0, 1, 2, 4]:
				assert_eq(
					SiegeShop.price(cs, item, at, at),
					SiegeShop.price(hs, item, at, at),
					"%s at %d costs the same" % [item, at]
				)
		_free(host)
		_free(client)
	assert_gt(seen.size(), 1, "the scenarios recommend more than one thing")


func test_a_client_derives_the_phase_fields_the_snapshot_leaves_out() -> void:
	var host := K.game(2, 0, "short", Wl.HOST, 1)
	var client := K.game(2, 0, "short", Wl.CLIENT, 2)
	var link := K.Link.new(host, client)
	var tick := link.run(0, 450.0)
	var cs := client.state
	assert_eq(cs.phase_index, 2)
	assert_eq(cs.role, SiegeIds.ROLE_WAVE)
	assert_eq(cs.wave_no, 1)
	assert_eq(cs.phase_kind, Wl.WORK)
	assert_eq(cs.phase_duration_s, 300.0)
	assert_almost_eq(cs.phase_remaining_s, 300.0 - (tick * Wl.SIM_DT - 420.0), 0.2)
	assert_false(cs.shop_open())
	tick = link.run(tick, 730.0)
	assert_eq(cs.role, SiegeIds.ROLE_BREAK)
	assert_eq(cs.wave_no, 1, "break 1")
	assert_true(cs.shop_open())
	_free(host)
	_free(client)


func test_a_host_and_a_client_stay_in_step_through_a_drill() -> void:
	var host := K.game(2, 1, "drill", Wl.HOST, 1)
	var client := K.game(2, 1, "drill", Wl.CLIENT, 2)
	var link := K.Link.new(host, client)
	var tick := link.run(0, 60.0)
	_assert_same(host.state, client.state)
	assert_false(client.history.is_empty())
	assert_almost_eq(client.history.newest_t(), (tick - 1) * Wl.SIM_DT, 0.001)
	tick = link.run(tick, 130.0)
	_assert_same(host.state, client.state)
	assert_eq(client.state.role, SiegeIds.ROLE_COOLDOWN)
	assert_true(client.victory_march())
	var types: Array = []
	for e in link.sent:
		types.append(e["type"])
	assert_true(types.has(SiegeIds.EV_WAVE_START))
	assert_true(types.has(SiegeIds.EV_WAVE_END))
	assert_true(types.has(SiegeIds.EV_SHOT))
	var late := K.game(2, 1, "drill", Wl.CLIENT, 2)
	late.apply_snapshot(_wire(host.snapshot(), host.int_fields()["snapshot"]))
	_assert_same(host.state, late.state)
	for g in [host, client, late]:
		_free(g)


func _assert_same(h: SiegeState, c: SiegeState) -> void:
	assert_eq(c.phase_index, h.phase_index)
	assert_eq(c.role, h.role)
	assert_eq(c.gate_hp, ceilf(h.gate_hp))
	assert_eq(c.breaches, h.breaches)
	assert_eq(c.mine_level, h.mine_level)
	assert_eq(c.enemies.size(), h.enemies.size())
	for i in h.enemies.size():
		assert_eq(c.enemies[i].id, h.enemies[i].id)
	for hr in h.riders:
		var cr := c.rider_at(hr.slot)
		assert_eq(cr.target, hr.target, "slot %d target" % hr.slot)
		assert_eq(cr.od_state, hr.od_state if hr.od_state != SiegeIds.OD_PENDING else 0)
		assert_eq(int(cr.gold), floori(hr.gold), "slot %d gold" % hr.slot)
		assert_eq(cr.afk, hr.afk)
	for n in range(1, SiegeIds.PAD_COUNT + 1):
		assert_eq(c.pad(n).type, h.pad(n).type, "pad %d" % n)
		assert_eq(c.pad(n).level, h.pad(n).level)
	for id in 5:
		assert_eq(c.station(id).level, h.station(id).level)


var _shots: Array[Dictionary] = []


func _on_event(e: Dictionary) -> void:
	if e["type"] == SiegeIds.EV_SHOT:
		_shots.append(e)


func test_shot_events_replay_identically_on_two_clients() -> void:
	var host := K.game(1, 0, "drill", Wl.HOST, 1)
	_shots = []
	host.game_event.connect(_on_event)
	K.run_to(host, 0, 70.0)
	assert_gt(_shots.size(), 0)
	var fields: Array = host.int_fields()[SiegeIds.EV_SHOT]
	for e in _shots:
		var a := SiegeEvents.cast(_wire(e, fields))
		var b := SiegeEvents.cast(_wire(e, fields))
		var src := int(a["src"])
		var def := (
			host.content.station_def(src)
			if src < SiegeIds.SRC_PAD
			else host.content.pad_def(SiegeIds.PAD_SCORPION)
		)
		var va := SiegeBallistics.shot_velocities(
			SiegeEvents.shot_velocity(a),
			int(a["n"]),
			int(a["sd"]),
			float(def["spread_deg"]),
			float(def["speed_spread"])
		)
		var vb := SiegeBallistics.shot_velocities(
			SiegeEvents.shot_velocity(b),
			int(b["n"]),
			int(b["sd"]),
			float(def["spread_deg"]),
			float(def["speed_spread"])
		)
		assert_eq(va, vb)
	_free(host)


# --- the cadence band -------------------------------------------------------------------------


func test_the_host_publishes_the_cadence_band_once_for_every_rider() -> void:
	var g := K.game(2, 1, "short", Wl.HOST, 1)
	K.run_to(g, 0, 2.0)
	var bands: Array = (g.ctx.directives as F.Directives).cadence_bands
	assert_eq(bands.size(), 3, "two humans and a bot, once")
	for b: Array in bands:
		assert_eq(b[1], float(SiegeHudModel.CADENCE_LO))
		assert_eq(b[2], float(SiegeHudModel.CADENCE_HI))
	assert_eq((g.ctx.directives as F.Directives).requests, [], "it asks for no load")
	_free(g)


func test_a_client_publishes_no_band() -> void:
	var client := K.game(3, 1, "vo2", Wl.CLIENT, 2)
	client.apply_snapshot(_wire(FIX.snapshot(), client.int_fields()["snapshot"]))
	assert_eq((client.ctx.directives as F.Directives).cadence_bands, [])
	_free(client)


# --- the interpolation history ----------------------------------------------------------------


func _enemy(id: int, prog: float, lat: float = 0.0) -> SiegeEnemyState:
	var e := SiegeEnemyState.new()
	e.id = id
	e.prog_m = prog
	e.lat_m = lat
	return e


func _push(h: SiegeSnapHistory, t: float, prog: float) -> void:
	var list: Array[SiegeEnemyState] = [_enemy(1, prog), _enemy(2, prog * 2.0, 1.0)]
	h.push(t, list)


func test_the_history_interpolates_path_progress_and_never_extrapolates() -> void:
	var h := SiegeSnapHistory.new(FIX.content("short").path)
	_push(h, 1.0, 10.0)
	_push(h, 1.1, 20.0)
	assert_almost_eq(h.state_at(1, 1.05)[0], 15.0, 0.001)
	assert_almost_eq(h.state_at(1, 0.5)[0], 10.0, 0.001, "before the oldest: the oldest")
	assert_almost_eq(h.state_at(1, 5.0)[0], 20.0, 0.001, "after the newest: the newest")
	assert_eq(h.state_at(99, 1.05).size(), 0, "not in the history")
	assert_almost_eq(h.state_at(2, 1.05)[1], 1.0, 0.001, "lateral offset")
	h.render_t = 1.05
	assert_almost_eq(h.prog_of(1, -1.0), 15.0, 0.001)
	assert_almost_eq(h.lat_of(2, -1.0), 1.0, 0.001)
	assert_eq(h.prog_of(99, -1.0), -1.0)
	assert_true(h.pos_of(1, Vector3.ZERO).distance_to(h.path.point_at(15.0, 0.0)) < 0.01)
	assert_eq(h.pos_of(99, Vector3(7, 7, 7)), Vector3(7, 7, 7))


func test_the_render_clock_runs_behind_by_the_mean_spacing_and_never_back_or_past() -> void:
	var h := SiegeSnapHistory.new()
	for i in 6:
		_push(h, 1.0 + 0.1 * i, 10.0 * i)
	assert_almost_eq(h.mean_spacing(), 0.1, 1e-6)
	assert_almost_eq(h.delay(), 0.1, 1e-6)
	h.advance(0.0)
	assert_almost_eq(h.render_t, 1.4, 1e-6, "newest 1.5 minus 0.1")
	var last := h.render_t
	for i in 200:
		h.advance(0.016)
		assert_gte(h.render_t, last, "never backwards")
		assert_lte(h.render_t, h.newest_t() + 1e-9, "never past the newest snapshot")
		last = h.render_t
	assert_almost_eq(h.render_t, 1.5, 1e-6, "waits at the newest when none arrives")
	for i in 5:
		_push(h, 2.5 + 1.0 * i, 0.0)
	assert_gt(h.delay(), 0.5)
	var before := h.render_t
	h.advance(0.016)
	assert_gte(h.render_t, before, "a growing delay leaves the clock where it is")


func test_the_history_starts_over_after_a_gap_or_a_new_session() -> void:
	var h := SiegeSnapHistory.new()
	_push(h, 1.0, 1.0)
	_push(h, 1.1, 2.0)
	_push(h, 1.1, 3.0)
	assert_eq(h.entries.size(), 2, "the same time replaces")
	_push(h, 5.0, 4.0)
	assert_eq(h.entries.size(), 1, "a gap over 1.5 s starts over")
	_push(h, 0.2, 5.0)
	assert_eq(h.entries.size(), 1, "the host clock went back")
	for i in 20:
		_push(h, 0.3 + 0.1 * i, 1.0)
	assert_eq(h.entries.size(), SiegeSnapHistory.CAPACITY)
	h.clear()
	assert_true(h.is_empty())


func test_a_client_fills_its_history_from_snapshots() -> void:
	var client := K.game(3, 1, "vo2", Wl.CLIENT, 2)
	var snap := _wire(FIX.snapshot(), client.int_fields()["snapshot"])
	client.apply_snapshot(snap)
	snap["tick"] = int(snap["tick"]) + 2
	snap["e"][0][SiegeSnapshotSchema.E_PROG_DM] = (
		int(snap["e"][0][SiegeSnapshotSchema.E_PROG_DM]) + 10
	)
	client.apply_snapshot(snap)
	assert_eq(client.history.entries.size(), 2)
	var id := int(snap["e"][0][0])
	var t0 := client.history.newest_t() - 0.1
	var a := client.history.state_at(id, t0)[0]
	var b := client.history.state_at(id, t0 + 0.1)[0]
	assert_almost_eq(b - a, 1.0, 0.001)
	assert_almost_eq(client.history.state_at(id, t0 + 0.05)[0], a + 0.5, 0.001)
	_free(client)
