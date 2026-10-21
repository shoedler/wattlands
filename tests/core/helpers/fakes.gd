extends RefCounted
## Test doubles for tests/core (preload it; not a test script). Each subclasses the W0 stub
## or contract it stands in for, so LocalRider, WlTrainerService and WlApp are tested
## without the other W1 modules.


## Records every call; status() returns `st`; apply_directive() returns (and by default
## emits) a record like the real governor's.
class FakeGovernor:
	extends SafetyGovernor

	var calls: Array = []
	var st: Dictionary = {"mode": Wl.OFF}
	var configured: Dictionary = {}
	var configure_count: int = 0
	var setup_device: TrainerDevice = null
	var samples: Array[TrainerSample] = []
	var ticks: Array[float] = []
	var course_distance: float = -1.0
	var course_grade: float = NAN
	var emit_on_apply: bool = true
	## The fake's own gear (the real SafetyGovernor has gear(), so the field has another name).
	var fake_gear: int = 12
	var shutdown_count: int = 0
	## Called by shutdown() (W4: tests check what happened before the link dropped).
	var shutdown_hook: Callable = Callable()
	var plan: EffortPlan = null

	func setup(p_device: TrainerDevice) -> void:
		setup_device = p_device
		calls.append(["setup"])

	func configure(params: Dictionary) -> void:
		configured = params.duplicate(true)
		configure_count += 1
		calls.append(["configure"])

	func set_plan(p_plan: EffortPlan) -> void:
		plan = p_plan
		calls.append(["set_plan"])

	func start_phase(index: int) -> void:
		calls.append(["start_phase", index])

	func resume_phase(index: int, elapsed_s: float, phase_distance_m: float = -1.0) -> void:
		calls.append(["resume_phase", index, elapsed_s, phase_distance_m])

	func set_game_paused(paused: bool) -> void:
		calls.append(["set_game_paused", paused])

	func apply_directive(directive: EffortDirective) -> Dictionary:
		var rec := {
			"id": directive.id, "kind": "request", "requested": directive.to_dict(),
			"applied": {"target_pct": directive.target_pct}, "clamped_by": ["slew"],
			"refused": false, "reason": "", "t": 0.0,
		}
		if emit_on_apply:
			directive_applied.emit(rec)
		return rec

	func set_course_grade(grade_pct: float) -> void:
		course_grade = grade_pct
		calls.append(["set_course_grade", grade_pct])

	func set_course_distance(distance_m: float) -> void:
		course_distance = distance_m

	func shift(delta: int) -> int:
		fake_gear = clampi(fake_gear + delta, 1, 24)
		calls.append(["shift", delta])
		return fake_gear

	func gear() -> int:
		return fake_gear

	func on_sample(sample: TrainerSample) -> void:
		samples.append(sample)

	func tick(dt: float) -> void:
		ticks.append(dt)

	func emergency_safe() -> void:
		calls.append(["emergency_safe"])

	func resume() -> void:
		calls.append(["resume"])

	func on_trainer_reconnected() -> void:
		calls.append(["on_trainer_reconnected"])

	func shutdown() -> void:
		shutdown_count += 1
		calls.append(["shutdown"])
		if shutdown_hook.is_valid():
			shutdown_hook.call()

	func status() -> Dictionary:
		return st.duplicate(true)

	func called(method_name: String) -> Array:
		var out: Array = []
		for c: Array in calls:
			if c[0] == method_name:
				out.append(c)
		return out


## Fires scripted gestures: fire_at[n] (1-based sample count) -> [gesture names].
class FakeGestures:
	extends GestureRecognizer

	var fire_at: Dictionary = {}
	var count: int = 0
	var configured: Array = []
	var erg_flags: Array[bool] = []
	var seen: Array[TrainerSample] = []

	func configure(ftp_w: float, solo: bool) -> void:
		configured = [ftp_w, solo]

	func set_erg(in_erg: bool) -> void:
		erg_flags.append(in_erg)

	func on_sample(sample: TrainerSample) -> Array[StringName]:
		count += 1
		seen.append(sample)
		var out: Array[StringName] = []
		for g: Variant in fire_at.get(count, []):
			out.append(StringName(str(g)))
		return out

	## advance(t) calls, and advance_fire[n] (1-based call count) -> [gesture names].
	var advance_calls: Array[float] = []
	var advance_fire: Dictionary = {}

	func advance(t: float) -> Array[StringName]:
		advance_calls.append(t)
		var out: Array[StringName] = []
		for g: Variant in advance_fire.get(advance_calls.size(), []):
			out.append(StringName(str(g)))
		return out


## Records the recorder calls.
class FakeRecorder:
	extends RideRecorderApi

	var started: Array = []
	var records: Array = []
	var laps: Array = []
	var timer: Array = []
	var stopped_at: float = -1.0
	var saves: Array[String] = []
	var recording: bool = false
	var save_path: String = "C:/fake/rides/ride.fit"

	func start(game_id: String, content_id: String, utc_start_unix: int, t: float) -> void:
		started = [game_id, content_id, utc_start_unix, t]
		recording = true

	func record(t: float, power_w: float, cadence_rpm: float, speed_kmh: float) -> void:
		records.append([t, power_w, cadence_rpm, speed_kmh])

	func lap(label: String, t: float) -> void:
		laps.append([label, t])

	func set_timer_running(running: bool, t: float) -> void:
		timer.append([running, t])

	func stop(t: float) -> void:
		stopped_at = t
		recording = false

	func is_recording() -> bool:
		return recording

	func save(dir: String = "") -> String:
		saves.append(dir)
		return save_path

	func summary() -> Dictionary:
		return {"records": records.size(), "laps": laps.size()}


## A MockTrainer that also records the band and phase calls.
class RecordingMock:
	extends MockTrainer

	var cadence_bands: Array = []
	var power_bands: Array = []
	var phases: Array[int] = []

	func set_cadence_band(lo_rpm: float, hi_rpm: float) -> void:
		cadence_bands.append([lo_rpm, hi_rpm])
		super.set_cadence_band(lo_rpm, hi_rpm)

	func set_power_band(lo_w: float, hi_w: float) -> void:
		power_bands.append([lo_w, hi_w])
		super.set_power_band(lo_w, hi_w)

	func set_phase(index: int) -> void:
		phases.append(index)
		super.set_phase(index)


## A device whose samples the test emits by hand.
class FakeDevice:
	extends TrainerDevice

	var ticked: float = 0.0
	var max_w: int = 1500
	var dev_status: String = TrainerDevice.STATUS_READY

	func emit_sample(power_w: float, cadence_rpm: float = -1.0, speed_kmh: float = -1.0) -> void:
		sample_received.emit(TrainerSample.make(ticked, power_w, cadence_rpm, speed_kmh))

	func set_dev_status(s: String, detail: String = "") -> void:
		dev_status = s
		status_changed.emit(s, detail)

	func tick(dt: float) -> void:
		ticked += dt

	func status() -> String:
		return dev_status

	func is_ready() -> bool:
		return dev_status == TrainerDevice.STATUS_READY

	func power_range() -> Dictionary:
		return {"min_w": 0, "max_w": max_w, "step_w": 1}

	func device_name() -> String:
		return "Fake trainer"


## Never touches Bluetooth: records start() and lets the test hand over a device.
class FakeConnectionManager:
	extends FtmsConnectionManager

	var started: Array = []
	var disconnects: int = 0
	var dev: TrainerDevice = null
	var last: Dictionary = {"address": "AA:BB:CC:DD:EE:FF", "name": "KICKR CORE 1234"}

	func start(auto_connect_last: bool = true) -> void:
		started.append(auto_connect_last)

	func disconnect_trainer() -> void:
		disconnects += 1

	func device() -> TrainerDevice:
		return dev

	func last_device() -> Dictionary:
		return last.duplicate()

	func backend_name() -> String:
		return "fake"

	func make_ready(d: TrainerDevice) -> void:
		dev = d
		status_changed.emit(TrainerDevice.STATUS_READY, "fake ready")
		trainer_ready.emit(d)

	## A successful reconnect, as the real manager reports it: trainer_ready, then reconnected.
	func make_reconnected(d: TrainerDevice) -> void:
		make_ready(d)
		reconnected.emit(d)


## Records attach_rider / detach_rider.
class FakeInputRouter:
	extends WlInputRouter

	var attached: Array = []
	var detaches: int = 0

	func attach_rider(rider: LocalRider) -> void:
		attached.append(rider)

	func detach_rider() -> void:
		detaches += 1


## Counts process_queue() and hands out FakeRecorders.
class FakeRides:
	extends WlRides

	var queue_runs: int = 0

	func process_queue() -> void:
		queue_runs += 1

	func new_recorder() -> RideRecorderApi:
		return FakeRecorder.new()
