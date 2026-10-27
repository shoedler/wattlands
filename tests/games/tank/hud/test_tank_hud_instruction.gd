extends GutTest
## The local rider's band and their one instruction line (TankHudModel.band_w, instruction; brief
## 2.3 In band, 2.4 Surge to evade, 3.6): HOLD lo-hi W, HOLD lo+ W, SPIN nn+ RPM, SURGE nnn+ W with
## the time left (the steam window, or an evade only for a rider in a SIM WORK phase past 300 s),
## LATCH, RESERVE; and the telegraph list every peer's world tags read.

const X := preload("res://tests/games/tank/hud/tank_hud_fixtures.gd")


func _rider_on(s: TankState, engine: String) -> TankRiderState:
	return s.rider_at(s.station(engine).slot)


func _no_telegraph(s: TankState) -> TankState:
	for e in s.enemies:
		e.telegraph_s = 0.0
	s.boss.telegraph_s = 0.0
	return s


func _line(s: TankState, r: TankRiderState, mode: String, target: float = 0.0) -> Dictionary:
	var band := TankHudModel.band_w(s, r, mode, target, Vector2.ZERO)
	return TankHudModel.instruction(
		s, r, {"mode": mode, "cad": r.cadence_rpm, "band": band, "cband": Vector2.ZERO}
	)


func test_the_drive_in_sim_holds_its_tempo_band() -> void:
	var s := _no_telegraph(X.state(3))
	var r := _rider_on(s, TankIds.ENGINE_DIESEL)
	var band := TankHudModel.band_w(s, r, Wl.SIM, 0.0, Vector2.ZERO)
	assert_almost_eq(band.x, 0.76 * r.ftp, 1e-3)
	assert_almost_eq(band.y, 1.05 * r.ftp, 1e-3)
	var l := _line(s, r, Wl.SIM)
	assert_eq(l["kind"], TankHudModel.DO_HOLD)
	assert_eq(l["key"], "TANK_HUD_DO_HOLD")
	assert_eq(l["args"], [str(roundi(0.76 * r.ftp)), str(roundi(1.05 * r.ftp))])
	assert_false(l["urgent"])
	var published := Vector2(150, 200)
	assert_eq(TankHudModel.band_w(s, r, Wl.SIM, 0.0, published), published, "the director's band")


func test_an_erg_rider_holds_the_applied_target_and_spins_under_the_cadence_floor() -> void:
	var s := _no_telegraph(X.state(3))
	var r := _rider_on(s, TankIds.ENGINE_DYNAMO)
	var band := TankHudModel.band_w(s, r, Wl.ERG, 150.0, Vector2.ZERO)
	assert_almost_eq(band.x, 142.5, 1e-3)
	assert_almost_eq(band.y, 157.5, 1e-3)
	assert_eq(_line(s, r, Wl.ERG, 150.0)["args"], ["143", "158"])
	r.cadence_rpm = 52.0
	var l := _line(s, r, Wl.ERG, 150.0)
	assert_eq(l["kind"], TankHudModel.DO_SPIN, "ERG in band needs cadence >= 60")
	assert_eq(l["args"], ["60"])
	assert_eq(TankHudModel.band_w(s, r, Wl.ERG, 0.0, Vector2.ZERO), Vector2.ZERO)


func test_the_boiler_holds_ninety_percent_then_the_loader_spins_and_a_full_boiler_latches() -> void:
	var s := _no_telegraph(X.state(3))
	var r := _rider_on(s, TankIds.ENGINE_STEAM)
	var stm := s.station(TankIds.ENGINE_STEAM) as TankSteamState
	var l := _line(s, r, Wl.SIM)
	assert_eq(l["key"], "TANK_HUD_DO_HOLD_MIN")
	assert_eq(l["args"], [str(roundi(0.9 * r.ftp))])
	stm.loaded = true
	l = _line(s, r, Wl.SIM)
	assert_eq(l["kind"], TankHudModel.DO_SPIN)
	assert_eq(l["args"], ["50"], "a loaded loader needs cadence >= 50")
	stm.loaded = false
	stm.cycling = true
	assert_eq(_line(s, r, Wl.SIM)["args"], ["50"])
	stm.cycling = false
	stm.pressure_pct = 100.0
	assert_eq(_line(s, r, Wl.SIM)["kind"], TankHudModel.DO_LATCH)
	stm.over = true
	assert_eq(_line(s, r, Wl.SIM)["kind"], TankHudModel.DO_HOLD, "Overpressure building")


func test_the_steam_window_says_surge_with_its_time_left() -> void:
	var s := _no_telegraph(X.state(3))
	var r := _rider_on(s, TankIds.ENGINE_STEAM)
	(s.station(TankIds.ENGINE_STEAM) as TankSteamState).window_s = 3.2
	var l := _line(s, r, Wl.SIM)
	assert_eq(l["kind"], TankHudModel.DO_SURGE)
	assert_eq(l["args"], [str(roundi(1.2 * r.ftp))], "240+ W at FTP 200: 1.2 x FTP")
	assert_almost_eq(float(l["left_s"]), 3.2, 1e-6)
	assert_true(l["urgent"])


func test_surge_to_evade_shows_only_to_a_sim_work_rider_past_300_s() -> void:
	var s := X.state(3)
	var r := _rider_on(s, TankIds.ENGINE_DIESEL)
	assert_gt(TankHudModel.telegraph_left(s), 0.0, "the fixture's destroyer telegraphs")
	var l := _line(s, r, Wl.SIM)
	assert_eq(l["kind"], TankHudModel.DO_SURGE)
	assert_eq(l["args"], [str(roundi(1.2 * r.ftp))])
	assert_almost_eq(float(l["left_s"]), 2.5, 1e-6, "the countdown")
	assert_eq(_line(s, r, Wl.ERG, 180.0)["kind"], TankHudModel.DO_HOLD, "never to an ERG rider")
	s.t = 250.0
	s.seg.plan_elapsed_s = 250.0
	assert_ne(_line(s, r, Wl.SIM)["kind"], TankHudModel.DO_SURGE, "not in the first 300 s")
	s.seg.plan_elapsed_s = 301.0
	assert_eq(_line(s, r, Wl.SIM)["kind"], TankHudModel.DO_SURGE, "the plan clock counts")
	s.seg.kind = Wl.WARMUP
	assert_eq(_line(s, r, Wl.SIM)["kind"], TankHudModel.DO_SPIN, "never in a warm-up")
	s.seg.kind = Wl.WORK
	r.rescue = true
	assert_ne(_line(s, r, Wl.SIM)["kind"], TankHudModel.DO_SURGE, "not in a rescue")


func test_the_behemoths_main_gun_counts_down_for_an_evader() -> void:
	var s := X.state(3, "boss")
	var r := _rider_on(s, TankIds.ENGINE_DIESEL)
	var l := _line(s, r, Wl.SIM)
	assert_eq(l["kind"], TankHudModel.DO_SURGE)
	assert_almost_eq(float(l["left_s"]), s.boss.telegraph_s, 1e-6)


func test_reserve_and_the_cadence_rules_of_the_depot_and_checkpoints() -> void:
	var s := _no_telegraph(X.state(2))
	var r := s.riders[0]
	r.afk = true
	assert_eq(_line(s, r, Wl.SIM)["kind"], TankHudModel.DO_RESERVE)
	r.afk = false
	s.station_of(r.slot).reserve = true
	assert_eq(_line(s, r, Wl.SIM)["key"], "TANK_HUD_DO_RESERVE")
	s.station_of(r.slot).reserve = false
	for kind: String in [Wl.WARMUP, Wl.RECOVERY]:
		s.seg.kind = kind
		var l := _line(s, r, Wl.ERG, 120.0)
		assert_eq(l["kind"], TankHudModel.DO_SPIN, kind)
		assert_eq(l["args"], ["60"])
	var cb := TankHudModel.instruction(s, r, {"mode": Wl.ERG, "cband": Vector2(65, 120)})
	assert_eq(cb["args"], ["65"], "the published cadence band")
	s.seg.seg = TankIds.SEG_COOLDOWN
	assert_eq(_line(s, r, Wl.ERG)["kind"], TankHudModel.DO_NONE)


func test_the_telegraph_list_has_every_shooter_with_its_full_length() -> void:
	var s := X.state(3)
	var t := TankHudModel.telegraphs(s)
	assert_eq(t.size(), 1)
	assert_eq(int(t[0]["id"]), 13)
	assert_eq(float(t[0]["total"]), 4.0, "the destroyer's 4 s glint")
	s.enemy(13).mode = TankIds.EM_DEAD
	assert_eq(TankHudModel.telegraphs(s).size(), 0)
	var b := TankHudModel.telegraphs(X.state(3, "boss"))
	assert_true(bool(b[-1]["boss"]))
	assert_eq(float(b[-1]["total"]), 6.0)
	var g := TankHudModel.telegraphs(X.state(3, "gun_line"))
	assert_eq(float(g[0]["total"]), 3.0, "the heavy's 3 s glow")


func test_the_power_ratio_is_watts_over_the_riders_target_in_one_helper() -> void:
	var r := TankRiderState.new()
	r.ftp = 200.0
	assert_almost_eq(TankHudModel.power_ratio(r, 181.0), 1.0, 1e-3, "90.5 % FTP is on target")
	assert_almost_eq(TankHudModel.power_ratio(r, 0.0), 0.0, 1e-6)
	assert_almost_eq(TankHudModel.power_ratio(r, 1000.0), 1.6, 1e-6, "TankMech's ceiling")
	assert_eq(TankHudModel.band_state(true, 2.0), 0)
	assert_eq(TankHudModel.band_state(false, 1.3), 1)
	assert_eq(TankHudModel.band_state(false, 0.5), -1)
