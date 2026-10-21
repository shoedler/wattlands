extends LocalRider
## Test double of LocalRider: records setup, panics and finished rides; telemetry is settable.
## tick(dt) advances its own platform time and emits telemetry_updated with `tm` (t stamped),
## like the real rider, so drivers that follow the telemetry (FtpTest.run_on) run on it.

var setup_calls: Array = []
var panics: int = 0
var finished_rides: int = 0
var ticks: int = 0
var plan_set: EffortPlan = null
var phases_started: Array[int] = []
var tm: Telemetry = Telemetry.new()
var fit_to_return: String = ""
var _fake_t: float = 0.0


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
	_gov_params = {}
	if p_device != null:
		_gov_params["trainer_max_w"] = int(p_device.power_range().get("max_w", 1800))
	setup_calls.append(
		{
			"peer": p_peer_id,
			"slot": p_slot,
			"device": p_device,
			"options": p_options.duplicate(true)
		}
	)


func set_plan(p_plan: EffortPlan) -> void:
	plan_set = p_plan


func start_phase(index: int) -> void:
	phases_started.append(index)


func tick(dt: float) -> void:
	ticks += 1
	_fake_t += dt
	telemetry_updated.emit(telemetry())


func platform_time() -> float:
	return _fake_t


func panic() -> void:
	panics += 1


func telemetry() -> Telemetry:
	var out := tm.duplicate_telemetry()
	out.t = _fake_t
	return out


func finish_ride() -> String:
	finished_rides += 1
	return fit_to_return
