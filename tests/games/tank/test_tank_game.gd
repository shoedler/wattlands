extends GutTest
## TankGame driven directly with synthetic InputFrames and recording sinks (TankFakes): content,
## plans, the group's phase, end_phase, finished, bands, intents, snapshots, events, HUD layout,
## results and progress. Lead-owned G0 tests; builders add theirs under their own folders.

const F := preload("res://tests/games/tank/tank_fakes.gd")
## The kit minimums at 1080p (GAME_SDK 10.1), divided by 3 for art px and rounded up.
const KIT_MIN := {
	"power_gauge": Vector2i(100, 36),
	"cadence": Vector2i(97, 33),
	"timeline": Vector2i(127, 36),
	"hull_hp": Vector2i(57, 36),
	"watts": Vector2i(57, 36),
	"wbal": Vector2i(80, 14),
	"gear": Vector2i(50, 14),
	"teammates": Vector2i(134, 21),
}


func _game(ctx: GameContext) -> TankGame:
	return autofree(F.make_game(ctx))


func _dirs(ctx: GameContext) -> F.Directives:
	return ctx.directives as F.Directives


func _hud(ctx: GameContext) -> F.Hud:
	return ctx.hud as F.Hud


func test_the_crew_size_picks_the_tank_and_its_rooms() -> void:
	var expect := {
		1: [TankIds.TANK_BULWARK, ["bulwark"]],
		2: [TankIds.TANK_RAMPART, ["diesel", "dynamo"]],
		3: [TankIds.TANK_CITADEL, ["diesel", "dynamo", "steam"]],
	}
	for crew: int in expect:
		var g := _game(F.make_ctx(crew))
		assert_not_null(g.state, "crew %d" % crew)
		assert_eq(g.state.hull.tank, expect[crew][0])
		var engines: Array = g.state.stations.map(
			func(s: TankStationState) -> String: return s.engine
		)
		assert_eq(engines, expect[crew][1], "rooms rear to front")
		for r in g.state.riders:
			assert_eq(r.engine, expect[crew][1][r.slot], "slot %d starts on its engine" % r.slot)
			assert_eq(g.state.station(r.engine).slot, r.slot)


func test_bad_content_is_rejected_at_load_and_gives_no_plans() -> void:
	var ctx := F.make_ctx(1)
	ctx.content_overrides = {"tanks.json": {"hull": {"hp": -5}}}
	var g := _game(ctx)
	assert_push_error("hull.hp")
	assert_null(g.state)
	assert_eq(g.build_effort_plans(), {})


func test_plans_share_every_boundary_and_follow_the_rotation_table() -> void:
	for crew in [1, 2, 3]:
		var g := _game(F.make_ctx(crew))
		var plans := g.build_effort_plans()
		assert_eq(plans.size(), crew)
		var first: EffortPlan = plans[1]
		assert_eq(first.size(), 11, "depot, 3 x (advance, gun line, checkpoint), boss")
		for peer: int in plans:
			var plan: EffortPlan = plans[peer]
			for i in plan.size():
				var a := first.phase(i)
				var b := plan.phase(i)
				assert_eq(
					[b.kind, b.duration_s, b.open_ended, b.min_s, b.max_s, b.lap, b.label],
					[a.kind, a.duration_s, a.open_ended, a.min_s, a.max_s, a.lap, a.label],
					"crew %d peer %d phase %d" % [crew, peer, i]
				)
	var c3 := _game(F.make_ctx(3)).build_effort_plans()
	var rows := {
		1: ["diesel", "dynamo", "steam", "diesel"],
		2: ["dynamo", "steam", "diesel", "dynamo"],
		3: ["steam", "diesel", "dynamo", "steam"]
	}
	for peer: int in rows:
		var plan: EffortPlan = c3[peer]
		for stage in 3:
			assert_eq(
				plan.phase(1 + 3 * stage).meta["engine"],
				rows[peer][stage],
				"peer %d stage %d" % [peer, stage + 1]
			)
		assert_eq(plan.phase(10).meta["engine"], rows[peer][3], "peer %d boss" % peer)


func test_rotation_off_keeps_every_rider_on_its_start_engine() -> void:
	var ctx := F.make_ctx(3)
	ctx.options["rotation"] = false
	var plans := _game(ctx).build_effort_plans()
	for peer: int in plans:
		var plan: EffortPlan = plans[peer]
		var start := str(plan.phase(0).meta["engine"])
		for i in plan.size():
			assert_eq(plan.phase(i).meta["engine"], start, "peer %d phase %d" % [peer, i])


func test_a_full_session_ends_open_phases_together_and_finishes_once() -> void:
	var ctx := F.make_ctx(3)
	var g := _game(ctx)
	var plans := F.plans_of(g)
	watch_signals(g)
	F.run(g, plans, 0, 1630.0)
	var ended := _dirs(ctx).ended
	assert_eq(ended.size(), 7 * 3, "3 riders x (3 advances, 3 gun lines, the boss)")
	for i in range(0, ended.size(), 3):
		assert_eq(ended.slice(i, i + 3), [1, 2, 3], "every rider in one step")
	assert_signal_emit_count(g, "phase_changed", 12, "every segment and the cool-down")
	assert_signal_emitted_with_parameters(g, "finished", [TankIds.OUTCOME_VICTORY])
	assert_signal_emit_count(g, "finished", 1)


func test_nothing_is_sent_in_the_cooldown() -> void:
	var ctx := F.make_ctx(2)
	var g := _game(ctx)
	var plans := F.plans_of(g)
	var tick := F.run(g, plans, 0, 1620.5)
	var d := _dirs(ctx)
	var counts := [
		d.requests.size(), d.cadence_bands.size(), d.course_grades.size(), d.ended.size()
	]
	F.run(g, plans, tick, 170.0)
	assert_eq(
		[d.requests.size(), d.cadence_bands.size(), d.course_grades.size(), d.ended.size()], counts
	)


func test_bands_at_each_segment_start() -> void:
	var ctx := F.make_ctx(3)
	var g := _game(ctx)
	var plans := F.plans_of(g)
	F.run(g, plans, 0, 1.0)
	var bands := _dirs(ctx).cadence_bands
	assert_eq(bands, [[1, 60.0, 120.0], [2, 60.0, 120.0], [3, 60.0, 120.0]])
	var pb := _hud(ctx).of("power_band")
	assert_eq(pb.size(), 3)
	assert_eq(pb[0], ["power_band", 1, 0.76 * 200.0, 1.05 * 200.0], "the diesel's SIM band")
	assert_eq(pb[1], ["power_band", 2, 0.0, 0.0], "the dynamo rides ERG")
	assert_eq(pb[2], ["power_band", 3, 0.0, 0.0], "the steam band is on the station card only")


func test_local_intents_by_engine_and_surge_never_fires() -> void:
	var g := _game(F.make_ctx(3))
	var none: Array[StringName] = []
	var surge: Array[StringName] = [Wl.G_SURGE]
	var confirm: Array[StringName] = [&"confirm"]
	g.ctx.local_peer = 1
	assert_eq(g.local_intents(none, surge), [{"k": "ram", "via": "surge"}], "diesel")
	g.ctx.local_peer = 3
	assert_eq(g.local_intents(none, surge), [{"k": "over", "via": "surge"}], "steam")
	assert_eq(g.local_intents(confirm, surge), [{"k": "over", "via": "surge"}], "never latch")
	assert_eq(g.local_intents(confirm, none), [{"k": "latch", "via": "action"}])
	g.ctx.local_peer = 2
	assert_eq(g.local_intents(none, surge), [], "the dynamo has no sprint")
	assert_eq(g.local_intents(confirm, none), [{"k": "fire", "via": "action"}])


func test_intents_are_owned_by_engine_and_rate_limited() -> void:
	var ctx := F.make_ctx(3)
	var g := _game(ctx)
	var plans := F.plans_of(g)
	var spam: Array = []
	for i in 8:
		spam.append({"k": "fire"})
	var f := F.frame(ctx, plans, 100, 100.0, {1: [{"k": "fire"}, {"k": "ram"}], 2: spam})
	var got: Dictionary = g._collect_intents(f)
	assert_eq(
		(got[1] as Array).map(func(n: Dictionary) -> String: return n["k"]),
		["ram"],
		"the diesel can't fire"
	)
	assert_eq((got[2] as Array).size(), 5, "5 a second per peer")


func test_snapshots_round_trip_through_json_and_restore_a_client() -> void:
	for crew in [1, 2, 3]:
		var host := _game(F.make_ctx(crew))
		host.state = TankFixtures.state(crew)
		host.state.content = host.content
		var snap := host.snapshot()
		assert_eq(TankSnapshotSchema.check(snap), "")
		var wire: Variant = Protocol.apply_int_fields(
			JSON.parse_string(JSON.stringify(snap)), host.int_fields()["snapshot"]
		)
		var client := _game(F.make_ctx(crew, 0, "ashfall_road", Wl.CLIENT, crew))
		client.apply_snapshot(wire)
		assert_eq(JSON.stringify(client.snapshot()), JSON.stringify(snap), "crew %d" % crew)


func test_int_fields_cover_the_snapshot_and_every_event_type() -> void:
	var f := _game(F.make_ctx(1)).int_fields()
	assert_eq(f["snapshot"], TankSnapshotSchema.INT_PATHS)
	for t: String in TankEvents.TYPES:
		assert_true(f.has(t), t)


func test_hud_rects_stay_in_the_hud_bands_clear_of_panic_and_at_kit_minimums() -> void:
	var panic := Rect2i(
		TankConst.PANIC_X, TankConst.PANIC_Y, 640 - TankConst.PANIC_X, 360 - TankConst.PANIC_Y
	)
	var rects: Array = TankHud.RECTS.values()
	for name: String in TankHud.RECTS:
		var r: Rect2i = TankHud.RECTS[name]
		assert_true(
			r.end.y <= TankConst.HUD_TOP_H or r.position.y >= TankConst.HUD_BOTTOM_Y,
			"%s in a HUD band" % name
		)
		assert_true(r.position.x >= 0 and r.end.x <= 640 and r.end.y <= 360, "%s on screen" % name)
		assert_false(r.intersects(panic), "%s clear of PANIC" % name)
		if KIT_MIN.has(name):
			assert_true(
				r.size.x >= KIT_MIN[name].x and r.size.y >= KIT_MIN[name].y,
				"%s at its minimum" % name
			)
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			assert_false(
				(rects[i] as Rect2i).intersects(rects[j]), "rects %d and %d overlap" % [i, j]
			)
	var spec := _game(F.make_ctx(3)).hud_spec()
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
	for c: Dictionary in spec.controls:
		(c["control"] as Control).free()


func test_make_view_returns_a_node2d_that_reads_the_state() -> void:
	var g := _game(F.make_ctx(3))
	g.state = TankFixtures.state(3)
	var v: Node = autofree(g.make_view())
	assert_is(v, Node2D)
	assert_eq((v as TankView).game, g)


func test_results_grade_xp_and_unlocks_after_a_full_session() -> void:
	var ctx := F.make_ctx(1)
	(ctx.stats as F.Stats).rows = {1: {"kj": 420.0}}
	var g := _game(ctx)
	var plans := F.plans_of(g)
	F.run(g, plans, 0, 1630.0)
	var res := g.results()
	assert_eq(res.rows.size(), 1)
	assert_has(["S", "A", "B", "C", "D"], res.grade)
	var row := res.row(1)
	var bonus := {"S": 60, "A": 40, "B": 25, "C": 10, "D": 0}
	assert_eq(row["xp"], 42 + int(bonus[res.grade]))
	assert_has(row["unlocks"], "soot", "a finished session")
	assert_eq(res.summary_key, "TANK_RESULT_VICTORY")
	assert_gt(float(row["stats"]["TANK_STAT_BULWARK_S"]), 1000.0)


func test_apply_progress_counts_a_session_once_and_returns_only_new_unlocks() -> void:
	var ctx := F.make_ctx(1)
	var g := _game(ctx)
	var res := GameResults.new()
	res.session_id = "tank/ashfall_road/1/x"
	res.rows = [{"peer_id": 1, "xp": 50, "unlocks": ["soot", "rust"]}]
	assert_eq(g.apply_progress(res, ctx.progress), ["soot", "rust"])
	assert_eq(g.apply_progress(res, ctx.progress), [], "the same session twice")
	res.session_id = "tank/ashfall_road/1/y"
	res.rows = [{"peer_id": 1, "xp": 10, "unlocks": ["soot", "ash"]}]
	assert_eq(g.apply_progress(res, ctx.progress), ["ash"])
	assert_eq(float(ctx.progress.get_value("xp", 0)), 60.0)


func test_the_same_seed_gives_the_same_snapshots() -> void:
	var out: Array = []
	for _i in 2:
		var g := _game(F.make_ctx(3))
		var plans := F.plans_of(g)
		F.run(g, plans, 0, 400.0)
		out.append(JSON.stringify(g.snapshot()))
	assert_eq(out[0], out[1])
