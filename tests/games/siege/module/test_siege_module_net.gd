extends GutTest
## The module's network layer (brief 2.6): snapshots as ints after a JSON round trip and under
## 8 KB at the cap, the optional roads and rush keys, a rejoining client, a host and client in
## lockstep, the teammate strip from the snapshot, and the interpolation history.

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
	assert_eq(typeof(back["e"][0][3]), TYPE_INT)
	assert_eq(typeof(back["f"][1][1][0]), TYPE_INT, "shot target ids too (f[][][])")
	# Without int_fields the client's own int() casts give the same state.
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


func test_a_snapshot_stays_under_8_kb_at_the_enemy_cap_with_every_key() -> void:
	var host := K.game(3, 1, "vo2", Wl.HOST, 1)
	host.state = FIX.cap(host.content)
	assert_eq(host.state.enemies.size(), 150)
	var plain := host.snapshot()
	assert_false(plain.has("ro") or plain.has("ru"), "the common snapshot is the brief's")
	host.state.wave.active_roads = [1] as Array[int]
	host.state.wave.rush_s = 12.3
	host.state.wave.rush_next = 3
	var snap := host.snapshot()
	assert_eq(snap["ro"], [1])
	assert_eq(snap["ru"], [1, 2, 12300])
	var bytes := SiegeSnapshotSchema.byte_size(snap)
	assert_lte(bytes, SiegeSnapshotSchema.MAX_BYTES, "%d bytes" % bytes)
	assert_eq(SiegeSnapshotSchema.check(snap), "")
	_free(host)


func test_the_active_roads_and_the_rush_ride_in_the_snapshot_for_a_rejoin() -> void:
	var host := K.game(2, 0, "short", Wl.HOST, 1)
	host.state.wave.active_roads = [2, 0] as Array[int]
	host.state.wave.rush_s = 20.0
	host.state.wave.rush_next = 2
	var snap := _wire(host.snapshot(), host.int_fields()["snapshot"])
	var rejoined := K.game(2, 0, "short", Wl.CLIENT, 2)
	rejoined.apply_snapshot(snap)
	assert_eq(rejoined.state.wave.active_roads, [2, 0], "known without waiting for an event")
	assert_true(rejoined.state.rush_on())
	assert_almost_eq(rejoined.state.wave.rush_s, 20.0, 0.001)
	assert_eq(rejoined.state.wave.rush_next, 2)
	# All three roads and no rush need no key and restore the defaults.
	host.state.wave.active_roads = [0, 1, 2] as Array[int]
	host.state.wave.rush_s = 0.0
	var plain := host.snapshot()
	assert_false(plain.has("ro") or plain.has("ru"))
	rejoined.apply_snapshot(plain)
	assert_eq(rejoined.state.wave.active_roads, [0, 1, 2])
	assert_false(rejoined.state.rush_on())
	_free(host)
	_free(rejoined)


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
	# Someone joining late (a restarted client) catches up from one snapshot.
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
	assert_eq(c.gen_level, h.gen_level)
	assert_eq(c.wave.active_roads, h.wave.active_roads)
	assert_eq(c.enemies.size(), h.enemies.size())
	for i in h.enemies.size():
		assert_eq(c.enemies[i].id, h.enemies[i].id)
	for hr in h.riders:
		var cr := c.rider_at(hr.slot)
		assert_eq(cr.target, hr.target, "slot %d target" % hr.slot)
		assert_eq(cr.od_state, hr.od_state if hr.od_state != SiegeIds.OD_PENDING else 0)
		assert_eq(int(cr.denarii), floori(hr.denarii), "slot %d denarii" % hr.slot)
		assert_eq(cr.afk, hr.afk)
	for n in range(1, SiegeIds.PAD_COUNT + 1):
		assert_eq(c.pad(n).type, h.pad(n).type, "pad %d" % n)
		assert_eq(c.pad(n).level, h.pad(n).level)


# --- the teammate strip -----------------------------------------------------------------------


func test_a_clients_teammate_strip_comes_from_the_snapshot() -> void:
	var client := K.game(3, 1, "vo2", Wl.CLIENT, 2)
	client.apply_snapshot(_wire(FIX.snapshot(), client.int_fields()["snapshot"]))
	var strip := client.teammate_strip()
	assert_eq(strip.size(), 4)
	# Fixture: raw 240 / 110 / 252 / 250 W on FTP 200 / 220 / 240 / 260 (slot FTPs on every peer).
	var raw := [240, 110, 252, 250]
	var pct := [120, 50, 105, 96]
	for i in 4:
		assert_eq(strip[i]["slot"], i)
		assert_eq(strip[i]["raw_w"], raw[i], "slot %d raw W from the snapshot" % i)
		assert_eq(strip[i]["ftp_pct"], pct[i], "slot %d %%FTP" % i)
	assert_eq(strip[0]["target"], 3)
	assert_true(strip[0]["od"], "slot 0 is in Overdrive")
	assert_ne(strip[0]["marker"], "")
	assert_eq(strip[1]["target"], SiegeIds.TARGET_GEN)
	assert_true(strip[1]["rescue"])
	assert_eq(strip[1]["marker"], "")
	assert_eq(strip[3]["name"], "Bot 1")
	assert_true(strip[3]["is_bot"])
	assert_ne(strip[0]["color"], strip[1]["color"], "each rider keeps the slot colour")
	assert_ne(strip[0]["pattern"], strip[1]["pattern"], "and pattern")
	_free(client)


func test_the_host_feeds_the_teammate_chips_with_target_and_overdrive() -> void:
	var g := K.game(2, 0, "short", Wl.HOST, 1)
	var tick := K.run_to(g, 0, 430.0)
	g.state.rider(2).target = 3
	K.step(g, tick, {1: [SiegeIntents.overdrive("action")]})
	K.step(g, tick + 1)
	K.step(g, tick + 2)
	var chips := {}
	for c: Array in K.hud(g).of("teammate_status"):
		chips[c[1]] = c[2]
	assert_true(chips.has(1) and chips.has(2))
	for peer: int in chips:
		var chip: Dictionary = chips[peer]
		assert_eq(chip.keys().size(), 3)
		assert_true(chip.has("in_band") and chip.has("icon") and chip.has("text"))
	assert_true(str(chips[1]["text"]).contains("OD"), "the Overdrive marker")
	assert_false(str(chips[2]["text"]).contains("OD"))
	_free(g)


# --- the interpolation history ----------------------------------------------------------------


func _enemy(id: int, prog: float, lat: float = 0.0, road: int = 1) -> SiegeEnemyState:
	var e := SiegeEnemyState.new()
	e.id = id
	e.road = road
	e.prog_m = prog
	e.lat_m = lat
	return e


func _push(h: SiegeSnapHistory, t: float, prog: float) -> void:
	var list: Array[SiegeEnemyState] = [_enemy(1, prog), _enemy(2, prog * 2.0, 1.0, 0)]
	h.push(t, list)


func test_the_history_interpolates_road_progress_and_never_extrapolates() -> void:
	var h := SiegeSnapHistory.new(FIX.content("short").map)
	_push(h, 1.0, 10.0)
	_push(h, 1.1, 20.0)
	assert_almost_eq(h.state_at(1, 1.05)[1], 15.0, 0.001)
	assert_almost_eq(h.state_at(1, 0.5)[1], 10.0, 0.001, "before the oldest: the oldest")
	assert_almost_eq(h.state_at(1, 5.0)[1], 20.0, 0.001, "after the newest: the newest")
	assert_eq(h.state_at(99, 1.05).size(), 0, "not in the history")
	assert_almost_eq(h.state_at(2, 1.05)[2], 1.0, 0.001, "lateral offset")
	h.render_t = 1.05
	assert_almost_eq(h.prog_of(1, -1.0), 15.0, 0.001)
	assert_eq(h.prog_of(99, -1.0), -1.0)
	var map := h.map
	assert_true(h.pos_of(1, Vector2.ZERO).distance_to(map.point_at(1, 15.0, 0.0)) < 0.01)
	assert_eq(h.pos_of(99, Vector2(7, 7)), Vector2(7, 7))


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
	# Snapshots a second apart (the 8-rider load): the delay grows to match, nothing jumps back.
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
	snap["e"][0][3] = int(snap["e"][0][3]) + 10
	client.apply_snapshot(snap)
	assert_eq(client.history.entries.size(), 2)
	var id := int(snap["e"][0][0])
	var t0 := client.history.newest_t() - 0.1
	var a := client.history.state_at(id, t0)[1]
	var b := client.history.state_at(id, t0 + 0.1)[1]
	assert_almost_eq(b - a, 1.0, 0.001)
	assert_almost_eq(client.history.state_at(id, t0 + 0.05)[1], a + 0.5, 0.001)
	_free(client)
