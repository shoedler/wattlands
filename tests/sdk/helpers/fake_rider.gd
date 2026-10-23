extends LocalRider
## Test double for LocalRider (a W0 stub in the sdk-runtime worktree). It records every call
## the GameHost and the routers make, forwards bands to a real MockTrainer (so tests can see
## them "reach MockTrainer"), queues an ack per applied directive like the real LocalRider,
## and reports scripted telemetry. W2 runs the same paths with the real LocalRider in
## tests/sdk/integration/.

var plans_set: Array[EffortPlan] = []
var phases_started: Array[int] = []
var directives: Array[EffortDirective] = []
var grades: Array[float] = []
## The bands set on this rider ([lo, hi]); named apart from LocalRider.cadence_band() and
## power_band(), which the double overrides to report the same values.
var band_cadence: Array = [0.0, 0.0]
var band_power: Array = [0.0, 0.0]
var game_paused: bool = false
var paused_calls: Array[bool] = []
var shifts: Array[int] = []
var laps: Array[String] = []
var ticks: int = 0
var panics: int = 0
var finished_rides: int = 0
var shutdowns: int = 0
var options: Dictionary = {}
## Scripted telemetry. With follow_target the rider rides its planned ERG target exactly.
var follow_target: bool = true
var power_w: float = 150.0
var cadence_rpm: float = 90.0
var rescue: bool = false
var afk: bool = false
var coasting: bool = false
var haptic_pct: float = 0.0
## The rider's own pause on not pedaling (LocalRider.is_ride_paused) and heart rate, scripted.
var ride_paused: bool = false
var heart_rate: int = 0
## Where finish_ride writes its file ("" = no recorder: returns "").
var ride_dir: String = ""
var refuse_reason: String = ""
## Coasting stand-in for the governor's 4.6.4 rule: after this many ticks without pedaling
## the rider asks to pause (options.multiplayer false) or marks itself AFK (true). -1: never.
var coast_after_ticks: int = -1
var gesture_queue: Array[StringName] = []
var intent_queue: Array = []
var ack_queue: Array = []
## Queue acks in the real LocalRider's Telemetry.acks shape (no requested, t, game_t or
## phase_index) instead of the full record.
var bare_acks: bool = false
var t: float = 0.0
var _fake_phase: int = -1


func setup(
	p_peer_id: int,
	p_profile: RiderProfile,
	p_slot: PlayerSlot,
	p_device: TrainerDevice,
	p_options: Dictionary = {}
) -> void:
	peer_id = p_peer_id
	profile = p_profile
	slot = p_slot
	device = p_device
	options = p_options.duplicate(true)
	is_bot = p_slot != null and p_slot.is_bot


func set_plan(plan: EffortPlan) -> void:
	plans_set.append(plan)


func start_phase(index: int) -> void:
	phases_started.append(index)
	_fake_phase = index
	if device is MockTrainer:
		(device as MockTrainer).set_phase(index)


func apply_directive(d: EffortDirective) -> Dictionary:
	directives.append(d)
	var rec := {
		"id": d.id,
		"kind": "request",
		"requested": d.to_dict(),
		"applied": {} if refuse_reason != "" else d.to_dict(),
		"clamped_by": [],
		"refused": refuse_reason != "",
		"reason": refuse_reason,
		"t": t,
	}
	if bare_acks:
		ack_queue.append(
			{
				"id": rec["id"],
				"kind": rec["kind"],
				"applied": (rec["applied"] as Dictionary).duplicate(true),
				"clamped_by": [],
				"refused": rec["refused"],
				"reason": rec["reason"],
				"dropped": []
			}
		)
	else:
		ack_queue.append(rec.duplicate(true))
	return rec


func apply_course_grade(grade_pct: float) -> void:
	grades.append(grade_pct)


func set_cadence_band(lo_rpm: float, hi_rpm: float) -> void:
	band_cadence = [lo_rpm, hi_rpm]
	if device is MockTrainer:
		(device as MockTrainer).set_cadence_band(lo_rpm, hi_rpm)


func set_power_band(lo_w: float, hi_w: float) -> void:
	band_power = [lo_w, hi_w]
	if device is MockTrainer:
		(device as MockTrainer).set_power_band(lo_w, hi_w)


func cadence_band() -> Vector2:
	return Vector2(float(band_cadence[0]), float(band_cadence[1]))


func power_band() -> Vector2:
	return Vector2(float(band_power[0]), float(band_power[1]))


func set_game_paused(p: bool) -> void:
	game_paused = p
	paused_calls.append(p)


func shift(delta: int) -> void:
	shifts.append(delta)


func panic() -> void:
	panics += 1


func tick(dt: float) -> void:
	ticks += 1
	t += dt
	if device != null:
		device.tick(dt)
	if coast_after_ticks >= 0 and ticks == coast_after_ticks:
		if bool(options.get("multiplayer", false)):
			afk = true
		else:
			pause_requested.emit("coasting")


func is_ride_paused() -> bool:
	return ride_paused


func telemetry() -> Telemetry:
	var tm := Telemetry.new()
	tm.peer_id = peer_id
	tm.t = t
	var ftp := slot.ftp if slot != null else 200.0
	var phase := _current_phase()
	tm.mode = phase.mode if phase != null else Wl.ERG
	if tm.mode == Wl.ERG and phase != null:
		tm.applied_target_w = int(floor(phase.target_pct * ftp / 100.0))
	tm.power_w = (
		float(tm.applied_target_w)
		if (follow_target and tm.mode == Wl.ERG and phase != null)
		else power_w
	)
	if game_paused and follow_target:
		tm.power_w = power_w
	tm.cadence_rpm = cadence_rpm
	tm.ftp_pct = tm.power_w / maxf(ftp, 1.0) * 100.0
	tm.p_eff_w = tm.power_w * (slot.p_eff_per_w if slot != null else 1.0)
	tm.effort = tm.power_w / maxf(ftp, 1.0)
	tm.rescue = rescue
	tm.afk = afk
	tm.coasting = coasting
	# Like LocalRider: in multiplayer only the rider's own pause, in solo the game pause too.
	tm.paused = ride_paused or (game_paused and not is_multiplayer)
	tm.heart_rate_bpm = heart_rate
	tm.phase_index = _fake_phase
	tm.haptic_pct = haptic_pct
	return tm


func take_gestures() -> Array[StringName]:
	var out := gesture_queue
	gesture_queue = []
	return out


func push_intent(intent: Dictionary) -> void:
	intent_queue.append(intent)


func take_intents() -> Array:
	var out := intent_queue
	intent_queue = []
	return out


func take_acks() -> Array:
	var out := ack_queue
	ack_queue = []
	return out


func lap(label: String) -> void:
	laps.append(label)


func finish_ride() -> String:
	finished_rides += 1
	if is_bot or ride_dir == "":
		return ""
	DirAccess.make_dir_recursive_absolute(ride_dir)
	var path := ride_dir.path_join("ride_%d.fit" % peer_id)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("FIT")
	f.close()
	var s := FileAccess.open(path.get_basename() + ".json", FileAccess.WRITE)
	s.store_string("{}")
	s.close()
	return path


func shutdown() -> void:
	shutdowns += 1


func _current_phase() -> PlanPhase:
	if plans_set.is_empty() or _fake_phase < 0:
		return null
	return plans_set[plans_set.size() - 1].phase(_fake_phase)
