extends GutTest
## WorkoutHudModel: the instruction and target lines, the whole-session timeline, a client's time in
## band from the snapshot, the NEXT line, and the bands.

const U := preload("res://tests/games/workout/workout_test_util.gd")
const D := preload("res://src/games/workout/hud/workout_hud_draw.gd")
const M := preload("res://src/games/workout/hud/workout_hud_model.gd")

var _tr: Translation = null


func before_all() -> void:
	_tr = U.register_strings()


func after_all() -> void:
	U.unregister_strings(_tr)


## A game at plan time `t`, every rider in the phase there.
func _game_at(content: String, t: float, humans: int = 1, role: String = Wl.SOLO) -> WorkoutGame:
	var g: WorkoutGame = autofree(U.game(content, U.players(humans), role, 1))
	g.state.plan_t = t
	var i := 0
	while i + 1 < g.state.phases.size() and g.state.phase_start_s(i + 1) <= t:
		i += 1
	g.state.phase_index = i
	for r: WorkoutRiderState in g.state.riders.values():
		r.phase_index = i
	return g


func _tm(power: float = 130.0, cadence: float = 90.0, mode: String = Wl.ERG) -> Telemetry:
	var t := Telemetry.new()
	t.peer_id = 1
	t.t = 100.0
	t.power_w = power
	t.cadence_rpm = cadence
	t.mode = mode
	t.applied_target_w = 130 if mode == Wl.ERG else 0
	t.wbal_j = 20000.0
	t.gear = 12
	return t


func _instruction(g: WorkoutGame, t: Telemetry = null, low: bool = false) -> Dictionary:
	var r := g.state.rider(1)
	return M.instruction(g.state, M.phase_index(g.state, r), r, t, low)


func _target(g: WorkoutGame, t: Telemetry = null) -> Dictionary:
	var r := g.state.rider(1)
	return M.target_text(g.state, M.phase_index(g.state, r), r, t)


# --- instruction ---------------------------------------------------------------------


func test_instruction_low_cadence_and_rescue_come_first() -> void:
	var g := _game_at("easy_30", 400.0)
	var line := _instruction(g, _tm(), true)
	assert_eq(line["key"], "WORKOUT_HUD_DO_SPIN")
	assert_eq(line["args"], [roundi(HudRiderNumbers.RESCUE_RECOVER_RPM)])
	assert_true(line["urgent"])
	assert_eq(M.say(g, line), "SPIN 70+ RPM")
	var rescued := _tm()
	rescued.rescue = true
	assert_eq(_instruction(g, rescued)["key"], "WORKOUT_HUD_DO_SPIN", "rescue says the same")


func test_instruction_by_phase() -> void:
	var erg := _game_at("easy_30", 400.0)
	assert_eq(M.say(erg, _instruction(erg, _tm())), "HOLD 130 W")
	assert_false(_instruction(erg, _tm())["urgent"])
	var sprint := _game_at("easy_30", 670.0)
	assert_eq(M.say(sprint, _instruction(sprint, _tm(300.0, 100.0, Wl.SIM))), "SPRINT 240+ W")
	var rolling := _game_at("rolling_road", 600.0)
	assert_eq(M.say(rolling, _instruction(rolling, _tm(180.0, 90.0, Wl.SIM))), "HOLD 152-210 W")
	var warm_sprint := _game_at("e2e", 100.0)
	assert_eq(M.say(warm_sprint, _instruction(warm_sprint)), "FREE RIDE", "a warm-up sprint")
	var cool := _game_at("easy_30", cool_start(erg) + 10.0)
	assert_eq(M.say(cool, _instruction(cool, _tm())), "EASY SPIN")


func cool_start(g: WorkoutGame) -> float:
	return g.state.phase_start_s(g.state.phases.size() - 1)


func test_instruction_fits_the_plate_at_scale_2() -> void:
	for line: String in [
		"HOLD 1000 W", "HOLD 152-210 W", "SPRINT 1240+ W", "SPIN 70+ RPM", "EASY SPIN"
	]:
		assert_lte(D.text_w(line, 2), 210.0, line)


func test_instruction_without_telemetry_uses_the_plan() -> void:
	var g := _game_at("easy_30", 400.0)
	assert_eq(M.say(g, _instruction(g)), "HOLD 130 W", "65% of a 200 W FTP")


# --- target ----------------------------------------------------------------------------


func test_target_text() -> void:
	var erg := _game_at("easy_30", 400.0)
	assert_eq(M.say(erg, _target(erg, _tm())), "65% FTP  130 W")
	var ramp := _game_at("easy_30", 100.0)
	assert_eq(M.say(ramp, _target(ramp)), "50 > 65% FTP")
	var rolling := _game_at("rolling_road", 600.0)
	assert_eq(M.say(rolling, _target(rolling)), "HOLD 152-210 W")
	var sprint := _game_at("easy_30", 670.0)
	assert_eq(M.say(sprint, _target(sprint)), "SPRINT 240+ W")
	var cool := _game_at("easy_30", cool_start(erg) + 10.0)
	assert_eq(M.say(cool, _target(cool)), "EASY")


func test_a_warm_up_sprint_is_free_ride_never_sprint() -> void:
	var g := _game_at("e2e", 100.0)
	assert_true(
		WorkoutSession.is_sprint(g.state.phase(g.state.phase_index)), "it is a sprint phase"
	)
	assert_eq(_target(g)["key"], "WORKOUT_HUD_FREE_RIDE")
	assert_eq(M.say(g, _target(g)), "FREE RIDE")
	assert_false(M.say(g, _target(g)).contains("SPRINT"))


func test_the_erg_target_prefers_the_applied_watts() -> void:
	var g := _game_at("easy_30", 400.0)
	var t := _tm()
	t.applied_target_w = 111
	assert_eq(M.say(g, _target(g, t)), "65% FTP  111 W", "what the trainer really holds")


func test_the_ramp_target_is_where_the_ramp_is() -> void:
	var g := _game_at("easy_30", 150.0)
	var r := g.state.rider(1)
	assert_almost_eq(M.target_w(g.state, 0, r, null), 115.0, 0.01, "half way from 100 to 130 W")


# --- bands -----------------------------------------------------------------------------


func test_power_band_erg_and_sim() -> void:
	var g := _game_at("easy_30", 400.0)
	var r := g.state.rider(1)
	var i := M.phase_index(g.state, r)
	assert_eq(M.power_band(g.state, i, r, _tm(), Vector2(1, 2)), Vector2(123.5, 136.5), "ERG +- 5%")
	var sim := _tm(200.0, 90.0, Wl.SIM)
	assert_eq(
		M.power_band(g.state, i, r, sim, Vector2(152, 210)), Vector2(152, 210), "the published one"
	)
	assert_eq(M.power_band(g.state, i, r, sim, Vector2.ZERO), Vector2.ZERO)


# --- timeline --------------------------------------------------------------------------


func _phases(durations: Array) -> Array[PlanPhase]:
	var out: Array[PlanPhase] = []
	for d: Variant in durations:
		out.append(PlanPhase.erg(Wl.WORK, 65.0, float(d), "x"))
	return out


func test_timeline_columns_three_phases() -> void:
	var cols := M.timeline_columns(_phases([10.0, 20.0, 10.0]), 40)
	assert_eq(cols.size(), 40)
	var counts := [0, 0, 0]
	for c in cols:
		counts[c] += 1
	assert_eq(counts, [10, 20, 10], "by time")
	assert_eq(cols[0], 0)
	assert_eq(cols[39], 2)


func test_timeline_columns_400_phases() -> void:
	var durations: Array = []
	for i in 400:
		durations.append(30.0 if i % 2 == 0 else 60.0)
	var cols := M.timeline_columns(_phases(durations), M.TIMELINE_COLUMNS)
	assert_eq(cols.size(), M.TIMELINE_COLUMNS)
	var prev := -1
	for c in cols:
		assert_true(c >= prev and c < 400, "monotonic, in range")
		prev = c
	assert_eq(cols[0], 0)
	assert_eq(cols[M.TIMELINE_COLUMNS - 1], 399, "the last phase shows")


func test_timeline_columns_empty_and_zero_length() -> void:
	assert_eq(M.timeline_columns(_phases([]), 468).size(), 0)
	assert_eq(M.timeline_columns(_phases([10.0]), 0).size(), 0)
	assert_eq(M.timeline_columns(_phases([0.0, 0.0]), 4).size(), 4, "no division by zero")


func test_timeline_runs_cover_the_strip_merged() -> void:
	for content: String in ["easy_30", "rolling_road", "e2e"]:
		var g := _game_at(content, 0.0)
		var runs := M.timeline_runs(g.state, M.TIMELINE_COLUMNS)
		var x := 0
		for run: Dictionary in runs:
			assert_eq(int(run["x"]), x, "%s: contiguous" % content)
			assert_gt(int(run["w"]), 0)
			assert_true(int(run["h"]) >= M.TIMELINE_MIN_H and int(run["h"]) <= M.TIMELINE_H)
			x += int(run["w"])
		assert_eq(x, M.TIMELINE_COLUMNS, "%s: the whole strip" % content)
		assert_lt(runs.size(), 40, "%s: runs, not columns" % content)


func test_a_ramp_is_a_stair_and_sim_and_free_are_hatched() -> void:
	var g := _game_at("easy_30", 0.0)
	var runs := M.timeline_runs(g.state, M.TIMELINE_COLUMNS)
	var heights: Array[int] = []
	for run: Dictionary in runs:
		var p := g.state.phase(int(run["phase"]))
		assert_eq(bool(run["hatched"]), p.kind == Wl.FREE or p.mode == Wl.SIM, "hatch by phase")
		if int(run["phase"]) == 0:
			heights.append(int(run["h"]))
	assert_gt(heights.size(), 1, "the warm-up ramp climbs")
	assert_gt(heights[heights.size() - 1], heights[0])


func test_timeline_words_and_now_mark() -> void:
	var g := _game_at("sweet_spot", 400.0, 2)
	var tl := M.timeline(g, null)
	assert_eq(tl["label"], "SWEET SPOT 1")
	assert_eq(tl["index"], 1)
	assert_almost_eq(float(tl["phase_left_s"]), 620.0, 0.01)
	var total := g.state.total_s()
	assert_almost_eq(float(tl["session_left_s"]), total - 400.0, 0.01)
	assert_eq(int(tl["now_x"]), roundi(400.0 / total * M.TIMELINE_COLUMNS))
	assert_string_contains(str(tl["next"]), "Recovery 1")


func test_next_uses_the_banner_text_and_the_cool_down_its_own_key() -> void:
	var g := _game_at("sweet_spot", 400.0)
	var i := M.phase_index(g.state, g.state.rider(1)) + 1
	var banner := WorkoutHud.interval_banner(g.state, i, g.ctx.strings)
	assert_eq(
		M.next_text(g, i), g.ctx.strings.t(banner["key"], banner["args"]), "the banner's words"
	)
	var last := g.state.phases.size() - 1
	assert_eq(
		WorkoutHud.interval_banner(g.state, last, g.ctx.strings), {}, "the host's stays empty"
	)
	assert_eq(M.next_text(g, last), "Cool-down: 50% FTP for 3:00")
	assert_eq(M.next_text(g, last + 1), "Finish")


func test_next_never_calls_a_warm_up_sprint_a_sprint() -> void:
	var g := _game_at("e2e", 70.0)
	var next := M.next_text(g, M.phase_index(g.state, g.state.rider(1)) + 1)
	assert_false(next.contains("Shift up"), next)
	assert_string_contains(next, "ride free")


func test_timeline_before_the_first_step() -> void:
	var g: WorkoutGame = autofree(U.game("easy_30", U.players(1)))
	assert_eq(g.state.phase_index, -1)
	var tl := M.timeline(g, null)
	assert_eq(tl["index"], 0)
	assert_eq(tl["label"], "WARM-UP")


# --- time in band -----------------------------------------------------------------------


func test_client_time_in_band_comes_from_the_snapshot() -> void:
	var g := _game_at("sweet_spot", 400.0, 2, Wl.CLIENT)
	var r := g.state.rider(1)
	r.snap_tib_permille = 930
	r.snap_interval_permille = 960
	g.state.rider(2).snap_tib_permille = 910
	assert_eq(r.tib_fraction(), 0.0, "the trap: 0 on clients")
	assert_almost_eq(M.tib(g, r), 0.93, 1e-6)
	assert_almost_eq(M.block_tib(g, r), 0.96, 1e-6)
	assert_almost_eq(M.group_tib(g), 0.92, 1e-6)
	var s := M.score(g, null, 0.0)
	assert_eq(s["tib"], "93")
	assert_eq(s["grade"], "A")
	assert_eq(s["block"], "BLOCK 96%")
	assert_eq(s["group"], "GROUP 92%")


func test_host_time_in_band_comes_from_the_rider() -> void:
	var g := _game_at("sweet_spot", 400.0, 2)
	var r := g.state.rider(1)
	r.add_interval_time(1, true, 9.0)
	r.add_interval_time(1, false, 1.0)
	assert_almost_eq(M.tib(g, r), 0.9, 1e-6)
	assert_almost_eq(M.block_tib(g, r), 0.9, 1e-6)
	assert_almost_eq(M.group_tib(g), 0.45, 1e-6, "the other rider has none")


# --- crew --------------------------------------------------------------------------------


func test_card_rects_fill_from_the_bottom_row() -> void:
	assert_eq(M.card_rect(0), Rect2i(1, 34, 102, 32))
	assert_eq(M.card_rect(3), Rect2i(313, 34, 102, 32))
	assert_eq(M.card_rect(4), Rect2i(1, 0, 102, 32))
	assert_eq(M.card_rect(7), Rect2i(313, 0, 102, 32))
	var plate := Rect2i(Vector2i.ZERO, WorkoutHud.LAYOUT["crew"].size)
	for i in Wl.MAX_SLOTS:
		assert_true(plate.encloses(M.card_rect(i)), "card %d" % i)
		for j in i:
			assert_false(M.card_rect(i).intersects(M.card_rect(j)), "cards %d, %d" % [i, j])


func test_crew_reads_the_roster_first() -> void:
	var g := _game_at("sweet_spot", 400.0, 2)
	g.state.rider(2).power_w = 100.0
	g.ctx.roster = {
		2:
		{
			"raw_w": 182.0,
			"ftp_pct": 91.0,
			"rescue": false,
			"afk": false,
			"connected": true,
			"status": {"in_band": true},
		}
	}
	var cards := M.crew(g)
	assert_eq(cards.size(), 2)
	assert_true(cards[0]["local"])
	assert_false(cards[1]["local"])
	assert_eq(cards[1]["line"], "182W 91%")
	assert_true(cards[1]["in_band"])
	assert_eq(cards[1]["name"], "Rider 2")
	assert_eq(cards[1]["slot"], 1)


func test_crew_falls_back_on_the_state() -> void:
	var g := _game_at("sweet_spot", 400.0, 2)
	var r := g.state.rider(2)
	r.power_w = 180.0
	r.in_band = true
	var c := M.crew(g)[1]
	assert_eq(c["line"], "180W 90%")
	assert_true(c["in_band"])
	assert_eq(c["flag"], "")
	assert_eq(c["tib"], "0%")


func test_score_in_a_sprint_and_on_a_course() -> void:
	var sprint := _game_at("easy_30", 670.0)
	assert_eq(M.score(sprint, _tm(300.0, 100.0, Wl.SIM), 412.0)["peak"], "PEAK 412 W")
	var warm := _game_at("e2e", 100.0)
	assert_eq(M.score(warm, _tm(300.0, 100.0, Wl.SIM), 412.0)["peak"], "", "no peak in the warm-up")
	var erg := _game_at("easy_30", 400.0)
	assert_eq(M.score(erg, _tm(), 300.0)["peak"], "")
	assert_eq(M.score(erg, _tm(), 0.0)["grade_pct"], "", "no grade off a course")
	var road := _game_at("rolling_road", 600.0)
	var t := _tm(180.0, 90.0, Wl.SIM)
	t.applied_grade_pct = 4.2
	assert_eq(M.score(road, t, 0.0)["grade_pct"], "+4.2%")
	t.applied_grade_pct = -3.0
	assert_eq(M.score(road, t, 0.0)["grade_pct"], "-3.0%")


func test_score_speed_and_distance() -> void:
	var g := _game_at("easy_30", 400.0)
	var r := g.state.rider(1)
	r.speed.v_mps = 9.0
	r.speed.distance_m = 12345.0
	var s := M.score(g, null, 0.0)
	assert_eq(s["speed"], "32.4 KM/H")
	assert_eq(s["km"], "12.3 KM")
	assert_eq(s["group"], "", "a solo rider has no group score")
