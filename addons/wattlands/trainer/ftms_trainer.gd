class_name FtmsTrainer
extends TrainerDevice
## A real FTMS trainer (KICKR CORE, KICKR CORE 2) behind the TrainerDevice interface
## (BRIEF 4.1). Owned by trainer-core; public API frozen after W0.
## Turns setter calls into FtmsCodec control-point payloads and hands them to
## FtmsClient.write_control() (the only caller, 4.6.11); turns bike data into
## TrainerSamples (cadence estimated from speed when absent or stale, BRIEF 4.5).
##
## W1 details:
## - Samples: power_w (HAS_POWER, POWER_FROM_CPS when the client filled it from 0x2A63;
##   FTMS power is signed, and a negative reading, such as when back-pedalling, becomes 0 W),
##   cadence_rpm (0.5 rpm units, HAS_CADENCE), speed_kmh (0.01 km/h, HAS_SPEED) and
##   distance_m (HAS_DISTANCE) when the record has them; `t` is this device's platform time
##   (the sum of tick(dt)). Cadence estimation itself is CadenceEstimator's (trainer-control),
##   which LocalRider runs on every sample: a sample without cadence leaves it absent here.
## - status_changed follows the client's state (STATUS_CONNECTED while the flow runs or under
##   the hardware lock, STATUS_READY, STATUS_CONTROL_LOST, STATUS_ERROR, STATUS_DISCONNECTED);
##   control_response and machine_status pass through.
## - tick(dt) advances the sample clock and ticks a client that does not tick itself (one
##   outside the tree, or with process_self off).

## Set Target Resistance Level encoding (FtmsCodec.RESISTANCE_UINT8 or RESISTANCE_SINT16).
var resistance_encoding: String = FtmsCodec.RESISTANCE_UINT8

var _client: FtmsClient = null
var _name: String = ""
var _t: float = 0.0
var _last_sample: TrainerSample = null


static func create(p_client: FtmsClient, p_name: String = "") -> FtmsTrainer:
	var t := FtmsTrainer.new()
	t._bind(p_client, p_name)
	return t


func client() -> FtmsClient:
	return _client


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func device_name() -> String:
	if _name != "":
		return _name
	if _client != null:
		var info := _client.device_info()
		if str(info.get("model", "")) != "":
			return str(info["model"])
	return "FTMS trainer"


func is_ready() -> bool:
	return _client != null and _client.is_ready()


func status() -> String:
	if _client == null:
		return STATUS_DISCONNECTED
	return _map_state(_client.state())


func power_range() -> Dictionary:
	return _client.power_range() if _client != null else super.power_range()


func features() -> Dictionary:
	return _client.features() if _client != null else super.features()


func set_target_power(watts: int) -> void:
	_send(FtmsCodec.encode_target_power(watts))


func set_simulation(wind_mps: float, grade_pct: float, crr: float, cw: float) -> void:
	_send(FtmsCodec.encode_indoor_bike_simulation(wind_mps, grade_pct, crr, cw))


func set_resistance(level: float) -> void:
	_send(FtmsCodec.encode_target_resistance(level, resistance_encoding))


func request_stop() -> void:
	_send(FtmsCodec.encode_stop_pause(FtmsCodec.STOP_PARAM_STOP))


func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	_t += dt
	if _client != null and (not _client.is_inside_tree() or not _client.process_self):
		_client.tick(dt)


# --- Added in W1 ----------------------------------------------------------------------

## The latest sample emitted (null before the first).
func last_sample() -> TrainerSample:
	return _last_sample


## Platform seconds this device has been ticked (the samples' clock).
func platform_time_s() -> float:
	return _t


## A TrainerSample from a bike data record (FtmsClient.bike_data) at time t.
static func sample_from_record(record: Dictionary, t: float) -> TrainerSample:
	var s := TrainerSample.new()
	s.t = t
	s.flags = 0
	if record.has("power_w"):
		s.power_w = maxf(float(record["power_w"]), 0.0)
		s.flags |= TrainerSample.HAS_POWER
		if str(record.get("power_source", "")) == "cps":
			s.flags |= TrainerSample.POWER_FROM_CPS
	if record.has("cadence_rpm"):
		s.cadence_rpm = float(record["cadence_rpm"])
		s.flags |= TrainerSample.HAS_CADENCE
	if record.has("speed_kmh"):
		s.speed_kmh = float(record["speed_kmh"])
		s.flags |= TrainerSample.HAS_SPEED
	if record.has("distance_m"):
		s.distance_m = float(record["distance_m"])
		s.flags |= TrainerSample.HAS_DISTANCE
	return s


## Unbind from the client (W4, SAF-8; additive). FtmsConnectionManager keeps one FtmsClient
## for every trainer, so when a link to this trainer is replaced by another trainer's it calls
## this: from then on this object's writes are dropped (push_warning) instead of reaching the
## next trainer, its status reads "disconnected" and no more bike data arrives here. The
## manager makes a new FtmsTrainer when this trainer is linked again.
func release_client() -> void:
	if _client == null:
		return
	var pairs: Array = [
		[_client.bike_data, _on_bike_data],
		[_client.control_response, _on_control_response],
		[_client.machine_status, _on_machine_status],
		[_client.state_changed, _on_client_state],
	]
	for pair: Array in pairs:
		var sig: Signal = pair[0]
		var cb: Callable = pair[1]
		if sig.is_connected(cb):
			sig.disconnect(cb)
	_client = null
	status_changed.emit(STATUS_DISCONNECTED, "")


# --- Internals ------------------------------------------------------------------------

func _bind(p_client: FtmsClient, p_name: String) -> void:
	_client = p_client
	_name = p_name
	if _client == null:
		return
	_client.bike_data.connect(_on_bike_data)
	_client.control_response.connect(_on_control_response)
	_client.machine_status.connect(_on_machine_status)
	_client.state_changed.connect(_on_client_state)


## The single call site of FtmsClient.write_control in the code base (BRIEF 4.6.11).
func _send(payload: PackedByteArray) -> void:
	if payload.is_empty():
		return
	if _client == null:
		push_warning("FtmsTrainer: no client; dropped %s" % FtmsCodec.opcode_name(int(payload[0])))
		return
	_client.write_control(payload)


func _on_bike_data(record: Dictionary) -> void:
	_last_sample = sample_from_record(record, _t)
	sample_received.emit(_last_sample)


func _on_control_response(opcode: int, result: int) -> void:
	control_response.emit(opcode, result)


func _on_machine_status(code: int, data: PackedByteArray) -> void:
	machine_status.emit(code, data)


func _on_client_state(state: String, detail: String) -> void:
	status_changed.emit(_map_state(state), detail)


static func _map_state(state: String) -> String:
	match state:
		FtmsClient.STATE_READY:
			return STATUS_READY
		FtmsClient.STATE_CONTROL_LOST:
			return STATUS_CONTROL_LOST
		FtmsClient.STATE_FAILED:
			return STATUS_ERROR
		FtmsClient.STATE_IDLE, FtmsClient.STATE_DISCONNECTED:
			return STATUS_DISCONNECTED
	return STATUS_CONNECTED
