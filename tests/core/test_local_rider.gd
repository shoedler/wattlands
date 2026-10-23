extends GutTest
## LocalRider (BRIEF 4.1, docs/ARCHITECTURE.md "The per-rider stack"): composition, the
## per-tick sample flow, every Telemetry field, the gesture, intent and ack queues, band
## forwarding, laps, pause requests, shutdown and the live-rider registry. The governor,
## gestures and recorder are test doubles (tests/core/helpers/fakes.gd); the device is the
## W0 MockTrainer or a hand-driven FakeDevice.

const Fakes := preload("res://tests/core/helpers/fakes.gd")
const DT := Wl.SIM_DT

var _bus: WlEventBus = null


func before_each() -> void:
	_bus = WlEventBus.new()
	autofree(_bus)


func after_each() -> void:
	# Let replaced governors (queue_free) go before GUT counts orphans.
	await wait_process_frames(1)


func _profile(ftp: float = 200.0) -> RiderProfile:
	var p := RiderProfile.new()
	p.display_name = "Tester"
	p.ftp_w = ftp
	p.cp_w = ftp
	p.weight_kg = 80.0
	p.difficulty_pct = 60.0
	p.grade_min_pct = -4.0
	p.grade_max_pct = 9.0
	p.skip_warmup = false
	p.created = true
	return p


func _mock(spec: String = "const:w=200,rpm=90", ftp: float = 200.0) -> MockTrainer:
	var m := MockTrainer.from_spec(spec, ftp, {"seed": 7})
	autofree(m)
	return m


func _fake_device() -> Fakes.FakeDevice:
	var d := Fakes.FakeDevice.new()
	autofree(d)
	return d


## A rider with a FakeGovernor, FakeGestures and (optionally) a FakeRecorder.
func _rider(
	device: TrainerDevice,
	opts: Dictionary = {},
	profile: RiderProfile = null,
	slot: PlayerSlot = null
) -> LocalRider:
	var r := LocalRider.new()
	add_child_autofree(r)
	var o := {
		"governor": Fakes.FakeGovernor.new(),
		"gestures": Fakes.FakeGestures.new(),
		"bus": _bus,
	}
	o.merge(opts, true)
	var p := profile if profile != null else _profile()
	r.setup(3, p, slot, device, o)
	return r


func _gov(r: LocalRider) -> Fakes.FakeGovernor:
	return r.governor as Fakes.FakeGovernor


func _ges(r: LocalRider) -> Fakes.FakeGestures:
	return r.gestures as Fakes.FakeGestures


func _run(r: LocalRider, seconds: float) -> void:
	for _i in roundi(seconds / DT):
		r.tick(DT)


# --- composition -------------------------------------------------------------------------


func test_setup_composes_the_stack() -> void:
	var m := _mock()
	var r := _rider(m, {"multiplayer": false, "skip_warmup": true})
	var g := _gov(r)
	assert_eq(r.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(r.peer_id, 3)
	assert_eq(g.setup_device, m, "the governor owns the device's controller")
	assert_eq(g.get_parent(), r, "the governor lives under the rider")
	assert_eq(g.process_mode, Node.PROCESS_MODE_ALWAYS)
	var c := g.configured
	assert_eq(c.get("ftp_w"), 200.0)
	assert_eq(c.get("ftp_verified"), false)
	assert_eq(c.get("difficulty_pct"), 60.0)
	assert_eq(c.get("grade_min_pct"), -4.0)
	assert_eq(c.get("grade_max_pct"), 9.0)
	assert_eq(c.get("haptics_on"), true)
	assert_almost_eq(float(c.get("haptic_intensity")), 0.7, 1e-6)
	assert_eq(c.get("skip_warmup"), true, "options win over the profile")
	assert_eq(c.get("multiplayer"), false)
	assert_eq(c.get("weight_kg"), 80.0)
	assert_eq(c.get("trainer_max_w"), MockTrainer.DEFAULT_MAX_POWER_W)
	assert_eq(c.get("profile"), "normal")
	assert_eq(_ges(r).configured, [200.0, true], "gestures: FTP and solo")
	assert_eq(r.wbal.cp_w, 200.0)
	assert_eq(r.wbal.wprime_j, 20000.0)
	assert_eq(r.speed.rider_mass_kg, 75.0, "FAIR_FTP mass")
	assert_not_null(r.cadence)
	assert_null(r.recorder, "no recording unless asked")
	assert_eq(r.slot.p_eff_per_w, 1.25, "slot from the profile when none is given")


func test_default_components_are_the_real_classes() -> void:
	var r := LocalRider.new()
	add_child_autofree(r)
	r.setup(1, _profile(), null, _mock(), {"bus": _bus})
	assert_true(r.governor is SafetyGovernor)
	assert_eq(r.governor.get_parent(), r)
	assert_true(r.gestures is GestureRecognizer)
	assert_true(r.cadence is CadenceEstimator)
	r.tick(DT)
	assert_eq(r.telemetry().peer_id, 1)


func test_slot_drives_multiplayer_and_mass() -> void:
	var p := _profile(250.0)
	p.weight_kg = 90.0
	p.share_weight = true
	var slot := p.to_slot(5, Wl.RAW)
	var r := _rider(_mock(), {"multiplayer": true, "scaling_mode": Wl.RAW}, p, slot)
	assert_eq(r.speed.rider_mass_kg, 90.0, "RAW with the weight shared")
	assert_eq(_ges(r).configured, [250.0, false], "multiplayer turns solo gestures off")
	assert_eq(_gov(r).configured.get("multiplayer"), true)
	assert_eq(r.scaling_mode, Wl.RAW)
	assert_eq(r.peer_id, 3, "the peer id given to setup()")


func test_setup_resets_a_reused_mock() -> void:
	var m := Fakes.RecordingMock.new()
	autofree(m)
	var r := _rider(m)
	r.set_cadence_band(80.0, 95.0)
	r.set_power_band(150.0, 250.0)
	r.start_phase(3)
	r.setup(
		3,
		_profile(),
		null,
		m,
		{"governor": Fakes.FakeGovernor.new(), "gestures": Fakes.FakeGestures.new(), "bus": _bus}
	)
	assert_eq(m.cadence_bands.back(), [0.0, 0.0], "no band left over from the last session")
	assert_eq(m.power_bands.back(), [0.0, 0.0])
	assert_eq(m.phases.back(), -1)
	assert_eq(r.cadence_band(), Vector2.ZERO)
	assert_eq(r.telemetry().phase_index, -1)


func test_setup_again_while_recording_saves_the_ride_first() -> void:
	var rec := Fakes.FakeRecorder.new()
	var m := _mock()
	var r := _rider(m, {"recorder": rec, "rides_dir": "C:/rides/a"})
	_run(r, 2.0)
	watch_signals(_bus)
	r.setup(
		3,
		_profile(),
		null,
		m,
		{"governor": Fakes.FakeGovernor.new(), "gestures": Fakes.FakeGestures.new(), "bus": _bus}
	)
	assert_push_warning("recording")
	assert_eq(rec.saves, ["C:/rides/a"] as Array[String], "saved where the old options said")
	assert_almost_eq(rec.stopped_at, 2.0, 1e-9)
	assert_signal_emitted(_bus, "ride_saved")
	assert_null(r.recorder, "the new setup records only if asked")


func test_rebind_device_keeps_the_session() -> void:
	var d1 := _fake_device()
	var d2 := _fake_device()
	var rec := Fakes.FakeRecorder.new()
	var r := _rider(d1, {"recorder": rec})
	var g := _gov(r)
	var plan := _plan()
	r.set_plan(plan)
	r.start_phase(1)
	r.push_intent({"k": "keep"})
	_run(r, 1.0)
	d1.emit_sample(150.0, 80.0)
	r.rebind_device(d2)
	assert_eq(r.device, d2)
	assert_eq(g.setup_device, d2, "the governor drives the new object")
	assert_eq(r.governor, g, "same governor, same plan and phase state")
	assert_eq(r.plan(), plan)
	assert_eq(r.recorder, rec)
	r.tick(DT)
	assert_eq(g.samples.size(), 0, "a sample queued from the old object is dropped")
	d1.emit_sample(999.0, 80.0)
	d2.emit_sample(210.0, 85.0)
	r.tick(DT)
	assert_eq(g.samples.size(), 1, "only the new object feeds the rider")
	assert_eq(g.samples[0].power_w, 210.0)
	var tel := r.telemetry()
	assert_almost_eq(tel.t, 1.1, 1e-9, "the rider's time keeps running")
	assert_eq(tel.phase_index, 1)
	assert_eq(r.take_intents(), [{"k": "keep"}])
	assert_true(LocalRider.live_riders().has(r))
	r.rebind_device(d2)
	assert_eq(g.called("setup").size(), 2, "rebinding to the same object does nothing")


## W2: the same device object reconnected (BRIEF 4.4): the governor restores the last safe
## mode through its ramped path; the session stays.
func test_trainer_reconnected_resyncs_the_governor() -> void:
	var d := _fake_device()
	var rec := Fakes.FakeRecorder.new()
	var r := _rider(d, {"recorder": rec})
	var g := _gov(r)
	var plan := _plan()
	r.set_plan(plan)
	r.start_phase(1)
	_run(r, 1.0)
	r.trainer_reconnected()
	assert_eq(g.called("on_trainer_reconnected").size(), 1)
	assert_eq(g.called("setup").size(), 1, "no rebind: same device, same governor binding")
	assert_eq(r.device, d)
	assert_eq(r.plan(), plan)
	assert_eq(r.telemetry().phase_index, 1)
	assert_eq(r.recorder, rec)
	r.shutdown()
	r.trainer_reconnected()
	assert_eq(g.called("on_trainer_reconnected").size(), 1, "nothing after shutdown")
	var fresh := LocalRider.new()
	add_child_autofree(fresh)
	fresh.trainer_reconnected()
	assert_null(fresh.governor, "nothing before setup")


## W2: the timed gestures (coast, stop_5s, pedal_start) due between samples fire on the tick
## they are due (GestureRecognizer.advance), not only with the next sample.
func test_timed_gestures_fire_between_samples() -> void:
	var r := _rider(_fake_device())
	var ges := _ges(r)
	ges.advance_fire = {2: [Wl.G_STOP_5S]}
	watch_signals(r)
	_run(r, 3 * DT)
	assert_eq(ges.advance_calls.size(), 3, "once per tick")
	assert_almost_eq(ges.advance_calls[1], 2 * DT, 1e-9, "at the tick's platform time")
	assert_eq(r.take_gestures(), [Wl.G_STOP_5S] as Array[StringName])
	assert_signal_emitted_with_parameters(r, "gesture_detected", [Wl.G_STOP_5S])
	assert_signal_not_emitted(r, "pause_requested", "the gesture alone pauses nothing")


## W2: Telemetry.acks carry refused as a bool and the governor's dropped channels.
func test_acks_have_a_bool_refused_and_the_dropped_channels() -> void:
	var r := _rider(_mock())
	_gov(r).directive_applied.emit(
		{
			"id": 5,
			"kind": "request",
			"applied": {"mode": "SIM"},
			"clamped_by": [],
			"refused": 0,
			"reason": "",
			"requested": {},
			"dropped": [{"channel": "haptic", "reason": Wl.REFUSE_HAPTIC_WARMUP, "extra": 1}]
		}
	)
	var acks := r.take_acks()
	assert_eq(acks.size(), 1)
	assert_eq(typeof(acks[0]["refused"]), TYPE_BOOL)
	assert_false(acks[0]["refused"])
	assert_eq(acks[0]["dropped"], [{"channel": "haptic", "reason": Wl.REFUSE_HAPTIC_WARMUP}])
	_gov(r).directive_applied.emit(
		{"id": 6, "kind": "request", "refused": true, "reason": Wl.REFUSE_RANGE}
	)
	acks = r.take_acks()
	assert_true(acks[0]["refused"])
	assert_eq(acks[0]["dropped"], [], "no dropped list: empty")


## W2 (trainer-core's note): a mock that rode through the menus restarts its profile at the
## session's setup, so `cadence_drop:at_s`, surges, ramps and intervals count from the
## session start, like the rider's platform time.
func test_setup_restarts_a_mock_profile() -> void:
	var m := _mock("erg+cadence_drop:rpm=30,at_s=20,for_s=5")
	var r := _rider(m)
	_run(r, 15.0)
	assert_almost_eq(m.profile_time_s(), 15.0, 1e-6)
	r.setup(
		3,
		_profile(),
		null,
		m,
		{"governor": Fakes.FakeGovernor.new(), "gestures": Fakes.FakeGestures.new(), "bus": _bus}
	)
	assert_almost_eq(m.profile_time_s(), 0.0, 1e-9, "profile time starts again with the session")
	_run(r, 7.0)
	assert_false(
		m.cadence_drop_active(), "at_s=20 counts from the new setup (22 s since the mock started)"
	)
	_run(r, 14.0)
	assert_true(m.cadence_drop_active(), "21 s after the setup")


func test_rebind_device_needs_a_set_up_rider() -> void:
	var r := LocalRider.new()
	add_child_autofree(r)
	r.rebind_device(_fake_device())
	assert_push_error("rebind_device")
	var ok := _rider(_fake_device())
	ok.rebind_device(null)
	assert_push_error("rebind_device")


func test_setup_without_device_is_refused() -> void:
	var r := LocalRider.new()
	add_child_autofree(r)
	r.setup(2, _profile(), null, null, {"bus": _bus})
	assert_push_error("needs a TrainerDevice")
	r.tick(DT)
	assert_eq(r.telemetry().power_w, 0.0)
	assert_false(LocalRider.live_riders().has(r))


func test_setup_again_rebuilds_without_double_samples() -> void:
	var m := _mock()
	var r := _rider(m)
	var first := _gov(r)
	var g2 := Fakes.FakeGovernor.new()
	r.setup(
		4, _profile(), null, m, {"governor": g2, "gestures": Fakes.FakeGestures.new(), "bus": _bus}
	)
	assert_eq(r.peer_id, 4)
	assert_true(first.is_queued_for_deletion(), "the old governor goes away")
	_run(r, 5.0)
	assert_eq(first.samples.size(), 0)
	assert_between(g2.samples.size(), 4, 6, "one sample per notification, not two")
	assert_almost_eq(r.platform_time(), 5.0, 1e-9, "time restarts at setup")


## W2r2: a gesture handler (a menu pick) that sets the rider up again from inside the rider's
## own tick ends that tick: the new governor, ride and gestures never see the old platform time.
func test_setup_from_a_gesture_handler_ends_the_tick() -> void:
	var m := _mock()
	var rec1 := Fakes.FakeRecorder.new()
	var r := _rider(m, {"recorder": rec1})
	var first := _gov(r)
	_ges(r).fire_at = {1: ["surge", "coast"]}
	var g2 := Fakes.FakeGovernor.new()
	var ges2 := Fakes.FakeGestures.new()
	var rec2 := Fakes.FakeRecorder.new()
	var seen: Array[StringName] = []
	var telemetry_ts: Array[float] = []
	r.telemetry_updated.connect(func(tel: Telemetry) -> void: telemetry_ts.append(tel.t))
	r.gesture_detected.connect(
		func(g: StringName) -> void:
			seen.append(g)
			if r.governor == first:
				r.setup(
					4,
					_profile(),
					null,
					m,
					{"governor": g2, "gestures": ges2, "recorder": rec2, "bus": _bus}
				)
	)
	var ticks := 0
	while seen.is_empty() and ticks < 100:
		r.tick(DT)
		ticks += 1
	assert_push_warning("recording")
	assert_eq(
		seen, [&"surge"] as Array[StringName], "the old setup's remaining gestures are dropped"
	)
	assert_eq(r.take_gestures().size(), 0, "nothing from the old setup is queued for the new one")
	assert_eq(r.governor, g2)
	assert_almost_eq(r.platform_time(), 0.0, 1e-12, "the new setup's time starts at 0")
	assert_eq(
		first.samples.size(), 0, "the sample that fired the gesture never reaches the old governor"
	)
	assert_eq(first.ticks.size(), ticks - 1, "the old governor isn't ticked in the cut tick")
	assert_eq(g2.ticks.size(), 0, "the new governor isn't ticked with the old time")
	assert_eq(g2.samples.size(), 0)
	assert_eq(ges2.advance_calls.size(), 0, "the new gestures never see the old time")
	assert_eq(rec2.records.size(), 0, "the new ride gets no record at the old time")
	assert_eq(telemetry_ts.size(), ticks - 1, "no telemetry for the cut tick")
	r.tick(DT)
	assert_almost_eq(r.platform_time(), DT, 1e-12)
	assert_eq(g2.ticks, [DT] as Array[float])
	assert_eq(ges2.advance_calls.size(), 1)
	assert_almost_eq(ges2.advance_calls[0], DT, 1e-12)
	assert_eq(rec2.records.size(), 1)
	assert_almost_eq(float(rec2.records[0][0]), DT, 1e-12, "the new ride starts at its own time")


## W2r2: the same holds for a handler of the device's own sample signal.
func test_setup_from_a_sample_handler_ends_the_tick() -> void:
	var m := _mock()
	var r := _rider(m)
	var first := _gov(r)
	var g2 := Fakes.FakeGovernor.new()
	var ges2 := Fakes.FakeGestures.new()
	m.sample_received.connect(
		func(_s: TrainerSample) -> void:
			if r.governor == first:
				r.setup(5, _profile(), null, m, {"governor": g2, "gestures": ges2, "bus": _bus})
	)
	var ticks := 0
	while r.governor == first and ticks < 100:
		r.tick(DT)
		ticks += 1
	assert_eq(r.governor, g2)
	assert_almost_eq(r.platform_time(), 0.0, 1e-12)
	assert_eq(first.ticks.size(), ticks - 1)
	assert_eq(g2.ticks.size(), 0)
	assert_eq(g2.samples.size(), 0, "the sample from the old setup isn't handed on")
	assert_eq(ges2.seen.size(), 0)
	assert_eq(ges2.advance_calls.size(), 0)
	_run(r, 2.0)
	assert_eq(g2.ticks.size(), 40)
	assert_almost_eq(r.platform_time(), 2.0, 1e-9)


# --- sample flow and telemetry -------------------------------------------------------------


func test_sample_flow_reaches_gestures_and_governor() -> void:
	var r := _rider(_mock())
	var g := _gov(r)
	_run(r, 3.0)
	assert_between(g.samples.size(), 2, 4, "about 1 Hz")
	assert_eq(_ges(r).seen.size(), g.samples.size(), "every sample reaches the gestures")
	assert_eq(g.ticks.size(), 60, "the governor ticks every step")
	assert_eq(_ges(r).erg_flags.back(), false, "not ERG while the governor is OFF")
	var last_t := -1.0
	for s in g.samples:
		assert_gt(s.t, last_t, "samples carry the rider's rising time")
		assert_almost_eq(fmod(s.t + 1e-9, DT), 0.0, 1e-6, "stamped on a tick")
		last_t = s.t
		assert_eq(s.power_w, 200.0)
		assert_eq(s.cadence_rpm, 90.0)
	g.st = {"mode": Wl.ERG}
	_run(r, 1.2)
	assert_eq(_ges(r).erg_flags.back(), true, "ERG mode reaches the gestures")


func test_telemetry_fields() -> void:
	var r := _rider(_mock())
	var g := _gov(r)
	g.st = {
		"mode": Wl.ERG,
		"applied_target_w": 150,
		"applied_grade_pct": 4.0,
		"gear": 14,
		"clamped_by": [Wl.CLAMP_SLEW, Wl.CLAMP_WARMUP],
		"rescue": true,
		"coasting": false,
		"afk": false,
		"paused": false,
		"s_left_105": 250.0,
		"s_left_120": 50.0,
		"haptic_pct": 0.0,
	}
	r.start_phase(2)
	watch_signals(r)
	_run(r, 2.0)
	assert_signal_emit_count(r, "telemetry_updated", 40, "once per tick")
	var tel := r.telemetry()
	assert_eq(tel.peer_id, 3)
	assert_almost_eq(tel.t, 2.0, 1e-9)
	assert_eq(tel.power_w, 200.0)
	assert_eq(tel.cadence_rpm, 90.0)
	assert_almost_eq(tel.speed_kmh, 36.0, 1e-6, "the trainer's reported speed")
	assert_almost_eq(tel.effort, 1.0, 1e-9, "FAIR_FTP effort = P / FTP")
	assert_eq(tel.p_eff_w, tel.power_w * r.slot.p_eff_per_w)
	assert_almost_eq(tel.p_eff_w, 250.0, 1e-9)
	assert_almost_eq(tel.ftp_pct, 100.0, 1e-9)
	assert_eq(tel.wbal_j, r.wbal.wbal_j)
	assert_eq(tel.mode, Wl.ERG)
	assert_eq(tel.applied_target_w, 150)
	assert_eq(tel.applied_grade_pct, 0.0, "no grade outside SIM")
	assert_eq(tel.gear, 14)
	assert_eq(tel.clamped_by, [Wl.CLAMP_SLEW, Wl.CLAMP_WARMUP] as Array[String])
	assert_true(tel.rescue)
	assert_false(tel.coasting)
	assert_false(tel.afk)
	assert_false(tel.paused)
	assert_eq(tel.s_left_105, 250.0)
	assert_eq(tel.s_left_120, 50.0)
	assert_eq(tel.phase_index, 2)
	assert_true(tel.connected)
	assert_eq(tel.age_s, 0.0)
	assert_gt(tel.distance_m, 0.0)
	assert_lt(tel.cadence_age_s, 1.2)
	assert_eq(tel.gestures.size(), 0, "gestures travel through take_gestures()")
	assert_eq(tel.intents.size(), 0)
	g.st = {"mode": Wl.SIM, "applied_target_w": 150, "applied_grade_pct": 4.0, "haptic_pct": 1.5}
	tel = r.telemetry()
	assert_eq(tel.applied_target_w, 0, "no ERG target outside ERG")
	assert_eq(tel.applied_grade_pct, 4.0)
	assert_eq(tel.haptic_pct, 1.5)
	assert_eq(tel.gear, 12, "default gear when the governor gives none")


func test_telemetry_is_a_fresh_object_each_call() -> void:
	var r := _rider(_mock())
	_run(r, 1.5)
	var a := r.telemetry()
	var b := r.telemetry()
	assert_ne(a, b)
	assert_eq(a.to_dict(), b.to_dict())
	a.power_w = 999.0
	assert_eq(r.telemetry().power_w, 200.0)


func test_telemetry_signal_carries_the_tick_state() -> void:
	var r := _rider(_mock())
	var got: Array[Telemetry] = []
	r.telemetry_updated.connect(func(t: Telemetry) -> void: got.append(t))
	_run(r, 0.5)
	assert_eq(got.size(), 10)
	assert_almost_eq(got[9].t, 0.5, 1e-9)
	assert_almost_eq(got[0].t, DT, 1e-9)


func test_p_eff_follows_the_slot_in_every_mode() -> void:
	for mode: String in Wl.SCALING_MODES:
		var p := _profile(250.0)
		p.weight_kg = 70.0
		var slot := p.to_slot(3, mode)
		var r := _rider(_mock("const:w=300,rpm=90", 250.0), {"scaling_mode": mode}, p, slot)
		_run(r, 1.5)
		var tel := r.telemetry()
		assert_eq(tel.power_w, 300.0, mode)
		assert_eq(
			tel.p_eff_w, 300.0 * slot.p_eff_per_w, mode + ": p_eff_w == power_w x p_eff_per_w"
		)
		assert_almost_eq(tel.effort, EffortScaling.effort(mode, 300.0, 250.0, 70.0), 1e-9, mode)


func test_wbal_drains_on_raw_power_above_cp() -> void:
	var r := _rider(_mock("const:w=300,rpm=90"))
	_run(r, 11.0)
	var drained := 20000.0 - r.telemetry().wbal_j
	assert_between(drained, 900.0, 1100.0, "about (300 - 200) W x ~10 s after the first sample")
	var r2 := _rider(_mock("const:w=150,rpm=90"))
	_run(r2, 10.0)
	assert_eq(r2.telemetry().wbal_j, 20000.0, "below CP it stays full")


func test_speed_model_uses_p_eff_and_the_applied_grade() -> void:
	var flat := _rider(_mock())
	var hill := _rider(_mock())
	_gov(hill).st = {"mode": Wl.SIM, "applied_grade_pct": 6.0}
	_gov(flat).st = {"mode": Wl.SIM, "applied_grade_pct": 0.0}
	_run(flat, 30.0)
	_run(hill, 30.0)
	assert_gt(flat.speed.v_mps, hill.speed.v_mps, "a grade slows the speed model")
	assert_eq(
		_gov(flat).course_distance, flat.speed.distance_m, "course distance from the speed model"
	)
	var erg := _rider(_mock())
	_gov(erg).st = {"mode": Wl.ERG, "applied_grade_pct": 6.0}
	_run(erg, 30.0)
	assert_almost_eq(erg.speed.v_mps, flat.speed.v_mps, 1e-9, "no grade in ERG")
	var oracle := SpeedModel.steady_state_speed(250.0, 0.0, 83.0)
	assert_almost_eq(flat.speed.v_mps, oracle, 3.0, "heading for the P_eff steady state")


func test_stale_samples_read_zero() -> void:
	var d := _fake_device()
	var r := _rider(d)
	d.emit_sample(180.0, 85.0, 30.0)
	r.tick(DT)
	assert_eq(r.telemetry().power_w, 180.0)
	_run(r, 2.9)
	assert_eq(r.telemetry().power_w, 180.0, "held between notifications")
	_run(r, 0.2)
	var tel := r.telemetry()
	assert_eq(tel.power_w, 0.0, "older than 3 s counts as gone")
	assert_eq(tel.cadence_rpm, 0.0)
	assert_eq(tel.speed_kmh, 0.0)


func test_cadence_age() -> void:
	var d := _fake_device()
	var r := _rider(d)
	_run(r, 1.0)
	assert_almost_eq(r.telemetry().cadence_age_s, 1.0, 1e-9, "no cadence yet: time since setup")
	d.emit_sample(150.0, 80.0)
	r.tick(DT)
	assert_almost_eq(r.telemetry().cadence_age_s, 0.0, 1e-9)
	d.emit_sample(150.0)
	_run(r, 2.0)
	assert_almost_eq(
		r.telemetry().cadence_age_s, 2.0, 1e-6, "a sample without cadence doesn't refresh it"
	)
	assert_eq(r.telemetry().cadence_rpm, 0.0)


# --- gestures, intents, acks -------------------------------------------------------------


func test_gesture_queue() -> void:
	var d := _fake_device()
	var r := _rider(d)
	_ges(r).fire_at = {1: [Wl.G_SURGE], 2: [Wl.G_COAST, Wl.G_PEDAL_START]}
	watch_signals(r)
	d.emit_sample(200.0, 90.0)
	r.tick(DT)
	d.emit_sample(10.0, 5.0)
	r.tick(DT)
	assert_signal_emit_count(r, "gesture_detected", 3)
	assert_eq(r.take_gestures(), [Wl.G_SURGE, Wl.G_COAST, Wl.G_PEDAL_START] as Array[StringName])
	assert_eq(r.take_gestures(), [] as Array[StringName], "taken once")
	assert_signal_not_emitted(r, "pause_requested")


## Feed one sample a second (power, cadence) for `seconds`.
func _ride(r: LocalRider, d: Fakes.FakeDevice, seconds: float, power: float, rpm: float) -> void:
	var steps := roundi(seconds / DT)
	for i in steps:
		if i % 20 == 0:
			d.emit_sample(power, rpm, rpm * 0.4)
		r.tick(DT)


## BRIEF 3.5: 5 s of not_pedaling ride-pauses the rider (FIT timer stop), 1 s of pedaling at
## >= 30 rpm resumes; in solo the pause also asks the GameHost to pause the game clock.
func test_ride_pause_after_5_s_and_resume_after_1_s_in_solo() -> void:
	var d := _fake_device()
	var rec := Fakes.FakeRecorder.new()
	var r := _rider(d, {"recorder": rec})
	watch_signals(r)
	_ride(r, d, 2.0, 200.0, 90.0)
	_ride(r, d, 4.9, 0.0, 0.0)
	assert_false(r.is_ride_paused(), "not yet: 4.9 s")
	_ride(r, d, 0.2, 0.0, 0.0)
	assert_true(r.is_ride_paused(), "5 s after the first not_pedaling sample")
	assert_signal_emitted_with_parameters(r, "ride_paused_changed", [true])
	assert_signal_emitted_with_parameters(r, "pause_requested", ["stop_5s"])
	assert_eq(rec.timer.size(), 1)
	assert_eq(rec.timer[0][0], false, "the ride timer stops")
	assert_almost_eq(float(rec.timer[0][1]), 7.0, 0.051)
	assert_true(r.telemetry().paused)
	_ride(r, d, 3.0, 20.0, 25.0)
	assert_true(r.is_ride_paused(), "25 rpm is not enough to resume")
	_ride(r, d, 0.95, 120.0, 35.0)
	assert_true(r.is_ride_paused(), "not yet: under 1 s at >= 30 rpm")
	_ride(r, d, 0.1, 120.0, 35.0)
	assert_false(r.is_ride_paused(), "1 s at >= 30 rpm resumes")
	assert_signal_emitted_with_parameters(r, "ride_paused_changed", [false])
	assert_eq(rec.timer.back()[0], true, "the ride timer runs again")
	assert_false(r.telemetry().paused)


func test_a_pedaling_sample_restarts_the_5_s() -> void:
	var d := _fake_device()
	var r := _rider(d)
	_ride(r, d, 4.0, 0.0, 0.0)
	_ride(r, d, 1.0, 100.0, 80.0)
	_ride(r, d, 4.0, 0.0, 0.0)
	assert_false(r.is_ride_paused())
	_ride(r, d, 1.1, 0.0, 0.0)
	assert_true(r.is_ride_paused())


## In multiplayer the pause stops only this rider's ride timer and shows in Telemetry.paused;
## the shared game pause does not count as the rider's own (the host decides on it).
func test_ride_pause_in_multiplayer() -> void:
	var d := _fake_device()
	var rec := Fakes.FakeRecorder.new()
	var mp := _rider(d, {"multiplayer": true, "recorder": rec})
	watch_signals(mp)
	_ride(mp, d, 5.1, 0.0, 0.0)
	assert_true(mp.is_ride_paused())
	assert_signal_emitted_with_parameters(mp, "ride_paused_changed", [true])
	assert_signal_not_emitted(mp, "pause_requested")
	assert_true(mp.telemetry().paused)
	assert_eq(rec.timer.back()[0], false)
	_ride(mp, d, 1.1, 150.0, 85.0)
	assert_false(mp.telemetry().paused)
	mp.set_game_paused(true)
	assert_false(mp.telemetry().paused, "the shared game pause is not the rider's own")
	assert_eq(rec.timer.back()[0], false, "but the ride timer stops with it")


func test_bots_never_ride_pause() -> void:
	var d := _fake_device()
	var slot := Bots.make_slot(1, 1, 200.0)
	var bot := _rider(d, {}, null, slot)
	watch_signals(bot)
	_ride(bot, d, 6.0, 0.0, 0.0)
	assert_false(bot.is_ride_paused())
	assert_signal_not_emitted(bot, "pause_requested")


## Heart rate: the paired sensor's bpm (heart_rate_source), else a MockTrainer `hr` profile,
## reaches Telemetry and the recorder; 0 means none.
func test_heart_rate_from_the_source_or_the_mock() -> void:
	var rec := RideRecorder.new()
	var r := _rider(_mock("const:w=200,rpm=90"), {"recorder": rec})
	_run(r, 1.0)
	assert_eq(r.telemetry().heart_rate_bpm, 0, "no sensor")
	r.heart_rate_source = func() -> int: return 133
	_run(r, 2.0)
	assert_eq(r.telemetry().heart_rate_bpm, 133)
	var recs := rec.records()
	assert_eq(int(recs.back()["heart_rate_bpm"]), 133, "recorded each second")
	var m := _rider(_mock("const:w=200,rpm=90+hr:rest_bpm=60,max_bpm=180"))
	_run(m, 120.0)
	var bpm := m.telemetry().heart_rate_bpm
	assert_between(bpm, 120, 180, "the mock's heart rate follows power")
	m.heart_rate_source = func() -> int: return 0
	assert_eq(m.telemetry().heart_rate_bpm, bpm, "a quiet sensor falls back to the mock")


func test_gesture_queue_is_bounded() -> void:
	var d := _fake_device()
	var r := _rider(d)
	var plan := {}
	for i in range(1, LocalRider.MAX_QUEUE + 11):
		plan[i] = [Wl.G_SURGE]
	_ges(r).fire_at = plan
	for i in LocalRider.MAX_QUEUE + 10:
		d.emit_sample(200.0, 90.0)
		r.tick(DT)
	assert_eq(r.take_gestures().size(), LocalRider.MAX_QUEUE)


func test_intents_queue() -> void:
	var r := _rider(_mock())
	var intent := {"k": "route", "to": "gen"}
	r.push_intent(intent)
	r.push_intent({"k": "overdrive"})
	intent["to"] = "changed"
	var got := r.take_intents()
	assert_eq(got, [{"k": "route", "to": "gen"}, {"k": "overdrive"}], "copies, in order")
	assert_eq(r.take_intents(), [])


func test_apply_directive_acks_once_when_the_governor_emits() -> void:
	var r := _rider(_mock())
	watch_signals(r)
	var d := EffortDirective.from_dict(
		{"target_pct": 80.0, "duration_s": 10, "reason": "pull", "source": "fishing"}
	)
	d.id = 41
	var rec := r.apply_directive(d)
	assert_eq(rec.get("id"), 41)
	assert_signal_emit_count(r, "directive_applied", 1)
	var acks := r.take_acks()
	assert_eq(acks.size(), 1)
	assert_eq(
		acks[0],
		{
			"id": 41,
			"kind": "request",
			"applied": {"target_pct": 80.0},
			"clamped_by": [Wl.CLAMP_SLEW],
			"refused": false,
			"reason": "",
			"dropped": []
		}
	)
	assert_eq(r.take_acks(), [], "taken once")


func test_apply_directive_acks_once_when_the_governor_only_returns() -> void:
	var r := _rider(_mock())
	_gov(r).emit_on_apply = false
	watch_signals(r)
	var d := EffortDirective.from_dict({"mode": "SIM", "duration_s": 30, "reason": "overdrive"})
	d.id = 7
	r.apply_directive(d)
	assert_signal_emit_count(r, "directive_applied", 1)
	assert_eq(r.take_acks().size(), 1)


func test_governor_records_outside_apply_are_acked() -> void:
	var r := _rider(_mock())
	watch_signals(r)
	r.apply_course_grade(3.5)
	assert_eq(_gov(r).course_grade, 3.5)
	_gov(r).directive_applied.emit(
		{
			"id": 9,
			"kind": "course_grade",
			"applied": {"grade_pct": 3.5},
			"clamped_by": [],
			"refused": false,
			"reason": "",
			"requested": {"grade_pct": 3.5}
		}
	)
	assert_signal_emit_count(r, "directive_applied", 1)
	var acks := r.take_acks()
	assert_eq(acks[0]["kind"], "course_grade")
	assert_false(acks[0].has("requested"), "acks carry what was applied")


func test_governor_signals_are_forwarded() -> void:
	var r := _rider(_mock())
	watch_signals(r)
	var g := _gov(r)
	g.rescue_changed.emit(true)
	g.afk_changed.emit(true)
	g.pause_requested.emit("coasting")
	assert_signal_emitted_with_parameters(r, "rescue_changed", [true])
	assert_signal_emitted_with_parameters(r, "afk_changed", [true])
	assert_signal_emitted_with_parameters(r, "pause_requested", ["coasting"])


func test_governor_status_reaches_the_bus_for_humans_only() -> void:
	var r := _rider(_mock())
	watch_signals(_bus)
	_gov(r).status_changed.emit({"mode": Wl.ERG})
	assert_signal_emitted_with_parameters(_bus, "governor_status", [3, {"mode": Wl.ERG}])
	var bot_slot := Bots.make_slot(1, 1, 200.0)
	var bot := _rider(_mock("erg"), {}, Bots.make_profile(1, 200.0), bot_slot)
	assert_true(bot.is_bot)
	_gov(bot).status_changed.emit({"mode": Wl.ERG})
	assert_signal_emit_count(_bus, "governor_status", 1)


# --- bands, phases, laps ------------------------------------------------------------------


func test_bands_reach_the_mock_trainer_and_the_bus() -> void:
	var m := Fakes.RecordingMock.new()
	autofree(m)
	var r := _rider(m)
	assert_eq(m.cadence_bands, [[0.0, 0.0]], "setup clears a reused mock's band")
	m.cadence_bands.clear()
	m.power_bands.clear()
	watch_signals(_bus)
	r.set_cadence_band(80.0, 95.0)
	r.set_power_band(150.0, 250.0)
	assert_eq(m.cadence_bands, [[80.0, 95.0]])
	assert_eq(m.power_bands, [[150.0, 250.0]])
	assert_signal_emitted_with_parameters(_bus, "cadence_band_changed", [3, 80.0, 95.0])
	assert_signal_emitted_with_parameters(_bus, "power_band_changed", [3, 150.0, 250.0])
	assert_eq(r.cadence_band(), Vector2(80, 95))
	r.set_cadence_band(80.0, 95.0)
	assert_signal_emit_count(_bus, "cadence_band_changed", 1, "unchanged band: no event")
	r.set_cadence_band(0.0, 0.0)
	assert_eq(m.cadence_bands.back(), [0.0, 0.0], "0, 0 clears")
	assert_signal_emitted_with_parameters(_bus, "cadence_band_changed", [3, 0.0, 0.0])


func test_bands_with_a_real_trainer_still_reach_the_bus() -> void:
	var r := _rider(_fake_device())
	watch_signals(_bus)
	r.set_power_band(100.0, 120.0)
	assert_signal_emitted_with_parameters(_bus, "power_band_changed", [3, 100.0, 120.0])


func test_bad_bands_are_refused() -> void:
	var r := _rider(_mock())
	r.set_cadence_band(95.0, 80.0)
	assert_push_error("bad cadence band")
	r.set_power_band(-5.0, 10.0)
	assert_push_error("bad power band")
	assert_eq(r.cadence_band(), Vector2.ZERO)


func _plan() -> EffortPlan:
	var plan := (
		EffortPlan
		. of(
			[
				PlanPhase.erg(Wl.WARMUP, 50, 300, "Warm-up").with_ramp(65),
				PlanPhase.erg(Wl.WORK, 80, 120, "Wave 1").with_lap(),
				PlanPhase.erg(Wl.RECOVERY, 55, 60, "Rest"),
				PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, 30, "").with_lap(),
			]
		)
	)
	plan.add(PlanPhase.erg(Wl.COOLDOWN, 50, 180, ""))
	plan.cooldown_appended = true
	return plan


func test_start_phase_forwards_and_laps() -> void:
	var m := Fakes.RecordingMock.new()
	autofree(m)
	var rec := Fakes.FakeRecorder.new()
	var r := _rider(
		m, {"recorder": rec, "game_id": "siege", "content_id": "fort", "utc_start_unix": 1792000000}
	)
	assert_eq(rec.started, ["siege", "fort", 1792000000, 0.0])
	assert_eq(m.phases, [-1] as Array[int], "setup resets a reused mock's phase")
	m.phases.clear()
	var plan := _plan()
	r.set_plan(plan)
	assert_eq(_gov(r).plan, plan)
	for i in plan.size():
		r.start_phase(i)
		_run(r, 1.0)
	assert_eq(m.phases, [0, 1, 2, 3, 4] as Array[int], "MockTrainer follows the phase")
	var starts: Array = []
	for c: Array in _gov(r).called("start_phase"):
		starts.append(c[1])
	assert_eq(starts, [0, 1, 2, 3, 4])
	assert_eq(rec.laps.size(), 3, "lap phases and the cool-down")
	assert_eq(rec.laps[0], ["Wave 1", 1.0])
	assert_eq(rec.laps[1], ["Phase 4", 3.0], "unlabelled lap phases get a name")
	assert_eq(rec.laps[2], ["Cool-down", 4.0], "the cool-down is always a lap")
	assert_eq(r.telemetry().phase_index, 4)


func test_cooldown_clears_the_bands() -> void:
	var r := _rider(_mock())
	r.set_plan(_plan())
	r.set_cadence_band(70.0, 90.0)
	r.set_power_band(100.0, 200.0)
	r.start_phase(4)
	assert_eq(r.cadence_band(), Vector2.ZERO)
	assert_eq(r.power_band(), Vector2.ZERO)


func test_cooldown_lap_by_kind_without_the_flag() -> void:
	var rec := Fakes.FakeRecorder.new()
	var r := _rider(_mock(), {"recorder": rec})
	var plan := EffortPlan.of(
		[PlanPhase.erg(Wl.WARMUP, 50, 300), PlanPhase.erg(Wl.COOLDOWN, 50, 180)]
	)
	r.set_plan(plan)
	r.start_phase(1)
	assert_eq(rec.laps, [["Cool-down", 0.0]])


func test_game_lap_marker() -> void:
	var rec := Fakes.FakeRecorder.new()
	var r := _rider(_mock(), {"recorder": rec})
	_run(r, 2.5)
	r.lap("Boss")
	assert_eq(rec.laps, [["Boss", 2.5]])


func test_lap_names_translate_strings_keys() -> void:
	var rec := Fakes.FakeRecorder.new()
	var r := _rider(_mock(), {"recorder": rec})
	var plan := (
		EffortPlan
		. of(
			[
				PlanPhase.erg(Wl.WARMUP, 50, 300, "CORE_FTP_TITLE").with_lap(),
				PlanPhase.erg(Wl.WORK, 70, 60, "Wave 2").with_lap(),
				PlanPhase.erg(Wl.WORK, 70, 60).with_lap(),
			]
		)
	)
	r.set_plan(plan)
	r.start_phase(0)
	r.start_phase(1)
	r.start_phase(2)
	r.lap("CORE_LAP_COOLDOWN")
	r.lap("Boss 1")
	var names: Array = []
	for l: Array in rec.laps:
		names.append(l[0])
	assert_eq(
		names,
		[
			tr("CORE_FTP_TITLE"),
			"Wave 2",
			tr("CORE_LAP_PHASE").replace("{n}", "3"),
			tr("CORE_LAP_COOLDOWN"),
			"Boss 1"
		]
	)
	assert_ne(tr("CORE_LAP_PHASE"), "CORE_LAP_PHASE", "the key is in core.csv")
	assert_ne(names[0], "CORE_FTP_TITLE", "a strings-key label becomes text in the FIT lap name")


func test_recorder_is_fed_while_recording() -> void:
	var rec := Fakes.FakeRecorder.new()
	var r := _rider(_mock(), {"recorder": rec})
	_run(r, 3.0)
	assert_eq(rec.records.size(), 60, "the latest values every tick; the recorder keeps 1 Hz")
	var last: Array = rec.records.back()
	assert_almost_eq(float(last[0]), 3.0, 1e-9)
	assert_eq(last[1], 200.0)
	assert_eq(last[2], 90.0)
	var times: Array = []
	for row: Array in rec.records:
		times.append(row[0])
	var sorted := times.duplicate()
	sorted.sort()
	assert_eq(times, sorted)


## W2: the recorder gets -1 (absent) for a cadence or speed the trainer doesn't report, and
## for a stale sample, so the FIT holds no made-up zeros; a stale sample's power is 0 W.
func test_recorder_gets_absent_values_for_missing_or_stale_fields() -> void:
	var rec := Fakes.FakeRecorder.new()
	var d := _fake_device()
	var r := _rider(d, {"recorder": rec})
	r.tick(DT)
	d.emit_sample(180.0)
	r.tick(DT)
	var row: Array = rec.records.back()
	assert_eq(row[1], 180.0)
	assert_eq(row[2], -1.0, "no cadence from the trainer: absent")
	assert_eq(row[3], -1.0, "no speed: absent")
	d.emit_sample(190.0, 88.0, 31.5)
	r.tick(DT)
	row = rec.records.back()
	assert_eq(row[2], 88.0)
	assert_eq(row[3], 31.5)
	_run(r, LocalRider.STALE_S + 0.2)
	row = rec.records.back()
	assert_eq(row[1], 0.0, "stale: 0 W")
	assert_eq(row[2], -1.0, "stale: absent")
	assert_eq(row[3], -1.0)


func test_record_option_uses_the_rides_service() -> void:
	var r := _rider(_mock(), {"record": true})
	assert_not_null(r.recorder, "Rides.new_recorder()")
	var bot := _rider(_mock(), {"record": false})
	assert_null(bot.recorder)


func test_finish_ride_saves_once() -> void:
	var rec := Fakes.FakeRecorder.new()
	var r := _rider(_mock(), {"recorder": rec, "rides_dir": "C:/rides/slot0"})
	_run(r, 2.0)
	watch_signals(_bus)
	var path := r.finish_ride()
	assert_eq(path, rec.save_path)
	assert_almost_eq(rec.stopped_at, 2.0, 1e-9)
	assert_eq(rec.saves, ["C:/rides/slot0"] as Array[String])
	assert_signal_emitted(_bus, "ride_saved")
	assert_eq(r.finish_ride(), path)
	assert_eq(rec.saves.size(), 1, "saved once")
	var n := rec.records.size()
	_run(r, 1.0)
	assert_eq(rec.records.size(), n, "nothing recorded after the stop")
	var none := _rider(_mock())
	assert_eq(none.finish_ride(), "")


func test_pause_reaches_governor_recorder_and_telemetry() -> void:
	var rec := Fakes.FakeRecorder.new()
	var r := _rider(_mock(), {"recorder": rec})
	_run(r, 1.0)
	r.set_game_paused(true)
	assert_eq(_gov(r).called("set_game_paused"), [["set_game_paused", true]])
	assert_eq(rec.timer, [[false, 1.0]])
	assert_true(r.telemetry().paused)
	r.set_game_paused(false)
	assert_eq(rec.timer.back(), [true, 1.0])
	assert_false(r.telemetry().paused)


func test_shift_panic_resume_and_course_grade() -> void:
	var r := _rider(_mock())
	r.shift(1)
	r.shift(1)
	r.shift(-1)
	assert_eq(_gov(r).called("shift").size(), 3)
	assert_eq(r.telemetry().gear, 13, "the gear shift() returned while the status has none")
	_gov(r).st = {"gear": 14}
	assert_eq(r.telemetry().gear, 14, "the governor's status wins")
	r.panic()
	r.resume()
	assert_eq(_gov(r).called("emergency_safe").size(), 1)
	assert_eq(_gov(r).called("resume").size(), 1)


func test_configure_governor_merges() -> void:
	var r := _rider(_mock())
	r.configure_governor({"profile": "ramp_test"})
	var c := _gov(r).configured
	assert_eq(c.get("profile"), "ramp_test")
	assert_eq(c.get("ftp_w"), 200.0, "the rest stays")
	assert_eq(r.governor_params().get("profile"), "ramp_test")
	var ramp := _rider(_mock(), {"governor_profile": "ramp_test"})
	assert_eq(_gov(ramp).configured.get("profile"), "ramp_test")


# --- shutdown and the registry ----------------------------------------------------------------


func test_shutdown_is_idempotent_and_unlists_the_rider() -> void:
	var r := _rider(_mock())
	assert_true(LocalRider.live_riders().has(r))
	r.shutdown()
	r.shutdown()
	assert_eq(_gov(r).shutdown_count, 1)
	assert_true(r.is_shut_down())
	assert_false(LocalRider.live_riders().has(r))
	var ticks := _gov(r).ticks.size()
	_run(r, 1.0)
	assert_gt(_gov(r).ticks.size(), ticks, "the governor keeps ticking so safe commands go out")


func test_shutdown_stops_gestures() -> void:
	var d := _fake_device()
	var r := _rider(d)
	_ges(r).fire_at = {1: [Wl.G_SURGE]}
	r.shutdown()
	d.emit_sample(200.0, 90.0)
	r.tick(DT)
	assert_eq(r.take_gestures().size(), 0)


func test_live_riders_forget_freed_riders() -> void:
	var a := LocalRider.new()
	var b := LocalRider.new()
	add_child(a)
	add_child(b)
	a.setup(1, _profile(), null, _mock(), {"governor": Fakes.FakeGovernor.new(), "bus": _bus})
	b.setup(2, _profile(), null, _mock(), {"governor": Fakes.FakeGovernor.new(), "bus": _bus})
	var live := LocalRider.live_riders()
	assert_true(live.has(a))
	assert_true(live.has(b))
	a.free()
	live = LocalRider.live_riders()
	assert_eq(live.has(b), true)
	assert_eq(
		live.size(), live.filter(func(x: LocalRider) -> bool: return is_instance_valid(x)).size()
	)
	b.free()
	assert_false(LocalRider.live_riders().any(func(x: LocalRider) -> bool: return x == null))


func test_untouched_rider_is_harmless() -> void:
	var r := LocalRider.new()
	add_child_autofree(r)
	r.tick(DT)
	r.start_phase(0)
	r.set_game_paused(true)
	r.shift(1)
	r.panic()
	r.shutdown()
	assert_eq(r.apply_directive(EffortDirective.new()), {})
	assert_eq(r.take_gestures().size(), 0)
	assert_eq(r.finish_ride(), "")
	assert_eq(r.telemetry().phase_index, 0)
