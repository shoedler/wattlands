extends LocalRider
## Test double of LocalRider: records setup, panics and finished rides; telemetry is settable.

var setup_calls: Array = []
var panics: int = 0
var finished_rides: int = 0
var ticks: int = 0
var plan_set: EffortPlan = null
var phases_started: Array[int] = []
var tm: Telemetry = Telemetry.new()
var fit_to_return: String = ""


func setup(p_peer_id: int, p_profile: RiderProfile, p_slot: PlayerSlot, p_device: TrainerDevice, p_options: Dictionary = {}) -> void:
	peer_id = p_peer_id
	profile = p_profile
	slot = p_slot
	device = p_device
	setup_calls.append({"peer": p_peer_id, "slot": p_slot, "device": p_device, "options": p_options.duplicate(true)})


func set_plan(p_plan: EffortPlan) -> void:
	plan_set = p_plan


func start_phase(index: int) -> void:
	phases_started.append(index)


func tick(_dt: float) -> void:
	ticks += 1


func panic() -> void:
	panics += 1


func telemetry() -> Telemetry:
	return tm.duplicate_telemetry()


func finish_ride() -> String:
	finished_rides += 1
	return fit_to_return
