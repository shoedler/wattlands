extends WlTrainerService
## Test double of TrainerService: a settable device, status and local rider.

var dev: TrainerDevice = null
var rider: LocalRider = null
var st: String = TrainerDevice.STATUS_DISCONNECTED
var starts: int = 0
var mock_specs: Array[String] = []
var conn: FtmsConnectionManager = null
## connect_trainer() and disconnect_trainer() calls (forwarded to `conn` at once: no real
## control point to drain).
var connect_calls: Array[String] = []
var disconnect_calls: int = 0


func start() -> void:
	starts += 1


func device() -> TrainerDevice:
	return dev


func local_rider() -> LocalRider:
	return rider


func status() -> String:
	return st


func is_mock() -> bool:
	return dev is MockTrainer


func connection() -> FtmsConnectionManager:
	return conn


func use_mock(spec: String) -> void:
	mock_specs.append(spec)
	if dev == null:
		dev = MockTrainer.from_spec(spec, 200.0)
		add_child(dev)
	st = TrainerDevice.STATUS_READY
	device_changed.emit(dev)
	status_changed.emit(st, "")


func connect_trainer(address: String) -> void:
	connect_calls.append(address)
	if conn != null:
		conn.connect_to(address)


func disconnect_trainer() -> void:
	disconnect_calls += 1
	if conn != null:
		conn.disconnect_trainer()
