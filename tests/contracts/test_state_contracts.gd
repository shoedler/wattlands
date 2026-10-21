extends GutTest
## Telemetry, PlayerSlot, PhaseState, TrainerSample and InputFrame (BRIEF 3.6, 4.1, 5.5):
## JSON round trips and defaults.


func _rt(d: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(d))
	assert_true(parsed is Dictionary)
	return parsed if parsed is Dictionary else {}


func _same_json(a: Dictionary, b: Dictionary, msg: String = "") -> void:
	assert_eq(JSON.stringify(a), JSON.stringify(b), msg)


# --- Telemetry ------------------------------------------------------------------------


func _telemetry() -> Telemetry:
	var m := Telemetry.new()
	m.peer_id = 3
	m.t = 123.45
	m.power_w = 212.0
	m.cadence_rpm = 88.5
	m.speed_kmh = 35.4
	m.effort = 0.85
	m.p_eff_w = 212.5
	m.wbal_j = 15432.5
	m.ftp_pct = 85.0
	m.mode = Wl.SIM
	m.applied_target_w = 0
	m.applied_grade_pct = 2.5
	m.gear = 14
	m.clamped_by.append(Wl.CLAMP_WARMUP)
	m.clamped_by.append(Wl.CLAMP_HAPTIC_INTENSITY)
	m.rescue = true
	m.coasting = true
	m.afk = true
	m.paused = true
	m.s_left_105 = 250.0
	m.s_left_120 = 12.5
	m.gestures.append(Wl.G_SURGE)
	m.gestures.append(Wl.G_COAST)
	m.intents = [{"type": "route", "lane": 2.0}]
	m.distance_m = 1234.5
	m.phase_index = 4
	m.acks = [
		{
			"id": 9.0,
			"kind": "request",
			"applied": {"target_pct": 80.0},
			"clamped_by": [],
			"refused": "",
			"reason": ""
		}
	]
	m.connected = false
	m.age_s = 3.5
	m.cadence_age_s = 1.25
	m.haptic_pct = 2.1
	return m


func test_telemetry_defaults() -> void:
	var m := Telemetry.new()
	assert_eq(m.mode, Wl.OFF)
	assert_eq(m.gear, 12)
	assert_eq(m.s_left_105, 300.0)
	assert_eq(m.s_left_120, 60.0)
	assert_eq(m.phase_index, -1)
	assert_true(m.connected)
	assert_eq(m.cadence_age_s, 0.0)
	assert_eq(m.haptic_pct, 0.0)


func test_telemetry_round_trip() -> void:
	var m := _telemetry()
	var d := m.to_dict()
	assert_eq(d["peer"], 3)
	assert_eq(d["gestures"], ["surge", "coast"])
	assert_eq(d["cadence_age_s"], 1.25)
	assert_eq(d["haptic_pct"], 2.1)
	var back := Telemetry.from_dict(_rt(d))
	_same_json(back.to_dict(), d)
	assert_eq(back.peer_id, 3)
	assert_true(typeof(back.peer_id) == TYPE_INT)
	assert_eq(back.mode, Wl.SIM)
	assert_eq(back.gear, 14)
	assert_eq(back.clamped_by, [Wl.CLAMP_WARMUP, Wl.CLAMP_HAPTIC_INTENSITY])
	assert_eq(back.gestures, [Wl.G_SURGE, Wl.G_COAST])
	assert_true(back.gestures[0] is StringName)
	assert_true(back.rescue and back.coasting and back.afk and back.paused)
	assert_false(back.connected)
	assert_eq(back.phase_index, 4)
	assert_eq(back.age_s, 3.5)
	assert_eq(back.cadence_age_s, 1.25)
	assert_eq(back.haptic_pct, 2.1)
	assert_eq(back.intents[0]["type"], "route")
	assert_eq(back.acks[0]["kind"], "request")


func test_telemetry_from_empty_dict() -> void:
	_same_json(Telemetry.from_dict({}).to_dict(), Telemetry.new().to_dict())


func test_telemetry_duplicate_is_deep() -> void:
	var m := _telemetry()
	var c := m.duplicate_telemetry()
	c.clamped_by.clear()
	(c.intents[0] as Dictionary)["lane"] = 5.0
	assert_eq(m.clamped_by.size(), 2)
	assert_eq(m.intents[0]["lane"], 2.0)


# --- PlayerSlot -----------------------------------------------------------------------


func test_player_slot_defaults() -> void:
	var s := PlayerSlot.new()
	assert_eq(s.ftp, 200.0)
	assert_false(s.ftp_verified)
	assert_eq(s.scaling_mode, Wl.FAIR_FTP)
	assert_eq(s.p_eff_per_w, 1.25)
	assert_eq(s.rider_mass_kg, 75.0)
	assert_eq(s.preferred_cadence_rpm, 90.0)
	assert_true(s.haptics_on)
	assert_eq(s.haptic_intensity, 0.7)
	assert_false(s.autopilot)
	assert_false(s.is_bot)


func test_player_slot_round_trip() -> void:
	var s := PlayerSlot.new()
	s.peer_id = 5
	s.name = "Ada"
	s.apply_look(6)
	s.ftp = 287.5
	s.ftp_verified = true
	s.scaling_mode = Wl.WKG
	s.p_eff_per_w = 1.1
	s.rider_mass_kg = 75.0
	s.preferred_cadence_rpm = 95.0
	s.haptics_on = false
	s.haptic_intensity = 0.25
	s.autopilot = true
	s.is_bot = false
	s.options = {"engine": "steam", "seat": 2.0}
	var d := s.to_dict()
	assert_eq(d["color"], "f0e442")
	var back := PlayerSlot.from_dict(_rt(d))
	_same_json(back.to_dict(), d)
	assert_eq(back.peer_id, 5)
	assert_eq(back.slot_index, 6)
	assert_eq(back.color, Wl.SLOT_COLORS[2])
	assert_eq(back.shape, "square")
	assert_eq(back.pattern, "dotted")
	assert_true(back.hollow)
	assert_eq(back.scaling_mode, Wl.WKG)
	assert_eq(back.haptic_intensity, 0.25)
	assert_true(back.autopilot)
	assert_eq(back.options, {"engine": "steam", "seat": 2.0})


func test_player_slot_apply_look() -> void:
	var s := PlayerSlot.new()
	for i in Wl.MAX_SLOTS:
		s.apply_look(i)
		var look := Wl.slot_look(i)
		assert_eq(s.slot_index, i)
		assert_eq(s.color, look["color"])
		assert_eq(s.shape, look["shape"])
		assert_eq(s.pattern, look["pattern"])
		assert_eq(s.hollow, look["hollow"])


func test_player_slot_from_empty_dict() -> void:
	_same_json(PlayerSlot.from_dict({}).to_dict(), PlayerSlot.new().to_dict())


# --- PhaseState -----------------------------------------------------------------------


func test_phase_state_round_trip() -> void:
	var s := PhaseState.new()
	s.index = 2
	s.kind = Wl.WORK
	s.mode = Wl.ERG
	s.elapsed_s = 42.5
	s.duration_s = 180.0
	s.open_ended = true
	s.min_s = 90.0
	s.max_s = 300.0
	s.label = "Advance"
	s.planned_pct = 72.5
	s.remaining_s = 257.5
	s.count = 6
	s.plan_elapsed_s = 642.5
	s.prev_ended_by = Wl.ENDED_END_PHASE
	var d := s.to_dict()
	var back := PhaseState.from_dict(_rt(d))
	_same_json(back.to_dict(), d)
	assert_eq(back.index, 2)
	assert_true(typeof(back.count) == TYPE_INT)
	assert_eq(back.plan_elapsed_s, 642.5)
	assert_eq(back.prev_ended_by, "end_phase")
	assert_false(back.is_cooldown())
	back.kind = Wl.COOLDOWN
	assert_true(back.is_cooldown())


func test_phase_state_defaults() -> void:
	var s := PhaseState.from_dict({})
	assert_eq(s.index, -1)
	assert_eq(s.plan_elapsed_s, 0.0)
	assert_eq(s.prev_ended_by, "", "the first phase has no previous phase")


# --- TrainerSample and InputFrame -----------------------------------------------------


func test_trainer_sample_make() -> void:
	var s := TrainerSample.make(1.5, 200.0)
	assert_eq(s.flags, TrainerSample.HAS_POWER)
	assert_false(s.has_cadence())
	assert_false(s.has_speed())
	assert_eq(s.cadence_rpm, -1.0)
	var full := TrainerSample.make(2.0, 210.0, 90.0, 36.0)
	assert_eq(
		full.flags, TrainerSample.HAS_POWER | TrainerSample.HAS_CADENCE | TrainerSample.HAS_SPEED
	)
	assert_true(full.has_cadence())
	assert_true(full.has_speed())
	assert_eq(
		full.to_dict(),
		{
			"t": 2.0,
			"power_w": 210.0,
			"cadence_rpm": 90.0,
			"speed_kmh": 36.0,
			"distance_m": -1.0,
			"flags": 7
		}
	)


func test_input_frame_lookups() -> void:
	var f := InputFrame.new()
	assert_null(f.telemetry(1))
	assert_null(f.phase_of(1))
	var m := Telemetry.new()
	var p := PhaseState.new()
	f.players[1] = m
	f.phase[1] = p
	assert_same(f.telemetry(1), m)
	assert_same(f.phase_of(1), p)
