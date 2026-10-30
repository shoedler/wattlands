extends GutTest
## The cockpit's states, not its pixels (docs/games/siege.md 3 "HUD", SiegeCockpitModel): the heart
## rate's three cells, the applied target, stale power, the instruction line per state, hysteresis
## and SIM, and every state of the approved mock (src/games/siege/art/hud_mock.mjs).

const K := preload("res://tests/games/siege/hud/siege_hud_kit.gd")
const F := preload("res://tests/games/siege/siege_fakes.gd")

var _games: Array[SiegeGame] = []


func after_each() -> void:
	for g in _games:
		F.free_game(g)
	_games.clear()


func _g(index: int = 4, elapsed_s: float = 105.0) -> SiegeGame:
	var g := K.game(index, elapsed_s)
	_games.append(g)
	return g


## The game's own rider cleared of the fixture's Overdrive.
func _plain(index: int = 4, elapsed_s: float = 105.0) -> SiegeGame:
	var g := _g(index, elapsed_s)
	var r := g.state.rider(1)
	r.od_state = SiegeIds.OD_READY
	r.od_s = 0.0
	r.rescue = false
	return g


func _od(g: SiegeGame, left_s: float) -> void:
	var r := g.state.rider(1)
	r.od_state = SiegeIds.OD_ACTIVE
	r.od_s = left_s


# --- heart rate --------------------------------------------------------------------------------


func test_a_sensor_shows_its_cell_and_digits() -> void:
	var f := K.cockpit(4.0, 190.0, 90.0, 190, 151).face(_plain())
	assert_eq(f["hr"], HudRiderNumbers.HR_LIVE)
	assert_eq(f["hr_text"], "151")


func test_a_dropout_keeps_the_cell_with_dashes() -> void:
	var c := K.cockpit(4.0, 190.0, 90.0, 190, 151)
	K.ride(c, 4.05, 5.0, 190.0, 90.0, 190, 0)
	var f := c.face(_plain())
	assert_eq(f["hr"], HudRiderNumbers.HR_DROPOUT, "0 bpm must not claim no sensor")
	assert_eq(f["hr_text"], "--")


func test_a_known_sensor_with_no_reading_yet_is_a_dropout_too() -> void:
	var c := K.cockpit(1.0)
	c.numbers.sensor_status_override = TrainerDevice.STATUS_SCANNING
	assert_eq(c.face(_plain())["hr"], HudRiderNumbers.HR_DROPOUT)


func test_no_sensor_drops_the_cell_and_narrows_the_plate() -> void:
	var f := K.cockpit().face(_plain())
	assert_eq(f["hr"], HudRiderNumbers.HR_NONE)
	var ctl := SiegeHudCockpit.new()
	autofree(ctl)
	ctl.model = f
	assert_eq(ctl.plate_w(), SiegeHudCockpit.NARROW)
	ctl.model = K.cockpit(4.0, 190.0, 90.0, 190, 120).face(_plain())
	assert_eq(ctl.plate_w(), SiegeHudCockpit.WIDE)
	assert_eq(SiegeHudCockpit.WIDE, 404)
	assert_eq(SiegeHudCockpit.NARROW, 344)


# --- the target, the watts ---------------------------------------------------------------------


func test_the_target_is_what_telemetry_applied_never_the_plan() -> void:
	var g := _plain()
	var f := K.cockpit(4.0, 170.0, 90.0, 171).face(g)
	assert_eq(f["target_cap"].to_upper(), "TARGET 171 W", "a cap the plan doesn't know")
	assert_eq(f["applied_w"], 171)
	assert_almost_eq((f["band"] as Vector2).x, 171.0 * 0.95, 0.01)
	assert_almost_eq((f["band"] as Vector2).y, 171.0 * 1.05, 0.01)


func test_without_a_target_the_caption_says_so() -> void:
	var c := K.cockpit(1.0, 100.0, 90.0, 0)
	var f := c.face(_plain())
	assert_eq(f["target_cap"].to_upper(), "TARGET --")
	assert_eq(f["band"], Vector2.ZERO)


func test_rescue_shows_the_applied_target_and_its_caption() -> void:
	var g := _plain()
	var c := K.cockpit(4.0, 104.0, 58.0, 100)
	var x := K.tm(4.1, 104.0, 58.0, 100)
	x.rescue = true
	c.feed(x)
	var f := c.face(g)
	assert_eq(f["target_cap"].to_upper(), "RESCUE 100 W")
	assert_eq(f["cad_cap"].to_upper(), "RPM 70+")
	assert_eq(f["line"].to_upper(), "RESCUE: SPIN 70+")
	assert_true(f["line_alarm"])
	assert_true(f["cad_low"], "under 70 the cadence sits on the chip")
	assert_eq(f["next"].to_upper(), "THEN: RAMP BACK TO 190 W")
	var up := K.tm(4.2, 104.0, 75.0, 100)
	up.rescue = true
	c.feed(up)
	assert_false(c.face(g)["cad_low"], "70+ is met, the line stays till rescue ends")
	assert_eq(c.face(g)["line_kind"], SiegeCockpitModel.LINE_RESCUE)


func test_stale_power_shows_dashes_not_zero() -> void:
	var c := K.cockpit()
	var x := K.tm(4.1, 0.0, 0.0)
	x.cadence_age_s = 3.5
	c.feed(x)
	var f := c.face(_plain())
	assert_eq(f["w"], -1)
	assert_eq(f["w_text"], "--")
	assert_eq(f["pct_text"], "--")
	assert_eq(f["state"], HudRiderNumbers.IN_BAND, "no arrow on a number we don't have")
	assert_true(f["cad_stale"])
	assert_eq(f["cad_text"], "--")


func test_the_watts_are_a_three_second_mean() -> void:
	var c := K.cockpit(4.0, 200.0)
	K.ride(c, 4.05, 5.5, 100.0)
	var f := c.face(_plain())
	assert_almost_eq(float(f["w"]), 150.0, 4.0)


func test_the_colour_state_does_not_flicker_on_one_hertz_data() -> void:
	var g := _plain()
	var c := K.cockpit(4.0, 190.0)
	var t := 4.05
	var seen := {}
	for i in 30:
		K.ride(c, t, t + 0.95, 180.0 if i % 2 == 0 else 200.0)
		t += 1.0
		seen[c.face(g)["state"]] = true
	assert_eq(seen.keys(), [HudRiderNumbers.IN_BAND], "a 5% band holds on a wobbling rider")


func test_under_and_over_the_band() -> void:
	var g := _plain()
	assert_eq(K.cockpit(4.0, 150.0).face(g)["state"], HudRiderNumbers.UNDER)
	assert_eq(K.cockpit(4.0, 240.0).face(g)["state"], HudRiderNumbers.OVER)


func test_wkg_shows_only_if_the_rider_opted_in() -> void:
	var g := _plain()
	var c := K.cockpit(4.0, 192.0)
	assert_eq(c.face(g)["wkg"], "", "no opt-in")
	c.wkg_override_kg = 71.0
	assert_eq(c.face(g)["wkg"], "2.7")


# --- SIM ----------------------------------------------------------------------------------------


func test_the_gear_and_the_chip_are_only_in_sim() -> void:
	var g := _plain()
	assert_false(K.cockpit().face(g)["sim"])
	_od(g, 22.0)
	var c := K.cockpit(4.0, 262.0, 96.0, 0)
	K.ride(c, 4.05, 5.0, 262.0, 96.0, 0, 0, Wl.SIM)
	var x := K.tm(5.05, 262.0, 96.0, 0, Wl.SIM)
	x.gear = 15
	c.feed(x)
	var f := c.face(g)
	assert_true(f["sim"])
	assert_eq(f["gear"], 15)
	assert_eq(f["clock_cap"].to_upper(), "SPRINT LEFT")
	assert_eq(f["clock"], "0:22")


func test_overdrive_reads_the_real_band() -> void:
	var g := _plain()
	_od(g, 22.0)
	var c := K.cockpit(4.0, 262.0, 96.0, 0)
	K.ride(c, 4.05, 5.0, 262.0, 96.0, 0, 0, Wl.SIM)
	var f := c.face(g)
	assert_eq(f["target_cap"].to_upper(), "SPRINT 240-280")
	assert_eq(f["line"].to_upper(), "SPRINT 240-280 W, SHIFT UP")
	assert_eq(f["band"], SiegeOverdrive.band_w(g.state.content, 200.0))
	assert_eq(f["next"].to_upper(), "THEN: ERG AT 190 W")
	g.state.rider(1).ftp = 300.0
	var f2 := c.face(g)
	assert_eq(f2["line"].to_upper(), "SPRINT 360-420 W, SHIFT UP", "from the rider's FTP")


# --- the instruction line ------------------------------------------------------------------------


func test_a_steady_wave_asks_for_the_band() -> void:
	var f := K.cockpit().face(_plain())
	assert_eq(f["line"].to_upper(), "SPIN 80-100")
	assert_eq(f["line_kind"], SiegeCockpitModel.LINE_SPIN)
	assert_false(f["line_alarm"])
	assert_false(f["clock_soon"])


func test_the_last_thirty_seconds_before_a_step_up_say_load_up() -> void:
	var g := _plain(1, 90.0)  # the build break, 30 s left, a wave at 95% next
	var f := K.cockpit(4.0, 100.0, 90.0, 100).face(g)
	assert_eq(f["line"].to_upper(), "LOAD UP IN 0:30, SPIN UP")
	assert_true(f["clock_soon"], "the clock turns gold")
	K.stand(g, 1, 80.0)
	var before := K.cockpit(4.0, 100.0, 90.0, 100).face(g)
	assert_eq(before["line_kind"], SiegeCockpitModel.LINE_SPIN, "not yet at 40 s")


func test_a_step_down_gets_no_load_up_line() -> void:
	var g := _plain(4, 280.0)  # a wave at 95%, a break at 50% next
	var f := K.cockpit().face(g)
	assert_eq(f["line_kind"], SiegeCockpitModel.LINE_SPIN)
	assert_false(f["clock_soon"])


func test_low_cadence_goes_on_a_chip_while_rescue_is_armed() -> void:
	var g := _plain()
	var c := K.cockpit(4.0, 190.0, 62.0, 190)
	var f := c.face(g)
	assert_eq(f["line"].to_upper(), "SPIN UP: RESCUE AT 45")
	assert_true(f["line_alarm"])
	assert_true(f["cad_low"])


func test_low_cadence_in_a_break_raises_no_alarm() -> void:
	var g := _plain(1, 10.0)
	var f := K.cockpit(4.0, 100.0, 50.0, 100).face(g)
	assert_eq(f["line_kind"], SiegeCockpitModel.LINE_SPIN, "50% FTP: rescue is not armed")
	assert_false(f["cad_low"])
	assert_false(f["line_alarm"])


func test_coasting_says_pedal_and_wins_over_rescue() -> void:
	var g := _plain()
	var c := K.cockpit()
	var x := K.tm(4.1, 0.0, 0.0, 60)
	x.coasting = true
	x.rescue = true
	c.feed(x)
	var f := c.face(g)
	assert_eq(f["line"].to_upper(), "PEDAL: LOAD DROPPED")
	assert_true(f["line_alarm"])


func test_warm_up_and_cool_down_have_their_own_lines() -> void:
	var w := K.cockpit(4.0, 116.0, 86.0, 115).face(_plain(0, 150.0))
	assert_eq(w["line"].to_upper(), "SETTLE IN, SPIN 80-100")
	var cool := K.cockpit(4.0, 100.0, 84.0, 100).face(_plain(7, 80.0))
	assert_eq(cool["line"].to_upper(), "SPIN IT OUT")
	assert_eq(cool["next"].to_upper(), "NEXT: RESULTS")


func test_the_last_seconds_of_the_warm_up_ramp_step_down_to_the_break() -> void:
	var g := _plain(0, 280.0)
	var f := K.cockpit(4.0, 130.0, 86.0, 128).face(g)
	assert_eq(f["line_kind"], SiegeCockpitModel.LINE_WARMUP, "65% to 50% is no step up")


# --- the next line, the reserve -------------------------------------------------------------------


func test_next_uses_applied_style_watts_from_the_plan_and_this_ftp() -> void:
	var g := _plain(1, 10.0)
	var r := g.state.rider(1)
	r.ftp = 300.0
	assert_eq(K.cockpit().face(g)["next"].to_upper(), "NEXT: WAVE 1, 5:00 AT 285 W")
	r.ftp_verified = false
	assert_eq(
		K.cockpit().face(g)["next"].to_upper(),
		"NEXT: WAVE 1, 5:00 AT 242 W",
		"x 0.85, rounded down"
	)


func test_applied_w_follows_the_governors_rules() -> void:
	assert_eq(SiegeHudModel.applied_w(95.0, 200.0), 190)
	assert_eq(SiegeHudModel.applied_w(95.0, 201.0), 190, "whole watts, rounded down")
	assert_eq(SiegeHudModel.applied_w(95.0, 200.0, false), 161, "unverified x 0.85")
	assert_eq(SiegeHudModel.applied_w(10.0, 200.0), 60, "the floor")
	assert_eq(SiegeHudModel.applied_w(400.0, 200.0), 300, "the ceiling")


func test_a_ramp_names_now_and_its_end() -> void:
	var f := K.cockpit(4.0, 116.0, 86.0, 115).face(_plain(0, 150.0))
	assert_eq(f["target_cap"].to_upper(), "RAMP 115-130")


func test_the_reserve_shows_a_number_only_below_half() -> void:
	var g := _plain()
	var c := K.cockpit()
	var x := K.tm(4.1, 190.0)
	x.wbal_j = HudRiderNumbers.wprime_j() * 0.92
	c.feed(x)
	assert_eq(c.face(g)["wbal_text"], "")
	assert_almost_eq(float(c.face(g)["wbal"]), 0.92, 0.001)
	x = K.tm(4.2, 190.0)
	x.wbal_j = HudRiderNumbers.wprime_j() * 0.34
	c.feed(x)
	assert_eq(c.face(g)["wbal_text"], "34%")


func test_the_face_names_the_rider_and_the_station() -> void:
	var g := _plain()
	g.state.rider(1).target = SiegeIds.STATION_ARROWS
	var f := K.cockpit().face(g)
	assert_eq(f["name"], "Rider 1")
	assert_eq(f["station"].to_upper(), "ARROW ORGAN")
	assert_eq(f["shape"], Wl.SLOT_SHAPES[0])


func test_a_spectator_has_no_cockpit() -> void:
	var g := _plain()
	g.ctx.local_peer = 99
	assert_eq(K.cockpit().face(g), {})


# --- every state of the mock ------------------------------------------------------------------------


func _mock_wave() -> Dictionary:
	var g := _plain(4, 105.0)
	var c := K.cockpit(4.0, 192.0, 88.0, 190, 151)
	c.wkg_override_kg = 71.0
	return c.face(g)


func test_mock_wave() -> void:
	var f := _mock_wave()
	assert_eq(f["clock_cap"].to_upper(), "WAVE LEFT")
	assert_eq(f["clock"], "3:15")
	assert_eq(f["target_cap"].to_upper(), "TARGET 190 W")
	assert_eq(f["w_text"], "192")
	assert_eq(f["pct_text"], "96%")
	assert_eq(f["wkg"], "2.7")
	assert_eq(f["cad_text"], "88")
	assert_eq(f["cad_cap"].to_upper(), "RPM 80-100")
	assert_eq(f["hr_text"], "151")
	assert_eq(f["line"].to_upper(), "SPIN 80-100")
	assert_eq(f["next"].to_upper(), "NEXT: BREAK, 3:00 AT 100 W")
	assert_false(f["sim"])
	assert_eq(f["wbal_text"], "")


func test_mock_overdrive() -> void:
	var g := _plain(4, 120.0)
	_od(g, 22.0)
	var c := K.cockpit(4.0, 262.0, 96.0, 0, 168)
	K.ride(c, 4.05, 5.0, 262.0, 96.0, 0, 168, Wl.SIM)
	var f := c.face(g)
	assert_eq(f["clock_cap"].to_upper(), "SPRINT LEFT")
	assert_eq(f["clock"], "0:22")
	assert_eq(f["target_cap"].to_upper(), "SPRINT 240-280")
	assert_eq(f["w_text"], "262")
	assert_eq(f["pct_text"], "131%")
	assert_eq(f["line"].to_upper(), "SPRINT 240-280 W, SHIFT UP")
	assert_eq(f["next"].to_upper(), "THEN: ERG AT 190 W")
	assert_true(f["sim"])


func test_mock_alarm() -> void:
	var g := _plain(6, 20.0)
	var c := K.cockpit(4.0, 191.0, 62.0, 190, 151)
	K.ride(c, 4.05, 5.0, 191.0, 62.0, 190, 0)
	var x := K.tm(5.05, 191.0, 62.0)
	x.wbal_j = HudRiderNumbers.wprime_j() * 0.34
	c.feed(x)
	var f := c.face(g)
	assert_eq(f["clock"], "4:40")
	assert_eq(f["pct_text"], "95%")
	assert_true(f["cad_low"])
	assert_eq(f["hr_text"], "--", "the sensor dropped")
	assert_eq(f["line"].to_upper(), "SPIN UP: RESCUE AT 45")
	assert_true(f["line_alarm"])
	assert_eq(f["next"].to_upper(), "NEXT: COOL-DOWN, 3:00 AT 100 W")
	assert_eq(f["wbal_text"], "34%")


func test_mock_warmup() -> void:
	var f := K.cockpit(4.0, 116.0, 86.0, 115, 118).face(_plain(0, 150.0))
	assert_eq(f["clock_cap"].to_upper(), "WARM-UP")
	assert_eq(f["clock"], "2:30")
	assert_eq(f["target_cap"].to_upper(), "RAMP 115-130")
	assert_eq(f["pct_text"], "58%")
	assert_eq(f["line"].to_upper(), "SETTLE IN, SPIN 80-100")
	assert_eq(f["next"].to_upper(), "NEXT: BUILD BREAK, 2:00 AT 100 W")


func test_mock_cooldown() -> void:
	var f := K.cockpit(4.0, 91.0, 84.0, 100, 122).face(_plain(7, 80.0))
	assert_eq(f["clock_cap"].to_upper(), "COOL-DOWN")
	assert_eq(f["clock"], "1:40")
	assert_eq(f["target_cap"].to_upper(), "TARGET 100 W", "the platform's cool-down has no ramp")
	assert_eq(f["line"].to_upper(), "SPIN IT OUT")
	assert_eq(f["next"].to_upper(), "NEXT: RESULTS")


func test_mock_break() -> void:
	var f := K.cockpit(4.0, 101.0, 90.0, 100).face(_plain(1, 90.0))
	assert_eq(f["clock_cap"].to_upper(), "BREAK LEFT")
	assert_eq(f["clock"], "0:30")
	assert_true(f["clock_soon"])
	assert_eq(f["target_cap"].to_upper(), "TARGET 100 W")
	assert_eq(f["w_text"], "101")
	assert_eq(f["pct_text"], "50%")
	assert_eq(f["line"].to_upper(), "LOAD UP IN 0:30, SPIN UP")
	assert_eq(f["next"].to_upper(), "NEXT: WAVE 1, 5:00 AT 190 W")
	assert_eq(f["hr"], HudRiderNumbers.HR_NONE, "no sensor: the plate is narrower")


# --- the Control -------------------------------------------------------------------------------


func test_the_control_draws_every_state_without_an_error() -> void:
	var g := _plain()
	var ctl := K.ctl(SiegeHudCockpit.new(), g, SiegeHudCockpit.RECT) as SiegeHudCockpit
	add_child_autofree(ctl)
	ctl.cockpit.numbers.sensor_status_override = TrainerDevice.STATUS_DISCONNECTED
	var x := K.tm(1.0, 190.0, 90.0, 190, Wl.ERG, 150)
	ctl.set_telemetry(x)
	ctl.refresh()
	await wait_physics_frames(2)
	assert_gt(ctl.draws, 0)
	assert_eq(ctl.plate_w(), SiegeHudCockpit.WIDE)
	var low := K.tm(2.0, 0.0, 0.0, 60)
	low.rescue = true
	low.cadence_age_s = 4.0
	ctl.set_telemetry(low)
	_od(g, 10.0)
	ctl.refresh()
	await wait_physics_frames(2)
	assert_eq(ctl.model["w_text"], "--")


func test_a_long_name_is_cut_to_fit_the_plaque() -> void:
	var g := _plain()
	g.ctx.player(1).name = "Maximilian von Hohenzollern-Sigmaringen"
	var ctl := K.ctl(SiegeHudCockpit.new(), g, SiegeHudCockpit.RECT) as SiegeHudCockpit
	add_child_autofree(ctl)
	ctl.set_telemetry(K.tm(1.0, 190.0))
	ctl.refresh()
	await wait_physics_frames(2)
	assert_gt(ctl.draws, 0)
	var room := SiegeHudCockpit.NARROW - 40
	var cut := SiegeHudType.fit(str(ctl.model["name"]), "LABEL", room / 2)
	assert_lte(SiegeHudType.width(cut, "LABEL"), room / 2)
	assert_lt(cut.length(), str(ctl.model["name"]).length())


func test_a_refresh_with_nothing_new_does_not_redraw() -> void:
	var g := _plain()
	var ctl := K.ctl(SiegeHudCockpit.new(), g, SiegeHudCockpit.RECT) as SiegeHudCockpit
	add_child_autofree(ctl)
	ctl.set_telemetry(K.tm(1.0, 190.0))
	ctl.refresh()
	await wait_physics_frames(2)
	var settled := ctl.draws
	for i in 5:
		ctl.refresh()
	await wait_physics_frames(2)
	assert_eq(ctl.draws, settled, "the model is the same: no redraw")
