extends GutTest
## Sprint scoring (BRIEF 3.5, 3.7): FREE sprints score under the sprint rule, power >= 1.2 x
## FTP; a sprint is a hit once the rule held for 3 s in a row; peaks are reported per rider.

const U := preload("res://tests/games/workout/workout_test_util.gd")
const DT := 0.05


func test_threshold_comes_from_the_sprint_rule() -> void:
	var t := WorkoutSprintTracker.create(250.0, 4)
	assert_almost_eq(t.threshold_w, 300.0, 0.001)
	assert_almost_eq(t.threshold_w, SprintRule.create(250.0).threshold_w(), 0.001)
	assert_eq(t.phase_index, 4)


func test_streaks_peaks_and_hits() -> void:
	var t := WorkoutSprintTracker.create(200.0)
	for i in 40:
		t.update(250.0, DT)
	assert_almost_eq(t.best_s, 2.0, 0.001)
	assert_false(t.hit(), "2 s is not enough")
	t.update(100.0, DT)
	assert_eq(t.streak_s, 0.0, "a dip ends the streak")
	for i in 60:
		t.update(240.0, DT)
	assert_true(t.hit(), "exactly 1.2 x FTP for 3 s counts")
	t.update(900.0, DT)
	var res := t.result()
	assert_eq(res["peak_w"], 900)
	assert_almost_eq(t.held_s, 5.05, 0.001)
	assert_almost_eq(float(res["held_s"]), snappedf(t.held_s, 0.1), 0.0001, "results round to 0.1 s")
	assert_true(bool(res["hit"]))


func test_sprint_events_and_toasts_in_a_session() -> void:
	var players := U.players(1, 1, 200.0)
	var g := U.game("easy_30", players)
	var weak := func(slot: PlayerSlot, p: PlanPhase, ps: PhaseState, tick: int) -> Dictionary:
		var v := U.compliant(slot, p, ps)
		if p.kind == Wl.FREE and slot.is_bot:
			v["power_w"] = 230.0
		return v
	var events := U.ride(g, weak)
	var sprints := U.of_type(events, WorkoutRules.EV_SPRINT)
	assert_eq(sprints.size(), 3, "one result per sprint")
	var free_indices: Array[int] = []
	for i in g.state.phases.size():
		if g.state.phases[i].kind == Wl.FREE:
			free_indices.append(i)
	for k in 3:
		var e := sprints[k]
		assert_eq(int(e["i"]), free_indices[k])
		assert_eq(e["r"][0][0], 1)
		assert_eq(e["r"][0][1], 280, "human peak 1.4 x FTP")
		assert_eq(e["r"][0][2], 100, "held 10.0 s in a row")
		assert_eq(e["r"][0][3], 1, "hit")
		assert_eq(e["r"][1][0], -1)
		assert_eq(e["r"][1][3], 0, "230 W stays under 240 W")
	var r := g.state.rider(1)
	assert_eq(r.sprints.size(), 3)
	var hud: U.FakeHud = g.ctx.hud
	var hits := 0
	for c in hud.of("toast"):
		if c["key"] == "WORKOUT_TOAST_SPRINT_HIT":
			hits += 1
			assert_eq(c["peer"], 1, "sprint toasts go to that rider only")
		assert_ne(c["peer"], -1, "no toasts for bots")
	assert_eq(hits, 3)
	var warned := 0
	for c in hud.of("toast"):
		if c["key"] == "WORKOUT_TOAST_SPRINT_SOON":
			warned += 1
			assert_eq(c["peer"], Wl.ALL_PEERS)
	assert_eq(warned, 3, "a countdown before each sprint")
	g.free()


func test_sprint_bands_on_the_gauge() -> void:
	var g := U.game("easy_30", U.players(1, 1, 200.0))
	U.ride(g)
	var hud: U.FakeHud = g.ctx.hud
	var bands := hud.of("power_band")
	# 3 sprints x 2 riders set a band, 3 x 2 clear it on the ERG phase after.
	assert_eq(bands.size(), 12, str(bands))
	assert_eq([bands[0]["lo"], bands[0]["hi"]], [240.0, 320.0], "120-160% FTP")
	assert_eq([bands[2]["lo"], bands[2]["hi"]], [0.0, 0.0], "cleared in ERG")
	g.free()


func test_no_sprint_band_inside_the_warmup() -> void:
	var g := U.game("e2e", U.players(1))
	var events := U.ride(g)
	var hud: U.FakeHud = g.ctx.hud
	assert_eq(hud.of("power_band").size(), 0, "the e2e sprint starts at 90 s: no band")
	assert_eq(U.of_type(events, WorkoutRules.EV_SPRINT).size(), 1, "it is still scored")
	g.free()


## A rider whose phase lags the lead by a few ticks has its sprint scored with everyone's
## when the lead leaves the sprint; its last ticks in the sprint start no second result.
func test_a_lagging_rider_is_scored_once_per_sprint() -> void:
	var players := U.players(2)
	var g := U.game("e2e", players)
	autofree(g)
	var events: Array[Dictionary] = []
	g.game_event.connect(func(e: Dictionary) -> void: events.append(e))
	var timeline := g.state.phases
	var starts := U.phase_ticks(timeline)
	for tick in starts[3] + 20:
		var frame := InputFrame.new()
		frame.tick = tick
		frame.t = float(tick) * DT
		for slot in players:
			var t := tick if slot.peer_id == 1 else maxi(tick - 3, 0)
			var ps := U.phase_state(timeline, starts, t)
			frame.players[slot.peer_id] = U.telemetry(slot, U.compliant(slot, timeline[ps.index], ps), tick)
			frame.phase[slot.peer_id] = ps
		g.sim_step(DT, frame)
	var sprints := U.of_type(events, WorkoutRules.EV_SPRINT)
	assert_eq(sprints.size(), 1)
	assert_eq((sprints[0]["r"] as Array).size(), 2, "both riders in the one sprint event")
	for peer: int in [1, 2]:
		var r := g.state.rider(peer)
		assert_eq(r.sprints.size(), 1, "rider %d: one sprint result" % peer)
		assert_eq(int(r.sprints[0]["i"]), 2)
		assert_null(r.sprint, "no tracker left running")
	assert_eq((g.results().row(2)["sprints"] as Array).size(), 1)


## W3 WO-6 (BRIEF 3.7 separates "free sprints" from "FREE phases"): a FREE phase longer than
## 30 s (an imported 10-minute FreeRide) is free riding: no 120-160 % band, a free-ride banner
## instead of the sprint banner, no "Sprint in" countdown and no sprint result. A 30 s FREE
## phase after the warm-up is still a sprint.
func test_a_long_free_ride_is_no_sprint() -> void:
	var g := U.game("e2e", U.players(1, 0, 200.0))
	var warm := PlanPhase.erg(Wl.WARMUP, 50.0, 300.0, "WORKOUT_LBL_WARMUP").with_ramp(65.0).with_lap()
	var free := PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, 600.0, "Free ride").with_lap()
	var work := PlanPhase.erg(Wl.WORK, 75.0, 120.0, "WORKOUT_LBL_ENDURANCE").with_lap()
	var timeline: Array[PlanPhase] = [warm, free, work]
	g.state.set_timeline(timeline)
	var r := g.state.rider(1)
	assert_false(WorkoutSession.is_sprint(free))
	assert_eq(WorkoutHud.band_for(g.state, 1, r), [], "no sprint band for a 10-minute free ride")
	assert_eq(WorkoutHud.interval_banner(g.state, 1, g.ctx.strings)["key"], "WORKOUT_BANNER_FREE")
	var events := U.ride(g)
	assert_eq(U.of_type(events, WorkoutRules.EV_SPRINT).size(), 0, "a free ride scores no sprint")
	assert_eq(r.sprints.size(), 0)
	var hud: U.FakeHud = g.ctx.hud
	for c in hud.of("toast"):
		assert_ne(c["key"], "WORKOUT_TOAST_SPRINT_SOON", "no sprint countdown")
	assert_eq(hud.of("power_band").size(), 0, "no band during the free ride")
	g.free()
	var g2 := U.game("e2e", U.players(1, 0, 200.0))
	var sprint := PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, 30.0, "WORKOUT_LBL_SPRINT").with_lap()
	var timeline2: Array[PlanPhase] = [warm, sprint, work]
	g2.state.set_timeline(timeline2)
	assert_true(WorkoutSession.is_sprint(sprint))
	assert_eq(WorkoutHud.band_for(g2.state, 1, g2.state.rider(1)), [240.0, 320.0], "a 30 s sprint keeps its band")
	assert_eq(WorkoutHud.interval_banner(g2.state, 1, g2.ctx.strings)["key"], "WORKOUT_BANNER_SPRINT")
	assert_eq(U.of_type(U.ride(g2), WorkoutRules.EV_SPRINT).size(), 1, "and its score")
	g2.free()
