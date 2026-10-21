extends "res://tests/governor/gov_test_base.gd"
## W2r2: what a governor does with no phase (menus ride free at SIM grade 0, wind 0), and what
## it takes over from the governor it replaces on the same device (SafetyGovernor
## .adopt_connection, called by LocalRider.setup()): the BRIEF 4.6.8 warm-up, "counted from the
## first pedal stroke after the trainer connects, and reset after 20 minutes without pedaling",
## and what the controller last wrote to the trainer, so the next mode change is ramped (4.5)
## and the 2 writes per second hold across the hand-over.

const WARM := {"skip_warmup": false}


## What LocalRider.setup() does on the same device: a fresh governor that adopts the old one's
## trainer connection, configured afterwards; the rig ticks the new governor from now on.
func _next_governor(rig: Rig, params: Dictionary = {}, device: TrainerDevice = null) -> SafetyGovernor:
	var old := rig.gov
	var dev := device if device != null else rig.device
	var g := SafetyGovernor.new()
	autofree(g)
	g.warmup_changed.connect(func(v: bool) -> void: rig.events.append({"t": rig.t, "name": "warmup_changed", "value": v}))
	g.setup(dev)
	g.adopt_connection(old)
	var p := BASE_PARAMS.duplicate()
	p.merge(params, true)
	g.configure(p)
	if rig.device.sample_received.is_connected(old.on_sample):
		rig.device.sample_received.disconnect(old.on_sample)
	if dev != rig.device:
		autofree(dev)
		rig.device = dev
	dev.sample_received.connect(g.on_sample)
	rig.gov = g
	return g


func _stop_pedaling(dev: ScriptedDevice) -> void:
	dev.erg_follow = -1.0
	dev.power_w = 0.0
	dev.cadence_rpm = 0.0


# --- no phase: SIM flat ---------------------------------------------------------------------


func test_no_plan_rides_sim_flat() -> void:
	var rig := make_rig({}, follower())
	var dev: ScriptedDevice = rig.device
	rig.run(2.0)
	assert_eq(dev.writes.size(), 1, "one write")
	assert_eq(dev.writes[0]["op"], "sim")
	assert_almost_eq(float(dev.writes[0]["grade_pct"]), 0.0, 1e-12, "grade 0")
	assert_almost_eq(float(dev.writes[0]["wind_mps"]), 0.0, 1e-12, "wind 0")
	assert_almost_eq(float(dev.writes[0]["crr"]), 0.004, 1e-12)
	assert_almost_eq(float(dev.writes[0]["cw"]), 0.51, 1e-12)
	var s := rig.s()
	assert_eq(s["mode"], Wl.SIM)
	assert_eq(s["desired_mode"], Wl.OFF, "no phase: nothing planned")
	assert_almost_eq(float(s["applied_grade_pct"]), 0.0, 1e-12)
	assert_almost_eq(float(s["wind_mps"]), 0.0, 1e-12)
	assert_eq(int(s["applied_target_w"]), 0)
	assert_eq((s["clamped_by"] as Array).size(), 0)
	rig.run(10.0)
	assert_eq(dev.writes.size(), 1, "no-op writes are skipped")
	assert_eq(rig.gov.shift(1), 12, "no gear shifts without a SIM phase")


## W4 (SAF-6, BRIEF 4.5): the no-phase SIM flat is SIM at the trainer, so the first ERG phase
## after it is a real SIM -> ERG switch and a directive SIM block must wait 30 s after it.
## (W2r2 counted it as no switch; W3 found that let a game switch SIM -> ERG -> SIM within 1 s.)
func test_a_plan_before_its_first_phase_rides_sim_flat_and_entering_erg_is_a_switch() -> void:
	var rig := make_rig({}, follower())
	var dev: ScriptedDevice = rig.device
	rig.gov.set_plan(EffortPlan.of([erg(Wl.WORK, 80.0, 600.0)]))
	rig.run(1.0)
	assert_eq(dev.mode, Wl.SIM)
	assert_almost_eq(dev.grade_pct, 0.0, 1e-12)
	var t_erg := rig.t
	rig.gov.start_phase(0)
	rig.run(1.0)
	var ergs := dev.writes_of("erg")
	assert_eq(ergs.size(), 1, "SIM flat already: straight to the ERG entry")
	assert_lte(int(ergs[0]["w"]), 160, "never above the planned target")
	assert_almost_eq(float(rig.s()["last_switch_t"]), t_erg, 1e-6, "SIM flat -> ERG is a switch")
	var rec := rig.directive({"mode": "SIM", "duration_s": 15.0})
	assert_true(rec["refused"], "a SIM block 1 s after the SIM -> ERG switch is refused")
	assert_eq(rec["reason"], Wl.REFUSE_SWITCH_SPACING)
	assert_push_warning("switch_spacing")
	rig.run(28.0)
	assert_true(rig.directive({"mode": "SIM", "duration_s": 15.0})["refused"], "29 s after: still refused")
	rig.run(1.0)
	assert_false(rig.directive({"mode": "SIM", "duration_s": 15.0})["refused"], "30 s after the switch: accepted")


## SAF-6: a fresh governor whose controller has written nothing knows no previous mode, so its
## first ERG phase is no switch (the rig's sessions start that way).
func test_a_first_erg_phase_before_any_write_is_no_switch() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 80.0, 600.0)])
	assert_almost_eq(float(rig.s()["last_switch_t"]), -1e9, 1e-3)
	rig.run(1.0)
	assert_false(rig.directive({"mode": "SIM", "duration_s": 15.0})["refused"])


## SAF-6: clear_plan() from ERG is an ERG -> SIM switch (the governor rides SIM flat from then).
func test_clear_plan_from_erg_is_a_switch() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 80.0, 600.0)])
	rig.run(40.0)
	var t_clear := rig.t
	rig.gov.clear_plan()
	assert_almost_eq(float(rig.s()["last_switch_t"]), t_clear, 1e-6)


## SAF-6 across sessions (the W3 repro): the menus ride SIM flat, the next governor on the same
## trainer starts an ERG phase (a switch), and a SIM block 1 s later is refused. A switch made
## under the old governor carries over to the next one (adopt_connection) on its own clock.
func test_switch_spacing_holds_across_the_hand_over() -> void:
	var rig := make_rig({}, follower())
	rig.run(5.0)
	var g := _next_governor(rig)
	g.set_plan(plan_with_cooldown([erg(Wl.WARMUP, 50.0, 300.0)]))
	g.start_phase(0)
	rig.run(1.0)
	assert_eq((rig.device as ScriptedDevice).mode, Wl.ERG, "precondition: the session switched to ERG")
	assert_almost_eq(float(rig.s()["last_switch_t"]), 0.0, 1e-6, "the SIM flat -> ERG switch at the new governor's t 0")
	assert_true(rig.directive({"mode": "SIM", "duration_s": 15.0})["refused"], "SIM -> ERG -> SIM within 1 s is refused")
	assert_push_warning("switch_spacing")
	rig.run(39.0)
	g.clear_plan()
	assert_almost_eq(float(rig.s()["last_switch_t"]), 40.0, 1e-6, "ERG -> SIM flat at t 40")
	var g2 := _next_governor(rig)
	assert_almost_eq(float(rig.s()["last_switch_t"]), 0.0, 1e-6, "carried over, at the next governor's t 0")
	g2.set_plan(plan_with_cooldown([erg(Wl.WORK, 70.0, 300.0)]))
	g2.start_phase(0)
	rig.run(1.0)
	assert_true(rig.directive({"mode": "SIM", "duration_s": 15.0})["refused"], "1 s after the carried switch: refused")
	assert_push_warning("switch_spacing")


func test_clear_plan_ramps_from_erg_to_sim_flat() -> void:
	var dev: ScriptedDevice = follower()
	dev.erg_follow = 0.8
	var rig := make_rig({}, dev)
	rig.start([erg(Wl.WORK, 80.0, 600.0)])
	rig.run(30.0)
	assert_eq(dev.target_w, 160)
	var n := dev.writes.size()
	var t0 := rig.t
	rig.gov.clear_plan()
	var s := rig.s()
	assert_eq(int(s["phase_index"]), -1)
	assert_eq(s["desired_mode"], Wl.OFF)
	assert_true(rig.directive({"target_pct": 70.0})["refused"], "no phase: directives are refused")
	rig.run(3.0)
	var after := dev.writes.slice(n)
	assert_eq(after.size(), 2, "the 4.5 step-down, then SIM flat")
	assert_eq(after[0]["op"], "erg")
	assert_eq(int(after[0]["w"]), 128, "min(applied target, 3 s power)")
	assert_eq(after[1]["op"], "sim")
	assert_almost_eq(float(after[1]["grade_pct"]), 0.0, 1e-12)
	assert_almost_eq(float(after[1]["wind_mps"]), 0.0, 1e-12)
	assert_gte(float(after[1]["t"]) - float(after[0]["t"]), 0.5 - 1e-6, "one write slot apart")
	assert_lt(float(after[1]["t"]) - t0, 1.5, "promptly")
	assert_eq(rig.s()["mode"], Wl.SIM)
	assert_eq(dev.mode, Wl.SIM)


func test_clear_plan_ends_rescue_and_a_sim_block() -> void:
	var dev: ScriptedDevice = follower()
	var rig := make_rig({}, dev)
	rig.start([erg(Wl.WORK, 80.0, 600.0).with_range(50.0, 100.0)])
	rig.run(40.0)
	assert_false(rig.directive({"mode": "SIM", "duration_s": 20.0})["refused"])
	rig.run(1.0)
	assert_true(rig.s()["sim_block_active"])
	rig.gov.clear_plan()
	assert_false(rig.s()["sim_block_active"], "every channel cleared")
	var rig2 := make_rig({}, follower())
	var dev2: ScriptedDevice = rig2.device
	rig2.start([erg(Wl.WORK, 100.0, 600.0)])
	rig2.run(20.0)
	dev2.erg_follow = -1.0
	dev2.cadence_rpm = 30.0
	dev2.power_w = 150.0
	rig2.run_until(func() -> bool: return rig2.gov.is_rescue(), 10.0)
	assert_true(rig2.gov.is_rescue())
	rig2.gov.clear_plan()
	assert_false(rig2.gov.is_rescue(), "the rescue ends with the plan")
	assert_eq(rig2.events_named("rescue_changed").back()["value"], false)


# --- adopt_connection: warm-up ------------------------------------------------------------------


func test_warmup_begun_with_no_plan_continues_under_the_next_governor() -> void:
	var rig := make_rig(WARM, follower())
	rig.run(100.0)
	var first_pedal := 1.0
	assert_almost_eq(float(rig.s()["warmup_remaining_s"]), 300.0 - (rig.t - first_pedal), 1e-6)
	var g := _next_governor(rig, WARM)
	assert_true(g.is_warmup_active())
	assert_almost_eq(float(g.status()["warmup_remaining_s"]), 300.0 - (rig.t - first_pedal), 1e-6,
		"the menus' warm-up carries into the session")
	rig.start([erg(Wl.WORK, 80.0, 900.0)])
	rig.run(10.0)
	assert_eq(rig.applied_w(), 130, "the 65% cap still holds")
	var ended := rig.run_until(func() -> bool: return not g.is_warmup_active(), 250.0)
	assert_time(ended, first_pedal + 300.0, "ends 300 s after the first stroke after the connection")
	rig.run(5.0)
	assert_eq(rig.applied_w(), 160)


func test_a_finished_warmup_stays_finished_for_the_next_governor() -> void:
	var rig := make_rig(WARM, follower())
	rig.start([erg(Wl.WORK, 60.0, 900.0)])
	rig.run(305.0)
	assert_false(rig.gov.is_warmup_active())
	var g := _next_governor(rig, WARM)
	assert_false(g.is_warmup_active(), "back-to-back sessions share one warm-up")
	assert_almost_eq(float(g.status()["warmup_remaining_s"]), 0.0, 1e-12)
	rig.start([erg(Wl.WORK, 80.0, 900.0)])
	rig.run(10.0)
	assert_eq(rig.applied_w(), 160, "no 65% cap")


func test_skip_warmup_still_applies_after_adopting() -> void:
	var rig := make_rig(WARM, follower())
	rig.run(50.0)
	var g := _next_governor(rig, {"skip_warmup": true})
	assert_false(g.is_warmup_active())
	rig.start([erg(Wl.WORK, 80.0, 900.0)])
	rig.run(10.0)
	assert_eq(rig.applied_w(), 160)


func test_twenty_minutes_without_pedaling_resets_it_across_governors() -> void:
	var rig := make_rig(WARM, follower())
	rig.run(310.0)
	assert_false(rig.gov.is_warmup_active())
	var dev: ScriptedDevice = rig.device
	var last_pedal := dev.sample_times[dev.sample_times.size() - 1]
	_stop_pedaling(dev)
	rig.run(600.0)
	var g := _next_governor(rig, WARM)
	assert_false(g.is_warmup_active(), "a 10-minute stop keeps it")
	rig.run_until(func() -> bool: return rig.t >= last_pedal + 1200.0 - DT - 1e-6, 700.0)
	assert_false(g.is_warmup_active(), "not before 20 minutes")
	rig.step()
	assert_true(g.is_warmup_active(), "20 minutes without pedaling reset it")
	assert_almost_eq(float(g.status()["warmup_remaining_s"]), 300.0, 1e-9, "pending until the next stroke")


func test_a_new_device_starts_a_new_warmup() -> void:
	var rig := make_rig(WARM, follower())
	rig.run(305.0)
	assert_false(rig.gov.is_warmup_active())
	var other: ScriptedDevice = follower()
	var g := _next_governor(rig, WARM, other)
	assert_true(g.is_warmup_active(), "another trainer object is a new connection")
	assert_almost_eq(float(g.status()["warmup_remaining_s"]), 300.0, 1e-9)
	assert_eq(g.status()["mode"], Wl.OFF, "nothing is assumed about the new trainer")
	assert_eq(float(g.warmup_state()["started_t"]), -1.0)


func test_a_reconnect_keeps_it() -> void:
	var rig := make_rig(WARM, follower())
	rig.run(120.0)
	var before := float(rig.s()["warmup_remaining_s"])
	rig.gov.on_trainer_reconnected()
	assert_almost_eq(float(rig.s()["warmup_remaining_s"]), before, 1e-9, "same object reconnected")
	var other: ScriptedDevice = follower()
	autofree(other)
	rig.gov.setup(other)
	assert_almost_eq(float(rig.s()["warmup_remaining_s"]), before, 1e-9, "a rebind to a new object of the same trainer")


func test_adopt_does_nothing_with_null_itself_or_another_device() -> void:
	var rig := make_rig(WARM, follower())
	rig.run(305.0)
	rig.gov.adopt_connection(null)
	rig.gov.adopt_connection(rig.gov)
	assert_false(rig.gov.is_warmup_active())
	var lone: SafetyGovernor = autofree(SafetyGovernor.new())
	lone.adopt_connection(rig.gov)
	assert_true(lone.is_warmup_active(), "not bound to a device: nothing taken over")
	assert_eq(float(lone.warmup_state()["t"]), 0.0)


# --- adopt_connection: the trainer's written state -------------------------------------------------


func test_the_next_governor_ramps_from_the_trainers_real_state() -> void:
	var dev: ScriptedDevice = follower()
	dev.erg_follow = 0.8
	var rig := make_rig({}, dev)
	rig.start([cooldown()])
	rig.run(30.0)
	assert_eq(dev.target_w, 100, "the cool-down's 50%")
	var n := dev.writes.size()
	var g := _next_governor(rig)
	assert_eq(g.status()["mode"], Wl.ERG, "it knows the trainer is in ERG")
	assert_eq(int(g.status()["applied_target_w"]), 100)
	rig.run(3.0)
	var after := dev.writes.slice(n)
	assert_eq(after.size(), 2, "ERG -> SIM flat is ramped (4.5), not a jump")
	assert_eq(after[0]["op"], "erg")
	assert_eq(int(after[0]["w"]), 80, "max(floor, min(applied, 3 s power))")
	assert_eq(after[1]["op"], "sim")
	assert_almost_eq(float(after[1]["grade_pct"]), 0.0, 1e-12)
	assert_almost_eq(float(after[1]["wind_mps"]), 0.0, 1e-12)


func test_the_write_slot_holds_across_the_hand_over() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 80.0, 600.0)])
	rig.run(30.0)
	var dev: ScriptedDevice = rig.device
	rig.gov.clear_plan()
	var n := dev.writes.size()
	while dev.writes.size() == n:
		rig.step()
	var t_last := float(dev.writes[dev.writes.size() - 1]["t"])
	_next_governor(rig)
	rig.start([erg(Wl.WORK, 70.0, 600.0)])
	rig.run(2.0)
	var later := dev.writes_of("erg", t_last + 1e-6)
	assert_gt(later.size(), 0)
	assert_gte(float(later[0]["t"]) - t_last, 0.5 - 1e-6, "no write within 0.5 s of the old governor's last one")
	assert_lte(dev.max_writes_in_window(1.0), 2)


func test_a_shut_down_predecessor_leaves_the_mode_off() -> void:
	var rig := make_rig(WARM, follower())
	rig.start([erg(Wl.WORK, 60.0, 600.0)])
	rig.run(20.0)
	rig.gov.shutdown()
	var g := _next_governor(rig, WARM)
	assert_eq(g.status()["mode"], Wl.OFF, "SIM flat then Stop went out")
	assert_false(bool(g.status()["shut_down"]))
	assert_almost_eq(float(g.status()["warmup_remaining_s"]), 300.0 - (rig.t - 1.0), 1e-6, "the warm-up still carries")


# --- adopt_connection: duration limits (W4, SAF-2) ------------------------------------------------
# BRIEF 4.6.1: a latched limit "stays there until the applied target has been <= 90% FTP for 120
# consecutive seconds of ERG (inclusive)"; "time in SIM adds nothing". A new session on the same
# trainer is no release, so the counters, both latches and the reset run carry over.


func test_a_latch_carries_to_the_next_governor_on_the_same_trainer() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 125.0, 60.0)])
	rig.run(70.0)
	assert_true(bool(rig.s()["latched_120"]), "precondition: the 120% limit latched")
	var left_105 := float(rig.s()["s_left_105"])
	var g := _next_governor(rig)
	var s := g.status()
	assert_true(bool(s["latched_120"]), "the 120% latch carries over")
	assert_almost_eq(float(s["s_left_120"]), 0.0, 1e-9)
	assert_almost_eq(float(s["s_left_105"]), left_105, 1e-9, "the 105% count carries over")
	# The next session: SIM first (adds nothing, restarts the reset count), then 125% ERG.
	rig.start([sim(Wl.GRADE_FLAT, 300.0, Wl.WARMUP), erg(Wl.WORK, 125.0, 60.0)])
	rig.run(300.0)
	g.start_phase(1)
	rig.run(30.0)
	assert_eq(rig.applied_w(), 240, "no ERG reset run happened: the 120% cap (240 W) holds")
	assert_has(rig.s()["clamped_by"], Wl.CLAMP_LIMIT_120)


func test_the_reset_run_carries_and_completes_under_the_next_governor() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 125.0, 70.0), erg(Wl.RECOVERY, 80.0, 600.0)])
	rig.run(70.0)
	assert_true(bool(rig.s()["latched_120"]))
	rig.gov.start_phase(1)
	rig.run(80.0)
	var run_s := float(rig.s()["reset_run_s"])
	assert_gt(run_s, 60.0, "precondition: most of the 120 s reset run done")
	var g := _next_governor(rig)
	assert_almost_eq(float(g.status()["reset_run_s"]), run_s, 1e-9, "the reset run carries over")
	assert_true(bool(g.status()["latched_120"]))
	rig.start([erg(Wl.RECOVERY, 80.0, 600.0)])
	var released := rig.run_until(func() -> bool: return not bool(g.status()["latched_120"]), 60.0)
	assert_gt(released, 0.0, "the run completes under the new governor")
	assert_lte(float(g.status()["reset_run_s"]) - 120.0, 1.0)


func test_a_new_trainer_connection_starts_the_limits_afresh() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 125.0, 60.0)])
	rig.run(70.0)
	assert_true(bool(rig.s()["latched_120"]))
	var g := _next_governor(rig, {}, follower())
	assert_false(bool(g.status()["latched_120"]), "another device object is a new connection")
	assert_almost_eq(float(g.status()["s_left_120"]), 60.0, 1e-9)
	assert_almost_eq(float(g.status()["s_left_105"]), 300.0, 1e-9)
