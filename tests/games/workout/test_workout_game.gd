extends GutTest
## WorkoutGame as a GameModule (BRIEF 3.6, 3.7): plans for every rider, the HUD spec, host
## HUD calls during a session, no directives, no lap markers, staggers on rescue and AFK,
## zero input, and a whole session per built-in content with compliant synthetic riders.

const U := preload("res://tests/games/workout/workout_test_util.gd")


## Records directive calls; Workout should never make one.
class RecordingSink:
	extends DirectiveSink
	var calls: int = 0

	func request(_peer: int, _directive: EffortDirective) -> DirectiveResult:
		calls += 1
		return DirectiveResult.refused(Wl.REFUSE_NOT_AUTHORITY)

	func course_grade(_peer: int, _grade_pct: float) -> void:
		calls += 1

	func end_phase(_peer: int) -> bool:
		calls += 1
		return false

	func cadence_band(_peer: int, _lo: float, _hi: float) -> void:
		calls += 1

	func replan(_peer: int, _plan: EffortPlan) -> bool:
		calls += 1
		return false


func test_is_a_game_module() -> void:
	var script := load("res://src/games/workout/workout_game.gd") as GDScript
	assert_not_null(script)
	var g: Variant = script.new()
	assert_true(g is GameModule)
	assert_true(g is WorkoutGame)
	(g as Node).free()


func test_configure_orders_riders_by_slot() -> void:
	var players := U.players(2, 2)
	players.reverse()
	var g := U.game("easy_30", players)
	autofree(g)
	var expected: Array[int] = [1, 2, -1, -2]
	assert_eq(g.state.order, expected)
	assert_eq(g.state.phases.size(), 9, "8 phases plus the cool-down")
	assert_eq(g.state.rider(-1).is_bot, true)


func test_hud_spec() -> void:
	var g := U.game("easy_30", U.players(1))
	autofree(g)
	var spec := g.hud_spec()
	assert_eq(spec.widgets.size(), 0, "no kit widgets")
	assert_eq(spec.controls.size(), 4)
	var keys: Array[String] = ["timeline", "mine", "crew", "score"]
	var plates: Array[Rect2i] = []
	for i in keys.size():
		var rect: Rect2i = WorkoutHud.LAYOUT[keys[i]]
		plates.append(rect)
		assert_eq(spec.controls[i]["at"], rect, keys[i])
		assert_true(HudSpec.is_valid_position(spec.controls[i]["at"]))
		assert_true(spec.controls[i]["control"] is WorkoutHudCtl, keys[i])
		autofree(spec.controls[i]["control"])
	assert_true(spec.shows_power, "the mine plate shows raw W and %FTP")
	assert_true(spec.show_safety_banners)
	assert_eq(spec.toast_area, Rect2i(6, 76, 300, 24))
	assert_eq(spec.banner_area, Rect2i(280, 104, 400, 32))
	assert_eq(spec.help.size(), 6)
	for e: Dictionary in spec.help:
		if e["text"] == "WORKOUT_HELP_BLOCKS":
			# the one arrow outside every plate: it ends on the interval strip on the bank (y 418-460)
			assert_eq(e["arrow_to"], Vector2(560, 440))
			continue
		var inside := false
		for r in plates:
			inside = inside or Rect2(r).has_point(e["arrow_to"])
		assert_true(inside, "%s ends inside a plate" % e["text"])
	assert_eq(spec.palette["corner_radius"], 0)
	assert_true(spec.palette["font"] is Font, "the platform's toasts use the HUD's type")


func test_nothing_to_choose() -> void:
	var g := U.game("easy_30", U.players(1, 1))
	autofree(g)
	assert_eq(g.autopilot_intents(-1), [])
	assert_eq(g.autopilot_intents(1), [])
	var actions: Array[StringName] = [&"confirm"]
	var gestures: Array[StringName] = [&"surge"]
	assert_eq(g.local_intents(actions, gestures), [])
	var keys := g.int_fields().keys()
	keys.sort()
	assert_eq(keys, ["interval_end", "interval_start", "snapshot", "sprint"])


func test_a_session_sends_no_directives_and_no_lap_markers() -> void:
	var c := U.ctx("easy_30", U.players(2, 1))
	var sink := RecordingSink.new()
	c.directives = sink
	var g := WorkoutGame.new()
	autofree(g)
	g.configure(c)
	var laps: Array = []
	g.lap_marker.connect(func(label: String) -> void: laps.append(label))
	var finished: Array = []
	g.finished.connect(func(reason: String) -> void: finished.append(reason))
	U.ride(g)
	assert_eq(sink.calls, 0, "the plan does the trainer work")
	assert_eq(laps, [], "FIT laps come from lap = true phases")
	assert_eq(finished, [], "the plan ends on its own")


func test_host_hud_calls_during_a_session() -> void:
	var g := U.game("sweet_spot", U.players(2, 1))
	autofree(g)
	U.ride(g)
	var hud: U.FakeHud = g.ctx.hud
	var banners := hud.of("banner")
	assert_eq(banners.size(), 4, "one banner per interval; the cool-down has the platform's")
	assert_eq(banners[0]["key"], "WORKOUT_BANNER_RAMP")
	assert_eq(banners[0]["args"]["from"], 50)
	assert_eq(banners[0]["args"]["to"], 65)
	assert_eq(banners[1]["key"], "WORKOUT_BANNER_ERG")
	assert_eq(banners[1]["args"]["pct"], 90)
	assert_eq(banners[1]["args"]["time"], "12:00")
	assert_eq(banners[1]["peer"], Wl.ALL_PEERS)
	var done := []
	for t in hud.of("toast"):
		if t["key"] == "WORKOUT_TOAST_INTERVAL_DONE":
			done.append(t["peer"])
	assert_eq(done, [1, 2, 1, 2], "each human hears about each work interval; bots don't")
	var statuses := hud.of("teammate_status")
	var peers := {}
	for s in statuses:
		peers[s["peer"]] = s["status"]
	assert_eq(peers.keys().size(), 3, "every rider's compliance reaches the strip")
	assert_eq(peers[-1], {"in_band": true, "icon": "", "text": "100%"})
	assert_lt(statuses.size(), 3 * 2200, "throttled")
	var readouts := hud.of("readout")
	assert_gt(readouts.size(), 100)
	assert_eq(readouts.back()["text"], "100%")
	assert_eq(hud.of("power_band").size(), 0, "no SIM phase, no band")


func test_rolling_road_band_for_every_rider() -> void:
	var players := U.players(1, 1, 250.0)
	var g := U.game("rolling_road", players)
	autofree(g)
	# Stop on the last step of Rolling road (2100 s), before the cool-down.
	U.ride(g, Callable(), 41999)
	var hud: U.FakeHud = g.ctx.hud
	var bands := hud.of("power_band")
	assert_eq(bands.size(), 2)
	assert_eq(
		[bands[0]["peer"], bands[0]["lo"], bands[0]["hi"]], [1, 190.0, 262.5], "76-105% of 250 W"
	)
	assert_eq(bands[1]["peer"], -1)
	var banner: Dictionary = hud.of("banner")[1]
	assert_eq(banner["key"], "WORKOUT_BANNER_ROLLING")
	assert_eq([banner["args"]["lo"], banner["args"]["hi"]], [76, 105])
	var r := g.state.rider(1)
	assert_almost_eq(r.tib_fraction(), 1.0, 0.0001)
	assert_gt(r.distance_m(), 8000.0, "30 minutes on the road")
	assert_gt(r.course_d, 5000.0)


## In Rolling road each rider moves on the trainer's applied SIM grade (what the rider's own
## speed model follows the course by), so the drawn position matches the grade the governor
## applies; a rider whose trainer is still in ERG moves on the course grade.
func test_course_position_follows_the_applied_sim_grade() -> void:
	var players := U.players(2)
	var g := U.game("rolling_road", players)
	autofree(g)
	var timeline := g.state.phases
	var starts := U.phase_ticks(timeline)
	var ref := SpeedModel.create(players[0].rider_mass_kg)
	var ref_course := 0.0
	for tick in starts[1] + 1200:
		var frame := InputFrame.new()
		frame.tick = tick
		frame.t = float(tick) * U.DT
		var ps := U.phase_state(timeline, starts, tick)
		var p := timeline[ps.index]
		for slot in players:
			var v := U.compliant(slot, p, ps)
			if p.mode == Wl.SIM:
				v["applied_grade_pct"] = 0.0 if slot.peer_id == 1 else 5.0
			frame.players[slot.peer_id] = U.telemetry(slot, v, tick)
			frame.phase[slot.peer_id] = ps
		var tel: Telemetry = frame.players[1]
		var before := ref.distance_m
		ref.step(U.DT, tel.p_eff_w, tel.applied_grade_pct if p.mode == Wl.SIM else 0.0)
		if p.mode == Wl.SIM:
			ref_course += ref.distance_m - before
		g.sim_step(U.DT, frame)
	var flat := g.state.rider(1)
	var steep := g.state.rider(2)
	assert_almost_eq(flat.distance_m(), ref.distance_m, 0.001, "same model, same P_eff, same grade")
	assert_almost_eq(
		flat.course_d, ref_course, 0.001, "course distance counts from the phase start"
	)
	assert_lt(
		steep.course_d, flat.course_d - 50.0, "a steeper applied grade is slower along the course"
	)
	# The grade source: SIM telemetry's applied grade, else the course under the rider.
	var tel_sim := Telemetry.new()
	tel_sim.mode = Wl.SIM
	tel_sim.applied_grade_pct = 3.5
	assert_eq(WorkoutRules.course_speed_grade(g.state, steep, tel_sim), 3.5)
	var tel_erg := Telemetry.new()
	tel_erg.mode = Wl.ERG
	assert_eq(
		WorkoutRules.course_speed_grade(g.state, steep, tel_erg),
		g.state.course.grade_at(steep.course_d)
	)
	var no_course := WorkoutState.new()
	assert_eq(WorkoutRules.course_speed_grade(no_course, steep, tel_erg), 0.0)


func test_rescue_and_afk_are_staggers() -> void:
	var g := U.game("threshold", U.players(2))
	autofree(g)
	# Rider 2 is rescued for the first 60 s of the first threshold block (index 1, 300 s) and
	# AFK for the first 30 s of the second (index 3); the platform calls on_rescue / on_afk
	# on the transitions, as the GameHost does.
	var rescued := func(slot: PlayerSlot, p: PlanPhase, ps: PhaseState, tick: int) -> Dictionary:
		var v := U.compliant(slot, p, ps)
		if slot.peer_id != 2:
			return v
		if ps.index == 1 and ps.elapsed_s < 60.0:
			v["rescue"] = true
			v["power_w"] = 0.5 * slot.ftp
			v["applied_target_w"] = int(0.5 * slot.ftp)
		if ps.index == 3 and ps.elapsed_s < 30.0:
			v["afk"] = true
			v["power_w"] = 0.0
		if ps.index == 1 and is_zero_approx(ps.elapsed_s):
			g.on_rescue(2, true)
		elif ps.index == 1 and is_equal_approx(ps.elapsed_s, 60.0):
			g.on_rescue(2, false)
		elif ps.index == 3 and is_zero_approx(ps.elapsed_s):
			g.on_afk(2, true)
		elif ps.index == 3 and is_equal_approx(ps.elapsed_s, 30.0):
			g.on_afk(2, false)
		return v
	U.ride(g, rescued)
	var r := g.state.rider(2)
	assert_almost_eq(r.interval_fraction(1), (480.0 - 60.0) / 480.0, 0.001)
	assert_almost_eq(r.interval_fraction(3), (480.0 - 30.0) / 480.0, 0.001)
	assert_almost_eq(r.tib_s, 2220.0 - 90.0, 0.01, "only the time in band is lost")
	assert_almost_eq(g.state.rider(1).tib_s, 2220.0, 0.01)
	assert_false(r.rescue or r.afk, "both staggers ended")
	g.on_afk(2, true)
	assert_true(g.state.rider(2).afk)
	g.on_afk(2, false)
	assert_false(g.state.rider(2).afk)
	assert_eq(
		g.results().row(2)["xp"],
		WorkoutResults.xp_for(float(g.results().row(2)["kj"]), r.tib_fraction(), 0)
	)


## The platform may mark a rider AFK (a dropped peer, a rejoin before fresh pedaling) or
## rescued before telemetry says so: the callback alone keeps the rider out of band until
## its false call, and nothing else is taken away.
func test_callbacks_hold_until_cleared() -> void:
	var g := U.game("sweet_spot", U.players(2))
	autofree(g)
	var marked := func(slot: PlayerSlot, p: PlanPhase, ps: PhaseState, tick: int) -> Dictionary:
		if slot.peer_id == 2 and ps.index == 1:
			if is_equal_approx(ps.elapsed_s, 100.0):
				g.on_afk(2, true)
			elif is_equal_approx(ps.elapsed_s, 140.0):
				g.on_afk(2, false)
			elif is_equal_approx(ps.elapsed_s, 200.0):
				g.on_rescue(2, true)
			elif is_equal_approx(ps.elapsed_s, 210.0):
				g.on_rescue(2, false)
		return U.compliant(slot, p, ps)
	var events := U.ride(g, marked)
	var r := g.state.rider(2)
	assert_almost_eq(
		r.interval_fraction(1),
		(720.0 - 50.0) / 720.0,
		0.001,
		"40 s AFK + 10 s rescue, by callback only"
	)
	assert_almost_eq(g.state.rider(1).interval_fraction(1), 1.0, 0.0001)
	assert_false(r.afk_cb or r.rescue_cb)
	assert_false(r.afk or r.rescue)
	var end_1: Dictionary = U.of_type(events, WorkoutRules.EV_INTERVAL_END)[1]
	assert_eq(end_1["r"], [[1, 1000], [2, int(round((720.0 - 50.0) / 720.0 * 1000.0))]])
	# While marked, the snapshot shows the rider AFK to every client.
	g.on_afk(2, true)
	var snap := g.snapshot()
	assert_eq(int(snap["r"][1][4]) & WorkoutSnapshot.F_AFK, WorkoutSnapshot.F_AFK)


func test_every_built_in_session_grades_s_for_compliant_riders() -> void:
	for id: String in ["easy_30", "sweet_spot", "threshold", "vo2", "rolling_road", "e2e"]:
		var g := U.game(id, U.players(1, 1))
		var events := U.ride(g)
		var res := g.results()
		assert_eq(res.grade, "S", "%s grade" % id)
		for row in res.rows:
			assert_almost_eq(
				float(row["time_in_band_pct"]), 100.0, 0.01, "%s rider %s" % [id, row["peer_id"]]
			)
		var starts := U.of_type(events, WorkoutRules.EV_INTERVAL_START)
		assert_eq(
			starts.size(), g.state.phases.size(), "%s: a start per phase, cool-down included" % id
		)
		g.free()


func test_a_zero_watt_rider_grades_d() -> void:
	var g := U.game("e2e", U.players(1))
	autofree(g)
	var zero := func(slot: PlayerSlot, p: PlanPhase, ps: PhaseState, tick: int) -> Dictionary:
		var v := U.compliant(slot, p, ps)
		v["power_w"] = 0.0
		v["cadence_rpm"] = 0.0
		return v
	U.ride(g, zero)
	assert_eq(g.results().grade, "D")


func test_session_preview_for_every_content() -> void:
	var tr := U.register_strings()
	var g := WorkoutGame.new()
	autofree(g)
	for id: String in ["easy_30", "sweet_spot", "threshold", "vo2", "rolling_road", "e2e"]:
		var pv := g.session_preview(id)
		assert_false(pv.is_empty(), id)
		assert_ne(
			str(pv["title"]), "WORKOUT_CONTENT_" + id.to_upper(), "%s title is translated" % id
		)
	assert_string_contains(str(g.session_preview("easy_30")["lines"][2]), "Sprint 1")
	var road_line := str(g.session_preview("rolling_road")["lines"][1])
	assert_string_contains(road_line, "30:00")
	assert_string_contains(road_line, "76-105% FTP", "the session's own band")
	assert_eq(
		WorkoutSession.block_label(g.ctx.strings if g.ctx != null else GameStrings.new(), 3),
		"Block 3"
	)
	U.unregister_strings(tr)
	assert_eq(
		WorkoutSession.block_label(GameStrings.new(), 4),
		"Block 4",
		"plain text without the strings table, never the key"
	)
	assert_eq(WorkoutSession.block_label(null, 5), "Block 5")
