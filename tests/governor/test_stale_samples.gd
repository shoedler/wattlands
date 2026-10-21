extends "res://tests/governor/gov_test_base.gd"
## W4 (SAF-7): the stale-sample watchdog. BRIEF 4.6.4 times coasting "from the first sample that
## meets it"; a KICKR that stops notifying (or notifications that stall while the link stays up)
## sent no such sample, so the coasting floor, pause/AFK and rescue never ran while LocalRider
## already showed the rider at 0 W. Now, while the device reports a link, no sample for more
## than STALE_SAMPLE_S (3 s) counts as one not_pedaling sample (0 W, no cadence) at the moment
## the stream went stale. ADR in docs/decisions/trainer-control.md.


## A ScriptedDevice that can go silent (no notifications) and report its link state.
class QuietDevice extends "res://tests/governor/scripted_device.gd":
	var silent: bool = false
	var link: String = TrainerDevice.STATUS_READY

	func status() -> String:
		return link

	func is_ready() -> bool:
		return link == TrainerDevice.STATUS_READY

	func tick(dt: float) -> void:
		if silent:
			t += dt
			_next_sample_t = t + sample_period_s
			return
		super.tick(dt)


func _quiet() -> QuietDevice:
	var d := QuietDevice.new()
	d.erg_follow = 1.0
	d.cadence_rpm = 90.0
	return d


func _last_sample_t(d: QuietDevice) -> float:
	return d.sample_times[d.sample_times.size() - 1]


func test_a_silent_stream_reaches_the_coasting_floor() -> void:
	var dev := _quiet()
	var rig := make_rig({}, dev)
	rig.start([erg(Wl.WORK, 75.0, 600.0)])
	rig.run(20.0)
	assert_eq(rig.applied_w(), 150, "precondition: 75% of 200 W")
	dev.silent = true
	var last := _last_sample_t(dev)
	rig.run(2.9)
	assert_false(bool(rig.s()["samples_stale"]), "a gap of up to 3 s is a normal ~1 Hz stream")
	var stale_at := rig.run_until(func() -> bool: return bool(rig.s()["samples_stale"]), 1.0)
	assert_gt(stale_at, 0.0)
	assert_gt(stale_at - last, 3.0, "stale only after more than 3 s without a sample")
	assert_lte(stale_at - last, 3.0 + DT + 1e-6)
	var coast_at := rig.run_until(func() -> bool: return rig.gov.is_coasting(), 5.0)
	assert_time(coast_at, last + 6.0, "the not_pedaling sample at last + 3 s, then the 3 s coasting rule")
	rig.run(1.0)
	assert_eq(rig.applied_w(), GovernorClamps.floor_w(200.0), "the ERG floor (60 W)")
	assert_has(rig.s()["clamped_by"], Wl.CLAMP_COASTING)


## The W3 proof (build/w3/safety: test_coasting_floor_when_the_sample_stream_stops), with a real
## LocalRider: 15 s without samples shows 0 W in telemetry, and now the governor agrees.
func test_the_w3_repro_with_a_local_rider() -> void:
	var dev: ScriptedDevice = follower()
	autofree(dev)
	var r := LocalRider.new()
	add_child_autofree(r)
	var p := RiderProfile.new()
	p.ftp_w = 200.0
	p.cp_w = 200.0
	p.ftp_verified = true
	p.skip_warmup = true
	r.setup(1, p, p.to_slot(1, Wl.FAIR_FTP), dev, {"multiplayer": false, "skip_warmup": true})
	r.set_plan(plan_with_cooldown([erg(Wl.WORK, 75.0, 120.0)]))
	r.start_phase(0)
	for i in roundi(20.0 / DT):
		r.tick(DT)
	dev.sample_period_s = 1.0e9
	for i in roundi(15.0 / DT):
		r.tick(DT)
	var tel := r.telemetry()
	var st := r.governor.status()
	assert_eq(tel.power_w, 0.0, "telemetry: the sample is stale")
	assert_true(bool(st["coasting"]), "the governor coasts too")
	assert_lte(int(st["applied_target_w"]), 60, "15 s with no sample: the ERG floor (60 W); applied %d W" % int(st["applied_target_w"]))


func test_pause_after_ten_more_seconds_solo_and_afk_in_multiplayer() -> void:
	for mp: bool in [false, true]:
		var dev := _quiet()
		var rig := make_rig({"multiplayer": mp}, dev)
		rig.start([erg(Wl.WORK, 75.0, 600.0)])
		rig.run(10.0)
		dev.silent = true
		var last := _last_sample_t(dev)
		var at := rig.run_until(func() -> bool:
			return not rig.events_named("afk_changed" if mp else "pause_requested").is_empty(), 20.0)
		assert_time(at, last + 13.0, "10 s after coasting began (mp %s)" % str(mp))


func test_samples_coming_back_end_it() -> void:
	var dev := _quiet()
	var rig := make_rig({}, dev)
	rig.start([erg(Wl.WORK, 75.0, 600.0)])
	rig.run(10.0)
	dev.silent = true
	rig.run(6.5)
	assert_true(rig.gov.is_coasting())
	assert_false(rig.gov.is_rescue(), "precondition: before the rescue's 5 s")
	dev.silent = false
	rig.run(1.05)
	assert_false(bool(rig.s()["samples_stale"]))
	assert_false(rig.gov.is_coasting(), "a pedaling sample ends the stretch")
	rig.run(10.0)
	assert_eq(rig.applied_w(), 150, "back to the target (slew from the floor)")


func test_no_watchdog_while_the_link_is_down() -> void:
	for st: String in [TrainerDevice.STATUS_DISCONNECTED, TrainerDevice.STATUS_SCANNING, TrainerDevice.STATUS_CONNECTING]:
		var dev := _quiet()
		var rig := make_rig({}, dev)
		rig.start([erg(Wl.WORK, 75.0, 600.0)])
		rig.run(10.0)
		dev.silent = true
		dev.link = st
		rig.run(10.0)
		assert_false(bool(rig.s()["samples_stale"]), st + ": a dropped link is the reconnect flow's job")
		assert_false(rig.gov.is_coasting(), st)


func test_a_trainer_that_never_notifies_after_the_bind_coasts_too() -> void:
	var dev := _quiet()
	dev.silent = true
	var rig := make_rig({}, dev)
	rig.start([erg(Wl.WORK, 75.0, 600.0)])
	var coast_at := rig.run_until(func() -> bool: return rig.gov.is_coasting(), 10.0)
	assert_time(coast_at, 6.0, "counted from the bind (t 0): stale at 3 s, coasting at 6 s")


func test_the_watchdog_restarts_at_a_reconnect() -> void:
	var dev := _quiet()
	var rig := make_rig({}, dev)
	rig.start([erg(Wl.WORK, 75.0, 600.0)])
	rig.run(10.0)
	dev.silent = true
	dev.link = TrainerDevice.STATUS_DISCONNECTED
	rig.run(20.0)
	dev.link = TrainerDevice.STATUS_READY
	var t_back := rig.t
	rig.gov.on_trainer_reconnected()
	rig.run(2.9)
	assert_false(bool(rig.s()["samples_stale"]), "counted from the reconnect, not from the last sample")
	var coast_at := rig.run_until(func() -> bool: return rig.gov.is_coasting(), 5.0)
	assert_time(coast_at, t_back + 6.0)


func test_the_rescue_power_trigger_sees_it_but_coasting_wins() -> void:
	var dev := _quiet()
	var rig := make_rig({}, dev)
	rig.start([erg(Wl.WORK, 75.0, 600.0)])
	rig.run(20.0)
	dev.silent = true
	rig.run(15.0)
	assert_true(rig.gov.is_rescue(), "power below 75% of the target for 5 s (from the stale sample)")
	assert_eq(rig.applied_w(), GovernorClamps.floor_w(200.0), "the coasting floor wins over rescue's 50% (4.6.12)")
