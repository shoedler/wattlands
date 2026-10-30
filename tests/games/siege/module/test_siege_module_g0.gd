extends GutTest
## Smoke tests of SiegeGame's wiring: plans, phase_changed,
## finished, results and XP, apply_progress once per session, int_fields, controls, a client's
## snapshot, the view and HUD from a fixture.

const F := preload("res://tests/games/siege/siege_fakes.gd")
const FIX := preload("res://tests/games/siege/fixtures/siege_fixtures.gd")


func test_the_drill_plays_to_finished_with_phase_changed_per_phase() -> void:
	var ctx := F.make_ctx(1, 1, "drill")
	var g := F.make_game(ctx)
	var plans := F.plans_of(g)
	var changed: Array = []
	var finished: Array = []
	var events: Array = []
	g.phase_changed.connect(func(i: int) -> void: changed.append(i))
	g.finished.connect(func(r: String) -> void: finished.append(r))
	g.game_event.connect(func(e: Dictionary) -> void: events.append(e["type"]))
	F.run(g, plans, 0, 125.0)
	assert_eq(changed, [0, 1, 2])
	assert_eq(finished, ["complete"], "once, when the last wave ends")
	assert_eq(events.count(SiegeIds.EV_WAVE_START), 1)
	assert_eq(events.count(SiegeIds.EV_WAVE_END), 1)
	assert_true(g.state.done)
	assert_eq((ctx.directives as F.Directives).requests, [], "no directive in the drill")
	F.free_game(g)


func test_results_xp_and_progress_once_per_session() -> void:
	var ctx := F.make_ctx(1, 1, "short")
	var g := F.make_game(ctx)
	(ctx.stats as F.Stats).rows = {1: {"kj": 1004.0}, -1: {"kj": 50.0}}
	var res := g.results()
	assert_true(["S", "A", "B", "C", "D"].has(res.grade))
	var bonus := {"S": 60, "A": 40, "B": 25, "C": 10, "D": 0}
	assert_eq(
		int(res.row(1)["xp"]), 100 + int(bonus[res.grade]), "round(kJ / 10) + the grade bonus"
	)
	assert_true(res.row(1)["stats"].has("SIEGE_STAT_KILLS"))
	assert_true(res.team.has("SIEGE_STAT_BREACHES"))
	res.session_id = "siege/short/1/a"
	res.row(1)["xp"] = 120
	var store := ProgressStore.open("siege", "")
	assert_eq(g.apply_progress(res, store), ["swallowtail_pennant"])
	assert_eq(g.apply_progress(res, store), [], "the same session counts once")
	assert_eq(float(store.get_value("xp", 0)), 120.0)
	res.session_id = "siege/short/1/b"
	res.row(1)["xp"] = 400
	assert_eq(
		g.apply_progress(res, store),
		["walnut_wheel", "bronze_chain_trim"],
		"520 crosses 250 and 500"
	)
	assert_eq(float(store.get_value("xp", 0)), 520.0)
	F.free_game(g)


func test_int_fields_and_controls() -> void:
	var ctx := F.make_ctx(1, 0, "vo2")
	var g := F.make_game(ctx)
	var f := g.int_fields()
	for t: String in SiegeIds.EVENT_TYPES:
		assert_true(f.has(t), t)
	assert_eq(f["snapshot"], SiegeSnapshotSchema.INT_PATHS)
	var plans := F.plans_of(g)
	F.run(g, plans, 0, 1.0)
	var no_actions: Array[StringName] = []
	var surge: Array[StringName] = [Wl.G_SURGE]
	var none: Array[StringName] = []
	assert_eq(g.local_intents(no_actions, surge), [SiegeIntents.overdrive("surge")])
	var a1: Array[StringName] = [&"ability_1", &"swap"]
	assert_eq(
		g.local_intents(a1, none), [SiegeIntents.overdrive("action"), SiegeIntents.route("next")]
	)
	var dirs: Array[StringName] = [&"up"]
	assert_eq(g.local_intents(dirs, none), [SiegeIntents.route("mine")])
	g.state.role = SiegeIds.ROLE_BREAK
	assert_eq(g.local_intents(a1, surge), [], "in a break the shop panel takes the input")
	assert_eq(g.autopilot_intents(1), [])
	F.free_game(g)


func test_a_client_applies_the_fixture_snapshot() -> void:
	var ctx := F.make_ctx(3, 1, "vo2", Wl.CLIENT, 2)
	var g := F.make_game(ctx)
	g.apply_snapshot(Protocol.apply_int_fields(FIX.snapshot(), g.int_fields()["snapshot"]))
	assert_eq(g.state.phase_index, 4)
	assert_eq(g.state.role, SiegeIds.ROLE_WAVE)
	assert_eq(g.state.wave_no, 2)
	assert_eq(g.state.rider_at(1).raw_w, 110.0)
	assert_eq(g.state.enemies.size(), 43)
	var reads := (ctx.hud as F.Hud).of("readout")
	assert_eq(reads[0], ["readout", SiegeHud.READOUT_GATE, "72 / 155"])
	F.free_game(g)


func test_the_view_and_hud_build_headless_from_the_fixture() -> void:
	var view := SiegeView.new()
	var st := FIX.mid_wave()
	view.bind(st, st.path)
	add_child_autofree(view)
	assert_true(view.is_inside_tree())
	assert_eq(view.state, st)
	assert_eq(view.path, st.path)
	var ctx := F.make_ctx(1, 1, "short")
	var g := F.make_game(ctx)
	var spec := g.hud_spec()
	assert_true(spec.has_widget(HudSpec.TIMELINE))
	var keys: Array[String] = []
	for h: Dictionary in spec.help:
		keys.append(str(h["text"]))
	assert_eq(
		keys,
		[
			"SIEGE_HELP_WHEEL",
			"SIEGE_HELP_PATH",
			"SIEGE_HELP_STATIONS",
			"SIEGE_HELP_ROAD",
			"SIEGE_HELP_GATE",
			"SIEGE_HELP_ROUTE_CARD",
			"SIEGE_HELP_SHOP",
		]
	)
	for c: Dictionary in spec.controls:
		var ctl: Variant = c.get("control")
		if ctl is Node:
			(ctl as Node).free()
	for h: Dictionary in spec.help:
		assert_true(str(h["text"]).begins_with("SIEGE_HELP_"))
		var at: Vector2 = h["arrow_to"]
		assert_true(at.x >= 0.0 and at.x <= 960.0 and at.y >= 0.0 and at.y <= 540.0, str(at))
	var v: Node = g.make_view()
	assert_is(v, Node2D)
	assert_eq((v as SiegeView).game, g)
	assert_eq((v as SiegeView).state, g.state)
	v.free()
	F.free_game(g)
