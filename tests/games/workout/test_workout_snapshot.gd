extends GutTest
## Snapshots and events (BRIEF 3.6): determinism (same inputs, same snapshots), JSON round
## trips with int_fields, clients applying snapshots and events and predicting their own
## marker.

const U := preload("res://tests/games/workout/workout_test_util.gd")


## Rides `content` with 3 riders for `ticks` steps and returns every snapshot (every
## second tick, as the host sends them) as JSON text.
func _snapshots(content: String, ticks: int) -> Array[String]:
	var g := U.game(content, U.players(2, 1, 210.0))
	var out: Array[String] = []
	var timeline := g.state.phases
	var starts := U.phase_ticks(timeline)
	for tick in ticks:
		var frame := InputFrame.new()
		frame.tick = tick
		frame.t = float(tick) * U.DT
		for slot in g.ctx.players:
			var ps := U.phase_state(timeline, starts, tick)
			var v := U.compliant(slot, timeline[ps.index], ps)
			# Some per-rider variety.
			v["power_w"] = float(v["power_w"]) * (1.0 + 0.03 * float(slot.slot_index)) + float(tick % 7)
			frame.players[slot.peer_id] = U.telemetry(slot, v, tick)
			frame.phase[slot.peer_id] = ps
		g.sim_step(U.DT, frame)
		if tick % 2 == 1:
			out.append(JSON.stringify(g.snapshot()))
	g.free()
	return out


func test_same_inputs_same_snapshots() -> void:
	var a := _snapshots("easy_30", 15000)
	var b := _snapshots("easy_30", 15000)
	assert_eq(a.size(), 7500)
	assert_eq(a, b, "deterministic")
	assert_ne(a[100], a[200], "the state moves")


func test_snapshot_shape_and_size() -> void:
	var g := U.game("rolling_road", U.players(4, 4))
	U.ride(g, Callable(), 7000)
	var snap := g.snapshot()
	assert_true(snap.has("tl"), "the first snapshot carries the timeline")
	var second := g.snapshot()
	assert_false(second.has("tl"))
	assert_eq((snap["r"] as Array).size(), 8)
	assert_lt(JSON.stringify(snap).to_utf8_buffer().size(), 2048, "small")
	assert_lt(JSON.stringify(second).to_utf8_buffer().size(), 1024)
	g.free()


func test_every_number_is_an_int_and_declared() -> void:
	var g := U.game("rolling_road", U.players(2, 1))
	U.ride(g, Callable(), 6500)
	var snap := g.snapshot()
	_assert_all_ints(snap, "snapshot")
	var parsed: Variant = JSON.parse_string(JSON.stringify(snap))
	var fixed: Variant = U.apply_int_fields(parsed, g.int_fields()["snapshot"])
	_assert_all_ints(fixed, "decoded snapshot")
	assert_eq(JSON.stringify(fixed), JSON.stringify(snap), "exact round trip through the declared paths")
	g.free()


func test_events_round_trip_with_int_fields() -> void:
	var g := U.game("easy_30", U.players(2, 1))
	var events := U.ride(g)
	var fields := g.int_fields()
	for type: String in [WorkoutRules.EV_INTERVAL_START, WorkoutRules.EV_INTERVAL_END, WorkoutRules.EV_SPRINT]:
		var some := U.of_type(events, type)
		assert_false(some.is_empty(), type)
		for e in some:
			var back: Variant = U.apply_int_fields(JSON.parse_string(JSON.stringify(e)), fields[type])
			assert_eq(JSON.stringify(back), JSON.stringify(e), "%s round trip" % type)
	g.free()


func test_event_order() -> void:
	var g := U.game("vo2", U.players(1))
	var events := U.ride(g)
	var types: Array[String] = []
	for e in events:
		types.append(str(e["type"]))
	# 10 game phases + cool-down: 11 starts, 10 ends.
	assert_eq(U.of_type(events, WorkoutRules.EV_INTERVAL_START).size(), 11)
	assert_eq(U.of_type(events, WorkoutRules.EV_INTERVAL_END).size(), 10)
	assert_eq(types[0], WorkoutRules.EV_INTERVAL_START)
	assert_eq(types[1], WorkoutRules.EV_INTERVAL_END)
	assert_eq(int(events[1]["i"]), 0)
	assert_eq(int(events[2]["i"]), 1)
	assert_eq(events[1]["r"], [[1, 1000]], "interval 0 fully in band")
	g.free()


func test_client_applies_snapshots_and_events() -> void:
	var players := U.players(2, 1)
	var host := U.game("rolling_road", players)
	U.ride(host, Callable(), 8000)
	var snap: Variant = JSON.parse_string(JSON.stringify(host.snapshot()))
	snap = U.apply_int_fields(snap, host.int_fields()["snapshot"])
	var client := U.game("rolling_road", players, Wl.CLIENT, 2)
	client.apply_snapshot(snap)
	for peer: int in host.state.order:
		var h := host.state.rider(peer)
		var c := client.state.rider(peer)
		assert_almost_eq(c.distance_m(), h.distance_m(), 0.05, "distance of %d" % peer)
		assert_almost_eq(c.speed_mps(), h.speed_mps(), 0.01)
		assert_almost_eq(c.course_d, h.course_d, 0.05)
		assert_eq(c.in_band, h.in_band)
		assert_eq(c.snap_tib_permille, int(round(h.tib_fraction() * 1000.0)))
	assert_eq(client.state.phase_index, host.state.phase_index)
	assert_almost_eq(client.state.plan_t, host.state.plan_t, 0.051)
	var hud: U.FakeHud = client.ctx.hud
	assert_eq(hud.of("readout").back()["id"], WorkoutHud.READOUT_TIB, "the client's own in-band readout")
	# Prediction moves only the local marker.
	var before := client.state.rider(2).distance_m()
	var other := client.state.rider(1).distance_m()
	var local := Telemetry.new()
	local.p_eff_w = 250.0
	for i in 2:
		client.client_predict(U.DT, local)
	assert_gt(client.state.rider(2).distance_m(), before)
	assert_eq(client.state.rider(1).distance_m(), other)
	# Events.
	client.apply_event({"type": WorkoutRules.EV_INTERVAL_END, "i": 0, "r": [[1, 990]]})
	assert_eq(client.state.last_interval["r"], [[1, 990]])
	client.apply_event({"type": WorkoutRules.EV_SPRINT, "i": 2, "r": [[1, 300, 50, 1]]})
	assert_eq(int(client.state.last_sprint["i"]), 2)
	client.apply_event({"type": WorkoutRules.EV_INTERVAL_START, "i": 3})
	assert_eq(client.state.phase_index, 3)
	host.free()
	client.free()


func test_client_gets_the_timeline_from_snapshots() -> void:
	var players := U.players(2)
	var host := U.game("threshold", players)
	U.ride(host, Callable(), 20)
	var client := U.game("threshold", players, Wl.CLIENT, 2)
	var empty: Array[PlanPhase] = []
	client.state.set_timeline(empty)
	client.apply_snapshot(host.snapshot())
	assert_eq(client.state.phases.size(), host.state.phases.size())
	for i in host.state.phases.size():
		assert_eq(client.state.phases[i].to_dict(), host.state.phases[i].to_dict())
	host.free()
	client.free()


func _assert_all_ints(v: Variant, where: String) -> void:
	if v is Dictionary:
		for k: Variant in v.keys():
			if str(k) == "tll":
				continue
			_assert_all_ints(v[k], "%s.%s" % [where, k])
	elif v is Array:
		for i in (v as Array).size():
			_assert_all_ints(v[i], "%s[%d]" % [where, i])
	elif v is float:
		fail_test("%s is a float (%s)" % [where, v])
	elif not (v is int or v is String or v is bool):
		fail_test("%s has type %d" % [where, typeof(v)])


## W3 NET-3: a long imported timeline (403 phases) never makes a snapshot over the relay's
## 16 KB limit: it travels in parts on consecutive snapshots, and a client that cannot read the
## .zwo itself rebuilds the whole timeline from them (Protocol's int_fields included).
func test_a_long_timeline_goes_in_parts_under_16_kb() -> void:
	var players := U.players(2)
	var host := U.game("threshold", players)
	var long: Array[PlanPhase] = [PlanPhase.erg(Wl.WARMUP, 50.0, 300.0, "Warm-up").with_ramp(65.0).with_lap()]
	for i in 200:
		# Labels like the importer's ("Intervals 7/200: on, 30 s at 100%").
		long.append(PlanPhase.erg(Wl.WORK, 100.0, 30.0, "Intervals %d/200: on, 30 s at 100%%" % (i + 1)).with_lap())
		long.append(PlanPhase.erg(Wl.RECOVERY, 50.0, 30.0, "Intervals %d/200: off, 30 s at 50%%" % (i + 1)).with_lap())
	long.append(PlanValidator.cooldown_phase())
	host.state.set_timeline(long)
	var parts := WorkoutSnapshot.timeline_parts(long)
	assert_eq(parts, 4, "403 phases in parts of %d" % WorkoutSnapshot.TIMELINE_PART_PHASES)
	assert_gt(JSON.stringify(WorkoutSnapshot.encode_timeline(long)).to_utf8_buffer().size(), NetMessages.MAX_MESSAGE_BYTES,
		"precondition: the whole timeline alone is over 16 KB")
	var client := U.game("threshold", players, Wl.CLIENT, 2)
	var empty: Array[PlanPhase] = []
	client.state.set_timeline(empty)
	var paths: Array = host.int_fields()["snapshot"]
	for k in WorkoutGame.TIMELINE_EVERY:
		var snap := host.snapshot()
		var wire := Protocol.encode(Protocol.game_msg("snapshot", {"game_id": "workout", "seq": k + 1, "tick": k, "state": snap}))
		assert_lt(wire.to_utf8_buffer().size() + 32, NetMessages.MAX_MESSAGE_BYTES, "snapshot %d fits one relay frame" % k)
		assert_eq(snap.has("tl"), k < parts, "snapshot %d carries a timeline part" % k)
		var back: Variant = Protocol.apply_int_fields(JSON.parse_string(JSON.stringify(snap)), paths)
		if k < parts - 1:
			client.apply_snapshot(back)
			assert_eq(client.state.phases.size(), 0, "no timeline before every part is in")
		else:
			client.apply_snapshot(back)
	assert_eq(client.state.phases.size(), long.size(), "the client has the whole timeline")
	for i in long.size():
		assert_eq(client.state.phases[i].to_dict(), long[i].to_dict(), "phase %d" % i)
	host.free()
	client.free()
