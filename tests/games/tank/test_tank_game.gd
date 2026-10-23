extends GutTest
## TankGame driven directly with synthetic InputFrames and recording sinks (TankFakes):
## plans, directives, HUD feed, intents, signals, snapshots, events, results and progress.

const F := preload("res://tests/games/tank/tank_fakes.gd")


func _game(ctx: GameContext) -> TankGame:
	return autofree(F.make_game(ctx))


func _dirs(ctx: GameContext) -> F.Directives:
	return ctx.directives as F.Directives


func _hud(ctx: GameContext) -> F.Hud:
	return ctx.hud as F.Hud


func _phases_dict(plan: EffortPlan) -> Array:
	var out: Array = []
	for p in plan.phases:
		out.append(p.to_dict())
	return out


func test_configure_builds_one_rider_per_slot_from_content() -> void:
	var ctx := F.make_ctx(2, 1)
	var g := _game(ctx)
	assert_false(g.content.is_empty())
	assert_eq(g.state["riders"].size(), 3)
	assert_eq(g.state["riders"].map(func(r: Dictionary) -> int: return r["peer"]), [1, 2, -1])
	assert_eq(g.state["track_m"], 400.0)
	for rd: Dictionary in g.state["riders"]:
		assert_between(float(rd["dist_m"]), 0.0, 2.0, "seeded start spread from ctx.rng")


func test_the_track_option_sets_the_track_length() -> void:
	var ctx := F.make_ctx()
	ctx.options["track"] = 800
	assert_eq(_game(ctx).state["track_m"], 800.0)


func test_bad_content_is_rejected_at_load_and_gives_no_plans() -> void:
	var ctx := F.make_ctx(1, 0, "no_such_content")
	var g := _game(ctx)
	assert_push_error("missing content")
	assert_push_error("content no_such_content")
	assert_eq(g.build_effort_plans(), {})


func test_content_overrides_reach_the_game_and_are_validated() -> void:
	var ctx := F.make_ctx()
	ctx.content_overrides = {"default.json": {"nudge_pct": 4, "mps_per_w": 0.05}}  # run_game_sim --override
	var g := _game(ctx)
	assert_eq(float(g.content["nudge_pct"]), 4.0)
	assert_eq(float(g.state["mps_per_w"]), 0.05)
	assert_eq(g.build_effort_plans()[1].phase(1).range_pct, [75.0, 79.0])
	var bad := F.make_ctx()
	bad.content_overrides = {
		"default.json":
		{"phases": [{"kind": "COOLDOWN", "target_pct": 50, "duration_s": 180, "label": "x"}]}
	}
	var g2 := _game(bad)
	assert_push_error("never COOLDOWN")
	assert_eq(
		g2.build_effort_plans(), {}, "a game never writes the cool-down; bad content gives no plans"
	)


func test_one_plan_per_slot_bots_included() -> void:
	var ctx := F.make_ctx(2, 2)
	var plans := _game(ctx).build_effort_plans()
	assert_eq(plans.keys(), [1, 2, -1, -2])
	for peer: int in plans:
		var plan: EffortPlan = plans[peer]
		assert_eq(plan.size(), 2)
		var warm := plan.phase(0)
		assert_eq(
			[warm.kind, warm.mode, warm.target_pct, warm.ramp_to_pct, warm.duration_s, warm.lap],
			[Wl.WARMUP, Wl.ERG, 50.0, 65.0, 300.0, true]
		)
		var work := plan.phase(1)
		assert_eq(
			[work.kind, work.mode, work.target_pct, work.duration_s, work.lap],
			[Wl.WORK, Wl.ERG, 75.0, 180.0, true]
		)
		assert_eq(work.range_pct, [75.0, 80.0], "the +5% hill fits inside range_pct")
		assert_eq([warm.label, work.label], ["TANK_PHASE_WARMUP", "TANK_PHASE_WORK"])
		assert_false(
			plan.cooldown_appended, "the PlanValidator appends the cool-down, never the game"
		)


func test_work_offset_moves_only_work_targets_and_is_clamped() -> void:
	var ctx := F.make_ctx(4)
	var offsets := [-10, 5, 20, -50]
	for i in 4:
		ctx.players[i].options["work_offset"] = offsets[i]
	var plans := _game(ctx).build_effort_plans()
	var expect := [
		[65.0, [65.0, 70.0]], [80.0, [80.0, 85.0]], [80.0, [80.0, 85.0]], [65.0, [65.0, 70.0]]
	]
	for i in 4:
		var plan: EffortPlan = plans[i + 1]
		assert_eq(
			[plan.phase(1).target_pct, plan.phase(1).range_pct], expect[i], "offset %d" % offsets[i]
		)
		assert_eq(plan.phase(0).target_pct, 50.0, "warm-up targets never move")


func test_every_content_and_offset_keeps_the_warmup_and_long_phase_limits() -> void:
	for content_id: String in F.manifest()["contents"]:
		for offset: int in [-10, 0, 5]:
			var ctx := F.make_ctx(1, 0, content_id)
			ctx.players[0].options["work_offset"] = offset
			var plan: EffortPlan = _game(ctx).build_effort_plans()[1]
			var start := 0.0
			for p in plan.phases:
				var where := "%s offset %d phase %s" % [content_id, offset, p.label]
				assert_ne(p.kind, Wl.COOLDOWN, where)
				assert_true(p.lap, where)
				if start < PlanValidator.WARMUP_S:
					assert_lte(p.peak_pct(), PlanValidator.WARMUP_MAX_PCT, where + ": BRIEF 4.6.8")
				assert_lte(
					p.peak_pct(),
					PlanValidator.LONG_PHASE_CAP_PCT if p.worst_case_length_s() > 300.0 else 150.0,
					where
				)
				assert_gt(p.duration_s, 0.0, where)
				start += p.duration_s


func test_a_full_session_sends_exactly_one_hill_per_rider_and_nothing_in_the_cooldown() -> void:
	var ctx := F.make_ctx(2, 1)
	var g := _game(ctx)
	watch_signals(g)
	var plans := F.plans_of(g)
	var tick := F.run(g, plans, 0, 359.9)
	assert_eq(_dirs(ctx).requests, [], "nothing before WORK elapsed 60 s")
	tick = F.run(g, plans, tick, 0.2)
	var expected: Array = []
	for peer: int in [1, 2, -1]:
		expected.append(
			[peer, {"target_pct": 80.0, "duration_s": 30.0, "reason": "hill", "source": "tank"}]
		)
	assert_eq(_dirs(ctx).requests, expected, "exactly the fields the game sets, once per rider")
	assert_eq(_dirs(ctx).cadence_bands, [[1, 80.0, 100.0], [2, 80.0, 100.0], [-1, 80.0, 100.0]])
	var bands := _hud(ctx).of("power_band")
	assert_eq(bands.size(), 3)
	assert_eq(bands[0], ["power_band", 1, 140.0, 160.0])
	tick = F.run(g, plans, tick, 125.0)  # into the cool-down (starts at 480 s)
	assert_signal_emit_count(g, "lap_marker", 1)
	assert_signal_emitted_with_parameters(g, "lap_marker", ["TANK_LAP_HALFWAY"])
	assert_signal_emit_count(g, "finished", 1)
	assert_signal_emitted_with_parameters(g, "finished", ["complete"])
	var requests_before := _dirs(ctx).requests.size()
	var bands_before := _dirs(ctx).cadence_bands.size()
	F.run(g, plans, tick, 120.0)
	assert_eq(_dirs(ctx).requests.size(), requests_before, "no directive in the cool-down")
	assert_eq(_dirs(ctx).cadence_bands.size(), bands_before, "no band in the cool-down")
	assert_signal_emit_count(g, "finished", 1, "finished is emitted once")
	assert_signal_emit_count(g, "phase_changed", 3)
	assert_eq(get_signal_parameters(g, "phase_changed", 2), [2])
	assert_gt(int(g.state["riders"][0]["laps"]), 3, "markers keep riding home in the cool-down")


func test_every_work_phase_gets_its_own_hill_and_lap_marker() -> void:
	var ctx := F.make_ctx(1)
	var warm := {
		"kind": "WARMUP",
		"target_pct": 50,
		"ramp_to_pct": 65,
		"duration_s": 300,
		"label": "TANK_PHASE_WARMUP"
	}
	var work := {"kind": "WORK", "target_pct": 75, "duration_s": 180, "label": "TANK_PHASE_WORK"}
	ctx.content_overrides = {"default.json": {"phases": [warm, work, work]}}
	var g := _game(ctx)
	watch_signals(g)
	F.run(g, F.plans_of(g), 0, 670.0)
	assert_eq(_dirs(ctx).requests.size(), 2, "one hill in each WORK phase")
	assert_eq(
		_dirs(ctx).requests.map(func(r: Array) -> float: return r[1]["target_pct"]), [80.0, 80.0]
	)
	assert_signal_emit_count(g, "lap_marker", 2)


func test_teammate_status_once_per_second_with_in_band() -> void:
	var ctx := F.make_ctx(1)
	var g := _game(ctx)
	var plans := F.plans_of(g)
	F.run(g, plans, 0, 2.0)
	var st := _hud(ctx).of("teammate_status")
	assert_eq(st.size(), 2)
	assert_eq(st[0][1], 1)
	assert_true(st[0][2]["in_band"])
	assert_eq(st[0][2]["text"], ctx.strings.t("TANK_STATUS_LAPS", [0]))
	F.run(g, plans, 40, 1.0, 50.0)
	assert_false(_hud(ctx).of("teammate_status")[2][2]["in_band"], "half the target is out of band")
	assert_eq(_hud(ctx).of("readout").back(), ["readout", "laps", "0"])


func test_boost_intents_raise_boost_events_unless_the_option_is_off() -> void:
	var ctx := F.make_ctx(2)
	var g := _game(ctx)
	watch_signals(g)
	var plans := F.plans_of(g)
	g.sim_step(
		Wl.SIM_DT,
		F.frame(ctx, plans, 0, 100.0, {2: [5, {"k": 7}, {"k": "boost", "via": "action"}]})
	)
	assert_signal_emitted_with_parameters(g, "game_event", [{"type": "boost", "slot": 1}])
	ctx.options["boosts"] = false
	var g2 := _game(ctx)
	watch_signals(g2)
	g2.sim_step(Wl.SIM_DT, F.frame(ctx, plans, 0, 100.0, {1: [{"k": "boost"}]}))
	assert_signal_not_emitted(g2, "game_event")


func test_the_host_toasts_only_its_own_riders_laps() -> void:
	var ctx := F.make_ctx(2)
	var g := _game(ctx)
	watch_signals(g)
	for rd: Dictionary in g.state["riders"]:
		rd["dist_m"] = 399.99
	g.sim_step(Wl.SIM_DT, F.frame(ctx, F.plans_of(g), 0))
	assert_signal_emit_count(g, "game_event", 2, "both laps go to clients")
	var toasts := _hud(ctx).of("toast")
	assert_eq(
		toasts, [["toast", "TANK_LAP_DONE", [1], 1]], "peer = ctx.local_peer draws on the host only"
	)


func test_rescue_is_a_stagger_with_a_toast_for_humans_only() -> void:
	var ctx := F.make_ctx(2, 1)
	var g := _game(ctx)
	var plans := F.plans_of(g)
	g.on_rescue(2, true)
	g.on_rescue(-1, true)
	assert_eq(_hud(ctx).of("toast"), [["toast", "TANK_STAGGER", [], 2]])
	var before := float(TankRules.rider(g.state, 2)["dist_m"])
	var tick := F.run(g, plans, 0, 1.0)
	assert_eq(float(TankRules.rider(g.state, 2)["dist_m"]), before, "a staggered marker waits")
	g.on_rescue(2, false)
	F.run(g, plans, tick, 1.0)
	assert_gt(float(TankRules.rider(g.state, 2)["dist_m"]), before)


func test_afk_stops_the_marker_and_keeps_the_slot() -> void:
	var ctx := F.make_ctx(2)
	var g := _game(ctx)
	g.on_afk(2, true)
	var before := float(TankRules.rider(g.state, 2)["dist_m"])
	F.run(g, F.plans_of(g), 0, 1.0)
	assert_eq(float(TankRules.rider(g.state, 2)["dist_m"]), before)
	assert_eq(g.state["riders"].size(), 2)
	g.on_afk(2, false)
	assert_false(TankRules.rider(g.state, 2)["afk"])


func test_local_intents_tag_gestures_apart_from_actions() -> void:
	var g := _game(F.make_ctx())
	assert_eq(g.local_intents([], [Wl.G_SURGE]), [{"k": "boost", "via": "surge"}])
	assert_eq(g.local_intents([&"confirm"], []), [{"k": "boost", "via": "action"}])
	assert_eq(
		g.local_intents([&"confirm"], [Wl.G_SURGE]),
		[{"k": "boost", "via": "surge"}],
		"a surge wins"
	)
	assert_eq(g.local_intents([&"left"], [Wl.G_COAST]), [])


func test_autopilot_boosts_every_30_s_and_never_touches_effort() -> void:
	var g := _game(F.make_ctx(1, 1))
	for t: int in [0, 299, 301, 600]:
		g.state["tick"] = t
		assert_eq(g.autopilot_intents(-1), [], "tick %d" % t)
	for t: int in [300, 900, 1500]:
		g.state["tick"] = t
		assert_eq(g.autopilot_intents(-1), [{"k": "boost", "auto": 1}], "tick %d" % t)


func _all_integral(v: Variant) -> bool:
	if v is Array:
		return (v as Array).all(func(x: Variant) -> bool: return _all_integral(x))
	if v is Dictionary:
		return (v as Dictionary).values().all(func(x: Variant) -> bool: return _all_integral(x))
	return not (v is float) or is_equal_approx(v, roundf(v))


func test_snapshots_round_trip_through_json_and_restore_a_client() -> void:
	var host_ctx := F.make_ctx(2, 1)
	var host := _game(host_ctx)
	host.on_afk(-1, true)
	F.run(host, F.plans_of(host), 0, 100.0)
	var snap := host.snapshot()
	assert_true(_all_integral(snap), "snapshots carry ints only")
	var text := JSON.stringify(snap)
	assert_lt(text.to_utf8_buffer().size(), 1024)
	var client := _game(F.make_ctx(2, 1, "default", Wl.CLIENT, 2))
	client.apply_snapshot(JSON.parse_string(text))
	assert_eq(client.state["tick"], host.state["tick"])
	assert_typeof(client.state["tick"], TYPE_INT)
	for i in 3:
		var h: Dictionary = host.state["riders"][i]
		var c: Dictionary = client.state["riders"][i]
		assert_almost_eq(float(c["dist_m"]), float(h["dist_m"]), 0.051)
		assert_eq(c["laps"], h["laps"])
		assert_typeof(c["laps"], TYPE_INT)
		assert_eq([c["rescue"], c["afk"]], [h["rescue"], h["afk"]])
	assert_eq(
		_hud(client.ctx).of("readout").back()[2], str(TankRules.rider(client.state, 2)["laps"])
	)


func test_int_fields_cover_the_snapshot_and_every_event_type() -> void:
	var f := _game(F.make_ctx()).int_fields()
	assert_has(f["snapshot"], "r[][]")
	assert_has(f["snapshot"], "tick")
	assert_eq(f["lap"], ["slot", "laps"])
	assert_eq(f["boost"], ["slot"])


func test_a_client_applies_events_and_toasts_only_its_own_laps() -> void:
	var ctx := F.make_ctx(2, 0, "default", Wl.CLIENT, 2)
	var g := _game(ctx)
	g.apply_event({"type": "lap", "slot": 1.0, "laps": 3.0})
	assert_eq(TankRules.rider(g.state, 2)["laps"], 3)
	assert_eq(_hud(ctx).of("toast"), [["toast", "TANK_LAP_DONE", [3], 0]])
	g.apply_event({"type": "lap", "slot": 0, "laps": 1})
	assert_eq(_hud(ctx).of("toast").size(), 1, "another rider's lap raises no toast here")
	g.apply_event({"type": "boost", "slot": 0})
	assert_eq(TankRules.rider(g.state, 1)["boost_s"], g.state["boost_s"])
	g.apply_event({"type": "lap", "slot": 9, "laps": 1})
	assert_eq(_hud(ctx).of("toast").size(), 1)


func test_client_predict_moves_only_the_local_marker() -> void:
	var g := _game(F.make_ctx(2, 0, "default", Wl.CLIENT, 2))
	var local := Telemetry.new()
	local.p_eff_w = 250.0
	var before1 := float(TankRules.rider(g.state, 1)["dist_m"])
	var before2 := float(TankRules.rider(g.state, 2)["dist_m"])
	for _i in 20:
		g.client_predict(Wl.SIM_DT, local)
	assert_almost_eq(
		float(TankRules.rider(g.state, 2)["dist_m"]) - before2,
		250.0 * float(g.content["mps_per_w"]),
		1e-6
	)
	assert_eq(float(TankRules.rider(g.state, 1)["dist_m"]), before1)


func test_hud_spec_places_kit_widgets_and_a_boost_button() -> void:
	var ctx := F.make_ctx()
	var spec := _game(ctx).hud_spec()
	for w: String in [
		HudSpec.TIMELINE,
		HudSpec.POWER_GAUGE,
		HudSpec.CADENCE,
		HudSpec.WBAL,
		HudSpec.GEAR,
		HudSpec.TEAMMATES,
		HudSpec.READOUT
	]:
		assert_true(spec.has_widget(w), w)
	for entry in spec.widgets:
		assert_true(HudSpec.is_valid_position(entry["at"]), str(entry))
	assert_eq(spec.controls.size(), 1)
	var button: Button = autofree(spec.controls[0]["control"])
	var at: Rect2i = spec.controls[0]["at"]
	assert_true(Rect2i(0, 0, 640, 360).encloses(at), "inside pixel_base")
	button.pressed.emit()
	assert_eq((ctx.intents as F.Intents).sent, [{"k": "boost", "via": "button"}])


func test_make_view_returns_a_node2d_that_draws_the_state() -> void:
	var g := _game(F.make_ctx(2, 1))
	var view := g.make_view()
	assert_is(view, Node2D)
	assert_eq((view as TankView).game, g)
	add_child_autofree(view)
	await wait_process_frames(2)
	assert_true(view.is_inside_tree())


func test_results_fill_platform_rows_with_laps_xp_unlocks_and_a_grade() -> void:
	var ctx := F.make_ctx(2, 1)
	var g := _game(ctx)
	(ctx.stats as F.Stats).rows = {
		1: {"kj": 120.0, "time_in_band_pct": 80.0},
		2: {"kj": 80.0, "time_in_band_pct": 82.0},
		-1: {"kj": 100.0, "time_in_band_pct": 84.0}
	}
	TankRules.rider(g.state, 1)["laps"] = 4
	TankRules.rider(g.state, 2)["laps"] = 1
	TankRules.rider(g.state, -1)["laps"] = 3
	var res := g.results()
	assert_eq(res.rows.size(), 3)
	assert_eq(
		[res.row(1)["xp"], res.row(1)["unlocks"], res.row(1)["stats"]["laps"]],
		[32, ["gold_marker"], 4]
	)
	assert_eq([res.row(2)["xp"], res.row(2)["unlocks"]], [13, []])
	assert_eq([res.row(-1)["xp"], res.row(-1)["is_bot"]], [25, true])
	assert_eq(res.row(1)["kj"], 120.0, "the platform's columns stay")
	assert_eq(res.grade, "B")
	assert_eq(res.score, 8.0)
	assert_eq(res.team, {"laps": 8})
	assert_eq(res.summary_key, "TANK_RESULTS")


func test_results_work_without_platform_stats() -> void:
	var ctx := F.make_ctx(1)
	ctx.stats = null
	var g := _game(ctx)
	TankRules.rider(g.state, 1)["laps"] = 2
	var res := g.results()
	assert_eq(res.row(1)["xp"], 10, "XP from laps alone")
	assert_eq(res.grade, "D")


func test_apply_progress_counts_a_session_once_and_returns_only_new_unlocks() -> void:
	var ctx := F.make_ctx(2)
	var g := _game(ctx)
	var res := GameResults.new()
	res.rows.append({"peer_id": 1, "xp": 30, "unlocks": ["gold_marker"]})
	res.rows.append({"peer_id": 2, "xp": 5, "unlocks": []})
	res.session_id = "s1"
	var store := ProgressStore.open("tank", "")
	assert_eq(g.apply_progress(res, store), ["gold_marker"])
	assert_eq(store.get_value("xp"), 30.0)
	assert_eq(g.apply_progress(res, store), [], "the same session twice")
	assert_eq(store.get_value("xp"), 30.0)
	res.session_id = "s2"
	assert_eq(g.apply_progress(res, store), [], "already held")
	assert_eq(store.get_value("xp"), 60.0)
	assert_eq(store.get_value("unlocks"), ["gold_marker"])
	var other := _game(F.make_ctx(2, 0, "default", Wl.CLIENT, 3))
	assert_eq(other.apply_progress(res, ProgressStore.open("tank", "")), [], "no row for this peer")


func _hashes(rng_seed: int) -> Array:
	var ctx := F.make_ctx(2, 1, "default", Wl.SOLO, 1, rng_seed)
	var g := _game(ctx)
	var plans := F.plans_of(g)
	var out: Array = []
	var tick := 0
	for _i in 6:
		tick = F.run(g, plans, tick, 20.0)
		out.append(JSON.stringify(g.snapshot()).sha256_text())
	return out


func test_the_same_seed_gives_the_same_snapshots() -> void:
	assert_eq(_hashes(11), _hashes(11))
	assert_ne(_hashes(11), _hashes(12), "the seed reaches the rules through ctx.rng")


## W3 SDK-7: "short" shows the SDK calls the default content has no room for. Its SIM phase
## (grade_source "game") gets a gentle course_grade at 2 Hz and nothing else does; at that phase's
## start every rider's remaining plan is replanned, once, to an open-ended "Finish" the PlanValidator
## accepts; every rider's phase change shows a banner on that rider's own peer.
func test_short_feeds_its_sim_phase_with_course_grade_and_replans_to_an_open_ended_finish() -> void:
	var ctx := F.make_ctx(2, 0, "short")
	var g := _game(ctx)
	var plans := F.plans_of(g)
	var built: EffortPlan = g.build_effort_plans()[1]
	assert_eq([built.phase(1).mode, built.phase(1).grade_source], [Wl.SIM, Wl.GRADE_GAME])
	var tick := F.run(g, plans, 0, 59.9)
	assert_eq(_dirs(ctx).course_grades, [], "no course grade outside the SIM phase")
	assert_eq(_dirs(ctx).replans, [])
	tick = F.run(g, plans, tick, 40.0)
	var grades: Array = _dirs(ctx).course_grades
	for peer: int in [1, 2]:
		var mine := grades.filter(func(c: Array) -> bool: return c[0] == peer)
		assert_between(mine.size(), 79, 81, "2 Hz over the 40 s SIM phase for peer %d" % peer)
		for c: Array in mine:
			assert_between(float(c[1]), -1.5, 1.5, "a gentle roller")
	assert_eq(_dirs(ctx).replans.size(), 2, "one replan per rider")
	for r: Array in _dirs(ctx).replans:
		var rest: EffortPlan = r[1]
		assert_eq(rest.size(), 1)
		assert_true(rest.phase(0).open_ended)
		assert_eq([rest.phase(0).min_s, rest.phase(0).max_s], [30.0, 50.0])
		var whole := PlanValidator.spliced(built, 1, rest)
		var v := PlanValidator.validate(whole)
		assert_true(v["ok"], "the replanned plan validates: %s" % str(v["errors"]))
		assert_eq(v["warnings"], [], "no mode-switch warning")
	F.run(g, plans, tick, 30.0)
	assert_eq(_dirs(ctx).course_grades.size(), grades.size(), "no course grade after the SIM phase")
	var banners := _hud(ctx).of("banner")
	for peer: int in [1, 2]:
		var mine := banners.filter(func(c: Array) -> bool: return c[4] == peer)
		assert_eq(mine.size(), 3, "one banner per phase, on rider %d's own peer" % peer)
		if mine.size() == 3:
			assert_eq(
				mine[1].slice(1, 4),
				["TANK_BANNER_PHASE", [ctx.strings.t("TANK_PHASE_ROLLERS")], 3.0]
			)
	assert_eq(banners.size(), 6, "and no banner to every peer")


## W4r2 R12: after "short"'s open-ended Finish the riders' phases drift apart (each ends by its own
## end_phase or max_s). Each rider's banner then comes when ITS phase changes, on its own peer only,
## never to every peer; bots get none; phase_changed (the group's phase) comes once the last rider
## got there.
func test_phase_banners_follow_each_riders_own_phase() -> void:
	var ctx := F.make_ctx(2, 1, "short")
	var g := _game(ctx)
	watch_signals(g)
	var plans := F.plans_of(g)
	# Rider 2 and the bot ride their last phase 18 s longer (their Finish ends at max_s).
	for peer: int in [2, -1]:
		var late: EffortPlan = plans[peer]
		late.phase(2).duration_s += 18.0
	var tick := F.run(g, plans, 0, 160.1)  # rider 1 entered the cool-down at 160 s
	var cool := ctx.strings.t(PlanValidator.cooldown_phase().label)
	var to := func(peer: int) -> Array:
		return _hud(ctx).of("banner").filter(func(c: Array) -> bool: return c[4] == peer)
	assert_eq(
		(to.call(1) as Array).size(), 4, "rider 1: a banner per phase, the cool-down's included"
	)
	assert_eq((to.call(1) as Array).back().slice(1, 3), ["TANK_BANNER_PHASE", [cool]])
	assert_eq(
		(to.call(2) as Array).size(),
		3,
		"rider 2 still rides its last phase: no cool-down banner yet"
	)
	assert_eq(to.call(0), [], "no banner goes to every peer")
	assert_eq(to.call(-1), [], "bots get no banner")
	assert_signal_emit_count(g, "phase_changed", 3, "the group is not in the cool-down yet")
	F.run(g, plans, tick, 18.0)  # 178.1 s: rider 2 and the bot entered it too
	assert_eq(
		(to.call(2) as Array).size(), 4, "rider 2's cool-down banner comes with its own change"
	)
	assert_eq((to.call(2) as Array).back().slice(1, 3), ["TANK_BANNER_PHASE", [cool]])
	assert_eq((to.call(1) as Array).size(), 4, "rider 1 gets no second cool-down banner")
	assert_signal_emit_count(g, "phase_changed", 4)
	assert_eq(get_signal_parameters(g, "phase_changed", 3), [3], "the group reached the cool-down")


## W3 SDK-7: an open-ended phase ends with end_phase, once, after min_s while the rider is in
## band; out of band the game leaves it to the platform's max_s.
func test_an_open_ended_phase_ends_with_end_phase_after_min_s_in_band() -> void:
	for power_pct: float in [100.0, 50.0]:
		var ctx := F.make_ctx(1)
		var g := _game(ctx)
		var plan := EffortPlan.of(
			[
				PlanPhase.erg(Wl.WARMUP, 50, 60, "TANK_PHASE_WARMUP").with_lap(),
				(
					PlanPhase
					. erg(Wl.WORK, 55, 40, "TANK_PHASE_FINISH")
					. with_range(55, 60)
					. with_open(30, 50)
					. with_lap()
				)
			]
		)
		var plans := {1: F.with_cooldown(plan)}
		var tick := F.run(g, plans, 0, 89.9, power_pct)
		assert_eq(_dirs(ctx).ended, [], "not before min_s")
		F.run(g, plans, tick, 2.0, power_pct)
		assert_eq(
			_dirs(ctx).ended,
			[1] if power_pct == 100.0 else [],
			"in band after min_s: end_phase once (power %d%%)" % power_pct
		)
