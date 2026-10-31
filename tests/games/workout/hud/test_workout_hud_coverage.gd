extends GutTest
## What must be on screen (BRIEF 3.1, 3.7, 3.9), each item asserted from the model: raw W, %FTP, W/kg
## opt-in; target band with in-band state; HR; cadence with band and stale dim; the low-cadence
## warning; W' with low; phase, time left, next preview, whole timeline; TIB session and block; crew
## compliance, rescue, AFK, disconnected; gear in SIM; platform banners, toasts, rescue and link
## notices in the rects the HUD gives them.

const U := preload("res://tests/games/workout/workout_test_util.gd")
const M := preload("res://src/games/workout/hud/workout_hud_model.gd")

var _tr: Translation = null


func before_all() -> void:
	_tr = U.register_strings()


func after_all() -> void:
	U.unregister_strings(_tr)


func _game_at(content: String, t: float, humans: int = 2) -> WorkoutGame:
	var g: WorkoutGame = autofree(U.game(content, U.players(humans)))
	g.state.plan_t = t
	var i := 0
	while i + 1 < g.state.phases.size() and g.state.phase_start_s(i + 1) <= t:
		i += 1
	g.state.phase_index = i
	for r: WorkoutRiderState in g.state.riders.values():
		r.phase_index = i
	return g


func _tm(t: float, power: float, cadence: float = 90.0, mode: String = Wl.ERG) -> Telemetry:
	var tm := Telemetry.new()
	tm.peer_id = 1
	tm.t = t
	tm.power_w = power
	tm.cadence_rpm = cadence
	tm.mode = mode
	tm.applied_target_w = 130 if mode == Wl.ERG else 0
	tm.wbal_j = 20000.0
	tm.gear = 15
	return tm


## The mine plate's model after `samples` seconds of `tm`, as the Control would compute it.
func _mine(
	g: WorkoutGame,
	tm: Telemetry,
	weight: float = 0.0,
	nums: HudRiderNumbers = null,
	cadence_band := Vector2.ZERO,
	published := Vector2.ZERO
) -> Dictionary:
	var n := nums if nums != null else _numbers()
	var r := g.state.rider(1)
	var band := M.power_band(g.state, M.phase_index(g.state, r), r, tm, published)
	n.ftp_w = r.ftp
	if tm != null:
		tm.peer_id = 1
		for i in 4:
			var s := tm.duplicate_telemetry()
			s.t = tm.t + float(i)
			n.feed(s)
	n.set_band(band.x, band.y)
	return M.mine(g, n, tm, cadence_band, weight)


func _numbers() -> HudRiderNumbers:
	var n := HudRiderNumbers.new()
	n.sensor_status_override = TrainerDevice.STATUS_DISCONNECTED
	return n


func test_raw_watts_and_ftp_percent() -> void:
	var m := _mine(_game_at("easy_30", 400.0), _tm(10.0, 182.0))
	assert_eq(m["watts"], "182", "the mean, in raw W")
	assert_eq(m["pct"], "91%")


func test_watts_show_the_mean_not_the_latest_sample() -> void:
	var g := _game_at("easy_30", 400.0)
	var n := _numbers()
	n.feed(_tm(1.0, 100.0))
	n.feed(_tm(2.0, 100.0))
	n.feed(_tm(3.0, 100.0))
	var last := _tm(4.0, 400.0)
	n.feed(last)
	var m := M.mine(g, n, last, Vector2.ZERO, 0.0)
	assert_lt(int(m["watts"]), 400, "a 3 s mean")
	assert_gt(int(m["watts"]), 100)


func test_stale_power_shows_dashes() -> void:
	var g := _game_at("easy_30", 400.0)
	var stale := _tm(10.0, 0.0, 0.0)
	stale.cadence_age_s = 5.0
	var m := _mine(g, stale)
	assert_eq(m["watts"], "--")
	assert_eq(m["pct"], "--")
	assert_lt(float(m["gauge_v"]), 0.0, "no needle")
	assert_false(m["in_band"])


func test_no_telemetry_yet_shows_dashes() -> void:
	var g := _game_at("easy_30", 400.0)
	var m := _mine(g, null)
	assert_eq(m["watts"], "--")
	assert_eq(m["cadence"], "--")
	assert_true(m["cadence_dim"])
	assert_lt(float(m["wbal"]), 0.0)
	assert_eq(m["wbal_pct"], "--")
	assert_eq(m["gear"], "-")
	assert_false(m["gear_lit"])
	assert_eq(m["line"], "HOLD 130 W", "the plan still says what to do")
	assert_eq(m["mode"], Wl.ERG)


func test_zero_watts_with_a_fresh_cadence_is_a_rider_who_stopped() -> void:
	var m := _mine(_game_at("easy_30", 400.0), _tm(10.0, 0.0, 0.0))
	assert_eq(m["watts"], "0")


func test_wkg_only_when_opted_in() -> void:
	var g := _game_at("easy_30", 400.0)
	assert_eq(_mine(g, _tm(10.0, 180.0))["wkg"], "", "off by default")
	assert_eq(_mine(g, _tm(10.0, 180.0), 75.0)["wkg"], "2.4 W/KG")


func test_target_band_with_in_band_state() -> void:
	var g := _game_at("easy_30", 400.0)
	var inside := _mine(g, _tm(10.0, 130.0))
	assert_true(inside["in_band"])
	assert_eq(inside["band_state"], HudRiderNumbers.IN_BAND)
	assert_eq(inside["band"], Vector2(123.5, 136.5))
	assert_gt(float(inside["gauge_hi"]), float(inside["gauge_lo"]))
	var under := _mine(g, _tm(10.0, 60.0))
	assert_false(under["in_band"])
	assert_eq(under["band_state"], HudRiderNumbers.UNDER)
	var over := _mine(g, _tm(10.0, 300.0))
	assert_eq(over["band_state"], HudRiderNumbers.OVER)


func test_sim_band_comes_from_the_published_band() -> void:
	var g := _game_at("rolling_road", 600.0)
	var m := _mine(g, _tm(10.0, 180.0, 90.0, Wl.SIM), 0.0, null, Vector2.ZERO, Vector2(152, 210))
	assert_eq(m["band"], Vector2(152, 210))
	assert_true(m["in_band"])


func test_heart_rate_three_states() -> void:
	var g := _game_at("easy_30", 400.0)
	var none := _mine(g, _tm(10.0, 130.0))
	assert_eq(none["hr_state"], HudRiderNumbers.HR_NONE, "no sensor: no cell")
	var live := _tm(10.0, 130.0)
	live.heart_rate_bpm = 142
	var n := _numbers()
	var on := _mine(g, live, 0.0, n)
	assert_eq(on["hr_state"], HudRiderNumbers.HR_LIVE)
	assert_eq(on["hr"], "142")
	var dropped := _mine(g, _tm(20.0, 130.0), 0.0, n)
	assert_eq(dropped["hr_state"], HudRiderNumbers.HR_DROPOUT)
	assert_eq(dropped["hr"], "--")


func test_cadence_with_band_and_stale_dim() -> void:
	var g := _game_at("easy_30", 400.0)
	var m := _mine(g, _tm(10.0, 130.0, 90.0), 0.0, null, Vector2(80, 100))
	assert_eq(m["cadence"], "90")
	assert_false(m["cadence_dim"])
	assert_true(m["cadence_in"])
	assert_gt(float(m["cadence_hi"]), float(m["cadence_lo"]))
	var stale := _tm(10.0, 130.0, 90.0)
	stale.cadence_age_s = 5.0
	assert_true(_mine(g, stale)["cadence_dim"])


func test_a_free_phase_has_the_default_cadence_band() -> void:
	var g := _game_at("easy_30", 670.0)
	var m := _mine(g, _tm(10.0, 300.0, 100.0, Wl.SIM))
	assert_almost_eq(float(m["cadence_lo"]), inverse_lerp(30.0, 150.0, 60.0), 1e-5)
	assert_almost_eq(float(m["cadence_hi"]), inverse_lerp(30.0, 150.0, 140.0), 1e-5)
	var erg := _mine(_game_at("easy_30", 400.0), _tm(10.0, 130.0))
	assert_eq(float(erg["cadence_hi"]), 0.0, "ERG with no band published shows none")


func test_the_crank_icon_turns_with_the_riders_own_revs() -> void:
	var g := _game_at("easy_30", 400.0)
	g.cranks.step(1, 60.0, 0.5)
	assert_eq(_mine(g, _tm(10.0, 130.0))["crank_frame"], WorkoutRig.crank_frame(0.5))
	assert_eq(_mine(g, _tm(10.0, 130.0))["crank_frame"], 12)


func test_low_cadence_warning() -> void:
	var g := _game_at("easy_30", 400.0)
	var n := _numbers()
	var low := _tm(10.0, 130.0, 50.0)
	var m := _mine(g, low, 0.0, n)
	assert_true(n.low_cadence(), "rescue armed, under 70 rpm for 1.5 s")
	assert_eq(m["line"], "SPIN 70+ RPM")
	assert_true(m["urgent"])


func test_wprime_with_low() -> void:
	var g := _game_at("easy_30", 400.0)
	var fine := _mine(g, _tm(10.0, 130.0))
	assert_almost_eq(float(fine["wbal"]), 1.0, 1e-6)
	assert_false(fine["wbal_low"])
	assert_eq(fine["wbal_pct"], "100%")
	var t := _tm(10.0, 130.0)
	t.wbal_j = 3000.0
	var low := _mine(g, t)
	assert_true(low["wbal_low"])
	assert_eq(low["wbal_pct"], "15%")


func test_gear_only_lit_in_sim() -> void:
	var g := _game_at("rolling_road", 600.0)
	var sim := _mine(g, _tm(10.0, 180.0, 90.0, Wl.SIM))
	assert_true(sim["gear_lit"])
	assert_eq(sim["gear"], "15")
	assert_almost_eq(float(sim["gear_f"]), 15.0 / 24.0, 1e-6)
	var erg := _mine(_game_at("easy_30", 400.0), _tm(10.0, 130.0))
	assert_false(erg["gear_lit"])
	assert_eq(erg["gear"], "-")
	assert_eq(float(erg["gear_f"]), 0.0)


func test_phase_time_left_next_and_the_whole_timeline() -> void:
	var g := _game_at("sweet_spot", 400.0)
	var tl := M.timeline(g, _tm(10.0, 180.0))
	assert_eq(tl["label"], "SWEET SPOT 1")
	assert_ne(str(tl["target"]), "")
	assert_gt(float(tl["phase_left_s"]), 0.0)
	assert_ne(str(tl["next"]), "")
	assert_gt(float(tl["session_left_s"]), float(tl["phase_left_s"]))
	var seen := {}
	for run: Dictionary in M.timeline_runs(g.state, M.TIMELINE_COLUMNS):
		seen[int(run["phase"])] = true
	assert_eq(seen.size(), g.state.phases.size(), "every phase, the cool-down too")


func test_time_in_band_session_and_block() -> void:
	var g := _game_at("sweet_spot", 400.0)
	var r := g.state.rider(1)
	r.add_interval_time(0, true, 50.0)
	r.add_interval_time(1, true, 48.0)
	r.add_interval_time(1, false, 2.0)
	var s := M.score(g, null, 0.0)
	assert_eq(s["tib"], "98")
	assert_eq(s["grade"], "S")
	assert_eq(s["block"], "BLOCK 96%")


func test_crew_compliance_rescue_afk_and_disconnected() -> void:
	var g := _game_at("sweet_spot", 400.0, 4)
	var riders := g.state
	riders.rider(1).in_band = true
	riders.rider(2).rescue = true
	riders.rider(3).afk = true
	riders.rider(4).connected = false
	riders.rider(4).afk = true
	var cards := M.crew(g)
	assert_true(cards[0]["in_band"], "compliance lamp")
	assert_eq(cards[0]["flag"], "")
	assert_eq(cards[0]["tib"], "0%")
	assert_eq(cards[1]["flag"], "RESCUE")
	assert_true(cards[1]["flag_over"])
	assert_eq(cards[2]["flag"], "AFK")
	assert_false(cards[2]["flag_over"])
	assert_eq(cards[3]["flag"], "LINK", "a dropped rider is also AFK: the link wins")
	assert_eq(cards[3]["line"], "--W", "no number for a dropped rider")
	assert_false(cards[3]["in_band"])


func test_platform_notices_have_their_rects() -> void:
	var spec := WorkoutHud.spec(_game_at("easy_30", 400.0))
	assert_true(spec.show_safety_banners, "warm-up and pause banners stay")
	assert_eq(spec.toast_area, WorkoutHud.LAYOUT["toasts"])
	assert_eq(spec.banner_area, WorkoutHud.LAYOUT["banners"])
	assert_true(spec.shows_power, "the mine plate shows raw W and %FTP")
	for c: Dictionary in spec.controls:
		(c["control"] as Node).free()
